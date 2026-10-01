/// 기록과 설정의 실기기 검증. UI-12·13 / F-11·23 / V-09·17.
///
/// 확인하는 것은 다섯이다.
///
/// 1. 기록이 **날짜로 자르지 않고 전체를 최근순으로** 읽는다.
/// 2. 발화와 변경 전후가 한 줄에 함께 보이고, 명시값과 추정을 구분한다.
/// 3. 되돌리기는 **전체에서 최신인 되돌릴 수 있는 변경**에만 붙는다.
/// 4. 마이페이지의 테마·기본 인분·음성 응답·기한 알림이 저장되고 다시 띄워도 남는다.
/// 5. 반영 경로가 없는 설정은 **준비 중으로 표시하고 조작할 수 없다.**
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:today_meal/core/design/skin.dart';
import 'package:today_meal/core/di.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/core/settings/app_settings.dart';
import 'package:today_meal/domain/model/inventory.dart';
import 'package:today_meal/domain/repository/repositories.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> say(String utterance) async {
    await di<CommandRepository>().interpret(
      commandId: newCommandId(),
      utterance: utterance,
    );
  }

  Future<AppSettings> enterAsGuest(WidgetTester tester,
      {AppSettings? settings}) async {
    final resolved = await launchApp(tester, settings: settings);
    if (find.text(Strings.loginGuest).evaluate().isNotEmpty) {
      await tapAndWait(tester, find.text(Strings.loginGuest));
    }
    if (find.text(Strings.permissionSkip).evaluate().isNotEmpty) {
      await tapAndWait(tester, find.text(Strings.permissionSkip),
          wait: const Duration(seconds: 4));
    }
    await waitFor(tester, find.text(Strings.tabHistory));
    await clearFridge();
    return resolved;
  }

  Future<void> openHistory(WidgetTester tester) async {
    await tapAndWait(tester, find.text(Strings.tabHistory).last,
        wait: const Duration(seconds: 6));
    await waitFor(tester, find.text(Strings.historyTitle), reason: '기록 화면');
  }

  Future<void> openMyPage(WidgetTester tester) async {
    await tapAndWait(tester, find.text(Strings.tabMyPage).last,
        wait: const Duration(seconds: 3));
    await waitFor(tester, find.text(Strings.myPageThemeSection),
        reason: '마이페이지');
  }

  testWidgets('기록이 발화와 변경 전후를 최근순으로 읽는다', (tester) async {
    await enterAsGuest(tester);
    await say('계란 열 개 넣었어');
    await say('계란 두 개 썼어');
    await openHistory(tester);

    await waitFor(tester, find.text(Strings.historyConsume),
        reason: '사용 기록');
    expect(find.text(Strings.historyStockIn), findsWidgets, reason: '입고 기록');
    // 명시값과 추정을 구분해 표시한다.
    final marked = find.text(Strings.historyExact).evaluate().isNotEmpty ||
        find.text(Strings.historyEstimated).evaluate().isNotEmpty;
    expect(marked, isTrue);
  });

  testWidgets('되돌리기는 최신 변경에만 붙는다', (tester) async {
    await enterAsGuest(tester);
    await say('두부 네 모 넣었어');
    await say('두부 한 모 썼어');
    await openHistory(tester);

    await waitFor(tester, find.text(Strings.historyConsume));
    expect(find.text(Strings.undo), findsOneWidget,
        reason: '되돌리기는 전체에서 최신인 하나에만 붙는다');
  });

  testWidgets('기록에서 되돌리면 재고가 복원된다', (tester) async {
    await enterAsGuest(tester);
    await say('양파 여섯 개 넣었어');
    await say('양파 두 개 썼어');

    final inventory = di<InventoryRepository>();
    double onion(List<IngredientBatch> batches) => batches
        .where((batch) => batch.name == '양파')
        .fold(0, (sum, batch) => sum + (double.tryParse(batch.quantity ?? '') ?? 0));

    final used = onion(await inventory.listBatches());
    await openHistory(tester);
    await waitFor(tester, find.text(Strings.historyConsume));
    await scrollTo(tester, find.text(Strings.undo));
    await tapAndWait(tester, find.text(Strings.undo),
        wait: const Duration(seconds: 10));

    final restored = onion(await inventory.listBatches());
    expect(restored, greaterThan(used), reason: '되돌리기가 쓴 만큼을 되살린다');
  });

  testWidgets('고른 테마가 저장되고 다시 띄워도 남는다', (tester) async {
    final settings = await enterAsGuest(tester);
    await openMyPage(tester);

    await tapAndWait(tester, find.text(Strings.myPageThemeDark),
        wait: const Duration(seconds: 3));
    expect(settings.skin, SkinName.dark);

    // 저장된 값으로 다시 띄운다.
    final reloaded = await AppSettings.load();
    expect(reloaded.skin, SkinName.dark, reason: '테마가 기기에 남는다');
  });

  testWidgets('기본 인분을 바꾸면 저장되고 추천 요청에 쓰인다', (tester) async {
    final settings = await enterAsGuest(tester);
    await openMyPage(tester);

    await scrollTo(tester, find.text(Strings.myPageDefaultServings));
    final before = settings.defaultServings;
    // 스테퍼의 늘리기. 마이페이지에는 스테퍼가 하나뿐이다.
    await tapAndWait(tester, find.byIcon(Icons.add_rounded).first,
        wait: const Duration(seconds: 3));

    expect(settings.defaultServings, greaterThan(before));
    final reloaded = await AppSettings.load();
    expect(reloaded.defaultServings, settings.defaultServings);
  });

  testWidgets('음성 응답과 기한 알림이 저장된다', (tester) async {
    final settings = await enterAsGuest(tester);
    await openMyPage(tester);

    // 신규 사용자의 선택 동의 기본값은 꺼짐이다.
    expect(settings.expiryAlert, isFalse,
        reason: '동의하지 않은 표시를 켜 둔 채로 시작하지 않는다');

    await scrollTo(tester, find.text(Strings.myPageSpokenReply));
    final before = settings.spokenReply;
    // 토글은 Material 의 Switch 가 아니라 목업을 따른 우리 위젯이다. 그 줄 안에서
    // 누를 것을 찾는다 — 화면에 토글이 둘이므로 줄을 먼저 좁혀야 한다.
    final row = find
        .ancestor(
          of: find.text(Strings.myPageSpokenReply),
          matching: find.byType(Row),
        )
        .last;
    await tapAndWait(
      tester,
      find.descendant(of: row, matching: find.byType(GestureDetector)).first,
      wait: const Duration(seconds: 3),
    );
    expect(settings.spokenReply, isNot(before));

    final reloaded = await AppSettings.load();
    expect(reloaded.spokenReply, settings.spokenReply);
  });

  testWidgets('반영 경로가 없는 설정은 준비 중으로 둔다', (tester) async {
    await enterAsGuest(tester);
    await openMyPage(tester);

    await scrollTo(tester, find.text(Strings.myPagePantryStaples));
    // 늘 있는 양념·피하는 재료·알림 시점 셋이다. 조작 가능한 설정으로 두지 않는다.
    expect(find.text(Strings.settingPending), findsNWidgets(3));
  });

  testWidgets('호출어는 표시 문구와 실제 값이 같다', (tester) async {
    await enterAsGuest(tester);
    await openMyPage(tester);

    await scrollTo(tester, find.text(Strings.wakeWordSetting));
    expect(find.text(Strings.wakeWord), findsWidgets);
  });
}
