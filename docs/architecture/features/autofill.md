# System AutoFill

## Current state

- Flutter rebuilds a dedicated native cache after vault unlock and after vault
  or entry mutations. Vault v2 credentials are eligible only when the current
  MemberIndex explicitly authorizes one or more exact AutoFill domains and its
  revision matches the revealed member ciphertext. Logout and account removal
  clear the cache and its platform key.
- iOS embeds a signed `ASCredentialProviderExtension`, publishes credential
  identities to `ASCredentialIdentityStore`, and releases credentials only
  after Keychain biometric authorization.
- Android registers `PalladinAutofillService` and releases domain-matched
  datasets only after a Keystore-bound `BiometricPrompt` operation.
- Android accepts `webDomain` only when Android 12+ reports an OS-verified App
  Link for the requesting package and exact host, or when the requester is the
  explicitly allowlisted system Chrome package authenticated by its system-app
  identity. Other native apps and sideloaded browser lookalikes fail closed.

## Security contract

1. MK, VK, the user's private key, decrypted vault payloads, plaintext
   passwords, and TOTP seeds never enter App Groups, SharedPreferences, logs,
   analytics, or an unprotected file.
2. Native providers never query the backend directly and never receive the
   user's vault keys.
3. The provider cache stores platform ciphertext encrypted with a dedicated
   random AutoFill key. This key is not derived from MK/VK and is protected by
   Keychain/Keystore with biometric-set invalidation.
4. Missing, ambiguous, mismatched, or unverified service identifiers fail
   closed. Android revalidates the requesting package and domain before and
   after biometric authentication.
5. Logout and account deletion wipe the cache and its dedicated key. A
   biometric-set change invalidates that key. Vault lock requires fresh
   provider authentication before a credential can be returned.
6. Plaintext exists only after successful provider authentication and only long
   enough to build the OS credential response. Temporary byte buffers are
   wiped where platform APIs expose mutable storage.
7. Domain policy is exact-host only. HTTP(S) URLs may be projected to their
   ASCII host, but userinfo, explicit ports, wildcards, Unicode/confusable
   hosts, malformed labels, parent-domain inference, and `www` equivalence are
   rejected. There is no eTLD, subdomain, or suffix matching.
8. Cache records are bounded to 2,000 records and 16 domains per record; native
   readers reject cache files over 16 MiB. Each authenticated record contains
   only its id, display label, username, password, and authorized exact hosts.

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
   race while the first sync is still starting.
2. Canonical create, update, restore, delete/archive, and permanent purge, plus
   vault create and vault delete, clear the old cache before sending the remote
   mutation and rebuild it only after a definitive HTTP result. A final
   transport failure is ambiguous, so the cache remains empty until the next
   authoritative synchronization. Overlapping canonical mutations form one
   process-local invalidation batch: rebuild waits for every result, and one
   ambiguous result suppresses the whole batch rebuild. Multi-step import
   invalidates after its first successful write and rebuilds only after all
   completed writes are visible. A failed rebuild therefore leaves no stale
   password available to AutoFill.
3. Ordinary vault lock keeps the encrypted cache so AutoFill can operate after
   a fresh OS biometric challenge. The Flutter private key is never copied into
   the native provider.
4. Logout first bypasses Flutter's serialized synchronization queue and invokes
   a dedicated native revocation path. Native cache writes and revocation are
   mutually exclusive and carry a token issued by the native cache store.
   Revocation always rotates that token before clearing the cache, so native code
   rejects every delayed replacement from the previous session. The token counter
   remains native across Flutter engine recreation and does not depend on a Dart
   counter restarting from zero. The revocation call itself uses an independent
   executor/queue so an earlier Flutter operation cannot prevent it from clearing
   cache ciphertext and the dedicated platform key. A revoked latch rejects every
   later write until an unlocked, authenticated state explicitly obtains a new
   native cache-session token. Best-effort OS identity cleanup follows. A critical
   revocation failure aborts logout before local auth tokens are removed instead
   of reporting an unsafe successful session transition.
5. A biometric-set change invalidates the platform key. Any failed native read
   clears the unusable cache (and iOS credential identities); the next unlocked
   synchronization creates a fresh dedicated key and cache.

## Required device QA

- Android: Chrome login form, biometric success/cancel/failure, stale-cache
  mutation test, logout wipe, biometric enrollment change.
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
