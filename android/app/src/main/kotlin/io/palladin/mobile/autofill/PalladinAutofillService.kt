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
import io.palladin.mobile.MainActivity
import io.palladin.mobile.R

/**
 * System Autofill entry point.
 *
 * This first stage deliberately exposes no credential data. It only detects a
 * login form and offers an authenticated action that opens Palladin. A later
 * stage will replace that action with domain-matched datasets decrypted from
 * an OS-protected cache after explicit user authentication.
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
        if (fields.passwordIds.isEmpty()) {
            callback.onSuccess(null)
            return
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_UNLOCK_FOR_AUTOFILL
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra(EXTRA_AUTOFILL_UNLOCK_REQUESTED, true)
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            AUTOFILL_UNLOCK_REQUEST_CODE,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
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
        // Saving credentials is intentionally unsupported until the encrypted
        // native cache and an explicit user-confirmation flow are implemented.
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

    private companion object {
        const val ACTION_UNLOCK_FOR_AUTOFILL = "io.palladin.mobile.action.UNLOCK_FOR_AUTOFILL"
        const val EXTRA_AUTOFILL_UNLOCK_REQUESTED = "palladin.autofill.unlock_requested"
        const val AUTOFILL_UNLOCK_REQUEST_CODE = 276
    }
}
