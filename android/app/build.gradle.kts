import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing values, from the gitignored android/key.properties (see
// key.properties.example). Without that file release builds are debug-signed.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties: Properties? =
    if (keyPropertiesFile.exists()) {
        Properties().apply { keyPropertiesFile.inputStream().use { load(it) } }
    } else {
        null
    }

fun signingValue(properties: Properties, name: String): String =
    properties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException("android/key.properties has no value for $name")

android {
    namespace = "io.github.bbglind.tvplayer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.github.bbglind.tvplayer"
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

    signingConfigs {
        if (keyProperties != null) {
            create("release") {
                val path = signingValue(keyProperties, "storeFile")
                val keystore =
                    if (path.startsWith("~/")) {
                        file(System.getProperty("user.home") + path.substring(1))
                    } else {
                        file(path)
                    }
                if (!keystore.isFile) {
                    throw GradleException("android/key.properties: storeFile $path does not exist")
                }
                storeFile = keystore
                storePassword = signingValue(keyProperties, "storePassword")
                keyAlias = signingValue(keyProperties, "keyAlias")
                keyPassword = signingValue(keyProperties, "keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Debug keys without key.properties, so `flutter run --release`
            // still works for others.
            signingConfig = signingConfigs.getByName(if (keyProperties != null) "release" else "debug")
        }
    }
}

if (keyProperties == null &&
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
) {
    // Not logger.warn: Flutter runs Gradle with -q, which hides warnings.
    logger.quiet(
        "WARNING: android/key.properties not found, this release build is " +
            "DEBUG-SIGNED. Don't publish it (see docs/releasing.md).",
    )
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
