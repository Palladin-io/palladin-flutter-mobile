package io.palladin.mobile.autofill

/** A one-operation UI confirmation, never an origin-verification or association record. */
internal class ManualAutofillSelection(private val requestingPackage: String) {
    private var choice: Pair<String, String>? = null
    private var finished = false

    fun select(recordId: String, domain: String) {
        if (!finished) choice = recordId to domain
    }

    fun confirm(recordId: String, domain: String, targetPackage: String): Boolean {
        if (finished || targetPackage != requestingPackage || choice != (recordId to domain)) return false
        cancel()
        return true
    }

    fun cancel() {
        finished = true
        choice = null
    }
}
