plugins {
id("com.android.application")
id("org.jetbrains.kotlin.android")
id("dev.flutter.flutter-gradle-plugin")
}

android {
namespace = "com.mafx.share"
compileSdk = flutter.compileSdkVersion
ndkVersion = flutter.ndkVersion

defaultConfig {
    applicationId = "com.mafx.share"
    minSdk = 23
    targetSdk = 35
    versionCode = 2
    versionName = "1.0.1"
}

compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlinOptions {
    jvmTarget = "17"
}

}

flutter {
source = "../.."
}
