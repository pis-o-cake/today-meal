package com.pisocake.todaymeal.core.voice

/**
 * 호출 이후의 명령을 텍스트로 바꾼다.
 *
 * <p>구현은 Android `SpeechRecognizer` 다. 상시 전사에 쓰지 않는다 — 대기 중에는 STT 를
 * 실행하지 않는 것이 검증 기준이다.
 *
 * <p>CAUTION: 내장 서비스가 항상 기기 내에서 처리되는 것은 아니다. 완전 오프라인 STT 라고
 * 표현하지 않는다.
 */
interface SpeechTranscriber {

    /** 기기에 인식 서비스가 있는지. 없으면 텍스트 입력 경로만 제공한다. */
    fun isAvailable(): Boolean

    /**
     * 기기 내 인식 엔진이 있는지.
     *
     * <p>지원 OS 에서만 판정할 수 있다. 한국어 모델 지원은 별도로 확인해야 한다.
     */
    fun isOnDeviceAvailable(): Boolean

    /**
     * 한 번의 명령을 전사한다.
     *
     * <p>발화 종료는 인식 서비스의 콜백을 기준으로 판정한다. 무음 종료 시간 설정은 서비스마다
     * 지원이 달라 동일한 동작을 가정하지 않으며, 앱이 별도 타임아웃을 함께 건다.
     *
     * @param languageTag 인식 언어. 예 `ko-KR`.
     * @param onPartial 중간 결과. 화면에 자막으로 보여준다.
     * @return 최종 전사 결과.
     * @throws TranscriptionException 인식 실패·타임아웃·오디오 중단.
     */
    suspend fun transcribeOnce(
        languageTag: String = "ko-KR",
        onPartial: (String) -> Unit = {},
    ): String

    /** 진행 중인 전사를 취소하고 마이크를 놓는다. */
    fun cancel()
}

/** 전사 실패. 메시지는 로그용이므로 영어로 고정한다. */
class TranscriptionException(message: String, cause: Throwable? = null) :
    Exception(message, cause)
