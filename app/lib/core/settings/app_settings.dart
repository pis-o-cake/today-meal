/// 기기에 남기는 설정과 세션.
///
/// 화면 테마·음성 응답·기본 인분과 **서버 세션 토큰**을 담는다. 앱을 다시 켰을 때
/// 고른 것이 그대로 있고 로그인이 풀리지 않아야 하므로 메모리에만 두지 않는다.
///
/// 계정 정보는 서버가 정본이다. 여기 있는 것은 화면에 바로 쓰기 위한 사본이며,
/// 앱을 열 때마다 `/api/auth/me` 로 토큰이 아직 유효한지 확인한다.
///
/// CAUTION: 비밀번호는 저장하지 않는다. 토큰은 저장하되 **로그에 남기지 않는다** —
/// 이 값 하나로 계정에 들어갈 수 있다.
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
enum AccountProvider {
  guest,
  email,
  kakao,
  google,
  apple;

  /// 서버가 준 `provider` 문자열을 옮긴다. 모르는 값은 게스트로 낮춘다.
  static AccountProvider parse(String? raw) => AccountProvider.values.firstWhere(
        (value) => value.name == raw,
        orElse: () => AccountProvider.guest,
      );
}

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

  SkinName _skin = SkinName.glass;
  bool _spokenReply = true;
  bool _expiryAlert = false;
  int _defaultServings = 2;
  bool _onboarded = false;
  Account? _account;
  String? _token;

  /// 고른 화면 테마.
  SkinName get skin => _skin;

  /// 응답을 소리로 읽어줄지. **마이크 음소거와 다른 설정이다.**
  bool get spokenReply => _spokenReply;

  /// 기한이 다가온 재료를 앱에서 눈에 띄게 표시할지.
  ///
  /// IMPORTANT: OS 푸시가 아니다. 앱 안의 표시만 켜고 끈다.
  ///
  /// 신규 사용자는 **꺼짐**이다 — 가입 화면의 기한 알림 동의가 선택 항목이고 기본 해제이므로,
  /// 켜 둔 채로 시작하면 동의하지 않은 표시를 보여주게 된다.
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

  /// 저장해 둔 서버 세션 토큰. 게스트면 `null` 이다.
  ///
  /// CAUTION: 로그에 남기지 않는다.
  String? get token => _token;

  void _read() {
    final store = _store;
    if (store == null) return;
    _skin = SkinName.values.firstWhere(
      (value) => value.name == store.getString(_keySkin),
      orElse: () => SkinName.glass,
    );
    _spokenReply = store.getBool(_keySpokenReply) ?? true;
    _expiryAlert = store.getBool(_keyExpiryAlert) ?? false;
    _defaultServings = store.getInt(_keyServings) ?? 2;
    _onboarded = store.getBool(_keyOnboarded) ?? false;

    _token = store.getString(_keyToken);

    final provider = store.getString(_keyProvider);
    if (provider == null) return;
    _account = Account(
      nickname: store.getString(_keyNickname) ?? '',
      email: store.getString(_keyEmail) ?? '',
      provider: AccountProvider.parse(provider),
    );
  }

  Future<void> chooseSkin(SkinName next) async {
    if (_skin == next) return;
    final before = _skin;
    _skin = next;
    notifyListeners();
    await _save(() => _store?.setString(_keySkin, next.name), () => _skin = before);
  }

  Future<void> setSpokenReply(bool on) async {
    if (_spokenReply == on) return;
    final before = _spokenReply;
    _spokenReply = on;
    notifyListeners();
    await _save(
      () => _store?.setBool(_keySpokenReply, on),
      () => _spokenReply = before,
    );
  }

  Future<void> setExpiryAlert(bool on) async {
    if (_expiryAlert == on) return;
    final before = _expiryAlert;
    _expiryAlert = on;
    notifyListeners();
    await _save(
      () => _store?.setBool(_keyExpiryAlert, on),
      () => _expiryAlert = before,
    );
  }

  Future<void> setDefaultServings(int value) async {
    final next = value.clamp(1, 8);
    if (_defaultServings == next) return;
    final before = _defaultServings;
    _defaultServings = next;
    notifyListeners();
    await _save(
      () => _store?.setInt(_keyServings, next),
      () => _defaultServings = before,
    );
  }

  /// 설정 하나를 저장한다. **실패하면 이전 값으로 되돌린다.**
  ///
  /// IMPORTANT: 화면은 이미 새 값을 그렸다. 저장이 실패했는데 그대로 두면 다음 실행에서
  /// 슬그머니 옛 값으로 돌아가고, 사용자는 자기가 바꾼 것이 왜 사라졌는지 알 수 없다.
  ///
  /// Returns: 저장에 성공했는지. 화면이 실패를 알릴 수 있다.
  Future<bool> _save(
    Future<bool?>? Function() write,
    void Function() rollback,
  ) async {
    try {
      await write();
      return true;
    } catch (error) {
      rollback();
      notifyListeners();
      debugPrint('settings save failed: $error');
      return false;
    }
  }

  Future<void> markOnboarded() async {
    if (_onboarded) return;
    _onboarded = true;
    notifyListeners();
    await _store?.setBool(_keyOnboarded, true);
  }

  /// 세션을 기기에 남긴다.
  ///
  /// [token] 이 `null` 이면 게스트다 — 게스트도 "고른 상태"이므로 계정을 저장한다.
  /// 비밀번호는 받지도 저장하지도 않는다.
  Future<void> signIn(Account next, {String? token}) async {
    _account = next;
    _token = token;
    notifyListeners();
    final store = _store;
    if (store == null) return;
    await store.setString(_keyProvider, next.provider.name);
    await store.setString(_keyNickname, next.nickname);
    await store.setString(_keyEmail, next.email);
    if (token == null) {
      await store.remove(_keyToken);
    } else {
      await store.setString(_keyToken, token);
    }
  }

  /// 토큰이 더는 유효하지 않다. 계정을 지우고 게스트로 떨어뜨린다.
  ///
  /// 로그아웃과 다르다 — 사용자가 끝낸 것이 아니라 서버가 거절한 것이다. 화면은 이때
  /// 로그인을 다시 요구한다.
  Future<void> sessionExpired() => signOut();

  /// 세션을 끝내고 계정 화면의 값을 지운다.
  ///
  /// 다른 계정의 흔적을 남기지 않는다. 재고는 서버가 가구로 갖고 있으므로 여기서
  /// 지우는 것은 이 기기의 계정 정보뿐이다.
  Future<void> signOut() async {
    _account = null;
    _token = null;
    notifyListeners();
    final store = _store;
    if (store == null) return;
    await store.remove(_keyProvider);
    await store.remove(_keyNickname);
    await store.remove(_keyEmail);
    await store.remove(_keyToken);
  }

  static const _keySkin = 'skin';
  static const _keySpokenReply = 'voice.spokenReply';
  static const _keyExpiryAlert = 'alert.expiry';
  static const _keyServings = 'meal.servings';
  static const _keyOnboarded = 'onboarded';
  static const _keyProvider = 'account.provider';
  static const _keyNickname = 'account.nickname';
  static const _keyEmail = 'account.email';
  static const _keyToken = 'account.token';
}
