package io.palladin.mobile.autofill

import org.junit.Assert.*
import org.junit.Test

class CredentialAssociationProofsTest {
    @Test fun proofExpiresAndNeverTransfersAcrossHostPackageOrSigner() {
        var now = 100L
        val proofs = CredentialAssociationProofs { now }
        val key = CredentialAssociationKey("www.example.com", "example.app", setOf("current"))
        assertFalse(proofs.contains(key))
        proofs.accept(key)
        assertTrue(proofs.contains(key))
        assertFalse(proofs.contains(key.copy(host = "accounts.example.com")))
        assertFalse(proofs.contains(key.copy(packageName = "other.app")))
        assertFalse(proofs.contains(key.copy(signers = setOf("rotated"))))
        now += 60_000
        assertFalse(proofs.contains(key))
    }

    @Test fun boundedProofsEvictOldestAndIgnoreBackwardClock() {
        var now = 100L
        val proofs = CredentialAssociationProofs { now }
        val key = CredentialAssociationKey("example.com", "example.app", setOf("signer"))
        repeat(33) { proofs.accept(key.copy(host = "$it.example.com")) }
        assertFalse(proofs.contains(key.copy(host = "0.example.com")))
        assertTrue(proofs.contains(key.copy(host = "32.example.com")))
        now = 99
        assertFalse(proofs.contains(key.copy(host = "32.example.com")))
    }
}
