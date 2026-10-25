package io.palladin.mobile.autofill

import org.junit.Assert.*
import org.junit.Test

class AutofillOriginPolicyTest {
    private val normalize: (String) -> String? = { value ->
        value.takeIf { it.matches(Regex("[a-z]+\\.[a-z]+")) }
    }

    @Test fun nativeFormWithoutWebDomainUsesEveryVerifiedExactHost() {
        val origin = resolve(emptyList(), native = setOf("shop.pl", "shop.cz"))
        assertEquals(setOf("shop.pl", "shop.cz"), origin?.domains)
        assertTrue(origin?.requiresSelection == true)
    }

    @Test fun reportedWebHostNeverFallsBackToOtherAppHosts() {
        assertNull(resolve(listOf("evil.pl"), native = setOf("shop.pl"), webVerified = false))
        assertNull(resolve(listOf("invalid"), native = setOf("shop.pl")))
        assertNull(resolve(listOf(""), native = setOf("shop.pl")))
        assertNull(resolve(listOf("shop.pl", "shop.cz"), native = setOf("shop.pl")))
    }

    @Test fun validWebHostStaysAnExactSingleDomain() {
        val origin = resolve(listOf("shop.pl", "shop.pl"), native = setOf("shop.cz"))
        assertEquals(setOf("shop.pl"), origin?.domains)
        assertFalse(origin?.requiresSelection ?: true)
    }

    @Test fun browserWithoutWebHostIsRejectedButUnknownNativeAuthorityAllowsManualChoice() {
        assertNull(resolve(emptyList(), native = setOf("shop.pl"), browser = true))
        assertEquals(AutofillOriginMode.MANUAL_NATIVE, resolve(emptyList(), native = emptySet())?.mode)
        assertEquals(AutofillOriginMode.MANUAL_NATIVE, resolve(emptyList(), native = null)?.mode)
    }

    @Test fun nativeAuthorityCannotAuthorizeWildcardsOrMalformedHosts() {
        assertEquals(emptySet<String>(), resolve(emptyList(), native = setOf("*.shop.pl", "invalid"))?.domains)
        assertEquals(setOf("shop.pl"), resolve(emptyList(), native = setOf("*.shop.pl", "shop.pl"))?.domains)
    }

    @Test fun invalidAndBrowserFormsDoNotQueryNativeAuthority() {
        for ((domains, browser) in listOf(listOf("invalid") to false, emptyList<String>() to true)) {
            val result = AutofillOriginPolicy.resolve(domains, normalize, { true }, {
                fail("Native authority must not replace a missing browser or malformed web origin")
                emptySet()
            }, browser)
            assertNull(result)
        }
    }

    @Test fun chosenNativeDomainMustRemainBoundToRequestRecordAndCurrentAuthority() {
        val requested = setOf("shop.pl", "shop.cz")
        assertTrue(AutofillOriginPolicy.canReleaseNative("shop.pl", setOf("shop.pl"), requested, setOf("shop.pl")))
        assertFalse(AutofillOriginPolicy.canReleaseNative("shop.pl", setOf("shop.pl"), requested, emptySet()))
        assertFalse(AutofillOriginPolicy.canReleaseNative("shop.pl", setOf("shop.cz"), requested, requested))
        assertFalse(AutofillOriginPolicy.canReleaseNative("evil.pl", setOf("evil.pl"), requested, setOf("evil.pl")))
        assertFalse(AutofillOriginPolicy.canReleaseNative("shop.pl", setOf("shop.pl"), requested, null))
    }

    private fun resolve(
        domains: List<String>,
        native: Set<String>? = setOf("shop.pl"),
        webVerified: Boolean = true,
        browser: Boolean = false,
    ) = AutofillOriginPolicy.resolve(domains, normalize, { webVerified }, { native }, browser)
}
