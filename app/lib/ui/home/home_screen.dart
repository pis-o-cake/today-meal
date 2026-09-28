/// 오늘 화면.
///
/// 목업 `mockup/canvas/Main.dc.html` 을 옮긴 것이다. 구조는 위에서 아래로
/// 인사 → 대기 표시 → 캐릭터와 등급 → 주 행동 → 신선도 아치 순이다.
///
/// **화면 배색이 고른 등급을 따라 바뀐다.** 목록을 훑는 화면이 아니라 색으로 상황을 읽는
/// 화면이라서, 배경·강조색·캐릭터가 한 등급을 함께 가리킨다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/breakpoints.dart';
import '../../core/design/labels.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../widgets/freshness_arc.dart';
import '../widgets/glass.dart';
import '../widgets/mascot.dart';
import 'home_view_model.dart';

/// 오늘 화면 본문. 하단 탭과 오버레이는 셸이 얹는다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onOpenFridge,
    required this.onOpenMenu,
    this.voiceBar = const SizedBox.shrink(),
    super.key,
  });

  /// 냉장고 탭으로 넘긴다.
  final VoidCallback onOpenFridge;

  /// 메뉴 상세를 연다.
  final void Function(MenuSuggestion suggestion) onOpenMenu;

  /// 호출 대기 표시줄.
  ///
  /// 음성 계층을 여기서 읽지 않고 셸이 [VoiceStatusBar] 를 꽂는다. 이 화면만 따로
  /// 시험할 때 음성 스택을 세우지 않아도 되기 때문이다.
  final Widget voiceBar;

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeViewModel>();
    final palette = Bands.of(home.selected);
    final wide = !context.formFactor.isCompact;

    // 등급을 바꾸면 배경색이 툭 바뀌지 않고 흘러 넘어간다. 궤도가 미끄러지는 동안
    // 배경이 먼저 도착하면 두 동작이 따로 논다.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: palette.bgMid),
      duration: const Duration(milliseconds: 460),
      curve: Curves.easeOut,
      builder: (context, bgMid, child) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: palette.bgEdge),
        duration: const Duration(milliseconds: 460),
        curve: Curves.easeOut,
        builder: (context, bgEdge, child) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.6),
              radius: 1.25,
              colors: [
                Colors.white,
                bgMid ?? palette.bgMid,
                bgEdge ?? palette.bgEdge,
              ],
              stops: const [0, 0.42, 1],
            ),
          ),
          child: child,
        ),
        child: child,
      ),
      child: SafeArea(
        child: Column(
          children: [
            const _Greeting(),
            const SizedBox(height: 10),
            voiceBar,
            // IMPORTANT: 읽지 못한 상태를 "여유 0가지" 로 그리지 않는다. 그렇게 두면
            // 서버가 끊긴 것을 냉장고가 빈 것으로 읽는다.
            Expanded(
              child: switch ((home.loading, home.error)) {
                (true, _) when home.counts.values.every((c) => c == 0) =>
                  const _Pending(),
                (_, final Object error?) => _Failed(
                    error: error,
                    onRetry: () => home.load(),
                  ),
                _ => _Focus(
                    palette: palette,
                    grade: home.selected,
                    count: home.counts[home.selected] ?? 0,
                    batches: home.selectedBatches,
                    maxMascot: wide ? 212 : 164,
                  ),
              },
            ),
            if (home.error == null)
              _Action(
                palette: palette,
                grade: home.selected,
                menu: home.topMenu,
                otherCount: home.otherMenuCount,
                onOpenFridge: onOpenFridge,
                onOpenMenu: onOpenMenu,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: FreshnessArc(
                counts: home.counts,
                selected: home.selected,
                onSelect: home.select,
                hint: Strings.arcHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 날짜와 인사.
class _Greeting extends StatelessWidget {
  const _Greeting();

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
                ?.copyWith(color: Tokens.inkFaint, fontWeight: FontWeight.w600),
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

/// 아직 읽는 중. 캐릭터 자리를 비워두면 화면이 무너져 보인다.
class _Pending extends StatelessWidget {
  const _Pending();

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
                  ?.copyWith(color: Tokens.inkFaint),
            ),
          ],
        ),
      );
}

/// 읽지 못했다. **성공한 것처럼 그리지 않는다.**
class _Failed extends StatelessWidget {
  const _Failed({required this.error, required this.onRetry});

  final Object error;
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
              style: text.bodyMedium?.copyWith(color: Tokens.inkFaint),
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
  });

  final BandPalette palette;
  final Freshness grade;
  final int count;
  final List<IngredientBatch> batches;

  /// 캐릭터의 최대 크기. 남은 높이가 모자라면 이보다 작아진다.
  final double maxMascot;

  /// 칩으로 보여줄 재료 수. 넘치면 접는다 — 여기서 목록을 다 읽게 하지 않는다.
  static const _chipLimit = 3;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shown = batches.take(_chipLimit).toList(growable: false);
    final hidden = batches.length - shown.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        // WARNING: 가로 모드와 작은 태블릿에서는 남은 높이가 캐릭터보다 작다. 고정 크기로
        // 두면 넘쳐 아래가 잘린다. 등급 이름과 칩이 먼저 보여야 하므로 캐릭터를 줄인다.
        final mascot =
            (constraints.maxHeight * 0.42).clamp(72.0, maxMascot);
        return _body(context, text, shown, hidden, mascot);
      },
    );
  }

  Widget _body(
    BuildContext context,
    TextTheme text,
    List<IngredientBatch> shown,
    int hidden,
    double mascot,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Mascot(mood: palette.mood, size: mascot),
          const SizedBox(height: 6),
          Text(
            Labels.freshness(grade),
            style: text.displayLarge?.copyWith(color: palette.accent),
          ),
          const SizedBox(height: 6),
          Text(
            '${Strings.bandCount(count)} · ${Labels.freshnessHint(grade)}',
            textAlign: TextAlign.center,
            style: text.bodyLarge
                ?.copyWith(color: Tokens.inkFaint, fontWeight: FontWeight.w500),
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
                  for (final batch in shown) FloatingChip(label: _describe(batch)),
                  if (hidden > 0) FloatingChip(label: '+$hidden'),
                ],
              ),
            ),
          ),
        ],
      ),
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
    required this.menu,
    required this.otherCount,
    required this.onOpenFridge,
    required this.onOpenMenu,
  });

  final BandPalette palette;
  final Freshness grade;
  final MenuSuggestion? menu;
  final int otherCount;
  final VoidCallback onOpenFridge;
  final void Function(MenuSuggestion suggestion) onOpenMenu;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final menu = this.menu;

    // 기한이 지난 등급에서는 요리를 권하지 않는다. 확인하러 가는 것이 다음 할 일이다.
    final (label, meta, action) = menu == null
        ? (
            grade == Freshness.unknown ? Strings.dateTell : Strings.fridgeOpen,
            '',
            onOpenFridge,
          )
        : (
            menu.name,
            _meta(menu),
            () => onOpenMenu(menu),
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        children: [
          Material(
            color: Colors.white,
            shape: const StadiumBorder(),
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
                          style: text.titleMedium, overflow: TextOverflow.ellipsis),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Text(
                        meta,
                        style: text.bodyMedium?.copyWith(
                            color: Tokens.inkFaint, fontWeight: FontWeight.w500),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Icon(Icons.arrow_forward_rounded, size: 20, color: palette.accent),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: otherCount > 0
                ? TextButton(
                    onPressed: onOpenFridge,
                    child: Text(
                      Strings.menuOthers(otherCount),
                      style: text.bodyMedium?.copyWith(
                          color: Tokens.inkFaint, fontWeight: FontWeight.w600),
                    ),
                  )
                : null,
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
