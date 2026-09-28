/// 신선도 아치.
///
/// 목업의 핵심 조작부다. 무지개 트랙 위에 등급 5개의 얼굴을 올려두고, 누른 등급이
/// 화면 전체(배경색·캐릭터·문구)를 바꾼다. 목록을 훑지 않고 **색으로 골라 들어가는** 것이
/// 이 화면의 방식이다.
///
/// 지남 → 급함 → 챙길 것 → 여유 → 미확인 순으로 왼쪽부터 놓는다. 급한 것이 가운데
/// 오도록 두지 않는다 — 순서가 바뀌면 사용자가 위치로 익힌 것이 무너진다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/tokens.dart';
import '../../domain/model/inventory.dart';

/// 아치 전체.
class FreshnessArc extends StatelessWidget {
  const FreshnessArc({
    required this.counts,
    required this.selected,
    required this.onSelect,
    required this.hint,
    super.key,
  });

  /// 등급별 재료 종 수. 0 인 등급도 자리를 지킨다 — 자리가 바뀌면 위치로 익힐 수 없다.
  final Map<Freshness, int> counts;

  final Freshness selected;
  final ValueChanged<Freshness> onSelect;

  /// 트랙 아래 안내 문구.
  final String hint;

  /// 트랙의 세로 크기. 얼굴이 위로 튀어나오므로 여유를 둔다.
  static const height = 128.0;

  /// 얼굴이 놓이는 각도(도). 왼쪽 위에서 오른쪽으로 내려온다.
  static const _angles = [158.0, 124.0, 90.0, 56.0, 22.0];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final geometry = _ArcGeometry(width);
          return SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _TrackPainter(geometry)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 86,
                  child: _hint(context),
                ),
                for (final (index, grade) in Bands.ordered.indexed)
                  _token(context, geometry, index, grade),
              ],
            ),
          );
        },
      );

  Widget _hint(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.swap_horiz_rounded, size: 15, color: Tokens.inkFaint),
          const SizedBox(width: 5),
          Text(
            hint,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Tokens.inkFaint, fontWeight: FontWeight.w500),
          ),
        ],
      );

  Widget _token(
    BuildContext context,
    _ArcGeometry geometry,
    int index,
    Freshness grade,
  ) {
    final point = geometry.pointAt(_angles[index]);
    final on = grade == selected;
    final count = counts[grade] ?? 0;
    // 아치를 따라 얼굴도 살짝 눕는다. 전부 정면이면 트랙 위에 붙어 보이지 않는다.
    final tilt = (90 - _angles[index]) * 0.35 * math.pi / 180;

    return Positioned(
      left: point.dx - 26,
      top: point.dy - 26,
      child: Semantics(
        button: true,
        selected: on,
        label: '${_label(grade)} $count가지',
        child: GestureDetector(
          onTap: () => onSelect(grade),
          child: Transform.rotate(
            angle: tilt,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: on ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                boxShadow: on
                    ? const [
                        BoxShadow(
                            color: Color(0x24141923),
                            blurRadius: 18,
                            offset: Offset(0, 8)),
                      ]
                    : null,
              ),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: Opacity(
                        opacity: on ? 1 : 0.66,
                        child: CustomPaint(
                          size: const Size(40, 40),
                          painter: _FacePainter(grade, dimmed: !on),
                        ),
                      ),
                    ),
                    if (count > 0)
                      Positioned(top: -4, right: -4, child: _badge(context, count)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(BuildContext context, int count) => Container(
        constraints: const BoxConstraints(minWidth: 20),
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: const ShapeDecoration(color: Tokens.ink, shape: StadiumBorder()),
        child: Text(
          '$count',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      );

  String _label(Freshness grade) => switch (grade) {
        Freshness.expired => '지남',
        Freshness.urgent => '급함',
        Freshness.soon => '챙길 것',
        Freshness.fresh => '여유',
        Freshness.unknown => '미확인',
      };
}

/// 트랙의 타원 기하. 얼굴과 트랙이 같은 곡선 위에 있어야 한다.
class _ArcGeometry {
  _ArcGeometry(this.width)
      : cx = width / 2,
        rx = width / 2 - 40;

  final double width;
  final double cx;
  final double rx;
  static const ry = 64.0;
  static const cy = 100.0;

  Offset pointAt(double degrees) {
    final radians = degrees * math.pi / 180;
    return Offset(cx + rx * math.cos(radians), cy - ry * math.sin(radians));
  }

  /// 굵은 트랙이 지나는 경로.
  Path track() => _arc(168, 12, rx, ry);

  /// 트랙 위의 가느다란 광택선.
  Path sheen() => _arc(146, 34, rx + 22, ry + 22);

  Path _arc(double from, double to, double ex, double ey) {
    final path = Path();
    // 각도를 잘게 나눠 잇는다. Path.arcTo 는 타원 회전 규약이 SVG 와 달라 어긋난다.
    const steps = 48;
    for (var i = 0; i <= steps; i++) {
      final degrees = from + (to - from) * i / steps;
      final radians = degrees * math.pi / 180;
      final point = Offset(cx + ex * math.cos(radians), cy - ey * math.sin(radians));
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path;
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(this.geometry);

  final _ArcGeometry geometry;

  /// 등급 색을 이은 무지개. 왼쪽이 지남, 오른쪽이 미확인이다.
  static const _rainbow = [
    Color(0xFFE2E6ED),
    Color(0xFFFFD3C6),
    Color(0xFFFFE7C0),
    Color(0xFFCDEFD7),
    Color(0xFFDDE2EE),
  ];
  static const _stops = [0.0, 0.27, 0.5, 0.73, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final track = geometry.track();
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.drawPath(
      track,
      Paint()
        ..shader = const LinearGradient(colors: _rainbow, stops: _stops)
            .createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 64
        ..strokeCap = StrokeCap.round,
    );
    // 흰 막을 한 겹 덮어 색을 눌러준다. 원색으로 두면 아래 내용보다 눈에 띈다.
    canvas.drawPath(
      track,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.34)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 64
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      geometry.sheen(),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TrackPainter old) => old.geometry.width != geometry.width;
}

/// 아치 위의 작은 얼굴. 캐릭터와 같은 표정 규칙을 쓰되 48 좌표계로 줄인 것이다.
class _FacePainter extends CustomPainter {
  _FacePainter(this.grade, {required this.dimmed});

  final Freshness grade;

  /// 선택되지 않은 얼굴은 색을 뺀다.
  final bool dimmed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 48);
    final palette = Bands.of(grade);
    final body = dimmed
        ? Color.lerp(palette.mascotBody, const Color(0xFFBFC4CC), 0.5)!
        : palette.mascotBody;

    canvas.drawCircle(const Offset(24, 24), 19, Paint()..color = body);
    canvas.save();
    canvas.translate(17, 15);
    canvas.rotate(-30 * math.pi / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 10, height: 6),
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.restore();

    final fill = Paint()..color = Tokens.faceInk;
    final line = Paint()
      ..color = Tokens.faceInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final brow = Paint()
      ..color = Tokens.faceInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    switch (grade) {
      case Freshness.expired:
        canvas.drawLine(const Offset(15.5, 25), const Offset(21.5, 25), line);
        canvas.drawLine(const Offset(26.5, 25), const Offset(32.5, 25), line);
        canvas.drawLine(const Offset(22, 32), const Offset(26, 32), line);
      case Freshness.urgent:
        canvas.drawPath(_pill(19, 25, 9), fill);
        canvas.drawPath(_pill(29, 25, 9), fill);
        canvas.drawCircle(const Offset(24, 32), 2.2, fill);
        canvas.drawLine(const Offset(14, 18.5), const Offset(20, 16.5), brow);
        canvas.drawLine(const Offset(34, 18.5), const Offset(28, 16.5), brow);
      case Freshness.soon:
        canvas.drawPath(_pill(19, 24, 9), fill);
        canvas.drawPath(_pill(29, 24, 9), fill);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(21.5, 31, 5, 2.4), const Radius.circular(1.2)),
          fill,
        );
      case Freshness.fresh:
        canvas.drawPath(_smile(15, 26, 22, -4.5), line);
        canvas.drawPath(_smile(26, 26, 33, -4.5), line);
        canvas.drawPath(_smile(20.5, 30.5, 27.5, 4), line);
      case Freshness.unknown:
        canvas.drawCircle(const Offset(19, 25), 2.4, fill);
        canvas.drawCircle(const Offset(29, 25), 2.4, fill);
        canvas.drawPath(_smile(21, 32, 27, -1.6), line);
    }
  }

  Path _pill(double cx, double cy, double h) => Path()
    ..addRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: 5, height: h),
      const Radius.circular(2.5),
    ));

  Path _smile(double x0, double y, double x1, double lift) => Path()
    ..moveTo(x0, y)
    ..quadraticBezierTo((x0 + x1) / 2, y + lift * 2, x1, y);

  @override
  bool shouldRepaint(_FacePainter old) =>
      old.grade != grade || old.dimmed != dimmed;
}
