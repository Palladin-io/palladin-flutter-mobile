package io.palladin.mobile

import android.content.Context
import android.os.SystemClock
import io.palladin.mobile.autofill.AutofillOriginVerifier
import io.palladin.mobile.autofill.CredentialAssociationIdentity
import io.palladin.mobile.autofill.CredentialAssociationKey
import io.palladin.mobile.autofill.CredentialAssociationProofs
import io.palladin.mobile.autofill.OriginStatus

/** Debug APK only: substitutes the network proof, never production identity/origin/handoff checks. */
internal object SyntheticCredentialAssociation {
    const val HOST = "example.com"
    private const val FORM = "io.palladin.autofill.harness.form"

    fun configure(context: Context, state: String) {
        require(state in setOf("valid", "expired", "wrong-signer"))
        check(AutofillOriginVerifier(context).status(FORM, HOST) == OriginStatus.UNVERIFIED)
        val key = checkNotNull(CredentialAssociationIdentity.current(context, FORM, HOST))
        if (state == "wrong-signer") {
            proofs().accept(key.copy(signers = setOf(List(32) { "AB" }.joinToString(":"))))
        } else {
            check(CredentialAssociationIdentity.acceptIfCurrent(context, key))
            if (state == "expired") expire(context)
        }
        check((AutofillOriginVerifier(context).credentialFillStatus(FORM, HOST) == OriginStatus.VERIFIED) == (state == "valid"))
    }

    fun expire(context: Context) {
        val key = checkNotNull(CredentialAssociationIdentity.current(context, FORM, HOST))
        val proofs = proofs()
        synchronized(proofs) {
            @Suppress("UNCHECKED_CAST")
            val accepted = CredentialAssociationProofs::class.java.getDeclaredField("accepted").apply { isAccessible = true }
                .get(proofs) as MutableMap<CredentialAssociationKey, Long>
            check(key in accepted)
            accepted[key] = SystemClock.elapsedRealtime() - 60_000
        }
        check(!CredentialAssociationIdentity.isVerified(context, FORM, HOST))
    }

    private fun proofs(): CredentialAssociationProofs =
        CredentialAssociationIdentity::class.java.getDeclaredField("proofs").apply { isAccessible = true }
            .get(CredentialAssociationIdentity) as CredentialAssociationProofs
}
