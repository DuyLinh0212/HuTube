import java.util.Base64
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val publicFirebaseFile = file("../../assets/firebase.public.json")
val publicFirebaseDefaults = if (publicFirebaseFile.exists()) {
    (JsonSlurper().parse(publicFirebaseFile) as Map<*, *>).entries.associate { it.key.toString() to it.value.toString() }
} else emptyMap()
val firebaseOverrides = (project.findProperty("dart-defines") as? String).orEmpty()
    .split(",").mapNotNull { encoded ->
        runCatching {
            val value = String(Base64.getDecoder().decode(encoded), Charsets.UTF_8).split("=", limit = 2)
            if (value.size == 2 && value[1].isNotBlank()) value[0] to value[1] else null
        }.getOrNull()
    }.toMap()
val firebaseDefines = publicFirebaseDefaults + firebaseOverrides

android {
    namespace = "com.hutube.user_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hutube.user_app"
        // Native Firebase must initialize before Dart when a push wakes a
        // terminated app. These are public app identifiers, never server keys.
        if (listOf("FIREBASE_API_KEY", "FIREBASE_APP_ID", "FIREBASE_PROJECT_ID", "FIREBASE_MESSAGING_SENDER_ID")
                .all { !firebaseDefines[it].isNullOrBlank() }) {
            resValue("string", "google_app_id", firebaseDefines.getValue("FIREBASE_APP_ID"))
            resValue("string", "google_api_key", firebaseDefines.getValue("FIREBASE_API_KEY"))
            resValue("string", "project_id", firebaseDefines.getValue("FIREBASE_PROJECT_ID"))
            resValue("string", "gcm_defaultSenderId", firebaseDefines.getValue("FIREBASE_MESSAGING_SENDER_ID"))
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // better_native_video_player requires Android 7.0 (API 24).
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            val localKeystore = file("debug.keystore")
            if (localKeystore.exists()) {
                storeFile = localKeystore
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
        create("release") {
            val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
            if (keystorePath != null && file(keystorePath).exists()) {
                storeFile = file(keystorePath)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD") ?: "android"
                keyAlias = System.getenv("ANDROID_KEY_ALIAS") ?: "androiddebugkey"
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD") ?: "android"
            } else {
                val localKeystore = file("debug.keystore")
                if (localKeystore.exists()) {
                    storeFile = localKeystore
                    storePassword = "android"
                    keyAlias = "androiddebugkey"
                    keyPassword = "android"
                } else {
                    initWith(getByName("debug"))
                }
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

val adbReverseTask = tasks.register("adbReverse") {
    doLast {
        try {
            val adb = android.adbExecutable.absolutePath
            project.exec {
                commandLine(adb, "reverse", "tcp:5080", "tcp:5080")
                isIgnoreExitValue = true
            }
            println("[HuTube] adb reverse tcp:5080 tcp:5080 thanh cong.")
        } catch (e: Exception) {
            println("[HuTube] Bo qua adb reverse: ${e.message}")
        }
    }
}

afterEvaluate {
    tasks.findByName("preBuild")?.dependsOn(adbReverseTask)
}
