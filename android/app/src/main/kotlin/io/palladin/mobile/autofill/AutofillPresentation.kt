package io.palladin.mobile.autofill

import android.content.Context
import android.widget.RemoteViews
import android.view.View
import io.palladin.mobile.R

internal fun autofillPresentation(context: Context, label: String): RemoteViews =
    RemoteViews(context.packageName, R.layout.autofill_unlock_prompt).apply {
        setTextViewText(R.id.autofill_unlock_label, label)
    }

internal fun autofillCredentialPresentation(
    context: Context,
    username: String,
    label: String,
    domain: String,
): RemoteViews = RemoteViews(context.packageName, R.layout.autofill_credential_row).apply {
    setTextViewText(R.id.autofill_credential_username, username)
    val showLabel = label.isNotBlank() &&
        !label.trim().equals(username.trim(), ignoreCase = true) &&
        !label.trim().equals(domain, ignoreCase = true)
    setViewVisibility(R.id.autofill_credential_label, if (showLabel) View.VISIBLE else View.GONE)
    if (showLabel) setTextViewText(R.id.autofill_credential_label, label)
    setTextViewText(R.id.autofill_credential_domain, domain)
}
