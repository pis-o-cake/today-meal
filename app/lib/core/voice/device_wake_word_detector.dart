/// 기기 내장 인식 서비스로 호출어를 감지한다.
///
/// 처음에는 sherpa-onnx 의 온디바이스 한국어 스트리밍 ASR 을 썼다. 갤럭시 SM-E426S
/// (Android 13) 에서 127MB 인코더를 올리는 도중 **시그널 없이 프로세스째로 정리**됐다
/// (탐블스톤·SIGSEGV 없음, `libprocessgroup killed cgroup ... in 0ms`). 성공해도 상시
/// 127MB 상주는 저가 기기 시연에서 같은 위험이 남으므로 수단을 바꿨다.
///
/// 지금은 짧은 구간 청취를 반복하며 전사에서 호출어를 찾는다. 전용 호출어 엔진이 아니라
/// 범용 인식기를 쓰는 타협이다. 대가는 배터리와 구간 사이의 짧은 공백이다.
library;

import 'dart:async';

import 'package:logger/logger.dart';

import 'voice_ports.dart';
import 'wake_listen_source.dart';
import 'wake_phrase.dart';

/// 호출어 감지 자체가 불가능한 상태. 메시지는 로그용이므로 영어로 고정한다.
class WakeWordException implements Exception {
  const WakeWordException(this.message);

  final String message;

  @override
  String toString() => 'WakeWordException: $message';
}

/// 구간 청취를 반복하는 감지기.
class DeviceSpeechWakeWordDetector implements WakeWordDetector {
  DeviceSpeechWakeWordDetector({
    required WakeListenSource source,
    String phrase = defaultWakePhrase,
    Logger? logger,
  })  : _source = source,
        _phrase = phrase,
        _logger = logger ?? Logger(printer: SimplePrinter());

  /// 구간이 정상 종료된 뒤 다음 구간까지의 간격. 인식 서비스가 마이크를 놓을 틈이다.
  static const _gap = Duration(milliseconds: 250);

  /// 실패 후 첫 재시도 간격. 실패가 이어지면 배로 늘린다.
  static const _retryBase = Duration(milliseconds: 400);

  /// 재시도 간격 상한. 다른 앱이 마이크를 오래 잡아도 포기하지 않고 이 간격으로 버틴다.
  static const _retryCap = Duration(seconds: 8);

  final WakeListenSource _source;
  final String _phrase;
  final Logger _logger;
  final _detections = StreamController<void>.broadcast();
  final _heard = StreamController<Heard>.broadcast();

  bool _running = false;
  int _failures = 0;
  int _segment = 0;
  Future<void>? _loop;

  @override
  Stream<void> get detections => _detections.stream;

  @override
  Stream<Heard> get heard => _heard.stream;

  @override
  Future<void> start() async {
    if (_running) return;
    if (!await _source.prepare()) {
      // 조용히 성공하면 감지되는 것으로 착각한다.
      throw const WakeWordException('speech recognizer is unavailable');
    }
    _running = true;
    _failures = 0;
    _loop = _run();
    _logger.i('Wake word detection started');
  }

  @override
  Future<void> stop() async {
    if (!_running && _loop == null) return;
    _running = false;
    await _source.abort();
    await _loop;
    _loop = null;
    _logger.i('Wake word detection stopped');
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _detections.close();
    await _heard.close();
  }

  Future<void> _run() async {
    while (_running) {
      final matched = await _listenSegment();
      if (matched) {
        // 마이크를 놓아야 전사기가 시작할 수 있다. 재기동은 세션 매니저가 부른다.
        _running = false;
        await _source.abort();
        return;
      }
      if (!_running) return;
      await Future<void>.delayed(_failures == 0 ? _gap : _retryDelay());
    }
  }

  /// Returns: 이 구간에서 호출어를 찾았는지.
  Future<bool> _listenSegment() async {
    var matched = false;
    final segment = ++_segment;
    try {
      await _source.listenOnce((transcript) {
        if (matched || !_running) return;
        if (transcript.isNotEmpty && !_heard.isClosed) {
          _heard.add((segment: segment, transcript: transcript));
        }
        if (matchWakePhrase(transcript, phrase: _phrase) == null) return;
        matched = true;
        _logger.i('Wake phrase detected');
        if (!_detections.isClosed) _detections.add(null);
      });
      _failures = 0;
    } catch (error) {
      // 구간 실패로 감지를 포기하지 않는다. 마이크는 다른 앱이 잠깐 잡을 수 있다.
      _failures++;
      _logger.w('Wake listen segment failed ($_failures): $error');
    }
    return matched;
  }

  Duration _retryDelay() {
    final scaled = _retryBase * (1 << (_failures - 1).clamp(0, 8));
    return scaled > _retryCap ? _retryCap : scaled;
  }
}

/// 마이크를 잡지 않는 감지기.
///
/// 감지기가 기기에서 문제를 일으킬 때 원인을 가르는 스위치이자, 배터리를 아끼고 싶을
/// 때의 설정이다. 이때는 마이크 버튼이 주 진입이 된다.
class DisabledWakeWordDetector implements WakeWordDetector {
  final _detections = StreamController<void>.broadcast();

  @override
  Stream<void> get detections => _detections.stream;

  @override
  Stream<Heard> get heard => const Stream.empty();

  @override
  Future<void> start() async {
    // 조용히 성공한다. 꺼 두기로 한 상태이므로 예외를 던지지 않는다.
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _detections.close();
}
