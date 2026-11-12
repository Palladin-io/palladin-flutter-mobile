package io.palladin.mobile.autofill

import org.junit.Assert.*
import org.junit.Test

class AutoFillSourceAdoptionTest {
    private fun material(): Map<String, Any> = mapOf(
        "accountId" to "member", "encryptedPrivateKey" to "synthetic-ciphertext",
        "kdf" to mapOf("securityVersion" to 2, "minimumSecurityVersion" to 1,
            "profileId" to "synthetic-profile", "kdfSalt" to "synthetic-salt",
            "credentialRevision" to 4, "privateKeyWrapRevision" to 3),
    )
    private val profile = AutoFillSourceProfile("member", "org", "1", "24h", 1, "a".repeat(64))
    private val claims get() = profile.digest()
    private fun config() = AutoFillSourceConfiguration.create(profile, material())!!
    private var disk: AutoFillSourceFence? = null
    private fun store() = AutoFillSourceAuthority({ disk }, { disk = it })
    @Test fun `only exact active account material adopts with explicit permission`() {
        val account = config()
        val first = store()
        val original = first.begin(claims, "old", account, true)
        first.activate("old", original)
        val restarted = store()
        val adopted = restarted.begin(claims, "new", account, false)
        assertTrue(adopted > original)
        assertTrue(restarted.current(claims, "new", adopted))
        val unchanged = restarted.snapshot()
        assertEquals(adopted, restarted.activate("new", adopted))
        assertEquals(unchanged, restarted.snapshot())
        assertFalse(restarted.current(claims, "old", original))
        val forced = restarted.begin(claims, "forced", account, true)
        assertFalse(restarted.current(claims, "forced", forced))
        restarted.activate("forced", forced)
        val omitted = restarted.begin(claims, "default", account)
        assertFalse(restarted.current(claims, "default", omitted))
    }
    @Test fun `unknown revoked changed account or claims never adopts`() {
        val account = config()
        for (scenario in listOf("missing", "legacy", "revoked", "account", "claims", "null-material")) {
            disk = when (scenario) {
                "missing" -> null
                "legacy" -> AutoFillSourceFence(7, claims, true)
                "revoked" -> AutoFillSourceFence(7, claims, false, account.accountUnlockDigest, account)
                else -> AutoFillSourceFence(7, claims, true, account.accountUnlockDigest, account)
            }
            val source = store()
            val supplied = when (scenario) {
                "account" -> AutoFillSourceConfiguration.create(profile, material() + ("encryptedPrivateKey" to "changed"))
                "claims" -> AutoFillSourceConfiguration.create(profile.copy(offlinePolicyVersion = 2), material())
                "null-material" -> null
                else -> account
            }
            val expected = supplied?.profile?.digest() ?: claims
            val epoch = source.begin(expected, "new", supplied, false)
            assertFalse(scenario, source.current(expected, "new", epoch))
        }
    }
    @Test fun `every canonical unlock field binds adoption and missing or unknown fields cannot prove equality`() {
        val baseline = material()
        val expected = AutoFillAccountUnlockDigest.from(baseline, "member")!!
        assertEquals(expected, AutoFillAccountUnlockDigest.from(baseline.toList().reversed().toMap(), "member"))
        assertNull(AutoFillAccountUnlockDigest.from(baseline, "different-member"))
        assertNull(AutoFillAccountUnlockDigest.from(baseline - "encryptedPrivateKey", "member"))
        assertNull(AutoFillAccountUnlockDigest.from(baseline + ("unknown" to "value"), "member"))
        assertNotEquals(expected, AutoFillAccountUnlockDigest.from(baseline + ("encryptedPrivateKey" to "changed"), "member"))
        @Suppress("UNCHECKED_CAST") val kdf = baseline["kdf"] as Map<String, Any>
        for ((field, value) in kdf) {
            val changed = if (value is Int) value + 1 else "$value-changed"
            assertNotEquals(field, expected, AutoFillAccountUnlockDigest.from(baseline + ("kdf" to (kdf + (field to changed))), "member"))
            assertNull(field, AutoFillAccountUnlockDigest.from(baseline + ("kdf" to (kdf - field)), "member"))
        }
        assertNotEquals(expected, AutoFillAccountUnlockDigest.from(baseline + ("kdf" to (kdf + ("deviceWrapperMetadata" to "changed"))), "member"))
        assertNull(AutoFillAccountUnlockDigest.from(baseline + ("kdf" to (kdf + ("unknown" to "value"))), "member"))
    }
    @Test fun `cold configuration getter requires active protected material and every independent claim`() {
        val source = store()
        val initial = source.begin(claims, "session", config())
        assertNull(store().configuration(profile))
        source.activate("session", initial)
        assertEquals(config().wire(), store().configuration(profile)?.wire())
        for (changed in listOf(profile.copy(principalId = "other"), profile.copy(organizationId = "other"),
            profile.copy(organizationMembershipGeneration = "2"), profile.copy(offlinePolicy = "1h"),
            profile.copy(offlinePolicyVersion = 2), profile.copy(profileBinding = "b".repeat(64)))) {
            assertNull(store().configuration(changed))
        }
        source.invalidate("session", initial)
        assertNull(store().configuration(profile))
        disk = AutoFillSourceFence(8, claims, true)
        assertNull(store().configuration(profile))
        disk = null
        assertNull(store().configuration(profile))
    }

}
