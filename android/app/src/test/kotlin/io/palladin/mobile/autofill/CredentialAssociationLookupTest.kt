package io.palladin.mobile.autofill

import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.*
import org.junit.Test

class CredentialAssociationLookupTest {
    private val key = CredentialAssociationKey("example.com", "example.app", setOf("signer"))

    @Test fun canceledAndTimedOutLookupsCannotPublishLateSuccess() {
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val values = Collections.synchronizedList(mutableListOf<Boolean>())
        val result = CountDownLatch(1)
        val lookup = CredentialAssociationLookup({ _, _ ->
            entered.countDown()
            while (release.count > 0) try { release.await() } catch (_: InterruptedException) { }
            true
        }, deadlineMs = 50)
        try {
            val cancel = lookup.submit(key) { allowed -> values += allowed; result.countDown() }
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            assertTrue(result.await(1, TimeUnit.SECONDS))
            cancel()
            release.countDown()
            awaitBothWorkersIdle()
            assertEquals(listOf(false), values.toList())
        } finally { release.countDown() }
    }

    @Test fun queuedRequestsAlsoExpireWhenBothDnsWorkersIgnoreCancellation() {
        val entered = CountDownLatch(2)
        val release = CountDownLatch(1)
        val results = CountDownLatch(4)
        val executed = AtomicInteger()
        val values = Collections.synchronizedList(mutableListOf<Boolean>())
        val lookup = CredentialAssociationLookup({ _, _ ->
            executed.incrementAndGet(); entered.countDown()
            while (release.count > 0) try { release.await() } catch (_: InterruptedException) { }
            true
        }, deadlineMs = 200)
        val cancels = mutableListOf<() -> Unit>()
        try {
            repeat(2) { cancels += lookup.submit(key) { values += it; results.countDown() } }
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            repeat(2) { cancels += lookup.submit(key) { values += it; results.countDown() } }
            assertTrue(results.await(1, TimeUnit.SECONDS))
            assertEquals(2, executed.get())
            release.countDown()
            cancels.forEach { it() }
            awaitBothWorkersIdle()
            assertEquals(List(4) { false }, values.toList())
        } finally { release.countDown(); cancels.forEach { it() } }
    }

    @Test fun totalWorkerAndQueueAdmissionRemainBounded() {
        val entered = CountDownLatch(2)
        val release = CountDownLatch(1)
        val rejected = CountDownLatch(1)
        val rejectedValues = Collections.synchronizedList(mutableListOf<Boolean>())
        val lookup = CredentialAssociationLookup({ _, _ ->
            entered.countDown(); release.await(); true
        }, deadlineMs = 2000)
        val cancels = mutableListOf<() -> Unit>()
        try {
            repeat(2) { cancels += lookup.submit(key) {} }
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            repeat(2) { cancels += lookup.submit(key) {} }
            cancels += lookup.submit(key) { rejectedValues += it; rejected.countDown() }
            assertTrue(rejected.await(1, TimeUnit.SECONDS))
            assertEquals(listOf(false), rejectedValues.toList())
        } finally { cancels.forEach { it() }; release.countDown() }
    }
    private fun awaitBothWorkersIdle() {
        val entered = CountDownLatch(2)
        val release = CountDownLatch(1)
        val finished = CountDownLatch(2)
        val barrier = CredentialAssociationLookup({ _, _ ->
            entered.countDown()
            release.await()
            false
        }, deadlineMs = 2000)
        val cancels = List(2) { barrier.submit(key) { finished.countDown() } }
        try {
            // Both workers must leave the old fetch/finish path before either can pass this barrier.
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            release.countDown()
            assertTrue(finished.await(1, TimeUnit.SECONDS))
        } finally { release.countDown(); cancels.forEach { it() } }
    }

}
