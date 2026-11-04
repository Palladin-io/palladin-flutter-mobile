package io.palladin.mobile.autofill

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

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
                val request = Intent(this@SourceFixtureActivity, SourceAutofillAuthenticationActivity::class.java)
                    .putExtra(AutofillAuthenticationActivity.EXTRA_PACKAGE_NAME, packageName)
                    .putExtra(AutofillAuthenticationActivity.EXTRA_ORIGIN_MODE, "MANUAL_NATIVE")
                    .putExtra(AutofillAuthenticationActivity.EXTRA_DATASET_AUTHENTICATION, true)
                    .putParcelableArrayListExtra(AutofillAuthenticationActivity.EXTRA_USERNAME_IDS, arrayListOf(username.autofillId))
                    .putParcelableArrayListExtra(AutofillAuthenticationActivity.EXTRA_PASSWORD_IDS, arrayListOf(password.autofillId))
                startActivityForResult(request, 7)
            }
        })
        setContentView(layout)
    }
    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        super.onActivityResult(request, result, data)
        if (request == 7) status.text = if (result == RESULT_CANCELED) "SOURCE_OWNER_CANCEL_PASS" else "SOURCE_OWNER_FAIL"
    }
}
