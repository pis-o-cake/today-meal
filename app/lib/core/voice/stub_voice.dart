/// 음성 계층의 자리표시 구현.
///
/// **실제 플러그인 배선은 S-01 에서 한다.** 그때까지 이 구현은 조용히 성공하지 않고 예외를
/// 던진다 — 조용히 넘기면 감지되는 것으로 착각하고, 화면은 대기 중인 것처럼 보인다.
///
/// 상태기계는 이 예외를 받아 `Unavailable` 로 표시하므로, 앱을 켜면 음성이 아직 배선되지
/// 않았다는 사실이 화면에 드러난다.
library;

import 'dart:async';

import 'voice_ports.dart';

class StubWakeWordDetector implements WakeWordDetector {
  final _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get detections => _controller.stream;

  @override
  Future<void> start() async {
    throw StateError('wake word detection is planned in slice S-01');
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _controller.close();
}

class StubSpeechTranscriber implements SpeechTranscriber {
  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<String> transcribeOnce({
    String localeId = 'ko_KR',
    void Function(String partial)? onPartial,
  }) async {
    throw const TranscriptionException('transcription is planned in slice S-01');
  }

  @override
  Future<void> cancel() async {}
}

class StubSpeechSpeaker implements SpeechSpeaker {
  @override
  Future<bool> isKoreanAvailable() async => false;

  @override
  Future<bool> speak(String text) async => false;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
