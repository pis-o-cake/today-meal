/// 조리 한 판.
///
/// 조리 진행 화면은 레시피가 **어디서 왔는지 모른다.** 추천 메뉴에서 왔을 수도, 영상에서
/// 왔을 수도 있고, 둘의 모양이 다르다 — 추천 메뉴 상세의 단계에는 시간이 없고, 영상 단계에는
/// 있을 수 있다. 화면이 두 갈래를 따로 다루면 같은 화면이 두 벌이 된다.
///
/// IMPORTANT: **없는 시간을 만들지 않는다.** 원본에 시간이 적혀 있지 않은 단계는
/// [CookStep.timerSeconds] 가 `null` 이며, 화면은 타이머 대신 "말로 맞추라" 고 안내한다.
library;

import 'package:flutter/foundation.dart';

import '../../domain/model/menu.dart';

@immutable
class CookStep {
  const CookStep({
    required this.text,
    this.timerSeconds,
    this.timerLabel,
    this.ingredients = const [],
  });

  final String text;

  /// 원본에 적힌 시간. 적혀 있지 않으면 `null`.
  final int? timerSeconds;

  final String? timerLabel;

  /// 이 단계에 쓰는 재료. 비어 있을 수 있다.
  final List<String> ingredients;

  bool get hasTimer => timerSeconds != null;
}

@immutable
class CookPlan {
  const CookPlan({
    required this.name,
    required this.servings,
    required this.steps,
    this.suggestionId,
    this.estimatedMinutes,
  });

  /// 추천 메뉴 상세에서 만든다.
  ///
  /// 상세의 단계는 글줄뿐이라 타이머가 없다. 그것이 맞다 — 서버가 시간을 주지 않았으므로
  /// 여기서 지어내지 않는다.
  factory CookPlan.fromMenu(MenuDetail detail, {int? suggestionId}) => CookPlan(
        name: detail.name,
        servings: detail.servings,
        estimatedMinutes: detail.estimatedMinutes,
        suggestionId: suggestionId,
        steps: [
          for (final text in detail.steps) CookStep(text: text),
        ],
      );

  /// 영상 레시피에서 만든다.
  ///
  /// `suggestionId` 가 없다 — 영상은 서버의 추천이 아니므로 조리를 마쳐도 자동 차감 대상이
  /// 아니다. 그 차이를 화면이 알아야 한다([canDeduct]).
  factory CookPlan.fromVideo(VideoRecipe recipe) => CookPlan(
        name: recipe.name,
        servings: recipe.baseServings ?? _defaultServings,
        estimatedMinutes: recipe.estimatedMinutes,
        steps: [
          for (final step in recipe.steps)
            CookStep(
              text: step.text,
              timerSeconds: step.timerSeconds,
              timerLabel: step.timerLabel,
              ingredients: step.ingredients,
            ),
        ],
      );

  final String name;
  final int servings;
  final int? estimatedMinutes;
  final List<CookStep> steps;

  /// 이 조리가 기댄 추천. 없으면 영상에서 온 것이다.
  final int? suggestionId;

  /// 조리를 마쳤을 때 재고를 자동으로 뺄 수 있는지.
  ///
  /// 서버는 **추천 단위**로 차감한다(`markCooked`). 영상 레시피에는 그 단위가 없으므로
  /// 말로 빼야 하며, 화면이 그 사실을 알려야 한다 — 뺐다고 표시하고 빼지 않으면 안 된다.
  bool get canDeduct => suggestionId != null;

  int get total => steps.length;

  bool get isEmpty => steps.isEmpty;

  /// 영상이 인분을 적지 않았을 때. 2인분이 이 앱의 기본이다.
  static const _defaultServings = 2;
}
