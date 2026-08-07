import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/dashboard/data/repositories/local_search_repository_impl.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/search_result_entity.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/vault_list_cubit.dart';

class MockVaultListCubit extends Mock implements VaultListCubit {}

class MockMemberIndexReader extends Mock implements MemberIndexReader {}

class MockMemberEntryListLoader extends Mock implements MemberEntryListLoader {}

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
  late MockMemberEntryListLoader loader;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    vaults = MockVaultListCubit();
    index = MockMemberIndexReader();
    loader = MockMemberEntryListLoader();
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
        entryLoader: loader,
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
      entryLoader: loader,
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
        'e10000',
        'e10001',
        'e10002',
        'e10003',
        'e10004',
      ],
    );
  });

  test('search traverses the final entry in the supported 20k index', () {
    when(() => index.entries('v1')).thenReturn(
      List.generate(
        20000,
        (i) => MemberIndexEntry(
          entryId: 'e$i',
          entryType: 1,
          memberLabel: i == 19999 ? 'last needle' : 'unrelated $i',
          searchFields: const [],
          revision: '$i',
          state: MemberEntryState.active,
        ),
      ),
    );

    final results = LocalSearchRepositoryImpl(
      vaults: vaults,
      memberIndex: index,
      entryLoader: loader,
    ).search('needle', limit: 10);

    expect(results.whereType<EntrySearchResult>().single.entryId, 'e19999');
  });

  test('locked Vault state exposes no local results or recents', () {
    when(() => vaults.state).thenReturn(const VaultListLocked());
    final repository = LocalSearchRepositoryImpl(
      vaults: vaults,
      memberIndex: index,
      entryLoader: loader,
    );
    expect(repository.search('secret'), isEmpty);
    expect(repository.recentEntries(), isEmpty);
    verifyNever(() => index.entries(any()));
  });

  test('prepare loads Vaults and decrypts every MemberIndex', () async {
    final privateKey = Uint8List(32);
    final secondVault = VaultEntity(
      id: 'v2',
      name: 'Personal',
      grantMode: GrantMode.granular,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      entryCount: 1,
      activeGrantCount: 0,
      memberCount: 1,
    );
    when(() => vaults.state).thenReturn(VaultListLoaded([_vault, secondVault]));
    when(
      () => vaults.loadForMemberIndex(any()),
    ).thenAnswer((_) async => [_vault, secondVault]);
    when(
      () => loader.load(
        vaultId: any(named: 'vaultId'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer((_) async => const []);

    await LocalSearchRepositoryImpl(
      vaults: vaults,
      memberIndex: index,
      entryLoader: loader,
    ).prepare(privateKey);

    verify(() => vaults.loadForMemberIndex(any())).called(1);
    verify(
      () => loader.load(
        vaultId: 'v1',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).called(1);
    verify(
      () => loader.load(
        vaultId: 'v2',
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).called(1);
  });
}
