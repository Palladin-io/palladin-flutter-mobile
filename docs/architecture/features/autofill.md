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
- Android currently fails closed for native application forms that do not
  expose a trustworthy `webDomain`. Package-to-domain association is not
  inferred from a package name.

## Security contract

1. MK, VK, the user's private key, decrypted vault payloads, plaintext
   passwords, and TOTP seeds never enter App Groups, SharedPreferences, logs,
   analytics, or an unprotected file.
2. Native providers never query the backend directly and never receive the
   user's vault keys.
3. The provider cache stores platform ciphertext encrypted with a dedicated
   random AutoFill key. This key is not derived from MK/VK and is protected by
   Keychain/Keystore with biometric-set invalidation.
4. Missing, ambiguous, or mismatched service identifiers fail closed. Native
   Android application filling remains disabled until Palladin has a verified
   package-to-domain association model.
5. Logout and account deletion wipe the cache and its dedicated key. A
   biometric-set change invalidates that key. Vault lock requires fresh
   provider authentication before a credential can be returned.
6. Plaintext exists only after successful provider authentication and only long
   enough to build the OS credential response. Temporary byte buffers are
   wiped where platform APIs expose mutable storage.

## Cache lifecycle

1. Unlock synchronizes eligible credentials from server ciphertext using the
   in-memory private key already held by `AuthBloc`.
2. Create, update, delete, import, vault create, and vault delete clear the old
   cache before rebuilding it. A failed rebuild therefore leaves no stale
   password available to AutoFill.
3. Ordinary vault lock keeps the encrypted cache so AutoFill can operate after
   a fresh OS biometric challenge. The Flutter private key is never copied into
   the native provider.
4. Logout clears cache ciphertext, the dedicated platform key, and iOS
   credential identities.
5. A biometric-set change invalidates the platform key. A failed read clears
   the unusable Android cache; iOS remains unavailable until the next unlocked
   synchronization replaces its cache and key.

## Required device QA

- Android: Chrome login form, biometric success/cancel/failure, stale-cache
  mutation test, logout wipe, biometric enrollment change.
- iOS: Safari login form, identity selection, biometric success/cancel/failure,
  stale-cache mutation test, logout wipe, biometric enrollment change.
- Native Android application forms are expected to return no datasets until a
  verified package association model is implemented.

## Native files

- iOS provider: `ios/CredentialProvider/`
- Android provider:
  `android/app/src/main/kotlin/io/palladin/mobile/autofill/`
- Android service config: `android/app/src/main/res/xml/autofill_service.xml`
