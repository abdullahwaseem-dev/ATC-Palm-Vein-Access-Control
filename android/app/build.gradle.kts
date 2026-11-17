import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials live in android/key.properties (never committed).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "com.atc.palmaccess"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.atc.palmaccess"
        // VP530 SDK supports Android 7.0+ on the MTK board; Rockchip flavors raise this.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The vendor SDK only ships ARM native libraries.
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
    }

    flavorDimensions += "platform"
    productFlavors {
        create("mtk") {
            dimension = "platform"
            buildConfigField("int", "RECOGNIZE_TIMES", "3")
            buildConfigField("String", "PLATFORM", "\"MTK\"")
        }
        create("r3xxx") {
            dimension = "platform"
            minSdk = 25
            buildConfigField("int", "RECOGNIZE_TIMES", "3")
            buildConfigField("String", "PLATFORM", "\"Rockchip 3xxx\"")
        }
        create("r356x") {
            dimension = "platform"
            minSdk = 28
            buildConfigField("int", "RECOGNIZE_TIMES", "20")
            buildConfigField("String", "PLATFORM", "\"Rockchip 356x\"")
        }
    }

    sourceSets {
        getByName("r3xxx") { jniLibs.srcDirs("src/rk/jniLibs"); java.srcDirs("src/rk/kotlin") }
        getByName("r356x") { jniLibs.srcDirs("src/rk/jniLibs"); java.srcDirs("src/rk/kotlin") }
    }

    signingConfigs {
        create("release") {
            if (keystoreProperties.isNotEmpty()) {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildFeatures { buildConfig = true }
    // QA builds only (-PqaScreenshots): allow screenshots for on-device testing. Release builds keep FLAG_SECURE.
    defaultConfig.buildConfigField("boolean", "ALLOW_SCREENSHOTS", (project.hasProperty("qaScreenshots")).toString())

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.isNotEmpty())
                signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            pickFirsts += listOf("**/libJNI_Domo.so", "**/libjpeg-turbo1500.so", "**/libusb100.so", "**/libuvc.so", "**/libc++_shared.so")
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
    // HFSecurity VP530 palm-vein SDK (one per chipset).
    "mtkImplementation"(files("libs/mtk/vp530-android-sdk-v2.2.12-3xxx-mtk-260829.aar"))
    "r3xxxImplementation"(files("libs/r3xxx/vp530-android-sdk-v2.2.11-3xxx-260520.aar"))
    "r356xImplementation"(files("libs/r356x/vp530-android-sdk-v2.2.11-356x-260506.aar"))
    // UVC camera classes are bundled in the MTK AAR; Rockchip builds need the standalone jar.
    "r3xxxImplementation"(files("libs/uvc/lib-eyecool-uvccamera-v2.4.0.jar"))
    "r356xImplementation"(files("libs/uvc/lib-eyecool-uvccamera-v2.4.0.jar"))

    // Runtime dependencies required by the vendor SDK (latest API-compatible releases).
    implementation("org.greenrobot:greendao:3.3.0")
    implementation("com.github.yuweiguocn:GreenDaoUpgradeHelper:v2.2.1")
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("com.squareup.okhttp3:okhttp:3.14.9")

    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.zxing:core:3.5.3")
}
