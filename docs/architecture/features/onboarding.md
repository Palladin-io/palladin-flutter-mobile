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

`PrimaryButton` lives in `lib/core/widgets/` and is shared across features. It and `CompactPrimaryButton` use `PrimaryButtonGlow` for enabled brand actions. Disabled/loading buttons retain their existing interaction behavior without the glow. `OnboardingTextField` remains the shared input in this feature; reuse it rather than duplicating it.

Account analytics and email preferences use the shared [privacy feature](privacy.md).
Optional privacy choices appear on first entry to the ready application, after registration, verification, setup and unlock; `/settings/privacy` exposes later changes.
