package io.palladin.mobile.autofill

internal data class CredentialAssociationKey(val host: String, val packageName: String, val signers: Set<String>)

internal class CredentialAssociationProofs(private val now: () -> Long) {
    private val accepted = LinkedHashMap<CredentialAssociationKey, Long>()

    @Synchronized fun accept(key: CredentialAssociationKey) {
        if (key.signers.isEmpty()) return
        val immutable = key.copy(signers = key.signers.toSet())
        accepted.remove(immutable)
        accepted[immutable] = now()
        while (accepted.size > 32) accepted.remove(accepted.keys.first())
    }

    @Synchronized fun contains(key: CredentialAssociationKey): Boolean {
        val issued = accepted[key] ?: return false
        val age = now() - issued
        if (age !in 0 until 60_000) { accepted.remove(key); return false }
        return true
    }
}
