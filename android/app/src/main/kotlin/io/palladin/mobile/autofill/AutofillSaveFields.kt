package io.palladin.mobile.autofill

import android.app.assist.AssistStructure
import android.view.autofill.AutofillId

internal data class AutofillSaveFields(val username: AutofillId, val password: AutofillId) {
    fun isBoundTo(structure: AssistStructure, source: AutofillSaveSource): Boolean {
        var matched = 0
        var invalid = false
        val forms = mutableSetOf<AssistStructure.ViewNode?>()
        fun visit(node: AssistStructure.ViewNode, host: String?, scheme: String?, form: AssistStructure.ViewNode?) {
            val ownHost = node.webDomain?.takeIf(String::isNotEmpty)
            val inheritedHost = ownHost ?: host
            val inheritedScheme = if (ownHost != null) node.webScheme else node.webScheme?.takeIf(String::isNotEmpty) ?: scheme
            val currentForm = if (node.htmlInfo?.tag.equals("form", true)) node else form
            if (node.autofillId == username || node.autofillId == password) {
                matched++
                forms.add(currentForm)
                if (source.mode == AutofillOriginMode.WEB) {
                    invalid = invalid || AutoFillCacheStore.normalizeDomain(inheritedHost.orEmpty()) !in source.domains ||
                        !AutofillOriginPolicy.isSecureWebScheme(inheritedScheme)
                } else invalid = invalid || inheritedHost != null || inheritedScheme != null
            }
            for (index in 0 until node.childCount) visit(node.getChildAt(index), inheritedHost, inheritedScheme, currentForm)
        }
        if (!bounded(structure)) return false
        for (index in 0 until structure.windowNodeCount) visit(structure.getWindowNodeAt(index).rootViewNode, null, null, null)
        return matched == 2 && !invalid && forms.size == 1
    }

    fun read(structure: AssistStructure): AutofillSaveValues? {
        if (from(structure) != this) return null
        var user: CharArray? = null
        var secret: CharArray? = null
        var count = 0
        fun visit(node: AssistStructure.ViewNode) {
            if (++count > 10000) return
            if (node.autofillId == username || node.autofillId == password) {
                val value = node.autofillValue?.takeIf { it.isText }?.textValue
                val limit = if (node.autofillId == username) 1024 else 4096
                if (value != null && value.isNotEmpty() && value.length <= limit) {
                    val chars = CharArray(value.length) { value[it] }
                    if (node.autofillId == username) user = chars else secret = chars
                }
            }
            for (index in 0 until node.childCount) visit(node.getChildAt(index))
        }
        for (index in 0 until structure.windowNodeCount) visit(structure.getWindowNodeAt(index).rootViewNode)
        if (user == null || secret == null || count > 10000) {
            user?.fill('\u0000'); secret?.fill('\u0000')
            return null
        }
        return AutofillSaveValues(user, secret)
    }

    companion object {
        private fun bounded(structure: AssistStructure): Boolean {
            var count = 0
            fun visit(node: AssistStructure.ViewNode, depth: Int): Boolean {
                if (++count > 10000 || depth > 64 || node.childCount > 10000) return false
                for (index in 0 until node.childCount) if (!visit(node.getChildAt(index), depth + 1)) return false
                return true
            }
            return structure.windowNodeCount == 1 && visit(structure.getWindowNodeAt(0).rootViewNode, 0)
        }

        fun from(structure: AssistStructure): AutofillSaveFields? {
            if (structure.windowNodeCount != 1 || !bounded(structure)) return null
            val ids = PalladinAutofillService.CredentialFieldIds.from(structure)
            val username = ids.usernameIds.singleOrNull() ?: return null
            // Password-change and confirmation forms are deliberately not captured.
            val password = (ids.passwordIds + ids.newPasswordIds).singleOrNull() ?: return null
            if (username == password || ids.confirmationIds.isNotEmpty()) return null
            return AutofillSaveFields(username, password)
        }
    }
}
