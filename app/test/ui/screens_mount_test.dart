import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:today_meal/core/design/labels.dart';
import 'package:today_meal/core/design/skin.dart';
import 'package:today_meal/core/design/tokens.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/core/settings/app_settings.dart';
import 'package:today_meal/domain/model/change_record.dart';
import 'package:today_meal/domain/model/inventory.dart';
import 'package:today_meal/domain/model/menu.dart';
import 'package:today_meal/domain/repository/repositories.dart';
import 'package:today_meal/ui/cook/cook_done_screen.dart';
import 'package:today_meal/ui/cook/cook_home_screen.dart';
import 'package:today_meal/ui/cook/cook_session.dart';
import 'package:today_meal/ui/cook/cook_view_model.dart';
import 'package:today_meal/ui/cook/cooking_screen.dart';
import 'package:today_meal/ui/cook/cooking_view_model.dart';
import 'package:today_meal/ui/fridge/fridge_screen.dart';
import 'package:today_meal/ui/fridge/item_add_screen.dart';
import 'package:today_meal/ui/fridge/item_add_view_model.dart';
import 'package:today_meal/ui/fridge/item_detail_screen.dart';
import 'package:today_meal/ui/fridge/item_detail_view_model.dart';
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
  group('재료 상세의 수량', () {
    Future<ItemDetailViewModel> open() async {
      final batches = await _Inventory().listBatches();
      return ItemDetailViewModel(batch: batches.first, inventory: _Inventory());
    }

    test('직접 적은 수를 받는다', () async {
      final item = await open();

      expect(item.setQuantity('300'), isTrue);
      expect(item.quantity, '300');
      expect(item.setQuantity(' 0.5 '), isTrue);
      expect(item.quantity, '0.5');
      // `3.0` 으로 남기면 서버가 준 `3` 과 달라 보인다.
      expect(item.setQuantity('3.0'), isTrue);
      expect(item.quantity, '3');
    });

    test('수가 아니거나 음수면 바꾸지 않는다', () async {
      final item = await open();
      final before = item.quantity;

      expect(item.setQuantity('많이'), isFalse);
      expect(item.setQuantity('-2'), isFalse);
      expect(item.setQuantity(''), isFalse);
      expect(item.quantity, before);
    });

    test('소수 잔량도 하나씩 올리고 내린다', () async {
      final item = await open()
        ..setQuantity('1.5');

      item.increment();
      expect(item.quantity, '2.5');
      item
        ..decrement()
        ..decrement();
      expect(item.quantity, '0.5');
      item.decrement();
      expect(item.quantity, '0', reason: '0 아래로 내려가지 않는다');
    });
  });

  group('재료 넣기', () {
    test('이름과 0 보다 큰 수량이 있어야 넣을 수 있다', () {
      final item = ItemAddViewModel(inventory: _Inventory());
      expect(item.ready, isFalse);

      item.setName('두부');
      expect(item.ready, isFalse, reason: '서버는 잔량 없는 묶음을 저장하지 않는다');
      item.setQuantity('0');
      expect(item.ready, isFalse);
      item.setQuantity('2');
      expect(item.ready, isTrue);
      item.setName('  ');
      expect(item.ready, isFalse);
    });

    test('고른 값을 그대로 보내고, 실패한 재시도는 같은 요청 ID 로 간다', () async {
      final inventory = _Inventory()..failing = true;
      final item = ItemAddViewModel(inventory: inventory)
        ..setName(' 우유 ')
        ..setQuantity('1')
        ..selectUnit('l')
        ..selectStorage(StorageLocation.freezer)
        ..selectDateKind(DateKind.sellBy)
        ..selectDate(DateTime(2026, 10, 3, 15));

      await item.save();
      expect(item.added, isNull, reason: '실패하면 넣은 것처럼 닫지 않는다');
      expect(item.error, isNotNull);

      inventory.failing = false;
      await item.save();
      expect(item.added, isNotNull);
      expect(inventory.added, hasLength(2));
      expect(inventory.added.first.commandId, inventory.added.last.commandId);
      expect(inventory.added.last.toJson(), {
        'command_id': inventory.added.last.commandId,
        'name': '우유',
        'quantity': '1',
        'unit': 'l',
        'storage_location': 'freezer',
        'date_kind': 'sell_by',
        'date_value': '2026-10-03',
      });
    });
  });

  group('냉장고 비우기', () {
    test('실패한 재시도는 같은 요청 ID 로 가고, 성공하면 버린 수를 돌려준다', () async {
      final inventory = _Inventory()..failing = true;
      final fridge = FridgeViewModel(inventory: inventory);

      expect(await fridge.discardAll(), isNull);
      inventory.failing = false;
      expect(await fridge.discardAll(), 2);

      expect(inventory.emptied, hasLength(2));
      expect(inventory.emptied.first, inventory.emptied.last);
      expect(fridge.emptying, isFalse);
    });
  });

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

      testWidgets('조리 탭에서 추천을 새로 받는다', (tester) async {
        // 추천은 한 번 받으면 다시 부르지 않는다. 재고를 바꾼 뒤 새로 받을 길이 있어야 한다.
        final menu = _Menu();
        final cook = CookViewModel(menu: menu, video: _Video());
        await cook.loadPicks();
        await _pump(
          tester,
          name,
          ChangeNotifierProvider.value(
            value: cook,
            child: CookHomeScreen(onStart: (_) {}, onOpenMenu: (_) {}),
          ),
        );
        expect(menu.asked, 1);

        await tester.tap(find.byTooltip(Strings.cookPicksRefresh));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(menu.asked, 2);
        expect(find.text('두부조림'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('조리 탭이 뜬다', (tester) async {
        final cook = CookViewModel(menu: _Menu(), video: _Video());
        await cook.loadPicks();
        await _pump(
          tester,
          name,
          ChangeNotifierProvider.value(
            value: cook,
            child: CookHomeScreen(onStart: (_) {}, onOpenMenu: (_) {}),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('조리 진행이 뜬다', (tester) async {
        final cooking = CookingViewModel(
          plan: _plan,
          menu: _Menu(),
          command: _Command(),
        );
        addTearDown(cooking.dispose);
        await _pump(
          tester,
          name,
          ChangeNotifierProvider.value(
            value: cooking,
            child: CookingScreen(onDone: () {}),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('조리 완료가 뺀 재료와 못 뺀 재료를 나눠 보여준다', (tester) async {
        // 못 뺀 재료만 "잔량 미확인"으로 나열해, 뺀 것이 미확인인 것처럼 읽혔다.
        await _pump(
          tester,
          name,
          CookDoneScreen(
            plan: _plan,
            result: const CookedResult(
              suggestionId: 1,
              alreadyApplied: false,
              changes: [
                CookedChange(name: '삼겹살', before: '300', after: '100', unit: 'g'),
              ],
              skippedIngredients: ['대파'],
            ),
            minutes: 17,
            onClose: () {},
          ),
        );

        expect(find.text('삼겹살'), findsOneWidget);
        expect(find.text(Strings.cookDoneDelta('300g', '100g')), findsOneWidget);
        expect(find.text('대파'), findsOneWidget);
        expect(find.text(Strings.cookDoneSkipped), findsOneWidget);
        expect(find.text(Strings.quantityUnknown), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('조리 완료가 뜬다', (tester) async {
        await _pump(
          tester,
          name,
          CookDoneScreen(
            plan: _plan,
            result: const CookedResult(suggestionId: 1, alreadyApplied: false),
            minutes: 17,
            onClose: () {},
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('재료 상세에서 수량을 직접 적는다', (tester) async {
        // 그램은 하나씩 올리고 내려서는 맞출 수 없다.
        final batches = await _Inventory().listBatches();
        final item = ItemDetailViewModel(
          batch: batches.first,
          inventory: _Inventory(),
        );
        await _pump(
          tester,
          name,
          ChangeNotifierProvider.value(
            value: item,
            child: ItemDetailScreen(onClosed: () {}),
          ),
        );

        // 수량 칸의 숫자를 누른다. 같은 글이 머리말에도 있을 수 있어 마지막 것을 고른다.
        final shown = '${item.quantity}${Labels.unit(item.batch.unit)}';
        await tester.ensureVisible(find.text(shown).last);
        await tester.tap(find.text(shown).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.enterText(find.byType(TextField), '250.5');
        await tester.tap(find.text(Strings.confirm));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(item.quantity, '250.5');
        expect(item.dirty, isTrue);
        expect(tester.takeException(), isNull);
      });

      testWidgets('재료 상세가 뜬다', (tester) async {
        final batches = await _Inventory().listBatches();
        await _pump(
          tester,
          name,
          ChangeNotifierProvider.value(
            value: ItemDetailViewModel(
              batch: batches.first,
              inventory: _Inventory(),
            ),
            child: ItemDetailScreen(onClosed: () {}),
          ),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('재료 넣기가 뜬다', (tester) async {
        var added = false;
        final item = ItemAddViewModel(inventory: _Inventory());
        await _pump(
          tester,
          name,
          ChangeNotifierProvider.value(
            value: item,
            child: ItemAddScreen(onAdded: () => added = true),
          ),
        );
        expect(tester.takeException(), isNull);

        await tester.enterText(find.byType(TextField).first, '두부');
        await tester.enterText(find.byType(TextField).at(1), '2');
        // 적은 값으로 넣기 버튼이 열린다. 한 프레임을 그려야 눌린다.
        await tester.pump();
        await tester.tap(find.text(Strings.addSave));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(item.added, isNotNull);
        expect(added, isTrue, reason: '넣으면 냉장고와 오늘 화면을 다시 읽게 알린다');
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
    // WARNING: `pumpAndSettle` 은 캐릭터의 끝없는 움직임 때문에 영원히 기다린다.
    // 연출은 화면에 그려진 뒤에 시작하는데, 시험 환경은 래스터를 보고하지 않아 그
    // 기다림이 상한(4초)에 걸린다. 상한과 연출(1.8초)을 합친 것보다 넉넉히 흘려 보낸다.
    await tester.pump(const Duration(seconds: 5));
    // 연출은 빌드가 끝난 **다음 프레임**에 시작한다 — 준비 작업이 ViewModel 을
    // 건드리므로 빌드 중에 부르면 프레임워크가 막는다. 그 한 프레임을 흘린다.
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
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
    // 설정은 어느 화면에서나 읽을 수 있어야 한다 — 냉장고 타일이 기한 알림을 본다.
    ChangeNotifierProvider.value(
      value: AppSettings.memory(),
      child: SkinScope(
        skin: skin,
        child: MaterialApp(
          theme: buildTheme(skin),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

class _Inventory implements InventoryRepository {
  /// 넣은 재료. 재시도가 같은 요청 ID 로 가는지 본다.
  final added = <BatchDraft>[];

  /// 비우기의 요청 ID.
  final emptied = <String?>[];

  /// 참이면 서버에 닿지 못한 것처럼 실패한다. 실패해도 요청은 기록한다.
  bool failing = false;

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

  /// 이 시험은 고치기를 쓰지 않는다. 불리면 시험이 잘못된 것이다.
  @override
  Future<IngredientBatch> editBatch(int batchId, BatchEdit edit) async =>
      throw UnimplementedError();

  @override
  Future<void> discardBatch(int batchId, {String? commandId}) async => throw UnimplementedError();

  @override
  Future<IngredientBatch> addBatch(BatchDraft draft) async {
    added.add(draft);
    if (failing) throw Exception('connection refused');
    return IngredientBatch(
      batchId: 99,
      ingredientId: 99,
      name: draft.name,
      quantity: draft.quantity,
      unit: draft.unit,
      certainty: QuantityCertainty.exact,
      storage: draft.storage,
      freshness: Freshness.unknown,
    );
  }

  @override
  Future<int> discardAll({String? commandId}) async {
    emptied.add(commandId);
    if (failing) throw Exception('connection refused');
    return (await listBatches()).length;
  }
}

class _Menu implements MenuRepository {
  /// 추천을 받은 횟수.
  int asked = 0;

  @override
  Future<List<MenuSuggestion>> createSuggestions({
    int? servings,
    int? maxMinutes,
    List<String> focus = const [],
  }) async {
    asked += 1;
    return const [
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
  }

  @override
  Future<MenuDetail> detail(int recipeId, {int? servings}) async =>
      const MenuDetail(recipeId: 10, name: '두부조림', servings: 2, baseServings: 2);

  @override
  Future<CookedResult> markCooked(int suggestionId, {int? servings}) async =>
      CookedResult(suggestionId: suggestionId, alreadyApplied: false);
}

class _Command implements CommandRepository {
  @override
  Future<CommandOutcome> interpret({
    required String commandId,
    required String utterance,
    String? follows,
  }) async =>
      const CommandOutcome(commandId: 'x', status: 'applied', intent: 'register');

  @override
  Future<CommandOutcome> undo(String commandId) async =>
      const CommandOutcome(commandId: 'x', status: 'applied', intent: 'cancel');

  @override
  Future<List<ChangeRecord>> history({int limit = 50, DateTime? on}) async => [
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

  @override
  Future<List<DateTime>> historyDays({int limit = 60}) async => const [];
}

/// 조리 한 판. 타이머가 있는 단계와 없는 단계를 섞는다 — 둘의 그림이 다르다.
final _plan = CookPlan(
  name: '두부계란전',
  servings: 2,
  suggestionId: 1,
  steps: const [
    CookStep(text: '두부를 1cm 두께로 썰어요', ingredients: ['두부 1모']),
    CookStep(
        text: '키친타월에 올려 물기를 빼요',
        timerSeconds: 180,
        timerLabel: '물기 빼기'),
  ],
);

class _Video implements VideoRepository {
  @override
  Future<VideoRecipe> analyze(String url) async =>
      throw const VideoException(VideoFailure.unreachable);
}
