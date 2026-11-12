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
    private var traceEnabled = false
    private fun trace(stage: String) {
        if (traceEnabled) android.util.Log.i("PalladinAutoFillTrace", stage)
    }
    var onPending: (() -> Unit)? = null
    var onInvalidated: ((String) -> Unit)? = null
    var onSourceChanged: ((String) -> Unit)? = null

    fun initialize(context: Context) = synchronized(AutoFillMutationLock.monitor) {
        traceEnabled = context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0
        if (store != null) return@synchronized
        val source = AutoFillSourceStore(context.applicationContext)
        store = source
        requestState = AutoFillRequestState(source.authority, SystemClock::elapsedRealtime, System::currentTimeMillis)
    }
    private val source get() = requireNotNull(store).authority
    private val state get() = requireNotNull(requestState)

    private var sourceSession: String? = null
    private var currentProfile: AutoFillSourceProfile? = null
    fun beginSession(profile: AutoFillSourceProfile, session: String, accountUnlock: Any? = null, forceQuarantine: Boolean = true): Long {
        synchronized(AutoFillMutationLock.monitor) {
            val restoring = currentProfile == null || (sourceSession == null && currentProfile == profile)
            if (boundSession != null || !restoring) { trace("BEGIN_CANCEL"); cancel(null) } else state.sourceSessionChanged()
            currentProfile = null
            val epoch = source.begin(profile.digest(), session, AutoFillSourceConfiguration.create(profile, accountUnlock), forceQuarantine)
            currentProfile = profile
            sourceSession = session
            if (owner.get() != null && metadata != null) onPending?.invoke()
            return epoch
        }
    }
    fun sourceConfiguration(expected: AutoFillSourceProfile): Map<String, Any>? = source.configuration(expected)?.wire()
    fun sourceSnapshot(): Map<String, Any>? = source.snapshot()?.let {
        mapOf("sourceEpoch" to it.epoch, "profileDigest" to it.profile)
    }
    fun revokeSnapshot(epoch: Long, profile: String): Long {
        try {
            val result = source.revokeSnapshot(epoch, profile)
            sourceSession = null
            trace("REVOKE_SNAPSHOT_CANCEL")
            cancel(null)
            return result
        } catch (error: Exception) {
            if ((error as? AutoFillSourceException)?.code != "SOURCE_STALE_SNAPSHOT") cancel(null)
            throw error
        }
    }
    fun activate(session: String, epoch: Long) = source.activate(session, epoch)
    fun invalidate(session: String, epoch: Long, profileBinding: String): Long = synchronized(AutoFillMutationLock.monitor) {
        requireProfileBinding(profileBinding)
        val result = source.invalidate(session, epoch)
        state.sourceChanged()
        (metadata?.get("id") as? String)?.let { onSourceChanged?.invoke(it) }
        result
    }
    fun revokeSession(session: String, epoch: Long, profileBinding: String): Long = synchronized(AutoFillMutationLock.monitor) {
        val profile = requireProfileBinding(profileBinding).digest()
        if (source.sessionEpoch(profile, session) != epoch) throw AutoFillSourceException("SOURCE_STALE_EPOCH")
        // Revoke this fill authorization, retaining the owner's exact-CAS repair session.
        try { source.invalidate(session, epoch) } finally { trace("REVOKE_SESSION_CANCEL"); cancel(null) }
    }
    private fun requireProfileBinding(value: String): AutoFillSourceProfile = currentProfile?.takeIf { it.profileBinding == value }
        ?: throw AutoFillSourceException("SOURCE_STALE_SESSION")
    fun lock(session: String) = synchronized(AutoFillMutationLock.monitor) {
        source.lock(session)
        if (sourceSession == session) sourceSession = null
        // A stale Dart callback must not cancel a replacement request.
        if (boundSession == session) { trace("LOCK_CANCEL"); cancel(null) }
    }
    private var boundSession: String? = null

    fun open(activity: SourceAutofillAuthenticationActivity, mode: AutofillOriginMode, hosts: Set<String>, usernameOnly: Boolean) {
        initialize(activity)
        trace("OPEN")
        cancel(null)
        val id = state.open(mode, hosts, usernameOnly)
        owner = WeakReference(activity)
        openedAt = SystemClock.elapsedRealtime()
        metadata = if (mode == AutofillOriginMode.MANUAL_WEB) {
            mapOf("id" to id, "mode" to mode.name, "verifiedHosts" to emptyList<String>(),
                "reportedHost" to hosts.single(), "destinationApp" to activity.destinationApp,
                "usernameOnly" to usernameOnly)
        } else mapOf("id" to id, "mode" to mode.name, "verifiedHosts" to hosts.sorted(), "usernameOnly" to usernameOnly)
        handler.postDelayed(expiry, AutoFillRequestState.MAX_AGE_MS)
        val route = Intent(activity, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tasks = activity.getSystemService(ActivityManager::class.java).appTasks
        val task = tasks.firstOrNull { it.taskInfo?.baseIntent?.component?.className == MainActivity::class.java.name }
        if (task == null) activity.startActivity(route.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        else task.startActivity(activity, route, null)
        trace("MAIN_LAUNCH_REQUESTED")
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
    fun authorizePasswordUnlock(id: String, binding: String) = state.authorizePasswordUnlock(id, binding)
    fun authorizeUnlockedSession(id: String, binding: String, principal: String, session: String, epoch: Long): String = synchronized(AutoFillMutationLock.monitor) {
        val profile = currentProfile ?: throw AutoFillSourceException("SOURCE_UNAVAILABLE")
        if (profile.principalId != principal || boundSession != session) throw AutoFillSourceException("AUTOFILL_REQUEST_INVALIDATED")
        state.authorizeUnlockedSession(id, binding, session, epoch)
    }
    fun confirm(id: String, binding: String, authorization: String, selection: AutoFillSelection, sourceEpoch: Long) = state.confirm(id, binding, authorization, selection, sourceEpoch)
    fun validate(id: String, binding: String, authorization: String, host: String, sourceEpoch: Long): Boolean =
        state.validate(id, binding, authorization, host, sourceEpoch) && owner.get()?.originVerified(host) == true
    fun complete(id: String, binding: String, authorization: String, selection: AutoFillSelection, consent: String?, notAfter: Long, sourceEpoch: Long, username: String, password: String): Boolean {
        val activity = owner.get() ?: return false
        val result = try {
            state.consume(id, binding, authorization, selection, consent, notAfter, sourceEpoch,
                { !activity.isDestroyed && activity.originVerified(selection.host) }) {
                activity.complete(username, password, selection.host)
            }
        } catch (error: Exception) {
            // A failed OS return consumes no reusable grant and ends the
            // original result owner as canceled, never reporting a false fill.
            cancel(id)
            throw error
        }
        if (result) clearMetadata()
        return result
    }
    fun foreground() = synchronized(AutoFillMutationLock.monitor) {
        val id = pending()?.get("id") as? String ?: return@synchronized
        state.presented(id)
    }
    fun background() = synchronized(AutoFillMutationLock.monitor) {
        if (state.background()) cancel(null)
    }
    fun cancel(id: String?): Boolean {
        if (id != null && metadata?.get("id") != id) { trace("CANCEL_STALE"); return false }
        trace(if (id == null) "CANCEL_NATIVE" else "CANCEL_DART")
        val invalidated = metadata?.get("id") as? String
        requestState?.cancel(id)
        val activity = owner.get()
        clearMetadata()
        activity?.cancel()
        if (invalidated != null) onInvalidated?.invoke(invalidated)
        return invalidated != null
    }
    fun destroyed(activity: SourceAutofillAuthenticationActivity) { if (owner.get() === activity) { trace("OWNER_DESTROYED"); cancel(null) } }
    private fun clearMetadata() {
        handler.removeCallbacks(expiry)
        owner.clear(); metadata = null; boundSession = null
    }
}
