import 'package:flutter_test/flutter_test.dart';
import 'package:today_meal/core/design/breakpoints.dart';

/// 폭 기준이 태블릿 병행을 지탱하는지 확인한다.
///
/// 화면을 두 벌 만들지 않고 이 판정 하나로 배치를 가른다.
void main() {
  test('핸드폰 세로는 1단', () {
    expect(Breakpoints.of(390), FormFactor.compact);
    expect(Breakpoints.of(390).columns, 1);
  });

  test('핸드폰 가로와 작은 태블릿은 2단', () {
    expect(Breakpoints.of(700), FormFactor.medium);
    expect(Breakpoints.of(700).columns, 2);
  });

  test('태블릿 가로는 expanded', () {
    expect(Breakpoints.of(1280), FormFactor.expanded);
    expect(Breakpoints.of(1280).isTabletWidth, isTrue);
  });

  test('경계에서 등급이 뒤집히지 않는다', () {
    expect(Breakpoints.of(Breakpoints.medium - 1), FormFactor.compact);
    expect(Breakpoints.of(Breakpoints.medium), FormFactor.medium);
    expect(Breakpoints.of(Breakpoints.expanded - 1), FormFactor.medium);
    expect(Breakpoints.of(Breakpoints.expanded), FormFactor.expanded);
  });
}
