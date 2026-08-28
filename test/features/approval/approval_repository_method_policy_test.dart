import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/approval/data/datasources/approval_remote_datasource.dart';
import 'package:mobile_palladin/features/approval/data/repositories/approval_repository_impl.dart';
import 'package:mobile_palladin/features/approval/domain/exceptions/approval_exceptions.dart';
import 'package:mobile_palladin/features/approval/domain/repositories/approval_repository.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant_method.dart';
import 'package:mobile_palladin/features/vault/data/datasources/agent_discovery_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/entry_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';

class _Approval extends Mock implements ApprovalRemoteDatasource {}

class _Entries extends Mock implements EntryRemoteDatasource {}

class _Vaults extends Mock implements VaultRemoteDatasource {}

class _Crypto extends Mock implements EntryV2CryptoService {}

class _VaultKeys extends Mock implements VaultRotationCryptoService {}

class _CanonicalEntries extends Mock implements CanonicalEntryDetailService {}

class _Discovery extends Mock implements AgentDiscoveryRemote {}

class _Entry extends Fake implements EntryEntity {}

void main() {
  const vaultId = '22222222-2222-4222-8222-222222222222';
  const entryId = '33333333-3333-4333-8333-333333333333';
  const agentId = '55555555-5555-4555-8555-555555555555';

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(<String, Object?>{});
    registerFallbackValue(_Entry());
  });

  for (final fixture
      in <
        ({
          EntryType type,
          Map<String, dynamic> content,
          Map<String, dynamic> fields,
        })
      >[
        (
          type: EntryType.key,
          content: const {'value': 'secret'},
          fields: const {'agentLabel': 'discovery', 'value': 'onGrantValue'},
        ),
        (
          type: EntryType.credential,
          content: const {'password': 'secret'},
          fields: const {'agentLabel': 'discovery', 'password': 'onGrantValue'},
        ),
        (
          type: EntryType.script,
          content: const {'script': 'echo safe'},
          fields: const {'agentLabel': 'discovery', 'script': 'onGrantRuntime'},
        ),
        (
          type: EntryType.creditCard,
          content: const {'cardNumber': '4242424242424242'},
          fields: const {
            'agentLabel': 'discovery',
            'cardNumber': 'onGrantRuntime',
          },
        ),
      ]) {
    test(
      '${fixture.type.name} preserves selected methods and its delivery policy',
      () async {
        final approval = _Approval();
        final entries = _Entries();
        final vaults = _Vaults();
        final crypto = _Crypto();
        final vaultKeys = _VaultKeys();
        final canonical = _CanonicalEntries();
        final discovery = _Discovery();
        int? approvedMethods;
        int? deliveryPolicy;

        when(
          () => canonical.reveal(
            expected: any(named: 'expected'),
            memberPrivateKey: any(named: 'memberPrivateKey'),
          ),
        ).thenAnswer(
          (_) async => CanonicalEntrySnapshot(
            entry: {
              'organizationId': '11111111-1111-4111-8111-111111111111',
              'currentRevision': '7',
              'memberKeyGeneration': 3,
            },
            secret: {
              'entryType': fixture.type.toWire(),
              'memberLabel': 'Entry',
              'agentVisibilityPolicy': {
                'discoverable': true,
                'fields': fixture.fields,
              },
            },
            payload: Map<String, dynamic>.from(fixture.content),
          ),
        );
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
          approvedMethods = invocation.namedArguments[#approvedMethods]! as int;
          deliveryPolicy = invocation.namedArguments[#deliveryPolicy]! as int;
          return <String, Object?>{'sealed': true};
        });
        when(
          () => approval.createGranularGrant(
            vaultId: any(named: 'vaultId'),
            entryId: any(named: 'entryId'),
            grantId: any(named: 'grantId'),
            agentId: any(named: 'agentId'),
            grantEntry: any(named: 'grantEntry'),
            expiresAt: any(named: 'expiresAt'),
            queryLimit: any(named: 'queryLimit'),
            methods: any(named: 'methods'),
          ),
        ).thenAnswer((_) async => 'grant-id');

        final repository = ApprovalRepositoryImpl(
          approvalDatasource: approval,
          entryDatasource: entries,
          vaultDatasource: vaults,
          cryptoService: crypto,
          vaultKeys: vaultKeys,
          canonicalEntries: canonical,
          discovery: discovery,
        );
        final create = repository.createGranularGrant(
          vaultId: vaultId,
          entryId: entryId,
          agentId: agentId,
          agentPublicKey: base64.encode(List<int>.filled(32, 4)),
          recipientKeyVersion: 3,
          agentAccessEpoch: 1,
          privateKey: Uint8List.fromList(List<int>.filled(32, 7)),
          limit: const GrantLifetime(),
          methods: const [GrantMethod.get, GrantMethod.exec],
        );

        if (fixture.type == EntryType.creditCard) {
          await expectLater(
            create,
            throwsA(
              isA<ApprovalException>().having(
                (error) => error.kind,
                'kind',
                ApprovalErrorKind.cryptoFailure,
              ),
            ),
          );
          verifyNever(
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
          );
          return;
        }

        await create;

        expect(approvedMethods, 3);
        expect(deliveryPolicy, fixture.type.deliveryPolicyCode());
      },
    );
  }

  test(
    'FULL seals one Vault key wrapper, never creates a per-Entry envelope, and wipes the opened key',
    () async {
      final approval = _Approval();
      final entries = _Entries();
      final vaults = _Vaults();
      final crypto = _Crypto();
      final vaultKeys = _VaultKeys();
      final canonical = _CanonicalEntries();
      final discovery = _Discovery();
      final openedVaultKey = Uint8List.fromList(
        List<int>.generate(32, (i) => i + 1),
      );
      const wrappedVaultKey = <String, Object?>{
        'wrappedVaultKey': <String, Object?>{
          'encodedSealedKeyPackage': 'synthetic',
        },
      };

      when(() => vaults.getEncryptedVault(vaultId)).thenAnswer(
        (_) async => <String, dynamic>{
          'organizationId': '11111111-1111-4111-8111-111111111111',
          'memberKeyGeneration': 4,
          'currentKeyEpoch': <String, dynamic>{'vaultKeyVersion': 7},
          'memberVaultKey': <String, dynamic>{
            'wrappedVaultKey': <String, dynamic>{},
          },
        },
      );
      when(
        () => vaultKeys.openMemberVaultKey(
          any(),
          any(),
          expectedOrganizationId: any(named: 'expectedOrganizationId'),
          expectedVaultId: any(named: 'expectedVaultId'),
          expectedVaultKeyVersion: any(named: 'expectedVaultKeyVersion'),
          expectedMemberKeyGeneration: any(
            named: 'expectedMemberKeyGeneration',
          ),
        ),
      ).thenAnswer((_) async => openedVaultKey);
      when(
        () => crypto.sealAgentVaultKey(
          vaultKey: any(named: 'vaultKey'),
          organizationId: any(named: 'organizationId'),
          vaultId: any(named: 'vaultId'),
          grantId: any(named: 'grantId'),
          agentId: any(named: 'agentId'),
          agentAccessEpoch: any(named: 'agentAccessEpoch'),
          vaultKeyVersion: any(named: 'vaultKeyVersion'),
          agentPublicKey: any(named: 'agentPublicKey'),
          recipientKeyVersion: any(named: 'recipientKeyVersion'),
        ),
      ).thenAnswer((_) async => wrappedVaultKey);
      when(
        () => approval.createFullGrant(
          vaultId: any(named: 'vaultId'),
          grantId: any(named: 'grantId'),
          agentId: any(named: 'agentId'),
          agentWrappedVaultKey: any(named: 'agentWrappedVaultKey'),
          expiresAt: any(named: 'expiresAt'),
          queryLimit: any(named: 'queryLimit'),
          methods: any(named: 'methods'),
        ),
      ).thenAnswer((_) async => 'grant-id');

      final repository = ApprovalRepositoryImpl(
        approvalDatasource: approval,
        entryDatasource: entries,
        vaultDatasource: vaults,
        cryptoService: crypto,
        vaultKeys: vaultKeys,
        canonicalEntries: canonical,
        discovery: discovery,
      );

      await repository.createFullGrant(
        vaultId: vaultId,
        agentId: agentId,
        agentPublicKey: base64.encode(List<int>.filled(32, 4)),
        recipientKeyVersion: 3,
        agentAccessEpoch: 2,
        privateKey: Uint8List.fromList(List<int>.filled(32, 7)),
        limit: const GrantUseLimit(5),
        methods: const [GrantMethod.get, GrantMethod.inject],
      );

      verify(
        () => crypto.sealAgentVaultKey(
          vaultKey: openedVaultKey,
          organizationId: '11111111-1111-4111-8111-111111111111',
          vaultId: vaultId,
          grantId: any(named: 'grantId'),
          agentId: agentId,
          agentAccessEpoch: 2,
          vaultKeyVersion: 7,
          agentPublicKey: any(named: 'agentPublicKey'),
          recipientKeyVersion: 3,
        ),
      ).called(1);
      verify(
        () => approval.createFullGrant(
          vaultId: vaultId,
          grantId: any(named: 'grantId'),
          agentId: agentId,
          agentWrappedVaultKey: wrappedVaultKey,
          expiresAt: null,
          queryLimit: 5,
          methods: 'Get, Inject',
        ),
      ).called(1);
      verifyNever(
        () => approval.createGranularGrant(
          vaultId: any(named: 'vaultId'),
          entryId: any(named: 'entryId'),
          grantId: any(named: 'grantId'),
          agentId: any(named: 'agentId'),
          grantEntry: any(named: 'grantEntry'),
          expiresAt: any(named: 'expiresAt'),
          queryLimit: any(named: 'queryLimit'),
          methods: any(named: 'methods'),
        ),
      );
      expect(openedVaultKey, everyElement(0));
    },
  );
}
