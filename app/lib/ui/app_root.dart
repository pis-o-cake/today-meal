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
/// 유효한 세션이나 이미 고른 게스트 상태가 있으면 로그인을 건너뛴다. 로그아웃하면 다시
/// 로그인으로 돌아간다.
///
/// 라우터를 두지 않고 상태 하나로 가른다. 화면 다섯이고 뒤로 가기가 가입에서만 의미를
/// 가지므로, 경로 표를 만들면 얻는 것보다 잃는 것이 많다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/settings/app_settings.dart';
import '../core/settings/local_accounts.dart';
import 'account/login_screen.dart';
import 'account/signup_screen.dart';
import 'permission/permission_screen.dart';
import 'shell.dart';
import 'splash/splash_screen.dart';

/// 지금 보여줄 화면.
enum _Step { splash, login, signUp, permission, home }

class AppRoot extends StatefulWidget {
  const AppRoot({required this.accounts, this.prepare, super.key});

  final LocalAccounts accounts;

  /// 첫 데이터 읽기. 스플래시 연출과 함께 돌린다.
  final Future<void> Function()? prepare;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  _Step _step = _Step.splash;

  AppSettings get _settings => context.read<AppSettings>();

  /// 스플래시가 끝났다. 저장된 상태에 따라 갈 곳을 정한다.
  void _afterSplash() => setState(() => _step = _next());

  _Step _next() {
    if (!_settings.hasChosenEntry) return _Step.login;
    if (!_settings.onboarded) return _Step.permission;
    return _Step.home;
  }

  Future<void> _enter(Account account) async {
    await _settings.signIn(account);
    if (!mounted) return;
    setState(() => _step = _settings.onboarded ? _Step.home : _Step.permission);
  }

  Future<void> _finishOnboarding() async {
    await _settings.markOnboarded();
    if (!mounted) return;
    setState(() => _step = _Step.home);
  }

  Future<void> _signOut() async {
    await _settings.signOut();
    if (!mounted) return;
    setState(() => _step = _Step.login);
  }

  @override
  Widget build(BuildContext context) => switch (_step) {
        _Step.splash => SplashScreen(
            prepare: widget.prepare,
            onReady: _afterSplash,
          ),
        _Step.login => LoginScreen(
            accounts: widget.accounts,
            onSignedIn: _enter,
            onGuest: () => _enter(const Account.guest()),
            onSignUp: () => setState(() => _step = _Step.signUp),
          ),
        _Step.signUp => SignUpScreen(
            accounts: widget.accounts,
            onSignedUp: _enter,
            onBack: () => setState(() => _step = _Step.login),
          ),
        _Step.permission => PermissionScreen(onDone: _finishOnboarding),
        _Step.home => AppShell(
            onSignIn: () => setState(() => _step = _Step.login),
            onSignOut: _signOut,
          ),
      };
}
