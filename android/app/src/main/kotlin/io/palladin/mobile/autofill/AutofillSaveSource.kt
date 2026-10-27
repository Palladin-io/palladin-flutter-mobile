package io.palladin.mobile.autofill

internal data class AutofillSaveSource(
    val packageName: String,
    val signatures: Set<String>,
    val mode: AutofillOriginMode,
    val domains: Set<String>,
    val schemes: Set<String>,
) {
    val isEligible: Boolean get() = packageName.isNotBlank() && signatures.isNotEmpty() &&
        domains.isNotEmpty() && domains.size <= 16 && when (mode) {
            AutofillOriginMode.WEB -> domains.size == 1 && schemes.isNotEmpty() &&
                schemes.all(AutofillOriginPolicy::isSecureWebScheme)
            AutofillOriginMode.VERIFIED_NATIVE -> schemes.isEmpty()
            AutofillOriginMode.MANUAL_NATIVE -> false
        }

    fun matches(current: AutofillSaveSource): Boolean = isEligible && current.isEligible && this == current
}
