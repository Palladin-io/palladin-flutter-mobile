final class MemberVaultKeyContext {
  MemberVaultKeyContext({
    required Map<String, dynamic> memberVaultKey,
    required this.memberKeyGeneration,
  }) : memberVaultKey = Map.unmodifiable(memberVaultKey);

  final Map<String, dynamic> memberVaultKey;
  final int memberKeyGeneration;
}

/// Process-memory-only cache for the encrypted Member Vault key context
/// already returned by `GET /api/vaults`.
final class MemberVaultKeyContextStore {
  final Map<String, MemberVaultKeyContext> _contexts = {};

  MemberVaultKeyContext? get(String vaultId) => _contexts[vaultId];

  void install({
    required String vaultId,
    required Map<String, dynamic> memberVaultKey,
    required int memberKeyGeneration,
  }) {
    if (vaultId.isEmpty || memberKeyGeneration < 1) {
      throw ArgumentError('Invalid Member Vault key context');
    }
    _contexts[vaultId] = MemberVaultKeyContext(
      memberVaultKey: memberVaultKey,
      memberKeyGeneration: memberKeyGeneration,
    );
  }

  void clear() => _contexts.clear();
}
