plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val ocrRuntime = layout.projectDirectory.dir("ocr_runtime")
val stagePdfOcr by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile)
    commandLine("python", "tools/stage_pdf_ocr.py")
}

android {
    namespace = "ai.artofficecraft.artofficecraft_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    sourceSets.named("main") {
        assets.srcDir(ocrRuntime.dir("assets"))
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ai.artofficecraft.artofficecraft_mobile"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            isDebuggable = false
            // The isolated publication job signs the unsigned release APK.
        }
    }
}

tasks.named("preBuild") {
    dependsOn(stagePdfOcr)
}

dependencies {
    implementation(files(ocrRuntime.file("tesseract4android-4.9.0.aar")).builtBy(stagePdfOcr))
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
