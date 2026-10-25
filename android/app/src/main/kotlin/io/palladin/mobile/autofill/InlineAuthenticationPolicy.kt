package io.palladin.mobile.autofill

internal fun supportsInlineAuthentication(
    sdkVersion: Int,
    maxSuggestionCount: Int,
    supportsVersionOne: Boolean,
): Boolean = sdkVersion >= 30 && maxSuggestionCount > 0 && supportsVersionOne
