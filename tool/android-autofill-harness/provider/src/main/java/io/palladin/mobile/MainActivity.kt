package io.palladin.mobile

import android.app.Activity
import android.os.Bundle
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
 private lateinit var expectedFields: Map<AutofillId, String>
 override fun onCreate(state: Bundle?) {
  super.onCreate(state)
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
  startActivityForResult(Intent(this, AutofillAuthenticationActivity::class.java).apply {
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
  val response = data?.getParcelableExtra<FillResponse>(AutofillManager.EXTRA_AUTHENTICATION_RESULT)
  @Suppress("UNCHECKED_CAST")
  val datasets = response?.let { it.javaClass.getMethod("getDatasets").invoke(it) as List<Dataset> }.orEmpty()
  val dataset = datasets.singleOrNull()
  @Suppress("UNCHECKED_CAST")
  val ids = dataset?.let { it.javaClass.getMethod("getFieldIds").invoke(it) as List<AutofillId> }.orEmpty()
  @Suppress("UNCHECKED_CAST")
  val values = dataset?.let { it.javaClass.getMethod("getFieldValues").invoke(it) as List<AutofillValue?> }.orEmpty()
  val verified = requestCode == 1 && resultCode == RESULT_OK && datasets.size == 1 &&
   ids.size == expectedFields.size && values.size == ids.size && ids.toSet() == expectedFields.keys &&
   ids.zip(values).all { (id, value) -> value?.textValue?.toString() == expectedFields[id] }
  val rejected = requestCode == 1 && resultCode == RESULT_CANCELED && response == null
  val status = if (intent.getStringExtra("inspectResponse") in setOf("web-http", "web-missing", "web-empty", "native-empty", "native-username-manual-password", "web-username-manual", "native-username-manual-cancel")) {
   "responseRejected=$rejected"
  } else "responseVerified=$verified"
  setContentView(TextView(this).apply { text = status; textSize = 22f })
 }
}
