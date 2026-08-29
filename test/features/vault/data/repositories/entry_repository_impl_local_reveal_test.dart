import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/repositories/entry_repository_impl.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/local_current_entry_service.dart';

class _MockEntryRemote extends Mock implements EntryRemoteDatasource {}

class _MockVaultRemote extends Mock implements VaultRemoteDatasource {}

class _MockLegacyCrypto extends Mock implements EntryCryptoService {}

class _MockLocalCurrent extends Mock implements LocalCurrentEntryService {}

void main() {
  setUpAll(() => registerFallbackValue(Uint8List(32)));

  test(
    'reveal/copy source uses local complete item with zero HTTP calls',
    () async {
      final entries = _MockEntryRemote();
      final vaults = _MockVaultRemote();
      final crypto = _MockLegacyCrypto();
      final local = _MockLocalCurrent();
      when(
        () => local.revealCurrent(
          vaultId: 'vault-1',
          entryId: 'entry-1',
          memberPrivateKey: any(named: 'memberPrivateKey'),
        ),
      ).thenAnswer(
        (_) async => CanonicalEntrySnapshot(
          entry: {
            'currentRevision': '12',
            'currentKeyVersion': 5,
            'updatedAt': '2026-08-29T08:12:00Z',
          },
          secret: {
            'entryType': 1,
            'memberLabel': 'Offline credential',
            'description': 'Available without API',
            'content': {
              'username': 'member@example.test',
              'password': 'fixture-secret',
            },
          },
          payload: {
            'username': 'member@example.test',
            'password': 'fixture-secret',
          },
        ),
      );
      final repository = EntryRepositoryImpl(
        entryDatasource: entries,
        vaultDatasource: vaults,
        cryptoService: crypto,
        localCurrentEntry: local,
      );

      final revealed = await repository.revealEntry(
        vaultId: 'vault-1',
        entryId: 'entry-1',
        privateKey: Uint8List(32),
      );

      expect(revealed.entry.currentRevision, '12');
      expect(revealed.entry.currentKeyVersion, 5);
      expect(revealed.payload['password'], 'fixture-secret');
      verifyZeroInteractions(entries);
      verifyZeroInteractions(vaults);
      verifyZeroInteractions(crypto);
    },
  );
}
