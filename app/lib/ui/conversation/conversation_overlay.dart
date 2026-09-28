import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../core/voice/voice_state.dart';
import 'conversation_view_model.dart';

/// 대화 오버레이.
///
/// 호출어는 어느 탭에서나 받으므로 탭이 아니라 덮는 층으로 둔다. 대기와 배경 상태에서는
/// 아무것도 그리지 않아 화면을 막지 않는다.
///
/// 음성 상태를 **색만으로 구분하지 않고** 문구와 함께 보여준다.
class ConversationOverlay extends StatelessWidget {
  const ConversationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConversationViewModel>();
    final state = vm.state;

    // 대기·배경·음소거는 오버레이를 띄우지 않는다. 홈 화면이 상태를 작게 표시한다.
    if (state is Waiting || state is Suspended || state is Muted) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Tokens.gutterCompact),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StateLine(state: state),
              const SizedBox(height: Tokens.gapCard),
              if (vm.lastUtterance != null) _Utterance(text: vm.lastUtterance!),
              const SizedBox(height: Tokens.gapCard),
              _Result(vm: vm),
              const SizedBox(height: Tokens.gapCard),
              _Actions(vm: vm),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateLine extends StatelessWidget {
  const _StateLine({required this.state});

  final VoiceState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (state) {
      Listening() => (Strings.voiceListening, Bands.fresh.accent),
      Processing() => (Strings.voiceProcessing, Bands.soon.accent),
      Clarifying() => (Strings.voiceClarifying, Bands.soon.accent),
      Speaking() => (Strings.voiceSpeaking, Bands.fresh.accent),
      Unavailable() => (Strings.voiceUnavailable, Bands.urgent.accent),
      _ => (Strings.voiceWaiting, Tokens.inkFaint),
    };
    return Row(
      children: [
        Icon(Icons.mic, color: color, size: 20),
        const SizedBox(width: Tokens.gapTight),
        Text(
          label,
          style: theme.textTheme.titleLarge?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _Utterance extends StatelessWidget {
  const _Utterance({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      '"$text"',
      style: Theme.of(context).textTheme.headlineMedium,
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.vm});

  final ConversationViewModel vm;

  @override
  Widget build(BuildContext context) {
    final state = vm.state;
    if (state is Clarifying) {
      // 되묻는 중이면 **아직 반영되지 않았다.** 결과 칩을 보여주지 않는다.
      return Text(
        state.question,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Bands.soon.accent),
      );
    }
    final changes = vm.lastOutcome?.changes ?? const [];
    if (changes.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: Tokens.gapTight,
      runSpacing: Tokens.gapTight,
      children: [
        for (final change in changes)
          Chip(label: Text('${change.name} ${change.afterLabel}')),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.vm});

  final ConversationViewModel vm;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (vm.canUndo)
          TextButton(
            onPressed: vm.undo,
            child: const Text(Strings.cancelJustNow),
          ),
        const SizedBox(width: Tokens.gapTight),
        TextButton(
          onPressed: vm.toggleMute,
          child: Text(vm.state is Muted ? Strings.unmute : Strings.mute),
        ),
      ],
    );
  }
}
