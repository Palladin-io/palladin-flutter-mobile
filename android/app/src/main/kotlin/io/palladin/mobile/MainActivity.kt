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
                        "revokeCacheAccess" -> {
                            val arguments = call.arguments as? Map<*, *>
                            val generation = (arguments?.get("generation") as? Number)?.toLong()
                                ?: throw IllegalArgumentException("Missing generation")
                            cacheStore.revokeAccess(generation)
                        }
                        "replaceCache" -> {
                            val arguments = call.arguments as? Map<*, *>
                                ?: throw IllegalArgumentException("Missing arguments")
                            val generation = (arguments["generation"] as? Number)?.toLong()
                                ?: throw IllegalArgumentException("Missing generation")
                            val records = arguments["records"] as? List<*>
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                cacheStore.replace(records, generation)
                            } else {
                                cacheStore.clear(generation)
                            }
                        }
                        "clearCache" -> {
                            val arguments = call.arguments as? Map<*, *>
                            val generation = (arguments?.get("generation") as? Number)?.toLong()
                                ?: throw IllegalArgumentException("Missing generation")
                            cacheStore.clear(generation)
                        }
                        else -> throw UnsupportedOperationException(call.method)
                    }
                }
                runOnUiThread {
                    outcome.fold(
                        onSuccess = { result.success(null) },
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
