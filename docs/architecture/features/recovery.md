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
- **Key-possession proof:** each completion attempt fetches a fresh one-time
  `POST /api/account/recovery/challenge` package. `RecoveryCryptoService`
  opens it with the recovered private key as `account-recovery-challenge-v1`
  (exactly 104 B sealed / 56 B plaintext, `PLDNRCV1` magic and the user id of
  the authenticated session from `SecureTokenStorage`, never from the
  response) and sends the 32-byte `recoveryProof` with
  `PUT /api/account/recovery`. Any failure is one `RecoveryChallengeException`;
  the proof is wiped after upload. Vectors: `test/fixtures/account-recovery-challenge-v1/`.

**Cross-feature deps:** `vault` (`VaultProtocolBytes` strict base64url), `onboarding` (mnemonic utilities + shared widgets), `auth` (post-recovery sign-in state).
