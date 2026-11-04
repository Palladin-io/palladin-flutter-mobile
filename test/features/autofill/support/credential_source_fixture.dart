import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/models/member_sync_models.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';

class TestAutoFillEntries extends Mock implements LocalCurrentEntryService {}

class TestAutoFillIndex implements MemberIndexReader {
  List<MemberIndexEntry> values = [];
  Future<void> Function()? waiting;
  @override
  List<MemberIndexEntry> entries(String vaultId) => values;
  @override
  Future<void> waitForCurrent(String vaultId) async => waiting?.call();
}

MemberIndexEntry syntheticAutoFillEntry(
  String id, {
  String domain = 'login.example.com',
  MemberEntryState state = MemberEntryState.active,
  bool corrupt = false,
  int type = 1,
  String revision = '1',
}) => MemberIndexEntry(
  entryId: id,
  entryType: type,
  memberLabel: id,
  searchFields: const [],
  revision: revision,
  state: state,
  corrupt: corrupt,
  autofillDomains: [domain],
);

LocalCurrentEntryReveal syntheticAutoFillReveal({bool expired = false}) =>
    LocalCurrentEntryReveal(
      snapshot: CanonicalEntrySnapshot(
        entry: {
          'id': 'chosen',
          'vaultId': 'vault',
          'organizationId': 'org',
          'state': 'active',
          'currentRevision': '1',
          'currentKeyVersion': 1,
        },
        payload: {
          'username': 'synthetic-user',
          'password': 'synthetic-password',
        },
        secret: {'type': 'CREDENTIAL'},
      ),
      accessContext: MemberOfflineAccessContext(
        contextVersion: 1,
        principalId: 'user',
        organizationId: 'org',
        organizationMembershipGeneration: '1',
        vaultId: 'vault',
        memberId: 'member',
        memberKeyGeneration: 1,
        vaultKeyVersion: 1,
        memberRecipientKeyVersion: 1,
        memberRecipientKeyFingerprint: 'synthetic',
        offlinePolicy: '24h',
        offlinePolicyVersion: 1,
        issuedAt: DateTime.utc(2026),
        notAfter: expired ? DateTime.utc(2026, 1, 2) : DateTime.utc(2100),
      ),
    );
