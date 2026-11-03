package io.palladin.mobile.autofill

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class AutoFillIncrementalCacheTest {
    @Test fun globalDenialThenSingleUpdateRetains159CiphertextsWithoutOpeningThem() {
        val directory = Files.createTempDirectory("autofill-v3-test").toFile()
        var fence = AutoFillFence(7, "active", NOW)
        var bodyEncryptions = 0
        var bodyDecryptions = 0
        val cache = AutoFillIncrementalCache(directory, { fence }, { fence = it }, { _, key -> key.copyOf() },
            { NOW }, { target, bytes -> target.writeBytes(bytes) }, onRecordCrypto = { encrypt ->
                if (encrypt) bodyEncryptions++ else bodyDecryptions++
            })
        try {
            val epoch = cache.beginWriterSession(7)
            val first = cache.replace(payload(160), 7, epoch)
            val denied = cache.deny(JSONObject().put("base", first).put("writerEpoch", epoch)
                .put("entries", JSONArray((0 until 160).map { JSONObject().put("vaultId", "vault").put("entryId", "entry-$it") })))
            assertEquals(0, fence.availableRecords)
            val originalFiles = directory.listFiles()!!.associate { it.name to it.readBytes() }
            bodyEncryptions = 0
            val updated = payload(160)
            updated.getJSONObject("manifest").getJSONArray("vaults").getJSONObject(0)
                .getJSONArray("entries").getJSONObject(0).put("revision", "2")
            val changed = updated.getJSONArray("records").getJSONObject(0).put("revision", "2").put("password", "synthetic-new")
            val second = cache.applyDelta(JSONObject().put("base", denied.getJSONObject("base")).put("writerEpoch", epoch)
                .put("manifest", updated.getJSONObject("manifest")).put("upserts", JSONArray().put(changed))
                .put("removals", JSONArray()).put("releasingDenies", JSONArray().put(denied.getString("denyToken"))))
            assertEquals(1, bodyEncryptions)
            assertEquals(0, bodyDecryptions)
            assertEquals(denied.getJSONObject("base").getLong("revision") + 1, second.getLong("revision"))
            assertEquals(160, fence.availableRecords)
            assertEquals(159, originalFiles.filterKeys { it.contains("record") }.count { (name, bytes) -> directory.resolve(name).isFile && directory.resolve(name).readBytes().contentEquals(bytes) })
        } finally { directory.deleteRecursively() }
    }

    @Test fun scopedDenialRejectsOldPickerAndDeletionProducesValidEmptyBase() = fixture { cache, fence, key ->
        val epoch = cache.beginWriterSession(7)
        val base = cache.replace(payload(1), 7, epoch)
        val selected = cache.readWithAuthenticatedKey(fence(), key())
        val denied = cache.deny(JSONObject().put("base", base).put("writerEpoch", epoch)
            .put("entries", JSONArray().put(JSONObject().put("vaultId", "vault").put("entryId", "entry-0"))))
        assertThrows(IllegalArgumentException::class.java) { cache.requireCurrentRevision(7, selected.single().catalogRevision) }
        assertTrue(cache.readWithAuthenticatedKey(fence(), key()).isEmpty())
        val empty = cache.applyDelta(JSONObject().put("base", denied.getJSONObject("base")).put("writerEpoch", epoch)
            .put("manifest", payload(0).getJSONObject("manifest")).put("upserts", JSONArray())
            .put("removals", JSONArray().put(JSONObject().put("vaultId", "vault").put("entryId", "entry-0")))
            .put("releasingDenies", JSONArray().put(denied.getString("denyToken"))))
        assertTrue(empty.getLong("revision") > 0)
        assertTrue(cache.readWithAuthenticatedKey(fence(), key()).isEmpty())
        assertEquals(0, fence().availableRecords)
    }

    @Test fun lockPreventsPendingCommitWithoutRevokingProvider() {
        val directory = Files.createTempDirectory("autofill-v3-lock").toFile()
        var fence = AutoFillFence(7, "active", NOW)
        var shouldLock = false
        var epoch = 0L
        lateinit var cache: AutoFillIncrementalCache
        cache = AutoFillIncrementalCache(directory, { fence }, { fence = it }, { _, key -> key.copyOf() },
            { NOW }, { file, bytes -> file.writeBytes(bytes) }, beforeCommit = { if (shouldLock) cache.endWriterSession(epoch) })
        try {
            epoch = cache.beginWriterSession(7)
            val base = cache.replace(payload(1), 7, epoch)
            shouldLock = true
            assertThrows(AutoFillIncrementalException::class.java) { cache.replace(payload(1), 7, epoch, base) }
            assertEquals(base.getLong("revision"), fence.catalogRevision)
            assertEquals("active", fence.state)
        } finally { directory.deleteRecursively() }
    }

    @Test fun missingBaseAndEndedWriterNeverInstallDelta() = fixture { cache, fence, _ ->
        val epoch = cache.beginWriterSession(7)
        val missing = JSONObject().put("generation", 7).put("revision", 1)
        val args = JSONObject().put("base", missing).put("writerEpoch", epoch)
            .put("manifest", payload(1).getJSONObject("manifest")).put("upserts", JSONArray()).put("removals", JSONArray()).put("releasingDenies", JSONArray())
        assertThrows(AutoFillIncrementalException::class.java) { cache.applyDelta(args) }
        assertEquals(0, fence().catalogRevision)
        cache.replace(payload(1), 7, epoch)
        cache.endWriterSession(epoch)
        assertThrows(AutoFillIncrementalException::class.java) { cache.applyDelta(args) }
    }

    @Test fun expiredBaseRequiresRecoveryWithoutChangingFence() {
        val directory = Files.createTempDirectory("autofill-v3-expired-base").toFile()
        var fence = AutoFillFence(7, "active", NOW)
        var time = NOW
        val cache = AutoFillIncrementalCache(directory, { fence }, { fence = it }, { _, key -> key.copyOf() },
            { time }, { file, bytes -> file.writeBytes(bytes) })
        try {
            val epoch = cache.beginWriterSession(7)
            val base = cache.replace(payload(1), 7, epoch)
            val denial = cache.deny(JSONObject().put("base", base).put("writerEpoch", epoch)
                .put("entries", JSONArray().put(JSONObject().put("vaultId", "vault").put("entryId", "entry-0"))))
            val deniedBase = denial.getJSONObject("base")
            time = java.time.Instant.parse("2026-08-30T08:00:00Z").toEpochMilli()
            val failure = assertThrows(AutoFillIncrementalException::class.java) {
                cache.applyDelta(delta(deniedBase, epoch, payload(1).getJSONObject("manifest"))
                    .put("releasingDenies", JSONArray().put(denial.getString("denyToken"))))
            }
            assertEquals("AUTOFILL_FULL_RECOVERY_REQUIRED", failure.code)
            assertEquals(deniedBase.getLong("revision"), fence.catalogRevision)
            assertEquals(0, fence.availableRecords)
        } finally { directory.deleteRecursively() }
    }

    @Test fun emptyPointerRecoveryKeepsRevisionAndRejectsOldPicker() {
        val directory = Files.createTempDirectory("autofill-v3-recovery").toFile()
        var fence = AutoFillFence(7, "active", NOW)
        val cache = AutoFillIncrementalCache(directory, { fence }, { fence = it }, { _, key -> key.copyOf() },
            { NOW }, { file, bytes -> file.writeBytes(bytes) })
        try {
            val firstEpoch = cache.beginWriterSession(7)
            val old = cache.replace(payload(1), 7, firstEpoch)
            cache.invalidateWriter(7)
            fence = fence.copy(catalogRevision = fence.catalogRevision + 1, catalogFile = "", catalogDigest = "", wrappedKey = "", availableRecords = 0)
            val epoch = cache.beginWriterSession(7)
            cache.invalidateWriter(6) // A delayed clear from an old generation cannot close this writer.
            cache.endWriterSession(firstEpoch)
            val current = cache.replace(payload(1), 7, epoch)
            assertTrue(current.getLong("revision") > old.getLong("revision"))
            assertThrows(IllegalArgumentException::class.java) { cache.requireCurrentRevision(7, old.getLong("revision")) }
        } finally { directory.deleteRecursively() }
    }

    private fun fixture(action: (AutoFillIncrementalCache, () -> AutoFillFence, () -> ByteArray) -> Unit) {
        val directory = Files.createTempDirectory("autofill-v3-test").toFile()
        var fence = AutoFillFence(7, "active", NOW)
        var openingKey = ByteArray(0)
        val cache = AutoFillIncrementalCache(directory, { fence }, { fence = it }, { _, key -> openingKey = key.copyOf(); key.copyOf() },
            { NOW }, { file, bytes -> file.writeBytes(bytes) })
        try { action(cache, { fence }, { openingKey.copyOf() }) } finally { openingKey.fill(0); directory.deleteRecursively() }
    }

    @Test fun v3FenceAuthenticatesCatalogPointerAndWrappedKey() {
        val fence = AutoFillFence(7, "active", NOW, 4, "palladin_autofill_v3_catalog_00000000-0000-0000-0000-000000000000", "digest", "wrapped", 1)
        val encoded = AutoFillFenceCodec.encode(fence) { value ->
            java.security.MessageDigest.getInstance("SHA-256").digest(value.toString().toByteArray())
        }
        val raw = JSONObject(String(encoded))
        assertEquals(3, raw.getInt("version"))
        assertEquals(fence, AutoFillFenceCodec.decode(String(encoded)) { value ->
            java.security.MessageDigest.getInstance("SHA-256").digest(value.toString().toByteArray())
        })
        raw.put("catalogRevision", 5)
        assertThrows(IllegalArgumentException::class.java) {
            AutoFillFenceCodec.decode(raw.toString()) { value -> java.security.MessageDigest.getInstance("SHA-256").digest(value.toString().toByteArray()) }
        }
    }

    @Test fun leaseExpiringDuringEncryptionCannotBeAcknowledged() {
        val directory = Files.createTempDirectory("autofill-v3-expiry").toFile()
        var fence = AutoFillFence(7, "active", NOW)
        var currentTime = NOW
        val expiry = java.time.Instant.parse("2026-08-30T08:00:00Z").toEpochMilli()
        val cache = AutoFillIncrementalCache(directory, { fence }, { fence = it }, { _, key -> key.copyOf() },
            { currentTime }, { file, bytes -> file.writeBytes(bytes) }, beforeCommit = { currentTime = expiry })
        try {
            val epoch = cache.beginWriterSession(7)
            assertThrows(Exception::class.java) { cache.replace(payload(1), 7, epoch) }
            assertEquals(0, fence.catalogRevision)
        } finally { directory.deleteRecursively() }
    }

    @Test fun fullReplacementCannotEraseAnotherDenialOwner() = fixture { cache, fence, _ ->
        val epoch = cache.beginWriterSession(7)
        val first = cache.replace(payload(1), 7, epoch)
        val denied = cache.deny(JSONObject().put("base", first).put("writerEpoch", epoch)
            .put("entries", JSONArray().put(JSONObject().put("vaultId", "vault").put("entryId", "entry-0"))))
        assertThrows(Exception::class.java) { cache.replace(payload(1), 7, epoch) }
        assertThrows(Exception::class.java) { cache.replace(payload(1), 7, epoch, denied.getJSONObject("base")) }
        assertEquals(0, fence().availableRecords)
        val next = cache.replace(payload(1), 7, epoch, denied.getJSONObject("base"), JSONArray().put(denied.getString("denyToken")))
        assertEquals(1, fence().availableRecords)
        assertTrue(next.getLong("revision") > denied.getJSONObject("base").getLong("revision"))
    }

    @Test fun changedScopeCannotReuseOldCiphertext() = fixture { cache, fence, _ ->
        val epoch = cache.beginWriterSession(7)
        val first = cache.replace(payload(1), 7, epoch)
        val altered = payload(1).getJSONObject("manifest")
        altered.getJSONArray("vaults").getJSONObject(0).put("vaultKeyVersion", 2)
        assertThrows(Exception::class.java) { cache.applyDelta(delta(first, epoch, altered)) }
        assertEquals(first.getLong("revision"), fence().catalogRevision)
    }

    @Test fun overlappingDenialsStayOwnedAfterDeletion() = fixture { cache, fence, _ ->
        val epoch = cache.beginWriterSession(7)
        val first = cache.replace(payload(1), 7, epoch)
        fun deny(base: JSONObject) = cache.deny(JSONObject().put("base", base).put("writerEpoch", epoch)
            .put("entries", JSONArray().put(JSONObject().put("vaultId", "vault").put("entryId", "entry-0"))))
        val a = deny(first)
        val b = deny(a.getJSONObject("base"))
        fun remove(base: JSONObject, token: String) = cache.applyDelta(delta(base, epoch, payload(0).getJSONObject("manifest"))
            .put("removals", JSONArray().put(JSONObject().put("vaultId", "vault").put("entryId", "entry-0")))
            .put("releasingDenies", JSONArray().put(token)))
        val removed = remove(b.getJSONObject("base"), a.getString("denyToken"))
        assertThrows(Exception::class.java) { cache.replace(payload(0), 7, epoch, removed) }
        val reconciled = remove(removed, b.getString("denyToken"))
        assertEquals(0, fence().availableRecords)
        assertTrue(reconciled.getLong("revision") > removed.getLong("revision"))
    }

    @Test fun releasingRetainedDenialRejectsChangedMissingAuthorityAndUnknownOwner() = fixture { cache, fence, _ ->
        val epoch = cache.beginWriterSession(7)
        val first = cache.replace(payload(1), 7, epoch)
        val denied = cache.deny(JSONObject().put("base", first).put("writerEpoch", epoch)
            .put("entries", JSONArray().put(JSONObject().put("vaultId", "vault").put("entryId", "entry-0"))))
        val base = denied.getJSONObject("base")
        val token = denied.getString("denyToken")
        fun attempt(manifest: JSONObject, owner: String = token) = cache.applyDelta(
            delta(base, epoch, manifest).put("releasingDenies", JSONArray().put(owner)))
        val changed = payload(1).getJSONObject("manifest")
        changed.getJSONArray("vaults").getJSONObject(0).getJSONArray("entries").getJSONObject(0).put("revision", "2")
        assertThrows(Exception::class.java) { attempt(changed) }
        assertThrows(Exception::class.java) { attempt(payload(0).getJSONObject("manifest")) }
        assertThrows(Exception::class.java) { attempt(payload(1).getJSONObject("manifest"), "unowned") }
        assertEquals(base.getLong("revision"), fence().catalogRevision)
        assertEquals(0, fence().availableRecords)
    }

    private fun delta(base: JSONObject, epoch: Long, manifest: JSONObject) = JSONObject().put("base", base).put("writerEpoch", epoch)
        .put("manifest", manifest).put("upserts", JSONArray()).put("removals", JSONArray()).put("releasingDenies", JSONArray())

    @Test fun providerCannotUseWriterKeyWithoutAuthenticatedOpeningKey() = fixture { cache, fence, key ->
        val epoch = cache.beginWriterSession(7)
        cache.replace(payload(1), 7, epoch)
        assertThrows(Exception::class.java) { cache.readWithAuthenticatedKey(fence(), ByteArray(32)) }
        assertEquals(1, cache.readWithAuthenticatedKey(fence(), key()).size)
        cache.endWriterSession(epoch)
        assertEquals(1, cache.readWithAuthenticatedKey(fence(), key()).size)
    }

    @Test fun renewingCatalogDoesNotExtendOriginalRecordLease() = fixture { cache, fence, key ->
        val epoch = cache.beginWriterSession(7)
        val base = cache.replace(payload(1), 7, epoch)
        val manifest = payload(1).getJSONObject("manifest")
        manifest.getJSONArray("vaults").getJSONObject(0)
            .put("issuedAt", "2026-08-29T08:01:00Z").put("notAfter", "2026-08-30T08:01:00Z")
        cache.applyDelta(delta(base, epoch, manifest))
        assertEquals(java.time.Instant.parse("2026-08-30T08:00:00Z").toEpochMilli(),
            cache.readWithAuthenticatedKey(fence(), key()).single().notAfterMillis)
    }

    @Test fun stagedWriteFailureLeavesOldAuthorizedBaseAndBodies() {
        val directory = Files.createTempDirectory("autofill-v3-fault").toFile()
        var fence = AutoFillFence(7, "active", NOW)
        var fail = false
        var openingKey = ByteArray(0)
        val cache = AutoFillIncrementalCache(directory, { fence }, { fence = it }, { _, key -> openingKey = key.copyOf(); key.copyOf() },
            { NOW }, { file, bytes -> if (fail && file.name.contains("catalog")) throw java.io.IOException("Synthetic failure") else file.writeBytes(bytes) })
        try {
            val epoch = cache.beginWriterSession(7)
            val base = cache.replace(payload(1), 7, epoch)
            fail = true
            assertThrows(java.io.IOException::class.java) { cache.applyDelta(delta(base, epoch, payload(1).getJSONObject("manifest"))) }
            assertEquals(base.getLong("revision"), fence.catalogRevision)
            assertEquals(1, cache.readWithAuthenticatedKey(fence, openingKey).size)
        } finally { openingKey.fill(0); directory.deleteRecursively() }
    }

    @Test fun missingOrTamperedUnchangedBodyRejectsDelta() {
        for (remove in listOf(false, true)) {
            val directory = Files.createTempDirectory("autofill-v3-tamper").toFile()
            var fence = AutoFillFence(7, "active", NOW)
            val cache = AutoFillIncrementalCache(directory, { fence }, { fence = it }, { _, key -> key.copyOf() },
                { NOW }, { file, bytes -> file.writeBytes(bytes) })
            try {
                val epoch = cache.beginWriterSession(7)
                val base = cache.replace(payload(1), 7, epoch)
                val body = directory.listFiles()!!.single { it.name.contains("record") }
                if (remove) body.delete() else body.writeBytes(ByteArray(40))
                val error = assertThrows(AutoFillIncrementalException::class.java) { cache.applyDelta(delta(base, epoch, payload(1).getJSONObject("manifest"))) }
                assertEquals("AUTOFILL_FULL_RECOVERY_REQUIRED", error.code)
                assertEquals(base.getLong("revision"), fence.catalogRevision)
            } finally { directory.deleteRecursively() }
        }
    }

    @Test fun staleBaseAndOldWriterCannotOverwriteNewerState() = fixture { cache, fence, _ ->
        val epoch = cache.beginWriterSession(7)
        val base = cache.replace(payload(1), 7, epoch)
        val next = cache.applyDelta(delta(base, epoch, payload(1).getJSONObject("manifest")))
        val error = assertThrows(AutoFillIncrementalException::class.java) { cache.applyDelta(delta(base, epoch, payload(1).getJSONObject("manifest"))) }
        assertEquals("AUTOFILL_STALE_BASE", error.code)
        cache.endWriterSession(epoch)
        assertThrows(AutoFillIncrementalException::class.java) { cache.applyDelta(delta(next, epoch, payload(1).getJSONObject("manifest"))) }
        assertEquals(next.getLong("revision"), fence().catalogRevision)
    }

    @Test fun revokeBetweenStagingAndCommitCannotReactivateGeneration() {
        val directory = Files.createTempDirectory("autofill-v3-revoke").toFile()
        var fence = AutoFillFence(7, "active", NOW)
        val cache = AutoFillIncrementalCache(directory, { fence }, { fence = it }, { _, key -> key.copyOf() },
            { NOW }, { file, bytes -> file.writeBytes(bytes) }, beforeCommit = { fence = AutoFillFence(8, "revoked", NOW) })
        try {
            val epoch = cache.beginWriterSession(7)
            assertThrows(AutoFillIncrementalException::class.java) { cache.replace(payload(1), 7, epoch) }
            assertEquals("revoked", fence.state)
            assertEquals(8, fence.generation)
        } finally { directory.deleteRecursively() }
    }

    @Test fun emptyScopedDenialStillVerifiesAndAdvancesExactBase() = fixture { cache, fence, _ ->
        val epoch = cache.beginWriterSession(7)
        val base = cache.replace(payload(1), 7, epoch)
        val args = JSONObject().put("base", base).put("writerEpoch", epoch).put("entries", JSONArray())
        val denied = cache.deny(args)
        assertTrue(denied.getString("denyToken").isNotEmpty())
        assertTrue(denied.getJSONObject("base").getLong("revision") > base.getLong("revision"))
        val stale = assertThrows(AutoFillIncrementalException::class.java) { cache.deny(args) }
        assertEquals("AUTOFILL_STALE_BASE", stale.code)
        val resolved = cache.applyDelta(delta(denied.getJSONObject("base"), epoch, payload(1).getJSONObject("manifest"))
            .put("releasingDenies", JSONArray().put(denied.getString("denyToken"))))
        assertEquals(resolved.getLong("revision"), fence().catalogRevision)
    }

    companion object {
        const val NOW = 1_787_990_400_000L
        fun payload(count: Int): JSONObject {
            val entries = JSONArray()
            val records = JSONArray()
            repeat(count) { index ->
                entries.put(JSONObject().put("entryId", "entry-$index").put("revision", "1").put("keyVersion", 1))
                records.put(JSONObject().put("id", "entry-$index").put("organizationId", "org")
                    .put("vaultId", "vault").put("revision", "1").put("keyVersion", 1)
                    .put("label", "Synthetic $index").put("username", "synthetic").put("password", "synthetic-only")
                    .put("domains", JSONArray().put("example.invalid")))
            }
            val vault = JSONObject().put("vaultId", "vault").put("contextVersion", 1).put("memberId", "principal")
                .put("memberKeyGeneration", 1).put("vaultKeyVersion", 1).put("memberRecipientKeyVersion", 1)
                .put("memberRecipientKeyFingerprint", "synthetic-fingerprint")
                .put("issuedAt", "2026-08-29T08:00:00Z").put("notAfter", "2026-08-30T08:00:00Z").put("entries", entries)
            val manifest = JSONObject().put("principalId", "principal").put("organizationId", "org")
                .put("organizationMembershipGeneration", "1").put("offlinePolicy", "24h").put("offlinePolicyVersion", 1)
                .put("vaults", JSONArray().put(vault))
            return JSONObject().put("version", 3).put("manifest", manifest).put("records", records)
        }
    }
}
