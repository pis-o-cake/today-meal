/// 확인 질문 (UI-04).
///
/// 목업 `Clarify.dc.html` 이다 — 먼저 반영한 항목, 캐릭터, 질문, 후속 응답 창.
///
/// **선택지 버튼은 아직 두지 않는다.** 서버는 질문을 한 문장으로만 주고 고를 수 있는
/// 값의 목록을 주지 않는다. 문장에서 선택지를 짐작해 버튼을 만들면, 눌렀을 때 서버가
/// 무엇으로 받을지 알 수 없다. UI 계약대로 **경로가 없는데 UI 만 성공으로 바꾸지 않는다.**
///
/// TODO: R-01 에서 서버가 질문과 함께 선택지·대화 그룹을 주면 목업의 버튼 세 개를 넣는다.
library;

import 'package:flutter/material.dart';

import '../../../core/design/band.dart';
import '../../../core/design/skin.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/voice/voice_session_manager.dart';
import '../../../domain/repository/repositories.dart';
import '../../widgets/glass.dart';
import '../../widgets/mascot.dart';

class ClarifyView extends StatelessWidget {
  const ClarifyView({
    required this.question,
    required this.applied,
    required this.palette,
    required this.level,
    required this.onCancel,
    this.partial,
    this.speaking = false,
    this.onUndo,
    super.key,
  });

  /// 서버가 되묻는 한 가지.
  final String question;

  /// 질문 전에 이미 반영된 변경.
  ///
  /// 지금 서버는 질문할 때 전체를 보류하므로 보통 비어 있다. 부분 반영이 붙으면
  /// (R-01) 여기에 계란처럼 먼저 저장된 항목이 온다. **없으면 줄을 그리지 않는다.**
  final List<CommandChange> applied;

  final BandPalette palette;

  /// 마이크 입력 크기(0~1).
  final double level;

  /// 지금까지 들은 답. 아직 없으면 `null` 이다.
  final String? partial;

  /// 질문을 읽고 있는 중인지. 응답 창은 낭독이 끝난 뒤에 열린다.
  final bool speaking;

  /// 이미 반영된 변경을 되돌린다. 되돌릴 것이 없으면 `null` 이다.
  final VoidCallback? onUndo;

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        if (applied.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: _AppliedRow(
                applied: applied, skin: skin, palette: palette, onUndo: onUndo),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => Mascot(
                    mood: palette.mood,
                    size: (constraints.maxHeight * 0.34).clamp(88.0, 176.0),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Strings.voiceClarifying,
                  textAlign: TextAlign.center,
                  style: text.displaySmall?.copyWith(color: palette.accent),
                ),
                const SizedBox(height: 12),
                // 질문은 서버 문장 그대로다. 줄여 쓰거나 바꿔 쓰지 않는다.
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      question,
                      textAlign: TextAlign.center,
                      style: text.headlineSmall,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Strings.clarifyKeepUnknown,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                      color: skin.inkFaint, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        if (partial != null && partial!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _Heard(said: partial!, palette: palette, skin: skin),
          ),
        _Window(
          speaking: speaking,
          palette: palette,
          skin: skin,
          onCancel: onCancel,
        ),
      ],
    );
  }
}

/// 질문 전에 이미 반영된 항목 한 줄.
class _AppliedRow extends StatelessWidget {
  const _AppliedRow({
    required this.applied,
    required this.skin,
    required this.palette,
    required this.onUndo,
  });

  final List<CommandChange> applied;
  final Skin skin;
  final BandPalette palette;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final names = applied.map((c) => c.name).toSet().join(', ');

    return GlassPanel(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      shadow: [skin.shade(0.06, 18, 6)],
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: skin.done.accent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.check_rounded, size: 14, color: skin.done.bgMid),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                Strings.clarifyAppliedFirst(names),
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (onUndo != null)
            TextButton(
              onPressed: onUndo,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 44),
                foregroundColor: skin.inkMuted,
              ),
              child: Text(Strings.undo,
                  style: text.labelLarge?.copyWith(color: skin.inkMuted)),
            ),
        ],
      ),
    );
  }
}

/// 지금 들은 답.
class _Heard extends StatelessWidget {
  const _Heard({required this.said, required this.palette, required this.skin});

  final String said;
  final BandPalette palette;
  final Skin skin;

  @override
  Widget build(BuildContext context) => GlassPanel(
        radius: 18,
        weight: GlassWeight.thick,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shadow: [skin.shade(0.06, 18, 6)],
        child: Row(
          children: [
            Icon(Icons.graphic_eq_rounded, size: 18, color: palette.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '“$said”',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

/// 후속 응답 창과 취소.
class _Window extends StatelessWidget {
  const _Window({
    required this.speaking,
    required this.palette,
    required this.skin,
    required this.onCancel,
  });

  final bool speaking;
  final BandPalette palette;
  final Skin skin;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (speaking)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: palette.accent),
                )
              else
                _Countdown(
                    seconds: VoiceSessionManager.clarifyWindow.inSeconds,
                    palette: palette,
                    skin: skin),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  speaking
                      ? Strings.voiceSpeaking
                      : Strings.clarifyWindowHint(
                          VoiceSessionManager.clarifyWindow.inSeconds),
                  style: text.labelLarge?.copyWith(color: skin.inkMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: GlassPill(
              padding: EdgeInsets.zero,
              child: InkWell(
                onTap: onCancel,
                customBorder: const StadiumBorder(),
                child: Center(
                  child: Text(Strings.voiceCancel,
                      style: text.titleMedium?.copyWith(fontSize: 16)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 남은 응답 시간.
///
/// 이 고리는 **알림이지 마감이 아니다.** 시간 안에 말을 시작하면 인식 서비스가 발화
/// 끝까지 기다린다. 0 에 닿아도 말하는 중이면 끊기지 않는다.
class _Countdown extends StatefulWidget {
  const _Countdown({
    required this.seconds,
    required this.palette,
    required this.skin,
  });

  final int seconds;
  final BandPalette palette;
  final Skin skin;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick = AnimationController(
    vsync: this,
    duration: Duration(seconds: widget.seconds),
  );

  @override
  void initState() {
    super.initState();
    _tick.forward();
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 36,
        height: 36,
        child: AnimatedBuilder(
          animation: _tick,
          builder: (context, _) {
            final left = (widget.seconds * (1 - _tick.value)).ceil();
            return Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size.square(36),
                  painter: _RingPainter(
                    progress: 1 - _tick.value,
                    color: widget.palette.accent,
                    track: widget.palette.accentSoft,
                  ),
                ),
                Text(
                  '$left',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: widget.skin.ink),
                ),
              ],
            );
          },
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
  });

  final double progress;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 15);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(rect.center, 15, stroke..color = track);
    canvas.drawArc(
      rect,
      -1.5707963,
      6.2831853 * progress.clamp(0.0, 1.0),
      false,
      stroke..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
