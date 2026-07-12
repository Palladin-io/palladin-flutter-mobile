import 'dart:typed_data';

/// Base class for all authentication states.
sealed class AuthState {
  const AuthState();
}

/// Initial state before any auth check has been performed.
final class AuthInitial extends AuthState {
  const AuthInitial();
}

/// An authentication operation is in progress.
final class AuthLoading extends AuthState {
  const AuthLoading();
}

/// The user is authenticated and has valid credentials.
///
/// [isVaultLocked] defaults to `true` so the router forwards the user to
/// the unlock screen after every login. Once the user supplies their
/// master password, [VaultUnlocked] carries the derived [masterKey] and
/// [privateKey] into this state via [copyWith]. A [VaultLockRequested]
/// event clears those keys from memory.
///
/// [permissions] is the bitwise flag bag from the JWT `permissions`
/// claim (see `core/Palladin.Core.Security/Permission.cs` on the
/// backend). Mobile only reads it — UI uses it to gate Pro-only
/// affordances such as creating multiple vaults. Defaults to `0`
/// (Permission.None) when the claim is absent.
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({
    required this.userId,
    required this.isOnboarded,
    this.isVaultLocked = true,
    this.masterKey,
    this.privateKey,
    this.permissions = 0,
    this.email,
    this.emailVerified = true,
  });

  final String userId;
  final bool isOnboarded;
  final bool isVaultLocked;
  final int permissions;

  /// Whether the account's email is verified (JWT `email_verified` claim).
  /// Defaults to `true` — OAuth sessions are always verified. A freshly
  /// registered password account is `false`, which routes the user to the
  /// "verify your email" gate before the vault. Read-only on mobile.
  final bool emailVerified;

  /// User's email address, decoded from the JWT `email` claim. Used
  /// purely for display in account chrome (e.g. the settings drawer
  /// header) — never as a routing or auth identifier. Defaults to
  /// `null` when the claim is missing.
  final String? email;

  /// 32-byte master key derived from the user's master password via
  /// Argon2id. Held in memory only while the vault is unlocked.
  final Uint8List? masterKey;

  /// 32-byte X25519 private key decrypted with [masterKey]. Held in
  /// memory only while the vault is unlocked.
  final Uint8List? privateKey;

  /// Returns a new [AuthAuthenticated] with selected fields replaced.
  ///
  /// When [clearKeys] is `true`, [masterKey] and [privateKey] are reset
  /// to `null` regardless of the other arguments — used when locking
  /// the vault to drop all key material from memory.
  AuthAuthenticated copyWith({
    String? userId,
    bool? isOnboarded,
    bool? isVaultLocked,
    Uint8List? masterKey,
    Uint8List? privateKey,
    int? permissions,
    String? email,
    bool? emailVerified,
    bool clearKeys = false,
  }) {
    return AuthAuthenticated(
      userId: userId ?? this.userId,
      isOnboarded: isOnboarded ?? this.isOnboarded,
      isVaultLocked: isVaultLocked ?? this.isVaultLocked,
      masterKey: clearKeys ? null : (masterKey ?? this.masterKey),
      privateKey: clearKeys ? null : (privateKey ?? this.privateKey),
      permissions: permissions ?? this.permissions,
      email: email ?? this.email,
      emailVerified: emailVerified ?? this.emailVerified,
    );
  }
}

/// The user is not authenticated (no valid tokens).
final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

/// An authentication operation failed.
///
/// Carries the original [error] so the presentation layer can inspect
/// its type (e.g. [AuthServerException]) and resolve a localized message.
final class AuthError extends AuthState {
  const AuthError(this.error);

  final Object error;
}
