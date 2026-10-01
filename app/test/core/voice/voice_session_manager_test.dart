import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:today_meal/core/voice/voice_ports.dart';
import 'package:today_meal/core/voice/voice_session_manager.dart';
import 'package:today_meal/core/voice/voice_state.dart';

/// 마이크 소유권 전환을 검증한다.
///
/// 확인하는 것은 순서다 — 전사를 시작하기 전에 감지기가 마이크를 놓았는지, 어떤 경로로
/// 끝나든 감지기가 다시 기동되는지, 배경에서는 감지하지 않는지.
void main() {
  late List<String> calls;
  late _FakeDetector detector;
  late _FakeTranscriber transcriber;
  late _FakeSpeaker speaker;

  setUp(() {
    calls = [];
    detector = _FakeDetector(calls);
    transcriber = _FakeTranscriber(calls);
    speaker = _FakeSpeaker(calls);
  });

  VoiceSessionManager build({String? checkingMessage, bool asksBack = false}) =>
      VoiceSessionManager(
        detector: detector,
        transcriber: transcriber,
        speaker: speaker,
        retryMessage: '반영하지 못했어요',
        checkingMessage: checkingMessage,
        restartMessage: '다시 말해주세요',
        asksBack: asksBack,
      );

  /// 한 번의 대화 동안 지나간 상태 이름.
  Future<List<String>> statesOf(
    VoiceSessionManager manager,
    VoiceTurnResult result,
  ) async {
    final seen = <VoiceState>[];
    final sub = manager.states.listen(seen.add);
    await manager.startSession((_) async => result);
    await sub.cancel();
    return seen.map((s) => s.runtimeType.toString()).toList();
  }

  test('감지기가 마이크를 놓은 뒤에 전사가 시작된다', () async {
    final manager = build();
    await manager.onForeground();
    calls.clear();

    await manager.startSession((_) async => const TurnAnswered('네'));

    final stopIndex = calls.indexOf('detector.stop');
    final transcribeIndex = calls.indexOf('transcriber.transcribe');
    expect(stopIndex, greaterThanOrEqualTo(0));
    expect(stopIndex, lessThan(transcribeIndex));
  });

  test('정상 처리 후 대기로 복귀한다', () async {
    final manager = build();
    await manager.onForeground();

    await manager.startSession((_) async => const TurnAnswered('네'));

    expect(calls, contains('detector.start'));
    expect(manager.state, isA<Waiting>());
  });

  test('낭독이 실패해도 대기로 복귀한다', () async {
    speaker.succeeds = false;
    final manager = build();
    await manager.onForeground();

    await manager.startSession((_) async => const TurnAnswered('네'));

    // 실패 경로에서도 돌아와야 한다. 한쪽 콜백만 걸면 여기서 멈춘다.
    expect(calls, contains('detector.start'));
    expect(manager.state, isA<Waiting>());
  });

  test('서버 호출이 실패해도 대기로 복귀한다', () async {
    final manager = build();
    await manager.onForeground();

    await manager.startSession(
      (_) async => const TurnFailed(spoken: '', logDetail: 'upstream 502'),
    );

    expect(calls, contains('detector.start'));
    expect(manager.state, isA<Waiting>());
  });

  test('말이 없었으면 아무것도 읽지 않고 닫는다', () async {
    // 다시 말해달라고 읽고 닫으면 말할 곳이 없다.
    transcriber.transcript = '';
    final manager = build(checkingMessage: '확인 중이에요');
    await manager.onForeground();

    final order = await statesOf(manager, const TurnApplied('반영했어요.'));

    expect(manager.state, isA<Waiting>());
    expect(speaker.spoken, isEmpty);
    expect(order, isNot(contains('Processing')));
    expect(order, isNot(contains('Speaking')));
  });

  test('바뀐 것이 없으면 반영 결과를 보여주지 않는다', () async {
    // 조회의 답을 반영 결과로 그리면 사용자는 재고가 바뀐 것으로 안다.
    final manager = build();
    await manager.onForeground();

    final order = await statesOf(manager, const TurnAnswered('계란은 여섯 개 있어요.'));

    expect(order, contains('Answering'));
    expect(order, isNot(contains('Speaking')));
    expect(speaker.spoken, ['계란은 여섯 개 있어요.']);
    expect(manager.state, isA<Waiting>());
  });

  test('읽을 말이 없는 응답은 바로 닫는다', () async {
    final manager = build();
    await manager.onForeground();

    final order = await statesOf(manager, const TurnAnswered(''));

    expect(order, isNot(contains('Answering')));
    expect(order, isNot(contains('Speaking')));
    expect(manager.state, isA<Waiting>());
  });

  test('실패는 반영 결과 없이 알린다', () async {
    final manager = build();
    await manager.onForeground();

    final order = await statesOf(
      manager,
      const TurnFailed(spoken: '', logDetail: 'upstream 502'),
    );

    expect(order, contains('Answering'));
    expect(order, isNot(contains('Speaking')));
    expect(speaker.spoken, ['반영하지 못했어요']);
  });

  test('확인 중에 들린 말에는 반응하지 않는다', () async {
    // 전사가 끝난 뒤에도 인식기의 콜백이 늦게 온다. 받으면 화면이 듣기로 되돌아간다.
    final manager = build();
    await manager.onForeground();

    final seen = <VoiceState>[];
    final sub = manager.states.listen(seen.add);
    await manager.startSession((_) async {
      transcriber.late?.call('다른 말');
      return const TurnApplied('반영했어요.');
    });
    await sub.cancel();

    final order = seen.map((s) => s.runtimeType.toString()).toList();
    final processing = order.indexOf('Processing');
    expect(processing, greaterThanOrEqualTo(0));
    expect(order.sublist(processing), isNot(contains('Listening')));
  });

  test('안내를 읽는 동안 감지를 멈추고 다 읽으면 다시 세운다', () async {
    // 인식기가 마이크를 연 채로 읽으면 자기 목소리를 받아 적고 낭독이 끊긴다.
    final manager = build();
    await manager.onForeground();
    calls.clear();

    final read = await manager.narrate('두부를 썬다');

    expect(read, isTrue);
    expect(speaker.spoken, ['두부를 썬다']);
    expect(calls.indexOf('detector.stop'), lessThan(calls.indexOf('speaker.speak')));
    expect(calls.indexOf('speaker.speak'), lessThan(calls.lastIndexOf('detector.start')));
    expect(manager.state, isA<Waiting>());
  });

  test('확인하는 동안 확인 중임을 말하고 결과는 그 뒤에 읽는다', () async {
    final manager = build(checkingMessage: '확인 중이에요');
    await manager.onForeground();

    await manager.startSession((_) async => const TurnApplied('반영했어요.'));

    expect(speaker.spoken, ['확인 중이에요', '반영했어요.']);
  });

  test('음소거 중에는 전사하지 않는다', () async {
    final manager = build();
    await manager.onForeground();
    await manager.mute();
    calls.clear();

    await manager.startSession((_) async => const TurnAnswered('네'));

    expect(calls, isNot(contains('transcriber.transcribe')));
    expect(manager.state, isA<Muted>());
  });

  test('배경에서는 감지하지 않고 Suspended 로 표시한다', () async {
    final manager = build();
    await manager.onForeground();
    await manager.onBackground();
    calls.clear();

    await manager.startSession((_) async => const TurnAnswered('네'));

    // 전경 한정이다. 대기 중인 것처럼 보이게 두지 않는다.
    expect(calls, isNot(contains('transcriber.transcribe')));
    expect(manager.state, isA<Suspended>());
  });

  test('전경 복귀 시 감지를 다시 시작한다', () async {
    final manager = build();
    await manager.onForeground();
    await manager.onBackground();
    calls.clear();

    await manager.onForeground();

    expect(calls, contains('detector.start'));
    expect(manager.state, isA<Waiting>());
  });

  test('되묻지 않으면 빠진 것을 알리고 닫는다', () async {
    // 질문을 듣고 답해도 반영까지 이어지지 않는 경우가 있다. 묻고 실패하는 것보다 낫다.
    final manager = build();
    await manager.onForeground();
    var handled = 0;

    final seen = <VoiceState>[];
    final sub = manager.states.listen(seen.add);
    await manager.startSession((_) async {
      handled += 1;
      return const TurnNeedsClarification('계란은 얼마나인가요?');
    });
    await sub.cancel();

    final order = seen.map((s) => s.runtimeType.toString()).toList();
    expect(order, contains('Answering'));
    expect(order, isNot(contains('Clarifying')));
    expect(order, isNot(contains('Speaking')));
    expect(speaker.spoken, ['계란은 얼마나인가요? 다시 말해주세요']);
    // 답을 들으려고 마이크를 다시 열지 않는다.
    expect(transcriber.patiences.length, 1);
    expect(handled, 1);
    expect(manager.state, isA<Waiting>());
  });

  test('되묻기 후 응답이 없으면 임시 변경을 적용하지 않는다', () async {
    final manager = build(asksBack: true);
    await manager.onForeground();
    var handled = 0;
    transcriber.followUpTranscript = '';

    await manager.startSession((_) async {
      handled += 1;
      return const TurnNeedsClarification('몇 월인가요?');
    });

    // 후속 응답이 없으면 handle 을 두 번 부르지 않는다.
    expect(handled, 1);
    expect(manager.state, isA<Waiting>());
  });

  test('되묻고 나면 응답 창만큼 말을 기다린다', () async {
    // 인식기 기본값에 맡겼더니 8초 창이 4초에 닫혔다. 질문을 듣고 답하려는 순간이었다.
    final manager = build(asksBack: true);
    await manager.onForeground();
    var asked = false;

    await manager.startSession((_) async {
      if (asked) return const TurnApplied('반영했어요.');
      asked = true;
      return const TurnNeedsClarification('어떤 단위인가요?');
    });

    expect(transcriber.patiences, [null, VoiceSessionManager.clarifyWindow]);
  });

  test('감지기 기동이 실패하면 사용 불가로 표시한다', () async {
    detector.failOnStart = true;
    final manager = build();

    await manager.onForeground();

    expect(manager.state, isA<Unavailable>());
    expect(
      (manager.state as Unavailable).reason,
      UnavailableReason.wakeWordInitFailed,
    );
  });

  test('bindWakeWord 이후 감지 이벤트가 세션을 시작한다', () async {
    // 이 배선이 빠져 있어 실기기에서 감지는 되고 아무 일도 일어나지 않았다.
    final manager = build();
    final handled = <String>[];
    manager.bindWakeWord((utterance) async {
      handled.add(utterance);
      return const TurnAnswered('반영했어요.');
    });

    await manager.onForeground();
    detector.emitDetection();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(handled, ['계란 두 개 썼어']);
  });

  test('호출하면 듣기 → 확인 → 반영 순서로만 간다', () async {
    // 호출 응답("네?")을 Speaking 으로 내보냈더니 화면이 그것을 **반영 결과**로 그려서,
    // 부르자마자 반영 화면이 떴다.
    final manager = build();
    await manager.onForeground();

    final seen = <VoiceState>[];
    manager.states.listen(seen.add);

    await manager.startSession((_) async => const TurnApplied('반영했어요.'));

    final order = seen.map((s) => s.runtimeType.toString()).toList();
    final firstSpeaking = order.indexOf('Speaking');
    final firstListening = order.indexOf('Listening');
    final firstProcessing = order.indexOf('Processing');

    expect(firstListening, greaterThanOrEqualTo(0));
    expect(firstListening, lessThan(firstProcessing),
        reason: '듣기가 확인보다 먼저다');
    expect(firstProcessing, lessThan(firstSpeaking),
        reason: '반영은 확인 뒤에만 나온다');
  });

  test('호출 즉시 듣기 상태로 바꾼다', () async {
    // 마이크를 넘기는 데 1초 넘게 걸린다. 그동안 화면이 그대로면 호출이 안 된 것으로
    // 보인다.
    final manager = build();
    await manager.onForeground();

    final seen = <VoiceState>[];
    manager.states.listen(seen.add);

    final session = manager.startSession((_) async => const TurnAnswered('네'));
    await Future<void>.delayed(Duration.zero);

    expect(seen.first, isA<Listening>(), reason: '마이크를 넘기기 전에 화면부터 바꾼다');
    await session;
  });

  testWidgets('낭독이 응답하지 않아도 대기로 돌아온다', (tester) async {
    // flutter_tts 의 완료 콜백이 오지 않으면 영원히 기다린다. 실기기에서 반영 화면에
    // 갇힌 원인이다. 대기로 못 돌아오는 것이 이 제품에서 가장 나쁜 고장이다.
    speaker.hangs = true;
    final manager = build();
    await manager.onForeground();

    final states = <VoiceState>[];
    manager.states.listen(states.add);

    final session = manager.startSession((_) async => const TurnApplied('반영했어요.'));
    await tester.pump(VoiceSessionManager.speakTimeout + const Duration(seconds: 1));
    await tester.pump(VoiceSessionManager.resultMinimum + const Duration(seconds: 1));
    await session;

    expect(manager.state, isA<Waiting>(), reason: '낭독이 막혀도 대기로 돌아와야 한다');
    expect(calls, contains('speaker.stop'));
  });

  test('전경이 아니면 감지를 무시한다', () async {
    final manager = build();
    final handled = <String>[];
    manager.bindWakeWord((utterance) async {
      handled.add(utterance);
      return const TurnAnswered('반영했어요.');
    });

    detector.emitDetection();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(handled, isEmpty);
  });
}

class _FakeDetector implements WakeWordDetector {
  _FakeDetector(this.calls);

  final List<String> calls;
  bool failOnStart = false;
  final _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get detections => _controller.stream;

  @override
  Stream<Heard> get heard => const Stream.empty();

  @override
  Future<void> start() async {
    calls.add('detector.start');
    if (failOnStart) throw StateError('access key missing');
  }

  @override
  Future<void> stop() async => calls.add('detector.stop');

  /// 감지 이벤트를 흘려보낸다.
  void emitDetection() => _controller.add(null);

  @override
  Future<void> dispose() async {
    calls.add('detector.dispose');
    await _controller.close();
  }
}

class _FakeTranscriber implements SpeechTranscriber {
  _FakeTranscriber(this.calls);

  final List<String> calls;
  String transcript = '계란 두 개 썼어';
  String? followUpTranscript;
  int _count = 0;

  /// 전사가 끝난 뒤에도 남아 있는 중간 결과 콜백.
  void Function(String partial)? late;

  /// 전사마다 받은 기다림 시간.
  final patiences = <Duration?>[];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String> transcribeOnce({
    String localeId = 'ko_KR',
    Duration? patience,
    void Function(String partial)? onPartial,
    void Function(double level)? onLevel,
  }) async {
    calls.add('transcriber.transcribe');
    patiences.add(patience);
    late = onPartial;
    _count += 1;
    if (_count > 1 && followUpTranscript != null) return followUpTranscript!;
    return transcript;
  }

  @override
  Future<void> cancel() async => calls.add('transcriber.cancel');
}

class _FakeSpeaker implements SpeechSpeaker {
  _FakeSpeaker(this.calls);

  final List<String> calls;

  /// 읽은 문장. 순서대로 쌓는다.
  final spoken = <String>[];
  bool succeeds = true;

  /// 완료 콜백이 오지 않는 상태. 실기기의 삼성 TTS 가 이렇게 멈췄다.
  bool hangs = false;

  @override
  Future<bool> isKoreanAvailable() async => true;

  @override
  Future<bool> speak(String text) {
    calls.add('speaker.speak');
    spoken.add(text);
    if (hangs) return Completer<bool>().future;
    return Future.value(succeeds);
  }

  @override
  Future<void> stop() async => calls.add('speaker.stop');

  @override
  Future<void> dispose() async => calls.add('speaker.dispose');
}
