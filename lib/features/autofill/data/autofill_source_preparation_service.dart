import 'dart:typed_data';

import '../../vault/data/services/member_sync_service.dart';
import '../../vault/data/services/member_sync_session_authority_provider.dart';
import '../domain/autofill_cache_invalidator.dart';
import 'autofill_source_access_service.dart';

/// Authorizes the canonical ciphertext source after existing Member sync.
/// Does not open Entry secrets or create a second credential database.
final class AutoFillSourcePreparationService
    implements AutoFillPreparedCacheSynchronizer {
  AutoFillSourcePreparationService({
    required AutoFillSourceAccessService source,
    required MemberAutoFillMetadataReader metadata,
    required MemberSyncSessionAuthorityProvider authority,
  }) : _source = source,
       _metadata = metadata,
       _authority = authority;

  final AutoFillSourceAccessService _source;
  final MemberAutoFillMetadataReader _metadata;
  final MemberSyncSessionAuthorityProvider _authority;
  final List<AutoFillSourceMutation> _failedRepairs = [];

  List<String>? _preparedVaultIds;
  void Function()? _validatePrepared;

  /// Reuses RAM indexes, never native authorization. The caller still publishes
  /// through the durable repair gate and native source acknowledgement.
  List<String>? preparedVaultIds() {
    final validate = _validatePrepared;
    if (validate == null) return null;
    try {
      validate();
      return _preparedVaultIds;
    } catch (_) {
      _validatePrepared = null;
      _preparedVaultIds = null;
      return null;
    }
  }

  @override
  Future<void> synchronizePrepared({
    required Uint8List privateKey,
    required Iterable<String> vaultIds,
  }) async {
    _validatePrepared = null;
    _preparedVaultIds = null;
    final ticket = await _source.ticket();
    try {
      final authority = await _authority.captureForPreparation();
      _source.validateAuthority(ticket, authority.claims);
      final snapshot = await _metadata.readAutoFillMetadata(
        vaultIds: vaultIds,
        authority: authority.claims,
      );
      await _metadata.revalidateAutoFillMetadata(
        snapshot,
        authority: authority.claims,
      );
      void validate() {
        authority.validateCurrent();
        _source.validateAuthority(ticket, authority.claims);
        _metadata.validateAutoFillPublication(snapshot);
      }

      validate();
      for (final owner in _failedRepairs) {
        if (_source.ownsMutation(owner)) _source.complete(owner);
      }
      await _source.activate(expected: ticket, validateSource: validate);
      _failedRepairs.clear();
      validate();
      _preparedVaultIds = List.unmodifiable(snapshot.vaults.keys);
      _validatePrepared = _reuseValidator(
        ticket,
        authority,
        MemberAutoFillMetadata(
          readGeneration: snapshot.readGeneration,
          publicationRevision: snapshot.publicationRevision,
          contentRevision: snapshot.contentRevision,
          vaults: Map.unmodifiable({
            for (final vault in snapshot.vaults.entries)
              vault.key: MemberAutoFillVaultMetadata(
                context: vault.value.context,
                sequence: vault.value.sequence,
                entries: const [],
              ),
          }),
        ),
      );
    } catch (_) {
      if (_source.owns(ticket)) {
        _failedRepairs.add(await _source.invalidate());
      }
      rethrow;
    }
  }

  // Separate closure scope retains only value-free fences, never the original
  // snapshot with plaintext labels, usernames and domains after a Vault lock.
  void Function() _reuseValidator(
    AutoFillSourceTicket ticket,
    MemberPreparationAuthority authority,
    MemberAutoFillMetadata stamp,
  ) => () {
    authority.validateCurrent();
    _source.validateAuthority(ticket, authority.claims);
    _metadata.validateAutoFillPublication(stamp);
  };
}
