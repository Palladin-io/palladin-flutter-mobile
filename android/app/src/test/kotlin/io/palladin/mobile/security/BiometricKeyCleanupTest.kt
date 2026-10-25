package io.palladin.mobile.security

import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class BiometricKeyCleanupTest {
    @Test fun removesOnlyBiometricKeyAndCiphertextAndIsIdempotent() {
        val root = Files.createTempDirectory("biometric-cleanup").toFile()
        try {
            val file = root.resolve("biometric_storage/palladin_vault_mk_v2.v2.txt")
            file.parentFile!!.mkdirs()
            file.writeText("dummy ciphertext")
            val unrelated = root.resolve("biometric_storage/other.v2.txt")
            unrelated.writeText("other")
            val aliases = mutableSetOf("_CM_palladin_vault_mk_v2_master_key", "other")
            val cleanup = BiometricKeyCleanup(root, { aliases.remove(it) }, { it in aliases })
            cleanup.clear()
            cleanup.clear()
            assertFalse(file.exists())
            assertEquals(setOf("other"), aliases)
            assertTrue(unrelated.exists())
        } finally { root.deleteRecursively() }
    }

    @Test fun failedKeyDeletionIsReportedAndCiphertextStillRemoved() {
        val root = Files.createTempDirectory("biometric-cleanup").toFile()
        try {
            val file = root.resolve("biometric_storage/palladin_vault_mk_v2.v2.txt")
            file.parentFile!!.mkdirs()
            file.writeText("dummy ciphertext")
            val cleanup = BiometricKeyCleanup(root, { throw IllegalStateException("locked store") }, { true })
            assertThrows(Exception::class.java) { cleanup.clear() }
            assertFalse(file.exists())
        } finally { root.deleteRecursively() }
    }
}
