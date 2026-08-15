import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/grants/data/models/grant_model.dart';
import 'package:mobile_palladin/features/grants/domain/entities/grant.dart';

Map<String, dynamic> _encryptedReason() => {
  'descriptor': {
    'protocolVersion': 2,
    'cryptoSuiteId': 'palladin-vault-xchacha-v1',
    'purpose': 'encryptedReason',
    'scope': {
      'organizationId': 'org-1',
      'vaultId': 'v-1',
      'entryId': 'e-1',
      'grantOrRequestId': 'g-1',
      'agentId': 'a-1',
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
  group('GrantModel.fromJson → toEntity', () {
    test('maps a granular pending grant with reason and entry', () {
      final entity = GrantModel.fromJson(<String, dynamic>{
        'id': 'g-1',
        'agentId': 'a-1',
        'agentName': 'Deploy Bot',
        'status': 'pending',
        'mode': 'granular',
        'entryId': 'e-1',
        'entryLabel': 'Gmail',
        'reason': 'Need Gmail to send email',
        'createdAt': '2026-06-01T10:00:00Z',
      }, contextVaultId: 'v-1').toEntity();

      expect(entity.id, 'g-1');
      expect(entity.vaultId, 'v-1');
      expect(entity.agentId, 'a-1');
      expect(entity.agentName, 'Deploy Bot');
      expect(entity.status, GrantStatus.pending);
      expect(entity.scope, GrantScope.granular);
      expect(entity.entryId, 'e-1');
      expect(entity.entryLabel, 'Gmail');
      expect(entity.reason, 'Need Gmail to send email');
    });

    test('retains encrypted reason and actor ids for local history', () {
      final model = GrantModel.fromJson(<String, dynamic>{
        'id': 'g-1',
        'vaultId': 'v-1',
        'agentId': 'a-1',
        'status': 'active',
        'type': 'granular',
        'methods': 'get',
        'entryId': 'e-1',
        'createdAt': '2026-06-01T10:00:00Z',
        'createdBy': 'member-1',
        'revokedBy': 'member-2',
        'deniedBy': 'member-3',
        'encryptedReason': _encryptedReason(),
      });

      expect(
        (model.encryptedReason?['descriptor'] as Map)['resourceRevision'],
        '1',
      );
      final entity = model.toEntity(resolvedReason: 'Local plaintext');
      expect(entity.reason, 'Local plaintext');
      expect(entity.createdBy, 'member-1');
      expect(entity.revokedBy, 'member-2');
      expect(entity.deniedBy, 'member-3');
    });

    test('maps a full active grant with expiry', () {
      final entity = GrantModel.fromJson(<String, dynamic>{
        'id': 'g-2',
        'vaultId': 'v-2',
        'agentId': 'a-2',
        'status': 'active',
        'mode': 'full',
        'expiresAt': '2026-07-01T00:00:00Z',
        'createdAt': '2026-06-01T10:00:00Z',
        'approvedAt': '2026-06-01T11:00:00Z',
        'approvedByName': 'Alice',
      }).toEntity();

      expect(entity.scope, GrantScope.full);
      expect(entity.status, GrantStatus.active);
      expect(entity.entryId, isNull);
      expect(entity.expiresAt, isNotNull);
      expect(entity.approvedByName, 'Alice');
    });

    test('use-limited grant carries queryLimit/queryCount', () {
      final entity = GrantModel.fromJson(<String, dynamic>{
        'id': 'g-3',
        'vaultId': 'v-3',
        'agentId': 'a-3',
        'status': 2,
        'mode': 1,
        'queryLimit': 10,
        'queryCount': 3,
        'createdAt': '2026-06-01T10:00:00Z',
      }).toEntity();

      expect(entity.status, GrantStatus.active);
      expect(entity.scope, GrantScope.granular);
      expect(entity.queryLimit, 10);
      expect(entity.queryCount, 3);
      expect(entity.expiresAt, isNull);
    });

    test('unknown status fails closed to revoked', () {
      expect(GrantStatus.fromWire('???'), GrantStatus.revoked);
      expect(GrantStatus.fromWire(null), GrantStatus.revoked);
    });

    test('numeric enum values match the canonical backend ordinals', () {
      expect(GrantStatus.fromWire(1), GrantStatus.pending);
      expect(GrantStatus.fromWire(2), GrantStatus.active);
      expect(GrantStatus.fromWire(3), GrantStatus.expired);
      expect(GrantStatus.fromWire(4), GrantStatus.revoked);
      expect(GrantStatus.fromWire(5), GrantStatus.consumed);
      expect(GrantStatus.fromWire(6), GrantStatus.denied);
      expect(GrantScope.fromWire(1), GrantScope.granular);
      expect(GrantScope.fromWire(2), GrantScope.full);
    });

    test('accepts a grant whose referenced agent has been removed', () {
      final entity = GrantModel.fromJson(<String, dynamic>{
        'id': 'g-removed-agent',
        'vaultId': 'v-1',
        'agentId': null,
        'status': 'revoked',
        'type': 'full',
        'createdAt': '2026-06-01T10:00:00Z',
      }).toEntity();

      expect(entity.agentId, isNull);
    });
  });
}
