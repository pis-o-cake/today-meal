package com.pisocake.todaymeal.core.voice

import android.content.Context
import com.pisocake.todaymeal.BuildConfig
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import timber.log.Timber

/**
 * Porcupine 기반 웨이크워드 감지기.
 *
 * <p>스켈레톤이다. 실제 `PorcupineManager` 배선은 SP-1 에서 호출어 모델과 AccessKey 를 확인한
 * 뒤 연결한다. 그때까지 [start] 는 준비되지 않았음을 예외로 드러낸다 — 조용히 성공하면
 * 감지가 되는 것으로 착각한다.
 *
 * <p>모델 파일은 `src/main/assets/` 에 두고, 콘솔에서 생성한 커스텀 모델을 자체 학습 모델로
 * 소개하지 않는다.
 */
class PorcupineWakeWordDetector(
    private val context: Context,
) : WakeWordDetector {

    // 감지 이벤트는 놓쳐도 다음 호출이 있다. 최신 것만 남기고 버린다.
    private val _detections = MutableSharedFlow<Unit>(
        replay = 0,
        extraBufferCapacity = 1,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )

    override val detections: Flow<Unit> = _detections.asSharedFlow()

    override suspend fun start() {
        check(BuildConfig.PORCUPINE_ACCESS_KEY.isNotBlank()) {
            "Porcupine access key is missing: set porcupine.accessKey in local.properties"
        }
        // TODO: S-01 에서 PorcupineManager 를 만들고 콜백에서 _detections.tryEmit(Unit) 을 호출한다.
        //  모델 경로는 assets 의 한국어 커스텀 호출어 파일이다.
        Timber.w("Wake word detection is not wired yet: planned in slice S-01")
        throw NotImplementedError("PorcupineWakeWordDetector.start is planned in slice S-01")
    }

    override suspend fun stop() {
        // TODO: S-01 에서 PorcupineManager.stop 을 호출해 마이크를 놓는다.
        Timber.d("Wake word detector stop requested (not wired yet)")
    }

    override fun release() {
        // TODO: S-01 에서 PorcupineManager.delete 를 호출한다.
        Timber.d("Wake word detector release requested (not wired yet)")
    }
}
