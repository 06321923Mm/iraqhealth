import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

val keystorePropertiesFile = project.file("../key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

// مفتاح الخرائط: يُقرأ من android/local.properties أو من متغير البيئة MAPS_API_KEY (مثلاً في CI).
// إذا ظل فارغاً، GoogleMap تعرض لوحة رمادية فارغة في كل الشاشات.
val resolvedMapsApiKey: String =
    localProperties.getProperty("MAPS_API_KEY")
        ?: System.getenv("MAPS_API_KEY")
        ?: ""

android {
    namespace = "net.iraqhealth.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "net.iraqhealth.app"
        // Android 8.0 (Oreo) فما فوق
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
        manifestPlaceholders["MAPS_API_KEY"] = resolvedMapsApiKey
    }

    if (keystorePropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
