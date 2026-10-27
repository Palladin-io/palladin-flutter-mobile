package io.palladin.mobile

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import android.text.TextUtils
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import io.palladin.mobile.autofill.autofillCredentialPresentation
import io.palladin.mobile.autofill.autofillInlineContent
import io.palladin.mobile.autofill.autofillPresentation
import java.util.Locale

/** Debug-only rendered assertions and screenshot surface, using synthetic values only. */
class PresentationPreviewActivity : Activity() {
 override fun onCreate(state: Bundle?) {
  super.onCreate(state)
  val language = intent.getStringExtra("language") ?: "en"
  require(language in setOf("en", "pl"))
  val night = intent.getBooleanExtra("night", false)
  val config = Configuration(resources.configuration).apply {
   setLocale(Locale.forLanguageTag(language))
   uiMode = (uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
    if (night) Configuration.UI_MODE_NIGHT_YES else Configuration.UI_MODE_NIGHT_NO
   fontScale = 1.3f
  }
  val context = createConfigurationContext(config)
  val root = LinearLayout(context).apply {
   orientation = LinearLayout.VERTICAL
   setPadding(24, 120, 24, 24)
   setBackgroundColor(context.getColor(R.color.autofill_prompt_background))
  }
  val expectedUnlock = if (language == "pl") "Odblokuj Palladin, aby uzupełnić dane" else "Unlock Palladin to autofill"
  val expectedGenerate = if (language == "pl") "Wygeneruj silne hasło w Palladin" else "Generate a strong password with Palladin"
  val attribution = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
  for ((generate, expected) in listOf(false to expectedUnlock, true to expectedGenerate)) {
   val inline = autofillInlineContent(context, generate, attribution)
   check(inline.title.toString() == expected)
   check(inline.contentDescription.toString() == expected)
   check(inline.startIcon != null && inline.isValid)
   val row = autofillPresentation(context, expected).apply(context, root)
   val title = row.findViewById<TextView>(R.id.autofill_unlock_label)
   check(title.text.toString() == expected && title.ellipsize == TextUtils.TruncateAt.END)
   root.addView(row)
  }
  val username = "synthetic.long.username.for.ellipsis@example.invalid"
  val label = "Synthetic long credential label for large-font and ellipsis verification"
  val host = "exact.synthetic.fixture.invalid"
  val row = autofillCredentialPresentation(context, username, label, host).apply(context, root)
  for ((id, expected) in listOf(R.id.autofill_credential_username to username, R.id.autofill_credential_label to label, R.id.autofill_credential_domain to host)) {
   val text = row.findViewById<TextView>(id)
   check(text.text.toString() == expected)
   check(text.maxLines == 1 && text.ellipsize == TextUtils.TruncateAt.END)
  }
  check(row.findViewById<View>(R.id.autofill_credential_brand).importantForAccessibility == View.IMPORTANT_FOR_ACCESSIBILITY_NO)
  root.addView(row)
  for (duplicate in listOf(username, host, "")) {
   val compact = autofillCredentialPresentation(context, username, duplicate, host).apply(context, root)
   check(compact.findViewById<View>(R.id.autofill_credential_label).visibility == View.GONE)
  }
  root.addView(TextView(context).apply {
   text = "presentationVerified=true $language night=$night"
   setTextColor(context.getColor(R.color.autofill_prompt_text))
  })
  setContentView(root)
 }
}
