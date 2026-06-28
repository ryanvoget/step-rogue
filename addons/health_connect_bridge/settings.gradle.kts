pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        // Godot's Maven repository (available since Godot 4.2)
        maven { url = uri("https://godotengine.org/maven") }
    }
}

rootProject.name = "HealthConnectBridge"
