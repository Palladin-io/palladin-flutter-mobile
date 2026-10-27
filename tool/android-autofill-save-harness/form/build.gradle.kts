plugins { id("com.android.application") }
android {
    namespace = "io.palladin.autofill.savefixture.form"
    compileSdk = 36
    defaultConfig {
        applicationId = "io.palladin.autofill.savefixture.form"
        minSdk = 31
        targetSdk = 36
        versionCode = 1
        versionName = "synthetic"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
androidComponents { beforeVariants(selector().withBuildType("release")) { it.enable = false } }
