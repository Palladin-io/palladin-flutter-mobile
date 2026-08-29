package io.palladin.mobile.autofill

import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.system.Os
import android.system.OsConstants
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.spec.MGF1ParameterSpec
import java.time.Instant
import java.util.Base64 as JavaBase64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

internal data class CachedCredential(
    val id: String,
    val label: String,
    val username: String,
    val password: String,
    val domains: List<String>,
)

internal data class AutoFillUnwrapOperation(
    val generation: Long,
    val cipher: Cipher,
)

internal data class AutoFillFence(
    val generation: Long,
    val state: String,
    val maximumObservedWallTimeMillis: Long,
)

internal object AutoFillClockPolicy {
    private const val ROLLBACK_TOLERANCE_MILLIS = 5L * 60L * 1000L

    fun observe(maximumObservedWallTimeMillis: Long, observedWallTimeMillis: Long): Long {
        require(maximumObservedWallTimeMillis > 0 && observedWallTimeMillis > 0)
        require(observedWallTimeMillis >= maximumObservedWallTimeMillis - ROLLBACK_TOLERANCE_MILLIS)
        return maxOf(maximumObservedWallTimeMillis, observedWallTimeMillis)
    }
}

internal class AutoFillProcessClockGuard {
    private var baselineWallTimeMillis: Long? = null
    private var baselineElapsedTimeMillis: Long? = null

    @Synchronized
    fun observe(wallTimeMillis: Long, elapsedTimeMillis: Long) {
        require(wallTimeMillis > 0 && elapsedTimeMillis >= 0)
        val baselineWall = baselineWallTimeMillis
        val baselineElapsed = baselineElapsedTimeMillis
        if (baselineWall == null || baselineElapsed == null) {
            baselineWallTimeMillis = wallTimeMillis
            baselineElapsedTimeMillis = elapsedTimeMillis
            return
        }
        require(elapsedTimeMillis >= baselineElapsed)
        val elapsedAdvance = elapsedTimeMillis - baselineElapsed
        val minimumWallTime = baselineWall + elapsedAdvance - ROLLBACK_TOLERANCE_MILLIS
        require(wallTimeMillis >= minimumWallTime)
    }

    companion object {
        private const val ROLLBACK_TOLERANCE_MILLIS = 5L * 60L * 1000L
        val shared = AutoFillProcessClockGuard()
    }
}

internal object AutoFillClockBoundary {
    fun observe(
        fence: AutoFillFence,
        wallTimeMillis: Long,
        elapsedTimeMillis: Long,
        processGuard: AutoFillProcessClockGuard,
        quarantine: () -> Unit,
    ): Long {
        try {
            processGuard.observe(wallTimeMillis, elapsedTimeMillis)
            return AutoFillClockPolicy.observe(
                fence.maximumObservedWallTimeMillis,
                wallTimeMillis,
            )
        } catch (error: IllegalArgumentException) {
            if (fence.state == "active") quarantine()
            throw IllegalStateException("AutoFill wall clock rollback", error)
        }
    }
}

internal object AutoFillStatePresencePolicy {
    fun requireConsistent(
        fenceExists: Boolean,
        integrityKeyExists: Boolean,
        generationArtifactExists: Boolean,
    ) {
        require(
            (fenceExists && integrityKeyExists) ||
                (!fenceExists && !integrityKeyExists && !generationArtifactExists),
        )
    }
}

private class AutoFillClockAuthorityException(cause: Throwable) :
    IllegalStateException("Invalid AutoFill clock authority", cause)

internal object AutoFillFencePolicy {
    fun requireActive(fence: AutoFillFence?, generation: Long) {
        require(fence?.generation == generation && fence.state == "active")
    }
}

internal object AutoFillMutationLock {
    val monitor = Any()
}

internal object AutoFillHandoffGate {
    fun <T> run(
        validate: () -> Unit,
        handoff: () -> T,
    ): T = synchronized(AutoFillMutationLock.monitor) {
        validate()
        handoff()
    }
}

internal object AutoFillAtomicFileWriter {
    fun write(
        target: File,
        bytes: ByteArray,
        syncDirectory: (File) -> Unit = ::syncDirectory,
    ) {
        val directory = requireNotNull(target.parentFile)
        check(directory.isDirectory || directory.mkdirs()) {
            "Unable to create AutoFill state directory"
        }
        val temporary = File(directory, "${target.name}.tmp")
        FileOutputStream(temporary).use { output ->
            output.write(bytes)
            output.fd.sync()
        }
        check(temporary.renameTo(target)) { "Unable to replace AutoFill state" }
        syncDirectory(directory)
    }

    private fun syncDirectory(directory: File) {
        val descriptor = Os.open(
            directory.absolutePath,
            OsConstants.O_RDONLY,
            0,
        )
        try {
            Os.fsync(descriptor)
        } finally {
            Os.close(descriptor)
        }
    }
}

internal object AutoFillFenceCodec {
    private val fields = setOf(
        "version",
        "generation",
        "state",
        "maximumObservedWallTimeMillis",
        "mac",
    )
    private val states = setOf("active", "revoked", "quarantined")

    fun encode(
        fence: AutoFillFence,
        signer: (AutoFillFence) -> ByteArray,
    ): ByteArray {
        val mac = signer(fence)
        return try {
            JSONObject()
                .put("version", 2)
                .put("generation", fence.generation)
                .put("state", fence.state)
                .put("maximumObservedWallTimeMillis", fence.maximumObservedWallTimeMillis)
                .put("mac", JavaBase64.getEncoder().encodeToString(mac))
                .toString()
                .toByteArray(Charsets.UTF_8)
        } finally {
            mac.fill(0)
        }
    }

    fun decode(
        encoded: String,
        signer: (AutoFillFence) -> ByteArray,
    ): AutoFillFence {
        val raw = JSONObject(encoded)
        require(raw.keys().asSequence().toSet() == fields)
        require(raw.getInt("version") == 2)
        val fence = AutoFillFence(
            generation = raw.getLong("generation"),
            state = raw.getString("state"),
            maximumObservedWallTimeMillis = raw.getLong("maximumObservedWallTimeMillis"),
        )
        require(
            fence.generation > 0 &&
                fence.state in states &&
                fence.maximumObservedWallTimeMillis > 0,
        )
        val actual = JavaBase64.getDecoder().decode(raw.getString("mac"))
        val expected = signer(fence)
        try {
            require(MessageDigest.isEqual(actual, expected))
        } finally {
            actual.fill(0)
            expected.fill(0)
        }
        return fence
    }
}

private data class EntryAuthority(
    val revision: String,
    val keyVersion: Int,
)

private data class VaultAuthority(
    val notAfterMillis: Long,
    val entries: Map<String, EntryAuthority>,
)

internal object AutoFillCachePayloadValidator {
    fun validate(payload: JSONObject, nowMillis: Long): MutableList<CachedCredential> {
        require(payload.fieldNames() == setOf("version", "manifest", "records"))
        require(payload.getInt("version") == CACHE_VERSION)
        val manifest = payload.getJSONObject("manifest")
        require(manifest.fieldNames() == MANIFEST_FIELDS)
        val principalId = manifest.requiredString("principalId")
        val organizationId = manifest.requiredString("organizationId")
        require(DECIMAL.matches(manifest.requiredString("organizationMembershipGeneration")))
        val offlinePolicy = manifest.requiredString("offlinePolicy")
        require(offlinePolicy in OFFLINE_POLICIES)
        require(manifest.positiveInt("offlinePolicyVersion") > 0)
        val vaults = parseVaults(
            manifest.getJSONArray("vaults"),
            principalId = principalId,
            offlinePolicy = offlinePolicy,
            nowMillis = nowMillis,
        )
        val recordsJson = payload.getJSONArray("records")
        require(recordsJson.length() in 1..MAX_RECORDS)
        val expectedIdentities = vaults.flatMap { (vaultId, authority) ->
            authority.entries.keys.map { entryId -> "$vaultId:$entryId" }
        }.toSet()
        val identities = mutableSetOf<String>()
        val records = mutableListOf<CachedCredential>()
        for (index in 0 until recordsJson.length()) {
            val raw = recordsJson.getJSONObject(index)
            require(raw.fieldNames() == RECORD_FIELDS)
            val id = raw.requiredString("id")
            require(raw.requiredString("organizationId") == organizationId)
            val vaultId = raw.requiredString("vaultId")
            val authority = vaults[vaultId]?.entries?.get(id)
                ?: throw IllegalArgumentException("Missing Entry authority")
            require(raw.requiredString("revision") == authority.revision)
            require(raw.positiveInt("keyVersion") == authority.keyVersion)
            require(identities.add("$vaultId:$id"))
            val domainsJson = raw.getJSONArray("domains")
            require(domainsJson.length() in 1..MAX_DOMAINS_PER_RECORD)
            val domains = buildList {
                for (domainIndex in 0 until domainsJson.length()) {
                    val normalized = AutoFillCacheStore.normalizeDomain(
                        domainsJson.getString(domainIndex),
                    ) ?: throw IllegalArgumentException("Invalid AutoFill domain")
                    add(normalized)
                }
            }.distinct().sorted()
            require(domains.size == domainsJson.length())
            records += CachedCredential(
                id = id,
                label = raw.requiredString("label"),
                username = raw.getString("username"),
                password = raw.requiredString("password"),
                domains = domains,
            )
        }
        require(identities == expectedIdentities)
        return records
    }

    private fun parseVaults(
        rawVaults: JSONArray,
        principalId: String,
        offlinePolicy: String,
        nowMillis: Long,
    ): Map<String, VaultAuthority> {
        require(rawVaults.length() in 1..MAX_RECORDS)
        val vaults = mutableMapOf<String, VaultAuthority>()
        for (index in 0 until rawVaults.length()) {
            val raw = rawVaults.getJSONObject(index)
            require(raw.fieldNames() == VAULT_FIELDS)
            val vaultId = raw.requiredString("vaultId")
            require(raw.getInt("contextVersion") == 1)
            require(raw.requiredString("memberId") == principalId)
            require(raw.positiveInt("memberKeyGeneration") > 0)
            require(raw.positiveInt("vaultKeyVersion") > 0)
            require(raw.positiveInt("memberRecipientKeyVersion") > 0)
            raw.requiredString("memberRecipientKeyFingerprint")
            val issuedAt = Instant.parse(raw.requiredString("issuedAt"))
            val notAfter = Instant.parse(raw.requiredString("notAfter"))
            require(notAfter.toEpochMilli() == issuedAt.toEpochMilli() + leaseMillis(offlinePolicy))
            require(issuedAt.toEpochMilli() <= nowMillis + FUTURE_CLOCK_TOLERANCE_MILLIS)
            require(nowMillis < notAfter.toEpochMilli())
            val entriesJson = raw.getJSONArray("entries")
            require(entriesJson.length() in 1..MAX_RECORDS)
            val entries = mutableMapOf<String, EntryAuthority>()
            for (entryIndex in 0 until entriesJson.length()) {
                val entry = entriesJson.getJSONObject(entryIndex)
                require(entry.fieldNames() == ENTRY_AUTHORITY_FIELDS)
                val entryId = entry.requiredString("entryId")
                val revision = entry.requiredString("revision")
                require(DECIMAL.matches(revision))
                val previous = entries.put(
                    entryId,
                    EntryAuthority(
                        revision = revision,
                        keyVersion = entry.positiveInt("keyVersion"),
                    ),
                )
                require(previous == null)
            }
            require(vaults.put(vaultId, VaultAuthority(notAfter.toEpochMilli(), entries)) == null)
        }
        return vaults
    }

    private fun leaseMillis(policy: String): Long = when (policy) {
        "1h" -> 60L * 60L * 1000L
        "4h" -> 4L * 60L * 60L * 1000L
        "24h" -> 24L * 60L * 60L * 1000L
        else -> throw IllegalArgumentException("Unsupported AutoFill lease")
    }

    private fun JSONObject.requiredString(name: String): String =
        getString(name).takeIf(String::isNotEmpty)
            ?: throw IllegalArgumentException("Missing $name")

    private fun JSONObject.positiveInt(name: String): Int =
        getInt(name).takeIf { it > 0 }
            ?: throw IllegalArgumentException("Invalid $name")

    private fun JSONObject.fieldNames(): Set<String> =
        keys().asSequence().toSet()

    private val DECIMAL = Regex("^(?:0|[1-9][0-9]*)$")
    private val OFFLINE_POLICIES = setOf("1h", "4h", "24h")
    private val MANIFEST_FIELDS = setOf(
        "principalId",
        "organizationId",
        "organizationMembershipGeneration",
        "offlinePolicy",
        "offlinePolicyVersion",
        "vaults",
    )
    private val VAULT_FIELDS = setOf(
        "vaultId",
        "contextVersion",
        "memberId",
        "memberKeyGeneration",
        "vaultKeyVersion",
        "memberRecipientKeyVersion",
        "memberRecipientKeyFingerprint",
        "issuedAt",
        "notAfter",
        "entries",
    )
    private val ENTRY_AUTHORITY_FIELDS = setOf("entryId", "revision", "keyVersion")
    private val RECORD_FIELDS = setOf(
        "id",
        "organizationId",
        "vaultId",
        "revision",
        "keyVersion",
        "label",
        "username",
        "password",
        "domains",
    )
    private const val CACHE_VERSION = 2
    private const val MAX_RECORDS = 2_000
    private const val MAX_DOMAINS_PER_RECORD = 16
    private const val FUTURE_CLOCK_TOLERANCE_MILLIS = 5L * 60L * 1000L
}

internal class AutoFillCacheStore(
    private val context: Context,
    private val nowMillis: () -> Long = System::currentTimeMillis,
    private val elapsedRealtimeMillis: () -> Long = SystemClock::elapsedRealtime,
    private val processClockGuard: AutoFillProcessClockGuard = AutoFillProcessClockGuard.shared,
) {
    fun hasCache(): Boolean = synchronized(AutoFillMutationLock.monitor) {
        try {
            requireCompleteClockAuthorityLocked()
        } catch (_: IllegalArgumentException) {
            denyIncompleteClockAuthorityLocked()
            return@synchronized false
        }
        try {
            purgeLegacyLocked()
            val fence = readFenceLocked()
            if (fence == null) {
                runCatching { clearAllGenerationArtifactsLocked() }
                return@synchronized false
            }
            require(fence.state == FENCE_ACTIVE)
            observeWallTimeLocked(fence.generation)
            cacheFile(fence.generation).isFile
        } catch (_: AutoFillClockAuthorityException) {
            denyIncompleteClockAuthorityLocked()
            false
        } catch (_: Exception) {
            failClosedLocked()
            false
        }
    }

    fun beginSession(): Long = synchronized(AutoFillMutationLock.monitor) {
        purgeLegacyLocked()
        try {
            requireCompleteClockAuthorityLocked()
        } catch (error: IllegalArgumentException) {
            denyIncompleteClockAuthorityLocked()
            throw IllegalStateException("Incomplete AutoFill clock authority", error)
        }
        val observed = nowMillis()
        val previous = try {
            readFenceLocked()
        } catch (error: AutoFillClockAuthorityException) {
            denyIncompleteClockAuthorityLocked()
            throw IllegalStateException("Invalid AutoFill clock authority", error)
        }
        if (previous == null) {
            processClockGuard.observe(observed, elapsedRealtimeMillis())
        } else {
            requireWallTimeNotRolledBack(previous, observed)
        }
        val generation = nextGenerationLocked()
        writeFenceLocked(
            AutoFillFence(
                generation,
                FENCE_ACTIVE,
                maxOf(previous?.maximumObservedWallTimeMillis ?: 0L, observed),
            ),
        )
        generation
    }

    fun replace(rawPayload: Map<*, *>?, sessionToken: Long) {
        synchronized(AutoFillMutationLock.monitor) {
            requireActiveFenceLocked(sessionToken)
            observeWallTimeLocked(sessionToken)
            val payload = JSONObject(rawPayload ?: throw IllegalArgumentException("Missing payload"))
            AutoFillCachePayloadValidator.validate(payload, nowMillis())
            val plaintext = payload.toString().toByteArray(Charsets.UTF_8)
            val dataKey = ByteArray(DATA_KEY_BYTES).also(SecureRandom()::nextBytes)
            try {
                val contentCipher = Cipher.getInstance(AES_TRANSFORMATION)
                contentCipher.init(
                    Cipher.ENCRYPT_MODE,
                    SecretKeySpec(dataKey, KeyProperties.KEY_ALGORITHM_AES),
                )
                contentCipher.updateAAD(aad(sessionToken))
                val ciphertext = contentCipher.doFinal(plaintext)
                val wrapCipher = rsaCipher()
                wrapCipher.init(
                    Cipher.ENCRYPT_MODE,
                    getOrCreateKeyPair(sessionToken).certificate.publicKey,
                    OAEP_PARAMETERS,
                )
                val wrappedKey = wrapCipher.doFinal(dataKey)
                val envelope = JSONObject()
                    .put("version", CACHE_VERSION)
                    .put("generation", sessionToken)
                    .put("wrappedKey", wrappedKey.toBase64())
                    .put("nonce", contentCipher.iv.toBase64())
                    .put("ciphertext", ciphertext.toBase64())
                    .toString()
                    .toByteArray(Charsets.UTF_8)
                try {
                    writeAtomically(cacheFile(sessionToken), envelope)
                    requireActiveFenceLocked(sessionToken)
                    observeWallTimeLocked(sessionToken)
                    clearOtherGenerationArtifactsLocked(sessionToken)
                } finally {
                    envelope.fill(0)
                    ciphertext.fill(0)
                    wrappedKey.fill(0)
                }
            } finally {
                plaintext.fill(0)
                dataKey.fill(0)
            }
        }
    }

    fun clear() {
        revokeAccess()
    }

    fun clear(sessionToken: Long) {
        synchronized(AutoFillMutationLock.monitor) {
            val fence = readFenceLocked() ?: return@synchronized
            if (fence.generation != sessionToken || fence.state != FENCE_ACTIVE) {
                throw IllegalStateException("Stale AutoFill cache session")
            }
            writeFenceLocked(fence.copy(state = FENCE_QUARANTINED))
            clearGenerationArtifactsLocked(sessionToken)
            val current = readFenceLocked()
            if (current?.generation == sessionToken && current.state == FENCE_QUARANTINED) {
                writeFenceLocked(current.copy(state = FENCE_ACTIVE))
            }
        }
    }

    fun revokeAccess(): Long = synchronized(AutoFillMutationLock.monitor) {
        try {
            requireCompleteClockAuthorityLocked()
        } catch (error: IllegalArgumentException) {
            denyIncompleteClockAuthorityLocked()
            throw IllegalStateException("Incomplete AutoFill clock authority", error)
        }
        val current = try {
            readFenceLocked()
        } catch (error: AutoFillClockAuthorityException) {
            denyIncompleteClockAuthorityLocked()
            throw IllegalStateException("Invalid AutoFill clock authority", error)
        }
        val generation = maxOf(
            (current?.generation ?: 0L) + 1L,
            nowMillis().coerceAtLeast(1L),
        )
        val maximumObserved = current?.maximumObservedWallTimeMillis ?: 0L
        writeFenceLocked(
            AutoFillFence(
                generation,
                FENCE_REVOKED,
                maxOf(maximumObserved, nowMillis()),
            ),
        )
        generation
    }

    fun cleanupRevoked(generation: Long) {
        synchronized(AutoFillMutationLock.monitor) {
            val fence = readFenceLocked()
            if (fence?.generation != generation || fence.state != FENCE_REVOKED) {
                return@synchronized
            }
            clearAllGenerationArtifactsLocked()
            purgeLegacyLocked()
        }
    }

    fun createUnwrapOperation(): AutoFillUnwrapOperation = synchronized(AutoFillMutationLock.monitor) {
        purgeLegacyLocked()
        val fence = readFenceLocked() ?: throw IllegalStateException("AutoFill fence unavailable")
        require(fence.state == FENCE_ACTIVE)
        observeWallTimeLocked(fence.generation)
        val privateKey = loadKeyStore().getKey(keyAlias(fence.generation), null)
            ?: throw IllegalStateException("AutoFill key is unavailable")
        AutoFillUnwrapOperation(
            generation = fence.generation,
            cipher = rsaCipher().apply {
                init(Cipher.DECRYPT_MODE, privateKey, OAEP_PARAMETERS)
            },
        )
    }

    fun revalidate(generation: Long) {
        synchronized(AutoFillMutationLock.monitor) {
            requireActiveFenceLocked(generation)
            observeWallTimeLocked(generation)
        }
    }

    fun <T> withRevalidatedGeneration(
        generation: Long,
        handoff: () -> T,
    ): T = AutoFillHandoffGate.run(
        validate = {
            requireActiveFenceLocked(generation)
            observeWallTimeLocked(generation)
        },
        handoff = handoff,
    )

    fun decrypt(operation: AutoFillUnwrapOperation): MutableList<CachedCredential> =
        synchronized(AutoFillMutationLock.monitor) {
            requireActiveFenceLocked(operation.generation)
            observeWallTimeLocked(operation.generation)
            val file = cacheFile(operation.generation)
            require(file.length() in 1..MAX_CACHE_BYTES)
            val envelope = JSONObject(file.readText(Charsets.UTF_8))
            require(envelope.fieldNames() == ENVELOPE_FIELDS)
            require(envelope.getInt("version") == CACHE_VERSION)
            require(envelope.getLong("generation") == operation.generation)
            val wrappedKey = envelope.getString("wrappedKey").fromBase64()
            val nonce = envelope.getString("nonce").fromBase64()
            val ciphertext = envelope.getString("ciphertext").fromBase64()
            val dataKey = operation.cipher.doFinal(wrappedKey)
            try {
                val contentCipher = Cipher.getInstance(AES_TRANSFORMATION)
                contentCipher.init(
                    Cipher.DECRYPT_MODE,
                    SecretKeySpec(dataKey, KeyProperties.KEY_ALGORITHM_AES),
                    GCMParameterSpec(GCM_TAG_BITS, nonce),
                )
                contentCipher.updateAAD(aad(operation.generation))
                val plaintext = contentCipher.doFinal(ciphertext)
                try {
                    val records = AutoFillCachePayloadValidator.validate(
                        JSONObject(String(plaintext, Charsets.UTF_8)),
                        nowMillis(),
                    )
                    requireActiveFenceLocked(operation.generation)
                    observeWallTimeLocked(operation.generation)
                    records
                } finally {
                    plaintext.fill(0)
                }
            } finally {
                wrappedKey.fill(0)
                nonce.fill(0)
                ciphertext.fill(0)
                dataKey.fill(0)
            }
        }

    fun quarantine(generation: Long) {
        synchronized(AutoFillMutationLock.monitor) {
            val current = try {
                readFenceLocked()
            } catch (_: AutoFillClockAuthorityException) {
                denyIncompleteClockAuthorityLocked()
                return@synchronized
            } catch (_: Exception) {
                failClosedLocked()
                return@synchronized
            } ?: return@synchronized
            if (current.generation != generation || current.state != FENCE_ACTIVE) {
                return@synchronized
            }
            writeFenceLocked(current.copy(state = FENCE_QUARANTINED))
            runCatching { clearGenerationArtifactsLocked(generation) }
        }
    }

    private fun requireActiveFenceLocked(generation: Long) {
        AutoFillFencePolicy.requireActive(readFenceLocked(), generation)
    }

    private fun nextGenerationLocked(): Long {
        val parsed = runCatching { readFenceLocked()?.generation }.getOrNull() ?: 0L
        return maxOf(parsed + 1L, nowMillis().coerceAtLeast(1L))
    }

    private fun readFenceLocked(): AutoFillFence? {
        requireCompleteClockAuthorityLocked()
        if (!fenceFile.isFile) return null
        val integrityKey = loadKeyStore().getKey(INTEGRITY_KEY_ALIAS, null)
            ?: throw IllegalStateException("AutoFill integrity key unavailable")
        return try {
            AutoFillFenceCodec.decode(fenceFile.readText(Charsets.UTF_8)) { fence ->
                fenceMac(
                    fence.generation,
                    fence.state,
                    fence.maximumObservedWallTimeMillis,
                    integrityKey,
                )
            }
        } catch (error: Exception) {
            throw AutoFillClockAuthorityException(error)
        }
    }

    private fun writeFenceLocked(fence: AutoFillFence) {
        requireCompleteClockAuthorityLocked()
        val encoded = AutoFillFenceCodec.encode(fence) { value ->
            fenceMac(
                value.generation,
                value.state,
                value.maximumObservedWallTimeMillis,
            )
        }
        try {
            writeAtomically(fenceFile, encoded)
        } finally {
            encoded.fill(0)
        }
    }

    private fun observeWallTimeLocked(generation: Long) {
        val current = readFenceLocked()
            ?: throw IllegalStateException("AutoFill fence unavailable")
        require(current.generation == generation && current.state == FENCE_ACTIVE)
        val observed = nowMillis()
        val maximumObserved = requireWallTimeNotRolledBack(current, observed)
        if (maximumObserved > current.maximumObservedWallTimeMillis) {
            writeFenceLocked(current.copy(maximumObservedWallTimeMillis = maximumObserved))
        }
    }

    private fun requireWallTimeNotRolledBack(fence: AutoFillFence, observed: Long): Long {
        return AutoFillClockBoundary.observe(
            fence = fence,
            wallTimeMillis = observed,
            elapsedTimeMillis = elapsedRealtimeMillis(),
            processGuard = processClockGuard,
            quarantine = {
                writeFenceLocked(fence.copy(state = FENCE_QUARANTINED))
            },
        )
    }

    private fun failClosedLocked() {
        val current = runCatching { readFenceLocked() }.getOrNull()
        val observed = nowMillis().coerceAtLeast(1L)
        val generation = maxOf(
            (current?.generation ?: 0L) + 1L,
            observed,
            System.nanoTime().coerceAtLeast(1L),
        )
        runCatching {
            writeFenceLocked(
                AutoFillFence(
                    generation = generation,
                    state = FENCE_QUARANTINED,
                    maximumObservedWallTimeMillis = maxOf(
                        current?.maximumObservedWallTimeMillis ?: 0L,
                        observed,
                    ),
                ),
            )
        }
        runCatching { clearAllGenerationArtifactsLocked() }
        runCatching { purgeLegacyLocked() }
    }

    private fun requireCompleteClockAuthorityLocked() {
        AutoFillStatePresencePolicy.requireConsistent(
            fenceFile.isFile,
            integrityKeyExistsLocked(),
            generationArtifactsExistLocked(),
        )
    }

    private fun denyIncompleteClockAuthorityLocked() {
        runCatching { clearAllGenerationArtifactsLocked() }
        runCatching { purgeLegacyLocked() }
    }

    private fun fenceMac(
        generation: Long,
        state: String,
        maximumObservedWallTimeMillis: Long,
        integrityKey: java.security.Key = getOrCreateIntegrityKey(),
    ): ByteArray = Mac.getInstance(HMAC_ALGORITHM).run {
        init(integrityKey)
        doFinal(
            "palladin-autofill-fence-v2:$generation:$state:$maximumObservedWallTimeMillis"
                .toByteArray(Charsets.UTF_8),
        )
    }

    private fun purgeLegacyLocked() {
        deleteFiles(
            listOf(
                File(context.noBackupFilesDir, LEGACY_CACHE_FILE_NAME),
                File(context.noBackupFilesDir, "$LEGACY_CACHE_FILE_NAME.tmp"),
            ),
        )
        val keyStore = loadKeyStore()
        if (keyStore.containsAlias(LEGACY_KEY_ALIAS)) keyStore.deleteEntry(LEGACY_KEY_ALIAS)
    }

    private fun clearGenerationArtifactsLocked(generation: Long) {
        deleteFiles(
            listOf(
                cacheFile(generation),
                File(context.noBackupFilesDir, "${cacheFileName(generation)}.tmp"),
            ),
        )
        val keyStore = loadKeyStore()
        val alias = keyAlias(generation)
        if (keyStore.containsAlias(alias)) keyStore.deleteEntry(alias)
    }

    private fun clearOtherGenerationArtifactsLocked(activeGeneration: Long) {
        generationFiles().filterNot { it.name == cacheFileName(activeGeneration) }
            .forEach { file -> if (!file.delete()) throw IOException("Unable to remove old AutoFill cache") }
        val keyStore = loadKeyStore()
        keyStore.aliases().toList()
            .filter { it.startsWith(KEY_ALIAS_PREFIX) && it != keyAlias(activeGeneration) }
            .forEach(keyStore::deleteEntry)
    }

    private fun clearAllGenerationArtifactsLocked() {
        deleteFiles(generationFiles())
        val keyStore = loadKeyStore()
        keyStore.aliases().toList()
            .filter { it.startsWith(KEY_ALIAS_PREFIX) }
            .forEach(keyStore::deleteEntry)
    }

    private fun generationFiles(): List<File> =
        context.noBackupFilesDir.listFiles().orEmpty()
            .filter { it.name.startsWith(CACHE_FILE_PREFIX) }

    private fun deleteFiles(files: Iterable<File>) {
        val failed = files.firstOrNull { it.exists() && !it.delete() }
        if (failed != null) throw IOException("Unable to remove AutoFill cache")
    }

    private fun getOrCreateKeyPair(generation: Long): KeyStore.PrivateKeyEntry {
        val keyStore = loadKeyStore()
        val alias = keyAlias(generation)
        (keyStore.getEntry(alias, null) as? KeyStore.PrivateKeyEntry)?.let { return it }
        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(RSA_KEY_BITS)
            .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA1)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(0, KeyProperties.AUTH_BIOMETRIC_STRONG)
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, ANDROID_KEY_STORE).apply {
            initialize(builder.build())
            generateKeyPair()
        }
        return loadKeyStore().getEntry(alias, null) as KeyStore.PrivateKeyEntry
    }

    private fun getOrCreateIntegrityKey(): java.security.Key {
        val keyStore = loadKeyStore()
        keyStore.getKey(INTEGRITY_KEY_ALIAS, null)?.let { return it }
        return KeyGenerator.getInstance(HMAC_ALGORITHM, ANDROID_KEY_STORE).run {
            init(
                KeyGenParameterSpec.Builder(
                    INTEGRITY_KEY_ALIAS,
                    KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
                )
                    .setKeySize(HMAC_KEY_BITS)
                    .setDigests(KeyProperties.DIGEST_SHA256)
                    .build(),
            )
            generateKey()
        }
    }

    private fun integrityKeyExistsLocked(): Boolean =
        loadKeyStore().containsAlias(INTEGRITY_KEY_ALIAS)

    private fun generationArtifactsExistLocked(): Boolean {
        if (generationFiles().isNotEmpty()) return true
        return loadKeyStore().aliases().toList().any { it.startsWith(KEY_ALIAS_PREFIX) }
    }

    private fun writeAtomically(target: File, bytes: ByteArray) {
        AutoFillAtomicFileWriter.write(target, bytes)
    }

    private fun loadKeyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }

    private fun JSONObject.fieldNames(): Set<String> =
        keys().asSequence().toSet()

    private fun rsaCipher(): Cipher = Cipher.getInstance(RSA_TRANSFORMATION)

    private val fenceFile: File
        get() = File(context.noBackupFilesDir, FENCE_FILE_NAME)

    private fun cacheFile(generation: Long): File =
        File(context.noBackupFilesDir, cacheFileName(generation))

    companion object {

        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val LEGACY_KEY_ALIAS = "palladin_autofill_wrap_v1"
        private const val LEGACY_CACHE_FILE_NAME = "palladin_autofill_cache_v1"
        private const val INTEGRITY_KEY_ALIAS = "palladin_autofill_integrity_v2"
        private const val KEY_ALIAS_PREFIX = "palladin_autofill_wrap_v2_"
        private const val CACHE_FILE_PREFIX = "palladin_autofill_cache_v2_"
        private const val FENCE_FILE_NAME = "palladin_autofill_fence_v2"
        private const val CACHE_VERSION = 2
        private const val FENCE_ACTIVE = "active"
        private const val FENCE_REVOKED = "revoked"
        private const val FENCE_QUARANTINED = "quarantined"
        private const val DATA_KEY_BYTES = 32
        private const val RSA_KEY_BITS = 2048
        private const val HMAC_KEY_BITS = 256
        private const val GCM_TAG_BITS = 128
        private const val MAX_CACHE_BYTES = 16L * 1024L * 1024L
        private const val AES_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val RSA_TRANSFORMATION = "RSA/ECB/OAEPWithSHA-256AndMGF1Padding"
        private const val HMAC_ALGORITHM = "HmacSHA256"
        private val OAEP_PARAMETERS = OAEPParameterSpec(
            "SHA-256",
            "MGF1",
            MGF1ParameterSpec.SHA1,
            PSource.PSpecified.DEFAULT,
        )
        private val ENVELOPE_FIELDS = setOf(
            "version",
            "generation",
            "wrappedKey",
            "nonce",
            "ciphertext",
        )

        fun normalizeDomain(raw: String?): String? {
            val value = raw?.trim()?.lowercase()?.trimEnd('.') ?: return null
            if (value.isEmpty() ||
                value.any { it.code > 0x7f } ||
                value.contains("://") ||
                value.contains('@') ||
                value.contains(':') ||
                !value.contains('.') ||
                value.contains("..") ||
                value.split('.').any { label ->
                    label.isEmpty() || label.length > 63 ||
                        label.startsWith('-') || label.endsWith('-') ||
                        label.any { character ->
                            !(character in 'a'..'z' ||
                                character in '0'..'9' ||
                                character == '-')
                        }
                }
            ) return null
            return value
        }

        fun domainMatches(requested: String, stored: String): Boolean = requested == stored

        private fun cacheFileName(generation: Long): String = "$CACHE_FILE_PREFIX$generation"

        private fun keyAlias(generation: Long): String = "$KEY_ALIAS_PREFIX$generation"

        private fun aad(generation: Long): ByteArray =
            "palladin-autofill-cache-v2:$generation".toByteArray(Charsets.UTF_8)

        private fun ByteArray.toBase64(): String =
            Base64.encodeToString(this, Base64.NO_WRAP)

        private fun String.fromBase64(): ByteArray = Base64.decode(this, Base64.NO_WRAP)
    }
}
