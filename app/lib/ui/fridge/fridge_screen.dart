/// 냉장고 화면.
///
/// 목업 `mockup/canvas/Fridge.dc.html` 을 옮긴 것이다. 신선도 등급으로 묶고 **급한 것부터**
/// 쌓는다. 오늘 화면이 한 등급을 크게 보여준다면 여기는 전부를 훑는 화면이다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/labels.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../widgets/freshness_arc.dart';
import '../widgets/glass.dart';
import '../widgets/screen_scaffold.dart';
import 'fridge_view_model.dart';

class FridgeScreen extends StatelessWidget {
  const FridgeScreen({this.badge = const SizedBox.shrink(), super.key});

  /// 호출 대기 배지. 셸이 꽂는다.
  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final fridge = context.watch<FridgeViewModel>();
    return ScreenScaffold(
      title: Strings.tabFridge,
      badge: badge,
      header: _Filters(fridge: fridge),
      child: switch ((fridge.loading, fridge.error)) {
        (true, _) when fridge.totalCount == 0 =>
          const Center(child: CircularProgressIndicator(strokeWidth: 3)),
        (_, final Object error?) => _Failed(error: error, onRetry: fridge.load),
        _ => _Sections(sections: fridge.sections),
      },
    );
  }
}

/// 검색과 보관 위치.
class _Filters extends StatelessWidget {
  const _Filters({required this.fridge});

  final FridgeViewModel fridge;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassPanel(
          radius: 16,
          solid: true,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shadow: Tokens.shadowRaised,
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const Icon(Icons.search_rounded, size: 20, color: Tokens.inkFaint),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    onChanged: fridge.search,
                    style: text.bodyLarge
                        ?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: Strings.fridgeSearchHint,
                      hintStyle: text.bodyLarge?.copyWith(
                          fontSize: 16, color: Tokens.inkFaint),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _chip(context, Strings.fridgeAll, null),
              for (final storage in StorageLocation.values)
                _chip(context, Labels.storage(storage), storage),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${Strings.itemCount(fridge.visible.length)} · ${Strings.fridgeSortHint}',
          style: text.labelMedium
              ?.copyWith(color: Tokens.inkFaint, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, StorageLocation? value) {
    final on = fridge.storage == value;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => fridge.filterStorage(value),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: on ? Tokens.ink : Tokens.glass,
            shape: StadiumBorder(
              side: BorderSide(color: on ? Tokens.ink : Tokens.glassEdge),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Center(
              child: Text(
                label,
                style: text.bodyLarge?.copyWith(
                  color: on ? Colors.white : Tokens.inkMuted,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 등급별 묶음 목록.
class _Sections extends StatelessWidget {
  const _Sections({required this.sections});

  final List<FridgeSection> sections;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const _Empty();
    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          itemCount: sections.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, index) => _Section(section: sections[index]),
        ),
        const Positioned(left: 0, right: 0, bottom: 0, child: ListFade()),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section});

  final FridgeSection section;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final palette = Bands.of(section.grade);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 오늘 화면의 아치와 같은 얼굴이다. 등급을 얼굴로도 익히게 한다.
            GradeFace(grade: section.grade, size: 26),
            const SizedBox(width: 8),
            Text(
              Labels.freshness(section.grade),
              style: text.titleMedium
                  ?.copyWith(fontSize: 16, color: palette.accent),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${Strings.bandCount(section.batches.length)} · '
                '${Labels.freshnessHint(section.grade)}',
                overflow: TextOverflow.ellipsis,
                style: text.labelMedium
                    ?.copyWith(color: Tokens.inkFaint, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GlassPanel(
          radius: Tokens.radiusTile,
          solid: true,
          padding: EdgeInsets.zero,
          shadow: Tokens.shadowRaised,
          child: Column(
            children: [
              for (final (index, batch) in section.batches.indexed) ...[
                if (index > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(height: 1, thickness: 1, color: Tokens.hairline),
                  ),
                _Row(batch: batch),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 재료 한 줄.
class _Row extends StatelessWidget {
  const _Row({required this.batch});

  final IngredientBatch batch;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final amount = Labels.amount(batch);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(batch.name, style: text.titleMedium),
                const SizedBox(height: 3),
                Text(
                  _meta(),
                  style: text.labelMedium?.copyWith(
                      color: Tokens.inkFaint, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                // 잔량을 모르면 숫자를 만들지 않는다.
                amount.isEmpty ? Strings.quantityUnknown : amount,
                style: text.titleLarge?.copyWith(
                  fontSize: 18,
                  color: amount.isEmpty ? Tokens.inkFaint : Tokens.ink,
                ),
              ),
              if (batch.storage != StorageLocation.unknown) ...[
                const SizedBox(height: 3),
                InfoChip(label: Labels.storage(batch.storage)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// 기한 줄. 모르는 것은 모른다고 적는다.
  String _meta() {
    final days = batch.daysLeft;
    final kind = batch.expiryKind;
    if (days == null || kind == null) return Strings.dateUnknown;
    return '${Labels.dateKind(kind)} ${Strings.daysLeft(days)}';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Strings.empty, textAlign: TextAlign.center, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              Strings.emptyHint,
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: Tokens.inkFaint),
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
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Strings.serverFailed, style: text.titleMedium),
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
