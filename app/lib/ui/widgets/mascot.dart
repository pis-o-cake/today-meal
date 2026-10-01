/// 앱 캐릭터 — 냉장고 친구.
///
/// 목업 `mockup/canvas/Mascot2.dc.html`(캐릭터 시안 2, 확정안)을 옮긴 것이다. 200×200
/// 좌표계에서 그리고 요청 크기로 배율만 바꾼다 — 좌표를 크기마다 다시 잡으면 표정이
/// 어긋난다.
///
/// 표정은 [MascotMood] 하나로 결정된다. 색·볼터치·눈·입·메모지가 한 묶음이라 밖에서
/// 부분만 바꾸지 못하게 막았다.
///
/// **움직임도 기분이 정한다.** 넉넉은 통통 튀고, 코앞과 지남은 힘이 빠져 내려앉는다
/// ([_Life]). 같은 속도로 움직이면 표정만으로는 급한 정도가 읽히지 않는다.
///
/// IMPORTANT: 프레임마다 `setState` 를 부르지 않는다. 움직임은 [AnimatedBuilder] 안에서만
/// 돌며, 모션 감소 설정에서는 아예 돌지 않는다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/motion.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../domain/model/inventory.dart';

/// 캐릭터 한 마리.
///
/// 몸 색은 테마와 기분이 함께 정한다 — 같은 "얼마 안 남았어요" 가 파스텔에서는 살구색,
/// 글래스에서는 탁한 주홍이다. 표정과 기울기·메모지는 기분만 따른다.
class Mascot extends StatefulWidget {
  const Mascot({required this.mood, this.size = 164, this.energy = 0, super.key});

  final MascotMood mood;
  final double size;

  /// 살아 있는 정도(0~1). 듣는 중에는 마이크 입력을 넣어 숨이 커진다.
  final double energy;

  @override
  State<Mascot> createState() => _MascotState();

  /// 기분에 맞는 테마 배색.
  ///
  /// 신선도 다섯은 등급 색을, 음성 상태 셋과 인사는 그 상태의 색을 쓴다.
  static BandPalette paletteOf(Skin skin, MascotMood mood) => switch (mood) {
        MascotMood.expired => skin.band(Freshness.expired),
        MascotMood.urgent => skin.band(Freshness.urgent),
        MascotMood.soon => skin.band(Freshness.soon),
        MascotMood.fresh => skin.band(Freshness.fresh),
        MascotMood.unknown => skin.band(Freshness.unknown),
        MascotMood.listening => skin.listening,
        MascotMood.asking => skin.asking,
        MascotMood.done => skin.done,
        MascotMood.hello => skin.hello,
      };
}

class _MascotState extends State<Mascot> with SingleTickerProviderStateMixin {
  late final AnimationController _life = AnimationController(vsync: this);

  MascotMood? _shown;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // IMPORTANT: MediaQuery 는 initState 에서 읽을 수 없다.
    _still = context.reduceMotion;
    _restart();
  }

  @override
  void didUpdateWidget(Mascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood) _restart();
  }

  /// 기분이 바뀌면 그 기분의 속도로 다시 돈다.
  void _restart() {
    final life = _Life.of(widget.mood);
    if (_shown == widget.mood && _life.isAnimating) return;
    _shown = widget.mood;
    _life.duration = life.period;
    if (_still) {
      _life
        ..stop()
        // 정지 상태에서는 가장 읽기 쉬운 한 장면(가운데)으로 고정한다.
        ..value = 0;
      return;
    }
    _life.repeat();
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Mascot.paletteOf(context.skin, widget.mood);
    final life = _Life.of(widget.mood);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _life,
        builder: (context, _) {
          // 0 → 1 → 0 으로 오가는 한 박자. 목업의 `keyTimes` 를 옮긴 것이다.
          final beat = _still ? 0.0 : _wave(_life.value);
          return Transform.translate(
            offset: Offset(0, life.bob * beat * widget.size / 200),
            child: Transform.scale(
              scaleX: 1 + life.squashX * beat,
              scaleY: 1 + life.squashY * beat,
              alignment: Alignment.bottomCenter,
              child: CustomPaint(
                painter: _MascotPainter(
                  mood: widget.mood,
                  energy: widget.energy,
                  body: palette.mascotBody,
                  deep: palette.mascotDeep,
                  frosted: context.skin.frosted,
                  beat: beat,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 톱니가 아닌 부드러운 왕복. 0 에서 시작해 가운데에서 1 이 되고 다시 0 으로 온다.
  static double _wave(double at) => (1 - math.cos(at * 2 * math.pi)) / 2;
}

/// 기분별 움직임.
///
/// 목업 `Mascot2.dc.html` 의 `ANIM` 표다. **주기가 뜻을 담는다** — 넉넉은 0.9초에 한 번
/// 튀고, 기한이 지난 것은 4.6초에 한 번 힘없이 내려앉는다.
@immutable
class _Life {
  const _Life({
    required this.period,
    required this.bob,
    required this.squashX,
    required this.squashY,
    this.sweat = false,
  });

  /// 한 박자의 길이.
  final Duration period;

  /// 위아래 이동(200 좌표계 기준). 음수는 떠오르고 양수는 내려앉는다.
  final double bob;

  /// 가로·세로 눌림. 튀어오를 때 세로로 늘고 가라앉을 때 가로로 퍼진다.
  final double squashX;
  final double squashY;

  /// 땀방울을 흘리는지. 목업은 '기한 코앞' 에만 둔다.
  final bool sweat;

  static _Life of(MascotMood mood) => _lives[mood] ?? _lives[MascotMood.soon]!;

  static const _lives = <MascotMood, _Life>{
    MascotMood.fresh: _Life(
        period: Duration(milliseconds: 900),
        bob: -14,
        squashX: -0.045,
        squashY: 0.05),
    MascotMood.done: _Life(
        period: Duration(milliseconds: 1100),
        bob: -9,
        squashX: -0.03,
        squashY: 0.035),
    MascotMood.hello: _Life(
        period: Duration(milliseconds: 1300),
        bob: -7,
        squashX: -0.02,
        squashY: 0.025),
    MascotMood.listening:
        _Life(period: Duration(milliseconds: 1400), bob: -7, squashX: 0, squashY: 0),
    MascotMood.asking: _Life(
        period: Duration(milliseconds: 2600), bob: -3, squashX: 0, squashY: 0),
    MascotMood.soon: _Life(
        period: Duration(milliseconds: 2600),
        bob: -3,
        squashX: -0.01,
        squashY: 0.015),
    MascotMood.unknown: _Life(
        period: Duration(seconds: 3), bob: -2, squashX: 0, squashY: 0),
    // 급한 둘은 **아래로** 내려앉는다. 떠오르면 여유로워 보인다.
    MascotMood.urgent: _Life(
        period: Duration(milliseconds: 3600),
        bob: 5,
        squashX: 0.05,
        squashY: -0.06,
        sweat: true),
    MascotMood.expired: _Life(
        period: Duration(milliseconds: 4600),
        bob: 7,
        squashX: 0.08,
        squashY: -0.1),
  };
}

/// 기분별 볼터치·기울기·메모지. 색과 달리 테마를 타지 않는다.
class _Face {
  const _Face(this.cheek, {this.tilt = 0, this.note = ''});

  /// 볼터치 불투명도. 0 이면 볼터치가 없다.
  final double cheek;

  /// 몸의 기울기(도). 지친 기분에서 살짝 기운다.
  final double tilt;

  /// 문에 붙은 메모지의 글자. 빈 값이면 줄만 그린다.
  final String note;
}

const _faces = <MascotMood, _Face>{
  MascotMood.expired: _Face(0, tilt: -5),
  MascotMood.urgent: _Face(0.45, note: '!'),
  MascotMood.soon: _Face(0.45),
  MascotMood.fresh: _Face(0.5),
  MascotMood.done: _Face(0.55),
  MascotMood.unknown: _Face(0.2, note: '?'),
  MascotMood.listening: _Face(0.45),
  MascotMood.asking: _Face(0.35, note: '?'),
  MascotMood.hello: _Face(0.5),
};

class _MascotPainter extends CustomPainter {
  _MascotPainter({
    required this.mood,
    required this.energy,
    required this.body,
    required this.deep,
    this.frosted = false,
    this.beat = 0,
  });

  final MascotMood mood;
  final double energy;
  final Color body;
  final Color deep;

  /// 유리 테마인지. 몸통을 반투명 유리로 그리고 검은 외곽선을 밝은 림으로 바꾼다.
  ///
  /// IMPORTANT: 색만 바꾸면 화이트 테마와 구분되지 않는다. 목업의 글래스 캐릭터는 몸통이
  /// **단색이 아니라 반투명 그라데이션**이고 테두리가 빛을 받는다 — 그 질감이 이 테마의 정체다.
  final bool frosted;

  /// 한 박자 안의 위치(0~1). 그림자 크기와 땀방울이 이 값을 따른다.
  final double beat;

  /// 목업의 좌표계. 이 값으로 그리고 마지막에 배율만 건다.
  static const _canvas = 200.0;

  static const _outline = Tokens.faceInk;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _canvas);
    final face = _faces[mood] ?? _faces[MascotMood.urgent]!;

    _shadow(canvas);
    canvas.save();
    // 듣는 중에는 목소리에 맞춰 몸이 미세하게 기운다.
    final sway = mood == MascotMood.listening ? math.sin(energy * math.pi) * 2 : 0.0;
    canvas.translate(100, 184);
    canvas.rotate((face.tilt + sway) * math.pi / 180);
    canvas.translate(-100, -184);

    _feet(canvas);
    _body(canvas);
    _gloss(canvas);
    _doors(canvas);
    _memo(canvas, face);
    _cheeks(canvas, face);
    _expression(canvas);
    _sweat(canvas);
    canvas.restore();

    if (mood == MascotMood.listening) _waves(canvas);
  }

  /// 발밑 그림자. 몸이 떠오르면 줄고 내려앉으면 퍼진다.
  void _shadow(Canvas canvas) {
    final life = _Life.of(mood);
    // 위로 뜨는 기분은 그림자가 줄고, 내려앉는 기분은 커진다. `bob` 의 부호가 그것을 말한다.
    final width = 96 - life.bob * beat * 0.9;
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 190), width: width, height: 12),
      Paint()..color = _outline.withValues(alpha: 0.12),
    );
  }

  /// 땀방울 하나. '기한 코앞' 에만 흐른다.
  ///
  /// 목업은 1.9초에 한 번 떨어뜨린다. 여기서는 몸의 박자를 그대로 쓴다 — 별도 시계를 하나
  /// 더 돌릴 만큼 눈에 띄는 연출이 아니다.
  void _sweat(Canvas canvas) {
    if (!_Life.of(mood).sweat) return;
    final fall = beat;
    final opacity = fall < 0.2 ? fall / 0.2 : (1 - (fall - 0.2) / 0.8);
    if (opacity <= 0) return;

    canvas.save();
    canvas.translate(0, fall * 12);
    final drop = Path()
      ..moveTo(161, 56)
      ..relativeQuadraticBezierTo(-6, 9, -3, 13)
      ..relativeQuadraticBezierTo(4, 4, 8, 0)
      ..relativeQuadraticBezierTo(2, -5, -5, -13)
      ..close();
    canvas.drawPath(
      drop,
      Paint()..color = const Color(0xFFA9DCFF).withValues(alpha: opacity),
    );
    canvas.drawPath(
      drop,
      Paint()
        ..color = _outline.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  /// 아래 발 두 개.
  void _feet(Canvas canvas) {
    final paint = Paint()..color = _outline;
    for (final x in [68.0, 118.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 176, 14, 12), const Radius.circular(4)),
        paint,
      );
    }
  }

  /// 냉장고 몸통.
  ///
  /// 유리 테마에서는 채움과 테두리가 모두 그라데이션이다. 목업 `Mascot2` 의 `gidB`·`gidR`
  /// 을 옮긴 것이다.
  void _body(Canvas canvas) {
    final bounds = Rect.fromLTWH(46, 24, 108, 156);
    final rect = RRect.fromRectAndRadius(bounds, const Radius.circular(32));

    if (!frosted) {
      canvas.drawRRect(rect, Paint()..color = body);
      canvas.drawRRect(
        rect,
        Paint()
          ..color = _outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5,
      );
      return;
    }

    // 위는 밝고 투명하게, 아래로 짙게. 유리가 빛을 받는 방향이다.
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: const Alignment(0.8, 1),
          colors: [
            Color.lerp(body, Colors.white, 0.55)!.withValues(alpha: 0.82),
            body.withValues(alpha: 0.6),
          ],
        ).createShader(bounds),
    );
    // 검은 외곽선 대신 빛을 받는 림. 유리에 먹선을 두르면 스티커가 된다.
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: 0.95),
            Color.lerp(deep, Colors.black, 0.2)!.withValues(alpha: 0.85),
          ],
        ).createShader(bounds)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
    );
    _frostedSheen(canvas);
  }

  /// 유리 전용 광택. 흰 타원·안쪽 림·오른쪽 아래 그늘 셋이다.
  void _frostedSheen(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(80, 68), width: 44, height: 64),
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(52.5, 30.5, 95, 143),
        const Radius.circular(26),
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    // 오른쪽 아래를 따라 도는 그늘. 유리의 두께가 보이는 자리다.
    final shade = Path()
      ..moveTo(150, 124)
      ..lineTo(150, 148)
      ..arcToPoint(const Offset(122, 176),
          radius: const Radius.circular(28), clockwise: true)
      ..lineTo(86, 176);
    canvas.drawPath(
      shade,
      Paint()
        ..color = deep.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  /// 표면 광택. 평면으로 두면 스티커처럼 보인다.
  void _gloss(Canvas canvas) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(56, 36)
        ..quadraticBezierTo(52, 44, 52, 60),
      paint,
    );
    canvas.drawLine(
      const Offset(53, 90),
      const Offset(53, 102),
      paint..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  /// 냉동실 칸막이와 손잡이 둘.
  void _doors(Canvas canvas) {
    final paint = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(46, 74), const Offset(154, 74),
        paint..strokeCap = StrokeCap.butt);
    final handle = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(138, 40), const Offset(138, 58), handle);
    canvas.drawLine(const Offset(138, 88), const Offset(138, 114), handle);
  }

  /// 문에 붙은 메모지. 급한 것과 되물을 것이 여기 적힌다.
  void _memo(Canvas canvas, _Face face) {
    canvas.save();
    canvas.translate(80, 48);
    canvas.rotate(-8 * math.pi / 180);
    canvas.translate(-80, -48);

    final paper = RRect.fromRectAndRadius(
      Rect.fromLTWH(66, 36, 28, 24), const Radius.circular(4));
    canvas.drawRRect(paper, Paint()..color = const Color(0xFFFFF3B8));
    canvas.drawRRect(
      paper,
      Paint()
        ..color = _outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    // 자석 압정.
    canvas.drawCircle(const Offset(80, 36), 3.5, Paint()..color = deep);
    canvas.drawCircle(
      const Offset(80, 36),
      3.5,
      Paint()
        ..color = _outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (face.note.isEmpty) {
      final line = Paint()
        ..color = _outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(const Offset(71, 46), const Offset(87, 46), line);
      canvas.drawLine(const Offset(71, 52), const Offset(81, 52), line);
    } else {
      final painter = TextPainter(
        text: TextSpan(
          text: face.note,
          style: const TextStyle(
            color: _outline,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(80 - painter.width / 2, 55 - painter.height));
    }
    canvas.restore();
  }

  void _cheeks(Canvas canvas, _Face face) {
    if (face.cheek <= 0) return;
    final paint = Paint()
      ..color = Tokens.blush.withValues(alpha: face.cheek);
    canvas.drawCircle(const Offset(72, 134), 7, paint);
    canvas.drawCircle(const Offset(124, 134), 7, paint);
  }

  void _expression(Canvas canvas) {
    final fill = Paint()..color = _outline;
    final stroke = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final brow = Paint()
      ..color = _outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    final shine = Paint()..color = Colors.white;

    switch (mood) {
      // 웃는 눈과 웃는 입. 여유·완료·인사가 같은 표정을 쓴다.
      case MascotMood.fresh:
      case MascotMood.done:
      case MascotMood.hello:
        canvas.drawPath(_arc(77, 121, 91, 121, -9), stroke);
        canvas.drawPath(_arc(105, 121, 119, 121, -9), stroke);
        canvas.drawPath(_arc(91, 135, 105, 135, 8), stroke);
      case MascotMood.soon:
        canvas.drawPath(_pill(84, 119, 16), fill);
        canvas.drawPath(_pill(112, 119, 16), fill);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(93, 136, 10, 5), const Radius.circular(2.5)),
          fill,
        );
      case MascotMood.urgent:
        canvas.drawPath(_pill(84, 121, 16), fill);
        canvas.drawPath(_pill(112, 121, 16), fill);
        canvas.drawLine(const Offset(75, 107), const Offset(90, 102), brow);
        canvas.drawLine(const Offset(121, 107), const Offset(106, 102), brow);
        canvas.drawCircle(const Offset(98, 141), 4.5, fill);
      case MascotMood.expired:
        canvas.drawLine(const Offset(78, 121), const Offset(90, 121), stroke);
        canvas.drawLine(const Offset(106, 121), const Offset(118, 121), stroke);
        canvas.drawLine(const Offset(94, 139), const Offset(102, 139), stroke);
      case MascotMood.unknown:
        canvas.drawCircle(const Offset(84, 120), 4.5, fill);
        canvas.drawCircle(const Offset(112, 120), 4.5, fill);
        canvas.drawPath(_arc(93, 139, 103, 139, -3), stroke);
      case MascotMood.listening:
        canvas.drawCircle(const Offset(84, 119), 7, fill);
        canvas.drawCircle(const Offset(112, 119), 7, fill);
        canvas.drawCircle(const Offset(86.5, 116), 2.2, shine);
        canvas.drawCircle(const Offset(114.5, 116), 2.2, shine);
        // 입이 목소리에 맞춰 벌어진다.
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(98, 137),
            width: 12,
            height: 14 * (0.7 + 0.6 * energy),
          ),
          fill,
        );
      case MascotMood.asking:
        canvas.drawPath(_pill(84, 121, 14), fill);
        canvas.drawPath(_pill(112, 121, 14), fill);
        canvas.drawPath(
          Path()..moveTo(76, 105)..quadraticBezierTo(83, 99, 90, 103), brow);
        canvas.drawLine(const Offset(106, 107), const Offset(120, 107), brow);
        canvas.drawPath(_arc(92, 139, 104, 139, -4), stroke);
    }
  }

  /// 듣는 중의 음파. 목소리가 크면 함께 커진다.
  void _waves(Canvas canvas) {
    final paint = Paint()
      ..color = deep.withValues(alpha: (0.5 + 0.5 * energy).clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(164, 40)
        ..quadraticBezierTo(171, 49, 164, 58),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(173, 33)
        ..quadraticBezierTo(185, 49, 173, 65),
      paint..color = deep.withValues(alpha: (0.25 + 0.6 * energy).clamp(0.0, 1.0)),
    );
  }

  /// 세로 알약. 눈으로 쓴다.
  Path _pill(double cx, double cy, double h) => Path()
    ..addRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: 10, height: h),
      const Radius.circular(5),
    ));

  /// 두 점을 잇는 2차 곡선. [lift] 가 음수면 위로 굽는다.
  Path _arc(double x0, double y0, double x1, double y1, double lift) => Path()
    ..moveTo(x0, y0)
    ..quadraticBezierTo((x0 + x1) / 2, y0 + lift * 2, x1, y1);

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.mood != mood ||
      old.energy != energy ||
      old.beat != beat ||
      old.body != body ||
      old.deep != deep ||
      old.frosted != frosted;
}
