import 'dart:async';

import 'package:logger/logger.dart';

import 'voice_ports.dart';
import 'voice_state.dart';

/// 마이크 소유권 상태기계.
///
/// **이 프로젝트에서 가장 위험한 구성요소다.** 웨이크워드 감지기와 전사기는 같은 마이크를
/// 동시에 점유할 수 없어, 소유권을 넘기는 지점이 곧 실패 지점이 된다. 그래서 마이크를
/// 만지는 코드를 이 클래스 하나에 모으고 [state] 를 단일 진실 원천으로 둔다.
///
/// ViewModel 은 상태를 읽고 명령을 보내기만 하며 감지기나 전사기를 직접 다루지 않는다.
///
/// ```
/// 감지 → 감지기 stop(마이크 해제) → 전사 → 서버 → TTS → 감지기 start
/// ```
///
/// TTS 재생 중에는 전사를 시작하지 않는다. 시작하면 자기 응답을 다시 명령으로 처리한다.
/// 재생 완료와 실패 **양쪽**에서 감지기를 재기동한다.
class VoiceSessionManager {
  VoiceSessionManager({
    required WakeWordDetector detector,
    required SpeechTranscriber transcriber,
    required SpeechSpeaker speaker,
    bool Function()? spokenReply,
    required String retryMessage,
    String? ackMessage,
    Future<void> Function()? listeningCue,
    String? checkingMessage,
    String? restartMessage,
    bool asksBack = false,
    Logger? logger,
  })  : _detector = detector,
        _transcriber = transcriber,
        _speaker = speaker,
        _spokenReply = spokenReply,
        _retryMessage = retryMessage,
        _ackMessage = ackMessage,
        _listeningCue = listeningCue,
        _checkingMessage = checkingMessage,
        _restartMessage = restartMessage,
        _asksBack = asksBack,
        _logger = logger ?? Logger(printer: SimplePrinter());

  /// 명령 세션의 앱 타임아웃. 인식 서비스의 무음 종료와 별개로 건다.
  static const commandTimeout = Duration(seconds: 20);

  /// 재질문 후속 응답 창.
  ///
  /// UI 계약(UI-15)이 정한 값이다. 질문 낭독이 끝난 뒤부터 센다. 이 시간 안에 답을
  /// 시작하면 인식 서비스가 발화 끝까지 기다리므로 **말하는 중간에 끊기지 않는다.**
  static const clarifyWindow = Duration(seconds: 8);

  /// 낭독 한 번의 한계.
  ///
  /// WARNING: `flutter_tts` 는 `awaitSpeakCompletion(true)` 일 때 완료 콜백이 오지
  /// 않으면 **영원히 기다린다.** 삼성 TTS 가 다른 앱에 오디오를 뺏기면 그렇게 된다.
  /// 실기기에서 반영 화면에 갇힌 원인이다.
  static const speakTimeout = Duration(seconds: 15);

  /// 한 번의 대화가 쓸 수 있는 최대 시간.
  ///
  /// IMPORTANT: 마지막 안전장치다. 어느 단계가 막히든 이 시간이 지나면 대기로 돌아온다.
  /// 대기로 못 돌아오는 것이 이 제품에서 가장 나쁜 고장이다 — 사용자는 앱이 죽은 것으로
  /// 본다.
  static const sessionTimeout = Duration(seconds: 75);

  /// 반영 결과를 화면에 남겨두는 최소 시간.
  ///
  /// UI 계약(UI-16)이 정한 값이다. **낭독 시간을 포함해** 이만큼은 보여준다 — TTS 가
  /// 바로 끝나거나 실패해도 결과가 스치고 지나가지 않아야 한다.
  static const resultMinimum = Duration(seconds: 4);

  final WakeWordDetector _detector;
  final SpeechTranscriber _transcriber;
  final SpeechSpeaker _speaker;

  /// 응답을 소리로 읽을지. 마이페이지의 음성 응답 설정이다.
  ///
  /// IMPORTANT: 마이크 음소거와 다른 설정이다. 꺼도 명령은 계속 듣는다 — 읽어주기만 멈춘다.
  final bool Function()? _spokenReply;
  final String _retryMessage;

  /// 호출에 바로 답할 문구. 없으면 답하지 않는다.
  final String? _ackMessage;

  /// 듣기 직전에 울리는 신호음. 끝날 때까지 기다린 뒤 듣는다.
  final Future<void> Function()? _listeningCue;

  /// 서버에 보내는 동안 읽을 문구. 없으면 말없이 기다린다.
  final String? _checkingMessage;

  /// 빠진 내용을 알린 뒤 덧붙일 문구. 처음부터 다시 말해달라는 안내다.
  final String? _restartMessage;

  /// 서버가 되물으면 그 자리에서 답을 들을지.
  ///
  /// 꺼 두면 무엇이 빠졌는지만 알리고 닫는다. 사용자는 다시 불러 처음부터 말한다.
  ///
  /// TODO: 답을 앞 발화의 빠진 항목에 잇는 서버 계약이 갖춰지면 켠다. 지금은 질문을
  /// 듣고 답해도 반영까지 이어지지 않는 경우가 있어, 묻고 실패하는 것보다 묻지 않는 쪽이
  /// 낫다.
  final bool _asksBack;

  final Logger _logger;

  final _states = StreamController<VoiceState>.broadcast();
  VoiceState _current = const Suspended();
  Future<void>? _session;
  StreamSubscription<void>? _wakeSub;
  bool _muted = false;
  bool _foreground = false;

  /// 지금 읽는 안내의 번호. 새로 읽기 시작하면 앞의 것이 밀려난 것을 안다.
  int _narration = 0;

  /// 화면과 ViewModel 이 구독하는 유일한 상태.
  Stream<VoiceState> get states => _states.stream;

  /// 호출어를 기다리는 동안 들은 말. 호출어 없이 알아들어야 하는 화면이 쓴다.
  Stream<Heard> get heard => _detector.heard;

  /// 지금 상태. 구독 전에도 읽을 수 있다.
  VoiceState get state => _current;

  void _emit(VoiceState next) {
    _current = next;
    if (!_states.isClosed) _states.add(next);
  }

  /// 호출어 감지를 세션 시작으로 잇는다. 앱 기동 시 한 번만 부른다.
  ///
  /// IMPORTANT: 이 배선이 없으면 감지기는 정상으로 돌고 로그에 감지까지 남기면서도
  /// **아무 일도 일어나지 않는다.** 실기기에서 실제로 그랬다. 감지 이벤트를 구독하는
  /// 곳은 여기 하나뿐이어야 한다.
  void bindWakeWord(
    Future<VoiceTurnResult> Function(String utterance) handle,
  ) {
    _wakeSub ??= _detector.detections.listen((_) {
      _logger.i('Wake word detected; starting session');
      unawaited(startSession(handle));
    });
  }

  /// 앱이 전경으로 왔다. 감지를 시작한다.
  ///
  /// **웨이크워드는 전경 한정이다.** 이 호출이 없으면 감지하지 않는다.
  Future<void> onForeground() async {
    _foreground = true;
    await _resumeDetection();
  }

  /// 앱이 배경으로 갔다. 감지를 멈추고 그 사실을 표시한다.
  ///
  /// 대기 중인 것처럼 보이게 두지 않는다. 백그라운드 상시 대기는 주방 고정 태블릿을
  /// 위한 후속 범위다.
  Future<void> onBackground() async {
    _foreground = false;
    await _detector.stop();
    await _transcriber.cancel();
    await _speaker.stop();
    _emit(const Suspended());
  }

  /// 한 번의 대화를 처리한다.
  ///
  /// 호출어 감지부터 응답 재생까지를 한 흐름으로 묶고, 어떤 경로로 끝나든 대기 상태로
  /// 돌아온다. `finally` 에서 감지기를 재기동하는 것이 그 보장이다.
  Future<void> startSession(
    Future<VoiceTurnResult> Function(String utterance) handle,
  ) {
    if (!_foreground) {
      _logger.d('Wake word ignored: app is not in foreground');
      return Future.value();
    }
    if (_muted) {
      _logger.d('Wake word ignored: session is muted');
      return Future.value();
    }
    final running = _session;
    if (running != null) {
      _logger.d('Wake word ignored: a session is already running');
      return running;
    }
    // 어느 단계가 막혀도 대기로 돌아오도록 전체에 한계를 건다.
    final started = _runSession(handle)
        .timeout(sessionTimeout, onTimeout: () async {
          _logger.w('Voice session exceeded ${sessionTimeout.inSeconds}s; recovering');
          await _recover();
        })
        .whenComplete(() => _session = null);
    _session = started;
    return started;
  }

  /// 막힌 세션을 정리하고 대기로 돌린다.
  Future<void> _recover() async {
    await _transcriber.cancel();
    await _speaker.stop();
    await _resumeDetection();
  }

  Future<void> _runSession(
    Future<VoiceTurnResult> Function(String utterance) handle,
  ) async {
    try {
      // IMPORTANT: 화면을 먼저 바꾼다. 마이크를 넘기는 데 드는 시간(감지기 정지 +
      // 인식기 정리 + 응답 낭독)이 1초를 넘어, 그동안 아무 반응이 없으면 호출이
      // 안 된 것으로 보인다.
      _emit(const Listening());

      // 감지기가 마이크를 놓아야 전사기가 시작할 수 있다.
      await _detector.stop();

      // 호출에 바로 답한다. 낭독이 끝난 뒤에 듣기 시작해야 자기 목소리를 명령으로
      // 되받지 않는다.
      //
      // WARNING: 이 응답을 [Speaking] 으로 내보내지 않는다. 화면은 [Speaking] 을
      // **반영 결과**로 그리므로, 호출하자마자 반영 화면이 떴다.
      //
      // 인식기 준비를 낭독과 **동시에** 돌린다. 줄 세우면 그 시간이 호출 반응 속도에
      // 그대로 더해진다.
      final ack = _ackMessage;
      final warmUp = _transcriber.isAvailable();
      if (ack != null && ack.isNotEmpty) await _speak(ack);
      await warmUp;
      await _listeningCue?.call();
      final utterance = await _transcribe(commandTimeout);
      if (utterance == null || utterance.trim().isEmpty) {
        // 말이 없었으면 조용히 닫는다. 다시 말해달라고 하고 닫으면 말할 곳이 없다.
        _logger.w('Command transcription produced no result');
        return;
      }

      final result = await _check(utterance, handle);
      if (result is TurnNeedsClarification && _asksBack) {
        await _clarify(result, handle);
        return;
      }
      await _conclude(result);
    } catch (error, stack) {
      // 실패를 완료처럼 알리지 않되, 실패한 채로 멈춰 있지도 않는다.
      _logger.e('Voice session failed', error: error, stackTrace: stack);
      _emit(const Unavailable(UnavailableReason.audioInterrupted));
      await _speak(_retryMessage);
    } finally {
      await _resumeDetection();
    }
  }

  /// 한 번 전사한다.
  ///
  /// [followUpTo] 가 있으면 답하고 있는 질문이다. 부분 전사를 흘리는 동안에도 이 값을
  /// 유지해야 화면에서 질문이 사라지지 않는다.
  Future<String?> _transcribe(
    Duration limit, {
    String? followUpTo,
    Duration? patience,
  }) async {
    // 부분 전사와 음량을 함께 흘린다. 마지막 값을 들고 있어야 한쪽만 와도 다른 쪽을
    // 잃지 않는다.
    var partial = '';
    var level = 0.0;
    // IMPORTANT: 전사가 끝난 뒤에도 인식기의 콜백이 늦게 온다. 그대로 받으면 확인 중에
    // 들린 말로 화면이 듣기로 되돌아간다. 확인 중에는 하던 일을 계속한다.
    var open = true;
    void emit() {
      if (!open) return;
      _emit(
        Listening(partialText: partial, level: level, followUpTo: followUpTo),
      );
    }

    try {
      return await _transcriber
          .transcribeOnce(
            patience: patience,
            onPartial: (value) {
              partial = value;
              emit();
            },
            onLevel: (value) {
              level = value;
              emit();
            },
          )
          .timeout(limit);
    } on TimeoutException {
      _logger.w('Transcription timed out after ${limit.inSeconds}s');
      return null;
    } on TranscriptionException catch (error) {
      _logger.w('Transcription failed: ${error.message}');
      return null;
    } finally {
      open = false;
    }
  }

  Future<void> _clarify(
    TurnNeedsClarification result,
    Future<VoiceTurnResult> Function(String utterance) handle,
  ) async {
    _emit(Clarifying(result.question));
    await _speak(result.question);

    // 호출어를 반복하지 않아도 답할 수 있게 짧은 창을 연다. 화면은 이 동안에도
    // 질문을 계속 보여준다 — 질문이 사라지면 무엇에 답하는지 알 수 없다.
    _emit(Listening(followUpTo: result.question));
    await _listeningCue?.call();
    // IMPORTANT: 응답 창은 **말을 시작하기까지**의 시간이다. 전사 전체에 걸면 답하는
    // 도중에 끊기고, 인식기 기본값(4초)에 맡기면 창이 절반만 열린다. 실기기에서
    // 질문을 듣고 답하려는 순간 화면이 닫혔다.
    final followUp = await _transcribe(
      commandTimeout,
      followUpTo: result.question,
      patience: clarifyWindow,
    );
    if (followUp == null || followUp.trim().isEmpty) {
      // 확인되지 않은 임시 변경은 적용하지 않는다.
      _logger.i('Clarification timed out; pending change discarded');
      return;
    }

    await _conclude(await _check(followUp, handle));
  }

  /// 서버에 보내고, 기다리는 동안 확인 중임을 말로 알린다.
  ///
  /// 낭독과 요청을 **동시에** 돌린다. 줄 세우면 낭독 시간만큼 결과가 늦는다. 낭독이
  /// 끝난 뒤에 돌아가는 것은 결과 낭독과 겹치지 않게 하려는 것이다.
  Future<VoiceTurnResult> _check(
    String utterance,
    Future<VoiceTurnResult> Function(String utterance) handle,
  ) async {
    _emit(Processing(utterance));
    final checking = _checkingMessage;
    final told = checking == null || checking.isEmpty
        ? Future.value(true)
        : _speak(checking);
    final result = await handle(utterance);
    await told;
    return result;
  }

  /// 결과를 알리고 끝낸다. **반영했을 때만** 반영 결과를 보여준다.
  Future<void> _conclude(VoiceTurnResult result) async {
    switch (result) {
      case TurnApplied(:final spoken):
        await _tell(Speaking(spoken), spoken);
      case TurnAnswered(:final spoken):
        await _answer(spoken);
      // 답을 듣지 않는 자리다. 무엇이 빠졌는지 알리고, 다시 말해달라고 한 뒤 닫는다.
      case TurnNeedsClarification(:final question):
        await _answer([question, ?_restartMessage].join(' '));
      case TurnFailed(:final spoken, :final logDetail):
        // 실패를 완료처럼 알리지 않는다.
        _logger.w('Turn failed: $logDetail');
        await _answer(spoken.isEmpty ? _retryMessage : spoken);
    }
  }

  /// 반영한 것이 없는 응답. 읽을 말이 없으면 바로 닫는다.
  Future<void> _answer(String text) async {
    if (text.isEmpty) return;
    await _tell(Answering(text), text);
  }

  Future<void> _tell(VoiceState showing, String text) async {
    final shown = Stopwatch()..start();
    _emit(showing);
    final spoken = await _speak(text);
    if (!spoken) {
      // 낭독이 실패해도 결과는 화면에 남는다. 대기 복귀는 finally 가 보장한다.
      _logger.w('TTS did not complete; result remains on screen only');
    }
    // 낭독 시간까지 포함해 최소 표시 시간을 채운다. 낭독이 길었으면 더 기다리지 않는다.
    final left = resultMinimum - shown.elapsed;
    if (left > Duration.zero) await Future<void>.delayed(left);
  }

  /// 낭독 한 번. 막히면 멈추고 넘어간다.
  ///
  /// 음성 응답을 꺼 두었으면 읽지 않고 **성공으로 답한다** — 사용자가 끈 것이지 실패가
  /// 아니며, 실패로 다루면 화면이 재시도 안내를 띄운다.
  ///
  /// [owner] 는 안내 낭독의 번호다. 밀려난 낭독이 뒤늦게 시간 초과로 끝나면서 **지금
  /// 읽고 있는 것을 멈추면 안 된다.**
  Future<bool> _speak(String text, {int? owner}) async {
    if (!(_spokenReply?.call() ?? true)) return true;
    try {
      return await _speaker.speak(text).timeout(speakTimeout);
    } on TimeoutException {
      _logger.w('TTS timed out after ${speakTimeout.inSeconds}s');
      if (owner == null || owner == _narration) await _speaker.stop();
      return false;
    } catch (error) {
      _logger.w('TTS failed: $error');
      return false;
    }
  }

  Future<void> _resumeDetection() async {
    await _transcriber.cancel();
    if (!_foreground) {
      _emit(const Suspended());
      return;
    }
    if (_muted) {
      _emit(const Muted());
      return;
    }
    try {
      await _detector.start();
      _emit(const Waiting());
    } catch (error, stack) {
      _logger.e('Failed to resume wake word detection', error: error, stackTrace: stack);
      _emit(const Unavailable(UnavailableReason.wakeWordInitFailed));
    }
  }

  /// 화면의 글을 읽어준다. 명령 대화가 아니라 조리 단계 같은 안내다.
  ///
  /// **읽는 동안 호출어 감지를 멈춘다.** 인식기가 마이크를 연 채로 읽으면 자기 목소리를
  /// 받아 적고, 인식기가 오디오를 가져가 낭독이 끊긴다. 다 읽으면 감지를 다시 세운다.
  ///
  /// 대화 중에는 읽지 않는다. 새로 읽기 시작하면 앞의 낭독을 멈춘다.
  ///
  /// Returns: 끝까지 읽었는지. 다른 낭독에 밀렸거나 읽지 못했으면 `false`.
  Future<bool> narrate(String text) async {
    if (_session != null || text.trim().isEmpty) return false;
    final mine = ++_narration;
    await _speaker.stop();
    await _detector.stop();
    final spoken = await _speak(text, owner: mine);
    // 새 낭독이 이어받았으면 감지를 세우지 않는다. 그쪽이 끝난 뒤에 세운다.
    if (mine != _narration) return false;
    if (_session == null) await _resumeDetection();
    return spoken;
  }

  /// 읽던 것을 멈추고 호출어 감지로 돌아간다. 화면을 떠날 때 부른다.
  Future<void> stopNarration() async {
    _narration += 1;
    await _speaker.stop();
    if (_session == null) await _resumeDetection();
  }

  /// 진행 중인 대화를 접고 대기로 돌아간다.
  ///
  /// 사용자가 오버레이를 닫은 것이다. 말을 걸어놓고 빠져나갈 길이 없으면 갇힌다.
  /// 진행 중인 전사와 낭독을 버리고 감지기를 다시 세운다.
  Future<void> cancelSession() async {
    _logger.i('Conversation cancelled by user');
    await _transcriber.cancel();
    await _speaker.stop();
    await _resumeDetection();
  }

  /// 음소거한다. 대기 중으로 표시하지 않는다.
  Future<void> mute() async {
    _muted = true;
    await _detector.stop();
    await _speaker.stop();
    _emit(const Muted());
  }

  /// 음소거를 해제하고 대기로 돌아간다.
  Future<void> unmute() async {
    _muted = false;
    await _resumeDetection();
  }

  /// 권한이 없거나 초기화가 실패한 상태를 그대로 표시한다.
  void markUnavailable(UnavailableReason reason) {
    _logger.w('Voice unavailable: $reason');
    _emit(Unavailable(reason));
  }

  /// 자원을 해제한다.
  Future<void> dispose() async {
    await _wakeSub?.cancel();
    _wakeSub = null;
    await _detector.dispose();
    await _speaker.dispose();
    await _states.close();
  }
}
