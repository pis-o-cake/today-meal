/// 대화 오버레이 — 호출하면 뜨는 화면.
///
/// 목업의 「듣는 중」·「확인 질문」·「반영 결과」를 한 층에 담았다. 호출어는 어느 탭에서나
/// 받으므로 탭이 아니라 덮는 층으로 둔다.
///
/// 상태마다 배색이 다르다. 듣는 중은 어둡게 덮어 **지금은 말할 차례**임을 분명히 하고,
/// 확인 질문과 반영 결과는 밝은 판으로 올라와 읽을 차례임을 알린다.
///
/// 음성 상태를 **색만으로 구분하지 않고** 문구와 함께 보여준다.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../core/voice/voice_state.dart';
import '../widgets/glass.dart';
import '../widgets/ingredient_graph.dart';
import '../widgets/mascot.dart';
import 'conversation_view_model.dart';

class ConversationOverlay extends StatelessWidget {
  const ConversationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConversationViewModel>();
    final state = vm.state;

    // 대기·배경·음소거는 덮지 않는다. 화면마다 작은 표시가 대신한다.
    if (state is Waiting || state is Suspended || state is Muted) {
      return const SizedBox.shrink();
    }

    // Scaffold 밖에 뜨므로 Material 을 직접 얹는다. 없으면 글자에 노란 밑줄이 그어진다.
    return Material(
      type: MaterialType.transparency,
      child: switch (state) {
        Listening() || Processing() => _Listening(vm: vm, state: state),
        Clarifying(:final question) => _Clarifying(vm: vm, question: question),
        Speaking(:final text) => _Answered(vm: vm, text: text),
        Unavailable(:final reason) => _Unavailable(reason: reason),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

/// 듣는 중. 화면을 어둡게 덮고 재료 그래프가 숨쉰다.
class _Listening extends StatelessWidget {
  const _Listening({required this.vm, required this.state});

  final ConversationViewModel vm;
  final VoiceState state;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final transcript = vm.lastUtterance ?? '';
    final processing = state is Processing;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 뒤 화면을 흐리게 덮는다. 완전히 가리지 않아 어디서 불렀는지 남는다.
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 0.9,
                colors: [
                  Tokens.overlay.withValues(alpha: 0.90),
                  Tokens.overlay.withValues(alpha: 0.97),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, -0.2),
          child: IngredientGraph(
            accent: Tokens.overlayGraph,
            highlighted: vm.recognizedIngredients,
          ),
        ),
        // 어디를 눌러도 닫힌다. 말을 걸어놓고 빠져나갈 길이 없으면 갇힌다.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: vm.cancel,
            child: const SizedBox.shrink(),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 64),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  processing ? Strings.voiceProcessing : Strings.voiceListening,
                  style: text.headlineMedium
                      ?.copyWith(fontSize: 27, color: Colors.white),
                ),
                const SizedBox(height: 11),
                SizedBox(
                  height: 46,
                  child: transcript.isEmpty
                      ? Text(
                          Strings.voiceTapToClose,
                          style: text.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.4)),
                        )
                      : _Transcript(
                          text: transcript,
                          highlighted: vm.recognizedIngredients,
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 인식된 말. 알아들은 재료를 강조해 **무엇으로 들었는지** 보여준다.
class _Transcript extends StatelessWidget {
  const _Transcript({required this.text, required this.highlighted});

  final String text;
  final List<String> highlighted;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontSize: 14.5,
          height: 1.6,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.66),
        );
    final accent = style?.copyWith(
      color: Tokens.overlayAccent,
      fontWeight: FontWeight.w700,
    );

    return RichText(
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: [
          const TextSpan(text: '“'),
          ..._split(text, accent, style),
          const TextSpan(text: '”'),
        ],
      ),
    );
  }

  /// 강조할 재료 이름을 기준으로 조각낸다.
  List<TextSpan> _split(String source, TextStyle? accent, TextStyle? plain) {
    if (highlighted.isEmpty) return [TextSpan(text: source)];
    final spans = <TextSpan>[];
    var rest = source;
    while (rest.isNotEmpty) {
      var cut = -1;
      var word = '';
      for (final candidate in highlighted) {
        final at = rest.indexOf(candidate);
        if (at < 0) continue;
        if (cut < 0 || at < cut) {
          cut = at;
          word = candidate;
        }
      }
      if (cut < 0) {
        spans.add(TextSpan(text: rest));
        break;
      }
      if (cut > 0) spans.add(TextSpan(text: rest.substring(0, cut)));
      spans.add(TextSpan(text: word, style: accent));
      rest = rest.substring(cut + word.length);
    }
    return spans;
  }
}

/// 확인 질문. 밝은 판으로 올라와 읽을 차례임을 알린다.
class _Clarifying extends StatelessWidget {
  const _Clarifying({required this.vm, required this.question});

  final ConversationViewModel vm;
  final String question;

  @override
  Widget build(BuildContext context) => _Sheet(
        palette: Bands.asking,
        step: 1,
        onClose: vm.cancel,
        mood: MascotMood.asking,
        headline: Strings.voiceClarifying,
        body: question,
      );
}

/// 반영 결과.
class _Answered extends StatelessWidget {
  const _Answered({required this.vm, required this.text});

  final ConversationViewModel vm;
  final String text;

  @override
  Widget build(BuildContext context) => _Sheet(
        palette: Bands.done,
        step: 2,
        onClose: vm.cancel,
        mood: MascotMood.done,
        headline: Strings.voiceDone,
        body: text,
        footer: vm.canUndo
            ? _UndoButton(onPressed: vm.undo)
            : null,
      );
}

/// 확인 질문과 반영 결과가 함께 쓰는 판.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.palette,
    required this.step,
    required this.onClose,
    required this.mood,
    required this.headline,
    required this.body,
    this.footer,
  });

  final BandPalette palette;

  /// 듣기 → 확인 → 반영 중 지금 단계.
  final int step;

  final VoidCallback onClose;
  final MascotMood mood;
  final String headline;
  final String body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: palette.background),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const SizedBox(width: 44),
                  Expanded(
                    child: Center(
                      child: StepTrail(
                        labels: const [
                          Strings.stepListen,
                          Strings.stepConfirm,
                          Strings.stepApply,
                        ],
                        current: step,
                      ),
                    ),
                  ),
                  _CloseButton(onPressed: onClose),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: LayoutBuilder(
                  builder: (context, constraints) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Mascot(
                        mood: mood,
                        size: (constraints.maxHeight * 0.34).clamp(72.0, 164.0),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        headline,
                        textAlign: TextAlign.center,
                        style: text.displaySmall?.copyWith(color: palette.accent),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Text(
                            body,
                            textAlign: TextAlign.center,
                            style: text.headlineSmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: footer!,
              ),
          ],
        ),
      ),
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: Tokens.ink,
            foregroundColor: Colors.white,
            shape: const StadiumBorder(),
          ),
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: const Text(Strings.undo),
        ),
      );
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        height: 44,
        child: IconButton(
          onPressed: onPressed,
          iconSize: 20,
          color: Tokens.inkMuted,
          style: IconButton.styleFrom(
            backgroundColor: Tokens.glass,
            shape: const CircleBorder(side: BorderSide(color: Tokens.glassEdge)),
          ),
          icon: const Icon(Icons.close_rounded),
        ),
      );
}

/// 음성을 쓸 수 없는 상태. **성공한 것처럼 감추지 않는다.**
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.reason});

  final UnavailableReason reason;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: Bands.neutral.background),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Mascot(mood: MascotMood.expired, size: 128),
                const SizedBox(height: 12),
                Text(Strings.voiceUnavailable, style: text.headlineSmall),
                const SizedBox(height: 6),
                Text(
                  '$reason',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(color: Tokens.inkFaint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
