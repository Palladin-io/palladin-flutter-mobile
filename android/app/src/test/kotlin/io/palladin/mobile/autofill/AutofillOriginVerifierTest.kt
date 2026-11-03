package io.palladin.mobile.autofill

import android.content.pm.ApplicationInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutofillOriginVerifierTest {
    @Test fun credentialProofCannotOverrideDisabledUnavailableOrBrowserOrigins() {
        var proofChecks = 0
        val verifier = org.mockito.Mockito.spy(AutofillOriginVerifier(
            org.mockito.Mockito.mock(android.content.Context::class.java),
            { _, _ -> proofChecks++; true },
        ))
        val packageName = "example.app"
        val host = "example.com"
        org.mockito.Mockito.doReturn(false).`when`(verifier).isBrowser(packageName)
        for (status in listOf(OriginStatus.LINK_HANDLING_DISABLED, OriginStatus.QUERY_UNAVAILABLE)) {
            org.mockito.Mockito.doReturn(status).`when`(verifier).status(packageName, host)
            org.junit.Assert.assertEquals(status, verifier.credentialFillStatus(packageName, host))
        }
        org.mockito.Mockito.doReturn(OriginStatus.UNVERIFIED).`when`(verifier).status(packageName, host)
        org.mockito.Mockito.doReturn(true).`when`(verifier).isBrowser(packageName)
        org.junit.Assert.assertEquals(OriginStatus.UNVERIFIED, verifier.credentialFillStatus(packageName, host))
        org.junit.Assert.assertEquals(0, proofChecks)
        org.mockito.Mockito.doReturn(false).`when`(verifier).isBrowser(packageName)
        org.junit.Assert.assertEquals(OriginStatus.VERIFIED, verifier.credentialFillStatus(packageName, host))
        assertFalse(verifier.isVerified(packageName, host)) // Save/generator retain OS authority.
    }

    @Test
    fun onlyExplicitlyKnownBrowserPackageCanUseBrowserException() {
        assertTrue(AutofillOriginVerifier.isKnownBrowserPackage("com.android.chrome"))
        assertFalse(AutofillOriginVerifier.isKnownBrowserPackage("com.example.fakebrowser"))
    }

    @Test
    fun browserExceptionRequiresPlatformTrustedSystemIdentity() {
        assertTrue(
            AutofillOriginVerifier.hasTrustedSystemIdentity(ApplicationInfo.FLAG_SYSTEM),
        )
        assertTrue(
            AutofillOriginVerifier.hasTrustedSystemIdentity(
                ApplicationInfo.FLAG_UPDATED_SYSTEM_APP,
            ),
        )
        assertFalse(AutofillOriginVerifier.hasTrustedSystemIdentity(0))
    }
}
