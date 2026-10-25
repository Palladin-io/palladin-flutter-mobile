package io.palladin.mobile.autofill

internal data class AutofillOrigin(val domains: Set<String>, val requiresSelection: Boolean)

internal object AutofillOriginPolicy {
    fun canReleaseNative(
        selectedDomain: String,
        recordDomains: Collection<String>,
        requestDomains: Set<String>,
        currentVerifiedDomains: Set<String>?,
    ): Boolean = selectedDomain in recordDomains && selectedDomain in requestDomains &&
        currentVerifiedDomains?.contains(selectedDomain) == true

    fun resolve(
        reportedDomains: Collection<String>,
        normalize: (String) -> String?,
        verifyWebDomain: (String) -> Boolean,
        verifiedNativeDomains: () -> Set<String>?,
        isBrowser: Boolean,
    ): AutofillOrigin? {
        if (reportedDomains.isEmpty()) {
            if (isBrowser) return null
            val native = verifiedNativeDomains()?.mapNotNull(normalize)?.toSet().orEmpty()
            return native.takeIf { it.isNotEmpty() }?.let { AutofillOrigin(it, true) }
        }
        val domains = reportedDomains.map { normalize(it) ?: return null }.toSet()
        val domain = domains.singleOrNull() ?: return null
        return if (verifyWebDomain(domain)) AutofillOrigin(setOf(domain), false) else null
    }
}
