/// 재료 상세 (UI-11).
///
/// 목업 `mockup/canvas/FridgeItem.dc.html` 을 옮긴 것이다. 냉장고 타일을 누르면 열린다.
///
/// IMPORTANT: 기한 종류를 **서로 바꾸지 않는다.** 유통기한을 고른 뒤 날짜를 적으면 유통기한으로
/// 저장되며, 소비기한으로 승격되지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/labels.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../widgets/glass.dart';
import '../widgets/line_face.dart';
import '../widgets/mascot.dart';
import '../widgets/nav_icons.dart';
import 'item_detail_view_model.dart';

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({
    required this.onClosed,
    this.recipes = const [],
    this.onOpenRecipe,
    this.onOpenCook,
    super.key,
  });

  /// 저장하거나 버려서 화면이 닫혔다. 냉장고가 목록을 다시 읽어야 한다.
  final VoidCallback onClosed;

  /// 이 재료로 만들 수 있는 요리. 서버 추천에서 걸러 온다.
  final List<MenuSuggestion> recipes;

  final void Function(MenuSuggestion suggestion)? onOpenRecipe;

  /// 조리 탭으로 보낸다.
  final VoidCallback? onOpenCook;

  @override
  Widget build(BuildContext context) {
    final item = context.watch<ItemDetailViewModel>();
    final skin = context.skin;

    // 저장이나 버리기가 끝났다. 프레임 뒤에 닫는다 — build 안에서 pop 할 수 없다.
    if (item.saved || item.discarded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        onClosed();
        Navigator.of(context).maybePop();
      });
    }

    return DecoratedBox(
      decoration: BoxDecoration(gradient: skin.listBackground),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _Header(item: item),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    _Identity(item: item),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _Fields(item: item),
                    ),
                    const SizedBox(height: 10),
                    _VoiceHint(skin: skin),
                    if (recipes.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      _Recipes(
                        name: item.name,
                        recipes: recipes,
                        onOpen: onOpenRecipe,
                        onOpenAll: onOpenCook,
                      ),
                    ],
                    if (item.error != null) ...[
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _SaveError(skin: skin),
                      ),
                    ],
                  ],
                ),
              ),
              _SaveButton(item: item),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item});

  final ItemDetailViewModel item;

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
              Strings.itemTitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            onPressed: item.saving ? null : () => _confirmDiscard(context, item),
            style: TextButton.styleFrom(
              foregroundColor: skin.band(Freshness.urgent).accent,
            ),
            child: const Text(Strings.itemDelete),
          ),
        ],
      ),
    );
  }

  /// 버리기를 확인받는다. 되돌리기가 어려운 일이므로 한 번 묻는다.
  void _confirmDiscard(BuildContext context, ItemDetailViewModel item) {
    showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(Strings.itemDiscardTitle(item.name)),
        content: const Text(Strings.itemDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text(Strings.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialog).pop();
              item.discard();
            },
            child: const Text(Strings.itemDelete),
          ),
        ],
      ),
    );
  }
}

/// 캐릭터 · 상태 칩 · 이름 · 기한 한 줄.
class _Identity extends StatelessWidget {
  const _Identity({required this.item});

  final ItemDetailViewModel item;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final grade = item.batch.freshness;
    final palette = skin.band(grade);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Center(child: Mascot(mood: palette.mood, size: 68)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BandChip(grade: grade, palette: palette),
                const SizedBox(height: 4),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.hero(30, height: 1.15),
                ),
                const SizedBox(height: 2),
                Text(
                  _dateLine(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                      color: palette.accent, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `소비기한 2026.10.03 · D-1`. **모르는 값은 적지 않는다.**
  String _dateLine(ItemDetailViewModel item) {
    final parts = <String>[];
    final value = item.dateValue;
    if (value == null) return Strings.dateTellPlease;
    parts.add('${Labels.dateKind(item.dateKind)} ${_dots(value)}');
    final days = item.batch.daysLeft;
    if (days != null) parts.add(Strings.daysLeft(days));
    return parts.join(' · ');
  }

  static String _dots(DateTime value) =>
      '${value.year}.${_two(value.month)}.${_two(value.day)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// 기한 상태 칩. 얼굴을 함께 둔다 — 색만으로 구분하지 않는다.
class _BandChip extends StatelessWidget {
  const _BandChip({required this.grade, required this.palette});

  final Freshness grade;
  final BandPalette palette;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: palette.accentSoft,
          borderRadius: BorderRadius.circular(Tokens.radiusChip),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 3, 8, 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LineFace(grade: grade, color: palette.accent, size: 14),
              const SizedBox(width: 3),
              Text(
                Labels.freshnessShort(grade),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: palette.accent, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
}

/// 고칠 수 있는 칸들.
class _Fields extends StatelessWidget {
  const _Fields({required this.item});

  final ItemDetailViewModel item;

  @override
  Widget build(BuildContext context) => GlassPanel(
        weight: GlassWeight.thick,
        radius: Tokens.radiusPanel,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _Field(
              label: Strings.itemFieldName,
              value: Text(item.name,
                  style: Theme.of(context).textTheme.titleSmall),
              action: _IconAction(
                icon: Icons.edit_outlined,
                label: Strings.itemEditName,
                onPressed: () => _editName(context, item),
              ),
            ),
            _Field(
              divided: true,
              label: Strings.itemFieldQuantity,
              value: const SizedBox.shrink(),
              trailing: _Stepper(item: item),
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
              expand: true,
            ),
            _Field(
              divided: true,
              label: Strings.itemFieldDateKind,
              // 목업의 세 갈래다. '모름' 은 종류가 아니라 날짜가 없는 상태이므로
              // 여기 두지 않는다 — 날짜를 비우면 그대로 모르는 것이 된다.
              value: _Segmented<DateKind>(
                options: const [
                  DateKind.useBy,
                  DateKind.sellBy,
                  DateKind.checkReminder,
                ],
                current: item.dateKind,
                labelOf: Labels.dateKind,
                onSelect: item.selectDateKind,
              ),
              expand: true,
            ),
            _Field(
              divided: true,
              label: Strings.itemFieldDate,
              value: Text(
                item.dateValue == null
                    ? Strings.dateTellPlease
                    : _weekday(item.dateValue!),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              action: _IconAction(
                icon: Icons.calendar_today_rounded,
                label: Strings.itemPickDate,
                onPressed: () => _pickDate(context, item),
              ),
            ),
          ],
        ),
      );

  /// `2026.10.03 (토)`.
  String _weekday(DateTime value) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    final dots =
        '${value.year}.${_two(value.month)}.${_two(value.day)}';
    return '$dots (${days[value.weekday - 1]})';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  Future<void> _editName(BuildContext context, ItemDetailViewModel item) async {
    final controller = TextEditingController(text: item.name);
    final next = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text(Strings.itemEditName),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(dialog).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text(Strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialog).pop(controller.text),
            child: const Text(Strings.confirm),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next != null) item.rename(next);
  }

  Future<void> _pickDate(BuildContext context, ItemDetailViewModel item) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: item.dateValue ?? today,
      // 지난 기한도 고칠 수 있어야 한다 — 어제 산 것의 날짜를 뒤늦게 적는 경우다.
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
    this.action,
    this.trailing,
    this.divided = false,
    this.expand = false,
  });

  final String label;
  final Widget value;
  final Widget? action;
  final Widget? trailing;
  final bool divided;

  /// 값이 남은 폭을 다 쓰는지. 분절 버튼처럼 넓은 값에 쓴다.
  final bool expand;

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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: skin.inkFaint, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          if (expand) Expanded(child: value) else Expanded(child: value),
          if (trailing != null) trailing!,
          if (action != null) action!,
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

/// 수량 더하기·빼기.
class _Stepper extends StatelessWidget {
  const _Stepper({required this.item});

  final ItemDetailViewModel item;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.chipNeutral,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Round(
            icon: Icons.remove_rounded,
            label: Strings.itemMinus,
            onPressed: item.decrement,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56, maxWidth: 88),
            child: Text(
              // 잔량을 모르면 숫자를 지어내지 않고 모른다고 적는다.
              item.quantity == null
                  ? Strings.quantityUnknownShort
                  : '${item.quantity}${Labels.unit(item.batch.unit)}',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          _Round(
            icon: Icons.add_rounded,
            label: Strings.itemPlus,
            onPressed: item.increment,
          ),
        ],
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: skin.raised,
            shape: BoxShape.circle,
            boxShadow: [skin.shade(0.1, 3, 1)],
          ),
          child: Icon(icon, size: 16, color: skin.ink),
        ),
      ),
    );
  }
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
    return Semantics(
      child: Container(
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

/// 이 재료로 만들 수 있는 요리.
class _Recipes extends StatelessWidget {
  const _Recipes({
    required this.name,
    required this.recipes,
    required this.onOpen,
    required this.onOpenAll,
  });

  final String name;
  final List<MenuSuggestion> recipes;
  final void Function(MenuSuggestion suggestion)? onOpen;
  final VoidCallback? onOpenAll;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(Strings.itemRecipesTitle(name),
                    style: text.titleMedium),
              ),
              if (onOpenAll != null)
                TextButton(
                  onPressed: onOpenAll,
                  style: TextButton.styleFrom(foregroundColor: skin.inkFaint),
                  child: const Text(Strings.itemRecipesAll),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              for (final (index, recipe) in recipes.indexed) ...[
                if (index > 0) const SizedBox(width: 10),
                _RecipeCard(recipe: recipe, onTap: onOpen),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard({required this.recipe, required this.onTap});

  final MenuSuggestion recipe;
  final void Function(MenuSuggestion suggestion)? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final palette = skin.band(Labels.availabilityBand(recipe.availability));

    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(recipe),
      child: SizedBox(
        width: 148,
        child: GlassPanel(
          radius: Tokens.radiusTile,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: NavIcon(
                      glyph: NavGlyph.cook, color: palette.accent, size: 20),
                ),
              ),
              const SizedBox(height: 6),
              Text(recipe.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                _meta(recipe),
                style: text.labelSmall?.copyWith(
                    color: skin.inkSubtle, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 4),
              InfoChip(
                label: Labels.availability(recipe.availability),
                background: palette.accentSoft,
                foreground: palette.accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _meta(MenuSuggestion recipe) {
    final parts = <String>[Strings.menuServings(recipe.servings)];
    final minutes = recipe.estimatedMinutes;
    if (minutes != null) parts.add(Strings.menuMinutes(minutes));
    return parts.join(' · ');
  }
}

class _VoiceHint extends StatelessWidget {
  const _VoiceHint({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Icon(Icons.mic_none_rounded, size: 15, color: skin.inkSubtle),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                Strings.itemVoiceHint,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: skin.inkSubtle, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      );
}

/// 저장이 실패했다. **저장된 것처럼 닫지 않는다.**
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
                  color: palette.accent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.item});

  final ItemDetailViewModel item;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: FilledButton(
          onPressed: item.saving ? null : item.save,
          style: FilledButton.styleFrom(
            backgroundColor: skin.strong,
            foregroundColor: skin.onStrong,
            shape: const StadiumBorder(),
          ),
          child: item.saving
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: skin.onStrong),
                )
              : const Text(Strings.itemSave),
        ),
      ),
    );
  }
}
