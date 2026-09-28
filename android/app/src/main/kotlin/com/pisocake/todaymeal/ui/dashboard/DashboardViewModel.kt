package com.pisocake.todaymeal.ui.dashboard

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.pisocake.todaymeal.core.voice.VoiceSessionManager
import com.pisocake.todaymeal.core.voice.VoiceTurnResult
import com.pisocake.todaymeal.domain.repository.CommandRepository
import com.pisocake.todaymeal.domain.repository.InventoryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import timber.log.Timber

/**
 * 대기 대시보드의 상태를 만든다.
 *
 * <p>ViewModel 은 감지기나 전사기를 직접 다루지 않는다. [VoiceSessionManager] 의 상태를 읽고
 * 서버 호출을 넘겨주기만 한다.
 */
@HiltViewModel
class DashboardViewModel @Inject constructor(
    private val voiceSession: VoiceSessionManager,
    private val inventoryRepository: InventoryRepository,
    private val commandRepository: CommandRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(DashboardUiState())
    val uiState: StateFlow<DashboardUiState> = _uiState.asStateFlow()

    init {
        observeVoiceState()
        refresh()
    }

    private fun observeVoiceState() {
        viewModelScope.launch {
            voiceSession.state.collect { state ->
                _uiState.update { it.copy(voiceState = state) }
            }
        }
    }

    /** 재고와 먼저 쓸 재료를 다시 읽는다. */
    fun refresh() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, errorKey = null) }
            inventoryRepository.listPriorityBatches()
                .onSuccess { batches ->
                    _uiState.update { it.copy(priorityBatches = batches, isLoading = false) }
                }
                .onFailure { error ->
                    Timber.w(error, "Dashboard refresh failed")
                    _uiState.update {
                        it.copy(isLoading = false, errorKey = DashboardUiState.ErrorKey.NETWORK)
                    }
                }
        }
    }

    /**
     * 호출어가 감지되면 한 번의 대화를 시작한다.
     *
     * <p>세션은 `viewModelScope` 가 아니라 앱 수명에 묶어야 하나, 지금은 화면이 하나뿐이라
     * 여기서 시작한다. 화면이 늘면 세션 소유를 Activity 로 올린다.
     */
    fun onWakeWordDetected() {
        voiceSession.startSession(viewModelScope) { utterance -> handleUtterance(utterance) }
    }

    /**
     * 전사된 발화를 서버로 보낸다.
     *
     * <p>IMPORTANT: `commandId` 를 발화마다 **한 번만** 만든다. 재시도에서 새로 만들면 서버가
     * 중복을 막을 수 없다.
     */
    private suspend fun handleUtterance(utterance: String): VoiceTurnResult {
        val commandId = UUID.randomUUID().toString()
        return commandRepository.interpret(commandId, utterance).fold(
            onSuccess = { outcome ->
                _uiState.update {
                    it.copy(
                        lastChangeSummary = outcome.spoken,
                        undoToken = outcome.undoToken,
                    )
                }
                val question = outcome.clarificationQuestion
                when {
                    question != null -> VoiceTurnResult.NeedsClarification(question)
                    else -> VoiceTurnResult.Answered(outcome.spoken.orEmpty())
                }
            },
            onFailure = { error ->
                // 실패를 완료처럼 알리지 않는다. 읽어줄 문구는 화면이 리소스에서 채운다.
                VoiceTurnResult.Failed(spoken = "", logDetail = error.message ?: "unknown")
            },
        )
    }

    /** 직전 변경 묶음을 되돌린다. */
    fun undoLastChange() {
        val token = _uiState.value.undoToken ?: return
        viewModelScope.launch {
            commandRepository.undo(token)
                .onSuccess { outcome ->
                    _uiState.update {
                        it.copy(lastChangeSummary = outcome.spoken, undoToken = null)
                    }
                    refresh()
                }
                .onFailure { error -> Timber.e(error, "Undo failed for %s", token) }
        }
    }

    /** 음소거를 토글한다. */
    fun toggleMute() {
        viewModelScope.launch {
            if (_uiState.value.voiceState is com.pisocake.todaymeal.core.voice.VoiceState.Muted) {
                voiceSession.unmute()
            } else {
                voiceSession.mute()
            }
        }
    }
}
