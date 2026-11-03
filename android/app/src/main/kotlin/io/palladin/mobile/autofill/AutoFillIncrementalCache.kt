package io.palladin.mobile.autofill

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Instant
import java.util.Base64
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

internal class AutoFillIncrementalException(val code: String) : IllegalStateException(code)

/** Native app-only writer. Provider decryption receives an OS-authenticated key, never this holder. */
internal class AutoFillIncrementalCache(
    private val directory: File,
    private val readFence: () -> AutoFillFence?,
    private val commitFence: (AutoFillFence) -> Unit,
    private val wrapKey: (Long, ByteArray) -> ByteArray,
    private val now: () -> Long,
    private val write: (File, ByteArray) -> Unit = { file, bytes -> AutoFillAtomicFileWriter.write(file, bytes) },
    private val onRecordCrypto: (Boolean) -> Unit = {},
    private val beforeCommit: () -> Unit = {},
) {
    private val writerLock = Any()
    private var epoch = nextWriterEpoch.incrementAndGet()
    private var writerGeneration = 0L
    private var writerKey: ByteArray? = null

    fun beginWriterSession(generation: Long): Long = synchronized(writerLock) {
        writerKey?.fill(0)
        writerKey = null
        writerGeneration = generation
        epoch = nextWriterEpoch.incrementAndGet()
        epoch
    }

    fun endWriterSession(expectedEpoch: Long) = synchronized(writerLock) {
        if (epoch == expectedEpoch) {
            epoch = nextWriterEpoch.incrementAndGet()
            writerKey?.fill(0)
            writerKey = null
        }
    }

    fun invalidateWriter(generation: Long? = null) = synchronized(writerLock) {
        if (generation != null && generation != writerGeneration) return@synchronized
        epoch = nextWriterEpoch.incrementAndGet()
        writerKey?.fill(0)
        writerKey = null
    }

    fun replace(payload: JSONObject, generation: Long, expectedEpoch: Long, base: JSONObject? = null, releasingDenies: JSONArray = JSONArray()): JSONObject {
        requireBoundedJson(payload)
        AutoFillCachePayloadValidator.validate(payload, now(), incremental = true)
        val initial = synchronized(AutoFillMutationLock.monitor) { active(generation) }
        checkEpoch(expectedEpoch, generation)
        if (!initial.catalogFile.isNullOrEmpty()) {
            if (base == null || positive(base, "generation") != generation || positive(base, "revision") != initial.catalogRevision) stale()
            val oldKey = synchronized(writerLock) { writerKey?.copyOf() ?: recovery() }
            try {
                val existing = openCatalog(initial, oldKey, authenticateOnly = true)
                val releases = strings(releasingDenies)
                require(releases.size == releasingDenies.length())
                require(releases == existing.getJSONObject("denies").keys().asSequence().toSet())
            } finally { oldKey.fill(0) }
        } else {
            require(base == null && releasingDenies.length() == 0)
        }
        val key = ByteArray(32).also(SecureRandom()::nextBytes)
        try {
            val manifest = payload.getJSONObject("manifest")
            val records = JSONArray()
            val raw = payload.getJSONArray("records")
            for (index in 0 until raw.length()) records.put(encryptRecord(raw.getJSONObject(index), manifest, generation, key))
            val catalog = JSONObject().put("manifest", copy(manifest)).put("records", records).put("denies", JSONObject())
            val wrapped = wrapKey(generation, key)
            try {
                return commit(initial, catalog, key, expectedEpoch, encode(wrapped), installWriterKey = true)
            } finally { wrapped.fill(0) }
        } finally { key.fill(0) }
    }

    fun deny(arguments: JSONObject): JSONObject = withBase(arguments) { initial, catalog, key, expectedEpoch ->
        val coordinates = coordinates(arguments.getJSONArray("entries"))
        val records = references(catalog)
        require(coordinates.all { it in records })
        val token = UUID.randomUUID().toString()
        catalog.getJSONObject("denies").put(token, JSONArray(coordinates.toList()))
        val base = commit(initial, catalog, key, expectedEpoch, requireNotNull(initial.wrappedKey))
        JSONObject().put("base", base).put("denyToken", token)
    }

    fun applyDelta(arguments: JSONObject): JSONObject = withBase(arguments) { initial, catalog, key, expectedEpoch ->
        val manifest = arguments.getJSONObject("manifest")
        val upserts = arguments.getJSONArray("upserts")
        requireBoundedJson(arguments)
        AutoFillCachePayloadValidator.validate(payload(manifest, upserts), now(), incremental = true, partial = true)
        val oldManifest = catalog.getJSONObject("manifest")
        require(profile(oldManifest) == profile(manifest))
        val original = references(catalog)
        val removals = coordinates(arguments.getJSONArray("removals"))
        require(removals.all { it in original || it in deniedCoordinates(catalog) })
        val updated = LinkedHashMap(original)
        removals.forEach(updated::remove)
        val changed = mutableSetOf<String>()
        for (index in 0 until upserts.length()) {
            val record = upserts.getJSONObject(index)
            val id = coordinate(record.getString("vaultId"), record.getString("id"))
            require(id !in removals && changed.add(id))
            updated[id] = encryptRecord(record, manifest, initial.generation, key)
        }
        val expected = authorities(manifest)
        require(updated.keys == expected.keys)
        val currentProfile = profile(manifest)
        for ((id, reference) in updated) {
            validateRetained(reference, currentProfile, expected.getValue(id), id)
        }
        val denies = catalog.getJSONObject("denies")
        val releases = strings(arguments.getJSONArray("releasingDenies"))
        require(releases.size == arguments.getJSONArray("releasingDenies").length())
        for (token in releases) {
            require(denies.has(token))
            val owned = strings(denies.getJSONArray(token))
            // The complete current manifest and immutable-reference checks above
            // reconcile unchanged records without opening their credential bodies.
            require(owned.all { it in updated || it in removals })
            denies.remove(token)
        }
        catalog.put("manifest", copy(manifest)).put("records", JSONArray(updated.values.toList()))
        commit(initial, catalog, key, expectedEpoch, requireNotNull(initial.wrappedKey))
    }

    fun readWithAuthenticatedKey(fence: AutoFillFence, key: ByteArray): MutableList<CachedCredential> {
        requireCurrentRevision(fence.generation, fence.catalogRevision)
        val catalog = openCatalog(fence, key)
        val manifest = catalog.getJSONObject("manifest")
        val denied = deniedCoordinates(catalog)
        val result = mutableListOf<CachedCredential>()
        val currentAuthorities = authorities(manifest)
        val currentProfile = profile(manifest)
        for ((id, reference) in references(catalog)) {
            validateRetained(reference, currentProfile, currentAuthorities.getValue(id), id)
            if (id in denied) continue
            val original = reference.getJSONObject("authority")
            val file = recordFile(reference)
            val bytes = checkedBytes(file, reference.getString("digest"))
            val plaintext = open(bytes, key, recordAAD(fence.generation, original))
            onRecordCrypto(false)
            try {
                val raw = JSONObject(String(plaintext, Charsets.UTF_8))
                val records = AutoFillCachePayloadValidator.validate(payload(original, JSONArray().put(raw)), now(), incremental = true)
                val currentExpiry = expiry(currentAuthorities.getValue(id).first)
                result += records.single().copy(notAfterMillis = minOf(records.single().notAfterMillis, currentExpiry), catalogRevision = fence.catalogRevision)
            } finally { plaintext.fill(0); bytes.fill(0) }
        }
        requireCurrentRevision(fence.generation, fence.catalogRevision)
        return result
    }

    fun requireCurrentRevision(generation: Long, revision: Long) {
        val fence = active(generation)
        require(fence.catalogRevision == revision)
    }

    private fun <T> withBase(arguments: JSONObject, operation: (AutoFillFence, JSONObject, ByteArray, Long) -> T): T {
        val base = arguments.getJSONObject("base")
        val generation = positive(base, "generation")
        val revision = positive(base, "revision")
        val expectedEpoch = positive(arguments, "writerEpoch")
        val initial = synchronized(AutoFillMutationLock.monitor) {
            val current = active(generation)
            if (current.catalogRevision == 0L || current.catalogFile.isNullOrEmpty()) recovery()
            if (current.catalogRevision != revision) stale()
            current
        }
        val key = synchronized(writerLock) {
            checkEpoch(expectedEpoch, generation)
            writerKey?.copyOf() ?: recovery()
        }
        try {
            val catalog = try { openCatalog(initial, key) } catch (error: AutoFillIncrementalException) { throw error } catch (_: Exception) { recovery() }
            return operation(initial, catalog, key, expectedEpoch)
        } finally { key.fill(0) }
    }

    private fun commit(initial: AutoFillFence, catalog: JSONObject, key: ByteArray, expectedEpoch: Long, wrapped: String, installWriterKey: Boolean = false): JSONObject {
        val revision = Math.addExact(initial.catalogRevision, 1)
        // Snapshot candidates before commit: never delete files staged by a later writer.
        val garbageCandidates = directory.listFiles().orEmpty().filter { RECORD_FILE.matches(it.name) || CATALOG_FILE.matches(it.name) }
        val filename = "palladin_autofill_v3_catalog_${UUID.randomUUID()}"
        val plaintext = canonical(catalog).toByteArray(Charsets.UTF_8)
        val encrypted = try { seal(plaintext, key, catalogAAD(initial.generation, revision)) } finally { plaintext.fill(0) }
        try {
            require(references(catalog).values.sumOf { recordFile(it).length() } + encrypted.size <= MAX_BYTES)
            write(File(directory, filename), encrypted)
            beforeCommit()
            synchronized(AutoFillMutationLock.monitor) {
                synchronized(writerLock) {
                    checkEpoch(expectedEpoch, initial.generation)
                    val current = active(initial.generation)
                    if (current.catalogRevision != initial.catalogRevision || current.catalogDigest != initial.catalogDigest) stale()
                    val finalManifest = catalog.getJSONObject("manifest")
                    AutoFillCachePayloadValidator.validate(payload(finalManifest, JSONArray()), now(), incremental = true, partial = true)
                    val finalAuthorities = authorities(finalManifest)
                    val finalProfile = profile(finalManifest)
                    for ((id, reference) in references(catalog)) {
                        validateRetained(reference, finalProfile, finalAuthorities.getValue(id), id)
                    }
                    val available = references(catalog).keys.count { it !in deniedCoordinates(catalog) }
                    commitFence(current.copy(catalogRevision = revision, catalogFile = filename,
                        catalogDigest = digest(encrypted), wrappedKey = wrapped, availableRecords = available))
                    if (installWriterKey) {
                        writerKey?.fill(0)
                        writerKey = key.copyOf()
                    }
                    val retained = references(catalog).values.map { it.getString("file") }.toSet() + filename
                    garbageCandidates.filterNot { it.name in retained }.forEach { it.delete() }
                }
            }
            return JSONObject().put("generation", initial.generation).put("revision", revision)
        } finally { encrypted.fill(0) }
    }

    private fun encryptRecord(record: JSONObject, manifest: JSONObject, generation: Long, key: ByteArray): JSONObject {
        val id = coordinate(record.getString("vaultId"), record.getString("id"))
        val authority = singleAuthority(manifest, id)
        AutoFillCachePayloadValidator.validate(payload(authority, JSONArray().put(record)), now(), incremental = true)
        val plaintext = canonical(record).toByteArray(Charsets.UTF_8)
        val encrypted = try { seal(plaintext, key, recordAAD(generation, authority)) } finally { plaintext.fill(0) }
        onRecordCrypto(true)
        try {
            val filename = "palladin_autofill_v3_record_${UUID.randomUUID()}"
            write(File(directory, filename), encrypted)
            return JSONObject().put("coordinate", id).put("authority", authority).put("file", filename).put("digest", digest(encrypted))
        } finally { encrypted.fill(0) }
    }

    private fun openCatalog(fence: AutoFillFence, key: ByteArray, authenticateOnly: Boolean = false): JSONObject {
        val filename = fence.catalogFile ?: recovery()
        require(CATALOG_FILE.matches(filename))
        val bytes = checkedBytes(File(directory, filename), fence.catalogDigest ?: recovery())
        val plaintext = try { open(bytes, key, catalogAAD(fence.generation, fence.catalogRevision)) } finally { bytes.fill(0) }
        try {
            val catalog = JSONObject(String(plaintext, Charsets.UTF_8))
            require(catalog.keys().asSequence().toSet() == setOf("manifest", "records", "denies"))
            if (authenticateOnly) return catalog
            val manifest = catalog.getJSONObject("manifest")
            AutoFillCachePayloadValidator.validate(payload(manifest, JSONArray()), now(), incremental = true, partial = true)
            val entries = references(catalog)
            require(entries.values.sumOf { recordFile(it).length() } + bytes.size <= MAX_BYTES)
            val currentAuthorities = authorities(manifest)
            val currentProfile = profile(manifest)
            require(entries.keys == currentAuthorities.keys)
            for ((id, reference) in entries) {
                validateRetained(reference, currentProfile, currentAuthorities.getValue(id), id)
                // Verify every retained ciphertext's presence/integrity without opening its body.
                checkedBytes(recordFile(reference), reference.getString("digest")).fill(0)
            }
            return catalog
        } finally { plaintext.fill(0) }
    }

    private fun validateRetained(reference: JSONObject, currentProfile: String, after: Pair<JSONObject, JSONObject>, id: String) {
        val original = reference.getJSONObject("authority")
        require(profile(original) == currentProfile)
        val before = authorities(original).getValue(id)
        require(canonical(before.second) == canonical(after.second))
        fun binding(vault: JSONObject): String = canonical(without(vault, setOf("entries", "issuedAt", "notAfter")))
        require(binding(before.first) == binding(after.first))
        if (now() >= minOf(expiry(before.first), expiry(after.first))) recovery()
    }

    private fun active(generation: Long): AutoFillFence {
        val fence = readFence() ?: recovery()
        if (fence.generation != generation) stale()
        if (fence.state != "active") recovery()
        return fence
    }

    private fun checkEpoch(expectedEpoch: Long, generation: Long) = synchronized(writerLock) {
        if (epoch != expectedEpoch || writerGeneration != generation) throw AutoFillIncrementalException("AUTOFILL_WRITER_INVALIDATED")
    }

    private fun checkedBytes(file: File, expectedDigest: String): ByteArray {
        require(file.isFile && file.length() in 1..MAX_BYTES)
        val bytes = file.readBytes()
        if (digest(bytes) != expectedDigest) { bytes.fill(0); throw IllegalArgumentException("Invalid AutoFill ciphertext") }
        return bytes
    }
    private fun recordFile(reference: JSONObject): File = reference.getString("file").also { require(RECORD_FILE.matches(it)) }.let { File(directory, it) }
    private fun references(catalog: JSONObject): LinkedHashMap<String, JSONObject> {
        val raw = catalog.getJSONArray("records")
        require(raw.length() <= 2_000)
        val result = linkedMapOf<String, JSONObject>()
        for (index in 0 until raw.length()) {
            val value = raw.getJSONObject(index)
            require(result.put(value.getString("coordinate"), value) == null)
        }
        return result
    }
    private fun deniedCoordinates(catalog: JSONObject): Set<String> = catalog.getJSONObject("denies").let { denies ->
        denies.keys().asSequence().flatMap { strings(denies.getJSONArray(it)).asSequence() }.toSet()
    }
    private fun coordinates(values: JSONArray): Set<String> {
        val result = mutableSetOf<String>()
        for (index in 0 until values.length()) {
            val value = values.getJSONObject(index)
            require(value.keys().asSequence().toSet() == setOf("vaultId", "entryId"))
            require(value.getString("vaultId").isNotEmpty() && value.getString("entryId").isNotEmpty())
            require(result.add(coordinate(value.getString("vaultId"), value.getString("entryId"))))
        }
        return result
    }
    private fun authorities(manifest: JSONObject): Map<String, Pair<JSONObject, JSONObject>> = buildMap {
        val vaults = manifest.getJSONArray("vaults")
        for (v in 0 until vaults.length()) {
            val vault = vaults.getJSONObject(v)
            val entries = vault.getJSONArray("entries")
            for (e in 0 until entries.length()) {
                val entry = entries.getJSONObject(e)
                require(put(coordinate(vault.getString("vaultId"), entry.getString("entryId")), vault to entry) == null)
            }
        }
    }
    private fun singleAuthority(manifest: JSONObject, id: String): JSONObject {
        val (vault, entry) = authorities(manifest).getValue(id)
        return without(manifest, setOf("vaults")).put("vaults", JSONArray().put(without(vault, setOf("entries")).put("entries", JSONArray().put(copy(entry)))))
    }
    private fun profile(manifest: JSONObject): String = canonical(without(manifest, setOf("vaults")))
    private fun expiry(vault: JSONObject): Long = Instant.parse(vault.getString("notAfter")).toEpochMilli()
    private fun payload(manifest: JSONObject, records: JSONArray) = JSONObject().put("version", 3).put("manifest", manifest).put("records", records)
    private fun coordinate(vault: String, entry: String) = canonical(JSONArray().put(vault).put(entry))
    private fun strings(array: JSONArray): Set<String> = (0 until array.length()).map { array.getString(it).also { value -> require(value.isNotEmpty()) } }.toSet()
    private fun positive(raw: JSONObject, key: String): Long {
        val value = raw.get(key)
        require(value is Int || value is Long)
        return (value as Number).toLong().also { require(it > 0) }
    }
    private fun recordAAD(generation: Long, authority: JSONObject) = "palladin-autofill-record-v3:$generation:${canonical(authority)}".toByteArray(Charsets.UTF_8)
    private fun catalogAAD(generation: Long, revision: Long) = "palladin-autofill-catalog-v3:$generation:$revision".toByteArray(Charsets.UTF_8)
    private fun without(value: JSONObject, excluded: Set<String>) = JSONObject().apply { value.keys().asSequence().filterNot { it in excluded }.forEach { put(it, value.get(it)) } }
    private fun requireBoundedJson(value: JSONObject) {
        val bytes = value.toString().toByteArray(Charsets.UTF_8)
        try { require(bytes.size <= MAX_BYTES) } finally { bytes.fill(0) }
    }
    private fun copy(value: JSONObject) = JSONObject(value.toString())
    private fun digest(bytes: ByteArray) = encode(MessageDigest.getInstance("SHA-256").digest(bytes))
    private fun encode(bytes: ByteArray) = Base64.getEncoder().encodeToString(bytes)
    private fun seal(plaintext: ByteArray, key: ByteArray, aad: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"))
        cipher.updateAAD(aad)
        return cipher.iv + cipher.doFinal(plaintext)
    }
    private fun open(bytes: ByteArray, key: ByteArray, aad: ByteArray): ByteArray {
        require(bytes.size > 28)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        cipher.updateAAD(aad)
        return cipher.doFinal(bytes, 12, bytes.size - 12)
    }
    private fun canonical(value: Any?): String = when (value) {
        is JSONObject -> value.keys().asSequence().sorted().joinToString(",", "{", "}") { "${JSONObject.quote(it)}:${canonical(value.get(it))}" }
        is JSONArray -> (0 until value.length()).joinToString(",", "[", "]") { canonical(value.get(it)) }
        is String -> JSONObject.quote(value)
        else -> value.toString()
    }
    private fun recovery(): Nothing = throw AutoFillIncrementalException("AUTOFILL_FULL_RECOVERY_REQUIRED")
    private fun stale(): Nothing = throw AutoFillIncrementalException("AUTOFILL_STALE_BASE")
    companion object {
        private val nextWriterEpoch = AtomicLong(0)
        private const val MAX_BYTES = 16L * 1024L * 1024L
        private val RECORD_FILE = Regex("palladin_autofill_v3_record_[a-f0-9-]{36}")
        private val CATALOG_FILE = Regex("palladin_autofill_v3_catalog_[a-f0-9-]{36}")
    }
}
