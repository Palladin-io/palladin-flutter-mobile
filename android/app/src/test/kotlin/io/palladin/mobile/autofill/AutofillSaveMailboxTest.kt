package io.palladin.mobile.autofill

import org.junit.Assert.*
import org.junit.Test

class AutofillSaveMailboxTest {
    @Test fun requiresOriginalSessionAndConsumesOnce() {
        var now = 1L
        val mailbox = AutofillSaveMailbox { now }
        assertNull(mailbox.offer("request", "user".toCharArray(), "synthetic".toCharArray()))
        val session = mailbox.activate("account")
        val id = mailbox.offer("request", "user".toCharArray(), "synthetic".toCharArray())!!
        assertNull(mailbox.take(id, "other"))
        assertNull(mailbox.take(id, session))
        val next = mailbox.offer("request", "user".toCharArray(), "synthetic".toCharArray())!!
        assertEquals("synthetic", String(mailbox.take(next, session)!!.password))
        assertNull(mailbox.take(next, session))
    }

    @Test fun expiryReplacementRestartAndNewLoginFailClosed() {
        var now = 1L
        val mailbox = AutofillSaveMailbox { now }
        val session = mailbox.activate("account")
        fun offer() = mailbox.offer("request", "user".toCharArray(), "synthetic".toCharArray())!!
        val expired = offer()
        now += AutofillSaveMailbox.MAX_AGE_MS
        assertNull(mailbox.take(expired, session))
        val replaced = offer()
        val replacement = offer()
        assertNull(mailbox.take(replaced, session))
        assertNull(mailbox.take(replacement, session))
        val oldLogin = offer()
        mailbox.activate("account")
        assertNull(mailbox.take(oldLogin, session))
        assertNull(AutofillSaveMailbox { now }.take(oldLogin, session))
    }

    @Test fun revocationWipesOwnedBuffers() {
        val mailbox = AutofillSaveMailbox { 1 }
        mailbox.activate("account")
        val user = "user".toCharArray()
        val password = "synthetic".toCharArray()
        mailbox.offer("request", user, password)
        mailbox.revoke()
        assertTrue(user.all { it == '\u0000' })
        assertTrue(password.all { it == '\u0000' })
    }
}
