/// 재료 넣기.
///
/// 목업 밖의 화면이라 재료 상세(UI-08)의 칸 모양을 따른다 — 같은 재료를 적는 화면이 서로
/// 다르게 생기면 어느 쪽이 맞는지 헷갈린다.
///
/// IMPORTANT: 기한 종류를 **서로 바꾸지 않는다.** 고른 종류로 저장한다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/design/labels.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../widgets/glass.dart';
import 'item_add_view_model.dart';

class ItemAddScreen extends StatelessWidget {
  const ItemAddScreen({required this.onAdded, super.key});

  /// 넣기에 성공했다. 냉장고와 오늘 화면이 목록을 다시 읽어야 한다.
  final VoidCallback onAdded;

  Future<void> _save(BuildContext context, ItemAddViewModel item) async {
    await item.save();
    if (item.added == null || !context.mounted) return;
    onAdded();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final item = context.watch<ItemAddViewModel>();
    final skin = context.skin;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: skin.listBackground),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              const _Header(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  children: [
                    _Fields(item: item),
                    const SizedBox(height: 10),
                    _VoiceHint(skin: skin),
                    if (item.error != null) ...[
                      const SizedBox(height: 14),
                      _SaveError(skin: skin),
                    ],
                  ],
                ),
              ),
              _SaveButton(
                saving: item.saving,
                onPressed: item.ready ? () => _save(context, item) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          SizedBox(
            width: Tokens.tap,
            height: Tokens.tap,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              iconSize: 22,
              color: skin.ink,
              tooltip: Strings.itemBack,
              style: IconButton.styleFrom(
                backgroundColor: skin.glass,
                shape: CircleBorder(side: BorderSide(color: skin.edge)),
              ),
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
            ),
          ),
          Expanded(
            child: Text(
              Strings.addTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          // 제목을 가운데 두려고 뒤로 버튼만큼 비운다.
          const SizedBox(width: Tokens.tap),
        ],
      ),
    );
  }
}

/// 적을 칸들.
class _Fields extends StatelessWidget {
  const _Fields({required this.item});

  final ItemAddViewModel item;

  @override
  Widget build(BuildContext context) => GlassPanel(
    weight: GlassWeight.thick,
    radius: Tokens.radiusPanel,
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        _Field(
          label: Strings.itemFieldName,
          value: _Input(
            hint: Strings.addNameHint,
            onChanged: item.setName,
            autofocus: true,
            action: TextInputAction.next,
          ),
        ),
        _Field(
          divided: true,
          label: Strings.itemFieldQuantity,
          value: _Input(
            hint: Strings.addQuantityHint,
            onChanged: item.setQuantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            // 숫자와 소수점 하나만 받는다. 음수와 글자는 잔량이 될 수 없다.
            formatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'^\d{0,6}(\.\d{0,3})?'),
              ),
            ],
            suffix: Labels.unit(item.unit),
          ),
        ),
        _Field(
          divided: true,
          label: Strings.addFieldUnit,
          value: _UnitChips(current: item.unit, onSelect: item.selectUnit),
        ),
        _Field(
          divided: true,
          label: Strings.itemFieldStorage,
          value: _Segmented<StorageLocation>(
            options: const [
              StorageLocation.fridge,
              StorageLocation.freezer,
              StorageLocation.pantry,
            ],
            current: item.storage,
            labelOf: Labels.storage,
            onSelect: item.selectStorage,
          ),
        ),
        _Field(
          divided: true,
          label: Strings.itemFieldDateKind,
          // 재료 상세와 같은 세 갈래다.
          value: _Segmented<DateKind>(
            options: const [
              DateKind.sellBy,
              DateKind.checkReminder,
            ],
            current: item.dateKind,
            labelOf: Labels.dateKind,
            onSelect: item.selectDateKind,
          ),
        ),
        _Field(
          divided: true,
          label: Strings.itemFieldDate,
          value: Text(
            item.dateValue == null
                ? Strings.addDateNone
                : Labels.date(item.dateValue!),
            style: item.dateValue == null
                ? Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: context.skin.inkDim)
                : Theme.of(context).textTheme.titleSmall,
          ),
          actions: [
            if (item.dateValue != null)
              _IconAction(
                icon: Icons.close_rounded,
                label: Strings.addDateClear,
                onPressed: item.clearDate,
              ),
            _IconAction(
              icon: Icons.calendar_today_rounded,
              label: Strings.itemPickDate,
              onPressed: () => _pickDate(context),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _pickDate(BuildContext context) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: item.dateValue ?? today,
      // 이미 지난 기한도 적을 수 있어야 한다 — 냉장고에 있던 것을 뒤늦게 옮겨 적는 경우다.
      firstDate: DateTime(today.year - 2),
      lastDate: DateTime(today.year + 5),
    );
    if (picked != null) item.selectDate(picked);
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.actions = const [],
    this.divided = false,
  });

  final String label;
  final Widget value;
  final List<Widget> actions;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      decoration: BoxDecoration(
        border: divided
            ? Border(top: BorderSide(color: skin.hairline))
            : const Border(),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: value),
          ...actions,
        ],
      ),
    );
  }
}

/// 한 줄 입력. 칸 안에 테두리 없이 앉는다.
///
/// 입력기의 수명을 이 위젯에 묶는다 — 화면이 다시 그려질 때마다 새로 만들면 커서가 튄다.
class _Input extends StatefulWidget {
  const _Input({
    required this.hint,
    required this.onChanged,
    this.keyboardType,
    this.formatters = const [],
    this.suffix,
    this.autofocus = false,
    this.action,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final List<TextInputFormatter> formatters;

  /// 입력 칸 뒤에 붙는 말. 수량의 단위다.
  final String? suffix;
  final bool autofocus;
  final TextInputAction? action;

  @override
  State<_Input> createState() => _InputState();
}

class _InputState extends State<_Input> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.formatters,
      textInputAction: widget.action,
      onChanged: widget.onChanged,
      style: text.titleSmall?.copyWith(color: skin.ink),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: widget.hint,
        hintStyle: text.bodyMedium?.copyWith(color: skin.inkDim),
        suffixText: widget.suffix,
        suffixStyle: text.bodyMedium?.copyWith(
          color: skin.inkMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 단위 고르기. 서버가 아는 단위만 보여준다 — 모르는 단위로 적힌 수량은 레시피 차감에서
/// 환산할 수 없다.
class _UnitChips extends StatelessWidget {
  const _UnitChips({required this.current, required this.onSelect});

  final String current;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final MapEntry(key: symbol, value: label)
              in Strings.units.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Semantics(
                button: true,
                selected: symbol == current,
                label: label,
                child: GestureDetector(
                  onTap: () => onSelect(symbol),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: ShapeDecoration(
                      color: symbol == current ? skin.strong : skin.chipNeutral,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      label,
                      style: text.labelMedium?.copyWith(
                        color: symbol == current
                            ? skin.onStrong
                            : skin.inkFaint,
                        fontWeight: symbol == current
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;

  /// 스크린리더 이름. 아이콘만 있는 버튼이라 반드시 둔다.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 40,
    child: IconButton(
      onPressed: onPressed,
      iconSize: 18,
      color: context.skin.inkDim,
      tooltip: label,
      icon: Icon(icon),
    ),
  );
}

/// 세 갈래 중 하나를 고른다.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.current,
    required this.labelOf,
    required this.onSelect,
  });

  final List<T> options;
  final T current;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.chipNeutral,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(child: _segment(context, skin, option)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, Skin skin, T option) {
    final on = option == current;
    final label = labelOf(option);
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: GestureDetector(
        onTap: () => onSelect(option),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: on ? skin.raised : Colors.transparent,
            shape: const StadiumBorder(),
            shadows: on ? [skin.shade(0.08, 6, 2)] : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              color: on ? skin.ink : skin.inkFaint,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceHint extends StatelessWidget {
  const _VoiceHint({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        Icon(Icons.mic_none_rounded, size: 15, color: skin.inkSubtle),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            Strings.addVoiceHint,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: skin.inkSubtle, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    ),
  );
}

/// 넣기가 실패했다. **넣은 것처럼 닫지 않는다.**
class _SaveError extends StatelessWidget {
  const _SaveError({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final palette = skin.band(Freshness.urgent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(Tokens.radiusTile),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: palette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              Strings.serverFailed,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: palette.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.onPressed});

  final bool saving;

  /// `null` 이면 아직 넣을 수 없다. 이름과 수량이 있어야 한다.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: FilledButton(
          onPressed: saving ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: skin.strong,
            foregroundColor: skin.onStrong,
            shape: const StadiumBorder(),
          ),
          child: saving
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: skin.onStrong,
                  ),
                )
              : const Text(Strings.addSave),
        ),
      ),
    );
  }
}
