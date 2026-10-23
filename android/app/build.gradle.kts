import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing: android/keystore.properties (untracked, see keystore.properties.example) if its storeFile exists,
// otherwise ~/.android/dirian-release.jks with its password from the macOS Keychain item "Dirian Android keystore".
val keystoreProperties = Properties().apply {
    rootProject.file("keystore.properties").takeIf { it.exists() }?.inputStream()?.use { load(it) }
}
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
val releaseStoreFile = File(
    keystoreProperties.getProperty("storeFile")?.takeIf { File(it).exists() }
        ?: "${System.getProperty("user.home")}/.android/dirian-release.jks"
)
val usePropertiesFile = keystoreProperties.getProperty("storeFile")?.let { File(it).exists() } == true

fun keychainPassword(): String? = runCatching {
    val process = ProcessBuilder("security", "find-generic-password", "-a", "dirian", "-s", "Dirian Android keystore", "-w").start()
    val password = process.inputStream.bufferedReader().readText().trim()
    password.takeIf { process.waitFor() == 0 && it.isNotEmpty() }
}.getOrNull()

val releaseStorePassword: String? = when {
    !releaseRequested || !releaseStoreFile.exists() -> null
    usePropertiesFile -> keystoreProperties.getProperty("storePassword")
    else -> keychainPassword()
}

android {
    namespace = "com.ikev.dirian"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.ikev.dirian"
        minSdk = 26
        targetSdk = 35
        versionCode = 4
        versionName = "0.2.2"
    }

    signingConfigs {
        if (releaseStorePassword != null) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = keystoreProperties.getProperty("keyAlias")?.takeIf { usePropertiesFile } ?: "dirian"
                keyPassword = keystoreProperties.getProperty("keyPassword")?.takeIf { usePropertiesFile } ?: releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfigs.findByName("release")?.let { signingConfig = it }
        }
    }

    buildFeatures {
        compose = true
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
    implementation(platform("androidx.compose:compose-bom:2024.09.03"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.6")
    implementation("androidx.core:core-ktx:1.13.1")
}
