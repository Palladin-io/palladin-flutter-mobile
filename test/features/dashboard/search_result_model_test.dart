import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/dashboard/data/models/search_result_model.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/search_result_entity.dart';

void main() {
  group('SearchResultModel.fromJson', () {
    test('parses an entry hit with vaultId + vaultName', () {
      final model = SearchResultModel.fromJson(const {
        'type': 'entry',
        'id': 'e1',
        'name': 'Stripe API Key',
        'vaultId': 'v1',
        'vaultName': 'Production',
        'icon': 'vpn_key',
      });

      expect(model.type, SearchResultType.entry);
      expect(model.id, 'e1');
      expect(model.name, 'Stripe API Key');
      expect(model.vaultId, 'v1');
      expect(model.vaultName, 'Production');
      expect(model.icon, 'vpn_key');
    });

    test('leaves vaultId/vaultName null for a vault hit', () {
      final model = SearchResultModel.fromJson(const {
        'type': 'vault',
        'id': 'v1',
        'name': 'Production',
      });

      expect(model.type, SearchResultType.vault);
      expect(model.vaultId, isNull);
      expect(model.vaultName, isNull);
      expect(model.icon, isNull);
    });

    test('leaves vaultId null for an agent hit', () {
      final model = SearchResultModel.fromJson(const {
        'type': 'agent',
        'id': 'a1',
        'name': 'Claude Code',
      });

      expect(model.type, SearchResultType.agent);
      expect(model.vaultId, isNull);
    });

    test('unknown type falls back to entry (forward-compatible)', () {
      final model = SearchResultModel.fromJson(const {
        'type': 'something-new',
        'id': 'x1',
        'name': 'Mystery',
      });

      expect(model.type, SearchResultType.entry);
    });
  });

  group('SearchResultModel.toEntity', () {
    test('carries vaultId through to the entity', () {
      const model = SearchResultModel(
        type: SearchResultType.entry,
        id: 'e1',
        name: 'Stripe API Key',
        vaultId: 'v1',
        vaultName: 'Production',
        icon: 'vpn_key',
      );

      final entity = model.toEntity();

      expect(entity.type, SearchResultType.entry);
      expect(entity.id, 'e1');
      expect(entity.name, 'Stripe API Key');
      expect(entity.vaultId, 'v1');
      expect(entity.vaultName, 'Production');
      expect(entity.icon, 'vpn_key');
    });
  });
}
