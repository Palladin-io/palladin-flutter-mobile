import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/entry_model.dart';
import 'package:mobile_palladin/features/vault/data/models/update_entry_request.dart';
import 'package:mobile_palladin/features/vault/data/repositories/entry_repository_impl.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/import_draft.dart';
import 'package:mobile_palladin/features/vault/domain/exceptions/entry_exceptions.dart';

class _MockEntryRemoteDatasource extends Mock
    implements EntryRemoteDatasource {}

class _MockVaultRemoteDatasource extends Mock
    implements VaultRemoteDatasource {}

class _MockEntryCryptoService extends Mock implements EntryCryptoService {}

class _FakeUpdateEntryRequest extends Fake implements UpdateEntryRequest {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(_FakeUpdateEntryRequest());
  });

  test(
    'import invalidates on first write and rebuilds after completion',
    () async {
      final entryDatasource = _MockEntryRemoteDatasource();
      final cryptoService = _MockEntryCryptoService();
      final notifier = AutoFillMutationNotifier();
      final privateKey = Uint8List(32);
      final overwrite = ImportEntryOverwrite(
        entryId: 'entry-1',
        label: 'Example',
        type: EntryType.credential,
        payload: const {'username': 'alice', 'password': 'new-password'},
        urlDomain: 'example.com',
        createdAt: DateTime.utc(2026),
      );
      when(
        () => cryptoService.unwrapVK(
          wrappedVK: 'wrapped-vk',
          privateKey: privateKey,
        ),
      ).thenAnswer((_) async => Uint8List(32));
      when(
        () => cryptoService.encryptEntry(
          payload: overwrite.payload,
          vaultKey: any(named: 'vaultKey'),
        ),
      ).thenAnswer(
        (_) async => const EntryContentModel(
          encryptedBlob: 'ciphertext',
          nonce: 'nonce',
        ),
      );
      when(
        () => entryDatasource.updateEntry('vault-1', 'entry-1', any()),
      ).thenAnswer((_) async {});
      final repository = EntryRepositoryImpl(
        entryDatasource: entryDatasource,
        vaultDatasource: _MockVaultRemoteDatasource(),
        cryptoService: cryptoService,
        autoFillMutationNotifier: notifier,
      );
      final actions = <AutoFillMutationAction>[];
      final subscription = notifier.changes.listen(actions.add);

      final result = await repository.importEntriesEncrypted(
        vaultId: 'vault-1',
        format: 'csv',
        creates: const [],
        overwrites: [overwrite],
        privateKey: privateKey,
        wrappedVK: 'wrapped-vk',
      );

      expect(result.updatedCount, 1);
      expect(actions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);
      await subscription.cancel();
    },
  );

  test(
    'delete invalidates before the lifecycle mutation and rebuilds',
    () async {
      final entryDatasource = _MockEntryRemoteDatasource();
      final notifier = AutoFillMutationNotifier();
      final actions = <AutoFillMutationAction>[];
      final subscription = notifier.changes.listen(actions.add);
      addTearDown(subscription.cancel);
      when(() => entryDatasource.deleteEntry('vault-1', 'entry-1')).thenAnswer((
        _,
      ) async {
        expect(actions, [AutoFillMutationAction.invalidate]);
      });
      final repository = EntryRepositoryImpl(
        entryDatasource: entryDatasource,
        vaultDatasource: _MockVaultRemoteDatasource(),
        cryptoService: _MockEntryCryptoService(),
        autoFillMutationNotifier: notifier,
      );

      await repository.deleteEntry(vaultId: 'vault-1', entryId: 'entry-1');

      expect(actions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);
    },
  );

  test('ambiguous delete failure leaves AutoFill invalidated', () async {
    final entryDatasource = _MockEntryRemoteDatasource();
    final notifier = AutoFillMutationNotifier();
    final actions = <AutoFillMutationAction>[];
    final subscription = notifier.changes.listen(actions.add);
    addTearDown(subscription.cancel);
    when(() => entryDatasource.deleteEntry('vault-1', 'entry-1')).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/entries/entry-1'),
        type: DioExceptionType.connectionError,
      ),
    );
    final repository = EntryRepositoryImpl(
      entryDatasource: entryDatasource,
      vaultDatasource: _MockVaultRemoteDatasource(),
      cryptoService: _MockEntryCryptoService(),
      autoFillMutationNotifier: notifier,
    );

    await expectLater(
      repository.deleteEntry(vaultId: 'vault-1', entryId: 'entry-1'),
      throwsA(isA<EntryException>()),
    );

    expect(actions, [AutoFillMutationAction.invalidate]);
  });
}
