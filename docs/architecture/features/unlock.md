# unlock

Master-password unlock with a biometric shortcut.

- **Cubit:** `UnlockCubit`.
- **Pages:** `UnlockPage`. **Widgets:** reuses `OnboardingTextField`, `PrimaryButton`.
- **Layering:** full data / domain / presentation split. `UnlockCryptoService` (in `data/services/`) derives the vault key from the master password via libsodium — uses the `try/finally` zero-out pattern for key bytes.
- **Flow:** on success posts `AuthVaultUnlocked` to `AuthBloc`.

**Cross-feature deps:** `auth` (posts unlock event). Reuses onboarding widgets — see the `PrimaryButton` relocation note in [../widget-catalog.md](../widget-catalog.md).
