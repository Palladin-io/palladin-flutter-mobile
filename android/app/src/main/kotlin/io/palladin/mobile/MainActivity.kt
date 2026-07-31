package io.palladin.mobile

import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.palladin.mobile.autofill.AutoFillCacheStore
import io.palladin.mobile.export.ProtectedExportStore
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val cacheExecutor = Executors.newSingleThreadExecutor()
    private val revocationExecutor = Executors.newSingleThreadExecutor()
    private val exportExecutor = Executors.newSingleThreadExecutor()

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
        revocationExecutor.shutdownNow()
        cacheExecutor.shutdownNow()
        exportExecutor.shutdownNow()
        super.onDestroy()
    }

    private companion object {
        const val AUTOFILL_CHANNEL = "io.palladin.mobile/autofill"
        const val EXPORT_CHANNEL = "io.palladin.mobile/protected-export"
    }
}
