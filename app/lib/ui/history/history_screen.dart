/// 기록 화면.
///
/// 목업 `mockup/canvas/History.dc.html` 을 옮긴 것이다. 시각 · 종류 · 잔량 변화를 한 줄에
/// 놓는다.
///
/// **수량을 바꾸지 않는 변경은 잔량 칸을 비운다.** 개봉과 이동이 수량을 건드리지 않는다는
/// 사실이 화면에 드러나야 한다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/labels.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/change_record.dart';
import '../widgets/glass.dart';
import '../widgets/screen_scaffold.dart';
import 'history_view_model.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({this.badge = const SizedBox.shrink(), super.key});

  final Widget badge;

  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryViewModel>();
    return ScreenScaffold(
      title: Strings.tabHistory,
      subtitle: Strings.historyUndoHint,
      badge: badge,
      child: switch ((history.loading, history.error)) {
        (true, _) when history.records.isEmpty =>
          const Center(child: CircularProgressIndicator(strokeWidth: 3)),
        (_, final Object error?) => _Failed(error: error, onRetry: history.load),
        _ => _Timeline(records: history.records),
      },
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.records});

  final List<ChangeRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const _Empty();
    final text = Theme.of(context).textTheme;
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 96),
          children: [
            Text(
              Strings.historyToday,
              style: text.labelMedium
                  ?.copyWith(color: Tokens.inkFaint, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            GlassPanel(
              radius: 22,
              solid: true,
              padding: EdgeInsets.zero,
              shadow: Tokens.shadowRaised,
              child: Column(
                children: [
                  for (final (index, record) in records.indexed) ...[
                    if (index > 0)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child:
                            Divider(height: 1, thickness: 1, color: Tokens.hairline),
                      ),
                    _Row(record: record),
                  ],
                ],
              ),
            ),
          ],
        ),
        const Positioned(left: 0, right: 0, bottom: 0, child: ListFade()),
      ],
    );
  }
}

/// 기록 한 줄.
class _Row extends StatelessWidget {
  const _Row({required this.record});

  final ChangeRecord record;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _time(),
                style: text.labelMedium?.copyWith(
                  color: Tokens.inkFaint,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Badge(record: record),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        record.name,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                if (record.isEstimated) ...[
                  const SizedBox(height: 5),
                  // 사용자가 말한 숫자와 앱이 추정한 숫자는 다른 사실이다.
                  InfoChip(label: Strings.historyEstimated),
                ],
                if (record.kind == HistoryKind.state) ...[
                  const SizedBox(height: 5),
                  Text(
                    Strings.historyNoExtraDeduction,
                    style: text.labelMedium?.copyWith(
                        color: Tokens.inkFaint, fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          _Quantity(record: record),
        ],
      ),
    );
  }

  String _time() {
    final at = record.occurredAt.toLocal();
    return '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
  }
}

/// 동작 배지. 되돌린 기록은 색을 달리해 구분한다.
class _Badge extends StatelessWidget {
  const _Badge({required this.record});

  final ChangeRecord record;

  @override
  Widget build(BuildContext context) {
    final reverted = record.reversesEventId != null;
    return InfoChip(
      label: Labels.historyAction(record),
      background: reverted ? Bands.soon.bgEdge : const Color(0xFFECEEF2),
      foreground: reverted ? Bands.soon.accent : const Color(0xFF4E5661),
    );
  }
}

/// 잔량 변화. **수량을 바꾸지 않는 기록은 비운다.**
class _Quantity extends StatelessWidget {
  const _Quantity({required this.record});

  final ChangeRecord record;

  @override
  Widget build(BuildContext context) {
    if (!record.changesQuantity) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final unit = Labels.unit(record.unit);
    final before = record.quantityBefore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (before != null)
          Text(
            '${Labels.number(before)}$unit →',
            style: text.labelMedium
                ?.copyWith(color: Tokens.inkFaint, fontWeight: FontWeight.w600),
          ),
        Text(
          '${Labels.number(record.quantityAfter!)}$unit',
          style: text.titleLarge?.copyWith(fontSize: 22, letterSpacing: -0.9),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            Strings.emptyHint,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Tokens.inkFaint),
          ),
        ),
      );
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
