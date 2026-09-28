/// 추천된 메뉴 하나.
class MenuSuggestion {
  const MenuSuggestion({
    required this.suggestionId,
    required this.recipeId,
    required this.name,
    required this.servings,
    required this.availability,
    this.estimatedMinutes,
    this.reason,
    this.priorityIngredients = const [],
    this.missingIngredients = const [],
    this.uncertainIngredients = const [],
  });

  final int suggestionId;
  final int recipeId;
  final String name;
  final int servings;

  /// 추정치다. 조리 환경에 따라 달라지므로 확정 시간으로 표시하지 않는다.
  final int? estimatedMinutes;

  /// 이 메뉴를 고른 이유. 어떤 재료를 먼저 쓰는지 말한다.
  final String? reason;

  final MenuAvailability availability;
  final List<String> priorityIngredients;
  final List<String> missingIngredients;

  /// 양을 확인해야 하는 재료. 숫자를 지어내지 않는다.
  final List<String> uncertainIngredients;
}

/// 준비 가능 여부.
///
/// **필수 재료가 하나라도 없으면 [ready] 가 아니다.** 판정은 서버가 한다.
enum MenuAvailability {
  ready,
  needsCheck,
  needsPurchase;

  static MenuAvailability parse(String? raw) => switch (raw) {
        'ready' => MenuAvailability.ready,
        'needs_purchase' => MenuAvailability.needsPurchase,
        _ => MenuAvailability.needsCheck,
      };

  bool get isReady => this == MenuAvailability.ready;
}

/// 메뉴 상세.
class MenuDetail {
  const MenuDetail({
    required this.recipeId,
    required this.name,
    required this.servings,
    required this.baseServings,
    this.estimatedMinutes,
    this.ingredients = const [],
    this.steps = const [],
  });

  final int recipeId;
  final String name;
  final int servings;
  final int baseServings;
  final int? estimatedMinutes;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
}

/// 레시피 재료 한 줄.
class RecipeIngredient {
  const RecipeIngredient({
    required this.name,
    required this.isEssential,
    required this.status,
    this.requiredAmount,
    this.unit,
  });

  final String name;

  /// 필요량. 모르면 `null` 이며 화면은 숫자를 지어내지 않는다.
  final String? requiredAmount;

  final String? unit;

  /// 없으면 요리가 성립하지 않는 재료인지.
  final bool isEssential;

  final IngredientStatus status;
}

/// 재고 대조 결과.
enum IngredientStatus {
  have,
  needsCheck,
  missing;

  static IngredientStatus parse(String? raw) => switch (raw) {
        'have' => IngredientStatus.have,
        'missing' => IngredientStatus.missing,
        _ => IngredientStatus.needsCheck,
      };
}
