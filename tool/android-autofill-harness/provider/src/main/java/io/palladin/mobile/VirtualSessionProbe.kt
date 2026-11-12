package io.palladin.mobile

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import android.os.CancellationSignal
import android.service.autofill.*
import android.view.autofill.AutofillId
import android.widget.RemoteViews
import io.palladin.mobile.autofill.PalladinAutofillService
import io.palladin.mobile.autofill.sourceAutofillResult
import io.palladin.mobile.autofill.completeAutoFillResult
import java.io.File

/** Isolated synthetic service: never installed or selected on a physical device. */
class VirtualSessionProbeService : AutofillService() {
    override fun onFillRequest(request: FillRequest, signal: CancellationSignal, callback: FillCallback) {
        val structure = request.fillContexts.last().structure
        if (structure.activityComponent?.packageName != "io.palladin.autofill.harness.form") {
            callback.onSuccess(null); return
        }
        val fields = PalladinAutofillService.CredentialFieldIds.from(structure)
        File(filesDir, "virtual-session-request").writeText("contexts=${request.fillContexts.size};username=${fields.usernameIds.size};password=${fields.passwordIds.size}")
        if (fields.allIds.isEmpty()) { callback.onSuccess(null); return }
        val route = Intent(this, VirtualSessionProbeAuth::class.java)
            .putParcelableArrayListExtra("usernames", ArrayList(fields.usernameIds))
            .putParcelableArrayListExtra("passwords", ArrayList(fields.passwordIds))
        val pending = PendingIntent.getActivity(this, request.id, route, PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val row = RemoteViews(packageName, android.R.layout.simple_list_item_1).apply { setTextViewText(android.R.id.text1, "Synthetic unlock") }
        val dataset = Dataset.Builder(row).setAuthentication(pending.intentSender)
        fields.allIds.forEach { dataset.setValue(it, null) }
        callback.onSuccess(FillResponse.Builder().addDataset(dataset.build()).build())
    }
    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) { callback.onFailure("Synthetic only") }
}
class VirtualSessionProbeAuth : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        if (File(filesDir, "virtual-session-trampoline").exists()) {
            VirtualSessionProbePicker.owner = this
            startActivity(Intent(this, VirtualSessionProbePicker::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } else setContentView(android.widget.Button(this).apply {
            text = "Select synthetic credential"
            setOnClickListener { finishSynthetic() }
        })
    }
    fun finishSynthetic() {
        val usernames = intent.getParcelableArrayListExtra("usernames", AutofillId::class.java).orEmpty()
        val passwords = intent.getParcelableArrayListExtra("passwords", AutofillId::class.java).orEmpty()
        val result = sourceAutofillResult(this, intent, usernames, passwords, true, "synthetic-user", "synthetic-only-not-secret", "fixture.invalid")
        if (File(filesDir, "virtual-session-trampoline").exists()) completeAutoFillResult(this, result)
        else { setResult(RESULT_OK, result); finish() }
    }
}
class VirtualSessionProbePicker : Activity() {
    companion object { var owner: VirtualSessionProbeAuth? = null }
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        setContentView(android.widget.Button(this).apply {
            text = "Select synthetic credential"
            setOnClickListener { val original = owner; owner = null; original?.finishSynthetic() }
        })
    }
}
