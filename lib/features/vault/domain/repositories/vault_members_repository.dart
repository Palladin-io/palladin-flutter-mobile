import '../entities/vault_member.dart';

/// Failure semantics for Member directory and staged removal operations.
enum VaultMembersErrorKind { forbidden, protectedMember, network, unknown }

final class VaultMembersException implements Exception {
  const VaultMembersException(this.kind);
  final VaultMembersErrorKind kind;
}

/// Domain boundary for bounded Member management.
abstract interface class VaultMembersRepository {
  Future<List<VaultMember>> list(String vaultId);

  Future<void> requestRemoval(String memberId);
}
