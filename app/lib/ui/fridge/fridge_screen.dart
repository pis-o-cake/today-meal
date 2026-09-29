/// 냉장고 화면 (UI-06).
///
/// 목업 `mockup/canvas/Fridge.dc.html` 을 옮긴 것이다. 2열 타일로 재료를 늘어놓고,
/// 타일 하나가 **상태 · 이름 · 잔량 · 남은 기한**을 한눈에 보여준다.
///
/// 목록이 아니라 타일인 이유는 잔량 숫자를 크게 쓰기 위해서다. 냉장고 앞에 서서 보는
/// 화면이라 한 줄짜리 목록은 읽히지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/di.dart';
import '../../core/design/breakpoints.dart';
import '../../core/design/labels.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../../domain/repository/repositories.dart';
import '../widgets/glass.dart';
import '../widgets/line_face.dart';
import '../widgets/mascot.dart';
import '../widgets/screen_scaffold.dart';
import 'fridge_view_model.dart';
import 'item_detail_screen.dart';
import 'item_detail_view_model.dart';

class FridgeScreen extends StatefulWidget {
  const FridgeScreen({super.key});

  @override
  State<FridgeScreen> createState() => _FridgeScreenState();
}

class _FridgeScreenState extends State<FridgeScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// 검색칸을 연다. 목업의 머리말은 아이콘만 두고 누르면 칸이 열린다.
  void _openSearch() {
    setState(() => _searching = true);
    _focus.requestFocus();
  }

  void _closeSearch() {
    setState(() => _searching = false);
    _search.clear();
    context.read<FridgeViewModel>().search('');
  }

  /// 재료 상세를 연다. 탭을 바꾸지 않고 위에 쌓는다 — 돌아올 곳을 잃지 않는다.
  ///
  /// 상세가 닫히면 목록을 다시 읽는다. 저장했을 수도, 버렸을 수도 있다.
  void _openItem(IngredientBatch batch) {
    final fridge = context.read<FridgeViewModel>();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider(
          create: (_) =>
              ItemDetailViewModel(batch: batch, inventory: di<InventoryRepository>()),
          child: ItemDetailScreen(onClosed: fridge.load),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fridge = context.watch<FridgeViewModel>();
    return ListScreen(
      header: _Header(
        fridge: fridge,
        searching: _searching,
        controller: _search,
        focus: _focus,
        onOpenSearch: _openSearch,
        onCloseSearch: _closeSearch,
        onQuery: fridge.search,
      ),
      child: switch ((fridge.loading, fridge.error)) {
        (true, _) when fridge.totalCount == 0 => const Center(
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        (_, final Object error?) => _Failed(error: error, onRetry: fridge.load),
        // 재고가 0개인 것과 검색 결과가 0건인 것은 다른 상황이다. 같은 빈 화면으로
        // 처리하면 사용자가 무엇을 해야 하는지 알 수 없다.
        _ when fridge.visible.isEmpty && fridge.totalCount > 0 => _NoMatch(
          onClear: _closeSearch,
        ),
        _ when fridge.visible.isEmpty => const _Empty(),
        _ => _Tiles(items: fridge.visible, onOpen: _openItem),
      },
    );
  }
}

/// 캐릭터 · 제목 · 요약 · 검색 · 보관 위치 세그먼트.
class _Header extends StatelessWidget {
  const _Header({
    required this.fridge,
    required this.searching,
    required this.controller,
    required this.focus,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onQuery,
  });

  final FridgeViewModel fridge;
  final bool searching;
  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    // 가장 급한 등급을 캐릭터가 얼굴로 말한다. 숫자보다 먼저 읽힌다.
    final urgent = fridge.countOf(Freshness.urgent) + fridge.countOf(Freshness.expired);
    final mood = urgent > 0 ? MascotMood.urgent : MascotMood.fresh;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (searching)
          _SearchField(
            controller: controller,
            focus: focus,
            onQuery: onQuery,
            onClose: onCloseSearch,
          )
        else
          Row(
            children: [
              Mascot(mood: mood, size: 56),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(Strings.tabFridge, style: Tokens.hero(30)),
                    const SizedBox(height: 2),
                    Text(
                      Strings.fridgeSummary(
                        fridge.totalCount,
                        fridge.countOf(Freshness.urgent),
                        fridge.countOf(Freshness.expired),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(
                        color: skin.inkFaint,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              HeaderButton(
                icon: Icons.search_rounded,
                label: Strings.fridgeSearch,
                onPressed: onOpenSearch,
              ),
            ],
          ),
        const SizedBox(height: 14),
        _Segments(fridge: fridge),
        const SizedBox(height: 8),
        _StatusChips(fridge: fridge),
      ],
    );
  }
}

/// 기한 상태로 거르는 칩 행.
///
/// 보관 위치 세그먼트와 **따로 둔다** — 축이 다르다. 하나로 합치면 "냉동의 기한 코앞" 을
/// 고를 수 없다.
///
/// 고른 칩을 다시 누르면 전체로 돌아간다. 고른 것을 해제할 방법이 없으면 사용자가 갇힌다.
class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.fridge});

  final FridgeViewModel fridge;

  @override
  Widget build(BuildContext context) => Semantics(
    label: Strings.fridgeStatusFilter,
    child: SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(context, null),
          for (final grade in Bands.ordered) _chip(context, grade),
        ],
      ),
    ),
  );

  Widget _chip(BuildContext context, Freshness? grade) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final on = fridge.grade == grade;
    final count = fridge.countInScope(grade);
    final palette = grade == null ? null : skin.band(grade);
    final label = grade == null ? Strings.bandShortAll : Labels.freshnessShort(grade);
    final fg = on ? (palette?.accent ?? skin.ink) : skin.inkFaint;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        selected: on,
        label: '$label $count',
        child: GestureDetector(
          onTap: () => fridge.filterGrade(grade),
          child: Container(
            height: 36,
            padding: EdgeInsets.fromLTRB(grade == null ? 12 : 8, 0, 12, 0),
            decoration: ShapeDecoration(
              color: on ? (palette?.accentSoft ?? skin.raised) : skin.chipNeutral,
              shape: StadiumBorder(
                side: BorderSide(color: on ? Colors.transparent : skin.hairline),
              ),
            ),
            child: Row(
              children: [
                if (grade != null) ...[
                  LineFace.compact(grade: grade, color: fg, size: 18),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: text.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  '$count',
                  style: text.labelSmall?.copyWith(
                    color: fg.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 검색 입력. 머리말 자리를 그대로 차지한다.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onQuery,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onQuery;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Expanded(
            child: GlassPill(
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 20, color: skin.inkFaint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      onChanged: onQuery,
                      textInputAction: TextInputAction.search,
                      style: Theme.of(context).textTheme.bodyLarge
                          ?.copyWith(fontSize: 16, color: skin.ink),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: Strings.fridgeSearchHint,
                        hintStyle: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(fontSize: 16, color: skin.inkDim),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          HeaderButton(
            icon: Icons.close_rounded,
            label: Strings.fridgeSearchClear,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// 보관 위치 세그먼트. 칸마다 개수를 붙여 어디에 뭐가 있는지 먼저 보인다.
class _Segments extends StatelessWidget {
  const _Segments({required this.fridge});

  final FridgeViewModel fridge;

  /// 화면에 두는 보관 위치. '모름' 은 필터로 쓸모가 없어 뺀다 — 전체에서 조회된다.
  static const _shown = [
    StorageLocation.fridge,
    StorageLocation.freezer,
    StorageLocation.pantry,
  ];

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Semantics(
      label: '보관 위치',
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: ShapeDecoration(
          color: skin.fillOf(skin.glass),
          gradient: skin.sheen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: skin.edge),
          ),
          shadows: [skin.shade(0.06, 18, 6)],
        ),
        child: Row(
          children: [
            Expanded(child: _segment(context, skin, Strings.fridgeAll, null)),
            for (final storage in _shown)
              Expanded(child: _segment(context, skin, Labels.storage(storage), storage)),
          ],
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, Skin skin, String label, StorageLocation? value) {
    final on = fridge.storage == value;
    final text = Theme.of(context).textTheme;
    final count = value == null ? fridge.totalCount : fridge.countOfStorage(value);

    return Semantics(
      button: true,
      selected: on,
      label: '$label $count',
      child: GestureDetector(
        onTap: () => fridge.filterStorage(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          decoration: ShapeDecoration(
            color: on ? skin.raised : Colors.transparent,
            shape: const StadiumBorder(),
            shadows: on ? [skin.shade(0.08, 12, 4)] : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: text.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: on ? skin.ink : skin.inkFaint,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: text.labelSmall?.copyWith(
                  color: skin.inkDim,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2열 타일.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.items, required this.onOpen});

  final List<IngredientBatch> items;

  /// 재료 상세로 보낸다.
  final void Function(IngredientBatch batch) onOpen;

  @override
  Widget build(BuildContext context) {
    // 태블릿에서는 한 줄에 더 놓는다. 타일 크기를 유지해야 숫자가 계속 크게 보인다.
    final columns = context.formFactor.isCompact ? 2 : 3;
    return Stack(
      children: [
        GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 108),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // 상태 이름 · 이름 · 잔량 · 막대 · 기한 · 한 마디가 모두 들어가는 높이.
            mainAxisExtent: 186,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) =>
              _Tile(batch: items[index], onTap: () => onOpen(items[index])),
        ),
        const Positioned(left: 0, right: 0, bottom: 0, child: ListFade()),
      ],
    );
  }
}

/// 재료 한 칸.
class _Tile extends StatelessWidget {
  const _Tile({required this.batch, required this.onTap});

  final IngredientBatch batch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final palette = skin.band(batch.freshness);
    final expired = batch.freshness == Freshness.expired;

    return Semantics(
      button: true,
      label: '${batch.name} ${Labels.freshness(batch.freshness)}',
      child: GestureDetector(
        onTap: onTap,
        child: GlassPanel(
          radius: Tokens.radiusCard,
          weight: GlassWeight.thick,
          padding: const EdgeInsets.all(14),
          shadow: [skin.shade(0.06, 24, 8)],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // WARNING: 여기에 Spacer 를 쓰지 않는다. Flexible 과 남은 폭을 반씩 나눠
              // 상태 이름이 눌린다 — 긴 이름("얼마 안 남았어요")에서 가로로 넘친다.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: InfoChip(
                      label: Labels.freshnessShort(batch.freshness),
                      background: palette.bgEdge,
                      foreground: palette.accent,
                      leading: LineFace.compact(
                        grade: batch.freshness,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    Labels.storage(batch.storage),
                    style: text.labelSmall?.copyWith(
                      color: skin.inkDim,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                batch.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium,
              ),
              const SizedBox(height: 2),
              _Amount(batch: batch, skin: skin, style: text),
              _Remaining(batch: batch, palette: palette, skin: skin),
              const SizedBox(height: 7),
              Text(
                _meta(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(
                  color: skin.inkFaint,
                  fontWeight: FontWeight.w500,
                ),
              ),
              // 아랫줄은 한 마디 요약이다. 기한이 지난 것은 남은 날 대신 경고를 적는다.
              Text(
                _sub(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelSmall?.copyWith(
                  color: expired ? skin.band(Freshness.urgent).accent : palette.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 기한 줄. 종류를 붙여야 소비기한과 점검 알림이 섞이지 않는다.
  String _meta() {
    final kind = batch.expiryKind;
    final date = batch.dates.where((d) => d.kind == kind).firstOrNull;
    if (kind == null) return Strings.dateTellPlease;
    final value = date?.value;
    if (value == null) return Labels.dateKind(kind);
    return '${Labels.dateKind(kind)} ${_dotted(value)}';
  }

  /// 남은 날 또는 경고.
  String _sub() {
    if (batch.freshness == Freshness.expired) return Strings.stateCheckNeeded;
    final days = batch.daysLeft;
    if (days == null) return '';
    return Strings.daysLeft(days);
  }

  /// `2026-10-03` 을 `2026.10.03` 으로. **연도를 만들어 붙이지 않는다.**
  String _dotted(String raw) => raw.replaceAll('-', '.');
}

/// 잔량. 숫자를 크게, 단위를 작게 붙인다.
class _Amount extends StatelessWidget {
  const _Amount({required this.batch, required this.skin, required this.style});

  final IngredientBatch batch;
  final Skin skin;
  final TextTheme style;

  @override
  Widget build(BuildContext context) {
    final amount = Labels.amount(batch);
    if (amount.isEmpty) {
      return Text(
        Strings.quantityUnknown,
        style: style.titleMedium?.copyWith(color: skin.inkFaint),
      );
    }
    final quantity = batch.quantity;
    // 정성 표현("조금")은 숫자가 아니므로 통째로 크게 쓴다.
    final number = quantity == null ? amount : Labels.number(quantity);
    final unit = quantity == null ? '' : Labels.unit(batch.unit);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            number,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.headlineMedium?.copyWith(fontSize: 26, letterSpacing: -1.04),
          ),
        ),
        if (unit.isNotEmpty)
          Text(
            unit,
            style: style.bodyLarge?.copyWith(
              color: skin.inkMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        if (batch.quantityUncertain) ...[
          const SizedBox(width: 6),
          InfoChip(label: Strings.historyEstimated),
        ],
      ],
    );
  }
}

/// 상태 막대.
///
/// **남은 수명의 비율이 아니다.** UI 계약대로 등급을 요약하는 장식이며, 서버가 검증된
/// 비율을 주기 전에는 **등급마다 고정 길이**로만 그린다. 남은 날로 길이를 계산하면
/// 없는 정밀도를 만들어 낸다.
///
/// 기한을 모르면 채우지 않고 점선만 둔다. 0% 로 채우면 다 썼다는 뜻이 되어 거짓이다.
class _Remaining extends StatelessWidget {
  const _Remaining({required this.batch, required this.palette, required this.skin});

  final IngredientBatch batch;
  final BandPalette palette;
  final Skin skin;

  /// 등급별 막대 길이. 목업의 예시 퍼센트를 등급 단위로 묶은 것이다.
  static const _length = <Freshness, double>{
    Freshness.expired: 0.06,
    Freshness.urgent: 0.16,
    Freshness.soon: 0.4,
    Freshness.fresh: 0.82,
  };

  @override
  Widget build(BuildContext context) {
    final fill = _length[batch.freshness];
    if (fill == null) {
      return Container(
        height: 6,
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: skin.trackDashed,
            width: 1.5,
            strokeAlign: BorderSide.strokeAlignInside,
          ),
        ),
      );
    }
    return Container(
      height: 6,
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: skin.track,
        borderRadius: BorderRadius.circular(3),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fill,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// 재고가 하나도 없다. 첫 등록을 안내한다.
class _Empty extends StatelessWidget {
  const _Empty();

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
            const Mascot(mood: MascotMood.unknown, size: 112),
            const SizedBox(height: 12),
            Text(Strings.empty, textAlign: TextAlign.center, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              Strings.emptyHint,
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: skin.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// 검색·필터에 걸린 것이 없다. 재고가 빈 것과 다르다.
class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.onClear});

  final VoidCallback onClear;

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
            const Mascot(mood: MascotMood.unknown, size: 96),
            const SizedBox(height: 12),
            Text(Strings.fridgeSearchEmpty, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              Strings.fridgeSearchEmptyHint,
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: skin.inkFaint),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onClear,
              child: const Text(Strings.fridgeSearchClear),
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
