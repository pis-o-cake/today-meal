/// 조리 탭 (UI-08).
///
/// 목업 `mockup/canvas/CookHome.dc.html` 을 옮긴 것이다. 조리로 들어가는 길이 둘이다 —
/// **냉장고 재료로 하는 추천**과 **영상 링크로 하는 정리**다. 위아래로 나란히 두는 것이
/// 의도다: 냉장고를 먼저 권하되 링크를 감추지 않는다.
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
import '../../domain/repository/repositories.dart';
import '../widgets/glass.dart';
import '../widgets/mascot.dart';
import '../widgets/nav_icons.dart';
import '../widgets/screen_scaffold.dart';
import 'cook_view_model.dart';

class CookHomeScreen extends StatefulWidget {
  const CookHomeScreen({required this.onStart, super.key});

  /// 조리를 시작한다. 추천에서 왔는지 영상에서 왔는지는 셸이 가른다.
  final void Function(CookRequest request) onStart;

  @override
  State<CookHomeScreen> createState() => _CookHomeScreenState();
}

/// 조리 시작 요청.
///
/// 추천과 영상 중 **하나만** 담긴다. 둘을 함께 받는 자리가 있으면 어느 쪽으로 시작했는지
/// 알 수 없게 된다.
@immutable
class CookRequest {
  const CookRequest.menu(MenuSuggestion this.suggestion) : recipe = null;

  const CookRequest.video(VideoRecipe this.recipe) : suggestion = null;

  final MenuSuggestion? suggestion;
  final VideoRecipe? recipe;
}

class _CookHomeScreenState extends State<CookHomeScreen> {
  final _link = TextEditingController();

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cook = context.watch<CookViewModel>();
    final skin = context.skin;
    return ListScreen(
      header: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Strings.cookTitle, style: Tokens.hero(30)),
                const SizedBox(height: 2),
                Text(
                  Strings.cookSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: skin.inkFaint, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const Mascot(mood: MascotMood.hello, size: 56),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
        children: [
          _Picks(cook: cook, onStart: widget.onStart),
          const SizedBox(height: 14),
          _VideoSection(cook: cook, link: _link, onStart: widget.onStart),
          const SizedBox(height: 14),
          _VoiceHint(skin: skin),
        ],
      ),
    );
  }
}

/// 냉장고 재료로 만들 수 있는 추천.
class _Picks extends StatelessWidget {
  const _Picks({required this.cook, required this.onStart});

  final CookViewModel cook;
  final void Function(CookRequest request) onStart;

  /// 화면에 올릴 추천 수. 더 많으면 고르는 것이 일이 된다.
  static const _limit = 3;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final picks = cook.picks.take(_limit).toList(growable: false);

    return GlassPanel(
      weight: GlassWeight.thick,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InfoChip(
                label: Strings.cookPicksBadge,
                background: skin.band(Freshness.unknown).accentSoft,
                foreground: skin.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(Strings.cookPicksTitle,
                    style: text.titleMedium, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          if (_reason(picks) case final String why) ...[
            const SizedBox(height: 4),
            Text(
              why,
              style: text.labelMedium
                  ?.copyWith(color: skin.inkSubtle, fontWeight: FontWeight.w500),
            ),
          ],
          const SizedBox(height: 6),
          if (cook.loadingPicks && picks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            )
          else if (cook.picksError != null)
            // 못 고른 것과 부르지 못한 것은 다른 상황이다. 다시 시도할 수 있어야 한다.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      Strings.serverFailed,
                      style: text.bodyMedium?.copyWith(color: skin.inkFaint),
                    ),
                  ),
                  TextButton(
                    onPressed: () => cook.loadPicks(force: true),
                    child: const Text(Strings.retry),
                  ),
                ],
              ),
            )
          else if (picks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                Strings.cookPicksEmpty,
                style: text.bodyMedium?.copyWith(color: skin.inkFaint),
              ),
            )
          else
            for (final (index, pick) in picks.indexed)
              _PickRow(
                pick: pick,
                divided: index > 0,
                onTap: () => onStart(CookRequest.menu(pick)),
              ),
        ],
      ),
    );
  }

  /// 왜 이 메뉴들인지. **서버가 준 이유만 쓴다** — 없으면 줄을 비운다.
  ///
  /// 머리말의 부제를 되풀이하지 않는다. 같은 문장이 두 번 보이면 둘 다 읽히지 않는다.
  String? _reason(List<MenuSuggestion> picks) => picks.firstOrNull?.reason;
}

class _PickRow extends StatelessWidget {
  const _PickRow({
    required this.pick,
    required this.divided,
    required this.onTap,
  });

  final MenuSuggestion pick;
  final bool divided;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final palette = skin.band(Labels.availabilityBand(pick.availability));

    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided
            ? Border(top: BorderSide(color: skin.hairline))
            : const Border(),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: NavIcon(
                      glyph: NavGlyph.cook, color: palette.accent, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pick.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      _meta(pick),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(
                          color: skin.inkSubtle, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StartPill(skin: skin),
            ],
          ),
        ),
      ),
    );
  }

  /// 인분·시간·가용성. **모르는 값은 빼고 아는 것만 잇는다.**
  String _meta(MenuSuggestion pick) {
    final parts = <String>[Strings.menuServings(pick.servings)];
    final minutes = pick.estimatedMinutes;
    if (minutes != null) parts.add(Strings.menuMinutes(minutes));
    parts.add(Labels.availability(pick.availability));
    return parts.join(' · ');
  }
}

class _StartPill extends StatelessWidget {
  const _StartPill({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: ShapeDecoration(
          color: skin.strong,
          shape: const StadiumBorder(),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow_rounded, size: 14, color: skin.onStrong),
            const SizedBox(width: 4),
            Text(
              Strings.cookStart,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: skin.onStrong, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
}

/// 영상 링크를 넣고 정리한다.
class _VideoSection extends StatelessWidget {
  const _VideoSection({
    required this.cook,
    required this.link,
    required this.onStart,
  });

  final CookViewModel cook;
  final TextEditingController link;
  final void Function(CookRequest request) onStart;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final recipe = cook.recipe;
    final failure = cook.videoFailure;

    return GlassPanel(
      weight: GlassWeight.thick,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Strings.cookVideoTitle, style: text.titleMedium),
          const SizedBox(height: 4),
          Text(
            Strings.cookVideoHint,
            style: text.labelMedium
                ?.copyWith(color: skin.inkSubtle, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          _LinkRow(cook: cook, link: link),
          if (failure != null) ...[
            const SizedBox(height: 10),
            _VideoError(failure: failure),
          ],
          if (recipe != null) ...[
            const SizedBox(height: 10),
            _VideoCard(recipe: recipe),
            const SizedBox(height: 10),
            _VideoStartButton(
              onPressed: recipe.steps.isEmpty
                  ? null
                  : () => onStart(CookRequest.video(recipe)),
            ),
          ],
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.cook, required this.link});

  final CookViewModel cook;
  final TextEditingController link;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final busy = cook.summarizing;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: skin.chipNeutral,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: skin.hairline),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 18, color: skin.inkDim),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: link,
                    enabled: !busy,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    onSubmitted: (value) => cook.summarize(value),
                    style: Theme.of(context).textTheme.bodyLarge,
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: Strings.cookVideoPlaceholder,
                      hintStyle: TextStyle(color: skin.inkDim),
                      labelText: null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        _SummarizeButton(
          busy: busy,
          onPressed: busy ? null : () => cook.summarize(link.text),
        ),
      ],
    );
  }
}

class _SummarizeButton extends StatelessWidget {
  const _SummarizeButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SizedBox(
      height: 48,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: skin.strong,
          foregroundColor: skin.onStrong,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        // 도는 표시를 버튼 안에 두어 무엇을 기다리는지 분명히 한다.
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: skin.onStrong),
              )
            : const Text(Strings.cookVideoSubmit),
      ),
    );
  }
}

/// 정리한 영상 한 장.
class _VideoCard extends StatelessWidget {
  const _VideoCard({required this.recipe});

  final VideoRecipe recipe;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final ready = recipe.availability.isReady;
    final palette = skin.band(ready ? Freshness.fresh : Freshness.soon);

    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumb(skin: skin),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recipe.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                  _meta(recipe),
                  style: text.labelSmall?.copyWith(
                      color: skin.inkSubtle, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                InfoChip(
                  label: _match(recipe),
                  background: palette.accentSoft,
                  foreground: palette.accent,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 단계 수·시간·재료 수. **없는 값은 빼고 아는 것만 잇는다.**
  String _meta(VideoRecipe recipe) {
    final parts = <String>[];
    final minutes = recipe.estimatedMinutes;
    if (minutes != null) {
      parts.add(Strings.cookVideoSteps(recipe.steps.length, minutes));
    } else {
      parts.add('${recipe.steps.length}단계');
    }
    if (recipe.ingredients.isNotEmpty) {
      parts.add(
          Strings.cookVideoHave(recipe.haveCount, recipe.ingredients.length));
    }
    return parts.join(' · ');
  }

  /// 재료가 맞는지. 없는 것을 **이름으로** 말한다 — 개수만 말하면 뭘 사야 할지 모른다.
  String _match(VideoRecipe recipe) {
    if (recipe.missingIngredients.isEmpty) {
      return Labels.availability(recipe.availability);
    }
    return Strings.cookVideoMissing(recipe.missingIngredients.take(2).join(', '));
  }
}

/// 영상 자리. **실제 섬네일을 받아오지 않는다** — 받아오면 링크를 우리가 대신 여는 셈이다.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) => Container(
        width: 92,
        height: 64,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [skin.inkMuted, skin.inkSubtle],
          ),
        ),
        child: Center(
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: skin.raised, shape: BoxShape.circle),
            child: Icon(Icons.play_arrow_rounded, size: 16, color: skin.ink),
          ),
        ),
      );
}

class _VideoStartButton extends StatelessWidget {
  const _VideoStartButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: skin.ink,
          side: BorderSide(color: skin.divider),
          shape: const StadiumBorder(),
        ),
        icon: NavIcon(glyph: NavGlyph.cook, color: skin.ink, size: 18),
        label: const Text(Strings.cookVideoStart),
      ),
    );
  }
}

/// 정리 실패. **원인마다 할 일이 다르므로 문구를 나눈다.**
class _VideoError extends StatelessWidget {
  const _VideoError({required this.failure});

  final VideoFailure failure;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final palette = skin.band(Freshness.urgent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: palette.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _message(failure),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: palette.accent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _message(VideoFailure failure) => switch (failure) {
        VideoFailure.badLink => Strings.cookVideoBadLink,
        VideoFailure.notFound => Strings.cookVideoBadLink,
        VideoFailure.noScript => Strings.cookVideoNoScript,
        VideoFailure.notRecipe => Strings.cookVideoFailed,
        VideoFailure.unreachable => Strings.serverFailed,
        VideoFailure.notConnected => Strings.serverFailed,
      };
}

class _VoiceHint extends StatelessWidget {
  const _VoiceHint({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_none_rounded, size: 15, color: skin.inkSubtle),
          const SizedBox(width: 6),
          Text(
            Strings.cookVoiceHint,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: skin.inkSubtle, fontWeight: FontWeight.w500),
          ),
        ],
      );
}
