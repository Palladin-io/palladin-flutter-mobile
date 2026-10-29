package io.palladin.mobile.autofill

import android.os.Bundle
import android.widget.inline.InlinePresentationSpec
import androidx.autofill.inline.UiVersions
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.mockStatic
import org.mockito.Mockito.`when`

class AutofillInlinePresentationTest {
    @Test
    fun keepsOriginalPositionAndReusesLastSpecOnlyWithinImeCapacity() {
        val first = mock(InlinePresentationSpec::class.java)
        val second = mock(InlinePresentationSpec::class.java)
        val style = mock(Bundle::class.java)
        `when`(first.style).thenReturn(style)
        `when`(second.style).thenReturn(style)
        mockStatic(UiVersions::class.java).use { versions ->
            versions.`when`<List<String>> { UiVersions.getVersions(style) }
                .thenReturn(listOf(UiVersions.INLINE_UI_VERSION_1))
            assertSame(first, selectAutofillInlineSpec(listOf(first, second), 3, 0, 30))
            assertSame(second, selectAutofillInlineSpec(listOf(first, second), 3, 1, 30))
            assertSame(second, selectAutofillInlineSpec(listOf(first, second), 3, 2, 30))
            assertNull(selectAutofillInlineSpec(listOf(first, second), 3, 3, 30))
        }
    }

    @Test
    fun unsupportedSlotDoesNotBorrowAnotherSlotsStyle() {
        val supported = mock(InlinePresentationSpec::class.java)
        val unsupported = mock(InlinePresentationSpec::class.java)
        val v1 = mock(Bundle::class.java)
        val unknown = mock(Bundle::class.java)
        `when`(supported.style).thenReturn(v1)
        `when`(unsupported.style).thenReturn(unknown)
        mockStatic(UiVersions::class.java).use { versions ->
            versions.`when`<List<String>> { UiVersions.getVersions(v1) }
                .thenReturn(listOf(UiVersions.INLINE_UI_VERSION_1))
            versions.`when`<List<String>> { UiVersions.getVersions(unknown) }.thenReturn(emptyList())
            assertNull(selectAutofillInlineSpec(listOf(unsupported, supported), 2, 0, 30))
            assertSame(supported, selectAutofillInlineSpec(listOf(unsupported, supported), 2, 1, 30))
        }
    }

    @Test
    fun malformedStyleRetainsDropdownInsteadOfCrashingRequest() {
        val spec = mock(InlinePresentationSpec::class.java)
        `when`(spec.style).thenThrow(IllegalArgumentException("synthetic malformed style"))
        assertNull(selectAutofillInlineSpec(listOf(spec), 1, 0, 30))
    }

    @Test
    fun unavailableOrMalformedRequestsKeepDropdownFallback() {
        val spec = mock(InlinePresentationSpec::class.java)
        assertNull(selectAutofillInlineSpec(listOf(spec), 1, 0, 29))
        assertNull(selectAutofillInlineSpec(emptyList(), 1, 0, 30))
        assertNull(selectAutofillInlineSpec(listOf(spec), 0, 0, 30))
        assertNull(selectAutofillInlineSpec(listOf(spec), -1, 0, 30))
        assertNull(selectAutofillInlineSpec(listOf(spec), 1, -1, 30))
        assertNull(selectAutofillInlineSpec(listOf(spec, spec), 1, 0, 30))
        assertNull(selectAutofillInlineSpec(List(33) { spec }, 33, 0, 30))
    }
}
