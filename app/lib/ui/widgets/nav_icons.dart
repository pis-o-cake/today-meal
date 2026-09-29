/// 하단 탭 아이콘.
///
/// 목업 `TabIcons.dc.html` 에서 고른 **A 수저**(숟가락 + 젓가락)와 냉장고·시계·사람이다.
/// Material 아이콘에는 수저가 없고, 남은 셋만 Material 로 쓰면 선 굵기와 여백이 달라
/// 한 줄에서 튄다. 네 개를 같은 24 좌표계·같은 굵기로 그린다.
///
/// 고른 탭은 굵기가 올라간다 — 색만으로 구분하지 않는다.
library;

import 'package:flutter/material.dart';

/// 목업의 탭 넷.
enum NavGlyph { meal, fridge, history, profile }

class NavIcon extends StatelessWidget {
  const NavIcon({
    required this.glyph,
    required this.color,
    this.size = 22,
    this.selected = false,
    super.key,
  });

  final NavGlyph glyph;
  final Color color;
  final double size;

  /// 고른 탭인지. 선이 굵어진다.
  final bool selected;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _GlyphPainter(
            glyph: glyph,
            color: color,
            width: selected ? 2 : 1.8,
          ),
        ),
      );
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({required this.glyph, required this.color, required this.width});

  final NavGlyph glyph;
  final Color color;
  final double width;

  /// 목업 SVG 의 좌표계.
  static const _canvas = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _canvas;
    canvas.scale(scale);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (glyph) {
      case NavGlyph.meal:
        _meal(canvas, paint);
      case NavGlyph.fridge:
        _fridge(canvas, paint);
      case NavGlyph.history:
        _history(canvas, paint);
      case NavGlyph.profile:
        _profile(canvas, paint);
    }
  }

  /// 숟가락 하나와 젓가락 둘. 젓가락은 아래로 갈수록 모인다.
  void _meal(Canvas canvas, Paint paint) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(8, 6.5), width: 6, height: 8),
      paint,
    );
    canvas.drawLine(const Offset(8, 10.5), const Offset(8, 21), paint);
    canvas.drawLine(const Offset(15, 3), const Offset(15.5, 21), paint);
    canvas.drawLine(const Offset(19, 3), const Offset(18, 21), paint);
  }

  /// 냉동실과 냉장실이 나뉜 문. 손잡이가 두 칸에 하나씩 있다.
  void _fridge(Canvas canvas, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(5, 2.5, 14, 19),
        const Radius.circular(3),
      ),
      paint,
    );
    canvas.drawLine(const Offset(5, 10), const Offset(19, 10), paint);
    canvas.drawLine(const Offset(8.5, 6), const Offset(8.5, 7.5), paint);
    canvas.drawLine(const Offset(8.5, 13), const Offset(8.5, 16), paint);
  }

  void _history(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(12, 12), 9, paint);
    canvas.drawPath(
      Path()
        ..moveTo(12, 7)
        ..lineTo(12, 12)
        ..lineTo(15, 14),
      paint,
    );
  }

  void _profile(Canvas canvas, Paint paint) {
    canvas.drawCircle(const Offset(12, 8), 4, paint);
    // 어깨선. 반원이라 아래가 열려 있다.
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(12, 20.5), radius: 7.5),
      3.14159,
      3.14159,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.width != width;
}
