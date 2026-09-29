/// 회원가입 (UI-10).
///
/// 목업 `SignUp.dc.html` 이다 — 닉네임·이메일·비밀번호·확인과 약관 동의.
///
/// 목업의 가입 버튼은 **동의만** 검사한다. UI 계약대로 입력 검증을 보완해, 형식이 맞고
/// 필수 동의가 끝났을 때만 버튼이 켜진다. 선택 동의 없이도 가입할 수 있다.
///
/// 서버가 계정을 만들고 바로 로그인시킨다. **가입하면 자기 가구로 시작하므로 냉장고가
/// 비어 있다** — 게스트로 둘러보던 재고는 기본 가구의 것이며 옮겨오지 않는다.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/local_accounts.dart';
import '../../domain/repository/repositories.dart';
import '../widgets/glass.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({
    required this.auth,
    required this.onSignedUp,
    required this.onBack,
    super.key,
  });

  final AuthRepository auth;

  /// 서버가 만든 계정과 그 세션 토큰.
  final void Function(Account account, String token) onSignedUp;
  final VoidCallback onBack;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _nickname = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _shown = false;
  bool _busy = false;
  String? _emailError;
  String? _confirmError;

  /// 서버에 물어본 이메일 사용 가능 여부. 아직 묻지 않았으면 `null` 이다.
  EmailAvailability? _emailState;

  /// 지금 확인 중인 이메일. 늦게 온 응답이 최신 입력을 덮지 않게 한다.
  String? _checking;

  /// 타이핑이 멈추기를 기다리는 타이머. 글자마다 부르면 서버를 두드린다.
  Timer? _debounce;

  /// 타이핑이 멈췄다고 보는 시간.
  static const _settleDelay = Duration(milliseconds: 500);

  /// 손댄 적 있는 칸. 건드리지 않은 칸에 먼저 빨간 글씨를 띄우지 않는다.
  final _touched = <String>{};

  /// 약관 동의. 신규 사용자는 **모두 꺼진 상태**로 시작한다.
  final _agreed = <_Term, bool>{for (final term in _Term.values) term: false};

  @override
  void initState() {
    super.initState();
    for (final field in [_nickname, _email, _password, _confirm]) {
      field.addListener(_revalidate);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final field in [_nickname, _email, _password, _confirm]) {
      field.dispose();
    }
    super.dispose();
  }

  /// 타이핑이 멈추면 이메일을 한 번 확인한다.
  ///
  /// 글자마다 부르지 않는다 — 서버를 두드릴 뿐 아니라, 아직 다 치지 않은 주소에
  /// "쓸 수 없어요" 를 띄우게 된다.
  void _scheduleEmailCheck() {
    _debounce?.cancel();
    final email = _email.text.trim();
    setState(() {
      _emailState = null;
      _checking = null;
    });
    if (!Credentials.isEmail(email)) return;
    _debounce = Timer(_settleDelay, () => _checkEmail(email));
  }

  Future<void> _checkEmail(String email) async {
    setState(() => _checking = email);
    final result = await widget.auth.checkEmail(email);
    if (!mounted) return;
    // 그 사이에 더 쳤으면 이 응답은 버린다.
    if (_email.text.trim() != email) return;
    setState(() {
      _checking = null;
      _emailState = result;
    });
  }

  /// 이메일 칸에 보여줄 오류. 서버가 준 것이 앱 형식 검사보다 앞선다.
  String? get _emailMessage {
    if (_emailError != null) return _emailError;
    if (_emailState == EmailAvailability.taken) return Strings.signUpErrorTaken;
    return _errorFor('email', _email.text.trim(), Credentials.isEmail,
        Strings.signUpErrorEmail);
  }

  void _revalidate() => setState(() {
        _emailError = null;
        _confirmError = null;
      });

  /// 칸 하나의 오류. 비어 있거나 아직 손대지 않았으면 조용히 둔다.
  String? _errorFor(String key, String value, bool Function(String) valid,
      String message) {
    if (!_touched.contains(key) || value.isEmpty) return null;
    return valid(value) ? null : message;
  }

  void _touch(String key) => setState(() => _touched.add(key));

  bool get _requiredAgreed =>
      _Term.values.where((t) => t.required).every((t) => _agreed[t]!);

  bool get _allAgreed => _agreed.values.every((on) => on);

  bool get _inputsValid =>
      _nickname.text.trim().isNotEmpty &&
      Credentials.isEmail(_email.text) &&
      Credentials.isStrongPassword(_password.text) &&
      _confirm.text == _password.text &&
      // 이미 쓰는 이메일이면 눌러도 서버가 거절한다. 확인하지 못한 경우
      // (`unknown`)는 막지 않는다 — 판정은 가입 시점의 서버가 한다.
      _emailState != EmailAvailability.taken;

  bool get _canSubmit => _inputsValid && _requiredAgreed;

  Future<void> _submit() async {
    if (_busy) return;
    final email = _email.text.trim();
    final nickname = _nickname.text.trim();
    if (_confirm.text != _password.text) {
      setState(() => _confirmError = Strings.signUpErrorConfirm);
      return;
    }

    setState(() => _busy = true);
    final result = await widget.auth.signUp(
      nickname: nickname,
      email: email,
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _busy = false);

    if (result.ok) {
      final account = result.account!;
      widget.onSignedUp(
        Account(
          nickname: account.nickname ?? nickname,
          email: account.email ?? email,
          provider: AccountProvider.parse(account.provider),
        ),
        result.token!,
      );
      return;
    }

    setState(() {
      switch (result.failure!) {
        case AuthFailure.emailTaken:
          _emailError = Strings.signUpErrorTaken;
        case AuthFailure.invalidInput:
          _confirmError = Strings.signUpErrorPassword;
        // 이메일 가입에서는 나오지 않는 값들이다.
        case AuthFailure.wrongCredentials:
        case AuthFailure.cancelled:
        case AuthFailure.notConnected:
        case AuthFailure.unreachable:
          _confirmError = Strings.serverFailed;
      }
    });
  }

  void _toggleAll() {
    final next = !_allAgreed;
    setState(() {
      for (final term in _Term.values) {
        _agreed[term] = next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: skin.background(skin.hello, focusY: -0.8),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TitleBar(skin: skin, onBack: widget.onBack),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassField(
                        label: Strings.signUpNickname,
                        controller: _nickname,
                        hint: Strings.signUpNicknameHint,
                        autofillHints: const [AutofillHints.nickname],
                        error: _touched.contains('nickname') &&
                                _nickname.text.trim().isEmpty
                            ? Strings.signUpErrorNickname
                            : null,
                        onChanged: (_) => _touch('nickname'),
                      ),
                      const SizedBox(height: 14),
                      GlassField(
                        label: Strings.loginEmail,
                        controller: _email,
                        hint: Strings.loginEmailHint,
                        error: _emailMessage,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        onChanged: (_) {
                          _touch('email');
                          _scheduleEmailCheck();
                        },
                        trailing: _EmailMark(
                          checking: _checking != null,
                          state: _emailState,
                          skin: skin,
                        ),
                      ),
                      const SizedBox(height: 14),
                      GlassField(
                        label: Strings.loginPassword,
                        controller: _password,
                        hint: Strings.signUpPasswordHint,
                        obscure: !_shown,
                        autofillHints: const [AutofillHints.newPassword],
                        error: _errorFor(
                            'password',
                            _password.text,
                            Credentials.isStrongPassword,
                            Strings.signUpErrorPassword),
                        onChanged: (_) => _touch('password'),
                        trailing: SizedBox(
                          width: Tokens.tap,
                          height: Tokens.tap,
                          child: IconButton(
                            onPressed: () => setState(() => _shown = !_shown),
                            iconSize: 22,
                            color: skin.inkFaint,
                            tooltip: _shown
                                ? Strings.loginHidePassword
                                : Strings.loginShowPassword,
                            icon: Icon(_shown
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _Rules(password: _password.text, skin: skin),
                      const SizedBox(height: 14),
                      GlassField(
                        label: Strings.signUpConfirm,
                        controller: _confirm,
                        hint: Strings.signUpConfirmHint,
                        error: _confirmError ??
                            _errorFor('confirm', _confirm.text,
                                (v) => v == _password.text,
                                Strings.signUpErrorConfirm),
                        obscure: true,
                        autofillHints: const [AutofillHints.newPassword],
                        onChanged: (_) => _touch('confirm'),
                      ),
                      const SizedBox(height: 18),
                      _Terms(
                        agreed: _agreed,
                        allAgreed: _allAgreed,
                        skin: skin,
                        onToggleAll: _toggleAll,
                        onToggle: (term) =>
                            setState(() => _agreed[term] = !_agreed[term]!),
                        onOpen: _openTerms,
                      ),
                      const SizedBox(height: 22),
                      _Submit(
                        skin: skin,
                        enabled: _canSubmit && !_busy,
                        busy: _busy,
                        onPressed: _submit,
                      ),
                      SizedBox(
                        height: 40,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              Strings.signUpHaveAccount,
                              style: text.bodyMedium?.copyWith(
                                  color: skin.inkFaint,
                                  fontWeight: FontWeight.w500),
                            ),
                            TextButton(
                              onPressed: widget.onBack,
                              child: Text(
                                Strings.loginSubmit,
                                style: text.bodyMedium?.copyWith(
                                    color: skin.primary,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 약관 본문.
  ///
  /// IMPORTANT: 본문 화면은 아직 없다(R-12). 목업처럼 자기 화면을 다시 여는 것으로
  /// 대체하지 않고, 준비 중이라는 사실을 그대로 알린다.
  void _openTerms(_Term term) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${term.label} · ${Strings.termsPending}'),
        backgroundColor: context.skin.strong,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// 약관 셋. 필수 둘과 선택 하나다.
enum _Term {
  service(Strings.signUpTermsService, required: true, hasDoc: true),
  privacy(Strings.signUpTermsPrivacy, required: true, hasDoc: true),
  alert(Strings.signUpTermsAlert, required: false, hasDoc: false);

  const _Term(this.label, {required this.required, required this.hasDoc});

  final String label;
  final bool required;

  /// 열어 볼 본문이 있는지. 기한 알림은 설정이라 본문이 없다.
  final bool hasDoc;

  String get tag =>
      required ? Strings.signUpTermsRequired : Strings.signUpTermsOptional;
}

/// 이메일 칸 오른쪽의 확인 표시.
///
/// 쓸 수 있으면 체크, 확인 중이면 회전, 나머지는 비운다 — 오류 문구가 이미 칸 아래에
/// 나오므로 여기서 또 말하지 않는다.
class _EmailMark extends StatelessWidget {
  const _EmailMark({
    required this.checking,
    required this.state,
    required this.skin,
  });

  final bool checking;
  final EmailAvailability? state;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    if (checking) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: skin.inkDim),
        ),
      );
    }
    if (state != EmailAvailability.free) return const SizedBox.shrink();
    return Semantics(
      label: Strings.signUpEmailFree,
      child: Center(
        child: Icon(Icons.check_rounded, size: 20, color: skin.done.accent),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.skin, required this.onBack});

  final Skin skin;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            SizedBox(
              width: Tokens.tap,
              height: Tokens.tap,
              child: IconButton(
                onPressed: onBack,
                iconSize: 22,
                color: skin.ink,
                tooltip: Strings.signUpBack,
                style: IconButton.styleFrom(
                  backgroundColor: skin.glass,
                  shape: CircleBorder(side: BorderSide(color: skin.edge)),
                ),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              ),
            ),
            Expanded(
              child: Text(
                Strings.signUpTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(width: Tokens.tap),
          ],
        ),
      );
}

/// 비밀번호 조건. 충족한 것만 색이 들어간다.
class _Rules extends StatelessWidget {
  const _Rules({required this.password, required this.skin});

  final String password;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final rules = [
      (Strings.signUpRuleLetter, Credentials.hasLetter(password)),
      (Strings.signUpRuleDigit, Credentials.hasDigit(password)),
      (Strings.signUpRuleLength, Credentials.isLongEnough(password)),
    ];
    final met = skin.done.accent;

    return Semantics(
      label: '비밀번호 조건',
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Row(
          children: [
            for (final (label, ok) in rules)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  children: [
                    Icon(Icons.check_rounded,
                        size: 14, color: ok ? met : skin.inkDim),
                    const SizedBox(width: 3),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: ok ? met : skin.inkDim,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Terms extends StatelessWidget {
  const _Terms({
    required this.agreed,
    required this.allAgreed,
    required this.skin,
    required this.onToggleAll,
    required this.onToggle,
    required this.onOpen,
  });

  final Map<_Term, bool> agreed;
  final bool allAgreed;
  final Skin skin;
  final VoidCallback onToggleAll;
  final void Function(_Term term) onToggle;
  final void Function(_Term term) onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      label: Strings.signUpTermsGroup,
      child: GlassPanel(
        radius: 16,
        padding: const EdgeInsets.symmetric(vertical: 4),
        shadow: [skin.shade(0.08, 24, 8)],
        child: Column(
          children: [
            Semantics(
              checked: allAgreed,
              child: InkWell(
                onTap: onToggleAll,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        _Box(on: allAgreed, size: 24, radius: 8, skin: skin),
                        const SizedBox(width: 10),
                        Text(Strings.signUpAgreeAll, style: text.titleSmall),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(height: 1, color: skin.hairline),
            ),
            for (final term in _Term.values)
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      checked: agreed[term]!,
                      child: InkWell(
                        onTap: () => onToggle(term),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                _Box(
                                    on: agreed[term]!,
                                    size: 20,
                                    radius: 6,
                                    skin: skin),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${term.tag} ',
                                          style: text.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: term.required
                                                ? skin.primary
                                                : skin.inkFaint,
                                          ),
                                        ),
                                        TextSpan(text: term.label),
                                      ],
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodyMedium?.copyWith(
                                        color: skin.inkMuted,
                                        fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (term.hasDoc)
                    SizedBox(
                      width: Tokens.tap,
                      height: Tokens.tap,
                      child: IconButton(
                        onPressed: () => onOpen(term),
                        iconSize: 16,
                        color: skin.inkDim,
                        tooltip: Strings.signUpTermsOpen(term.label),
                        icon: const Icon(Icons.arrow_forward_ios_rounded),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.on,
    required this.size,
    required this.radius,
    required this.skin,
  });

  final bool on;
  final double size;
  final double radius;
  final Skin skin;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: on ? skin.primary : skin.field,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
              color: on ? skin.primary : skin.trackDashed, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.check_rounded,
          size: size * 0.6,
          color: on ? skin.onPrimary : skin.inkDim,
        ),
      );
}

class _Submit extends StatelessWidget {
  const _Submit({
    required this.skin,
    required this.enabled,
    required this.onPressed,
    this.busy = false,
  });

  final Skin skin;
  final bool enabled;
  final VoidCallback onPressed;

  /// 서버 응답을 기다리는 중. 두 번 눌러 두 계정을 만들지 않게 막는다.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusField));
    return Semantics(
      button: true,
      enabled: enabled,
      child: SizedBox(
        height: 52,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: enabled ? skin.primary : skin.toggleOff,
            shape: shape,
            shadows: enabled ? [skin.shade(0.13, 22, 10)] : null,
          ),
          child: InkWell(
            onTap: enabled ? onPressed : null,
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
                      Strings.signUpSubmit,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          color: enabled ? skin.onPrimary : skin.inkDim),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
