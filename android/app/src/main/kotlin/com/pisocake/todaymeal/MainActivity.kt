package com.pisocake.todaymeal

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import com.pisocake.todaymeal.core.design.TodayMealTheme
import com.pisocake.todaymeal.ui.dashboard.DashboardRoute
import dagger.hilt.android.AndroidEntryPoint

/**
 * 유일한 Activity.
 *
 * <p>화면 유지는 호출어 감지와 별개의 기기 운영 설정이다. `FLAG_KEEP_SCREEN_ON` 으로 전경
 * 화면을 유지하며, 낮은 밝기의 대기 대시보드는 앱 내부 화면이고 운영체제의 잠금 화면과 다르다.
 *
 * <p>WARNING: 재부팅이나 강제 종료 후에는 앱을 다시 실행해야 한다. 부팅 자동 실행과 기기 전체
 * 키오스크 관리는 후속 범위다.
 */
@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent { TodayMealApp() }
    }
}

@Composable
private fun TodayMealApp() {
    TodayMealTheme {
        // TODO: S-03 에서 냉장고 화면을 붙이고 navigation-compose 로 연결한다.
        DashboardRoute(onOpenFridge = {})
    }
}
