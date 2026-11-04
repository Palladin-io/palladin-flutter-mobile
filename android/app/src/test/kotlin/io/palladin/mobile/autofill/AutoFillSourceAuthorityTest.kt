package io.palladin.mobile.autofill

import org.junit.Assert.*
import org.junit.Test

class AutoFillSourceAuthorityTest {
    private var disk: AutoFillSourceFence? = null
    private fun authority() = AutoFillSourceAuthority({ disk }, { disk = it })
    private fun rejected(block: () -> Unit) {
        try { block(); fail("Expected stale source rejection") } catch (_: AutoFillSourceException) { }
    }
    @Test fun `invalidation blocks old activation and handoff until exact repair`() {
        val source = authority()
        val initial = source.begin("profile", "session")
        source.activate("session", initial)
        assertTrue(source.current("profile", "session", initial))
        val replacement = source.invalidate("session", initial)
        assertFalse(source.current("profile", "session", initial))
        rejected { source.activate("session", initial) }
        assertFalse(source.current("profile", "session", replacement))
        source.activate("session", replacement)
        assertTrue(source.current("profile", "session", replacement))
    }
    @Test fun `old session cannot invalidate replacement and process restart is not admission`() {
        val source = authority()
        val old = source.begin("profile", "old")
        source.activate("old", old)
        val replacement = source.begin("other", "new")
        source.activate("new", replacement)
        rejected { source.invalidate("old", old) }
        assertTrue(source.current("other", "new", replacement))
        assertFalse(authority().current("other", "new", replacement))
        source.lock("old")
        assertTrue(source.current("other", "new", replacement))
        source.lock("new")
        assertFalse(source.current("other", "new", replacement))
    }
    @Test fun `later mutation epoch rejects earlier owner activation`() {
        val source = authority()
        val first = source.begin("profile", "session")
        source.activate("session", first)
        val ownerA = source.invalidate("session", first)
        val ownerB = source.invalidate("session", ownerA)
        rejected { source.activate("session", ownerA) }
        assertFalse(source.current("profile", "session", ownerB))
        source.activate("session", ownerB)
        assertTrue(source.current("profile", "session", ownerB))
    }
    @Test fun `failed durable denial never acknowledges or permits handoff`() {
        var failWrite = false
        val source = AutoFillSourceAuthority({ disk }, { if (failWrite) error("synthetic write failure") else disk = it })
        val initial = source.begin("profile", "session")
        source.activate("session", initial)
        failWrite = true
        try { source.invalidate("session", initial); fail("Expected failure") } catch (_: IllegalStateException) { }
        assertFalse(source.current("profile", "session", initial))
    }
}
