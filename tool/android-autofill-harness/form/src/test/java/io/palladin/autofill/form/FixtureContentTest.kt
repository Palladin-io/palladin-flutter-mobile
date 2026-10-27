package io.palladin.autofill.form

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FixtureContentTest {
    @Test fun onlyExactSyntheticHttpsDocumentReceivesContent() {
        assertEquals("synthetic document", fixtureContent("https://fixture.invalid/", "synthetic document"))
        for (url in listOf("http://fixture.invalid/", "https://foreign.invalid/", "https://sub.fixture.invalid/", "https://fixture.invalid/other", "https://fixture.invalid/?query=1")) {
            assertNull(fixtureContent(url, "synthetic document"))
        }
    }
}
