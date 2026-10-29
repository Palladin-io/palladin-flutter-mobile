package io.palladin.mobile.autofill

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.autofill.Dataset
import android.view.inputmethod.InlineSuggestionsRequest
import android.service.autofill.InlinePresentation
import android.widget.RemoteViews
import android.widget.inline.InlinePresentationSpec
import androidx.autofill.inline.UiVersions
import io.palladin.mobile.MainActivity

private const val EXTRA_INLINE_SPECS = "palladin.autofill.inline_specs"
private const val EXTRA_INLINE_CAPACITY = "palladin.autofill.inline_capacity"
private const val MAX_INLINE_SPECS = 32

internal fun selectAutofillInlineSpec(
    specs: List<InlinePresentationSpec>,
    capacity: Int,
    index: Int,
    sdkInt: Int,
): InlinePresentationSpec? {
    if (sdkInt < Build.VERSION_CODES.R || specs.isEmpty() || specs.size > MAX_INLINE_SPECS ||
        capacity < specs.size || index < 0 || index >= capacity
    ) return null
    // The public request contract reuses the final spec for remaining positions.
    val spec = specs[minOf(index, specs.lastIndex)]
    return spec.takeIf {
        runCatching { UiVersions.INLINE_UI_VERSION_1 in UiVersions.getVersions(it.style) }.getOrDefault(false)
    }
}

internal fun carryAutofillInlineRequest(intent: Intent, request: InlineSuggestionsRequest?) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
    val inline = request ?: return
    val specs = inline.inlinePresentationSpecs
    if (specs.isEmpty() || specs.size > MAX_INLINE_SPECS || inline.maxSuggestionCount < specs.size) return
    // Copy only presentation metadata into our immutable explicit PendingIntent.
    // The IME token, package, extras and any credential values are not propagated.
    intent.putParcelableArrayListExtra(EXTRA_INLINE_SPECS, ArrayList(specs))
    intent.putExtra(EXTRA_INLINE_CAPACITY, inline.maxSuggestionCount)
}

internal fun authenticatedAutofillDataset(
    context: Context,
    request: Intent,
    dropdown: RemoteViews,
    username: String,
    label: String,
    domain: String,
    index: Int = 0,
): Dataset.Builder {
    val builder = Dataset.Builder(dropdown)
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return builder
    // Malformed/unsupported presentation metadata cannot suppress the dropdown.
    val inline = runCatching {
        val specs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            request.getParcelableArrayListExtra(EXTRA_INLINE_SPECS, InlinePresentationSpec::class.java)
        } else {
            @Suppress("DEPRECATION")
            request.getParcelableArrayListExtra<InlinePresentationSpec>(EXTRA_INLINE_SPECS)
        }.orEmpty()
        val spec = selectAutofillInlineSpec(
            specs, request.getIntExtra(EXTRA_INLINE_CAPACITY, 0), index, Build.VERSION.SDK_INT,
        ) ?: return@runCatching null
        val attribution = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val content = autofillInlineCredentialContent(context, username, label, domain, attribution)
        InlinePresentation(content.slice, spec, false)
    }.getOrNull()
    if (inline != null) builder.setInlinePresentation(inline)
    return builder
}
