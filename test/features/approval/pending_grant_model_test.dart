import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/approval/data/models/pending_grant_model.dart';

void main() {
  group('PendingGrantModel.fromJson → toEntity', () {
    test('maps a full pending request with reason + agent public key', () {
      final entity = PendingGrantModel.fromJson(<String, dynamic>{
        'grantId': 'g-1',
        'vaultId': 'v-1',
        'agentId': 'a-1',
        'entryId': 'e-1',
        'agentPublicKey': 'cHVibGljLWtleQ==',
        'recipientAgentKeyVersion': 2,
        'entryScopes': [
          {
            'entryId': 'entry-1',
            'fieldIds': ['credential.password'],
          },
        ],
        'vaultName': 'Prod',
        'agentName': 'Deploy Bot',
        'entryLabel': 'Gmail',
        'reason': 'Need Gmail to send email for task X',
        'createdAt': '2026-06-01T10:00:00Z',
      }).toEntity();

      expect(entity.grantId, 'g-1');
      expect(entity.vaultId, 'v-1');
      expect(entity.agentId, 'a-1');
      expect(entity.entryId, 'e-1');
      expect(entity.agentPublicKey, 'cHVibGljLWtleQ==');
      expect(entity.recipientAgentKeyVersion, 2);
      expect(entity.fieldIds, ['credential.password']);
      expect(entity.vaultName, 'Prod');
      expect(entity.agentName, 'Deploy Bot');
      expect(entity.entryLabel, 'Gmail');
      expect(entity.reason, 'Need Gmail to send email for task X');
      expect(entity.createdAt.isUtc, isFalse); // normalized to local
    });

    test('tolerates `id` instead of `grantId` and missing optionals', () {
      final entity = PendingGrantModel.fromJson(<String, dynamic>{
        'id': 'g-2',
        'vaultId': 'v-2',
        'agentId': 'a-2',
        'entryId': 'e-2',
        'agentPublicKey': 'a2V5',
        'recipientAgentKeyVersion': 1,
        'createdAt': '2026-06-02T08:00:00Z',
      }).toEntity();

      expect(entity.grantId, 'g-2');
      expect(entity.vaultName, isNull);
      expect(entity.agentName, isNull);
      expect(entity.entryLabel, isNull);
      expect(entity.reason, isNull);
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
          'recipientAgentKeyVersion': 1,
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
        'recipientAgentKeyVersion': 1,
        'agentRegistered': false,
        'createdAt': '2026-06-02T08:00:00Z',
      }).toEntity();

      expect(entity.isAgentRegistered, isFalse);
    });

    test('rejects a response without recipient key version', () {
      expect(
        () => PendingGrantModel.fromJson(<String, dynamic>{
          'grantId': 'g-5',
          'vaultId': 'v-5',
          'agentId': 'a-5',
          'entryId': 'e-5',
          'agentPublicKey': 'a2V5',
          'createdAt': '2026-06-02T08:00:00Z',
        }),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
