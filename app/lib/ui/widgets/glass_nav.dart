/// 하단 탭 · 좌측 레일.
///
/// 목업의 탭 넷을 옮긴 것이다 — 뭐 먹지? · 냉장고 · 기록 · 마이페이지. Material 의
/// `NavigationBar` 는 화면 아래에 붙는 불투명 판이라 라디얼 그라데이션 위에서 배경이
/// 잘려 보인다.
///
/// 목록 화면은 본문 위에 얹는 **위가 둥근 판**을 쓰고, 오늘 화면은 자기 타원 유리면이
/// 탭을 품는다([DeckTabs]). 판을 두 겹 얹으면 화면 아래가 두 층으로 나뉘어 답답하다.
///
/// 태블릿 폭에서는 같은 배색의 레일로 바뀐다. **화면을 두 벌 만들지 않는다.**
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import 'nav_icons.dart';

/// 탭 한 칸.
class NavItem {
  const NavItem({required this.label, required this.glyph});

  final String label;
  final NavGlyph glyph;
}

/// 유리면 위에 얹는 탭.
///
/// 배경을 갖지 않는다 — 아래 유리면이 이미 판이라 한 겹을 더 얹으면 두 층으로 보인다.
class DeckTabs extends StatelessWidget {
  const DeckTabs({
    required this.items,
    required this.current,
    required this.onSelect,
    super.key,
  });

  final List<NavItem> items;
  final int current;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 60,
        child: Row(
          children: [
            for (final (index, item) in items.indexed)
              Expanded(
                child: _Tab(
                  item: item,
                  on: index == current,
                  onTap: () => onSelect(index),
                ),
              ),
          ],
        ),
      );
}

/// 목록 화면의 둥근 상단 탭 바.
///
/// 오늘 화면은 타원 유리면이 탭을 품지만, 냉장고·기록·마이페이지는 본문이 화면 끝까지
/// 차므로 본문 위에 얹는 판이 필요하다.
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
  Widget build(BuildContext context) {
    final skin = context.skin;
    final bar = DecoratedBox(
      decoration: BoxDecoration(
        color: skin.fillOf(skin.glass),
        gradient: skin.sheen,
        border: Border(top: BorderSide(color: skin.edge)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final (index, item) in items.indexed)
                Expanded(
                  child: _Tab(
                    item: item,
                    on: index == current,
                    onTap: () => onSelect(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return DecoratedBox(
      // 그림자는 위로 올라간다. 본문이 판 아래로 사라지는 경계를 만든다.
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: skin.shadowTint
                .withValues(alpha: (0.07 * skin.shadowScale).clamp(0, 1)),
            blurRadius: 32,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: skin.frosted
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: bar,
              )
            : bar,
      ),
    );
  }
}

/// 탭 한 칸. 고른 것만 진하고 굵다 — 색만으로 구분하지 않는다.
class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.on, required this.onTap});

  final NavItem item;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final color = on ? skin.ink : skin.inkDim;

    return Semantics(
      button: true,
      selected: on,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            NavIcon(glyph: item.glyph, color: color, selected: on),
            const SizedBox(height: 3),
            // 마이페이지가 가장 길다. 좁은 기기에서 줄이 넘어가지 않게 맞춘다.
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: text.labelSmall?.copyWith(
                color: color,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: item.label.length > 4 ? -0.6 : -0.24,
              ),
            ),
          ],
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
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: skin.fillOf(skin.glass),
          gradient: skin.sheen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Tokens.radiusNav),
            side: BorderSide(color: skin.edge),
          ),
          shadows: skin.shadowCard,
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (index, item) in items.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _railTab(context, skin, item, index),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _railTab(BuildContext context, Skin skin, NavItem item, int index) {
    final on = index == current;
    final text = Theme.of(context).textTheme;
    final color = on ? skin.ink : skin.inkFaint;

    return Semantics(
      button: true,
      selected: on,
      label: item.label,
      child: GestureDetector(
        onTap: () => onSelect(index),
        child: Container(
          width: 72,
          height: 62,
          decoration: BoxDecoration(
            color: on ? skin.raised : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
            boxShadow: on ? [skin.shade(0.08, 12, 4)] : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              NavIcon(glyph: item.glyph, color: color, selected: on),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                style: text.labelSmall?.copyWith(
                  color: color,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: item.label.length > 4 ? -0.6 : -0.24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
