import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/labels.dart';
import '../../core/design/responsive.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../menu/menu_detail_screen.dart';
import 'home_view_model.dart';

/// 오늘 화면.
///
/// 재고를 **신선도 밴드로 묶어** 세로로 쌓는다. 급한 것이 위로 오고 기한이 지난 것은
/// 요리 후보에서 빠졌다는 사실을 함께 적는다.
///
/// 잔량 미확인은 밴드 등급과 섞지 않고 카드의 별도 뱃지로 둔다 — 숫자를 지어내지 않는다.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    return RefreshIndicator(
      onRefresh: vm.load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: Tokens.gutterWide * 3),
        children: [
          ContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ConditionHeader(condition: vm.condition),
                const SizedBox(height: Tokens.gapCard),
                if (vm.loading && vm.bands.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(Tokens.gutterWide),
                    child: CircularProgressIndicator(),
                  ))
                else if (vm.error != null && vm.bands.isEmpty)
                  _ErrorBox(error: vm.error!, onRetry: vm.load)
                else if (vm.bands.isEmpty)
                  const _EmptyBox()
                else
                  for (final band in vm.bands) ...[
                    _BandCard(band: band),
                    const SizedBox(height: Tokens.gapCard),
                  ],
                if (vm.menus.isNotEmpty) _MenuSection(menus: vm.menus),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConditionHeader extends StatelessWidget {
  const _ConditionHeader({required this.condition});

  final FridgeCondition condition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Strings.appName, style: theme.textTheme.titleLarge),
              const SizedBox(height: Tokens.gapTight),
              Text(
                Strings.emptyHint,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // 등급 계산은 서버가 한다. 앱은 담기만 한다.
        Chip(
          label: Text(Labels.condition(condition.condition)),
          backgroundColor: switch (condition.condition) {
            Condition.urgent => Tokens.alert.withValues(alpha: 0.18),
            Condition.attention => Tokens.warm.withValues(alpha: 0.18),
            Condition.relaxed => Tokens.lime.withValues(alpha: 0.18),
          },
        ),
      ],
    );
  }
}

class _BandCard extends StatelessWidget {
  const _BandCard({required this.band});

  final FreshnessBand band;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Labels.freshnessColor(band.grade);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.gapCard),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 4, height: 20, color: color),
                const SizedBox(width: Tokens.gapTight),
                Text(
                  Labels.freshness(band.grade),
                  style: theme.textTheme.titleLarge?.copyWith(color: color),
                ),
                const SizedBox(width: Tokens.gapTight),
                Text(
                  '${Strings.bandCount(band.count)} · '
                  '${Labels.freshnessHint(band.grade)}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: Tokens.gapCard),
            Wrap(
              spacing: Tokens.gapTight,
              runSpacing: Tokens.gapTight,
              children: [for (final batch in band.batches) _BatchChip(batch: batch)],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchChip extends StatelessWidget {
  const _BatchChip({required this.batch});

  final IngredientBatch batch;

  @override
  Widget build(BuildContext context) {
    final days = batch.daysLeft;
    final suffix = days != null ? ' ${Strings.daysLeft(days)}' : '';
    return Chip(
      label: Text('${batch.name}$suffix'),
      // 잔량 미확인은 등급과 다른 사실이다. 별도 표시로 둔다.
      avatar: batch.quantityUncertain
          ? const Icon(Icons.help_outline, size: 16)
          : null,
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({required this.menus});

  final List<MenuSuggestion> menus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${Strings.menuSectionTitle} — ${Strings.menuSectionHint}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: Tokens.gapCard),
        for (final menu in menus) ...[
          _MenuCard(menu: menu),
          const SizedBox(height: Tokens.gapCard),
        ],
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.menu});

  final MenuSuggestion menu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.cardRadius),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MenuDetailScreen(
              recipeId: menu.recipeId,
              servings: menu.servings,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Tokens.gapCard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(menu.name, style: theme.textTheme.headlineMedium),
                  ),
                  // 필수 재료가 없으면 '지금 가능' 이 아니다. 판정은 서버가 한다.
                  Chip(
                    label: Text(Labels.availability(menu.availability)),
                    backgroundColor: menu.availability.isReady
                        ? Tokens.lime.withValues(alpha: 0.18)
                        : Tokens.warm.withValues(alpha: 0.18),
                  ),
                ],
              ),
              if (menu.reason != null) ...[
                const SizedBox(height: Tokens.gapTight),
                Text(menu.reason!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: Tokens.gapTight),
              Wrap(
                spacing: Tokens.gapTight,
                runSpacing: Tokens.gapTight,
                children: [
                  Text(
                    Strings.menuServings(menu.servings),
                    style: theme.textTheme.labelLarge,
                  ),
                  if (menu.estimatedMinutes != null)
                    Text(
                      Strings.menuMinutes(menu.estimatedMinutes!),
                      style: theme.textTheme.labelLarge,
                    ),
                  for (final name in menu.priorityIngredients)
                    Chip(label: Text(name)),
                  for (final name in menu.missingIngredients)
                    Chip(
                      label: Text('$name 부족'),
                      backgroundColor: Tokens.alert.withValues(alpha: 0.18),
                    ),
                  for (final name in menu.uncertainIngredients)
                    Chip(
                      label: Text('$name 확인'),
                      backgroundColor: Tokens.warm.withValues(alpha: 0.18),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Tokens.gutterWide),
      child: Column(
        children: [
          Text(Strings.empty, style: theme.textTheme.titleLarge),
          const SizedBox(height: Tokens.gapTight),
          Text(
            Strings.emptyHint,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.error, required this.onRetry});

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Tokens.gapCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Strings.serverFailed,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: Tokens.gapTight),
          // 실패 원인을 숨기지 않는다. 개발 중 진단이 화면에서 끝나야 한다.
          Text('$error', style: theme.textTheme.bodyMedium),
          const SizedBox(height: Tokens.gapTight),
          TextButton(onPressed: onRetry, child: const Text(Strings.retry)),
        ],
      ),
    );
  }
}
