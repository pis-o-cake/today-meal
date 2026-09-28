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

  testWidgets('홈 화면이 밴드와 메뉴를 그린다', (tester) async {
    final home = HomeViewModel(inventory: _FakeInventory(), menu: _FakeMenu());
    await home.load();

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: ChangeNotifierProvider.value(
          value: home,
          child: const Scaffold(body: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('두부'), findsWidgets);
    expect(find.text('두부조림'), findsOneWidget);
    // 필수 재료가 없는 메뉴는 '지금 가능' 이 아니다.
    expect(find.text('재료 준비 후'), findsOneWidget);
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
