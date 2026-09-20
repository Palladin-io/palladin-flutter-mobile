import '../../../../../core/crypto/vault_session_store.dart';
import '../../../../../core/storage/secure_token_storage.dart';
import '../../../../../core/utils/jwt_claims.dart';
import '../../../domain/entities/entry_share_reception.dart';

final class EntryShareRecipientAuthority {
  const EntryShareRecipientAuthority(this._tokens, this._keys);
  final SecureTokenStorage _tokens;
  final VaultSessionStore _keys;

  Future<EntryShareRecipientOwner?> read(String? expectedPrincipal) async {
    final generation = _keys.memberKeySessionGeneration;
    if (expectedPrincipal == null) {
      return (
        principalId: null,
        organizationId: null,
        authorizationGeneration: null,
        keyGeneration: generation,
      );
    }
    final token = await _tokens.accessToken;
    if (token == null || generation != _keys.memberKeySessionGeneration) {
      return null;
    }
    final claims = JwtClaims.decodePayload(token);
    if (claims['sub'] != expectedPrincipal) return null;
    final authorization = switch (claims['authz_ver']) {
      final String value => value,
      final int value => '$value',
      _ => null,
    };
    if (authorization == null) return null;
    return (
      principalId: expectedPrincipal,
      organizationId: JwtClaims.organizationIdFrom(token),
      authorizationGeneration: authorization,
      keyGeneration: generation,
    );
  }
}
