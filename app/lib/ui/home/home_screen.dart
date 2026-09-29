/// 오늘 화면 (UI-02).
///
/// 목업 `mockup/canvas/Main.dc.html` 을 옮긴 것이다. 위에서 아래로 인사(오른쪽 위에
/// 날짜 칩) → 호출 상태 칩 → 캐릭터와 등급 → 주 행동 → 타원 유리면(얼굴 다섯 + 탭
/// 다섯) 순이다.
///
/// **화면 배색이 고른 등급을 따라 바뀐다.** 목록을 훑는 화면이 아니라 색으로 상황을 읽는
/// 화면이라서, 배경·강조색·캐릭터가 한 등급을 함께 가리킨다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/breakpoints.dart';
import '../../core/design/labels.dart';
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
  String _describe(IngredientBatch batch) {
    final parts = <String>[batch.name];
    final amount = Labels.amount(batch);
    if (amount.isNotEmpty) parts.add(amount);
    final days = batch.daysLeft;
    if (days != null) parts.add(Strings.daysLeft(days));
    return parts.join(' · ');
  }
}

/// 주 행동 버튼. 등급마다 다음에 할 일이 다르다.
class _Action extends StatelessWidget {
  const _Action({
    required this.palette,
    required this.grade,
    required this.skin,
    required this.menus,
    required this.onOpenFridge,
    required this.onOpenMenu,
  });

  final BandPalette palette;
  final Freshness grade;
  final Skin skin;
  final List<MenuSuggestion> menus;
  final VoidCallback onOpenFridge;
  final void Function(MenuSuggestion suggestion) onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final menu = menus.firstOrNull;
    final others = menus.length <= 1 ? 0 : menus.length - 1;

    // 기한이 지난 등급에서는 요리를 권하지 않는다. 확인하러 가는 것이 다음 할 일이다.
    // 날짜를 모르는 등급에서는 기한을 말해달라고 한다.
    final (label, meta, glyph, action) = switch (menu) {
      final MenuSuggestion pick =>
        (pick.name, _meta(pick), _Badge.pot, () => onOpenMenu(pick)),
      null when grade == Freshness.unknown =>
        (Strings.dateTell, Strings.dateTellExample, _Badge.mic, onOpenFridge),
      null => (Strings.fridgeOpen, '', _Badge.fridge, onOpenFridge),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          Material(
            color: skin.raised,
            shape: const StadiumBorder(),
            // 목업의 두 겹 그림자. 화면에서 가장 앞에 있어야 한다.
            elevation: 0,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: const StadiumBorder(),
                shadows: skin.shadowAction,
              ),
              child: InkWell(
                onTap: action,
                customBorder: const StadiumBorder(),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 62),
                  padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Badge(palette: palette, glyph: glyph),
                      const SizedBox(width: 12),
                      // 이름과 곁들이는 값을 두 줄로 쌓는다. 한 줄에 이으면 긴 이름에서
                      // 인분·시간이 먼저 잘려 정작 필요한 정보가 사라진다.
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

  /// 인분과 시간. 모르는 값은 빼고 아는 것만 잇는다.
  String _meta(MenuSuggestion menu) {
    final parts = <String>[Strings.menuServings(menu.servings)];
    final minutes = menu.estimatedMinutes;
    if (minutes != null) parts.add(Strings.menuMinutes(minutes));
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
