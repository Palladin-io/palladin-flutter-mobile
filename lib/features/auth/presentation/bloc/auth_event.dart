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
  const VaultUnlocked({
    required this.masterKey,
    required this.privateKey,
  });

  final Uint8List masterKey;
  final Uint8List privateKey;
}

/// Locks the vault — clears the in-memory [masterKey] and [privateKey]
/// and flips `isVaultLocked` back to `true` so the router redirects to
/// `/unlock`.
final class VaultLockRequested extends AuthEvent {
  const VaultLockRequested();
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
