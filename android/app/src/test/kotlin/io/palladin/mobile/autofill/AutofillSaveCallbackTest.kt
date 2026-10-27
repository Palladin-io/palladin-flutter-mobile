package io.palladin.mobile.autofill

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.service.autofill.SaveCallback
import android.service.autofill.SaveRequest
import io.palladin.mobile.R
import org.junit.Test
import org.mockito.Mockito.*

class AutofillSaveCallbackTest {
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
