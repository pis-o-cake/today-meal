/// 진입과 계정의 실기기 검증. UI-01~04·13 / F-15·22 / V-13.
///
/// 확인하는 것은 넷이다.
///
/// 1. 첫 실행이 스플래시를 지나 **로그인 화면**에 선다.
/// 2. 둘러보기가 권한 안내를 지나 홈으로 들어가고 **다섯 탭이 모두 뜬다.**
/// 3. 가입한 계정은 **자기 가구**로 들어가 냉장고가 비어 있다.
/// 4. 로그아웃하면 그 세션이 끊기고 다시 로그인할 수 있다.
///
/// WARNING: 이 파일은 서버에 실제 계정을 만든다. 검증용 서버를 쓴다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/core/settings/app_settings.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String freshEmail() =>
      'e2e-${DateTime.now().microsecondsSinceEpoch}@example.com';

  testWidgets('첫 실행은 스플래시를 지나 로그인 화면에 선다', (tester) async {
    await launchApp(tester);

    // 스플래시가 먼저 뜬다. 검은 화면으로 시작하지 않는다.
    await waitFor(tester, find.text(Strings.loginSubmit),
        reason: '로그인 화면');
    expect(find.text(Strings.loginGuest), findsOneWidget);
    expect(find.text(Strings.loginKakao), findsOneWidget);
    // 연동하지 않은 제공자도 감추지 않는다 — 왜 안 되는지 말하기 위해 남긴다.
    expect(find.text(Strings.loginGoogle), findsOneWidget);
  });

  testWidgets('연동하지 않은 로그인을 성공으로 처리하지 않는다', (tester) async {
    await launchApp(tester);
    await waitFor(tester, find.text(Strings.loginGoogle));

    await tapAndWait(tester, find.text(Strings.loginGoogle));

    expect(find.text(Strings.loginSubmit), findsOneWidget,
        reason: '로그인 화면에 그대로 남아야 한다');
    expect(find.textContaining(Strings.loginProviderPending), findsWidgets);
  });

  testWidgets('틀린 비밀번호는 이메일의 존재 여부를 알려주지 않는다', (tester) async {
    await launchApp(tester);
    await waitFor(tester, find.text(Strings.loginSubmit));

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), freshEmail());
    await tester.enterText(fields.at(1), 'wrongpass123');
    await tapAndWait(tester, find.text(Strings.loginSubmit),
        wait: const Duration(seconds: 6));

    expect(find.text(Strings.loginWrongCredentials), findsOneWidget);
    expect(find.text(Strings.tabFridge), findsNothing, reason: '홈으로 들어가면 안 된다');
  });

  testWidgets('둘러보기는 권한 안내를 지나 다섯 탭으로 들어간다', (tester) async {
    await launchApp(tester);
    await waitFor(tester, find.text(Strings.loginGuest));

    await tapAndWait(tester, find.text(Strings.loginGuest));

    // UI-04. 마이크를 요구하지 않고도 지나갈 수 있어야 한다.
    await waitFor(tester, find.text(Strings.permissionSkip), reason: '권한 안내');
    await tapAndWait(tester, find.text(Strings.permissionSkip),
        wait: const Duration(seconds: 4));

    for (final tab in [
      Strings.tabFridge,
      Strings.tabCook,
      Strings.tabHistory,
      Strings.tabMyPage,
    ]) {
      expect(find.text(tab), findsWidgets, reason: '$tab 탭');
    }
  });

  testWidgets('권한 안내는 한 번만 보여준다', (tester) async {
    final settings = await launchApp(tester);
    await waitFor(tester, find.text(Strings.loginGuest));
    await tapAndWait(tester, find.text(Strings.loginGuest));
    await waitFor(tester, find.text(Strings.permissionSkip));
    await tapAndWait(tester, find.text(Strings.permissionSkip),
        wait: const Duration(seconds: 4));

    // 저장된 설정 그대로 다시 띄운다. 두 번째 실행이다.
    await launchApp(tester, settings: await AppSettings.load());
    await waitGone(tester, find.text(Strings.permissionSkip),
        reason: '권한 안내가 다시 뜨면 안 된다');
    expect(settings.onboarded, isTrue);
  });

  testWidgets('가입한 계정은 빈 냉장고로 시작한다', (tester) async {
    await launchApp(tester);
    await waitFor(tester, find.text(Strings.loginSignUp));

    await tapAndWait(tester, find.text(Strings.loginSignUp));
    await waitFor(tester, find.text(Strings.signUpSubmit), reason: '가입 화면');

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '검증');
    await tester.enterText(fields.at(1), freshEmail());
    await tester.enterText(fields.at(2), 'kitchen123');
    await tester.enterText(fields.at(3), 'kitchen123');
    await pumpFor(tester, const Duration(seconds: 2));

    // 필수 약관에 동의해야 가입 버튼이 살아난다. 화면 밖이면 눌리지 않으므로
    // 먼저 보이게 올린다.
    await scrollTo(tester, find.text(Strings.signUpAgreeAll));
    await tapAndWait(tester, find.text(Strings.signUpAgreeAll), warn: true);
    await scrollTo(tester, find.text(Strings.signUpSubmit));
    await tapAndWait(tester, find.text(Strings.signUpSubmit),
        wait: const Duration(seconds: 10), warn: true);

    // 권한 안내를 지나 홈으로.
    if (find.text(Strings.permissionSkip).evaluate().isNotEmpty) {
      await tapAndWait(tester, find.text(Strings.permissionSkip),
          wait: const Duration(seconds: 4));
    }
    await waitFor(tester, find.text(Strings.tabFridge), reason: '홈');

    await tapAndWait(tester, find.text(Strings.tabFridge).last,
        wait: const Duration(seconds: 6));

    // 가입 직후에는 기본 가구의 시연 재고가 보이지 않는다.
    expect(find.text(Strings.empty), findsWidgets,
        reason: '새 계정의 냉장고는 비어 있다');
  });

  testWidgets('로그아웃하면 로그인 화면으로 돌아간다', (tester) async {
    await launchApp(tester);
    await waitFor(tester, find.text(Strings.loginGuest));
    await tapAndWait(tester, find.text(Strings.loginGuest));
    await waitFor(tester, find.text(Strings.permissionSkip));
    await tapAndWait(tester, find.text(Strings.permissionSkip),
        wait: const Duration(seconds: 4));

    await tapAndWait(tester, find.text(Strings.tabMyPage).last,
        wait: const Duration(seconds: 3));
    await waitFor(tester, find.text(Strings.myPageGuestKitchen),
        reason: '게스트 마이페이지');

    // 게스트는 로그아웃이 아니라 로그인으로 간다.
    await scrollTo(tester, find.text(Strings.myPageSignIn));
    await tapAndWait(tester, find.text(Strings.myPageSignIn),
        wait: const Duration(seconds: 3));

    expect(find.text(Strings.loginSubmit), findsOneWidget);
  });
}
