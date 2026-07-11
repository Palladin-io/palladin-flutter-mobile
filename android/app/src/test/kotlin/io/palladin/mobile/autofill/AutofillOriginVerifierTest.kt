package io.palladin.mobile.autofill

import android.content.pm.ApplicationInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutofillOriginVerifierTest {
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
