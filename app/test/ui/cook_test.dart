import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:today_meal/core/design/skin.dart';
import 'package:today_meal/core/l10n/strings.dart';
import 'package:today_meal/ui/cook/cook_home_screen.dart';
import 'package:today_meal/domain/model/change_record.dart';
import 'package:today_meal/domain/model/menu.dart';
import 'package:today_meal/domain/repository/repositories.dart';
import 'package:today_meal/core/voice/voice_ports.dart';
import 'package:today_meal/ui/cook/cook_command.dart';
import 'package:today_meal/ui/cook/cook_session.dart';
import 'package:today_meal/ui/cook/cook_view_model.dart';
import 'package:today_meal/ui/cook/cooking_view_model.dart';

/// 조리의 계약.
///
/// 지키는 것은 넷이다.
///
/// 1. 원본에 **시간이 적혀 있지 않은 단계에 타이머를 만들지 않는다.**
/// 2. 영상 레시피는 차감 단위가 없으므로 **뺐다고 말하지 않는다.**
/// 3. 영상 정리가 실패하면 이전 결과를 남기지 않는다.
/// 4. 추천과 영상은 서로 막지 않는다.
final _threeSteps = CookPlan.fromMenu(
  const MenuDetail(
    recipeId: 10,
    name: '두부조림',
    servings: 2,
    baseServings: 2,
    steps: ['두부를 썬다', '양념을 만든다', '조린다'],
  ),
  suggestionId: 7,
);

void main() {
  group('조리 중에 하는 말', () {
    test('짧은 말을 명령으로 읽는다', () {
      expect(readCookCommand('다음'), isA<CookNext>());
      expect(readCookCommand('다음 단계'), isA<CookNext>());
      expect(readCookCommand('이전'), isA<CookPrevious>());
      expect(readCookCommand('다시 읽어 줘'), isA<CookReadAgain>());
      expect(readCookCommand('타이머 시작'), isA<CookTimerStart>());
      expect(readCookCommand('타이머 멈춰'), isA<CookTimerStop>());
    });

    test('말한 길이로 타이머를 읽는다', () {
      Duration? length(String said) => switch (readCookCommand(said)) {
            CookTimerSet(:final length) => length,
            _ => null,
          };

      expect(length('타이머 3분'), const Duration(minutes: 3));
      expect(length('타이머 삼 분'), const Duration(minutes: 3));
      expect(length('타이머 십오 분'), const Duration(minutes: 15));
      expect(length('3분 타이머 맞춰 줘'), const Duration(minutes: 3));
      expect(length('타이머 1분 30초'), const Duration(minutes: 1, seconds: 30));
      expect(length('타이머 30초'), const Duration(seconds: 30));
    });

    test('옆 사람과 하는 말에는 반응하지 않는다', () {
      // 상시 듣고 있다. 긴 말에 단계가 넘어가면 안 된다.
      expect(readCookCommand('다음에 장 볼 때 두부도 같이 사 오자'), isNull);
      expect(readCookCommand('3분 정도 조리면 돼'), isNull,
          reason: '타이머라고 말하지 않았다');
      expect(readCookCommand('타이머'), isNull, reason: '무엇을 할지 말하지 않았다');
      expect(readCookCommand(''), isNull);
    });
  });

  group('조리 계획', () {
    test('추천 상세에는 타이머가 없다', () {
      // 서버가 시간을 주지 않았다. 없는 시간을 앱이 만들면 조리 중에 엉뚱하게 울린다.
      final plan = CookPlan.fromMenu(
        const MenuDetail(
          recipeId: 10,
          name: '두부조림',
          servings: 2,
          baseServings: 2,
          steps: ['두부를 썬다', '조린다'],
        ),
        suggestionId: 7,
      );

      expect(plan.total, 2);
      expect(plan.steps.every((step) => step.timerSeconds == null), isTrue);
      expect(plan.canDeduct, isTrue, reason: '추천에서 왔으므로 서버가 뺄 수 있다');
    });

    test('영상 레시피는 적힌 시간만 가져오고 차감하지 않는다', () {
      final plan = CookPlan.fromVideo(const VideoRecipe(
        videoId: 'abc',
        url: 'https://youtu.be/abc',
        dishName: '두부조림',
        baseServings: 2,
        availability: MenuAvailability.ready,
        steps: [
          VideoStep(order: 1, text: '두부를 썬다'),
          VideoStep(order: 2, text: '3분 조린다', timerSeconds: 180),
        ],
      ));

      expect(plan.steps.map((s) => s.timerSeconds), [null, 180]);
      expect(plan.canDeduct, isFalse,
          reason: '영상에는 차감 단위가 없다. 뺐다고 말하면 거짓이다');
    });

    test('인분을 적지 않은 영상은 기본 인분으로 둔다', () {
      final plan = CookPlan.fromVideo(const VideoRecipe(
        videoId: 'abc',
        url: 'https://youtu.be/abc',
        availability: MenuAvailability.needsCheck,
        steps: [VideoStep(order: 1, text: '끓인다')],
      ));
      expect(plan.servings, 2);
    });
  });

  group('조리 진행', () {
    CookingViewModel build({int? suggestionId}) => CookingViewModel(
          command: _FakeCommand(),
          plan: CookPlan(
            name: '두부계란전',
            servings: 2,
            suggestionId: suggestionId,
            steps: const [
              CookStep(text: '썬다'),
              CookStep(text: '물기를 뺀다', timerSeconds: 180),
              CookStep(text: '부친다'),
            ],
          ),
          menu: _FakeMenu(),
        );

    test('단계가 바뀔 때마다 그 단계를 읽는다', () async {
      // 읽는 중 표시만 돌고 실제로는 읽지 않았다. 실기기에서 겪은 결함이다.
      final read = <String>[];
      final vm = CookingViewModel(
        plan: CookPlan.fromMenu(
          const MenuDetail(
            recipeId: 10,
            name: '두부조림',
            servings: 2,
            baseServings: 2,
            steps: ['두부를 썬다', '조린다'],
          ),
          suggestionId: 7,
        ),
        menu: _FakeMenu(),
        command: _FakeCommand(),
        narrate: (text) async {
          read.add(text);
          return true;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(read, ['두부를 썬다']);
      expect(vm.reading, isFalse, reason: '다 읽었으면 읽는 중이 아니다');

      vm.next();
      await Future<void>.delayed(Duration.zero);
      expect(read, ['두부를 썬다', '조린다']);

      vm.readAgain();
      await Future<void>.delayed(Duration.zero);
      expect(read.last, '조린다');
      expect(read.length, 3);
      vm.dispose();
    });

    test('읽는 동안에만 읽는 중이라고 한다', () async {
      final done = Completer<bool>();
      final vm = CookingViewModel(
        plan: CookPlan.fromMenu(
          const MenuDetail(
            recipeId: 10,
            name: '두부조림',
            servings: 2,
            baseServings: 2,
            steps: ['두부를 썬다'],
          ),
          suggestionId: 7,
        ),
        menu: _FakeMenu(),
        command: _FakeCommand(),
        narrate: (_) => done.future,
      );
      await Future<void>.delayed(Duration.zero);
      expect(vm.reading, isTrue);

      done.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(vm.reading, isFalse);
      vm.dispose();
    });

    test('호출어 없이 한 말을 따른다', () async {
      // 화면은 호출어 없이 듣는다고 적어 놓고 아무것도 듣지 않았다.
      final heard = StreamController<Heard>();
      final vm = CookingViewModel(
        plan: _threeSteps,
        menu: _FakeMenu(),
        command: _FakeCommand(),
        heard: heard.stream,
      );

      heard.add((segment: 1, transcript: '다음'));
      await Future<void>.delayed(Duration.zero);
      expect(vm.at, 1);

      heard.add((segment: 2, transcript: '이전'));
      await Future<void>.delayed(Duration.zero);
      expect(vm.at, 0);

      // 단계에 시간이 적혀 있지 않아도 말한 시간으로 건다.
      expect(vm.hasTimer, isFalse);
      heard.add((segment: 3, transcript: '타이머 3분'));
      await Future<void>.delayed(Duration.zero);
      expect(vm.hasTimer, isTrue);
      expect(vm.remaining, 180);
      expect(vm.running, isTrue);

      heard.add((segment: 4, transcript: '타이머 멈춰'));
      await Future<void>.delayed(Duration.zero);
      expect(vm.running, isFalse);

      vm.dispose();
      await heard.close();
    });

    test('한 번 말한 것은 한 번만 따른다', () async {
      // 같은 말이 중간 결과와 후보로 여러 번 온다. 두 번 따르면 두 단계가 넘어간다.
      final heard = StreamController<Heard>();
      final vm = CookingViewModel(
        plan: _threeSteps,
        menu: _FakeMenu(),
        command: _FakeCommand(),
        heard: heard.stream,
      );

      heard
        ..add((segment: 1, transcript: '다음'))
        ..add((segment: 1, transcript: '다음 단계'))
        ..add((segment: 1, transcript: '다음 단계로'));
      await Future<void>.delayed(Duration.zero);
      expect(vm.at, 1);

      // 말이 길어지며 바뀐 타이머 길이는 다시 받는다.
      heard
        ..add((segment: 2, transcript: '타이머 3분'))
        ..add((segment: 2, transcript: '타이머 3분 30초'));
      await Future<void>.delayed(Duration.zero);
      expect(vm.remaining, 210);

      vm.dispose();
      await heard.close();
    });

    test('말로 건 타이머는 다음 단계로 가져가지 않는다', () async {
      final vm = CookingViewModel(
        plan: _threeSteps,
        menu: _FakeMenu(),
        command: _FakeCommand(),
      )..setTimer(const Duration(minutes: 3));
      expect(vm.hasTimer, isTrue);

      vm.next();
      expect(vm.hasTimer, isFalse);
      vm.dispose();
    });

    test('타이머는 저절로 시작하지 않는다', () {
      // 단계를 읽기 전에 시간이 흐르면 사용자가 손을 놓친다.
      final cooking = build()..next();
      addTearDown(cooking.dispose);

      expect(cooking.hasTimer, isTrue);
      expect(cooking.remaining, 180);
      expect(cooking.running, isFalse);
    });

    test('시간이 없는 단계에서는 타이머를 만들지 않는다', () {
      final cooking = build();
      addTearDown(cooking.dispose);

      expect(cooking.hasTimer, isFalse);
      expect(cooking.remaining, isNull);
      cooking.toggleTimer();
      expect(cooking.running, isFalse, reason: '없는 타이머는 켜지지 않는다');
    });

    test('마지막 단계에서만 완료로 바뀐다', () {
      final cooking = build();
      addTearDown(cooking.dispose);

      expect(cooking.isLast, isFalse);
      cooking.goTo(2);
      expect(cooking.isLast, isTrue);
      expect(cooking.nextText, isNull);
    });

    test('영상에서 온 조리는 서버에 알리지 않는다', () async {
      final menu = _FakeMenu();
      final cooking = CookingViewModel(
        plan: CookPlan.fromVideo(const VideoRecipe(
          videoId: 'abc',
          url: 'https://youtu.be/abc',
          availability: MenuAvailability.ready,
          steps: [VideoStep(order: 1, text: '끓인다')],
        )),
        menu: menu,
        command: _FakeCommand(),
      );
      addTearDown(cooking.dispose);

      await cooking.finish();
      expect(menu.cookedCalls, isEmpty);
      expect(cooking.result, isNull);
    });

    test('완료는 화면에서 조리한 인분으로 뺀다', () async {
      // 저장된 추천 인분으로 빼면 4인분을 만든 사람에게 2인분이 빠진다.
      final menu = _FakeMenu();
      final cooking = CookingViewModel(
        plan: CookPlan(
          name: '두부조림',
          servings: 4,
          suggestionId: 7,
          steps: const [CookStep(text: '조린다')],
        ),
        menu: menu,
        command: _FakeCommand(),
      );
      addTearDown(cooking.dispose);

      await cooking.finish();
      expect(menu.cookedServings, [4]);
    });

    test('되돌리기는 그 명령을 실제로 취소한다', () async {
      // 화면만 닫으면 사용자는 되돌렸다고 믿고 틀린 재고를 본다.
      final menu = _FakeMenu();
      final command = _FakeCommand();
      final cooking = CookingViewModel(
        plan: CookPlan(
          name: '두부조림',
          servings: 2,
          suggestionId: 7,
          steps: const [CookStep(text: '조린다')],
        ),
        menu: menu,
        command: command,
      );
      addTearDown(cooking.dispose);

      await cooking.finish();
      expect(cooking.canUndo, isTrue);

      await cooking.undoCooked();
      expect(command.undone, ['cmd-1']);
      expect(cooking.undone, isTrue);
      expect(cooking.canUndo, isFalse, reason: '두 번 되돌리지 않는다');

      await cooking.undoCooked();
      expect(command.undone, hasLength(1));
    });

    test('되돌릴 대상이 없으면 되돌리기를 열지 않는다', () async {
      final menu = _FakeMenu()..undoToken = null;
      final cooking = CookingViewModel(
        plan: CookPlan(
          name: '두부조림',
          servings: 2,
          suggestionId: 7,
          steps: const [CookStep(text: '조린다')],
        ),
        menu: menu,
        command: _FakeCommand(),
      );
      addTearDown(cooking.dispose);

      await cooking.finish();
      expect(cooking.canUndo, isFalse);
    });

    test('되돌리기 실패를 성공으로 표시하지 않는다', () async {
      final command = _FakeCommand()..fails = true;
      final cooking = CookingViewModel(
        plan: CookPlan(
          name: '두부조림',
          servings: 2,
          suggestionId: 7,
          steps: const [CookStep(text: '조린다')],
        ),
        menu: _FakeMenu(),
        command: command,
      );
      addTearDown(cooking.dispose);

      await cooking.finish();
      await cooking.undoCooked();
      expect(cooking.undone, isFalse);
      expect(cooking.undoError, isNotNull);
    });

    test('추천에서 온 조리는 서버가 뺀 내용을 받는다', () async {
      final menu = _FakeMenu();
      final cooking = CookingViewModel(
        plan: CookPlan(
          name: '두부조림',
          servings: 2,
          suggestionId: 7,
          steps: const [CookStep(text: '조린다')],
        ),
        menu: menu,
        command: _FakeCommand(),
      );
      addTearDown(cooking.dispose);

      await cooking.finish();
      expect(menu.cookedCalls, [7]);
      expect(cooking.result?.didApply, isTrue);
    });
  });

  group('영상 정리', () {
    test('빈 링크는 서버를 부르지 않는다', () async {
      final video = _FakeVideo();
      final cook = CookViewModel(menu: _FakeMenu(), video: video);

      await cook.summarize('   ');
      expect(video.calls, isEmpty);
      expect(cook.videoFailure, VideoFailure.badLink);
    });

    test('실패하면 이전 결과를 남기지 않는다', () async {
      // 남겨두면 방금 넣은 링크의 결과처럼 보인다.
      final video = _FakeVideo();
      final cook = CookViewModel(menu: _FakeMenu(), video: video);

      await cook.summarize('https://youtu.be/ok');
      expect(cook.recipe, isNotNull);

      video.failure = VideoFailure.noScript;
      await cook.summarize('https://youtu.be/bad');
      expect(cook.recipe, isNull);
      expect(cook.videoFailure, VideoFailure.noScript);
    });

    testWidgets('카드 몸통은 상세를 열고 시작 알약은 조리로 간다', (tester) async {
      // 카드 전체가 시작이었을 때는 무엇을 만드는지 보지도 못한 채 조리 화면에 들어갔다.
      final cook = CookViewModel(menu: _FakeMenu(), video: _FakeVideo());
      await cook.loadPicks();
      MenuSuggestion? opened;
      CookRequest? started;

      await tester.pumpWidget(
        MaterialApp(
          home: SkinScope(
            skin: Skins.of(SkinName.glass),
            child: ChangeNotifierProvider.value(
              value: cook,
              child: CookHomeScreen(
                onStart: (request) => started = request,
                onOpenMenu: (suggestion) => opened = suggestion,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('두부조림'));
      await tester.pump();
      expect(opened?.name, '두부조림', reason: '몸통을 누르면 상세가 열린다');
      expect(started, isNull, reason: '몸통을 눌러 조리로 들어가면 안 된다');

      await tester.tap(find.text(Strings.cookStart).first);
      await tester.pump();
      expect(started?.suggestion?.name, '두부조림', reason: '알약은 조리로 간다');
    });

    test('지목한 재료를 추천 요청에 실어 보낸다', () async {
      final menu = _FakeMenu();
      final vm = CookViewModel(menu: menu, video: _FakeVideo());

      await vm.loadPicks(force: true, focus: const ['삼겹살']);

      expect(menu.asked, [
        ['삼겹살'],
      ]);
      expect(vm.focus, ['삼겹살']);
    });

    test('추천 실패가 영상 정리를 막지 않는다', () async {
      final cook = CookViewModel(menu: _BrokenMenu(), video: _FakeVideo());

      await cook.loadPicks();
      expect(cook.picks, isEmpty);
      expect(cook.picksError, isNotNull);

      await cook.summarize('https://youtu.be/ok');
      expect(cook.recipe, isNotNull);
      expect(cook.videoFailure, isNull);
    });
  });
}

class _FakeMenu implements MenuRepository {
  final cookedCalls = <int>[];

  /// 추천을 부를 때마다 실려 온 지목 재료.
  final asked = <List<String>>[];

  /// 완료 요청에 실린 인분. 화면에서 조리한 인분이 그대로 와야 한다.
  final cookedServings = <int?>[];

  /// 서버가 주는 되돌리기 대상. `null` 이면 되돌릴 것이 없다.
  String? undoToken = 'cmd-1';

  @override
  Future<List<MenuSuggestion>> createSuggestions({
    int? servings,
    int? maxMinutes,
    List<String> focus = const [],
  }) async {
    asked.add(focus);
    return const [
      MenuSuggestion(
        suggestionId: 1,
        recipeId: 10,
        name: '두부조림',
        servings: 2,
        availability: MenuAvailability.ready,
      ),
    ];
  }

  @override
  Future<MenuDetail> detail(int recipeId, {int? servings}) async =>
      const MenuDetail(recipeId: 10, name: '두부조림', servings: 2, baseServings: 2);

  @override
  Future<CookedResult> markCooked(int suggestionId, {int? servings}) async {
    cookedCalls.add(suggestionId);
    cookedServings.add(servings);
    return CookedResult(
      suggestionId: suggestionId,
      alreadyApplied: false,
      undoToken: undoToken,
    );
  }
}

class _BrokenMenu implements MenuRepository {
  @override
  Future<List<MenuSuggestion>> createSuggestions({
    int? servings,
    int? maxMinutes,
    List<String> focus = const [],
  }) async =>
      throw Exception('connection refused');

  @override
  Future<MenuDetail> detail(int recipeId, {int? servings}) async =>
      throw Exception('connection refused');

  @override
  Future<CookedResult> markCooked(int suggestionId, {int? servings}) async =>
      throw Exception('connection refused');
}

class _FakeVideo implements VideoRepository {
  final calls = <String>[];

  /// 다음 호출이 실패할 이유. `null` 이면 성공한다.
  VideoFailure? failure;

  @override
  Future<VideoRecipe> analyze(String url) async {
    calls.add(url);
    final reason = failure;
    if (reason != null) throw VideoException(reason);
    return const VideoRecipe(
      videoId: 'ok',
      url: 'https://youtu.be/ok',
      dishName: '두부조림',
      availability: MenuAvailability.ready,
      steps: [VideoStep(order: 1, text: '조린다')],
    );
  }
}


/// 되돌리기만 확인하는 명령 저장소.
class _FakeCommand implements CommandRepository {
  final undone = <String>[];

  /// 다음 되돌리기를 실패시킨다.
  bool fails = false;

  @override
  Future<CommandOutcome> undo(String commandId) async {
    if (fails) throw Exception('connection refused');
    undone.add(commandId);
    return const CommandOutcome(
      commandId: 'x',
      status: 'applied',
      intent: 'consume',
    );
  }

  @override
  Future<CommandOutcome> interpret({
    required String commandId,
    required String utterance,
    String? follows,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<ChangeRecord>> history({int limit = 50, DateTime? on}) async =>
      const [];

  @override
  Future<List<DateTime>> historyDays({int limit = 60}) async => const [];
}
