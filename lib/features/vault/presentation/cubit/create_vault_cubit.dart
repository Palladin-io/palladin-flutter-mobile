import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../data/services/vault_crypto_service.dart';
import '../../domain/entities/vault_entity.dart';
import '../../domain/exceptions/vault_exceptions.dart';
import '../../domain/repositories/vault_repository.dart';
import 'create_vault_state.dart';

export 'create_vault_state.dart';

/// Drives the "Create vault" bottom sheet.
///
/// The cubit is intentionally stateless between submissions — it owns
/// only loading / success / error state. All form values (name, icon,
/// color, mode) live in the sheet widget.
///
/// On submit:
///   1. Generate a fresh 32-byte VK, seal it for the user's public key
///      (derived locally from the unlocked private key), base64-encode.
///   2. POST `/api/vaults` with the sealed VK and metadata.
///   3. Emit [CreateVaultSuccess] with the created entity.
class CreateVaultCubit extends Cubit<CreateVaultState> {
  CreateVaultCubit({
    required this.repository,
    required this.cryptoService,
  }) : super(const CreateVaultInitial());

  final VaultRepository repository;
  final VaultCryptoService cryptoService;

  /// Runs the create-vault pipeline.
  ///
  /// [privateKey] must come from the unlocked auth state — passing
  /// `null` (or an empty list) is a programming error and surfaces
  /// as [VaultErrorKind.unknown].
  Future<void> createVault({
    required String name,
    String? description,
    String? icon,
    String? color,
    required GrantMode grantMode,
    required Uint8List privateKey,
  }) async {
    if (name.trim().isEmpty || privateKey.isEmpty) {
      AppLogger.w('Vault', 'createVault called with invalid input');
      emit(const CreateVaultError(VaultErrorKind.unknown));
      return;
    }

    AppLogger.d('Vault', 'Creating vault "$name"');
    emit(const CreateVaultLoading());
    try {
      final wrappedVK = await cryptoService.generateWrappedVK(privateKey);
      final vault = await repository.createVault(
        name: name.trim(),
        description: _trimToNull(description),
        icon: _trimToNull(icon),
        color: _trimToNull(color),
        grantMode: grantMode,
        wrappedVK: wrappedVK,
      );
      AppLogger.i('Vault', 'Vault created: id=${vault.id}');
      emit(CreateVaultSuccess(vault));
    } on VaultException catch (e) {
      AppLogger.w('Vault', 'Vault creation failed: ${e.kind.name}');
      emit(CreateVaultError(e.kind));
    } catch (e, s) {
      AppLogger.e('Vault', 'Vault creation failed unexpectedly',
          error: e, stackTrace: s);
      emit(const CreateVaultError(VaultErrorKind.unknown));
    }
  }

  /// Drops any error / success state back to [CreateVaultInitial].
  /// Called when the sheet is reopened so a stale error banner doesn't
  /// linger over a fresh form.
  void reset() {
    if (state is CreateVaultInitial) return;
    emit(const CreateVaultInitial());
  }

  String? _trimToNull(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
