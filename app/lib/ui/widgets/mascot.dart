/// 앱 캐릭터.
///
/// 목업 `mockup/canvas/Mascot.dc.html`(캐릭터 시안 1)을 옮긴 것이다. 200×200 좌표계에서
/// 그리고 요청 크기로 배율만 바꾼다 — 좌표를 크기마다 다시 잡으면 표정이 어긋난다.
///
/// 표정은 [MascotMood] 하나로 결정된다. 색·잎 기울기·볼터치·눈·입이 한 묶음이라
/// 밖에서 부분만 바꾸지 못하게 막았다.
library;

import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/tokens.dart';

/// 캐릭터 한 마리.
class Mascot extends StatelessWidget {
  const Mascot({required this.mood, this.size = 164, super.key});

  final MascotMood mood;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MascotPainter(mood)),
      );
}

/// 기분별 몸 색과 잎 기울기.
class _Skin {
  const _Skin(this.light, this.body, this.deep, this.leaf, this.leafRot, this.cheek);

  final Color light;
  final Color body;
  final Color deep;
  final Color leaf;

  /// 잎의 기울기(도). 기분에 따라 잎이 처지거나 선다.
  final double leafRot;

  /// 볼터치 불투명도. 0 이면 볼터치가 없다.
  final double cheek;
}

const _skins = <MascotMood, _Skin>{
  MascotMood.expired: _Skin(
      Color(0xFFEEF1F5), Color(0xFFC2C9D3), Color(0xFF8C95A3), Color(0xFFA7B19D), 58, 0),
  MascotMood.urgent: _Skin(
      Color(0xFFFFE3DA), Color(0xFFFFB3A0), Color(0xFFF4704E), Color(0xFF5FB870), -8, 0.3),
  MascotMood.soon: _Skin(
      Color(0xFFFFF1D6), Color(0xFFFFD79B), Color(0xFFF2A63C), Color(0xFF5FB870), 0, 0.3),
  MascotMood.fresh: _Skin(
      Color(0xFFE4F8EA), Color(0xFFAEE8BE), Color(0xFF4FC178), Color(0xFF3FAE5E), -12, 0.35),
  MascotMood.done: _Skin(
      Color(0xFFE4F8EA), Color(0xFFAEE8BE), Color(0xFF4FC178), Color(0xFF3FAE5E), -16, 0.4),
  MascotMood.unknown: _Skin(
      Color(0xFFEEF0F5), Color(0xFFCCD2DE), Color(0xFF99A2B2), Color(0xFF9DB39D), 22, 0.12),
  MascotMood.listening: _Skin(
      Color(0xFFE9ECFF), Color(0xFFB9C4FF), Color(0xFF6F7FF0), Color(0xFF5FB870), -18, 0.3),
  MascotMood.asking: _Skin(
      Color(0xFFFFF1D6), Color(0xFFFFD79B), Color(0xFFF2A63C), Color(0xFF5FB870), 10, 0.25),
};

class _MascotPainter extends CustomPainter {
  _MascotPainter(this.mood);

  final MascotMood mood;

  /// 목업의 좌표계. 이 값으로 그리고 마지막에 배율만 건다.
  static const _canvas = 200.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _canvas;
    canvas.scale(scale);

    final skin = _skins[mood] ?? _skins[MascotMood.urgent]!;
    _drawShadow(canvas, skin);
    _drawLeaf(canvas, skin);
    _drawBody(canvas, skin);
    _drawGloss(canvas);
    _drawCheeks(canvas, skin);
    _drawFace(canvas);
    _drawQuestion(canvas, skin);
  }

  void _drawShadow(Canvas canvas, _Skin skin) {
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 186), width: 112, height: 14),
      Paint()..color = skin.deep.withValues(alpha: 0.22),
    );
  }

  /// 머리 위 새싹. 기분마다 기울기가 달라 회전축을 잎 밑동에 둔다.
  void _drawLeaf(Canvas canvas, _Skin skin) {
    canvas.save();
    canvas.translate(100, 50);
    canvas.rotate(skin.leafRot * 3.1415926535 / 180);
    canvas.translate(-100, -50);

    final stem = Path()
      ..moveTo(100, 52)
      ..cubicTo(100, 42, 102, 34, 107, 29);
    canvas.drawPath(
      stem,
      Paint()
        ..color = skin.leaf
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    final blade = Path()
      ..moveTo(106, 30)
      ..cubicTo(110, 16, 128, 11, 137, 17)
      ..cubicTo(131, 29, 117, 34, 106, 30)
      ..close();
    canvas.drawPath(blade, Paint()..color = skin.leaf);

    final vein = Path()
      ..moveTo(109, 28)
      ..quadraticBezierTo(121, 22, 131, 19);
    canvas.drawPath(
      vein,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  void _drawBody(Canvas canvas, _Skin skin) {
    final body = Path()
      ..moveTo(100, 46)
      ..cubicTo(148, 46, 178, 80, 178, 118)
      ..cubicTo(178, 154, 146, 176, 100, 176)
      ..cubicTo(54, 176, 22, 154, 22, 118)
      ..cubicTo(22, 80, 52, 46, 100, 46)
      ..close();

    // 왼쪽 위에서 빛이 오는 라디얼 그라데이션. 평면으로 두면 스티커처럼 보인다.
    canvas.drawPath(
      body,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.24, -0.4),
          radius: 0.8,
          colors: [skin.light, skin.body, skin.deep],
          stops: const [0, 0.52, 1],
        ).createShader(Rect.fromLTWH(0, 0, _canvas, _canvas)),
    );

    // 배 아래쪽의 반사광.
    final belly = Path()
      ..moveTo(46, 150)
      ..quadraticBezierTo(100, 184, 154, 150);
    canvas.drawPath(
      belly,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  /// 광택. 큰 타원 하나와 작은 원 하나로 유약 바른 질감을 낸다.
  void _drawGloss(Canvas canvas) {
    canvas.save();
    canvas.translate(64, 82);
    canvas.rotate(-32 * 3.1415926535 / 180);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 38, height: 20),
      Paint()..color = Colors.white.withValues(alpha: 0.8),
    );
    canvas.restore();
    canvas.drawCircle(
      const Offset(146, 90), 5, Paint()..color = Colors.white.withValues(alpha: 0.55));
  }

  void _drawCheeks(Canvas canvas, _Skin skin) {
    if (skin.cheek <= 0) return;
    final paint = Paint()..color = Tokens.blush.withValues(alpha: skin.cheek);
    canvas.drawCircle(const Offset(60, 134), 10, paint);
    canvas.drawCircle(const Offset(140, 134), 10, paint);
  }

  void _drawFace(Canvas canvas) {
    final fill = Paint()..color = Tokens.faceInk;
    final thick = Paint()
      ..color = Tokens.faceInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    final brow = Paint()
      ..color = Tokens.faceInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final shine = Paint()..color = Colors.white;

    switch (mood) {
      case MascotMood.fresh:
      case MascotMood.done:
        // 웃는 눈. 호를 위로 굽힌다.
        canvas.drawPath(_arc(70, 116, 90, 116, -12), thick);
        canvas.drawPath(_arc(110, 116, 130, 116, -12), thick);
        canvas.drawPath(_arc(90, 134, 110, 134, 11), thick);
      case MascotMood.soon:
        canvas.drawPath(_pill(80, 114, 24), fill);
        canvas.drawPath(_pill(120, 114, 24), fill);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(93, 137, 14, 6), const Radius.circular(3)),
          fill,
        );
      case MascotMood.urgent:
        canvas.drawPath(_pill(80, 116, 24), fill);
        canvas.drawPath(_pill(120, 116, 24), fill);
        canvas.drawPath(Path()..moveTo(68, 100)..lineTo(86, 94), brow);
        canvas.drawPath(Path()..moveTo(132, 100)..lineTo(114, 94), brow);
        canvas.drawCircle(const Offset(100, 142), 6, fill);
      case MascotMood.expired:
        // 감은 눈. 선 두 개로 지친 인상을 만든다.
        canvas.drawPath(Path()..moveTo(71, 117)..lineTo(89, 117), thick);
        canvas.drawPath(Path()..moveTo(111, 117)..lineTo(129, 117), thick);
        canvas.drawPath(Path()..moveTo(94, 140)..lineTo(106, 140), thick);
      case MascotMood.unknown:
        canvas.drawCircle(const Offset(80, 115), 6, fill);
        canvas.drawCircle(const Offset(120, 115), 6, fill);
        canvas.drawPath(_arc(93, 140, 107, 140, -4), thick);
      case MascotMood.listening:
        // 눈을 크게 뜨고 입을 벌린다. 듣는 중임이 표정으로 읽혀야 한다.
        canvas.drawCircle(const Offset(80, 113), 9.5, fill);
        canvas.drawCircle(const Offset(120, 113), 9.5, fill);
        canvas.drawCircle(const Offset(84, 109), 3, shine);
        canvas.drawCircle(const Offset(124, 109), 3, shine);
        canvas.drawOval(
          Rect.fromCenter(center: const Offset(100, 139), width: 16, height: 18), fill);
      case MascotMood.asking:
        canvas.drawPath(_pill(80, 116, 22), fill);
        canvas.drawPath(_pill(120, 116, 22), fill);
        // 한쪽 눈썹만 올려 되묻는 표정을 만든다.
        canvas.drawPath(
          Path()..moveTo(68, 98)..quadraticBezierTo(77, 90, 86, 95), brow);
        canvas.drawPath(Path()..moveTo(114, 99)..lineTo(132, 99), brow);
        canvas.drawPath(_arc(92, 140, 108, 140, -5), thick);
    }
  }

  /// 되물을 때의 물음표. 미확인과 확인 질문에만 나온다.
  void _drawQuestion(Canvas canvas, _Skin skin) {
    if (mood != MascotMood.unknown && mood != MascotMood.asking) return;
    final painter = TextPainter(
      text: TextSpan(
        text: '?',
        style: TextStyle(
          color: skin.deep,
          fontSize: 40,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(162 - painter.width / 2, 60 - painter.height));
  }

  /// 세로 알약. 눈으로 쓴다.
  Path _pill(double cx, double cy, double h) => Path()
    ..addRRect(RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: 14, height: h),
      const Radius.circular(7),
    ));

  /// 두 점을 잇는 2차 곡선. [lift] 가 음수면 위로 굽는다.
  Path _arc(double x0, double y0, double x1, double y1, double lift) => Path()
    ..moveTo(x0, y0)
    ..quadraticBezierTo((x0 + x1) / 2, y0 + lift * 2, x1, y1);

  @override
  bool shouldRepaint(_MascotPainter old) => old.mood != mood;
}
