import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/dashboard/data/models/recent_entry_model.dart';

void main() {
  group('RecentEntryModel.fromJson → toEntity', () {
    test('parses all fields from a complete JSON object', () {
      final entity = RecentEntryModel.fromJson(<String, dynamic>{
        'id': 'entry-1',
        'label': 'Stripe API Key',
        'vaultId': 'vault-1',
        'vaultName': 'Production',
        'type': 0,
        'icon': 'vpn_key',
        'updatedAt': '2026-06-28T12:00:00Z',
        'createdAt': '2026-06-01T08:00:00Z',
      }).toEntity();

      expect(entity.id, 'entry-1');
      expect(entity.label, 'Stripe API Key');
      expect(entity.vaultId, 'vault-1');
      expect(entity.vaultName, 'Production');
      expect(entity.typeWire, 0);
      expect(entity.icon, 'vpn_key');
      expect(entity.updatedAt, DateTime.utc(2026, 6, 28, 12));
      expect(entity.createdAt, DateTime.utc(2026, 6, 1, 8));
    });

    test('parses string type "Key" as 0', () {
      final model = RecentEntryModel.fromJson(<String, dynamic>{
        'id': 'e1',
        'label': 'L',
        'vaultId': 'v1',
        'vaultName': 'V',
        'type': 'Key',
        'updatedAt': '2026-06-01T00:00:00Z',
        'createdAt': '2026-06-01T00:00:00Z',
      });
      expect(model.type, 0);
    });

    test('parses string type "Credential" as 1', () {
      final model = RecentEntryModel.fromJson(<String, dynamic>{
        'id': 'e2',
        'label': 'L',
        'vaultId': 'v1',
        'vaultName': 'V',
        'type': 'Credential',
        'updatedAt': '2026-06-01T00:00:00Z',
        'createdAt': '2026-06-01T00:00:00Z',
      });
      expect(model.type, 1);
    });

    test('icon is nullable — null when absent', () {
      final entity = RecentEntryModel.fromJson(<String, dynamic>{
        'id': 'e3',
        'label': 'L',
        'vaultId': 'v1',
        'vaultName': 'V',
        'type': 1,
        'updatedAt': '2026-06-01T00:00:00Z',
        'createdAt': '2026-06-01T00:00:00Z',
      }).toEntity();
      expect(entity.icon, isNull);
    });
  });
}
