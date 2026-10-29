package io.palladin.mobile.autofill

import android.app.PendingIntent
import android.graphics.BlendMode
import android.graphics.drawable.Icon
import androidx.autofill.inline.v1.InlineSuggestionUi
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

@android.annotation.TargetApi(30)
internal fun autofillInlineContent(
    context: Context,
    generate: Boolean,
    attribution: PendingIntent,
): InlineSuggestionUi.Content {
    val label = context.getString(
        if (generate) R.string.autofill_generate_prompt else R.string.autofill_unlock_label,
    )
    return InlineSuggestionUi.newContentBuilder(attribution)
        .setTitle(label)
        .setStartIcon(Icon.createWithResource(context, R.drawable.launch_logo_image).apply {
            setTintBlendMode(BlendMode.DST)
        })
        .setContentDescription(label)
        .build()
}

@android.annotation.TargetApi(30)
internal fun autofillInlineCredentialContent(
    context: Context,
    username: String,
    label: String,
    domain: String,
    attribution: PendingIntent,
): InlineSuggestionUi.Content = InlineSuggestionUi.newContentBuilder(attribution)
    .setTitle(username)
    .setSubtitle(domain)
    .setStartIcon(Icon.createWithResource(context, R.drawable.launch_logo_image).apply {
        setTintBlendMode(BlendMode.DST)
    })
    .setContentDescription(context.getString(R.string.autofill_credential_description, username, label, domain))
    .build()
