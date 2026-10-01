package com.pisocake.today_meal

import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 앱의 유일한 화면.
 *
 * 여기서 하는 일은 **앱이 뜨기 전에 보이는 것을 다듬는 것** 셋이다.
 *
 * 1. 창 배경을 사용자가 고른 화면 테마에 맞춘다. 기기의 다크 모드를 따르지 않는다 —
 *    파스텔을 쓰는 사람이 기기를 다크로 두었다고 검은 화면부터 볼 이유가 없다.
 * 2. Android 12+ 의 시스템 스플래시를 곧바로 걷는다.
 * 3. **걷힌 시각을 Flutter 에 알린다.** Flutter 는 시스템 스플래시 뒤에서 이미 프레임을
 *    그리고 있어서, 스스로는 언제부터 사람에게 보이는지 알 수 없다. 알려주지 않으면
 *    스플래시 연출이 가려진 채로 돌다가 **중간부터** 보인다.
 */
class MainActivity : FlutterActivity() {

    private var splashGone = false
    private var waiting: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // WARNING: 리스너는 첫 프레임 전에 걸어야 한다. `super.onCreate` 뒤에 걸면
        // 시스템 스플래시가 이미 자기 퇴장 연출을 시작한 뒤다.
        watchSystemSplash()
        super.onCreate(savedInstanceState)
        applyLaunchBackground()
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != AWAIT_SPLASH) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                // 이미 걷혔으면 바로 답하고, 아니면 걷힐 때 답한다.
                if (splashGone) result.success(null) else waiting = result
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, CUE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != PLAY_CUE) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                ListeningCue.play()
                result.success(ListeningCue.lengthMs)
            }
    }

    /**
     * 저장된 화면 테마의 배경색을 창에 건다.
     *
     * 값은 Flutter 의 `SharedPreferences` 에 있다(`shared_preferences` 플러그인이
     * `flutter.` 를 앞에 붙인다). 아직 고르지 않았으면 기본인 파스텔이다.
     */
    private fun applyLaunchBackground() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        window.setBackgroundDrawable(
            ColorDrawable(backgroundOf(prefs.getString("flutter.skin", null)))
        )
    }

    /**
     * 화면 테마별 진입 배경.
     *
     * CAUTION: 값은 Dart 쪽 `Skins.<theme>.hello.bgMid` 와 같아야 한다. 한쪽만 고치면
     * 앱이 뜨는 순간 색이 바뀐다.
     */
    private fun backgroundOf(skin: String?): Int = when (skin) {
        "dark" -> Color.parseColor("#202124")
        "white" -> Color.parseColor("#F4F5F7")
        "glass" -> Color.parseColor("#FFFFFF")
        else -> Color.parseColor("#F6F7FF")
    }

    /**
     * 시스템 스플래시를 즉시 걷고 그 사실을 남긴다.
     *
     * Android 11 이하에는 시스템 스플래시가 없다. 창 배경이 곧 진입 화면이므로 처음부터
     * 걷힌 것으로 둔다.
     */
    private fun watchSystemSplash() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            splashGone = true
            return
        }
        splashScreen.setOnExitAnimationListener { view ->
            view.remove()
            splashGone = true
            waiting?.success(null)
            waiting = null
        }
    }

    private companion object {
        const val CHANNEL = "today_meal/launch"
        const val AWAIT_SPLASH = "awaitSystemSplash"
        const val CUE_CHANNEL = "today_meal/cue"
        const val PLAY_CUE = "playListening"
    }
}
