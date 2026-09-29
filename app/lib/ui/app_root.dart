/// 첫 진입 흐름.
///
/// 목업 인계가 정한 순서다.
///
/// ```
/// 스플래시 → (계정을 고른 적 없음) 로그인 → 가입
///                              ↘ 둘러보기
///          → (권한 안내 전) 권한 → 홈
///          → 홈
/// ```
///
/// 저장해 둔 세션 토큰이 있으면 스플래시에서 **서버에 확인**하고 들어간다. 만료·폐기된
/// 토큰으로 그냥 들어가면 사용자는 자기 냉장고를 보고 있다고 믿으면서 기본 가구를 본다.
///
/// 라우터를 두지 않고 상태 하나로 가른다. 화면 다섯이고 뒤로 가기가 가입에서만 의미를
/// 가지므로, 경로 표를 만들면 얻는 것보다 잃는 것이 많다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings/app_settings.dart';
import '../domain/repository/repositories.dart';
import 'account/login_screen.dart';
import 'account/signup_screen.dart';
import 'permission/permission_screen.dart';
import 'shell.dart';
import 'splash/splash_screen.dart';

/// 지금 보여줄 화면.
enum _Step { splash, login, signUp, permission, home }

class AppRoot extends StatefulWidget {
  const AppRoot({required this.auth, this.prepare, super.key});

  final AuthRepository auth;

  /// 첫 데이터 읽기. 스플래시 연출과 함께 돌린다.
  final Future<void> Function()? prepare;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  _Step _step = _Step.splash;

  AppSettings get _settings => context.read<AppSettings>();

  /// 저장해 둔 토큰을 확인하고 데이터를 읽는다.
  ///
  /// 토큰 확인을 데이터 읽기보다 **먼저** 한다. 순서가 바뀌면 남의 가구 데이터를 읽어
  /// 화면에 잠깐 보여주게 된다.
  Future<void> _prepare() async {
    final token = _settings.token;
    if (token != null) {
      final account = await widget.auth.restore(token);
      if (account == null) {
        // 서버가 거절했다. 조용히 게스트로 두지 않고 로그인을 다시 요구한다.
        await _settings.sessionExpired();
      } else {
        await _settings.signIn(
          Account(
            nickname: account.nickname ?? '',
            email: account.email ?? '',
            provider: AccountProvider.parse(account.provider),
          ),
          token: token,
        );
      }
    }
    await widget.prepare?.call();
  }

  /// 스플래시가 끝났다. 저장된 상태에 따라 갈 곳을 정한다.
  void _afterSplash() => setState(() => _step = _next());

  _Step _next() {
    if (!_settings.hasChosenEntry) return _Step.login;
    if (!_settings.onboarded) return _Step.permission;
    return _Step.home;
  }

  Future<void> _enter(Account account, {String? token}) async {
    await _settings.signIn(account, token: token);
    if (!mounted) return;
    setState(() => _step = _settings.onboarded ? _Step.home : _Step.permission);
  }

  Future<void> _finishOnboarding() async {
    await _settings.markOnboarded();
    if (!mounted) return;
    setState(() => _step = _Step.home);
  }

  Future<void> _signOut() async {
    // 서버 세션을 먼저 끝낸다. 기기만 지우면 토큰이 만료까지 살아 있다.
    await widget.auth.signOut();
    await _settings.signOut();
    if (!mounted) return;
    setState(() => _step = _Step.login);
  }

  @override
  Widget build(BuildContext context) => switch (_step) {
        _Step.splash => SplashScreen(
            prepare: _prepare,
            onReady: _afterSplash,
          ),
        _Step.login => LoginScreen(
            auth: widget.auth,
            onSignedIn: (account, token) => _enter(account, token: token),
            onGuest: () => _enter(const Account.guest()),
            onSignUp: () => setState(() => _step = _Step.signUp),
          ),
        _Step.signUp => SignUpScreen(
            auth: widget.auth,
            onSignedUp: (account, token) => _enter(account, token: token),
            onBack: () => setState(() => _step = _Step.login),
          ),
        _Step.permission => PermissionScreen(onDone: _finishOnboarding),
        _Step.home => AppShell(
            onSignIn: () => setState(() => _step = _Step.login),
            onSignOut: _signOut,
          ),
      };
}
