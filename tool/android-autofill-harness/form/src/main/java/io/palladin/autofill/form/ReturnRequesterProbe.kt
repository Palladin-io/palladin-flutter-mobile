package io.palladin.autofill.form

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.TextView
import java.io.File

class ReturnRequesterProbe : Activity() {
    private var received = 0
    private lateinit var passwordId: android.view.autofill.AutofillId
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        setContentView(TextView(this).apply { text = "Synthetic original requester" })
        File(filesDir, "return-result").writeText("pending")
        passwordId = android.widget.EditText(this).autofillId
        startActivityForResult(Intent().setClassName("io.palladin.autofill.harness.provider", "io.palladin.mobile.ReturnSourceProbe").putExtra("passwordOnly", intent.getBooleanExtra("passwordOnly", false)).putExtra("passwordId", passwordId).putExtra("homeBehindPicker", intent.getBooleanExtra("homeBehindPicker", false)), 7)
    }
    override fun onActivityResult(request: Int, result: Int, data: Intent?) {
        super.onActivityResult(request, result, data)
        received++
        val payloadVerified = if (intent.getBooleanExtra("passwordOnly", false)) {
            val dataset = data?.getParcelableExtra(android.view.autofill.AutofillManager.EXTRA_AUTHENTICATION_RESULT, android.service.autofill.Dataset::class.java)
            val ids = dataset?.javaClass?.getMethod("getFieldIds")?.invoke(dataset) as? List<*>
            val values = dataset?.javaClass?.getMethod("getFieldValues")?.invoke(dataset) as? List<*>
            ids == listOf(passwordId) && values?.size == 1 &&
                (values.single() as? android.view.autofill.AutofillValue)?.textValue?.toString() == "synthetic-only-not-secret" &&
                data.getBooleanExtra(android.view.autofill.AutofillManager.EXTRA_AUTHENTICATION_RESULT_EPHEMERAL_DATASET, false)
        } else data?.getBooleanExtra("syntheticResult", false) == true
        File(filesDir, "return-result").writeText("verified=${request == 7 && result == RESULT_OK && payloadVerified};count=$received")
    }
}
