package io.palladin.mobile.autofill

import android.app.assist.AssistStructure
import android.text.InputType
import android.util.Pair
import android.view.View
import android.view.ViewStructure
import android.view.autofill.AutofillId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`

class CredentialFieldIdsTest {
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
        assertNull(AutofillOriginPolicy.resolve(domains, { it }, { true }, { emptySet() }, false))
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
