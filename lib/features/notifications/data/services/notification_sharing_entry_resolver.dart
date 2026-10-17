import 'dart:typed_data';

import '../../../vault/data/services/member_entry_list_service.dart';
import '../../../vault/data/services/member_sync_service.dart';
import '../../../vault/domain/entities/entry_entity.dart';
import '../../../vault/domain/entities/member_index_entry.dart';
import '../../domain/entities/entry_sharing_notification_target.dart';

final class NotificationSharingEntryResolver {
  const NotificationSharingEntryResolver({
    required this.entries,
    required this.readAuthority,
  });

  final MemberEntryListLoader entries;
  final Future<MemberSyncSessionAuthority> Function() readAuthority;

  Future<EntryEntity?> resolve({
    required EntrySharingNotificationTarget target,
    required String principalId,
    required Uint8List memberPrivateKey,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    try {
      final owner = await readAuthority();
      if (!isCurrent() || owner.principalId != principalId) return null;
      final localEntries = await entries.load(
        vaultId: target.vaultId,
        memberPrivateKey: memberPrivateKey,
      );
      if (!isCurrent()) return null;
      final current = await readAuthority();
      if (!isCurrent() ||
          current.principalId != owner.principalId ||
          current.organizationId != owner.organizationId ||
          current.organizationMembershipGeneration !=
              owner.organizationMembershipGeneration) {
        return null;
      }
      final matches = localEntries
          .where((entry) => entry.entryId == target.entryId)
          .toList(growable: false);
      if (matches.length != 1) return null;
      final entry = matches.single;
      if (entry.corrupt ||
          (entry.state != MemberEntryState.active &&
              entry.state != MemberEntryState.archived)) {
        return null;
      }
      final now = DateTime.now();
      return EntryEntity(
        id: entry.entryId,
        vaultId: target.vaultId,
        label: entry.memberLabel,
        icon: entry.iconReference,
        type: EntryTypeExtension.fromWire(entry.entryType),
        createdAt: now,
        updatedAt: now,
        lifecycleState: entry.state,
        currentRevision: entry.revision,
        currentKeyVersion: entry.currentKeyVersion,
      );
    } catch (_) {
      return null;
    }
  }
}
