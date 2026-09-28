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
    required String retryMessage,
    String? ackMessage,
    Logger? logger,
  })  : _detector = detector,
        _transcriber = transcriber,
        _speaker = speaker,
        _retryMessage = retryMessage,
        _ackMessage = ackMessage,
        _logger = logger ?? Logger(printer: SimplePrinter());

  /// 명령 세션의 앱 타임아웃. 인식 서비스의 무음 종료와 별개로 건다.
  static const commandTimeout = Duration(seconds: 20);

  /// 재질문 후속 응답 창.
  static const clarifyWindow = Duration(seconds: 10);

  final WakeWordDetector _detector;
  final SpeechTranscriber _transcriber;
  final SpeechSpeaker _speaker;
  final String _retryMessage;

  /// 호출에 바로 답할 문구. 없으면 답하지 않는다.
  final String? _ackMessage;

  final Logger _logger;

  final _states = StreamController<VoiceState>.broadcast();
  VoiceState _current = const Suspended();
  Future<void>? _session;
  StreamSubscription<void>? _wakeSub;
  bool _muted = false;
  bool _foreground = false;

  /// 화면과 ViewModel 이 구독하는 유일한 상태.
  Stream<VoiceState> get states => _states.stream;

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
    final started = _runSession(handle).whenComplete(() => _session = null);
    _session = started;
    return started;
  }

  Future<void> _runSession(
    Future<VoiceTurnResult> Function(String utterance) handle,
  ) async {
    try {
      // 감지기가 마이크를 놓아야 전사기가 시작할 수 있다.
      await _detector.stop();

      // 호출에 바로 답한다. 불러도 아무 반응이 없으면 동작하지 않는 것으로 보인다.
      // 낭독이 끝난 뒤에 듣기 시작해야 자기 목소리를 명령으로 되받지 않는다.
      final ack = _ackMessage;
      if (ack != null && ack.isNotEmpty) {
        _emit(Speaking(ack));
        await _speaker.speak(ack);
      }

      _emit(const Listening());
      final utterance = await _transcribe(commandTimeout);
      if (utterance == null || utterance.trim().isEmpty) {
        _logger.w('Command transcription produced no result');
        await _speakAndFinish(_retryMessage);
        return;
      }

      _emit(Processing(utterance));
      final result = await handle(utterance);
      switch (result) {
        case TurnAnswered(:final spoken):
          await _speakAndFinish(spoken);
        case TurnNeedsClarification():
          await _clarify(result, handle);
        case TurnFailed(:final spoken, :final logDetail):
          // 실패를 완료처럼 알리지 않는다.
          _logger.w('Turn failed: $logDetail');
          await _speakAndFinish(spoken.isEmpty ? _retryMessage : spoken);
      }
    } catch (error, stack) {
      _logger.e('Voice session failed', error: error, stackTrace: stack);
      _emit(const Unavailable(UnavailableReason.audioInterrupted));
    } finally {
      await _resumeDetection();
    }
  }

  Future<String?> _transcribe(Duration limit) async {
    try {
      return await _transcriber
          .transcribeOnce(onPartial: (partial) => _emit(Listening(partialText: partial)))
          .timeout(limit);
    } on TimeoutException {
      _logger.w('Transcription timed out after ${limit.inSeconds}s');
      return null;
    } on TranscriptionException catch (error) {
      _logger.w('Transcription failed: ${error.message}');
      return null;
    }
  }

  Future<void> _clarify(
    TurnNeedsClarification result,
    Future<VoiceTurnResult> Function(String utterance) handle,
  ) async {
    _emit(Clarifying(result.question));
    await _speaker.speak(result.question);

    // 호출어를 반복하지 않아도 답할 수 있게 짧은 창을 연다.
    _emit(const Listening());
    final followUp = await _transcribe(clarifyWindow);
    if (followUp == null || followUp.trim().isEmpty) {
      // 확인되지 않은 임시 변경은 적용하지 않는다.
      _logger.i('Clarification timed out; pending change discarded');
      return;
    }

    _emit(Processing(followUp));
    final next = await handle(followUp);
    final text = switch (next) {
      TurnAnswered(:final spoken) => spoken,
      TurnFailed(:final spoken) => spoken.isEmpty ? _retryMessage : spoken,
      TurnNeedsClarification(:final question) => question,
    };
    await _speakAndFinish(text);
  }

  Future<void> _speakAndFinish(String text) async {
    _emit(Speaking(text));
    final spoken = await _speaker.speak(text);
    if (!spoken) {
      // 낭독이 실패해도 결과는 화면에 남는다. 대기 복귀는 finally 가 보장한다.
      _logger.w('TTS did not complete; result remains on screen only');
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
