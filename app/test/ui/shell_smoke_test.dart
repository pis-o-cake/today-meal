import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:today_meal/core/design/tokens.dart';
import 'package:today_meal/domain/model/change_record.dart';
import 'package:today_meal/domain/model/inventory.dart';
import 'package:today_meal/domain/model/menu.dart';
import 'package:today_meal/domain/repository/repositories.dart';
import 'package:today_meal/ui/fridge/fridge_view_model.dart';
import 'package:today_meal/ui/history/history_view_model.dart';
import 'package:today_meal/ui/home/home_screen.dart';
import 'package:today_meal/ui/home/home_view_model.dart';

/// 화면이 실제 데이터로 그려지는지 확인한다.
///
/// UI 는 계속 바뀌므로 시각 디테일을 고정하지 않는다. **구조가 무너지지 않는지**만 본다 —
/// 신선도 밴드로 묶이는가, 잔량 미확인이 별도로 드러나는가, 필수 재료가 없는 메뉴가
/// '지금 가능' 으로 표시되지 않는가.
void main() {
  testWidgets('신선도 밴드가 급한 것부터 쌓인다', (tester) async {
    final vm = HomeViewModel(
      inventory: _FakeInventory(),
      menu: _FakeMenu(),
    );
    await vm.load();

    final grades = vm.bands.map((b) => b.grade).toList();
    expect(grades, [Freshness.urgent, Freshness.soon, Freshness.unknown]);
    // 빈 밴드는 내보내지 않는다.
    expect(grades, isNot(contains(Freshness.fresh)));
  });

  testWidgets('홈 화면이 가장 급한 등급을 펼치고 그 메뉴를 권한다', (tester) async {
    final home = HomeViewModel(inventory: _FakeInventory(), menu: _FakeMenu());
    await home.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ChangeNotifierProvider.value(
          value: home,
          child: Scaffold(
            body: HomeScreen(
              onOpenFridge: () {},
              onOpenMenu: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 고르지 않으면 가장 급한 등급이 잡힌다.
    expect(home.selected, Freshness.urgent);
    expect(find.text('급함'), findsOneWidget);
    expect(find.text('오늘 안에 쓰세요'), findsNothing,
        reason: '등급 힌트는 개수와 한 줄로 합쳐 나온다');
    expect(find.textContaining('오늘 안에 쓰세요'), findsOneWidget);

    // 고른 등급의 재료만 칩으로 나온다. 다른 등급은 아치의 배지로만 센다.
    // 단위는 한국어 표기로 나와야 한다 — 'mo' 가 그대로 보이면 안 된다.
    expect(find.text('두부 · 2모 · D-1'), findsOneWidget);
    expect(find.textContaining('대파'), findsNothing);

    // 주 행동은 그 등급으로 만들 메뉴다.
    expect(find.text('두부조림'), findsOneWidget);
  });

  testWidgets('등급을 고르면 화면이 그 등급으로 바뀐다', (tester) async {
    final home = HomeViewModel(inventory: _FakeInventory(), menu: _FakeMenu());
    await home.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ChangeNotifierProvider.value(
          value: home,
          child: Scaffold(
            body: HomeScreen(onOpenFridge: () {}, onOpenMenu: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    home.select(Freshness.soon);
    await tester.pumpAndSettle();

    expect(find.text('챙길 것'), findsOneWidget);
    expect(find.text('대파 · 1단 · D-2'), findsOneWidget);
    expect(find.text('두부 · 2모 · D-1'), findsNothing);
  });

  testWidgets('재고를 읽지 못하면 빈 냉장고로 그리지 않는다', (tester) async {
    // 서버가 끊긴 것을 "여유 0가지" 로 그리면 사용자는 냉장고가 빈 것으로 읽는다.
    final home = HomeViewModel(inventory: _BrokenInventory(), menu: _FakeMenu());
    await home.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ChangeNotifierProvider.value(
          value: home,
          child: Scaffold(
            body: HomeScreen(onOpenFridge: () {}, onOpenMenu: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('서버에 연결할 수 없어요'), findsOneWidget);
    expect(find.text('여유'), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  test('재료가 없는 등급에는 메뉴를 권하지 않는다', () async {
    // 서버 추천은 냉장고 전체를 보고 만들어진다. 그냥 첫 번째를 꺼내면
    // "챙길 것 0가지" 옆에 메뉴가 떠서 무엇으로 만든다는 것인지 알 수 없다.
    final vm = HomeViewModel(inventory: _FakeInventory(), menu: _FakeMenu());
    await vm.load();

    vm.select(Freshness.fresh); // 이 등급에는 재료가 없다
    expect(vm.counts[Freshness.fresh], 0);
    expect(vm.topMenu, isNull);
    expect(vm.otherMenuCount, 0);
  });

  test('그 등급의 재료를 쓰는 메뉴만 권한다', () async {
    final vm = HomeViewModel(inventory: _FakeInventory(), menu: _FakeMenu());
    await vm.load();

    vm.select(Freshness.urgent); // 두부
    expect(vm.topMenu?.name, '두부조림');
  });

  test('아치는 빈 등급도 0 으로 세어 자리를 지킨다', () async {
    // 목록([bands])은 빈 등급을 빼지만 아치는 위치가 고정이라 빼지 못한다.
    final vm = HomeViewModel(inventory: _FakeInventory(), menu: _FakeMenu());
    await vm.load();

    expect(vm.counts.length, 5);
    expect(vm.counts[Freshness.fresh], 0);
    expect(vm.counts[Freshness.urgent], 1);
  });

  test('잔량 미확인이 신선도와 섞이지 않는다', () async {
    final vm = HomeViewModel(inventory: _FakeInventory(), menu: _FakeMenu());
    await vm.load();
    final unknownBand =
        vm.bands.firstWhere((b) => b.grade == Freshness.unknown);
    expect(unknownBand.batches.single.quantityUncertain, isTrue);
  });

  test('추천 실패가 재고 표시를 막지 않는다', () async {
    final vm = HomeViewModel(inventory: _FakeInventory(), menu: _FailingMenu());
    await vm.load();
    expect(vm.bands, isNotEmpty);
    expect(vm.menus, isEmpty);
    expect(vm.error, isNull);
  });

  test('냉장고 검색과 보관 필터가 함께 걸린다', () async {
    final vm = FridgeViewModel(inventory: _FakeInventory());
    await vm.load();
    expect(vm.visible.length, 3);

    vm.search('두부');
    expect(vm.visible.single.name, '두부');

    vm.search('');
    vm.filterStorage(StorageLocation.freezer);
    expect(vm.visible, isEmpty);
  });

  test('이력이 상태 변경의 잔량 칸을 비운다', () async {
    final vm = HistoryViewModel(command: _FakeCommand());
    await vm.load();
    final state = vm.records.firstWhere((r) => r.kind == HistoryKind.state);
    expect(state.changesQuantity, isFalse);
  });
}

class _FakeInventory implements InventoryRepository {
  @override
  Future<List<IngredientBatch>> listBatches() async => const [
        IngredientBatch(
          batchId: 1,
          ingredientId: 1,
          name: '두부',
          quantity: '2',
          unit: 'mo',
          certainty: QuantityCertainty.exact,
          storage: StorageLocation.fridge,
          freshness: Freshness.urgent,
          daysLeft: 1,
          expiryKind: DateKind.useBy,
        ),
        IngredientBatch(
          batchId: 2,
          ingredientId: 2,
          name: '대파',
          quantity: '1',
          unit: 'bunch',
          certainty: QuantityCertainty.exact,
          storage: StorageLocation.fridge,
          freshness: Freshness.soon,
          daysLeft: 2,
          expiryKind: DateKind.bestBefore,
        ),
        IngredientBatch(
          batchId: 3,
          ingredientId: 3,
          name: '김치',
          qualitativeAmount: '조금',
          certainty: QuantityCertainty.qualitative,
          storage: StorageLocation.fridge,
          freshness: Freshness.unknown,
          quantityUncertain: true,
        ),
      ];

  @override
  Future<List<PriorityBatch>> listPriorityBatches() async => const [];

  @override
  Future<FridgeCondition> condition() async => const FridgeCondition(
        condition: Condition.urgent,
        urgentCount: 1,
        soonCount: 1,
        expiredCount: 0,
        unknownQuantityCount: 1,
        totalCount: 3,
      );
}

/// 서버가 끊긴 상황.
class _BrokenInventory implements InventoryRepository {
  @override
  Future<List<IngredientBatch>> listBatches() async =>
      throw Exception('connection refused');

  @override
  Future<List<PriorityBatch>> listPriorityBatches() async =>
      throw Exception('connection refused');

  @override
  Future<FridgeCondition> condition() async =>
      throw Exception('connection refused');
}

class _FakeMenu implements MenuRepository {
  @override
  Future<List<MenuSuggestion>> createSuggestions({
    int? servings,
    int? maxMinutes,
  }) async =>
      const [
        MenuSuggestion(
          suggestionId: 1,
          recipeId: 10,
          name: '두부조림',
          servings: 2,
          estimatedMinutes: 20,
          reason: '두부가 내일까지예요.',
          availability: MenuAvailability.needsPurchase,
          priorityIngredients: ['두부'],
          missingIngredients: ['고춧가루'],
        ),
      ];

  @override
  Future<MenuDetail> detail(int recipeId, {int? servings}) async =>
      const MenuDetail(recipeId: 10, name: '두부조림', servings: 2, baseServings: 2);

  @override
  Future<CookedResult> markCooked(int suggestionId) async =>
      CookedResult(suggestionId: suggestionId, alreadyApplied: false);
}

class _FailingMenu implements MenuRepository {
  @override
  Future<List<MenuSuggestion>> createSuggestions({
    int? servings,
    int? maxMinutes,
  }) async =>
      throw StateError('upstream 502');

  @override
  Future<MenuDetail> detail(int recipeId, {int? servings}) async =>
      throw StateError('upstream 502');

  @override
  Future<CookedResult> markCooked(int suggestionId) async =>
      throw StateError('upstream 502');
}

class _FakeCommand implements CommandRepository {
  @override
  Future<CommandOutcome> interpret({
    required String commandId,
    required String utterance,
  }) async =>
      const CommandOutcome(commandId: 'x', status: 'applied', intent: 'register');

  @override
  Future<CommandOutcome> undo(String commandId) async =>
      const CommandOutcome(commandId: 'x', status: 'applied', intent: 'cancel');

  @override
  Future<List<ChangeRecord>> history({int limit = 50}) async => [
        ChangeRecord(
          kind: HistoryKind.quantity,
          action: 'stock_in',
          name: '계란',
          batchId: 1,
          quantityAfter: '10',
          unit: 'ea',
          occurredAt: DateTime(2026, 9, 28, 19, 2),
        ),
        ChangeRecord(
          kind: HistoryKind.state,
          action: 'opened',
          name: '우유',
          batchId: 2,
          occurredAt: DateTime(2026, 9, 28, 19, 5),
        ),
      ];
}
