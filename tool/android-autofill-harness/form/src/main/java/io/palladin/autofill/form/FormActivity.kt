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
    private lateinit var autofillCallback: AutofillManager.AutofillCallback

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val mode = intent.getStringExtra("mode") ?: "native-login"
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(24, 100, 24, 24)
        }
        val result = TextView(this)
        val evidence = TextView(this)
        val manager = getSystemService(AutofillManager::class.java)
        val positive = mode in setOf("native-login", "native-username", "native-username-hint", "native-login-opaque", "native-username-manual", "native-username-manual-verified", "web-login", "web-username")
        var requested = false
        var unavailable = false
        var shown = false
        var enabledAtRequest = false
        var domReady = !mode.startsWith("web")
        var focusVerified = false
        var noneditableTarget = false
        var unavailableEvents = 0
        var shownEvents = 0
        fun publishEvidence() {
            evidence.text = "requestIssued=$requested unavailable=$unavailable uiShown=$shown enabled=$enabledAtRequest domReady=$domReady focusVerified=$focusVerified unavailableEvents=$unavailableEvents shownEvents=$shownEvents noneditableTarget=$noneditableTarget"
        }
        fun observe(event: Int) {
            if (event == AutofillManager.AutofillCallback.EVENT_INPUT_UNAVAILABLE) { unavailable = true; unavailableEvents++ }
            if (event == AutofillManager.AutofillCallback.EVENT_INPUT_SHOWN) { shown = true; shownEvents++ }
            publishEvidence()
        }
        autofillCallback = object : AutofillManager.AutofillCallback() {
            override fun onAutofillEvent(view: View, event: Int) = observe(event)
            override fun onAutofillEvent(view: View, virtualId: Int, event: Int) = observe(event)
        }
        manager.registerCallback(autofillCallback)
        fun request(target: View) {
            requested = true
            enabledAtRequest = manager.isEnabled
            publishEvidence()
            manager.requestAutofill(target)
        }
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
                override fun onPageFinished(view: WebView, url: String) {
                    view.evaluateJavascript("document.readyState === 'complete'") {
                        domReady = it == "true"
                        publishEvidence()
                    }
                }
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
                setOnClickListener {
                    web.evaluateJavascript("(function(){const field=document.querySelector('input:not([disabled]):not([type=hidden])');if(field)field.focus();return !!field && document.activeElement===field;})()") {
                        focusVerified = it == "true"
                        request(web)
                    }
                }
            })
            layout.addView(Button(this).apply {
                text = "Verify fill"
                setOnClickListener {
                    val assertion = if (positive) {
                        "document.getElementById('username').value === 'synthetic-user' && " +
                            "(!document.getElementById('password') || document.getElementById('password').value === 'synthetic-only-not-secret')"
                    } else "Array.from(document.querySelectorAll('input')).every(input => input.value === '')"
                    web.evaluateJavascript(assertion) {
                        result.text = (if (positive) "fillVerified=" else "fieldsUnchanged=") + (it == "true")
                    }
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
                "native-username-hint" -> {
                    username.inputType = InputType.TYPE_CLASS_TEXT
                    username.setAutofillHints()
                    username.hint = "Adres e-mail lub login"
                }
                "native-username-manual", "native-username-manual-verified", "native-login-opaque" -> {
                    username.inputType = InputType.TYPE_CLASS_TEXT
                    username.setAutofillHints()
                    username.hint = "識別子"
                }
                "native-search" -> { username.id = R.id.search; username.inputType = InputType.TYPE_CLASS_TEXT; username.setAutofillHints("search") }
                "native-otp" -> { username.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD; username.setAutofillHints("smsOTPCode") }
                "native-confirm" -> { username.id = R.id.confirm_password; username.inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD; username.setAutofillHints(View.AUTOFILL_HINT_PASSWORD) }
                "native-hidden" -> username.visibility = View.INVISIBLE
                "native-disabled" -> username.isEnabled = false
            }
            if (mode in setOf("native-username-hint", "native-username-manual",
                    "native-username-manual-verified", "native-login-opaque")) {
                check(username.autofillHints.isNullOrEmpty()) { "Synthetic no-hint fixture is malformed" }
            }
            val password = if (mode in setOf("native-login", "native-login-opaque")) EditText(this).apply {
                id = View.generateViewId()
                hint = "Synthetic password"
                inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
                setAutofillHints(View.AUTOFILL_HINT_PASSWORD)
            } else null
            val focusTarget: TextView = when (mode) {
                "native-container" -> TextView(this).apply {
                    text = "Synthetic label"
                    isFocusableInTouchMode = true
                    importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_YES
                    setAutofillHints(View.AUTOFILL_HINT_USERNAME)
                    check(autofillType == View.AUTOFILL_TYPE_NONE && inputType == InputType.TYPE_NULL)
                    noneditableTarget = true
                }
                "native-hidden", "native-disabled" -> EditText(this).apply {
                    inputType = InputType.TYPE_CLASS_TEXT
                    hint = "Synthetic probe"
                }
                else -> username
            }
            if (focusTarget !== username) layout.addView(focusTarget)
            if (mode != "native-container") layout.addView(username)
            password?.let(layout::addView)
            layout.addView(Button(this).apply {
                text = "Request Autofill"
                setOnClickListener {
                    focusVerified = focusTarget.requestFocus()
                    request(focusTarget)
                }
            })
            if (positive) {
                layout.addView(Button(this).apply {
                    text = "Clear fields"
                    setOnClickListener {
                        username.text.clear()
                        password?.text?.clear()
                        result.text = "fieldsUnchanged=" + (username.text.isEmpty() && (password == null || password.text.isEmpty()))
                    }
                })
                layout.addView(Button(this).apply {
                    text = "Verify empty"
                    setOnClickListener {
                        result.text = "fieldsUnchanged=" + (username.text.isEmpty() && (password == null || password.text.isEmpty()))
                    }
                })
            }
            layout.addView(Button(this).apply {
                text = "Verify fill"
                setOnClickListener {
                    result.text = if (positive) {
                        "fillVerified=" + (username.text.toString() == "synthetic-user" &&
                            (password == null || password.text.toString() == "synthetic-only-not-secret"))
                    } else "fieldsUnchanged=" + (username.text.isEmpty() &&
                        (password == null || password.text.isEmpty()) &&
                        (if (mode == "native-container") focusTarget.text.toString() == "Synthetic label"
                         else focusTarget.text.isEmpty()))
                }
            })
        }
        layout.addView(result)
        layout.addView(evidence)
        setContentView(layout)
    }

    override fun onDestroy() {
        if (::autofillCallback.isInitialized) {
            getSystemService(AutofillManager::class.java).unregisterCallback(autofillCallback)
        }
        super.onDestroy()
    }
}
