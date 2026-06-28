# onboarding

Account-setup wizard: set master password, back up mnemonic, confirm.

- **Cubit:** `OnboardingCubit`.
- **Pages:** `OnboardingWizardPage`, `MasterPasswordPage`, `RecoveryKeyBackupPage`, `RecoveryKeyConfirmPage`.
- **Widgets:** `OnboardingTextField` (+ `FieldFeedbackSlot`), `PrimaryButton`, `OnboardingScaffold`, `PasswordStrengthBar`.
- **Layering:** full split. The domain layer holds standalone `PasswordStrength`, `Mnemonic`, `CryptoParams` utilities reused by `recovery` and the crypto services.

**⚠ Architecture smell — app-wide widgets live here.** `OnboardingTextField` (+ `FieldFeedbackSlot`) and `PrimaryButton` are imported across **every** feature, yet they sit inside the onboarding feature folder. `PrimaryButton` should move to `lib/core/widgets/` (used in 14 files / 6 features). Until moved, import them from their onboarding paths — do **not** duplicate.
