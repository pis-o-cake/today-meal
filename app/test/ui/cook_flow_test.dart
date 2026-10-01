import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:today_meal/core/design/skin.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/domain/model/change_record.dart';
import 'package:today_meal/domain/model/menu.dart';
import 'package:today_meal/domain/repository/repositories.dart';
import 'package:today_meal/ui/cook/cook_done_screen.dart';
import 'package:today_meal/ui/cook/cook_flow.dart';
import 'package:today_meal/ui/cook/cook_session.dart';
import 'package:today_meal/ui/cook/cooking_view_model.dart';

/// 조리 진행 → 완료 화면 전환.
///
/// 셸이 하는 배선(`push` → `pushReplacement` → `pop` → `dispose`)을 그대로 흉내낸다.
/// 화면이 바뀌는 순간의 ViewModel 수명이 이 테스트의 대상이다 — 닫힌 ViewModel 을 다시
/// 그리면 여기서 잡힌다.
void main() {
  testWidgets('완료를 누르면 완료 화면으로 넘어가고 예외가 없다', (tester) async {
    await _pumpCook(tester);

    await tester.tap(find.text(Strings.cookingFinish));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.byType(CookDoneScreen), findsOneWidget);
  });

  testWidgets('완료 화면을 닫아도 예외가 없다', (tester) async {
    await _pumpCook(tester);

    await tester.tap(find.text(Strings.cookingFinish));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text(Strings.cookDoneConfirm));
    // 닫는 애니메이션이 도는 동안 ViewModel 이 닫힌다. 그 사이 다시 그리면 터진다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpCook(WidgetTester tester) async {
  final plan = CookPlan(
    name: '두부조림',
    servings: 2,
    suggestionId: 7,
    steps: const [CookStep(text: '두부를 썬다'), CookStep(text: '조린다')],
  );

  final skin = Skins.of(SkinName.pastel);
  await tester.pumpWidget(
    SkinScope(
      skin: skin,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => _runCook(context, plan),
                child: const Text('시작'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('시작'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));

  // 마지막 단계에서만 완료 버튼이 뜬다.
  final cooking = tester
      .element(find.byType(CookFlow))
      .read<CookingViewModel>();
  cooking.goTo(plan.total - 1);
  await tester.pump();
}

/// 셸의 `_runCook` 과 같은 배선. ViewModel 의 주인은 route 다.
Future<void> _runCook(BuildContext context, CookPlan plan) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => CookingViewModel(
          plan: plan,
          menu: _Menu(),
          command: _Command(),
        ),
        child: CookFlow(plan: plan),
      ),
    ),
  );
}

class _Menu implements MenuRepository {
  @override
  Future<List<MenuSuggestion>> createSuggestions({
    int? servings,
    int? maxMinutes,
    List<String> focus = const [],
  }) async =>
      const [];

  @override
  Future<MenuDetail> detail(int recipeId, {int? servings}) async =>
      const MenuDetail(recipeId: 1, name: '두부조림', servings: 2, baseServings: 2);

  @override
  Future<CookedResult> markCooked(int suggestionId, {int? servings}) async =>
      CookedResult(
        suggestionId: suggestionId,
        alreadyApplied: false,
        undoToken: 'cmd-1',
      );
}

class _Command implements CommandRepository {
  @override
  Future<CommandOutcome> undo(String commandId) async => const CommandOutcome(
        commandId: 'x',
        status: 'applied',
        intent: 'consume',
      );

  @override
  Future<CommandOutcome> interpret({
    required String commandId,
    required String utterance,
    String? follows,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<ChangeRecord>> history({int limit = 50, DateTime? on}) async =>
      const [];

  @override
  Future<List<DateTime>> historyDays({int limit = 60}) async => const [];
}
