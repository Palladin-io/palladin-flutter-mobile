package io.palladin.mobile.autofill

import org.junit.Assert.*
import org.junit.Test

class ManualAutofillSelectionTest {
    @Test fun confirmationRequiresTheSelectedEntryDomainAndRequestPackage() {
        val selection = ManualAutofillSelection("app.example")
        assertFalse(selection.confirm("entry", "shop.pl", "app.example"))
        selection.select("entry", "shop.pl")
        assertFalse(selection.confirm("other", "shop.pl", "app.example"))
        assertFalse(selection.confirm("entry", "evil.pl", "app.example"))
        assertFalse(selection.confirm("entry", "shop.pl", "app.other"))
        assertTrue(selection.confirm("entry", "shop.pl", "app.example"))
    }

    @Test fun aConfirmedSelectionCannotBeReusedOrRebound() {
        val selection = ManualAutofillSelection("app.example")
        selection.select("entry", "shop.pl")
        assertTrue(selection.confirm("entry", "shop.pl", "app.example"))
        assertFalse(selection.confirm("entry", "shop.pl", "app.example"))
        selection.select("other", "shop.cz")
        assertFalse(selection.confirm("other", "shop.cz", "app.example"))
    }

    @Test fun cancellationClearsAndDisablesPendingConfirmation() {
        val selection = ManualAutofillSelection("app.example")
        selection.select("entry", "shop.pl")
        selection.cancel()
        assertFalse(selection.confirm("entry", "shop.pl", "app.example"))
        selection.select("entry", "shop.pl")
        assertFalse(selection.confirm("entry", "shop.pl", "app.example"))
    }
}
