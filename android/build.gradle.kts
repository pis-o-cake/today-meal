// 루트에서는 플러그인을 적용하지 않고 버전만 선언한다.
plugins {
    alias(libs.plugins.android.application) apply false
    // AGP 9 부터 Kotlin 지원이 내장이다. kotlin-android 플러그인을 적용하지 않는다.
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.hilt) apply false
}
