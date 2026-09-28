import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/labels.dart';
import '../../core/design/responsive.dart';
import '../../core/design/band.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import 'fridge_view_model.dart';

/// 냉장고 화면.
///
/// 재료마다 기한 종류·날짜·남은 날과 잔량을 함께 보여준다. **잔량 미확인은 숫자를 지어내지
/// 않고** 그대로 표시하며, 기한 종류를 밝혀 무엇 때문인지 알 수 있게 한다.
class FridgeScreen extends StatelessWidget {
  const FridgeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<FridgeViewModel>();
    return RefreshIndicator(
      onRefresh: vm.load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: Tokens.gutterWide * 3),
        children: [
          ContentFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${Strings.tabFridge} · ${Strings.itemCount(vm.totalCount)}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: Tokens.gapCard),
                TextField(
                  onChanged: vm.search,
                  decoration: const InputDecoration(
                    hintText: Strings.fridgeSearchHint,
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: Tokens.gapCard),
                _StorageFilter(vm: vm),
                const SizedBox(height: Tokens.gapCard),
                if (vm.loading && vm.visible.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else
                  for (final batch in vm.visible) ...[
                    _BatchRow(batch: batch),
                    const SizedBox(height: Tokens.gapTight),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageFilter extends StatelessWidget {
  const _StorageFilter({required this.vm});

  final FridgeViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Tokens.gapTight,
      children: [
        FilterChip(
          label: const Text(Strings.fridgeAll),
          selected: vm.storage == null,
          onSelected: (_) => vm.filterStorage(null),
        ),
        for (final value in StorageLocation.values)
          FilterChip(
            label: Text(Labels.storage(value)),
            selected: vm.storage == value,
            onSelected: (_) => vm.filterStorage(value),
          ),
      ],
    );
  }
}

class _BatchRow extends StatelessWidget {
  const _BatchRow({required this.batch});

  final IngredientBatch batch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = Labels.freshnessColor(batch.freshness);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.gapCard),
        child: Row(
          children: [
            Container(width: 4, height: 40, color: color),
            const SizedBox(width: Tokens.gapCard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(batch.name, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    _dateLine(batch),
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  batch.hasAmount ? batch.amountLabel : Strings.quantityUnknown,
                  style: theme.textTheme.bodyLarge,
                ),
                // 잔량 미확인은 기한 등급과 다른 사실이다. 따로 표시한다.
                if (batch.quantityUncertain && batch.hasAmount)
                  Text(
                    Strings.quantityUnknown,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: Bands.soon.accent),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 기한 한 줄. **종류를 밝힌다** — 제조일과 소비기한은 다른 정보다.
  String _dateLine(IngredientBatch batch) {
    final kind = batch.expiryKind;
    final days = batch.daysLeft;
    final storage = Labels.storage(batch.storage);
    if (kind == null || days == null) {
      return '${Strings.dateUnknown} · $storage';
    }
    return '${Labels.dateKind(kind)} ${Strings.daysLeft(days)} · $storage';
  }
}
