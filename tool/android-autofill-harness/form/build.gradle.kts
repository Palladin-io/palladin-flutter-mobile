plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
 namespace = "io.palladin.autofill.form"
 compileSdk = 36
 defaultConfig { applicationId = "io.palladin.autofill.harness.form"; minSdk = 28; targetSdk = 36; versionCode = 1; versionName = "synthetic" }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }

}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
dependencies {  }

androidComponents { beforeVariants(selector().withBuildType("release")) { it.enable = false } }
