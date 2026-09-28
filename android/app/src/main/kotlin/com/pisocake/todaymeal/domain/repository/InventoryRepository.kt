package com.pisocake.todaymeal.domain.repository

import com.pisocake.todaymeal.domain.model.IngredientBatch

/**
 * 재고 조회.
 *
 * <p>인터페이스가 `domain` 에, 구현이 `data` 에 있다. ViewModel 은 구현을 모른다.
 *
 * <p>IMPORTANT: 수량 계산과 날짜 비교를 앱에 두지 않는다. 같은 규칙이 앱과 서버 양쪽에 생기면
 * 어느 쪽이 맞는지 판정할 수 없다. 이 인터페이스는 읽기만 한다.
 */
interface InventoryRepository {

    /** 가구의 현재 재고를 읽는다. */
    suspend fun listBatches(): Result<List<IngredientBatch>>

    /** 기한 임박·개봉·잔량 미확인 재료를 읽는다. */
    suspend fun listPriorityBatches(): Result<List<IngredientBatch>>
}
