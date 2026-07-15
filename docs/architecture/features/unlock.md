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
- **Layering:** full data / domain / presentation split. `UnlockCryptoService` (in `data/services/`) derives the vault key from the master password via libsodium — uses the `try/finally` zero-out pattern for key bytes.
- **Flow:** on success, a password account with pending default-vault
  provisioning completes that idempotent client-side step before posting
  `AuthVaultUnlocked` to `AuthBloc`. This covers verification followed by an
  application restart; derived keys are zeroed if required provisioning fails.

**Cross-feature deps:** `auth` (posts unlock event). Reuses onboarding widgets — see the `PrimaryButton` relocation note in the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md).
