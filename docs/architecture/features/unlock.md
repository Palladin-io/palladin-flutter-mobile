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

Biometrics are optional. Password login/unlock never enroll automatically; the
Home setup card and Security settings provide explicit enable/disable. Not now
stores only a per-account/device dismissal preference. Biometric cancellation
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
to a later successful unlock. Ordinary app unlock has no request to authorize.

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
