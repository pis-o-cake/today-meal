import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:today_meal/core/design/skin.dart';
import 'package:today_meal/core/design/tokens.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/core/voice/voice_ports.dart';
import 'package:today_meal/core/voice/voice_session_manager.dart';
import 'package:today_meal/core/voice/voice_state.dart';
import 'package:today_meal/domain/model/change_record.dart';
import 'package:today_meal/domain/model/inventory.dart';
import 'package:today_meal/domain/repository/repositories.dart';
import 'package:today_meal/ui/conversation/conversation_overlay.dart';
import 'package:today_meal/ui/conversation/conversation_view_model.dart';
import 'package:today_meal/ui/conversation/views/listening_view.dart';
import 'package:today_meal/ui/conversation/views/result_view.dart';
import 'package:today_meal/ui/widgets/seconds_left.dart';
import 'package:today_meal/ui/widgets/step_bar.dart';

/// 서버 결과가 어느 화면으로 가는지.
///
/// 반영 결과는 **재고가 바뀌었을 때만** 뜬다. 조회·거절·통신 실패를 반영 결과로 그리면
/// 사용자는 바뀌지 않은 재고를 바뀐 것으로 안다.
void main() {
  (VoiceSessionManager, ConversationViewModel) wire(CommandRepository command) {
    final voice = VoiceSessionManager(
      detector: _Detector(),
      transcriber: _Transcriber(),
      speaker: _Speaker(),
      retryMessage: '반영하지 못했어요',
    );
    final vm = ConversationViewModel(
      voice: voice,
      command: command,
      retryMessage: '반영하지 못했어요',
    );
    return (voice, vm);
  }

  Future<List<String>> statesFor(CommandRepository command) async {
    final (voice, vm) = wire(command);
    await voice.onForeground();

    final seen = <VoiceState>[];
    final sub = voice.states.listen(seen.add);
    await vm.onMicButton();
    await sub.cancel();
    return seen.map((s) => s.runtimeType.toString()).toList();
  }

  test('재고가 바뀌면 반영 결과를 보여준다', () async {
    final order = await statesFor(_Command(
      status: 'applied',
      spoken: '계란 두 개를 뺐어요.',
      changes: const [CommandChange(name: '계란', action: 'consume', after: '4')],
    ));

    expect(order, contains('Speaking'));
    expect(order, isNot(contains('Answering')));
  });

  test('조회는 답만 읽고 반영 결과를 보여주지 않는다', () async {
    final order = await statesFor(_Command(
      status: 'applied',
      spoken: '계란은 여섯 개 있어요.',
    ));

    expect(order, contains('Answering'));
    expect(order, isNot(contains('Speaking')));
  });

  test('거절은 반영 결과를 보여주지 않는다', () async {
    final order = await statesFor(_Command(
      status: 'rejected',
      spoken: '그건 할 수 없어요.',
      // 거절인데 변경이 실려 와도 반영으로 보지 않는다.
      changes: const [CommandChange(name: '계란', action: 'consume', after: '4')],
    ));

    expect(order, contains('Answering'));
    expect(order, isNot(contains('Speaking')));
  });

  test('통신 실패는 반영 결과를 보여주지 않는다', () async {
    final order = await statesFor(_Command(status: 'applied', fails: true));

    expect(order, contains('Answering'));
    expect(order, isNot(contains('Speaking')));
  });

  test('메뉴를 물으면 대화가 끝난 뒤에 추천을 열라고 알린다', () async {
    // 답만 읽고 닫히면 물은 것의 답을 볼 곳이 없다.
    final (voice, vm) = wire(_Command(
      status: 'applied',
      intent: 'recommend',
      spoken: '삼겹살로 만들 메뉴를 찾아볼게요.',
      focus: const ['삼겹살'],
    ));
    await voice.onForeground();

    final order = <String>[];
    final named = <List<String>>[];
    final states = voice.states.listen((s) => order.add(s.runtimeType.toString()));
    final asked = vm.menuRequests.listen((focus) {
      order.add('menu');
      named.add(focus);
    });
    await vm.onMicButton();
    await Future<void>.delayed(Duration.zero);
    await states.cancel();
    await asked.cancel();

    expect(order, contains('menu'));
    expect(order.indexOf('menu'), greaterThan(order.indexOf('Answering')),
        reason: '답을 읽는 동안에는 화면을 바꾸지 않는다');
    // 지목한 재료를 넘기지 않으면 물은 것과 다른 답이 온다. 실기기에서 겪었다.
    expect(named, [
      ['삼겹살'],
    ]);
  });

  test('재고를 바꾼 말에는 추천을 열지 않는다', () async {
    final (voice, vm) = wire(_Command(status: 'applied', spoken: '계란은 여섯 개 있어요.'));
    await voice.onForeground();

    var asked = 0;
    final sub = vm.menuRequests.listen((_) => asked += 1);
    await vm.onMicButton();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(asked, 0);
  });

  /// 재고를 바꾼 명령을 말하고 결과가 떠 있는 데까지 흘린다.
  Future<ConversationViewModel> applied(
    WidgetTester tester,
    Skin skin, {
    List<CommandChange> changes = const [
      CommandChange(
          name: '계란', action: 'consume', before: '6', after: '4', unit: 'ea'),
    ],
  }) async {
    final (voice, vm) = wire(_Command(
      status: 'applied',
      spoken: '계란 두 개를 뺐어요.',
      undoToken: 'undo-1',
      changes: changes,
    ));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(skin),
        home: SkinScope(
          skin: skin,
          child: ChangeNotifierProvider.value(
            value: vm,
            child: const ConversationOverlay(),
          ),
        ),
      ),
    );
    await voice.onForeground();
    unawaited(vm.onMicButton());
    // WARNING: `pumpAndSettle` 을 쓰지 않는다. 캐릭터가 끝없이 숨쉰다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(vm.state, isA<Speaking>());
    return vm;
  }

  testWidgets('글래스는 듣던 화면에서 반영 결과를 알린다', (tester) async {
    final vm = await applied(tester, Skins.glass);

    expect(find.byType(StepBar), findsNothing);
    expect(find.byType(ResultView), findsNothing);
    expect(find.byType(ListeningView), findsOneWidget);
    expect(find.text(Strings.voiceDone), findsOneWidget);
    expect(find.text('계란 두 개를 뺐어요.'), findsOneWidget);
    expect(find.text('계란'), findsOneWidget);
    expect(find.text(Strings.undo), findsOneWidget);
    expect(find.text(Strings.resultConfirm), findsOneWidget);

    await tester.pump(
        VoiceSessionManager.resultMinimum + const Duration(seconds: 1));
    expect(vm.state, isA<Waiting>());
    expect(find.byType(ListeningView), findsNothing);
  });

  testWidgets('남은 초를 1초마다 줄이고 1에서 멈춘다', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SecondsLeft(
          from: 3,
          builder: (context, seconds) => Text(Strings.resultReturnHint(seconds)),
        ),
      ),
    );
    expect(find.text(Strings.resultReturnHint(3)), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(Strings.resultReturnHint(2)), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(Strings.resultReturnHint(1)), findsOneWidget);

    // 낭독이 길어져 화면이 더 머물러도 0초라고 하지 않는다.
    await tester.pump(const Duration(seconds: 3));
    expect(find.text(Strings.resultReturnHint(1)), findsOneWidget);
  });

  testWidgets('글래스의 반영 안내는 남은 초를 센다', (tester) async {
    await applied(tester, Skins.glass);
    final total = VoiceSessionManager.resultMinimum.inSeconds;
    expect(find.text(Strings.resultReturnHint(total)), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text(Strings.resultReturnHint(total - 1)), findsOneWidget);

    await tester.pump(VoiceSessionManager.resultMinimum);
  });

  testWidgets('넣은 재료는 기한을, 말하지 않았으면 미입력을 적는다', (tester) async {
    await applied(tester, Skins.glass, changes: [
      CommandChange(
        name: '계란',
        action: 'stock_in',
        before: '0',
        after: '10',
        unit: 'ea',
        dateKind: DateKind.sellBy,
        dateValue: DateTime(2026, 10, 15),
      ),
      const CommandChange(
          name: '대파', action: 'stock_in', before: '0', after: '1', unit: 'bunch'),
    ]);

    expect(find.textContaining('유통기한 2026.10.15'), findsOneWidget);
    expect(find.textContaining(Strings.expiryNotGiven), findsOneWidget);

    await tester.pump(
        VoiceSessionManager.resultMinimum + const Duration(seconds: 1));
  });

  testWidgets('쓴 재료에는 기한을 적지 않는다', (tester) async {
    await applied(tester, Skins.glass);

    expect(find.textContaining(Strings.expiryNotGiven), findsNothing);

    await tester.pump(
        VoiceSessionManager.resultMinimum + const Duration(seconds: 1));
  });

  testWidgets('다른 테마는 단계 막대와 반영 결과 화면을 쓴다', (tester) async {
    await applied(tester, Skins.pastel);

    expect(find.byType(StepBar), findsOneWidget);
    expect(find.byType(ResultView), findsOneWidget);
    expect(find.byType(ListeningView), findsNothing);

    await tester.pump(
        VoiceSessionManager.resultMinimum + const Duration(seconds: 1));
  });
}

class _Command implements CommandRepository {
  _Command({
    required this.status,
    this.spoken,
    this.changes = const [],
    this.undoToken,
    this.intent = 'test',
    this.focus = const [],
    this.fails = false,
  });

  final String status;
  final String intent;
  final List<String> focus;
  final String? spoken;
  final String? undoToken;
  final List<CommandChange> changes;
  final bool fails;

  @override
  Future<CommandOutcome> interpret({
    required String commandId,
    required String utterance,
    String? follows,
  }) async {
    if (fails) throw StateError('connection refused');
    return CommandOutcome(
      commandId: commandId,
      status: status,
      intent: intent,
      spoken: spoken,
      undoToken: undoToken,
      changes: changes,
      focus: focus,
    );
  }

  /// 이 시험은 되돌리기와 이력을 쓰지 않는다. 불리면 시험이 잘못된 것이다.
  @override
  Future<CommandOutcome> undo(String commandId) async =>
      throw UnimplementedError();

  @override
  Future<List<ChangeRecord>> history({int limit = 50, DateTime? on}) async =>
      throw UnimplementedError();

  @override
  Future<List<DateTime>> historyDays({int limit = 60}) async =>
      throw UnimplementedError();
}

class _Detector implements WakeWordDetector {
  final _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get detections => _controller.stream;

  @override
  Stream<Heard> get heard => const Stream.empty();

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() => _controller.close();
}

class _Transcriber implements SpeechTranscriber {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String> transcribeOnce({
    String localeId = 'ko_KR',
    Duration? patience,
    void Function(String partial)? onPartial,
    void Function(double level)? onLevel,
  }) async =>
      '계란 두 개 썼어';

  @override
  Future<void> cancel() async {}
}

class _Speaker implements SpeechSpeaker {
  @override
  Future<bool> isKoreanAvailable() async => true;

  @override
  Future<bool> speak(String text) async => true;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
