package io.palladin.mobile.autofill

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent

internal fun completeAutoFillResult(owner: Activity, result: Intent) {
    check(!owner.isFinishing && !owner.isDestroyed)
    val originalTask = owner.taskId
    check(originalTask >= 0)
    // The live OS result owner supplies this task, never a package or Dart ID.
    // Backgrounding Main alone may resume Home instead of the original app.
    owner.getSystemService(ActivityManager::class.java).moveTaskToFront(originalTask, 0)
    owner.setResult(Activity.RESULT_OK, result)
    owner.finish()
}
