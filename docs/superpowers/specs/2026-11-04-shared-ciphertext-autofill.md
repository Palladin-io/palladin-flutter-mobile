# AutoFill from the canonical encrypted Member source

## Accepted direction

Replace the dedicated plaintext-derived AutoFill export with request-time access
to the application's canonical encrypted Member source. Unlock and ordinary sync
must not reveal credential bodies or produce a second credential database.
Keep native field recognition, exact origin/package verification, explicit manual
consent, system provider setup, browser guidance, save and password generation.
Android and iOS are required; iOS publication is not authorized.

## Existing dependencies and boundaries

`SqliteMemberSyncCache` owns the active/staged ciphertext generations, Member
Vault-key wrapper, finite access context, wall-clock bound and profile quarantine.
`MemberSyncService` validates/decrypts the MemberIndex into session memory.
`LocalCurrentEntryService` opens one selected Entry through the existing
`VaultRotationCryptoService` and `EntryV2CryptoService`, using independent session
claims and revalidation. These services remain the crypto implementation.

The SQLite database currently lives in application support. iOS extension access
requires one canonical database in the signed per-flavor App Group, with a
transactional, crash-safe migration; a copied export is not the target design.
SQLite WAL readers must observe a complete committed generation and consult the
same durable quarantine/revocation boundary before final handoff.

## Request flow

1. Native OS entrypoint classifies fields and validates the requesting service.
   Native code retains original field IDs, package/certificate authority, exact
   host set and a fresh request nonce. Internal navigation never carries a
   credential in an Intent or Bundle; the required final Android OS result may
   contain the ephemeral authenticated Dataset.
2. Request UI uses existing account unlock. A live app key may be borrowed only
   within its current unlocked session. Cold-start/password unlock remains valid;
   app-unlock biometrics are optional and must perform the existing protected key
   operation. Existing per-fill native biometric authorization remains required
   until a separately reviewed product policy changes it; borrowing an unlocked
   app key is not itself permission to bypass that boundary.
3. Query the current authenticated MemberIndex for exact hosts, or the existing
   explicit absent-domain manual mode. Display only index metadata before an
   Entry is selected. Never open all MemberSecret bodies to render a chooser.
4. Open only the selected current Entry, revalidate its revision, key bindings,
   account/session, lease and durable invalidation fence. Recheck native origin
   and original request immediately before OS completion. Manual mode retains a
   separate one-operation confirmation.
5. Consume the request once and wipe owned plaintext/key buffers on completion,
   cancellation, replacement, lock or revocation. A late callback cannot fill.

Android must use one app repository/session owner rather than accidentally
starting two independent main-app engines with conflicting auth/sync state.
The existing native authentication Activity remains the OS result owner.

## iOS executable feasibility gate

No existing Swift target implements the full Member crypto contract. Before
choosing a Flutter credential-extension runtime, build a minimal extension host
that executes the existing Dart crypto against synthetic fixtures and measure
resident memory and cold request completion. A Share-extension example is not
evidence for a Credential Provider memory budget. Failure of this gate requires
a shared library extraction, not copied Swift cryptography or a hidden fallback
to the old bulk cache. This decision remains open until executable evidence.

The extension cannot borrow app Dart memory. It needs independently protected
profile authority and an explicit unlock path. Reusing an existing protected MK
requires review of its actual Keychain accessibility/access group and fresh OS
authorization; this specification does not authorize a new MK/VK/private-key item
or plaintext persistence. Password unlock uses encrypted account key material
and the same KDF/unwrap implementation. Selected database rows are never their
own expected principal/organization/lease authority.

## Removal and migration

Once both replacement providers pass integration gates, remove app startup and
durable-update export scheduling, `AutoFillIncrementalPublisher`,
`DurableAutoFillRepairCoordinator`, export preparation state/cards/Home takeover,
and dedicated record/catalog writers. Retain independent provider setup, origin
classification, save/generation and durable revoke semantics. Migrate old encrypted
cache artifacts by denial and deletion; never ship dual provider databases as a
silent fallback. Remove obsolete tests only with replacement boundary coverage.

## Acceptance evidence

- Unlock/remount/sync: zero MemberSecret opens and zero credential-export writes.
- One selected fill: one selected body open; one Entry update opens no unrelated
  bodies. Deletion/revocation cannot fill an old selection.
- Process-dead provider request supports explicit unlock and one-shot completion.
- Android native/web and iOS service/manual matching retain exact origins,
  browser exclusions, username-only and HTTP/OTP/search negatives.
- Cancel, lock, account replacement, mutation during reveal, expiry, rollback,
  quarantined/missing/corrupt database and delayed handoff fail closed.
- Cross-process iOS read/mutation/revoke races and crash-safe database migration
  are executable tests. Synthetic runtime memory is not physical release proof.

## Checkpoint

Base: Debug16 `4db354d2…b6cf6e`; no production migration implemented yet.
Next: native request ownership and executable iOS runtime gate, then freeze the
shared request contract with independent security review. Root owns setup UX;
core owns removal of bulk export/progress only after replacement acceptance.

## Design provenance

Bitwarden Android `dde0e884…3bd3b1`,
`app/src/main/kotlin/com/x8bit/bitwarden/data/autofill/provider/AutofillCipherProviderImpl.kt`,
filters the decrypted runtime cipher list by URI before selecting a cipher.
KeePassDX `77ecfa86…29b554`, `credentialprovider/autofill/KeeAutofillService.kt`,
uses SearchHelper against an opened database or an authentication picker.
These are architectural comparisons, not source copied into Palladin. Apple's
[credential provider security description](https://support.apple.com/en-ca/guide/security/sec6319ac7b9/web)
distinguishes metadata identities from passwords. Palladin retains its own
independent scope, offline-lease and origin requirements.
