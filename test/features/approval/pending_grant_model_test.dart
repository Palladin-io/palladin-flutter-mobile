import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_claw_vault/features/approval/data/models/pending_grant_model.dart';

void main() {
  group('PendingGrantModel.fromJson → toEntity', () {
    test('maps a full pending request with reason + agent public key', () {
      final entity = PendingGrantModel.fromJson(<String, dynamic>{
        'grantId': 'g-1',
        'vaultId': 'v-1',
        'agentId': 'a-1',
        'entryId': 'e-1',
        'agentPublicKey': 'cHVibGljLWtleQ==',
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
        'createdAt': '2026-06-02T08:00:00Z',
      }).toEntity();

      expect(entity.grantId, 'g-2');
      expect(entity.vaultName, isNull);
      expect(entity.agentName, isNull);
      expect(entity.entryLabel, isNull);
      expect(entity.reason, isNull);
    });
  });
}
