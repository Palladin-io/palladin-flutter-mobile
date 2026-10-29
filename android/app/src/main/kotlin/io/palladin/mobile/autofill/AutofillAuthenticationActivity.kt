package io.palladin.mobile.autofill

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.service.autofill.Dataset
import android.service.autofill.FillResponse
import android.view.View
import android.view.ViewGroup
import android.widget.ArrayAdapter
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.SearchView
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.palladin.mobile.R

class AutofillAuthenticationActivity : FragmentActivity() {
    private lateinit var cacheStore: AutoFillCacheStore
    private var nativeRecords: MutableList<CachedCredential>? = null
    private var nativeDialog: AlertDialog? = null
    private var manualSelection: ManualAutofillSelection? = null
    private val requiresUsernameConfirmation: Boolean
        get() = intent.getBooleanExtra(EXTRA_USERNAME_CONFIRMATION, false)

    override fun onDestroy() {
        clearNativeSelection()
        super.onDestroy()
    }

    override fun onStop() {
        if (nativeRecords != null) finishCanceled()
        super.onStop()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        cacheStore = AutoFillCacheStore(this)

        val domain = AutoFillCacheStore.normalizeDomain(
            intent.getStringExtra(EXTRA_DOMAIN),
        )
        val packageName = intent.getStringExtra(EXTRA_PACKAGE_NAME)
            ?.takeIf(String::isNotBlank)
        val nativeDomains = intent.getStringArrayListExtra(EXTRA_NATIVE_DOMAINS).orEmpty()
        val mode = runCatching {
            AutofillOriginMode.valueOf(intent.getStringExtra(EXTRA_ORIGIN_MODE).orEmpty())
        }.getOrDefault(AutofillOriginMode.WEB)
        if (requiresUsernameConfirmation && !validUsernameOnlyTargets(mode,
                intent.autofillIds(EXTRA_USERNAME_IDS), intent.autofillIds(EXTRA_PASSWORD_IDS),
                intent.autofillIds(EXTRA_NEW_PASSWORD_IDS))) {
            finishCanceled()
            return
        }
        if (mode != AutofillOriginMode.WEB) {
            if (intent.getStringExtra(EXTRA_DOMAIN) != null ||
                intent.getStringExtra(EXTRA_WEB_SCHEME) != null || packageName == null ||
                intent.getBooleanExtra(EXTRA_GENERATE, false) ||
                nativeDomains.any { AutoFillCacheStore.normalizeDomain(it) != it } ||
                (mode == AutofillOriginMode.VERIFIED_NATIVE &&
                    !nativeOriginStillVerified(packageName, nativeDomains.toSet())) ||
                (mode == AutofillOriginMode.MANUAL_NATIVE &&
                    (nativeDomains.isNotEmpty() || AutofillOriginVerifier(this).isBrowser(packageName))) ||
                !cacheStore.hasCache()
            ) {
                finishCanceled()
                return
            }
            val operation = runCatching(cacheStore::createUnwrapOperation).getOrElse {
                cacheStore.clear()
                finishCanceled()
                return
            }
            showBiometricPrompt(operation, null, packageName, nativeDomains.toSet(), mode)
            return
        }
        val originVerified = domain != null &&
            packageName != null &&
            webOriginStillVerified(packageName, domain)
        if (domain == null || !originVerified) {
            finishCanceled()
            return
        }

        if (intent.getBooleanExtra(EXTRA_GENERATE, false)) {
            val history = GeneratedPasswordHistory(this)
            if (!history.hasActiveSession() || intent.autofillIds(EXTRA_NEW_PASSWORD_IDS).isEmpty()) {
                finishCanceled()
                return
            }
            val historyOperation = runCatching { history.createUnwrapOperation() }.getOrElse {
                finishCanceled()
                return
            }
            showGenerationPrompt(history, historyOperation, domain, packageName)
            return
        }
        if (!cacheStore.hasCache()) {
            finishCanceled()
            return
        }

        val operation = runCatching(cacheStore::createUnwrapOperation).getOrElse {
            cacheStore.clear()
            finishCanceled()
            return
        }
        showBiometricPrompt(operation, domain, packageName)
    }

    private fun showGenerationPrompt(
        history: GeneratedPasswordHistory,
        operation: GeneratedHistoryUnwrapOperation,
        domain: String,
        requestingPackage: String,
    ) {
        val prompt = BiometricPrompt(
            this,
            ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    val cipher = result.cryptoObject?.cipher
                    if (cipher == null) {
                        finishCanceled()
                        return
                    }
                    completeGeneration(history, operation, cipher, domain, requestingPackage)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    finishCanceled()
                }
            },
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(getString(R.string.autofill_generate_title))
            .setSubtitle(getString(R.string.autofill_generate_subtitle, domain))
            .setNegativeButtonText(getString(R.string.autofill_cancel))
            .setAllowedAuthenticators(androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(operation.cipher))
    }

    private fun completeGeneration(
        history: GeneratedPasswordHistory,
        operation: GeneratedHistoryUnwrapOperation,
        authenticatedCipher: javax.crypto.Cipher,
        domain: String,
        requestingPackage: String,
    ) {
        val ids = intent.autofillIds(EXTRA_NEW_PASSWORD_IDS)
        if (ids.isEmpty() || !webOriginStillVerified(requestingPackage, domain)) {
            finishCanceled()
            return
        }
        val password = StrongPasswordGenerator.generate()
        val presentation = autofillPresentation(this, getString(R.string.autofill_generate_label))
        val dataset = Dataset.Builder(presentation)
        ids.forEach { dataset.setValue(it, AutofillValue.forText(password), presentation) }
        val response = AutofillSaveCoordinator.response(FillResponse.Builder(), intent.getStringExtra(AutofillSaveCoordinator.EXTRA_REQUEST)).addDataset(dataset.build()).build()
        val handedOff = runCatching {
            history.appendAuthenticated(
                operation,
                authenticatedCipher,
                domain,
                password,
                handoff = {
                    require(webOriginStillVerified(requestingPackage, domain))
                    setResult(
                        Activity.RESULT_OK,
                        Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, response),
                    )
                    finish()
                },
            )
        }.isSuccess
        if (!handedOff) finishCanceled()
    }

    private fun showBiometricPrompt(
        operation: AutoFillUnwrapOperation,
        domain: String?,
        requestingPackage: String,
        nativeDomains: Set<String> = emptySet(),
        mode: AutofillOriginMode = AutofillOriginMode.WEB,
    ) {
        val prompt = BiometricPrompt(
            this,
            ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult,
                ) {
                    val authenticatedCipher = result.cryptoObject?.cipher
                    if (authenticatedCipher == null) {
                        finishCanceled()
                        return
                    }
                    val authenticated = AutoFillUnwrapOperation(operation.generation, authenticatedCipher)
                    if (domain == null) {
                        showNativeCredentialChooser(authenticated, requestingPackage, nativeDomains, mode)
                    } else {
                        completeFill(authenticated, domain, requestingPackage)
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    finishCanceled()
                }
            },
        )
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(getString(R.string.autofill_biometric_title))
            .setSubtitle(
                if (domain == null) getString(R.string.autofill_native_biometric_subtitle)
                else getString(R.string.autofill_biometric_subtitle, domain),
            )
            .setNegativeButtonText(getString(R.string.autofill_cancel))
            .setAllowedAuthenticators(androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()
        prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(operation.cipher))
    }

    private fun webOriginStillVerified(requestingPackage: String, domain: String): Boolean =
        AutofillOriginPolicy.isSecureWebScheme(intent.getStringExtra(EXTRA_WEB_SCHEME)) &&
            AutofillOriginVerifier(this).isVerified(requestingPackage, domain)

    private fun nativeOriginStillVerified(requestingPackage: String, domains: Set<String>): Boolean =
        domains.isNotEmpty() && AutofillOriginVerifier(this)
            .nativeDomains(requestingPackage)?.containsAll(domains) == true

    private fun showNativeCredentialChooser(
        operation: AutoFillUnwrapOperation,
        requestingPackage: String,
        domains: Set<String>,
        mode: AutofillOriginMode,
    ) {
        val manual = mode == AutofillOriginMode.MANUAL_NATIVE
        if (isFinishing || (manual && AutofillOriginVerifier(this).isBrowser(requestingPackage)) ||
            (!manual && !nativeOriginStillVerified(requestingPackage, domains))
        ) {
            finishCanceled()
            return
        }
        val records = runCatching { cacheStore.decrypt(operation) }.getOrElse {
            cacheStore.quarantine(operation.generation)
            finishCanceled()
            return
        }
        if (requiresUsernameConfirmation) {
            for (index in records.indices) records[index] = records[index].copy(password = "")
        }
        nativeRecords = records
        manualSelection = if (manual || requiresUsernameConfirmation) ManualAutofillSelection(requestingPackage) else null
        val matches = records.flatMap { record ->
            record.domains.filter { domain ->
                AutoFillCacheStore.normalizeDomain(domain) == domain && (manual || domain in domains)
            }.map { domain -> record to domain }
        }
        if (matches.isEmpty()) {
            finishCanceled()
            return
        }
        var visible = matches
        val adapter = ArrayAdapter<String>(this, android.R.layout.simple_list_item_1)
        fun publishMatches(query: String) {
            visible = matches.filter { (record, domain) ->
                record.label.contains(query, ignoreCase = true) ||
                    record.username.contains(query, ignoreCase = true) ||
                    domain.contains(query, ignoreCase = true)
            }
            adapter.clear()
            adapter.addAll(visible.map { (record, domain) ->
                "${record.label} — $domain\n${record.username}"
            })
        }
        val search = SearchView(this).apply {
            setIconifiedByDefault(false)
            queryHint = getString(R.string.autofill_search_credentials)
            isSaveEnabled = false
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            imeOptions = android.view.inputmethod.EditorInfo.IME_ACTION_SEARCH or
                android.view.inputmethod.EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
            setOnQueryTextListener(object : SearchView.OnQueryTextListener {
                override fun onQueryTextSubmit(query: String?): Boolean = true
                override fun onQueryTextChange(newText: String?): Boolean {
                    publishMatches(newText.orEmpty())
                    return true
                }
            })
        }
        val list = ListView(this).apply {
            this.adapter = adapter
            setOnItemClickListener { _, _, position, _ ->
                val (record, domain) = visible[position]
                if (manual || requiresUsernameConfirmation) {
                    manualSelection?.select(record.id, domain)
                    nativeDialog?.dismiss()
                    showSelectionConfirmation(operation, requestingPackage, record, domain, domains, manual)
                } else {
                    completeNativeSelection(operation, requestingPackage, record, domain, domains)
                }
            }
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(search)
            addView(list, LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                minOf(resources.getDimensionPixelSize(R.dimen.autofill_picker_list_height),
                    resources.displayMetrics.heightPixels / 3),
            ))
        }
        publishMatches("")
        nativeDialog = AlertDialog.Builder(this)
            .setTitle(R.string.autofill_choose_credential)
            .setView(content)
            .setNegativeButton(R.string.autofill_cancel) { _, _ -> finishCanceled() }
            .setOnCancelListener { finishCanceled() }
            .create().also { dialog ->
                dialog.setOnDismissListener {
                    search.setOnQueryTextListener(null)
                    search.setQuery("", false)
                    adapter.clear()
                }
                dialog.show()
            }
    }

    private fun showSelectionConfirmation(
        operation: AutoFillUnwrapOperation,
        requestingPackage: String,
        record: CachedCredential,
        domain: String,
        requestDomains: Set<String>,
        manual: Boolean,
    ) {
        val message = if (requiresUsernameConfirmation) {
            getString(R.string.autofill_username_confirm_message, requestingPackage, domain) +
                if (manual) "\n\n" + getString(R.string.autofill_manual_confirm_message, requestingPackage, domain) else ""
        } else getString(R.string.autofill_manual_confirm_message, requestingPackage, domain)
        nativeDialog = AlertDialog.Builder(this)
            .setTitle(if (requiresUsernameConfirmation) R.string.autofill_username_confirm_title else R.string.autofill_manual_confirm_title)
            .setMessage(message)
            .setPositiveButton(if (requiresUsernameConfirmation) R.string.autofill_fill_username_once else R.string.autofill_fill_once) { _, _ ->
                if (manual) completeManualSelection(operation, requestingPackage, record, domain)
                else completeNativeSelection(operation, requestingPackage, record, domain, requestDomains)
            }
            .setNegativeButton(R.string.autofill_cancel) { _, _ -> finishCanceled() }
            .setOnCancelListener { finishCanceled() }
            .show()
    }

    private fun completeManualSelection(
        operation: AutoFillUnwrapOperation,
        requestingPackage: String,
        record: CachedCredential,
        domain: String,
    ) {
        if (isFinishing || nativeRecords?.any { it === record } != true) return
        if (AutofillOriginVerifier(this).isBrowser(requestingPackage) || domain !in record.domains) {
            finishCanceled()
            return
        }
        val response = selectionResponse(record, domain) ?: run {
            finishCanceled()
            return
        }
        val handedOff = runCatching {
            cacheStore.withRevalidatedCredentials(operation.generation, listOf(record)) {
                require(!AutofillOriginVerifier(this).isBrowser(requestingPackage))
                require(manualSelection?.confirm(record.id, domain, requestingPackage) == true)
                clearNativeSelection()
                setResult(Activity.RESULT_OK,
                    Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, response))
                finish()
            }
        }.isSuccess
        if (!handedOff) finishCanceled()
    }

    private fun selectionResponse(record: CachedCredential, domain: String): FillResponse? {
        val passwords = intent.autofillIds(EXTRA_PASSWORD_IDS)
        val usernames = intent.autofillIds(EXTRA_USERNAME_IDS)
        if (passwords.isEmpty() && usernames.isEmpty()) return null
        if (requiresUsernameConfirmation && !validUsernameOnlyTargets(
                runCatching { AutofillOriginMode.valueOf(intent.getStringExtra(EXTRA_ORIGIN_MODE).orEmpty()) }
                    .getOrDefault(AutofillOriginMode.WEB),
                usernames, passwords, intent.autofillIds(EXTRA_NEW_PASSWORD_IDS))) return null
        val presentation = autofillCredentialPresentation(this, record.username, record.label, domain)
        val dataset = authenticatedAutofillDataset(this, intent, presentation, record.username, record.label, domain)
        usernames.forEach {
            dataset.setValue(it, AutofillValue.forText(record.username), presentation)
        }
        passwords.forEach {
            dataset.setValue(it, AutofillValue.forText(record.password), presentation)
        }
        return AutofillSaveCoordinator.response(FillResponse.Builder(), intent.getStringExtra(AutofillSaveCoordinator.EXTRA_REQUEST)).addDataset(dataset.build()).build()
    }

    private fun completeNativeSelection(
        operation: AutoFillUnwrapOperation,
        requestingPackage: String,
        record: CachedCredential,
        domain: String,
        requestDomains: Set<String>,
    ) {
        if (isFinishing || nativeRecords?.any { it === record } != true) return
        fun stillAuthorized() = AutofillOriginPolicy.canReleaseNative(
            domain,
            record.domains,
            requestDomains,
            AutofillOriginVerifier(this).nativeDomains(requestingPackage),
        )
        if (!stillAuthorized()) {
            finishCanceled()
            return
        }
        val response = selectionResponse(record, domain) ?: run {
            finishCanceled()
            return
        }
        val handedOff = runCatching {
            cacheStore.withRevalidatedCredentials(operation.generation, listOf(record)) {
                require(stillAuthorized())
                if (requiresUsernameConfirmation) {
                    require(manualSelection?.confirm(record.id, domain, requestingPackage) == true)
                }
                clearNativeSelection()
                setResult(
                    Activity.RESULT_OK,
                    Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, response),
                )
                finish()
            }
        }.isSuccess
        if (!handedOff) finishCanceled()
    }

    private fun completeFill(
        operation: AutoFillUnwrapOperation,
        domain: String,
        requestingPackage: String,
    ) {
        if (requiresUsernameConfirmation || !webOriginStillVerified(requestingPackage, domain)) {
            cacheStore.quarantine(operation.generation)
            finishCanceled()
            return
        }
        val records = runCatching { cacheStore.decrypt(operation) }.getOrElse {
            cacheStore.quarantine(operation.generation)
            finishCanceled()
            return
        }
        try {
            val matches = records.filter { record ->
                record.domains.any { stored -> AutoFillCacheStore.domainMatches(domain, stored) }
            }
            if (matches.isEmpty()) {
                finishCanceled()
                return
            }

            val usernameIds = intent.autofillIds(EXTRA_USERNAME_IDS)
            val passwordIds = intent.autofillIds(EXTRA_PASSWORD_IDS)
            if (passwordIds.isEmpty() && usernameIds.isEmpty()) {
                finishCanceled()
                return
            }

            val response = AutofillSaveCoordinator.response(FillResponse.Builder(), intent.getStringExtra(AutofillSaveCoordinator.EXTRA_REQUEST))
            for ((index, record) in matches.withIndex()) {
                val presentation = autofillCredentialPresentation(
                    context = this,
                    username = record.username,
                    label = record.label,
                    domain = domain,
                )
                val dataset = authenticatedAutofillDataset(
                    this, intent, presentation, record.username, record.label, domain, index,
                )
                usernameIds.forEach { id ->
                    dataset.setValue(id, AutofillValue.forText(record.username), presentation)
                }
                passwordIds.forEach { id ->
                    dataset.setValue(id, AutofillValue.forText(record.password), presentation)
                }
                response.addDataset(dataset.build())
            }

            val result = Intent().putExtra(
                AutofillManager.EXTRA_AUTHENTICATION_RESULT,
                response.build(),
            )
            // The provider handoff is the security boundary. Keep the same
            // cross-thread generation lock from the final origin/fence/lease
            // checks through setResult so a committed revoke cannot race into
            // the gap after validation and still release stale plaintext.
            val handedOff = runCatching {
                cacheStore.withRevalidatedCredentials(operation.generation, matches) {
                    require(webOriginStillVerified(requestingPackage, domain))
                    setResult(Activity.RESULT_OK, result)
                    finish()
                }
            }.isSuccess
            if (!handedOff) {
                cacheStore.quarantine(operation.generation)
                finishCanceled()
                return
            }
        } finally {
            records.clear()
        }
    }

    private fun Intent.autofillIds(name: String): List<AutofillId> =
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            getParcelableArrayListExtra(name, AutofillId::class.java).orEmpty()
        } else {
            @Suppress("DEPRECATION")
            getParcelableArrayListExtra<AutofillId>(name).orEmpty()
        }

    private fun clearNativeSelection() {
        manualSelection?.cancel()
        manualSelection = null
        nativeRecords?.clear()
        nativeRecords = null
        nativeDialog?.dismiss()
        nativeDialog = null
    }

    private fun finishCanceled() {
        clearNativeSelection()
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    companion object {
        internal fun validUsernameOnlyTargets(
            mode: AutofillOriginMode,
            usernames: List<AutofillId>,
            passwords: List<AutofillId>,
            newPasswords: List<AutofillId>,
        ): Boolean = mode != AutofillOriginMode.WEB && usernames.size == 1 &&
            passwords.isEmpty() && newPasswords.isEmpty()

        const val EXTRA_ORIGIN_MODE = "palladin.autofill.origin_mode"
        const val EXTRA_NATIVE_DOMAINS = "palladin.autofill.native_domains"
        const val EXTRA_WEB_SCHEME = "palladin.autofill.web_scheme"
        const val EXTRA_DOMAIN = "palladin.autofill.domain"
        const val EXTRA_PACKAGE_NAME = "palladin.autofill.package_name"
        const val EXTRA_USERNAME_CONFIRMATION = "palladin.autofill.username_confirmation"
        const val EXTRA_USERNAME_IDS = "palladin.autofill.username_ids"
        const val EXTRA_PASSWORD_IDS = "palladin.autofill.password_ids"
        const val EXTRA_NEW_PASSWORD_IDS = "palladin.autofill.new_password_ids"
        const val EXTRA_GENERATE = "palladin.autofill.generate"
    }
}
