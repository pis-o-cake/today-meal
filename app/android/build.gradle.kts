// 플러그인 하위 프로젝트에 강제할 compileSdk. 앱의 값과 같게 유지한다.
val pluginCompileSdk = 36

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Porcupine 이 끌고 오는 flutter_voice_processor 가 android-31 로 컴파일돼 있고,
// 그 의존성(androidx.fragment)이 34 이상을 요구한다. 플러그인이 올라오기 전까지
// 하위 프로젝트의 compileSdk 를 앱과 같게 맞춘다.
//
// IMPORTANT: 아래 evaluationDependsOn 보다 먼저 등록해야 한다. 그 블록이 하위 프로젝트를
// 즉시 평가시키므로, 뒤에 두면 "already evaluated" 로 실패한다.
//
// WARNING: 플러그인이 최신 SDK 에서 깨지면 이 덮어쓰기가 원인일 수 있다. 플러그인 쪽이
// compileSdk 를 올린 뒤에는 이 블록을 지운다.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            val setter = android.javaClass.methods.firstOrNull {
                it.name == "setCompileSdkVersion" &&
                    it.parameterTypes.size == 1 &&
                    it.parameterTypes[0] == Int::class.javaPrimitiveType
            }
            setter?.invoke(android, pluginCompileSdk)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
