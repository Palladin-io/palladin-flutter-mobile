import 'dart:typed_data';

import '../../../../core/utils/app_logger.dart';
import '../../../vault/data/services/member_entry_list_service.dart';
import '../../domain/entities/grant.dart';
import '../models/grant_model.dart';

typedef GrantEntryLabelTarget = ({
  GrantScope scope,
  String grantId,
  String vaultId,
  String entryId,
});

/// Resolves Grant Entry labels from the unlocked, runtime-only MemberIndex.
final class GrantEntryLabelResolver {
  const GrantEntryLabelResolver({required MemberEntryListLoader entries})
    : _entries = entries;

  final MemberEntryListLoader _entries;

  static GrantEntryLabelTarget? targetFor(GrantModel grant) {
    final entryId = grant.entryId;
    if (grant.type != GrantScope.granular ||
        entryId == null ||
        entryId.isEmpty) {
      return null;
    }
    return (
      scope: grant.type,
      grantId: grant.id,
      vaultId: grant.vaultId,
      entryId: entryId,
    );
  }

  Future<Map<GrantEntryLabelTarget, String>> resolve({
    required List<GrantModel> grants,
    required Uint8List memberPrivateKey,
  }) async {
    final grantsByVault = <String, List<GrantModel>>{};
    for (final grant in grants) {
      final target = targetFor(grant);
      if (target == null) continue;
      (grantsByVault[grant.vaultId] ??= []).add(grant);
    }

    final resolved = <GrantEntryLabelTarget, String>{};
    for (final vault in grantsByVault.entries) {
      try {
        final index = await _entries.load(
          vaultId: vault.key,
          memberPrivateKey: memberPrivateKey,
        );
        final labels = {
          for (final entry in index)
            if (!entry.corrupt && entry.memberLabel.trim().isNotEmpty)
              entry.entryId: entry.memberLabel.trim(),
        };
        for (final grant in vault.value) {
          final target = targetFor(grant)!;
          final label = labels[target.entryId];
          if (label != null) resolved[target] = label;
        }
      } catch (_) {
        AppLogger.w('Grants', 'Local Grant Entry label resolution failed');
      }
    }
    return Map.unmodifiable(resolved);
  }
}
