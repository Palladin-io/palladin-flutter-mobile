import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/di/injection.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_creation.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_sharing_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/create_entry_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/edit_entry_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/global_entries_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/recently_deleted_cubit.dart';
import 'package:mobile_palladin/features/vault/presentation/cubit/entry_share_creation_cubit.dart';
import '../../design/mobile/vault_adapters.dart';

void main() {
  setUp(() async {
    await getIt.reset();
    await registerVaultPreview();
  });
  tearDown(() async {
    await getIt.reset();
  });

  test(
    'real create/edit/delete/restore flows update the memory index',
    () async {
      final key = Uint8List(32);
      final create = getIt<CreateEntryCubit>();
      final edit = getIt<EditEntryCubit>();
      final global = getIt<GlobalEntriesCubit>();
      final deleted = getIt<RecentlyDeletedCubit>(param1: 'vault-personal');
      await create.createEntry(
        vaultId: 'vault-personal',
        label: 'Preview regression',
        type: EntryType.credential,
        payload: {'username': 'demo', 'password': 'synthetic'},
        privateKey: key,
      );
      final entry = (create.state as CreateEntrySuccess).entry;
      await edit.revealForEdit(entry: entry, privateKey: key);
      expect((edit.state as EditEntryReady).payload['password'], 'synthetic');
      await edit.updateEntry(
        vaultId: entry.vaultId,
        entryId: entry.id,
        label: 'Edited preview',
        type: entry.type,
        payload: {'username': 'demo', 'password': 'changed synthetic'},
        privateKey: key,
        createdAt: entry.createdAt,
      );
      expect(edit.state, isA<EditEntrySuccess>());
      await global.load(vaultPreview.vaults.values.toList(), key);
      expect(
        global.state.rows.any((r) => r.entry.memberLabel == 'Edited preview'),
        isTrue,
      );
      await edit.deleteEntry(vaultId: entry.vaultId, entryId: entry.id);
      await deleted.load();
      expect(
        (deleted.state as RecentlyDeletedLoaded).items.any(
          (e) => e.entryId == entry.id,
        ),
        isTrue,
      );
      await deleted.restore(entry.id, key);
      expect(
        (deleted.state as RecentlyDeletedLoaded).items.any(
          (e) => e.entryId == entry.id,
        ),
        isFalse,
      );
      await create.close();
      await edit.close();
      await global.close();
      await deleted.close();
    },
  );

  test('share form creates synthetic links and list supports revoke', () async {
    final entry = vaultPreview.records['entry-github']!;
    final cubit = getIt<EntryShareCreationCubitFactory>()(
      expected: entry,
      sessionReader: () async => null,
      sourceReader: () async => vaultPreview.snapshot(entry.id),
    );
    await cubit.load();
    expect(cubit.state.phase, EntryShareCreationPhase.ready);
    await cubit.create(options: EntryShareCreationOptions.fromInput());
    expect(cubit.state.phase, EntryShareCreationPhase.created);
    final remote = getIt<EntrySharingRemoteDatasource>();
    final id = cubit.state.shareId!;
    await remote.revoke(
      entry.vaultId,
      entry.id,
      id,
      cancelToken: CancelToken(),
    );
    final page = await remote.list(
      entry.vaultId,
      entry.id,
      cancelToken: CancelToken(),
    );
    expect(page.items.firstWhere((s) => s.shareId == id).status, 'revoked');
    await cubit.close();
  });
}
