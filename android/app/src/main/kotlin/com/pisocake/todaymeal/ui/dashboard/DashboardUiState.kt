package com.pisocake.todaymeal.ui.dashboard

import com.pisocake.todaymeal.core.voice.VoiceState
import com.pisocake.todaymeal.domain.model.IngredientBatch
import com.pisocake.todaymeal.domain.model.MenuSuggestion

/**
 * 대기 대시보드가 그리는 전부.
 *
 * <p>View 는 이 값 하나를 받아 그린다. 화면에 로직을 두지 않으므로 "비었는가"·"오류인가" 같은
 * 판정도 여기서 끝낸다.
 *
 * @property lastChangeSummary 최근 변경 한 줄. 되돌리기 버튼과 함께 보여준다.
 * @property undoToken 되돌릴 대상. `null` 이면 되돌릴 것이 없다.
 */
data class DashboardUiState(
    val voiceState: VoiceState = VoiceState.Waiting,
    val menus: List<MenuSuggestion> = emptyList(),
    val priorityBatches: List<IngredientBatch> = emptyList(),
    val lastChangeSummary: String? = null,
    val undoToken: String? = null,
    val isLoading: Boolean = false,
    val errorKey: ErrorKey? = null,
) {
    /** 화면이 보여줄 오류 종류. 문구는 리소스에서 온다. */
    enum class ErrorKey { NETWORK, UNEXPECTED }

    val hasMenus: Boolean get() = menus.isNotEmpty()
    val hasPriority: Boolean get() = priorityBatches.isNotEmpty()
    val canUndo: Boolean get() = undoToken != null
}
