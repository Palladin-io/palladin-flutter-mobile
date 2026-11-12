# unlock

Master-password unlock with a biometric shortcut.

- **Cubit:** `UnlockCubit`.
- **Pages:** `UnlockPage`. **Widgets:** reuses `AuthBrandBackground`,
  `AuthContentWidth`, `AuthBrandHeader`, `OnboardingTextField`, and
  `PrimaryButton`. Its glow, lockup height, 320px content cap, 20px minimum
  gutters, and labelled-field start match the authentication entry screen.
  The shared header keeps the persistent `Enter your master password` caption
  instead of rotating the authentication-entry messages.
  When available, the biometric action is a separate middle section with equal
  flexible space between the Unlock action and the forgot-password controls.
  Its 40px fingerprint sits inside a 72×72 logical-pixel touch target with a
  localized tooltip/accessibility label. The target is disabled while unlocking.
  The body remains scrollable on compact screens and when the keyboard opens.
- **Layering:** full data / domain / presentation split. `IdentityKdfService`
  owns the frozen password-only v1 Argon2id + HKDF contract;
  `UnlockCryptoService` opens the wrapped private key with the derived master
  key. Both use `try/finally` zero-out patterns for key bytes.
- **Flow:** on success, a password account with pending default-vault
  provisioning completes that idempotent client-side step before posting
  `AuthVaultUnlocked` to `AuthBloc`. This covers verification followed by an
  application restart; derived keys are zeroed if required provisioning fails.

**Cross-feature deps:** `auth` (posts unlock event). Reuses the core `PrimaryButton` and onboarding input widgets.

## Sharing account continuation

A locked, verified account can receive a shared snapshot before unlocking its
own Vaults. The explicit account action transfers that reception in RAM while
the ordinary `UnlockPage`/`UnlockCubit` derives the account key, opens its private
key and completes any required default-Vault provisioning. Successful unlock
returns to the original reception without a new sharing delivery or confirmation;
destination selection and saving the independent copy remain explicit.

The combined production-router test in
`test/core/router/entry_share_guest_save_test.dart` exercises native KDF/crypto,
real loopback account/Vault/Entry HTTP and the production provisioner. It covers
success, wrong-password retry and required-provisioning failure/retry. Failures
keep the account locked and the same reception pending, with no Entry write.
Biometric storage is substituted as unavailable and enrollment/read are asserted
absent; this does not exercise the optional protected biometric unlock mechanism.

EN/light and PL/dark enlarged-text cases keep the password editable above the
keyboard and preserve the form when reception is discarded. The account frame
clips page decoration to its own body so the light bloom cannot overpaint the
sharing notice; the shared background's geometry inside that body is unchanged.
These are client-composition/rendering tests, not real authentication, device
lifecycle, biometric or deployed end-to-end evidence.

## Protected biometric unlock

Biometrics are optional. Once explicitly enrolled, entering the active unlock
screen starts the OS biometric prompt once, after availability is known.
Cancellation/resume does not re-prompt automatically; the fingerprint remains
available for explicit retry. No automatic prompt runs while backgrounded,
covered by another route, already loading, disposed, or after password input.
Password login/unlock never enroll automatically; the
Home setup card and Security settings provide explicit enable/disable. Home
actions use a horizontal pair: active AccentButton for Not now on the left and
PrimaryButton for enrollment on the right, both using compact card sizing
(10px labels and compact padding), with equal flexible heights for
scaled text. Both actions are disabled only while enrollment is in progress. Not now
stores only a per-account/device explicit-dismissal preference; intentional
disable does the same. Successful enrollment clears that preference and hides
the Home card through the enabled status alone. The old handled preference was
also written by enrollment, so it is not treated as evidence of a user dismissal:
missing enrollment can show the optional card once again. This does not restore
keys or enroll automatically. Biometric cancellation
keeps the current auth state and never logs the user out.

The approved model retains a local **encrypted** MK envelope. iOS
`SharedBiometricUnlock` wraps it with a random AES-GCM key in a narrow per-flavor
Keychain access group shared only by Runner and its Credential Provider. The key
uses `biometryCurrentSet`, `WhenPasscodeSetThisDeviceOnly`, no synchronization;
the general Runner Keychain group is not shared. Envelope authentication binds
profile, group, epoch and key identity. This enables independent extension unlock
without storing a plaintext MK, VK or private key. Android retains its per-use
strong-biometric Keystore-protected encrypted MK; app-mediated provider requests
reuse the verified unlock path. Neither model protects an already unlocked
process against a compromised OS.

`IOSBiometricKeyStore` uses the native shared-unlock plugin for enrollment, read,
verified migration and clear. A legacy enrollment is not silently trusted as a
new shared enrollment: the app verifies the recovered key against the account
private-key envelope before committing migration. Cancellation, failed validation,
source/session replacement and cleanup generation changes prevent late commits.
Native deletion/tombstones prevent fallback from resurrecting deleted material.
Mutable temporary key buffers are wiped on completion and failure.

Source mutation tickets bind enrollment/migration/clear to independent current
account authority. Returning from an OS biometric prompt skips only redundant
foreground repair while that mutation is active. Explicit invalidation, revoke
and account changes remain effective. Logout, disable and password changes clear
protected unlock through the same fenced cleanup boundary; cleanup failure is
reported rather than treated as success.

## Request-bound password and biometric unlock

An AutoFill request captures its immutable OS destination and authorization
context before asynchronous unlock. `UnlockCubit` awaits that binding before
account lookup/KDF and invokes the captured one-operation authorization only
after crypto verifies the private key. A canceled/replaced request cannot attach
to a later successful unlock. Ordinary app unlock establishes only the app-owned in-memory unlocked session.
Under the product-owner decision of 2026-11-05, an Android AutoFill request may
reuse that verified session without another prompt. The host captures its exact
private-key identity and principal, fences both sides of async request minting,
and cancels immediately on lock/logout/account or key replacement. Native
authorization remains one-request-only, bound to the source session/epoch;
manual-native selection still requires its warning and separate confirmation.

Account lookup coalesces concurrent in-flight reads within the same authenticated
session. Only genuine connection/timeout failures may use the integrity-protected
local account projection, with exact profile, principal, organization, policy and
KDF bindings. HTTP authorization errors or malformed responses never fall back.
The projection contains encrypted private-key material and public KDF metadata,
not tokens or plaintext keys. Offline credential reads still enforce original
finite Member leases; account unlock does not renew them.

All FlutterSecureStorage consumers use `deviceSecureStorage` with Android
`encryptedSharedPreferences: true` at construction. In pinned version 9.2.4,
opening the encrypted backend migrates and removes legacy entries. Mixing a
per-operation encrypted marker write with default unencrypted session reads
therefore made tokens/user ID disappear and redirected users to login. The
[plugin documentation](https://pub.dev/packages/flutter_secure_storage/versions/9.2.4)
explicitly requires setting this option on the constructor. Startup migrates
existing legacy session/metadata without a biometric prompt or session deletion.
The Android contract test models this source-verified migration; host Flutter
tests do not execute Android's native storage implementation.

Dart channel-contract and lifecycle tests plus JVM deletion tests cover these
branches. Actual Face ID/fingerprint, changed enrollment, cancellation, restart,
and device logout/re-enrollment require device QA before claiming release
acceptance. The fixed deletion identifiers must be reviewed on plugin upgrades.


## Android AutoFill launch latency (Debug39)

Android app unlock always starts its ordinary OS-protected biometric-store read
without waiting for AutoFill source configuration/account lookup. The request
controller wraps that local read only to preserve prompt lifecycle and cancel,
expiry or replacement fencing; late key bytes are wiped if the original request
is no longer current. This wrapper does not bind a source or grant a fill
capability. After account private-key verification, the existing host binds and
authorizes the exact request from the active app session. Origin, source epoch,
lease and one-use consent checks still run at handoff.

The previous Android DI redirected app biometric reads into request-bound native
unlock, which awaited network-dependent source initialization before displaying
the OS prompt. S22 metadata trace on2026-11-09 showed binding17:22:26.597–31.178,
with biometric unlock requested at27.577. The composition regression holds
source initialization unresolved and verifies that the local prompt starts,
lifecycle protection is active and no fill capability exists. Separate tests
cover cancellation wiping a late key. iOS composition is unchanged.

The unlock loading state identifies its initiating method. Automatic biometric
unlock keeps the password button label visible; progress surrounds the
fingerprint action instead. Both actions remain protected against concurrent
unlock attempts, and cancellation restores manual retry. EN/PL widget tests
cover progress ownership, the touch target and duplicate-prompt suppression.
A local Profile build has a distinct Palladin (Profile) app/provider label for
physical performance comparisons without debug JIT overhead. Profile does not
enable verbose application logging.

### Account lookup overlapping the biometric prompt

The app UnlockCubit invokes the local biometric read before starting the fresh
account lookup. The two waits overlap; unlock still requires both successful
biometric recovery and current account authority before private-key decryption.
Cancellation does not wait for the account request, and detached request errors
are observed. The independent iOS provider runtime is unchanged.

Deterministic regression: a simulated 5-second biometric response and 2-second
account lookup complete at second 5 instead of second 7, with one prompt, one
account request and one private-key decrypt. This is scheduling evidence, not
S22/iPhone timing. A pending lookup or 401 cannot authorize unlock.
