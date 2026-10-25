package io.palladin.mobile.autofill

import java.io.PrintWriter
import java.io.StringWriter
import org.junit.Assert.*
import org.junit.Test

class AutofillRequestDiagnosisTest {
    @Test fun `dump distinguishes skipped checks from rejection and acceptance`() {
        val initial = dump(AutofillRequestDiagnosis())
        assertTrue(initial.contains("result=NO_REQUEST"))
        assertTrue(initial.contains("cache=NOT_CHECKED"))
        val rejected = dump(AutofillRequestDiagnosis(
            result = RequestResult.REJECTED,
            passwordCount = 1,
            domains = DomainCount.ONE,
            origin = OriginStatus.UNVERIFIED,
        ))
        assertTrue(rejected.contains("origin=UNVERIFIED"))
        assertTrue(rejected.contains("cache=NOT_CHECKED"))
        val offered = dump(AutofillRequestDiagnosis(
            result = RequestResult.RESPONSE_OFFERED,
            cache = CheckAvailability.AVAILABLE,
            inlineRequestPresent = true,
        ))
        assertTrue(offered.contains("result=RESPONSE_OFFERED"))
        assertTrue(offered.contains("inlineRequestPresent=true"))
    }

    @Test fun `replacement for canceled request retains no prior metadata`() {
        var last = AutofillRequestDiagnosis(passwordCount = 99, domains = DomainCount.AMBIGUOUS,
            origin = OriginStatus.VERIFIED, cache = CheckAvailability.AVAILABLE)
        assertTrue(dump(last).contains("passwordCount=99"))
        last = AutofillRequestDiagnosis(result = RequestResult.CANCELED)
        assertTrue(dump(last).contains("passwordCount=0"))
        assertFalse(dump(last).contains("=VERIFIED"))
        assertFalse(dump(last).contains("=AVAILABLE"))
    }

    @Test fun `output contract allows only fixed keys and enum count boolean values`() {
        val allowedKeys = setOf("result", "passwordCount", "domains", "requestingPackagePresent",
            "origin", "generationSession", "cache", "inlineRequestPresent")
        val lines = dump(AutofillRequestDiagnosis()).trim().lines()
        assertEquals(allowedKeys, lines.map { it.substringBefore('=') }.toSet())
        lines.forEach { assertTrue(it.substringAfter('=').matches(Regex("[A-Z_]+|[0-9]+|true|false"))) }
    }

    private fun dump(value: AutofillRequestDiagnosis): String {
        val output = StringWriter()
        value.dump(PrintWriter(output))
        return output.toString()
    }
}
