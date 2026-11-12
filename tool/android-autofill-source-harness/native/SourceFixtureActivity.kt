package io.palladin.mobile.autofill

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView
import java.io.File

/** Debug-only isolated target. It never fabricates native authentication. */
class SourceFixtureActivity : Activity() {
    private lateinit var status: TextView
    override fun onCreate(saved: Bundle?) {
        super.onCreate(saved)
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val username = EditText(this)
        val password = EditText(this).apply { inputType = 129 }
        status = TextView(this).apply { text = "SOURCE_TARGET_READY" }
        layout.addView(username); layout.addView(password); layout.addView(status)
        layout.addView(Button(this).apply {
            text = "Open native request"
            setOnClickListener {
                status.text = "SOURCE_TARGET_WAITING"
                val legacy = intent.getBooleanExtra("legacy", false)
                if (legacy) File(noBackupFilesDir, "palladin_autofill_cache_v1").writeText("synthetic-noncredential-marker")
                val owner = if (legacy) AutofillAuthenticationActivity::class.java else SourceAutofillAuthenticationActivity::class.java
                val request = Intent(this@SourceFixtureActivity, owner)
                    .putExtra(AutofillAuthenticationActivity.EXTRA_PACKAGE_NAME, packageName)
                    .putExtra(AutofillAuthenticationActivity.EXTRA_ORIGIN_MODE, "MANUAL_NATIVE")
                    .putExtra(AutofillAuthenticationActivity.EXTRA_DATASET_AUTHENTICATION, true)
                    .putParcelableArrayListExtra(AutofillAuthenticationActivity.EXTRA_USERNAME_IDS, arrayListOf(username.autofillId))
                    .putParcelableArrayListExtra(AutofillAuthenticationActivity.EXTRA_PASSWORD_IDS, if (intent.getBooleanExtra("usernameOnly", false)) arrayListOf() else arrayListOf(password.autofillId))
                startActivityForResult(request, 7)
            }
        })
        setContentView(layout)
    }
    override fun onNewIntent(value: Intent) { super.onNewIntent(value); setIntent(value) }
    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        super.onActivityResult(request, result, data)
        if (request == 7) {
            if (intent.getBooleanExtra("legacy", false)) {
                val marker = File(noBackupFilesDir, "palladin_autofill_cache_v1")
                status.text = if (result == RESULT_CANCELED && marker.isFile &&
                    marker.readText() == "synthetic-noncredential-marker") "LEGACY_CACHE_UNTOUCHED" else "LEGACY_CACHE_TOUCHED"
                marker.delete()
            } else status.text = if (result == RESULT_CANCELED) "SOURCE_OWNER_CANCEL_PASS" else "SOURCE_OWNER_FAIL"
        }
    }
}
