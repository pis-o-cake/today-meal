import 'package:flutter_test/flutter_test.dart';
import 'package:today_meal/core/voice/wake_phrase.dart';

/// 호출어 매칭.
///
/// 온디바이스 전사는 띄어쓰기와 받아쓰기가 흔들린다. 관대하게 잡되 아무 말에나 반응하지
/// 않아야 한다.
void main() {
  test('정확히 말하면 잡는다', () {
    expect(matchWakePhrase('헤이 냉장고'), '');
  });

  test('띄어쓰기가 붙어도 잡는다', () {
    expect(matchWakePhrase('헤이냉장고'), '');
  });

  test('흔한 오인식 표기도 잡는다', () {
    expect(matchWakePhrase('해이 냉장고'), isNotNull);
    expect(matchWakePhrase('하이냉장고'), isNotNull);
  });

  test('뒤에 이어진 말을 함께 돌려준다', () {
    // 한 번에 말하는 경우를 살린다. 버리면 사용자가 두 번 말해야 한다.
    expect(matchWakePhrase('헤이 냉장고, 계란 두 개 썼어'), '계란두개썼어');
  });

  test('앞에 군말이 있어도 잡는다', () {
    expect(matchWakePhrase('어 헤이 냉장고 계란 몇 개 있어'), '계란몇개있어');
  });

  test('없는 말에는 반응하지 않는다', () {
    expect(matchWakePhrase('오늘 날씨 좋네'), isNull);
    expect(matchWakePhrase('냉장고 문 닫아'), isNull);
    expect(matchWakePhrase(''), isNull);
  });

  test('호출어 일부만 나오면 잡지 않는다', () {
    expect(matchWakePhrase('헤이'), isNull);
    expect(matchWakePhrase('냉장고'), isNull);
  });
}
