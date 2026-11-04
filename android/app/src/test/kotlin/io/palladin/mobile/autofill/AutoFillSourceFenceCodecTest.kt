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
}
