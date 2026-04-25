import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';

/// Base class for all states of the create-vault sheet.
sealed class CreateVaultState {
  const CreateVaultState();
}

/// Idle — sheet is open but the user hasn't submitted yet.
final class CreateVaultInitial extends CreateVaultState {
  const CreateVaultInitial();
}

/// A create request is in flight (crypto + network).
final class CreateVaultLoading extends CreateVaultState {
  const CreateVaultLoading();
}

/// The vault was successfully created. [vault] is the created entity
/// — useful for the UI to navigate straight into it.
final class CreateVaultSuccess extends CreateVaultState {
  const CreateVaultSuccess(this.vault);

  final VaultEntity vault;
}

/// Creation failed. [kind] is a typed error so the UI can render the
/// correct localized message (especially `planLimitReached` and
/// `fullModeNotAllowed`, which are user-actionable).
final class CreateVaultError extends CreateVaultState {
  const CreateVaultError(this.kind);

  final VaultErrorKind kind;
}
