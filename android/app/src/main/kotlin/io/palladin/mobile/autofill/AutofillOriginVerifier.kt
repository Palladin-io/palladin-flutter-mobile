package io.palladin.mobile.autofill

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
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

    fun nativeDomains(
        packageName: String,
        reportStatus: (OriginStatus) -> Unit = {},
    ): Set<String>? {
        fun reject(status: OriginStatus): Set<String>? {
            reportStatus(status)
            return null
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return reject(OriginStatus.QUERY_UNAVAILABLE)
        if (isBrowser(packageName)) return reject(OriginStatus.UNVERIFIED)
        val state = runCatching {
            context.getSystemService(DomainVerificationManager::class.java)
                .getDomainVerificationUserState(packageName)
        }.getOrNull() ?: return reject(OriginStatus.QUERY_UNAVAILABLE)
        if (!state.isLinkHandlingAllowed) return reject(OriginStatus.LINK_HANDLING_DISABLED)
        val domains = state.hostToStateMap.filterValues {
            it == DomainVerificationUserState.DOMAIN_STATE_VERIFIED
        }.keys.mapNotNull(AutoFillCacheStore::normalizeDomain).toSet()
        reportStatus(if (domains.isEmpty()) OriginStatus.UNVERIFIED else OriginStatus.VERIFIED)
        return domains
    }

    fun isBrowser(packageName: String): Boolean {
        if (isKnownBrowserPackage(packageName)) return true
        // A package's own verified links do not identify a page inside a browser.
        // Query only this package's all-host HTTPS capability; no URL is opened.
        return runCatching {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://example.invalid"))
                .addCategory(Intent.CATEGORY_BROWSABLE)
                .setPackage(packageName)
            context.packageManager.queryIntentActivities(
                intent,
                PackageManager.MATCH_ALL,
            ).isNotEmpty()
        }.getOrDefault(true)
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
