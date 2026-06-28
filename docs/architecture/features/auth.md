# auth

OAuth 2.0 login (Google, Apple, X via `flutter_appauth`).

- **BLoC:** `AuthBloc` / `AuthEvent` / `AuthState`.
- **Pages:** `LoginPage`. **Widgets:** `OAuthButton`, `BrandHero`.
- **Layering:** full data / domain / presentation split.
- **Role:** `AuthBloc` is a **singleton read by every other feature** to check authentication + vault-lock state and to extract the in-memory private key. It receives `AuthVaultUnlocked` from `unlock`.

**Cross-feature deps:** none upstream; nearly every feature depends *on* `AuthBloc`.
