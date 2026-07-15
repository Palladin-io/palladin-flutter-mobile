package io.palladin.mobile

import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.palladin.mobile.autofill.AutoFillCacheStore
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val cacheExecutor = Executors.newSingleThreadExecutor()
    private val revocationExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val cacheStore = AutoFillCacheStore(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUTOFILL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            val executor = if (call.method == "revokeCacheAccess") {
                revocationExecutor
            } else {
                cacheExecutor
            }
            executor.execute {
                val outcome = runCatching {
                    when (call.method) {
                        "beginCacheSession" -> {
                            cacheStore.beginSession()
                        }
                        "revokeCacheAccess" -> {
                            cacheStore.revokeAccess()
                        }
                        "replaceCache" -> {
                            val arguments = call.arguments as? Map<*, *>
                                ?: throw IllegalArgumentException("Missing arguments")
                            val sessionToken = (arguments["sessionToken"] as? Number)?.toLong()
                                ?: throw IllegalArgumentException("Missing session token")
                            val records = arguments["records"] as? List<*>
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                cacheStore.replace(records, sessionToken)
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
    }

    override fun onDestroy() {
        revocationExecutor.shutdownNow()
        cacheExecutor.shutdownNow()
        super.onDestroy()
    }

    private companion object {
        const val AUTOFILL_CHANNEL = "io.palladin.mobile/autofill"
    }
}
