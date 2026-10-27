package io.palladin.autofill.form

import android.app.Activity
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillManager
import android.webkit.WebView
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.TextView

/** Local-only synthetic forms; assertions expose booleans, never field values. */
class FormActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val mode = intent.getStringExtra("mode") ?: "native-login"
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 100, 24, 24)
        }
        val result = TextView(this)
        if (mode.startsWith("web")) {
            val web = WebView(this)
            web.settings.javaScriptEnabled = true
            layout.addView(web, LinearLayout.LayoutParams(-1, 450))
            val password = if (mode == "web-login") {
                "<input id='password' type='password' autocomplete='current-password' placeholder='Synthetic password'>"
            } else ""
            web.loadDataWithBaseURL(
                "https://fixture.invalid/",
                "<html><meta name='viewport' content='width=device-width'><body><form>" +
                    "<input id='username' type='email' autocomplete='username' placeholder='Synthetic username'>" +
                    password + "</form></body></html>",
                "text/html", "UTF-8", null,
            )
            layout.addView(Button(this).apply {
                text = "Verify fill"
                setOnClickListener {
                    web.evaluateJavascript(
                        "document.getElementById('username').value === 'synthetic-user' && " +
                            "(!document.getElementById('password') || document.getElementById('password').value === 'synthetic-only-not-secret')",
                    ) { result.text = "fillVerified=" + (it == "true") }
                }
            })
        } else {
            val username = EditText(this).apply {
                id = View.generateViewId()
                hint = "Synthetic username"
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
                setAutofillHints(View.AUTOFILL_HINT_USERNAME)
            }
            val password = if (mode == "native-login") EditText(this).apply {
                id = View.generateViewId()
                hint = "Synthetic password"
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                setAutofillHints(View.AUTOFILL_HINT_PASSWORD)
            } else null
            layout.addView(username)
            password?.let(layout::addView)
            layout.addView(Button(this).apply {
                text = "Request Autofill"
                setOnClickListener {
                    username.requestFocus()
                    getSystemService(AutofillManager::class.java).requestAutofill(username)
                }
            })
            layout.addView(Button(this).apply {
                text = "Verify fill"
                setOnClickListener {
                    result.text = "fillVerified=" + (username.text.toString() == "synthetic-user" &&
                        (password == null || password.text.toString() == "synthetic-only-not-secret"))
                }
            })
        }
        layout.addView(result)
        setContentView(layout)
    }
}
