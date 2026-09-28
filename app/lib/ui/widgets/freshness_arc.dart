/// 신선도 아치.
///
/// 목업의 핵심 조작부다. 무지개 궤도 위에 등급 5개의 얼굴을 올려두고, 가운데 온 등급이
/// 화면 전체(배경색·캐릭터·문구)를 바꾼다. 목록을 훑지 않고 **색으로 골라 들어가는** 것이
/// 이 화면의 방식이다.
///
/// **얼굴은 궤도 위 제자리에 있고 고른 표시가 미끄러진다.** 얼굴까지 함께 돌리면 끝
/// 등급을 골랐을 때 반대쪽 얼굴이 궤도 밖으로 떨어진다.
///
/// 손가락을 따라 표시가 따라오고, 손을 떼면 가장 가까운 얼굴로 스프링처럼 붙는다.
/// 한 칸씩 툭툭 끊기면 어디로 갔는지 읽히지 않는다.
///
/// 지남 → 급함 → 챙길 것 → 여유 → 미확인 순으로 고정이다. 순서가 바뀌면 사용자가
/// 위치로 익힌 것이 무너진다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/tokens.dart';
import '../../domain/model/inventory.dart';

class FreshnessArc extends StatefulWidget {
  const FreshnessArc({
    required this.counts,
    required this.selected,
    required this.onSelect,
    required this.hint,
    this.slide,
    super.key,
  });

  /// 등급별 재료 종 수. 0 인 등급도 자리를 지킨다 — 자리가 바뀌면 위치로 익힐 수 없다.
  final Map<Freshness, int> counts;

  final Freshness selected;
  final ValueChanged<Freshness> onSelect;

  /// 궤도 아래 안내 문구.
  final String hint;

  /// 궤도 위의 현재 위치(칸 단위, 소수 포함).
  ///
  /// 화면이 **끄는 동안 함께** 넘어가게 하려는 것이다. [onSelect] 만으로는 손을 뗀
  /// 뒤에야 바뀌어 아치와 본문이 따로 논다.
  ///
  /// IMPORTANT: 콜백이 아니라 [ValueNotifier] 다. 애니메이션 틱마다 부모를
  /// `setState` 하면 빌드 도중 재빌드가 나고, 화면 전체가 매 프레임 다시 그려진다.
  final ValueNotifier<double>? slide;

  /// 트랙의 세로 크기. 얼굴이 위로 튀어나오므로 여유를 둔다.
  static const height = 128.0;

  /// 얼굴이 놓이는 각도(도). 왼쪽 위에서 오른쪽으로 내려온다. **고정이다.**
  static const angles = [158.0, 124.0, 90.0, 56.0, 22.0];

  /// 얼굴 사이의 각도 간격. 한 칸을 화면 거리로 바꿀 때 쓴다.
  static const gap = 34.0;

  @override
  State<FreshnessArc> createState() => _FreshnessArcState();
}

class _FreshnessArcState extends State<FreshnessArc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring;
  late final Animation<double> _curve;

  /// 궤도 위의 현재 위치(칸 단위). 정수가 아니어도 되므로 끄는 중에도 따라온다.
  late double _at = _indexOf(widget.selected).toDouble();

  double _from = 0;
  double _to = 0;
  bool _dragging = false;

  double get _last => (Bands.ordered.length - 1).toDouble();

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    // 살짝 지나쳤다 돌아온다. 딱 멈추면 기계적이다.
    _curve = CurvedAnimation(parent: _spring, curve: Curves.easeOutBack)
      ..addListener(() => _moveTo(_from + (_to - _from) * _curve.value));
  }

  @override
  void didUpdateWidget(FreshnessArc old) {
    super.didUpdateWidget(old);
    // 얼굴을 눌러 바뀐 경우에도 같은 스냅으로 따라간다.
    final target = _indexOf(widget.selected).toDouble();
    if (!_dragging && !_spring.isAnimating && (_at - target).abs() > 0.01) {
      _snapTo(target);
    }
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  /// 위치를 옮기고 바깥에 알린다.
  void _moveTo(double next) {
    setState(() => _at = next);
    widget.slide?.value = next;
  }

  int _indexOf(Freshness grade) {
    final at = Bands.ordered.indexOf(grade);
    return at < 0 ? 0 : at;
  }

  void _snapTo(double target) {
    _from = _at;
    _to = target;
    _spring
      ..reset()
      ..forward();
  }

  /// 손을 뗀 자리에서 가장 가까운 얼굴로 붙인다.
  void _settle() {
    _dragging = false;
    final nearest = _at.round().clamp(0, Bands.ordered.length.toInt() - 1);
    _snapTo(nearest.toDouble());
    final grade = Bands.ordered[nearest];
    if (grade != widget.selected) widget.onSelect(grade);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final geometry = _ArcGeometry(constraints.maxWidth);
          return GestureDetector(
            // 트랙이 아니라 영역 전체를 잡는다. 얼굴이 작아 트랙만 잡으면 잘 안 걸린다.
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) {
              _dragging = true;
              _spring.stop();
            },
            onHorizontalDragUpdate: (details) {
              // 얼굴이 고정이므로 오른쪽으로 밀면 오른쪽 얼굴이 골라진다. 손가락이
              // 가리키는 쪽이 그대로 선택이다.
              _moveTo((_at + details.delta.dx / geometry.pixelsPerStep)
                  .clamp(0.0, _last));
            },
            onHorizontalDragEnd: (details) {
              // 던지듯 밀면 한 칸 더 간다.
              final fling = details.velocity.pixelsPerSecond.dx / 1600;
              _at = (_at + fling.clamp(-1.0, 1.0)).clamp(0.0, _last);
              _settle();
            },
            onHorizontalDragCancel: _settle,
            child: SizedBox(
              height: FreshnessArc.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _TrackPainter(geometry)),
                  ),
                  Positioned(left: 0, right: 0, top: 86, child: _hint(context)),
                  _marker(geometry),
                  for (final (index, grade) in Bands.ordered.indexed)
                    _token(context, geometry, index, grade),
                ],
              ),
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
            widget.hint,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Tokens.inkFaint, fontWeight: FontWeight.w500),
          ),
        ],
      );

  /// 고른 표시. 궤도 위를 미끄러지며 얼굴 뒤에 깔린다.
  Widget _marker(_ArcGeometry geometry) {
    // 얼굴 사이를 각도로 보간한다. 정수가 아닌 위치에서도 궤도 위에 머문다.
    final low = _at.floor().clamp(0, FreshnessArc.angles.length - 1);
    final high = _at.ceil().clamp(0, FreshnessArc.angles.length - 1);
    final t = _at - low;
    final angle = FreshnessArc.angles[low] +
        (FreshnessArc.angles[high] - FreshnessArc.angles[low]) * t;
    final point = geometry.pointAt(angle);

    return Positioned(
      left: point.dx - 26,
      top: point.dy - 26,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: (90 - angle) * 0.35 * math.pi / 180,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x24141923), blurRadius: 18, offset: Offset(0, 8)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _token(
    BuildContext context,
    _ArcGeometry geometry,
    int index,
    Freshness grade,
  ) {
    final angle = FreshnessArc.angles[index];
    final point = geometry.pointAt(angle);
    final distance = (index - _at).abs();
    final on = distance < 0.5;
    final count = widget.counts[grade] ?? 0;
    // 궤도를 따라 얼굴도 살짝 눕는다. 전부 정면이면 트랙 위에 붙어 보이지 않는다.
    final tilt = (90 - angle) * 0.35 * math.pi / 180;
    // 가운데에서 멀수록 작고 옅다. 깊이가 생겨야 회전목마로 읽힌다.
    final scale = (1 - distance * 0.17).clamp(0.62, 1.0);
    final fade = (1 - distance * 0.24).clamp(0.32, 1.0);

    return Positioned(
      left: point.dx - 26,
      top: point.dy - 26,
      child: Semantics(
        button: true,
        selected: on,
        label: '${_label(grade)} $count가지',
        child: GestureDetector(
          onTap: () => widget.onSelect(grade),
          child: Transform.rotate(
            angle: tilt,
            child: Transform.scale(
              scale: scale,
              child: DecoratedBox(
                // 고른 표시는 따로 그린다. 여기서는 얼굴만 놓는다.
                decoration: const BoxDecoration(),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: Opacity(
                          opacity: fade,
                          child: GradeFace(grade: grade, size: 40, dimmed: !on),
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                            top: -4, right: -4, child: _badge(context, count)),
                    ],
                  ),
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

  /// 한 칸을 넘기는 데 필요한 가로 이동(px).
  ///
  /// 궤도 위 각도 간격을 화면 거리로 바꾼 값이다. 상수로 두면 화면 폭에 따라 손맛이
  /// 달라진다.
  double get pixelsPerStep => rx * FreshnessArc.gap * math.pi / 180;

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

/// 등급의 작은 얼굴.
///
/// 아치와 냉장고 목록이 같은 얼굴을 쓴다. 등급을 색만이 아니라 **표정으로도** 익히게
/// 하려는 것이므로 두 곳이 달라지면 안 된다.
class GradeFace extends StatelessWidget {
  const GradeFace({
    required this.grade,
    this.size = 40,
    this.dimmed = false,
    super.key,
  });

  final Freshness grade;
  final double size;

  /// 고르지 않은 얼굴은 색을 뺀다.
  final bool dimmed;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size, size),
        painter: _FacePainter(grade, dimmed: dimmed),
      );
}

/// 캐릭터와 같은 표정 규칙을 48 좌표계로 줄인 것이다.
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
