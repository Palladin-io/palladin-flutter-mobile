package io.palladin.mobile

import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import design.codeux.biometric_storage.BiometricStorageFile
import design.codeux.biometric_storage.InitOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.palladin.mobile.autofill.*
import java.util.concurrent.Executors

/** Uses the existing MK storage API; does not introduce another key or wrapper. */
internal class AutoFillRequestBridge(private val activity: FragmentActivity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, AutoFillRequestBroker.CHANNEL)
    private val worker = Executors.newSingleThreadExecutor()
    private data class Authentication(val attempt: AutoFillAuthenticationAttempt, val result: MethodChannel.Result, var prompt: BiometricPrompt? = null)
    private var authentication: Authentication? = null

    init {
        AutoFillRequestBroker.initialize(activity)
        AutoFillRequestBroker.onPending = { channel.invokeMethod("pendingChanged", null) }
        AutoFillRequestBroker.onInvalidated = { id -> cancelPrompt(); channel.invokeMethod("invalidated", id) }
        channel.setMethodCallHandler { call, result ->
            try {
                val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                fun string(key: String) = (args[key] as? String)?.takeIf { it.isNotBlank() }
                    ?: throw IllegalArgumentException("Missing request field")
                fun number(key: String): Long {
                    val value = args[key]
                    require(value is Int || value is Long)
                    return (value as Number).toLong().also { require(it > 0) }
                }
                fun selection() = AutoFillSelection(string("vaultId"), string("entryId"), string("selectedHost"))
                when (call.method) {
                    "pending" -> result.success(AutoFillRequestBroker.pending())
                    "sourceSnapshot" -> result.success(AutoFillRequestBroker.sourceSnapshot())
                    "revokeSource" -> result.success(AutoFillRequestBroker.revokeSnapshot(number("sourceEpoch"), string("profileDigest")))
                    "beginSourceSession" -> result.success(AutoFillRequestBroker.beginSession(AutoFillSourceProfile(
                        string("principalId"), string("organizationId"), string("organizationMembershipGeneration"),
                        string("offlinePolicy"), Math.toIntExact(number("offlinePolicyVersion")), string("profileBinding")), string("sessionId")))
                    "activateSource" -> result.success(AutoFillRequestBroker.activate(string("sessionId"), number("sourceEpoch")))
                    "invalidateSource" -> result.success(AutoFillRequestBroker.invalidate(string("sessionId"), number("sourceEpoch"), string("profileBinding")))
                    "revokeSourceSession" -> result.success(AutoFillRequestBroker.revokeSession(string("sessionId"), number("sourceEpoch"), string("profileBinding")))
                    "invalidateSession" -> { AutoFillRequestBroker.lock(string("sessionId")); result.success(null) }
                    "bind" -> result.success(AutoFillRequestBroker.bind(string("id"), string("principalId"), string("organizationId"), string("sessionId")))
                    "authenticatePresence", "readBiometricMasterKey" -> authenticate(string("id"), string("bindingToken"),
                        call.method == "readBiometricMasterKey", args["promptTitle"] as? String, args["cancelLabel"] as? String, result)
                    "authorizePasswordUnlock" -> result.success(AutoFillRequestBroker.authorizePasswordUnlock(string("id"), string("bindingToken")))
                    "confirmSelection" -> result.success(AutoFillRequestBroker.confirm(string("id"), string("bindingToken"), string("authorizationToken"), selection(), number("sourceEpoch")))
                    "validate" -> result.success(AutoFillRequestBroker.validate(string("id"), string("bindingToken"), string("authorizationToken"), string("selectedHost"), number("sourceEpoch")))
                    "complete" -> {
                        val completed = AutoFillRequestBroker.complete(string("id"), string("bindingToken"), string("authorizationToken"), selection(),
                            args["consentToken"] as? String, number("effectiveNotAfterMillis"), number("sourceEpoch"), args["username"] as? String ?: "", args["password"] as? String ?: "")
                        result.success(completed)
                        if (completed) activity.moveTaskToBack(true)
                    }
                    "cancel" -> { AutoFillRequestBroker.cancel(string("id")); result.success(null); activity.moveTaskToBack(true) }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error((error as? AutoFillSourceException)?.code ?: "AUTOFILL_REQUEST_UNAVAILABLE", "AutoFill request unavailable", null) }
        }
    }

    private fun authenticate(id: String, binding: String, readMasterKey: Boolean, title: String?, cancel: String?, result: MethodChannel.Result) {
        if (authentication != null) throw AutoFillSourceException("AUTOFILL_AUTHENTICATION_BUSY")
        val attempt = AutoFillRequestBroker.beginAuthentication(id, binding)
        val file = if (readMasterKey) BiometricStorageFile(activity.applicationContext, "palladin_vault_mk_v2", InitOptions(-1, true, true)) else null
        val cipher = if (readMasterKey) requireNotNull(file?.cipherForDecrypt()) else null
        val operation = Authentication(attempt, result)
        authentication = operation
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(authenticationResult: BiometricPrompt.AuthenticationResult) {
                if (authentication !== operation) return
                if (!readMasterKey) {
                    try { succeed(operation, AutoFillRequestBroker.authenticated(attempt)) }
                    catch (_: Exception) { fail(operation, "AUTOFILL_REQUEST_INVALIDATED") }
                    return
                }
                val authenticatedCipher = authenticationResult.cryptoObject?.cipher
                if (authenticatedCipher == null || authenticatedCipher !== cipher) { fail(operation, "AUTOFILL_REQUEST_INVALIDATED"); return }
                worker.execute {
                    var key: ByteArray? = null
                    try {
                        // Non-null actual authenticated cipher only: never plugin fallback.
                        val encoded = requireNotNull(file!!.readFile(authenticatedCipher))
                        key = Base64.decode(encoded, Base64.DEFAULT)
                        require(key.size == 32)
                        val bytes = key
                        activity.runOnUiThread {
                            try {
                                if (authentication !== operation) return@runOnUiThread
                                val token = AutoFillRequestBroker.authenticated(attempt)
                                succeed(operation, mapOf("masterKey" to bytes, "authorizationToken" to token))
                            } catch (_: Exception) { fail(operation, "AUTOFILL_REQUEST_INVALIDATED") }
                            finally { bytes.fill(0) }
                        }
                        key = null // UI continuation owns the temporary buffer.
                    } catch (_: Exception) {
                        key?.fill(0)
                        activity.runOnUiThread { fail(operation, "AUTOFILL_BIOMETRIC_UNAVAILABLE") }
                    }
                }
            }
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) { fail(operation, "AUTOFILL_AUTHENTICATION_CANCELED") }
        })
        operation.prompt = prompt
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title?.takeIf { it.isNotBlank() } ?: activity.getString(R.string.autofill_biometric_title))
            .setNegativeButtonText(cancel?.takeIf { it.isNotBlank() } ?: activity.getString(android.R.string.cancel))
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG).build()
        try {
            if (cipher == null) prompt.authenticate(info) else prompt.authenticate(info, BiometricPrompt.CryptoObject(cipher))
        } catch (_: Exception) { fail(operation, "AUTOFILL_BIOMETRIC_UNAVAILABLE") }
    }
    private fun succeed(operation: Authentication, value: Any) {
        if (authentication !== operation) return
        authentication = null
        operation.result.success(value)
    }
    private fun fail(operation: Authentication, code: String) {
        if (authentication !== operation) return
        authentication = null
        operation.result.error(code, "AutoFill authentication unavailable", null)
    }
    private fun cancelPrompt() {
        val operation = authentication ?: return
        fail(operation, "AUTOFILL_AUTHENTICATION_CANCELED")
        operation.prompt?.cancelAuthentication()
    }
    fun background() { AutoFillRequestBroker.cancel(null); cancelPrompt() }
    fun close() {
        background()
        channel.setMethodCallHandler(null)
        AutoFillRequestBroker.onPending = null
        AutoFillRequestBroker.onInvalidated = null
        worker.shutdownNow()
    }
}
