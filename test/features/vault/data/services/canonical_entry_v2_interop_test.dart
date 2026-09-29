import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/core/crypto/vault_session_store.dart';
import 'package:mobile_palladin/features/autofill/data/autofill_mutation_notifier.dart';
import 'package:mobile_palladin/features/grants/data/datasources/grants_remote_datasource.dart';
import 'package:mobile_palladin/features/grants/data/models/grant_model.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/models/entry_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/models/vault_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart'
    as visibility;
import 'package:mobile_palladin/features/vault/domain/entities/member_index_entry.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_form_utils.dart';

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _VaultCrypto extends Mock implements VaultCryptoService {}

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
  late _VaultCrypto vaultCrypto;
  late _Grants grants;
  late _EntryV2 crypto;
  late CanonicalEntryDetailService service;
  late AutoFillMutationNotifier notifier;
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
    registerFallbackValue(() => true);
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
    vaultCrypto = _VaultCrypto();
    grants = _Grants();
    crypto = _EntryV2();
    notifier = AutoFillMutationNotifier();
    service = CanonicalEntryDetailService(
      entries: entries,
      vaults: vaults,
      keys: keys,
      vaultCrypto: vaultCrypto,
      envelopes: _UnusedEnvelopes(),
      grants: grants,
      entryV2: crypto,
      autoFillMutationNotifier: notifier,
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
      () => vaultCrypto.openVaultProjection(
        json: any(named: 'json'),
        memberPrivateKey: any(named: 'memberPrivateKey'),
      ),
    ).thenAnswer(
      (_) async => OpenedVaultProjection(
        organizationId: orgId,
        vaultId: vaultId,
        vaultKey: Uint8List(32),
        vaultDiscoveryKey: Uint8List(32),
        metadata: const MemberVaultMetadata(
          name: 'Vault',
          description: null,
          icon: null,
          color: null,
          grantMode: 'granular',
        ),
        epoch: const VaultKeyEpochModel(
          vaultKeyVersion: 4,
          vdkVersion: 6,
          agentMessageKeyVersion: 1,
          manifestSigningKeyVersion: 1,
        ),
        memberKeyGeneration: 3,
        wrapper: const MemberVaultKeyWrapperMetadata(
          wrapperSuiteId: 'x25519',
          wrappedKeyVersion: 4,
          memberKeyGeneration: 3,
          recipientKeyVersion: 1,
          recipientFingerprint: 'fingerprint',
        ),
      ),
    );
    when(
      () => keys.openMemberVaultKey(any(), any()),
    ).thenAnswer((_) async => Uint8List(32));
    when(
      () => keys.openMemberVaultKey(
        any(),
        any(),
        expectedOrganizationId: any(named: 'expectedOrganizationId'),
        expectedVaultId: any(named: 'expectedVaultId'),
        expectedVaultKeyVersion: any(named: 'expectedVaultKeyVersion'),
        expectedMemberKeyGeneration: any(named: 'expectedMemberKeyGeneration'),
      ),
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

  EntryEntity deletionTarget() => EntryEntity(
    id: entryId,
    vaultId: vaultId,
    label: 'Key',
    type: EntryType.key,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    currentRevision: '7',
    currentKeyVersion: 2,
  );

  test(
    'delete seals operation 5, retries identical ciphertext and rebuilds AutoFill',
    () async {
      when(
        () => entries.getCanonicalEntry(vaultId, entryId),
      ).thenAnswer((_) async => head());
      final actions = <AutoFillMutationAction>[];
      final subscription = notifier.changes.listen(actions.add);
      addTearDown(subscription.cancel);
      final requests = <Object?>[];
      when(
        () => entries.deleteEntry(
          vaultId,
          entryId,
          any(),
          isSessionCurrent: any(named: 'isSessionCurrent'),
        ),
      ).thenAnswer((call) async {
        expect(actions, [AutoFillMutationAction.invalidate]);
        requests.add(call.positionalArguments[2]);
        if (requests.length == 1) {
          throw DioException(
            requestOptions: RequestOptions(path: '/delete'),
            type: DioExceptionType.connectionError,
          );
        }
        return Response(
          requestOptions: RequestOptions(path: '/delete'),
          statusCode: 200,
        );
      });
      await service.deleteEntry(
        expected: deletionTarget(),
        memberPrivateKey: Uint8List(32),
        isSessionCurrent: () => true,
      );
      expect(requests, hasLength(2));
      expect(identical(requests.first, requests.last), isTrue);
      expect(requests.first, {
        'baseRevision': '7',
        'newEntryKey': bundle.entryKey,
        'memberSecret': bundle.memberSecret,
        'memberIndex': bundle.memberIndex,
      });
      final call = verify(
        () => crypto.seal(
          organizationId: orgId,
          vaultId: vaultId,
          entryId: entryId,
          revision: 8,
          entryKeyRevision: 1,
          memberIndexRevision: 8,
          entryKeyVersion: 3,
          vaultKeyVersion: 4,
          vdkVersion: 6,
          memberKeyGeneration: 3,
          operation: 5,
          secret: captureAny(named: 'secret'),
          vaultKey: captureAny(named: 'vaultKey'),
          vaultDiscoveryKey: captureAny(named: 'vaultDiscoveryKey'),
        ),
      ).captured;
      expect((call[0] as MemberSecret).memberLabel, 'Key');
      expect(call[1], everyElement(0));
      expect(call[2], everyElement(0));
      expect(actions, [
        AutoFillMutationAction.invalidate,
        AutoFillMutationAction.rebuild,
      ]);
    },
  );

  test('delete preserves a non-discoverable secret and its policy', () async {
    when(
      () => entries.getCanonicalEntry(vaultId, entryId),
    ).thenAnswer((_) async => head());
    final privateSecret = <String, dynamic>{
      ...canonicalSecret,
      'discoverable': false,
      'agentLabel': null,
      'agentFieldAccess': {
        ...canonicalSecret['agentFieldAccess'] as Map,
        'entryType': 'never',
        'agentLabel': 'never',
      },
    };
    when(
      () => crypto.openMemberSecret(
        entryKey: any(named: 'entryKey'),
        memberSecret: any(named: 'memberSecret'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenAnswer((_) async => privateSecret);
    when(
      () => entries.deleteEntry(
        vaultId,
        entryId,
        any(),
        isSessionCurrent: any(named: 'isSessionCurrent'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/delete'),
        statusCode: 200,
      ),
    );
    await service.deleteEntry(
      expected: deletionTarget(),
      memberPrivateKey: Uint8List(32),
      isSessionCurrent: () => true,
    );
    final secret =
        verify(
              () => crypto.seal(
                organizationId: orgId,
                vaultId: vaultId,
                entryId: entryId,
                revision: 8,
                entryKeyRevision: 1,
                memberIndexRevision: 8,
                entryKeyVersion: 3,
                vaultKeyVersion: 4,
                vdkVersion: 6,
                memberKeyGeneration: 3,
                operation: 5,
                secret: captureAny(named: 'secret'),
                vaultKey: any(named: 'vaultKey'),
                vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
              ),
            ).captured.single
            as MemberSecret;
    expect(secret.discoverable, isFalse);
    expect(secret.agentLabel, isNull);
    expect(
      secret.agentFieldAccess.values,
      isNot(contains(AgentFieldAccess.discovery)),
    );
  });

  test(
    'delete aborts after session replacement during native cache invalidation',
    () async {
      var current = true;
      when(
        () => entries.getCanonicalEntry(vaultId, entryId),
      ).thenAnswer((_) async => head());
      final subscription = notifier.changes.listen((action) {
        if (action == AutoFillMutationAction.invalidate) current = false;
      });
      addTearDown(subscription.cancel);
      await expectLater(
        service.deleteEntry(
          expected: deletionTarget(),
          memberPrivateKey: Uint8List(32),
          isSessionCurrent: () => current,
        ),
        throwsA(isA<CanonicalEntryDetailException>()),
      );
      verifyNever(
        () => entries.deleteEntry(
          any(),
          any(),
          any(),
          isSessionCurrent: any(named: 'isSessionCurrent'),
        ),
      );
    },
  );

  test('ambiguous delete failure leaves AutoFill invalidated', () async {
    when(
      () => entries.getCanonicalEntry(vaultId, entryId),
    ).thenAnswer((_) async => head());
    final actions = <AutoFillMutationAction>[];
    final subscription = notifier.changes.listen(actions.add);
    addTearDown(subscription.cancel);
    when(
      () => entries.deleteEntry(
        vaultId,
        entryId,
        any(),
        isSessionCurrent: any(named: 'isSessionCurrent'),
      ),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/delete'),
        type: DioExceptionType.connectionError,
      ),
    );
    await expectLater(
      service.deleteEntry(
        expected: deletionTarget(),
        memberPrivateKey: Uint8List(32),
        isSessionCurrent: () => true,
      ),
      throwsA(
        isA<CanonicalEntryDetailException>().having(
          (error) => error.kind,
          'kind',
          CanonicalEntryDetailError.network,
        ),
      ),
    );
    expect(actions, [AutoFillMutationAction.invalidate]);
  });

  test('delete preserves optimistic conflict as a typed error', () async {
    when(
      () => entries.getCanonicalEntry(vaultId, entryId),
    ).thenAnswer((_) async => head());
    when(
      () => entries.deleteEntry(
        vaultId,
        entryId,
        any(),
        isSessionCurrent: any(named: 'isSessionCurrent'),
      ),
    ).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/delete'),
        statusCode: 409,
      ),
    );
    await expectLater(
      service.deleteEntry(
        expected: deletionTarget(),
        memberPrivateKey: Uint8List(32),
        isSessionCurrent: () => true,
      ),
      throwsA(
        isA<CanonicalEntryDetailException>().having(
          (error) => error.kind,
          'kind',
          CanonicalEntryDetailError.conflict,
        ),
      ),
    );
  });

  test('canonical custom fields survive the detail/edit adapter', () {
    const fieldId = '88888888-8888-4888-8888-888888888888';
    final source = <String, dynamic>{
      ...canonicalSecret,
      'content': {
        'value': 'synthetic-key',
        'customFields': [
          {
            'id': fieldId,
            'label': 'QA later field',
            'kind': 'concealed',
            'value': 'synthetic-later-field',
            'includeInMemberIndex': false,
          },
        ],
      },
      'agentFieldAccess': {
        ...canonicalSecret['agentFieldAccess'] as Map,
        'custom:$fieldId': 'onGrantValue',
      },
    };
    final adapted = service.adaptCanonicalSecret(source);
    final payload = adapted['content'] as Map<String, dynamic>;
    expect(payload['fields'], [
      {
        'id': fieldId,
        'label': 'QA later field',
        'type': 'concealed',
        'value': 'synthetic-later-field',
        'agentVisible': false,
      },
    ]);
    expect(payload.containsKey('customFields'), isFalse);
    expect((source['content'] as Map)['customFields'], hasLength(1));
  });

  for (final representation in ['map', 'uri']) {
    for (final access in ['never', 'onGrantDerived', 'missing']) {
      test(
        'native TOTP $representation edit preserves $access and canonical identity',
        () async {
          const config = {
            'secret': 'JBSWY3DPEHPK3PXP',
            'algorithm': 'SHA1',
            'digits': 6,
            'period': 30,
          };
          final dynamic native = representation == 'map'
              ? config
              : 'otpauth://totp/?secret=JBSWY3DPEHPK3PXP';
          final parsed = CredentialPayload.fromJson({
            'username': 'fixture',
            'password': 'fixture',
            'totp': native,
          });
          final content = EntryFormUtils.buildPayload(
            type: EntryType.credential,
            username: parsed.username,
            password: parsed.password,
            credentialTotp: parsed.totp,
          );
          when(
            () => entries.updateCanonicalEntry(vaultId, entryId, any()),
          ).thenAnswer(
            (_) async => Response(
              requestOptions: RequestOptions(path: '/update'),
              statusCode: 200,
            ),
          );
          await service.update(
            snapshot: CanonicalEntrySnapshot(
              entry: head(),
              secret: {
                'entryType': EntryType.credential.toWire(),
                'agentVisibilityPolicy': {
                  'discoverable': true,
                  'fields': {
                    'agentLabel': 'discovery',
                    'urlDomain': 'discovery',
                    if (access != 'missing') 'totp': access,
                  },
                },
              },
              payload: content,
            ),
            expected: EntryEntity(
              id: entryId,
              vaultId: vaultId,
              label: 'Fixture',
              type: EntryType.credential,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
            label: 'Fixture',
            description: '',
            icon: '',
            type: EntryType.credential,
            content: content,
            memberPrivateKey: Uint8List(32),
          );
          final captured =
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
                      secret: captureAny(named: 'secret'),
                      vaultKey: any(named: 'vaultKey'),
                      vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
                      existingEntryDek: any(named: 'existingEntryDek'),
                    ),
                  ).captured.single
                  as MemberSecret;
          expect((captured.content as CredentialSecretContent).totp, config);
          expect(captured.content.customFields, isEmpty);
          expect(
            captured.agentFieldAccess['credential.totp']?.name,
            access == 'missing' ? 'never' : access,
          );
        },
      );
    }
  }

  for (final kind in ['concealed', 'totp']) {
    for (final mode in ['all', 'selected', 'never']) {
      test(
        'v2 $mode grant refresh retains V2 for a later $kind field',
        () async {
          const fieldId = '88888888-8888-4888-8888-888888888888';
          when(
            () => grants.listGrants(
              vaultId,
              status: 'active',
              cursor: any(named: 'cursor'),
              pageSize: 100,
            ),
          ).thenAnswer(
            (_) async => GrantPage(
              grants: [
                GrantModel(
                  id: '44444444-4444-4444-8444-444444444444',
                  vaultId: vaultId,
                  agentId: '55555555-5555-4555-8555-555555555555',
                  status: 'active',
                  type: GrantScope.granular,
                  createdAt: '2026-09-19T00:00:00Z',
                  agentPublicKey: base64.encode(List<int>.filled(32, 4)),
                  recipientAgentKeyVersion: 1,
                  methods: 'Inject',
                  entryScopes: [
                    GrantEntryScope(
                      entryId: entryId,
                      fieldIds: ['key.value'],
                      fieldSelectionMode: mode == 'never' ? 'all' : mode,
                      selectedFieldIds: mode == 'selected'
                          ? ['key.value']
                          : null,
                      grantEnvelopeRevision: '1',
                      grantKeyVersion: 1,
                    ),
                  ],
                ),
              ],
            ),
          );
          Map<String, Object?>? delivered;
          when(
            () => crypto.sealGrant(
              organizationId: any(named: 'organizationId'),
              vaultId: any(named: 'vaultId'),
              entryId: any(named: 'entryId'),
              grantId: any(named: 'grantId'),
              agentId: any(named: 'agentId'),
              entryRevision: any(named: 'entryRevision'),
              memberKeyGeneration: any(named: 'memberKeyGeneration'),
              agentPublicKey: any(named: 'agentPublicKey'),
              recipientKeyVersion: any(named: 'recipientKeyVersion'),
              approvedMethods: any(named: 'approvedMethods'),
              deliveryPolicy: any(named: 'deliveryPolicy'),
              fieldIds: any(named: 'fieldIds'),
              grantPayload: any(named: 'grantPayload'),
              grantEnvelopeRevision: any(named: 'grantEnvelopeRevision'),
              grantKeyVersion: any(named: 'grantKeyVersion'),
              expiresAt: any(named: 'expiresAt'),
              remainingUses: any(named: 'remainingUses'),
            ),
          ).thenAnswer((invocation) async {
            delivered =
                invocation.namedArguments[#grantPayload]
                    as Map<String, Object?>;
            return {'fieldIds': invocation.namedArguments[#fieldIds]};
          });
          when(
            () => entries.updateCanonicalEntry(vaultId, entryId, any()),
          ).thenAnswer(
            (_) async => Response(
              requestOptions: RequestOptions(path: '/update'),
              statusCode: 200,
            ),
          );
          await service.update(
            snapshot: CanonicalEntrySnapshot(
              entry: head(),
              secret: {
                'agentLabel': 'Key',
                'agentVisibilityPolicy': {
                  'discoverable': true,
                  'fields': {
                    'agentLabel': 'discovery',
                    'value': 'onGrantValue',
                  },
                },
              },
              payload: {'value': 'synthetic-key'},
            ),
            expected: EntryEntity(
              id: entryId,
              vaultId: vaultId,
              label: 'Key',
              type: EntryType.key,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
            label: 'Key',
            description: '',
            icon: '',
            type: EntryType.key,
            agentVisibilityPolicy: visibility.AgentVisibilityPolicy(
              discoverable: true,
              fields: {
                'agentLabel': visibility.AgentFieldAccess.discovery,
                'value': visibility.AgentFieldAccess.onGrantValue,
                fieldId: mode == 'never'
                    ? visibility.AgentFieldAccess.never
                    : kind == 'totp'
                    ? visibility.AgentFieldAccess.onGrantDerived
                    : visibility.AgentFieldAccess.onGrantValue,
                '99999999-9999-4999-8999-999999999999':
                    visibility.AgentFieldAccess.never,
              },
            ),
            content: {
              'value': 'synthetic-key',
              'fields': [
                {
                  'id': fieldId,
                  'label': 'Later',
                  'type': kind,
                  'value': kind == 'totp'
                      ? {
                          'secret': 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
                          'algorithm': 'SHA1',
                          'digits': 6,
                          'period': 30,
                        }
                      : 'synthetic-new',
                  'agentVisible': false,
                },
              ],
            },
            memberPrivateKey: Uint8List(32),
          );
          expect(
            (delivered!['fields'] as List).map((field) => (field as Map)['id']),
            mode == 'all' ? ['custom:$fieldId', 'key.value'] : ['key.value'],
          );
          expect(delivered!['schema'], 'palladin.grant-payload.v2');
          if (mode == 'all' && kind == 'totp') {
            final value = (delivered!['fields'] as List).first['value'] as Map;
            expect(value['source'], 'totp');
            expect(value.containsKey('code'), isFalse);
          }
          final saved =
              verify(
                    () => crypto.seal(
                      organizationId: any(named: 'organizationId'),
                      vaultId: any(named: 'vaultId'),
                      entryId: any(named: 'entryId'),
                      revision: any(named: 'revision'),
                      entryKeyRevision: any(named: 'entryKeyRevision'),
                      memberIndexRevision: any(named: 'memberIndexRevision'),
                      agentDiscoveryRevision: any(
                        named: 'agentDiscoveryRevision',
                      ),
                      entryKeyVersion: any(named: 'entryKeyVersion'),
                      vaultKeyVersion: any(named: 'vaultKeyVersion'),
                      vdkVersion: any(named: 'vdkVersion'),
                      memberKeyGeneration: any(named: 'memberKeyGeneration'),
                      operation: any(named: 'operation'),
                      secret: captureAny(named: 'secret'),
                      vaultKey: any(named: 'vaultKey'),
                      vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
                      existingEntryDek: any(named: 'existingEntryDek'),
                    ),
                  ).captured.single
                  as MemberSecret;
          expect(saved.content.customFields.single.id, fieldId);
        },
      );
    }
  }

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
    'Script conversion requests atomic revocation of its direct grant',
    () async {
      const grantId = '77777777-7777-4777-8777-777777777777';
      when(
        () => grants.listGrants(
          vaultId,
          status: 'active',
          cursor: any(named: 'cursor'),
          pageSize: 100,
        ),
      ).thenAnswer(
        (_) async => const GrantPage(
          grants: [
            GrantModel(
              id: grantId,
              vaultId: vaultId,
              agentId: '88888888-8888-4888-8888-888888888888',
              status: 'active',
              type: GrantScope.scriptExecution,
              createdAt: '2026-08-25T00:00:00Z',
              entryId: entryId,
              scriptScopes: [
                ScriptExecutionGrantScope(
                  entryId: entryId,
                  entryRevision: '7',
                  isScript: true,
                ),
              ],
            ),
          ],
        ),
      );
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
          'entryType': EntryType.script.toWire(),
          'agentLabel': 'Maintenance script',
          'description': null,
          'agentVisibilityPolicy': {
            'discoverable': true,
            'fields': {
              'agentLabel': 'discovery',
              'interpreter': 'discovery',
              'script': 'onGrantRuntime',
              'refs': 'onGrantRuntime',
              'notes': 'onGrantRuntime',
            },
          },
        },
        payload: {
          'type': 'SCRIPT',
          'script': 'echo ok',
          'interpreter': 'bash',
          'refs': const <Object?>[],
          'notes': null,
        },
      );

      await service.update(
        snapshot: snapshot,
        expected: EntryEntity(
          id: entryId,
          vaultId: vaultId,
          label: 'Maintenance script',
          type: EntryType.script,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        label: 'Converted key',
        description: '',
        icon: '',
        type: EntryType.key,
        content: {'type': 'KEY', 'value': 'new-value', 'notes': null},
        memberPrivateKey: Uint8List(32),
      );

      final payload =
          verify(
                () => entries.updateCanonicalEntry(
                  vaultId,
                  entryId,
                  captureAny(),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(payload['scriptGrantPackages'], isEmpty);
      expect(payload['revokedScriptGrantIds'], [grantId]);
    },
  );

  test(
    'credit card update reconciles custom runtime and derived policy fields',
    () async {
      const removedId = '44444444-4444-4444-8444-444444444444';
      const runtimeId = '55555555-5555-4555-8555-555555555555';
      const derivedId = '66666666-6666-4666-8666-666666666666';
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
          'agentLabel': 'Card',
          'description': null,
          'agentVisibilityPolicy': {
            'discoverable': true,
            'fields': {
              'agentLabel': 'discovery',
              'cardholderName': 'onGrantRuntime',
              'cardNumber': 'onGrantRuntime',
              'expiryMonth': 'onGrantRuntime',
              'expiryYear': 'onGrantRuntime',
              'billingAddress': 'onGrantRuntime',
              'notes': 'never',
              removedId: 'onGrantRuntime',
            },
          },
        },
        payload: {
          'type': 'CREDIT_CARD',
          'cardholderName': 'Old name',
          'cardNumber': '4111111111111111',
          'expiryMonth': '12',
          'expiryYear': '2030',
          'billingAddress': 'Old address',
          'notes': null,
          'fields': [
            {
              'id': removedId,
              'label': 'Removed',
              'type': 'concealed',
              'value': 'old',
            },
          ],
        },
      );

      await service.update(
        snapshot: snapshot,
        expected: EntryEntity(
          id: entryId,
          vaultId: vaultId,
          label: 'Card',
          type: EntryType.creditCard,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        label: 'Card',
        description: '',
        icon: '',
        type: EntryType.creditCard,
        content: {
          'type': 'CREDIT_CARD',
          'cardholderName': 'New name',
          'cardNumber': '5555555555554444',
          'cvv': '0123',
          'expiryMonth': '01',
          'expiryYear': '2032',
          'billingAddress': 'New address',
          'notes': null,
          'fields': [
            {
              'id': runtimeId,
              'label': 'Account reference',
              'type': 'text',
              'value': 'primary',
            },
            {
              'id': derivedId,
              'label': 'Card TOTP',
              'type': 'totp',
              'value': {
                'secret': 'JBSWY3DPEHPK3PXP',
                'algorithm': 'SHA1',
                'digits': 6,
                'period': 30,
              },
            },
          ],
        },
        memberPrivateKey: Uint8List(32),
      );

      final captured =
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
                  secret: captureAny(named: 'secret'),
                  vaultKey: any(named: 'vaultKey'),
                  vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
                  existingEntryDek: any(named: 'existingEntryDek'),
                ),
              ).captured.single
              as MemberSecret;
      expect(captured.content.toJson()['cvv'], '0123');
      expect(
        captured.agentFieldAccess['creditCard.cvv'],
        AgentFieldAccess.never,
      );
      expect(
        captured.agentFieldAccess['custom:$runtimeId'],
        AgentFieldAccess.onGrantRuntime,
      );
      expect(
        captured.agentFieldAccess['custom:$derivedId'],
        AgentFieldAccess.onGrantDerived,
      );
      expect(captured.agentFieldAccess, isNot(contains(removedId)));
      expect(captured.agentFieldAccess, isNot(contains('custom:$removedId')));
    },
  );

  for (final type in [
    EntryType.credential,
    EntryType.key,
    EntryType.creditCard,
  ]) {
    for (final scenario in [
      'new',
      'new-never',
      'never',
      'derived',
      'missing',
      'missing-canonical',
    ]) {
      test(
        '${type.name} TOTP edit preserves identity and $scenario policy',
        () async {
          const id = '66666666-6666-4666-8666-666666666666';
          Map<String, dynamic> field(String secret) => {
            'id': id,
            'label': 'TOTP',
            'type': 'totp',
            'value': {
              'secret': secret,
              'algorithm': 'SHA1',
              'digits': 6,
              'period': 30,
            },
          };
          final base = <String, dynamic>{
            if (type == EntryType.credential) ...{
              'username': 'fixture',
              'password': 'fixture',
            },
            if (type == EntryType.key) 'value': 'fixture',
            if (type == EntryType.creditCard) ...{
              'cardholderName': 'Fixture',
              'cardNumber': '4111111111111111',
              'expiryMonth': '12',
              'expiryYear': '2030',
            },
          };
          when(
            () => entries.updateCanonicalEntry(vaultId, entryId, any()),
          ).thenAnswer(
            (_) async => Response(
              requestOptions: RequestOptions(path: '/update'),
              statusCode: 200,
            ),
          );
          Map<String, Object?>? refreshedPayload;
          if (scenario == 'derived' && type != EntryType.creditCard) {
            const grantId = '77777777-7777-4777-8777-777777777777';
            const agentId = '88888888-8888-4888-8888-888888888888';
            when(
              () => grants.listGrants(
                vaultId,
                status: 'active',
                cursor: any(named: 'cursor'),
                pageSize: 100,
              ),
            ).thenAnswer(
              (_) async => GrantPage(
                grants: [
                  GrantModel(
                    id: grantId,
                    vaultId: vaultId,
                    agentId: agentId,
                    status: 'active',
                    type: GrantScope.granular,
                    createdAt: '2026-07-01T00:00:00Z',
                    agentPublicKey: base64.encode(List<int>.filled(32, 4)),
                    recipientAgentKeyVersion: 3,
                    methods: 'Inject',
                    entryScopes: const [
                      GrantEntryScope(
                        entryId: entryId,
                        fieldIds: ['custom:$id'],
                        grantEnvelopeRevision: '4',
                        entryRevision: '7',
                        grantKeyVersion: 5,
                        memberKeyGeneration: 3,
                        recipientAgentKeyVersion: 3,
                        agentKeyFingerprint: 'fixture',
                      ),
                    ],
                  ),
                ],
              ),
            );
            when(
              () => crypto.sealGrant(
                organizationId: orgId,
                vaultId: vaultId,
                entryId: entryId,
                grantId: grantId,
                agentId: agentId,
                entryRevision: 8,
                memberKeyGeneration: 3,
                agentPublicKey: any(named: 'agentPublicKey'),
                recipientKeyVersion: 3,
                approvedMethods: any(named: 'approvedMethods'),
                deliveryPolicy: 0,
                fieldIds: ['custom:$id'],
                grantPayload: any(named: 'grantPayload'),
                grantEnvelopeRevision: 5,
                grantKeyVersion: 6,
                expiresAt: null,
                remainingUses: null,
              ),
            ).thenAnswer((invocation) async {
              refreshedPayload =
                  invocation.namedArguments[#grantPayload]
                      as Map<String, Object?>;
              return {'fixture': true};
            });
          }
          final snapshot = CanonicalEntrySnapshot(
            entry: head(),
            secret: {
              'entryType': type.toWire(),
              'agentVisibilityPolicy': {
                'discoverable': true,
                'fields': {
                  'agentLabel': 'discovery',
                  if (type == EntryType.creditCard) ...{
                    'cardholderName': 'onGrantRuntime',
                    'cardNumber': 'onGrantRuntime',
                    'expiryMonth': 'onGrantRuntime',
                    'expiryYear': 'onGrantRuntime',
                  },
                  if (type == EntryType.credential) 'urlDomain': 'discovery',
                  if (scenario == 'never' || scenario == 'new-never')
                    id: 'never',
                  if (scenario == 'derived') id: 'onGrantDerived',
                },
              },
            },
            payload: {
              ...base,
              if (scenario == 'missing-canonical')
                'customFields': [
                  {
                    ...field('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
                    'kind': 'totp',
                  },
                ]
              else
                'fields': [
                  if (!scenario.startsWith('new'))
                    field('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'),
                ],
            },
          );
          await service.update(
            snapshot: snapshot,
            expected: EntryEntity(
              id: entryId,
              vaultId: vaultId,
              label: 'Fixture',
              type: type,
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
            label: 'Fixture',
            description: '',
            icon: '',
            type: type,
            content: {
              ...base,
              'fields': [field('GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ')],
            },
            memberPrivateKey: Uint8List(32),
          );
          final captured =
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
                      secret: captureAny(named: 'secret'),
                      vaultKey: any(named: 'vaultKey'),
                      vaultDiscoveryKey: any(named: 'vaultDiscoveryKey'),
                      existingEntryDek: any(named: 'existingEntryDek'),
                    ),
                  ).captured.single
                  as MemberSecret;
          expect(captured.content.customFields.single.id, id);
          if (scenario == 'derived' && type != EntryType.creditCard) {
            expect(refreshedPayload, isNotNull);
            final fields = refreshedPayload!['fields'] as List;
            expect(fields, hasLength(1));
            expect(fields.single, containsPair('id', 'custom:$id'));
            expect(fields.single, containsPair('mode', 'derived'));
            final value = (fields.single as Map)['value'] as Map;
            expect(refreshedPayload!['schema'], 'palladin.grant-payload.v2');
            expect(value['source'], 'totp');
            expect(value['secret'], 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
            expect(value, isNot(contains('code')));
          }

          expect(
            captured.agentFieldAccess['custom:$id'],
            scenario == 'new' || scenario == 'derived'
                ? AgentFieldAccess.onGrantDerived
                : AgentFieldAccess.never,
          );
        },
      );
    }
  }

  test('canonical reveal rejects the retired strict card payload', () async {
    when(
      () => entries.getCanonicalEntry(vaultId, entryId),
    ).thenAnswer((_) async => head());
    when(
      () => crypto.openMemberSecret(
        entryKey: any(named: 'entryKey'),
        memberSecret: any(named: 'memberSecret'),
        vaultKey: any(named: 'vaultKey'),
      ),
    ).thenAnswer(
      (_) async => <String, dynamic>{
        'schema': MemberSecret.schema,
        'entryType': 'creditCard',
        'memberLabel': 'Legacy card',
        'agentLabel': 'Legacy card',
        'description': null,
        'icon': null,
        'color': null,
        'discoverable': true,
        'content': {
          'cardholderName': 'Ada Lovelace',
          'cardNumber': '4242424242424242',
          'expiryMonth': '12',
          'expiryYear': '2030',
          'securityCode': '123',
          'pin': '4321',
          'billingAddress': null,
          'notes': null,
          'customFields': const <Object?>[],
        },
        'agentFieldAccess': const <String, String>{},
      },
    );

    await expectLater(
      service.reveal(
        expected: EntryEntity(
          id: entryId,
          vaultId: vaultId,
          label: 'Legacy card',
          type: EntryType.creditCard,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        memberPrivateKey: Uint8List(32),
      ),
      throwsA(
        isA<CanonicalEntryDetailException>().having(
          (error) => error.kind,
          'kind',
          CanonicalEntryDetailError.corrupt,
        ),
      ),
    );
  });

  test(
    'canonical reveal rejects a protocol-v2 scope not bound to the requested Entry',
    () async {
      final response = head();
      final entryKey = Map<String, dynamic>.from(response['entryKey'] as Map);
      final descriptor = Map<String, dynamic>.from(
        entryKey['descriptor'] as Map,
      );
      descriptor['scope'] = {
        ...Map<String, dynamic>.from(descriptor['scope'] as Map),
        'entryId': '44444444-4444-4444-8444-444444444444',
      };
      entryKey['descriptor'] = descriptor;
      response['entryKey'] = entryKey;
      when(
        () => entries.getCanonicalEntry(vaultId, entryId),
      ).thenAnswer((_) async => response);

      await expectLater(
        service.reveal(
          expected: EntryEntity(
            id: entryId,
            vaultId: vaultId,
            label: 'Key',
            type: EntryType.key,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
          memberPrivateKey: Uint8List(32),
        ),
        throwsA(
          isA<CanonicalEntryDetailException>().having(
            (error) => error.kind,
            'kind',
            CanonicalEntryDetailError.corrupt,
          ),
        ),
      );
      verifyNever(
        () => crypto.openMemberSecret(
          entryKey: any(named: 'entryKey'),
          memberSecret: any(named: 'memberSecret'),
          vaultKey: any(named: 'vaultKey'),
        ),
      );
    },
  );

  test(
    'canonical reveal rejects a protocol-v2 wrapper not bound to the current Vault key',
    () async {
      final response = head();
      final entryKey = Map<String, dynamic>.from(response['entryKey'] as Map);
      final descriptor = Map<String, dynamic>.from(
        entryKey['descriptor'] as Map,
      );
      descriptor['binding'] = {'wrappingVaultKeyVersion': 99};
      entryKey['descriptor'] = descriptor;
      response['entryKey'] = entryKey;
      when(
        () => entries.getCanonicalEntry(vaultId, entryId),
      ).thenAnswer((_) async => response);

      await expectLater(
        service.reveal(
          expected: EntryEntity(
            id: entryId,
            vaultId: vaultId,
            label: 'Key',
            type: EntryType.key,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
          memberPrivateKey: Uint8List(32),
        ),
        throwsA(
          isA<CanonicalEntryDetailException>().having(
            (error) => error.kind,
            'kind',
            CanonicalEntryDetailError.corrupt,
          ),
        ),
      );
      verifyNever(
        () => crypto.openMemberSecret(
          entryKey: any(named: 'entryKey'),
          memberSecret: any(named: 'memberSecret'),
          vaultKey: any(named: 'vaultKey'),
        ),
      );
    },
  );

  test(
    'canonical reveal rejects a fetched head older than the expected revision',
    () async {
      when(
        () => entries.getCanonicalEntry(vaultId, entryId),
      ).thenAnswer((_) async => head());
      await expectLater(
        service.reveal(
          expected: EntryEntity(
            id: entryId,
            vaultId: vaultId,
            label: 'Key',
            type: EntryType.key,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            currentRevision: '8',
            currentKeyVersion: 2,
          ),
          memberPrivateKey: Uint8List(32),
        ),
        throwsA(
          isA<CanonicalEntryDetailException>().having(
            (error) => error.kind,
            'kind',
            CanonicalEntryDetailError.conflict,
          ),
        ),
      );
      verifyNever(
        () => crypto.openMemberSecret(
          entryKey: any(named: 'entryKey'),
          memberSecret: any(named: 'memberSecret'),
          vaultKey: any(named: 'vaultKey'),
        ),
      );
    },
  );

  test(
    'canonical reveal rejects a fetched head with the wrong expected key version',
    () async {
      when(
        () => entries.getCanonicalEntry(vaultId, entryId),
      ).thenAnswer((_) async => head());
      await expectLater(
        service.reveal(
          expected: EntryEntity(
            id: entryId,
            vaultId: vaultId,
            label: 'Key',
            type: EntryType.key,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            currentRevision: '7',
            currentKeyVersion: 3,
          ),
          memberPrivateKey: Uint8List(32),
        ),
        throwsA(
          isA<CanonicalEntryDetailException>().having(
            (error) => error.kind,
            'kind',
            CanonicalEntryDetailError.conflict,
          ),
        ),
      );
      verifyNever(
        () => crypto.openMemberSecret(
          entryKey: any(named: 'entryKey'),
          memberSecret: any(named: 'memberSecret'),
          vaultKey: any(named: 'vaultKey'),
        ),
      );
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
          currentKeyVersion: 2,
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
