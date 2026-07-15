# System AutoFill

Linear: CVT-276

## Current state

- Flutter rebuilds a dedicated native cache after vault unlock and after vault
  or entry mutations. Only credential entries with a normalized web domain are
  included. Logout and account removal clear the cache and its platform key.
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

## Cache lifecycle

1. Unlock synchronizes eligible credentials from server ciphertext using the
   in-memory private key already held by `AuthBloc`.
2. Create, update, delete, vault create, and vault delete clear the old cache
   before rebuilding it. Multi-step import invalidates after its first
   successful write and rebuilds only after all completed writes are visible.
   A failed rebuild therefore leaves no stale password available to AutoFill.
3. Ordinary vault lock keeps the encrypted cache so AutoFill can operate after
   a fresh OS biometric challenge. The Flutter private key is never copied into
   the native provider.
4. Logout first bypasses Flutter's serialized synchronization queue and invokes
   a dedicated native revocation path. Native cache writes and revocation are
   mutually exclusive and carry monotonically increasing session generations.
   Revocation records its generation before clearing the cache, and native code
   rejects any delayed replacement from that or an older generation. The
   revocation call itself uses an independent executor/queue so an earlier
   Flutter operation cannot prevent it from clearing cache ciphertext and the
   dedicated platform key. A revoked latch rejects every later write regardless
   of its operation generation until an unlocked, authenticated state explicitly
   begins a new native cache session. Best-effort OS identity cleanup follows. A
   critical revocation failure aborts logout before local auth tokens are removed
   instead of reporting an unsafe successful session transition.
5. A biometric-set change invalidates the platform key. A failed read clears
   the unusable Android cache; iOS remains unavailable until the next unlocked
   synchronization replaces its cache and key.

## Required device QA

- Android: Chrome login form, biometric success/cancel/failure, stale-cache
  mutation test, logout wipe, biometric enrollment change.
- iOS: Safari login form, identity selection, biometric success/cancel/failure,
  stale-cache mutation test, logout wipe, biometric enrollment change.
- Native Android application forms return datasets only for exact hosts backed
  by an OS-verified App Link on Android 12+; unverified packages return none.

## Native files

- iOS provider: `ios/CredentialProvider/`
- Android provider:
  `android/app/src/main/kotlin/io/palladin/mobile/autofill/`
- Android service config: `android/app/src/main/res/xml/autofill_service.xml`
