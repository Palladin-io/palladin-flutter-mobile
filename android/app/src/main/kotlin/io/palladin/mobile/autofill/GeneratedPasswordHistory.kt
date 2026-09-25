package io.palladin.mobile.autofill

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.spec.MGF1ParameterSpec
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec

internal data class GeneratedPasswordRecord(
    val id: String,
    val domain: String,
    val createdAtMillis: Long,
    val password: String,
)

internal data class GeneratedHistoryUnwrapOperation(
    val principalId: String,
    val sessionToken: String,
    val wrappedKey: ByteArray,
    val cipher: Cipher,
)

internal object StrongPasswordGenerator {
    private const val LOWER = "abcdefghijklmnopqrstuvwxyz"
    private const val UPPER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    private const val DIGITS = "0123456789"
    private const val SYMBOLS = "!@#$%^&*()-_=+[]{};:,.?/"
    private const val ALPHABET = LOWER + UPPER + DIGITS + SYMBOLS
    private val random = SecureRandom()

    fun generate(): String {
        val chars = CharArray(20)
        chars[0] = LOWER[random.nextInt(LOWER.length)]
        chars[1] = UPPER[random.nextInt(UPPER.length)]
        chars[2] = DIGITS[random.nextInt(DIGITS.length)]
        chars[3] = SYMBOLS[random.nextInt(SYMBOLS.length)]
        for (index in 4 until chars.size) chars[index] = ALPHABET[random.nextInt(ALPHABET.length)]
        for (index in chars.lastIndex downTo 1) {
            val other = random.nextInt(index + 1)
            val previous = chars[index]
            chars[index] = chars[other]
            chars[other] = previous
        }
        return String(chars)
    }
}

/** The per-use biometric RSA key unwraps a stable random history key. The history
 * survives disposable Vault cache generations without persisting a client Vault key.
 */
internal class GeneratedPasswordHistory(context: Context) {
    private val directory = context.noBackupFilesDir
    private val sessionFile = File(directory, "generated-password-session-v1")
    private val random = SecureRandom()

    fun activate(principalId: String): String = synchronized(AutoFillMutationLock.monitor) {
        require(principalId.isNotBlank() && principalId.length <= 128)
        ensureBiometricKey()
        val token = UUID.randomUUID().toString()
        val body = JSONObject().put("version", 1).put("principalId", principalId)
            .put("token", token).toString()
        val signature = sign(body.toByteArray(Charsets.UTF_8))
        AutoFillAtomicFileWriter.write(
            sessionFile,
            JSONObject().put("body", body).put("mac", encode(signature))
                .toString().toByteArray(Charsets.UTF_8),
        )
        token
    }

    fun revoke(token: String) = synchronized(AutoFillMutationLock.monitor) {
        if (sessionFile.exists() && readMarkerLocked().getString("token") == token) {
            check(sessionFile.delete())
        }
    }

    fun revokeAll() = synchronized(AutoFillMutationLock.monitor) {
        if (sessionFile.exists()) check(sessionFile.delete())
    }

    fun hasActiveSession(): Boolean = synchronized(AutoFillMutationLock.monitor) {
        runCatching {
            activePrincipalLocked()
            keyStore().containsAlias(HISTORY_KEY_ALIAS)
        }.getOrDefault(false)
    }

    fun createUnwrapOperation(expectedPrincipal: String? = null): GeneratedHistoryUnwrapOperation =
        synchronized(AutoFillMutationLock.monitor) {
            val marker = readMarkerLocked()
            val principal = marker.getString("principalId")
            if (expectedPrincipal != null) require(principal == expectedPrincipal)
            val keyEntry = keyStore().getEntry(HISTORY_KEY_ALIAS, null) as? KeyStore.PrivateKeyEntry
                ?: throw IllegalStateException("Generated-password key is unavailable")
            val file = historyFile(principal)
            val wrappedKey = if (file.exists()) {
                readEnvelopeLocked(principal).getString("wrappedKey").decode()
            } else {
                val freshKey = ByteArray(32).also(random::nextBytes)
                try {
                    rsaCipher().apply {
                        init(Cipher.ENCRYPT_MODE, keyEntry.certificate.publicKey, OAEP_PARAMETERS)
                    }.doFinal(freshKey)
                } finally {
                    freshKey.fill(0)
                }
            }
            GeneratedHistoryUnwrapOperation(
                principal,
                marker.getString("token"),
                wrappedKey,
                rsaCipher().apply {
                    init(Cipher.DECRYPT_MODE, keyEntry.privateKey, OAEP_PARAMETERS)
                },
            )
        }

    fun appendAuthenticated(
        operation: GeneratedHistoryUnwrapOperation,
        authenticatedCipher: Cipher,
        domain: String,
        password: String,
        handoff: () -> Unit = {},
    ): GeneratedPasswordRecord = withAuthenticatedKey(operation, authenticatedCipher) { key ->
        require(AutoFillCacheStore.normalizeDomain(domain) == domain)
        require(password.length == 20)
        val records = readLocked(operation, key)
        check(records.size < MAX_RECORDS) { "Generated password history is full" }
        val record = GeneratedPasswordRecord(
            UUID.randomUUID().toString(), domain, System.currentTimeMillis(), password,
        )
        records += record
        writeLocked(operation, key, records)
        val currentMarker = readMarkerLocked()
        require(currentMarker.getString("principalId") == operation.principalId)
        require(currentMarker.getString("token") == operation.sessionToken)
        handoff()
        record
    }

    fun readAuthenticated(
        operation: GeneratedHistoryUnwrapOperation,
        authenticatedCipher: Cipher,
    ): List<GeneratedPasswordRecord> = withAuthenticatedKey(operation, authenticatedCipher) { key ->
        readLocked(operation, key)
    }

    fun deleteAuthenticated(
        operation: GeneratedHistoryUnwrapOperation,
        authenticatedCipher: Cipher,
        id: String,
    ) = withAuthenticatedKey(operation, authenticatedCipher) { key ->
        val records = readLocked(operation, key)
        check(records.removeAll { it.id == id })
        writeLocked(operation, key, records)
    }

    fun clearAuthenticated(
        operation: GeneratedHistoryUnwrapOperation,
        authenticatedCipher: Cipher,
    ) = withAuthenticatedKey(operation, authenticatedCipher) { key ->
        readLocked(operation, key)
        writeLocked(operation, key, emptyList())
    }

    private fun <T> withAuthenticatedKey(
        operation: GeneratedHistoryUnwrapOperation,
        authenticatedCipher: Cipher,
        action: (ByteArray) -> T,
    ): T = synchronized(AutoFillMutationLock.monitor) {
        val currentMarker = readMarkerLocked()
        require(currentMarker.getString("principalId") == operation.principalId)
        require(currentMarker.getString("token") == operation.sessionToken)
        val file = historyFile(operation.principalId)
        if (file.exists()) {
            val current = readEnvelopeLocked(operation.principalId).getString("wrappedKey").decode()
            require(MessageDigest.isEqual(current, operation.wrappedKey))
        }
        val key = authenticatedCipher.doFinal(operation.wrappedKey)
        try {
            require(key.size == 32)
            action(key)
        } finally {
            key.fill(0)
            operation.wrappedKey.fill(0)
        }
    }

    private fun readLocked(
        operation: GeneratedHistoryUnwrapOperation,
        key: ByteArray,
    ): MutableList<GeneratedPasswordRecord> {
        val file = historyFile(operation.principalId)
        if (!file.exists()) return mutableListOf()
        val envelope = readEnvelopeLocked(operation.principalId)
        val nonce = envelope.getString("nonce").decode()
        require(nonce.size == 12)
        val cipher = Cipher.getInstance(AES_TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(aad(operation.principalId))
        val plaintext = cipher.doFinal(envelope.getString("ciphertext").decode())
        try {
            val payload = JSONObject(String(plaintext, Charsets.UTF_8))
            require(payload.keys().asSequence().toSet() == setOf("version", "principalId", "records"))
            require(payload.getInt("version") == 1)
            require(payload.getString("principalId") == operation.principalId)
            val records = payload.getJSONArray("records")
            require(records.length() <= MAX_RECORDS)
            val ids = mutableSetOf<String>()
            return MutableList(records.length()) { index ->
                val raw = records.getJSONObject(index)
                require(raw.keys().asSequence().toSet() == RECORD_FIELDS)
                val id = raw.getString("id")
                val domain = raw.getString("domain")
                val password = raw.getString("password")
                require(ids.add(id) && AutoFillCacheStore.normalizeDomain(domain) == domain)
                require(password.length == 20)
                GeneratedPasswordRecord(id, domain, raw.getLong("createdAtMillis"), password)
            }
        } finally {
            plaintext.fill(0)
        }
    }

    private fun writeLocked(
        operation: GeneratedHistoryUnwrapOperation,
        key: ByteArray,
        records: List<GeneratedPasswordRecord>,
    ) {
        val rawRecords = JSONArray()
        records.forEach { record ->
            rawRecords.put(JSONObject().put("id", record.id).put("domain", record.domain)
                .put("createdAtMillis", record.createdAtMillis).put("password", record.password))
        }
        val plaintext = JSONObject().put("version", 1).put("principalId", operation.principalId)
            .put("records", rawRecords).toString().toByteArray(Charsets.UTF_8)
        try {
            val cipher = Cipher.getInstance(AES_TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"))
            cipher.updateAAD(aad(operation.principalId))
            val encrypted = cipher.doFinal(plaintext)
            AutoFillAtomicFileWriter.write(
                historyFile(operation.principalId),
                JSONObject().put("version", 1).put("wrappedKey", encode(operation.wrappedKey))
                    .put("nonce", encode(cipher.iv)).put("ciphertext", encode(encrypted))
                    .toString().toByteArray(Charsets.UTF_8),
            )
        } finally {
            plaintext.fill(0)
        }
    }

    private fun readEnvelopeLocked(principal: String): JSONObject {
        val file = historyFile(principal)
        require(file.length() in 1..MAX_FILE_BYTES)
        val envelope = JSONObject(file.readText(Charsets.UTF_8))
        require(envelope.keys().asSequence().toSet() == ENVELOPE_FIELDS)
        require(envelope.getInt("version") == 1)
        return envelope
    }

    private fun activePrincipalLocked(): String =
        readMarkerLocked().getString("principalId").also { require(it.isNotBlank()) }

    private fun readMarkerLocked(): JSONObject {
        val envelope = JSONObject(sessionFile.readText(Charsets.UTF_8))
        require(envelope.keys().asSequence().toSet() == setOf("body", "mac"))
        val body = envelope.getString("body")
        val actual = envelope.getString("mac").decode()
        val expected = sign(body.toByteArray(Charsets.UTF_8))
        require(MessageDigest.isEqual(actual, expected))
        val marker = JSONObject(body)
        require(marker.keys().asSequence().toSet() == setOf("version", "principalId", "token"))
        require(marker.getInt("version") == 1)
        require(marker.getString("token").isNotBlank())
        return marker
    }

    private fun ensureBiometricKey() {
        val store = keyStore()
        if (store.containsAlias(HISTORY_KEY_ALIAS)) return
        require(directory.listFiles().orEmpty().none {
            it.name.startsWith("generated-password-history-v1-")
        })
        val builder = KeyGenParameterSpec.Builder(
            HISTORY_KEY_ALIAS, KeyProperties.PURPOSE_DECRYPT,
        ).setKeySize(2048)
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
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore")
            .apply { initialize(builder.build()); generateKeyPair() }
    }

    private fun sign(bytes: ByteArray): ByteArray {
        val store = keyStore()
        val key = (store.getKey(SESSION_KEY_ALIAS, null) as? SecretKey) ?: run {
            val spec = KeyGenParameterSpec.Builder(
                SESSION_KEY_ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY,
            ).setDigests(KeyProperties.DIGEST_SHA256).build()
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, "AndroidKeyStore")
                .apply { init(spec) }.generateKey()
        }
        return Mac.getInstance("HmacSHA256").apply { init(key) }.doFinal(bytes)
    }

    private fun historyFile(principal: String): File {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(principal.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
        return File(directory, "generated-password-history-v1-$digest")
    }

    private fun aad(principal: String) = "palladin-generated-passwords-v1:$principal".toByteArray()
    private fun keyStore() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private fun rsaCipher() = Cipher.getInstance("RSA/ECB/OAEPWithSHA-256AndMGF1Padding")
    private fun encode(bytes: ByteArray) = Base64.encodeToString(bytes, Base64.NO_WRAP)
    private fun String.decode() = Base64.decode(this, Base64.DEFAULT)

    companion object {
        private const val HISTORY_KEY_ALIAS = "palladin-generated-password-history-v1"
        private const val SESSION_KEY_ALIAS = "palladin-generated-password-session-v1"
        private const val AES_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val MAX_RECORDS = 100
        private const val MAX_FILE_BYTES = 64 * 1024L
        private val RECORD_FIELDS = setOf("id", "domain", "createdAtMillis", "password")
        private val ENVELOPE_FIELDS = setOf("version", "wrappedKey", "nonce", "ciphertext")
        private val OAEP_PARAMETERS = OAEPParameterSpec(
            "SHA-256", "MGF1", MGF1ParameterSpec.SHA1, PSource.PSpecified.DEFAULT,
        )
    }
}
