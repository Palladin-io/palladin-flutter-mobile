package io.palladin.mobile.autofill

import java.util.UUID

internal class AutofillSaveValues(val username: CharArray, val password: CharArray) {
    fun clear() { username.fill('\u0000'); password.fill('\u0000') }
}

/** One bounded RAM slot. A fresh login cannot adopt an earlier account's capture. */
internal class AutofillSaveMailbox(private val elapsed: () -> Long) {
    private var session: String? = null
    private var pendingId: String? = null
    private var values: AutofillSaveValues? = null
    private var created = 0L

    @Synchronized fun activate(principal: String): String {
        require(principal.isNotBlank() && principal.length <= 128)
        revoke()
        return UUID.randomUUID().toString().also { session = it }
    }

    @Synchronized fun activeSession(): String? = session

    @Synchronized fun offer(request: String, username: CharArray, password: CharArray): String? {
        clear()
        val candidate = AutofillSaveValues(username, password)
        if (session == null || request.isBlank() || username.isEmpty() ||
            username.size > 1024 || password.isEmpty() || password.size > 4096) {
            candidate.clear()
            return null
        }
        values = candidate
        created = elapsed()
        return UUID.randomUUID().toString().also { pendingId = it }
    }

    @Synchronized fun take(id: String, expectedSession: String): AutofillSaveValues? {
        val age = elapsed() - created
        val result = if (id == pendingId && expectedSession == session &&
            age >= 0 && age < MAX_AGE_MS) values else null
        if (result != null) values = null
        clear()
        return result
    }

    @Synchronized fun clear() {
        values?.clear()
        values = null
        pendingId = null
        created = 0
    }

    @Synchronized fun revoke() { clear(); session = null }

    companion object { const val MAX_AGE_MS = 2 * 60 * 1000L }
}
