package io.palladin.mobile.autofill

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.palladin.mobile.MainActivity
import java.lang.ref.WeakReference

/** One live OS request, owned by the original non-exported authentication activity. */
internal object AutoFillRequestBroker {
    const val CHANNEL = "io.palladin.mobile/autofill-request"
    private val handler = Handler(Looper.getMainLooper())
    private var store: AutoFillSourceStore? = null
    private var requestState: AutoFillRequestState? = null
    private var owner = WeakReference<SourceAutofillAuthenticationActivity>(null)
    private var metadata: Map<String, Any>? = null
    private var openedAt = 0L
    private val expiry = Runnable { cancel(null) }
    var onPending: (() -> Unit)? = null
    var onInvalidated: ((String) -> Unit)? = null

    fun initialize(context: Context) = synchronized(AutoFillMutationLock.monitor) {
        if (store != null) return@synchronized
        val source = AutoFillSourceStore(context.applicationContext)
        store = source
        requestState = AutoFillRequestState(source.authority, SystemClock::elapsedRealtime, System::currentTimeMillis)
    }
    private val source get() = requireNotNull(store).authority
    private val state get() = requireNotNull(requestState)

    private var sourceSession: String? = null
    private var currentProfile: AutoFillSourceProfile? = null
    fun beginSession(profile: AutoFillSourceProfile, session: String): Long {
        synchronized(AutoFillMutationLock.monitor) {
            val restoring = currentProfile == null || (sourceSession == null && currentProfile == profile)
            if (boundSession != null || !restoring) cancel(null) else state.sourceSessionChanged()
            currentProfile = null
            val epoch = source.begin(profile.digest(), session)
            currentProfile = profile
            sourceSession = session
            if (owner.get() != null && metadata != null) onPending?.invoke()
            return epoch
        }
    }
    fun activate(session: String, epoch: Long) = source.activate(session, epoch)
    fun invalidate(session: String, epoch: Long): Long = synchronized(AutoFillMutationLock.monitor) {
        val result = source.invalidate(session, epoch)
        cancel(null)
        result
    }
    fun lock(session: String) = synchronized(AutoFillMutationLock.monitor) {
        source.lock(session)
        if (sourceSession == session) sourceSession = null
        // A stale Dart callback must not cancel a replacement request.
        if (boundSession == session) cancel(null)
    }
    private var boundSession: String? = null

    fun open(activity: SourceAutofillAuthenticationActivity, mode: AutofillOriginMode, hosts: Set<String>, usernameOnly: Boolean) {
        initialize(activity)
        cancel(null)
        val id = state.open(mode, hosts, usernameOnly)
        owner = WeakReference(activity)
        openedAt = SystemClock.elapsedRealtime()
        metadata = mapOf("id" to id, "mode" to mode.name, "verifiedHosts" to hosts.sorted(), "usernameOnly" to usernameOnly)
        handler.postDelayed(expiry, AutoFillRequestState.MAX_AGE_MS)
        val route = Intent(activity, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tasks = activity.getSystemService(ActivityManager::class.java).appTasks
        val task = tasks.firstOrNull { it.taskInfo?.baseIntent?.component?.className == MainActivity::class.java.name }
        if (task == null) activity.startActivity(route.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        else task.startActivity(activity, route, null)
        onPending?.invoke()
    }
    fun pending(): Map<String, Any>? {
        val value = metadata ?: return null
        val remaining = AutoFillRequestState.MAX_AGE_MS - (SystemClock.elapsedRealtime() - openedAt)
        if (remaining <= 0 || owner.get()?.isDestroyed != false) { cancel(null); return null }
        return value + ("remainingMs" to remaining)
    }
    fun bind(id: String, principal: String, organization: String, session: String): String {
        val authority = currentProfile ?: throw AutoFillSourceException("SOURCE_UNAVAILABLE")
        require(authority.principalId == principal && authority.organizationId == organization)
        val profile = authority.digest()
        val binding = state.bind(id, profile, session, source.sessionEpoch(profile, session))
        boundSession = session
        return binding.token
    }
    fun beginAuthentication(id: String, binding: String) = state.beginAuthentication(id, binding)
    fun authenticated(attempt: AutoFillAuthenticationAttempt) = state.authenticated(attempt)
    fun confirm(id: String, binding: String, authorization: String, selection: AutoFillSelection) = state.confirm(id, binding, authorization, selection)
    fun validate(id: String, binding: String, authorization: String, host: String): Boolean =
        state.validate(id, binding, authorization, host) && owner.get()?.originVerified(host) == true
    fun complete(id: String, binding: String, authorization: String, selection: AutoFillSelection, consent: String?, notAfter: Long, username: String, password: String): Boolean {
        val activity = owner.get() ?: return false
        val result = state.consume(id, binding, authorization, selection, consent, notAfter,
            { !activity.isDestroyed && activity.originVerified(selection.host) }) {
            activity.complete(username, password, selection.host)
        }
        if (result) clearMetadata()
        return result
    }
    fun cancel(id: String?) {
        if (id != null && metadata?.get("id") != id) return
        val invalidated = metadata?.get("id") as? String
        requestState?.cancel(id)
        val activity = owner.get()
        clearMetadata()
        activity?.cancel()
        if (invalidated != null) onInvalidated?.invoke(invalidated)
    }
    fun destroyed(activity: SourceAutofillAuthenticationActivity) { if (owner.get() === activity) cancel(null) }
    private fun clearMetadata() {
        handler.removeCallbacks(expiry)
        owner.clear(); metadata = null; boundSession = null
    }
}
