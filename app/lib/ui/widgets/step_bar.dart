/// 듣기 → 확인 → 반영 진행 표시.
///
/// 목업 `Listening`·`Clarify`·`Result` 의 머리말이다. 세 칸을 가로로 나눠 각 칸에
/// **막대와 이름**을 둔다.
///
/// - 지난 단계: 강조색 막대를 옅게 두고 이름 앞에 체크
/// - 지금 단계: 강조색 막대에 빛이 흐르고 이름은 굵게, 앞에 맥박하는 점
/// - 다음 단계: 회색 막대와 옅은 이름
///
/// 음성만으로는 어디까지 진행됐는지 알 수 없어 화면에 남긴다. 색만으로 구분하지 않고
/// 이름·굵기·기호를 함께 바꾼다.
library;

import 'package:flutter/material.dart';

import '../../core/design/motion.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';

/// 한 단계.
class VoiceStep {
  const VoiceStep({required this.name, required this.currentName});

  /// 지나갔거나 아직 오지 않은 단계의 이름. "듣기"·"확인"·"반영".
  final String name;

  /// 지금 단계일 때의 이름. "듣는 중"·"확인 중"·"반영 완료".
  final String currentName;
}

class StepBar extends StatelessWidget {
  const StepBar({
    required this.steps,
    required this.current,
    required this.accent,
    required this.accentBright,
    this.doneAtLast = false,
    super.key,
  });

  final List<VoiceStep> steps;

  /// 지금 단계의 인덱스.
  final int current;

  /// 이름에 쓰는 진한 강조색.
  final Color accent;

  /// 막대와 점에 쓰는 밝은 강조색.
  final Color accentBright;

  /// 마지막 단계에서 맥박 대신 완료 표시를 쓸지.
  ///
  /// 반영은 **끝난 상태**라 계속 맥박하면 아직 하고 있는 것으로 읽힌다.
  final bool doneAtLast;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;

    return Semantics(
      label: '진행 단계',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (index, step) in steps.indexed)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == steps.length - 1 ? 0 : 6),
                child: _Step(
                  step: step,
                  state: index < current
                      ? _StepState.done
                      : index == current
                          ? _StepState.now
                          : _StepState.next,
                  finished: doneAtLast && index == steps.length - 1,
                  accent: accent,
                  accentBright: accentBright,
                  skin: skin,
                  text: text,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _StepState { done, now, next }

class _Step extends StatelessWidget {
  const _Step({
    required this.step,
    required this.state,
    required this.finished,
    required this.accent,
    required this.accentBright,
    required this.skin,
    required this.text,
  });

  final VoiceStep step;
  final _StepState state;
  final bool finished;
  final Color accent;
  final Color accentBright;
  final Skin skin;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final now = state == _StepState.now;
    return Semantics(
      label: now ? '${step.currentName} 진행 중' : step.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _track(context),
          const SizedBox(height: 9),
          SizedBox(height: 20, child: _label()),
        ],
      ),
    );
  }

  Widget _track(BuildContext context) {
    final bar = switch (state) {
      // 지난 단계도 색을 남긴다. 회색으로 되돌리면 되돌아간 것처럼 보인다.
      _StepState.done => Container(
          height: 6,
          decoration: BoxDecoration(
            color: accentBright.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      _StepState.now => Container(
          height: 6,
          decoration: BoxDecoration(
            color: accentBright,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: accentBright.withValues(alpha: 0.33),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          // 끝난 단계에서는 빛을 흘리지 않는다.
          child: finished ? null : const _Sheen(),
        ),
      _StepState.next => Container(
          height: 6,
          decoration: BoxDecoration(
            color: skin.divider,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    };
    return ClipRRect(borderRadius: BorderRadius.circular(3), child: bar);
  }

  Widget _label() {
    final now = state == _StepState.now;
    final label = now ? step.currentName : step.name;
    final style = text.labelLarge?.copyWith(
      color: switch (state) {
        _StepState.now => accent,
        _StepState.done => skin.inkMuted,
        _StepState.next => skin.inkSubtle,
      },
      fontWeight: now ? FontWeight.w800 : FontWeight.w600,
    );

    return Row(
      children: [
        switch (state) {
          _StepState.done => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.check_rounded, size: 14, color: accentBright),
            ),
          _StepState.now => Padding(
              padding: const EdgeInsets.only(right: 5),
              child: finished
                  ? Icon(Icons.check_circle_rounded, size: 16, color: accent)
                  : _Pulse(color: accent),
            ),
          _StepState.next => const SizedBox.shrink(),
        },
        Flexible(
          child: Text(label, overflow: TextOverflow.ellipsis, style: style),
        ),
      ],
    );
  }
}

/// 막대 위로 흐르는 빛.
///
/// 목업의 `<animate>` 를 옮긴 것이다 — 폭 절반짜리 밝은 띠가 왼쪽에서 오른쪽으로
/// 지난다. 진행률이 아니라 **지금 하고 있다**는 표시다.
class _Sheen extends StatefulWidget {
  const _Sheen();

  @override
  State<_Sheen> createState() => _SheenState();
}

class _SheenState extends State<_Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: Motion.stepSheen,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 모션 감소에서는 흐르지 않는다. 막대의 색만으로 현재 단계를 읽는다.
    if (context.reduceMotion) {
      _run.stop();
    } else if (!_run.isAnimating) {
      _run.repeat();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _run,
      builder: (context, _) => FractionallySizedBox(
        widthFactor: 0.5,
        alignment: Alignment(_run.value * 4 - 2, 0),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x00FFFFFF), Color(0xCCFFFFFF), Color(0x00FFFFFF)],
            ),
          ),
        ),
      ),
    );
  }
}

/// 지금 단계의 맥박 점.
///
/// 가운데 점은 그대로 있고 뒤의 원이 커지며 사라진다. 점만 깜빡이면 오류 표시로 읽힌다.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.color});

  final Color color;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: Motion.pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _beat.stop();
    } else if (!_beat.isAnimating) {
      _beat.repeat();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 14,
        height: 14,
        child: AnimatedBuilder(
          animation: _beat,
          builder: (context, _) => CustomPaint(
            painter: _PulsePainter(
              color: widget.color,
              phase: context.reduceMotion ? 0 : _beat.value,
            ),
          ),
        ),
      );
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.color, required this.phase});

  final Color color;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final unit = size.width / 16;
    // 목업의 r 4→8, opacity 0.35→0 을 옮긴 것이다.
    final wave = (phase < 0.5 ? phase : 1 - phase) * 2;
    if (phase > 0) {
      canvas.drawCircle(
        center,
        (4 + 4 * wave) * unit,
        Paint()..color = color.withValues(alpha: 0.35 * (1 - wave)),
      );
    }
    canvas.drawCircle(center, 4 * unit, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.phase != phase || old.color != color;
}

/// 대화 화면의 닫기 버튼.
class CloseCircle extends StatelessWidget {
  const CloseCircle({required this.onPressed, this.label, super.key});

  final VoidCallback onPressed;
  final String? label;

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
        icon: const Icon(Icons.close_rounded),
      ),
    );
  }
}
