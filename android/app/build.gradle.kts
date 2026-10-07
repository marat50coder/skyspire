import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config — pulled from android/key.properties (git-ignored).
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "com.skyspire.spiregame"
    // compileSdk 36 is required by flutter_local_notifications 19+ and the
    // 16 KB page-size patch set — see pitfalls §9 and §12.
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications 19+ (and anything else
        // that pulls in java.time.* on API 23/24 — we're on 26 so this is
        // belt-and-braces but costs nothing).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.skyspire.spiregame"
        // minSdk floor is 26 — AppsFlyer 6.17+ drops support below it.
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Keep minify/shrink off until the user supplies an R8 keep-rules
            // file for AppsFlyer + Firebase. Pitfalls §19 recommends shipping
            // the first unobfuscated APK, then enabling R8 once stable.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        resources {
            // AppsFlyer + Firebase bundle duplicate META-INF entries.
            excludes += setOf(
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "META-INF/*.kotlin_module",
            )
        }
        // 16 KB page-size support — see pitfalls §9.
        jniLibs {
            useLegacyPackaging = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("androidx.multidex:multidex:2.0.1")
    // Window-manager extensions power the 16KB-page detection path at
    // runtime; the dependency is tiny and avoids a corner-case crash on
    // Pixel 8/9 devices running the April 2025 QPR.
    implementation("androidx.window:window:1.3.0")
}

flutter {
    source = "../.."
}
