package com.pisocake.todaymeal.core.voice

/**
 * 응답을 읽는다.
 *
 * <p>구현은 Android `TextToSpeech` 다. 기기에 한국어 음성 데이터가 없으면 낭독이 되지 않으므로
 * [isKoreanAvailable] 로 먼저 확인한다.
 */
interface SpeechSpeaker {

    /** 초기화가 끝났고 한국어 음성을 쓸 수 있는지. */
    fun isKoreanAvailable(): Boolean

    /**
     * 한 문장을 읽는다. 재생이 끝나면 반환한다.
     *
     * <p>IMPORTANT: 호출자는 완료와 실패 <b>양쪽</b> 경로에서 감지기를 재기동해야 한다.
     * 한쪽만 걸면 실패 경로에서 대기로 돌아오지 못한다. 이 함수는 실패 시 예외를 던지지 않고
     * `false` 를 돌려주어 호출자가 한 곳에서 처리하게 한다.
     *
     * @param text 읽을 문장. 짧게 유지하고 상세는 화면에 남긴다.
     * @return 정상적으로 재생을 마쳤는지.
     */
    suspend fun speak(text: String): Boolean

    /** 재생을 멈춘다. */
    fun stop()

    /** 자원을 해제한다. */
    fun release()
}
