package com.pisocake.todaymeal.di

import android.content.Context
import com.pisocake.todaymeal.core.voice.AndroidSpeechSpeaker
import com.pisocake.todaymeal.core.voice.AndroidSpeechTranscriber
import com.pisocake.todaymeal.core.voice.PorcupineWakeWordDetector
import com.pisocake.todaymeal.core.voice.SpeechSpeaker
import com.pisocake.todaymeal.core.voice.SpeechTranscriber
import com.pisocake.todaymeal.core.voice.WakeWordDetector
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

/**
 * 음성 계층 배선.
 *
 * <p>세 구현을 모두 싱글턴으로 둔다. 마이크를 다루는 객체가 여럿 생기면 소유권 관리가
 * 무의미해진다.
 */
@Module
@InstallIn(SingletonComponent::class)
object VoiceModule {

    @Provides
    @Singleton
    fun provideWakeWordDetector(@ApplicationContext context: Context): WakeWordDetector =
        PorcupineWakeWordDetector(context)

    @Provides
    @Singleton
    fun provideTranscriber(@ApplicationContext context: Context): SpeechTranscriber =
        AndroidSpeechTranscriber(context)

    @Provides
    @Singleton
    fun provideSpeaker(@ApplicationContext context: Context): SpeechSpeaker =
        AndroidSpeechSpeaker(context)
}
