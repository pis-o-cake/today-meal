package com.pisocake.todaymeal.domain.model

/**
 * 재고 변경 한 줄.
 *
 * <p>사용 차감과 잔량 보정을 [action] 으로 구분한다. "두 개 썼어"와 "두 개 남았어"는 결과
 * 잔량이 같아도 다른 사실이다.
 */
data class ChangeRecord(
    val changeEventId: Long,
    val batchName: String,
    val action: ChangeAction,
    val quantityBefore: String? = null,
    val quantityAfter: String? = null,
    val unit: String? = null,
    val isEstimated: Boolean = false,
    val occurredAt: String,
    val commandId: String,
)

/** 변경 동작. */
enum class ChangeAction { STOCK_IN, CONSUME, ADJUST, DISCARD, MOVE, SPLIT, REVERT }
