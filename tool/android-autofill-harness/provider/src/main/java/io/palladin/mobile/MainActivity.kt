package io.palladin.mobile

import android.app.Activity
import android.os.Bundle
import android.widget.TextView
import io.palladin.mobile.autofill.AutoFillCacheStore
import java.time.Instant

/** Debug-only launcher seeds the real encrypted cache with synthetic records. */
class MainActivity : Activity() {
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
 }
}
