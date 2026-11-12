package io.palladin.mobile.autofill

import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.util.Base64

/** Projection of encrypted account material, never tokens or decrypted keys. */
internal data class AutoFillSourceConfiguration(
    val profile: AutoFillSourceProfile,
    private val accountUnlock: Map<String, Any?>,
) {
    val accountUnlockDigest: String = requireNotNull(AutoFillAccountUnlockDigest.from(accountUnlock, profile.principalId))
    fun wire(): Map<String, Any> = mapOf(
        "profileBinding" to profile.profileBinding, "principalId" to profile.principalId,
        "organizationId" to profile.organizationId,
        "organizationMembershipGeneration" to profile.organizationMembershipGeneration,
        "offlinePolicy" to profile.offlinePolicy, "offlinePolicyVersion" to profile.offlinePolicyVersion,
        "accountUnlock" to accountUnlock,
    )
    companion object {
        fun create(profile: AutoFillSourceProfile, material: Any?): AutoFillSourceConfiguration? {
            val canonical = AutoFillAccountUnlockDigest.canonical(material, profile.principalId) ?: return null
            profile.digest()
            return AutoFillSourceConfiguration(profile, canonical)
        }
        fun decode(value: JSONObject): AutoFillSourceConfiguration {
            require(value.keys().asSequence().toSet() == setOf("profileBinding", "principalId", "organizationId",
                "organizationMembershipGeneration", "offlinePolicy", "offlinePolicyVersion", "accountUnlock"))
            val version = value.get("offlinePolicyVersion")
            require(version is Int || version is Long)
            val profile = AutoFillSourceProfile(value.getString("principalId"), value.getString("organizationId"),
                value.getString("organizationMembershipGeneration"), value.getString("offlinePolicy"),
                Math.toIntExact((version as Number).toLong()), value.getString("profileBinding"))
            fun map(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { key ->
                when (val item = json.get(key)) { is JSONObject -> map(item); JSONObject.NULL -> null; else -> item }
            }
            return requireNotNull(create(profile, map(value.getJSONObject("accountUnlock"))))
        }
    }
}

internal object AutoFillAccountUnlockDigest {
    private val kdfFields = setOf("securityVersion", "minimumSecurityVersion", "profileId", "kdfSalt", "credentialRevision", "privateKeyWrapRevision")
    fun canonical(value: Any?, principal: String): Map<String, Any?>? = runCatching {
        val account = value as? Map<*, *> ?: return null
        require(account.keys == setOf("accountId", "encryptedPrivateKey", "kdf"))
        require(account["accountId"] == principal && principal.isNotBlank())
        val encrypted = account["encryptedPrivateKey"] as? String ?: return null
        require(encrypted.isNotBlank())
        val kdf = account["kdf"] as? Map<*, *> ?: return null
        require(kdf.keys.containsAll(kdfFields) && (kdf.keys - kdfFields).all { it == "deviceWrapperMetadata" })
        fun integer(key: String): Long {
            val number = kdf[key]
            require(number is Int || number is Long)
            return (number as Number).toLong()
        }
        fun string(key: String) = (kdf[key] as? String)?.takeIf { it.isNotBlank() } ?: error("Invalid account projection")
        val metadata = kdf["deviceWrapperMetadata"]
        require(metadata == null || metadata is String)
        val canonicalKdf = linkedMapOf<String, Any?>("securityVersion" to integer("securityVersion"),
            "minimumSecurityVersion" to integer("minimumSecurityVersion"), "profileId" to string("profileId"),
            "kdfSalt" to string("kdfSalt"), "credentialRevision" to integer("credentialRevision"),
            "privateKeyWrapRevision" to integer("privateKeyWrapRevision"))
        if (metadata != null) canonicalKdf["deviceWrapperMetadata"] = metadata
        mapOf("accountId" to principal, "encryptedPrivateKey" to encrypted, "kdf" to canonicalKdf)
    }.getOrNull()

    fun from(value: Any?, principal: String): String? {
        val account = canonical(value, principal) ?: return null
        val kdf = account["kdf"] as Map<*, *>
        val bytes = JSONArray().put("palladin-account-unlock-v1").put(account["accountId"])
            .put(account["encryptedPrivateKey"]).put(kdf["securityVersion"]).put(kdf["minimumSecurityVersion"])
            .put(kdf["profileId"]).put(kdf["kdfSalt"]).put(kdf["credentialRevision"])
            .put(kdf["privateKeyWrapRevision"]).put(kdf["deviceWrapperMetadata"] ?: JSONObject.NULL)
            .toString().toByteArray(Charsets.UTF_8)
        return try { Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-256").digest(bytes)) }
        finally { bytes.fill(0) }
    }
}
