/// 호출 대기 표시줄.
///
/// 음성이 살아 있는지를 화면에 계속 남긴다 — 불렀는데 듣지 않는 상태를 모르면 사용자는
/// 앱이 고장난 것으로 본다. 색만으로 구분하지 않고 점과 문구를 함께 쓴다.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../core/voice/voice_state.dart';
import '../../ui/widgets/breathing_dot.dart';
import '../../ui/widgets/glass.dart';
import '../widgets/screen_scaffold.dart';
import '../conversation/conversation_view_model.dart';

/// 호출 대기 표시와 음소거.
///
/// 음성이 살아 있는지를 화면에 계속 남긴다 — 불렀는데 듣지 않는 상태를 모르면 사용자는
/// 앱이 고장난 것으로 본다.
class VoiceStatusBar extends StatelessWidget {
  const VoiceStatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<ConversationViewModel>();
    final text = Theme.of(context).textTheme;
    final state = voice.state;
    final muted = state is Muted;

    return GlassPill(
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: voice.onMicButton,
            customBorder: const StadiumBorder(),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 12),
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Dot(state: state),
                    const SizedBox(width: 8),
                    Text(labelFor(state), style: text.labelLarge),
                    if (state is Waiting) ...[
                      const SizedBox(width: 6),
                      Text(
                        Strings.wakeWordHint,
                        style: text.labelMedium
                            ?.copyWith(color: Tokens.inkFaint, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 18, color: Tokens.hairline),
          IconButton(
            onPressed: voice.toggleMute,
            iconSize: 18,
            color: Tokens.inkFaint,
            tooltip: muted ? Strings.unmute : Strings.mute,
            icon: Icon(muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
          ),
        ],
      ),
    );
  }

}

/// 대기 점. 색만으로 구분하지 않고 옆 문구와 함께 쓴다.
class _Dot extends StatelessWidget {
  const _Dot({required this.state});

  final VoiceState state;

  @override
  Widget build(BuildContext context) => BreathingDot(
        color: colorFor(state),
        alive: isAlive(state),
      );
}

/// 지금 음성이 살아 있는지. 멈춘 상태는 멈춰 보여야 한다.
bool isAlive(VoiceState state) => switch (state) {
      Muted() || Suspended() || Unavailable() => false,
      _ => true,
    };

/// 목록 화면의 작은 호출 대기 배지.
///
/// 오늘 화면의 긴 표시줄과 달리 **살아 있다는 사실만** 알린다. 같은 상태를 읽으므로
/// 두 곳이 어긋나지 않는다.
class VoiceBadgeSlot extends StatelessWidget {
  const VoiceBadgeSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ConversationViewModel>().state;
    return VoiceBadge(
      label: labelFor(state),
      color: colorFor(state),
      alive: isAlive(state),
    );
  }
}

/// 상태 문구. 오늘 화면과 목록 화면이 같은 표를 쓴다.
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

/// 상태 색. **색만으로 구분하지 않으므로** 항상 문구와 함께 쓴다.
Color colorFor(VoiceState state) => switch (state) {
      Waiting() => const Color(0xFF3F4FD1),
      Listening() || Processing() => const Color(0xFF6F7FF0),
      Clarifying() || Speaking() => const Color(0xFFA8690A),
      Muted() || Suspended() => Tokens.inkFaint,
      Unavailable() => const Color(0xFFD8431F),
    };
