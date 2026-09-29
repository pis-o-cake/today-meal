import 'package:flutter_test/flutter_test.dart';
import 'package:today_meal/domain/model/menu.dart';
import 'package:today_meal/domain/repository/repositories.dart';
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
void main() {
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
      );
      addTearDown(cooking.dispose);

      await cooking.finish();
      expect(menu.cookedCalls, isEmpty);
      expect(cooking.result, isNull);
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

  @override
  Future<List<MenuSuggestion>> createSuggestions({
    int? servings,
    int? maxMinutes,
  }) async =>
      const [
        MenuSuggestion(
          suggestionId: 1,
          recipeId: 10,
          name: '두부조림',
          servings: 2,
          availability: MenuAvailability.ready,
        ),
      ];

  @override
  Future<MenuDetail> detail(int recipeId, {int? servings}) async =>
      const MenuDetail(recipeId: 10, name: '두부조림', servings: 2, baseServings: 2);

  @override
  Future<CookedResult> markCooked(int suggestionId) async {
    cookedCalls.add(suggestionId);
    return CookedResult(suggestionId: suggestionId, alreadyApplied: false);
  }
}

class _BrokenMenu implements MenuRepository {
  @override
  Future<List<MenuSuggestion>> createSuggestions({
    int? servings,
    int? maxMinutes,
  }) async =>
      throw Exception('connection refused');

  @override
  Future<MenuDetail> detail(int recipeId, {int? servings}) async =>
      throw Exception('connection refused');

  @override
  Future<CookedResult> markCooked(int suggestionId) async =>
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
