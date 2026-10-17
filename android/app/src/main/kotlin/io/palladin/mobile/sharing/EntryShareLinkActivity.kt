package io.palladin.mobile.sharing

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import io.palladin.mobile.MainActivity

class EntryShareLinkActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        val source = intent
        intent = Intent()
        super.onCreate(null)
        receive(source, restored = savedInstanceState != null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(Intent())
        setIntent(Intent())
        receive(intent, restored = false)
    }

    private fun receive(source: Intent, restored: Boolean) {
        val url = if (!restored &&
            source.action == Intent.ACTION_VIEW &&
            source.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY == 0
        ) source.dataString else null
        EntryShareIngressBridge.offer(this, url)
        startActivity(Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        })
        finishAndRemoveTask()
    }
}
