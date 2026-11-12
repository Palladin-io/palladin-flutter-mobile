package io.palladin.mobile.autofill

import android.app.Activity
import android.app.ActivityManager
import android.content.Intent
import org.junit.Assert.*
import org.junit.Test
import org.mockito.Mockito.*

class AutoFillResultReturnTest {
    @Test fun `restore exact live owner task before delivering result once`() {
        val owner = mock(Activity::class.java)
        val tasks = mock(ActivityManager::class.java)
        val result = mock(Intent::class.java)
        `when`(owner.taskId).thenReturn(47)
        `when`(owner.getSystemService(ActivityManager::class.java)).thenReturn(tasks)
        completeAutoFillResult(owner, result)
        val order = inOrder(tasks, owner)
        order.verify(tasks).moveTaskToFront(47, 0)
        order.verify(owner).setResult(Activity.RESULT_OK, result)
        order.verify(owner).finish()
        verify(owner, never()).moveTaskToBack(anyBoolean())
    }
    @Test fun `reorder failure never reports success or finishes original result owner`() {
        val owner = mock(Activity::class.java)
        val tasks = mock(ActivityManager::class.java)
        `when`(owner.taskId).thenReturn(47)
        `when`(owner.getSystemService(ActivityManager::class.java)).thenReturn(tasks)
        doThrow(SecurityException()).`when`(tasks).moveTaskToFront(47, 0)
        try { completeAutoFillResult(owner, mock(Intent::class.java)); fail("Reorder accepted") } catch (_: SecurityException) {}
        verify(owner, never()).setResult(eq(Activity.RESULT_OK), any(Intent::class.java))
        verify(owner, never()).finish()
    }
    @Test fun `destroyed owner cannot reorder or deliver`() {
        val owner = mock(Activity::class.java)
        `when`(owner.isDestroyed).thenReturn(true)
        try { completeAutoFillResult(owner, mock(Intent::class.java)); fail("Destroyed owner accepted") } catch (_: IllegalStateException) {}
        verify(owner, never()).getSystemService(ActivityManager::class.java)
        verify(owner, never()).finish()
    }
}
