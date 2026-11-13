plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.example.fieldservice"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.example.fieldservice"
        minSdk = 26
        targetSdk = 35
        versionCode = 12
        versionName = "1.3.0"
    }
}

dependencies {
    implementation("com.ditto:ditto-kotlin:5.2.0")
    implementation("androidx.lifecycle:lifecycle-viewmodel-ktx:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
