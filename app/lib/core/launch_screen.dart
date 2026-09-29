/// 시스템 스플래시가 걷힌 시각.
///
/// Flutter 는 시스템 스플래시 **뒤에서** 이미 프레임을 그린다. 그래서 위젯이 스스로는
/// 언제부터 사람에게 보이는지 알 수 없고, 그냥 시작하면 연출이 가려진 채로 돌다가
/// **중간부터** 보인다 — 실기기에서 겪었다.
///
/// 네이티브가 그 순간을 알려준다(`MainActivity`). 채널이 없는 플랫폼과 시험 환경에서는
/// 기다리지 않는다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class LaunchScreen {
  static const _channel = MethodChannel('today_meal/launch');

  /// 기다림의 상한. 네이티브가 답하지 않아도 앱이 멈추면 안 된다.
  static const _limit = Duration(seconds: 4);

  /// 시스템 스플래시가 걷힐 때까지.
  ///
  /// 안드로이드가 아니거나 채널이 없으면 바로 끝난다. 답이 오지 않아도 [_limit] 뒤에
  /// 끝난다 — 연출을 영영 시작하지 못하는 것보다 조금 일찍 시작하는 편이 낫다.
  static Future<void> gone() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel
          .invokeMethod<void>('awaitSystemSplash')
          .timeout(_limit, onTimeout: () {});
    } on MissingPluginException {
      // 시험 환경에는 네이티브가 없다. 기다릴 것도 없다.
    } catch (error) {
      debugPrint('launch screen channel failed: $error');
    }
  }
}
