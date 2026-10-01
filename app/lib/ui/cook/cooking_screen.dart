/// 조리 진행 (UI-10).
///
/// 목업 `mockup/canvas/Cooking.dc.html` 을 옮긴 것이다. 손이 젖어 있는 상태에서 보는
/// 화면이므로 지금 단계의 글자가 화면에서 가장 크고, 버튼은 아래쪽 엄지 범위에 모여 있다.
///
/// IMPORTANT: **타이머가 없는 단계에 시간을 만들지 않는다.** 원본에 시간이 적혀 있지 않으면
/// 눈금 대신 "말로 맞추라" 고 안내한다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/motion.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../domain/model/inventory.dart';
import '../widgets/glass.dart';
import 'cook_session.dart';
import 'cooking_view_model.dart';

class CookingScreen extends StatelessWidget {
  const CookingScreen({required this.onDone, super.key});

  /// 마지막 단계를 마쳤다. 완료 화면으로 넘긴다.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final cooking = context.watch<CookingViewModel>();
    final skin = context.skin;

    // 단계가 하나도 없으면 진행할 것이 없다. 빈 화면을 그리지 않고 바로 돌려보낸다.
    if (cooking.plan.isEmpty) return _Empty(skin: skin);

    return DecoratedBox(
      decoration: BoxDecoration(gradient: skin.listBackground),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              _Header(plan: cooking.plan),
              _Progress(cooking: cooking),
              // 내용이 짧으면 가운데로 모으고, 길면 스크롤한다. 위에 붙여 두면 타이머가
              // 없는 단계에서 화면 아래 절반이 비어 손이 닿는 자리와 멀어진다.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight - 20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _CurrentStep(step: cooking.step),
                          const SizedBox(height: 12),
                          if (cooking.hasTimer)
                            _Timer(cooking: cooking)
                          else
                            _NoTimer(skin: skin),
                          if (cooking.nextText != null) ...[
                            const SizedBox(height: 12),
                            _NextPeek(text: cooking.nextText!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _Commands(skin: skin),
              _Controls(cooking: cooking, onDone: onDone),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(gradient: skin.listBackground),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(Strings.cookVideoFailed,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text(Strings.close),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.plan});

  final CookPlan plan;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          _RoundButton(
            icon: Icons.close_rounded,
            label: Strings.cookingClose,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text(plan.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium),
                Text(
                  '${Strings.cookingMode} · ${Strings.cookingServings(plan.servings)}',
                  style: text.labelSmall?.copyWith(
                      color: skin.inkDim, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          _RoundButton(
            icon: Icons.format_list_bulleted_rounded,
            label: Strings.cookingAllSteps,
            onPressed: () => _showAll(context),
          ),
        ],
      ),
    );
  }

  /// 전체 단계. 지금 어디쯤인지 확인하고 건너뛸 수 있어야 한다.
  void _showAll(BuildContext context) {
    final cooking = context.read<CookingViewModel>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.skin.raised,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 8),
          children: [
            for (final (index, step) in cooking.plan.steps.indexed)
              ListTile(
                selected: index == cooking.at,
                leading: Text('${index + 1}',
                    style: Theme.of(sheet).textTheme.titleSmall),
                title: Text(step.text),
                onTap: () {
                  cooking.goTo(index);
                  Navigator.of(sheet).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;

  /// 스크린리더 이름. 아이콘만 있는 버튼이라 반드시 둔다.
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SizedBox(
      width: Tokens.tap,
      height: Tokens.tap,
      child: IconButton(
        onPressed: onPressed,
        iconSize: 20,
        color: skin.inkMuted,
        tooltip: label,
        style: IconButton.styleFrom(
          backgroundColor: skin.glass,
          shape: CircleBorder(side: BorderSide(color: skin.edge)),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

/// 단계 막대와 번호. 읽어주는 중인지도 함께 보인다.
class _Progress extends StatelessWidget {
  const _Progress({required this.cooking});

  final CookingViewModel cooking;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final palette = skin.band(Freshness.urgent);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              for (final (index, _) in cooking.plan.steps.indexed) ...[
                if (index > 0) const SizedBox(width: 5),
                Expanded(
                  child: Semantics(
                    selected: index == cooking.at,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: switch (index.compareTo(cooking.at)) {
                          -1 => palette.accentBright,
                          0 => palette.accent,
                          _ => skin.track,
                        },
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                Strings.cookingStepOf(cooking.at + 1, cooking.plan.total),
                style: text.labelLarge?.copyWith(
                    color: palette.accent, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 4),
              Text(
                Strings.cookingStepTotal(cooking.plan.total),
                style: text.labelLarge?.copyWith(
                    color: skin.inkDim, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              // 읽는 동안에만 읽는 중이라고 한다. 다 읽었으면 다시 들을 길을 준다.
              if (cooking.reading)
                _Reading(palette: palette)
              else
                IconButton(
                  onPressed: cooking.readAgain,
                  tooltip: Strings.cookingReadAgain,
                  iconSize: 20,
                  color: skin.inkSubtle,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.volume_up_rounded),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 읽어주는 중 표시. 막대 그림이 오르내린다.
class _Reading extends StatefulWidget {
  const _Reading({required this.palette});

  final BandPalette palette;

  @override
  State<_Reading> createState() => _ReadingState();
}

class _ReadingState extends State<_Reading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: Motion.pulse,
  );

  bool _started = false;

  /// 막대 셋의 위상. 목업의 0.9s · 1.1s · 0.8s 를 한 시계로 옮긴 값이다.
  static const _phases = [0.0, 0.35, 0.7];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // IMPORTANT: MediaQuery 는 initState 에서 읽을 수 없다.
    if (_started) return;
    _started = true;
    if (!context.reduceMotion) _wave.repeat();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Row(
      children: [
        AnimatedBuilder(
          animation: _wave,
          builder: (context, _) => Row(
            children: [
              for (final (index, phase) in _phases.indexed) ...[
                if (index > 0) const SizedBox(width: 3),
                Container(
                  width: 3,
                  height: _height(phase),
                  decoration: BoxDecoration(
                    color: widget.palette.accent,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          Strings.cookingReading,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: skin.inkSubtle, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  /// 막대 하나의 높이. 4 ~ 12 사이를 오간다.
  double _height(double phase) {
    final at = (_wave.value + phase) % 1;
    final wave = (at < 0.5 ? at : 1 - at) * 2;
    return 4 + wave * 8;
  }
}

/// 지금 단계. 화면에서 가장 큰 글자다.
class _CurrentStep extends StatelessWidget {
  const _CurrentStep({required this.step});

  final CookStep step;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return GlassPanel(
      weight: GlassWeight.thick,
      radius: 26,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.text,
            style: const TextStyle(
              fontSize: 25,
              height: 1.38,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          if (step.ingredients.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in step.ingredients)
                  InfoChip(
                    label: name,
                    background: skin.chipNeutral,
                    foreground: skin.inkMuted,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 단계 타이머. 눈금이 남은 시간만큼 줄어든다.
class _Timer extends StatelessWidget {
  const _Timer({required this.cooking});

  final CookingViewModel cooking;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final palette = skin.band(cooking.rang ? Freshness.urgent : Freshness.soon);

    return GlassPanel(
      weight: GlassWeight.thick,
      radius: 26,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          SizedBox(
            width: 124,
            height: 124,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 남은 비율을 눈금으로. 진행률이 아니라 **남은 양**이다.
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: cooking.progress,
                    strokeWidth: 9,
                    strokeCap: StrokeCap.round,
                    backgroundColor: skin.track,
                    valueColor: AlwaysStoppedAnimation(palette.accent),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _clock(cooking.remaining ?? 0),
                      style: text.headlineMedium?.copyWith(
                        fontSize: 28,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      cooking.step.timerLabel ?? '',
                      style: text.labelSmall?.copyWith(
                          color: skin.inkDim, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: cooking.toggleTimer,
                    style: FilledButton.styleFrom(
                      backgroundColor: skin.strong,
                      foregroundColor: skin.onStrong,
                      shape: const StadiumBorder(),
                    ),
                    icon: Icon(
                      cooking.running
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 16,
                    ),
                    label: Text(cooking.running
                        ? Strings.cookingPause
                        : Strings.cookingResume),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SmallButton(
                        label: Strings.cookingPlusMinute,
                        onPressed: cooking.addMinute,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SmallButton(
                        label: Strings.cookingRestart,
                        onPressed: cooking.restartTimer,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// `02:48` 꼴. 분이 60 을 넘어도 분으로 표시한다 — 조리에 시간 단위는 필요 없다.
  String _clock(int seconds) {
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: skin.ink,
          side: BorderSide(color: skin.divider),
          shape: const StadiumBorder(),
          padding: EdgeInsets.zero,
        ),
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

/// 이 단계에 시간이 적혀 있지 않다. **숫자를 만들지 않고 말로 맞추게 한다.**
class _NoTimer extends StatelessWidget {
  const _NoTimer({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: skin.trackDashed, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.timer_outlined, size: 22, color: skin.inkFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                Strings.cookingNoTimer,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: skin.inkFaint, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

/// 다음 단계 미리보기. 무엇을 준비할지 알 수 있어야 한다.
class _NextPeek extends StatelessWidget {
  const _NextPeek({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            Strings.cookingNextLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: skin.inkDim, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: skin.inkMuted, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 조리 중에 말로 할 수 있는 것. 손이 젖어 있을 때 쓰는 길이다.
class _Commands extends StatelessWidget {
  const _Commands({required this.skin});

  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final palette = skin.band(Freshness.urgent);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      // 한 줄에 둔다. 줄이 나뉘면 안내와 예시가 따로 읽힌다. 좁은 화면에서는 줄여 맞춘다.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.graphic_eq_rounded, size: 14, color: palette.accent),
            const SizedBox(width: 5),
            Text(
              Strings.cookingHandsFree,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: palette.accent, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            const FloatingChip(label: Strings.cookingSayNext),
            const SizedBox(width: 8),
            const FloatingChip(label: Strings.cookingSayAgain),
            const SizedBox(width: 8),
            const FloatingChip(label: Strings.cookingSayTimer),
          ],
        ),
      ),
    );
  }
}

/// 이전 · 다음(또는 완료).
class _Controls extends StatelessWidget {
  const _Controls({required this.cooking, required this.onDone});

  final CookingViewModel cooking;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final palette = skin.band(Freshness.fresh);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 56,
              child: OutlinedButton(
                onPressed: cooking.isFirst ? null : cooking.previous,
                style: OutlinedButton.styleFrom(
                  foregroundColor: skin.ink,
                  side: BorderSide(color: skin.divider),
                  shape: const StadiumBorder(),
                ),
                child: const Text(Strings.cookingPrev),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 56,
              child: cooking.isLast
                  ? FilledButton(
                      onPressed: cooking.finishing ? null : onDone,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: skin.onStrong,
                        shape: const StadiumBorder(),
                      ),
                      child: cooking.finishing
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: skin.onStrong),
                            )
                          : const Text(Strings.cookingFinish),
                    )
                  : FilledButton.icon(
                      onPressed: cooking.next,
                      style: FilledButton.styleFrom(
                        backgroundColor: skin.strong,
                        foregroundColor: skin.onStrong,
                        shape: const StadiumBorder(),
                      ),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text(Strings.cookingNext),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
