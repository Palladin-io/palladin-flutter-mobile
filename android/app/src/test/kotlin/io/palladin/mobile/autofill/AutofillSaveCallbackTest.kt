package io.palladin.mobile.autofill

import android.content.Context
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import io.palladin.mobile.R
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import android.view.autofill.AutofillId
import org.junit.Test
import org.mockito.Mockito.*

class AutofillSaveCallbackTest {
    @Test fun staleSaveFailureDoesNotDiscardReplacementRequest() {
        mockStatic(Looper::class.java).use {
            mockConstruction(Handler::class.java).use {
                val context = mock(Context::class.java)
                `when`(context.getString(R.string.autofill_save_unavailable)).thenReturn("Save unavailable")
                val state = mock(Bundle::class.java)
                `when`(state.getString(AutofillSaveCoordinator.EXTRA_REQUEST)).thenReturn("old-request")
                val save = mock(SaveRequest::class.java)
                `when`(save.clientState).thenReturn(state)
                val callback = mock(SaveCallback::class.java)
                // Install the metadata produced by prepare(B); Android still owns A's clientState.
                val requestType = Class.forName("io.palladin.mobile.autofill.AutofillSaveCoordinator\$Request")
                val constructor = requestType.declaredConstructors.single().apply { isAccessible = true }
                val replacement = constructor.newInstance("new-request", "session",
                    AutofillSaveSource("synthetic.package", setOf("signature"),
                        AutofillOriginMode.VERIFIED_NATIVE, setOf("fixture.invalid"), emptySet<String>()),
                    AutofillSaveFields(mock(AutofillId::class.java), mock(AutofillId::class.java)), 0L)
                val requestField = AutofillSaveCoordinator::class.java.getDeclaredField("request").apply { isAccessible = true }
                requestField.set(AutofillSaveCoordinator, replacement)
                try {
                    AutofillSaveCoordinator.save(context, save, callback)
                    verify(callback).onFailure("Save unavailable")
                    verifyNoMoreInteractions(callback)
                    assertSame(replacement, requestField.get(AutofillSaveCoordinator))
                    `when`(state.getString(AutofillSaveCoordinator.EXTRA_REQUEST)).thenReturn(null)
                    AutofillSaveCoordinator.save(context, save, callback)
                    assertSame(replacement, requestField.get(AutofillSaveCoordinator))
                    `when`(state.getString(AutofillSaveCoordinator.EXTRA_REQUEST)).thenReturn("new-request")
                    AutofillSaveCoordinator.save(context, save, callback)
                    assertNull(requestField.get(AutofillSaveCoordinator))
                    verify(callback, times(3)).onFailure("Save unavailable")
                    verifyNoMoreInteractions(callback)
                } finally {
                    AutofillSaveCoordinator.clear()
                }
            }
        }
    }

    @Test fun rejectedDeferredSaveNeverReportsSuccess() {
        mockStatic(Looper::class.java).use {
            mockConstruction(Handler::class.java).use {
                val context = mock(Context::class.java)
                `when`(context.getString(R.string.autofill_save_unavailable)).thenReturn("Save unavailable")
                val callback = mock(SaveCallback::class.java)
                AutofillSaveCoordinator.save(context, mock(SaveRequest::class.java), callback)
                verify(callback).onFailure("Save unavailable")
                verifyNoMoreInteractions(callback)
            }
        }
    }
}
