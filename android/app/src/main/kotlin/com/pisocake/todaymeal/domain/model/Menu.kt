package com.pisocake.todaymeal.domain.model

/**
 * 추천된 메뉴 하나.
 *
 * @property estimatedMinutes 추정치다. 조리 환경에 따라 달라지므로 확정 시간으로 표시하지 않는다.
 * @property availability 지금 만들 수 있는지. 필수 재료가 없으면 [MenuAvailability.NEEDS_PURCHASE] 다.
 */
data class MenuSuggestion(
    val suggestionId: Long,
    val recipeId: Long,
    val name: String,
    val servings: Int,
    val estimatedMinutes: Int? = null,
    val reason: String? = null,
    val priorityIngredients: List<String> = emptyList(),
    val missingIngredients: List<String> = emptyList(),
    val uncertainIngredients: List<String> = emptyList(),
    val availability: MenuAvailability,
)

/** 준비 가능 여부. 필수 재료가 없는 메뉴를 '지금 가능'으로 표시하지 않는다. */
enum class MenuAvailability { READY, NEEDS_CHECK, NEEDS_PURCHASE }
