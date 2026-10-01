/// 듣기 시작 신호음.
///
/// 호출 응답을 말("네?")로 하면 낭독이 끝나야 듣기 시작해 앞말이 잘린다. 짧은 두 음으로
/// 바꾸고, 소리가 끝난 뒤에 듣기 시작해 신호음을 받아쓰지 않는다.
library;

import 'package:flutter/services.dart';
import 'package:logger/logger.dart';

class ListeningCue {
  ListeningCue({Logger? logger}) : _logger = logger ?? Logger(printer: SimplePrinter());

  static const _channel = MethodChannel('today_meal/cue');

  /// 네이티브가 길이를 알려주지 않을 때의 대기.
  static const _fallback = Duration(milliseconds: 200);

  final Logger _logger;

  /// 신호음을 울리고 끝날 때까지 기다린다. 실패해도 예외를 내지 않는다 — 부가 연출이다.
  Future<void> play() async {
    try {
      final ms = await _channel.invokeMethod<int>('playListening');
      await Future<void>.delayed(ms == null ? _fallback : Duration(milliseconds: ms));
    } on MissingPluginException {
      // 신호음을 구현하지 않은 플랫폼. 소리 없이 듣는다.
    } on PlatformException catch (error) {
      _logger.w('Listening cue failed: ${error.message}');
    }
  }
}
