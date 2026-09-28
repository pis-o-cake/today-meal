package com.pisocake.todaymeal.core.voice

/**
 * 음성 세션의 상태.
 *
 * <p>화면은 이 값 하나만 보고 그린다. 마이크를 누가 점유했는지는 [VoiceSessionManager] 만
 * 알고 있으며, 상태를 색만으로 구분하지 않고 문구와 함께 표시한다.
 *
 * <pre>{@code
 * Waiting → Listening → Processing → Speaking → Waiting
 *                          ↓
 *                      Clarifying → Listening
 * }</pre>
 */
sealed interface VoiceState {

    /** 웨이크워드 대기. 감지기가 마이크를 갖고 있다. */
    data object Waiting : VoiceState

    /** 호출을 감지해 명령을 전사하는 중. 전사기가 마이크를 갖고 있다. */
    data class Listening(val partialText: String? = null) : VoiceState

    /** 서버가 처리하는 중. 마이크를 아무도 갖지 않는다. */
    data class Processing(val utterance: String) : VoiceState

    /**
     * 서버가 한 가지를 되묻는 중.
     *
     * <p>호출어를 반복하지 않아도 답할 수 있게 짧은 후속 응답 창을 연다. 시간이 초과되면
     * 확인되지 않은 임시 변경을 적용하지 않고 [Waiting] 으로 돌아간다.
     */
    data class Clarifying(val question: String) : VoiceState

    /**
     * 응답을 읽는 중.
     *
     * <p>이 동안 전사를 멈춘다. 멈추지 않으면 자기 응답을 다시 명령으로 처리한다.
     */
    data class Speaking(val text: String) : VoiceState

    /** 사용자가 음소거했다. 대기 중으로 표시하지 않는다. */
    data object Muted : VoiceState

    /**
     * 마이크를 쓸 수 없다.
     *
     * <p>권한 해제·통화·다른 앱의 오디오 점유로 감지가 멈춘 상태다. 실제 상태를 그대로
     * 보여주며 대기 중인 것처럼 표시하지 않는다.
     */
    data class Unavailable(val reason: Reason) : VoiceState {

        /** 사용할 수 없는 이유. 화면 문구를 가른다. */
        enum class Reason {
            MISSING_PERMISSION,
            WAKE_WORD_INIT_FAILED,
            RECOGNIZER_UNAVAILABLE,
            TTS_UNAVAILABLE,
            AUDIO_INTERRUPTED,
        }
    }
}
