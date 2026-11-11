import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val buildingTesting = gradle.startParameter.taskNames.any { it.substringAfterLast(':').matches(Regex("(?:assemble|bundle|install|compile|process|pre)Qa.*", RegexOption.IGNORE_CASE)) }
val productionProperties = Properties()
val productionPropertiesFile = rootProject.file("key.properties")
if (!buildingTesting && productionPropertiesFile.isFile) {
    productionPropertiesFile.inputStream().use { productionProperties.load(it) }
}

android {
    namespace = "com.distribuidoraalberdi.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.distribuidoraalberdi.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = productionProperties.getProperty("keyAlias")
            keyPassword = productionProperties.getProperty("keyPassword")
            storeFile = productionProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = productionProperties.getProperty("storePassword")
        }
    }

    flavorDimensions += "environment"
    productFlavors {
        create("production") {
            dimension = "environment"
            signingConfig = signingConfigs.getByName("release")
        }
        create("qa") {
            dimension = "environment"
            applicationIdSuffix = ".testing"
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

androidComponents {
    beforeVariants(selector().withFlavor("environment" to "qa")) { variant ->
        variant.enable = variant.buildType == "debug"
    }
    onVariants(selector().withFlavor("environment" to "qa")) { variant ->
        val abiByTarget = mapOf(
            "android-arm" to "armeabi-v7a",
            "android-arm64" to "arm64-v8a",
            "android-x64" to "x86_64",
        )
        val targets = providers.gradleProperty("target-platform").orNull
            ?.split(',').orEmpty()
        if (targets.isNotEmpty()) {
            val abis = targets.map { checkNotNull(abiByTarget[it]) }.toSet()
            val excluded = (abiByTarget.values.toSet() + "x86") - abis
            variant.packaging.jniLibs.excludes.addAll(excluded.map { "lib/$it/**" })
        }
    }
}

tasks.configureEach {
    // TESTING does not consume a Google Services configuration or resources.
    if (name.startsWith("processQa") && name.endsWith("GoogleServices")) {
        enabled = false
    }
    if (name == "preProductionReleaseBuild") {
        doFirst {
            check(listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
                .all { !productionProperties.getProperty(it).isNullOrBlank() }) {
                "Production release signing is required."
            }
        }
    }
    if (name == "preQaDebugBuild") {
        doFirst {
            val flutterRoot = rootProject.projectDir.parentFile
            val target = providers.gradleProperty("target").orNull
            check(target != null && flutterRoot.resolve(target).canonicalFile ==
                flutterRoot.resolve("lib/main_testing.dart").canonicalFile) {
                "Testing requires lib/main_testing.dart."
            }
            val entries = providers.gradleProperty("dart-defines").orNull.orEmpty()
                .split(',').filter { it.isNotEmpty() }.map {
                    String(Base64.getDecoder().decode(it), Charsets.UTF_8).split('=', limit = 2)
                }
            check(entries.all { it.size == 2 } &&
                entries.map { it[0] }.distinct().size == entries.size) {
                "Invalid or duplicate Dart defines."
            }
            val defines = entries.associate { it[0] to it[1] }
            check(defines["APP_ENV"] == "testing" &&
                defines["SUPABASE_TESTING_URL"] == "https://blcgugdeluzxvpwqkhjq.supabase.co" &&
                defines["SUPABASE_TESTING_KEY"]?.matches(Regex("sb_publishable_[A-Za-z0-9_-]{16,}")) == true &&
                defines["ENABLE_TESTING_DIRECT_SALES_V2"] == "true" &&
                defines["ENABLE_STOCK"] == "true" &&
                defines["ENABLE_INTERNAL_BOLETAS"] == "false" &&
                defines["USE_TESTING"] in listOf(null, "true")) {
                "Invalid Android TESTING profile."
            }
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
