plugins {
    id("com.android.application")
    // id("kotlin-android")
    id("org.jetbrains.kotlin.android")
    // Firebase Gradle plugin
    id("com.google.gms.google-services") version "4.4.2"
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.JavaVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {

    namespace = "me.zentha.dreamr"
    // compileSdk = flutter.compileSdkVersion
    compileSdk = 36
    // ndkVersion = flutter.ndkVersion
    ndkVersion = "27.0.12077973"

    // compileOptions {
    //     sourceCompatibility = JavaVersion.VERSION_11
    //     targetCompatibility = JavaVersion.VERSION_11
    // }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    
    lintOptions {
        disable("Instantiatable", "MissingClass")
    }

    kotlinOptions {
        // jvmTarget = JavaVersion.VERSION_11.toString()
        jvmTarget = "17" 
    }

    defaultConfig {
        applicationId = "me.zentha.dreamr"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk = flutter.minSdkVersion
        //targetSdk = flutter.targetSdkVersion
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = 14                        // also change in pubspec.yaml
        versionName = "1.0.8"                   // also change in pubspec.yaml
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    
    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    // implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk8:$kotlin_version"
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
