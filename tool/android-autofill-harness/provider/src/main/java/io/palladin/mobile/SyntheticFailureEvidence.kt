package io.palladin.mobile

import org.json.JSONArray
import org.json.JSONObject

internal fun syntheticFailureEvidence(phases: List<String>, error: Throwable?): JSONObject {
    val allowedPhases = setOf("CREATED", "AUTH_LAUNCHED", "RESULT_STARTED", "RESULT_VERIFIED", "RESULT_MISMATCH", "RESULT_REJECTED", "STOPPED", "RESUMED", "UNCAUGHT")
    fun symbol(value: String): String = value.takeIf {
        it.length <= 160 && it.matches(Regex("[A-Za-z0-9_.$<>]+"))
    } ?: "invalid"
    fun metadata(failure: Throwable) = JSONObject()
        .put("exceptionClass", symbol(failure.javaClass.name))
        .put("frames", JSONArray(failure.stackTrace.take(12).map {
            JSONObject().put("class", symbol(it.className)).put("method", symbol(it.methodName)).put("line", it.lineNumber)
        }))
    val report = error?.let(::metadata) ?: JSONObject()
    report.put("phases", JSONArray(phases.filter { it in allowedPhases }.takeLast(16)))
    val causes = JSONArray()
    val seen = java.util.Collections.newSetFromMap(java.util.IdentityHashMap<Throwable, Boolean>())
    if (error != null) seen.add(error)
    var cause = error?.cause
    while (cause != null && causes.length() < 2 && seen.add(cause)) {
        causes.put(metadata(cause))
        cause = cause.cause
    }
    return report.put("causes", causes)
}

internal fun syntheticFailureHandler(
    prior: Thread.UncaughtExceptionHandler,
    capture: (Throwable) -> Unit,
): Thread.UncaughtExceptionHandler = Thread.UncaughtExceptionHandler { thread, error ->
    try { capture(error) } catch (_: Exception) { /* Preserve the original uncaught failure. */ }
    finally { prior.uncaughtException(thread, error) }
}
