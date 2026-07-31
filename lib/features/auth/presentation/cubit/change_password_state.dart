import 'dart:typed_data';

/// State for the change-master-password flow.
sealed class ChangePasswordState {
  const ChangePasswordState();
}

/// Idle — the form is editable.
final class ChangePasswordInitial extends ChangePasswordState {
  const ChangePasswordInitial();
}

/// The re-derivation + re-wrap + submit pipeline is running.
final class ChangePasswordLoading extends ChangePasswordState {
  const ChangePasswordLoading();
}

/// The password was changed. Carries the new master key and the
/// (unchanged) private key so the live session's in-memory key material
/// is refreshed to match the new ciphertext on the server.
final class ChangePasswordSuccess extends ChangePasswordState {
  const ChangePasswordSuccess({
    required this.masterKey,
    required this.privateKey,
  });

  final Uint8List masterKey;
  final Uint8List privateKey;
}

/// The change failed. Carries the typed [error]
/// ([ChangePasswordWrongCurrentException] or [PasswordAuthServerException]).
final class ChangePasswordFailure extends ChangePasswordState {
  const ChangePasswordFailure(this.error);

  final Object error;
}
