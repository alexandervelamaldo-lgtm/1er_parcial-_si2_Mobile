// Top-level Gradle settings — registers the Flutter Gradle Plugin and the
// :app module. Without this file, Flutter assumes the project is using the
// deleted v1 embedding and refuses to build.
pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 8.9.1+ es requerido por androidx.activity:1.12.4, core-ktx:1.18.0
    // y otras transitivas que arrastra Firebase / webview_flutter actual.
    id("com.android.application") version "8.9.1" apply false
    // Kotlin 2.1.0+ es requerido por flutter_tts y otros plugins con código
    // Kotlin que ya usan features modernas (K2 compiler). 1.9.22 ya quedó atrás.
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
    // Firebase — google-services reads google-services.json
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
