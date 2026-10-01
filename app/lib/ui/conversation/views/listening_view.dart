/// 듣는 중 (UI-14).
///
/// 목업 `Listening.dc.html` 이다 — 파동 위의 캐릭터, "듣고 있어요", 받아 적는 중 카드,
/// 20초 안내, 취소.
///
/// **중간 전사를 그대로 보여준다.** 잘못 들었으면 말을 끝내기 전에 사용자가 안다. 없는
/// 문장을 채워 넣지 않으며, 아직 아무 말도 들리지 않았으면 카드를 비워 둔다.
library;

import 'package:flutter/material.dart';

import '../../../core/design/band.dart';
import '../../../core/design/labels.dart';
import '../../../core/design/motion.dart';
import '../../../core/design/skin.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/voice/voice_session_manager.dart';
import '../../../domain/model/inventory.dart';
import '../../../domain/repository/repositories.dart';
import '../../widgets/glass.dart';
import '../../widgets/living_mascot.dart';
import '../../widgets/seconds_left.dart';

/// 듣던 화면에서 바로 알리는 반영 결과.
///
/// 글래스 테마는 결과 화면으로 넘어가지 않는다. 화면이 바뀌면 다른 일이 시작된 것으로
/// 읽히므로, 말한 자리에서 무엇이 바뀌었는지 알린다.
class AppliedResult {
  const AppliedResult({
    required this.changes,
    required this.onConfirm,
    this.onUndo,
  });

  /// 서버가 확인한 변경.
  final List<CommandChange> changes;

  /// 되돌릴 수 있으면 콜백이 있다.
  final VoidCallback? onUndo;

  /// 화면을 닫는다. 추가 저장이 아니다.
  final VoidCallback onConfirm;
}

class ListeningView extends StatelessWidget {
  const ListeningView({
    required this.partial,
    required this.palette,
    required this.level,
    required this.onCancel,
    this.processing = false,
    this.answer,
    this.applied,
    super.key,
  });

  /// 지금까지 들은 말. 아직 없으면 `null` 이다.
  final String? partial;

  final BandPalette palette;

  /// 마이크 입력 크기(0~1).
  final double level;

  /// 서버가 처리하는 중인지. 마이크는 닫혔고 결과를 기다린다.
  final bool processing;

  /// 읽어주고 있는 답. 반영한 것이 없는 응답은 이 화면에 머문 채 알린다.
  final String? answer;

  /// 반영 결과. 있으면 받아 적던 카드 자리에 바뀐 재고를 적는다.
  final AppliedResult? applied;

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final said = partial;
    final told = answer;
    final done = applied;

    return Column(
      children: [
        Expanded(
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stage = constraints.biggest.shortestSide.clamp(180.0, 320.0);
                return ListeningStage(
                  palette: palette,
                  size: stage,
                  child: LivingMascot(
                    mood: palette.mood,
                    size: stage / LivingMascot.spread,
                    energy: processing ? 0 : level,
                    ripples: !processing,
                    accent: palette.accentBright,
                  ),
                );
              },
            ),
          ),
        ),
        Text(
          switch ((done, told, processing)) {
            (AppliedResult _, _, _) => Strings.voiceDone,
            (_, String _, _) => Strings.voiceSpeaking,
            (_, _, true) => Strings.voiceProcessing,
            _ => Strings.voiceHeroListening,
          },
          style: Tokens.hero(38, height: 1.15).copyWith(color: palette.accent),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            told ?? Strings.voiceListeningHint,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: text.bodyLarge?.copyWith(
              color: told == null ? skin.inkFaint : skin.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          // 바뀐 것이 없으면 들은 말을 그대로 둔다. 빈 카드는 무엇이 바뀐 것으로 읽힌다.
          child: done != null && done.changes.isNotEmpty
              ? _Applied(changes: done.changes, palette: palette, skin: skin)
              : _Transcript(
                  said: said,
                  palette: palette,
                  skin: skin,
                  live: !processing,
                ),
        ),
        const SizedBox(height: 16),
        done == null
            ? _Footer(
                skin: skin,
                onCancel: onCancel,
                live: !processing,
                returning: told != null,
              )
            : _Settled(result: done, skin: skin),
      ],
    );
  }
}

/// 바뀐 재고 카드. 받아 적던 카드와 같은 자리, 같은 모양이다.
class _Applied extends StatelessWidget {
  const _Applied({
    required this.changes,
    required this.palette,
    required this.skin,
  });

  final List<CommandChange> changes;
  final BandPalette palette;
  final Skin skin;

  /// 받아 적던 카드의 본문과 같은 높이 한계. 넘치면 스크롤한다.
  static const _maxHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return GlassPanel(
      weight: GlassWeight.thick,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      shadow: [skin.shade(0.08, 28, 10)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 20, color: palette.accent),
              const SizedBox(width: 8),
              Text(
                Strings.resultChanged,
                style: text.labelMedium
                    ?.copyWith(color: palette.accent, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32, maxHeight: _maxHeight),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final change in changes) _AppliedRow(change: change, skin: skin),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 바뀐 재료 한 줄. 이름과 바뀐 뒤의 양, 그 아래에 한 일과 기한이다.
class _AppliedRow extends StatelessWidget {
  const _AppliedRow({required this.change, required this.skin});

  final CommandChange change;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final after = change.after;
    final detail = [Labels.changeAction(change.action), Labels.changeExpiry(change)]
        .where((part) => part.isNotEmpty)
        .join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  change.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleLarge?.copyWith(
                      fontSize: 21, height: 1.3, fontWeight: FontWeight.w600),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(color: skin.inkFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 양을 모르면 적지 않는다. 없는 숫자를 채우지 않는다.
          if (after != null)
            Text(
              '${Labels.number(after)}${Labels.unit(change.unit)}',
              style: text.titleLarge?.copyWith(
                  fontSize: 21, height: 1.3, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}

/// 받아 적는 중 카드.
class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.said,
    required this.palette,
    required this.skin,
    required this.live,
  });

  final String? said;
  final BandPalette palette;
  final Skin skin;

  /// 마이크가 열려 있는지. 물결과 깜빡이는 막대를 켠다.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final heard = said != null && said!.isNotEmpty;

    return GlassPanel(
      weight: GlassWeight.thick,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      shadow: [skin.shade(0.08, 28, 10)],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Waveform(color: palette.accent, live: live),
              const SizedBox(width: 8),
              Text(
                Strings.voiceTranscribing,
                style: text.labelMedium
                    ?.copyWith(color: palette.accent, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 아직 들은 말이 없으면 비워 둔다. 예시 문장을 채우면 말한 것으로 읽힌다.
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32, maxHeight: 120),
            child: SingleChildScrollView(
              reverse: true,
              child: heard
                  ? _WithCaret(said: said!, color: palette.accent, live: live)
                  : Text(
                      Strings.voiceNothingHeard,
                      style: text.titleLarge
                          ?.copyWith(fontSize: 21, color: skin.inkDim),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 전사 뒤의 깜빡이는 입력 막대.
class _WithCaret extends StatelessWidget {
  const _WithCaret({
    required this.said,
    required this.color,
    required this.live,
  });

  final String said;
  final Color color;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: 21, height: 1.45, fontWeight: FontWeight.w600);
    return Text.rich(
      TextSpan(
        text: said,
        style: style,
        children: [
          if (live)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Container(width: 2, height: 22, color: color),
              ),
            ),
        ],
      ),
    );
  }
}

/// 다섯 개의 막대가 오르내리는 물결.
///
/// 목업의 `<animate>` 다섯 줄을 옮긴 것이다. 각 막대가 다른 주기로 움직여 **소리처럼**
/// 보인다. 같은 주기로 두면 이퀄라이저 장식으로 읽힌다.
class _Waveform extends StatefulWidget {
  const _Waveform({required this.color, required this.live});

  final Color color;
  final bool live;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _run =
      AnimationController(vsync: this, duration: const Duration(seconds: 2));

  /// 막대마다의 주기(초). 목업의 `dur` 값이다.
  static const _periods = [1.1, 0.9, 1.2, 1.0, 1.3];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Waveform old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final move = widget.live && !context.reduceMotion;
    if (move && !_run.isAnimating) {
      _run.repeat();
    } else if (!move && _run.isAnimating) {
      _run.stop();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        height: 20,
        child: AnimatedBuilder(
          animation: _run,
          builder: (context, _) => CustomPaint(
            painter: _WavePainter(
              color: widget.color,
              time: _run.isAnimating ? _run.value * 2 : -1,
              periods: _periods,
            ),
          ),
        ),
      );
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.color,
    required this.time,
    required this.periods,
  });

  final Color color;

  /// 흐른 시간(초). 음수면 멈춘 상태로 그린다.
  final double time;
  final List<double> periods;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const heights = [8.0, 14.0, 18.0, 12.0, 6.0];
    for (var i = 0; i < periods.length; i++) {
      final base = heights[i];
      final height = time < 0
          ? base
          : base + (18 - base) * _wave(time / periods[i] + i * 0.3);
      final top = (size.height - height) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * 6 + 1, top, 4, height),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  /// 0~1 사이를 오가는 삼각파. 정현파보다 소리처럼 각이 진다.
  double _wave(double t) {
    final phase = t % 1;
    return phase < 0.5 ? phase * 2 : (1 - phase) * 2;
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.time != time || old.color != color;
}

/// 남은 시간 안내와 취소.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.skin,
    required this.onCancel,
    required this.live,
    required this.returning,
  });

  final Skin skin;
  final VoidCallback onCancel;

  /// 마이크가 열려 있는지.
  final bool live;

  /// 답을 읽고 곧 닫히는지.
  final bool returning;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (live) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: skin.band(Freshness.urgent).accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: SecondsLeft(
                    from: VoiceSessionManager.commandTimeout.inSeconds,
                    builder: (context, seconds) =>
                        Text(Strings.micLimitHint(seconds), style: style),
                  ),
                ),
              ] else if (returning)
                _Returning(style: style)
              else
                // 마이크가 닫혔으면 마이크 안내를 남기지 않는다. 줄은 지켜 화면이
                // 들썩이지 않게 한다.
                Text('', style: style),
            ],
          ),
          const SizedBox(height: 10),
          _Pill(label: Strings.voiceCancel, onTap: onCancel),
        ],
      ),
    );
  }
}

/// 반영 뒤의 안내와 되돌리기·확인. 듣는 중의 아래쪽과 높이가 같아 화면이 들썩이지 않는다.
class _Settled extends StatelessWidget {
  const _Settled({required this.result, required this.skin});

  final AppliedResult result;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final undo = result.onUndo;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        children: [
          _Returning(
            style: text.labelMedium
                ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (undo != null) ...[
                Expanded(
                  child: _Pill(
                    label: Strings.undo,
                    icon: Icons.undo_rounded,
                    onTap: undo,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _Pill(label: Strings.resultConfirm, onTap: result.onConfirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 호출 대기로 돌아가기까지 남은 시간.
class _Returning extends StatelessWidget {
  const _Returning({required this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) => SecondsLeft(
        from: VoiceSessionManager.resultMinimum.inSeconds,
        builder: (context, seconds) =>
            Text(Strings.resultReturnHint(seconds), style: style),
      );
}

/// 아래쪽의 유리 알약 버튼.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      height: 52,
      width: double.infinity,
      child: GlassPill(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: skin.ink),
                const SizedBox(width: 8),
              ],
              Text(label, style: text.titleMedium?.copyWith(fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}
