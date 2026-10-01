/// 시연 시나리오를 그 순서 그대로 실기기에서 돌린다.
///
/// 발표에서 보여줄 흐름 하나를 처음부터 끝까지 이어서 확인한다. 낱낱의 기능은 앞선
/// 스위트들이 보므로, 여기서 보는 것은 **그 순서대로 했을 때 걸리는 곳이 없는가**다.
///
/// ```
/// 게스트 진입
///   → "계란 열 개 넣었어, 소비기한 10월 5일까지야"
///   → "삼겹살 300그램 넣었어, 소비기한 10월 3일까지야"
///   → "두부 두 모 넣었어"           (기한을 안 말해 되묻기 → 답)
///   → "대파 한 단 넣었어"           (기한은 모름으로 남김)
///   → 냉장고에서 넷을 확인
///   → "삼겹살로 뭐 해먹을까?"       (지목 추천 → 조리 탭 목록)
///   → 메뉴 상세에서 2인분 → 4인분   (재료 수량 재환산)
/// ```
///
/// 소리만 가짜다([fake_voice.dart]). 서버 왕복·화면 전환·재고 변경은 모두 실제다.
///
/// WARNING: 기한은 **오늘 기준으로 만든다.** 시연 날짜를 코드에 박으면 그 날이 지나면
/// 기한이 지난 재료가 되어 요리 후보에서 빠진다.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:today_meal/core/di.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/domain/model/inventory.dart';
import 'package:today_meal/domain/repository/repositories.dart';
import 'package:today_meal/ui/cook/cook_view_model.dart';

import 'harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 시연에서 쓸 기한. 삼겹살이 가장 급하고 계란은 여유가 있다.
  final soon = DateTime.now().add(const Duration(days: 3));
  final sooner = DateTime.now().add(const Duration(days: 1));
  final middle = DateTime.now().add(const Duration(days: 2));

  String said(DateTime date) => '${date.month}월 ${date.day}일';

  Future<List<IngredientBatch>> stock() => di<InventoryRepository>().listBatches();

  double amountOf(List<IngredientBatch> batches, String name) => batches
      .where((batch) => batch.name == name)
      .fold(0, (sum, batch) => sum + (double.tryParse(batch.quantity ?? '') ?? 0));

  IngredientBatch? batchOf(List<IngredientBatch> batches, String name) =>
      batches.where((batch) => batch.name == name).firstOrNull;

  /// 한 번 말한다. 호출 → 듣기 → 반영 → 대기 복귀까지 기다린다.
  ///
  /// WARNING: 큐를 **비우고** 넣는다. 앞선 발화에서 쓰이지 않은 말이 남아 있으면 다음
  /// 차례에 그것이 먼저 전사돼 엉뚱한 결과가 나온다.
  Future<void> speak(
    WidgetTester tester,
    FakeVoice voice,
    String utterance,
  ) async {
    voice.transcriber.queue
      ..clear()
      ..add(utterance);
    voice.detector.callOut();
    await waitFor(tester, find.text(Strings.voiceHeroListening),
        reason: '듣기 화면: $utterance');
    // 반영까지 간다. 되묻기가 끼면 그 화면도 지나간다.
    await waitFor(tester, appliedResult(),
        limit: const Duration(seconds: 60), reason: '반영 결과: $utterance');
    // 손대지 않고 기다린다. 결과는 최소 표시 시간과 낭독이 끝나면 스스로 닫히고 대기로
    // 돌아간다 — 시연에서도 이 동작을 보여준다. 버튼을 누르면 겹친 알약을 잘못 짚는다.
    await waitGone(tester, appliedResult(),
        limit: const Duration(seconds: 40), reason: '대기로 복귀: $utterance');
  }

  testWidgets('시연 시나리오: 재료 넷을 말로 넣고 삼겹살로 추천받아 인분을 바꾼다',
      (tester) async {
    final voice = fakeVoice();
    await launchApp(tester, voice: voice);

    // --- 진입 -------------------------------------------------------------
    await waitFor(tester, find.text(Strings.loginGuest));
    await tapAndWait(tester, find.text(Strings.loginGuest));
    await waitFor(tester, find.text(Strings.permissionSkip), reason: '권한 안내');
    await tapAndWait(tester, find.text(Strings.permissionSkip),
        wait: const Duration(seconds: 4));
    await waitFor(tester, find.text(Strings.tabFridge), reason: '홈');
    await clearFridge();

    // --- 재료 넷 ----------------------------------------------------------
    await speak(tester, voice, '계란 열 개 넣었어 소비기한은 ${said(soon)}까지야');
    await speak(tester, voice, '삼겹살 300그램 넣었어 소비기한은 ${said(sooner)}까지야');
    await speak(tester, voice, '두부 두 모 넣었어 소비기한은 ${said(middle)}까지야');
    // 기한을 말하지 않는다. 지어내지 않고 모름으로 남아야 한다.
    await speak(tester, voice, '대파 한 단 넣었어');

    final after = await stock();
    expect(amountOf(after, '계란'), 10, reason: '계란 10개');
    expect(amountOf(after, '삼겹살'), 300, reason: '삼겹살 300g');
    expect(amountOf(after, '두부'), 2, reason: '두부 2모');
    expect(amountOf(after, '대파'), 1, reason: '대파 1단');

    // 말한 단위가 그대로 남는다. 300 을 3 으로 읽거나 개로 바꾸지 않는다.
    expect(batchOf(after, '삼겹살')?.unit, 'g');
    // 말하지 않은 기한을 지어내지 않는다.
    expect(batchOf(after, '대파')?.dates, isEmpty,
        reason: '대파는 기한을 말하지 않았다');
    expect(batchOf(after, '삼겹살')?.dates, isNotEmpty,
        reason: '삼겹살은 말한 기한이 남는다');

    // --- 냉장고 ----------------------------------------------------------
    await tapAndWait(tester, find.text(Strings.tabFridge).last,
        wait: const Duration(seconds: 6));
    await waitFor(tester, find.byTooltip(Strings.fridgeSearch),
        reason: '냉장고 화면');
    for (final name in ['계란', '삼겹살', '두부', '대파']) {
      expect(find.text(name), findsWidgets, reason: '$name 타일');
    }
    // 기한을 모르는 재료는 숫자를 만들지 않고 말해 달라고 한다.
    expect(find.text(Strings.dateTellPlease), findsWidgets);

    // --- 삼겹살로 뭐 해먹을까 --------------------------------------------
    voice.transcriber.queue.add('삼겹살로 뭐 해먹을까?');
    voice.detector.callOut();
    await waitFor(tester, find.text(Strings.voiceHeroListening),
        reason: '듣기 화면: 추천 요청');

    // 대화가 끝난 뒤 조리 탭이 열리고 추천이 온다. 지목했어도 **고르는 것은 사용자**다.
    await waitFor(tester, find.text(Strings.cookPicksTitle),
        limit: const Duration(seconds: 90), reason: '조리 탭');
    await waitFor(tester, find.text(Strings.cookStart),
        limit: const Duration(seconds: 90), reason: '추천 후보');
    expect(find.textContaining(Strings.cookingMode), findsNothing,
        reason: '묻자마자 조리 화면으로 들어가면 무엇을 만들지 볼 수 없다');

    // 지목한 재료를 쓰는 후보가 왔다.
    expect(di<CookViewModel>().focus, ['삼겹살']);
    expect(find.text(Strings.cookPicksEmpty), findsNothing);

    // --- 메뉴 상세와 인분 환산 -------------------------------------------
    // 후보 카드를 눌러 상세를 연다. 카드의 메타가 인분·시간을 담고 있다.
    await tapAndWait(tester, find.textContaining(Strings.menuServings(2)).first,
        wait: const Duration(seconds: 10));
    await waitFor(tester, find.text(Strings.menuIngredients),
        limit: const Duration(seconds: 40), reason: '메뉴 상세의 재료');
    expect(find.text(Strings.menuServingsBasis(2)), findsWidgets,
        reason: '2인분 기준으로 먼저 보여준다');

    final beforeServings = await stock();

    // 4 인분으로 올린다. 서버가 재료 수량을 다시 환산해 준다.
    await tapAndWait(tester, find.byIcon(Icons.add_rounded),
        wait: const Duration(seconds: 6));
    await tapAndWait(tester, find.byIcon(Icons.add_rounded),
        wait: const Duration(seconds: 8));
    await waitFor(tester, find.text(Strings.menuServingsBasis(4)),
        limit: const Duration(seconds: 40), reason: '4인분 기준 재료');

    // 조회와 인분 변경은 재고를 바꾸지 않는다.
    expect(amountOf(await stock(), '삼겹살'), amountOf(beforeServings, '삼겹살'));
    expect(amountOf(await stock(), '계란'), amountOf(beforeServings, '계란'));
  });
}
