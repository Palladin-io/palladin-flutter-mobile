import 'dart:typed_data';

import '../../../security_upgrade/domain/security_upgrade_start.dart';

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

/// This device has no Secret Key for the version-2 account; the page obtains
/// one and calls `UnlockCubit.unlockWithSecretKey`.
final class UnlockSecretKeyRequired extends UnlockState {
  const UnlockSecretKeyRequired({required this.accountId, required this.email});

  final String accountId;
  final String email;
}

/// The account must finish the security upgrade before the vault opens.
final class UnlockSecurityUpgradeRequired extends UnlockState {
  const UnlockSecurityUpgradeRequired(this.start);

  final SecurityUpgradeStart start;
}
