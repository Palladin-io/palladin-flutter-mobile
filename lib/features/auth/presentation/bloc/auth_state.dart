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
final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated({
    required this.userId,
    required this.isOnboarded,
    this.isVaultLocked = true,
    this.masterKey,
    this.privateKey,
  });

  final String userId;
  final bool isOnboarded;
  final bool isVaultLocked;

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
    bool clearKeys = false,
  }) {
    return AuthAuthenticated(
      userId: userId ?? this.userId,
      isOnboarded: isOnboarded ?? this.isOnboarded,
      isVaultLocked: isVaultLocked ?? this.isVaultLocked,
      masterKey: clearKeys ? null : (masterKey ?? this.masterKey),
      privateKey: clearKeys ? null : (privateKey ?? this.privateKey),
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
