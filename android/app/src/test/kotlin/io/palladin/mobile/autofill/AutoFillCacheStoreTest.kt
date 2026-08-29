package io.palladin.mobile.autofill

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.json.JSONObject
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertThrows
import org.junit.Test

class AutoFillCacheStoreTest {
    @Test
    fun normalizeDomainRejectsAmbiguousHosts() {
        assertEquals("www.example.com", AutoFillCacheStore.normalizeDomain("WWW.Example.com."))
        assertNull(AutoFillCacheStore.normalizeDomain("localhost"))
        assertNull(AutoFillCacheStore.normalizeDomain("example..com"))
        assertNull(AutoFillCacheStore.normalizeDomain("https://example.com"))
        assertNull(AutoFillCacheStore.normalizeDomain("user@example.com"))
        assertNull(AutoFillCacheStore.normalizeDomain("example.com:443"))
        assertNull(AutoFillCacheStore.normalizeDomain("exаmple.com"))
        assertNull(AutoFillCacheStore.normalizeDomain("*.example.com"))
    }

    @Test
    fun domainMatchesExactHostsOnly() {
        assertTrue(AutoFillCacheStore.domainMatches("example.com", "example.com"))
        assertFalse(AutoFillCacheStore.domainMatches("login.example.com", "example.com"))
        assertFalse(AutoFillCacheStore.domainMatches("evil-example.com", "example.com"))
        assertFalse(AutoFillCacheStore.domainMatches("example.org", "example.com"))
    }

    @Test
    fun wallClockRollbackBeyondFiveMinutesFailsClosed() {
        assertEquals(1_000_000L, AutoFillClockPolicy.observe(1_000_000L, 700_000L))
        assertEquals(1_200_000L, AutoFillClockPolicy.observe(1_000_000L, 1_200_000L))
        assertThrows(IllegalArgumentException::class.java) {
            AutoFillClockPolicy.observe(1_000_000L, 699_999L)
        }
    }

    @Test
    fun frozenWallClockCannotExtendLeaseBeyondMonotonicTolerance() {
        val guard = AutoFillProcessClockGuard()
        guard.observe(wallTimeMillis = 1_000_000, elapsedTimeMillis = 10_000)
        guard.observe(wallTimeMillis = 1_000_000, elapsedTimeMillis = 310_000)
        assertThrows(IllegalArgumentException::class.java) {
            guard.observe(wallTimeMillis = 1_000_000, elapsedTimeMillis = 310_001)
        }
    }

    @Test
    fun slowlyAdvancingWallClockCannotTrailMonotonicTimeIndefinitely() {
        val guard = AutoFillProcessClockGuard()
        guard.observe(wallTimeMillis = 1_000_000, elapsedTimeMillis = 10_000)
        guard.observe(wallTimeMillis = 1_060_000, elapsedTimeMillis = 370_000)
        assertThrows(IllegalArgumentException::class.java) {
            guard.observe(wallTimeMillis = 1_060_000, elapsedTimeMillis = 370_001)
        }
    }

    @Test
    fun failedSessionClockBoundaryQuarantinesTheExistingActiveFence() {
        val guard = AutoFillProcessClockGuard()
        val fence = AutoFillFence(42, "active", 1_000_000)
        var quarantined = false
        AutoFillClockBoundary.observe(
            fence = fence,
            wallTimeMillis = 1_000_000,
            elapsedTimeMillis = 10_000,
            processGuard = guard,
            quarantine = { quarantined = true },
        )

        assertThrows(IllegalStateException::class.java) {
            AutoFillClockBoundary.observe(
                fence = fence,
                wallTimeMillis = 1_000_000,
                elapsedTimeMillis = 310_001,
                processGuard = guard,
                quarantine = { quarantined = true },
            )
        }
        assertTrue(quarantined)
    }

    @Test
    fun partialFenceOrIntegrityKeyDeletionCannotResetClockAuthority() {
        AutoFillStatePresencePolicy.requireConsistent(
            fenceExists = false,
            integrityKeyExists = false,
            generationArtifactExists = false,
        )
        AutoFillStatePresencePolicy.requireConsistent(
            fenceExists = true,
            integrityKeyExists = true,
            generationArtifactExists = true,
        )
        AutoFillStatePresencePolicy.requireConsistent(
            fenceExists = true,
            integrityKeyExists = true,
            generationArtifactExists = false,
        )
        assertThrows(IllegalArgumentException::class.java) {
            AutoFillStatePresencePolicy.requireConsistent(
                fenceExists = false,
                integrityKeyExists = true,
                generationArtifactExists = false,
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            AutoFillStatePresencePolicy.requireConsistent(
                fenceExists = true,
                integrityKeyExists = false,
                generationArtifactExists = true,
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            AutoFillStatePresencePolicy.requireConsistent(
                fenceExists = false,
                integrityKeyExists = false,
                generationArtifactExists = true,
            )
        }

        val guard = AutoFillProcessClockGuard()
        val forwardFence = AutoFillFence(43, "active", 2_000_000)
        var quarantined = false
        AutoFillClockBoundary.observe(
            fence = forwardFence,
            wallTimeMillis = 2_000_000,
            elapsedTimeMillis = 20_000,
            processGuard = guard,
            quarantine = { quarantined = true },
        )
        assertThrows(IllegalStateException::class.java) {
            AutoFillClockBoundary.observe(
                fence = forwardFence,
                wallTimeMillis = 1_699_999,
                elapsedTimeMillis = 20_001,
                processGuard = guard,
                quarantine = { quarantined = true },
            )
        }
        assertTrue(quarantined)
    }

    @Test
    fun externalFenceTimestampMutationCannotExtendTheLease() {
        val fence = AutoFillFence(
            generation = 42,
            state = "active",
            maximumObservedWallTimeMillis = 1_000_000,
        )
        val encoded = AutoFillFenceCodec.encode(fence, ::testFenceMac)
        val tampered = JSONObject(String(encoded, Charsets.UTF_8))
            .put("maximumObservedWallTimeMillis", 1)
            .toString()

        assertThrows(IllegalArgumentException::class.java) {
            AutoFillFenceCodec.decode(tampered, ::testFenceMac)
        }
    }

    @Test
    fun revokeBetweenDecryptAndProviderHandoffFailsRevalidation() {
        val active = AutoFillFence(42, "active", 1_000_000)
        AutoFillFencePolicy.requireActive(active, 42)
        assertThrows(IllegalArgumentException::class.java) {
            AutoFillFencePolicy.requireActive(active.copy(state = "revoked"), 42)
        }
        assertThrows(IllegalArgumentException::class.java) {
            AutoFillFencePolicy.requireActive(active.copy(generation = 43), 42)
        }
    }

    @Test
    fun revokeCannotCommitBetweenFinalValidationAndProviderHandoff() {
        val handoffEntered = CountDownLatch(1)
        val releaseHandoff = CountDownLatch(1)
        val revokeEntered = CountDownLatch(1)
        val handoff = Thread {
            AutoFillHandoffGate.run(validate = {}) {
                handoffEntered.countDown()
                check(releaseHandoff.await(2, TimeUnit.SECONDS))
            }
        }
        handoff.start()
        assertTrue(handoffEntered.await(2, TimeUnit.SECONDS))

        val revoke = Thread {
            synchronized(AutoFillMutationLock.monitor) {
                revokeEntered.countDown()
            }
        }
        revoke.start()
        assertFalse(revokeEntered.await(100, TimeUnit.MILLISECONDS))

        releaseHandoff.countDown()
        assertTrue(revokeEntered.await(2, TimeUnit.SECONDS))
        handoff.join(2_000)
        revoke.join(2_000)
        assertFalse(handoff.isAlive)
        assertFalse(revoke.isAlive)
    }

    @Test
    fun v2PayloadBindsRecordToIndependentManifestAuthority() {
        val payload = validPayload()
        val records = AutoFillCachePayloadValidator.validate(
            payload,
            nowMillis = 1_787_990_400_000,
        )
        assertEquals(listOf("entry-1"), records.map(CachedCredential::id))

        payload.getJSONArray("records").getJSONObject(0).put("revision", "13")
        assertThrows(IllegalArgumentException::class.java) {
            AutoFillCachePayloadValidator.validate(payload, 1_787_990_400_000)
        }
    }

    @Test
    fun v1PayloadWithoutLeaseIsRejected() {
        val payload = JSONObject()
            .put("version", 1)
            .put("records", validPayload().getJSONArray("records"))
        assertThrows(IllegalArgumentException::class.java) {
            AutoFillCachePayloadValidator.validate(payload, 1_787_990_400_000)
        }
    }

    @Test
    fun futureIssuedLeaseIsRejectedOnFirstInstall() {
        val payload = validPayload()
        val vault = payload.getJSONObject("manifest").getJSONArray("vaults").getJSONObject(0)
        vault.put("issuedAt", "2026-08-29T09:00:00Z")
        vault.put("notAfter", "2026-08-30T09:00:00Z")

        assertThrows(IllegalArgumentException::class.java) {
            AutoFillCachePayloadValidator.validate(payload, 1_787_985_000_000)
        }
    }

    @Test
    fun manifestCannotAuthorizeAnUnrepresentedExtraEntry() {
        val payload = validPayload()
        val entries = payload.getJSONObject("manifest")
            .getJSONArray("vaults").getJSONObject(0).getJSONArray("entries")
        entries.put(JSONObject().put("entryId", "entry-2").put("revision", "1").put("keyVersion", 1))

        assertThrows(IllegalArgumentException::class.java) {
            AutoFillCachePayloadValidator.validate(payload, 1_787_985_000_000)
        }
    }

    private fun validPayload(): JSONObject = JSONObject(
        """
        {
          "version": 2,
          "manifest": {
            "principalId": "member-1",
            "organizationId": "org-1",
            "organizationMembershipGeneration": "7",
            "offlinePolicy": "24h",
            "offlinePolicyVersion": 1,
            "vaults": [{
              "vaultId": "vault-1",
              "contextVersion": 1,
              "memberId": "member-1",
              "memberKeyGeneration": 4,
              "vaultKeyVersion": 3,
              "memberRecipientKeyVersion": 2,
              "memberRecipientKeyFingerprint": "fixture-fingerprint",
              "issuedAt": "2026-08-29T08:00:00Z",
              "notAfter": "2026-08-30T08:00:00Z",
              "entries": [{"entryId":"entry-1","revision":"12","keyVersion":5}]
            }]
          },
          "records": [{
            "id":"entry-1",
            "organizationId":"org-1",
            "vaultId":"vault-1",
            "revision":"12",
            "keyVersion":5,
            "label":"Fixture",
            "username":"fixture-user",
            "password":"not-a-real-password",
            "domains":["fixture.invalid"]
          }]
        }
        """.trimIndent(),
    )

    private fun testFenceMac(fence: AutoFillFence): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(ByteArray(32) { 7 }, "HmacSHA256"))
            doFinal(
                (
                    "palladin-autofill-fence-v2:${fence.generation}:${fence.state}:" +
                        fence.maximumObservedWallTimeMillis
                    ).toByteArray(Charsets.UTF_8),
            )
        }
}
