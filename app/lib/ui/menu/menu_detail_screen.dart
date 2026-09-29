/// 메뉴 상세 (UI-07).
///
/// 목업 `Menu.dc.html` 이다 — 가용성 칩, 이름, 시간, 먼저 쓰는 이유, 인분, 재료 상태,
/// 조리 순서, 조리 모드.
///
/// **조회와 조리 모드는 재고를 바꾸지 않는다.** 목업 인계대로 레시피 일괄 차감("해먹었어요")
/// 을 노출하지 않는다 — 레시피 분량은 실제로 쓴 양이 아니라서, 눌러 차감하면 냉장고가
/// 사실과 달라진다. 실제 사용량은 "계란 두 개 썼어" 처럼 명시 발화로 반영한다.
///
/// 조리 모드는 화면을 켜 두기만 한다. 전경에서만 유지하며 나가면 해제한다.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/design/band.dart';
import '../../core/design/labels.dart';
import '../../core/design/responsive.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/di.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../../domain/repository/repositories.dart';
import '../widgets/glass.dart';
import '../widgets/nav_icons.dart';
import '../widgets/mascot.dart';

class MenuDetailScreen extends StatefulWidget {
  const MenuDetailScreen({
    required this.recipeId,
    this.suggestionId,
    this.servings,
    this.onStartCooking,
    super.key,
  });

  final int recipeId;

  /// 어느 추천에서 들어왔는지. 이력을 잇는 값이며 차감에 쓰지 않는다.
  final int? suggestionId;

  final int? servings;

  /// 조리 진행 화면으로 넘긴다.
  ///
  /// 없으면 버튼이 화면을 켜 두는 조리 모드로만 동작한다 — 이 화면만 떼어 시험할 때다.
  final void Function(MenuDetail detail)? onStartCooking;

  @override
  State<MenuDetailScreen> createState() => _MenuDetailScreenState();
}

class _MenuDetailScreenState extends State<MenuDetailScreen>
    with WidgetsBindingObserver {
  MenuDetail? _detail;
  Object? _error;
  bool _cooking = false;
  late int _servings = widget.servings ?? 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 화면을 떠나면 유지 요청을 반드시 해제한다. 남겨 두면 배터리를 먹는다.
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 조리 모드는 전경에서만 유지한다. 배경에서 켜 두면 사용자가 모르는 채로 계속 돈다.
    if (!_cooking) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(WakelockPlus.enable());
    } else {
      unawaited(WakelockPlus.disable());
    }
  }

  Future<void> _load() async {
    try {
      final detail =
          await di<MenuRepository>().detail(widget.recipeId, servings: _servings);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  Future<void> _toggleCooking() async {
    final next = !_cooking;
    setState(() => _cooking = next);
    await (next ? WakelockPlus.enable() : WakelockPlus.disable());
  }

  void _changeServings(int next) {
    if (next < 1 || next > 8) return;
    setState(() => _servings = next);
    unawaited(_load());
  }

  /// 조리를 시작한다.
  ///
  /// 단계 화면이 화면을 켜 두고 호출어 없이 듣는다. 여기서 화면만 켜 두던 예전 조리 모드는
  /// 그 화면이 대신하므로, 넘길 곳이 있으면 넘긴다.
  void _start(MenuDetail detail) {
    final go = widget.onStartCooking;
    if (go == null) {
      unawaited(_toggleCooking());
      return;
    }
    go(detail);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final detail = _detail;

    return Scaffold(
      // 다른 화면과 같은 배색을 쓴다. 이 화면만 흰 판이면 떠 보인다.
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: skin.ink,
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: skin.listBackground),
        child: SafeArea(
          child: switch ((detail, _error)) {
            (_, final Object error?) => _Failed(error: error, onRetry: _load),
            (null, _) => const Center(child: CircularProgressIndicator()),
            (final MenuDetail ready, _) => Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.only(bottom: 160),
                    children: [
                      ContentFrame(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Head(detail: ready, skin: skin),
                            const SizedBox(height: Tokens.gapCard),
                            _Servings(
                              servings: ready.servings,
                              skin: skin,
                              onChange: _changeServings,
                            ),
                            const SizedBox(height: Tokens.gapCard),
                            _Ingredients(detail: ready, skin: skin),
                            const SizedBox(height: Tokens.gapCard),
                            _Steps(detail: ready, skin: skin),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _CookBar(
                      cooking: _cooking,
                      skin: skin,
                      onToggle: () => _start(ready),
                    ),
                  ),
                ],
              ),
          },
        ),
      ),
    );
  }
}

/// 가용성 · 이름 · 시간 · 먼저 쓰는 이유.
class _Head extends StatelessWidget {
  const _Head({required this.detail, required this.skin});

  final MenuDetail detail;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final minutes = detail.estimatedMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(detail.name, style: Tokens.hero(32)),
        if (minutes != null) ...[
          const SizedBox(height: 6),
          Text(
            // 추정이라는 사실을 함께 적는다. 숫자만 두면 보장으로 읽힌다.
            '${Strings.menuMinutes(minutes)} · ${Strings.menuMinutesCaveat}',
            style: text.bodyLarge
                ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
          ),
        ],
      ],
    );
  }
}

/// 인분 조절. 값을 바꾸면 서버가 환산한 분량을 다시 읽는다.
class _Servings extends StatelessWidget {
  const _Servings({
    required this.servings,
    required this.skin,
    required this.onChange,
  });

  final int servings;
  final Skin skin;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(Strings.menuServingsLabel, style: text.titleSmall),
        GlassPill(
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _round(context, Icons.remove_rounded, servings > 1,
                  () => onChange(servings - 1), false),
              SizedBox(
                width: 64,
                child: Text(
                  Strings.menuServings(servings),
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(fontSize: 18),
                ),
              ),
              _round(context, Icons.add_rounded, servings < 8,
                  () => onChange(servings + 1), true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _round(BuildContext context, IconData icon, bool on, VoidCallback onTap,
          bool filled) =>
      SizedBox(
        width: Tokens.tap,
        height: Tokens.tap,
        child: IconButton(
          onPressed: on ? onTap : null,
          iconSize: 20,
          color: filled ? skin.onStrong : skin.ink,
          disabledColor: skin.inkDim,
          style: IconButton.styleFrom(
            backgroundColor: filled && on ? skin.strong : Colors.transparent,
          ),
          icon: Icon(icon),
        ),
      );
}

class _Ingredients extends StatelessWidget {
  const _Ingredients({required this.detail, required this.skin});

  final MenuDetail detail;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassPanel(
      radius: Tokens.radiusPanel,
      weight: GlassWeight.thick,
      padding: const EdgeInsets.symmetric(vertical: 6),
      shadow: [skin.shade(0.06, 18, 6)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(Strings.menuIngredients, style: text.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text(
                  Strings.menuServingsBasis(detail.servings),
                  style: text.labelMedium
                      ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          for (final item in detail.ingredients)
            _IngredientRow(item: item, skin: skin),
        ],
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({required this.item, required this.skin});

  final RecipeIngredient item;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // 색만으로 구분하지 않는다. 아이콘 모양과 문구도 함께 바꾼다.
    final (icon, band, label) = switch (item.status) {
      IngredientStatus.have => (
          Icons.check_rounded,
          Freshness.fresh,
          Strings.menuHave,
        ),
      IngredientStatus.needsCheck => (
          Icons.help_outline_rounded,
          Freshness.soon,
          Strings.menuNeedsCheck,
        ),
      IngredientStatus.missing => (
          Icons.remove_rounded,
          Freshness.urgent,
          Strings.menuMissing,
        ),
    };
    final palette = skin.band(band);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: palette.accentSoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 15, color: palette.accent),
            ),
            const SizedBox(width: 10),
            Text(
              item.name,
              style: text.titleSmall?.copyWith(
                // 필수 재료를 구분한다. 없으면 요리가 성립하지 않는다.
                fontWeight: item.isEssential ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                // 분량을 모르면 숫자를 만들지 않는다.
                item.requiredAmount == null
                    ? Strings.quantityUnknown
                    : '${Labels.number(item.requiredAmount!)}'
                        '${Labels.unit(item.unit)}',
                style: text.bodyMedium?.copyWith(
                    color: skin.inkFaint, fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              label,
              style: text.labelMedium
                  ?.copyWith(color: palette.accent, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.detail, required this.skin});

  final MenuDetail detail;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassPanel(
      radius: Tokens.radiusPanel,
      weight: GlassWeight.thick,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      shadow: [skin.shade(0.06, 18, 6)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Strings.menuSteps,
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          for (final (index, step) in detail.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration:
                        BoxDecoration(color: skin.strong, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text(
                      '${index + 1}',
                      style: text.labelLarge?.copyWith(color: skin.onStrong),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        step,
                        style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w500, height: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 조리 모드 버튼과 안내.
///
/// 목업의 아래 고정 영역이다. 배경 그라데이션으로 본문이 이 아래로 사라지게 한다.
class _CookBar extends StatelessWidget {
  const _CookBar({
    required this.cooking,
    required this.skin,
    required this.onToggle,
  });

  final bool cooking;
  final Skin skin;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final edge = skin.neutral.bgEdge;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [edge.withValues(alpha: 0), edge],
          stops: const [0, 0.34],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 16),
        child: Column(
          children: [
            SizedBox(
              height: 56,
              width: double.infinity,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: cooking ? skin.chipNeutral : skin.strong,
                  shape: const StadiumBorder(),
                  shadows: cooking ? null : [skin.shade(0.22, 22, 10)],
                ),
                child: InkWell(
                  onTap: onToggle,
                  customBorder: const StadiumBorder(),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      cooking
                          ? Icon(Icons.stop_circle_outlined,
                              size: 20, color: skin.ink)
                          : NavIcon(
                              glyph: NavGlyph.cook,
                              color: skin.onStrong,
                              size: 20),
                      const SizedBox(width: 8),
                      Text(
                        cooking ? Strings.cookModeStop : Strings.cookModeStart,
                        style: text.titleMedium?.copyWith(
                            color: cooking ? skin.ink : skin.onStrong),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Strings.cookModeHint,
              textAlign: TextAlign.center,
              style: text.labelMedium?.copyWith(
                  color: skin.inkFaint, fontWeight: FontWeight.w500, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Mascot(mood: MascotMood.unknown, size: 112),
            const SizedBox(height: 12),
            Text(Strings.serverFailed, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.bodyMedium?.copyWith(color: skin.inkFaint),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
                onPressed: onRetry, child: const Text(Strings.retry)),
          ],
        ),
      ),
    );
  }
}
