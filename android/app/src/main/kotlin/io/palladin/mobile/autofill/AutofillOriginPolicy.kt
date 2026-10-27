package io.palladin.mobile.autofill

internal enum class AutofillOriginMode { WEB, VERIFIED_NATIVE, MANUAL_NATIVE }

internal data class AutofillOrigin(val domains: Set<String>, val mode: AutofillOriginMode) {
    val requiresSelection: Boolean get() = mode != AutofillOriginMode.WEB
}

internal object AutofillOriginPolicy {
    fun isSecureWebScheme(scheme: String?): Boolean = scheme?.equals("https", true) == true

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
        reportedSchemes: Collection<String> = emptySet(),
    ): AutofillOrigin? {
        if (reportedDomains.isEmpty()) {
            if (isBrowser || reportedSchemes.isNotEmpty()) return null
            val native = verifiedNativeDomains()?.mapNotNull(normalize)?.toSet().orEmpty()
            return AutofillOrigin(
                native,
                if (native.isEmpty()) AutofillOriginMode.MANUAL_NATIVE else AutofillOriginMode.VERIFIED_NATIVE,
            )
        }
        if (reportedSchemes.isEmpty() || !reportedSchemes.all(::isSecureWebScheme)) return null
        val domains = reportedDomains.map { normalize(it) ?: return null }.toSet()
        val domain = domains.singleOrNull() ?: return null
        return if (verifyWebDomain(domain)) AutofillOrigin(setOf(domain), AutofillOriginMode.WEB) else null
    }
}
