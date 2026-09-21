import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/member_entry_list_service.dart';
import 'package:mobile_palladin/features/vault/data/services/member_sync_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/global_entries_cubit.dart';

VaultEntity vault(String id) => VaultEntity(
  id: id,
  name: id,
  grantMode: GrantMode.granular,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  entryCount: 0,
  activeGrantCount: 0,
  memberCount: 1,
);

MemberIndexEntry entry(
  String id,
  String label, {
  MemberEntryState state = MemberEntryState.active,
  bool corrupt = false,
  int type = 0,
}) => MemberIndexEntry(
  entryId: id,
  entryType: type,
  memberLabel: label,
  searchFields: ['searchable'],
  revision: '1',
  state: state,
  corrupt: corrupt,
);

class Index implements MemberIndexReader {
  final values = <String, List<MemberIndexEntry>>{};
  @override
  List<MemberIndexEntry> entries(String id) => values[id] ?? [];
  @override
  Future<void> waitForCurrent(String id) async {}
}

class Loader implements MemberEntryListLoader {
  final calls = <String>[];
  Future<void> Function(String, Uint8List)? onLoad;
  @override
  Future<List<MemberIndexEntry>> load({
    required String vaultId,
    required Uint8List memberPrivateKey,
  }) async {
    calls.add(vaultId);
    await onLoad?.call(vaultId, memberPrivateKey);
    return [];
  }

  @override
  void lock() {}
}

void main() {
  late Index index;
  late Loader loader;
  late StreamController<String> updates;
  late GlobalEntriesCubit cubit;
  setUp(() {
    index = Index();
    loader = Loader();
    updates = StreamController.broadcast(sync: true);
    cubit = GlobalEntriesCubit(
      index: index,
      loader: loader,
      indexUpdates: updates.stream,
    );
  });
  tearDown(() async {
    await cubit.close();
    await updates.close();
  });

  test(
    'joins active authenticated entries from all Vaults and filters locally',
    () async {
      index.values['A'] = [
        entry('same', 'Zulu'),
        entry('old', 'Archived', state: MemberEntryState.archived),
      ];
      index.values['B'] = [
        entry('same', 'Alpha', type: 1),
        entry('bad', 'Corrupt', corrupt: true),
      ];
      await cubit.load([vault('A'), vault('B')], Uint8List(32));
      expect(cubit.state.filter().map((row) => row.entry.memberLabel), [
        'Alpha',
        'Zulu',
      ]);
      expect(
        cubit.state
            .filter(query: ' SEARCHABLE ', vaultIds: {'B'}, types: {1})
            .single
            .vault
            .id,
        'B',
      );
      expect(
        cubit.state.filter(descending: true).first.entry.memberLabel,
        'Zulu',
      );
    },
  );

  test('a failed Vault does not stop later Vault synchronization', () async {
    loader.onLoad = (id, _) async {
      if (id == 'A') throw StateError('Synthetic failure');
      index.values[id] = [entry('ok', 'Visible')];
    };
    await cubit.load([vault('A'), vault('B')], Uint8List(32));
    expect(loader.calls, ['A', 'B']);
    expect(cubit.state.failedVaultIds, {'A'});
    expect(cubit.state.rows.single.vault.id, 'B');
    expect(cubit.state.loading, isFalse);
  });

  test(
    'index purge and Vault removal immediately remove joined rows',
    () async {
      index.values['A'] = [entry('a', 'Alpha')];
      index.values['B'] = [entry('b', 'Beta')];
      await cubit.load([vault('A'), vault('B')], Uint8List(32));
      index.values.remove('A');
      updates.add('A');
      expect(cubit.state.rows.single.vault.id, 'B');
      cubit.replaceVaults([]);
      expect(cubit.state.rows, isEmpty);
    },
  );

  test(
    'lock wipes owned key copy and fences pending loads and index updates',
    () async {
      final pending = Completer<void>();
      Uint8List? borrowedKey;
      loader.onLoad = (_, key) {
        borrowedKey = key;
        return pending.future;
      };
      final source = Uint8List.fromList(List.filled(32, 7));
      final operation = cubit.load([vault('A'), vault('B')], source);
      cubit.lock();
      expect(borrowedKey, everyElement(0));
      expect(source, everyElement(7));
      index.values['A'] = [entry('late', 'Do not republish')];
      updates.add('A');
      pending.complete();
      await operation;
      expect(cubit.state.rows, isEmpty);
      expect(cubit.state.loading, isFalse);
      expect(loader.calls, ['A']);
    },
  );

  test(
    'keeps the entire supported index instead of truncating to suggestions',
    () async {
      index.values['A'] = List.generate(20000, (i) => entry('$i', 'Entry $i'));
      await cubit.load([vault('A')], Uint8List(32));
      expect(cubit.state.rows, hasLength(20000));
      expect(
        cubit.state.filter(query: 'Entry 19999').single.entry.entryId,
        '19999',
      );
    },
  );
}
