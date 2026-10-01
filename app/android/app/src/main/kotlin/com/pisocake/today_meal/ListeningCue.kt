package com.pisocake.today_meal

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.min
import kotlin.math.sin

/**
 * 듣기 시작을 알리는 짧은 "띠딩".
 *
 * <p>호출 응답을 말("네?")로 하면 낭독이 끝나야 듣기 시작해 앞말이 잘린다. 음성 비서처럼
 * 짧은 두 음으로 바꿔 지연을 줄인다. 효과음 파일을 두지 않고 그 자리에서 합성한다.
 *
 * <p>미디어 음량을 따른다. 알림 음량은 인식 서비스의 반복 비프를 줄이려고 끄는 경우가 있다.
 */
object ListeningCue {

    private const val TAG = "ListeningCue"
    private const val SAMPLE_RATE = 44_100

    /**
     * (주파수 Hz, 시작 ms). 완전4도쯤 올라가는 두 음을 겹쳐 울린다.
     *
     * <p>높은 음을 짧게 끊으면 가볍게 들린다. 낮은 음을 종처럼 울리고 서서히 줄여야
     * 음성 비서의 부드러운 "띠-딩"에 가깝다.
     */
    private val NOTES = listOf(659.3 to 0, 987.8 to 110)
    private const val NOTE_MS = 300
    private const val DECAY_MS = 110.0
    private const val ATTACK_MS = 6.0
    private const val VOLUME = 0.22

    /** 재생 길이(ms). Dart 는 이만큼 기다린 뒤 듣기 시작해 이 소리를 받아쓰지 않는다. */
    val lengthMs: Int = NOTES.maxOf { it.second } + NOTE_MS

    private val pcm: ShortArray by lazy { synthesize() }

    fun play() {
        try {
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(SAMPLE_RATE)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(pcm.size * 2)
                .build()
            track.write(pcm, 0, pcm.size)
            track.play()
            Handler(Looper.getMainLooper()).postDelayed({ track.release() }, lengthMs + 200L)
        } catch (error: Exception) {
            // 신호음은 부가 연출이다. 실패해도 듣기는 계속한다.
            Log.w(TAG, "Listening cue failed", error)
        }
    }

    private fun synthesize(): ShortArray {
        val total = SAMPLE_RATE * lengthMs / 1000
        val mix = DoubleArray(total)
        val attack = SAMPLE_RATE * ATTACK_MS / 1000
        val decay = SAMPLE_RATE * DECAY_MS / 1000
        for ((hz, offsetMs) in NOTES) {
            val offset = SAMPLE_RATE * offsetMs / 1000
            val count = min(SAMPLE_RATE * NOTE_MS / 1000, total - offset)
            for (i in 0 until count) {
                // 빠르게 올라 지수로 줄인다. 종소리처럼 들리게 하는 핵심이다.
                val envelope = min(1.0, i / attack) * exp(-i / decay)
                val t = 2 * PI * hz * i / SAMPLE_RATE
                // 약한 2배음이 소리를 둥글게 한다. 순수 사인은 전자음처럼 날카롭다.
                val tone = sin(t) + 0.18 * sin(2 * t)
                mix[offset + i] += tone * envelope
            }
        }
        return ShortArray(total) { i ->
            (mix[i] * VOLUME * Short.MAX_VALUE).coerceIn(-32768.0, 32767.0).toInt().toShort()
        }
    }
}
