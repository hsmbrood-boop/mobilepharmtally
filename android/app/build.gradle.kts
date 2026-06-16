import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// release 서명 정보(키 비밀번호 등) 는 깃에 올라가면 안 되므로 별도
// `android/key.properties` 파일에서 읽는다. 파일이 없으면 debug 키로
// fallback 되어 개발 빌드(`flutter run`)는 계속 가능하다.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.orcholdings.pharmtally"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 가 java.time 등 신형 API 를 minSdk
        // 이하에서도 쓰기 위해 core library desugaring 을 활성화.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.orcholdings.pharmtally"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // SynDrive 통합 코드가 NotificationChannel(API 26) 등을 가드 없이 쓰므로
        // minSdk 26(Android 8.0) 이상 필요. (SynDrive 도 원래 26, 단말은 Android 16.)
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // key.properties 가 있을 때만 진짜 키를 사용. 없으면 빈 값이라
            // gradle 이 자동으로 debug 키로 fallback.
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // key.properties 가 있으면 release 키, 없으면 debug 키로 서명.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // core library desugaring 런타임. `compileOptions` 의 옵션과 짝.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // ── SynDrive(OneDrive 단방향 동기화) 통합에 필요한 의존성 ──
    // SyndriveActivity 설정 화면(AppCompat + Material), SAF(documentfile),
    // Graph API 호출(okhttp), 코루틴, WorkManager 주기 동기화.
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.work:work-runtime-ktx:2.10.1")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.1")
}
