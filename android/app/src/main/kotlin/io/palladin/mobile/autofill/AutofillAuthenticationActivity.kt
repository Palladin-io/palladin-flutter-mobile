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
import javax.crypto.Cipher

class AutofillAuthenticationActivity : FragmentActivity() {
    private lateinit var cacheStore: AutoFillCacheStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        cacheStore = AutoFillCacheStore(this)

        val domain = AutoFillCacheStore.normalizeDomain(
            intent.getStringExtra(EXTRA_DOMAIN),
        )
        if (domain == null || !cacheStore.hasCache()) {
            finishCanceled()
            return
        }

        val cipher = runCatching(cacheStore::createUnwrapCipher).getOrElse {
            cacheStore.clear()
            finishCanceled()
            return
        }
        showBiometricPrompt(cipher, domain)
    }

    private fun showBiometricPrompt(cipher: Cipher, domain: String) {
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
                    completeFill(authenticatedCipher, domain)
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
        prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(cipher))
    }

    private fun completeFill(cipher: Cipher, domain: String) {
        val records = runCatching { cacheStore.decrypt(cipher) }.getOrElse {
            cacheStore.clear()
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
            setResult(Activity.RESULT_OK, result)
            finish()
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
        const val EXTRA_USERNAME_IDS = "palladin.autofill.username_ids"
        const val EXTRA_PASSWORD_IDS = "palladin.autofill.password_ids"
    }
}
