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

        val saveRequestId = AutofillSaveCoordinator.prepare(this, structure)
        val fields = CredentialFieldIds.from(
            structure, manualRequest = request.flags and FillRequest.FLAG_MANUAL_REQUEST != 0,
        )
        val domains = CredentialFieldIds.domainsFrom(structure)
        val schemes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            CredentialFieldIds.schemesFrom(structure)
        } else emptySet()
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
                schemes,
            )
        }
        val domain = origin?.takeUnless { it.requiresSelection }?.domains?.singleOrNull()
        val generate = domain != null && fields.newPasswordIds.isNotEmpty() &&
            fields.currentPasswordIds.isEmpty() && history.hasActiveSession().also {
                lastRequest = lastRequest.copy(generationSession = availability(it))
            }
        if ((fields.passwordIds.isEmpty() && fields.usernameIds.isEmpty() && !generate) ||
            origin == null ||
            (fields.requiresUsernameConfirmation && origin.mode == AutofillOriginMode.WEB) ||
            (!generate && !cacheStore.hasCache().also {
                lastRequest = lastRequest.copy(cache = availability(it))
            })
        ) {
            lastRequest = lastRequest.copy(result = RequestResult.REJECTED)
            callback.onSuccess(saveRequestId?.let {
                AutofillSaveCoordinator.response(FillResponse.Builder(), it).build()
            })
            return
        }

        val launchIntent = Intent(this, AutofillAuthenticationActivity::class.java).apply {
            putExtra(AutofillSaveCoordinator.EXTRA_REQUEST, saveRequestId)
            putExtra(AutofillAuthenticationActivity.EXTRA_DOMAIN, domain)
            putExtra(AutofillAuthenticationActivity.EXTRA_WEB_SCHEME, schemes.firstOrNull())
            putExtra(AutofillAuthenticationActivity.EXTRA_ORIGIN_MODE, origin.mode.name)
            putStringArrayListExtra(
                AutofillAuthenticationActivity.EXTRA_NATIVE_DOMAINS,
                if (origin.requiresSelection) ArrayList(origin.domains) else null,
            )
            putExtra(AutofillAuthenticationActivity.EXTRA_GENERATE, generate)
            putExtra(AutofillAuthenticationActivity.EXTRA_USERNAME_CONFIRMATION, fields.requiresUsernameConfirmation)
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
        val responseBuilder = AutofillSaveCoordinator.response(FillResponse.Builder(), saveRequestId)
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
        // Fixed, value-free attribution intent is reused across requests. Long
        // press opens Palladin; selecting the chip uses the authentication intent.
        val attribution = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val content = autofillInlineContent(this, generate, attribution)
        return InlinePresentation(content.slice, spec, false)
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        try {
            AutofillSaveCoordinator.save(this, request, callback)
        } catch (_: Exception) {
            AutofillSaveCoordinator.clear()
            callback.onFailure(getString(R.string.autofill_save_unavailable))
        }
    }

    private fun availability(available: Boolean): CheckAvailability =
        if (available) CheckAvailability.AVAILABLE else CheckAvailability.UNAVAILABLE

    internal data class CredentialFieldIds(
        val usernameIds: List<AutofillId>,
        val passwordIds: List<AutofillId>,
        val newPasswordIds: List<AutofillId>,
        val currentPasswordIds: List<AutofillId>,
        val confirmationIds: List<AutofillId>,
        val requiresUsernameConfirmation: Boolean = false,
    ) {
        val allIds: List<AutofillId> = (usernameIds + passwordIds + newPasswordIds).distinct()

        companion object {
            private enum class Role { USERNAME, PASSWORD, CURRENT_PASSWORD, NEW_PASSWORD, CONFIRMATION }
            private sealed interface Decision {
                data class Matched(val role: Role) : Decision
                data object Unknown : Decision
                data object Rejected : Decision
            }
            private data class Candidate(
                val node: AssistStructure.ViewNode,
                val parent: AssistStructure.ViewNode?,
                val decision: Decision,
            )

            fun from(structure: AssistStructure, manualRequest: Boolean = false): CredentialFieldIds {
                val candidates = mutableListOf<Candidate>()
                for (index in 0 until structure.windowNodeCount) {
                    collect(structure.getWindowNodeAt(index).rootViewNode, null, candidates)
                }
                fun ids(vararg roles: Role) = candidates.filter {
                    (it.decision as? Decision.Matched)?.role in roles
                }.mapNotNull { it.node.autofillId }
                val usernames = ids(Role.USERNAME).toMutableList()
                val passwords = ids(Role.PASSWORD, Role.CURRENT_PASSWORD)
                val newPasswords = ids(Role.NEW_PASSWORD)
                val currentPasswords = ids(Role.CURRENT_PASSWORD)
                val confirmations = candidates.filter {
                    it.decision != Decision.Rejected && it.node.isPasswordConfirmation()
                }.mapNotNull { it.node.autofillId }
                if (usernames.isEmpty() && passwords.size == 1 && newPasswords.isEmpty() && confirmations.isEmpty()) {
                    val structural = candidates.filter { it.node.isNativeEditable() }
                        .groupBy { it.parent }.values.mapNotNull { group ->
                            if (group.size != 2 || group.count {
                                (it.decision as? Decision.Matched)?.role in setOf(Role.PASSWORD, Role.CURRENT_PASSWORD)
                            } != 1) null else group.singleOrNull {
                                it.decision == Decision.Unknown && it.node.isNativeEditableText()
                            }
                        }
                    if (structural.size == 1) usernames += structural.single().node.autofillId!!
                }
                if (usernames.isEmpty()) {
                    val labeled = candidates.filter {
                        it.decision == Decision.Unknown && it.node.hasNativeUsernameLabel()
                    }
                    if (labeled.size == 1) usernames += labeled.single().node.autofillId!!
                }
                var requiresUsernameConfirmation = false
                if (manualRequest && usernames.isEmpty() && passwords.isEmpty() &&
                    newPasswords.isEmpty() && confirmations.isEmpty() && domainsFrom(structure).isEmpty() &&
                    candidates.none { it.decision == Decision.Rejected && it.node.hasCredentialMetadata() }
                ) {
                    val focused = candidates.filter { it.node.isFocused }
                    val candidate = focused.singleOrNull()?.takeIf {
                        it.decision == Decision.Unknown && it.node.isNativeEditableText()
                    }
                    if (candidate != null) {
                        usernames += candidate.node.autofillId!!
                        requiresUsernameConfirmation = true
                    }
                }
                return CredentialFieldIds(usernames, passwords, newPasswords, currentPasswords,
                    confirmations, requiresUsernameConfirmation)
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

            @android.annotation.TargetApi(28)
            fun schemesFrom(structure: AssistStructure): Set<String> {
                val schemes = mutableSetOf<String>()
                fun collect(node: AssistStructure.ViewNode) {
                    if (!node.webDomain.isNullOrEmpty()) {
                        // A sibling's HTTPS scheme cannot establish this node's transport.
                        schemes += node.webScheme.orEmpty()
                    } else {
                        node.webScheme?.takeIf(String::isNotEmpty)?.let(schemes::add)
                    }
                    for (index in 0 until node.childCount) collect(node.getChildAt(index))
                }
                for (index in 0 until structure.windowNodeCount) {
                    collect(structure.getWindowNodeAt(index).rootViewNode)
                }
                return schemes
            }

            private fun collect(
                node: AssistStructure.ViewNode,
                parent: AssistStructure.ViewNode?,
                candidates: MutableList<Candidate>,
                ancestorsVisible: Boolean = true,
            ) {
                val visible = ancestorsVisible && node.visibility == View.VISIBLE
                candidates += Candidate(node, parent, if (visible) node.classify() else Decision.Rejected)
                for (index in 0 until node.childCount) collect(node.getChildAt(index), node, candidates, visible)
            }

            private fun AssistStructure.ViewNode.hasCredentialMetadata(): Boolean =
                !autofillHints.isNullOrEmpty() || isPasswordField() || isUsernameField() || hasNativeUsernameLabel()

            private fun AssistStructure.ViewNode.classify(): Decision {
                if (autofillId == null || !isEnabled || !isCredentialTarget()) return Decision.Rejected
                if (hasHint("one-time-code") || hasHint("smsOTPCode") ||
                    hasHint("2faAppOTPCode") || hasHint("emailOTPCode")
                ) return Decision.Rejected
                if (hasHint(NEW_PASSWORD_HINT) || hasHint(WEB_NEW_PASSWORD_HINT)) {
                    return Decision.Matched(Role.NEW_PASSWORD)
                }
                if (isPasswordConfirmation()) return Decision.Matched(Role.CONFIRMATION)
                if (hasHint(View.AUTOFILL_HINT_PASSWORD) || hasHint(WEB_CURRENT_PASSWORD_HINT)) {
                    return Decision.Matched(Role.CURRENT_PASSWORD)
                }
                if (isPasswordField()) return Decision.Matched(Role.PASSWORD)
                if (htmlInfo == null && nativeUsernamePurposeConflict()) return Decision.Rejected
                if (isUsernameField()) return Decision.Matched(Role.USERNAME)
                if (!autofillHints.isNullOrEmpty()) return Decision.Rejected
                return Decision.Unknown
            }

            private fun AssistStructure.ViewNode.isNativeEditable(): Boolean =
                htmlInfo == null && autofillId != null && visibility == View.VISIBLE && isEnabled &&
                    isFocusable && autofillType == View.AUTOFILL_TYPE_TEXT &&
                    (inputType and InputType.TYPE_MASK_CLASS) != InputType.TYPE_NULL

            private fun AssistStructure.ViewNode.isNativeEditableText(): Boolean =
                isNativeEditable() && (inputType and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT

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

            private fun AssistStructure.ViewNode.isCredentialTarget(): Boolean {
                if (autofillType != View.AUTOFILL_TYPE_TEXT) return false
                if ((inputType and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT &&
                    (inputType and InputType.TYPE_MASK_VARIATION) == InputType.TYPE_TEXT_VARIATION_FILTER
                ) return false
                if (idEntry in setOf("search", "search_src_text")) return false
                val html = htmlInfo ?: return true
                if (!html.tag.equals("input", ignoreCase = true)) return false
                if (html.attributes.orEmpty().any {
                    it.first.equals("disabled", true) || it.first.equals("readonly", true)
                }) return false
                return htmlAttribute("type")?.lowercase(java.util.Locale.ROOT)
                    .let { it == null || it in setOf("text", "email", "password") }
            }

            private fun AssistStructure.ViewNode.isPasswordConfirmation(): Boolean =
                hasHint("confirmPassword") || hasHint("confirm-password") ||
                    hasHint("passwordConfirmation") || listOf(idEntry, htmlAttribute("name"), htmlAttribute("id"))
                    .any { identifier ->
                        identifier?.lowercase(java.util.Locale.ROOT)?.replace("_", "")
                            ?.replace("-", "") in setOf("confirmpassword", "passwordconfirmation")
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

            private fun AssistStructure.ViewNode.nativeUsernameLabels(): List<String> =
                (listOfNotNull(idEntry, hint) + autofillHints.orEmpty()).filter { it.length <= 256 }.map { label ->
                    label.trim().replace(Regex("([a-z])([A-Z])"), "$1 $2")
                        .lowercase(java.util.Locale.ROOT).replace(Regex("[_-]+"), " ")
                        .replace(Regex("\\s+"), " ").replace(Regex("\\s*:\\s*\\*?$|\\s*\\*$"), "").trim()
                        .replace(Regex("^(enter|type|wpisz|podaj) (?:(your|swój|swoj) )?"), "")
                }

            private fun AssistStructure.ViewNode.nativeUsernamePurposeConflict(): Boolean =
                listOfNotNull(idEntry, hint).any { it.length > 256 } || nativeUsernameLabels().any { label ->
                    label.split(Regex("[^\\p{L}\\p{N}]+"))
                        .any { it in NON_USERNAME_WORDS }
                }

            private fun AssistStructure.ViewNode.hasNativeUsernameLabel(): Boolean {
                if (htmlInfo != null || !autofillHints.isNullOrEmpty() ||
                    (inputType and InputType.TYPE_MASK_CLASS) != InputType.TYPE_CLASS_TEXT ||
                    nativeUsernamePurposeConflict()
                ) return false
                return nativeUsernameLabels().any { label ->
                    if (label in STRONG_USERNAME_LABELS) true else {
                        val alternatives = label.split(Regex("\\s+(?:or|lub|albo)\\s+|\\s*/\\s*"))
                        alternatives.size == 2 && (
                            alternatives[0] in STRONG_USERNAME_LABELS && alternatives[1] in EMAIL_LABELS ||
                                alternatives[1] in STRONG_USERNAME_LABELS && alternatives[0] in EMAIL_LABELS
                            )
                    }
                }
            }

            private val STRONG_USERNAME_LABELS = setOf(
                "username", "user name", "user id", "login", "nazwa użytkownika", "nazwa uzytkownika",
            )
            private val EMAIL_LABELS = setOf("email", "e mail", "email address", "adres email", "adres e mail")
            private val NON_USERNAME_WORDS = setOf(
                "search", "szukaj", "wyszukaj", "newsletter", "subscribe", "subscription",
                "otp", "code", "kod", "pin", "confirm", "confirmation", "repeat",
                "potwierdź", "potwierdz", "powtórz", "powtorz", "password", "hasło", "haslo",
                "new", "nowy", "nowa",
            )

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
