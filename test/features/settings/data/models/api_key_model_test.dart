import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_palladin/features/settings/data/models/api_key_model.dart';
import 'package:mobile_palladin/features/settings/data/models/org_model.dart';
import 'package:mobile_palladin/features/settings/domain/entities/api_key.dart';

void main() {
  group('OrgModel', () {
    test('fromJson parses all fields', () {
      final model = OrgModel.fromJson(const {
        'orgId': 'o1',
        'name': 'Acme',
        'planType': 'Pro',
        'memberCount': 5,
      });
      expect(model.orgId, 'o1');
      expect(model.name, 'Acme');
      expect(model.planType, 'Pro');
      expect(model.memberCount, 5);
    });

    test('fromJson defaults memberCount to 1 when missing', () {
      final model = OrgModel.fromJson(const {
        'orgId': 'o1',
        'name': 'Acme',
      });
      expect(model.memberCount, 1);
      expect(model.planType, '');
    });

    test('toEntity maps to a domain Org', () {
      final org = OrgModel.fromJson(const {
        'orgId': 'o1',
        'name': 'Acme',
        'planType': 'Free',
        'memberCount': 2,
      }).toEntity();
      expect(org.orgId, 'o1');
      expect(org.memberCount, 2);
    });
  });

  group('ApiKeyModel', () {
    test('fromJson parses an active key without revokedAt', () {
      final model = ApiKeyModel.fromJson(const {
        'apiKeyId': 'k1',
        'name': 'Prod',
        'status': 'Active',
        'createdAt': '2026-05-01T10:00:00Z',
      });
      final entity = model.toEntity();
      expect(entity.status, ApiKeyStatus.active);
      expect(entity.isActive, isTrue);
      expect(entity.revokedAt, isNull);
    });

    test('fromJson parses a revoked key with revokedAt', () {
      final model = ApiKeyModel.fromJson(const {
        'apiKeyId': 'k2',
        'name': 'Old',
        'status': 'Revoked',
        'createdAt': '2026-04-01T10:00:00Z',
        'revokedAt': '2026-04-15T10:00:00Z',
      });
      final entity = model.toEntity();
      expect(entity.status, ApiKeyStatus.revoked);
      expect(entity.isActive, isFalse);
      expect(entity.revokedAt, isNotNull);
    });

    test('unknown status falls back to revoked (fail closed)', () {
      final model = ApiKeyModel.fromJson(const {
        'apiKeyId': 'k3',
        'name': 'Weird',
        'status': 'Pending',
        'createdAt': '2026-04-01T10:00:00Z',
      });
      expect(model.toEntity().status, ApiKeyStatus.revoked);
    });
  });

  group('NewApiKeyModel', () {
    test('fromJson carries the one-time plaintext', () {
      final model = NewApiKeyModel.fromJson(const {
        'apiKeyId': 'k9',
        'name': 'New',
        'plaintext': 'pl_live_abc123',
        'createdAt': '2026-05-17T10:00:00Z',
      });
      final entity = model.toEntity();
      expect(entity.plaintext, 'pl_live_abc123');
      expect(entity.apiKeyId, 'k9');
    });
  });
}
