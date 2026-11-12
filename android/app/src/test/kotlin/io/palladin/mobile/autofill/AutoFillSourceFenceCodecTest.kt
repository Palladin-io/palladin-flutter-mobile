package io.palladin.mobile.autofill

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

class AutoFillSourceFenceCodecTest {
    private fun sign(bytes: ByteArray) = Mac.getInstance("HmacSHA256").run {
        init(SecretKeySpec(ByteArray(32) { 7 }, "HmacSHA256")); doFinal(bytes)
    }
    @Test fun `durable fence authenticates epoch profile and quarantine`() {
        val original = AutoFillSourceFence(12, "synthetic-profile", false)
        val encoded = AutoFillSourceFenceCodec.encode(original, ::sign)
        assertEquals(original, AutoFillSourceFenceCodec.decode(encoded, ::sign))
        for ((field, value) in listOf("epoch" to 13, "profile" to "other", "active" to true)) {
            val tampered = JSONObject(String(encoded)).put(field, value).toString().toByteArray()
            try { AutoFillSourceFenceCodec.decode(tampered, ::sign); fail("Accepted changed authority") }
            catch (_: IllegalArgumentException) {}
        }
    }
    @Test fun `independent membership and policy affect profile binding`() {
        val profile = AutoFillSourceProfile("principal", "organization", "1", "24h", 1, "a".repeat(64))
        val bindings = listOf(profile, profile.copy(principalId = "other"), profile.copy(organizationId = "other"),
            profile.copy(organizationMembershipGeneration = "2"), profile.copy(offlinePolicy = "1h"),
            profile.copy(offlinePolicyVersion = 2), profile.copy(profileBinding = "b".repeat(64))).map { it.digest() }
        assertEquals(bindings.size, bindings.toSet().size)
    }
    @Test fun `authenticated encrypted configuration survives process state loss and rejects tampering`() {
        val profile = AutoFillSourceProfile("member", "org", "1", "24h", 1, "a".repeat(64))
        val material = mapOf("accountId" to "member", "encryptedPrivateKey" to "synthetic-ciphertext",
            "kdf" to mapOf("securityVersion" to 2, "minimumSecurityVersion" to 1, "profileId" to "kdf",
                "kdfSalt" to "salt", "credentialRevision" to 4, "privateKeyWrapRevision" to 3))
        val config = AutoFillSourceConfiguration.create(profile, material)!!
        var persisted = AutoFillSourceFenceCodec.encode(AutoFillSourceFence(7, profile.digest(), true,
            config.accountUnlockDigest, config), ::sign)
        val restarted = AutoFillSourceAuthority({ AutoFillSourceFenceCodec.decode(persisted, ::sign) }, { error("Getter wrote state") })
        assertEquals(config.wire(), restarted.configuration(profile)?.wire())
        val tampered = JSONObject(String(persisted))
        tampered.getJSONObject("configuration").getJSONObject("accountUnlock").put("encryptedPrivateKey", "changed")
        persisted = tampered.toString().toByteArray()
        try { restarted.configuration(profile); fail("Returned unauthenticated account material") }
        catch (_: IllegalArgumentException) {}
        assertNull(AutoFillSourceConfiguration.create(profile, material + ("masterKey" to "not-persistable")))
        assertNull(AutoFillSourceConfiguration.create(profile, material + ("accessToken" to "not-persistable")))
    }
    @Test fun `legacy authenticated fence remains readable but cannot supply offline configuration`() {
        val body = JSONObject().put("version", 1).put("epoch", 3).put("profile", "legacy").put("active", true)
        val encoded = body.put("mac", java.util.Base64.getEncoder().encodeToString(sign(body.toString().toByteArray())))
            .toString().toByteArray()
        val decoded = AutoFillSourceFenceCodec.decode(encoded, ::sign)
        assertTrue(decoded.active)
        assertNull(decoded.accountUnlockDigest)
        assertNull(decoded.configuration)
    }

}
