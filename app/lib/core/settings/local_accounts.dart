/// 이메일·비밀번호의 형식 검사.
///
/// 입력을 **돕기 위한** 검사다. 판정의 정본은 서버이며 같은 규칙을 서버도 갖고 있다
/// (`server/app/domain/auth/schemas.py`). 앱 검사를 통과해도 서버가 거절할 수 있고,
/// 그때는 서버가 준 이유를 그대로 보여준다.
library;

abstract final class Credentials {
  /// 목업이 표시하는 비밀번호 조건 — 영문·숫자·8자 이상. 서버와 같은 값이다.
  static const minLength = 8;

  static final _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static bool isEmail(String value) => _email.hasMatch(value.trim());

  static bool hasLetter(String value) => RegExp('[A-Za-z]').hasMatch(value);

  static bool hasDigit(String value) => RegExp('[0-9]').hasMatch(value);

  static bool isLongEnough(String value) => value.length >= minLength;

  static bool isStrongPassword(String value) =>
      hasLetter(value) && hasDigit(value) && isLongEnough(value);
}
