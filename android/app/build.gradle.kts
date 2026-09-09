// NOTE: fully-qualified `java.util.Properties` breaks here because the AGP
// `java` extension shadows the package name in the app-module script — explicit
// imports are required (official Flutter "Sign the app" template).
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material (keystore + passwords) stays OUTSIDE the repo:
// android/key.properties is gitignored (.gitignore:48); the keystore lives in
// the parent of the repo at <repo>/../keys/conver_system_upload.jks (e.g.
// F:\Craft\conver system\keys\conver_system_upload.jks). Semantics: `rootProject`
// here is the android/ Gradle project (settings.gradle.kts lives in android/),
// so rootProject.file("key.properties") resolves to android/key.properties.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.conversystem.conver_system_mobile"
    // 显式 37：flutter_secure_storage 11.x（M1-T01 锁定 ^11.0.0）的 AAR 元数据
    // 要求 compileSdk >= 37，Flutter 3.47.2 默认（flutter.compileSdkVersion=36）
    // 不满足（M1-T07 构建验证实证）。本机 SDK 平台 android-37.0 已装。
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.conversystem.conver_system_mobile"
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
    }

    // storeFile resolves via rootProject.file() against the android/ Gradle
    // project dir — NOT against this app module dir, where `file(it)` would be
    // off by one level (`android/app/../../keys` would hit <repo>/keys, inside
    // the repo, instead of <repo>/../keys outside it). With rootProject.file(),
    // the repo key.properties relative value "storeFile=../../keys/..." resolves
    // to <repo>/../keys/conver_system_upload.jks (outside the repo); the worktree
    // local copy uses an absolute path instead. Both work.
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            // Dedicated upload keystore — the default debug signing is no longer used.
            signingConfig = signingConfigs.getByName("release")
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
