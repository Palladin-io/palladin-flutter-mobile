package io.palladin.mobile.autofill

import android.content.Context
import android.widget.RemoteViews
import io.palladin.mobile.R

internal fun autofillPresentation(context: Context, label: String): RemoteViews =
    RemoteViews(context.packageName, R.layout.autofill_unlock_prompt).apply {
        setTextViewText(R.id.autofill_unlock_label, label)
    }
