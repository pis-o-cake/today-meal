/// 기기에 남기는 설정과 계정.
///
/// 화면 테마·음성 응답·기본 인분·로그인 상태를 담는다. 앱을 다시 켰을 때 고른 것이
/// 그대로 있어야 하므로 메모리에만 두지 않는다.
///
/// CAUTION: **서버 인증이 아니다.** `/api/auth/sign-in` 은 아직 구현되지 않았고
/// (`S-15`·`F-22`), 여기 저장하는 계정은 이 기기 안에서만 유효하다. 비밀번호는
/// 저장하지 않으며 다른 기기와 공유되지 않는다. 서버 세션이 붙으면 이 계층이
/// 그 캐시로 바뀐다.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/skin.dart';

/// 로그인한 사람.
@immutable
class Account {
  const Account({
    required this.nickname,
    required this.email,
    required this.provider,
  });

  /// 게스트. 로그인하지 않고 둘러보는 상태다.
  const Account.guest()
      : nickname = '',
        email = '',
        provider = AccountProvider.guest;

  final String nickname;
  final String email;
  final AccountProvider provider;

  bool get isGuest => provider == AccountProvider.guest;
}

/// 계정을 만든 경로.
///
/// 소셜 제공자는 아직 연동하지 않았다. 목록에 두는 것은 마이페이지가 **실제 경로**를
/// 표시해야 하기 때문이며, 연동 전에 이 값을 쓰지 않는다.
enum AccountProvider { guest, email, kakao, google, apple }

/// 기기에 남는 설정.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._store);

  /// 저장소를 열고 저장된 값을 읽는다.
  static Future<AppSettings> load() async {
    final store = await SharedPreferences.getInstance();
    return AppSettings._(store).._read();
  }

  /// 저장소 없이 쓰는 설정. 위젯 테스트와 첫 실행 실패 경로에서 쓴다.
  AppSettings.memory() : _store = null;

  final SharedPreferences? _store;

  SkinName _skin = SkinName.pastel;
  bool _spokenReply = true;
  bool _expiryAlert = true;
  int _defaultServings = 2;
  bool _onboarded = false;
  Account? _account;

  /// 고른 화면 테마.
  SkinName get skin => _skin;

  /// 응답을 소리로 읽어줄지. **마이크 음소거와 다른 설정이다.**
  bool get spokenReply => _spokenReply;

  /// 기한이 다가온 재료를 앱에서 눈에 띄게 표시할지.
  ///
  /// IMPORTANT: OS 푸시가 아니다. 앱 안의 표시만 켜고 끈다.
  bool get expiryAlert => _expiryAlert;

  /// 추천의 기본 인분.
  int get defaultServings => _defaultServings;

  /// 권한 안내를 이미 봤는지. 두 번째 실행부터 건너뛴다.
  bool get onboarded => _onboarded;

  /// 로그인한 사람. 아직 고르지 않았으면 `null` 이다.
  ///
  /// `null` 과 게스트는 다르다 — 고르지 않은 것은 로그인 화면으로 보내고, 게스트를
  /// 고른 것은 홈으로 보낸다.
  Account? get account => _account;

  bool get hasChosenEntry => _account != null;

  void _read() {
    final store = _store;
    if (store == null) return;
    _skin = SkinName.values.firstWhere(
      (value) => value.name == store.getString(_keySkin),
      orElse: () => SkinName.pastel,
    );
    _spokenReply = store.getBool(_keySpokenReply) ?? true;
    _expiryAlert = store.getBool(_keyExpiryAlert) ?? true;
    _defaultServings = store.getInt(_keyServings) ?? 2;
    _onboarded = store.getBool(_keyOnboarded) ?? false;

    final provider = store.getString(_keyProvider);
    if (provider == null) return;
    _account = Account(
      nickname: store.getString(_keyNickname) ?? '',
      email: store.getString(_keyEmail) ?? '',
      provider: AccountProvider.values.firstWhere(
        (value) => value.name == provider,
        orElse: () => AccountProvider.guest,
      ),
    );
  }

  Future<void> chooseSkin(SkinName next) async {
    if (_skin == next) return;
    _skin = next;
    notifyListeners();
    await _store?.setString(_keySkin, next.name);
  }

  Future<void> setSpokenReply(bool on) async {
    if (_spokenReply == on) return;
    _spokenReply = on;
    notifyListeners();
    await _store?.setBool(_keySpokenReply, on);
  }

  Future<void> setExpiryAlert(bool on) async {
    if (_expiryAlert == on) return;
    _expiryAlert = on;
    notifyListeners();
    await _store?.setBool(_keyExpiryAlert, on);
  }

  Future<void> setDefaultServings(int value) async {
    final next = value.clamp(1, 8);
    if (_defaultServings == next) return;
    _defaultServings = next;
    notifyListeners();
    await _store?.setInt(_keyServings, next);
  }

  Future<void> markOnboarded() async {
    if (_onboarded) return;
    _onboarded = true;
    notifyListeners();
    await _store?.setBool(_keyOnboarded, true);
  }

  /// 계정을 기기에 남긴다. 비밀번호는 받지 않는다.
  Future<void> signIn(Account next) async {
    _account = next;
    notifyListeners();
    final store = _store;
    if (store == null) return;
    await store.setString(_keyProvider, next.provider.name);
    await store.setString(_keyNickname, next.nickname);
    await store.setString(_keyEmail, next.email);
  }

  /// 세션을 끝내고 계정 화면의 값을 지운다.
  ///
  /// 다른 계정의 흔적을 남기지 않는다. 재고는 서버가 가구로 갖고 있으므로 여기서
  /// 지우는 것은 이 기기의 계정 정보뿐이다.
  Future<void> signOut() async {
    _account = null;
    notifyListeners();
    final store = _store;
    if (store == null) return;
    await store.remove(_keyProvider);
    await store.remove(_keyNickname);
    await store.remove(_keyEmail);
  }

  static const _keySkin = 'skin';
  static const _keySpokenReply = 'voice.spokenReply';
  static const _keyExpiryAlert = 'alert.expiry';
  static const _keyServings = 'meal.servings';
  static const _keyOnboarded = 'onboarded';
  static const _keyProvider = 'account.provider';
  static const _keyNickname = 'account.nickname';
  static const _keyEmail = 'account.email';
}
