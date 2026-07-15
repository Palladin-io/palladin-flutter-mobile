# onboarding

Account-setup wizard: set master password, back up mnemonic, confirm.

- **Cubit:** `OnboardingCubit`.
- **Pages:** `OnboardingWizardPage`, `MasterPasswordPage`, `RecoveryKeyBackupPage`, `RecoveryKeyConfirmPage`.
- **Widgets:** `OnboardingTextField` (+ `FieldFeedbackSlot`), `PrimaryButton`,
  `OnboardingScaffold` (optional branded `header`, pinned `bottom`,
  per-screen `titleFontSize`, fixed `contentTopSpacing`, optional title block,
  and shared `useAuthBrandLayout` frame),
  `PasswordStrengthBar`. `MasterPasswordPage` reuses auth's
  `PasswordSecurityCheckController` + `PasswordSecurityStatusLine` for the same
  debounced HIBP behavior as registration. The master-password step uses the
  same lockup height, glow, and 320px content width as authentication.
- **Layering:** full split. The domain layer holds standalone `PasswordStrength`, `Mnemonic`, `CryptoParams` utilities reused by `recovery` and the crypto services.
- **Default vault provisioning:** `DefaultVaultProvisioner` is the single
  client-side path shared by classic onboarding, password-email verification,
  and the first unlock fallback. It generates and wraps the VK on-device,
  treats backend `409` as idempotent success, and persists only a boolean retry
  marker - never key material.

**⚠ Architecture smell — app-wide widgets live here.** `OnboardingTextField` (+ `FieldFeedbackSlot`) and `PrimaryButton` are imported across **every** feature, yet they sit inside the onboarding feature folder. `PrimaryButton` should move to `lib/core/widgets/` (used in 14 files / 6 features). Until moved, import them from their onboarding paths — do **not** duplicate.
