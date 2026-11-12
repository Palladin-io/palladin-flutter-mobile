package io.palladin.mobile

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.TextView
import io.palladin.mobile.autofill.completeAutoFillResult
import io.palladin.mobile.autofill.sourceAutofillResult
import java.io.File

/** Disposable emulator probe: no account, credentials or Autofill bypass. */
class ReturnSourceProbe : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        ReturnPickerProbe.owner = this
        val tasks = getSystemService(ActivityManager::class.java).appTasks
        File(filesDir, "return-app-task-owner").writeText(tasks.any { it.taskInfo?.taskId == taskId }.toString())
        val route = Intent(this, ReturnPickerProbe::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra("completeReturn", true)
        val task = tasks.firstOrNull { it.taskInfo?.baseIntent?.component?.className == ReturnPickerProbe::class.java.name }
        if (task == null) startActivity(route.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        else {
            task.startActivity(this, route, null)
            // Synthetic second layout: explicitly put Home behind the picker,
            // as observed on Samsung after reusing the app task.
            if (intent.getBooleanExtra("homeBehindPicker", false)) {
                getSystemService(ActivityManager::class.java).moveTaskToFront(requireNotNull(task.taskInfo).taskId, ActivityManager.MOVE_TASK_WITH_HOME)
            }
        }
    }
}
class ReturnPickerProbe : Activity() {
    companion object { var owner: ReturnSourceProbe? = null }
    override fun onCreate(state: Bundle?) { super.onCreate(state); setContentView(TextView(this).apply { text = "Synthetic picker" }); completeIfRequested(intent) }
    override fun onNewIntent(value: Intent) { super.onNewIntent(value); completeIfRequested(value) }
    private fun completeIfRequested(value: Intent) {
        if (!value.getBooleanExtra("completeReturn", false)) return
        Handler(Looper.getMainLooper()).postDelayed({
            val original = owner ?: return@postDelayed
            owner = null
            val result = if (original.intent.getBooleanExtra("passwordOnly", false)) {
                val id = requireNotNull(original.intent.getParcelableExtra("passwordId", android.view.autofill.AutofillId::class.java))
                sourceAutofillResult(original, original.intent, emptyList(), listOf(id), true,
                    "synthetic-user", "synthetic-only-not-secret", "fixture.invalid")
            } else Intent().putExtra("syntheticResult", true)
            completeAutoFillResult(original, result)
        }, 300)
    }
}
