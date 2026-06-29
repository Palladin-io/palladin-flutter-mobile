# recovery

Mnemonic-based account recovery (re-derive keys from the recovery phrase).

- **Cubit:** `RecoveryCubit`.
- **Pages:** `RecoveryPage`. **Widgets:** reuses `OnboardingTextField`, `PrimaryButton` from onboarding; `Mnemonic` utility from onboarding's domain.
- **Layering:** full data / domain / presentation split. `RecoveryCryptoService` re-derives keys from the mnemonic (libsodium, `try/finally` zero-out).

**Cross-feature deps:** `onboarding` (mnemonic utilities + shared widgets), `auth` (post-recovery sign-in state).
