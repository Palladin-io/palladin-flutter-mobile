# System AutoFill

Linear: CVT-276

## Current state

- iOS embeds a signed `ASCredentialProviderExtension`. It fails closed with
  `userInteractionRequired` and does not expose credentials yet.
- Android registers `PalladinAutofillService`. It detects credential forms and
  offers an authenticated action that opens Palladin. It does not read, save,
  cache, or return credential values yet.

## Security contract

1. MK, VK, the user's private key, decrypted vault payloads, passwords, and
   TOTP seeds never enter App Groups, SharedPreferences, logs, analytics, or an
   unprotected file.
2. Native providers never query the backend directly and never receive the
   user's vault keys.
3. A future provider cache stores only per-platform ciphertext encrypted with
   a dedicated random AutoFill key. This key is not derived from MK/VK and is
   protected by Keychain/Keystore with user-presence requirements.
4. Domain/package matching happens before decrypting a record. Ambiguous,
   missing, or mismatched service identifiers fail closed.
5. Logout, account deletion, disabling AutoFill, or biometric-set changes wipe
   the cache and its dedicated key. Vault lock requires fresh provider
   authentication before a credential can be returned.
6. Plaintext exists only for the selected record and only long enough to build
   the OS credential response. Temporary byte buffers are wiped on every exit
   path.

## Delivery stages

### 1. Provider registration and locked flow

- iOS extension embedded and signed.
- Android service registered with `BIND_AUTOFILL_SERVICE`.
- Both platforms expose no credential data and direct the user to unlock.

### 2. Encrypted native cache

- Flutter sends credential records only while the vault is unlocked.
- iOS app encrypts records into its App Group; the extension accesses only a
  dedicated shared Keychain key guarded by user presence.
- Android encrypts records in private app storage with an
  authentication-bound Android Keystore key.
- Cache index contains normalized service identifiers and opaque record IDs;
  username/password remain encrypted.

### 3. Domain-matched fill

- Generate/update iOS `ASPasswordCredentialIdentity` records.
- Build iOS and Android datasets only from exact normalized domain/package
  matches.
- Decrypt only the selected credential after OS authentication.
- Add settings/deep links, cache lifecycle wiring, and manual QA for Chrome and
  one native Android login plus Safari and one native iOS login.

## Native files

- iOS provider: `ios/CredentialProvider/`
- Android provider:
  `android/app/src/main/kotlin/io/palladin/mobile/autofill/`
- Android service config: `android/app/src/main/res/xml/autofill_service.xml`
