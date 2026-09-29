/// 오늘 화면 (UI-02).
///
/// 목업 `mockup/canvas/Main.dc.html` 을 옮긴 것이다. 위에서 아래로 인사(오른쪽 위에
/// 날짜 칩) → 호출 상태 칩 → 캐릭터와 등급 → 주 행동 → 타원 유리면(얼굴 다섯 + 탭
/// 다섯) 순이다.
///
/// **화면 배색이 고른 등급을 따라 바뀐다.** 목록을 훑는 화면이 아니라 색으로 상황을 읽는
/// 화면이라서, 배경·강조색·캐릭터가 한 등급을 함께 가리킨다.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/breakpoints.dart';
import '../../core/design/labels.dart';
import '../../core/design/motion.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../widgets/bottom_deck.dart';
import '../widgets/glass.dart';
import '../widgets/glass_nav.dart';
import '../widgets/mascot.dart';
import '../widgets/nav_icons.dart';
import 'home_view_model.dart';
import 'voice_status_bar.dart';

/// 오늘 화면 본문. 대화 오버레이는 셸이 얹는다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onOpenFridge,
    required this.onOpenMenu,
    this.tabs = const [],
    this.currentTab = 0,
    this.onTab,
    this.showVoiceBar = true,
    super.key,
  });

  /// 냉장고 탭으로 넘긴다.
  final VoidCallback onOpenFridge;

  /// 메뉴 상세를 연다.
  final void Function(MenuSuggestion suggestion) onOpenMenu;

  /// 아래 유리면에 함께 얹을 탭.
  ///
  /// 오늘 화면은 유리면 하나가 얼굴과 탭을 모두 품는다. 판을 두 겹 얹으면 화면 아래가
  /// 두 층으로 나뉘어 답답하다.
  final List<NavItem> tabs;
  final int currentTab;
  final ValueChanged<int>? onTab;

  /// 호출 상태 칩을 그릴지.
  ///
  /// 음성 계층 없이 이 화면만 떼어 시험할 때 끈다. 앱에서는 늘 켜져 있다.
  final bool showVoiceBar;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// 궤도 위의 위치(칸 단위, 소수 포함).
  ///
  /// 끄는 동안 화면 전체가 **손가락을 따라** 넘어가게 하는 값이다. 고른 등급만 보면
  /// 손을 뗀 뒤에야 바뀌어 유리면과 본문이 따로 논다.
  final _slide = ValueNotifier<double>(0);
  bool _primed = false;

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeViewModel>();
    // 첫 배치에서 고른 등급 자리로 맞춘다. 0 으로 두면 처음에 지남부터 보인다.
    if (!_primed) {
      _primed = true;
      _slide.value = Bands.ordered.indexOf(home.selected).toDouble();
    }
    return ValueListenableBuilder<double>(
      valueListenable: _slide,
      builder: (context, at, _) => _body(context, home, at),
    );
  }

  Widget _body(BuildContext context, HomeViewModel home, double at) {
    final skin = context.skin;
    final wide = !context.formFactor.isCompact;

    // 끄는 중이면 이웃 두 등급을 섞고, 아니면 고른 등급 그대로다.
    final low = at.floor().clamp(0, Bands.ordered.length - 1);
    final high = at.ceil().clamp(0, Bands.ordered.length - 1);
    final blend = at - low;
    final palette = BandPalette.lerp(
      skin.band(Bands.ordered[low]),
      skin.band(Bands.ordered[high]),
      blend,
    );
    // 본문은 절반을 넘긴 쪽을 보여준다. 글자는 섞을 수 없다.
    final shown = Bands.ordered[blend < 0.5 ? low : high];

    // 배경은 보간한 값을 바로 쓴다. 따로 애니메이션을 걸면 유리면이 미끄러지는 동안
    // 배경만 늦게 도착해 두 동작이 따로 논다.
    return DecoratedBox(
      decoration: BoxDecoration(gradient: skin.background(palette)),
      child: SafeArea(
        child: Column(
          children: [
            _Greeting(skin: skin),
            if (widget.showVoiceBar) ...[
              const SizedBox(height: 10),
              VoiceStatusBar(palette: palette),
            ],
            // IMPORTANT: 읽지 못한 상태를 "넉넉해요 0가지" 로 그리지 않는다. 그렇게 두면
            // 서버가 끊긴 것을 냉장고가 빈 것으로 읽는다.
            Expanded(
              child: switch ((home.loading, home.error)) {
                (true, _) when home.counts.values.every((c) => c == 0) =>
                  _Pending(skin: skin),
                (_, final Object error?) =>
                  _Failed(error: error, skin: skin, onRetry: home.load),
                // 재고가 하나도 없으면 등급을 말하지 않는다. "넉넉해요 0가지" 는
                // 여유가 있다는 뜻으로 읽히지만 사실은 빈 냉장고다.
                _ when home.counts.values.every((c) => c == 0) =>
                  _Empty(skin: skin),
                _ => _Focus(
                    palette: palette,
                    grade: shown,
                    count: home.counts[shown] ?? 0,
                    batches: home.batchesOf(shown),
                    maxMascot: wide ? 212 : 172,
                    skin: skin,
                  ),
              },
            ),
            if (home.error == null && home.counts.values.any((c) => c > 0))
              _Action(
                palette: palette,
                grade: shown,
                skin: skin,
                menus: home.menusFor(shown),
                first: home.batchesOf(shown).firstOrNull?.name,
                onOpenFridge: widget.onOpenFridge,
                onOpenMenu: widget.onOpenMenu,
              ),
            BottomDeck(
              counts: home.counts,
              selected: home.selected,
              onSelect: home.select,
              slide: _slide,
              items: widget.tabs,
              current: widget.currentTab,
              onTab: widget.onTab ?? (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

/// 인사와 날짜 칩.
///
/// 날짜는 인사 **위 오른쪽 구석**이다 — 인사가 화면의 첫 줄이어야 하고, 날짜는 확인용이라
/// 시선의 중심에서 비켜 있어야 한다.
///
/// WARNING: 칩을 제목과 같은 줄에 겹쳐 놓지 않는다. 제목은 글꼴과 글자 수에 따라 폭이
/// 달라져서, 겹쳐 두면 긴 제목에서 날짜 위로 글자가 올라탄다 — 실기기에서 겪었다.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 18, 0),
        child: Column(
          children: [
            SizedBox(
              height: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 13, color: skin.inkFaint),
                  const SizedBox(width: 4),
                  Text(
                    _today(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: skin.inkFaint, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Text(Strings.todayGreeting, style: Tokens.hero(30)),
          ],
        ),
      );

  /// 오늘 날짜. 목업의 `10.2 금` 꼴이다 — 칩에 들어가야 해서 짧게 쓴다.
  String _today() {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final now = DateTime.now();
    return '${now.month}.${now.day} ${weekdays[now.weekday - 1]}';
  }
}

/// 냉장고가 비어 있다. 가입 직후에 늘 보는 화면이다.
class _Empty extends StatelessWidget {
  const _Empty({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => Mascot(
                mood: MascotMood.hello,
                size: (constraints.maxHeight * 0.36).clamp(96.0, 172.0),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              Strings.empty,
              textAlign: TextAlign.center,
              style: text.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              Strings.emptyHint,
              textAlign: TextAlign.center,
              style: text.bodyLarge
                  ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// 아직 읽는 중. 캐릭터 자리를 비워두면 화면이 무너져 보인다.
class _Pending extends StatelessWidget {
  const _Pending({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(
              Strings.serverChecking,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: skin.inkFaint),
            ),
          ],
        ),
      );
}

/// 읽지 못했다. **성공한 것처럼 그리지 않는다.**
class _Failed extends StatelessWidget {
  const _Failed({
    required this.error,
    required this.skin,
    required this.onRetry,
  });

  final Object error;
  final Skin skin;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Mascot(mood: MascotMood.unknown, size: 128),
            const SizedBox(height: 12),
            Text(Strings.serverFailed, style: text.headlineSmall),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(color: skin.inkFaint),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onRetry, child: const Text(Strings.retry)),
          ],
        ),
      ),
    );
  }
}

/// 캐릭터와 등급 이름, 재료 칩.
class _Focus extends StatelessWidget {
  const _Focus({
    required this.palette,
    required this.grade,
    required this.count,
    required this.batches,
    required this.maxMascot,
    required this.skin,
  });

  final BandPalette palette;
  final Freshness grade;
  final int count;
  final List<IngredientBatch> batches;

  /// 캐릭터의 최대 크기. 남은 높이가 모자라면 이보다 작아진다.
  final double maxMascot;
  final Skin skin;

  /// 칩으로 보여줄 재료 수. 넘치면 접는다 — 여기서 목록을 다 읽게 하지 않는다.
  static const _chipLimit = 3;

  /// 등급 이름이 한 줄에 들어가는 글자 크기의 경계. 목업의 값이다.
  static const _longName = 9;
  static const _veryLongName = 12;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shown = batches.take(_chipLimit).toList(growable: false);
    final hidden = batches.length - shown.length;
    final name = Labels.freshness(grade);

    return LayoutBuilder(
      builder: (context, constraints) {
        // WARNING: 가로 모드와 작은 태블릿에서는 남은 높이가 캐릭터보다 작다. 고정 크기로
        // 두면 넘쳐 아래가 잘린다. 등급 이름과 칩이 먼저 보여야 하므로 캐릭터를 줄인다.
        final mascot = (constraints.maxHeight * 0.42).clamp(72.0, maxMascot);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Mascot(mood: palette.mood, size: mascot),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                style: Tokens.hero(_wordSize(name), height: 1.15)
                    .copyWith(color: palette.accent),
              ),
              const SizedBox(height: 6),
              Text(
                '${Strings.bandCount(count)} · ${Labels.freshnessHint(grade)}',
                textAlign: TextAlign.center,
                style: text.bodyLarge
                    ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 14),
              // 칩이 여러 줄로 늘어나도 아래를 밀지 않는다. 잘릴 때는 위쪽 줄부터 남긴다.
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final batch in shown)
                        FloatingChip(label: _describe(batch)),
                      if (hidden > 0) FloatingChip(label: '+$hidden'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 등급 이름의 글자 크기. 긴 문구가 줄바꿈 없이 한 줄에 들어가야 한다.
  static double _wordSize(String name) {
    if (name.length >= _veryLongName) return 36;
    if (name.length >= _longName) return 38;
    return 44;
  }

  /// 칩 한 줄. 이름에 잔량이나 기한 중 **아는 것만** 붙인다.
  ///
  /// 이름과 잔량은 붙여 쓰고("두부 2모") 기한은 가운뎃점으로 뗀다. 셋을 모두 점으로
  /// 이으면 잔량이 별개 항목으로 읽힌다.
  ///
  /// 기한에는 종류를 함께 적는다 — 소비기한과 점검 알림은 같은 `D-1` 이어도 뜻이 다르다.
  String _describe(IngredientBatch batch) {
    final amount = Labels.amount(batch);
    final head = amount.isEmpty ? batch.name : '${batch.name} $amount';

    final days = batch.daysLeft;
    if (days == null) return head;
    final kind = batch.expiryKind;
    final tail = kind == null
        ? Strings.daysLeft(days)
        : '${Labels.dateKind(kind)} ${Strings.daysLeft(days)}';
    return '$head · $tail';
  }
}

/// 주 행동 버튼. 등급마다 다음에 할 일이 다르다.
class _Action extends StatefulWidget {
  const _Action({
    required this.palette,
    required this.grade,
    required this.skin,
    required this.menus,
    required this.first,
    required this.onOpenFridge,
    required this.onOpenMenu,
  });

  final BandPalette palette;
  final Freshness grade;
  final Skin skin;
  final List<MenuSuggestion> menus;

  /// 이 등급의 첫 재료 이름. 요리를 권하지 않는 등급에서 **무엇 때문인지** 말한다.
  final String? first;
  final VoidCallback onOpenFridge;
  final void Function(MenuSuggestion suggestion) onOpenMenu;

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action>
    with SingleTickerProviderStateMixin {
  /// 지금 보여주는 메뉴의 자리.
  int _at = 0;

  /// 한 번의 회전. 0 → 1 이 반 바퀴이며, 0.5 를 지날 때 다음 메뉴로 바뀐다.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: Motion.menuFlip,
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed) _spin.reset();
    });

  /// 도는 속도. 시작과 끝이 느리고 가운데가 빠르다 — 뒤집히는 순간이 가장 빨라야
  /// 글자가 바뀌는 장면이 보이지 않는다.
  late final Animation<double> _turned =
      CurvedAnimation(parent: _spin, curve: Curves.easeInOutCubic);

  Timer? _turn;
  bool _armed = false;

  /// 회전이 반을 넘겼는지. 넘긴 뒤부터 다음 메뉴를 그린다.
  bool _flipped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // IMPORTANT: MediaQuery 는 initState 에서 읽을 수 없다.
    if (_armed) return;
    _armed = true;
    _turned.addListener(_halfway);
    _rearm();
  }

  @override
  void didUpdateWidget(_Action old) {
    super.didUpdateWidget(old);
    // 등급이 바뀌면 메뉴 목록도 바뀐다. 자리를 처음으로 되돌린다.
    if (old.grade != widget.grade || old.menus.length != widget.menus.length) {
      _at = 0;
      _spin.reset();
      _flipped = false;
      _rearm();
    }
  }

  /// 반 바퀴를 돌아 뒷면이 보이는 순간에 내용을 바꾼다.
  ///
  /// 그래야 글자가 바뀌는 장면이 보이지 않는다 — 앞면에서 바꾸면 결국 글자만 바뀌는
  /// 것으로 보인다.
  void _halfway() {
    final past = _turned.value >= 0.5;
    if (past == _flipped) return;
    setState(() {
      _flipped = past;
      if (past) _at = (_at + 1) % widget.menus.length;
    });
  }

  /// 메뉴가 둘 이상일 때만 돌린다.
  ///
  /// 모션 감소에서는 돌리지 않는다 — 스스로 바뀌는 화면은 움직임이며, 읽는 중에 바뀌면
  /// 따라잡을 수 없다. 그때는 첫 메뉴만 보이고 "다른 메뉴 N개" 로 나머지를 알린다.
  void _rearm() {
    _turn?.cancel();
    if (widget.menus.length < 2 || context.reduceMotion) return;
    _turn = Timer.periodic(Motion.menuTurn, (_) {
      if (!mounted || _spin.isAnimating) return;
      _flipped = false;
      _spin.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _turn?.cancel();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final menus = widget.menus;
    final palette = widget.palette;
    final grade = widget.grade;
    final skin = widget.skin;
    final onOpenFridge = widget.onOpenFridge;
    final onOpenMenu = widget.onOpenMenu;

    final menu = menus.isEmpty ? null : menus[_at % menus.length];
    final others = menus.length <= 1 ? 0 : menus.length - 1;

    // 기한이 지난 등급에서는 요리를 권하지 않는다. 확인하러 가는 것이 다음 할 일이다.
    // 날짜를 모르는 등급에서는 기한을 말해달라고 한다.
    final (label, meta, glyph, action) = switch (menu) {
      final MenuSuggestion pick =>
        (pick.name, _meta(pick), _Badge.pot, () => onOpenMenu(pick)),
      null when grade == Freshness.unknown =>
        (Strings.dateTell, Strings.dateTellExample, _Badge.mic, onOpenFridge),
      // 요리를 권하지 않는 등급이다. 무엇 때문에 냉장고로 가는지 함께 적는다.
      null => (
          Strings.fridgeOpen,
          widget.first == null ? '' : Strings.fridgeCheckHint(widget.first!),
          _Badge.fridge,
          onOpenFridge,
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          // 알약 **전체**가 좌에서 우로 반 바퀴 돌고 다음 메뉴가 나온다. 글자만 바뀌면
          // 읽던 사람이 놀란다 — 무엇이 바뀌는지 먼저 보여야 한다.
          AnimatedBuilder(
            animation: _turned,
            builder: (context, child) => Transform(
              alignment: Alignment.center,
              // 원근을 살짝 준다. 없으면 가로로 납작해지기만 하고 도는 것으로 안 보인다.
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(_turned.value * math.pi),
              child: child,
            ),
            child: _pill(context, text, skin, palette, glyph, label, meta, action),
          ),
          // 자리는 늘 지킨다. 메뉴 수에 따라 화면이 위아래로 흔들리지 않는다.
          SizedBox(
            height: 40,
            child: others == 0
                ? null
                : TextButton(
                    onPressed: onOpenFridge,
                    child: Text(
                      Strings.menuOthers(others),
                      style: text.bodyMedium?.copyWith(
                          color: skin.inkFaint, fontWeight: FontWeight.w600),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 알약 한 개. 회전은 바깥에서 건다.
  ///
  /// 반 바퀴를 넘기면 글자가 뒤집혀 보이므로 그 구간만 한 번 더 뒤집는다. 판과 그림자는
  /// 뒤집지 않는다 — 그림자까지 뒤집히면 빛이 반대에서 오는 것으로 보인다.
  Widget _pill(
    BuildContext context,
    TextTheme text,
    Skin skin,
    BandPalette palette,
    int glyph,
    String label,
    String meta,
    VoidCallback action,
  ) {
    // WARNING: 그림자는 면 **바깥**에 있어야 한다. Material 안에 두면 그림자가 흰
    // 면 위에 덧칠돼 알약이 회색으로 보인다 — 실기기에서 겪은 결함이다.
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        shadows: skin.shadowAction,
      ),
      child: Material(
        color: skin.raised,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: action,
          customBorder: const StadiumBorder(),
          child: Container(
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
            child: Transform(
              alignment: Alignment.center,
              // 뒷면에서는 글자가 거울처럼 보인다. 그 구간만 되뒤집어 바로 세운다.
              transform: Matrix4.identity()..rotateY(_flipped ? math.pi : 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Badge(palette: palette, glyph: glyph),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium?.copyWith(height: 1.3),
                        ),
                        if (meta.isNotEmpty)
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelMedium?.copyWith(
                                height: 1.3,
                                color: skin.inkFaint,
                                fontWeight: FontWeight.w500),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.arrow_forward_rounded,
                      size: 20, color: palette.accent),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 인분·시간·재료 상태. 모르는 값은 빼고 아는 것만 잇는다.
  ///
  /// 가용성을 끝에 붙이는 것은 **누르기 전에 만들 수 있는지 알아야** 하기 때문이다.
  String _meta(MenuSuggestion menu) {
    final parts = <String>[Strings.menuServings(menu.servings)];
    final minutes = menu.estimatedMinutes;
    if (minutes != null) parts.add(Strings.menuMinutes(minutes));
    parts.add(Labels.stock(menu.availability));
    return parts.join(' · ');
  }
}

/// 주 행동 앞의 둥근 아이콘 배지.
///
/// 아이콘은 등급이 아니라 **버튼이 무엇을 하는지**를 말한다 — 메뉴를 열면 냄비, 냉장고로
/// 가면 냉장고, 말하게 하면 마이크다. 등급으로 고르면 "냉장고에서 확인하기" 옆에 냄비가
/// 붙는 일이 생긴다.
///
/// 탭 아이콘과 같은 그림을 쓰는 것이 의도다: 누르면 그 탭으로 가기 때문이다.
class _Badge extends StatelessWidget {
  const _Badge({required this.palette, required this.glyph});

  final BandPalette palette;

  /// 어떤 그림을 둘지. [pot]·[fridge]·[mic] 중 하나다.
  final int glyph;

  static const pot = 0;
  static const fridge = 1;
  static const mic = 2;

  static const _size = 46.0;

  @override
  Widget build(BuildContext context) => Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: palette.accentSoft,
          shape: BoxShape.circle,
        ),
        child: Center(child: _drawn()),
      );

  Widget _drawn() => switch (glyph) {
        fridge => NavIcon(
            glyph: NavGlyph.fridge, color: palette.accent, size: 24),
        mic => Icon(Icons.mic_none_rounded, size: 24, color: palette.accent),
        _ => NavIcon(glyph: NavGlyph.cook, color: palette.accent, size: 24),
      };
}
