import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.example.gridshare_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.gridshare_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Gradle 9.1's stripReleaseDebugSymbols task crashes on the NDK .so strip
        // step ("Failed to create MD5 hash for ...libflutter.so.temp-stream").
        // Setting debugSymbolLevel = none makes the build emit already-stripped
        // libs, so that broken task is skipped AND the APK stays small.
        ndk {
            debugSymbolLevel = "none"
        }

        // Clerk publishable key - read directly from local.properties file
        val localProperties = Properties()
        val localPropertiesFile = rootProject.file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { localProperties.load(it) }
        }
        val clerkPublishableKey = localProperties.getProperty("CLERK_PUBLISHABLE_KEY") ?: "pk_test_your_key_here"
        println("DEBUG: CLERK_PUBLISHABLE_KEY = $clerkPublishableKey")
        // Escape $ for Java string literal, then use concatenation to avoid Kotlin string interpolation
        val escapedKey = clerkPublishableKey.replace("\\$", "\\\\\\$")
        buildConfigField("String", "CLERK_PUBLISHABLE_KEY", "\"" + escapedKey + "\"")
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Clerk Android SDK - authentication with Google One Tap
    implementation("com.clerk:clerk-android-ui:1.0.36")
    implementation("com.clerk:clerk-android-api:1.0.36")
    // Google Identity Services for One Tap
    implementation("com.google.android.gms:play-services-auth:21.2.0")

    // Compose BOM and dependencies
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.2")
}
