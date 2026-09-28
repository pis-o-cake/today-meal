/// `speech_to_text` 플러그인 하나를 공유한다.
///
/// WARNING: 플러그인은 플랫폼 쪽에서 단일 인스턴스다. `initialize` 에 넘긴
/// `onStatus`/`onError` 는 **마지막 호출자만 남는다.** 호출어 감지기와 전사기가 각각
/// 초기화하면 한쪽 콜백이 조용히 사라져, 인식 실패를 감지하지 못한 채 멈춘다.
///
/// 그래서 초기화와 콜백 분배를 이 클래스 하나가 소유하고, 감지기·전사기는 이것을
/// 주입받는다. 마이크 소유권 자체는 `VoiceSessionManager` 가 계속 관리한다.
library;

import 'dart:async';

import 'package:logger/logger.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 공유 인식 엔진.
class SpeechEngine {
  SpeechEngine({SpeechToText? speech, Logger? logger})
      : _speech = speech ?? SpeechToText(),
        _logger = logger ?? Logger(printer: SimplePrinter());

  final SpeechToText _speech;
  final Logger _logger;
  final _statuses = StreamController<String>.broadcast();
  final _errors = StreamController<String>.broadcast();
  bool _ready = false;

  /// 플러그인 본체. 청취 옵션은 사용하는 쪽이 정한다.
  SpeechToText get plugin => _speech;

  /// 인식 서비스의 상태 변화. `listening` · `notListening` · `done`.
  Stream<String> get statuses => _statuses.stream;

  /// 인식 오류. 메시지는 플러그인이 주는 영어 코드다.
  Stream<String> get errors => _errors.stream;

  bool get isListening => _speech.isListening;

  /// 한 번만 초기화한다. 실패하면 `false` 를 돌려주고 예외를 던지지 않는다.
  Future<bool> ensureReady() async {
    if (_ready) return true;
    try {
      _ready = await _speech.initialize(
        onStatus: (status) {
          if (!_statuses.isClosed) _statuses.add(status);
        },
        onError: (error) {
          _logger.w('Speech error: ${error.errorMsg}');
          if (!_errors.isClosed) _errors.add(error.errorMsg);
        },
      );
    } catch (error, stack) {
      _logger.e('Speech engine init failed', error: error, stackTrace: stack);
      _ready = false;
    }
    return _ready;
  }

  /// 취소 후 다음 청취를 시작하기까지의 정리 시간.
  ///
  /// WARNING: Android `SpeechRecognizer` 는 취소 직후 곧바로 시작하면
  /// `error_client` 로 거부한다. 실기기에서 호출어 감지 15ms 뒤에 전사가 실패한
  /// 원인이다. 이 틈이 없으면 호출해도 명령을 받지 못한다.
  ///
  /// 호출 반응 속도에 그대로 더해지므로 필요한 만큼만 둔다. 250ms 로 줄여 실기기에서
  /// 확인했다.
  static const settle = Duration(milliseconds: 250);

  /// 진행 중인 청취를 버리고 마이크를 놓는다.
  Future<void> release() async {
    if (!_speech.isListening) return;
    try {
      await _speech.cancel();
    } catch (error) {
      _logger.w('Speech release failed: $error');
    }
    await Future<void>.delayed(settle);
  }

  Future<void> dispose() async {
    await release();
    await _statuses.close();
    await _errors.close();
  }
}
