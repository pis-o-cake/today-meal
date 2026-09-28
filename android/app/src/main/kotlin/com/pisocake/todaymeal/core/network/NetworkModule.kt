package com.pisocake.todaymeal.core.network

import com.pisocake.todaymeal.BuildConfig
import com.pisocake.todaymeal.data.remote.TodayMealApi
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import java.util.concurrent.TimeUnit
import javax.inject.Singleton
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory

/**
 * 네트워크 배선.
 *
 * <p>서버 주소는 `local.properties` 에서 온 `BuildConfig.API_BASE_URL` 이다. 소스에 박지 않는다.
 */
@Module
@InstallIn(SingletonComponent::class)
object NetworkModule {

    /** 서버가 모르는 필드를 추가해도 앱이 죽지 않게 한다. */
    @Provides
    @Singleton
    fun provideJson(): Json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
    }

    @Provides
    @Singleton
    fun provideOkHttp(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(CONNECT_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        // 명령 한 번이 모델 호출을 포함하므로 읽기 타임아웃을 넉넉히 둔다.
        .readTimeout(READ_TIMEOUT_SECONDS, TimeUnit.SECONDS)
        .addInterceptor(CallerHeaderInterceptor())
        .build()

    @Provides
    @Singleton
    fun provideRetrofit(client: OkHttpClient, json: Json): Retrofit = Retrofit.Builder()
        .baseUrl(BuildConfig.API_BASE_URL)
        .client(client)
        .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
        .build()

    @Provides
    @Singleton
    fun provideApi(retrofit: Retrofit): TodayMealApi = retrofit.create(TodayMealApi::class.java)

    private const val CONNECT_TIMEOUT_SECONDS = 10L
    private const val READ_TIMEOUT_SECONDS = 60L
}
