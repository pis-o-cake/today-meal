# kotlinx.serialization 이 생성한 serializer 를 보존한다.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class com.pisocake.todaymeal.data.remote.** {
    *** Companion;
}
-keepclasseswithmembers class com.pisocake.todaymeal.data.remote.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Porcupine 네이티브 바인딩.
-keep class ai.picovoice.porcupine.** { *; }
