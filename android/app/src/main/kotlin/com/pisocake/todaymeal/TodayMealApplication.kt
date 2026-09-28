package com.pisocake.todaymeal

import android.app.Application
import dagger.hilt.android.HiltAndroidApp
import timber.log.Timber

/**
 * Hilt 진입점.
 *
 * <p>로그는 Timber 로만 남긴다. `println` 과 `Log` 를 직접 쓰지 않는다.
 */
@HiltAndroidApp
class TodayMealApplication : Application() {

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            Timber.plant(Timber.DebugTree())
        }
        Timber.i("TodayMeal application started")
    }
}
