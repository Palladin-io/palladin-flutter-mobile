import '../../../../core/crypto/identity/device_pairing.dart';
import '../../data/datasources/secret_key_transfer_remote_datasource.dart';

/// Presentation-level outcome of a failed Secret Key transfer step.
enum DeviceTransferFailure {
  invalidCode,
  keyMismatch,
  accountMismatch,
  decryptFailed,
  secretKeyMissing,
  expired,
  network,
  server,
}

DeviceTransferFailure transferFailureOf(Object error) => switch (error) {
  SecretKeyTransferException(:final kind) => switch (kind) {
    SecretKeyTransferErrorKind.expired ||
    SecretKeyTransferErrorKind.consumed ||
    SecretKeyTransferErrorKind.notFound => DeviceTransferFailure.expired,
    SecretKeyTransferErrorKind.network => DeviceTransferFailure.network,
    SecretKeyTransferErrorKind.server => DeviceTransferFailure.server,
  },
  DevicePairingException(:final error) => switch (error) {
    DevicePairingError.malformedQr => DeviceTransferFailure.invalidCode,
    DevicePairingError.recipientKeyDigestMismatch ||
    DevicePairingError.challengeMismatch => DeviceTransferFailure.keyMismatch,
    DevicePairingError.malformedEnvelope ||
    DevicePairingError.aeadFailure => DeviceTransferFailure.decryptFailed,
  },
  _ => DeviceTransferFailure.server,
};
