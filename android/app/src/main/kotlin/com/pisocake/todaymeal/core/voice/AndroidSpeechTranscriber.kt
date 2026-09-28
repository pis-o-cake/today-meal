package com.pisocake.todaymeal.core.voice

import android.content.Context
import android.os.Build
import android.speech.SpeechRecognizer
import timber.log.Timber

/**
 * Android 내장 `SpeechRecognizer` 기반 전사기.
 *
 * <p>가용성 판정은 지금 동작한다. 실제 전사 배선은 SP-2·SP-3 에서 마이크 전환과 한국어 인식을
 * 확인한 뒤 연결한다.
 *
 * <p>CAUTION: 내장 서비스가 항상 기기 내에서 처리되는 것은 아니다. [isOnDeviceAvailable] 이
 * 참이어도 한국어 모델 지원은 별도로 확인해야 하며, 완전 오프라인 STT 라고 표현하지 않는다.
 */
class AndroidSpeechTranscriber(
    private val context: Context,
) : SpeechTranscriber {

    override fun isAvailable(): Boolean = SpeechRecognizer.isRecognitionAvailable(context)

    override fun isOnDeviceAvailable(): Boolean {
        // 온디바이스 판정 API 는 Android 12(S)부터 있다. 그 아래에서는 판정하지 않는다.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return false
        return SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
    }

    override suspend fun transcribeOnce(
        languageTag: String,
        onPartial: (String) -> Unit,
    ): String {
        // TODO: S-01 에서 SpeechRecognizer 를 만들고 콜백을 코루틴으로 잇는다.
        //  onReadyForSpeech 뒤에 신호음을 주고, onResults 또는 onError 뒤에 자원을 정리한다.
        Timber.w("Speech transcription is not wired yet: planned in slice S-01")
        throw TranscriptionException("AndroidSpeechTranscriber is planned in slice S-01")
    }

    override fun cancel() {
        // TODO: S-01 에서 SpeechRecognizer.cancel 과 destroy 를 호출해 마이크를 놓는다.
        Timber.d("Transcription cancel requested (not wired yet)")
    }
}
