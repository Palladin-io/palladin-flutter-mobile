package io.palladin.mobile.autofill

import org.junit.Assert.*
import org.junit.Test

class AutoFillRequestStateTest {
    private var disk: AutoFillSourceFence? = null
    private var now = 1000L
    private val source = AutoFillSourceAuthority({ disk }, { disk = it })
    private val state = AutoFillRequestState(source, { now })
    private val epoch = source.begin("profile", "session").also { source.activate("session", it) }
    private val selection = AutoFillSelection("vault", "entry", "example.test")
    private fun bind(mode: AutofillOriginMode = AutofillOriginMode.WEB, usernameOnly: Boolean = false): AutoFillRequestBinding {
        val id = state.open(mode, if (mode == AutofillOriginMode.MANUAL_NATIVE) emptySet() else setOf("example.test"), usernameOnly)
        return state.bind(id, "profile", "session", epoch)
    }
    private fun auth(binding: AutoFillRequestBinding): String = state.authenticated(state.beginAuthentication(binding.id, binding.token))
    private fun fill(binding: AutoFillRequestBinding, authorization: String, consent: String? = null, origin: () -> Boolean = { true }): Boolean =
        state.consume(binding.id, binding.token, authorization, selection, consent, now + 1000, epoch, origin) {}
    @Test fun `actual native authentication is required and single use`() {
        val binding = bind()
        assertFalse(fill(binding, "forged"))
        val authorization = auth(binding)
        assertTrue(fill(binding, authorization))
        assertFalse(fill(binding, authorization))
    }
    @Test fun `manual and username confirmation bind exact selection`() {
        for ((mode, username) in listOf(AutofillOriginMode.MANUAL_NATIVE to false, AutofillOriginMode.WEB to true)) {
            val binding = bind(mode, username)
            val authorization = auth(binding)
            assertFalse(fill(binding, authorization))
            val wrong = state.confirm(binding.id, binding.token, authorization, selection.copy(entryId = "other"), epoch)
            assertFalse(fill(binding, authorization, wrong))
            val consent = state.confirm(binding.id, binding.token, authorization, selection, epoch)
            assertTrue(fill(binding, authorization, consent))
        }
    }
    @Test fun `late biometric callback after new request cannot authorize`() {
        val old = bind()
        val attempt = state.beginAuthentication(old.id, old.token)
        bind()
        try { state.authenticated(attempt); fail("Accepted stale biometric") } catch (_: AutoFillSourceException) {}
    }
    @Test fun `source invalidation and origin expiry block final handoff`() {
        val binding = bind()
        val authorization = auth(binding)
        assertFalse(fill(binding, authorization, origin = { false }))
        source.invalidate("session", epoch)
        assertFalse(fill(binding, authorization))
    }
    @Test fun `cold quarantined unlock cannot handoff until same epoch is activated`() {
        val coldSource = AutoFillSourceAuthority({ disk }, { disk = it })
        val cold = AutoFillRequestState(coldSource, { now })
        val id = cold.open(AutofillOriginMode.WEB, setOf("example.test"), false)
        cold.sourceSessionChanged()
        val epoch = coldSource.begin("profile", "cold")
        val bound = cold.bind(id, "profile", "cold", epoch)
        val auth = cold.authenticated(cold.beginAuthentication(id, bound.token))
        assertFalse(cold.validate(id, bound.token, auth, "example.test", epoch))
        coldSource.activate("cold", epoch)
        assertTrue(cold.validate(id, bound.token, auth, "example.test", epoch))
        coldSource.invalidate("cold", epoch)
        assertFalse(cold.validate(id, bound.token, auth, "example.test", epoch))
    }
    @Test fun `selected lease expiry is checked at native consumption`() {
        val binding = bind()
        val authorization = auth(binding)
        var handedOff = false
        assertFalse(state.consume(binding.id, binding.token, authorization, selection, null, now, epoch, { true }) { handedOff = true })
        assertFalse(handedOff)
    }
    @Test fun `successful prompt cannot attach after security revocation`() {
        val binding = bind()
        val attempt = state.beginAuthentication(binding.id, binding.token)
        source.revokeSnapshot(epoch, "profile")
        try { state.authenticated(attempt); fail("Accepted revoked authentication") }
        catch (_: AutoFillSourceException) {}
    }
    @Test fun `wall clock rollback cannot extend selected lease during request`() {
        var wall = 10_000L
        val clocked = AutoFillRequestState(source, { now }, { wall })
        val id = clocked.open(AutofillOriginMode.WEB, setOf("example.test"), false)
        val binding = clocked.bind(id, "profile", "session", epoch)
        val authorization = clocked.authenticated(clocked.beginAuthentication(id, binding.token))
        now += 2000
        wall = 1000
        assertFalse(clocked.consume(id, binding.token, authorization, selection, null, 11_000, epoch, { true }) {})
    }
    @Test fun `cancel and request expiry invalidate native authorization`() {
        val binding = bind()
        val authorization = auth(binding)
        now += 120_000
        assertFalse(fill(binding, authorization))
        state.cancel()
        assertFalse(state.validate(binding.id, binding.token, authorization, "example.test", epoch))
    }
    @Test fun `completed password unwrap authorizes only the captured current request`() {
        val binding = bind()
        val authorization = state.authorizePasswordUnlock(binding.id, binding.token)
        assertTrue(fill(binding, authorization))
        assertFalse(fill(binding, authorization))
    }
    @Test fun `late password completion rejects cancellation revocation and account replacement`() {
        val canceled = bind()
        state.cancel()
        try { state.authorizePasswordUnlock(canceled.id, canceled.token); fail("Accepted canceled unlock") }
        catch (_: AutoFillSourceException) {}
        val changed = bind()
        source.revokeSnapshot(epoch, "profile")
        try { state.authorizePasswordUnlock(changed.id, changed.token); fail("Accepted invalidated unlock") }
        catch (_: AutoFillSourceException) {}
        source.begin("replacement-profile", "replacement-session")
        try { state.authorizePasswordUnlock(changed.id, changed.token); fail("Accepted replaced account") }
        catch (_: AutoFillSourceException) {}
    }

    @Test fun `origin verification cannot carry a request past lease or request deadline`() {
        for (advance in listOf(1_000L, AutoFillRequestState.MAX_AGE_MS)) {
            val binding = bind()
            val authorization = auth(binding)
            var handedOff = false
            assertFalse(state.consume(binding.id, binding.token, authorization, selection, null,
                if (advance == 1_000L) now + 1_000 else now + 300_000, epoch,
                { now += advance; true }) { handedOff = true })
            assertFalse(handedOff)
        }
    }

    @Test fun `routine ciphertext refresh preserves the captured authentication attempt`() {
        val binding = bind()
        val attempt = state.beginAuthentication(binding.id, binding.token)
        val next = source.invalidate("session", epoch)
        val authorization = state.authenticated(attempt)
        assertFalse(fill(binding, authorization))
        source.activate("session", next)
        assertFalse(fill(binding, authorization)) // Old selected-read epoch is still rejected.
    }

    @Test fun `routine refresh requires fresh selected read epoch and renewed exact consent`() {
        val binding = bind(AutofillOriginMode.MANUAL_NATIVE)
        val authorization = auth(binding)
        val oldConsent = state.confirm(binding.id, binding.token, authorization, selection, epoch)
        val next = source.invalidate("session", epoch)
        state.sourceChanged()
        assertFalse(state.validate(binding.id, binding.token, authorization, selection.host, next))
        source.activate("session", next)
        assertFalse(fill(binding, authorization, oldConsent))
        assertFalse(state.consume(binding.id, binding.token, authorization, selection, oldConsent,
            now + 1000, next, { true }) {})
        val currentConsent = state.confirm(binding.id, binding.token, authorization, selection, next)
        assertTrue(state.consume(binding.id, binding.token, authorization, selection, currentConsent,
            now + 1000, next, { true }) {})
    }
    @Test fun `refresh during final origin check still rejects selected ciphertext epoch`() {
        val binding = bind()
        val authorization = auth(binding)
        assertFalse(fill(binding, authorization, origin = {
            val next = source.invalidate("session", epoch)
            state.sourceChanged()
            source.activate("session", next)
            true
        }))
    }

    @Test fun `repair after live hard cancellation never restores prior authorization`() {
        val prior = bind()
        val oldAuthorization = auth(prior)
        val next = source.invalidate("session", epoch)
        state.cancel()
        source.activate("session", next)
        assertFalse(state.validate(prior.id, prior.token, oldAuthorization, selection.host, next))
        val id = state.open(AutofillOriginMode.WEB, setOf(selection.host), false)
        val current = state.bind(id, "profile", "session", next)
        val authorization = auth(current)
        assertTrue(state.consume(id, current.token, authorization, selection, null,
            now + 1000, next, { true }) {})
    }

}
