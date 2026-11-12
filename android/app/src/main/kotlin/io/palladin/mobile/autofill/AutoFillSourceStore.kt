package io.palladin.mobile.autofill

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.Base64

internal data class AutoFillSourceProfile(
    val principalId: String, val organizationId: String,
    val organizationMembershipGeneration: String, val offlinePolicy: String,
    val offlinePolicyVersion: Int, val profileBinding: String,
) {
    fun digest(): String {
        require(principalId.isNotBlank() && organizationId.isNotBlank() &&
            organizationMembershipGeneration.isNotBlank() && offlinePolicy.isNotBlank() &&
            offlinePolicyVersion > 0 && profileBinding.matches(Regex("[a-f0-9]{64}")))
        val bytes = org.json.JSONArray().put(principalId).put(organizationId)
            .put(organizationMembershipGeneration).put(offlinePolicy).put(offlinePolicyVersion)
            .put(profileBinding).toString().toByteArray(Charsets.UTF_8)
        return Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-256").digest(bytes))
    }
}

internal object AutoFillSourceFenceCodec {
    private fun body(fence: AutoFillSourceFence, version: Int = 2) = JSONObject().put("version", version)
        .put("epoch", fence.epoch).put("profile", fence.profile).put("active", fence.active).apply {
            if (version == 2) {
                put("accountUnlockDigest", fence.accountUnlockDigest ?: JSONObject.NULL)
                put("configuration", fence.configuration?.wire()?.let { JSONObject(it) } ?: JSONObject.NULL)
            }
        }.toString().toByteArray(Charsets.UTF_8)
    fun encode(fence: AutoFillSourceFence, sign: (ByteArray) -> ByteArray): ByteArray {
        require(fence.epoch > 0 && fence.profile.isNotBlank())
        val payload = body(fence)
        val mac = sign(payload)
        return try { JSONObject(String(payload, Charsets.UTF_8)).put("mac", Base64.getEncoder().encodeToString(mac)).toString().toByteArray(Charsets.UTF_8) }
        finally { payload.fill(0); mac.fill(0) }
    }
    fun decode(bytes: ByteArray, sign: (ByteArray) -> ByteArray): AutoFillSourceFence {
        val value = JSONObject(String(bytes, Charsets.UTF_8))
        val version = value.getInt("version")
        require(version in 1..2 && value.get("active") is Boolean)
        val fields = setOf("version", "epoch", "profile", "active", "mac") +
            if (version == 2) setOf("accountUnlockDigest", "configuration") else emptySet()
        require(value.keys().asSequence().toSet() == fields)
        val epoch = value.get("epoch")
        require(epoch is Int || epoch is Long)
        val digest = if (version == 2 && !value.isNull("accountUnlockDigest")) value.getString("accountUnlockDigest") else null
        if (digest != null) require(Base64.getDecoder().decode(digest).size == 32)
        val config = if (version == 2 && !value.isNull("configuration")) AutoFillSourceConfiguration.decode(value.getJSONObject("configuration")) else null
        val fence = AutoFillSourceFence((epoch as Number).toLong(), value.getString("profile"), value.getBoolean("active"), digest, config)
        require(fence.epoch > 0 && fence.profile.isNotBlank())
        if (config != null) require(config.profile.digest() == fence.profile && config.accountUnlockDigest == digest)
        val payload = body(fence, version)
        val expected = sign(payload)
        val actual = Base64.getDecoder().decode(value.getString("mac"))
        try { require(MessageDigest.isEqual(expected, actual)); return fence }
        finally { payload.fill(0); expected.fill(0); actual.fill(0) }
    }
}

internal class AutoFillSourceStore(context: Context) {
    private val file = File(context.noBackupFilesDir, "palladin_autofill_source_fence_v1")
    private val integrity = AutoFillCacheStore(context)
    val authority = AutoFillSourceAuthority(::read, ::write)
    private fun read(): AutoFillSourceFence? {
        try {
            if (!file.exists()) return null
            require(file.isFile && file.length() in 1..65536)
            val bytes = file.readBytes()
            return try { AutoFillSourceFenceCodec.decode(bytes, integrity::sourceControlMac) }
            finally { bytes.fill(0) }
        } catch (_: Exception) { throw AutoFillSourceException("SOURCE_UNAVAILABLE") }
    }
    private fun write(value: AutoFillSourceFence) {
        val bytes = AutoFillSourceFenceCodec.encode(value, integrity::sourceControlMac)
        try { require(bytes.size <= 65536); AutoFillAtomicFileWriter.write(file, bytes) }
        catch (_: Exception) { throw AutoFillSourceException("SOURCE_UNAVAILABLE") }
        finally { bytes.fill(0) }
    }
}
