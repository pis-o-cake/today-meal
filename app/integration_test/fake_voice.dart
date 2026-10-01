/// 실기기 검증용 가짜 음성 계층.
///
/// 마이크와 스피커만 가짜다. 그 뒤의 것 — 상태 전환, 대화 오버레이 화면, 서버 왕복,
/// 재고 변경, 결과 표시 시간 — 은 **모두 실제**다. 소리를 낼 수 없는 자동 검증에서
/// 대화 흐름 전체를 확인하기 위한 것이다.
///
/// WARNING: 이것으로 확인되지 않는 것이 있다. 호출어 인식률, 한국어 전사 정확도, 낭독
/// 중 자기 응답 재인식, 기기의 마이크 점유 충돌은 **실제 소리로만** 확인된다. 이 파일이
/// 통과한 것을 F-01~03 의 실기기 검증으로 기록하지 않는다.
library;

import 'dart:async';

import 'package:today_meal/core/voice/voice_ports.dart';

/// 호출어를 코드로 흘려보내는 감지기.
class FakeDetector implements WakeWordDetector {
  final _detections = StreamController<void>.broadcast();
  final _heard = StreamController<Heard>.broadcast();

  /// 감지기가 지금 마이크를 쥐고 있는지. 전사 전에 놓았는지 확인한다.
  bool listening = false;

  @override
  Stream<void> get detections => _detections.stream;

  @override
  Stream<Heard> get heard => _heard.stream;

  @override
  Future<void> start() async => listening = true;

  @override
  Future<void> stop() async => listening = false;

  /// 호출어가 들렸다.
  void callOut() => _detections.add(null);

  /// 호출어 없이 들린 짧은 말. 조리 화면이 쓴다.
  void say(int segment, String transcript) =>
      _heard.add((segment: segment, transcript: transcript));

  @override
  Future<void> dispose() async {
    await _detections.close();
    await _heard.close();
  }
}

/// 미리 정해 둔 말을 돌려주는 전사기.
class FakeTranscriber implements SpeechTranscriber {
  /// 다음에 전사될 말들. 앞에서부터 하나씩 쓴다.
  final queue = <String>[];

  /// 큐가 비었을 때 돌려줄 말. `null` 이면 무음으로 둔다.
  String? fallback;

  /// 전사 시작까지 두는 지연. 듣는 화면이 보이는지 확인할 틈을 준다.
  Duration delay = const Duration(milliseconds: 600);

  /// 전사할 때마다 받은 기다림 시간. 되묻기 창이 명령보다 긴지 본다.
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
    patiences.add(patience);
    await Future<void>.delayed(delay);
    final next = queue.isEmpty ? fallback : queue.removeAt(0);
    if (next == null) throw const TranscriptionException('no speech');
    // 중간 결과와 입력 크기도 실제처럼 흘려보낸다. 듣는 화면이 이 값으로 그린다.
    onPartial?.call(next);
    onLevel?.call(0.6);
    return next;
  }

  @override
  Future<void> cancel() async {}
}

/// 소리를 내지 않고 읽은 문장만 쌓는 낭독기.
class FakeSpeaker implements SpeechSpeaker {
  final spoken = <String>[];

  /// 낭독 한 번에 걸리는 시간. 결과 화면이 낭독이 끝날 때까지 남는지 본다.
  Duration duration = const Duration(milliseconds: 300);

  @override
  Future<bool> isKoreanAvailable() async => true;

  @override
  Future<bool> speak(String text) async {
    spoken.add(text);
    await Future<void>.delayed(duration);
    return true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
