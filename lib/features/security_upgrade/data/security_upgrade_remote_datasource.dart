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
    required this.memberEnvelopesPendingRewrap,
    required this.agentEnvelopesOnNonCurrentSuite,
    this.accountMemberEnvelopesPendingRewrap = 0,
    this.organizationIdsPendingRewrap = const [],
  });

  /// Pending in the current organization only.
  final int memberEnvelopesPendingRewrap;

  /// Pending across every organization; the legacy key may be deleted only
  /// at zero.
  final int accountMemberEnvelopesPendingRewrap;

  /// Organizations whose member envelopes still address the old key; each is
  /// re-wrapped when the member next unlocks there.
  final List<String> organizationIdsPendingRewrap;
  final int agentEnvelopesOnNonCurrentSuite;
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
    final members = response.data?['memberEnvelopesPendingRewrap'];
    final account = response.data?['accountMemberEnvelopesPendingRewrap'];
    final agents = response.data?['agentEnvelopesOnNonCurrentSuite'];
    final organizations = response.data?['organizationIdsPendingRewrap'];
    if (members is! int ||
        account is! int ||
        agents is! int ||
        organizations is! List ||
        organizations.any((id) => id is! String)) {
      throw const SecurityUpgradeException(SecurityUpgradeErrorKind.server);
    }
    return KeyMigrationReport(
      memberEnvelopesPendingRewrap: members,
      accountMemberEnvelopesPendingRewrap: account,
      organizationIdsPendingRewrap: List.unmodifiable(organizations),
      agentEnvelopesOnNonCurrentSuite: agents,
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

  /// Accepted asynchronously (202). A 409 (`legacy-member-key-in-use`,
  /// `member-key-directory-not-current`) keeps the record; the next unlock
  /// resumes and retries.
  Future<bool> deleteLegacyMemberKey(int legacyMemberKeyVersion) async {
    try {
      await _dio.delete<void>(
        '/api/account/legacy-member-key',
        queryParameters: {'legacyMemberKeyVersion': legacyMemberKeyVersion},
      );
      return true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 409) return false;
      throw SecurityUpgradeException(switch (error.response?.statusCode) {
        null => SecurityUpgradeErrorKind.network,
        _ => SecurityUpgradeErrorKind.server,
      });
    }
  }

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
