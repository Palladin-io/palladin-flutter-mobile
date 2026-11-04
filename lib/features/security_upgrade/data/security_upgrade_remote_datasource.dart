import 'package:dio/dio.dart';

/// Typed upgrade failures; the presentation layer localizes them.
enum SecurityUpgradeErrorKind { network, conflict, server }

class SecurityUpgradeException implements Exception {
  const SecurityUpgradeException(this.kind);
  final SecurityUpgradeErrorKind kind;
}

/// Server state after the atomic upgrade committed.
final class SecurityUpgradeCommit {
  const SecurityUpgradeCommit({required this.memberKeyVersion});
  final int memberKeyVersion;
}

/// `GET api/account/key-migration`.
final class KeyMigrationReport {
  const KeyMigrationReport({
    required this.memberKeyVersion,
    required this.legacyMemberEnvelopes,
    required this.legacyAgentEnvelopes,
  });

  final int memberKeyVersion;
  final int legacyMemberEnvelopes;
  final int legacyAgentEnvelopes;

  bool get complete => legacyMemberEnvelopes == 0 && legacyAgentEnvelopes == 0;
}

/// Identity and Vault endpoints of the in-place security upgrade. Only
/// ciphertext, public keys and non-secret metadata cross this boundary.
class SecurityUpgradeRemoteDatasource {
  SecurityUpgradeRemoteDatasource(this._dio);

  final Dio _dio;

  /// Atomic, compare-and-swap, idempotent by `migrationId`.
  Future<SecurityUpgradeCommit> upgrade(Map<String, Object?> body) =>
      _guard(() async {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/account/security-upgrade',
          data: body,
        );
        final version = response.data?['memberKeyVersion'];
        if (version is! int || version <= 0) {
          throw const SecurityUpgradeException(SecurityUpgradeErrorKind.server);
        }
        return SecurityUpgradeCommit(memberKeyVersion: version);
      });

  Future<KeyMigrationReport> report() => _guard(() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/account/key-migration',
    );
    final body = response.data;
    final version = body?['memberKeyVersion'];
    final members = body?['legacyMemberEnvelopes'];
    final agents = body?['legacyAgentEnvelopes'];
    if (version is! int || members is! int || agents is! int) {
      throw const SecurityUpgradeException(SecurityUpgradeErrorKind.server);
    }
    return KeyMigrationReport(
      memberKeyVersion: version,
      legacyMemberEnvelopes: members,
      legacyAgentEnvelopes: agents,
    );
  });

  /// Compare-and-swap replacement of this member's Vault key envelope.
  Future<void> replaceMemberEnvelope(
    String vaultId,
    Map<String, Object?> body,
  ) => _guard(
    () => _dio.put<void>(
      '/api/vaults/$vaultId/members/me/key-envelope',
      data: body,
    ),
  );

  Future<void> deleteLegacyMemberKey() =>
      _guard(() => _dio.delete<void>('/api/account/legacy-member-key'));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw SecurityUpgradeException(switch (status) {
        null => SecurityUpgradeErrorKind.network,
        409 || 412 => SecurityUpgradeErrorKind.conflict,
        _ => SecurityUpgradeErrorKind.server,
      });
    }
  }
}
