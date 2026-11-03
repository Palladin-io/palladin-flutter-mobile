package io.palladin.autofill.form

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FixtureContentTest {
    @Test fun dalFixtureRemainsExactAndExplicit() {
        assertEquals("synthetic", fixtureContent("https://example.com/", "synthetic", dalFixture = true))
        assertNull(fixtureContent("https://example.com/", "synthetic"))
        for (url in listOf("http://example.com/", "https://sub.example.com/", "https://example.com/other", "https://fixture.invalid/")) {
            assertNull(fixtureContent(url, "synthetic", dalFixture = true))
        }
    }

    @Test fun onlyExactSyntheticHttpsDocumentReceivesContent() {
        assertEquals("synthetic document", fixtureContent("https://fixture.invalid/", "synthetic document"))
        for (url in listOf("http://fixture.invalid/", "https://foreign.invalid/", "https://sub.fixture.invalid/", "https://fixture.invalid/other", "https://fixture.invalid/?query=1")) {
            assertNull(fixtureContent(url, "synthetic document"))
        }
    }
}
