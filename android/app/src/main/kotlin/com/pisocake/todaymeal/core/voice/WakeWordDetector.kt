package com.pisocake.todaymeal.core.voice

import kotlinx.coroutines.flow.Flow

/**
 * 웨이크워드 감지기.
 *
 * <p>구현은 Porcupine Android SDK 다. 인터페이스를 두는 이유는 실기기 검증(SP-1)에서 호출어
 * 모델이 막혔을 때 교체 지점이 필요하기 때문이다.
 *
 * <p><b>이 감지기와 {@link SpeechTranscriber} 는 마이크를 동시에 점유할 수 없다.</b> 소유권을
 * 넘기는 책임은 [VoiceSessionManager] 하나가 갖는다. 이 인터페이스의 구현이 직접 전사기를
 * 부르지 않는다.
 */
interface WakeWordDetector {

    /** 감지 이벤트. 구독하는 동안만 마이크를 점유한다. */
    val detections: Flow<Unit>

    /**
     * 감지를 시작한다.
     *
     * @throws IllegalStateException AccessKey 나 호출어 모델이 없을 때.
     */
    suspend fun start()

    /**
     * 감지를 멈추고 마이크를 놓는다.
     *
     * <p>IMPORTANT: 전사를 시작하기 전에 반드시 호출해야 한다. 마이크를 놓지 않으면
     * `SpeechRecognizer` 가 시작하지 못한다.
     */
    suspend fun stop()

    /** 자원을 해제한다. 프로세스 종료나 권한 해제 시 호출한다. */
    fun release()
}
