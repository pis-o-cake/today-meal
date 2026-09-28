import 'package:flutter_test/flutter_test.dart';
import 'package:today_meal/core/voice/device_wake_word_detector.dart';
import 'package:today_meal/core/voice/wake_listen_source.dart';

void main() {
  group('DeviceSpeechWakeWordDetector', () {
    test('준비에 실패하면 조용히 성공하지 않고 예외를 던진다', () async {
      final detector = DeviceSpeechWakeWordDetector(source: _FakeSource(ready: false));
      await expectLater(detector.start(), throwsA(isA<WakeWordException>()));
      await detector.dispose();
    });

    test('호출어가 섞인 전사에서 감지를 한 번 낸다', () async {
      final source = _FakeSource(segments: [
        ['오늘 날씨', '오늘 날씨 좋네'],
        ['자비스', '자비스 계란 두 개 썼어'],
      ]);
      final detector = DeviceSpeechWakeWordDetector(source: source);
      final seen = detector.detections.take(1).toList();

      await detector.start();
      await seen;
      // 감지 이벤트는 구간 안에서 나가고 마이크 해제는 구간이 반환된 뒤다. 루프가
      // 정리될 틈을 준 뒤에 확인한다.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(source.segmentsRun, 2, reason: '호출어 없는 구간은 흘려보내고 다음 구간을 듣는다');
      expect(source.aborted, isTrue, reason: '감지 후 마이크를 놓아야 전사기가 시작한다');
      await detector.dispose();
    });

    test('감지 후에는 루프를 멈춘다 — 재기동은 세션 매니저가 부른다', () async {
      final source = _FakeSource(segments: [
        ['자비스'],
        ['자비스'],
      ]);
      final detector = DeviceSpeechWakeWordDetector(source: source);
      final events = <void>[];
      final sub = detector.detections.listen(events.add);

      await detector.start();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(events, hasLength(1));
      expect(source.segmentsRun, 1);
      await sub.cancel();
      await detector.dispose();
    });

    test('구간이 실패해도 감지를 포기하지 않는다', () async {
      final source = _FakeSource(segments: [
        null, // 실패
        ['자비스'],
      ]);
      final detector = DeviceSpeechWakeWordDetector(source: source);
      final seen = detector.detections.take(1).toList();

      await detector.start();
      await seen;

      expect(source.segmentsRun, 2);
      await detector.dispose();
    });

    test('stop 이후에는 구간을 더 듣지 않는다', () async {
      final source = _FakeSource(segments: List.generate(20, (_) => ['잡음']));
      final detector = DeviceSpeechWakeWordDetector(source: source);

      await detector.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await detector.stop();
      final runAtStop = source.segmentsRun;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(source.segmentsRun, runAtStop);
      await detector.dispose();
    });
  });
}

/// 구간마다 흘려줄 전사 목록. `null` 인 구간은 실패한다.
class _FakeSource implements WakeListenSource {
  _FakeSource({this.ready = true, List<List<String>?>? segments})
      : _segments = segments ?? const [];

  final bool ready;
  final List<List<String>?> _segments;
  int segmentsRun = 0;
  bool aborted = false;

  @override
  Future<bool> prepare() async => ready;

  @override
  Future<void> listenOnce(void Function(String transcript) onTranscript) async {
    final index = segmentsRun;
    segmentsRun++;
    final scripted = index < _segments.length ? _segments[index] : <String>[];
    if (scripted == null) throw StateError('segment failed');
    for (final transcript in scripted) {
      onTranscript(transcript);
    }
  }

  @override
  Future<void> abort() async => aborted = true;
}
