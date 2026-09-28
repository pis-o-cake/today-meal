/// 듣는 중 연출.
///
/// 목업 `mockup/canvas/Neuron.dc.html` 을 줄여 옮긴 것이다. 재료와 메뉴를 잇는 그래프가
/// 목소리에 맞춰 숨쉰다.
///
/// 이 연출의 값어치는 **듣고 있다는 것이 한눈에 보인다**는 데 있다. 점 하나가 깜빡이는
/// 것으로는 인식 중인지 멈춘 것인지 알 수 없다.
///
/// 배치는 기동할 때 한 번만 계산한다. 매 프레임 물리를 돌리면 저가 기기에서 음성 처리와
/// 프레임을 함께 잃는다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 재료 그래프.
class IngredientGraph extends StatefulWidget {
  const IngredientGraph({
    required this.accent,
    this.highlighted = const [],
    super.key,
  });

  final Color accent;

  /// 방금 인식된 재료 이름. 그래프에서 밝게 켠다.
  final List<String> highlighted;

  @override
  State<IngredientGraph> createState() => _IngredientGraphState();
}

/// 그래프에 올릴 재료. 냉장고에 흔한 것들이라 사용자가 자기 것으로 읽는다.
///
/// 듣는 중 화면이 중간 전사에서 재료를 찾을 때도 이 목록을 쓴다. **여기 없는 이름을
/// 재료라고 하지 않는다** — 서버가 가려낸 결과가 오면 그것으로 바뀐다.
const knownIngredientNames = _ingredients;

const _ingredients = [
  '두부', '계란', '대파', '김치', '돼지고기', '애호박',
  '감자', '양파', '마늘', '간장', '참기름', '밥',
  '된장', '고추장', '새우', '소고기', '무', '우유',
];

/// 메뉴와 그 재료. 연결선이 여기서 나온다.
const _menus = <String, List<String>>{
  '된장찌개': ['두부', '애호박', '된장', '감자'],
  '계란말이': ['계란', '대파', '간장'],
  '김치찌개': ['김치', '돼지고기', '두부', '대파'],
  '감자볶음': ['감자', '양파', '참기름'],
  '소고기무국': ['소고기', '무', '간장', '마늘'],
  '새우볶음밥': ['새우', '밥', '계란', '양파'],
};

class _Node {
  _Node(this.name, this.x, this.y);

  final String name;
  double x;
  double y;

  /// 숨쉬는 위상. 노드마다 어긋나야 살아 있어 보인다.
  double phase = 0;
  double speed = 1;
  int degree = 0;
}

class _IngredientGraphState extends State<IngredientGraph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final List<_Node> _nodes;
  late final List<(int, int)> _links;

  @override
  void initState() {
    super.initState();
    _build();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// 노드를 놓고 힘 시뮬레이션을 한 번 돌린다.
  void _build() {
    // 고정 씨앗을 쓴다. 열 때마다 배치가 달라지면 같은 화면으로 읽히지 않는다.
    final random = math.Random(20261002);
    final names = [..._ingredients, ..._menus.keys];
    _nodes = [
      for (final name in names)
        _Node(name, random.nextDouble() * 200 - 100, random.nextDouble() * 200 - 100)
          ..phase = random.nextDouble() * math.pi * 2
          ..speed = 0.8 + random.nextDouble() * 1.2,
    ];
    final index = {for (final (i, n) in _nodes.indexed) n.name: i};

    _links = [
      for (final entry in _menus.entries)
        for (final ingredient in entry.value)
          if (index[entry.key] != null && index[ingredient] != null)
            (index[entry.key]!, index[ingredient]!),
    ];
    for (final (a, b) in _links) {
      _nodes[a].degree++;
      _nodes[b].degree++;
    }
    for (var step = 0; step < 300; step++) {
      _relax();
    }
  }

  /// 한 걸음. 서로 밀고 연결된 것끼리 당긴다.
  void _relax() {
    const rest = 46.0;
    final fx = List.filled(_nodes.length, 0.0);
    final fy = List.filled(_nodes.length, 0.0);

    for (var i = 0; i < _nodes.length; i++) {
      for (var j = i + 1; j < _nodes.length; j++) {
        final dx = _nodes[i].x - _nodes[j].x;
        final dy = _nodes[i].y - _nodes[j].y;
        final d2 = dx * dx + dy * dy + 0.01;
        if (d2 > 40000) continue;
        final d = math.sqrt(d2);
        final force = math.min(8, 950 / d2);
        fx[i] += dx / d * force;
        fy[i] += dy / d * force;
        fx[j] -= dx / d * force;
        fy[j] -= dy / d * force;
      }
    }
    for (final (a, b) in _links) {
      final dx = _nodes[b].x - _nodes[a].x;
      final dy = _nodes[b].y - _nodes[a].y;
      final d = math.sqrt(dx * dx + dy * dy) + 0.01;
      final force = 0.05 * (d - rest);
      fx[a] += dx / d * force;
      fy[a] += dy / d * force;
      fx[b] -= dx / d * force;
      fy[b] -= dy / d * force;
    }
    for (var i = 0; i < _nodes.length; i++) {
      // 가운데로 약하게 당긴다. 없으면 그래프가 화면 밖으로 흩어진다.
      fx[i] -= _nodes[i].x * 0.012;
      fy[i] -= _nodes[i].y * 0.012;
      _nodes[i].x += fx[i].clamp(-6.0, 6.0);
      _nodes[i].y += fy[i].clamp(-6.0, 6.0);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) => CustomPaint(
          painter: _GraphPainter(
            nodes: _nodes,
            links: _links,
            time: _pulse.value * 6,
            accent: widget.accent,
            highlighted: widget.highlighted.toSet(),
          ),
          size: Size.infinite,
        ),
      );
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.links,
    required this.time,
    required this.accent,
    required this.highlighted,
  });

  final List<_Node> nodes;
  final List<(int, int)> links;
  final double time;
  final Color accent;
  final Set<String> highlighted;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);

    // 목소리 크기를 흉내 낸 파형. 여러 주기를 겹쳐 기계적인 박자를 피한다.
    final energy = (0.5 +
            0.26 * math.sin(time * 1.9) +
            0.18 * math.sin(time * 4.7 + 1.3) +
            0.12 * math.sin(time * 9.1 + 0.4))
        .clamp(0.0, 1.0);

    _drawHalo(canvas, energy);
    _drawLinks(canvas, energy);
    _drawNodes(canvas, energy);
  }

  void _drawHalo(Canvas canvas, double energy) {
    final radius = 120 + 60 * energy;
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [accent.withValues(alpha: 0.16 * energy), accent.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
  }

  void _drawLinks(Canvas canvas, double energy) {
    final cold = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final hot = Paint()
      ..color = accent.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    for (final (a, b) in links) {
      final lit = highlighted.contains(nodes[a].name) ||
          highlighted.contains(nodes[b].name);
      canvas.drawLine(
        Offset(nodes[a].x, nodes[a].y),
        Offset(nodes[b].x, nodes[b].y),
        lit ? hot : cold,
      );
    }
  }

  void _drawNodes(Canvas canvas, double energy) {
    for (final node in nodes) {
      final lit = highlighted.contains(node.name);
      // 연결이 많은 노드가 크다. 그래프가 평평하면 구조가 안 보인다.
      final base = 1.6 + node.degree * 0.5;
      final breath = 1 + 0.18 * math.sin(time * node.speed + node.phase) * energy;
      final radius = base * breath * (lit ? 1.8 : 1);

      if (lit) {
        canvas.drawCircle(
          Offset(node.x, node.y),
          radius * 3,
          Paint()..color = accent.withValues(alpha: 0.25),
        );
      }
      canvas.drawCircle(
        Offset(node.x, node.y),
        radius,
        Paint()
          ..color = lit ? accent : Colors.white.withValues(alpha: 0.38),
      );
    }
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.time != time || old.highlighted != highlighted;
}
