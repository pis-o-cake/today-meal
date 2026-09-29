/// 오늘 화면 (UI-02).
///
/// 목업 `mockup/canvas/Main.dc.html` 을 옮긴 것이다. 위에서 아래로 날짜 → 인사 →
/// 호출 상태 칩 → 캐릭터와 등급 → 주 행동 → 타원 유리면(얼굴 다섯 + 탭 넷) 순이다.
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
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../widgets/bottom_deck.dart';
import '../widgets/glass.dart';
import '../widgets/glass_nav.dart';
import '../widgets/mascot.dart';
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

/// 날짜와 인사.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        children: [
          Text(
            _today(),
            style: text.bodyMedium
                ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(Strings.todayGreeting, style: text.headlineMedium),
        ],
      ),
    );
  }

  /// 오늘 날짜. 요일까지 붙여 "지금"임을 분명히 한다.
  String _today() {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final now = DateTime.now();
    return '${now.month}월 ${now.day}일 ${weekdays[now.weekday - 1]}요일';
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

  /// 이 길이를 넘는 등급 이름은 한 줄에 들어가지 않아 한 단계 줄인다.
  static const _longName = 7;

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
                style: (name.length > _longName
                        ? text.displayMedium
                        : text.displayLarge)
                    ?.copyWith(color: palette.accent),
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
    final (label, meta, action) = switch (menu) {
      final MenuSuggestion pick => (pick.name, _meta(pick), () => onOpenMenu(pick)),
      null when grade == Freshness.unknown =>
        (Strings.dateTell, Strings.dateTellExample, onOpenFridge),
      null => (Strings.fridgeOpen, '', onOpenFridge),
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
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.only(left: 22, right: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(label,
                            style: text.titleMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            meta,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium?.copyWith(
                                color: skin.inkFaint,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
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
