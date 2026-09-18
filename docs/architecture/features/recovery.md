# recovery

Mnemonic-based account recovery (re-derive keys from the recovery phrase).

Every recovery step uses the same dark-only grain as login and onboarding;
light backgrounds and the existing per-step layout remain unchanged.

- **Cubit:** `RecoveryCubit`.
- **Pages:** `RecoveryPage`. **Widgets:** reuses `OnboardingTextField`,
  `PrimaryButton`, auth's shared brand frame, and the shared debounced HIBP
  password status. The new-master-password step matches login/registration
  lockup height, glow, and 320px content width. `Mnemonic` comes from
  onboarding's domain.
- **Layering:** full data / domain / presentation split. `RecoveryCryptoService` re-derives keys from the mnemonic (libsodium, `try/finally` zero-out).

**Cross-feature deps:** `onboarding` (mnemonic utilities + shared widgets), `auth` (post-recovery sign-in state).
