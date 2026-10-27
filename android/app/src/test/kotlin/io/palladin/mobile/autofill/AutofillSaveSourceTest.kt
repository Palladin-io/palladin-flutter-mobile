package io.palladin.mobile.autofill

import org.junit.Assert.*
import org.junit.Test

class AutofillSaveSourceTest {
    private val web = AutofillSaveSource("package", setOf("signature"),
        AutofillOriginMode.WEB, setOf("login.example.com"), setOf("https"))
    @Test fun continuityRejectsEveryIndependentSourceChange() {
        assertTrue(web.matches(web))
        assertFalse(web.matches(web.copy(packageName = "other")))
        assertFalse(web.matches(web.copy(signatures = setOf("replacement"))))
        assertFalse(web.matches(web.copy(domains = setOf("other.example.com"))))
        assertFalse(web.matches(web.copy(schemes = setOf("http"))))
        assertFalse(web.matches(web.copy(schemes = emptySet())))
        assertFalse(web.matches(web.copy(mode = AutofillOriginMode.VERIFIED_NATIVE)))
    }
    @Test fun nativeNeverClaimsHttpsAndUnknownNativeFailsClosed() {
        val native = web.copy(mode = AutofillOriginMode.VERIFIED_NATIVE, schemes = emptySet())
        assertTrue(native.isEligible)
        assertFalse(native.copy(mode = AutofillOriginMode.MANUAL_NATIVE).isEligible)
        assertFalse(native.copy(domains = emptySet()).isEligible)
        assertFalse(native.copy(schemes = setOf("https")).isEligible)
        assertFalse(web.copy(signatures = emptySet()).isEligible)
    }
}
