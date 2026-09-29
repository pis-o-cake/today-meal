/// 살아 움직이는 캐릭터.
///
/// 목업 `Listening` 의 듣기 연출이다 — 냉장고가 **위아래로 들썩이고 좌우로 살짝
/// 흔들리며** 뒤로 파동이 세 겹 퍼진다.
///
/// 정지한 그림이면 인식 중인지 앱이 죽은 것인지 알 수 없다. 들썩임의 크기는 **마이크
/// 음량**이 정하므로, 말할 때만 크게 움직인다.
///
/// IMPORTANT: 프레임마다 `setState` 를 부르지 않는다. 60fps 로 위젯 트리를 다시 만들면
/// 이 위젯 밖의 화면까지 함께 다시 빌드된다. 움직임은 [AnimatedBuilder] 안에서만 돈다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/motion.dart';
import '../../core/design/skin.dart';
import 'mascot.dart';

class LivingMascot extends StatefulWidget {
  const LivingMascot({
    required this.mood,
    required this.size,
    this.energy = 0,
    this.ripples = false,
    this.accent,
    super.key,
  });

  final MascotMood mood;
  final double size;

  /// 마이크 입력 크기(0~1). 들썩임과 파동의 세기를 정한다.
  final double energy;

  /// 뒤에 파동을 퍼뜨릴지. 듣는 중에만 켠다.
  final bool ripples;

  /// 파동 색. 없으면 기분에 맞춘 테마 색을 쓴다.
  final Color? accent;

  /// 연출이 차지하는 폭의 배율. 파동이 캐릭터 밖으로 퍼진다.
  static const spread = 1.9;

  @override
  State<LivingMascot> createState() => _LivingMascotState();
}

class _LivingMascotState extends State<LivingMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _life =
      AnimationController(vsync: this, duration: Motion.breath);

  /// 부드럽게 따라가는 음량. 원값을 그대로 쓰면 경련한다.
  double _energy = 0;

  @override
  void initState() {
    super.initState();
    // 음량 추적은 화면을 다시 빌드하지 않는다. 그리는 쪽이 매 프레임 이 값을 읽는다.
    _life.addListener(_follow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _life.stop();
      _energy = widget.energy;
    } else if (!_life.isAnimating) {
      _life.repeat();
    }
  }

  void _follow() {
    final target = widget.energy;
    // 올라갈 때 빠르고 내려올 때 느리다. 말이 끊겨도 여운이 남는다.
    _energy += (target - _energy) * (target > _energy ? 0.35 : 0.06);
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final palette = Mascot.paletteOf(skin, widget.mood);
    final accent = widget.accent ?? palette.accentBright;
    final still = context.reduceMotion;

    return SizedBox(
      width: widget.size * LivingMascot.spread,
      height: widget.size * LivingMascot.spread,
      child: AnimatedBuilder(
        animation: _life,
        builder: (context, _) => _frame(accent, still),
      ),
    );
  }

  Widget _frame(Color accent, bool still) {
    final t = _life.value * 4;
    // 들썩임: 기본 숨 + 목소리에 따른 추가.
    final bounce = still ? 0.0 : math.sin(t * 2.2) * (2 + 8 * _energy);
    final sway = still ? 0.0 : math.sin(t * 1.3) * (1 + 3 * _energy);

    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.ripples && !still)
          CustomPaint(
            size: Size.square(widget.size * LivingMascot.spread),
            painter: _RipplePainter(time: t, energy: _energy, color: accent),
          ),
        Transform.translate(
          offset: Offset(sway, bounce),
          child: Transform.rotate(
            angle: sway * 0.012,
            child: Mascot(
              mood: widget.mood,
              size: widget.size,
              energy: _energy,
            ),
          ),
        ),
      ],
    );
  }
}

/// 뒤로 퍼지는 파동 세 겹.
///
/// 레이더식 회전 스윕이 아니라 **퍼져 나가는 원**이다. 회전은 스캔하는 인상이라 듣고
/// 있다는 뜻으로 읽히지 않는다.
class _RipplePainter extends CustomPainter {
  _RipplePainter({
    required this.time,
    required this.energy,
    required this.color,
  });

  final double time;
  final double energy;
  final Color color;

  /// 파동 겹 수. 목업의 `begin` 을 위상 차로 옮긴 것이다.
  static const _layers = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final base = size.width * 0.26;
    final reach = size.width * 0.5;

    for (var i = 0; i < _layers; i++) {
      final phase = (time * 0.42 + i / _layers) % 1;
      final radius = base + (reach - base) * phase;
      final fade = (1 - phase) * (0.16 + 0.34 * energy);
      if (fade <= 0.01) continue;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: fade.clamp(0.0, 1.0))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 + 2 * energy,
      );
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) =>
      old.time != time || old.energy != energy || old.color != color;
}

/// 듣는 중 캐릭터 뒤의 옅은 원과 퍼지는 테두리.
///
/// 목업은 캐릭터 뒤에 흰 원을 하나 두고 그 위로 테두리 원이 퍼진다. 파동만 있으면
/// 캐릭터가 배경에 잠긴다.
class ListeningStage extends StatelessWidget {
  const ListeningStage({
    required this.child,
    required this.palette,
    required this.size,
    super.key,
  });

  final Widget child;
  final BandPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 뒤판. 다크에서는 흰 원이 뜨므로 판 색을 쓴다.
          Container(
            width: size * 0.69,
            height: size * 0.69,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (skin.isDark ? skin.glassThick : Colors.white)
                  .withValues(alpha: 0.45),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
