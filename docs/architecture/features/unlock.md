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
absent; this neither extends nor approves the existing MK persistence deviation.

EN/light and PL/dark enlarged-text cases keep the password editable above the
keyboard and preserve the form when reception is discarded. The account frame
clips page decoration to its own body so the light bloom cannot overpaint the
sharing notice; the shared background's geometry inside that body is unchanged.
These are client-composition/rendering tests, not real authentication, device
lifecycle, biometric or deployed end-to-end evidence.

## Biometric key lifecycle

Biometric unlock retains a device-bound protected MK copy: iOS Keychain uses
`biometryCurrentSet` and `WhenPasscodeSetThisDeviceOnly`; Android uses an
AES-GCM ciphertext and an Android Keystore key requiring strong biometric
authorization for each operation. This does not make a compromised OS or the
unlocked process unable to access plaintext. The server never receives this key.

`BiometricStorageKeyStore` serializes enrollment, reads and deletion so an
in-flight enrollment cannot recreate material after a queued clear. Cleanup also
increments a generation immediately; password unlock captures it before async
work and stale operations cannot enroll after logout, disable or password change.
Disposed or invalidated unlocks wipe their derived key buffers. Cleanup
uses the fixed `biometric_storage` 5.x identifiers through a native deletion-only
channel: iOS deletes the Keychain item without allowing authentication UI;
Android deletes and checks the wrapping alias and removes its ciphertext file.
The dependency's delete API discards native failure information, so it is not
used as proof of cleanup. Missing items are idempotent success. The enrollment
marker and legacy raw key are also removed; failures are typed and not logged
with secret values.

Logout calls the same cleanup, even when token deletion fails. When tokens were
removed but protected cleanup fails, the app clears live keys and reports the
cleanup error instead of restoring an unlocked session. Password change clears
the old copy before the server mutation; failure leaves the password unchanged.
`clearBiometricKey` uses the same boundary. After password unlock, explicit setup can create a fresh biometric enrollment.

Password login and password unlock never enroll automatically. Home offers an
optional biometric setup card after login; Enable alone requests OS authentication.
Not now records only a per-account/device dismissal flag in SharedPreferences.
Security always exposes setup/disable later. Full logout removes the protected
copy, while the first-device dismissal preference survives logout. Enrollment
copies the authenticated in-memory MK, retains the cleanup generation fence and
wipes its temporary buffer on every outcome. Cancellation does not change auth
state. Disposing setup or changing the session revokes a late enrollment.

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
