package io.palladin.mobile.autofill

import android.os.Build
import java.io.FileDescriptor
import java.io.PrintWriter
import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Intent
import android.service.autofill.AutofillService
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.InlinePresentation
import androidx.autofill.inline.UiVersions
import androidx.autofill.inline.v1.InlineSuggestionUi
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import io.palladin.mobile.R
import io.palladin.mobile.MainActivity

/**
 * System Autofill entry point.
 *
 * It detects a domain-addressable login form and exposes only a biometric
 * authentication action. Credential values stay encrypted until
 * [AutofillAuthenticationActivity] completes a Keystore-bound biometric
 * operation and returns domain-matched datasets.
 */
class PalladinAutofillService : AutofillService() {
    private var lastRequest = AutofillRequestDiagnosis()

    // ActivityManagerService enforces DUMP/usage access before dispatching this
    // on the application main thread; Binder caller identity is not retained here.
    override fun dump(fd: FileDescriptor, writer: PrintWriter, args: Array<out String>?) {
        lastRequest.dump(writer)
    }

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: android.os.CancellationSignal,
        callback: FillCallback,
    ) {
        lastRequest = AutofillRequestDiagnosis(
            result = RequestResult.CHECKING,
            inlineRequestPresent = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                request.inlineSuggestionsRequest != null,
        )
        if (cancellationSignal.isCanceled) {
            lastRequest = lastRequest.copy(result = RequestResult.CANCELED)
            callback.onSuccess(null)
            return
        }

        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            lastRequest = lastRequest.copy(result = RequestResult.NO_STRUCTURE)
            callback.onSuccess(null)
            return
        }

        val fields = CredentialFieldIds.from(structure)
        val domains = CredentialFieldIds.domainsFrom(structure)
        val requestingPackage = structure.activityComponent?.packageName
        lastRequest = lastRequest.copy(
            passwordCount = fields.passwordIds.size,
            domains = when (domains.size) {
                0 -> DomainCount.ZERO
                1 -> DomainCount.ONE
                else -> DomainCount.AMBIGUOUS
            },
            requestingPackagePresent = requestingPackage != null,
        )
        val cacheStore = AutoFillCacheStore(this)
        val history = GeneratedPasswordHistory(this)
        val verifier = AutofillOriginVerifier(this)
        val origin = requestingPackage?.let { targetPackage ->
            AutofillOriginPolicy.resolve(
                domains,
                AutoFillCacheStore::normalizeDomain,
                { host ->
                    verifier.status(targetPackage, host).also {
                        lastRequest = lastRequest.copy(origin = it)
                    } == OriginStatus.VERIFIED
                },
                {
                    verifier.nativeDomains(targetPackage) {
                        lastRequest = lastRequest.copy(origin = it)
                    }
                },
                domains.isEmpty() && verifier.isBrowser(targetPackage),
            )
        }
        val domain = origin?.takeUnless { it.requiresSelection }?.domains?.singleOrNull()
        val generate = domain != null && fields.newPasswordIds.isNotEmpty() &&
            fields.currentPasswordIds.isEmpty() && history.hasActiveSession().also {
                lastRequest = lastRequest.copy(generationSession = availability(it))
            }
        if ((fields.passwordIds.isEmpty() && fields.usernameIds.isEmpty() && !generate) ||
            origin == null ||
            (!generate && !cacheStore.hasCache().also {
                lastRequest = lastRequest.copy(cache = availability(it))
            })
        ) {
            lastRequest = lastRequest.copy(result = RequestResult.REJECTED)
            callback.onSuccess(null)
            return
        }

        val launchIntent = Intent(this, AutofillAuthenticationActivity::class.java).apply {
            putExtra(AutofillAuthenticationActivity.EXTRA_DOMAIN, domain)
            putExtra(AutofillAuthenticationActivity.EXTRA_ORIGIN_MODE, origin.mode.name)
            putStringArrayListExtra(
                AutofillAuthenticationActivity.EXTRA_NATIVE_DOMAINS,
                if (origin.requiresSelection) ArrayList(origin.domains) else null,
            )
            putExtra(AutofillAuthenticationActivity.EXTRA_GENERATE, generate)
            putExtra(
                AutofillAuthenticationActivity.EXTRA_PACKAGE_NAME,
                requestingPackage,
            )
            putParcelableArrayListExtra(
                AutofillAuthenticationActivity.EXTRA_USERNAME_IDS,
                ArrayList(fields.usernameIds),
            )
            putParcelableArrayListExtra(
                AutofillAuthenticationActivity.EXTRA_PASSWORD_IDS,
                ArrayList(fields.passwordIds),
            )
            putParcelableArrayListExtra(
                AutofillAuthenticationActivity.EXTRA_NEW_PASSWORD_IDS,
                ArrayList(fields.newPasswordIds),
            )
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            requestingPackage.hashCode() xor origin.domains.hashCode(),
            launchIntent,
            PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val presentation = autofillPresentation(
            this,
            getString(if (generate) R.string.autofill_generate_prompt else R.string.autofill_unlock_label),
        )
        val responseBuilder = FillResponse.Builder()
        val inlinePresentation = inlineAuthenticationPresentation(request, generate)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && inlinePresentation != null) {
            responseBuilder.setAuthentication(
                fields.allIds.toTypedArray(), pendingIntent.intentSender,
                presentation, inlinePresentation,
            )
        } else {
            responseBuilder.setAuthentication(
                fields.allIds.toTypedArray(), pendingIntent.intentSender, presentation,
            )
        }
        val response = responseBuilder.build()

        lastRequest = lastRequest.copy(result = RequestResult.RESPONSE_OFFERED)
        callback.onSuccess(response)
    }

    private fun inlineAuthenticationPresentation(
        request: FillRequest,
        generate: Boolean,
    ): InlinePresentation? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null
        val inlineRequest = request.inlineSuggestionsRequest ?: return null
        val spec = inlineRequest.inlinePresentationSpecs.firstOrNull() ?: return null
        if (inlineRequest.maxSuggestionCount <= 0 ||
            !UiVersions.getVersions(spec.style).contains(UiVersions.INLINE_UI_VERSION_1)
        ) return null
        val label = getString(
            if (generate) R.string.autofill_generate_prompt else R.string.autofill_unlock_label,
        )
        // Fixed, value-free attribution intent is reused across requests. Long
        // press opens Palladin; selecting the chip uses the authentication intent.
        val attribution = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val content = InlineSuggestionUi.newContentBuilder(attribution)
            .setTitle(label)
            .setContentDescription(label)
            .build()
        return InlinePresentation(content.slice, spec, false)
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        // Saving credentials requires an explicit user-confirmation flow and
        // is intentionally outside the current MVP implementation.
        callback.onSuccess()
    }

    private fun availability(available: Boolean): CheckAvailability =
        if (available) CheckAvailability.AVAILABLE else CheckAvailability.UNAVAILABLE

    internal data class CredentialFieldIds(
        val usernameIds: List<AutofillId>,
        val passwordIds: List<AutofillId>,
        val newPasswordIds: List<AutofillId>,
        val currentPasswordIds: List<AutofillId>,
    ) {
        val allIds: List<AutofillId> = (usernameIds + passwordIds + newPasswordIds).distinct()

        companion object {
            fun from(structure: AssistStructure): CredentialFieldIds {
                val usernames = mutableListOf<AutofillId>()
                val passwords = mutableListOf<AutofillId>()
                val newPasswords = mutableListOf<AutofillId>()
                val currentPasswords = mutableListOf<AutofillId>()

                for (index in 0 until structure.windowNodeCount) {
                    collect(
                        structure.getWindowNodeAt(index).rootViewNode,
                        usernames,
                        passwords,
                        newPasswords,
                        currentPasswords,
                    )
                }
                return CredentialFieldIds(usernames, passwords, newPasswords, currentPasswords)
            }

            fun domainsFrom(structure: AssistStructure): Set<String> {
                val domains = mutableSetOf<String>()
                for (index in 0 until structure.windowNodeCount) {
                    collectDomains(
                        structure.getWindowNodeAt(index).rootViewNode,
                        domains,
                    )
                }
                return domains
            }

            private fun collect(
                node: AssistStructure.ViewNode,
                usernames: MutableList<AutofillId>,
                passwords: MutableList<AutofillId>,
                newPasswords: MutableList<AutofillId>,
                currentPasswords: MutableList<AutofillId>,
            ) {
                val id = node.autofillId
                if (id != null) {
                    when {
                        node.hasHint("one-time-code") || node.hasHint("smsOTPCode") ||
                            node.hasHint("2faAppOTPCode") -> Unit
                        node.hasHint(NEW_PASSWORD_HINT) || node.hasHint(WEB_NEW_PASSWORD_HINT) ->
                            newPasswords += id
                        node.hasHint(View.AUTOFILL_HINT_PASSWORD) ||
                            node.hasHint(WEB_CURRENT_PASSWORD_HINT) -> {
                            passwords += id
                            currentPasswords += id
                        }
                        node.isPasswordField() -> passwords += id
                        node.isUsernameField() -> usernames += id
                    }
                }
                for (index in 0 until node.childCount) {
                    collect(node.getChildAt(index), usernames, passwords, newPasswords, currentPasswords)
                }
            }

            private fun collectDomains(
                node: AssistStructure.ViewNode,
                domains: MutableSet<String>,
            ) {
                // WebView containers report an empty sentinel while virtual inputs
                // carry the real host. Keep every nonempty value for origin validation.
                node.webDomain?.takeIf(String::isNotEmpty)?.let(domains::add)
                for (index in 0 until node.childCount) {
                    collectDomains(node.getChildAt(index), domains)
                }
            }

            private fun AssistStructure.ViewNode.isPasswordField(): Boolean {
                if (hasHint(View.AUTOFILL_HINT_PASSWORD) ||
                    htmlAttribute("type")?.equals("password", true) == true
                ) return true
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
                    hasHint(View.AUTOFILL_HINT_EMAIL_ADDRESS) || hasHint("email") ||
                    htmlAttribute("type")?.equals("email", true) == true ||
                    (htmlAttribute("type").let { it == null || it.equals("text", true) } &&
                        listOf(htmlAttribute("name"), htmlAttribute("id")).any {
                            it?.lowercase(java.util.Locale.ROOT) in USERNAME_RESOURCE_NAMES
                        })
                ) {
                    return true
                }
                if ((inputType and InputType.TYPE_MASK_CLASS) != InputType.TYPE_CLASS_TEXT) {
                    return false
                }
                if (idEntry?.lowercase(java.util.Locale.ROOT) in USERNAME_RESOURCE_NAMES) {
                    return true
                }
                return when (inputType and InputType.TYPE_MASK_VARIATION) {
                    InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                    InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
                    -> true
                    else -> false
                }
            }

            private fun AssistStructure.ViewNode.hasHint(expected: String): Boolean =
                autofillHints.orEmpty().any { it.equals(expected, ignoreCase = true) } ||
                    htmlAttribute("autocomplete")?.split(Regex("\\s+"))
                        ?.any { it.equals(expected, ignoreCase = true) } == true

            private fun AssistStructure.ViewNode.htmlAttribute(name: String): String? =
                htmlInfo?.takeIf { it.tag.equals("input", ignoreCase = true) }
                    ?.attributes?.firstOrNull { it.first.equals(name, ignoreCase = true) }?.second

            private val USERNAME_RESOURCE_NAMES =
                setOf("username", "user_name", "email", "email_address", "login")
            private const val NEW_PASSWORD_HINT = "newPassword"
            private const val WEB_NEW_PASSWORD_HINT = "new-password"
            private const val WEB_CURRENT_PASSWORD_HINT = "current-password"
        }
    }

}
