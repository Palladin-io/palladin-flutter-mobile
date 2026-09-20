package io.palladin.mobile

import android.os.Build
import android.os.Bundle
import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.palladin.mobile.autofill.AutoFillCacheStore
import io.palladin.mobile.export.ProtectedExportStore
import io.palladin.mobile.sharing.EntryShareIngressBridge
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val cacheExecutor = Executors.newSingleThreadExecutor()
    private val exportExecutor = Executors.newSingleThreadExecutor()
    private var sharingAttachment: Any? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        intent = sanitizeDirectIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(sanitizeDirectIntent(intent))
    }

    private fun sanitizeDirectIntent(source: Intent): Intent {
        val uri = source.data ?: return source
        if (uri.scheme == "https" || uri.scheme == "http" ||
            uri.fragment != null || uri.host == "share" || uri.path?.startsWith("/share") == true
        ) {
            // Sharing enters only through the no-history activity, before plugins.
            EntryShareIngressBridge.offer(this, null)
            return Intent(this, MainActivity::class.java)
        }
        return source
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharingAttachment = EntryShareIngressBridge.attach(flutterEngine.dartExecutor.binaryMessenger)
        val cacheStore = AutoFillCacheStore(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUTOFILL_CHANNEL,
        ).setMethodCallHandler { call, result ->
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
        EntryShareIngressBridge.detach(sharingAttachment)
        cacheExecutor.shutdownNow()
        exportExecutor.shutdownNow()
        super.onDestroy()
    }

    private companion object {
        const val AUTOFILL_CHANNEL = "io.palladin.mobile/autofill"
        const val EXPORT_CHANNEL = "io.palladin.mobile/protected-export"
    }
}
