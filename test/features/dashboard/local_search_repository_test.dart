import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/dashboard/data/repositories/local_search_repository_impl.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/search_result_entity.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';

class MockVaultListCubit extends Mock implements VaultListCubit {}

class MockMemberIndexReader extends Mock implements MemberIndexReader {}

final _vault = VaultEntity(
  id: 'v1',
  name: 'Production',
  grantMode: GrantMode.granular,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  entryCount: 2,
  activeGrantCount: 0,
  memberCount: 1,
);

void main() {
  late MockVaultListCubit vaults;
  late MockMemberIndexReader index;

  setUp(() {
    vaults = MockVaultListCubit();
    index = MockMemberIndexReader();
    when(() => vaults.state).thenReturn(VaultListLoaded([_vault]));
  });

  test(
    'searches only active non-corrupt runtime projections deterministically',
    () {
      when(() => index.entries('v1')).thenReturn(const [
        MemberIndexEntry(
          entryId: 'e2',
          entryType: 1,
          memberLabel: 'Stripe secondary',
          searchFields: [],
          revision: '2',
          state: MemberEntryState.active,
        ),
        MemberIndexEntry(
          entryId: 'e1',
          entryType: 1,
          memberLabel: 'Stripe primary',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.active,
        ),
        MemberIndexEntry(
          entryId: 'archived',
          entryType: 1,
          memberLabel: 'Stripe archived',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.archived,
        ),
        MemberIndexEntry(
          entryId: 'corrupt',
          entryType: 1,
          memberLabel: 'Stripe corrupt',
          searchFields: [],
          revision: '1',
          state: MemberEntryState.active,
          corrupt: true,
        ),
      ]);
      final results = LocalSearchRepositoryImpl(
        vaults: vaults,
        memberIndex: index,
      ).search('stripe', limit: 10);
      expect(results.whereType<EntrySearchResult>().map((e) => e.entryId), [
        'e1',
        'e2',
      ]);
    },
  );

  test('max-size runtime index remains deterministic and result-bounded', () {
    when(() => index.entries('v1')).thenReturn(
      List.generate(
        20000,
        (i) => MemberIndexEntry(
          entryId: 'e$i',
          entryType: 1,
          memberLabel: 'match $i',
          searchFields: const [],
          revision: '$i',
          state: MemberEntryState.active,
        ),
      ),
    );
    final results = LocalSearchRepositoryImpl(
      vaults: vaults,
      memberIndex: index,
    ).search('match', limit: 10);
    expect(results, hasLength(10));
    expect(
      results.whereType<EntrySearchResult>().map((entry) => entry.entryId),
      [
        'e0',
        'e1',
        'e10',
        'e100',
        'e1000',
        'e1001',
        'e1002',
        'e1003',
        'e1004',
        'e1005',
      ],
    );
  });

  test('locked Vault state exposes no local results or recents', () {
    when(() => vaults.state).thenReturn(const VaultListLocked());
    final repository = LocalSearchRepositoryImpl(
      vaults: vaults,
      memberIndex: index,
    );
    expect(repository.search('secret'), isEmpty);
    expect(repository.recentEntries(), isEmpty);
    verifyNever(() => index.entries(any()));
  });
}
