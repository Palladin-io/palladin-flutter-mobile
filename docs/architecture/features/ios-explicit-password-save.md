# iOS explicit password save

On iOS 26.2+, the Credential Provider advertises
[`SupportsSavePasswordCredentials`](https://developer.apple.com/documentation/authenticationservices/ascredentialproviderviewcontroller/performwithoutuserinteractionifpossible%28savepasswordrequest%3A%29)
and handles Apple's [`ASSavePasswordRequest`](https://developer.apple.com/documentation/authenticationservices/assavepasswordrequest).
Only [`userInitiated`](https://developer.apple.com/documentation/authenticationservices/assavepasswordrequest/event-swift.enum/userinitiated) requests with an exact HTTPS URL service identifier are
accepted. Domain-only identifiers do not establish HTTPS. Automatic
`formDidDisappear` and `generatedPasswordFilled` requests are rejected; the
noninteractive callback always requests user interaction. No caller bundle
identity is inferred from this API. These public Apple contracts and their
26.2 availability were checked against the installed AuthenticationServices SDK
headers; the capability key is documented with the save callback above.

On iOS versions below 26.2, users can add a Credential manually through the
existing Palladin create flow. That fallback does not capture passwords from
another app or provide automatic save parity.

The provider asks for explicit consent and biometric authentication, then
stages a password for review. Its English and Polish copy explains that the
user must open Palladin within two minutes, unlock the same account, choose a
Vault, and confirm creation. Provider completion means the encrypted handoff
committed, not that a Vault Entry was created. The extension never opens the
containing app through an undocumented API, calls the backend, or publishes a
credential identity for a pending password.

## Temporary handoff

`PendingPasswordSave` keeps one bounded AES-GCM ciphertext in the configured
per-flavor App Group. A separate random Keychain key requires
`biometryCurrentSet` and `WhenUnlockedThisDeviceOnly`; it is unrelated to MK,
VK, the account private key, cache keys, and generated-password history.
Mutable plaintext/key buffers are cleared after use. Native/Flutter string
values exist only in memory during the authorized handoff and confirmation.
Swift/Apple credential strings and Flutter strings are immutable and may have
framework-managed copies that cannot be deterministically overwritten; Data
buffer wiping does not claim to erase those copies.

An independent Keychain authority binds the authenticated principal, save
session, capture ID, original Apple form session, exact origin, and a finite
120-second lifetime. Those bindings are authenticated as AAD and checked
against the stored authority, never accepted from the ciphertext itself.
Cross-process file locking serializes staging, revocation, replacement, and
consume. Biometric prompts run outside that lock; the authority and operation
lifecycle are checked again under the lock after authentication. A cancelled
or backgrounded operation cannot later release its result.

Runner registers `io.palladin.mobile/autofill-save`. It revokes the previous
save authority on process startup and activates a new session only for the
unlocked account. Pending captures therefore survive an ordinary app lock or
backgrounding, but **do not survive a Runner restart or account switch**.
This is a temporary continuation of an existing account session, not durable
password recovery. Logout revokes the separate authority; ordinary AutoFill
cache clearing for canonical Entry creation does not revoke it.

`pending` returns only an opaque ID. `take` requires that ID, the unlocked
session, and a localized biometric prompt. It authenticates, atomically marks
the capture consumed, deletes the ciphertext, then returns a bounded
`IOS_HTTPS` draft to Flutter. Runner retains only the value-free consumed lease
for `validate`; it does not retain another password copy. The shared Flutter
flow validates the session and selected exact domain around canonical Entry
creation. Cancellation, replacement, account switch, expiry, and backgrounding
of the presented confirmation invalidate the draft. No update/overwrite flow
is implied. Delayed cancellation carries the original opaque capture ID;
both the stored capture and Runner's active operation/consumed lease are cleared
only if that ID still matches. A value-free `invalidated(id)` channel event
clears only the corresponding Dart draft, without cancelling a replacement.
An explicit current-capture cancel without an ID and account revocation retain
their broader semantics.

## Verification and release boundary

Run `tool/test_ios_explicit_save.sh` for real cryptographic/file-store tests and
SDK typechecks. The optional simulator event/type test uses actual Apple
`ASSavePasswordRequest` instances, not a local stand-in. All inputs are
synthetic. These checks do not build an app or upload a release.

Physical iOS QA remains required before release: Safari's explicit save menu,
provider consent and biometric success/cancel, foreground-to-background races,
manual app return, same-account unlock, final Vault selection/create, successful
AutoFill only after canonical creation, expiry, Runner restart, logout/account
switch, biometric enrollment changes, and cancellation/replacement of requests.
Simulator logic checks do not prove Apple's system-menu UX or device Keychain
entitlements. TestFlight/App Store upload requires separate explicit approval.
