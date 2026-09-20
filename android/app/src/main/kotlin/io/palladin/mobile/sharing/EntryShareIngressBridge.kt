package io.palladin.mobile.sharing

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.palladin.mobile.R

internal object EntryShareIngressBridge {
    private val mailbox = EntryShareMailbox(System::currentTimeMillis, SystemClock::elapsedRealtime)
    private val handler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var attachment: Any? = null
    private val expiry = Runnable { publish(mailbox.clear()) }

    fun offer(context: Context, url: String?) {
        handler.removeCallbacks(expiry)
        val origin = "https://${context.getString(R.string.entry_sharing_host)}"
        publish(mailbox.offer(url, origin))
        handler.postDelayed(expiry, EntryShareMailbox.MAX_AGE_MS)
    }

    fun attach(messenger: BinaryMessenger): Any {
        val owner = Any()
        attachment = owner
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, "io.palladin.mobile/entry-sharing").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePending" -> {
                        handler.removeCallbacks(expiry)
                        result.success(mailbox.take())
                    }
                    else -> result.notImplemented()
                }
            }
        }
        return owner
    }

    fun detach(owner: Any?) {
        if (owner == null || attachment !== owner) return
        channel?.setMethodCallHandler(null)
        channel = null
        attachment = null
    }

    private fun publish(generation: Long) {
        channel?.invokeMethod("pending", generation)
    }
}
