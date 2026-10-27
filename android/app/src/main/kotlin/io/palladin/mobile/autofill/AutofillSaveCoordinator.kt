package io.palladin.mobile.autofill

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import io.palladin.mobile.R
import io.palladin.mobile.MainActivity
import java.security.MessageDigest
import java.util.UUID

/** Metadata and captured values never enter an Intent, Bundle or durable store. */
internal object AutofillSaveCoordinator {
    const val EXTRA_REQUEST = "palladin.autofill.save_request"
    const val EXTRA_PENDING = "palladin.autofill.save_pending"
    private val mailbox = AutofillSaveMailbox(SystemClock::elapsedRealtime)
    private val handler = Handler(Looper.getMainLooper())
    private data class Request(
        val id: String, val session: String, val source: AutofillSaveSource,
        val fields: AutofillSaveFields, val created: Long,
    )
    private var request: Request? = null
    private var pending: String? = null
    private var opened: String? = null
    private val expiry = Runnable { clear() }
    var onPending: (() -> Unit)? = null
    var onInvalidated: ((String) -> Unit)? = null

    fun activate(principal: String): String { clear(); return mailbox.activate(principal) }
    fun revoke() { clear(); mailbox.revoke() }
    fun cancel(id: String?) { if (id == null || id == pending) clear() }
    fun clear() {
        val invalidated = pending
        handler.removeCallbacks(expiry)
        mailbox.clear(); request = null; pending = null; opened = null
        invalidated?.let { onInvalidated?.invoke(it) }
    }

    fun prepare(context: Context, structure: AssistStructure): String? {
        clear()
        if (Build.VERSION.SDK_INT < 28) return null
        val session = mailbox.activeSession() ?: return null
        val fields = AutofillSaveFields.from(structure) ?: return null
        val source = source(context, structure) ?: return null
        if (!fields.isBoundTo(structure, source)) return null
        val id = UUID.randomUUID().toString()
        request = Request(id, session, source, fields, SystemClock.elapsedRealtime())
        handler.postDelayed(expiry, AutofillSaveMailbox.MAX_AGE_MS)
        return id
    }

    fun response(builder: FillResponse.Builder, id: String?): FillResponse.Builder {
        val current = current(id) ?: return builder
        val state = Bundle().apply { putString(EXTRA_REQUEST, current.id) }
        return builder.setSaveInfo(SaveInfo.Builder(
            SaveInfo.SAVE_DATA_TYPE_USERNAME or SaveInfo.SAVE_DATA_TYPE_PASSWORD,
            arrayOf(current.fields.username, current.fields.password),
        ).build()).setClientState(state)
    }

    fun save(context: Context, save: SaveRequest, callback: SaveCallback) {
        if (Build.VERSION.SDK_INT < 28) { reject(context, callback); return }
        val current = current(save.clientState?.getString(EXTRA_REQUEST))
        val structure = save.fillContexts.lastOrNull()?.structure
        val latest = structure?.let { source(context, it) }
        if (current == null || structure == null || latest == null || !current.source.matches(latest)) {
            reject(context, callback); return
        }
        if (!current.fields.isBoundTo(structure, latest)) { reject(context, callback); return }
        val values = current.fields.read(structure)
        if (values == null) { reject(context, callback); return }
        val id = mailbox.offer(current.id, values.username, values.password)
        if (id == null) { reject(context, callback); return }
        pending = id
        val launch = Intent(context, MainActivity::class.java).apply {
            action = "io.palladin.mobile.AUTOFILL_SAVE.$id"
            putExtra(EXTRA_PENDING, id)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val sender = PendingIntent.getActivity(context, 0, launch,
            PendingIntent.FLAG_ONE_SHOT or PendingIntent.FLAG_IMMUTABLE).intentSender
        callback.onSuccess(sender)
    }

    private fun reject(context: Context, callback: SaveCallback) {
        clear()
        callback.onFailure(context.getString(R.string.autofill_save_unavailable))
    }

    fun open(id: String?) {
        if (id == null || id != pending) return
        if (current(request?.id) == null) { clear(); return }
        opened = id
        onPending?.invoke()
    }

    fun pendingId(): String? = opened?.takeIf { current(request?.id) != null }

    fun take(context: Context, id: String, session: String): Map<String, Any>? {
        if (id != pending || opened != id) return null
        val current = current(request?.id)
        if (current == null || current.session != session || !reverify(context, current.source)) {
            clear(); return null
        }
        val values = mailbox.take(id, session) ?: run { clear(); return null }
        opened = null
        return try {
            mapOf("id" to id, "packageName" to current.source.packageName,
                "mode" to current.source.mode.name, "domains" to current.source.domains.sorted(),
                "username" to String(values.username), "password" to String(values.password),
                "remainingMs" to (AutofillSaveMailbox.MAX_AGE_MS - (SystemClock.elapsedRealtime() - current.created)))
        } finally { values.clear() }
    }

    fun validate(context: Context, id: String, session: String, domain: String): Boolean {
        val current = current(request?.id) ?: return false
        return pending == id && current.session == session && domain in current.source.domains &&
            reverify(context, current.source)
    }

    private fun current(id: String?): Request? {
        val value = request ?: return null
        val age = SystemClock.elapsedRealtime() - value.created
        return value.takeIf { id == it.id && it.session == mailbox.activeSession() &&
            age >= 0 && age < AutofillSaveMailbox.MAX_AGE_MS }
    }

    private fun reverify(context: Context, source: AutofillSaveSource): Boolean {
        if (signatures(context, source.packageName) != source.signatures) return false
        val verifier = AutofillOriginVerifier(context)
        return when (source.mode) {
            AutofillOriginMode.WEB -> source.domains.all { verifier.isVerified(source.packageName, it) }
            AutofillOriginMode.VERIFIED_NATIVE -> verifier.nativeDomains(source.packageName) == source.domains
            AutofillOriginMode.MANUAL_NATIVE -> false
        }
    }

    private fun source(context: Context, structure: AssistStructure): AutofillSaveSource? {
        if (Build.VERSION.SDK_INT < 28) return null
        val packageName = structure.activityComponent?.packageName ?: return null
        val verifier = AutofillOriginVerifier(context)
        val domains = PalladinAutofillService.CredentialFieldIds.domainsFrom(structure)
        val schemes = PalladinAutofillService.CredentialFieldIds.schemesFrom(structure)
        val origin = AutofillOriginPolicy.resolve(domains, AutoFillCacheStore::normalizeDomain,
            { verifier.isVerified(packageName, it) }, { verifier.nativeDomains(packageName) },
            domains.isEmpty() && verifier.isBrowser(packageName), schemes) ?: return null
        return AutofillSaveSource(packageName, signatures(context, packageName), origin.mode,
            origin.domains, schemes).takeIf { it.isEligible }
    }

    private fun signatures(context: Context, packageName: String): Set<String> = runCatching {
        if (Build.VERSION.SDK_INT < 28) return emptySet()
        val signing = context.packageManager.getPackageInfo(packageName,
            PackageManager.GET_SIGNING_CERTIFICATES).signingInfo ?: return emptySet()
        signing.apkContentsSigners.map { certificate ->
            MessageDigest.getInstance("SHA-256").digest(certificate.toByteArray())
                .joinToString("") { "%02x".format(it) }
        }.toSet()
    }.getOrDefault(emptySet())
}
