package com.pisocake.todaymeal.domain.repository

import com.pisocake.todaymeal.domain.model.MenuSuggestion

/**
 * 메뉴 추천 조회.
 *
 * <p>가능 여부는 서버가 판정한다. 앱은 받은 값을 그리기만 하며, 조회만으로 재고를 바꾸지 않는다.
 */
interface MenuRepository {

    /** 현재 재고로 가능한 메뉴를 최대 3개 읽는다. */
    suspend fun listSuggestions(): Result<List<MenuSuggestion>>
}
