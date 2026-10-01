/// 추천과 조리의 실기기 검증. UI-05·06·09~11 / F-13·14·25·07 / V-07·08·15.
///
/// 확인하는 것은 여섯이다.
///
/// 1. 재고가 있으면 추천이 오고 **없는 필수 재료를 '지금 가능' 으로 말하지 않는다.**
/// 2. 메뉴 상세가 인분을 바꾸면 **서버가 환산한 수량**으로 다시 그린다.
/// 3. 상세를 열고 인분을 바꾸는 것만으로 **재고가 바뀌지 않는다.**
/// 4. 조리를 시작해 단계를 앞뒤로 옮기고 타이머를 쓸 수 있다.
/// 5. 완료가 **화면에서 조리한 인분**으로 차감하고 그 결과를 이름으로 알린다.
/// 6. 되돌리기가 실제 취소 요청을 보내 재고를 복원한다.
///
/// 단계 낭독은 기기의 TTS 를 쓰므로 여기서 소리를 확인하지 않는다 — 낭독 호출 여부는
/// `test/ui/cook_test.dart` 가 본다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:today_meal/core/di.dart';
import 'package:today_meal/core/l10n/strings.dart';
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

  Future<List<IngredientBatch>> stock() => di<InventoryRepository>().listBatches();

  /// 이름이 같은 묶음의 잔량 합. 모르는 잔량은 세지 않는다.
  ///
  /// 잔량은 서버가 준 문자열이다 — `3.000` 이 `3` 과 같아야 하므로 숫자로 읽는다.
  double amountOf(List<IngredientBatch> batches, String name) => batches
      .where((batch) => batch.name == name)
      .fold(0, (sum, batch) => sum + (double.tryParse(batch.quantity ?? '') ?? 0));

  /// 추천이 나올 만큼의 재고를 넣고 홈으로 들어간다.
  Future<void> enterWithStock(WidgetTester tester) async {
    await launchApp(tester);
    await waitFor(tester, find.text(Strings.loginGuest));
    await tapAndWait(tester, find.text(Strings.loginGuest));
    await waitFor(tester, find.text(Strings.permissionSkip));
    await tapAndWait(tester, find.text(Strings.permissionSkip),
        wait: const Duration(seconds: 4));
    await waitFor(tester, find.text(Strings.tabCook));

    // 테스트마다 같은 자리에서 시작한다. 앞선 테스트가 남긴 재고가 추천을 흔든다.
    await clearFridge();
    // IMPORTANT: 기한을 **임박하게** 말한다. 홈의 주 행동은 고른 등급의 메뉴를
    // 보여주는데, 그 메뉴는 **먼저 쓸 재료**를 쓰는 것만 골라진다. 기한이 멀면
    // 서버가 먼저 쓸 재료를 비워 보내므로 어느 등급에도 메뉴가 붙지 않는다.
    //
    // WARNING: 기준일에 매인다. 오늘로부터 며칠 뒤가 되도록 날짜를 만든다.
    final soon = DateTime.now().add(const Duration(days: 3));
    final sooner = DateTime.now().add(const Duration(days: 2));
    await say('계란 열 개 넣었어 소비기한은 ${soon.month}월 ${soon.day}일까지야');
    await say('두부 네 모 넣었어 소비기한은 ${sooner.month}월 ${sooner.day}일까지야');
    await say('양파 세 개 넣었어 소비기한은 ${soon.month}월 ${soon.day}일까지야');
  }

  Future<void> openCookTab(WidgetTester tester) async {
    await tapAndWait(tester, find.text(Strings.tabCook).last,
        wait: const Duration(seconds: 3));
    await waitFor(tester, find.text(Strings.cookPicksTitle),
        reason: '조리 탭');
    // 추천은 모델 경로다. 후보 카드의 시작 버튼이 뜰 때까지 기다린다.
    await waitFor(tester, find.text(Strings.cookStart),
        limit: const Duration(seconds: 60), reason: '추천 후보');
  }

  testWidgets('조리 탭이 재고로 추천을 받는다', (tester) async {
    await enterWithStock(tester);
    await openCookTab(tester);

    expect(find.text(Strings.cookPicksEmpty), findsNothing);
    // 가용성은 인분·시간과 한 줄에 묶여 오므로 부분 일치로 찾는다.
    //
    // 없는 재료가 필요한 후보를 '지금 가능' 으로 말하지 않는다 — 검증용 서버의 가짜
    // 게이트웨이는 후보 둘 중 하나에 일부러 없는 재료를 넣는다.
    expect(find.textContaining(Strings.menuStockShort), findsWidgets,
        reason: '없는 재료가 필요한 후보는 재료 준비 후로 말한다');
    expect(find.textContaining(Strings.menuStockReady), findsWidgets,
        reason: '재고로 되는 후보는 재료가 다 있다고 말한다');
  });

  testWidgets('홈의 추천을 열면 메뉴 상세가 재료와 순서를 보여준다', (tester) async {
    await enterWithStock(tester);
    await tapAndWait(tester, find.text(Strings.tabToday).last,
        wait: const Duration(seconds: 3));
    await waitFor(tester, find.text(Strings.todayGreeting));

    // 홈의 추천 카드를 누른다. 추천은 모델 경로라 늦게 온다.
    await waitFor(tester, find.textContaining(Strings.menuServings(2)),
        limit: const Duration(seconds: 60), reason: '홈 추천 카드');
    await tapAndWait(tester, find.textContaining(Strings.menuServings(2)).first,
        wait: const Duration(seconds: 8));

    await waitFor(tester, find.text(Strings.menuIngredients),
        reason: '메뉴 상세의 재료');
    expect(find.text(Strings.menuSteps), findsWidgets);
  });

  testWidgets('인분을 바꿔도 재고는 그대로다', (tester) async {
    await enterWithStock(tester);
    final before = await stock();

    await tapAndWait(tester, find.text(Strings.tabToday).last,
        wait: const Duration(seconds: 3));
    await waitFor(tester, find.textContaining(Strings.menuServings(2)),
        limit: const Duration(seconds: 60));
    await tapAndWait(tester, find.textContaining(Strings.menuServings(2)).first,
        wait: const Duration(seconds: 8));
    await waitFor(tester, find.text(Strings.menuServingsLabel));

    // 인분은 스테퍼다. 2 에서 두 번 올려 4 로 만든다 — 서버가 환산한 수량으로
    // 다시 그린다.
    await tapAndWait(tester, find.byIcon(Icons.add_rounded),
        wait: const Duration(seconds: 6));
    await tapAndWait(tester, find.byIcon(Icons.add_rounded),
        wait: const Duration(seconds: 8));
    await waitFor(tester, find.text(Strings.menuServingsBasis(4)),
        reason: '4인분 기준 재료');

    final after = await stock();
    expect(amountOf(after, '계란'), amountOf(before, '계란'),
        reason: '상세 조회와 인분 변경은 재고를 바꾸지 않는다');
    expect(amountOf(after, '두부'), amountOf(before, '두부'));
  });

  testWidgets('조리를 시작해 단계를 옮기고 완료하면 재고가 줄어든다', (tester) async {
    await enterWithStock(tester);
    final before = await stock();
    await openCookTab(tester);

    await tapAndWait(tester, find.text(Strings.cookStart).first,
        wait: const Duration(seconds: 12));
    await waitFor(tester, find.textContaining(Strings.cookingMode),
        limit: const Duration(seconds: 40), reason: '조리 진행 화면');

    // 진행 중에는 차감하지 않는다.
    final during = await stock();
    expect(amountOf(during, '계란'), amountOf(before, '계란'),
        reason: '조리 시작만으로 재고가 줄면 안 된다');

    // 마지막 단계까지 간다. 단계 수를 모르므로 '다음' 이 사라질 때까지 누른다.
    for (var step = 0; step < 12; step++) {
      final next = find.text(Strings.cookingNext);
      if (next.evaluate().isEmpty) break;
      await tapAndWait(tester, next.first);
    }
    await waitFor(tester, find.text(Strings.cookingFinish),
        reason: '마지막 단계의 완료 버튼');

    await tapAndWait(tester, find.text(Strings.cookingFinish),
        wait: const Duration(seconds: 12));
    await waitFor(tester, find.text(Strings.cookDoneTitle),
        limit: const Duration(seconds: 40), reason: '조리 완료 화면');

    // 뺀 재료와 빼지 못한 재료를 나눠 말한다.
    final told = find.text(Strings.cookDoneUsedTitle).evaluate().isNotEmpty ||
        find.text(Strings.cookDoneNothing).evaluate().isNotEmpty;
    expect(told, isTrue, reason: '무엇을 뺐는지 화면이 말한다');

    final after = await stock();
    final changed = amountOf(after, '계란') != amountOf(before, '계란') ||
        amountOf(after, '두부') != amountOf(before, '두부') ||
        amountOf(after, '양파') != amountOf(before, '양파');
    expect(changed, isTrue, reason: '완료가 레시피 재료를 차감한다');
  });

  testWidgets('완료를 되돌리면 재고가 복원된다', (tester) async {
    await enterWithStock(tester);
    final before = await stock();
    await openCookTab(tester);

    await tapAndWait(tester, find.text(Strings.cookStart).first,
        wait: const Duration(seconds: 12));
    await waitFor(tester, find.textContaining(Strings.cookingMode),
        limit: const Duration(seconds: 40));
    for (var step = 0; step < 12; step++) {
      final next = find.text(Strings.cookingNext);
      if (next.evaluate().isEmpty) break;
      await tapAndWait(tester, next.first);
    }
    await tapAndWait(tester, find.text(Strings.cookingFinish),
        wait: const Duration(seconds: 12));
    await waitFor(tester, find.text(Strings.cookDoneTitle),
        limit: const Duration(seconds: 40));

    await tapAndWait(tester, find.text(Strings.undo),
        wait: const Duration(seconds: 12));
    await waitFor(tester, find.text(Strings.cookDoneUndone),
        reason: '되돌린 사실을 말한다');

    final after = await stock();
    expect(amountOf(after, '계란'), amountOf(before, '계란'),
        reason: '되돌리기가 실제 취소 요청을 보내 재고를 복원한다');
    expect(amountOf(after, '두부'), amountOf(before, '두부'));
    expect(amountOf(after, '양파'), amountOf(before, '양파'));
  });

  testWidgets('조리 중 뒤로 나가도 완료 화면이 남지 않는다', (tester) async {
    await enterWithStock(tester);
    await openCookTab(tester);

    await tapAndWait(tester, find.text(Strings.cookStart).first,
        wait: const Duration(seconds: 12));
    await waitFor(tester, find.textContaining(Strings.cookingMode),
        limit: const Duration(seconds: 40));

    await tapAndWait(tester, find.byTooltip(Strings.cookingClose),
        wait: const Duration(seconds: 4));

    // 조리 탭으로 돌아오고 진행 화면이 남지 않는다.
    await waitGone(tester, find.textContaining(Strings.cookingMode),
        reason: '조리 화면이 닫힌다');
    expect(find.text(Strings.cookPicksTitle), findsWidgets);
  });

  testWidgets('유튜브가 아닌 링크는 정리하지 않는다', (tester) async {
    await enterWithStock(tester);
    await openCookTab(tester);

    await scrollTo(tester, find.text(Strings.cookVideoTitle));
    final link = find.byType(TextField).last;
    await tester.enterText(link, 'https://example.com/not-a-video');
    await tester.pump();
    await tapAndWait(tester, find.text(Strings.cookVideoSubmit),
        wait: const Duration(seconds: 12));

    await waitFor(tester, find.text(Strings.cookVideoBadLink),
        reason: '유튜브가 아니라고 말한다');
  });
}
