plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.michalrapala.zostaje"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "channel"

    productFlavors {
        create("production") {
            dimension = "channel"
            applicationId = "app.michalrapala.zostaje"
            resValue("string", "app_name", "Zostaje")
        }
        create("internal") {
            dimension = "channel"
            applicationId = "app.michalrapala.zostaje.dev"
            resValue("string", "app_name", "Zostaje DEV")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // Reguly R8 dla buildu release.
            proguardFiles("proguard-rules.pro")
            // Tylko 64-bitowe ARM, czyli kazdy wspolczesny telefon. Flaga
            // --target-platform przycina wylacznie biblioteki Fluttera; natywne
            // biblioteki wtyczek leca ze swoich paczek AAR i odsiewa je dopiero
            // ten filtr - mniej MB w kazdej aktualizacji OTA.
            // Dotyczy TYLKO buildu release: debug zostaje pelny, wiec emulator
            // x86 dziala jak dotychczas.
            ndk {
                abiFilters.clear()
                abiFilters += "arm64-v8a"
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Sejf na kod odzyskiwania kopii - kod wedruje na nowy telefon z kontem Google
    implementation("com.google.android.gms:play-services-auth-blockstore:16.4.0")
}
