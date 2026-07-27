# auth

Identity password accounts use only the frozen password-only KDF profile
`identity-argon2id-password-v1` (`securityVersion: 1`). The exact UTF-8
password and random 16-byte account salt feed Argon2id (32 MiB, 2 iterations,
parallelism 1) to produce AccountRoot; HKDF-SHA256 with the RFC 4122 account-id
bytes as Extract salt derives separate AuthCredential and master-key outputs.
Only AuthCredential crosses TLS. There is no Account Secret, legacy profile,
migration endpoint, fallback, or persistent client KDF secret.

OAuth 2.0 login (Google, Apple, X via `flutter_appauth`).

- **BLoC:** `AuthBloc` / `AuthEvent` / `AuthState`.
- **Pages:** `LoginPage` uses a method picker first, then reveals the email +
  master-password form after `Continue with Email`. **Widgets:**
  `AuthBrandHeader` keeps the logo and rotating copy identical across login and
  registration, TOTP, and e-mail verification. Core `AuthBrandBackground` and
  `AuthContentWidth` keep the glow, vertical lockup position, and centered
  320px side margins identical across those screens. `AuthProviderDivider`
  separates email from providers,
  `OAuthButton` renders the app-standard glass provider controls, and the
  shared core `AuthLegalFooter` stays pinned below the scrollable auth content.
  The method picker uses the existing brand-red `PrimaryButton` for e-mail and
  the shared subtle radial brand glow. The e-mail login and registration forms
  share the same vertical rhythm; the denser registration form starts one
  spacing step higher so its sign-in prompt, master-password explanation, and
  legal links remain visible. Its fixed order is submit action, sign-in prompt,
  dynamic supporting copy, then the pinned legal footer. The supporting copy
  sits in flexible remaining space midway between the sign-in prompt and legal
  links; compact screens scroll the whole block instead of clipping either
  action. Login/register routes and registration steps use a pure fade with no
  lateral movement. Sign-up is shown only inside the email form.
- **Shared password feedback:** `PasswordSecurityCheckController` owns the
  debounced client-side k-anonymity HIBP check and rejects stale responses.
  `PasswordSecurityStatusLine` presents checking, secure, breached,
  improvement advice, check unavailable, or a higher-priority form error in
  one fixed line. Registration reuses the same status resolver in its pinned
  supporting-copy slot: checking, strength, breach, invalid e-mail, and
  mismatch feedback fade in where the master-password explanation normally
  sits. A successful safe-password result restores that explanation instead
  of showing `Secure!`. No status row exists between its fields and `Sign Up`,
  so validation never moves the submit action. Registration, onboarding's `Set Your Master
  Password`, and recovery share the controller and presentation rules. Invalid
  e-mail feedback is debounced by 500 ms and clears while the user is typing.
- **Email-verification gate:** the delivery message is the gate's single
  heading. Its content starts at `AuthBrandHeader.formTopSpacing`, matching the
  first action on the authentication entry screen. `Resend email` is the
  primary action, `Check again` refreshes the session and reads the
  server-issued `email_verified` claim, and `Sign out` remains tertiary. The
  confirmation action is labelled `I've verified my email`. Once the claim is
  confirmed, the shared client-side provisioner creates the encrypted default
  vault before the gate opens. The refresh endpoint returns only the new token
  pair; stored user/onboarding metadata is preserved. A failed status check or
  required provisioning attempt never clears the current session.
- **Layering:** full data / domain / presentation split.
- **Role:** `AuthBloc` is a **singleton read by every other feature** to check authentication + vault-lock state and to extract the in-memory private key. It receives `AuthVaultUnlocked` from `unlock`.

**Cross-feature deps:** none upstream; nearly every feature depends *on* `AuthBloc`.
