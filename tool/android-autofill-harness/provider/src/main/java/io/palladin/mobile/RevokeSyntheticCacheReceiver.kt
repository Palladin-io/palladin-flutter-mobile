package io.palladin.mobile

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import io.palladin.mobile.autofill.AutoFillCacheStore

/** Debug harness only: revoke without backgrounding the authentication Activity. */
class RevokeSyntheticCacheReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "io.palladin.autofill.harness.EXPIRE_ASSOCIATION") {
            SyntheticCredentialAssociation.expire(context)
            resultCode = 1
            return
        }
        if (intent.action == "io.palladin.autofill.harness.REVOKE") {
            AutoFillCacheStore(context).revokeAccess()
        }
    }
}
