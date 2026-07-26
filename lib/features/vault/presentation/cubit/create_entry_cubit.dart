import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/custom_field.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../../domain/repositories/entry_repository.dart';
import '../../data/services/key_entry_creation_service.dart';
import 'create_entry_state.dart';

export 'create_entry_state.dart';

/// Drives the Add Entry page — both Key and Credential variants.
///
/// The cubit is intentionally stateless between submissions — it owns
/// only loading / success / error state. All form values live in the
/// page widget. On submit:
///
///   1. Repository fetches the vault's wrappedVK and unwraps it locally
///      with the supplied [privateKey] (zeroized in finally).
///   2. The plaintext payload is JSON-serialized + UTF-8 encoded and
///      sealed with `crypto_secretbox_easy(VK, nonce)`.
///   3. The base64-encoded `encryptedBlob` + `nonce` are wrapped in the
///      polymorphic `content` envelope and POSTed to
///      `/api/vaults/{vaultId}/entries`.
///   4. [CreateEntrySuccess] is emitted with the newly-created entry.
class CreateEntryCubit extends Cubit<CreateEntryState> {
  CreateEntryCubit({required this.repository, this.keyCreationService})
    : super(const CreateEntryInitial());

  final EntryRepository repository;
  final KeyEntryCreationService? keyCreationService;

  /// Runs the full create-entry pipeline.
  ///
  /// [privateKey] must come from the unlocked auth state — passing an
  /// empty list is a programming error and surfaces as
  /// [EntryErrorKind.unknown].
  Future<void> createEntry({
    required String vaultId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
    required Uint8List privateKey,
    String? wrappedVK,
    List<AgentField>? agentFields,
  }) async {
    if (label.trim().isEmpty || privateKey.isEmpty) {
      AppLogger.w('Entry', 'createEntry called with invalid input');
      emit(const CreateEntryError(EntryErrorKind.unknown));
      return;
    }

    AppLogger.d('Entry', 'Creating entry "${type.name}" in vault $vaultId');
    emit(const CreateEntryLoading());
    try {
      final entry = type == EntryType.key && keyCreationService != null
          ? await keyCreationService!.create(
              vaultId: vaultId,
              label: label.trim(),
              description: _trimToNull(description) ?? '',
              icon: _trimToNull(icon) ?? '',
              content: payload,
              memberPrivateKey: privateKey,
            )
          : await repository.createEntryEncrypted(
              vaultId: vaultId,
              label: label.trim(),
              description: _trimToNull(description),
              icon: _trimToNull(icon),
              type: type,
              payload: payload,
              urlDomain: _trimToNull(urlDomain),
              privateKey: privateKey,
              wrappedVK: wrappedVK,
              agentFields: agentFields,
            );
      AppLogger.i('Entry', 'Entry created: id=${entry.id}');
      emit(CreateEntrySuccess(entry));
    } on EntryException catch (e) {
      AppLogger.w('Entry', 'Entry creation failed: ${e.kind.name}');
      emit(CreateEntryError(e.kind));
    } catch (e, s) {
      AppLogger.e(
        'Entry',
        'Entry creation failed unexpectedly',
        error: e,
        stackTrace: s,
      );
      emit(const CreateEntryError(EntryErrorKind.unknown));
    }
  }

  /// Drops any error / success state back to [CreateEntryInitial].
  void reset() {
    if (state is CreateEntryInitial) return;
    emit(const CreateEntryInitial());
  }

  String? _trimToNull(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
