/// 로그인 (UI-09).
///
/// 목업 `Login.dc.html` 이다 — 이메일·비밀번호, 간편 로그인, 로그인 없이 둘러보기.
///
/// 서버가 이메일과 비밀번호를 확인한다. 성공하면 세션 토큰을 받아 이후 모든 호출이
/// 그 계정의 가구를 본다.
///
/// 카카오·Google·Apple 은 연동 전이다. 버튼을 감추지 않고 **왜 안 되는지** 말한다 —
/// 목업의 `href` 를 따라 성공으로 넘기면 인증한 것처럼 보인다.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/local_accounts.dart';
import '../../domain/repository/repositories.dart';
import '../widgets/glass.dart';
import '../widgets/mascot.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.auth,
    required this.onSignedIn,
    required this.onGuest,
    required this.onSignUp,
    super.key,
  });

  final AuthRepository auth;

  /// 서버가 확인한 계정으로 로그인했다. 토큰은 호출자가 저장한다.
  final void Function(Account account, String token) onSignedIn;

  /// 로그인 없이 둘러본다.
  final VoidCallback onGuest;

  /// 가입 화면으로.
  final VoidCallback onSignUp;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _shown = false;
  bool _busy = false;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final password = _password.text;

    setState(() {
      _emailError = Credentials.isEmail(email) ? null : Strings.signUpErrorEmail;
      _passwordError = password.isEmpty ? Strings.loginPasswordEmpty : null;
    });
    if (_emailError != null || _passwordError != null) return;

    setState(() => _busy = true);
    final result = await widget.auth.signIn(email: email, password: password);
    if (!mounted) return;
    setState(() => _busy = false);

    // 입력은 화면에 남긴다. 실패했을 때 처음부터 다시 치게 하지 않는다.
    if (result.ok) {
      final account = result.account!;
      widget.onSignedIn(
        Account(
          nickname: account.nickname ?? '',
          email: account.email ?? email,
          provider: AccountProvider.parse(account.provider),
        ),
        result.token!,
      );
      return;
    }

    setState(() {
      // 서버는 이메일이 없는 것과 비밀번호가 틀린 것을 구분해 주지 않는다. 구분해
      // 보여주면 가입된 이메일인지 알 수 있게 되므로 앱도 구분하지 않는다.
      _passwordError = switch (result.failure!) {
        AuthFailure.wrongCredentials => Strings.loginWrongCredentials,
        AuthFailure.invalidInput => Strings.signUpErrorPassword,
        AuthFailure.unreachable => Strings.serverFailed,
        AuthFailure.emailTaken => Strings.signUpErrorTaken,
      };
    });
  }

  /// 연동하지 않은 제공자. 성공으로 넘기지 않고 사실을 알린다.
  void _pending() {
    final skin = context.skin;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          '${Strings.loginProviderPending}\n${Strings.loginProviderPendingHint}',
        ),
        backgroundColor: skin.strong,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final isIos = !kIsWeb && Platform.isIOS;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: skin.background(skin.hello)),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              children: [
                _Brand(skin: skin),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassField(
                        label: Strings.loginEmail,
                        controller: _email,
                        hint: Strings.loginEmailHint,
                        error: _emailError,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        onChanged: (_) => setState(() => _emailError = null),
                      ),
                      const SizedBox(height: 12),
                      GlassField(
                        label: Strings.loginPassword,
                        controller: _password,
                        hint: Strings.loginPasswordHint,
                        error: _passwordError,
                        obscure: !_shown,
                        autofillHints: const [AutofillHints.password],
                        onChanged: (_) => setState(() => _passwordError = null),
                        onSubmitted: (_) => _submit(),
                        trailing: _EyeButton(
                          shown: _shown,
                          onToggle: () => setState(() => _shown = !_shown),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _Primary(
                        label: Strings.loginSubmit,
                        skin: skin,
                        busy: _busy,
                        onPressed: _busy ? null : _submit,
                      ),
                      const SizedBox(height: 4),
                      _Links(
                          skin: skin,
                          onForgot: _pending,
                          onSignUp: widget.onSignUp),
                      const SizedBox(height: 2),
                      const SizedBox(height: 14),
                      _Divider(skin: skin),
                      const SizedBox(height: 14),
                      _Social(skin: skin, isIos: isIos, onPressed: _pending),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: Tokens.tap,
                        child: TextButton(
                          onPressed: widget.onGuest,
                          child: Text(
                            Strings.loginGuest,
                            style: text.bodyMedium?.copyWith(
                              color: skin.inkMuted,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(
        children: [
          const Mascot(mood: MascotMood.hello, size: 104),
          const SizedBox(height: 6),
          Text(Strings.appName, style: text.headlineMedium),
          const SizedBox(height: 4),
          Text(
            Strings.appTagline,
            style: text.bodyLarge
                ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// 비밀번호 보기·숨기기.
class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.shown, required this.onToggle});

  final bool shown;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: Tokens.tap,
        height: Tokens.tap,
        child: IconButton(
          onPressed: onToggle,
          iconSize: 22,
          color: context.skin.inkFaint,
          tooltip: shown ? Strings.loginHidePassword : Strings.loginShowPassword,
          icon: Icon(
              shown ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        ),
      );
}

/// 계정 화면의 주 행동 버튼.
class _Primary extends StatelessWidget {
  const _Primary({
    required this.label,
    required this.skin,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final Skin skin;

  /// `null` 이면 조건이 덜 찼거나 보내는 중이다. 색을 빼서 그것을 보여준다.
  final VoidCallback? onPressed;

  /// 서버 응답을 기다리는 중. 두 번 눌러 두 번 가입·로그인하지 않게 막는다.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusField));
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: on ? skin.primary : skin.toggleOff,
          shape: shape,
          shadows: on ? [skin.shade(0.13, 22, 10)] : null,
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: shape,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: skin.onPrimary),
                  )
                : Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 16, color: on ? skin.onPrimary : skin.inkDim),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Links extends StatelessWidget {
  const _Links({
    required this.skin,
    required this.onForgot,
    required this.onSignUp,
  });

  final Skin skin;
  final VoidCallback onForgot;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton(
          onPressed: onForgot,
          child: Text(Strings.loginForgot,
              style: text.bodyMedium
                  ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w600)),
        ),
        Container(width: 1, height: 12, color: skin.divider),
        TextButton(
          onPressed: onSignUp,
          child: Text(Strings.loginSignUp,
              style: text.bodyMedium
                  ?.copyWith(color: skin.primary, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Container(height: 1, color: skin.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              Strings.loginSocialDivider,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: skin.inkDim, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Container(height: 1, color: skin.divider)),
        ],
      );
}

/// 간편 로그인.
///
/// 목업의 공식 자산(카카오·Google 로고)은 저장소의 `docs/assets/` 에 있으나 아직 앱에
/// 번들하지 않았다. 지금은 브랜드 색과 글자만 쓰고, 연동할 때 자산을 함께 넣는다.
class _Social extends StatelessWidget {
  const _Social({
    required this.skin,
    required this.isIos,
    required this.onPressed,
  });

  final Skin skin;

  /// Apple 은 iOS 에만 표시한다.
  final bool isIos;
  final VoidCallback onPressed;

  /// 카카오 브랜드 색. 테마를 타지 않는다 — 제공자의 자산 규정이다.
  static const _kakao = Color(0xFFFEE500);
  static const _kakaoInk = Color(0xD9000000);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _button(context, Strings.loginKakao, _kakao, _kakaoInk, null),
          const SizedBox(height: 8),
          _button(context, Strings.loginGoogle, skin.raised, skin.ink,
              BorderSide(color: skin.edge)),
          if (isIos) ...[
            const SizedBox(height: 8),
            _button(context, Strings.loginApple, Colors.black, Colors.white, null),
          ],
        ],
      );

  Widget _button(BuildContext context, String label, Color background,
      Color ink, BorderSide? border) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Tokens.radiusField),
      side: border ?? BorderSide.none,
    );
    return SizedBox(
      height: 52,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: background, shape: shape),
        child: InkWell(
          onTap: onPressed,
          customBorder: shape,
          child: Center(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(fontSize: 15, color: ink, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
