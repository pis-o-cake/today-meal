import 'package:flutter/widgets.dart';

/// 화면 폭으로 판정한 기기 형태.
///
/// **태블릿 전용 화면을 따로 만들지 않는다.** 주방 고정 태블릿이 후속 방향이고, 화면을
/// 두 벌 유지하면 그 전환에서 한쪽이 뒤처진다. 대신 화면마다 이 값을 읽어 배치를 바꾼다.
enum FormFactor {
  /// 핸드폰 세로. 기준 형태다. 1단으로 쌓는다.
  compact,

  /// 핸드폰 가로 · 작은 태블릿. 2단까지 벌린다.
  medium,

  /// 태블릿 가로. 주방 거치 상태의 대시보드가 여기 온다.
  expanded;

  bool get isCompact => this == FormFactor.compact;
  bool get isTabletWidth => this == FormFactor.expanded;

  /// 본문을 몇 단으로 놓을지.
  int get columns => switch (this) {
        FormFactor.compact => 1,
        FormFactor.medium => 2,
        FormFactor.expanded => 2,
      };
}

/// 폭 기준.
///
/// Material 의 창 크기 등급을 따른다. 임의의 값을 쓰면 기기마다 어중간한 배치가 나온다.
abstract final class Breakpoints {
  /// 이 폭 아래는 핸드폰 세로로 본다.
  static const double medium = 600;

  /// 이 폭 이상은 태블릿 가로로 본다.
  static const double expanded = 900;

  /// 본문 최대 폭. 태블릿에서 글줄이 지나치게 길어지지 않게 한다.
  static const double maxContentWidth = 1200;

  static FormFactor of(double width) {
    if (width >= expanded) return FormFactor.expanded;
    if (width >= medium) return FormFactor.medium;
    return FormFactor.compact;
  }
}

/// 현재 형태를 읽는다.
extension FormFactorContext on BuildContext {
  FormFactor get formFactor =>
      Breakpoints.of(MediaQuery.sizeOf(this).width);
}
