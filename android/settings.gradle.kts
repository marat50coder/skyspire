pluginManagement {
    val flutterSdkPath =
        run {
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

// Plugin versions — intentionally differ from sibling portfolio projects so
// generated R8 maps + build artefacts do not collide on Google Play Protect
// clustering (portfolio_registry rule).
plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.3" apply false
    id("org.jetbrains.kotlin.android") version "2.1.21" apply false
    // Firebase config generator — reads android/app/google-services.json and
    // produces the google_app_id / default_web_client_id resources that
    // firebase_core looks up at runtime.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
