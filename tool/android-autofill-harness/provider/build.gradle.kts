import javax.xml.parsers.DocumentBuilderFactory
import javax.xml.transform.TransformerFactory
import javax.xml.transform.dom.DOMSource
import javax.xml.transform.stream.StreamResult

plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
val templateManifest = file("src/main/AndroidManifest.xml")
val productionManifest = file("../../../android/app/src/main/AndroidManifest.xml")
val generatedManifest = layout.buildDirectory.file("generated/harness/AndroidManifest.xml")
val generateHarnessManifest = tasks.register("generateHarnessManifest") {
    inputs.files(templateManifest, productionManifest)
    outputs.file(generatedManifest)
    doLast {
        val parser = DocumentBuilderFactory.newInstance().apply { isNamespaceAware = true }.newDocumentBuilder()
        val document = parser.parse(templateManifest)
        val production = parser.parse(productionManifest)
        val queries = production.getElementsByTagName("queries").item(0)
        document.documentElement.appendChild(document.importNode(queries, true))
        val output = generatedManifest.get().asFile
        output.parentFile.mkdirs()
        TransformerFactory.newInstance().newTransformer().transform(DOMSource(document), StreamResult(output))
    }
}
tasks.configureEach { if (name == "preBuild") dependsOn(generateHarnessManifest) }

android {
 namespace = "io.palladin.mobile"
 compileSdk = 37
 defaultConfig { applicationId = "io.palladin.autofill.harness.provider"; minSdk = 28; targetSdk = 36; versionCode = 1; versionName = "synthetic" }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 sourceSets.getByName("main") {
 manifest.srcFile(generatedManifest)
 java.srcDir("../../../android/app/src/main/kotlin/io/palladin/mobile/autofill")
 res.srcDir("../../../android/app/src/main/res")
}

 sourceSets.getByName("test").java.srcDir("../../../android/app/src/test/kotlin/io/palladin/mobile/autofill")
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
dependencies { implementation("androidx.biometric:biometric:1.1.0")
 implementation("androidx.autofill:autofill:1.3.0")
    implementation("com.squareup.okhttp3:okhttp:5.5.1")
 testImplementation("junit:junit:4.13.2")
 testImplementation("org.mockito:mockito-core:5.20.0")
 testImplementation("org.json:json:20240303")
}

androidComponents { beforeVariants(selector().withBuildType("release")) { it.enable = false } }

// Only the platform streaming JSON reader runs outside the SDK's throwing JVM stubs.
val androidJsonRuntime by configurations.creating
 dependencies { androidJsonRuntime("org.robolectric:android-all:14-robolectric-10818077") }
val jsonReaderClasses = tasks.register<Copy>("jsonReaderClasses") {
    from({ zipTree(androidJsonRuntime.singleFile) })
    include("android/util/JsonReader*.class", "android/util/JsonToken.class", "android/util/JsonScope.class", "android/util/MalformedJsonException.class", "com/android/internal/util/StringPool.class")
    into(layout.buildDirectory.dir("json-reader-test-runtime"))
}
tasks.withType<Test>().configureEach {
    dependsOn(jsonReaderClasses)
    doFirst { classpath = files(jsonReaderClasses.get().destinationDir) + classpath }
}
