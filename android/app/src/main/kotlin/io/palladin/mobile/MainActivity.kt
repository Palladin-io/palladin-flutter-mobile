package io.palladin.mobile

import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import io.palladin.mobile.autofill.AutoFillCacheStore
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val cacheExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val cacheStore = AutoFillCacheStore(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AUTOFILL_CHANNEL,
        ).setMethodCallHandler { call, result ->
            cacheExecutor.execute {
                val outcome = runCatching {
                    when (call.method) {
                        "replaceCache" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                cacheStore.replace(call.arguments as? List<*>)
                            } else {
                                cacheStore.clear()
                            }
                        }
                        "clearCache" -> cacheStore.clear()
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
        cacheExecutor.shutdownNow()
        super.onDestroy()
    }

    private companion object {
        const val AUTOFILL_CHANNEL = "io.palladin.mobile/autofill"
    }
}
