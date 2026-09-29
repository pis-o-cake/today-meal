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
          const SizedBox(height: 12),
          _DayPicker(history: history),
        ],
      ),
      child: switch ((history.loading, history.error)) {
        (true, _) when history.records.isEmpty =>
          const Center(child: CircularProgressIndicator(strokeWidth: 3)),
        (_, final Object error?) => _Failed(error: error, onRetry: history.load),
        _ => _Conversation(
            key: ValueKey(history.day),
            records: history.records,
            onUndo: history.undo,
            undoing: history.undoing,
            today: history.isToday,
          ),
      },
    );
  }
}

/// 날짜 고르개.
///
/// 오늘로 열고 달력에서 다른 날을 고른다. **기록이 있는 날만** 고를 수 있다 — 없는 날을
/// 고르면 빈 화면이 나오고, 사용자는 자기가 잘못 골랐는지 기록이 없는지 알 수 없다.
///
/// 좌우 화살표로 기록이 있는 앞뒤 날로 건너뛴다. 달력을 열지 않고도 하루씩 넘길 수 있어야
/// 한다 — 어제를 보는 일이 가장 잦다.
class _DayPicker extends StatelessWidget {
  const _DayPicker({required this.history});

  final HistoryViewModel history;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final days = history.days;
    final at = days.indexWhere((d) => _sameDay(d, history.day));
    // 목록은 최근 것이 앞이다. 다음 날은 앞쪽(index-1), 이전 날은 뒤쪽(index+1)이다.
    final older = at >= 0 && at + 1 < days.length ? days[at + 1] : null;
    final newer = at > 0 ? days[at - 1] : null;

    return Row(
      children: [
        _Step(
          icon: Icons.chevron_left_rounded,
          label: Strings.historyOlderDay,
          onPressed: older == null ? null : () => history.selectDay(older),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () => _pick(context),
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: ShapeDecoration(
                color: skin.fillOf(skin.glass),
                gradient: skin.sheen,
                shape: StadiumBorder(side: BorderSide(color: skin.edge)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 14, color: skin.inkFaint),
                  const SizedBox(width: 6),
                  Text(
                    _label(history),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Icon(Icons.expand_more_rounded, size: 18, color: skin.inkDim),
                ],
              ),
            ),
          ),
        ),
        _Step(
          icon: Icons.chevron_right_rounded,
          label: Strings.historyNewerDay,
          onPressed: newer == null ? null : () => history.selectDay(newer),
        ),
      ],
    );
  }

  /// 고른 날. 오늘은 "오늘" 이라고 적는다 — 날짜보다 빨리 읽힌다.
  String _label(HistoryViewModel history) {
    if (history.isToday) return Strings.historyToday;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final day = history.day;
    return '${day.month}월 ${day.day}일 (${weekdays[day.weekday - 1]})';
  }

  Future<void> _pick(BuildContext context) async {
    final days = history.days;
    final today = DateTime.now();
    final oldest = days.isEmpty ? today : days.last;
    final picked = await showDatePicker(
      context: context,
      initialDate: history.day,
      firstDate: DateTime(oldest.year, oldest.month, oldest.day),
      lastDate: DateTime(today.year, today.month, today.day),
      // 기록이 있는 날만 고르게 한다. 오늘은 비어 있어도 열 수 있어야 한다 —
      // 지금 말하면 바로 쌓이는 날이다.
      selectableDayPredicate: (day) =>
          _sameDay(day, today) || days.any((d) => _sameDay(d, day)),
    );
    if (picked != null) await history.selectDay(picked);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 앞뒤 날로 건너뛰는 단추. 갈 곳이 없으면 꺼진다.
class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;

  /// 스크린리더 이름. 아이콘만 있는 버튼이라 반드시 둔다.
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: Tokens.tap,
        height: Tokens.tap,
        child: IconButton(
          onPressed: onPressed,
          iconSize: 22,
          color: context.skin.inkFaint,
          tooltip: label,
          icon: Icon(icon),
        ),
      );
}

/// 하루치 대화.
///
/// **가장 최근이 맨 아래**이고 화면은 거기서 열린다. 메신저와 같은 순서다 — 위에서
/// 시작하면 방금 한 말을 보려고 매번 끝까지 내려야 한다.
class _Conversation extends StatefulWidget {
  const _Conversation({
    required this.records,
    required this.onUndo,
    required this.undoing,
    required this.today,
    super.key,
  });

  final List<ChangeRecord> records;

  /// 오늘을 보고 있는지. 비어 있을 때의 안내가 달라진다.
  final bool today;
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
    if (records.isEmpty) return _Empty(today: widget.today);

    // 되돌리기는 **그 날의 마지막 줄**에만 준다. 중간을 되돌리면 그 뒤가 무슨 뜻인지
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
  const _Empty({this.today = true});

  /// 오늘을 보고 있는지.
  final bool today;

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
              today ? Strings.emptyHint : Strings.historyEmptyDay,
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
