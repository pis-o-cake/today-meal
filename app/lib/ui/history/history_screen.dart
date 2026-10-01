/// 기록 화면 (UI-12).
///
/// 목업 `mockup/canvas/History.dc.html` 을 옮긴 것이다. **말한 문장(오른쪽) → 바뀐 결과
/// (왼쪽)** 의 대화로 보여준다. 전체를 최근순으로 받아 아래가 가장 최근이며, 열 때 그
/// 끝을 보여준다 — 되돌릴 수 있는 것은 전체에서 가장 최근의 변경이다. 목록이 아니라 대화인 이유는, 이 앱에서 재고가 바뀌는
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
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/change_record.dart';
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
            child: Text(Strings.historyTitle, style: Tokens.hero(30)),
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

class _Conversation extends StatefulWidget {
  const _Conversation({
    required this.records,
    required this.onUndo,
    required this.undoing,
  });

  final List<ChangeRecord> records;
  final Future<void> Function(ChangeRecord record) onUndo;
  final bool undoing;

  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // 첫 배치가 끝나야 끝 위치를 안다. 그 전에 옮기면 0 으로 튄다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _toLatest());
  }

  @override
  void didUpdateWidget(_Conversation old) {
    super.didUpdateWidget(old);
    // 되돌리기로 줄이 늘면 새 줄이 보여야 한다.
    if (old.records.length != widget.records.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _toLatest());
    }
  }

  void _toLatest() {
    if (!_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = widget.records;
    if (records.isEmpty) return const _Empty();

    // 되돌리기는 **전체에서 가장 최근 줄**에만 준다. 중간을 되돌리면 그 뒤가 무슨 뜻인지
    // 알 수 없어진다.
    final last = records.length - 1;

    return Stack(
      children: [
        ListView.separated(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 108),
          itemCount: records.length,
          separatorBuilder: (_, _) => const SizedBox(height: 18),
          itemBuilder: (context, index) => _Turn(
            record: records[index],
            canUndo:
                index == last && records[index].reversesEventId == null,
            undoing: widget.undoing,
            onUndo: () => widget.onUndo(records[index]),
          ),
        ),
        const Positioned(left: 0, right: 0, bottom: 0, child: ListFade()),
      ],
    );
  }
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
    // 동작마다 칩 색이 다르다. 넣은 것과 뺀 것, 고친 것과 되돌린 것이 한 줄씩 섞여 흐르므로
    // 글자만으로는 훑어지지 않는다.
    final chip = skin.historyKind(HistoryAction.parse(record.action));

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
                      background: chip.background,
                      foreground: chip.foreground,
                    ),
                    const SizedBox(width: 8),
                    // 칩은 동작 이름, 이 문장은 무엇이 일어났는지다. 둘 다 있어야 색을
                    // 못 보는 사람도 읽을 수 있다.
                    Flexible(
                      child: Text(
                        Labels.historySaid(record),
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
    final name = Text(
      record.name,
      style: text.labelMedium
          ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
    );

    if (!record.changesQuantity) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 4,
        children: [
          name,
          Text(
            Strings.historyNoQuantityChange,
            style: text.labelMedium
                ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
          ),
        ],
      );
    }

    final unit = Labels.unit(record.unit);
    final before = record.quantityBefore;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        // 재료 이름은 동작 문장이 아니라 수량 줄에 붙는다 — "계란 8 → 9개" 가 한 덩어리다.
        name,
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
        // 추정과 명시를 **둘 다** 표시한다. 추정에만 배지를 달면 배지가 없는 줄이
        // 확인된 값인지 표시를 빠뜨린 것인지 알 수 없다.
        InfoChip(
          label: record.isEstimated
              ? Strings.historyEstimated
              : Strings.historyExact,
        ),
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

/// 고른 날에 기록이 없다.
///
/// 오늘과 지난 날의 안내가 다르다 — 오늘은 지금 말하면 쌓이지만, 지난 날은 더 할 수 있는
/// 것이 없고 다른 날을 골라야 한다.
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
