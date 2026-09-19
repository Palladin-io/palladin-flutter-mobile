import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobile_palladin/features/approval/data/datasources/approval_remote_datasource.dart';
import 'package:mobile_palladin/features/approval/data/services/grant_approval_review_service.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/datasources/agent_discovery_remote_datasource.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_rotation_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/approval/data/models/pending_grant_model.dart';

Map<String, dynamic> _reason(
  String grantId,
  String vaultId,
  String agentId,
  String entryId,
) => {
  'descriptor': {
    'protocolVersion': 2,
    'cryptoSuiteId': 'palladin-vault-xchacha-v1',
    'purpose': 'encryptedReason',
    'scope': {
      'organizationId': '00000000-0000-4000-8000-000000000001',
      'vaultId': vaultId,
      'entryId': entryId,
      'grantOrRequestId': grantId,
      'agentId': agentId,
      'memberId': null,
    },
    'resourceRevision': '1',
    'keyVersion': 1,
    'memberKeyGeneration': 1,
    'binding': {
      'wrapperSuiteId': 'palladin-x25519-sealed-box-v1',
      'recipientKeyVersion': 1,
      'recipientKeyFingerprint': 'fingerprint',
      'requestedMethods': 1,
    },
  },
  'encodedSuitePayload': 'payload',
  'wrappedReasonDek': {
    'descriptor': <String, dynamic>{},
    'encodedSealedKeyPackage': 'wrapped',
  },
  'agentSignature': 'signature',
};

void main() {
  test('unavailable reason does not hide a pending request', () {
    final model = PendingGrantModel.fromJson({
      'grantId': 'g-1',
      'vaultId': 'v-1',
      'agentId': 'a-1',
      'entryId': 'e-1',
      'agentPublicKey': 'public',
      'createdAt': '2026-09-19T12:00:00Z',
      'encryptedReason': null,
    });
    expect(model.toEntity().grantId, 'g-1');
    expect(model.encryptedReason, isNull);
  });
  for (final variant in ['missing', 'substituted', 'widened']) {
    test('review rejects $variant reason before opening keys', () async {
      final reason = _reason(
        variant == 'substituted' ? 'other' : 'g-1',
        'v-1',
        'a-1',
        'e-1',
      );
      if (variant == 'widened') {
        ((reason['descriptor'] as Map)['binding'] as Map)['requestedMethods'] =
            3;
      }
      final wire = <String, dynamic>{
        'grantId': 'g-1',
        'vaultId': 'v-1',
        'agentId': 'a-1',
        'entryId': 'e-1',
        'agentPublicKey': 'public',
        'methods': 1,
        'createdAt': '2026-09-19T12:00:00Z',
        'encryptedReason': variant == 'missing' ? null : reason,
      };
      final calls = <String>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              calls.add(request.path);
              handler.resolve(Response(requestOptions: request, data: wire));
            },
          ),
        );
      final keys = _Keys();
      final entries = _Entries();
      final review = GrantApprovalReviewService(
        vaults: VaultRemoteDatasource(dio),
        entries: entries,
        keys: keys,
        envelopes: VaultProtocolEnvelopeService(),
        signatures: VaultProtocolSignatureService(),
        discovery: AgentDiscoveryRemoteDatasource(dio),
        approval: ApprovalRemoteDatasource(dio),
      );
      final grant = PendingGrantModel.fromJson(wire).toEntity();
      await expectLater(
        review.open(grant: grant, memberPrivateKey: Uint8List(32)),
        throwsFormatException,
      );
      expect(calls, ['/api/vaults/v-1/grants/g-1']);
      verifyZeroInteractions(keys);
      verifyZeroInteractions(entries);
    });
  }
  group('PendingGrantModel.fromJson → toEntity', () {
    test('maps a full pending request with reason + agent public key', () {
      final entity = PendingGrantModel.fromJson(<String, dynamic>{
        'grantId': 'g-1',
        'vaultId': 'v-1',
        'agentId': 'a-1',
        'entryId': 'e-1',
        'agentPublicKey': 'cHVibGljLWtleQ==',
        'methods': 1,
        'vaultName': 'Prod',
        'agentName': 'Deploy Bot',
        'entryLabel': 'Gmail',
        'encryptedReason': _reason('g-1', 'v-1', 'a-1', 'e-1'),
        'createdAt': '2026-06-01T10:00:00Z',
      }).toEntity();

      expect(entity.grantId, 'g-1');
      expect(entity.vaultId, 'v-1');
      expect(entity.agentId, 'a-1');
      expect(entity.entryId, 'e-1');
      expect(entity.agentPublicKey, 'cHVibGljLWtleQ==');
      expect(entity.vaultName, isNull);
      expect(entity.agentName, isNull);
      expect(entity.entryLabel, isNull);
      expect(entity.encryptedReason?.requestRevision, '1');
      expect(entity.createdAt.isUtc, isFalse); // normalized to local
    });

    test('tolerates `id` instead of `grantId` and missing optionals', () {
      final entity = PendingGrantModel.fromJson(<String, dynamic>{
        'id': 'g-2',
        'vaultId': 'v-2',
        'agentId': 'a-2',
        'entryId': 'e-2',
        'agentPublicKey': 'a2V5',
        'methods': 1,
        'encryptedReason': _reason('g-2', 'v-2', 'a-2', 'e-2'),
        'createdAt': '2026-06-02T08:00:00Z',
      }).toEntity();

      expect(entity.grantId, 'g-2');
      expect(entity.vaultName, isNull);
      expect(entity.agentName, isNull);
      expect(entity.entryLabel, isNull);
    });

    test(
      'defaults isAgentRegistered to true when `agentRegistered` absent',
      () {
        final entity = PendingGrantModel.fromJson(<String, dynamic>{
          'grantId': 'g-3',
          'vaultId': 'v-3',
          'agentId': 'a-3',
          'entryId': 'e-3',
          'agentPublicKey': 'a2V5',
          'methods': 1,
          'encryptedReason': _reason('g-3', 'v-3', 'a-3', 'e-3'),
          'createdAt': '2026-06-02T08:00:00Z',
        }).toEntity();

        expect(entity.isAgentRegistered, isTrue);
      },
    );

    test('maps `agentRegistered: false` for an unknown agent request', () {
      final entity = PendingGrantModel.fromJson(<String, dynamic>{
        'grantId': 'g-4',
        'vaultId': 'v-4',
        'agentId': 'a-4',
        'entryId': 'e-4',
        'agentPublicKey': 'a2V5',
        'methods': 1,
        'encryptedReason': _reason('g-4', 'v-4', 'a-4', 'e-4'),
        'agentRegistered': false,
        'createdAt': '2026-06-02T08:00:00Z',
      }).toEntity();

      expect(entity.isAgentRegistered, isFalse);
    });

    test('keeps a substituted reason row for review to reject', () {
      expect(
        () => PendingGrantModel.fromJson(<String, dynamic>{
          'grantId': 'g-5',
          'vaultId': 'v-5',
          'agentId': 'a-5',
          'entryId': 'e-5',
          'agentPublicKey': 'a2V5',
          'methods': 1,
          'encryptedReason': _reason('other', 'v-5', 'a-5', 'e-5'),
          'createdAt': '2026-06-02T08:00:00Z',
        }),
        returnsNormally,
      );
    });

    test('keeps widened methods visible for review to reject', () {
      final reason = _reason('g-6', 'v-6', 'a-6', 'e-6');
      ((reason['descriptor'] as Map)['binding'] as Map)['requestedMethods'] = 3;
      expect(
        () => PendingGrantModel.fromJson(<String, dynamic>{
          'grantId': 'g-6',
          'vaultId': 'v-6',
          'agentId': 'a-6',
          'entryId': 'e-6',
          'agentPublicKey': 'a2V5',
          'methods': 1,
          'encryptedReason': reason,
          'createdAt': '2026-06-02T08:00:00Z',
        }),
        returnsNormally,
      );
    });
  });
}

class _Keys extends Mock implements VaultRotationCryptoService {}

class _Entries extends Mock implements CanonicalEntryDetailService {}
