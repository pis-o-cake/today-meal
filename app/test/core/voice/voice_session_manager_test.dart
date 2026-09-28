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

  VoiceSessionManager build() => VoiceSessionManager(
        detector: detector,
        transcriber: transcriber,
        speaker: speaker,
        retryMessage: '다시 말해주세요',
      );

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

  test('전사가 비면 재시도 문구를 읽고 대기로 복귀한다', () async {
    transcriber.transcript = '';
    final manager = build();
    await manager.onForeground();

    await manager.startSession((_) async => const TurnAnswered('네'));

    expect(manager.state, isA<Waiting>());
    expect(calls, contains('speaker.speak'));
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

  test('되묻기 후 응답이 없으면 임시 변경을 적용하지 않는다', () async {
    final manager = build();
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

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String> transcribeOnce({
    String localeId = 'ko_KR',
    void Function(String partial)? onPartial,
  }) async {
    calls.add('transcriber.transcribe');
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
  bool succeeds = true;

  @override
  Future<bool> isKoreanAvailable() async => true;

  @override
  Future<bool> speak(String text) async {
    calls.add('speaker.speak');
    return succeeds;
  }

  @override
  Future<void> stop() async => calls.add('speaker.stop');

  @override
  Future<void> dispose() async => calls.add('speaker.dispose');
}
