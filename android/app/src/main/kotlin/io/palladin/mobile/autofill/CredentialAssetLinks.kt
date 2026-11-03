package io.palladin.mobile.autofill

import android.util.JsonReader
import android.util.JsonToken
import java.io.StringReader
import java.util.Locale

/** Only a direct HTTPS statement for credential delegation can supply authority. */
internal object CredentialAssetLinks {
    const val MAX_BYTES = 65_536
    private val fingerprint = Regex("(?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}")

    fun authorizes(json: String, packageName: String, currentSigners: Set<String>): Boolean = runCatching {
        if (json.length > MAX_BYTES || currentSigners.isEmpty() || currentSigners.any { !fingerprint.matches(it) }) return false
        val statements = JsonReader(StringReader(json)).use { reader ->
            reader.isLenient = false
            val result = Document(reader).read(0) as? List<*> ?: return false
            require(reader.peek() == JsonToken.END_DOCUMENT)
            result
        }
        require(statements.size <= 128)
        val delegated = mutableSetOf<String>()
        for (value in statements) {
            val statement = value as? Map<*, *> ?: return false
            if ("include" in statement) {
                if (statement.size != 1 || statement["include"] !is String) return false
                continue // Never fetch or derive authority from an include.
            }
            val relations = statement["relation"] as? List<*> ?: return false
            if (relations.size > 16 || relations.any { it !is String }) return false
            val target = statement["target"] as? Map<*, *> ?: return false
            val namespace = target["namespace"] as? String ?: return false
            if (namespace != "android_app") continue
            val targetPackage = target["package_name"] as? String ?: return false
            val certificates = target["sha256_cert_fingerprints"] as? List<*> ?: return false
            if (certificates.isEmpty() || certificates.size > 16) return false
            for (certificate in certificates) {
                if (certificate !is String || !fingerprint.matches(certificate)) return false
                if ("delegate_permission/common.get_login_creds" in relations && targetPackage == packageName) {
                    delegated += certificate.uppercase(Locale.ROOT)
                }
            }
        }
        delegated.containsAll(currentSigners.map { it.uppercase(Locale.ROOT) })
    }.getOrDefault(false)

    private object NumberValue

    private class Document(private val reader: JsonReader) {
        private var nodes = 0
        fun read(depth: Int): Any? {
            require(depth <= 6 && ++nodes <= 4096)
            return when (reader.peek()) {
                JsonToken.BEGIN_ARRAY -> {
                    reader.beginArray()
                    val list = mutableListOf<Any?>()
                    while (reader.hasNext()) { require(list.size < 128); list += read(depth + 1) }
                    reader.endArray()
                    list
                }
                JsonToken.BEGIN_OBJECT -> {
                    reader.beginObject()
                    val map = mutableMapOf<String, Any?>()
                    while (reader.hasNext()) {
                        val key = reader.nextName()
                        require(key.length <= 128 && key !in map && map.size < 16)
                        map[key] = read(depth + 1)
                    }
                    reader.endObject()
                    map
                }
                JsonToken.STRING -> reader.nextString().also { require(it.length <= 2048) }
                JsonToken.BOOLEAN -> reader.nextBoolean()
                JsonToken.NULL -> { reader.nextNull(); null }
                JsonToken.NUMBER -> {
                    require(reader.nextString().length <= 128)
                    NumberValue // Cannot be mistaken for an authority string.
                }
                else -> error("Unsupported statement token")
            }
        }
    }
}
