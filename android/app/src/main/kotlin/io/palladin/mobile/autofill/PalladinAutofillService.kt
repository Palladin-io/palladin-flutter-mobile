package io.palladin.mobile.autofill

import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.widget.RemoteViews
import io.palladin.mobile.R

/**
 * System Autofill entry point.
 *
 * It detects a domain-addressable login form and exposes only a biometric
 * authentication action. Credential values stay encrypted until
 * [AutofillAuthenticationActivity] completes a Keystore-bound biometric
 * operation and returns domain-matched datasets.
 */
class PalladinAutofillService : AutofillService() {
    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: android.os.CancellationSignal,
        callback: FillCallback,
    ) {
        if (cancellationSignal.isCanceled) {
            callback.onSuccess(null)
            return
        }

        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }

        val fields = CredentialFieldIds.from(structure)
        val domain = CredentialFieldIds.domainFrom(structure)
        val cacheStore = AutoFillCacheStore(this)
        if (fields.passwordIds.isEmpty() || domain == null || !cacheStore.hasCache()) {
            callback.onSuccess(null)
            return
        }

        val launchIntent = Intent(this, AutofillAuthenticationActivity::class.java).apply {
            putExtra(AutofillAuthenticationActivity.EXTRA_DOMAIN, domain)
            putParcelableArrayListExtra(
                AutofillAuthenticationActivity.EXTRA_USERNAME_IDS,
                ArrayList(fields.usernameIds),
            )
            putParcelableArrayListExtra(
                AutofillAuthenticationActivity.EXTRA_PASSWORD_IDS,
                ArrayList(fields.passwordIds),
            )
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            domain.hashCode(),
            launchIntent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val presentation = RemoteViews(packageName, R.layout.autofill_unlock_prompt)
        val response = FillResponse.Builder()
            .setAuthentication(
                fields.allIds.toTypedArray(),
                pendingIntent.intentSender,
                presentation,
            )
            .build()

        callback.onSuccess(response)
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // Saving credentials requires an explicit user-confirmation flow and
        // is intentionally outside the current MVP implementation.
        callback.onSuccess()
    }

    private data class CredentialFieldIds(
        val usernameIds: List<AutofillId>,
        val passwordIds: List<AutofillId>,
    ) {
        val allIds: List<AutofillId> = (usernameIds + passwordIds).distinct()

        companion object {
            fun from(structure: AssistStructure): CredentialFieldIds {
                val usernames = mutableListOf<AutofillId>()
                val passwords = mutableListOf<AutofillId>()

                for (index in 0 until structure.windowNodeCount) {
                    collect(
                        structure.getWindowNodeAt(index).rootViewNode,
                        usernames,
                        passwords,
                    )
                }
                return CredentialFieldIds(usernames, passwords)
            }

            fun domainFrom(structure: AssistStructure): String? {
                val domains = mutableSetOf<String>()
                for (index in 0 until structure.windowNodeCount) {
                    collectDomains(
                        structure.getWindowNodeAt(index).rootViewNode,
                        domains,
                    )
                }
                return domains.singleOrNull()
            }

            private fun collect(
                node: AssistStructure.ViewNode,
                usernames: MutableList<AutofillId>,
                passwords: MutableList<AutofillId>,
            ) {
                val id = node.autofillId
                if (id != null) {
                    when {
                        node.isPasswordField() -> passwords += id
                        node.isUsernameField() -> usernames += id
                    }
                }
                for (index in 0 until node.childCount) {
                    collect(node.getChildAt(index), usernames, passwords)
                }
            }

            private fun collectDomains(
                node: AssistStructure.ViewNode,
                domains: MutableSet<String>,
            ) {
                AutoFillCacheStore.normalizeDomain(node.webDomain)?.let(domains::add)
                for (index in 0 until node.childCount) {
                    collectDomains(node.getChildAt(index), domains)
                }
            }

            private fun AssistStructure.ViewNode.isPasswordField(): Boolean {
                if (hasHint(View.AUTOFILL_HINT_PASSWORD)) return true
                if ((inputType and InputType.TYPE_MASK_CLASS) != InputType.TYPE_CLASS_TEXT) {
                    return false
                }
                return when (inputType and InputType.TYPE_MASK_VARIATION) {
                    InputType.TYPE_TEXT_VARIATION_PASSWORD,
                    InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
                    InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
                    -> true
                    else -> false
                }
            }

            private fun AssistStructure.ViewNode.isUsernameField(): Boolean {
                if (hasHint(View.AUTOFILL_HINT_USERNAME) ||
                    hasHint(View.AUTOFILL_HINT_EMAIL_ADDRESS)
                ) {
                    return true
                }
                if ((inputType and InputType.TYPE_MASK_CLASS) != InputType.TYPE_CLASS_TEXT) {
                    return false
                }
                return when (inputType and InputType.TYPE_MASK_VARIATION) {
                    InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                    InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
                    -> true
                    else -> false
                }
            }

            private fun AssistStructure.ViewNode.hasHint(expected: String): Boolean =
                autofillHints.orEmpty().any { it.equals(expected, ignoreCase = true) }
        }
    }

}
