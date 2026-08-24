import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:mobile_palladin/features/approval/data/datasources/approval_remote_datasource.dart';
import 'package:mobile_palladin/features/approval/data/repositories/approval_repository_impl.dart';
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
          type: EntryType.creditCard,
          content: const {'cardNumber': '4242424242424242'},
          fields: const {
            'agentLabel': 'discovery',
            'cardNumber': 'onGrantRuntime',
          },
        ),
      ]) {
    test(
      '${fixture.type.name} preserves selected methods and canonical delivery policy',
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
          () => approval.createGrant(
            vaultId: any(named: 'vaultId'),
            grantId: any(named: 'grantId'),
            agentId: any(named: 'agentId'),
            type: any(named: 'type'),
            entryId: any(named: 'entryId'),
            entries: any(named: 'entries'),
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
        await repository.createGrant(
          vaultId: vaultId,
          agentId: agentId,
          agentPublicKey: base64.encode(List<int>.filled(32, 4)),
          recipientKeyVersion: 3,
          agentAccessEpoch: 1,
          isFull: false,
          entryId: entryId,
          privateKey: Uint8List.fromList(List<int>.filled(32, 7)),
          limit: const GrantLifetime(),
          methods: const [GrantMethod.get, GrantMethod.exec],
        );

        expect(approvedMethods, 3);
        expect(deliveryPolicy, fixture.type.deliveryPolicyCode());
      },
    );
  }
}
