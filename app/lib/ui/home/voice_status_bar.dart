/// 호출 상태 칩.
///
/// 목업 `Main.dc.html` 머리말의 알약이다 — 점 · 상태 문구 · 호출어 · 음소거 버튼.
///
/// 음성이 살아 있는지를 화면에 계속 남긴다. 불렀는데 듣지 않는 상태를 모르면 사용자는
/// 앱이 고장난 것으로 본다. 색만으로 구분하지 않고 점과 문구를 함께 쓴다.
///
/// 이 칩이 **마이크로 들어가는 유일한 화면 경로**다. UI 계약대로 따로 떠 있는 마이크
/// 버튼을 두지 않는다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../core/voice/voice_state.dart';
import '../../domain/model/inventory.dart';
import '../conversation/conversation_view_model.dart';
import '../widgets/breathing_dot.dart';
import '../widgets/glass.dart';

class VoiceStatusBar extends StatelessWidget {
  const VoiceStatusBar({required this.palette, super.key});

  /// 지금 화면의 등급 배색. 대기 중 점이 이 색을 쓴다.
  final BandPalette palette;

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<ConversationViewModel>();
    final skin = context.skin;
    final text = Theme.of(context).textTheme;
    final state = voice.state;
    final muted = state is Muted;

    return GlassPill(
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: labelFor(state),
            child: InkWell(
              onTap: voice.onMicButton,
              customBorder: const StadiumBorder(),
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 12),
                child: SizedBox(
                  height: Tokens.tap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BreathingDot(
                        color: dotColor(state, palette, skin),
                        alive: isAlive(state),
                      ),
                      const SizedBox(width: 8),
                      Text(labelFor(state), style: text.labelLarge),
                      // 호출어는 대기 중에만 알린다. 듣는 중에 또 부르라는 말이 된다.
                      if (state is Waiting) ...[
                        const SizedBox(width: 6),
                        Text(
                          Strings.wakeWordHint,
                          style: text.labelMedium?.copyWith(
                              color: skin.inkFaint, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(width: 1, height: 18, color: skin.divider),
          IconButton(
            onPressed: voice.toggleMute,
            iconSize: 18,
            color: skin.inkFaint,
            tooltip: muted ? Strings.unmute : Strings.mute,
            icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          ),
        ],
      ),
    );
  }
}

/// 지금 음성이 살아 있는지. 멈춘 상태는 멈춰 보여야 한다.
bool isAlive(VoiceState state) => switch (state) {
      Muted() || Suspended() || Unavailable() => false,
      _ => true,
    };

/// 상태 문구. 화면마다 같은 표를 쓴다.
String labelFor(VoiceState state) => switch (state) {
      Waiting() => Strings.voiceWaiting,
      Listening() => Strings.voiceListening,
      Processing() => Strings.voiceProcessing,
      Clarifying() => Strings.voiceClarifying,
      Speaking() => Strings.voiceSpeaking,
      Muted() => Strings.voiceMuted,
      Suspended() => Strings.voiceSuspended,
      Unavailable() => Strings.voiceUnavailable,
    };

/// 상태 점의 색.
///
/// **색만으로 구분하지 않으므로** 항상 [labelFor] 와 함께 쓴다. 대기 중에는 목업대로
/// 지금 화면의 등급 색을 쓰고, 나머지 상태는 그 상태의 색을 쓴다.
Color dotColor(VoiceState state, BandPalette palette, Skin skin) =>
    switch (state) {
      Waiting() => palette.accentBright,
      Listening() || Processing() => skin.listening.accentBright,
      Clarifying() || Speaking() => skin.asking.accentBright,
      Muted() || Suspended() => skin.inkDim,
      Unavailable() => skin.band(Freshness.urgent).accent,
    };
