package com.pisocake.todaymeal.core.voice

import android.content.Context
import android.speech.tts.TextToSpeech
import java.util.Locale
import timber.log.Timber

/**
 * Android `TextToSpeech` 기반 낭독기.
 *
 * <p>기기에 한국어 음성 데이터가 없으면 낭독이 되지 않는다. SP-3 에서 확인하고 없으면 설치를
 * 안내한다.
 */
class AndroidSpeechSpeaker(
    private val context: Context,
) : SpeechSpeaker {

    private var engine: TextToSpeech? = null
    private var koreanReady = false

    override fun isKoreanAvailable(): Boolean = koreanReady

    override suspend fun speak(text: String): Boolean {
        // TODO: S-01 에서 TextToSpeech 초기화 콜백과 UtteranceProgressListener 를 코루틴으로 잇는다.
        //  IMPORTANT: 완료와 오류 양쪽 콜백을 모두 이 함수의 반환으로 모아야 한다.
        Timber.w("Text to speech is not wired yet: planned in slice S-01")
        return false
    }

    override fun stop() {
        engine?.stop()
    }

    override fun release() {
        engine?.shutdown()
        engine = null
        koreanReady = false
    }

    private companion object {
        val KOREAN: Locale = Locale.KOREA
    }
}
