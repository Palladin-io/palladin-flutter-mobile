import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/entry_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/repositories/entry_repository_impl.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/import_draft.dart';

class _MockEntryRemoteDatasource extends Mock
    implements EntryRemoteDatasource {}

class _MockVaultRemoteDatasource extends Mock
    implements VaultRemoteDatasource {}

class _MockEntryCryptoService extends Mock implements EntryCryptoService {}

class _MockEntryV2CryptoService extends Mock implements EntryV2CryptoService {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
      MemberSecret(
        entryType: VaultEntryType.key,
        memberLabel: 'fallback',
        agentLabel: null,
        description: null,
        icon: null,
        color: null,
        discoverable: false,
        content: const KeySecretContent(
          value: '',
          notes: null,
          customFields: [],
        ),
        agentFieldAccess: const {
          'memberLabel': AgentFieldAccess.never,
          'agentLabel': AgentFieldAccess.never,
          'description': AgentFieldAccess.never,
          'icon': AgentFieldAccess.never,
          'color': AgentFieldAccess.never,
          'entryType': AgentFieldAccess.never,
          'key.value': AgentFieldAccess.never,
          'notes': AgentFieldAccess.never,
        },
      ),
    );
    registerFallbackValue(
      const UpdateEntryV2Request(
        vaultId: 'fallback',
        entryId: 'fallback',
        baseRevision: '1',
        envelopes: EntryEnvelopeBundleModel(
          entryKey: {},
          memberIndex: {},
          memberSecret: {},
          agentDiscovery: null,
        ),
        agentDiscoveryChanged: false,
      ),
    );
  });

  test(
    'import invalidates on first write and rebuilds after completion',
    () async {
      final entryDatasource = _MockEntryRemoteDatasource();
      final cryptoService = _MockEntryCryptoService();
      final notifier = AutoFillMutationNotifier();
      final v2Crypto = _MockEntryV2CryptoService();
      final sessions = VaultSessionStore()
        ..install(
          organizationId: 'organization-1',
          vaultId: 'vault-1',
          vaultKey: Uint8List(32),
          vaultDiscoveryKey: Uint8List(32),
          epoch: const VaultKeyEpoch(
            vaultKeyVersion: 1,
            vdkVersion: 1,
            agentMessageKeyVersion: 1,
            manifestSigningKeyVersion: 1,
          ),
          memberKeyGeneration: 1,
          wrapper: const MemberVaultKeyWrapperMetadata(
            wrapperSuiteId: 'suite',
            wrappedKeyVersion: 1,
            memberKeyGeneration: 1,
            recipientKeyVersion: 1,
            recipientFingerprint: 'fingerprint',
          ),
        );
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
        () => entryDatasource.getEntryV2('vault-1', 'entry-1'),
      ).thenAnswer((_) async => {'currentRevision': '1'});
      when(
        () => entryDatasource.listActiveGrants('vault-1'),
      ).thenAnswer((_) async => const []);
      when(
        () => v2Crypto.seal(
          organizationId: any(named: 'organizationId'),
          vaultId: any(named: 'vaultId'),
          entryId: any(named: 'entryId'),
          revision: any(named: 'revision'),
          vaultKeyVersion: any(named: 'vaultKeyVersion'),
          vdkVersion: any(named: 'vdkVersion'),
          memberKeyGeneration: any(named: 'memberKeyGeneration'),
          operation: any(named: 'operation'),
          secret: any(named: 'secret'),
          vaultKey: any(named: 'vaultKey'),
          vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
        ),
      ).thenAnswer(
        (_) async => const EntryEnvelopeBundleModel(
          entryKey: {},
          memberIndex: {},
          memberSecret: {},
          agentDiscovery: null,
        ),
      );
      when(
        () => entryDatasource.updateEntryV2('vault-1', 'entry-1', any()),
      ).thenAnswer((_) async => {'currentRevision': '2'});
      final repository = EntryRepositoryImpl(
        entryDatasource: entryDatasource,
        vaultDatasource: _MockVaultRemoteDatasource(),
        cryptoService: cryptoService,
        entryV2CryptoService: v2Crypto,
        sessionStore: sessions,
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
        AutoFillMutationAction.rebuild,
      ]);
      await subscription.cancel();
    },
  );
}
