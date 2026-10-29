package io.palladin.mobile.autofill

import android.view.autofill.AutofillId
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock

class UsernameOnlyAutofillTargetsTest {
    private val focused = mock(AutofillId::class.java)

    @Test fun onlySingleNativeUsernameTargetCanEnterConfirmation() {
        for (mode in listOf(AutofillOriginMode.MANUAL_NATIVE, AutofillOriginMode.VERIFIED_NATIVE)) {
            assertTrue(AutofillAuthenticationActivity.validUsernameOnlyTargets(mode,
                listOf(focused), emptyList(), emptyList()))
        }
        assertFalse(AutofillAuthenticationActivity.validUsernameOnlyTargets(AutofillOriginMode.WEB,
            listOf(focused), emptyList(), emptyList()))
    }

    @Test fun missingAmbiguousOrPasswordTargetsFailClosed() {
        for (usernames in listOf(emptyList(), listOf(focused, mock(AutofillId::class.java)))) {
            assertFalse(AutofillAuthenticationActivity.validUsernameOnlyTargets(
                AutofillOriginMode.VERIFIED_NATIVE, usernames, emptyList(), emptyList()))
        }
        assertFalse(AutofillAuthenticationActivity.validUsernameOnlyTargets(AutofillOriginMode.MANUAL_NATIVE,
            listOf(focused), listOf(focused), emptyList()))
        assertFalse(AutofillAuthenticationActivity.validUsernameOnlyTargets(AutofillOriginMode.MANUAL_NATIVE,
            listOf(focused), emptyList(), listOf(focused)))
    }
}
