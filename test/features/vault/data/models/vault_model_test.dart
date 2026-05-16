import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_claw_vault/features/vault/data/models/create_vault_request.dart';
import 'package:mobile_claw_vault/features/vault/data/models/vault_model.dart';
import 'package:mobile_claw_vault/features/vault/domain/entities/vault_entity.dart';

void main() {
  group('VaultModel.fromJson / toEntity', () {
    test('parses a full vault list payload entry', () {
      final json = {
        'id': 'v-1',
        'name': 'Personal',
        'description': 'private stuff',
        'icon': '🔒',
        'color': '#48ECDF',
        'grantMode': 2,
        'createdAt': '2026-04-01T10:00:00Z',
        'updatedAt': '2026-04-25T12:30:00Z',
        'entryCount': 7,
        'activeGrantCount': 1,
        'memberCount': 1,
      };

      final model = VaultModel.fromJson(json);
      final entity = model.toEntity();

      expect(entity.id, 'v-1');
      expect(entity.name, 'Personal');
      expect(entity.description, 'private stuff');
      expect(entity.icon, '🔒');
      expect(entity.color, '#48ECDF');
      expect(entity.grantMode, GrantMode.granular);
      expect(entity.entryCount, 7);
      expect(entity.activeGrantCount, 1);
      expect(entity.memberCount, 1);
      expect(entity.createdAt.toUtc().year, 2026);
      // List endpoint omits wrappedVK — entity should reflect that.
      expect(entity.wrappedVK, isNull);
    });

    test('threads wrappedVK from the detail payload through to the entity', () {
      // GET /api/vaults/{id} includes the sealed VK as a base64 string.
      final json = {
        'id': 'v-1',
        'name': 'Personal',
        'grantMode': 2,
        'createdAt': '2026-04-01T10:00:00Z',
        'updatedAt': '2026-04-25T12:30:00Z',
        'entryCount': 0,
        'activeGrantCount': 0,
        'memberCount': 1,
        'wrappedVK': 'd3JhcHBlZC1iYXNlNjQ=',
      };

      final entity = VaultModel.fromJson(json).toEntity();
      expect(entity.wrappedVK, 'd3JhcHBlZC1iYXNlNjQ=');
    });

    test('defaults missing counters on the create-vault response shape', () {
      final json = {
        'id': 'v-2',
        'name': 'Work',
        'description': null,
        'icon': null,
        'color': null,
        'grantMode': 1,
        'createdAt': '2026-04-25T00:00:00Z',
        'updatedAt': '2026-04-25T00:00:00Z',
        // entryCount / activeGrantCount / memberCount intentionally absent
      };

      final entity = VaultModel.fromJson(json).toEntity();
      expect(entity.grantMode, GrantMode.full);
      expect(entity.entryCount, 0);
      expect(entity.activeGrantCount, 0);
      expect(entity.memberCount, 1);
      expect(entity.description, isNull);
      expect(entity.icon, isNull);
    });
  });

  group('GrantModeExtension', () {
    test('round-trips Full and Granular through int', () {
      expect(GrantMode.full.toInt(), 1);
      expect(GrantMode.granular.toInt(), 2);
      expect(GrantModeExtension.fromInt(1), GrantMode.full);
      expect(GrantModeExtension.fromInt(2), GrantMode.granular);
    });

    test('fromInt defaults to Granular for unknown wire values', () {
      // Granular is the safer default — surfaces no-grant rather than
      // accidentally giving Full access if the backend ever ships an
      // unknown integer.
      expect(GrantModeExtension.fromInt(99), GrantMode.granular);
    });
  });

  group('CreateVaultRequest.toJson', () {
    test('omits null optional fields from the JSON body', () {
      final request = CreateVaultRequest(
        name: 'New',
        grantMode: GrantMode.granular,
        wrappedVK: 'd3JhcHBlZA==',
      );

      final json = request.toJson();
      expect(json, isA<Map<String, dynamic>>());
      expect(json['name'], 'New');
      expect(json['grantMode'], 2);
      expect(json['wrappedVK'], 'd3JhcHBlZA==');
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('icon'), isFalse);
      expect(json.containsKey('color'), isFalse);
    });

    test('includes optional fields when provided', () {
      final request = CreateVaultRequest(
        name: 'New',
        description: 'desc',
        icon: '🔒',
        color: '#48ECDF',
        grantMode: GrantMode.full,
        wrappedVK: 'd3JhcHBlZA==',
      );

      final json = request.toJson();
      expect(json['description'], 'desc');
      expect(json['icon'], '🔒');
      expect(json['color'], '#48ECDF');
      expect(json['grantMode'], 1);
    });
  });

  group('UpdateVaultRequest.toJson', () {
    test('emits an empty map when no fields are supplied', () {
      const request = UpdateVaultRequest();
      expect(request.toJson(), isEmpty);
    });

    test('only emits non-null fields (patch semantics)', () {
      const request = UpdateVaultRequest(
        name: 'Renamed',
        grantMode: GrantMode.full,
      );
      expect(request.toJson(), {
        'name': 'Renamed',
        'grantMode': 1,
      });
    });
  });
}
