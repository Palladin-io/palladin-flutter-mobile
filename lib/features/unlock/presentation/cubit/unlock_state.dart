import 'dart:typed_data';

/// Base class for all states of the unlock screen.
sealed class UnlockState {
  const UnlockState();
}

/// Idle state — nothing in flight, no error.
final class UnlockInitial extends UnlockState {
  const UnlockInitial();
}

/// An unlock operation is running (Argon2id + decrypt + secure-storage
/// write). Typically 300ms – 2s on mobile.
final class UnlockLoading extends UnlockState {
  const UnlockLoading();
}

/// Unlock succeeded — carries the derived key material so the page
/// listener can hand it off to [AuthBloc] via [VaultUnlocked].
///
/// [viaBiometrics] is `true` when the unlock was completed through the
/// biometric shortcut (not by typing the master password). The
/// presentation layer uses this to fire the `mb:unlock:biometric-used`
/// analytics event without coupling crypto state to analytics calls.
final class UnlockSuccess extends UnlockState {
  const UnlockSuccess({
    required this.masterKey,
    required this.privateKey,
    this.viaBiometrics = false,
  });

  final Uint8List masterKey;
  final Uint8List privateKey;
  final bool viaBiometrics;
}

/// Unlock failed — either wrong password, biometric refusal, or a
/// network error. [error] is typed so the presentation layer can map
/// to the correct localized message.
final class UnlockFailed extends UnlockState {
  const UnlockFailed(this.error);

  final Object error;
}
