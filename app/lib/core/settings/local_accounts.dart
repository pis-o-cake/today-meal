/// 기기에 저장하는 계정.
///
/// CAUTION: **서버 인증이 아니다.** `/api/auth/sign-in` 은 아직 구현되지 않았다
/// (`S-15`·`F-22`). 여기 저장한 계정은 이 기기 안에서만 유효하고 다른 기기와 공유되지
/// 않으며, 서버의 가구 데이터를 나누지도 않는다. 서버 세션이 붙으면 이 계층은 사라진다.
///
/// 비밀번호 원문은 저장하지 않는다. 계정마다 무작위 소금을 만들어 SHA-256 해시만 남긴다.
/// 로그에도 비밀번호나 해시를 남기지 않는다.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 로그인 시도의 결과.
enum SignInResult {
  ok,

  /// 이 기기에 그 이메일로 만든 계정이 없다.
  unknownEmail,

  /// 비밀번호가 다르다.
  wrongPassword,
}

/// 가입 시도의 결과.
enum SignUpResult { ok, emailTaken }

class LocalAccounts {
  LocalAccounts(this._store);

  static Future<LocalAccounts> open() async =>
      LocalAccounts(await SharedPreferences.getInstance());

  final SharedPreferences _store;
  final _random = Random.secure();

  /// 가입. 같은 이메일이 이미 있으면 덮어쓰지 않는다.
  Future<SignUpResult> signUp({
    required String nickname,
    required String email,
    required String password,
  }) async {
    final key = _key(email);
    if (_store.containsKey('$key.hash')) return SignUpResult.emailTaken;

    final salt = _salt();
    await _store.setString('$key.salt', salt);
    await _store.setString('$key.hash', _hash(password, salt));
    await _store.setString('$key.nickname', nickname);
    return SignUpResult.ok;
  }

  /// 로그인. 이메일이 없는 것과 비밀번호가 틀린 것을 **구분해 돌려준다.**
  ///
  /// IMPORTANT: 사용자에게 보여줄 때도 구분한다. 이 계정은 이 기기 안에만 있어
  /// 계정 존재 여부가 다른 사람에게 새어 나갈 곳이 없고, 구분하지 않으면 사용자가
  /// 무엇을 고쳐야 하는지 알 수 없다.
  SignInResult verify({required String email, required String password}) {
    final key = _key(email);
    final salt = _store.getString('$key.salt');
    final hash = _store.getString('$key.hash');
    if (salt == null || hash == null) return SignInResult.unknownEmail;
    return _hash(password, salt) == hash
        ? SignInResult.ok
        : SignInResult.wrongPassword;
  }

  /// 저장된 닉네임. 없으면 이메일의 앞부분을 쓴다.
  String nicknameOf(String email) {
    final saved = _store.getString('${_key(email)}.nickname');
    if (saved != null && saved.isNotEmpty) return saved;
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  /// 이메일은 대소문자를 구분하지 않는다. 키에 그대로 쓰지 않고 정규화한다.
  String _key(String email) => 'local.account.${email.trim().toLowerCase()}';

  String _salt() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes);
  }

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();
}

/// 이메일·비밀번호의 형식 검사.
///
/// 서버가 붙으면 서버도 같은 검사를 한다. 앱의 검사는 **입력을 돕는 것**이고 판정의
/// 정본이 아니다.
abstract final class Credentials {
  /// 목업이 표시하는 비밀번호 조건 — 영문·숫자·8자 이상.
  static const minLength = 8;

  static final _email = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$');

  static bool isEmail(String value) => _email.hasMatch(value.trim());

  static bool hasLetter(String value) => RegExp('[A-Za-z]').hasMatch(value);

  static bool hasDigit(String value) => RegExp('[0-9]').hasMatch(value);

  static bool isLongEnough(String value) => value.length >= minLength;

  static bool isStrongPassword(String value) =>
      hasLetter(value) && hasDigit(value) && isLongEnough(value);
}
