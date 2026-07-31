import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';

/// Base class for all states of the vault list screen.
sealed class VaultListState {
  const VaultListState();
}

/// Idle — nothing has been requested yet.
final class VaultListInitial extends VaultListState {
  const VaultListInitial();
}

/// A request is in flight — fetching the list or deleting an entry.
final class VaultListLoading extends VaultListState {
  const VaultListLoading();
}

/// Vault keys are unavailable; no decrypted list may remain reachable.
final class VaultListLocked extends VaultListState {
  const VaultListLocked();
}

/// Ciphertext history fell behind retention and needs a fresh snapshot.
final class VaultListResetRequired extends VaultListState {
  const VaultListResetRequired();
}

/// The most recent fetch succeeded. [vaults] is the canonical list to
/// render. May be empty (the UI shows the empty-state copy in that case).
final class VaultListLoaded extends VaultListState {
  const VaultListLoaded(this.vaults, {this.corruptVaultIds = const []});

  final List<VaultEntity> vaults;
  final List<String> corruptVaultIds;
}

/// The most recent operation failed. [kind] is a typed error so the
/// UI can render the correct localized message.
final class VaultListError extends VaultListState {
  const VaultListError(this.kind);

  final VaultErrorKind kind;
}
