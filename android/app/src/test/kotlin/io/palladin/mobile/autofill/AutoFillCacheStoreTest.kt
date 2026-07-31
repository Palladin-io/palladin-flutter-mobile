package io.palladin.mobile.autofill

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoFillCacheStoreTest {
    @Test
    fun normalizeDomainRejectsAmbiguousHosts() {
        assertEquals("www.example.com", AutoFillCacheStore.normalizeDomain("WWW.Example.com."))
        assertNull(AutoFillCacheStore.normalizeDomain("localhost"))
        assertNull(AutoFillCacheStore.normalizeDomain("example..com"))
        assertNull(AutoFillCacheStore.normalizeDomain("https://example.com"))
        assertNull(AutoFillCacheStore.normalizeDomain("user@example.com"))
        assertNull(AutoFillCacheStore.normalizeDomain("example.com:443"))
        assertNull(AutoFillCacheStore.normalizeDomain("exаmple.com"))
        assertNull(AutoFillCacheStore.normalizeDomain("*.example.com"))
    }

    @Test
    fun domainMatchesExactHostsOnly() {
        assertTrue(AutoFillCacheStore.domainMatches("example.com", "example.com"))
        assertFalse(AutoFillCacheStore.domainMatches("login.example.com", "example.com"))
        assertFalse(AutoFillCacheStore.domainMatches("evil-example.com", "example.com"))
        assertFalse(AutoFillCacheStore.domainMatches("example.org", "example.com"))
    }
}
