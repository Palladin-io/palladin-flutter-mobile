package io.palladin.mobile.autofill

import android.content.pm.ApplicationInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutofillOriginVerifierTest {
    @Test fun absentAppLinksStillRequireAnIndependentExactCredentialProof() {
        val context = org.mockito.Mockito.mock(android.content.Context::class.java)
        val manager = org.mockito.Mockito.mock(android.content.pm.verify.domain.DomainVerificationManager::class.java)
        org.mockito.Mockito.`when`(context.getSystemService(android.content.pm.verify.domain.DomainVerificationManager::class.java)).thenReturn(manager)
        val verifier = org.mockito.Mockito.spy(AutofillOriginVerifier(
            context, { pkg, host -> pkg == "example.app" && host == "login.example.com" }, apiLevel = 31,
        ))
        org.mockito.Mockito.doReturn(false).`when`(verifier).isBrowser("example.app")
        // Android returns null when the installed package declares no HTTP(S) domains.
        org.junit.Assert.assertEquals(OriginStatus.UNVERIFIED, verifier.status("example.app", "login.example.com"))
        org.junit.Assert.assertEquals(OriginStatus.VERIFIED, verifier.credentialFillStatus("example.app", "login.example.com"))
        org.junit.Assert.assertEquals(OriginStatus.UNVERIFIED, verifier.credentialFillStatus("example.app", "other.example.com"))
        org.mockito.Mockito.doReturn(false).`when`(verifier).isBrowser("other.app")
        org.junit.Assert.assertEquals(OriginStatus.UNVERIFIED, verifier.credentialFillStatus("other.app", "login.example.com"))
        assertFalse(verifier.isVerified("example.app", "login.example.com"))
    }

    @Test fun platformFailureDoesNotBecomeAbsentAppLinksEvenWithCredentialProof() {
        val context = org.mockito.Mockito.mock(android.content.Context::class.java)
        val manager = org.mockito.Mockito.mock(android.content.pm.verify.domain.DomainVerificationManager::class.java)
        org.mockito.Mockito.`when`(context.getSystemService(android.content.pm.verify.domain.DomainVerificationManager::class.java)).thenReturn(manager)
        org.mockito.Mockito.`when`(manager.getDomainVerificationUserState("example.app")).thenThrow(SecurityException())
        val verifier = org.mockito.Mockito.spy(AutofillOriginVerifier(context, { _, _ -> true }, apiLevel = 31))
        org.mockito.Mockito.doReturn(false).`when`(verifier).isBrowser("example.app")
        org.junit.Assert.assertEquals(OriginStatus.QUERY_UNAVAILABLE, verifier.credentialFillStatus("example.app", "login.example.com"))
    }

    @Test fun absentPlatformServiceOrDisabledLinksCannotUseCredentialProof() {
        val context = org.mockito.Mockito.mock(android.content.Context::class.java)
        val verifier = org.mockito.Mockito.spy(AutofillOriginVerifier(context, { _, _ -> true }, apiLevel = 31))
        org.mockito.Mockito.doReturn(false).`when`(verifier).isBrowser("example.app")
        org.junit.Assert.assertEquals(OriginStatus.QUERY_UNAVAILABLE, verifier.credentialFillStatus("example.app", "login.example.com"))
        val manager = org.mockito.Mockito.mock(android.content.pm.verify.domain.DomainVerificationManager::class.java)
        org.mockito.Mockito.`when`(context.getSystemService(android.content.pm.verify.domain.DomainVerificationManager::class.java)).thenReturn(manager)
        val state = org.mockito.Mockito.mock(android.content.pm.verify.domain.DomainVerificationUserState::class.java)
        org.mockito.Mockito.`when`(manager.getDomainVerificationUserState("example.app")).thenReturn(state)
        org.mockito.Mockito.`when`(state.isLinkHandlingAllowed).thenReturn(false)
        org.junit.Assert.assertEquals(OriginStatus.LINK_HANDLING_DISABLED, verifier.credentialFillStatus("example.app", "login.example.com"))
    }

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
