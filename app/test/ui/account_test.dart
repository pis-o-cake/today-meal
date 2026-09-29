import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:today_meal/core/design/skin.dart';
import 'package:today_meal/core/design/tokens.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/core/settings/app_settings.dart';
import 'package:today_meal/core/settings/local_accounts.dart';
import 'package:today_meal/domain/repository/repositories.dart';
import 'package:today_meal/ui/account/login_screen.dart';
import 'package:today_meal/ui/account/signup_screen.dart';

/// 계정 화면의 계약.
///
/// 지키는 것은 넷이다.
///
/// 1. 서버가 거절하면 **성공으로 넘어가지 않는다.**
/// 2. 로그인 실패는 이메일의 존재 여부를 **알려주지 않는다.**
/// 3. 필수 동의와 입력 조건이 다 차야 가입 버튼이 켜진다.
/// 4. 응답을 기다리는 동안 두 번 눌러 두 계정을 만들지 않는다.
void main() {
  group('형식 검사', () {
    test('이메일 형식', () {
      expect(Credentials.isEmail('a@b.com'), isTrue);
      expect(Credentials.isEmail('  a@b.com  '), isTrue);
      expect(Credentials.isEmail('a@b'), isFalse);
      expect(Credentials.isEmail('ab.com'), isFalse);
      expect(Credentials.isEmail(''), isFalse);
    });

    test('비밀번호는 영문·숫자·8자 이상', () {
      expect(Credentials.isStrongPassword('kitchen123'), isTrue);
      expect(Credentials.isStrongPassword('kitchen'), isFalse, reason: '숫자 없음');
      expect(Credentials.isStrongPassword('12345678'), isFalse, reason: '영문 없음');
      expect(Credentials.isStrongPassword('kit123'), isFalse, reason: '8자 미만');
    });
  });

  testWidgets('로그인 실패는 이메일의 존재 여부를 알려주지 않는다', (tester) async {
    final auth = _FakeAuth(failure: AuthFailure.wrongCredentials);
    Account? entered;
    await _pump(
      tester,
      LoginScreen(
        auth: auth,
        onSignedIn: (account, _) => entered = account,
        onGuest: () {},
        onSignUp: () {},
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'nobody@example.com');
    await tester.enterText(find.byType(TextField).last, 'kitchen123');
    await _press(tester, find.text(Strings.loginSubmit));

    expect(entered, isNull, reason: '거절당했으면 들어가지 않는다');
    expect(find.text(Strings.loginWrongCredentials), findsOneWidget);
    expect(find.textContaining('없는 계정'), findsNothing,
        reason: '이메일이 가입돼 있는지 드러내지 않는다');
  });

  testWidgets('로그인에 성공하면 토큰과 계정을 함께 넘긴다', (tester) async {
    final auth = _FakeAuth();
    Account? entered;
    String? token;
    await _pump(
      tester,
      LoginScreen(
        auth: auth,
        onSignedIn: (account, value) {
          entered = account;
          token = value;
        },
        onGuest: () {},
        onSignUp: () {},
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'cheol@example.com');
    await tester.enterText(find.byType(TextField).last, 'kitchen123');
    await tester.tap(find.text(Strings.loginSubmit));
    await tester.pumpAndSettle();

    expect(entered?.email, 'cheol@example.com');
    expect(entered?.provider, AccountProvider.email);
    expect(token, isNotNull, reason: '토큰이 없으면 이후 호출이 게스트가 된다');
  });

  testWidgets('서버에 닿지 못하면 로그인으로 처리하지 않는다', (tester) async {
    final auth = _FakeAuth(failure: AuthFailure.unreachable);
    Account? entered;
    await _pump(
      tester,
      LoginScreen(
        auth: auth,
        onSignedIn: (account, _) => entered = account,
        onGuest: () {},
        onSignUp: () {},
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'cheol@example.com');
    await tester.enterText(find.byType(TextField).last, 'kitchen123');
    await tester.tap(find.text(Strings.loginSubmit));
    await tester.pumpAndSettle();

    expect(entered, isNull);
    expect(find.text(Strings.serverFailed), findsOneWidget);
  });

  testWidgets('둘러보기는 서버를 부르지 않는다', (tester) async {
    final auth = _FakeAuth();
    var guest = false;
    await _pump(
      tester,
      LoginScreen(
        auth: auth,
        onSignedIn: (_, _) {},
        onGuest: () => guest = true,
        onSignUp: () {},
      ),
    );

    await _press(tester, find.text(Strings.loginGuest));

    expect(guest, isTrue);
    expect(auth.calls, isEmpty, reason: '게스트는 인증 경로를 타지 않는다');
  });

  testWidgets('카카오 로그인이 성공하면 계정과 토큰을 넘긴다', (tester) async {
    final auth = _FakeAuth();
    Account? entered;
    String? token;
    await _pump(
      tester,
      LoginScreen(
        auth: auth,
        onSignedIn: (account, value) {
          entered = account;
          token = value;
        },
        onGuest: () {},
        onSignUp: () {},
      ),
    );

    await _press(tester, find.text(Strings.loginKakao));

    expect(auth.calls, contains('signInWith:kakao'));
    expect(entered?.provider, AccountProvider.kakao);
    expect(entered?.nickname, '철');
    expect(token, 'kakao-token');
  });

  testWidgets('연동하지 않은 제공자를 성공으로 처리하지 않는다', (tester) async {
    final auth = _FakeAuth(socialFailure: AuthFailure.notConnected);
    Account? entered;
    await _pump(
      tester,
      LoginScreen(
        auth: auth,
        onSignedIn: (account, _) => entered = account,
        onGuest: () {},
        onSignUp: () {},
      ),
    );

    await _press(tester, find.text(Strings.loginGoogle));

    expect(entered, isNull);
    expect(find.textContaining(Strings.loginProviderPending), findsOneWidget);
  });

  testWidgets('제공자 화면에서 취소하면 아무 말도 하지 않는다', (tester) async {
    // 사용자가 스스로 그만둔 것이다. 오류를 띄우면 뭔가 잘못된 것으로 읽힌다.
    final auth = _FakeAuth(socialFailure: AuthFailure.cancelled);
    Account? entered;
    await _pump(
      tester,
      LoginScreen(
        auth: auth,
        onSignedIn: (account, _) => entered = account,
        onGuest: () {},
        onSignUp: () {},
      ),
    );

    await _press(tester, find.text(Strings.loginKakao));

    expect(entered, isNull);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('필수 동의와 입력이 다 차야 가입할 수 있다', (tester) async {
    final auth = _FakeAuth();
    Account? made;
    await _pump(
      tester,
      SignUpScreen(
        auth: auth,
        onSignedUp: (account, _) => made = account,
        onBack: () {},
      ),
    );

    // 입력만 채우고 동의는 하지 않는다.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '철');
    await tester.enterText(fields.at(1), 'cheol@example.com');
    await tester.enterText(fields.at(2), 'kitchen123');
    await tester.enterText(fields.at(3), 'kitchen123');
    await tester.pumpAndSettle();

    await _press(tester, find.text(Strings.signUpSubmit));
    expect(made, isNull, reason: '필수 동의 전에는 가입되지 않는다');
    expect(auth.signUpCount, 0);

    // 모두 동의하면 켜진다. 선택 동의까지 켜지지만 필수만으로도 충분하다.
    await _press(tester, find.text(Strings.signUpAgreeAll));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await _press(tester, find.text(Strings.signUpSubmit));

    expect(made?.nickname, '철');
    expect(auth.signUpCount, 1);
  });

  testWidgets('중복 확인이 이미 쓰는 이메일을 미리 막는다', (tester) async {
    final auth = _FakeAuth(availability: EmailAvailability.taken);
    Account? made;
    await _pump(
      tester,
      SignUpScreen(
        auth: auth,
        onSignedUp: (account, _) => made = account,
        onBack: () {},
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '철');
    await tester.enterText(fields.at(1), 'taken@example.com');
    await tester.enterText(fields.at(2), 'kitchen123');
    await tester.enterText(fields.at(3), 'kitchen123');
    await _press(tester, find.text(Strings.signUpAgreeAll));
    // 타이핑이 멈춘 뒤에 확인한다.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(auth.calls, contains('checkEmail'));
    expect(find.text(Strings.signUpErrorTaken), findsOneWidget);

    await _press(tester, find.text(Strings.signUpSubmit));
    expect(made, isNull, reason: '이미 쓰는 이메일이면 누를 수 없다');
    expect(auth.calls, isNot(contains('signUp')));
  });

  testWidgets('확인하지 못해도 가입을 막지 않는다', (tester) async {
    // 서버가 잠깐 흔들렸다고 아무도 가입하지 못하면 안 된다. 판정은 가입 시점이다.
    final auth = _FakeAuth(availability: EmailAvailability.unknown);
    Account? made;
    await _pump(
      tester,
      SignUpScreen(
        auth: auth,
        onSignedUp: (account, _) => made = account,
        onBack: () {},
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '철');
    await tester.enterText(fields.at(1), 'cheol@example.com');
    await tester.enterText(fields.at(2), 'kitchen123');
    await tester.enterText(fields.at(3), 'kitchen123');
    await _press(tester, find.text(Strings.signUpAgreeAll));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await _press(tester, find.text(Strings.signUpSubmit));
    expect(made?.nickname, '철');
  });

  testWidgets('가입 시점에 서버가 거절하면 이메일 칸에 표시한다', (tester) async {
    // 확인은 통과했는데 그 사이에 남이 먼저 가입한 경우다.
    final auth = _FakeAuth(failure: AuthFailure.emailTaken);
    Account? made;
    await _pump(
      tester,
      SignUpScreen(
        auth: auth,
        onSignedUp: (account, _) => made = account,
        onBack: () {},
      ),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '철');
    await tester.enterText(fields.at(1), 'taken@example.com');
    await tester.enterText(fields.at(2), 'kitchen123');
    await tester.enterText(fields.at(3), 'kitchen123');
    await _press(tester, find.text(Strings.signUpAgreeAll));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await _press(tester, find.text(Strings.signUpSubmit));

    expect(made, isNull);
    expect(find.text(Strings.signUpErrorTaken), findsOneWidget);
  });

  testWidgets('응답을 기다리는 동안 두 번 가입하지 않는다', (tester) async {
    final auth = _FakeAuth(hangs: true);
    await _pump(
      tester,
      SignUpScreen(auth: auth, onSignedUp: (_, _) {}, onBack: () {}),
    );

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '철');
    await tester.enterText(fields.at(1), 'cheol@example.com');
    await tester.enterText(fields.at(2), 'kitchen123');
    await tester.enterText(fields.at(3), 'kitchen123');
    await _press(tester, find.text(Strings.signUpAgreeAll));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text(Strings.signUpSubmit));
    await tester.pumpAndSettle();
    await tester.tap(find.text(Strings.signUpSubmit));
    await tester.pump();
    // 두 번째 탭은 버튼이 이미 꺼져 있어 닿지 않는다.
    await tester.tap(find.byType(SignUpScreen), warnIfMissed: false);
    await tester.pump();

    expect(auth.signUpCount, 1, reason: '한 번만 보내야 계정이 하나 만들어진다');
    auth.release();
    await tester.pumpAndSettle();
  });
}

/// 폰 크기로 띄운다.
///
/// 기본 테스트 창(800×600)에서는 계정 화면의 아래쪽 버튼이 화면 밖에 있어 탭이 닿지
/// 않는다. 실제 기기와 같은 세로 비율로 두어야 "버튼을 누를 수 있는가"를 본다.
Future<void> _pump(WidgetTester tester, Widget child) async {
  const skin = Skins.pastel;
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.75;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    SkinScope(
      skin: skin,
      child: MaterialApp(theme: buildTheme(skin), home: child),
    ),
  );
  await tester.pumpAndSettle();
}

/// 화면 밖이면 스크롤해 올리고 누른다.
Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// 서버 대신 미리 정한 답을 준다.
class _FakeAuth implements AuthRepository {
  _FakeAuth({
    this.failure,
    this.hangs = false,
    this.availability = EmailAvailability.free,
    this.socialFailure,
  });

  /// 간편 로그인의 결과. `null` 이면 성공한다.
  final AuthFailure? socialFailure;

  final AuthFailure? failure;

  /// 중복 확인의 답. 가입 화면이 이 값으로 버튼을 켜고 끈다.
  final EmailAvailability availability;

  /// 응답을 붙잡아 둔다. 기다리는 동안의 화면을 보기 위한 것이다.
  final bool hangs;

  final calls = <String>[];

  /// 가입을 몇 번 보냈는지. 중복 확인 호출이 섞여도 이것만 센다.
  int get signUpCount => calls.where((c) => c == 'signUp').length;
  final _held = <void Function()>[];

  void release() {
    for (final resume in _held) {
      resume();
    }
    _held.clear();
  }

  Future<AuthResult> _answer() async {
    if (hangs) {
      final gate = Completer<void>();
      _held.add(gate.complete);
      await gate.future;
    }
    if (failure != null) return AuthResult.failed(failure);
    return const AuthResult.success(
      token: 'test-token',
      account: AuthAccount(
        userId: 1,
        householdId: 2,
        provider: 'email',
        email: 'cheol@example.com',
        nickname: '철',
      ),
    );
  }

  @override
  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String nickname,
  }) {
    calls.add('signUp');
    return _answer();
  }

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) {
    calls.add('signIn');
    return _answer();
  }

  @override
  Future<EmailAvailability> checkEmail(String email) async {
    calls.add('checkEmail');
    return availability;
  }

  @override
  Future<AuthResult> signInWith(SocialProvider provider) async {
    calls.add('signInWith:${provider.name}');
    if (socialFailure != null) return AuthResult.failed(socialFailure);
    return const AuthResult.success(
      token: 'kakao-token',
      account: AuthAccount(
        userId: 7,
        householdId: 9,
        provider: 'kakao',
        nickname: '철',
      ),
    );
  }

  @override
  Future<void> signOut() async => calls.add('signOut');

  @override
  Future<AuthAccount?> restore(String token) async {
    calls.add('restore');
    return null;
  }
}
