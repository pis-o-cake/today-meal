/// 조리 완료 (UI-10).
///
/// 목업 `mockup/canvas/CookDone.dc.html` 을 옮긴 것이다.
///
/// IMPORTANT: **뺐다고 말하는 것은 서버가 실제로 뺀 것만이다.** 추천에서 시작한 조리는
/// 서버가 재고를 빼고 그 내용을 돌려주며([CookedResult]), 영상 레시피는 차감 단위가 없어
/// 아무것도 빼지 않는다 — 그 경우 화면이 "말로 빼 주세요" 라고 말한다.
library;

import 'package:flutter/material.dart';

import '../../core/design/band.dart';
import '../../core/design/labels.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';
import '../widgets/glass.dart';
import '../widgets/mascot.dart';
import 'cook_session.dart';

class CookDoneScreen extends StatelessWidget {
  const CookDoneScreen({
    required this.plan,
    required this.result,
    required this.minutes,
    required this.onClose,
    required this.onCookAgain,
    this.error,
    super.key,
  });

  final CookPlan plan;

  /// 서버가 뺀 내용. 영상 레시피이거나 호출이 실패하면 `null`.
  final CookedResult? result;

  /// 실제로 걸린 시간(분). 화면에 머문 시간이며 추정이 아니다.
  final int minutes;

  final VoidCallback onClose;
  final VoidCallback onCookAgain;

  /// 조리 확인이 실패했다. **성공한 것처럼 그리지 않는다.**
  final Object? error;

  /// 서버가 실제로 재고를 빼고 기록을 남겼는지.
  bool get _logged => error == null && (result?.didApply ?? false);

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: skin.listBackground),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: SizedBox(
                    width: Tokens.tap,
                    height: Tokens.tap,
                    child: IconButton(
                      onPressed: onClose,
                      iconSize: 20,
                      color: skin.inkMuted,
                      tooltip: Strings.close,
                      style: IconButton.styleFrom(
                        backgroundColor: skin.glass,
                        shape: CircleBorder(side: BorderSide(color: skin.edge)),
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) => Mascot(
                            mood: MascotMood.done,
                            size: (constraints.maxHeight * 0.5)
                                .clamp(96.0, 150.0),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          Strings.cookDoneTitle,
                          textAlign: TextAlign.center,
                          style: Tokens.hero(38, height: 1.15)
                              .copyWith(color: skin.band(Freshness.fresh).accent),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          Strings.cookDoneSummary(
                              plan.name, plan.servings, minutes),
                          textAlign: TextAlign.center,
                          style: text.bodyLarge?.copyWith(
                              color: skin.inkFaint,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Deducted(plan: plan, result: result, error: error),
              ),
              const SizedBox(height: 10),
              _VoiceHint(skin: skin, canDeduct: plan.canDeduct),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: onCookAgain,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: skin.ink,
                            side: BorderSide(color: skin.divider),
                            shape: const StadiumBorder(),
                          ),
                          icon: const Icon(Icons.undo_rounded, size: 18),
                          label: const Text(Strings.undo),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton(
                          onPressed: onClose,
                          style: FilledButton.styleFrom(
                            backgroundColor: skin.strong,
                            foregroundColor: skin.onStrong,
                            shape: const StadiumBorder(),
                          ),
                          child: const Text(Strings.cookDoneConfirm),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // 실제로 반영된 경우에만 기록을 말한다. 되물었거나 실패했으면 아무것도
              // 남지 않았으므로, 남겼다고 하면 거짓이다.
              if (_logged)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    Strings.cookDoneLogged,
                    style: text.labelMedium?.copyWith(
                        color: skin.inkFaint, fontWeight: FontWeight.w500),
                  ),
                )
              else
                const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/// 서버가 뺀 재료.
class _Deducted extends StatelessWidget {
  const _Deducted({
    required this.plan,
    required this.result,
    required this.error,
  });

  final CookPlan plan;
  final CookedResult? result;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;

    // 확인이 실패했거나 차감 단위가 없다. 뺐다고 말하지 않는다.
    if (error != null || result == null || !plan.canDeduct) {
      return _NotDeducted(failed: error != null);
    }

    final cooked = result!;
    // 서버가 되물었다. 아무것도 반영되지 않았다.
    if (cooked.clarificationQuestion != null) {
      return _Notice(
        icon: Icons.help_outline_rounded,
        grade: Freshness.unknown,
        text: cooked.clarificationQuestion!,
      );
    }

    return GlassPanel(
      weight: GlassWeight.thick,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(Strings.cookDoneUsedTitle, style: text.titleSmall),
                ),
                Text(
                  cooked.alreadyApplied
                      ? Strings.cookDoneKept
                      : Strings.cookDoneAuto,
                  style: text.labelSmall?.copyWith(
                      color: skin.inkDim, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          // 양을 몰라 빼지 못한 재료. **숫자를 지어내지 않았다는 사실을 밝힌다.**
          for (final (index, name) in cooked.skippedIngredients.indexed)
            _Row(
              name: name,
              meta: Strings.quantityUnknown,
              chip: Strings.cookDoneKept,
              used: false,
              divided: index > 0,
            ),
          if (cooked.skippedIngredients.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                Labels.availability(MenuAvailability.ready),
                style: text.labelMedium?.copyWith(
                    color: skin.inkSubtle, fontWeight: FontWeight.w500),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.name,
    required this.meta,
    required this.chip,
    required this.used,
    required this.divided,
  });

  final String name;
  final String meta;
  final String chip;
  final bool used;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final palette = skin.band(Freshness.urgent);

    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      decoration: BoxDecoration(
        border: divided
            ? Border(top: BorderSide(color: skin.hairline))
            : const Border(),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name, style: text.titleSmall),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: text.labelMedium?.copyWith(
                      color: skin.inkSubtle, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InfoChip(
            label: chip,
            background: used ? palette.accentSoft : skin.chipNeutral,
            foreground: used ? palette.accent : skin.inkFaint,
          ),
        ],
      ),
    );
  }
}

/// 재고를 빼지 않았다.
class _NotDeducted extends StatelessWidget {
  const _NotDeducted({required this.failed});

  /// 서버 호출이 실패한 것인지. 차감 단위가 없는 것과 원인이 다르다.
  final bool failed;

  @override
  Widget build(BuildContext context) => _Notice(
        icon: failed
            ? Icons.error_outline_rounded
            : Icons.mic_none_rounded,
        grade: failed ? Freshness.urgent : Freshness.unknown,
        text: failed ? Strings.serverFailed : Strings.cookDoneVoiceHint,
      );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.grade,
    required this.text,
  });

  final IconData icon;
  final Freshness grade;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.skin.band(grade);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(Tokens.radiusCard),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: palette.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: palette.accent, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceHint extends StatelessWidget {
  const _VoiceHint({required this.skin, required this.canDeduct});

  final Skin skin;

  /// 차감이 일어났는지. 일어나지 않았으면 안내가 위쪽 알림에 이미 있다.
  final bool canDeduct;

  @override
  Widget build(BuildContext context) {
    if (!canDeduct) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mic_none_rounded, size: 15, color: skin.inkFaint),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              Strings.cookDoneVoiceHint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: skin.inkFaint, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
