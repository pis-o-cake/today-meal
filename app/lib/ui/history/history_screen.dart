/// 기록 화면 (UI-08).
///
/// 목업 `mockup/canvas/History.dc.html` 을 옮긴 것이다. **말한 문장(오른쪽) → 바뀐 결과
/// (왼쪽)** 의 대화로 보여준다. 목록이 아니라 대화인 이유는, 이 앱에서 재고가 바뀌는
/// 유일한 길이 말이기 때문이다. 내가 뭐라고 했더니 뭐가 바뀌었는지가 한 쌍으로 읽혀야
/// 잘못된 것을 찾아낼 수 있다.
///
/// **수량을 바꾸지 않는 변경은 잔량 칸을 비운다.** 개봉과 이동이 수량을 건드리지 않는다는
/// 사실이 화면에 드러나야 한다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/labels.dart';
import '../../core/design/skin.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/change_record.dart';
import '../../domain/model/inventory.dart';
import '../widgets/glass.dart';
import '../widgets/mascot.dart';
import '../widgets/screen_scaffold.dart';
import 'history_view_model.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final history = context.watch<HistoryViewModel>();
    final skin = context.skin;
    final text = Theme.of(context).textTheme;

    // 되돌리기 실패는 목록을 지우지 않고 한 번 알린다. 성공 토스트는 띄우지 않는다.
    if (history.undoError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || history.undoError == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(Strings.historyUndoFailed),
            backgroundColor: skin.strong,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: Strings.retry,
              textColor: skin.onStrong,
              onPressed: history.load,
            ),
          ),
        );
        history.clearUndoError();
      });
    }

    return ListScreen(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(Strings.historyTitle, style: text.headlineMedium),
          ),
          const SizedBox(height: 2),
          Text(
            Strings.historyUndoHint,
            style: text.bodyMedium
                ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
          ),
        ],
      ),
      child: switch ((history.loading, history.error)) {
        (true, _) when history.records.isEmpty =>
          const Center(child: CircularProgressIndicator(strokeWidth: 3)),
        (_, final Object error?) => _Failed(error: error, onRetry: history.load),
        _ => _Conversation(
            records: history.records,
            onUndo: history.undo,
            undoing: history.undoing,
          ),
      },
    );
  }
}

class _Conversation extends StatelessWidget {
  const _Conversation({
    required this.records,
    required this.onUndo,
    required this.undoing,
  });

  final List<ChangeRecord> records;
  final Future<void> Function(ChangeRecord record) onUndo;
  final bool undoing;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) return const _Empty();

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 108),
          itemCount: records.length,
          separatorBuilder: (_, _) => const SizedBox(height: 18),
          itemBuilder: (context, index) {
            final record = records[index];
            // 날이 바뀌는 자리에만 묶음 이름을 끼운다. 목업의 "오늘 저녁" 칩이다.
            final previous = index == 0 ? null : records[index - 1];
            final newDay = previous == null ||
                !_sameDay(previous.occurredAt, record.occurredAt);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (newDay) ...[
                  _DayChip(at: record.occurredAt),
                  const SizedBox(height: 18),
                ],
                _Turn(
                  record: record,
                  // 되돌리기는 가장 최근 것에만 준다. 중간을 되돌리면 그 뒤가 무슨 뜻인지
                  // 알 수 없어진다.
                  canUndo: index == 0 && record.reversesEventId == null,
                  undoing: undoing,
                  onUndo: () => onUndo(record),
                ),
              ],
            );
          },
        ),
        const Positioned(left: 0, right: 0, bottom: 0, child: ListFade()),
      ],
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 날짜 묶음 이름. 오늘은 "오늘", 그 전은 날짜로 적는다.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final now = DateTime.now();
    final local = at.toLocal();
    final today = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    // 연도까지 적는다. UI 계약대로 화면 날짜는 YYYY.MM.DD 다.
    final label = today
        ? Strings.historyToday
        : '${local.year}.${_two(local.month)}.${_two(local.day)}';

    return Center(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: skin.fillOf(skin.glass),
          gradient: skin.sheen,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: skin.inkSubtle),
          ),
        ),
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// 말 한 번과 그 결과.
class _Turn extends StatelessWidget {
  const _Turn({
    required this.record,
    required this.canUndo,
    required this.undoing,
    required this.onUndo,
  });

  final ChangeRecord record;
  final bool canUndo;
  final bool undoing;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final said = record.utterance;
    final hasSaid = said != null && said.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 발화가 없는 기록도 있다(보정·되돌리기). 문장을 지어내지 않는다.
        if (hasSaid) _Said(text: said, at: record.occurredAt),
        if (hasSaid) const SizedBox(height: 8),
        _Applied(record: record, canUndo: canUndo, undoing: undoing, onUndo: onUndo),
      ],
    );
  }
}

/// 사용자가 말한 문장. 오른쪽 말풍선.
class _Said extends StatelessWidget {
  const _Said({required this.text, required this.at});

  final String text;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final style = Theme.of(context).textTheme;
    final local = at.toLocal();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4, right: 8),
          child: Text(
            '${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}',
            style: style.labelSmall
                ?.copyWith(color: skin.inkDim, fontWeight: FontWeight.w500),
          ),
        ),
        Flexible(
          child: Container(
            constraints:
                BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.66),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: skin.strong,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(
              '“$text”',
              style: style.bodyLarge?.copyWith(
                  color: skin.onStrong, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}

/// 반영된 결과. 왼쪽 카드.
class _Applied extends StatelessWidget {
  const _Applied({
    required this.record,
    required this.canUndo,
    required this.undoing,
    required this.onUndo,
  });

  final ChangeRecord record;
  final bool canUndo;
  final bool undoing;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final reverted = record.reversesEventId != null;
    // 되돌린 기록은 다른 색으로 묶는다. 같은 초록이면 "또 반영했다" 로 읽힌다.
    final kind = reverted ? skin.band(Freshness.soon) : skin.done;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: skin.glassThick,
            shape: BoxShape.circle,
            boxShadow: [skin.shade(0.08, 12, 4)],
          ),
          alignment: Alignment.center,
          child: Mascot(
            mood: reverted ? MascotMood.soon : MascotMood.done,
            size: 32,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            constraints:
                BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: skin.fillOf(skin.glassThick),
              gradient: skin.sheen,
              border: Border.all(color: skin.edge),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [skin.shade(0.06, 22, 8)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InfoChip(
                      label: Labels.historyAction(record),
                      background: reverted ? kind.bgEdge : skin.chipNeutral,
                      foreground: reverted ? kind.accent : skin.inkFaint,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        record.name,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyLarge
                            ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _Change(record: record, skin: skin),
                if (canUndo) ...[
                  const SizedBox(height: 8),
                  _UndoButton(
                      onPressed: undoing ? null : onUndo,
                      busy: undoing,
                      skin: skin),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 잔량 변화. **수량을 바꾸지 않는 기록은 그 사실을 적는다.**
class _Change extends StatelessWidget {
  const _Change({required this.record, required this.skin});

  final ChangeRecord record;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (!record.changesQuantity) {
      return Text(
        Strings.historyNoQuantityChange,
        style: text.labelMedium
            ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
      );
    }

    final unit = Labels.unit(record.unit);
    final before = record.quantityBefore;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        if (before != null)
          Text(
            '${Labels.number(before)}$unit',
            style: text.bodyLarge?.copyWith(
                fontSize: 15, color: skin.inkDim, fontWeight: FontWeight.w600),
          ),
        Icon(Icons.arrow_forward_rounded, size: 14, color: skin.inkDim),
        Text(
          '${Labels.number(record.quantityAfter!)}$unit',
          style: text.titleLarge?.copyWith(fontSize: 20, letterSpacing: -0.8),
        ),
        if (record.isEstimated) InfoChip(label: Strings.historyEstimated),
      ],
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton({
    required this.onPressed,
    required this.busy,
    required this.skin,
  });

  final VoidCallback? onPressed;
  final bool busy;
  final Skin skin;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: FilledButton.tonalIcon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: skin.chipNeutral,
            foregroundColor: skin.ink,
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.undo_rounded, size: 16),
          label: const Text(Strings.undo),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Mascot(mood: MascotMood.unknown, size: 112),
            const SizedBox(height: 12),
            Text(
              Strings.emptyHint,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: skin.inkFaint),
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
    final skin = context.skin;
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
