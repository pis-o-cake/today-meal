package com.pisocake.todaymeal.domain.model

/**
 * 재고 묶음.
 *
 * <p>같은 두부라도 기한이나 개봉 상태가 다르면 다른 묶음이다. 잔량을 모르는 묶음은 숫자를
 * 지어내지 않고 [certainty] 로 드러낸다.
 *
 * @property quantity 수량. 정성 잔량이면 `null` 이다.
 * @property qualitativeAmount `조금`·`반` 같은 표현. 숫자로 바꾸지 않는다.
 */
data class IngredientBatch(
    val batchId: Long,
    val ingredientId: Long,
    val displayName: String,
    val quantity: String? = null,
    val unit: String? = null,
    val qualitativeAmount: String? = null,
    val certainty: QuantityCertainty,
    val storage: StorageLocation,
    val dates: List<BatchDate> = emptyList(),
)

/** 수량의 확실성. 명시값과 추정값을 구분한다. */
enum class QuantityCertainty { EXACT, ESTIMATED, QUALITATIVE, UNKNOWN }

/** 보관 위치. 실제 온도 측정값이 아니다. */
enum class StorageLocation { FRIDGE, FREEZER, PANTRY, UNKNOWN }

/**
 * 묶음의 날짜 한 줄.
 *
 * @property value 날짜. `null` 이면 종류는 알지만 날짜를 모른다는 뜻이다.
 * @property isConfirmed 사용자나 라벨로 확인되었는지. 미확인을 확정값으로 승격하지 않는다.
 */
data class BatchDate(
    val kind: DateKind,
    val value: String? = null,
    val isConfirmed: Boolean = false,
    val rawText: String? = null,
)

/**
 * 날짜 종류.
 *
 * <p>서로 변환하지 않는다. 제조일을 소비기한으로 승격하지 않으며, [CHECK_REMINDER] 를
 * 소비기한이나 안전 보증으로 표현하지 않는다.
 */
enum class DateKind { USE_BY, SELL_BY, BEST_BEFORE, MANUFACTURED, PACKED, CHECK_REMINDER }
