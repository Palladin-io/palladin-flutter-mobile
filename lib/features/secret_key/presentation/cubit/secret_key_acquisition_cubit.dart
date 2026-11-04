import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/crypto/identity/device_pairing.dart';
import '../../../../core/crypto/identity/secret_key_codec.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/datasources/secret_key_transfer_remote_datasource.dart';
import 'device_transfer_failure.dart';
import 'device_transfer_sender_cubit.dart'
    show decodeTransferBytes, encodeTransferBytes;

export 'device_transfer_failure.dart';

sealed class SecretKeyAcquisitionState {
  const SecretKeyAcquisitionState();
}

/// Method picker.
final class SecretKeyAcquisitionChoose extends SecretKeyAcquisitionState {
  const SecretKeyAcquisitionChoose();
}

final class SecretKeyAcquisitionPreparing extends SecretKeyAcquisitionState {
  const SecretKeyAcquisitionPreparing();
}

/// This phone shows [qrPayload] to a signed-in phone (`recipient-shows-qr`).
final class SecretKeyAcquisitionShowingCode extends SecretKeyAcquisitionState {
  const SecretKeyAcquisitionShowingCode({
    required this.qrPayload,
    required this.sas,
    required this.expiresAt,
  });
  final String qrPayload;
  final String sas;
  final DateTime expiresAt;
}

/// This phone scanned a computer's code and waits for approval there.
final class SecretKeyAcquisitionAwaitingSender
    extends SecretKeyAcquisitionState {
  const SecretKeyAcquisitionAwaitingSender(this.sas);
  final String sas;
}

/// Manual Secret Key entry or Emergency Kit scan.
final class SecretKeyAcquisitionKitEntry extends SecretKeyAcquisitionState {
  const SecretKeyAcquisitionKitEntry({this.error});
  final SecretKeyEntryError? error;
}

/// The Secret Key is available; the page pops a copy and the cubit wipes
/// its own buffer on close.
final class SecretKeyAcquisitionAcquired extends SecretKeyAcquisitionState {
  const SecretKeyAcquisitionAcquired(this.secret);
  final Uint8List secret;
}

final class SecretKeyAcquisitionFailed extends SecretKeyAcquisitionState {
  const SecretKeyAcquisitionFailed(this.failure);
  final DeviceTransferFailure failure;
}

enum SecretKeyEntryError {
  malformed,
  checksumMismatch,
  kitAccountMismatch,
  notKitCode,
}

/// Obtains the Secret Key on a device that does not hold it yet: from a
/// signed-in device over the transfer relay, or from the Emergency Kit.
///
/// The X-Wing recipient seed lives only in this cubit and is wiped on
/// success, failure, cancel and close.
class SecretKeyAcquisitionCubit extends Cubit<SecretKeyAcquisitionState> {
  SecretKeyAcquisitionCubit({
    required this.accountId,
    required this._datasource,
    required this._crypto,
    this.pollInterval = const Duration(seconds: 2),
    this.sessionLifetime = const Duration(seconds: 300),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const SecretKeyAcquisitionChoose());

  /// Account from the sign-in bootstrap; the claimed envelope must match.
  final String accountId;
  final Duration pollInterval;
  final Duration sessionLifetime;
  final SecretKeyTransferRemoteDatasource _datasource;
  final DevicePairingCrypto _crypto;
  final DateTime Function() _now;

  Uint8List? _seed;
  Uint8List? _secret;
  String? _transferId;
  String? _pollToken;
  int _generation = 0;

  /// `recipient-shows-qr`: create a session and show its QR code.
  Future<void> showCode() async {
    final generation = await _restart();
    emit(const SecretKeyAcquisitionPreparing());
    try {
      final (seed, publicKey) = await _crypto.generateRecipientKey();
      if (generation != _generation) {
        seed.fillRange(0, seed.length, 0);
        return;
      }
      _seed = seed;
      final session = await _datasource.createAsRecipient(
        encodeTransferBytes(publicKey),
      );
      if (generation != _generation) return;
      _transferId = session.transferId;
      _pollToken = session.pollToken;
      final offer = PairingOffer.forRecipient(
        accountId: accountId,
        transferId: session.transferId,
        challenge: decodeTransferBytes(session.challenge),
        recipientPublicKey: publicKey,
      );
      final expiresAt = _now().add(sessionLifetime);
      emit(
        SecretKeyAcquisitionShowingCode(
          qrPayload: PairingQr.recipientShows(session.transferId, publicKey),
          sas: offer.sas,
          expiresAt: expiresAt,
        ),
      );
      await _poll(offer, generation, expiresAt);
    } catch (error) {
      await _fail(error, generation);
    }
  }

  /// `sender-shows-qr`: attach this phone's key to a scanned session.
  Future<void> onScannedSenderCode(String raw) async {
    final generation = await _restart();
    final PairingQr qr;
    try {
      qr = PairingQr.parse(raw);
      if (qr.role != PairingQrRole.senderShows) {
        throw const DevicePairingException(DevicePairingError.malformedQr);
      }
    } on DevicePairingException {
      emit(const SecretKeyAcquisitionFailed(DeviceTransferFailure.invalidCode));
      return;
    }
    emit(const SecretKeyAcquisitionPreparing());
    try {
      final (seed, publicKey) = await _crypto.generateRecipientKey();
      if (generation != _generation) {
        seed.fillRange(0, seed.length, 0);
        return;
      }
      _seed = seed;
      final pollToken = await _datasource.attachRecipient(
        transferId: qr.transferId,
        challenge: encodeTransferBytes(qr.binding),
        recipientPublicKey: encodeTransferBytes(publicKey),
      );
      if (generation != _generation) return;
      _transferId = qr.transferId;
      _pollToken = pollToken;
      final offer = PairingOffer.forRecipient(
        accountId: accountId,
        transferId: qr.transferId,
        challenge: qr.binding,
        recipientPublicKey: publicKey,
      );
      emit(SecretKeyAcquisitionAwaitingSender(offer.sas));
      await _poll(offer, generation, _now().add(sessionLifetime));
    } catch (error) {
      await _fail(error, generation);
    }
  }

  Future<void> chooseEmergencyKit() async {
    await _restart();
    emit(const SecretKeyAcquisitionKitEntry());
  }

  void submitTypedSecretKey(String input) {
    try {
      _complete(SecretKeyCodec.parse(accountId, input));
    } on SecretKeyFormatException catch (error) {
      emit(
        SecretKeyAcquisitionKitEntry(
          error: error.error == SecretKeyFormatError.malformed
              ? SecretKeyEntryError.malformed
              : SecretKeyEntryError.checksumMismatch,
        ),
      );
    }
  }

  void onScannedKitCode(String raw) {
    try {
      _complete(SecretKeyCodec.parseEmergencyKitQr(accountId, raw));
    } on SecretKeyFormatException catch (error) {
      emit(
        SecretKeyAcquisitionKitEntry(
          error: error.error == SecretKeyFormatError.accountMismatch
              ? SecretKeyEntryError.kitAccountMismatch
              : SecretKeyEntryError.notKitCode,
        ),
      );
    }
  }

  /// Returns to the method picker, cancelling any pending session.
  Future<void> back() async {
    await _restart();
    emit(const SecretKeyAcquisitionChoose());
  }

  Future<void> _poll(
    PairingOffer offer,
    int generation,
    DateTime expiresAt,
  ) async {
    while (generation == _generation && !isClosed) {
      if (!_now().isBefore(expiresAt)) {
        throw const SecretKeyTransferException(
          SecretKeyTransferErrorKind.expired,
        );
      }
      final claimed = await _datasource.claim(
        transferId: _transferId!,
        pollToken: _pollToken!,
      );
      if (generation != _generation) return;
      if (claimed != null) {
        _pollToken = null;
        if (claimed.accountId.toLowerCase() != accountId.toLowerCase()) {
          throw const _AccountMismatch();
        }
        final secret = await _crypto.open(
          offer: offer,
          envelope: claimed.envelope,
          recipientSeed: _seed!,
        );
        if (generation != _generation) {
          secret.fillRange(0, secret.length, 0);
          return;
        }
        _complete(secret);
        return;
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  void _complete(Uint8List secret) {
    _wipeSeed();
    _secret?.fillRange(0, _secret!.length, 0);
    _transferId = null;
    _pollToken = null;
    _secret = secret;
    emit(SecretKeyAcquisitionAcquired(secret));
  }

  Future<void> _fail(Object error, int generation) async {
    if (generation != _generation) return;
    AppLogger.w('SecretKey', 'Acquisition failed: ${error.runtimeType}');
    await _cancelSession();
    if (isClosed || generation != _generation) return;
    emit(
      SecretKeyAcquisitionFailed(
        error is _AccountMismatch
            ? DeviceTransferFailure.accountMismatch
            : transferFailureOf(error),
      ),
    );
  }

  /// Invalidates in-flight work and cancels the pending session.
  Future<int> _restart() async {
    final generation = ++_generation;
    await _cancelSession();
    return generation;
  }

  Future<void> _cancelSession() async {
    final transferId = _transferId;
    final pollToken = _pollToken;
    _transferId = null;
    _pollToken = null;
    _wipeSeed();
    if (transferId == null || pollToken == null) return;
    try {
      await _datasource.cancelAsRecipient(
        transferId: transferId,
        pollToken: pollToken,
      );
    } on SecretKeyTransferException {
      // The session expires on its own within five minutes.
    }
  }

  void _wipeSeed() {
    _seed?.fillRange(0, _seed!.length, 0);
    _seed = null;
  }

  @override
  Future<void> close() async {
    _generation++;
    await _cancelSession();
    _secret?.fillRange(0, _secret!.length, 0);
    _secret = null;
    return super.close();
  }
}

final class _AccountMismatch implements Exception {
  const _AccountMismatch();
}
