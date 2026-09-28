import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/design/labels.dart';
import '../../core/design/responsive.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/change_record.dart';
import 'history_view_model.dart';

/// 변경 기록 화면.
///
/// 수량 변경과 상태 변경을 한 타임라인에 섞는다. **상태 변경은 잔량 칸이 비어 있어**
/// 개봉과 이동이 수량을 바꾸지 않는다는 사실이 드러난다.
///
/// 역산 이벤트에는 "추가 차감 없음"을 붙인다 — 정정이 중복 차감하지 않았다는 것을
/// 사용자가 확인할 수 있어야 한다.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HistoryViewModel>();
    final time = DateFormat.Hm('ko');
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
                  '${Strings.tabHistory} · ${Strings.historyToday}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: Tokens.gapCard),
                if (vm.loading && vm.records.isEmpty)
                  const Center(child: CircularProgressIndicator())
                else
                  for (final record in vm.records) ...[
                    _Row(record: record, time: time),
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

class _Row extends StatelessWidget {
  const _Row({required this.record, required this.time});

  final ChangeRecord record;
  final DateFormat time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Tokens.gapCard),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 48,
              child: Text(
                time.format(record.occurredAt),
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: Tokens.gapTight),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        Labels.historyAction(record),
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(width: Tokens.gapTight),
                      Text(record.name, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                  if (record.reversesEventId != null)
                    Text(
                      '(${Strings.historyNoExtraDeduction})',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 상태 변경은 수량을 바꾸지 않는다. 칸을 비워 그 사실을 드러낸다.
                Text(
                  record.changesQuantity
                      ? '${record.quantityAfter}${record.unit ?? ''}'
                      : '—',
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  record.isEstimated
                      ? Strings.historyEstimated
                      : Strings.historyExplicit,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: record.isEstimated
                        ? Tokens.warm
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
