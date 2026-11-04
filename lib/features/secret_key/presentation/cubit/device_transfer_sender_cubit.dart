import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/crypto/identity/device_pairing.dart';
import '../../../../core/storage/account_secret_store.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/datasources/secret_key_transfer_remote_datasource.dart';
import 'device_transfer_failure.dart';

export 'device_transfer_failure.dart';

sealed class DeviceTransferSenderState {
  const DeviceTransferSenderState();
}

final class DeviceTransferSenderReady extends DeviceTransferSenderState {
  const DeviceTransferSenderReady();
}

final class DeviceTransferSenderLoading extends DeviceTransferSenderState {
  const DeviceTransferSenderLoading();
}

/// The user must compare [sas] with the code on the new device.
final class DeviceTransferSenderCompare extends DeviceTransferSenderState {
  const DeviceTransferSenderCompare(this.sas, {this.sealing = false});
  final String sas;
  final bool sealing;
}

final class DeviceTransferSenderApproved extends DeviceTransferSenderState {
  const DeviceTransferSenderApproved();
}

final class DeviceTransferSenderRejected extends DeviceTransferSenderState {
  const DeviceTransferSenderRejected();
}

final class DeviceTransferSenderFailed extends DeviceTransferSenderState {
  const DeviceTransferSenderFailed(this.failure);
  final DeviceTransferFailure failure;
}

/// Approves a new device by sealing this phone's Secret Key to the key the
/// new device shows in its QR code (`recipient-shows-qr`).
///
/// The recipient key served by the backend must match the digest scanned
/// from the new device, and the user must confirm the SAS before anything
/// is sealed.
class DeviceTransferSenderCubit extends Cubit<DeviceTransferSenderState> {
  DeviceTransferSenderCubit({
    required this.accountId,
    required SecretKeyTransferRemoteDatasource datasource,
    required DevicePairingCrypto crypto,
    required AccountSecretStore secretStore,
  }) : _datasource = datasource,
       _crypto = crypto,
       _secretStore = secretStore,
       super(const DeviceTransferSenderReady());

  final String accountId;
  final SecretKeyTransferRemoteDatasource _datasource;
  final DevicePairingCrypto _crypto;
  final AccountSecretStore _secretStore;

  String? _transferId;
  PairingOffer? _offer;
  Uint8List? _recipientPublicKey;

  /// Whether this phone holds the Secret Key it would hand over.
  Future<bool> hasSecretKey() async {
    final secret = await _secretStore.read(accountId);
    secret?.fillRange(0, secret.length, 0);
    return secret != null;
  }

  /// Handles a scanned `palladin-pair:v2:r:` payload.
  Future<void> onScanned(String raw) async {
    if (state is! DeviceTransferSenderReady) return;
    final PairingQr qr;
    try {
      qr = PairingQr.parse(raw);
    } on DevicePairingException {
      emit(const DeviceTransferSenderFailed(DeviceTransferFailure.invalidCode));
      return;
    }
    if (qr.role != PairingQrRole.recipientShows) {
      emit(const DeviceTransferSenderFailed(DeviceTransferFailure.invalidCode));
      return;
    }
    emit(const DeviceTransferSenderLoading());
    _transferId = qr.transferId;
    try {
      final session = await _datasource.readAsSender(qr.transferId);
      final encodedKey = session.recipientPublicKey;
      if (encodedKey == null) {
        throw const SecretKeyTransferException(
          SecretKeyTransferErrorKind.server,
        );
      }
      final publicKey = decodeTransferBytes(encodedKey);
      final offer = PairingOffer.verify(
        accountId: accountId,
        transferId: qr.transferId,
        challenge: decodeTransferBytes(session.challenge),
        recipientPublicKey: publicKey,
        scanned: qr,
      );
      _offer = offer;
      _recipientPublicKey = publicKey;
      if (!isClosed) emit(DeviceTransferSenderCompare(offer.sas));
    } catch (error) {
      AppLogger.w(
        'DeviceTransfer',
        'Sender offer failed: ${error.runtimeType}',
      );
      await _cancel();
      if (!isClosed) emit(DeviceTransferSenderFailed(transferFailureOf(error)));
    }
  }

  /// The user confirmed both devices show the same code.
  Future<void> approve() async {
    final current = state;
    final offer = _offer;
    final publicKey = _recipientPublicKey;
    final transferId = _transferId;
    if (current is! DeviceTransferSenderCompare ||
        current.sealing ||
        offer == null ||
        publicKey == null ||
        transferId == null) {
      return;
    }
    emit(DeviceTransferSenderCompare(current.sas, sealing: true));
    Uint8List? secret;
    try {
      secret = await _secretStore.read(accountId);
      if (secret == null) {
        await _cancel();
        if (!isClosed) {
          emit(
            const DeviceTransferSenderFailed(
              DeviceTransferFailure.secretKeyMissing,
            ),
          );
        }
        return;
      }
      final envelope = await _crypto.seal(
        confirmed: ConfirmedPairingOffer(offer),
        recipientPublicKey: publicKey,
        accountSecret: secret,
      );
      await _datasource.submitEnvelope(transferId, envelope);
      _reset();
      if (!isClosed) emit(const DeviceTransferSenderApproved());
    } catch (error) {
      AppLogger.w('DeviceTransfer', 'Sender seal failed: ${error.runtimeType}');
      await _cancel();
      if (!isClosed) emit(DeviceTransferSenderFailed(transferFailureOf(error)));
    } finally {
      secret?.fillRange(0, secret.length, 0);
    }
  }

  /// The codes differ or the user did not start this transfer.
  Future<void> reject() async {
    if (state is! DeviceTransferSenderCompare) return;
    await _cancel();
    if (!isClosed) emit(const DeviceTransferSenderRejected());
  }

  void restart() {
    _reset();
    emit(const DeviceTransferSenderReady());
  }

  Future<void> _cancel() async {
    final transferId = _transferId;
    _reset();
    if (transferId == null) return;
    try {
      await _datasource.cancelAsSender(transferId);
    } on SecretKeyTransferException {
      // The session expires on its own within five minutes.
    }
  }

  void _reset() {
    _transferId = null;
    _offer = null;
    _recipientPublicKey = null;
  }

  @override
  Future<void> close() async {
    if (_transferId != null) await _cancel();
    return super.close();
  }
}

/// Strict unpadded base64url decoding of relay fields.
Uint8List decodeTransferBytes(String value) {
  try {
    final bytes = Uint8List.fromList(
      base64Url.decode(base64Url.normalize(value)),
    );
    if (base64Url.encode(bytes).replaceAll('=', '') == value) return bytes;
  } on FormatException {
    // Reported below as a malformed server response.
  }
  throw const SecretKeyTransferException(SecretKeyTransferErrorKind.server);
}

String encodeTransferBytes(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
