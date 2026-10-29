package io.palladin.mobile

import org.json.JSONArray
import org.json.JSONObject

internal fun syntheticFailureEvidence(phases: List<String>, error: Throwable?): JSONObject {
    val allowedPhases = setOf("CREATED", "AUTH_LAUNCHED", "RESULT_STARTED", "RESULT_VERIFIED", "RESULT_MISMATCH", "RESULT_REJECTED", "STOPPED", "RESUMED", "UNCAUGHT")
    fun symbol(value: String): String = value.takeIf {
        it.length <= 160 && it.matches(Regex("[A-Za-z0-9_.$<>]+"))
    } ?: "invalid"
    return JSONObject().put("phases", JSONArray(phases.filter { it in allowedPhases }.takeLast(16))).apply {
        if (error != null) {
            put("exceptionClass", symbol(error.javaClass.name))
            put("frames", JSONArray(error.stackTrace.take(12).map {
                JSONObject().put("class", symbol(it.className)).put("method", symbol(it.methodName)).put("line", it.lineNumber)
            }))
        }
    }
}

internal fun syntheticFailureHandler(
    prior: Thread.UncaughtExceptionHandler,
    capture: (Throwable) -> Unit,
): Thread.UncaughtExceptionHandler = Thread.UncaughtExceptionHandler { thread, error ->
    try { capture(error) } catch (_: Exception) { /* Preserve the original uncaught failure. */ }
    finally { prior.uncaughtException(thread, error) }
}
