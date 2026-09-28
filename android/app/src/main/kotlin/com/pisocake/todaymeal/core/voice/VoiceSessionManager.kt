package com.pisocake.todaymeal.core.voice

import com.pisocake.todaymeal.core.voice.VoiceState.Unavailable.Reason
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import timber.log.Timber

/**
 * 마이크 소유권 상태기계.
 *
 * <p><b>이 프로젝트에서 가장 위험한 구성요소다.</b> 웨이크워드 감지기와 전사기는 같은 마이크를
 * 동시에 점유할 수 없어, 소유권을 넘기는 지점이 곧 실패 지점이 된다. 그래서 마이크를 만지는
 * 코드를 이 클래스 하나에 모으고 [state] 를 단일 진실 원천으로 둔다.
 *
 * <p>ViewModel 은 상태를 읽고 명령을 보내기만 하며 감지기나 전사기를 직접 다루지 않는다.
 *
 * <pre>{@code
 * 감지 → 감지기 stop(마이크 해제) → 신호음 → 전사 → 서버 → TTS → 감지기 start
 * }</pre>
 *
 * <p>IMPORTANT: TTS 재생 중에는 전사를 시작하지 않는다. 시작하면 자기 응답을 다시 명령으로
 * 처리한다. 재생 완료와 실패 <b>양쪽</b>에서 감지기를 재기동한다.
 */
@Singleton
class VoiceSessionManager @Inject constructor(
    private val detector: WakeWordDetector,
    private val transcriber: SpeechTranscriber,
    private val speaker: SpeechSpeaker,
) {

    private val _state = MutableStateFlow<VoiceState>(VoiceState.Waiting)

    /** 화면과 ViewModel 이 구독하는 유일한 상태. */
    val state: StateFlow<VoiceState> = _state.asStateFlow()

    private var sessionJob: Job? = null
    private var muted = false

    /**
     * 한 번의 대화를 처리한다.
     *
     * <p>호출어 감지부터 응답 재생까지를 한 흐름으로 묶고, 어떤 경로로 끝나든 대기 상태로
     * 돌아온다. `finally` 에서 감지기를 재기동하는 것이 그 보장이다.
     *
     * @param scope 세션을 돌릴 스코프. 화면이 아니라 앱 수명에 묶는다.
     * @param handle 전사된 텍스트를 서버로 보내 처리한다.
     */
    fun startSession(scope: CoroutineScope, handle: suspend (String) -> VoiceTurnResult) {
        if (muted) {
            Timber.d("Wake word ignored: session is muted")
            return
        }
        if (sessionJob?.isActive == true) {
            Timber.d("Wake word ignored: a session is already running")
            return
        }
        sessionJob = scope.launch { runSession(handle) }
    }

    private suspend fun runSession(handle: suspend (String) -> VoiceTurnResult) {
        try {
            // 감지기가 마이크를 놓아야 전사기가 시작할 수 있다.
            detector.stop()

            _state.value = VoiceState.Listening()
            val utterance = withTimeoutOrNull(COMMAND_TIMEOUT_MILLIS) {
                transcriber.transcribeOnce { partial ->
                    _state.value = VoiceState.Listening(partial)
                }
            }
            if (utterance.isNullOrBlank()) {
                Timber.w("Command transcription produced no result")
                speakAndFinish(RETRY_MESSAGE_KEY)
                return
            }

            _state.value = VoiceState.Processing(utterance)
            when (val result = handle(utterance)) {
                is VoiceTurnResult.Answered -> speakAndFinish(result.spoken)
                is VoiceTurnResult.NeedsClarification -> clarify(result, handle)
                is VoiceTurnResult.Failed -> {
                    // WARNING: 실패를 완료처럼 알리지 않는다.
                    Timber.w("Turn failed: %s", result.logDetail)
                    speakAndFinish(result.spoken)
                }
            }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (error: Exception) {
            Timber.e(error, "Voice session failed")
            _state.value = VoiceState.Unavailable(Reason.AUDIO_INTERRUPTED)
        } finally {
            resumeDetection()
        }
    }

    private suspend fun clarify(
        result: VoiceTurnResult.NeedsClarification,
        handle: suspend (String) -> VoiceTurnResult,
    ) {
        _state.value = VoiceState.Clarifying(result.question)
        speaker.speak(result.question)

        // 호출어를 반복하지 않아도 답할 수 있게 짧은 창을 연다.
        val followUp = withTimeoutOrNull(CLARIFY_WINDOW_MILLIS) {
            _state.value = VoiceState.Listening()
            transcriber.transcribeOnce { partial -> _state.value = VoiceState.Listening(partial) }
        }
        if (followUp.isNullOrBlank()) {
            // 확인되지 않은 임시 변경은 적용하지 않는다.
            Timber.i("Clarification timed out; pending change discarded")
            return
        }
        _state.value = VoiceState.Processing(followUp)
        when (val next = handle(followUp)) {
            is VoiceTurnResult.Answered -> speakAndFinish(next.spoken)
            is VoiceTurnResult.Failed -> speakAndFinish(next.spoken)
            is VoiceTurnResult.NeedsClarification -> speakAndFinish(next.question)
        }
    }

    private suspend fun speakAndFinish(text: String) {
        _state.value = VoiceState.Speaking(text)
        val spoken = speaker.speak(text)
        if (!spoken) {
            // 낭독이 실패해도 결과는 화면에 남는다. 대기 복귀는 finally 가 보장한다.
            Timber.w("TTS did not complete; result remains on screen only")
        }
    }

    private suspend fun resumeDetection() {
        transcriber.cancel()
        if (muted) {
            _state.value = VoiceState.Muted
            return
        }
        _state.value = runCatching { detector.start() }
            .fold(
                onSuccess = { VoiceState.Waiting },
                onFailure = { error ->
                    Timber.e(error, "Failed to resume wake word detection")
                    VoiceState.Unavailable(Reason.WAKE_WORD_INIT_FAILED)
                },
            )
    }

    /** 음소거한다. 대기 중으로 표시하지 않는다. */
    suspend fun mute() {
        muted = true
        sessionJob?.cancel()
        detector.stop()
        speaker.stop()
        _state.value = VoiceState.Muted
    }

    /** 음소거를 해제하고 대기로 돌아간다. */
    suspend fun unmute() {
        muted = false
        resumeDetection()
    }

    /** 권한이 없거나 초기화가 실패한 상태를 그대로 표시한다. */
    fun markUnavailable(reason: Reason) {
        Timber.w("Voice unavailable: %s", reason)
        _state.value = VoiceState.Unavailable(reason)
    }

    /** 자원을 해제한다. */
    fun release() {
        sessionJob?.cancel()
        detector.release()
        speaker.release()
    }

    private companion object {
        /** 명령 세션의 앱 타임아웃. 인식 서비스의 무음 종료와 별개로 건다. */
        const val COMMAND_TIMEOUT_MILLIS = 20_000L

        /** 재질문 후속 응답 창. */
        const val CLARIFY_WINDOW_MILLIS = 10_000L

        /** 전사 실패 시 읽어줄 문구의 키. 실제 문구는 리소스에서 온다. */
        const val RETRY_MESSAGE_KEY = "voice_retry"
    }
}

/**
 * 한 번의 대화 처리 결과.
 *
 * <p>서버 응답을 음성 계층이 이해할 수 있는 형태로 줄인 것이다. 재고 판정은 서버가 하고
 * 이 타입은 "무엇을 읽고 다음에 무엇을 할지"만 담는다.
 */
sealed interface VoiceTurnResult {

    /** 처리를 마쳤다. [spoken] 을 읽고 대기로 돌아간다. */
    data class Answered(val spoken: String) : VoiceTurnResult

    /** 한 가지를 되물어야 한다. */
    data class NeedsClarification(val question: String) : VoiceTurnResult

    /**
     * 실패했다.
     *
     * @property spoken 사용자에게 읽어줄 문구. 성공한 것처럼 말하지 않는다.
     * @property logDetail 로그에 남길 영어 설명.
     */
    data class Failed(val spoken: String, val logDetail: String) : VoiceTurnResult
}
