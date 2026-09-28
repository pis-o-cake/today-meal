/// 듣는 중 연출 — 재료 그래프.
///
/// 목업 `mockup/canvas/Neuron.dc.html` 을 옮긴 것이다. 재료와 메뉴가 노드, 레시피가
/// 연결선이고 **force-directed 로 떠다닌다.**
///
/// 정지 화면이 아니라 계속 움직이는 것이 핵심이다 — 점이 멈춰 있으면 인식 중인지 앱이
/// 죽은 것인지 알 수 없다. 말에 나온 재료는 보라색으로 커졌다 작아지고, 연결된 노드까지
/// 밝아진다. 노드를 누르면 이웃만 남고, 끌어서 옮길 수 있다.
///
/// 목소리 크기([energy])가 그래프 전체의 들썩임을 정한다. 레이더식 회전 스윕이나 호는
/// 쓰지 않는다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 재료 그래프.
class IngredientGraph extends StatefulWidget {
  const IngredientGraph({
    required this.accent,
    required this.energy,
    this.highlighted = const [],
    super.key,
  });

  final Color accent;

  /// 마이크 입력 크기(0~1).
  final double energy;

  /// 방금 인식된 재료 이름.
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
  '두부조림': ['두부', '간장', '대파', '고추장'],
  '계란찜': ['계란', '대파', '우유'],
};

class _Node {
  _Node(this.name, {required this.isMenu, required this.x, required this.y});

  final String name;

  /// 메뉴 노드는 이름 없이 점으로만 그린다. 재료가 주인공이다.
  final bool isMenu;

  double x;
  double y;
  double vx = 0;
  double vy = 0;
  int degree = 0;

  /// 숨쉬는 위상. 노드마다 어긋나야 살아 있어 보인다.
  double phase = 0;
  double speed = 1;

  /// 켜진 정도(0~1). 갑자기 켜지지 않고 번지듯 올라온다.
  double heat = 0;

  /// 손으로 잡고 있는 중인지.
  bool held = false;
}

class _IngredientGraphState extends State<IngredientGraph>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final List<_Node> _nodes;
  late final List<(int, int)> _links;
  final _neighbours = <int, Set<int>>{};

  double _time = 0;

  /// 부드럽게 따라가는 음량. 원값을 그대로 쓰면 그래프가 경련한다.
  double _energy = 0;

  /// 누른 노드. 있으면 그 이웃만 밝아진다.
  int? _focused;

  int? _dragging;

  @override
  void initState() {
    super.initState();
    _build();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _build() {
    // 고정 씨앗을 쓴다. 열 때마다 배치가 달라지면 같은 화면으로 읽히지 않는다.
    final random = math.Random(20261002);
    _nodes = [
      for (final name in _ingredients)
        _Node(name,
            isMenu: false,
            x: (random.nextDouble() - 0.5) * 220,
            y: (random.nextDouble() - 0.5) * 220)
          ..phase = random.nextDouble() * math.pi * 2
          ..speed = 0.7 + random.nextDouble() * 1.1,
      for (final name in _menus.keys)
        _Node(name,
            isMenu: true,
            x: (random.nextDouble() - 0.5) * 220,
            y: (random.nextDouble() - 0.5) * 220)
          ..phase = random.nextDouble() * math.pi * 2
          ..speed = 0.7 + random.nextDouble() * 1.1,
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
      (_neighbours[a] ??= {}).add(b);
      (_neighbours[b] ??= {}).add(a);
    }
    // 열자마자 엉켜 보이지 않게 미리 푼다.
    for (var i = 0; i < 260; i++) {
      _relax(0.6);
    }
  }

  void _tick(Duration elapsed) {
    _time = elapsed.inMicroseconds / 1e6;
    // 음량을 좇아가되 올라갈 때 빠르고 내려올 때 느리다. 말이 끊겨도 여운이 남는다.
    final target = widget.energy;
    _energy += (target - _energy) * (target > _energy ? 0.35 : 0.06);
    _heat();
    _relax(0.35);
    setState(() {});
  }

  /// 켜진 노드의 열기를 올리고 나머지는 식힌다.
  void _heat() {
    final lit = widget.highlighted.toSet();
    final focus = _focused;
    final focusSet = focus == null
        ? const <int>{}
        : {focus, ...?_neighbours[focus]};

    for (final (i, node) in _nodes.indexed) {
      final on = lit.contains(node.name) ||
          (focus != null && focusSet.contains(i)) ||
          // 인식된 재료에 이어진 메뉴도 함께 밝아진다.
          (_neighbours[i]?.any((j) => lit.contains(_nodes[j].name)) ?? false);
      final goal = on ? 1.0 : 0.0;
      node.heat += (goal - node.heat) * (on ? 0.18 : 0.06);
    }
  }

  /// 힘 한 걸음. 서로 밀고 연결된 것끼리 당긴다.
  void _relax(double damping) {
    // 목소리가 커지면 연결이 늘어나 그래프가 부푼다.
    final rest = 46 * (0.86 + 0.32 * _energy);

    for (var i = 0; i < _nodes.length; i++) {
      for (var j = i + 1; j < _nodes.length; j++) {
        final dx = _nodes[i].x - _nodes[j].x;
        final dy = _nodes[i].y - _nodes[j].y;
        final d2 = dx * dx + dy * dy + 0.01;
        if (d2 > 40000) continue;
        final d = math.sqrt(d2);
        final force = math.min(8, 950 / d2);
        _nodes[i].vx += dx / d * force;
        _nodes[i].vy += dy / d * force;
        _nodes[j].vx -= dx / d * force;
        _nodes[j].vy -= dy / d * force;
      }
    }
    for (final (a, b) in _links) {
      final dx = _nodes[b].x - _nodes[a].x;
      final dy = _nodes[b].y - _nodes[a].y;
      final d = math.sqrt(dx * dx + dy * dy) + 0.01;
      final force = 0.05 * (d - rest);
      _nodes[a].vx += dx / d * force;
      _nodes[a].vy += dy / d * force;
      _nodes[b].vx -= dx / d * force;
      _nodes[b].vy -= dy / d * force;
    }
    for (final node in _nodes) {
      if (node.held) {
        node.vx = 0;
        node.vy = 0;
        continue;
      }
      // 가운데로 약하게 당긴다. 없으면 그래프가 화면 밖으로 흩어진다.
      node.vx -= node.x * 0.012;
      node.vy -= node.y * 0.012;
      // 켜진 노드는 살짝 떠오른다.
      node.vy -= node.heat * 0.12;
      node.vx *= damping;
      node.vy *= damping;
      node.x += node.vx.clamp(-6.0, 6.0);
      node.y += node.vy.clamp(-6.0, 6.0);
    }
  }

  /// 화면 좌표에서 가장 가까운 노드. 멀면 `null`.
  int? _nodeAt(Offset local, Size size) {
    final point = local - Offset(size.width / 2, size.height / 2);
    var best = -1;
    var bestDistance = 28.0;
    for (final (i, node) in _nodes.indexed) {
      final d = (Offset(node.x, node.y) - point).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = i;
      }
    }
    return best < 0 ? null : best;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final hit = _nodeAt(details.localPosition, size);
              // 같은 노드를 다시 누르면 강조를 푼다. 빈 곳을 누르면 위층이 닫는다.
              setState(() => _focused = hit == _focused ? null : hit);
            },
            onPanStart: (details) {
              final hit = _nodeAt(details.localPosition, size);
              if (hit == null) return;
              _dragging = hit;
              _nodes[hit].held = true;
            },
            onPanUpdate: (details) {
              final held = _dragging;
              if (held == null) return;
              setState(() {
                _nodes[held].x += details.delta.dx;
                _nodes[held].y += details.delta.dy;
              });
            },
            onPanEnd: (_) {
              final held = _dragging;
              if (held != null) _nodes[held].held = false;
              _dragging = null;
            },
            child: CustomPaint(
              size: size,
              painter: _GraphPainter(
                nodes: _nodes,
                links: _links,
                time: _time,
                energy: _energy,
                accent: widget.accent,
                focused: _focused,
                neighbours: _focused == null
                    ? const {}
                    : {_focused!, ...?_neighbours[_focused]},
              ),
            ),
          );
        },
      );
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.links,
    required this.time,
    required this.energy,
    required this.accent,
    required this.focused,
    required this.neighbours,
  });

  final List<_Node> nodes;
  final List<(int, int)> links;
  final double time;
  final double energy;
  final Color accent;
  final int? focused;
  final Set<int> neighbours;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    _drawHalo(canvas);
    _drawLinks(canvas);
    _drawNodes(canvas, size);
  }

  /// 가운데 후광. 목소리에 맞춰 넓어진다.
  void _drawHalo(Canvas canvas) {
    final radius = 110 + 90 * energy;
    canvas.drawCircle(
      Offset.zero,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accent.withValues(alpha: 0.10 + 0.14 * energy),
            accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)),
    );
  }

  void _drawLinks(Canvas canvas) {
    for (final (a, b) in links) {
      final heat = math.max(nodes[a].heat, nodes[b].heat);
      final dimmed = focused != null && !(neighbours.contains(a) && neighbours.contains(b));
      final alpha = dimmed ? 0.04 : 0.09 + 0.55 * heat;
      canvas.drawLine(
        Offset(nodes[a].x, nodes[a].y),
        Offset(nodes[b].x, nodes[b].y),
        Paint()
          ..color = Color.lerp(Colors.white, accent, heat)!.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 + 0.6 * heat,
      );
    }
  }

  void _drawNodes(Canvas canvas, Size size) {
    for (final (i, node) in nodes.indexed) {
      final dimmed = focused != null && !neighbours.contains(i);
      final heat = node.heat;
      // 연결이 많은 노드가 크다. 평평하면 구조가 안 보인다.
      final base = node.isMenu ? 2.0 : 2.4 + node.degree * 0.45;
      final breath = 1 + 0.2 * math.sin(time * node.speed + node.phase) * (0.3 + energy);
      final radius = base * breath * (1 + heat * 0.9);
      final center = Offset(node.x, node.y);

      if (heat > 0.05) {
        canvas.drawCircle(
          center,
          radius * (2.6 + 1.4 * energy),
          Paint()..color = accent.withValues(alpha: 0.22 * heat),
        );
      }
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Color.lerp(
            Colors.white.withValues(alpha: dimmed ? 0.16 : 0.42),
            accent,
            heat,
          )!,
      );

      // 라벨은 재료만. 메뉴는 점으로 둔다 — 글자가 많으면 그래프가 안 보인다.
      if (node.isMenu) continue;
      if (dimmed && heat < 0.05) continue;
      _label(canvas, node, center, radius, heat, dimmed);
    }
  }

  void _label(Canvas canvas, _Node node, Offset center, double radius,
      double heat, bool dimmed) {
    final painter = TextPainter(
      text: TextSpan(
        text: node.name,
        style: TextStyle(
          color: Color.lerp(
            Colors.white.withValues(alpha: dimmed ? 0.2 : 0.55),
            Colors.white,
            heat,
          ),
          fontSize: 11 + 2 * heat,
          fontWeight: heat > 0.4 ? FontWeight.w700 : FontWeight.w500,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center + Offset(-painter.width / 2, radius + 4),
    );
  }

  @override
  bool shouldRepaint(_GraphPainter old) => true;
}
