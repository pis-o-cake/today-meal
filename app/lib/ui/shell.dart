import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/breakpoints.dart';
import '../core/design/tokens.dart';
import '../core/l10n/strings.dart';
import 'conversation/conversation_overlay.dart';
import 'conversation/conversation_view_model.dart';
import 'fridge/fridge_screen.dart';
import 'fridge/fridge_view_model.dart';
import 'history/history_screen.dart';
import 'history/history_view_model.dart';
import 'home/home_screen.dart';
import 'home/home_view_model.dart';

/// 탭 셸.
///
/// 하단 탭 셋으로 나눈다 — 오늘 · 냉장고 · 기록. 태블릿 폭에서는 하단 바 대신 좌측 레일을
/// 쓴다. **화면을 두 벌 만들지 않고** 같은 화면을 다른 내비에 꽂는다.
///
/// 대화는 탭이 아니라 오버레이다. 호출어는 어느 탭에서나 받으므로 탭 하나를 차지하면
/// 돌아갈 곳을 잃는다.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;

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
    switch (next) {
      case 1:
        context.read<FridgeViewModel>().load();
      case 2:
        context.read<HistoryViewModel>().load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final useRail = context.formFactor.isTabletWidth;
    final pages = [const HomeScreen(), const FridgeScreen(), const HistoryScreen()];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                if (useRail)
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.today_outlined),
                        selectedIcon: Icon(Icons.today),
                        label: Text(Strings.tabToday),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.kitchen_outlined),
                        selectedIcon: Icon(Icons.kitchen),
                        label: Text(Strings.tabFridge),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.history_outlined),
                        selectedIcon: Icon(Icons.history),
                        label: Text(Strings.tabHistory),
                      ),
                    ],
                  ),
                Expanded(child: pages[_index]),
              ],
            ),
            // 호출어는 어느 탭에서나 받는다. 오버레이로 덮는다.
            const Positioned.fill(child: ConversationOverlay()),
          ],
        ),
      ),
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: _select,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today),
                  label: Strings.tabToday,
                ),
                NavigationDestination(
                  icon: Icon(Icons.kitchen_outlined),
                  selectedIcon: Icon(Icons.kitchen),
                  label: Strings.tabFridge,
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history),
                  label: Strings.tabHistory,
                ),
              ],
            ),
      floatingActionButton: _MicButton(onPressed: _onMic),
    );
  }

  void _onMic() {
    // 웨이크워드가 전경 한정이라 버튼 경로를 상시 유지한다.
    unawaited(context.read<ConversationViewModel>().onMicButton());
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.large(
      onPressed: onPressed,
      tooltip: Strings.micInUse,
      child: const Icon(Icons.mic, size: Tokens.gapCard * 2),
    );
  }
}
