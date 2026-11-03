package io.palladin.mobile.autofill

import android.app.assist.AssistStructure
import android.text.InputType
import android.util.Pair
import android.view.View
import android.view.ViewStructure
import android.view.autofill.AutofillId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`

class CredentialFieldIdsTest {
    @Test
    fun explicitManualRequestCanSelectOnlyFocusedUnknownNativeUsername() {
        val field = node(inputType = InputType.TYPE_CLASS_TEXT)
        `when`(field.isFocused).thenReturn(true)
        `when`(field.hint).thenReturn("識別子")
        assertEquals(emptyList<AutofillId>(), parse(field).allIds)
        val manual = PalladinAutofillService.CredentialFieldIds.from(structure(field), manualRequest = true)
        assertEquals(listOf(field.autofillId), manual.usernameIds)
        assertEquals(true, manual.requiresUsernameConfirmation)
        assertEquals(emptyList<AutofillId>(), manual.passwordIds)
    }

    @Test
    fun manualRequestCannotRecoverRejectedAmbiguousOrWebFields() {
        val excluded = listOf(
            node(inputType = InputType.TYPE_CLASS_TEXT, idEntry = "search"),
            node(inputType = InputType.TYPE_CLASS_TEXT, hints = arrayOf("smsOTPCode")),
            node(inputType = InputType.TYPE_CLASS_TEXT, hints = arrayOf("confirmPassword")),
            node(inputType = InputType.TYPE_CLASS_TEXT, hints = arrayOf("newPassword")),
            node(inputType = InputType.TYPE_CLASS_TEXT, html = mapOf("type" to "text")),
            node(inputType = InputType.TYPE_CLASS_TEXT).also { `when`(it.webDomain).thenReturn("fixture.invalid") },
            node(inputType = InputType.TYPE_CLASS_TEXT).also { `when`(it.isEnabled).thenReturn(false) },
            node(inputType = InputType.TYPE_CLASS_TEXT).also { `when`(it.visibility).thenReturn(View.GONE) },
            node(inputType = InputType.TYPE_CLASS_TEXT).also { `when`(it.autofillType).thenReturn(View.AUTOFILL_TYPE_NONE) },
        )
        for (field in excluded) {
            `when`(field.isFocused).thenReturn(true)
            assertEquals(false, PalladinAutofillService.CredentialFieldIds.from(
                structure(field), manualRequest = true).requiresUsernameConfirmation)
        }
        val first = node(inputType = InputType.TYPE_CLASS_TEXT)
        val second = node(inputType = InputType.TYPE_CLASS_TEXT)
        assertEquals(emptyList<AutofillId>(), PalladinAutofillService.CredentialFieldIds.from(
            structure(first), manualRequest = true).allIds)
        `when`(first.isFocused).thenReturn(true)
        `when`(second.isFocused).thenReturn(true)
        assertEquals(emptyList<AutofillId>(), PalladinAutofillService.CredentialFieldIds.from(
            structure(first, second), manualRequest = true).allIds)
    }

    @Test
    fun manualUnknownDoesNotRecoverAnExcludedCredentialThroughAnotherField() {
        val probe = node(inputType = InputType.TYPE_CLASS_TEXT)
        `when`(probe.isFocused).thenReturn(true)
        for (excluded in listOf(
            node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME)).also { `when`(it.visibility).thenReturn(View.GONE) },
            node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME)).also { `when`(it.isEnabled).thenReturn(false) },
            node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME)).also { `when`(it.autofillType).thenReturn(View.AUTOFILL_TYPE_NONE) },
        )) {
            assertEquals(emptyList<AutofillId>(), PalladinAutofillService.CredentialFieldIds.from(
                structure(probe, excluded), manualRequest = true).allIds)
        }
        val hiddenParent = node().also { `when`(it.visibility).thenReturn(View.GONE) }
        val child = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        `when`(hiddenParent.childCount).thenReturn(1)
        `when`(hiddenParent.getChildAt(0)).thenReturn(child)
        assertEquals(emptyList<AutofillId>(), PalladinAutofillService.CredentialFieldIds.from(
            structure(probe, hiddenParent), manualRequest = true).allIds)
    }

    @Test
    fun sameParentPasswordStructureRecognizesOpaqueUsernameWithoutLabels() {
        val username = node(inputType = InputType.TYPE_CLASS_TEXT)
        `when`(username.hint).thenReturn("利用者")
        val password = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
        val fields = parse(username, password)
        assertEquals(listOf(username.autofillId), fields.usernameIds)
        assertEquals(listOf(password.autofillId), fields.passwordIds)
    }

    @Test
    fun structuralInferenceDoesNotCrossParentsOrIgnoreConflictingThirdField() {
        val username = node(inputType = InputType.TYPE_CLASS_TEXT)
        val password = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
        val third = node(inputType = InputType.TYPE_CLASS_TEXT)
        assertEquals(emptyList<AutofillId>(), parse(username, password, third).usernameIds)
        val otp = node(inputType = InputType.TYPE_CLASS_TEXT, hints = arrayOf("smsOTPCode"))
        assertEquals(emptyList<AutofillId>(), parse(username, password, otp).usernameIds)
        val parent = node()
        `when`(parent.childCount).thenReturn(1)
        `when`(parent.getChildAt(0)).thenReturn(password)
        assertEquals(emptyList<AutofillId>(), parse(username, parent).usernameIds)
        for (role in listOf("newPassword", "confirmPassword")) {
            val other = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
                hints = arrayOf(role))
            assertEquals(emptyList<AutofillId>(), parse(username, other).usernameIds)
        }
    }

    @Test
    fun structuralInferenceRejectsAdditionalNumericAndSeparatePasswordTargets() {
        val username = node(inputType = InputType.TYPE_CLASS_TEXT)
        val password = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
        for (inputType in listOf(InputType.TYPE_CLASS_NUMBER, InputType.TYPE_CLASS_PHONE)) {
            val extra = node(inputType = inputType)
            assertEquals(emptyList<AutofillId>(), parse(username, password, extra).usernameIds)
        }
        val parent = node()
        val otherPassword = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
        `when`(parent.childCount).thenReturn(1)
        `when`(parent.getChildAt(0)).thenReturn(otherPassword)
        assertEquals(emptyList<AutofillId>(), parse(username, password, parent).usernameIds)
    }

    @Test
    fun structuralUsernameCandidateMustBeTextEvenWhenItIsTheOnlyUnknownField() {
        val password = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
        for (inputType in listOf(InputType.TYPE_CLASS_NUMBER, InputType.TYPE_CLASS_PHONE,
            InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD)) {
            val candidate = node(inputType = inputType)
            assertEquals(emptyList<AutofillId>(), parse(candidate, password).usernameIds)
            `when`(candidate.isFocused).thenReturn(true)
            assertEquals(emptyList<AutofillId>(), PalladinAutofillService.CredentialFieldIds.from(
                structure(candidate), manualRequest = true).allIds)
        }
    }

    @Test
    fun structuralPairCannotIgnoreAnEditableTargetInAnotherParent() {
        val username = node(inputType = InputType.TYPE_CLASS_TEXT)
        val password = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
        for (extra in listOf(node(inputType = InputType.TYPE_CLASS_TEXT),
            node(inputType = InputType.TYPE_CLASS_NUMBER), node(inputType = InputType.TYPE_CLASS_PHONE),
            node(inputType = InputType.TYPE_CLASS_TEXT, hints = arrayOf("smsOTPCode")))) {
            val parent = node()
            `when`(parent.childCount).thenReturn(1)
            `when`(parent.getChildAt(0)).thenReturn(extra)
            assertEquals(emptyList<AutofillId>(), parse(username, password, parent).usernameIds)
        }
    }

    @Test
    fun malformedNullHintsDoNotCrashOrEnableAnyFallback() {
        for (hints in listOf(arrayOf<String?>(null), arrayOf(View.AUTOFILL_HINT_USERNAME, null))) {
            @Suppress("UNCHECKED_CAST")
            val field = node(inputType = InputType.TYPE_CLASS_TEXT, hints = hints as Array<String>)
            `when`(field.hint).thenReturn("Adres e-mail lub login")
            `when`(field.isFocused).thenReturn(true)
            assertEquals(emptyList<AutofillId>(), parse(field).allIds)
            assertEquals(emptyList<AutofillId>(), PalladinAutofillService.CredentialFieldIds.from(
                structure(field), manualRequest = true).allIds)
            val password = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
            assertEquals(emptyList<AutofillId>(), parse(field, password).usernameIds)
        }
    }

    @Test
    fun rejectedPurposeCannotFallThroughToStructuralInference() {
        val password = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
        for (purpose in listOf("newsletter", "search", "otp", "confirm")) {
            val candidate = node(inputType = InputType.TYPE_CLASS_TEXT, idEntry = purpose)
            assertEquals(purpose, emptyList<AutofillId>(), parse(candidate, password).usernameIds)
        }
    }

    @Test
    fun nativeEmailTypeRejectsExplicitNonUsernameHintsBeforeWeakInference() {
        for (purpose in listOf("search", "newsletter")) {
            val field = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                hints = arrayOf(purpose))
            assertEquals(purpose, emptyList<AutofillId>(), parse(field).allIds)
            `when`(field.hint).thenReturn("Username")
            assertEquals(purpose, emptyList<AutofillId>(), parse(field).allIds)
        }
        val unknown = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
            hints = arrayOf("customNeutralHint"))
        assertEquals(listOf(unknown.autofillId), parse(unknown).usernameIds)
    }

    @Test
    fun nativeCompleteUsernameLabelsSupportBothLanguagesAndAlternatives() {
        for (label in listOf("Username", "Username: *", "userName", "user_id", "Login", "Nazwa użytkownika",
            "Wpisz swój login", "Enter your username:", "email or username", "Login / e-mail",
            "Adres e-mail lub login", "username albo adres email")) {
            val field = node(inputType = InputType.TYPE_CLASS_TEXT)
            `when`(field.hint).thenReturn(label)
            assertEquals(label, listOf(field.autofillId), parse(field).usernameIds)
        }
    }

    @Test
    fun nativeEmailTypeAndSemanticUsernameCannotOverrideConflictingPurpose() {
        for (label in listOf("newsletter", "subscribe", "Search", "usernameSearch", "loginCode",
            "confirm login", "new password", "kod weryfikacyjny")) {
            for (semantic in listOf(emptyArray<String>(), arrayOf(View.AUTOFILL_HINT_USERNAME))) {
                val field = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
                    idEntry = label, hints = semantic)
                `when`(field.hint).thenReturn("Username")
                assertEquals(label, emptyList<AutofillId>(), parse(field).allIds)
                val hintConflict = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS)
                `when`(hintConflict.hint).thenReturn(label)
                assertEquals(label, emptyList<AutofillId>(), parse(hintConflict).allIds)
            }
        }
    }

    @Test
    fun nativeEmailTypeAndExplicitUsernameStillWorkWithoutConflicts() {
        val email = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS)
        val explicit = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        assertEquals(listOf(email.autofillId), parse(email).usernameIds)
        assertEquals(listOf(explicit.autofillId), parse(explicit).usernameIds)
    }

    @Test
    fun nativeFallbackRequiresOneUnambiguousCandidateWithoutExplicitUsername() {
        val first = node(inputType = InputType.TYPE_CLASS_TEXT)
        val second = node(inputType = InputType.TYPE_CLASS_TEXT)
        `when`(first.hint).thenReturn("Login")
        `when`(second.hint).thenReturn("Username")
        assertEquals(emptyList<AutofillId>(), parse(first, second).allIds)
        val explicit = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        assertEquals(listOf(explicit.autofillId), parse(first, explicit).usernameIds)
    }

    @Test
    fun exactNativeLoginPlaceholderProducesUsernameOnlyTargets() {
        val username = node(inputType = InputType.TYPE_CLASS_TEXT)
        `when`(username.hint).thenReturn("Adres e-mail lub login")
        `when`(username.isFocused).thenReturn(true)
        val fields = parse(username)
        assertEquals(listOf(username.autofillId), fields.usernameIds)
        assertEquals(listOf(username.autofillId), fields.allIds)
        assertEquals(emptyList<AutofillId>(), fields.passwordIds)
    }

    @Test
    fun observedIfirmaSemanticFieldsRemainTargetsRegardlessOfFocusedField() {
        // Reduced physical metadata; see tool/android-autofill-harness/observed-ifirma.md.
        for (usernameFocused in listOf(false, true)) {
            val username = node(inputType = 33, hints = arrayOf("username"))
            val password = node(inputType = 129, hints = arrayOf("password"))
            val disabled = node(inputType = 16385)
            `when`(username.isFocused).thenReturn(usernameFocused)
            `when`(password.isFocused).thenReturn(!usernameFocused)
            `when`(disabled.isEnabled).thenReturn(false)
            val nested = node()
            `when`(nested.autofillType).thenReturn(View.AUTOFILL_TYPE_NONE)
            `when`(nested.childCount).thenReturn(1)
            `when`(nested.getChildAt(0)).thenReturn(disabled)
            val parent = node()
            `when`(parent.autofillType).thenReturn(View.AUTOFILL_TYPE_NONE)
            `when`(parent.childCount).thenReturn(3)
            listOf(username, password, nested).forEachIndexed { index, child ->
                `when`(parent.getChildAt(index)).thenReturn(child)
            }
            val request = structure(parent)
            val fields = PalladinAutofillService.CredentialFieldIds.from(request)
            assertEquals(listOf(username.autofillId), fields.usernameIds)
            assertEquals(listOf(password.autofillId), fields.passwordIds)
            assertEquals(listOf(username.autofillId, password.autofillId), fields.allIds)
            assertFalse(fields.requiresUsernameConfirmation)
            assertTrue(PalladinAutofillService.CredentialFieldIds.domainsFrom(request).isEmpty())
            assertTrue(PalladinAutofillService.CredentialFieldIds.schemesFrom(request).isEmpty())
        }
    }

    @Test
    fun ordinaryEmailAndNonexactPlaceholdersRemainUnclassified() {
        for (placeholder in listOf("Email", "Adres e-mail", "Newsletter", "Search", "Adres e-mail lub login newsletter", "notusername", "phone", "email or phone", "Login " + "x".repeat(256))) {
            val field = node(inputType = InputType.TYPE_CLASS_TEXT)
            `when`(field.hint).thenReturn(placeholder)
            assertEquals(placeholder, emptyList<AutofillId>(), parse(field).allIds)
        }
    }

    @Test
    fun nativeLoginPlaceholderDoesNotOverrideExclusionsOrWebSemantics() {
        val excluded = listOf(
            node(inputType = InputType.TYPE_CLASS_TEXT, idEntry = "search"),
            node(inputType = InputType.TYPE_CLASS_TEXT, idEntry = "Search"),
            node(inputType = InputType.TYPE_CLASS_TEXT, idEntry = "newsletter"),
            node(inputType = InputType.TYPE_CLASS_TEXT, idEntry = "otp"),
            node(inputType = InputType.TYPE_CLASS_TEXT, idEntry = "confirm"),
            node(inputType = InputType.TYPE_CLASS_TEXT, hints = arrayOf("search")),
            node(inputType = InputType.TYPE_CLASS_TEXT, hints = arrayOf("newsletter")),
            node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_FILTER),
            node(inputType = InputType.TYPE_CLASS_TEXT, hints = arrayOf("emailOTPCode")),
            node(inputType = InputType.TYPE_CLASS_TEXT, hints = arrayOf("confirmPassword")),
            node(inputType = InputType.TYPE_CLASS_NUMBER),
            node(inputType = InputType.TYPE_CLASS_TEXT, html = mapOf("type" to "text")),
            node(inputType = InputType.TYPE_CLASS_TEXT).also { `when`(it.isEnabled).thenReturn(false) },
            node(inputType = InputType.TYPE_CLASS_TEXT).also { `when`(it.visibility).thenReturn(View.GONE) },
            node(inputType = InputType.TYPE_CLASS_TEXT).also { `when`(it.autofillType).thenReturn(View.AUTOFILL_TYPE_NONE) },
        )
        for (field in excluded) {
            `when`(field.hint).thenReturn("Adres e-mail lub login")
            assertEquals(emptyList<AutofillId>(), parse(field).allIds)
        }
    }

    @Test
    fun htmlPasswordWithoutAndroidInputTypeIsRecognized() {
        val password = node(html = mapOf("type" to "password"))
        assertEquals(listOf(password.autofillId), parse(password).passwordIds)
    }

    @Test
    fun htmlUsernameAutocompleteSupportsUsernameFirstForm() {
        val username = node(html = mapOf("type" to "text", "autocomplete" to "section-login username"))
        assertEquals(listOf(username.autofillId), parse(username).usernameIds)
    }

    @Test
    fun htmlUsernameNameWithoutAutocompleteIsRecognized() {
        val username = node(html = mapOf("type" to "text", "name" to "username"))
        assertEquals(listOf(username.autofillId), parse(username).usernameIds)
    }

    @Test
    fun htmlNewPasswordNeverBecomesExistingPasswordTarget() {
        val password = node(html = mapOf("type" to "password", "autocomplete" to "new-password"))
        val fields = parse(password)
        assertEquals(listOf(password.autofillId), fields.newPasswordIds)
        assertEquals(emptyList<AutofillId>(), fields.passwordIds)
    }

    @Test
    fun nativeUsernameResourceIdentifierRecognizesOrdinaryTextInput() {
        val username = node(inputType = InputType.TYPE_CLASS_TEXT, idEntry = "username")
        val password = node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD)
        assertEquals(listOf(username.autofillId), parse(username, password).usernameIds)
    }

    @Test
    fun nativeHintedLoginStillRecognizesBothTargets() {
        val username = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        val password = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        val fields = parse(username, password)
        assertEquals(listOf(username.autofillId), fields.usernameIds)
        assertEquals(listOf(password.autofillId), fields.passwordIds)
    }

    @Test
    fun unrelatedTextAndOtpFieldsAreNotCredentialTargets() {
        val search = node(inputType = InputType.TYPE_CLASS_TEXT, idEntry = "search")
        val otp = node(html = mapOf("type" to "text", "autocomplete" to "one-time-code"))
        assertEquals(emptyList<AutofillId>(), parse(search, otp).allIds)
    }

    @Test
    fun maskedOtpIsNotFilledWithAccountPassword() {
        val otp = node(
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
            html = mapOf("type" to "password", "autocomplete" to "one-time-code"),
        )
        assertEquals(emptyList<AutofillId>(), parse(otp).allIds)
    }

    @Test
    fun emptyWebViewContainerDomainDoesNotMakeRealHostAmbiguous() {
        val container = node()
        `when`(container.webDomain).thenReturn("")
        val webInput = node(html = mapOf("type" to "password"))
        `when`(webInput.webDomain).thenReturn("fixture.invalid")
        assertEquals(setOf("fixture.invalid"),
            PalladinAutofillService.CredentialFieldIds.domainsFrom(structure(container, webInput)))
    }

    @Test
    fun malformedNonemptyDomainIsRetainedForOriginRejection() {
        val malformed = node()
        `when`(malformed.webDomain).thenReturn(" ")
        val valid = node()
        `when`(valid.webDomain).thenReturn("fixture.invalid")
        assertEquals(setOf(" ", "fixture.invalid"),
            PalladinAutofillService.CredentialFieldIds.domainsFrom(structure(malformed, valid)))
    }

    @Test
    fun emptyOnlyDomainIsAbsentButStillCannotAuthorizeBrowser() {
        val container = node()
        `when`(container.webDomain).thenReturn("")
        val domains = PalladinAutofillService.CredentialFieldIds.domainsFrom(structure(container))
        assertEquals(emptySet<String>(), domains)
        assertNull(AutofillOriginPolicy.resolve(domains, { it }, { true }, { emptySet() }, true))
        assertEquals(AutofillOriginMode.MANUAL_NATIVE,
            AutofillOriginPolicy.resolve(domains, { it }, { true }, { emptySet() }, false)?.mode)
    }

    @Test
    fun twoRealDomainsRemainAmbiguous() {
        val first = node()
        `when`(first.webDomain).thenReturn("first.invalid")
        val second = node()
        `when`(second.webDomain).thenReturn("second.invalid")
        val domains = PalladinAutofillService.CredentialFieldIds.domainsFrom(structure(first, second))
        assertEquals(setOf("first.invalid", "second.invalid"), domains)
        assertNull(AutofillOriginPolicy.resolve(domains, { it }, { true }, { emptySet() }, false, setOf("https")))
    }

    @Test
    fun disabledAndInvisibleNativeFieldsAreNotTargets() {
        val disabled = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        `when`(disabled.isEnabled).thenReturn(false)
        val hidden = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        `when`(hidden.visibility).thenReturn(View.INVISIBLE)
        assertEquals(emptyList<AutofillId>(), parse(disabled, hidden).allIds)
    }

    @Test
    fun invisibleAncestorCannotContributeVisibleChildTargets() {
        val parent = node()
        `when`(parent.visibility).thenReturn(View.GONE)
        val password = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        `when`(parent.childCount).thenReturn(1)
        `when`(parent.getChildAt(0)).thenReturn(password)
        assertEquals(emptyList<AutofillId>(), parse(parent).allIds)
    }

    @Test
    fun nonTextControlsAndHintedContainersCannotReceiveCredentialValues() {
        val container = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        `when`(container.autofillType).thenReturn(View.AUTOFILL_TYPE_NONE)
        val username = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        `when`(container.childCount).thenReturn(1)
        `when`(container.getChildAt(0)).thenReturn(username)
        val toggle = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        `when`(toggle.autofillType).thenReturn(View.AUTOFILL_TYPE_TOGGLE)
        assertEquals(listOf(username.autofillId), parse(container, toggle).allIds)
    }

    @Test
    fun htmlHiddenDisabledAndReadonlyOverrideCredentialHints() {
        for (attributes in listOf(
            mapOf("type" to "hidden"), mapOf("type" to "checkbox"),
            mapOf("disabled" to ""), mapOf("readonly" to ""),
        )) {
            val field = node(html = attributes + ("autocomplete" to "username"))
            assertEquals(attributes.toString(), emptyList<AutofillId>(), parse(field).allIds)
        }
    }

    @Test
    fun explicitSearchSemanticsOverrideUsernameHints() {
        val webSearch = node(html = mapOf("type" to "search", "autocomplete" to "username"))
        val nativeSearch = node(
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_FILTER,
            hints = arrayOf(View.AUTOFILL_HINT_USERNAME),
        )
        assertEquals(emptyList<AutofillId>(), parse(webSearch, nativeSearch).allIds)
    }

    @Test
    fun passwordConfirmationCannotReceiveSavedPassword() {
        val native = node(
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
            idEntry = "confirm_password",
        )
        val web = node(html = mapOf("type" to "password", "name" to "password_confirmation"))
        assertEquals(emptyList<AutofillId>(), parse(native, web).allIds)
    }

    @Test
    fun explicitlyNewPasswordConfirmationIsGenerationOnly() {
        val confirmation = node(html = mapOf(
            "type" to "password", "name" to "confirm_password", "autocomplete" to "new-password",
        ))
        val fields = parse(confirmation)
        assertEquals(listOf(confirmation.autofillId), fields.newPasswordIds)
        assertEquals(emptyList<AutofillId>(), fields.passwordIds)
    }

    @Test
    fun schemeCollectionIgnoresOnlyEmptySentinelAndRetainsConflicts() {
        val empty = node()
        `when`(empty.webScheme).thenReturn("")
        val secure = node()
        `when`(secure.webScheme).thenReturn("https")
        val insecure = node()
        `when`(insecure.webScheme).thenReturn("http")
        val malformed = node()
        `when`(malformed.webScheme).thenReturn(" ")
        assertEquals(setOf("https", "http", " "),
            PalladinAutofillService.CredentialFieldIds.schemesFrom(structure(empty, secure, insecure, malformed)))
    }

    @Test
    fun confirmationHintsCannotReceiveSavedPassword() {
        val native = node(
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
            hints = arrayOf("confirmPassword"),
        )
        val web = node(html = mapOf("type" to "password", "autocomplete" to "confirm-password"))
        assertEquals(emptyList<AutofillId>(), parse(native, web).allIds)
    }

    @Test
    fun maskedEmailOtpCannotReceiveSavedPassword() {
        val otp = node(
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
            hints = arrayOf("emailOTPCode"),
        )
        assertEquals(emptyList<AutofillId>(), parse(otp).allIds)
    }

    @Test
    fun disabledContainerStillTraversesIndependentlyEnabledChild() {
        val container = node()
        `when`(container.isEnabled).thenReturn(false)
        `when`(container.autofillType).thenReturn(View.AUTOFILL_TYPE_NONE)
        val username = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        `when`(container.childCount).thenReturn(1)
        `when`(container.getChildAt(0)).thenReturn(username)
        assertEquals(listOf(username.autofillId), parse(container).usernameIds)
    }

    @Test
    fun unrelatedHttpsNodeCannotAuthorizeDomainWithMissingScheme() {
        for (missingScheme in listOf(null, "")) {
            val webInput = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
            `when`(webInput.webDomain).thenReturn("fixture.invalid")
            `when`(webInput.webScheme).thenReturn(missingScheme)
            val unrelated = node()
            `when`(unrelated.webScheme).thenReturn("https")
            val request = structure(webInput, unrelated)
            assertNull(AutofillOriginPolicy.resolve(
                PalladinAutofillService.CredentialFieldIds.domainsFrom(request),
                { it }, { true }, { emptySet() }, false,
                PalladinAutofillService.CredentialFieldIds.schemesFrom(request),
            ))
        }
    }

    @Test
    fun secureDomainNodeAcceptsEmptyWebViewContainerSentinel() {
        val webInput = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        `when`(webInput.webDomain).thenReturn("fixture.invalid")
        `when`(webInput.webScheme).thenReturn("https")
        val container = node()
        `when`(container.webDomain).thenReturn("")
        `when`(container.webScheme).thenReturn("")
        val request = structure(container, webInput)
        assertEquals(AutofillOriginMode.WEB, AutofillOriginPolicy.resolve(
            PalladinAutofillService.CredentialFieldIds.domainsFrom(request),
            { it }, { true }, { emptySet() }, false,
            PalladinAutofillService.CredentialFieldIds.schemesFrom(request),
        )?.mode)
    }

    @Test
    fun mixedFormIncludesOnlyEligibleCredentialTargets() {
        val username = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        val password = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        val hidden = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        `when`(hidden.visibility).thenReturn(View.GONE)
        val disabled = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        `when`(disabled.isEnabled).thenReturn(false)
        val otp = node(
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
            hints = arrayOf("emailOTPCode"),
        )
        val confirmation = node(
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
            idEntry = "confirm_password",
        )
        val container = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        `when`(container.autofillType).thenReturn(View.AUTOFILL_TYPE_NONE)
        val childUsername = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        `when`(container.childCount).thenReturn(1)
        `when`(container.getChildAt(0)).thenReturn(childUsername)

        val fields = parse(username, password, hidden, disabled, otp, confirmation, container)

        assertEquals(listOf(username.autofillId, childUsername.autofillId), fields.usernameIds)
        assertEquals(listOf(password.autofillId), fields.passwordIds)
        assertEquals(listOf(username.autofillId, childUsername.autofillId, password.autofillId), fields.allIds)
        assertEquals(emptyList<AutofillId>(), fields.newPasswordIds)
    }

    @Test fun saveReadsOnlyAutofillValuesAndRejectsAmbiguity() {
        val username = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        val password = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        val usernameValue = mock(android.view.autofill.AutofillValue::class.java)
        val passwordValue = mock(android.view.autofill.AutofillValue::class.java)
        `when`(usernameValue.isText).thenReturn(true)
        `when`(usernameValue.textValue).thenReturn("synthetic-user")
        `when`(passwordValue.isText).thenReturn(true)
        `when`(passwordValue.textValue).thenReturn("synthetic-password")
        `when`(username.autofillValue).thenReturn(usernameValue)
        `when`(password.autofillValue).thenReturn(passwordValue)
        `when`(password.text).thenReturn("wrong-display-text")
        val request = structure(username, password)
        val fields = AutofillSaveFields.from(request)!!
        assertEquals("synthetic-password", String(fields.read(request)!!.password))
        `when`(password.autofillValue).thenReturn(null)
        assertNull(fields.read(request))
        assertNull(AutofillSaveFields.from(structure(username, password,
            node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD)))))
        assertNull(AutofillSaveFields.from(structure(username,
            node(hints = arrayOf("emailOTPCode")))))
        assertNull(AutofillSaveFields.from(structure(username,
            node(hints = arrayOf("confirmPassword")))))
    }

    @Test fun saveRejectsSiblingOriginAndConfirmationOnlyPassword() {
        val username = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        val password = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        val sibling = node()
        `when`(sibling.webDomain).thenReturn("login.example.com")
        `when`(sibling.webScheme).thenReturn("https")
        val source = AutofillSaveSource("package", setOf("signature"), AutofillOriginMode.WEB,
            setOf("login.example.com"), setOf("https"))
        val request = structure(username, password, sibling)
        assertEquals(false, AutofillSaveFields.from(request)!!.isBoundTo(request, source))
        `when`(username.webDomain).thenReturn("login.example.com")
        `when`(username.webScheme).thenReturn("https")
        `when`(password.webDomain).thenReturn("login.example.com")
        `when`(password.webScheme).thenReturn("https")
        assertEquals(true, AutofillSaveFields.from(request)!!.isBoundTo(request, source))
        val confirmation = node(html = mapOf("type" to "password", "name" to "confirm_password",
            "autocomplete" to "new-password"))
        assertNull(AutofillSaveFields.from(structure(username, confirmation)))
    }

    @Test fun saveRejectsAdditionalEligibleConfirmationFields() {
        val username = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        val password = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        val confirmations = listOf(
            node(inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD,
                idEntry = "confirm_password"),
            node(hints = arrayOf("passwordConfirmation")),
            node(html = mapOf("type" to "password", "name" to "confirm_password")),
            node(html = mapOf("type" to "password", "autocomplete" to "confirm-password")),
            node(html = mapOf("type" to "password", "name" to "confirm_password",
                "autocomplete" to "new-password")),
        )
        for (confirmation in confirmations) {
            assertNull(AutofillSaveFields.from(structure(username, password, confirmation)))
        }
    }

    @Test fun saveIgnoresConfirmationNodesThatCannotBeCredentialTargets() {
        val username = node(hints = arrayOf(View.AUTOFILL_HINT_USERNAME))
        val password = node(hints = arrayOf(View.AUTOFILL_HINT_PASSWORD))
        val hidden = node(hints = arrayOf("confirmPassword"))
        `when`(hidden.visibility).thenReturn(View.GONE)
        val disabled = node(hints = arrayOf("confirmPassword"))
        `when`(disabled.isEnabled).thenReturn(false)
        val readonly = node(html = mapOf("type" to "password", "name" to "confirm_password", "readonly" to ""))
        val otp = node(hints = arrayOf("confirmPassword", "emailOTPCode"))
        val hiddenContainer = node()
        `when`(hiddenContainer.visibility).thenReturn(View.INVISIBLE)
        `when`(hiddenContainer.childCount).thenReturn(1)
        val hiddenChild = node(hints = arrayOf("confirmPassword"))
        `when`(hiddenContainer.getChildAt(0)).thenReturn(hiddenChild)
        for (excluded in listOf(hidden, disabled, readonly, otp, hiddenContainer)) {
            assertEquals(AutofillSaveFields(username.autofillId!!, password.autofillId!!),
                AutofillSaveFields.from(structure(username, password, excluded)))
        }
    }

    private fun parse(vararg nodes: AssistStructure.ViewNode): PalladinAutofillService.CredentialFieldIds =
        PalladinAutofillService.CredentialFieldIds.from(structure(*nodes))

    private fun structure(vararg nodes: AssistStructure.ViewNode): AssistStructure {
        val root = node()
        `when`(root.childCount).thenReturn(nodes.size)
        nodes.forEachIndexed { index, child -> `when`(root.getChildAt(index)).thenReturn(child) }
        val window = mock(AssistStructure.WindowNode::class.java)
        `when`(window.rootViewNode).thenReturn(root)
        val structure = mock(AssistStructure::class.java)
        `when`(structure.windowNodeCount).thenReturn(1)
        `when`(structure.getWindowNodeAt(0)).thenReturn(window)
        return structure
    }

    private fun node(
        inputType: Int = 0,
        idEntry: String? = null,
        hints: Array<String> = emptyArray(),
        html: Map<String, String>? = null,
    ): AssistStructure.ViewNode {
        val node = mock(AssistStructure.ViewNode::class.java)
        `when`(node.autofillId).thenReturn(mock(AutofillId::class.java))
        `when`(node.inputType).thenReturn(inputType)
        `when`(node.idEntry).thenReturn(idEntry)
        `when`(node.autofillHints).thenReturn(hints)
        `when`(node.autofillType).thenReturn(View.AUTOFILL_TYPE_TEXT)
        `when`(node.isEnabled).thenReturn(true)
        `when`(node.isFocusable).thenReturn(true)
        `when`(node.visibility).thenReturn(View.VISIBLE)
        if (html != null) {
            val info = mock(ViewStructure.HtmlInfo::class.java)
            `when`(info.tag).thenReturn("input")
            val attributes = html.map { (name, value) ->
                // SDK android.jar constructors throw on the JVM; only framework inputs are mocked.
                @Suppress("UNCHECKED_CAST")
                val pair = mock(Pair::class.java) as Pair<String, String>
                Pair::class.java.getField("first").apply { isAccessible = true }.set(pair, name)
                Pair::class.java.getField("second").apply { isAccessible = true }.set(pair, value)
                pair
            }
            `when`(info.attributes).thenReturn(attributes)
            `when`(node.htmlInfo).thenReturn(info)
        }
        return node
    }
}
