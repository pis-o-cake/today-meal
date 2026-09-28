/// 하단 탭 · 좌측 레일.
///
/// 목업의 떠 있는 알약형 탭 바를 옮긴 것이다. Material 의 `NavigationBar` 는 화면 아래에
/// 붙는 불투명 판이라 라디얼 그라데이션 위에서 배경이 잘려 보인다.
///
/// 태블릿 폭에서는 같은 배색의 레일로 바뀐다. **화면을 두 벌 만들지 않는다.**
library;

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';

/// 탭 한 칸.
class NavItem {
  const NavItem({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

/// 떠 있는 알약형 하단 탭.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    required this.items,
    required this.current,
    required this.onSelect,
    super.key,
  });

  final List<NavItem> items;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: Tokens.glass,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusNav),
              side: const BorderSide(color: Tokens.glassEdge),
            ),
            shadows: Tokens.shadowCard,
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: SizedBox(
              height: 52,
              child: Row(
                children: [
                  for (final (index, item) in items.indexed)
                    Expanded(child: _tab(context, item, index)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _tab(BuildContext context, NavItem item, int index) {
    final on = index == current;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => onSelect(index),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: on
                ? const [
                    BoxShadow(
                        color: Color(0x14141923), blurRadius: 12, offset: Offset(0, 4)),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 22, color: on ? Tokens.ink : Tokens.inkFaint),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: text.labelSmall?.copyWith(
                  color: on ? Tokens.ink : Tokens.inkFaint,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 태블릿 폭의 좌측 레일. 하단 탭과 같은 배색을 쓴다.
class GlassNavRail extends StatelessWidget {
  const GlassNavRail({
    required this.items,
    required this.current,
    required this.onSelect,
    super.key,
  });

  final List<NavItem> items;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: Tokens.glass,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusNav),
              side: const BorderSide(color: Tokens.glassEdge),
            ),
            shadows: Tokens.shadowCard,
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (index, item) in items.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _tab(context, item, index),
                  ),
              ],
            ),
          ),
        ),
      );

  Widget _tab(BuildContext context, NavItem item, int index) {
    final on = index == current;
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: on,
      child: GestureDetector(
        onTap: () => onSelect(index),
        child: Container(
          width: 64,
          height: 60,
          decoration: BoxDecoration(
            color: on ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: on
                ? const [
                    BoxShadow(
                        color: Color(0x14141923), blurRadius: 12, offset: Offset(0, 4)),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(item.icon, size: 22, color: on ? Tokens.ink : Tokens.inkFaint),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: text.labelSmall?.copyWith(
                  color: on ? Tokens.ink : Tokens.inkFaint,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
