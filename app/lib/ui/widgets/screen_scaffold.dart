/// 목록 화면의 뼈대.
///
/// 냉장고·기록이 같은 배경과 머리말을 쓴다. 화면마다 다시 짜면 여백과 배경이 조금씩
/// 어긋난다.
///
/// **오늘 화면은 이것을 쓰지 않는다.** 오늘은 등급 색을 화면 전체에 입히고 머리말도
/// 가운데 정렬이라 구조가 다르다.
library;

import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/tokens.dart';
import 'breathing_dot.dart';
import 'glass.dart';

/// 제목 + 호출 대기 배지 + 본문.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    required this.title,
    required this.child,
    this.subtitle,
    this.header,
    this.badge = const SizedBox.shrink(),
    super.key,
  });

  final String title;

  /// 제목 아래 한 줄. 이 화면에서 무엇을 할 수 있는지 알린다.
  final String? subtitle;

  /// 제목 아래에 붙는 검색·필터 같은 고정 영역.
  final Widget? header;

  /// 제목 오른쪽 배지. 셸이 [VoiceBadge] 를 꽂는다.
  final Widget badge;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: Bands.neutral.listBackground),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: text.headlineMedium?.copyWith(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.2,
                          ),
                        ),
                      ),
                      badge,
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: text.bodyLarge?.copyWith(
                          color: Tokens.inkFaint, fontWeight: FontWeight.w500),
                    ),
                  ],
                  if (header != null) ...[
                    const SizedBox(height: 12),
                    header!,
                  ],
                ],
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// 제목 옆의 작은 호출 대기 배지.
///
/// 오늘 화면의 긴 상태 표시줄과 달리 여기서는 **살아 있다는 사실만** 알린다. 목록을
/// 보는 동안에도 불러서 쓸 수 있다는 것이 이 배지의 전부다.
class VoiceBadge extends StatelessWidget {
  const VoiceBadge({
    required this.label,
    required this.color,
    this.alive = true,
    super.key,
  });

  final String label;
  final Color color;
  final bool alive;

  @override
  Widget build(BuildContext context) => GlassPill(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shadow: const [
          BoxShadow(color: Color(0x0F141923), blurRadius: 12, offset: Offset(0, 4)),
        ],
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BreathingDot(color: color, size: 7, alive: alive),
              const SizedBox(width: 2),
              Text(label, style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}

/// 목록 아래를 덮는 그라데이션. 하단 탭 뒤로 내용이 자연스럽게 사라지게 한다.
class ListFade extends StatelessWidget {
  const ListFade({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Bands.neutral.bgEdge.withValues(alpha: 0),
                Bands.neutral.bgEdge.withValues(alpha: 0.92),
              ],
            ),
          ),
        ),
      );
}
