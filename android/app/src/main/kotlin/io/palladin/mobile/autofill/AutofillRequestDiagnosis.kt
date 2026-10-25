package io.palladin.mobile.autofill

import java.io.PrintWriter

internal enum class RequestResult { NO_REQUEST, CHECKING, CANCELED, NO_STRUCTURE, REJECTED, RESPONSE_OFFERED }
internal enum class DomainCount { NOT_CHECKED, ZERO, ONE, AMBIGUOUS }
internal enum class OriginStatus { NOT_CHECKED, QUERY_UNAVAILABLE, LINK_HANDLING_DISABLED, UNVERIFIED, VERIFIED }
internal enum class CheckAvailability { NOT_CHECKED, AVAILABLE, UNAVAILABLE }

/** No request identifiers or values may be retained in this service-local snapshot. */
internal data class AutofillRequestDiagnosis(
    val result: RequestResult = RequestResult.NO_REQUEST,
    val passwordCount: Int = 0,
    val domains: DomainCount = DomainCount.NOT_CHECKED,
    val requestingPackagePresent: Boolean = false,
    val origin: OriginStatus = OriginStatus.NOT_CHECKED,
    val generationSession: CheckAvailability = CheckAvailability.NOT_CHECKED,
    val cache: CheckAvailability = CheckAvailability.NOT_CHECKED,
    val inlineRequestPresent: Boolean = false,
) {
    fun dump(writer: PrintWriter) {
        writer.println("result=$result")
        writer.println("passwordCount=$passwordCount")
        writer.println("domains=$domains")
        writer.println("requestingPackagePresent=$requestingPackagePresent")
        writer.println("origin=$origin")
        writer.println("generationSession=$generationSession")
        writer.println("cache=$cache")
        writer.println("inlineRequestPresent=$inlineRequestPresent")
    }
}
