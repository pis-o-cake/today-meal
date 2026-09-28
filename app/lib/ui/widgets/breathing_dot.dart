/// 숨쉬는 상태 점.
///
/// 호출 대기 중이라는 사실이 **살아 있는 것으로 읽혀야** 한다. 멈춘 점은 꺼진 것과
/// 구분되지 않는다.
///
/// 색만으로 상태를 구분하지 않으므로 항상 문구와 함께 쓴다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

class BreathingDot extends StatefulWidget {
  const BreathingDot({
    required this.color,
    this.size = 8,
    this.alive = true,
    super.key,
  });

  final Color color;
  final double size;

  /// 숨쉬는지. 음소거·배경처럼 멈춘 상태에서는 가만히 둔다 — 멈춘 것은 멈춰 보여야 한다.
  final bool alive;

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    if (widget.alive) _breath.repeat();
  }

  @override
  void didUpdateWidget(BreathingDot old) {
    super.didUpdateWidget(old);
    if (widget.alive && !_breath.isAnimating) {
      _breath.repeat();
    } else if (!widget.alive && _breath.isAnimating) {
      _breath.stop();
      _breath.value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _breath,
        builder: (context, _) {
          // 들숨이 빠르고 날숨이 느리다. 정현파 하나만 쓰면 기계적인 박자가 된다.
          final t = _breath.value;
          final wave = widget.alive
              ? (math.sin(t * math.pi * 2 - math.pi / 2) + 1) / 2
              : 0.4;
          final halo = 3 + 3.5 * wave;
          final core = widget.size * (0.88 + 0.12 * wave);

          return SizedBox(
            width: widget.size + 12,
            height: widget.size + 12,
            child: Center(
              child: Container(
                width: core,
                height: core,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.30 * (1 - wave * 0.6)),
                      blurRadius: 0,
                      spreadRadius: halo,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
}
