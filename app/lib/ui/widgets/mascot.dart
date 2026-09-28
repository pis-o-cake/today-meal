/// 앱 캐릭터 — 냉장고 친구.
///
/// 목업 `mockup/canvas/Mascot2.dc.html`(캐릭터 시안 2, 확정안)을 옮긴 것이다. 200×200
/// 좌표계에서 그리고 요청 크기로 배율만 바꾼다 — 좌표를 크기마다 다시 잡으면 표정이
/// 어긋난다.
///
/// 표정은 [MascotMood] 하나로 결정된다. 색·볼터치·눈·입·메모지가 한 묶음이라 밖에서
/// 부분만 바꾸지 못하게 막았다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/tokens.dart';

/// 캐릭터 한 마리.
class Mascot extends StatelessWidget {
  const Mascot({required this.mood, this.size = 164, this.energy = 0, super.key});

  final MascotMood mood;
  final double size;

  /// 살아 있는 정도(0~1). 듣는 중에는 마이크 입력을 넣어 숨이 커진다.
  final double energy;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MascotPainter(mood, energy)),
      );
}

/// 기분별 몸 색과 기울기.
class _Skin {
  const _Skin(this.body, this.deep, this.cheek, {this.tilt = 0, this.note = ''});

  final Color body;
  final Color deep;

  /// 볼터치 불투명도. 0 이면 볼터치가 없다.
  final double cheek;

  /// 몸의 기울기(도). 지친 기분에서 살짝 기운다.
  final double tilt;

  /// 문에 붙은 메모지의 글자. 빈 값이면 줄만 그린다.
  final String note;
}

const _skins = <MascotMood, _Skin>{
  MascotMood.expired:
      _Skin(Color(0xFFD5DAE1), Color(0xFF8C95A3), 0, tilt: -5),
  MascotMood.urgent:
      _Skin(Color(0xFFFFC2B2), Color(0xFFE8573A), 0.45, note: '!'),
  MascotMood.soon: _Skin(Color(0xFFFFE0AA), Color(0xFFE39A2D), 0.45),
  MascotMood.fresh: _Skin(Color(0xFFBDEBC9), Color(0xFF3FAE5E), 0.5),
  MascotMood.done: _Skin(Color(0xFFBDEBC9), Color(0xFF3FAE5E), 0.55),
  MascotMood.unknown:
      _Skin(Color(0xFFD9DEE8), Color(0xFF8A94A8), 0.2, note: '?'),
  MascotMood.listening: _Skin(Color(0xFFC7CFFF), Color(0xFF5A6BEA), 0.45),
  MascotMood.asking:
      _Skin(Color(0xFFFFE0AA), Color(0xFFE39A2D), 0.35, note: '?'),
};

class _MascotPainter extends CustomPainter {
  _MascotPainter(this.mood, this.energy);

  final MascotMood mood;
  final double energy;

  /// 목업의 좌표계. 이 값으로 그리고 마지막에 배율만 건다.
  static const _canvas = 200.0;

  static const _outline = Tokens.faceInk;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _canvas);
    final skin = _skins[mood] ?? _skins[MascotMood.urgent]!;

    _shadow(canvas, skin);
    canvas.save();
    // 듣는 중에는 목소리에 맞춰 몸이 미세하게 기운다.
    final sway = mood == MascotMood.listening ? math.sin(energy * math.pi) * 2 : 0.0;
    canvas.translate(100, 184);
    canvas.rotate((skin.tilt + sway) * math.pi / 180);
    canvas.translate(-100, -184);

    _feet(canvas);
    _body(canvas, skin);
    _gloss(canvas);
    _doors(canvas);
    _memo(canvas, skin);
    _cheeks(canvas, skin);
    _face(canvas);
    canvas.restore();

    if (mood == MascotMood.listening) _waves(canvas, skin);
  }

  void _shadow(Canvas canvas, _Skin skin) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 190), width: 96, height: 12),
      Paint()..color = _outline.withValues(alpha: 0.12),
    );
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
  void _body(Canvas canvas, _Skin skin) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(46, 24, 108, 156), const Radius.circular(32));
    canvas.drawRRect(rect, Paint()..color = skin.body);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = _outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5,
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
  void _memo(Canvas canvas, _Skin skin) {
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
    canvas.drawCircle(const Offset(80, 36), 3.5, Paint()..color = skin.deep);
    canvas.drawCircle(
      const Offset(80, 36),
      3.5,
      Paint()
        ..color = _outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (skin.note.isEmpty) {
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
          text: skin.note,
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

  void _cheeks(Canvas canvas, _Skin skin) {
    if (skin.cheek <= 0) return;
    final paint = Paint()
      ..color = const Color(0xFFFF8A98).withValues(alpha: skin.cheek);
    canvas.drawCircle(const Offset(72, 134), 7, paint);
    canvas.drawCircle(const Offset(124, 134), 7, paint);
  }

  void _face(Canvas canvas) {
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
      case MascotMood.fresh:
      case MascotMood.done:
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
  void _waves(Canvas canvas, _Skin skin) {
    final paint = Paint()
      ..color = skin.deep.withValues(alpha: 0.5 + 0.5 * energy)
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
      paint..color = skin.deep.withValues(alpha: 0.25 + 0.6 * energy),
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
      old.mood != mood || old.energy != energy;
}
