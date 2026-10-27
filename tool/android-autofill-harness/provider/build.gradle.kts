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
 compileSdk = 36
 defaultConfig { applicationId = "io.palladin.autofill.harness.provider"; minSdk = 28; targetSdk = 36; versionCode = 1; versionName = "synthetic" }
 compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
 sourceSets.getByName("main") {
 manifest.srcFile(generatedManifest)
 java.srcDir("../../../android/app/src/main/kotlin/io/palladin/mobile/autofill")
 res.srcDir("../../../android/app/src/main/res")
}

}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
dependencies { implementation("androidx.biometric:biometric:1.1.0")
 implementation("androidx.autofill:autofill:1.3.0") }

androidComponents { beforeVariants(selector().withBuildType("release")) { it.enable = false } }
