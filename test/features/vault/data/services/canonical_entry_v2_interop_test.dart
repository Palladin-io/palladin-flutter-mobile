import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/grants/data/datasources/grants_remote_datasource.dart';
import 'package:mobile_palladin/features/grants/data/models/grant_model.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/entry_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _Grants extends Mock implements GrantsRemoteDatasource {}

class _EntryV2 extends Mock implements EntryV2CryptoService {}

class _UnusedEnvelopes implements VaultEnvelopeCryptography {
  Never _unused() => throw StateError('legacy envelope path used');
  @override
  Future<Uint8List> decrypt({
    required VaultAadProfile profile,
    required Map<String, Object?> envelope,
    required Uint8List key,
    required VaultEnvelopeExpectations expected,
  }) async => _unused();
  @override
  Future<Map<String, String>> encrypt({
    required VaultAadProfile profile,
    required Map<String, Object?> context,
    required Uint8List plaintext,
    required Uint8List key,
  }) async => _unused();
  @override
  Future<Uint8List> randomKey() async => _unused();
  @override
  Future<Uint8List> sealPackage({
    required Uint8List packageBytes,
    required Uint8List recipientPublicKey,
  }) async => _unused();
}

void main() {
  const orgId = '11111111-1111-4111-8111-111111111111';
  const vaultId = '22222222-2222-4222-8222-222222222222';
  const entryId = '33333333-3333-4333-8333-333333333333';
  late _Entries entries;
  late _Vaults vaults;
  late _Keys keys;
  late _Grants grants;
  late _EntryV2 crypto;
  late CanonicalEntryDetailService service;
  final bundle = const EntryEnvelopeBundleModel(
    entryKey: {
      'descriptor': {'resourceRevision': '4'},
    },
    memberIndex: {
      'descriptor': {'resourceRevision': '8'},
    },
    memberSecret: {
      'descriptor': {'resourceRevision': '8'},
    },
    agentDiscovery: {
      'descriptor': {'resourceRevision': '6'},
    },
  );
  Map<String, dynamic> descriptor(int purpose, String revision) => {
    'protocolVersion': 2,
    'cryptoSuiteId': 'palladin.vault.xchacha20poly1305.v1',
    'purpose': purpose,
    'scope': {'organizationId': orgId, 'vaultId': vaultId, 'entryId': entryId},
    'resourceRevision': revision,
    'keyVersion': 2,
    'memberKeyGeneration': 3,
    'binding': {'wrappingVaultKeyVersion': 4},
  };
  Map<String, dynamic> head({int state = 1}) => {
    'organizationId': orgId,
    'vaultId': vaultId,
    'id': entryId,
    'state': state,
    'currentRevision': '7',
    'memberIndexRevision': '3',
    'agentDiscoveryRevisionHighWatermark': '5',
    'currentKeyVersion': 2,
    'entryKey': {
      'descriptor': descriptor(5, '4'),
      'encodedSuitePayload': 'opaque',
    },
    'memberSecret': {
      'descriptor': descriptor(3, '7'),
      'encodedSuitePayload': 'opaque',
    },
  };
  final canonicalSecret = <String, dynamic>{
    'schema': MemberSecret.schema,
    'entryType': 'key',
    'memberLabel': 'Key',
    'agentLabel': 'Key',
    'description': null,
    'icon': null,
    'color': null,
    'discoverable': true,
    'content': {'value': 'secret', 'notes': null, 'customFields': []},
    'agentFieldAccess': {
      'memberLabel': 'never',
      'agentLabel': 'discovery',
      'description': 'never',
      'icon': 'never',
      'color': 'never',
      'entryType': 'discovery',
      'key.value': 'onGrantValue',
      'notes': 'onGrantValue',
    },
  };

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(
      MemberSecret(
        entryType: VaultEntryType.key,
        memberLabel: 'x',
        agentLabel: 'x',
        description: null,
        icon: null,
        color: null,
        discoverable: true,
        content: const KeySecretContent(
          value: '',
          notes: null,
          customFields: [],
        ),
        agentFieldAccess: const {
          'memberLabel': AgentFieldAccess.never,
          'agentLabel': AgentFieldAccess.discovery,
          'description': AgentFieldAccess.never,
          'icon': AgentFieldAccess.never,
          'color': AgentFieldAccess.never,
          'entryType': AgentFieldAccess.discovery,
          'key.value': AgentFieldAccess.onGrantValue,
          'notes': AgentFieldAccess.onGrantValue,
        },
      ),
    );
  });
  setUp(() {
    entries = _Entries();
    vaults = _Vaults();
    keys = _Keys();
    grants = _Grants();
    crypto = _EntryV2();
    service = CanonicalEntryDetailService(
      entries: entries,
      vaults: vaults,
      keys: keys,
      envelopes: _UnusedEnvelopes(),
      grants: grants,
      entryV2: crypto,
    );
    when(() => vaults.getEncryptedVault(vaultId)).thenAnswer(
      (_) async => {
        'organizationId': orgId,
        'memberKeyGeneration': 3,
        'currentKeyEpoch': {'vaultKeyVersion': 4, 'vdkVersion': 6},
        'memberVaultKey': <String, dynamic>{},
        'discoveryKey': <String, dynamic>{},
      },
    );
    when(
      () => keys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => keys.openDiscoveryKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => grants.listGrants(
        vaultId,
        status: 'active',
        cursor: any(named: 'cursor'),
        pageSize: 100,
      ),
    ).thenAnswer((_) async => const GrantPage(grants: []));
    when(
      () => crypto.openEntryDek(
        entryKey: any(named: 'entryKey'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => crypto.openMemberSecret(
        entryKey: any(named: 'entryKey'),
        memberSecret: any(named: 'memberSecret'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenAnswer((_) async => canonicalSecret);
    when(
      () => crypto.seal(
        organizationId: any(named: 'organizationId'),
        vaultId: any(named: 'vaultId'),
        entryId: any(named: 'entryId'),
        revision: any(named: 'revision'),
        entryKeyRevision: any(named: 'entryKeyRevision'),
        memberIndexRevision: any(named: 'memberIndexRevision'),
        agentDiscoveryRevision: any(named: 'agentDiscoveryRevision'),
        entryKeyVersion: any(named: 'entryKeyVersion'),
        vaultKeyVersion: any(named: 'vaultKeyVersion'),
        vdkVersion: any(named: 'vdkVersion'),
        memberKeyGeneration: any(named: 'memberKeyGeneration'),
        operation: any(named: 'operation'),
        secret: any(named: 'secret'),
        vaultKey: any(named: 'vaultKey'),
        vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
        existingEntryDek: any(named: 'existingEntryDek'),
      ),
    ).thenAnswer((_) async => bundle);
  });

  test(
    'canonical update preserves independent revisions and reuses EntryDEK',
    () async {
      when(
        () => entries.updateCanonicalEntry(vaultId, entryId, any()),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/update'),
          statusCode: 200,
        ),
      );
      final snapshot = CanonicalEntrySnapshot(
        entry: head(),
        secret: {
          'agentLabel': 'Key',
          'description': null,
          'agentVisibilityPolicy': {
            'discoverable': true,
            'fields': {'agentLabel': 'discovery', 'value': 'onGrantValue'},
          },
        },
        payload: {'type': 'KEY', 'value': 'secret'},
      );
      await service.update(
        snapshot: snapshot,
        expected: EntryEntity(
          id: entryId,
          vaultId: vaultId,
          label: 'Key',
          type: EntryType.key,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        label: 'Key 2',
        description: '',
        icon: '',
        type: EntryType.key,
        content: {'type': 'KEY', 'value': 'secret-2'},
        memberPrivateKey: Uint8List(32),
      );
      verify(
        () => crypto.seal(
          organizationId: orgId,
          vaultId: vaultId,
          entryId: entryId,
          revision: 8,
          entryKeyRevision: 4,
          memberIndexRevision: 4,
          agentDiscoveryRevision: 6,
          entryKeyVersion: 2,
          vaultKeyVersion: 4,
          vdkVersion: 6,
          memberKeyGeneration: 3,
          operation: 2,
          secret: any(named: 'secret'),
          vaultKey: any(named: 'vaultKey'),
          vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
          existingEntryDek: any(named: 'existingEntryDek'),
        ),
      ).called(1);
    },
  );

  test(
    'canonical restore emits operation 4 and retries identical request',
    () async {
      when(
        () => entries.getCanonicalEntry(vaultId, entryId),
      ).thenAnswer((_) async => head(state: 2));
      final requests = <Object?>[];
      var attempt = 0;
      when(
        () => entries.restoreCanonicalEntry(vaultId, entryId, any()),
      ).thenAnswer((call) async {
        requests.add(call.positionalArguments[2]);
        if (attempt++ == 0) {
          throw DioException(
            requestOptions: RequestOptions(path: '/restore'),
            type: DioExceptionType.connectionError,
          );
        }
        return Response(
          requestOptions: RequestOptions(path: '/restore'),
          statusCode: 200,
        );
      });
      await service.restoreArchived(
        vaultId: vaultId,
        archived: const MemberIndexEntry(
          entryId: entryId,
          entryType: 0,
          memberLabel: 'Key',
          searchFields: [],
          revision: '7',
          state: MemberEntryState.archived,
        ),
        memberPrivateKey: Uint8List(32),
      );
      expect(requests, hasLength(2));
      expect(identical(requests[0], requests[1]), isTrue);
      verify(
        () => crypto.seal(
          organizationId: orgId,
          vaultId: vaultId,
          entryId: entryId,
          revision: 8,
          entryKeyRevision: 4,
          memberIndexRevision: 4,
          agentDiscoveryRevision: 6,
          entryKeyVersion: 2,
          vaultKeyVersion: 4,
          vdkVersion: 6,
          memberKeyGeneration: 3,
          operation: 4,
          secret: any(named: 'secret'),
          vaultKey: any(named: 'vaultKey'),
          vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
          existingEntryDek: any(named: 'existingEntryDek'),
        ),
      ).called(1);
    },
  );
}
