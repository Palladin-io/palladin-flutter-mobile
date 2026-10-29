package io.palladin.mobile

import org.junit.Assert.*
import org.junit.Test

class SyntheticFailureEvidenceTest {
    @Test fun excludesMessagesValuesAndFileNamesAndBoundsFrames() {
        val failure = IllegalStateException("PASSWORD=never-export-this")
        failure.stackTrace = Array(80) { StackTraceElement("test.Safe", "call", "SECRET_FILE", 12) }
        val report = syntheticFailureEvidence(List(50) { "RESULT_STARTED" }, failure)
        val encoded = report.toString()
        assertFalse(encoded.contains("never-export"))
        assertFalse(encoded.contains("SECRET_FILE"))
        assertEquals(16, report.getJSONArray("phases").length())
        assertEquals(12, report.getJSONArray("frames").length())
        assertEquals("java.lang.IllegalStateException", report.getString("exceptionClass"))
    }

    @Test fun malformedMetadataCannotIntroduceArbitraryText() {
        val failure = IllegalArgumentException("private message")
        failure.stackTrace = arrayOf(StackTraceElement("private value!", "x".repeat(500), "secret", 1))
        val encoded = syntheticFailureEvidence(listOf("private phase", "CREATED"), failure).toString()
        assertFalse(encoded.contains("private"))
        assertFalse(encoded.contains("x".repeat(500)))
        assertTrue(encoded.contains("CREATED"))
    }

    @Test fun failedCaptureStillDelegatesOriginalException() {
        val failure = IllegalStateException("private")
        var delegated: Throwable? = null
        val prior = Thread.UncaughtExceptionHandler { _, error -> delegated = error }
        val handler = syntheticFailureHandler(prior) { throw IllegalArgumentException("write failed") }
        handler.uncaughtException(Thread.currentThread(), failure)
        assertSame(failure, delegated)
    }
    @Test fun causesAreBoundedAndNeverExportMessagesOrFileNames() {
        var failure: Throwable = IllegalArgumentException("inner secret")
        repeat(8) {
            failure = IllegalStateException("outer secret", failure).also {
                it.stackTrace = arrayOf(StackTraceElement("test.Safe", "call", "SECRET_CAUSE_FILE", 1))
            }
        }
        val report = syntheticFailureEvidence(emptyList(), failure)
        assertEquals(2, report.getJSONArray("causes").length())
        assertFalse(report.toString().contains("secret"))
        assertFalse(report.toString().contains("SECRET_CAUSE_FILE"))
        val first = IllegalStateException("cycle secret")
        val second = IllegalArgumentException("cycle secret")
        first.initCause(second)
        second.initCause(first)
        assertEquals(1, syntheticFailureEvidence(emptyList(), first).getJSONArray("causes").length())
    }

}
