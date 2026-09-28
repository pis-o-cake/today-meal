package com.pisocake.todaymeal.core.voice

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 마이크 소유권 전환을 검증한다.
 *
 * <p>확인하는 것은 순서다 — 전사를 시작하기 전에 감지기가 마이크를 놓았는지, 어떤 경로로
 * 끝나든 감지기가 다시 기동되는지.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class VoiceSessionManagerTest {

    private val calls = mutableListOf<String>()

    private val detector = object : WakeWordDetector {
        override val detections: Flow<Unit> = emptyFlow()
        override suspend fun start() { calls += "detector.start" }
        override suspend fun stop() { calls += "detector.stop" }
        override fun release() { calls += "detector.release" }
    }

    private var transcript: String? = "계란 두 개 썼어"
    private val transcriber = object : SpeechTranscriber {
        override fun isAvailable() = true
        override fun isOnDeviceAvailable() = false
        override suspend fun transcribeOnce(
            languageTag: String,
            onPartial: (String) -> Unit,
        ): String {
            calls += "transcriber.transcribe"
            return transcript ?: throw TranscriptionException("no speech")
        }
        override fun cancel() { calls += "transcriber.cancel" }
    }

    private var speakSucceeds = true
    private val speaker = object : SpeechSpeaker {
        override fun isKoreanAvailable() = true
        override suspend fun speak(text: String): Boolean {
            calls += "speaker.speak"
            return speakSucceeds
        }
        override fun stop() { calls += "speaker.stop" }
        override fun release() { calls += "speaker.release" }
    }

    private fun manager() = VoiceSessionManager(detector, transcriber, speaker)

    @Test
    fun `detector releases microphone before transcription starts`() = runTest {
        val manager = manager()
        manager.startSession(this) { VoiceTurnResult.Answered("네") }
        advanceUntilIdle()

        val stopIndex = calls.indexOf("detector.stop")
        val transcribeIndex = calls.indexOf("transcriber.transcribe")
        assertTrue("감지기가 먼저 마이크를 놓아야 한다", stopIndex in 0 until transcribeIndex)
    }

    @Test
    fun `detector restarts after a successful turn`() = runTest {
        val manager = manager()
        manager.startSession(this) { VoiceTurnResult.Answered("네") }
        advanceUntilIdle()

        assertTrue("대기로 복귀해야 한다", calls.contains("detector.start"))
        assertEquals(VoiceState.Waiting, manager.state.value)
    }

    @Test
    fun `detector restarts even when text to speech fails`() = runTest {
        speakSucceeds = false
        val manager = manager()
        manager.startSession(this) { VoiceTurnResult.Answered("네") }
        advanceUntilIdle()

        // 실패 경로에서도 대기로 돌아와야 한다. 한쪽만 걸면 여기서 멈춘다.
        assertTrue(calls.contains("detector.start"))
        assertEquals(VoiceState.Waiting, manager.state.value)
    }

    @Test
    fun `detector restarts when the server call fails`() = runTest {
        val manager = manager()
        manager.startSession(this) {
            VoiceTurnResult.Failed(spoken = "다시 말해주세요", logDetail = "upstream 502")
        }
        advanceUntilIdle()

        assertTrue(calls.contains("detector.start"))
        assertEquals(VoiceState.Waiting, manager.state.value)
    }

    @Test
    fun `muted session ignores wake word`() = runTest {
        val manager = manager()
        manager.mute()
        calls.clear()
        manager.startSession(this) { VoiceTurnResult.Answered("네") }
        advanceUntilIdle()

        assertTrue("음소거 중에는 전사하지 않는다", calls.none { it == "transcriber.transcribe" })
        assertEquals(VoiceState.Muted, manager.state.value)
    }
}
