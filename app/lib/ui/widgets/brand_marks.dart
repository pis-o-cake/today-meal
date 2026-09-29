/// 제공자 로고.
///
/// 카카오와 Google 의 마크는 **제공자의 자산**이다. 모양과 색을 바꾸지 않는다 — 두 곳 모두
/// 자산 규정으로 변형을 금지한다. 그래서 테마를 타지 않고 늘 같은 색으로 그린다.
///
/// 그림 자료를 번들하지 않고 경로로 그리는 이유는 이미지 한 장을 위해 SVG 렌더러를 들이지
/// 않기 위해서다. 경로는 제공자가 배포한 SVG 의 것을 그대로 옮겼다.
library;

import 'package:flutter/material.dart';

/// Google 의 네 색 G.
///
/// 원본은 48×48 좌표계의 네 경로이며, 색은 Google 이 정한 값이다.
class GoogleMark extends StatelessWidget {
  const GoogleMark({this.size = 20, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        // 로고는 장식이 아니라 "어느 계정인지" 를 말한다. 이름을 함께 둔 버튼 안에
        // 들어가므로 여기서는 읽지 않게 한다.
        child: const ExcludeSemantics(
          child: CustomPaint(painter: _GooglePainter()),
        ),
      );
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  /// 원본 SVG 의 좌표계.
  static const _canvas = 48.0;

  /// Google 이 배포한 네 조각. 색과 경로를 그대로 옮겼다.
  static const _parts = <(String, int)>[
    (
      'M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 '
          '14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z',
      0xFFEA4335,
    ),
    (
      'M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 '
          '5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z',
      0xFF4285F4,
    ),
    (
      'M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 '
          '16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z',
      0xFFFBBC05,
    ),
    (
      'M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 '
          '2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z',
      0xFF34A853,
    ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _canvas);
    for (final (data, color) in _parts) {
      canvas.drawPath(_parse(data), Paint()..color = Color(color));
    }
  }

  @override
  bool shouldRepaint(_GooglePainter old) => false;

  /// SVG 경로 문자열을 [Path] 로.
  ///
  /// 이 로고들이 쓰는 명령만 다룬다 — `M`·`L`·`C`·`H`·`V` 와 그 소문자, 그리고 `Z` 다.
  /// 범용 파서가 아니며, 다른 로고를 넣을 때는 그 로고가 쓰는 명령을 확인해야 한다.
  ///
  /// WARNING: `H`·`V` 는 현재 점을 알아야 하므로 좌표를 직접 따라간다. `Path` 는 현재 점을
  /// 알려주지 않는다.
  static Path _parse(String data) {
    final path = Path();
    final tokens =
        RegExp(r'[A-Za-z]|-?\d*\.?\d+(?:[eE][-+]?\d+)?').allMatches(data);
    var command = '';
    final numbers = <double>[];

    // 현재 점과 이번 하위 경로의 시작점. `Z` 는 시작점으로 돌아간다.
    var x = 0.0;
    var y = 0.0;
    var startX = 0.0;
    var startY = 0.0;

    void run() {
      switch (command) {
        case 'M':
          for (var i = 0; i + 1 < numbers.length; i += 2) {
            // 첫 쌍만 이동이고 뒤따르는 쌍은 선분이다. SVG 의 규칙이다.
            if (i == 0) {
              path.moveTo(numbers[0], numbers[1]);
              startX = numbers[0];
              startY = numbers[1];
            } else {
              path.lineTo(numbers[i], numbers[i + 1]);
            }
            x = numbers[i];
            y = numbers[i + 1];
          }
        case 'm':
          for (var i = 0; i + 1 < numbers.length; i += 2) {
            x += numbers[i];
            y += numbers[i + 1];
            if (i == 0) {
              path.moveTo(x, y);
              startX = x;
              startY = y;
            } else {
              path.lineTo(x, y);
            }
          }
        case 'L':
          for (var i = 0; i + 1 < numbers.length; i += 2) {
            x = numbers[i];
            y = numbers[i + 1];
            path.lineTo(x, y);
          }
        case 'l':
          for (var i = 0; i + 1 < numbers.length; i += 2) {
            x += numbers[i];
            y += numbers[i + 1];
            path.lineTo(x, y);
          }
        case 'H':
          for (final value in numbers) {
            x = value;
            path.lineTo(x, y);
          }
        case 'h':
          for (final value in numbers) {
            x += value;
            path.lineTo(x, y);
          }
        case 'V':
          for (final value in numbers) {
            y = value;
            path.lineTo(x, y);
          }
        case 'v':
          for (final value in numbers) {
            y += value;
            path.lineTo(x, y);
          }
        case 'C':
          for (var i = 0; i + 5 < numbers.length; i += 6) {
            path.cubicTo(numbers[i], numbers[i + 1], numbers[i + 2],
                numbers[i + 3], numbers[i + 4], numbers[i + 5]);
            x = numbers[i + 4];
            y = numbers[i + 5];
          }
        case 'c':
          for (var i = 0; i + 5 < numbers.length; i += 6) {
            path.cubicTo(x + numbers[i], y + numbers[i + 1], x + numbers[i + 2],
                y + numbers[i + 3], x + numbers[i + 4], y + numbers[i + 5]);
            x += numbers[i + 4];
            y += numbers[i + 5];
          }
      }
      numbers.clear();
    }

    for (final token in tokens) {
      final piece = token.group(0)!;
      if (RegExp(r'^[A-Za-z]$').hasMatch(piece)) {
        run();
        if (piece == 'z' || piece == 'Z') {
          path.close();
          x = startX;
          y = startY;
          command = '';
          continue;
        }
        command = piece;
        continue;
      }
      numbers.add(double.parse(piece));
    }
    run();
    return path;
  }
}

/// 카카오의 말풍선.
///
/// 카카오가 배포한 버튼 이미지의 심볼이며, 노란 바탕(#FEE500) 위에 먹색으로 놓는 것이
/// 규정이다.
class KakaoMark extends StatelessWidget {
  const KakaoMark({this.size = 18, this.color = const Color(0xD9000000), super.key});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: ExcludeSemantics(
          child: CustomPaint(painter: _KakaoPainter(color)),
        ),
      );
}

class _KakaoPainter extends CustomPainter {
  const _KakaoPainter(this.color);

  final Color color;

  /// 원본 좌표계. 말풍선이 가로로 조금 더 넓다.
  static const _width = 18.0;
  static const _height = 18.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / _width, size.height / _height);
    final paint = Paint()..color = color;

    // 몸통. 가로로 눌린 타원이다.
    final body = Rect.fromCenter(
        center: const Offset(9, 8), width: 17, height: 15.2);
    canvas.drawOval(body, paint);

    // 왼쪽 아래로 흐르는 꼬리.
    canvas.drawPath(
      Path()
        ..moveTo(7.4, 13.2)
        ..lineTo(5.2, 17.4)
        ..lineTo(10.4, 13.6)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_KakaoPainter old) => old.color != color;
}
