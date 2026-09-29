/// 탭 셸.
///
/// 목업의 탭 다섯이다 — 뭐 먹지? · 냉장고 · 조리 · 기록 · 마이페이지. 태블릿 폭에서는 하단
/// 바 대신 좌측 레일을 쓴다. **화면을 두 벌 만들지 않고** 같은 화면을 다른 내비에 꽂는다.
///
/// 조리는 탭 안에서 시작하고 진행·완료는 그 위에 쌓는다 — 조리 중에 탭이 보이면 눌러서
/// 빠져나가게 되고, 돌아올 자리를 잃는다.
///
/// 대화는 탭이 아니라 오버레이다. 호출어는 어느 탭에서나 받으므로 탭 하나를 차지하면
/// 돌아갈 곳을 잃는다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/breakpoints.dart';
import '../core/di.dart';
import '../core/l10n/strings.dart';
import '../domain/model/menu.dart';
import '../domain/repository/repositories.dart';
import 'conversation/conversation_overlay.dart';
import 'conversation/conversation_view_model.dart';
import 'cook/cook_done_screen.dart';
import 'cook/cook_home_screen.dart';
import 'cook/cook_session.dart';
import 'cook/cook_view_model.dart';
import 'cook/cooking_screen.dart';
import 'cook/cooking_view_model.dart';
import 'fridge/fridge_screen.dart';
import 'fridge/fridge_view_model.dart';
import 'history/history_screen.dart';
import 'history/history_view_model.dart';
import 'home/home_screen.dart';
import 'home/home_view_model.dart';
import 'menu/menu_detail_screen.dart';
import 'mypage/mypage_screen.dart';
import 'widgets/glass_nav.dart';
import 'widgets/nav_icons.dart';

class AppShell extends StatefulWidget {
  const AppShell({required this.onSignIn, required this.onSignOut, super.key});

  /// 게스트가 마이페이지에서 로그인으로 간다.
  final VoidCallback onSignIn;

  /// 로그아웃.
  final VoidCallback onSignOut;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;

  /// 탭 정의. 첫 탭 아이콘은 목업 TabIcons 의 A 수저다.
  static const _items = [
    NavItem(label: Strings.tabToday, glyph: NavGlyph.meal),
    NavItem(label: Strings.tabFridge, glyph: NavGlyph.fridge),
    NavItem(label: Strings.tabCook, glyph: NavGlyph.cook),
    NavItem(label: Strings.tabHistory, glyph: NavGlyph.history),
    NavItem(label: Strings.tabMyPage, glyph: NavGlyph.profile),
  ];

  /// 탭 순서. 화면 배열과 새로 읽기 판정이 같은 값을 봐야 한다.
  static const _fridgeTab = 1;
  static const _cookTab = 2;
  static const _historyTab = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 웨이크워드는 전경 한정이다. 앱이 떠 있는 동안만 감지한다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _resumeVoice());
    context.read<HomeViewModel>().load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final voice = context.read<ConversationViewModel>();
    switch (state) {
      case AppLifecycleState.resumed:
        _resumeVoice();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // 배경으로 가면 감지를 멈추고 그 사실을 표시한다.
        unawaited(voice.suspend());
    }
  }

  void _resumeVoice() => unawaited(context.read<ConversationViewModel>().resume());

  void _select(int next) {
    setState(() => _index = next);
    // 탭을 열 때 그 화면의 데이터를 다시 읽는다. 말로 바꾼 재고가 바로 보여야 한다.
    switch (next) {
      case 0:
        context.read<HomeViewModel>().load();
      case _fridgeTab:
        context.read<FridgeViewModel>().load();
      case _cookTab:
        context.read<CookViewModel>().loadPicks();
      case _historyTab:
        context.read<HistoryViewModel>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final useRail = context.formFactor.isTabletWidth;
    final pages = [
      HomeScreen(
        onOpenFridge: () => _select(_fridgeTab),
        onOpenMenu: _openMenu,
        // 오늘 화면은 아래 유리면이 탭을 품는다. 판을 두 겹 얹지 않는다.
        tabs: useRail ? const [] : _items,
        currentTab: _index,
        onTab: _select,
      ),
      const FridgeScreen(),
      CookHomeScreen(onStart: _startCook),
      const HistoryScreen(),
      MyPageScreen(onSignIn: widget.onSignIn, onSignOut: widget.onSignOut),
    ];

    // IMPORTANT: 오버레이가 Scaffold 밖에 있어야 하단 탭까지 덮는다. 안에 두면
    // bottomNavigationBar 가 오버레이 위에 남아, 대화 중에 탭이 눌린다.
    return Stack(
      children: [
        Scaffold(
          // 화면마다 배경 그라데이션을 그리므로 셸은 SafeArea 를 쓰지 않는다.
          body: Row(
            children: [
              if (useRail)
                SafeArea(
                  child: GlassNavRail(
                    items: _items,
                    current: _index,
                    onSelect: _select,
                  ),
                ),
              Expanded(child: pages[_index]),
            ],
          ),
          // 오늘 화면은 자기 유리면에 탭을 얹으므로 여기서 또 그리지 않는다.
          bottomNavigationBar: useRail || _index == 0
              ? null
              : GlassNavBar(
                  items: _items,
                  current: _index,
                  onSelect: _select,
                ),
        ),
        // 호출어는 어느 탭에서나 받는다. 화면 전체를 덮는다.
        const Positioned.fill(child: ConversationOverlay()),
      ],
    );
  }

  /// 메뉴 상세를 연다. 탭을 바꾸지 않고 위에 쌓는다 — 돌아올 곳을 잃지 않는다.
  void _openMenu(MenuSuggestion suggestion) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => MenuDetailScreen(
          recipeId: suggestion.recipeId,
          suggestionId: suggestion.suggestionId,
          servings: suggestion.servings,
          // 상세를 닫고 조리로 들어간다. 겹쳐 두면 조리 중에 뒤로 가 상세가 나온다.
          onStartCooking: (detail) {
            Navigator.of(route).pop();
            unawaited(_runCook(CookPlan.fromMenu(
              detail,
              suggestionId: suggestion.suggestionId,
            )));
          },
        ),
      ),
    );
  }

  /// 조리를 시작한다.
  ///
  /// 추천에서 왔으면 상세를 먼저 받아 단계를 채운다 — 추천 카드에는 조리 순서가 없다.
  /// 영상에서 왔으면 이미 단계가 있으므로 바로 들어간다.
  Future<void> _startCook(CookRequest request) async {
    final plan = await _planFor(request);
    if (plan == null || !mounted) return;
    if (plan.isEmpty) {
      _tell(Strings.cookVideoFailed);
      return;
    }
    await _runCook(plan);
  }

  /// 조리 계획을 만든다. 상세를 받지 못하면 `null` 이며, 그 사실을 사용자에게 알린다.
  Future<CookPlan?> _planFor(CookRequest request) async {
    final recipe = request.recipe;
    if (recipe != null) return CookPlan.fromVideo(recipe);

    final pick = request.suggestion!;
    try {
      final detail = await di<MenuRepository>()
          .detail(pick.recipeId, servings: pick.servings);
      return CookPlan.fromMenu(detail, suggestionId: pick.suggestionId);
    } catch (error) {
      debugPrint('recipe detail failed: $error');
      if (mounted) _tell(Strings.serverFailed);
      return null;
    }
  }

  /// 조리 진행 화면을 띄우고, 마치면 완료 화면으로 바꾼다.
  ///
  /// 진행 화면을 완료 화면으로 **교체**한다(`pushReplacement`). 남겨 두면 완료 화면에서
  /// 뒤로 가 이미 끝난 조리로 되돌아간다.
  Future<void> _runCook(CookPlan plan) async {
    final started = DateTime.now();
    final cooking = CookingViewModel(plan: plan, menu: di<MenuRepository>());

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (route) => ChangeNotifierProvider.value(
          value: cooking,
          child: CookingScreen(
            onDone: () async {
              // 서버 확인이 끝난 뒤에 넘어간다. 먼저 넘기면 "뺐어요" 를 확인 전에 보인다.
              await cooking.finish();
              if (!route.mounted) return;
              await Navigator.of(route).pushReplacement(
                MaterialPageRoute<void>(
                  builder: (done) => CookDoneScreen(
                    plan: plan,
                    result: cooking.result,
                    error: cooking.finishError,
                    minutes: _elapsed(started),
                    onClose: () => Navigator.of(done).pop(),
                    onCookAgain: () => Navigator.of(done).pop(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    cooking.dispose();

    if (!mounted) return;
    // 조리가 재고를 줄였다. 냉장고와 오늘 화면이 옛 수를 들고 있으면 안 된다.
    unawaited(context.read<HomeViewModel>().load());
    unawaited(context.read<FridgeViewModel>().load());
  }

  /// 조리에 걸린 시간(분). 1분 미만도 1분으로 적는다 — 0분 걸렸다고 쓸 수는 없다.
  int _elapsed(DateTime started) {
    final minutes = DateTime.now().difference(started).inMinutes;
    return minutes < 1 ? 1 : minutes;
  }

  void _tell(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}
