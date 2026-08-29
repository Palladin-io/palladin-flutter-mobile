import '../../../../core/storage/secure_token_storage.dart';
import '../../../../core/utils/jwt_claims.dart';
import 'member_sync_service.dart';

/// Resolves the independent current-session authority used for local cache
/// bindings from the verified access token issued by the backend.
class MemberSyncSessionAuthorityProvider {
  const MemberSyncSessionAuthorityProvider(this._tokenStorage);

  final SecureTokenStorage _tokenStorage;

  Future<MemberSyncSessionAuthority> current() async {
    final token = await _tokenStorage.accessToken;
    final payload = token == null
        ? const <String, dynamic>{}
        : JwtClaims.decodePayload(token);
    final principalId = payload['sub'];
    final organizationId = token == null
        ? null
        : JwtClaims.organizationIdFrom(token);
    final generationValue = payload['authz_ver'];
    final generation = switch (generationValue) {
      final String value when RegExp(r'^(?:0|[1-9][0-9]*)$').hasMatch(value) =>
        value,
      final int value when value >= 0 => '$value',
      _ => null,
    };
    final policy = switch (payload['org_offline_policy']) {
      0 || '0' => 'disabled',
      1 || '1' => '1h',
      2 || '2' => '4h',
      3 || '3' => '24h',
      _ => null,
    };
    final policyVersionValue = payload['org_offline_policy_ver'];
    final policyVersion = switch (policyVersionValue) {
      final int value when value > 0 => value,
      final String value when RegExp(r'^[1-9][0-9]*$').hasMatch(value) =>
        int.tryParse(value),
      _ => null,
    };
    if (principalId is! String ||
        principalId.isEmpty ||
        organizationId == null ||
        generation == null ||
        policy == null ||
        policyVersion == null) {
      throw const FormatException('Missing Member sync session authority');
    }
    return MemberSyncSessionAuthority(
      principalId: principalId,
      organizationId: organizationId,
      organizationMembershipGeneration: generation,
      offlinePolicy: policy,
      offlinePolicyVersion: policyVersion,
    );
  }
}
