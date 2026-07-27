package io.palladin.mobile.autofill

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.SecureRandom
import java.security.spec.MGF1ParameterSpec
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.OAEPParameterSpec
import javax.crypto.spec.PSource
import javax.crypto.spec.SecretKeySpec
import android.util.Base64

internal data class CachedCredential(
    val id: String,
    val label: String,
    val username: String,
    val password: String,
    val domains: List<String>,
)

internal class AutoFillCacheStore(private val context: Context) {
    private val cacheFile: File
        get() = File(context.noBackupFilesDir, CACHE_FILE_NAME)

    fun hasCache(): Boolean = cacheFile.isFile

    fun beginSession(): Long = synchronized(MUTATION_LOCK) {
        currentSessionToken += 1
        accessRevoked = false
        currentSessionToken
    }

    fun replace(rawRecords: List<*>?, sessionToken: Long) {
        synchronized(MUTATION_LOCK) {
            if (accessRevoked || sessionToken != currentSessionToken) {
                return@synchronized
            }
            require(rawRecords.orEmpty().size <= MAX_RECORDS)
            val records = rawRecords.orEmpty().mapNotNull(::validatedRecord)
            val plaintext = JSONArray().apply {
                records.forEach { put(it) }
            }.toString().toByteArray(Charsets.UTF_8)
            val dataKey = ByteArray(DATA_KEY_BYTES).also(SecureRandom()::nextBytes)

            try {
                val contentCipher = Cipher.getInstance(AES_TRANSFORMATION)
                contentCipher.init(
                    Cipher.ENCRYPT_MODE,
                    SecretKeySpec(dataKey, KeyProperties.KEY_ALGORITHM_AES),
                )
                val ciphertext = contentCipher.doFinal(plaintext)

                val wrapCipher = rsaCipher()
                wrapCipher.init(
                    Cipher.ENCRYPT_MODE,
                    getOrCreateKeyPair().certificate.publicKey,
                    OAEP_PARAMETERS,
                )
                val wrappedKey = wrapCipher.doFinal(dataKey)
                val envelope = JSONObject()
                    .put("version", CACHE_VERSION)
                    .put("wrappedKey", wrappedKey.toBase64())
                    .put("nonce", contentCipher.iv.toBase64())
                    .put("ciphertext", ciphertext.toBase64())
                    .toString()
                    .toByteArray(Charsets.UTF_8)
                writeAtomically(envelope)
                envelope.fill(0)
                ciphertext.fill(0)
                wrappedKey.fill(0)
            } finally {
                plaintext.fill(0)
                dataKey.fill(0)
            }
        }
    }

    fun clear() {
        synchronized(MUTATION_LOCK) { clearLocked() }
    }

    fun clear(sessionToken: Long) {
        synchronized(MUTATION_LOCK) {
            if (sessionToken != currentSessionToken) return@synchronized
            clearLocked()
        }
    }

    fun revokeAccess(): Long = synchronized(MUTATION_LOCK) {
        currentSessionToken += 1
        accessRevoked = true
        clearLocked()
        currentSessionToken
    }

    private fun clearLocked() {
        val files = listOf(
            cacheFile,
            File(cacheFile.parentFile, "$CACHE_FILE_NAME.tmp"),
        )
        val failedFile = files.firstOrNull { it.exists() && !it.delete() }
        val keyStore = loadKeyStore()
        if (keyStore.containsAlias(KEY_ALIAS)) keyStore.deleteEntry(KEY_ALIAS)
        if (failedFile != null) {
            throw IOException("Unable to remove AutoFill cache")
        }
    }

    fun createUnwrapCipher(): Cipher {
        val privateKey = loadKeyStore().getKey(KEY_ALIAS, null)
            ?: throw IllegalStateException("AutoFill key is unavailable")
        return rsaCipher().apply {
            init(Cipher.DECRYPT_MODE, privateKey, OAEP_PARAMETERS)
        }
    }

    fun decrypt(cipher: Cipher): MutableList<CachedCredential> {
        require(cacheFile.length() in 1..MAX_CACHE_BYTES)
        val envelope = JSONObject(cacheFile.readText(Charsets.UTF_8))
        require(envelope.getInt("version") == CACHE_VERSION)
        val wrappedKey = envelope.getString("wrappedKey").fromBase64()
        val nonce = envelope.getString("nonce").fromBase64()
        val ciphertext = envelope.getString("ciphertext").fromBase64()
        val dataKey = cipher.doFinal(wrappedKey)

        try {
            val contentCipher = Cipher.getInstance(AES_TRANSFORMATION)
            contentCipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(dataKey, KeyProperties.KEY_ALGORITHM_AES),
                GCMParameterSpec(GCM_TAG_BITS, nonce),
            )
            val plaintext = contentCipher.doFinal(ciphertext)
            return try {
                parseRecords(JSONArray(String(plaintext, Charsets.UTF_8)))
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

    private fun getOrCreateKeyPair(): KeyStore.PrivateKeyEntry {
        val keyStore = loadKeyStore()
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.PrivateKeyEntry)?.let {
            return it
        }

        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_DECRYPT,
        )
            .setKeySize(RSA_KEY_BITS)
            .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA1)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_OAEP)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }

        KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_RSA,
            ANDROID_KEY_STORE,
        ).apply {
            initialize(builder.build())
            generateKeyPair()
        }
        return loadKeyStore().getEntry(KEY_ALIAS, null) as KeyStore.PrivateKeyEntry
    }

    private fun validatedRecord(raw: Any?): JSONObject? {
        val map = raw as? Map<*, *> ?: return null
        val id = (map["id"] as? String)?.takeIf(String::isNotBlank) ?: return null
        val label = (map["label"] as? String)?.takeIf(String::isNotBlank) ?: return null
        val username = map["username"] as? String ?: return null
        val password = (map["password"] as? String)?.takeIf(String::isNotEmpty) ?: return null
        val domains = ((map["domains"] as? List<*>)
            .orEmpty()
            .takeIf { it.size <= MAX_DOMAINS_PER_RECORD }
            ?: return null)
            .mapNotNull { normalizeDomain(it as? String) }
            .distinct()
        if (domains.isEmpty()) return null
        return JSONObject()
            .put("id", id)
            .put("label", label)
            .put("username", username)
            .put("password", password)
            .put("domains", JSONArray(domains))
    }

    private fun parseRecords(array: JSONArray): MutableList<CachedCredential> {
        val records = mutableListOf<CachedCredential>()
        for (index in 0 until array.length()) {
            val item = array.optJSONObject(index) ?: continue
            val password = item.optString("password")
            val domainsJson = item.optJSONArray("domains") ?: continue
            val domains = buildList {
                for (domainIndex in 0 until domainsJson.length()) {
                    normalizeDomain(domainsJson.optString(domainIndex))?.let(::add)
                }
            }.distinct()
            if (password.isEmpty() || domains.isEmpty()) continue
            records += CachedCredential(
                id = item.optString("id"),
                label = item.optString("label"),
                username = item.optString("username"),
                password = password,
                domains = domains,
            )
        }
        return records
    }

    private fun writeAtomically(bytes: ByteArray) {
        val target = cacheFile
        target.parentFile?.mkdirs()
        val temporary = File(target.parentFile, "$CACHE_FILE_NAME.tmp")
        FileOutputStream(temporary).use { output ->
            output.write(bytes)
            output.fd.sync()
        }
        bytes.fill(0)
        check(temporary.renameTo(target)) { "Unable to replace AutoFill cache" }
    }

    private fun loadKeyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }

    private fun rsaCipher(): Cipher = Cipher.getInstance(RSA_TRANSFORMATION)

    companion object {
        private val MUTATION_LOCK = Any()
        private var accessRevoked = true
        private var currentSessionToken = 0L

        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "palladin_autofill_wrap_v1"
        private const val CACHE_FILE_NAME = "palladin_autofill_cache_v1"
        private const val CACHE_VERSION = 1
        private const val DATA_KEY_BYTES = 32
        private const val RSA_KEY_BITS = 2048
        private const val GCM_TAG_BITS = 128
        private const val MAX_RECORDS = 2000
        private const val MAX_DOMAINS_PER_RECORD = 16
        private const val MAX_CACHE_BYTES = 16L * 1024 * 1024
        private const val AES_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val RSA_TRANSFORMATION = "RSA/ECB/OAEPWithSHA-256AndMGF1Padding"
        private val OAEP_PARAMETERS = OAEPParameterSpec(
            "SHA-256",
            "MGF1",
            MGF1ParameterSpec.SHA1,
            PSource.PSpecified.DEFAULT,
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
                            !(character in 'a'..'z' || character in '0'..'9' || character == '-')
                        }
                }
            ) return null
            return value
        }

        fun domainMatches(requested: String, stored: String): Boolean =
            requested == stored

        private fun ByteArray.toBase64(): String =
            Base64.encodeToString(this, Base64.NO_WRAP)

        private fun String.fromBase64(): ByteArray =
            Base64.decode(this, Base64.NO_WRAP)
    }
}
