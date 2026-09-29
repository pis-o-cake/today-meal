/// 탭 셸.
///
/// 목업의 탭 넷이다 — 뭐 먹지? · 냉장고 · 기록 · 마이페이지. 태블릿 폭에서는 하단 바 대신
/// 좌측 레일을 쓴다. **화면을 두 벌 만들지 않고** 같은 화면을 다른 내비에 꽂는다.
///
/// 대화는 탭이 아니라 오버레이다. 호출어는 어느 탭에서나 받으므로 탭 하나를 차지하면
/// 돌아갈 곳을 잃는다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/breakpoints.dart';
import '../core/l10n/strings.dart';
import '../domain/model/menu.dart';
import 'conversation/conversation_overlay.dart';
import 'conversation/conversation_view_model.dart';
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
    NavItem(label: Strings.tabHistory, glyph: NavGlyph.history),
    NavItem(label: Strings.tabMyPage, glyph: NavGlyph.profile),
  ];

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
      case 1:
        context.read<FridgeViewModel>().load();
      case 2:
        context.read<HistoryViewModel>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final useRail = context.formFactor.isTabletWidth;
    final pages = [
      HomeScreen(
        onOpenFridge: () => _select(1),
        onOpenMenu: _openMenu,
        // 오늘 화면은 아래 유리면이 탭을 품는다. 판을 두 겹 얹지 않는다.
        tabs: useRail ? const [] : _items,
        currentTab: _index,
        onTab: _select,
      ),
      const FridgeScreen(),
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
        builder: (_) => MenuDetailScreen(recipeId: suggestion.recipeId),
      ),
    );
  }
}
