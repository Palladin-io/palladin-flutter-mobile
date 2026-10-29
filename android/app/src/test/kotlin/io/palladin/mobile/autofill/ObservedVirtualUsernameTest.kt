package io.palladin.mobile.autofill

import android.app.assist.AssistStructure
import android.view.View
import android.view.autofill.AutofillId
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`

/** Sanitized physical evidence: tool/android-autofill-harness/observed-binance.md. */
class ObservedVirtualUsernameTest {
    @Test fun observedVirtualUsernameIsRecognizedWithoutNativeInputTypeOrClass() {
        val (structure, field) = observed()
        val fields = PalladinAutofillService.CredentialFieldIds.from(structure)
        assertEquals(listOf(field.autofillId), fields.usernameIds)
        assertTrue(fields.passwordIds.isEmpty())
        assertFalse(fields.requiresUsernameConfirmation)
        assertEquals(HOST, credentialAssociationHost(fields, setOf(HOST), setOf("https")))
        assertEquals(setOf(HOST), PalladinAutofillService.CredentialFieldIds.domainsFrom(structure))
        assertEquals(setOf("https"), PalladinAutofillService.CredentialFieldIds.schemesFrom(structure))
    }

    @Test fun associationUsesTheSameCanonicalOriginAsFinalHandoff() {
        val fields = PalladinAutofillService.CredentialFieldIds.from(observed().first)
        assertEquals(HOST, credentialAssociationHost(fields, setOf(HOST.uppercase(), "$HOST."), setOf("HTTPS", "https")))
        for (domains in listOf(setOf(HOST, "accounts.binance.com"), setOf(HOST, "https://bad/path"))) {
            assertNull(credentialAssociationHost(fields, domains, setOf("https")))
        }
        assertNull(credentialAssociationHost(fields, setOf(HOST), setOf("HTTPS", "http")))
        assertNull(credentialAssociationHost(fields, setOf(HOST), emptySet()))
    }

    @Test fun exactCredentialStatementComplementsMissingOsAppLink() {
        val (structure) = observed()
        val signer = List(32) { "AB" }.joinToString(":")
        val key = CredentialAssociationKey(HOST, "com.binance.dev", setOf(signer))
        val statement = """[{"relation":["delegate_permission/common.get_login_creds"],"target":{"namespace":"android_app","package_name":"${key.packageName}","sha256_cert_fingerprints":["$signer"]}}]"""
        val proofs = CredentialAssociationProofs { 100L }
        assertTrue(CredentialAssetLinks.authorizes(statement, key.packageName, key.signers))
        proofs.accept(key)
        val origin = AutofillOriginPolicy.resolve(
            PalladinAutofillService.CredentialFieldIds.domainsFrom(structure),
            AutoFillCacheStore::normalizeDomain, { proofs.contains(key.copy(host = it)) },
            { fail("No sibling association fallback"); emptySet() }, false,
            PalladinAutofillService.CredentialFieldIds.schemesFrom(structure),
        )
        assertEquals(setOf(HOST), origin?.domains)
    }

    @Test fun reportedHostRequiresItsOwnAuthorityDespiteVerifiedSiblingHosts() {
        val (structure) = observed()
        val siblings = setOf("accounts.binance.com", "app.binance.com", "app.binance.info")
        assertNull(resolve(structure, emptySet()))
        assertNull(resolve(structure, siblings))
        val exact = resolve(structure, siblings + HOST)
        assertEquals(AutofillOriginMode.WEB, exact?.mode)
        assertEquals(setOf(HOST), exact?.domains)
        assertFalse(exact!!.requiresSelection)
    }

    @Test fun exactAuthorityDoesNotAuthorizeCleartextOrMissingScheme() {
        for (scheme in listOf("http", "", "https,http")) {
            val (structure) = observed(scheme = scheme)
            assertNull(resolve(structure, setOf(HOST)))
            assertNull(credentialAssociationHost(PalladinAutofillService.CredentialFieldIds.from(structure),
                setOf(HOST), setOf(scheme)))
        }
    }

    @Test fun virtualOtpSearchConfirmationAndExcludedTargetsAreNotUsernames() {
        for (hint in listOf("smsOTPCode", "search", "confirmPassword", "newPassword", "")) {
            val (structure) = observed(hint = hint)
            val fields = PalladinAutofillService.CredentialFieldIds.from(structure, manualRequest = true)
            assertTrue(hint, fields.usernameIds.isEmpty())
            assertTrue(hint, fields.passwordIds.isEmpty())
            assertNull(credentialAssociationHost(fields, setOf(HOST), setOf("https")))
        }
        for (exclude in listOf<(AssistStructure.ViewNode) -> Unit>(
            { `when`(it.visibility).thenReturn(View.GONE) },
            { `when`(it.isEnabled).thenReturn(false) },
            { `when`(it.autofillType).thenReturn(View.AUTOFILL_TYPE_NONE) },
        )) {
            val (structure, field) = observed()
            exclude(field)
            assertTrue(PalladinAutofillService.CredentialFieldIds.from(structure, manualRequest = true).allIds.isEmpty())
        }
    }

    private fun resolve(structure: AssistStructure, verified: Set<String>) = AutofillOriginPolicy.resolve(
        PalladinAutofillService.CredentialFieldIds.domainsFrom(structure),
        AutoFillCacheStore::normalizeDomain,
        { it in verified },
        { fail("A reported web domain must never fall back to native associations"); emptySet() },
        false,
        PalladinAutofillService.CredentialFieldIds.schemesFrom(structure),
    )

    private fun observed(hint: String = "username", scheme: String = "https"): Pair<AssistStructure, AssistStructure.ViewNode> {
        val field = mock(AssistStructure.ViewNode::class.java)
        `when`(field.autofillId).thenReturn(mock(AutofillId::class.java))
        `when`(field.inputType).thenReturn(0)
        `when`(field.autofillType).thenReturn(View.AUTOFILL_TYPE_TEXT)
        `when`(field.autofillHints).thenReturn(arrayOf(hint))
        `when`(field.isEnabled).thenReturn(true)
        `when`(field.isFocused).thenReturn(true)
        `when`(field.visibility).thenReturn(View.VISIBLE)
        `when`(field.webDomain).thenReturn(HOST)
        `when`(field.webScheme).thenReturn(scheme)
        // The probe classified this node as OTHER; the actual class was not captured.
        // No guessed EditText, HTML attributes, idEntry, label or focusable metadata.
        val webView = mock(AssistStructure.ViewNode::class.java)
        `when`(webView.className).thenReturn("android.webkit.WebView")
        `when`(webView.isEnabled).thenReturn(true)
        `when`(webView.isFocused).thenReturn(true)
        `when`(webView.childCount).thenReturn(1)
        `when`(webView.getChildAt(0)).thenReturn(field)
        val window = mock(AssistStructure.WindowNode::class.java)
        `when`(window.rootViewNode).thenReturn(webView)
        val structure = mock(AssistStructure::class.java)
        `when`(structure.windowNodeCount).thenReturn(1)
        `when`(structure.getWindowNodeAt(0)).thenReturn(window)
        return structure to field
    }

    private companion object { const val HOST = "www.binance.com" }
}
