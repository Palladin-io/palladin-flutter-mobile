package io.palladin.autofill.form

import android.app.Activity
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillManager
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
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
            val password = if (mode == "web-login" || mode == "web-http") {
                "<input id='password' type='password' autocomplete='current-password' placeholder='Synthetic password'>"
            } else ""
            val usernameHtml = when (mode) {
                "web-search" -> "<input id='username' type='search' autocomplete='username'>"
                "web-otp" -> "<input type='password' autocomplete='one-time-code'>"
                "web-confirm" -> "<input id='confirm_password' name='confirm_password' type='password'>"
                "web-hidden" -> "<input id='probe'><input type='hidden' autocomplete='username'>"
                "web-disabled" -> "<input id='probe'><input type='text' autocomplete='username' disabled>"
                else -> "<input id='username' type='email' autocomplete='username' placeholder='Synthetic username'>"
            }
            val fixtureUrl = if (mode == "web-http") "http://fixture.invalid/" else "https://fixture.invalid/"
            val html = "<html><meta name='viewport' content='width=device-width'><body><form>" +
                usernameHtml + password + "</form></body></html>"
            web.webViewClient = object : WebViewClient() {
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse {
                    val content = fixtureContent(request.url.toString(), html)
                    return WebResourceResponse(
                        "text/html", "UTF-8", if (content == null) 404 else 200,
                        if (content == null) "Not Found" else "OK", emptyMap(),
                        (content ?: "").byteInputStream(),
                    )
                }
            }
            web.loadUrl(fixtureUrl)
            layout.addView(Button(this).apply {
                text = "Request Autofill"
                setOnClickListener { getSystemService(AutofillManager::class.java).requestAutofill(web) }
            })
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
            when (mode) {
                "native-search" -> { username.id = R.id.search; username.inputType = InputType.TYPE_CLASS_TEXT; username.setAutofillHints("search") }
                "native-otp" -> { username.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD; username.setAutofillHints("smsOTPCode") }
                "native-confirm" -> { username.id = R.id.confirm_password; username.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD; username.setAutofillHints(View.AUTOFILL_HINT_PASSWORD) }
                "native-hidden" -> username.visibility = View.INVISIBLE
                "native-disabled" -> username.isEnabled = false
            }
            val password = if (mode == "native-login") EditText(this).apply {
                id = View.generateViewId()
                hint = "Synthetic password"
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                setAutofillHints(View.AUTOFILL_HINT_PASSWORD)
            } else null
            val focusTarget = if (mode in setOf("native-hidden", "native-disabled", "native-container")) EditText(this).apply {
                inputType = InputType.TYPE_CLASS_TEXT
                hint = "Synthetic probe"
            } else username
            if (focusTarget !== username) layout.addView(focusTarget)
            if (mode == "native-container") {
                layout.addView(TextView(this).apply { text = "Synthetic label"; setAutofillHints(View.AUTOFILL_HINT_USERNAME) })
            } else layout.addView(username)
            password?.let(layout::addView)
            layout.addView(Button(this).apply {
                text = "Request Autofill"
                setOnClickListener {
                    focusTarget.requestFocus()
                    getSystemService(AutofillManager::class.java).requestAutofill(focusTarget)
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
