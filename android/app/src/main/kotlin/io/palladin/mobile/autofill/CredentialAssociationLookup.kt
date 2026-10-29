package io.palladin.mobile.autofill

import okhttp3.Call
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.FutureTask
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** A stuck platform DNS resolver can occupy at most two workers, never create more. */
internal class CredentialAssociationLookup(
    private val fetch: (CredentialAssociationKey, (Call) -> Boolean) -> Boolean,
    private val deadlineMs: Long = 3000,
) {
    fun submit(key: CredentialAssociationKey, result: (Boolean) -> Unit): () -> Unit {
        val completed = AtomicBoolean()
        val call = AtomicReference<Call?>()
        val work = AtomicReference<FutureTask<Unit>?>()
        val deadline = AtomicReference<java.util.concurrent.ScheduledFuture<*>?>()
        fun finish(allowed: Boolean, stop: Boolean) {
            if (!completed.compareAndSet(false, true)) return
            deadline.get()?.cancel(false)
            if (stop) {
                call.get()?.cancel()
                work.get()?.let { it.cancel(true); workers.remove(it) }
            }
            result(allowed)
        }
        val task = FutureTask<Unit> {
            if (!completed.get()) {
                val allowed = runCatching {
                    fetch(key) { candidate ->
                        call.set(candidate)
                        if (completed.get()) { candidate.cancel(); false } else true
                    }
                }.getOrDefault(false)
                finish(allowed, false)
            }
        }
        work.set(task)
        deadline.set(timer.schedule({ finish(false, true) }, deadlineMs, TimeUnit.MILLISECONDS))
        try { workers.execute(task) } catch (_: RejectedExecutionException) { finish(false, true) }
        return { finish(false, true) }
    }

    private companion object {
        val workers = ThreadPoolExecutor(2, 2, 0, TimeUnit.MILLISECONDS, ArrayBlockingQueue(2),
            { task -> Thread(task, "credential-association").apply { isDaemon = true } })
        val timer = ScheduledThreadPoolExecutor(1) { task ->
            Thread(task, "credential-association-deadline").apply { isDaemon = true }
        }.apply { removeOnCancelPolicy = true }
    }
}
