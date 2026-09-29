import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:today_meal/core/design/skin.dart';
import 'package:today_meal/core/design/tokens.dart';
import 'package:today_meal/core/settings/app_settings.dart';
import 'package:today_meal/domain/model/change_record.dart';
import 'package:today_meal/domain/model/inventory.dart';
import 'package:today_meal/domain/model/menu.dart';
import 'package:today_meal/domain/repository/repositories.dart';
import 'package:today_meal/ui/fridge/fridge_screen.dart';
import 'package:today_meal/ui/fridge/fridge_view_model.dart';
import 'package:today_meal/ui/history/history_screen.dart';
import 'package:today_meal/ui/history/history_view_model.dart';
import 'package:today_meal/ui/home/home_screen.dart';
import 'package:today_meal/ui/home/home_view_model.dart';
import 'package:today_meal/ui/mypage/mypage_screen.dart';
import 'package:today_meal/ui/splash/splash_screen.dart';

/// 화면이 **뜨기만 해도** 터지는 결함을 잡는다.
///
/// 실기기에서 두 번 겪었다. 스플래시는 `initState` 에서 `MediaQuery` 를 읽어 터졌고,
/// 권한 화면은 `Material` 조상 없이 잉크 효과를 써서 터졌다. 둘 다 화면을 한 번
/// 띄워 보기만 해도 드러난다.
///
/// 시각 디테일은 고정하지 않는다 — 목업이 바뀌면 같이 바뀌어야 하는 값들이다.
/// 여기서 보는 것은 **네 테마 모두에서 예외 없이 그려지는가**다.
void main() {
  for (final name in SkinName.values) {
    group('${name.name} 테마', () {
      testWidgets('오늘 화면이 뜬다', (tester) async {
        final home = HomeViewModel(inventory: _Inventory(), menu: _Menu());
        await home.load();
        await _pump(
          tester,
          name,
          ChangeNotifierProvider.value(
            value: home,
            child: HomeScreen(
              onOpenFridge: () {},
              onOpenMenu: (_) {},
              showVoiceBar: false,
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('냉장고 화면이 뜬다', (tester) async {
        final fridge = FridgeViewModel(inventory: _Inventory());
        await fridge.load();
        await _pump(
          tester,
          name,
          ChangeNotifierProvider.value(
            value: fridge,
            child: const FridgeScreen(),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('기록 화면이 뜬다', (tester) async {
        final history = HistoryViewModel(command: _Command());
        await history.load();
        await _pump(
          tester,
          name,
          ChangeNotifierProvider.value(
            value: history,
            child: const HistoryScreen(),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('마이페이지가 뜬다', (tester) async {
        await _pump(
          tester,
          name,
          ChangeNotifierProvider.value(
            value: AppSettings.memory(),
            child: MyPageScreen(onSignIn: () {}, onSignOut: () {}),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    });
  }

  testWidgets('스플래시가 뜨고 준비가 끝나면 넘어간다', (tester) async {
    var ready = false;
    await _pump(
      tester,
      SkinName.pastel,
      SplashScreen(onReady: () => ready = true),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(ready, isTrue, reason: '연출이 끝나면 다음 화면으로 넘어가야 한다');
  });

  testWidgets('모션 감소에서도 화면이 뜬다', (tester) async {
    // OS 가 움직임을 줄이라고 하면 반복 애니메이션을 멈춘다. 멈추는 경로에서
    // 컨트롤러를 잘못 다루면 이때만 터진다.
    final home = HomeViewModel(inventory: _Inventory(), menu: _Menu());
    await home.load();
    await _pump(
      tester,
      SkinName.pastel,
      ChangeNotifierProvider.value(
        value: home,
        child: HomeScreen(
          onOpenFridge: () {},
          onOpenMenu: (_) {},
          showVoiceBar: false,
        ),
      ),
      reduceMotion: true,
    );
    expect(tester.takeException(), isNull);
  });
}

/// 앱과 같은 겉껍질로 화면을 띄운다.
///
/// `SkinScope` 와 `MaterialApp` 을 함께 두는 것이 앱의 구조다. 테스트에서만 다른
/// 껍질을 쓰면 여기서 통과한 화면이 앱에서 터진다.
Future<void> _pump(
  WidgetTester tester,
  SkinName name,
  Widget child, {
  bool reduceMotion = false,
}) async {
  final skin = Skins.of(name);
  await tester.pumpWidget(
    SkinScope(
      skin: skin,
      child: MaterialApp(
        theme: buildTheme(skin),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: child,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

class _Inventory implements InventoryRepository {
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
          name: '계란',
          quantity: '10',
          unit: 'ea',
          certainty: QuantityCertainty.exact,
          storage: StorageLocation.unknown,
          freshness: Freshness.unknown,
        ),
      ];

  @override
  Future<List<PriorityBatch>> listPriorityBatches() async => const [];

  @override
  Future<FridgeCondition> condition() async => const FridgeCondition(
        condition: Condition.urgent,
        urgentCount: 1,
        soonCount: 0,
        expiredCount: 0,
        unknownQuantityCount: 0,
        totalCount: 2,
      );
}

class _Menu implements MenuRepository {
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
          availability: MenuAvailability.ready,
          priorityIngredients: ['두부'],
        ),
      ];

  @override
  Future<MenuDetail> detail(int recipeId, {int? servings}) async =>
      const MenuDetail(recipeId: 10, name: '두부조림', servings: 2, baseServings: 2);

  @override
  Future<CookedResult> markCooked(int suggestionId) async =>
      CookedResult(suggestionId: suggestionId, alreadyApplied: false);
}

class _Command implements CommandRepository {
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
          occurredAt: DateTime.now(),
          utterance: '계란 열 개 넣었어',
          spokenResponse: '계란 10개 등록했어요.',
        ),
      ];
}
