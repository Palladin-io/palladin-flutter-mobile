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
    @Test fun `cold snapshot revoke denies durable source without restoring session`() {
        val live = authority()
        val epoch = live.begin("profile", "session")
        live.activate("session", epoch)
        val restarted = authority()
        val snapshot = restarted.snapshot()!!
        assertFalse(restarted.current("profile", "session", epoch))
        val denied = restarted.revokeSnapshot(snapshot.epoch, snapshot.profile)
        assertEquals(epoch + 1, denied)
        assertEquals(AutoFillSourceFence(denied, "profile", false), disk)
    }
    @Test fun `old snapshot cannot revoke a newly established session`() {
        val source = authority()
        source.begin("profile", "old")
        val old = source.snapshot()!!
        val newer = source.begin("profile", "new")
        source.activate("new", newer)
        rejected { source.revokeSnapshot(old.epoch, old.profile) }
        assertTrue(source.current("profile", "new", newer))
        rejected { source.revokeSnapshot(newer, "wrong-profile") }
        assertTrue(source.current("profile", "new", newer))
    }
    @Test fun `absent snapshot is not authority to fabricate a revoke`() {
        val source = authority()
        assertNull(source.snapshot())
        assertNull(source.snapshot())
        rejected { source.revokeSnapshot(1, "profile") }
        assertNull(disk)
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
