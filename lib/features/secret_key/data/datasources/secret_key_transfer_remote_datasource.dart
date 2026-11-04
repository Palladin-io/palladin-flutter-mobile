import 'package:dio/dio.dart';

import '../../../../core/crypto/identity/device_pairing.dart';

/// Typed transfer failures the presentation layer localizes.
enum SecretKeyTransferErrorKind { expired, consumed, notFound, network, server }

class SecretKeyTransferException implements Exception {
  const SecretKeyTransferException(this.kind);
  final SecretKeyTransferErrorKind kind;
}

/// Session created by the new device in `recipient-shows-qr`.
final class RecipientTransferSession {
  const RecipientTransferSession({
    required this.transferId,
    required this.challenge,
    required this.pollToken,
  });

  final String transferId;
  final String challenge;
  final String pollToken;
}

/// Session created by the signed-in device in `sender-shows-qr`.
final class SenderTransferSession {
  const SenderTransferSession({
    required this.transferId,
    required this.challenge,
  });

  final String transferId;
  final String challenge;
}

/// Sender view of a session once the recipient key is known.
final class SenderTransferState {
  const SenderTransferState({
    required this.challenge,
    required this.recipientPublicKey,
  });

  final String challenge;

  /// Null until the recipient attaches its key (`sender-shows-qr`).
  final String? recipientPublicKey;
}

/// Claimed envelope; `accountId` is checked against the bootstrap account.
final class ClaimedTransfer {
  const ClaimedTransfer({required this.accountId, required this.envelope});
  final String accountId;
  final PairingEnvelope envelope;
}

/// Opaque relay endpoints for Secret Key transfer. Only public keys,
/// challenges and ciphertext cross this boundary.
class SecretKeyTransferRemoteDatasource {
  SecretKeyTransferRemoteDatasource(this._dio);

  final Dio _dio;

  Future<RecipientTransferSession> createAsRecipient(
    String recipientPublicKey,
  ) => _guard(() async {
    final body = await _post('/api/auth/secret-key-transfers', {
      'recipientPublicKey': recipientPublicKey,
    });
    return RecipientTransferSession(
      transferId: _string(body, 'transferId'),
      challenge: _string(body, 'challenge'),
      pollToken: _string(body, 'pollToken'),
    );
  });

  Future<String> attachRecipient({
    required String transferId,
    required String challenge,
    required String recipientPublicKey,
  }) => _guard(() async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/auth/secret-key-transfers/$transferId/recipient',
      data: {'challenge': challenge, 'recipientPublicKey': recipientPublicKey},
    );
    return _string(response.data, 'pollToken');
  });

  /// Returns null while the sender has not sealed yet (HTTP 202).
  Future<ClaimedTransfer?> claim({
    required String transferId,
    required String pollToken,
  }) => _guard(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/auth/secret-key-transfers/$transferId/claim',
      data: {'pollToken': pollToken},
    );
    if (response.statusCode == 202) return null;
    final body = response.data;
    return ClaimedTransfer(
      accountId: _string(body, 'accountId'),
      envelope: PairingEnvelope(
        kemCiphertext: _string(body, 'kemCiphertext'),
        ciphertext: _string(body, 'ciphertext'),
      ),
    );
  });

  Future<void> cancelAsRecipient({
    required String transferId,
    required String pollToken,
  }) => _guard(
    () => _dio.delete<void>(
      '/api/auth/secret-key-transfers/$transferId',
      data: {'pollToken': pollToken},
    ),
  );

  Future<SenderTransferSession> createAsSender() => _guard(() async {
    final body = await _post('/api/account/secret-key-transfers', const {});
    return SenderTransferSession(
      transferId: _string(body, 'transferId'),
      challenge: _string(body, 'challenge'),
    );
  });

  /// First read binds the session to this account (`senderBinding`).
  Future<SenderTransferState> readAsSender(String transferId) =>
      _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/api/account/secret-key-transfers/$transferId',
        );
        final body = response.data;
        final key = body?['recipientPublicKey'];
        return SenderTransferState(
          challenge: _string(body, 'challenge'),
          recipientPublicKey: key is String ? key : null,
        );
      });

  Future<void> submitEnvelope(String transferId, PairingEnvelope envelope) =>
      _guard(
        () => _post('/api/account/secret-key-transfers/$transferId/envelope', {
          'kemCiphertext': envelope.kemCiphertext,
          'ciphertext': envelope.ciphertext,
        }),
      );

  Future<void> cancelAsSender(String transferId) => _guard(
    () => _dio.delete<void>('/api/account/secret-key-transfers/$transferId'),
  );

  Future<Map<String, dynamic>?> _post(String path, Object data) async =>
      (await _dio.post<Map<String, dynamic>>(path, data: data)).data;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      throw SecretKeyTransferException(switch (error.response?.statusCode) {
        404 => SecretKeyTransferErrorKind.notFound,
        409 => SecretKeyTransferErrorKind.consumed,
        410 => SecretKeyTransferErrorKind.expired,
        null => SecretKeyTransferErrorKind.network,
        _ => SecretKeyTransferErrorKind.server,
      });
    }
  }

  static String _string(Map<String, dynamic>? body, String key) {
    final value = body?[key];
    if (value is! String || value.isEmpty) {
      throw const SecretKeyTransferException(SecretKeyTransferErrorKind.server);
    }
    return value;
  }
}
