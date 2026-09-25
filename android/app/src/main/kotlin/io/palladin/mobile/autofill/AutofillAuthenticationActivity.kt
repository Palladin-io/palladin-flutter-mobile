package io.palladin.mobile.autofill

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.service.autofill.Dataset
import android.service.autofill.FillResponse
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.palladin.mobile.R

class AutofillAuthenticationActivity : FragmentActivity() {
    private lateinit var cacheStore: AutoFillCacheStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cacheStore = AutoFillCacheStore(this)

        val domain = AutoFillCacheStore.normalizeDomain(
            intent.getStringExtra(EXTRA_DOMAIN),
        )
        val packageName = intent.getStringExtra(EXTRA_PACKAGE_NAME)
            ?.takeIf(String::isNotBlank)
        val originVerified = domain != null &&
            packageName != null &&
            AutofillOriginVerifier(this).isVerified(packageName, domain)
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
        if (ids.isEmpty() || !AutofillOriginVerifier(this).isVerified(requestingPackage, domain)) {
            finishCanceled()
            return
        }
        val password = StrongPasswordGenerator.generate()
        val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_1).apply {
            setTextViewText(android.R.id.text1, getString(R.string.autofill_generate_label))
        }
        val dataset = Dataset.Builder(presentation)
        ids.forEach { dataset.setValue(it, AutofillValue.forText(password), presentation) }
        val response = FillResponse.Builder().addDataset(dataset.build()).build()
        val handedOff = runCatching {
            history.appendAuthenticated(
                operation,
                authenticatedCipher,
                domain,
                password,
                handoff = {
                    require(AutofillOriginVerifier(this).isVerified(requestingPackage, domain))
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
        domain: String,
        requestingPackage: String,
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
                    completeFill(
                        AutoFillUnwrapOperation(operation.generation, authenticatedCipher),
                        domain,
                        requestingPackage,
                    )
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    finishCanceled()
                }
            },
        )
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(getString(R.string.autofill_biometric_title))
            .setSubtitle(getString(R.string.autofill_biometric_subtitle, domain))
            .setNegativeButtonText(getString(R.string.autofill_cancel))
            .setAllowedAuthenticators(androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()
        prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(operation.cipher))
    }

    private fun completeFill(
        operation: AutoFillUnwrapOperation,
        domain: String,
        requestingPackage: String,
    ) {
        if (!AutofillOriginVerifier(this).isVerified(requestingPackage, domain)) {
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
            if (passwordIds.isEmpty()) {
                finishCanceled()
                return
            }

            val response = FillResponse.Builder()
            for (record in matches) {
                val presentation = RemoteViews(packageName, android.R.layout.simple_list_item_1).apply {
                    setTextViewText(android.R.id.text1, "${record.label} - ${record.username}")
                }
                val dataset = Dataset.Builder(presentation)
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
                cacheStore.withRevalidatedGeneration(operation.generation) {
                    require(
                        AutofillOriginVerifier(this)
                            .isVerified(requestingPackage, domain),
                    )
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

    private fun finishCanceled() {
        setResult(Activity.RESULT_CANCELED)
        finish()
    }

    companion object {
        const val EXTRA_DOMAIN = "palladin.autofill.domain"
        const val EXTRA_PACKAGE_NAME = "palladin.autofill.package_name"
        const val EXTRA_USERNAME_IDS = "palladin.autofill.username_ids"
        const val EXTRA_PASSWORD_IDS = "palladin.autofill.password_ids"
        const val EXTRA_NEW_PASSWORD_IDS = "palladin.autofill.new_password_ids"
        const val EXTRA_GENERATE = "palladin.autofill.generate"
    }
}
