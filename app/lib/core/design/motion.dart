/// 움직임의 기준.
///
/// 목업의 연출은 대부분 **끊임없이 도는 반복 애니메이션**이다. 스플래시의 착지, 단계
/// 막대의 빛 흐름, 듣는 중의 파동, 캐릭터의 들썩임이 모두 그렇다.
///
/// 반복 애니메이션은 두 가지를 지켜야 한다.
///
/// 1. **모션 감소 설정을 존중한다.** OS 에서 움직임을 줄이라고 했으면 정지 상태로
///    그린다. UI 계약의 UI-00 규칙이며 다른 화면에도 같이 적용한다.
/// 2. **초기화 실패를 움직임으로 감추지 않는다.** 도는 그림은 "살아 있다" 는 뜻이라
///    실패한 동안 돌면 사용자가 기다리게 된다.
library;

import 'package:flutter/widgets.dart';

/// 목업의 반복 주기.
abstract final class Motion {
  /// 단계 막대의 빛이 한 번 흐르는 시간.
  static const stepSheen = Duration(milliseconds: 1500);

  /// 현재 단계 점이 한 번 맥박하는 시간.
  static const pulse = Duration(milliseconds: 1400);

  /// 듣는 중 파동이 한 겹 퍼지는 시간.
  static const ripple = Duration(milliseconds: 2400);

  /// 캐릭터가 숨쉬는 주기.
  static const breath = Duration(seconds: 4);

  /// 스플래시 한 판. 목업의 4.2초 반복은 관찰용이고 앱은 이 길이로 한 번만 재생한다.
  static const splash = Duration(milliseconds: 1800);

  /// 고른 얼굴 뒤 갈기가 한 바퀴 도는 시간.
  ///
  /// 목업의 24초다. 느린 것이 의도이며 줄이면 시선을 끌어 밴드 한마디를 가린다.
  static const maneTurn = Duration(seconds: 24);

  /// 조리 단계 타이머의 눈금이 한 번 도는 시간. 실제 남은 시간은 타이머가 정한다.
  static const cookTick = Duration(seconds: 1);

  /// 주 행동이 다음 메뉴로 넘어가는 간격.
  ///
  /// 읽을 시간을 줘야 한다. 이보다 짧으면 이름을 다 읽기 전에 바뀐다.
  static const menuTurn = Duration(milliseconds: 3600);

  /// 알약이 반 바퀴 도는 시간.
  ///
  /// 이보다 빠르면 무엇이 돌았는지 못 보고 글자만 바뀐 것으로 읽힌다.
  static const menuFlip = Duration(milliseconds: 620);

  /// 등급을 넘길 때의 스프링.
  static const bandSpring = Duration(milliseconds: 460);

  /// 화면 배색이 바뀌는 시간.
  static const skinFade = Duration(milliseconds: 320);
}

/// 움직임을 줄여야 하는지.
extension MotionContext on BuildContext {
  /// OS 가 움직임을 줄이라고 했는지.
  ///
  /// 참이면 반복 애니메이션을 돌리지 않고 **가장 읽기 쉬운 한 장면**으로 고정한다.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}
