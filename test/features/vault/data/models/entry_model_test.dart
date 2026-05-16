import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_claw_vault/features/vault/data/models/create_entry_request.dart';
import 'package:mobile_claw_vault/features/vault/data/models/entry_model.dart';
import 'package:mobile_claw_vault/features/vault/domain/entities/entry_entity.dart';

void main() {
  group('EntryModel.fromJson / toEntity', () {
    test('parses a full list-shape payload', () {
      final json = {
        'id': 'e-1',
        'vaultId': 'v-1',
        'label': 'Stripe API Key',
        'description': 'production',
        'icon': 'code',
        'type': 0, // EntryType.key
        'urlDomain': 'stripe.com',
        'createdAt': '2026-04-01T10:00:00Z',
        'updatedAt': '2026-04-25T12:30:00Z',
        'lastAccessedAt': '2026-04-26T08:15:00Z',
        'accessCount': 5,
      };

      final entity = EntryModel.fromJson(json).toEntity();

      expect(entity.id, 'e-1');
      expect(entity.vaultId, 'v-1');
      expect(entity.label, 'Stripe API Key');
      expect(entity.description, 'production');
      expect(entity.icon, 'code');
      expect(entity.type, EntryType.key);
      expect(entity.urlDomain, 'stripe.com');
      expect(entity.accessCount, 5);
      expect(entity.lastAccessedAt!.year, 2026);
      expect(entity.createdAt.toUtc().year, 2026);
    });

    test('defaults missing optional fields', () {
      final json = {
        'id': 'e-2',
        'vaultId': 'v-1',
        'label': 'Login',
        'type': 1, // EntryType.credential
        'createdAt': '2026-04-25T00:00:00Z',
        'updatedAt': '2026-04-25T00:00:00Z',
      };

      final entity = EntryModel.fromJson(json).toEntity();
      expect(entity.type, EntryType.credential);
      expect(entity.description, isNull);
      expect(entity.icon, isNull);
      expect(entity.urlDomain, isNull);
      expect(entity.lastAccessedAt, isNull);
      expect(entity.accessCount, 0);
    });
  });

  group('EntryContentModel', () {
    test('round-trips through JSON', () {
      final json = {
        'encryptedBlob': 'YmxvYg==',
        'nonce': 'bm9uY2U=',
      };
      final parsed = EntryContentModel.fromJson(json);
      expect(parsed.encryptedBlob, 'YmxvYg==');
      expect(parsed.nonce, 'bm9uY2U=');
      expect(parsed.toJson(), json);
    });
  });

  group('EntryDetailModel.fromJson', () {
    test('parses summary fields plus content envelope', () {
      final json = {
        'id': 'e-3',
        'vaultId': 'v-1',
        'label': 'Test',
        'type': 0, // EntryType.key
        'createdAt': '2026-04-25T00:00:00Z',
        'updatedAt': '2026-04-25T00:00:00Z',
        'content': {
          'encryptedBlob': 'YmxvYg==',
          'nonce': 'bm9uY2U=',
        },
      };

      final detail = EntryDetailModel.fromJson(json);
      expect(detail.content.encryptedBlob, 'YmxvYg==');
      expect(detail.content.nonce, 'bm9uY2U=');
      expect(detail.summary.id, 'e-3');
      expect(detail.summary.type, 0);
    });
  });

  group('EntryTypeExtension', () {
    test('toWire round-trips through fromWire', () {
      expect(EntryType.key.toWire(), 0);
      expect(EntryType.credential.toWire(), 1);
      expect(EntryTypeExtension.fromWire(0), EntryType.key);
      expect(EntryTypeExtension.fromWire(1), EntryType.credential);
    });

    test('fromWire falls back to credential on unknown ordinal', () {
      // Unknown wire values default to credential — surfaces the safer
      // two-field reveal panel rather than the single-secret panel.
      expect(EntryTypeExtension.fromWire(99), EntryType.credential);
      expect(EntryTypeExtension.fromWire(-1), EntryType.credential);
    });
  });

  group('CreateEntryRequest.toJson', () {
    test('includes all fields when provided', () {
      const request = CreateEntryRequest(
        label: 'Stripe',
        description: 'prod',
        icon: 'code',
        type: 0,
        content: EntryContentModel(
          encryptedBlob: 'Y2lwaGVy',
          nonce: 'bm9uY2U=',
        ),
        urlDomain: 'stripe.com',
      );

      final json = request.toJson();
      expect(json['label'], 'Stripe');
      expect(json['description'], 'prod');
      expect(json['icon'], 'code');
      expect(json['type'], 0);
      expect(json['urlDomain'], 'stripe.com');
      final content = json['content'] as Map<String, dynamic>;
      expect(content.containsKey('entryType'), isFalse);
      expect(content['encryptedBlob'], 'Y2lwaGVy');
      expect(content['nonce'], 'bm9uY2U=');
    });

    test('omits null optional fields', () {
      const request = CreateEntryRequest(
        label: 'Stripe',
        type: 0,
        content: EntryContentModel(
          encryptedBlob: 'Y2lwaGVy',
          nonce: 'bm9uY2U=',
        ),
      );

      final json = request.toJson();
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('icon'), isFalse);
      expect(json.containsKey('urlDomain'), isFalse);
      expect(json['label'], 'Stripe');
      expect(json['type'], 0);
      expect(json['content'], isA<Map<String, dynamic>>());
    });
  });

  group('KeyPayload / CredentialPayload', () {
    test('KeyPayload toJson omits null notes', () {
      const payload = KeyPayload(value: 'sk_live_xxx');
      final json = payload.toJson();
      expect(json['type'], 'KEY');
      expect(json['value'], 'sk_live_xxx');
      expect(json.containsKey('notes'), isFalse);
    });

    test('CredentialPayload round-trips through json', () {
      const payload = CredentialPayload(
        username: 'patryk',
        password: 'secret',
        url: 'https://stripe.com',
        notes: 'prod admin',
      );
      final json = payload.toJson();
      final parsed = CredentialPayload.fromJson(json);
      expect(parsed.username, 'patryk');
      expect(parsed.password, 'secret');
      expect(parsed.url, 'https://stripe.com');
      expect(parsed.notes, 'prod admin');
    });
  });
}
