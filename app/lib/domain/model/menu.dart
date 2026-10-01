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


/// 조리 확인 결과.
///
/// 조리로 줄어든 재료 하나.
class CookedChange {
  const CookedChange({
    required this.name,
    required this.before,
    required this.after,
    this.unit,
  });

  final String name;
  final String before;
  final String after;
  final String? unit;
}

/// [alreadyApplied] 가 참이면 이번 호출이 **아무것도 바꾸지 않았다.** 버튼을 두 번 눌러도
/// 재고가 두 번 줄지 않는다.
class CookedResult {
  const CookedResult({
    required this.suggestionId,
    required this.alreadyApplied,
    this.changes = const [],
    this.skippedIngredients = const [],
    this.clarificationQuestion,
    this.undoToken,
    this.spoken,
  });

  final int suggestionId;
  final bool alreadyApplied;

  /// 실제로 뺀 재료와 그 앞뒤의 양. 같은 재료는 한 줄로 합쳐 온다.
  final List<CookedChange> changes;

  /// 차감하지 못한 재료. 분량을 모르거나 단위를 맞출 수 없는 것 — 숫자를 지어내지 않는다.
  final List<String> skippedIngredients;

  /// 되물을 한 가지. 있으면 아무것도 반영하지 않았다.
  final String? clarificationQuestion;

  /// 되돌리기 대상. 실수로 눌렀을 때 복구할 수 있다.
  final String? undoToken;

  final String? spoken;

  bool get didApply => !alreadyApplied && clarificationQuestion == null;
}

/// 영상에서 정리한 레시피.
///
/// 서버가 유튜브의 제목·설명·자막에서 옮겨 적은 것이다. **영상에 적혀 있지 않은 것은 여기
/// 없다** — 분량이 `null` 인 재료와 시간이 `null` 인 단계가 정상이며, 화면이 그 자리를
/// 숫자로 채우지 않는다.
class VideoRecipe {
  const VideoRecipe({
    required this.videoId,
    required this.url,
    required this.availability,
    this.title,
    this.channel,
    this.dishName,
    this.baseServings,
    this.estimatedMinutes,
    this.ingredients = const [],
    this.steps = const [],
    this.missingIngredients = const [],
    this.uncertainIngredients = const [],
    this.unresolved = const [],
  });

  final String videoId;
  final String url;

  /// 영상 제목. 요리 이름이 따로 잡히지 않았을 때 대신 쓴다.
  final String? title;

  final String? channel;

  /// 모델이 잡은 요리 이름. 없으면 [title] 을 쓴다.
  final String? dishName;

  final int? baseServings;

  /// 단계에 적힌 시간의 합. 적힌 시간이 없으면 `null` 이다.
  final int? estimatedMinutes;

  final MenuAvailability availability;
  final List<RecipeIngredient> ingredients;
  final List<VideoStep> steps;
  final List<String> missingIngredients;
  final List<String> uncertainIngredients;

  /// 영상만으로 알 수 없어 사용자가 확인해야 하는 것.
  final List<String> unresolved;

  /// 화면에 쓸 이름.
  String get name => dishName ?? title ?? '';

  /// 가진 재료 수. `재료 6개 중 5개` 를 만드는 값이다.
  int get haveCount =>
      ingredients.where((item) => item.status == IngredientStatus.have).length;
}

/// 영상 레시피의 단계 하나.
class VideoStep {
  const VideoStep({
    required this.order,
    required this.text,
    this.timerSeconds,
    this.timerLabel,
    this.ingredients = const [],
  });

  final int order;
  final String text;

  /// 영상에 적힌 시간. **적혀 있지 않으면 `null`** 이며 타이머를 걸지 않는다.
  final int? timerSeconds;

  final String? timerLabel;

  /// 이 단계에 쓰는 재료 이름.
  final List<String> ingredients;

  bool get hasTimer => timerSeconds != null;
}
