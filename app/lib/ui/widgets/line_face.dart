/// 등급을 고르는 얼굴.
///
/// 목업 `Main.dc.html` 의 `faceSet` 을 옮긴 것이다. 머리 윤곽 없이 **이목구비만** 그린다 —
/// 다섯 개가 타원 위에 나란히 놓이므로, 각자 얼굴 판을 가지면 아래가 빽빽해진다.
///
/// 캐릭터의 표정과 **같은 모양**을 쓴다. 눈은 세로 알약이나 점이고 눈썹과 입만 선이다.
/// 선으로만 그리면 캐릭터와 다른 얼굴로 읽힌다.
///
/// 고른 얼굴만 등급 색이 들어가고 볼터치가 함께 뜬다. 나머지는 회색으로 물러난다 —
/// 색만으로 구분하지 않도록 고른 얼굴 뒤에는 갈기도 함께 돈다([BottomDeck]).
library;

import 'package:flutter/material.dart';

import '../../domain/model/inventory.dart';

class LineFace extends StatelessWidget {
  /// 아래 유리면에 놓는 큰 얼굴. 캐릭터와 같은 이목구비다.
  const LineFace({
    required this.grade,
    required this.color,
    this.size = 38,
    this.selected = false,
    super.key,
  }) : compact = false;

  /// 칩 안에 놓는 작은 얼굴.
  ///
  /// 가는 선만 쓴다 — 14px 에서 채운 눈은 뭉개져 점 두 개로 보이고, 등급을 가릴 수 없다.
  /// 목업도 냉장고 칩에는 이 얼굴을 쓴다.
  const LineFace.compact({
    required this.grade,
    required this.color,
    this.size = 14,
    super.key,
  })  : compact = true,
        selected = false;

  final Freshness grade;
  final Color color;
  final double size;

  /// 고른 얼굴인지. 볼터치는 고른 얼굴에만 뜬다.
  final bool selected;

  /// 칩용 작은 얼굴인지.
  final bool compact;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: compact
              ? _ChipFacePainter(grade, color)
              : _LineFacePainter(grade, color, selected),
        ),
      );
}

/// 칩 안의 작은 얼굴.
///
/// 목업 `Fridge.dc.html` 의 `FACE` 다. 큰 얼굴([_LineFacePainter])과 모양이 다른 것은
/// 의도다 — 작게 그리려면 획이 적어야 한다.
class _ChipFacePainter extends CustomPainter {
  _ChipFacePainter(this.grade, this.color);

  final Freshness grade;
  final Color color;

  static const _canvas = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _canvas);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void line(double x0, double y0, double x1, double y1) =>
        canvas.drawLine(Offset(x0, y0), Offset(x1, y1), paint);
    void arch(double x, double y, double w, double lift) => canvas.drawPath(
          Path()
            ..moveTo(x, y)
            ..relativeQuadraticBezierTo(w / 2, lift, w, 0),
          paint,
        );

    switch (grade) {
      case Freshness.expired:
        line(14, 22, 21, 22);
        line(27, 22, 34, 22);
        line(20, 31, 28, 31);
      case Freshness.urgent:
        line(18, 19, 18, 25);
        line(30, 19, 30, 25);
        line(13, 15, 19, 13);
        line(35, 15, 29, 13);
        canvas.drawCircle(const Offset(24.4, 30), 2.4, paint);
      case Freshness.soon:
        line(18, 19, 18, 25);
        line(30, 19, 30, 25);
        line(20, 31, 28, 31);
      case Freshness.fresh:
        arch(13, 24, 9, -10);
        arch(26, 24, 9, -10);
        arch(18, 30, 12, 12);
      case Freshness.unknown:
        line(18, 21, 18, 22);
        line(30, 21, 30, 22);
        arch(20, 31, 8, -5);
    }
  }

  @override
  bool shouldRepaint(_ChipFacePainter old) =>
      old.grade != grade || old.color != color;
}

class _LineFacePainter extends CustomPainter {
  _LineFacePainter(this.grade, this.color, this.selected);

  final Freshness grade;
  final Color color;
  final bool selected;

  /// 목업 SVG 의 좌표계.
  static const _canvas = 48.0;

  /// 볼터치. 캐릭터의 볼과 같은 분홍이며 테마를 타지 않는다.
  static const _cheek = Color(0x73FF7083);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _canvas);

    if (selected) _cheeks(canvas);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    switch (grade) {
      // 감은 눈과 굳은 입. 기한이 지난 얼굴이라 볼터치가 없다.
      case Freshness.expired:
        _line(canvas, stroke, 9, 23, 19, 23);
        _line(canvas, stroke, 29, 23, 39, 23);
        _line(canvas, stroke, 20, 34, 28, 34);

      // 치켜뜬 눈썹과 동그란 입. 놀란 얼굴이다.
      case Freshness.urgent:
        _line(canvas, stroke, 8, 14, 17, 10.5);
        _line(canvas, stroke, 40, 14, 31, 10.5);
        _pill(canvas, fill, 14, 23, 10);
        _pill(canvas, fill, 34, 23, 10);
        canvas.drawCircle(const Offset(24, 34), 3.4, fill);

      case Freshness.soon:
        _line(canvas, stroke, 20, 33.5, 28, 33.5);
        _pill(canvas, fill, 14, 22, 10);
        _pill(canvas, fill, 34, 22, 10);

      // 웃는 눈과 반달 입.
      case Freshness.fresh:
        _arch(canvas, stroke, 8.5, 24, 11, -7.5);
        _arch(canvas, stroke, 28.5, 24, 11, -7.5);
        canvas.drawPath(
          Path()
            ..moveTo(17.5, 30)
            ..lineTo(30.5, 30)
            ..arcToPoint(const Offset(17.5, 30),
                radius: const Radius.circular(6.5))
            ..close(),
          fill,
        );

      // 점만 있는 눈과 갸우뚱한 입.
      case Freshness.unknown:
        _arch(canvas, stroke, 18.5, 34, 11, -3.5);
        canvas.drawCircle(const Offset(14, 22), 3.6, fill);
        canvas.drawCircle(const Offset(34, 22), 3.6, fill);
    }
  }

  /// 양 볼의 분홍 점.
  void _cheeks(Canvas canvas) {
    final paint = Paint()..color = _cheek;
    canvas.drawCircle(const Offset(7, 31), 3.6, paint);
    canvas.drawCircle(const Offset(41, 31), 3.6, paint);
  }

  void _line(Canvas canvas, Paint paint, double x0, double y0, double x1,
          double y1) =>
      canvas.drawLine(Offset(x0, y0), Offset(x1, y1), paint);

  /// 세로 알약 모양의 눈.
  void _pill(Canvas canvas, Paint paint, double cx, double cy, double height) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 5.8, height: height),
        const Radius.circular(2.9),
      ),
      paint,
    );
  }

  /// 2차 곡선 한 줄. [lift] 가 음수면 위로 굽는다.
  void _arch(Canvas canvas, Paint paint, double x, double y, double width,
      double lift) {
    canvas.drawPath(
      Path()
        ..moveTo(x, y)
        ..relativeQuadraticBezierTo(width / 2, lift, width, 0),
      paint,
    );
  }

  @override
  bool shouldRepaint(_LineFacePainter old) =>
      old.grade != grade || old.color != color || old.selected != selected;
}
