# System AutoFill

## Current state

- Flutter rebuilds a dedicated native cache after vault unlock, committed
  policy-2 snapshot/delta repair, and vault or entry mutations. Rebuild reads
  only the complete local `MemberIndex + MemberSecret + EntryKey` generation;
  it never calls a legacy Entry list/detail/reveal projection or one endpoint
  per credential. Vault v2 credentials are eligible only when the current
  MemberIndex explicitly authorizes one or more exact AutoFill domains and its
  revision/key version matches the revealed member ciphertext.
- iOS embeds a signed `ASCredentialProviderExtension`, publishes credential
  identities to `ASCredentialIdentityStore`, and releases credentials only
  after Keychain biometric authorization.
- Android registers `PalladinAutofillService` and releases domain-matched
  datasets only after a Keystore-bound `BiometricPrompt` operation.
- Android accepts `webDomain` only when Android 12+ reports an OS-verified App
  Link for the requesting package and exact host, or when the requester is the
  explicitly allowlisted system Chrome package authenticated by its system-app
  identity. The manifest exposes only `com.android.chrome` to package queries
  needed for that identity check; it does not request `QUERY_ALL_PACKAGES`.
  Other native apps and sideloaded browser lookalikes fail closed.

## Security contract

1. MK, VK, the user's private key, decrypted vault payloads, plaintext
   passwords, and TOTP seeds never enter App Groups, SharedPreferences, logs,
   analytics, or an unprotected file.
2. Native providers never query the backend directly and never receive the
   user's vault keys.
3. The provider cache stores platform ciphertext encrypted with a dedicated
   random AutoFill key. This key is not derived from MK/VK and is protected by
   Keychain/Keystore with biometric-set invalidation.
4. Cache v2 carries a separately authenticated manifest for the profile,
   organization membership, complete per-Vault access context and finite
   lease, plus each Entry revision/key high-water. Every record is compared
   with that authority; self-consistent substituted records are rejected.
   Cache v1 has no lease or independent authority and is purged, never migrated.
5. Missing, corrupt, stale, expired, clock-rolled-back, ambiguous, mismatched,
   or unverified state fails closed. The durable generation fence includes an
   authenticated maximum observed wall time; rollback over five minutes
   quarantines the generation. A process-lifetime monotonic clock anchor also
   rejects a frozen or slowly advancing wall clock once it trails elapsed time
   by more than five minutes. Android revalidates the requesting package, exact
   domain, generation and lease after biometric authentication and again under
   the revocation lock through the provider response handoff.
6. Logout and account deletion durably revoke access before physical cache,
   key and identity cleanup. A biometric-set change invalidates the platform
   key. Vault lock requires fresh provider authentication before a credential
   can be returned.
7. Plaintext exists only after successful provider authentication and only long
   enough to build the OS credential response. Temporary byte buffers are
   wiped where platform APIs expose mutable storage.
8. Domain policy is exact-host only. HTTP(S) URLs may be projected to their
   ASCII host, but userinfo, explicit ports, wildcards, Unicode/confusable
   hosts, malformed labels, parent-domain inference, and `www` equivalence are
   rejected. There is no eTLD, subdomain, or suffix matching.
9. Cache records are bounded to 2,000 records and 16 domains per record; native
   readers reject cache files over 16 MiB. The authenticated platform
   ciphertext contains the manifest and only the record id/bindings, display
   label, username, password, and authorized exact hosts.

## Cache lifecycle

1. Unlock synchronizes eligible credentials from server ciphertext using the
   in-memory private key already held by `AuthBloc`. The cache builder reads the
   local MemberIndex first, ignores corrupt/archived/deleted entries, and
   rejects stale revealed revisions. Legacy entries without an explicit
   `autofillDomains` MemberIndex policy remain unavailable until re-projected.
   AutoFill and Dashboard search use the same `MemberIndexPreparationService`
   single-flight operation, so simultaneous unlock listeners cannot start a
   second Vault-list request or a second snapshot chain. AutoFill awaits that
   complete operation before reading the runtime index, preventing an empty-cache
   race while the first sync is still starting. Offline restart reopens the
   complete persisted policy-2 generation without a network call; an expired
   or disabled offline policy leaves the native candidate set empty.
2. Canonical create, update, restore, delete/archive, and permanent purge, plus
   multi-step import, await successful native cache clearing before sending the
   first remote mutation. Cache clearing awaits native session activation; a
   failed activation or missing token fails closed instead of acknowledging a
   no-op. A failed clear aborts the remote transition. Rebuild
   occurs only after a definitive HTTP result; a final transport failure is
   ambiguous, so the cache remains empty until the next authoritative
   synchronization. Overlapping cache-sensitive mutations form one
   process-local invalidation batch: rebuild waits for every result, and one
   ambiguous result suppresses the whole batch rebuild. Vault create and vault
   delete also rebuild the cache after their definitive mutation. A failed
   rebuild therefore leaves no stale password available to AutoFill.
   SignalR/reconnect invalidation first awaits a durable native deny, then
   repairs the combined Member generation, and only after its current index is
   committed rebuilds the cache locally. A failed deny or rebuild is not marked
   applied; the coalesced invalidation remains queued for retry. Every other
   durable Member sync commit (including an ordinary Entry-list refresh)
   coalesces into the same local-only candidate rebuild after the current index
   publication tail, without starting another sync or per-Entry request.
3. Ordinary vault lock keeps the encrypted cache so AutoFill can operate after
   a fresh OS biometric challenge. The Flutter private key is never copied into
   the native provider.
4. Logout and forced session loss invoke the native revocation path before
   authentication cleanup. Its commit point is an atomically persisted,
   authenticated generation fence; once acknowledged, provider access is denied
   even if later ciphertext/key/identity deletion fails or an OS callback never
   returns. Generation-scoped artifacts and compare-delete cleanup prevent a
   delayed old operation from changing a newer session. After a confirmed fence,
   auth tokens and local key material are cleared in `finally`-style cleanup and
   physical provider cleanup is best effort. If neither revocation nor fallback
   clear can prove a durable deny, interactive logout fails closed without
   claiming success; forced session loss keeps a coalesced bounded retry running
   until a deny is confirmed.
5. A biometric-set change invalidates the platform key. Any failed native read
   durably quarantines the unusable generation before best-effort artifact and
   iOS identity cleanup; the next unlocked synchronization creates a fresh
   dedicated key and cache.

## Required device QA

- Android: select Palladin as the system AutoFill provider. On Chrome versions
  that expose their own `Autofill services` preference, also select `Autofill
  using another service` and restart Chrome before testing the login form.
  Then verify biometric success/cancel/failure, stale-cache mutation, logout
  wipe, and biometric enrollment change.
- iOS: Safari login form, identity selection, biometric success/cancel/failure,
  stale-cache mutation test, logout wipe, biometric enrollment change.
- Native Android application forms return datasets only for exact hosts backed
  by an OS-verified App Link on Android 12+; unverified packages return none.
- Automated Flutter/native tests and simulator builds do not replace physical
  device QA. Record Chrome/Safari background and locked-app behavior,
  biometric-set changes, corrupt-cache recovery, and Vault v2 delta refresh on
  real Android and iOS devices before release sign-off.

## Native files

- iOS provider: `ios/CredentialProvider/`
- Android provider:
  `android/app/src/main/kotlin/io/palladin/mobile/autofill/`
- Android service config: `android/app/src/main/res/xml/autofill_service.xml`
