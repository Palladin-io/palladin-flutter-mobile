package io.palladin.mobile.autofill

import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.verify.domain.DomainVerificationManager
import android.content.pm.verify.domain.DomainVerificationUserState
import android.os.Build

/** Verifies that a requesting Android package is authorized for a web domain. */
internal class AutofillOriginVerifier(private val context: Context) {
    fun isVerified(packageName: String, domain: String): Boolean {
        return status(packageName, domain) == OriginStatus.VERIFIED
    }

    fun status(packageName: String, domain: String): OriginStatus {
        if (isTrustedSystemBrowser(packageName)) return OriginStatus.VERIFIED
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return OriginStatus.QUERY_UNAVAILABLE

        val manager = context.getSystemService(DomainVerificationManager::class.java)
        val state = runCatching {
            manager.getDomainVerificationUserState(packageName)
        }.getOrNull() ?: return OriginStatus.QUERY_UNAVAILABLE
        if (!state.isLinkHandlingAllowed) return OriginStatus.LINK_HANDLING_DISABLED
        return if (state.hostToStateMap[domain] == DomainVerificationUserState.DOMAIN_STATE_VERIFIED) {
            OriginStatus.VERIFIED
        } else {
            OriginStatus.UNVERIFIED
        }
    }

    private fun isTrustedSystemBrowser(packageName: String): Boolean {
        if (!isKnownBrowserPackage(packageName)) return false
        val applicationInfo = runCatching {
            context.packageManager.getApplicationInfo(packageName, 0)
        }.getOrNull() ?: return false
        return hasTrustedSystemIdentity(applicationInfo.flags)
    }

    companion object {
        private val KNOWN_BROWSER_PACKAGES = setOf("com.android.chrome")
        private const val SYSTEM_APP_FLAGS =
            ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP

        internal fun isKnownBrowserPackage(packageName: String): Boolean =
            packageName in KNOWN_BROWSER_PACKAGES

        internal fun hasTrustedSystemIdentity(applicationFlags: Int): Boolean =
            applicationFlags and SYSTEM_APP_FLAGS != 0
    }
}
