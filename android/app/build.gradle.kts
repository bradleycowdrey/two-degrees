plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// The same version as the Mac and iPhone apps (VERSION at the repository root); the build number
// counts commits, so every build is newer than the last.
val repoRoot = rootDir.parentFile
val appVersion = repoRoot.resolve("VERSION").takeIf { it.exists() }?.readText()?.trim() ?: "0.0.0"
val buildNumber = providers.exec { commandLine("git", "rev-list", "--count", "HEAD"); isIgnoreExitValue = true }
    .standardOutput.asText.get().trim().toIntOrNull() ?: 1

// Release signing, from the environment (GitHub secrets) when there is a key; otherwise debug-signed.
val keystoreFile = System.getenv("ANDROID_KEYSTORE_FILE")?.let(::file)?.takeIf { it.exists() }

android {
    namespace = "com.bradcowdrey.twodegrees"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.bradcowdrey.twodegrees"
        minSdk = 26
        targetSdk = 35
        versionCode = buildNumber
        versionName = appVersion
    }

    signingConfigs {
        if (keystoreFile != null) {
            create("release") {
                storeFile = keystoreFile
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    // The offline city list is shared with the Mac and iPhone apps (Resources/Cities.tsv).
    sourceSets["main"].assets.srcDir(layout.buildDirectory.dir("generated/cities"))
    testOptions { unitTests.isReturnDefaultValues = true }
}

val copyCities by tasks.registering(Copy::class) {
    from(repoRoot.resolve("Resources/Cities.tsv"))
    into(layout.buildDirectory.dir("generated/cities"))
}
tasks.named("preBuild") { dependsOn(copyCities) }

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2025.04.01")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.glance:glance-appwidget:1.1.1")
    implementation("androidx.glance:glance-material3:1.1.1")
    implementation("androidx.work:work-runtime-ktx:2.10.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250107")
}
