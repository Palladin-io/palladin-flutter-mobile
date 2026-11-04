package io.palladin.mobile.autofill

import java.util.UUID

internal data class AutoFillRequestBinding(val id: String, val token: String, val profile: String, val session: String, val sourceEpoch: Long)
internal data class AutoFillAuthenticationAttempt(val binding: AutoFillRequestBinding, val nonce: String)
internal data class AutoFillSelection(val vaultId: String, val entryId: String, val host: String)

/** One request's metadata and native-only authorization, never credential values. */
internal class AutoFillRequestState(private val source: AutoFillSourceAuthority, private val now: () -> Long, private val wallTime: () -> Long = now) {
    private data class Request(val id: String, val created: Long, val createdWall: Long, val mode: AutofillOriginMode, val hosts: Set<String>, val usernameOnly: Boolean)
    private var request: Request? = null
    private var binding: AutoFillRequestBinding? = null
    private var attempt: AutoFillAuthenticationAttempt? = null
    private var authorization: String? = null
    private var consent: Pair<AutoFillSelection, String>? = null

    fun open(mode: AutofillOriginMode, hosts: Set<String>, usernameOnly: Boolean): String = synchronized(AutoFillMutationLock.monitor) {
        cancel()
        require(mode == AutofillOriginMode.MANUAL_NATIVE || hosts.isNotEmpty())
        val value = Request(token(), now(), wallTime(), mode, hosts.toSet(), usernameOnly)
        request = value
        value.id
    }

    fun bind(id: String, profile: String, session: String, epoch: Long): AutoFillRequestBinding = synchronized(AutoFillMutationLock.monitor) {
        requireRequest(id)
        if (!source.matches(profile, session, epoch)) rejected()
        authorization = null; consent = null; attempt = null
        AutoFillRequestBinding(id, token(), profile, session, epoch).also { binding = it }
    }

    fun beginAuthentication(id: String, binding: String): AutoFillAuthenticationAttempt = synchronized(AutoFillMutationLock.monitor) {
        val bound = requireBinding(id, binding)
        authorization = null; consent = null
        AutoFillAuthenticationAttempt(bound, token()).also { attempt = it }
    }

    // Called only by the native OS-success path, never exposed on MethodChannel.
    fun authenticated(attempt: AutoFillAuthenticationAttempt): String = synchronized(AutoFillMutationLock.monitor) {
        requireBinding(attempt.binding.id, attempt.binding.token)
        if (this.attempt != attempt) rejected()
        this.attempt = null
        token().also { authorization = it }
    }

    // Called only by the request-captured successful password KDF/private-key unwrap path.
    fun authorizePasswordUnlock(id: String, binding: String): String = synchronized(AutoFillMutationLock.monitor) {
        authenticated(beginAuthentication(id, binding))
    }

    fun confirm(id: String, binding: String, authorization: String, selection: AutoFillSelection): String = synchronized(AutoFillMutationLock.monitor) {
        if (!validate(id, binding, authorization, selection.host)) rejected()
        require(selection.vaultId.isNotBlank() && selection.entryId.isNotBlank())
        token().also { consent = selection to it }
    }

    fun validate(id: String, binding: String, authorization: String, host: String): Boolean = synchronized(AutoFillMutationLock.monitor) {
        try {
            val bound = requireBinding(id, binding)
            if (!source.current(bound.profile, bound.session, bound.sourceEpoch)) return@synchronized false
            val current = requireRequest(id)
            this.authorization != null && this.authorization == authorization && host.isNotBlank() &&
                (current.mode == AutofillOriginMode.MANUAL_NATIVE || host in current.hosts)
        } catch (_: AutoFillSourceException) { false }
    }

    fun consume(id: String, binding: String, authorization: String, selection: AutoFillSelection, consent: String?, notAfter: Long, origin: () -> Boolean, handoff: () -> Unit): Boolean = synchronized(AutoFillMutationLock.monitor) {
        if (!validate(id, binding, authorization, selection.host)) return@synchronized false
        val current = requireRequest(id)
        val effectiveNow = maxOf(wallTime(), current.createdWall + (now() - current.created))
        if (effectiveNow >= notAfter) return@synchronized false
        if ((current.mode == AutofillOriginMode.MANUAL_NATIVE || current.usernameOnly) &&
            (this.consent?.first != selection || this.consent?.second != consent)) return@synchronized false
        if (!origin()) return@synchronized false
        cancel()
        handoff()
        true
    }

    fun sourceSessionChanged() = synchronized(AutoFillMutationLock.monitor) {
        if (binding != null) cancel()
    }

    fun cancel(id: String? = null) = synchronized(AutoFillMutationLock.monitor) {
        if (id != null && request?.id != id) return@synchronized
        request = null; binding = null; attempt = null; authorization = null; consent = null
    }

    private fun requireBinding(id: String, token: String): AutoFillRequestBinding {
        requireRequest(id)
        val value = binding ?: rejected()
        if (value.id != id || value.token != token || !source.matches(value.profile, value.session, value.sourceEpoch)) rejected()
        return value
    }
    private fun requireRequest(id: String): Request {
        val value = request ?: rejected()
        val age = now() - value.created
        if (value.id != id || age !in 0 until MAX_AGE_MS) rejected()
        return value
    }
    private fun rejected(): Nothing = throw AutoFillSourceException("AUTOFILL_REQUEST_INVALIDATED")
    private fun token() = UUID.randomUUID().toString()
    companion object { const val MAX_AGE_MS = 120_000L }
}
