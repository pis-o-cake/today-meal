/// 서버 응답을 도메인 모델로 옮긴다.
///
/// 모르는 문자열을 만나면 예외를 던지지 않고 `unknown` 으로 낮춘다. 서버가 상태값을
/// 추가했을 때 앱이 죽는 것보다 화면이 "모름"을 보여주는 편이 낫다.
///
/// **등급을 앱에서 계산하지 않는다.** 서버가 담아 보낸 값을 그대로 쓴다.
library;

import '../../domain/model/change_record.dart';
import '../../domain/model/inventory.dart';
import '../../domain/model/menu.dart';


IngredientBatch batchFromJson(Map<String, dynamic> json) => IngredientBatch(
      batchId: json['batch_id'] as int,
      ingredientId: json['ingredient_id'] as int,
      name: json['raw_name'] as String,
      quantity: json['quantity'] as String?,
      unit: json['unit'] as String?,
      qualitativeAmount: json['qualitative_amount'] as String?,
      certainty: QuantityCertainty.parse(json['quantity_certainty'] as String?),
      storage: StorageLocation.parse(json['storage_location'] as String?),
      freshness: Freshness.parse(json['freshness'] as String?),
      daysLeft: json['days_left'] as int?,
      expiryKind: DateKind.parse(json['expiry_kind'] as String?),
      quantityUncertain: json['quantity_uncertain'] as bool? ?? false,
      dates: (json['dates'] as List<dynamic>? ?? const [])
          .map((e) => _dateFromJson(e as Map<String, dynamic>))
          .whereType<BatchDate>()
          .toList(growable: false),
    );

BatchDate? _dateFromJson(Map<String, dynamic> json) {
  final kind = DateKind.parse(json['kind'] as String?);
  // 모르는 기한 종류를 소비기한으로 추측하면 안전 판정을 조작하는 것이 된다. 버린다.
  if (kind == null) return null;
  return BatchDate(
    kind: kind,
    value: json['date_value'] as String?,
    isConfirmed: json['is_confirmed'] as bool? ?? false,
    rawText: json['raw_text'] as String?,
  );
}

PriorityBatch priorityFromJson(Map<String, dynamic> json) => PriorityBatch(
      batch: batchFromJson(json['batch'] as Map<String, dynamic>),
      reason: PriorityReason.parse(json['reason'] as String?),
      isCookable: json['is_cookable'] as bool? ?? true,
      daysLeft: json['days_left'] as int?,
    );

FridgeCondition conditionFromJson(Map<String, dynamic> json) => FridgeCondition(
      condition: Condition.parse(json['condition'] as String?),
      urgentCount: json['urgent_count'] as int? ?? 0,
      soonCount: json['soon_count'] as int? ?? 0,
      expiredCount: json['expired_count'] as int? ?? 0,
      unknownQuantityCount: json['unknown_quantity_count'] as int? ?? 0,
      totalCount: json['total_count'] as int? ?? 0,
    );

MenuSuggestion suggestionFromJson(Map<String, dynamic> json) => MenuSuggestion(
      suggestionId: json['suggestion_id'] as int,
      recipeId: json['recipe_id'] as int,
      name: json['name'] as String,
      servings: json['servings'] as int,
      estimatedMinutes: json['estimated_minutes'] as int?,
      reason: json['reason'] as String?,
      availability: MenuAvailability.parse(json['availability'] as String?),
      priorityIngredients: _strings(json['priority_ingredients']),
      missingIngredients: _strings(json['missing_ingredients']),
      uncertainIngredients: _strings(json['uncertain_ingredients']),
    );

MenuDetail detailFromJson(Map<String, dynamic> json) => MenuDetail(
      recipeId: json['recipe_id'] as int,
      name: json['name'] as String,
      servings: json['servings'] as int,
      baseServings: json['base_servings'] as int,
      estimatedMinutes: json['estimated_minutes'] as int?,
      ingredients: (json['ingredients'] as List<dynamic>? ?? const [])
          .map((e) => _ingredientFromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map((e) => (e as Map<String, dynamic>)['text'] as String? ?? '')
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
    );

RecipeIngredient _ingredientFromJson(Map<String, dynamic> json) => RecipeIngredient(
      name: json['name'] as String,
      requiredAmount: json['required_amount'] as String?,
      unit: json['unit'] as String?,
      isEssential: json['is_essential'] as bool? ?? true,
      status: IngredientStatus.parse(json['status'] as String?),
    );

CookedResult cookedFromJson(Map<String, dynamic> json) => CookedResult(
      suggestionId: json['suggestion_id'] as int,
      alreadyApplied: json['already_applied'] as bool? ?? false,
      skippedIngredients: _strings(json['skipped_ingredients']),
      clarificationQuestion: json['clarification_question'] as String?,
      undoToken: json['undo_token'] as String?,
      spoken: json['spoken'] as String?,
    );

ChangeRecord recordFromJson(Map<String, dynamic> json) => ChangeRecord(
      kind: HistoryKind.parse(json['kind'] as String?),
      action: json['action'] as String,
      name: json['name'] as String,
      batchId: json['batch_id'] as int,
      quantityBefore: json['quantity_before'] as String?,
      quantityAfter: json['quantity_after'] as String?,
      unit: json['unit'] as String?,
      isEstimated: json['is_estimated'] as bool? ?? false,
      occurredAt:
          DateTime.tryParse(json['occurred_at'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      commandId: json['command_id'] as String?,
      reversesEventId: json['reverses_event_id'] as int?,
      utterance: json['utterance'] as String?,
      spokenResponse: json['spoken_response'] as String?,
    );

VideoRecipe videoFromJson(Map<String, dynamic> json) => VideoRecipe(
      videoId: json['video_id'] as String,
      url: json['url'] as String,
      title: json['title'] as String?,
      channel: json['channel'] as String?,
      dishName: json['dish_name'] as String?,
      baseServings: json['base_servings'] as int?,
      estimatedMinutes: json['estimated_minutes'] as int?,
      availability: MenuAvailability.parse(json['availability'] as String?),
      ingredients: (json['ingredients'] as List<dynamic>? ?? const [])
          .map((e) => _ingredientFromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      steps: (json['steps'] as List<dynamic>? ?? const [])
          .map((e) => _videoStepFromJson(e as Map<String, dynamic>))
          .toList(growable: false),
      missingIngredients: _strings(json['missing_ingredients']),
      uncertainIngredients: _strings(json['uncertain_ingredients']),
      unresolved: _strings(json['unresolved']),
    );

VideoStep _videoStepFromJson(Map<String, dynamic> json) => VideoStep(
      order: json['order'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      timerSeconds: json['timer_seconds'] as int?,
      timerLabel: json['timer_label'] as String?,
      ingredients: _strings(json['ingredients']),
    );

List<String> _strings(Object? raw) => (raw as List<dynamic>? ?? const [])
    .map((e) => e.toString())
    .toList(growable: false);
