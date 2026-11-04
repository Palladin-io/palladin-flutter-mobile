package io.palladin.mobile.autofill

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.service.autofill.FillResponse
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import androidx.fragment.app.FragmentActivity
import java.security.MessageDigest
import java.util.Base64

/** Owns OS field IDs and the original result; Flutter receives only a RAM request. */
class SourceAutofillAuthenticationActivity : FragmentActivity() {
    private lateinit var target: String
    private lateinit var mode: AutofillOriginMode
    private var hosts = emptySet<String>()
    private var signatures = emptySet<String>()
    private var usernames = emptyList<AutofillId>()
    private var passwords = emptyList<AutofillId>()
    private var datasetAuthentication = false

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        try {
            target = requireNotNull(intent.getStringExtra(AutofillAuthenticationActivity.EXTRA_PACKAGE_NAME)).also { require(it.isNotBlank()) }
            mode = AutofillOriginMode.valueOf(requireNotNull(intent.getStringExtra(AutofillAuthenticationActivity.EXTRA_ORIGIN_MODE)))
            require(!intent.getBooleanExtra(AutofillAuthenticationActivity.EXTRA_GENERATE, false))
            usernames = ids(AutofillAuthenticationActivity.EXTRA_USERNAME_IDS)
            passwords = ids(AutofillAuthenticationActivity.EXTRA_PASSWORD_IDS)
            require(usernames.isNotEmpty() || passwords.isNotEmpty())
            require(ids(AutofillAuthenticationActivity.EXTRA_NEW_PASSWORD_IDS).isEmpty())
            val usernameOnly = intent.getBooleanExtra(AutofillAuthenticationActivity.EXTRA_USERNAME_CONFIRMATION, false)
            if (usernameOnly) require(AutofillAuthenticationActivity.validUsernameOnlyTargets(mode, usernames, passwords, emptyList()))
            val verifier = AutofillOriginVerifier(this)
            datasetAuthentication = intent.getBooleanExtra(AutofillAuthenticationActivity.EXTRA_DATASET_AUTHENTICATION, false)
            require(datasetAuthentication == AutofillOriginPolicy.usesDatasetAuthentication(Build.VERSION.SDK_INT, verifier.isBrowser(target), false))
            hosts = if (mode == AutofillOriginMode.WEB) {
                setOf(requireNotNull(AutoFillCacheStore.normalizeDomain(intent.getStringExtra(AutofillAuthenticationActivity.EXTRA_DOMAIN))))
            } else {
                require(intent.getStringExtra(AutofillAuthenticationActivity.EXTRA_DOMAIN) == null && intent.getStringExtra(AutofillAuthenticationActivity.EXTRA_WEB_SCHEME) == null)
                intent.getStringArrayListExtra(AutofillAuthenticationActivity.EXTRA_NATIVE_DOMAINS).orEmpty().toSet().also {
                    require(it.all { host -> AutoFillCacheStore.normalizeDomain(host) == host })
                }
            }
            signatures = currentSignatures()
            require(signatures.isNotEmpty())
            if (mode == AutofillOriginMode.MANUAL_NATIVE) require(hosts.isEmpty() && !verifier.isBrowser(target))
            else require(hosts.isNotEmpty() && hosts.all(::originVerified))
            AutoFillRequestBroker.open(this, mode, hosts, passwords.isEmpty())
        } catch (_: Exception) { cancel() }
    }

    internal fun originVerified(host: String): Boolean {
        if (!::target.isInitialized || !::mode.isInitialized || isFinishing || isDestroyed ||
            AutoFillCacheStore.normalizeDomain(host) != host || currentSignatures() != signatures) return false
        val verifier = AutofillOriginVerifier(this)
        return when (mode) {
            AutofillOriginMode.WEB -> host in hosts &&
                AutofillOriginPolicy.isSecureWebScheme(intent.getStringExtra(AutofillAuthenticationActivity.EXTRA_WEB_SCHEME)) &&
                verifier.credentialFillStatus(target, host) == OriginStatus.VERIFIED
            AutofillOriginMode.VERIFIED_NATIVE -> host in hosts && verifier.nativeDomains(target)?.containsAll(hosts) == true
            AutofillOriginMode.MANUAL_NATIVE -> hosts.isEmpty() && !verifier.isBrowser(target)
        }
    }

    internal fun complete(username: String, password: String, host: String) {
        val presentation = autofillCredentialPresentation(this, username, applicationInfo.loadLabel(packageManager).toString(), host)
        val dataset = authenticatedAutofillDataset(this, intent, presentation, username, applicationInfo.loadLabel(packageManager).toString(), host)
        usernames.forEach { dataset.setValue(it, AutofillValue.forText(username), presentation) }
        passwords.forEach { dataset.setValue(it, AutofillValue.forText(password), presentation) }
        val selected = dataset.build()
        val result = if (datasetAuthentication) {
            Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, selected)
                .putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT_EPHEMERAL_DATASET, true)
        } else {
            val response = AutofillSaveCoordinator.response(FillResponse.Builder(), intent.getStringExtra(AutofillSaveCoordinator.EXTRA_REQUEST))
                .addDataset(selected).build()
            Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, response)
        }
        setResult(Activity.RESULT_OK, result)
        finish()
    }
    internal fun cancel() { setResult(Activity.RESULT_CANCELED); finish() }
    override fun onDestroy() { AutoFillRequestBroker.destroyed(this); super.onDestroy() }
    private fun ids(name: String): List<AutofillId> = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(name, AutofillId::class.java).orEmpty()
        else @Suppress("DEPRECATION") intent.getParcelableArrayListExtra<AutofillId>(name).orEmpty()
    private fun currentSignatures(): Set<String> = runCatching {
        val raw = if (Build.VERSION.SDK_INT >= 28) packageManager.getPackageInfo(target, PackageManager.GET_SIGNING_CERTIFICATES).signingInfo?.apkContentsSigners
        else @Suppress("DEPRECATION") packageManager.getPackageInfo(target, PackageManager.GET_SIGNATURES).signatures
        require(!raw.isNullOrEmpty() && raw.size <= 8)
        raw.map { Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-256").digest(it.toByteArray())) }.toSet()
    }.getOrDefault(emptySet())
}
