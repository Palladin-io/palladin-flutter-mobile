package io.palladin.mobile

import android.app.Activity
import android.app.ActivityManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import android.os.Bundle
import android.util.Size
import android.widget.inline.InlinePresentationSpec
import android.view.inputmethod.InlineSuggestionsRequest
import android.service.autofill.InlinePresentation
import androidx.autofill.inline.UiVersions
import androidx.autofill.inline.v1.InlineSuggestionUi
import io.palladin.mobile.autofill.carryAutofillInlineRequest
import android.content.Intent
import android.service.autofill.FillResponse
import android.service.autofill.Dataset
import android.view.autofill.AutofillValue
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.widget.EditText
import io.palladin.mobile.autofill.AutofillAuthenticationActivity
import android.widget.TextView
import io.palladin.mobile.autofill.AutoFillCacheStore
import java.time.Instant

/** Debug-only launcher seeds the real encrypted cache with synthetic records. */
class MainActivity : Activity() {
 private val phases = mutableListOf<String>()
 private var collectingDiagnostics = false
 private var expectInline = true
 private lateinit var expectedInlineSpec: InlinePresentationSpec
 private lateinit var expectedFields: Map<AutofillId, String>
 override fun onCreate(state: Bundle?) {
  super.onCreate(state)
  collectingDiagnostics = intent.getBooleanExtra("collectDiagnostics", false)
  if (collectingDiagnostics) {
   val inspectedPid = runCatching { File(filesDir, "synthetic-pid").readText().toInt() }.getOrNull()
   val exits = if (Build.VERSION.SDK_INT >= 30 && inspectedPid != null && inspectedPid > 0) {
    getSystemService(ActivityManager::class.java).getHistoricalProcessExitReasons(packageName, inspectedPid, 3)
     .map { JSONObject().put("reason", it.reason).put("status", it.status) }
   } else emptyList()
   File(filesDir, "synthetic-exits.json").writeText(JSONArray(exits).toString())
   finish()
   return
  }
  runCatching { File(filesDir, "synthetic-pid").writeText(android.os.Process.myPid().toString()) }
  recordPhase("CREATED")
  Thread.getDefaultUncaughtExceptionHandler()?.let { prior ->
   Thread.setDefaultUncaughtExceptionHandler(syntheticFailureHandler(prior) { recordPhase("UNCAUGHT", it) })
  }
  val status = runCatching {
   val store = AutoFillCacheStore(this)
   val session = store.beginSession()
   val issuedAt = Instant.now().minusSeconds(10)
   store.replace(mapOf(
    "version" to 2,
    "manifest" to mapOf("principalId" to "synthetic-member", "organizationId" to "synthetic-org",
     "organizationMembershipGeneration" to "1", "offlinePolicy" to "24h", "offlinePolicyVersion" to 1,
     "vaults" to listOf(mapOf("vaultId" to "synthetic-vault", "contextVersion" to 1,
      "memberId" to "synthetic-member", "memberKeyGeneration" to 1, "vaultKeyVersion" to 1,
      "memberRecipientKeyVersion" to 1, "memberRecipientKeyFingerprint" to "synthetic-fingerprint",
      "issuedAt" to issuedAt.toString(), "notAfter" to issuedAt.plusSeconds(86400).toString(),
      "entries" to listOf(mapOf("entryId" to "synthetic-entry", "revision" to "1", "keyVersion" to 1))))),
    "records" to listOf(mapOf("id" to "synthetic-entry", "organizationId" to "synthetic-org",
     "vaultId" to "synthetic-vault", "revision" to "1", "keyVersion" to 1,
     "label" to "Synthetic fixture", "username" to "synthetic-user", "password" to "synthetic-only-not-secret",
     "domains" to listOf("fixture.invalid")))
   ), session)
   "Synthetic encrypted cache ready"
  }.getOrElse { "Synthetic setup failed: " + it.javaClass.simpleName }
  setContentView(TextView(this).apply { text = status; textSize = 22f })
  if (status == "Synthetic encrypted cache ready") intent.getStringExtra("inspectResponse")?.let(::inspectResponse)
 }

 private fun inspectResponse(mode: String) {
  val usernameId = EditText(this).autofillId
  val passwordId = EditText(this).autofillId
  val usernames = if (mode.endsWith("empty")) arrayListOf() else arrayListOf(usernameId)
  val passwords = if (mode.endsWith("login") || mode == "native-username-manual-password") arrayListOf(passwordId) else arrayListOf()
  expectedFields = usernames.associateWith { "synthetic-user" } +
   passwords.associateWith { "synthetic-only-not-secret" }
  val inlineMode = intent.getStringExtra("inlineMode") ?: "supported"
  require(inlineMode in setOf("supported", "absent", "unsupported"))
  expectInline = inlineMode == "supported"
  val style = if (expectInline) UiVersions.newStylesBuilder().addStyle(InlineSuggestionUi.newStyleBuilder().build()).build() else Bundle()
  expectedInlineSpec = InlinePresentationSpec.Builder(Size(40, 40), Size(600, 80)).setStyle(style).build()
  recordPhase("AUTH_LAUNCHED")
  startActivityForResult(Intent(this, AutofillAuthenticationActivity::class.java).apply {
   if (inlineMode != "absent") {
    carryAutofillInlineRequest(this, InlineSuggestionsRequest.Builder(listOf(expectedInlineSpec)).setMaxSuggestionCount(1).build())
   }
   putExtra(AutofillAuthenticationActivity.EXTRA_ORIGIN_MODE, when {
    mode.startsWith("web") -> "WEB"
    mode == "native-username-manual-verified" -> "VERIFIED_NATIVE"
    else -> "MANUAL_NATIVE"
   })
   putExtra(AutofillAuthenticationActivity.EXTRA_USERNAME_CONFIRMATION, mode.contains("manual"))
   if (mode == "native-username-manual-verified") putStringArrayListExtra(
    AutofillAuthenticationActivity.EXTRA_NATIVE_DOMAINS, arrayListOf("fixture.invalid"))

   if (mode.startsWith("web")) {
    putExtra(AutofillAuthenticationActivity.EXTRA_DOMAIN, "fixture.invalid")
    if (mode != "web-missing") putExtra(
     AutofillAuthenticationActivity.EXTRA_WEB_SCHEME, if (mode == "web-http") "http" else "https",
    )
   }
   putExtra(AutofillAuthenticationActivity.EXTRA_PACKAGE_NAME, "io.palladin.autofill.harness.form")
   putParcelableArrayListExtra(AutofillAuthenticationActivity.EXTRA_USERNAME_IDS, usernames)
   putParcelableArrayListExtra(AutofillAuthenticationActivity.EXTRA_PASSWORD_IDS, passwords)
  }, 1)
 }

 @Suppress("DEPRECATION")
 override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
  super.onActivityResult(requestCode, resultCode, data)
  recordPhase("RESULT_STARTED")
  val result = data?.getParcelableExtra<android.os.Parcelable>(AutofillManager.EXTRA_AUTHENTICATION_RESULT)
  val direct = Build.VERSION.SDK_INT >= 31 && intent.getStringExtra("inspectResponse")?.startsWith("native") == true
  val response = result as? FillResponse
  @Suppress("UNCHECKED_CAST")
  val datasets = if (direct) listOfNotNull(result as? Dataset) else
   response?.let { it.javaClass.getMethod("getDatasets").invoke(it) as List<Dataset> }.orEmpty()
  val handoffVerified = if (direct) result is Dataset &&
   data?.getBooleanExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT_EPHEMERAL_DATASET, false) == true &&
   result.javaClass.getMethod("getAuthentication").invoke(result) == null
  else result is FillResponse && !data!!.hasExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT_EPHEMERAL_DATASET)
  val dataset = datasets.singleOrNull()
  @Suppress("UNCHECKED_CAST")
  val ids = dataset?.let { it.javaClass.getMethod("getFieldIds").invoke(it) as List<AutofillId> }.orEmpty()
  @Suppress("UNCHECKED_CAST")
  val values = dataset?.let { it.javaClass.getMethod("getFieldValues").invoke(it) as List<AutofillValue?> }.orEmpty()
  val inline = dataset?.let { it.javaClass.getMethod("getFieldInlinePresentation", Int::class.javaPrimitiveType).invoke(it, 0) as? InlinePresentation }
  val inlineContent = inline?.let { InlineSuggestionUi.fromSlice(it.slice) }
  val dropdown = dataset?.let { it.javaClass.getMethod("getFieldPresentation", Int::class.javaPrimitiveType).invoke(it, 0) }
  val inlineVerified = dropdown != null && if (expectInline) {
   inline != null && inline.inlinePresentationSpec == expectedInlineSpec &&
    inlineContent?.title?.toString() == "synthetic-user" &&
    inlineContent.subtitle?.toString() == "fixture.invalid" &&
    inlineContent.startIcon != null && inlineContent.contentDescription?.contains("Synthetic fixture") == true
  } else inline == null
  val verified = handoffVerified && inlineVerified && requestCode == 1 && resultCode == RESULT_OK && datasets.size == 1 &&
   ids.size == expectedFields.size && values.size == ids.size && ids.toSet() == expectedFields.keys &&
   ids.zip(values).all { (id, value) -> value?.textValue?.toString() == expectedFields[id] }
  val rejected = requestCode == 1 && resultCode == RESULT_CANCELED && result == null
  val status = if (intent.getStringExtra("inspectResponse") in setOf("web-http", "web-missing", "web-empty", "native-empty", "native-username-manual-password", "web-username-manual", "native-username-manual-cancel")) {
   "responseRejected=$rejected"
  } else "responseVerified=$verified"
  recordPhase(if (verified) "RESULT_VERIFIED" else if (rejected) "RESULT_REJECTED" else "RESULT_MISMATCH")
  setContentView(TextView(this).apply { text = status; textSize = 22f })
 }

 private fun recordPhase(phase: String, error: Throwable? = null) {
  if (collectingDiagnostics) return
  synchronized(phases) {
   phases += phase
   if (phases.size > 16) phases.removeAt(0)
   runCatching { File(filesDir, "synthetic-failure.json").writeText(syntheticFailureEvidence(phases, error).toString()) }
  }
 }

 override fun onResume() { super.onResume(); recordPhase("RESUMED") }
 override fun onStop() { recordPhase("STOPPED"); super.onStop() }
}
