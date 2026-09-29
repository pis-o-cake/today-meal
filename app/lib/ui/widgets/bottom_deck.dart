/// 오늘 화면 아래의 타원 유리면.
///
/// 목업 `Main.dc.html` 의 아래쪽 판이다. **큰 타원 유리면 하나에 얼굴 다섯과 탭 넷을
/// 함께** 얹는다. 둘을 따로 두면 화면 아래가 두 층으로 나뉘어 답답하다.
///
/// 얼굴은 타원의 윗선을 따라 놓이고 **제자리에 있다.** 미끄러지는 것은 고른 표시뿐이다 —
/// 얼굴까지 돌리면 끝 등급에서 반대쪽이 면 밖으로 떨어진다. 얼굴마다 타원의 접선 방향으로
/// 살짝 기운다.
///
/// 목업 기하(w = 화면 폭):
/// ```
/// 타원   rx = w * 0.9,  ry = 170,  위 40      → 중심 y = 210
/// 얼굴   x = w * [0.13, 0.315, 0.5, 0.685, 0.87]
///        y = 210 - (ry - 36) * sqrt(1 - u^2),  u = (x - w/2) / (rx - 36)
///        기울기 = atan((ry - 36) * u / ((rx - 36) * sqrt(1 - u^2)))
/// ```
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/labels.dart';
import '../../core/design/motion.dart';
import '../../core/design/skin.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import 'glass_nav.dart';
import 'line_face.dart';

class BottomDeck extends StatefulWidget {
  const BottomDeck({
    required this.counts,
    required this.selected,
    required this.onSelect,
    required this.items,
    required this.current,
    required this.onTab,
    this.slide,
    super.key,
  });

  final Map<Freshness, int> counts;
  final Freshness selected;
  final ValueChanged<Freshness> onSelect;

  /// 궤도 위의 현재 위치. 화면이 끄는 동안 함께 넘어가게 하는 값이다.
  final ValueNotifier<double>? slide;

  final List<NavItem> items;
  final int current;
  final ValueChanged<int> onTab;

  /// 유리면 전체 높이. 안내 문구 · 얼굴 · 탭이 모두 이 안에 든다.
  static const height = 196.0;

  /// 얼굴이 놓이는 가로 위치(화면 폭에 대한 비율).
  static const spots = [0.13, 0.315, 0.5, 0.685, 0.87];

  @override
  State<BottomDeck> createState() => _BottomDeckState();
}

class _BottomDeckState extends State<BottomDeck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spring;
  late final Animation<double> _curve;

  late double _at = _indexOf(widget.selected).toDouble();
  double _from = 0;
  double _to = 0;
  bool _dragging = false;

  double get _last => (Bands.ordered.length - 1).toDouble();

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(vsync: this, duration: Motion.bandSpring);
    // 살짝 지나쳤다 돌아온다. 딱 멈추면 기계적이다.
    _curve = CurvedAnimation(parent: _spring, curve: Curves.easeOutBack)
      ..addListener(() => _moveTo(_from + (_to - _from) * _curve.value));
  }

  @override
  void didUpdateWidget(BottomDeck old) {
    super.didUpdateWidget(old);
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

  int _indexOf(Freshness grade) {
    final at = Bands.ordered.indexOf(grade);
    return at < 0 ? 0 : at;
  }

  void _moveTo(double next) {
    setState(() => _at = next);
    widget.slide?.value = next;
  }

  void _snapTo(double target) {
    // 모션 감소에서는 튀지 않고 바로 자리를 잡는다.
    if (context.reduceMotion) {
      _moveTo(target);
      return;
    }
    _from = _at;
    _to = target;
    _spring
      ..reset()
      ..forward();
  }

  void _settle() {
    _dragging = false;
    final nearest = _at.round().clamp(0, Bands.ordered.length - 1);
    _snapTo(nearest.toDouble());
    final grade = Bands.ordered[nearest];
    if (grade != widget.selected) widget.onSelect(grade);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SizedBox(
      height: BottomDeck.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final deck = _DeckGeometry(constraints.maxWidth);
          return Stack(
            // 타원은 면보다 크다. 넘치는 부분을 잘라 화면 아래로 이어 보이게 한다.
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: deck.ovalLeft,
                top: _DeckGeometry.ovalTop,
                width: deck.ovalWidth,
                height: _DeckGeometry.ovalHeight,
                child: _Surface(skin: skin, radiusX: deck.rx),
              ),
              Positioned(left: 0, right: 0, top: 8, child: _hint(context, skin)),
              _faces(deck, skin),
              Positioned(
                left: 12,
                right: 12,
                bottom: 0,
                child: DeckTabs(
                  items: widget.items,
                  current: widget.current,
                  onSelect: widget.onTab,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _hint(BuildContext context, Skin skin) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.swipe_rounded, size: 15, color: skin.inkSubtle),
          const SizedBox(width: 5),
          Text(
            Strings.arcHint,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: skin.inkSubtle, fontWeight: FontWeight.w500),
          ),
        ],
      );

  Widget _faces(_DeckGeometry deck, Skin skin) => Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onHorizontalDragStart: (_) {
            _dragging = true;
            _spring.stop();
          },
          onHorizontalDragUpdate: (details) {
            // 얼굴이 고정이므로 오른쪽으로 밀면 오른쪽 얼굴이 골라진다.
            _moveTo(
                (_at + details.delta.dx / deck.pixelsPerStep).clamp(0.0, _last));
          },
          onHorizontalDragEnd: (details) {
            // 던지듯 밀면 한 칸 더 간다.
            final fling = details.velocity.pixelsPerSecond.dx / 1600;
            _at = (_at + fling.clamp(-1.0, 1.0)).clamp(0.0, _last);
            _settle();
          },
          onHorizontalDragCancel: _settle,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 드래그를 받을 면. 얼굴만 잡으면 빈 곳에서 밀리지 않는다.
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 120,
                child: Container(color: Colors.transparent),
              ),
              _marker(deck, skin),
              for (final (index, grade) in Bands.ordered.indexed)
                _face(deck, skin, index, grade),
            ],
          ),
        ),
      );

  /// 고른 표시. 타원 윗선을 따라 미끄러진다.
  Widget _marker(_DeckGeometry deck, Skin skin) {
    final low = _at.floor().clamp(0, BottomDeck.spots.length - 1);
    final high = _at.ceil().clamp(0, BottomDeck.spots.length - 1);
    final blend = _at - low;
    final spot = _Spot.lerp(deck.spotAt(low), deck.spotAt(high), blend);
    final palette = skin.band(Bands.ordered[_at.round().clamp(0, 4)]);

    return Positioned(
      left: spot.x - _face2,
      top: spot.y - _face2,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: spot.angle,
          child: Container(
            width: _faceBox,
            height: _faceBox,
            decoration: BoxDecoration(
              color: skin.fillOf(skin.raised),
              gradient: skin.sheen,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.22),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
                skin.shade(0.12, 22, 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _face(_DeckGeometry deck, Skin skin, int index, Freshness grade) {
    final spot = deck.spotAt(index);
    final distance = (index - _at).abs();
    final on = distance < 0.5;
    final count = widget.counts[grade] ?? 0;
    final palette = skin.band(grade);

    return Positioned(
      left: spot.x - _face2,
      top: spot.y - _face2,
      child: Semantics(
        button: true,
        selected: on,
        label: '${Labels.freshness(grade)} ${Strings.bandCount(count)}',
        child: GestureDetector(
          onTap: () => widget.onSelect(grade),
          child: SizedBox(
            width: _faceBox,
            height: _faceBox,
            child: Transform.rotate(
              angle: spot.angle,
              child: Center(
                child: LineFace(
                  grade: grade,
                  // 고른 얼굴만 등급 색이다. 나머지는 회색으로 물러난다.
                  color: on ? palette.accent : skin.inkDim,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 얼굴 판의 한 변과 그 절반.
  static const _faceBox = 52.0;
  static const _face2 = _faceBox / 2;
}

/// 반투명 타원면. 뒤 배경이 비쳐 화면과 이어져 보인다.
class _Surface extends StatelessWidget {
  const _Surface({required this.skin, required this.radiusX});

  final Skin skin;

  /// 타원의 가로 반지름. 상자의 절반이라야 참 타원이 된다.
  final double radiusX;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.all(
        Radius.elliptical(radiusX, _DeckGeometry.ry));
    final face = DecoratedBox(
      decoration: BoxDecoration(
        color: skin.fillOf(skin.glassThin),
        gradient: skin.sheen,
        borderRadius: shape,
        border: Border.all(color: skin.edge),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        // 면 위쪽으로 번지는 그림자. 본문과 판의 경계를 만든다.
        boxShadow: [
          BoxShadow(
            color: skin.shadowTint
                .withValues(alpha: (0.06 * skin.shadowScale).clamp(0, 1)),
            blurRadius: 40,
            offset: const Offset(0, -14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: skin.frosted
            ? BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: face,
              )
            : face,
      ),
    );
  }
}

/// 타원 위의 한 자리.
class _Spot {
  const _Spot(this.x, this.y, this.angle);

  final double x;
  final double y;

  /// 타원의 접선 방향(라디안).
  final double angle;

  static _Spot lerp(_Spot a, _Spot b, double t) => _Spot(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        a.angle + (b.angle - a.angle) * t,
      );
}

/// 얼굴이 놓이는 타원. 목업의 값을 그대로 쓴다.
class _DeckGeometry {
  _DeckGeometry(this.width)
      : rx = width * 0.9,
        a = width * 0.9 - 36;

  final double width;

  /// 타원의 가로 반지름.
  final double rx;

  /// 얼굴이 도는 궤도의 가로 반지름. 면보다 안쪽이라 얼굴이 면 위에 앉는다.
  final double a;

  /// 타원의 세로 반지름.
  static const ry = 170.0;

  /// 궤도의 세로 반지름.
  static const b = ry - 36;

  /// 면의 윗선 높이.
  static const ovalTop = 40.0;

  /// 타원 중심의 세로 위치.
  static const centerY = ovalTop + ry;

  static const ovalHeight = ry * 2;

  double get ovalLeft => width / 2 - rx;
  double get ovalWidth => rx * 2;

  _Spot spotAt(int index) {
    final x = width * BottomDeck.spots[index];
    final u = (x - width / 2) / a;
    final root = math.sqrt(math.max(1 - u * u, 0.0001));
    return _Spot(x, centerY - b * root, math.atan(b * u / (a * root)));
  }

  /// 한 칸을 넘기는 데 필요한 가로 이동(px).
  double get pixelsPerStep =>
      width * (BottomDeck.spots[1] - BottomDeck.spots[0]);
}
