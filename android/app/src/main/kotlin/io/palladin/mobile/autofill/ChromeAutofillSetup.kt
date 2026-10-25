package io.palladin.mobile.autofill

import android.content.Context
import android.content.Intent
import android.net.Uri

internal class ChromeAutofillSetup(private val queryMode: () -> Int?) {
    constructor(context: Context) : this({
        val uri = Uri.parse(
            "content://com.android.chrome.AutofillThirdPartyModeContentProvider/autofill_third_party_mode",
        )
        context.contentResolver.query(uri, arrayOf(STATE_COLUMN), null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) null else {
                val index = cursor.getColumnIndex(STATE_COLUMN)
                if (index < 0 || cursor.isNull(index)) null else cursor.getInt(index)
            }
        }
    })

    fun status(): String = try {
        when (queryMode()) {
            0 -> "disabled"
            1 -> "enabled"
            null -> "unavailable"
            else -> "unknown"
        }
    } catch (_: Exception) {
        "unknown"
    }

    companion object {
        private const val STATE_COLUMN = "autofill_third_party_state"

        fun settingsIntent(): Intent = Intent(Intent.ACTION_APPLICATION_PREFERENCES).apply {
            addCategory(Intent.CATEGORY_DEFAULT)
            addCategory(Intent.CATEGORY_APP_BROWSER)
            addCategory(Intent.CATEGORY_PREFERENCE)
            setPackage("com.android.chrome")
        }
    }
}
