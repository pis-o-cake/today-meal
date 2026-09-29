/// 등급을 고르는 선 얼굴.
///
/// 목업 `Main.dc.html` 의 `faceLine` 을 옮긴 것이다. 머리 윤곽 없이 **이목구비만** 선으로
/// 그린다 — 다섯 개가 타원 위에 나란히 놓이므로, 각자 얼굴 판을 가지면 아래가 빽빽해진다.
///
/// 고른 얼굴만 등급 색이 들어가고 나머지는 회색이다. 색만으로 구분하지 않도록 고른
/// 얼굴은 흰 판 위에 올라앉고 크기도 커진다([BottomDeck]).
library;

import 'package:flutter/material.dart';

import '../../domain/model/inventory.dart';

class LineFace extends StatelessWidget {
  const LineFace({
    required this.grade,
    required this.color,
    this.size = 30,
    super.key,
  });

  final Freshness grade;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _LineFacePainter(grade, color)),
      );
}

class _LineFacePainter extends CustomPainter {
  _LineFacePainter(this.grade, this.color);

  final Freshness grade;
  final Color color;

  /// 목업 SVG 의 좌표계.
  static const _canvas = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _canvas);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (grade) {
      // 감은 눈과 굳은 입. 기한이 지난 얼굴이다.
      case Freshness.expired:
        _line(canvas, paint, 14, 22, 21, 22);
        _line(canvas, paint, 27, 22, 34, 22);
        _line(canvas, paint, 20, 31, 28, 31);

      // 치켜뜬 눈썹과 작은 입. 놀란 얼굴이다.
      case Freshness.urgent:
        _line(canvas, paint, 18, 19, 18, 25);
        _line(canvas, paint, 30, 19, 30, 25);
        _line(canvas, paint, 13, 15, 19, 13);
        _line(canvas, paint, 35, 15, 29, 13);
        canvas.drawCircle(const Offset(24.4, 30), 2.4, paint);

      case Freshness.soon:
        _line(canvas, paint, 18, 19, 18, 25);
        _line(canvas, paint, 30, 19, 30, 25);
        _line(canvas, paint, 20, 31, 28, 31);

      // 웃는 눈과 웃는 입.
      case Freshness.fresh:
        _curve(canvas, paint, 13, 24, 22, 24, -5);
        _curve(canvas, paint, 26, 24, 35, 24, -5);
        _curve(canvas, paint, 18, 30, 30, 30, 6);

      // 점만 있는 눈과 갸우뚱한 입.
      case Freshness.unknown:
        _line(canvas, paint, 18, 21, 18, 22);
        _line(canvas, paint, 30, 21, 30, 22);
        _curve(canvas, paint, 20, 31, 28, 31, -2.5);
    }
  }

  void _line(Canvas canvas, Paint paint, double x0, double y0, double x1,
          double y1) =>
      canvas.drawLine(Offset(x0, y0), Offset(x1, y1), paint);

  /// 2차 곡선. [lift] 가 음수면 위로 굽는다.
  void _curve(Canvas canvas, Paint paint, double x0, double y0, double x1,
      double y1, double lift) {
    canvas.drawPath(
      Path()
        ..moveTo(x0, y0)
        ..quadraticBezierTo((x0 + x1) / 2, y0 + lift * 2, x1, y1),
      paint,
    );
  }

  @override
  bool shouldRepaint(_LineFacePainter old) =>
      old.grade != grade || old.color != color;
}
