package io.palladin.autofill.form

import android.app.Activity
import android.os.Bundle
import android.graphics.Rect
import android.util.SparseArray
import android.view.View
import android.view.ViewStructure
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.Button
import android.widget.LinearLayout
import java.io.File

/** Deterministic virtual fields using the same public contract as a WebView. */
class VirtualSessionProbe : Activity() {
    private var stops = 0
    override fun onStop() {
        super.onStop()
        stops++
        File(filesDir, "virtual-lifecycle").writeText("stopped=true;stops=$stops")
    }
    override fun onResume() {
        super.onResume()
        File(filesDir, "virtual-lifecycle").writeText("stopped=false;stops=$stops")
    }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val field = VirtualField()
        setContentView(LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            addView(field, LinearLayout.LayoutParams(-1, 300))
            addView(Button(this@VirtualSessionProbe).apply {
                text = "Next password step"
                setOnClickListener { field.password = true; field.enter() }
            })
        })
        File(filesDir, "virtual-fill").writeText("pending")
        field.postDelayed({ field.enter() }, 500)
    }
    inner class VirtualField : View(this@VirtualSessionProbe) {
        var password = false
        init { importantForAutofill = IMPORTANT_FOR_AUTOFILL_YES; isFocusable = true; isFocusableInTouchMode = true }
        private val child get() = if(password) 2 else 1
        fun enter() {
            requestFocus()
            val activityManager = getSystemService(AutofillManager::class.java)
            val selectedManager = if (intent.getBooleanExtra("applicationContextManager", false))
                applicationContext.getSystemService(AutofillManager::class.java) else activityManager
            File(filesDir, "virtual-manager").writeText("sameManager=${selectedManager === activityManager}")
            selectedManager.notifyViewEntered(this, child, Rect(30,60,600,160))
        }
        override fun onProvideAutofillVirtualStructure(structure: ViewStructure, flags: Int) {
            super.onProvideAutofillVirtualStructure(structure, flags)
            structure.setChildCount(1)
            structure.newChild(0).apply {
                setAutofillId(this@VirtualField.autofillId, child)
                setClassName("android.widget.EditText")
                setDimens(0,0,0,0,600,100)
                setVisibility(VISIBLE); setEnabled(true); setFocusable(true); setFocused(true)
                setAutofillType(AUTOFILL_TYPE_TEXT)
                setInputType(if(password) 129 else 33)
                setAutofillHints(arrayOf(if(password) AUTOFILL_HINT_PASSWORD else AUTOFILL_HINT_USERNAME))
                setAutofillValue(AutofillValue.forText(""))
            }
        }
        override fun autofill(values: SparseArray<AutofillValue>) {
            val valid = password && values.size()==1 && values.keyAt(0)==2 && values.valueAt(0).textValue?.toString()=="synthetic-only-not-secret"
            File(filesDir, "virtual-fill").writeText("verified=$valid;count=${values.size()}")
        }
    }
}
