/// 목업의 반복 부품.
///
/// 흰 반투명 판·알약 칩·진행 단계 표시. 화면마다 `BoxDecoration` 을 다시 쓰면 값이
/// 흩어져 판끼리 미묘하게 달라진다.
library;

import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';

/// 배경 그라데이션 위에 떠 있는 흰 반투명 판.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = Tokens.radiusCard,
    this.solid = false,
    this.shadow = Tokens.shadowCard,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  /// 본문이 올라가는 판은 조금 더 불투명하게 한다.
  final bool solid;

  final List<BoxShadow> shadow;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: solid ? Tokens.glassSolid : Tokens.glass,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Tokens.glassEdge),
          boxShadow: shadow,
        ),
        child: Padding(padding: padding, child: child),
      );
}

/// 알약 모양 글라스. 상태 표시줄·하단 탭처럼 완전히 둥근 판에 쓴다.
class GlassPill extends StatelessWidget {
  const GlassPill({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
    this.shadow = Tokens.shadowRaised,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow> shadow;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: ShapeDecoration(
          color: Tokens.glass,
          shape: StadiumBorder(side: BorderSide(color: Tokens.glassEdge)),
          shadows: shadow,
        ),
        child: Padding(padding: padding, child: child),
      );
}

/// 작은 정보 칩. 기한·보관 위치처럼 짧은 값에 쓴다.
class InfoChip extends StatelessWidget {
  const InfoChip({
    required this.label,
    this.background = const Color(0xFFEEF0F3),
    this.foreground = const Color(0xFF4E5661),
    this.icon,
    super.key,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Tokens.radiusChip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// 재료 이름처럼 배경 위에 떠 있는 옅은 칩.
class FloatingChip extends StatelessWidget {
  const FloatingChip({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: ShapeDecoration(
          color: const Color(0xB8FFFFFF),
          shape: StadiumBorder(side: BorderSide(color: Tokens.glassEdge)),
          shadows: const [
            BoxShadow(color: Color(0x0D141923), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Tokens.inkMuted, fontWeight: FontWeight.w600),
          ),
        ),
      );
}

/// 듣기 → 확인 → 반영 진행 표시.
///
/// 되묻기 흐름에서 지금 어디인지 알려준다. 음성만으로는 진행을 알 수 없어 화면에 남긴다.
class StepTrail extends StatelessWidget {
  const StepTrail({required this.labels, required this.current, super.key});

  final List<String> labels;

  /// 지금 단계의 인덱스. 앞 단계는 완료 표시가 붙는다.
  final int current;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassPill(
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, label) in labels.indexed)
            Padding(
              padding: EdgeInsets.only(right: index == labels.length - 1 ? 0 : 4),
              child: _step(text, label, index),
            ),
        ],
      ),
    );
  }

  Widget _step(TextTheme text, String label, int index) {
    final done = index < current;
    final now = index == current;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: now ? Tokens.ink : Colors.transparent,
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: now ? 14 : 12),
        child: SizedBox(
          height: 34,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done) ...[
                const Icon(Icons.check_rounded, size: 14, color: Color(0xFF1B7F43)),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: text.labelMedium?.copyWith(
                  color: now
                      ? Colors.white
                      : done
                          ? const Color(0xFF1B7F43)
                          : Tokens.inkFaint,
                  fontWeight: now || done ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
