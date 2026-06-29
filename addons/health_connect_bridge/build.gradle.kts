plugins {
    id("com.android.library") version "8.3.2"
    id("org.jetbrains.kotlin.android") version "2.1.0"
}

android {
    namespace = "com.parsec.healthconnect"
    compileSdk = 34

    defaultConfig {
        minSdk = 26  // Health Connect requires Android 8+
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    // Godot Android library — compile-only (Godot provides it at runtime).
    // Version format: <godot-version>.stable  e.g. 4.6.0.stable
    // If this fails, download godot-lib manually from Godot GitHub releases
    // and place in addons/health_connect_bridge/libs/
    compileOnly("org.godotengine:godot:4.6.0.stable")

    implementation("androidx.health.connect:connect-client:1.1.0-rc01")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
