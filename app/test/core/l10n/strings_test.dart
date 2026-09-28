import 'package:flutter_test/flutter_test.dart';
import 'package:today_meal/core/l10n/strings.dart';

/// 문구 보간.
///
/// 실기기에서 `$n가지` 가 그대로 화면에 나왔다. 이스케이프가 소스에 남아 보간이 되지
/// 않은 것이다. 눈으로만 보면 놓치므로 테스트로 고정한다.
void main() {
  test('숫자가 실제 값으로 들어간다', () {
    expect(Strings.bandCount(3), '3가지');
    expect(Strings.menuServings(2), '2인분');
    expect(Strings.menuMinutes(15), '약 15분');
    expect(Strings.itemCount(8), '재료 8종');
    expect(Strings.openedDaysAgo(2), '개봉 2일');
  });

  test('남은 날은 부호로 표현을 가른다', () {
    expect(Strings.daysLeft(3), 'D-3');
    expect(Strings.daysLeft(0), 'D-0');
    expect(Strings.daysLeft(-2), '2일 지남');
  });

  test('보간 기호가 문구에 남아 있지 않다', () {
    for (final text in [
      Strings.bandCount(1),
      Strings.menuServings(1),
      Strings.menuMinutes(1),
      Strings.itemCount(1),
      Strings.openedDaysAgo(1),
      Strings.daysLeft(1),
      Strings.daysLeft(-1),
    ]) {
      expect(text.contains(r'$'), isFalse, reason: text);
    }
  });
}
