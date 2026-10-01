import 'package:flutter_test/flutter_test.dart';
import 'package:today_meal/core/voice/wake_phrase.dart';

/// 호출어 매칭.
///
/// 전사는 띄어쓰기와 받아쓰기가 흔들린다. 관대하게 잡되 아무 말에나 반응하지 않아야 한다.
void main() {
  test('기본 문구는 화면 표시 문구와 같다', () {
    // 화면이 "헤이 키친" 이라 적고 다른 말로 깨어나면 사용자에게는 고장이다.
    expect(defaultWakePhrase, '헤이 키친');
  });

  test('정확히 말하면 잡는다', () {
    expect(matchWakePhrase('헤이 키친'), '');
  });

  test('띄어쓰기가 끼어도 잡는다', () {
    expect(matchWakePhrase('헤이키친'), '');
    expect(matchWakePhrase('헤 이 키 친'), '');
  });

  test('흔한 오인식 표기도 잡는다', () {
    expect(matchWakePhrase('해이 키친'), isNotNull);
    expect(matchWakePhrase('헤이 키치'), isNotNull);
    expect(matchWakePhrase('Hey Kitchen'), isNotNull);
  });

  test('실기기에서 받아써진 표기를 잡는다', () {
    // SM-E426S 에서 "헤이 키친" 을 불렀을 때 실제로 나온 전사다.
    expect(matchWakePhrase('베이키친'), '');
    expect(matchWakePhrase(' 에이키친'), '');
    expect(matchWakePhrase('hat kitchen'), '');
  });

  test('소리가 비슷하면 표기가 달라도 잡는다', () {
    expect(matchWakePhrase('헤이 치킨'), isNotNull);
    expect(matchWakePhrase('헤이 키칭'), isNotNull);
    expect(matchWakePhrase('해이 킷친'), isNotNull);
    expect(matchWakePhrase('페이 기친'), isNotNull);
    expect(matchWakePhrase('햇 키친'), isNotNull);
    expect(matchWakePhrase('hey 키친'), isNotNull);
    expect(matchWakePhrase('헤이 kitchen 계란 있어'), '계란있어');
  });

  test('문장 가운데에서는 앞말이 헤이처럼 들려야 잡는다', () {
    expect(matchWakePhrase('음 그러니까 헤이 키친'), '');
    expect(matchWakePhrase('오늘 저녁은 치킨 먹자'), isNull);
    expect(matchWakePhrase('우리집 키친 예쁘다'), isNull);
  });

  test('키친타월은 호출이 아니다', () {
    expect(matchWakePhrase('키친타월 샀어'), isNull);
    expect(matchWakePhrase('오늘 키친타월 샀어'), isNull);
  });

  test('이전 호출어도 계속 받는다', () {
    // 익숙해진 사용자를 끊지 않는다.
    expect(matchWakePhrase('자비스'), isNotNull);
    expect(matchWakePhrase('재비스'), isNotNull);
    expect(matchWakePhrase('헤이 냉장고'), isNotNull);
  });

  test('뒤에 이어진 말을 함께 돌려준다', () {
    // 한 번에 말하는 경우를 살린다. 버리면 사용자가 두 번 말해야 한다.
    expect(matchWakePhrase('헤이 키친, 계란 두 개 썼어'), '계란두개썼어');
  });

  test('앞에 군말이 있어도 잡는다', () {
    expect(matchWakePhrase('어 헤이 키친 계란 몇 개 있어'), '계란몇개있어');
  });

  test('없는 말에는 반응하지 않는다', () {
    expect(matchWakePhrase('오늘 날씨 좋네'), isNull);
    expect(matchWakePhrase('냉장고 문 닫아'), isNull);
    expect(matchWakePhrase(''), isNull);
  });

  test('호출어 일부만 나오면 잡지 않는다', () {
    expect(matchWakePhrase('헤이'), isNull);
    expect(matchWakePhrase('키친'), isNull);
    expect(matchWakePhrase('치킨 먹었어'), isNull);
    expect(matchWakePhrase('냉장고'), isNull);
  });
}
