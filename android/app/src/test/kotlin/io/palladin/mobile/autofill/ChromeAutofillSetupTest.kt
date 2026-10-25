package io.palladin.mobile.autofill

import org.junit.Assert.assertEquals
import org.junit.Test

class ChromeAutofillSetupTest {
    @Test
    fun disabledChromeDoesNotInheritOsProviderSelection() {
        assertEquals("disabled", ChromeAutofillSetup { 0 }.status())
        assertEquals("enabled", ChromeAutofillSetup { 1 }.status())
    }

    @Test
    fun absentOrOldChromeDoesNotRequireConfiguration() {
        assertEquals("unavailable", ChromeAutofillSetup { null }.status())
    }

    @Test
    fun unexpectedProviderValuesNeverClaimChromeIsEnabled() {
        assertEquals("unknown", ChromeAutofillSetup { 2 }.status())
        assertEquals("unknown", ChromeAutofillSetup { -1 }.status())
    }

    @Test
    fun queryFailureNeverClaimsChromeIsEnabled() {
        assertEquals("unknown", ChromeAutofillSetup { throw SecurityException() }.status())
        assertEquals("unknown", ChromeAutofillSetup { throw IllegalStateException() }.status())
    }
}
