import 'dart:typed_data';

import '../../../../core/utils/app_logger.dart';
import '../../../vault/data/services/member_entry_list_service.dart';
import '../../domain/entities/grant.dart';
import '../models/grant_model.dart';

/// Resolves Grant Entry labels from the unlocked, runtime-only MemberIndex.
final class GrantEntryLabelResolver {
  const GrantEntryLabelResolver({required MemberEntryListLoader entries})
    : _entries = entries;

  final MemberEntryListLoader _entries;

  Future<Map<String, String>> resolve({
    required List<GrantModel> grants,
    required Uint8List memberPrivateKey,
  }) async {
    final grantsByVault = <String, List<GrantModel>>{};
    for (final grant in grants) {
      final entryId = grant.entryId;
      if (grant.type != GrantScope.granular ||
          entryId == null ||
          entryId.isEmpty) {
        continue;
      }
      (grantsByVault[grant.vaultId] ??= []).add(grant);
    }

    final resolved = <String, String>{};
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
          final label = labels[grant.entryId];
          if (label != null) resolved[grant.id] = label;
        }
      } catch (_) {
        AppLogger.w('Grants', 'Local Grant Entry label resolution failed');
      }
    }
    return Map.unmodifiable(resolved);
  }
}
