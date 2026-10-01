/// 대화 오버레이 — 불렀을 때 뜨는 화면.
///
/// 목업 `Listening`·`Clarify`·`Result` 세 화면이다. **머리말의 단계 막대와 닫기 버튼은
/// 공통**이고 본문만 단계마다 다르다. 셋의 골격이 같아야 어디까지 진행됐는지 읽힌다.
///
/// **글래스 테마는 한 화면에서 끝낸다.** 단계 막대가 없고, 반영 결과도 듣던 화면에서
/// 알린다. 사용자는 말하기만 하므로 화면이 바뀌며 단계를 세어줄 이유가 없다. 다른 테마는
/// 목업의 세 화면을 그대로 쓴다.
///
/// 호출어는 어느 탭에서나 받으므로 탭이 아니라 화면 전체를 덮는 층으로 둔다.
///
/// ```
/// 듣기(Listening) → 확인(Processing·Clarifying) → 반영(Speaking) → 대기
///                                   ↓
///                    후속 응답 창(Listening.followUpTo)
/// ```
///
/// **반영 화면은 재고가 바뀌었을 때만 뜬다.** 조회의 답이나 거절·실패 안내([Answering])는
/// 듣기 화면에 머문 채 읽어주고 닫는다. 말이 없었으면 아무것도 읽지 않고 닫는다.
///
/// ```
/// 듣기(Listening) → 확인(Processing) → 답(Answering) → 대기
/// ```
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/band.dart';
import '../../core/design/motion.dart';
import '../../core/design/skin.dart';
import '../../core/design/tokens.dart';
import '../../core/l10n/strings.dart';
import '../../core/voice/voice_state.dart';
import '../widgets/step_bar.dart';
import 'conversation_view_model.dart';
import 'views/clarify_view.dart';
import 'views/listening_view.dart';
import 'views/result_view.dart';

class ConversationOverlay extends StatelessWidget {
  const ConversationOverlay({super.key});

  /// 단계 이름. 세 화면이 같은 표를 쓴다.
  static const steps = [
    VoiceStep(name: Strings.stepListen, currentName: Strings.stepListenNow),
    VoiceStep(name: Strings.stepConfirm, currentName: Strings.stepConfirmNow),
    VoiceStep(name: Strings.stepApply, currentName: Strings.stepApplyNow),
  ];

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
      child: _Frame(vm: vm, state: state),
    );
  }
}

/// 배경 · 단계 막대 · 닫기 버튼.
class _Frame extends StatelessWidget {
  const _Frame({required this.vm, required this.state});

  final ConversationViewModel vm;
  final VoiceState state;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final single = skin.frosted;
    final stage = _Stage.of(state, skin, single: single);

    return AnimatedContainer(
      duration: context.reduceMotion ? Duration.zero : Motion.skinFade,
      decoration: BoxDecoration(
        gradient: skin.background(stage.palette, focusY: -0.48),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: single
                        ? const SizedBox.shrink()
                        : StepBar(
                            steps: ConversationOverlay.steps,
                            current: stage.step,
                            accent: stage.palette.accent,
                            accentBright: stage.palette.accentBright,
                            doneAtLast: stage.finished,
                          ),
                  ),
                  const SizedBox(width: 14),
                  CloseCircle(onPressed: vm.cancel, label: Strings.close),
                ],
              ),
            ),
            Expanded(child: _body(stage, single: single)),
          ],
        ),
      ),
    );
  }

  Widget _body(_Stage stage, {required bool single}) => switch (state) {
        // 후속 응답 창은 확인 화면을 유지한다. 질문이 사라지면 무엇에 답하는지 모른다.
        Listening(:final followUpTo?, :final partialText) => ClarifyView(
            question: followUpTo,
            partial: partialText,
            applied: vm.appliedChanges,
            palette: stage.palette,
            level: vm.level,
            onUndo: vm.canUndo ? vm.undo : null,
            onCancel: vm.cancel,
          ),
        Listening(:final partialText) => ListeningView(
            partial: partialText,
            palette: stage.palette,
            level: vm.level,
            onCancel: vm.cancel,
          ),
        Processing(:final utterance) => ListeningView(
            partial: utterance,
            palette: stage.palette,
            level: 0,
            processing: true,
            onCancel: vm.cancel,
          ),
        Clarifying(:final question) => ClarifyView(
            question: question,
            applied: vm.appliedChanges,
            palette: stage.palette,
            level: 0,
            speaking: true,
            onUndo: vm.canUndo ? vm.undo : null,
            onCancel: vm.cancel,
          ),
        Answering(:final text) => ListeningView(
            partial: vm.lastUtterance,
            palette: stage.palette,
            level: 0,
            processing: true,
            answer: text,
            onCancel: vm.cancel,
          ),
        Speaking(:final text) when single => ListeningView(
            partial: vm.lastUtterance,
            palette: stage.palette,
            level: 0,
            processing: true,
            answer: text,
            applied: AppliedResult(
              changes: vm.appliedChanges,
              onUndo: vm.canUndo ? vm.undo : null,
              onConfirm: vm.cancel,
            ),
            onCancel: vm.cancel,
          ),
        Speaking(:final text) => ResultView(
            spoken: text,
            changes: vm.appliedChanges,
            palette: stage.palette,
            onUndo: vm.canUndo ? vm.undo : null,
            onConfirm: vm.cancel,
          ),
        Unavailable(:final reason) => _Unavailable(reason: reason, vm: vm),
        _ => const SizedBox.shrink(),
      };
}

/// 한 상태가 어느 단계에 있고 어떤 배색을 쓰는지.
class _Stage {
  const _Stage({
    required this.step,
    required this.palette,
    this.finished = false,
  });

  /// 듣기(0) · 확인(1) · 반영(2).
  final int step;

  final BandPalette palette;

  /// 마지막 단계가 끝난 상태인지. 막대의 빛을 멈춘다.
  final bool finished;

  static _Stage of(VoiceState state, Skin skin, {required bool single}) =>
      switch (state) {
        // 후속 응답은 확인 단계다. 듣고 있어도 듣기 단계로 되돌리지 않는다.
        Listening(followUpTo: final String _) =>
          _Stage(step: 1, palette: skin.asking),
        Listening() => _Stage(step: 0, palette: skin.listening),
        Processing() => _Stage(step: 1, palette: skin.listening),
        Clarifying() => _Stage(step: 1, palette: skin.asking),
        // 반영한 것이 없으므로 마지막 단계로 넘기지 않는다.
        Answering() => _Stage(step: 1, palette: skin.listening),
        // 한 화면에서는 배색을 바꾸지 않는다. 같은 자리에서 끝난 것으로 읽혀야 한다.
        Speaking() when single =>
          _Stage(step: 2, palette: skin.listening, finished: true),
        Speaking() => _Stage(step: 2, palette: skin.done, finished: true),
        Unavailable() => _Stage(step: 0, palette: skin.neutral),
        _ => _Stage(step: 0, palette: skin.neutral),
      };
}

/// 마이크를 쓸 수 없다. **원인을 사용자 문구로** 알리고 빠져나갈 길을 준다.
class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.reason, required this.vm});

  final UnavailableReason reason;
  final ConversationViewModel vm;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            Strings.voiceUnavailable,
            textAlign: TextAlign.center,
            style: Tokens.hero(34, height: 1.15).copyWith(color: skin.inkMuted),
          ),
          const SizedBox(height: 12),
          Text(
            _why(reason),
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: skin.inkFaint),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: vm.cancel,
            style: FilledButton.styleFrom(
              backgroundColor: skin.strong,
              foregroundColor: skin.onStrong,
              shape: const StadiumBorder(),
              minimumSize: const Size(160, 52),
            ),
            child: const Text(Strings.close),
          ),
        ],
      ),
    );
  }

  /// 내부 enum 을 그대로 보여주지 않는다. 사용자가 할 수 있는 일로 번역한다.
  String _why(UnavailableReason reason) => switch (reason) {
        UnavailableReason.missingPermission => Strings.permissionDeniedHint,
        UnavailableReason.wakeWordInitFailed => Strings.voiceRetry,
        UnavailableReason.recognizerUnavailable =>
          Strings.permissionSpeechAndroidWhy,
        UnavailableReason.ttsUnavailable => Strings.voiceRetry,
        UnavailableReason.audioInterrupted => Strings.voiceRetry,
      };
}
