# onboarding

Account-setup wizard: set master password, back up mnemonic, confirm.

Every wizard step shares the dark-only grain, including recovery-key backup,
confirmation and the completion placeholder. The same scaffold covers both
OAuth onboarding and password registration. Light backgrounds stay unchanged.

- **Cubit:** `OnboardingCubit`.
- **Pages:** `OnboardingWizardPage`, `MasterPasswordPage`, `RecoveryKeyBackupPage`, `RecoveryKeyConfirmPage`.
- **Widgets:** `OnboardingTextField` (+ `FieldFeedbackSlot`), `PrimaryButton`,
  `OnboardingScaffold` (optional branded `header`, pinned `bottom`,
  per-screen `titleFontSize`, fixed `contentTopSpacing`, optional title block,
  and shared `useAuthBrandLayout` frame),
  `PasswordStrengthBar`. `MasterPasswordPage` reuses auth's
  `PasswordSecurityCheckController` + `PasswordSecurityStatusLine` for the same
  debounced HIBP behavior as registration. The master-password step uses the
  same lockup height, position, rotating caption, glow, and 320px content
  width as authentication. Below the unchanged `AuthBrandHeader`, fields start
  at `denseFormTopSpacing`, without a separate step title. The bordered
  requirements card retains wrapping labels. Below it, a single 12px slot
  crossfades between the encryption explanation and password feedback; empty
  and safe-password states restore the explanation. The form scrolls independently;
  Continue uses the existing pinned `bottom` slot.
  `centerFooterAbovePinnedBottom` centers the feedback horizontally and
  vertically between the requirements card and Continue while keeping the
  action pinned. On short screens, the feedback scrolls with the form.
  Both centered-footer variants scroll the header with their content and
  feedback. Registration's `centerFooterInRemainingSpace` also scrolls its
  bottom slot; `centerFooterAbovePinnedBottom` keeps Continue pinned.
  A sharing-account notice plus keyboard
  can leave less height than the header; it must not consume the form viewport.
  Other variants retain their existing pinned header/action behavior.
  Recovery confirmation removes the stale error SnackBar when retrying or
  leaving its error state, before overlapping wizard Scaffolds can carry it
  into a route transition.
- **Layering:** full split. The domain layer holds standalone `PasswordStrength`, `Mnemonic`, `CryptoParams` utilities reused by `recovery` and the crypto services.
- **Default vault provisioning:** `DefaultVaultProvisioner` is the single
  client-side path shared by classic onboarding, password-email verification,
  and the first unlock fallback. It generates and wraps the VK on-device,
  treats backend `409` as idempotent success, and persists only a boolean retry
  marker - never key material.

`PrimaryButton` lives in `lib/core/widgets/` and is shared across features. It and `CompactPrimaryButton` use `PrimaryButtonGlow` for enabled brand actions. Disabled/loading buttons retain their existing interaction behavior without the glow. `OnboardingTextField` remains the shared input in this feature; reuse it rather than duplicating it.

Account analytics and email preferences use the shared [privacy feature](privacy.md).
Optional privacy choices appear on first entry to the ready application, after registration, verification, setup and unlock; `/settings/privacy` exposes later changes.
