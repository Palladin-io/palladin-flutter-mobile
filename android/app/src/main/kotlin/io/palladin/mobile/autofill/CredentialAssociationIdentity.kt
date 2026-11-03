package io.palladin.mobile.autofill

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.SystemClock
import java.security.MessageDigest

/** Independent installed identity; never accepts certificate material from a form or Intent. */
internal object CredentialAssociationIdentity {
    private val proofs = CredentialAssociationProofs(SystemClock::elapsedRealtime)

    fun current(context: Context, packageName: String, host: String): CredentialAssociationKey? = runCatching {
        if (Build.VERSION.SDK_INT < 31 || AutoFillCacheStore.normalizeDomain(host) != host ||
            host.length > 253 || !host.matches(Regex("[a-z0-9.-]+")) ||
            host.split('.').size < 2 || host.none { it in 'a'..'z' } ||
            host.substringAfterLast('.') in setOf("local", "localhost", "internal", "invalid", "test", "example")) return null
        val info = context.packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        val signers = info.signingInfo?.apkContentsSigners ?: return null
        if (signers.isEmpty() || signers.size > 8) return null
        val hashes = signers.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
                .joinToString(":") { "%02X".format(it.toInt() and 255) }
        }.toSet()
        CredentialAssociationKey(host, packageName, hashes)
    }.getOrNull()

    fun isVerified(context: Context, packageName: String, host: String): Boolean =
        current(context, packageName, host)?.let(proofs::contains) == true

    fun acceptIfCurrent(context: Context, key: CredentialAssociationKey): Boolean {
        if (current(context, key.packageName, key.host) != key) return false
        proofs.accept(key)
        return true
    }
}

internal fun credentialAssociationHost(
    fields: PalladinAutofillService.CredentialFieldIds,
    domains: Set<String>,
    schemes: Set<String>,
): String? {
    if (fields.usernameIds.isEmpty() && fields.passwordIds.isEmpty() ||
        fields.newPasswordIds.isNotEmpty() || fields.confirmationIds.isNotEmpty()) return null
    if (schemes.isEmpty() || !schemes.all(AutofillOriginPolicy::isSecureWebScheme)) return null
    return domains.map { AutoFillCacheStore.normalizeDomain(it) ?: return null }.toSet().singleOrNull()
}
