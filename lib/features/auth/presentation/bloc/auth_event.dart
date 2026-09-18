import 'dart:typed_data';

/// Base class for all authentication events.
sealed class AuthEvent {
  const AuthEvent();
}

/// Triggers the Google OAuth sign-in flow.
final class AuthLoginWithGoogle extends AuthEvent {
  const AuthLoginWithGoogle();
}

/// Requests a token refresh using stored credentials.
final class AuthRefreshRequested extends AuthEvent {
  const AuthRefreshRequested();
}

/// Logs out the current user and clears stored credentials.
final class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

/// Checks whether the user is already authenticated from a previous
/// session (e.g. on app startup).
final class AuthCheckRequested extends AuthEvent {
  const AuthCheckRequested();
}

/// Emitted after a successful master-password unlock. Carries the
/// derived keys into [AuthAuthenticated] so downstream features can
/// decrypt vault items without re-prompting the user.
final class VaultUnlocked extends AuthEvent {
  const VaultUnlocked({required this.masterKey, required this.privateKey});

  final Uint8List masterKey;
  final Uint8List privateKey;
}

/// Locks the vault — clears the in-memory [masterKey] and [privateKey]
/// and flips `isVaultLocked` back to `true` so the router redirects to
/// `/unlock`.
final class VaultLockRequested extends AuthEvent {
  const VaultLockRequested();
}

/// Fired after a successful email + master-password session is
/// established (registration, a non-TOTP login, or a completed TOTP
/// challenge). The tokens have already been persisted by the flow's
/// cubit, so `AuthBloc` reads userId / permissions / email /
/// emailVerified from storage and carries the freshly derived
/// [masterKey] and [privateKey] into an unlocked [AuthAuthenticated]
/// state — the user just typed their password, so there is no separate
/// unlock step.
final class PasswordSessionEstablished extends AuthEvent {
  const PasswordSessionEstablished({
    required this.masterKey,
    required this.privateKey,
  });

  final Uint8List masterKey;
  final Uint8List privateKey;
}

/// Fired after the user's email is verified (via the deep-link result
/// screen). Best-effort refreshes the access token so the updated
/// `email_verified` claim propagates, then flips `emailVerified` on the
/// current session **without** dropping the in-memory keys — a user who
/// verified in the same session stays unlocked. A no-op when the user is
/// not currently authenticated.
final class AuthEmailVerified extends AuthEvent {
  const AuthEmailVerified();
}

/// Fired by the onboarding wizard after setup completes.
///
/// On a fresh setup it carries the just-derived [masterKey] and
/// [privateKey] so `AuthBloc` can mark the vault unlocked immediately —
/// the user just set their master password, so there is no need to
/// unlock again. On the "already onboarded" (409) path both are `null`,
/// and `AuthBloc` keeps the vault locked so the router forwards the user
/// to `/unlock` (never an "unlocked" state with no keys).
final class OnboardingCompleted extends AuthEvent {
  const OnboardingCompleted({this.masterKey, this.privateKey});

  final Uint8List? masterKey;
  final Uint8List? privateKey;
}
