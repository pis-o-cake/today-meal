/// 반영 결과 (UI-05).
///
/// 목업 `Result.dc.html` 이다 — 캐릭터, "반영했어요", 읽어준 문장, 바뀐 재고 카드,
/// 되돌리기와 확인.
///
/// **서버가 확인한 변경만 보여준다.** 오류·거절을 반영했어요로 표시하지 않으며, 변경
/// 목록이 비어 있으면 카드를 그리지 않는다. 확인·닫기는 추가 저장이 아니라 화면을 닫는
/// 행동일 뿐이다.
library;

import 'package:flutter/material.dart';

import '../../../core/design/band.dart';
import '../../../core/design/labels.dart';
import '../../../core/design/skin.dart';
import '../../../core/design/tokens.dart';
import '../../../core/l10n/strings.dart';
import '../../../core/voice/voice_session_manager.dart';
import '../../../domain/repository/repositories.dart';
import '../../widgets/glass.dart';
import '../../widgets/mascot.dart';

class ResultView extends StatelessWidget {
  const ResultView({
    required this.spoken,
    required this.changes,
    required this.palette,
    required this.onConfirm,
    this.onUndo,
    super.key,
  });

  /// 읽어준 문장.
  final String spoken;

  /// 서버가 확인한 변경.
  final List<CommandChange> changes;

  final BandPalette palette;

  /// 되돌릴 수 있으면 콜백이 있다. 조회에는 되돌릴 것이 없다.
  final VoidCallback? onUndo;

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => Mascot(
                    mood: palette.mood,
                    size: (constraints.maxHeight * 0.38).clamp(88.0, 176.0),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Strings.voiceDone,
                  style: Tokens.hero(46, height: 1.15).copyWith(color: palette.accent),
                ),
                if (spoken.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _Spoken(text: spoken, skin: skin, palette: palette),
                ],
              ],
            ),
          ),
        ),
        // 변경이 없으면 카드를 그리지 않는다. 빈 카드는 무엇이 바뀐 것으로 읽힌다.
        if (changes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: _Changes(changes: changes, skin: skin),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: [
              if (onUndo != null) ...[
                Expanded(
                  child: _Button(
                    label: Strings.undo,
                    icon: Icons.undo_rounded,
                    onPressed: onUndo!,
                    skin: skin,
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: _Button(
                  label: Strings.resultConfirm,
                  onPressed: onConfirm,
                  skin: skin,
                  strong: true,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Text(
            Strings.resultReturnHint(
                VoiceSessionManager.resultMinimum.inSeconds),
            style: text.labelMedium
                ?.copyWith(color: skin.inkDim, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// 읽어준 문장. 스피커 아이콘을 붙여 **앱이 한 말**임을 밝힌다.
class _Spoken extends StatelessWidget {
  const _Spoken({required this.text, required this.skin, required this.palette});

  final String text;
  final Skin skin;
  final BandPalette palette;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 96),
        child: SingleChildScrollView(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.volume_up_rounded,
                    size: 20, color: palette.accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '“$text”',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: skin.inkMuted, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
}

/// 바뀐 재고 카드. 재료마다 한 줄이다.
class _Changes extends StatelessWidget {
  const _Changes({required this.changes, required this.skin});

  final List<CommandChange> changes;
  final Skin skin;

  /// 한 화면에 보여줄 줄 수. 넘치면 스크롤한다.
  static const _maxHeight = 220.0;

  @override
  Widget build(BuildContext context) => Semantics(
        label: Strings.resultChanged,
        child: GlassPanel(
          weight: GlassWeight.thick,
          padding: EdgeInsets.zero,
          shadow: [skin.shade(0.08, 28, 10)],
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxHeight),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final (index, change) in changes.indexed) ...[
                    if (index > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Divider(height: 1, color: skin.hairline),
                      ),
                    _Row(change: change, skin: skin),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.change, required this.skin});

  final CommandChange change;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final unit = Labels.unit(change.unit);
    final after = change.after;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(change.name, style: text.titleLarge),
                const SizedBox(height: 6),
                Text(
                  Labels.changeAction(change.action),
                  style: text.labelMedium?.copyWith(color: skin.inkFaint),
                ),
              ],
            ),
          ),
          if (after != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _label(change),
                  style: text.labelSmall
                      ?.copyWith(color: skin.inkFaint, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${Labels.number(after)}$unit',
                  style: text.headlineMedium
                      ?.copyWith(fontSize: 28, letterSpacing: -1.12),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 숫자 위의 한 마디. 이전 값이 없으면 새로 들어온 것이다.
  String _label(CommandChange change) =>
      change.before == null ? Strings.resultNew : Strings.historyAdjust;
}

class _Button extends StatelessWidget {
  const _Button({
    required this.label,
    required this.onPressed,
    required this.skin,
    this.icon,
    this.strong = false,
  });

  final String label;
  final VoidCallback onPressed;
  final Skin skin;
  final IconData? icon;

  /// 가장 강한 채움을 쓸지. 확인 버튼에만 쓴다.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 20, color: strong ? skin.onStrong : skin.ink),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: text.titleMedium?.copyWith(
              fontSize: 16, color: strong ? skin.onStrong : skin.ink),
        ),
      ],
    );

    if (!strong) {
      return SizedBox(
        height: 56,
        child: GlassPill(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: onPressed,
            customBorder: const StadiumBorder(),
            child: child,
          ),
        ),
      );
    }

    return SizedBox(
      height: 56,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: skin.strong,
          shape: const StadiumBorder(),
          shadows: [skin.shade(0.22, 22, 10)],
        ),
        child: InkWell(
          onTap: onPressed,
          customBorder: const StadiumBorder(),
          child: child,
        ),
      ),
    );
  }
}
