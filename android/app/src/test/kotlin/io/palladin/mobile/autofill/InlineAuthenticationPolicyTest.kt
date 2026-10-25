package io.palladin.mobile.autofill

import org.junit.Assert.*
import org.junit.Test

class InlineAuthenticationPolicyTest {
    @Test fun `supported IME request offers inline authentication`() {
        assertTrue(supportsInlineAuthentication(30, 1, true))
    }

    @Test fun `old Android absent request and unsupported style preserve dropdown`() {
        assertFalse(supportsInlineAuthentication(29, 1, true))
        assertFalse(supportsInlineAuthentication(36, 0, true))
        assertFalse(supportsInlineAuthentication(36, 1, false))
    }
}
