package com.pisocake.todaymeal.core.design

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * 색과 타이포의 정본.
 *
 * <p>주방에서 **서 있는 거리에서 읽는** 화면이라 본문 크기를 일반 앱보다 키운다. 색만으로
 * 상태를 구분하지 않으므로 상태색은 문구·아이콘과 함께 쓴다.
 */
object TodayMealColors {
    val Charcoal = Color(0xFF12100E)
    val CharcoalRaised = Color(0xFF1E1B18)
    val Cream = Color(0xFFF5F0E6)
    val CreamDim = Color(0xFFA8A29A)
    val Lime = Color(0xFFC8E64C)
    val Warm = Color(0xFFE8A33D)
    val Alert = Color(0xFFE0603C)
}

private val DarkScheme = darkColorScheme(
    primary = TodayMealColors.Lime,
    onPrimary = TodayMealColors.Charcoal,
    secondary = TodayMealColors.Warm,
    background = TodayMealColors.Charcoal,
    onBackground = TodayMealColors.Cream,
    surface = TodayMealColors.CharcoalRaised,
    onSurface = TodayMealColors.Cream,
    onSurfaceVariant = TodayMealColors.CreamDim,
    error = TodayMealColors.Alert,
)

private val LightScheme = lightColorScheme(
    primary = Color(0xFF6B7F14),
    background = TodayMealColors.Cream,
    onBackground = TodayMealColors.Charcoal,
)

/** 멀리서 읽히도록 키운 타이포. */
private val TodayMealTypography = Typography(
    displaySmall = TextStyle(fontSize = 44.sp, lineHeight = 52.sp, fontWeight = FontWeight.Bold),
    headlineMedium = TextStyle(fontSize = 32.sp, lineHeight = 40.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 24.sp, lineHeight = 32.sp, fontWeight = FontWeight.SemiBold),
    bodyLarge = TextStyle(fontSize = 20.sp, lineHeight = 28.sp),
    bodyMedium = TextStyle(fontSize = 17.sp, lineHeight = 24.sp),
    labelLarge = TextStyle(fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.Medium),
)

/** 카드와 간격 규칙. 값을 화면마다 다시 정하지 않는다. */
object TodayMealSpacing {
    val gutter = 24.dp
    val card = 20.dp
    val tight = 12.dp
    val cardRadius = 20.dp
}

@Composable
fun TodayMealTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkScheme else LightScheme,
        typography = TodayMealTypography,
        content = content,
    )
}
