package io.palladin.mobile.security

import java.io.File

/** Deletes the biometric_storage 5.x MK copy without reading or authenticating it. */
internal class BiometricKeyCleanup(
    private val filesDir: File,
    private val deleteAlias: (String) -> Unit,
    private val containsAlias: (String) -> Boolean,
) {
    fun clear() {
        val alias = "_CM_palladin_vault_mk_v2_master_key"
        val file = File(filesDir, "biometric_storage/palladin_vault_mk_v2.v2.txt")
        val keyResult = runCatching {
            deleteAlias(alias)
            check(!containsAlias(alias)) { "Biometric key deletion failed" }
        }
        val fileResult = runCatching {
            check(!file.exists() || file.delete()) { "Biometric ciphertext deletion failed" }
        }
        keyResult.getOrThrow()
        fileResult.getOrThrow()
    }
}
