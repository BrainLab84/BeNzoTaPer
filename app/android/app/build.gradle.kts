plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.tapering.buddy"
    // flutter_local_notifications 23 verlangt mindestens 37
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (Erinnerung) braucht Desugaring
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Endgültige ID vor der ersten Veröffentlichung festlegen (danach nie mehr ändern).
        applicationId = "de.tapering.buddy"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appName"] = "BeNzoTaPer"
        // Test-APK (TB_TEST=1): eigene ID + eigener Name, damit sie neben der alten App
        // installiert werden kann und deren Daten nicht anrührt.
        if (System.getenv("TB_TEST") == "1") {
            applicationIdSuffix = ".test"
            manifestPlaceholders["appName"] = "BeNzoTaPer Test"
        }
    }

    // Fester Schlüssel für die echte App (Updates ohne Datenverlust). Kommt aus Umgebungsvariablen:
    // TB_KEYSTORE_PATH (PKCS12-Datei), TB_KEYSTORE_PASSWORD, TB_KEY_ALIAS. In GitHub Actions aus den Secrets
    // TB_KEYSTORE_B64 / TB_KEYSTORE_PASSWORD / TB_KEY_ALIAS (Workflow apk-release.yml). Die Datei liegt nie im Repo.
    val tbKeystore = System.getenv("TB_KEYSTORE_PATH")
    signingConfigs {
        if (tbKeystore != null && file(tbKeystore).exists()) {
            create("tb") {
                storeFile = file(tbKeystore)
                storePassword = System.getenv("TB_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("TB_KEY_ALIAS")
                keyPassword = System.getenv("TB_KEYSTORE_PASSWORD")
                storeType = "PKCS12"
            }
        }
    }

    buildTypes {
        release {
            // Mit festem Schlüssel, wenn vorhanden (echte App); sonst Debug-Schlüssel (Test-APK „BeNzoTaPer Test“).
            signingConfig = signingConfigs.findByName("tb") ?: signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
