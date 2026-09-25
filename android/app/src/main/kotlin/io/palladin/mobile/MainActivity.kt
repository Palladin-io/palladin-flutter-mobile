package io.palladin.mobile

import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.palladin.mobile.autofill.AutoFillCacheStore
import io.palladin.mobile.autofill.GeneratedPasswordHistory
import io.palladin.mobile.autofill.StrongPasswordGenerator
import io.palladin.mobile.export.ProtectedExportStore
import java.util.concurrent.Executors
import javax.crypto.Cipher

class MainActivity : FlutterFragmentActivity() {
    private val cacheExecutor = Executors.newSingleThreadExecutor()
    private val historyExecutor = Executors.newSingleThreadExecutor()
    private val exportExecutor = Executors.newSingleThreadExecutor()
    private var historyPromptActive = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val cacheStore = AutoFillCacheStore(applicationContext)
        val generatedHistory = GeneratedPasswordHistory(applicationContext)
        cacheExecutor.execute { runCatching { generatedHistory.revokeAll() } }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUTOFILL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method in AUTHENTICATED_HISTORY_METHODS) {
                authenticateGeneratedHistory(call, result, generatedHistory)
                return@setMethodCallHandler
            }
            // Every fence/session mutation shares one ordered executor. The
            // Android path has no identity-store callback in this queue, so a
            // revoke cannot wedge, and an old revoke cannot arrive after a
            // subsequently submitted beginSession and deny the new session.
            cacheExecutor.execute {
                val outcome = runCatching {
                    when (call.method) {
                        "beginCacheSession" -> {
                            cacheStore.beginSession()
                        }
                        "revokeCacheAccess" -> {
                            val generation = cacheStore.revokeAccess()
                            cacheExecutor.execute {
                                runCatching { cacheStore.cleanupRevoked(generation) }
                            }
                            generation
                        }
                        "replaceCache" -> {
                            val arguments = call.arguments as? Map<*, *>
                                ?: throw IllegalArgumentException("Missing arguments")
                            val sessionToken = (arguments["sessionToken"] as? Number)?.toLong()
                                ?: throw IllegalArgumentException("Missing session token")
                            val payload = arguments["payload"] as? Map<*, *>
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                cacheStore.replace(payload, sessionToken)
                            } else {
                                cacheStore.clear(sessionToken)
                            }
                            null
                        }
                        "clearCache" -> {
                            val arguments = call.arguments as? Map<*, *>
                            val sessionToken = (arguments?.get("sessionToken") as? Number)?.toLong()
                                ?: throw IllegalArgumentException("Missing session token")
                            cacheStore.clear(sessionToken)
                            null
                        }
                        "activateGeneratedPasswordHistory" -> {
                            val principalId = (call.arguments as? Map<*, *>)?.get("principalId") as? String
                                ?: throw IllegalArgumentException("Missing principal")
                            generatedHistory.activate(principalId)
                        }
                        "revokeGeneratedPasswordHistory" -> {
                            val token = (call.arguments as? Map<*, *>)?.get("token") as? String
                                ?: throw IllegalArgumentException("Missing token")
                            generatedHistory.revoke(token)
                            null
                        }
                        "revokeAllGeneratedPasswordSessions" -> {
                            generatedHistory.revokeAll()
                            null
                        }
                        else -> throw UnsupportedOperationException(call.method)
                    }
                }
                runOnUiThread {
                    outcome.fold(
                        onSuccess = { value -> result.success(value) },
                        onFailure = { error ->
                            if (error is UnsupportedOperationException) {
                                result.notImplemented()
                            } else {
                                result.error("AUTOFILL_CACHE_ERROR", "Native cache operation failed", null)
                            }
                        },
                    )
                }
            }
        }
        val exportStore = ProtectedExportStore(applicationContext)
        exportExecutor.execute { runCatching { exportStore.sweepStale() } }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EXPORT_CHANNEL,
        ).setMethodCallHandler { call, result ->
            exportExecutor.execute {
                val outcome = runCatching {
                    val arguments = call.arguments as? Map<*, *>
                    when (call.method) {
                        "createExport" -> {
                            val extension = arguments?.get("extension") as? String
                                ?: throw IllegalArgumentException("Missing extension")
                            exportStore.create(extension)
                        }
                        "appendExport" -> {
                            val bytes = arguments?.get("bytes") as? ByteArray
                                ?: throw IllegalArgumentException("Missing bytes")
                            val id = arguments["id"] as? String
                                ?: throw IllegalArgumentException("Missing id")
                            try {
                                exportStore.append(id, bytes)
                            } finally {
                                bytes.fill(0)
                            }
                        }
                        "finishExport" -> {
                            val id = arguments?.get("id") as? String
                                ?: throw IllegalArgumentException("Missing id")
                            exportStore.finish(id)
                        }
                        "abortExport" -> {
                            val id = arguments?.get("id") as? String
                                ?: throw IllegalArgumentException("Missing id")
                            exportStore.abort(id)
                            null
                        }
                        "deleteExport" -> {
                            val path = arguments?.get("path") as? String
                                ?: throw IllegalArgumentException("Missing path")
                            exportStore.delete(path)
                        }
                        "sweepStaleExports" -> exportStore.sweepStale()
                        "cleanupExports" -> exportStore.cleanupAll()
                        else -> throw UnsupportedOperationException(call.method)
                    }
                }
                runOnUiThread {
                    outcome.fold(
                        onSuccess = { value -> result.success(value) },
                        onFailure = { error ->
                            if (error is UnsupportedOperationException) {
                                result.notImplemented()
                            } else {
                                result.error("PROTECTED_EXPORT_ERROR", "Native export operation failed", null)
                            }
                        },
                    )
                }
            }
        }
    }

    override fun onDestroy() {
        cacheExecutor.shutdownNow()
        historyExecutor.shutdownNow()
        exportExecutor.shutdownNow()
        super.onDestroy()
    }

    private fun authenticateGeneratedHistory(
        call: MethodCall,
        result: MethodChannel.Result,
        history: GeneratedPasswordHistory,
    ) {
        if (historyPromptActive) {
            result.error("BIOMETRIC_BUSY", "Generated password authentication is in progress", null)
            return
        }
        val args = call.arguments as? Map<*, *>
        val principalId = args?.get("principalId") as? String
        val promptText = args?.get("prompt") as? String
        if (principalId.isNullOrBlank() || promptText.isNullOrBlank()) {
            result.error("AUTOFILL_HISTORY_ERROR", "Missing authentication context", null)
            return
        }
        val operation = runCatching { history.createUnwrapOperation(principalId) }.getOrElse {
            result.error("AUTOFILL_HISTORY_ERROR", "History is unavailable", null)
            return
        }
        historyPromptActive = true
        val prompt = BiometricPrompt(
            this,
            ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(authentication: BiometricPrompt.AuthenticationResult) {
                    val cipher = authentication.cryptoObject?.cipher
                    if (cipher == null) {
                        finishHistoryPrompt(result, null, IllegalStateException("Missing biometric cipher"))
                        return
                    }
                    historyExecutor.execute {
                        val outcome = runCatching {
                            completeGeneratedHistory(call, history, operation, cipher)
                        }
                        runOnUiThread {
                            outcome.fold(
                                onSuccess = { value -> finishHistoryPrompt(result, value, null) },
                                onFailure = { error -> finishHistoryPrompt(result, null, error) },
                            )
                        }
                    }
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    finishHistoryPrompt(result, null, IllegalStateException("Biometric authentication canceled"))
                }
            },
        )
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(promptText)
            .setNegativeButtonText(getString(io.palladin.mobile.R.string.autofill_cancel))
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
            .build()
        prompt.authenticate(info, BiometricPrompt.CryptoObject(operation.cipher))
    }

    private fun completeGeneratedHistory(
        call: MethodCall,
        history: GeneratedPasswordHistory,
        operation: io.palladin.mobile.autofill.GeneratedHistoryUnwrapOperation,
        cipher: Cipher,
    ): Any? {
        val args = call.arguments as Map<*, *>
        return when (call.method) {
            "listGeneratedPasswords" -> history.readAuthenticated(operation, cipher).map { record ->
                mapOf(
                    "id" to record.id,
                    "domain" to record.domain,
                    "createdAtMillis" to record.createdAtMillis,
                )
            }
            "revealGeneratedPassword" -> {
                val id = args["id"] as? String ?: throw IllegalArgumentException("Missing record")
                history.readAuthenticated(operation, cipher).single { it.id == id }.password
            }
            "deleteGeneratedPassword" -> {
                val id = args["id"] as? String ?: throw IllegalArgumentException("Missing record")
                history.deleteAuthenticated(operation, cipher, id)
                null
            }
            "clearGeneratedPasswords" -> {
                history.clearAuthenticated(operation, cipher)
                null
            }
            "generatePasswordForEntry" -> {
                val domain = args["domain"] as? String ?: throw IllegalArgumentException("Missing domain")
                val password = StrongPasswordGenerator.generate()
                history.appendAuthenticated(operation, cipher, domain, password)
                password
            }
            else -> throw UnsupportedOperationException(call.method)
        }
    }

    private fun finishHistoryPrompt(result: MethodChannel.Result, value: Any?, error: Throwable?) {
        historyPromptActive = false
        if (error == null) result.success(value)
        else result.error("AUTOFILL_HISTORY_ERROR", "History operation failed", null)
    }

    private companion object {
        const val AUTOFILL_CHANNEL = "io.palladin.mobile/autofill"
        const val EXPORT_CHANNEL = "io.palladin.mobile/protected-export"
        val AUTHENTICATED_HISTORY_METHODS = setOf(
            "listGeneratedPasswords", "revealGeneratedPassword", "deleteGeneratedPassword",
            "clearGeneratedPasswords", "generatePasswordForEntry",
        )
    }
}
