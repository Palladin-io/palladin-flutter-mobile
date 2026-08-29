import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_palladin/features/vault/data/services/agent_visibility_projector.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';

void main() {
  test('grant payload matches the public cross-client contract bytes', () {
    final contract =
        jsonDecode(
              File(
                'test/fixtures/grant-payload/v1/vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final vector = (contract['vectors'] as List).single as Map<String, dynamic>;
    final policy = AgentVisibilityPolicy.fromJson(
      EntryType.credential,
      {
        'discoverable': true,
        'fields': {
          'agentLabel': 'discovery',
          'username': 'onGrantValue',
          'password': 'onGrantValue',
          'url': 'onGrantValue',
        },
      },
      content: {
        'username': 'synthetic-user',
        'password': 'synthetic-secret',
        'url': 'https://example.test/login',
      },
    );

    final payload = AgentVisibilityProjector.grantPayload(
      type: EntryType.credential,
      vaultId: '11112222-3333-4444-8555-666677778888',
      agentLabel: 'Example',
      description: '',
      content: const {
        'username': 'synthetic-user',
        'password': 'synthetic-secret',
        'url': 'https://example.test/login',
      },
      policy: policy,
      approvedFieldIds: const ['username', 'password', 'url'],
    );

    expect(canonicalizeVaultJson(payload), vector['plaintextCanonical']);
    expect(payload, vector['plaintext']);
    expect(
      AgentVisibilityProjector.grantPayloadFieldIds(payload),
      vector['fieldIds'],
    );
  });

  test(
    'legacy mobile GrantPayload remains a read-only compatibility vector',
    () {
      final contract =
          jsonDecode(
                File(
                  'test/fixtures/grant-payload/v1/vectors.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final vector =
          (contract['compatibilityVectors'] as List).single
              as Map<String, dynamic>;
      final rejectedIds = (contract['rejectedExamples'] as List)
          .map((value) => (value as Map<String, dynamic>)['id'] as String)
          .where((id) => id.startsWith('legacy-'))
          .toSet();

      expect(
        vector['producerContract'],
        'flutter-mobile.legacy-grant-payload.v1',
      );
      expect(vector['readOnly'], isTrue);
      expect(
        canonicalizeVaultJson(vector['plaintext']),
        vector['plaintextCanonical'],
      );
      expect((vector['plaintext'] as Map).containsKey('schema'), isFalse);
      expect(rejectedIds, {
        'legacy-current-hybrid',
        'legacy-broadened-access',
        'legacy-field-set-mismatch',
        'legacy-missing-inject-origin',
        'legacy-unsupported-method',
      });
    },
  );

  test('TOTP can only be never or derived-only', () {
    expect(
      () => AgentVisibilityPolicy.fromJson(
        EntryType.credential,
        {
          'discoverable': true,
          'fields': {'agentLabel': 'discovery', 'totp': 'onGrantValue'},
        },
        content: {'totp': 'SEED'},
      ),
      throwsFormatException,
    );
  });

  test('Script source and refs can only be never or runtime-only', () {
    for (final field in ['script', 'refs']) {
      expect(
        () => AgentVisibilityPolicy.fromJson(
          EntryType.script,
          {
            'discoverable': true,
            'fields': {'agentLabel': 'discovery', field: 'onGrantValue'},
          },
          content: {'script': 'secret script', 'refs': const []},
        ),
        throwsFormatException,
      );
    }
  });

  test('Discovery never contains TOTP seed or Script source', () {
    final credential = AgentVisibilityPolicy.fromJson(
      EntryType.credential,
      {
        'discoverable': true,
        'fields': {
          'agentLabel': 'discovery',
          'username': 'discovery',
          'totp': 'onGrantDerived',
        },
      },
      content: {'username': 'agent-user', 'totp': 'TOPSECRET'},
    );
    final discovery = AgentVisibilityProjector.discovery(
      type: EntryType.credential,
      agentLabel: 'Agent account',
      description: '',
      content: {'username': 'agent-user', 'totp': 'TOPSECRET'},
      policy: credential,
    );
    expect(discovery.toString(), isNot(contains('TOPSECRET')));

    final script = AgentVisibilityPolicy.fromJson(
      EntryType.script,
      {
        'discoverable': true,
        'fields': {
          'agentLabel': 'discovery',
          'interpreter': 'discovery',
          'script': 'onGrantRuntime',
        },
      },
      content: {'interpreter': 'bash', 'script': 'secret script'},
    );
    final scriptDiscovery = AgentVisibilityProjector.discovery(
      type: EntryType.script,
      agentLabel: 'Deploy',
      description: '',
      content: {'interpreter': 'bash', 'script': 'secret script'},
      policy: script,
    );
    expect(scriptDiscovery.toString(), isNot(contains('secret script')));
  });

  test('grant projector rejects a field outside policy before encryption', () {
    final policy = AgentVisibilityPolicy.fromJson(
      EntryType.credential,
      {
        'discoverable': true,
        'fields': {'agentLabel': 'discovery', 'password': 'never'},
      },
      content: {'password': 'secret'},
    );
    expect(
      () => AgentVisibilityProjector.grantPayload(
        type: EntryType.credential,
        vaultId: '11112222-3333-4444-8555-666677778888',
        agentLabel: 'Account',
        description: '',
        content: {'password': 'secret'},
        policy: policy,
        approvedFieldIds: const ['password'],
      ),
      throwsFormatException,
    );
  });

  test('Credit card fields stay runtime-only and support inject only', () {
    final policy = AgentVisibilityPolicy.fromJson(
      EntryType.creditCard,
      {
        'discoverable': true,
        'fields': {'agentLabel': 'discovery', 'cardNumber': 'onGrantRuntime'},
      },
      content: {'cardNumber': '4242424242424242'},
    );
    final discovery = AgentVisibilityProjector.discovery(
      type: EntryType.creditCard,
      agentLabel: 'Payment card',
      description: '',
      content: {'cardNumber': '4242424242424242'},
      policy: policy,
    );

    expect(discovery['capabilities'], const ['inject']);
    expect(discovery.toString(), isNot(contains('4242424242424242')));
    expect(
      () => AgentVisibilityPolicy.fromJson(
        EntryType.creditCard,
        {
          'discoverable': true,
          'fields': {'agentLabel': 'discovery', 'cardNumber': 'onGrantValue'},
        },
        content: {'cardNumber': '4242424242424242'},
      ),
      throwsFormatException,
    );
  });

  test('grantable field set omits an authorized but absent optional value', () {
    final policy = AgentVisibilityPolicy.fromJson(
      EntryType.key,
      {
        'discoverable': true,
        'fields': {
          'agentLabel': 'discovery',
          'value': 'onGrantValue',
          'notes': 'onGrantValue',
        },
      },
      content: {'value': 'secret', 'notes': null},
    );

    final fieldIds = AgentVisibilityProjector.grantableFieldIds(
      type: EntryType.key,
      agentLabel: 'API key',
      description: '',
      content: {'value': 'secret', 'notes': null},
      policy: policy,
    );
    final payload = AgentVisibilityProjector.grantPayload(
      type: EntryType.key,
      vaultId: '11112222-3333-4444-8555-666677778888',
      agentLabel: 'API key',
      description: '',
      content: {'value': 'secret', 'notes': null},
      policy: policy,
      approvedFieldIds: fieldIds,
    );

    expect(fieldIds, ['value']);
    expect(payload['fields'], [
      {
        'id': 'key.value',
        'kind': 'concealed',
        'mode': 'value',
        'value': 'secret',
      },
    ]);
    expect(AgentVisibilityProjector.grantPayloadFieldIds(payload), [
      'key.value',
    ]);
  });

  test('description remains discovery-only and cannot enter a Grant', () {
    expect(
      () => AgentVisibilityPolicy.fromJson(EntryType.key, {
        'discoverable': true,
        'fields': {'agentLabel': 'discovery', 'description': 'onGrantValue'},
      }, content: const {}),
      throwsFormatException,
    );
  });

  test('notes use the namespaced public contract id', () {
    final policy = AgentVisibilityPolicy.fromJson(
      EntryType.key,
      {
        'discoverable': true,
        'fields': {'agentLabel': 'discovery', 'notes': 'onGrantValue'},
      },
      content: const {'notes': 'Synthetic note'},
    );

    final payload = AgentVisibilityProjector.grantPayload(
      type: EntryType.key,
      vaultId: '11112222-3333-4444-8555-666677778888',
      agentLabel: 'API key',
      description: '',
      content: const {'notes': 'Synthetic note'},
      policy: policy,
      approvedFieldIds: const ['notes'],
    );

    expect(payload['fields'], [
      {
        'id': 'key.notes',
        'kind': 'multiline',
        'mode': 'value',
        'value': 'Synthetic note',
      },
    ]);
  });

  test('TOTP grants contain only a short-lived derived code', () {
    const rawTotp =
        'otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP&issuer=Example';
    final policy = AgentVisibilityPolicy.fromJson(
      EntryType.credential,
      {
        'discoverable': true,
        'fields': {'agentLabel': 'discovery', 'totp': 'onGrantDerived'},
      },
      content: const {'totp': rawTotp},
    );

    final payload = AgentVisibilityProjector.grantPayload(
      type: EntryType.credential,
      vaultId: '11112222-3333-4444-8555-666677778888',
      agentLabel: 'Account',
      description: '',
      content: const {'totp': rawTotp},
      policy: policy,
      approvedFieldIds: const ['totp'],
      now: DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true),
    );

    final value = (payload['fields'] as List).single['value'] as Map;
    expect(value.keys.toSet(), {'code', 'expiresIn'});
    expect(value['code'], matches(RegExp(r'^\d{6}$')));
    expect(value['expiresIn'], 1);
    expect(value.toString(), isNot(contains('JBSWY3DPEHPK3PXP')));
  });

  test('disabled credit-card preview cannot produce GrantPayload v1', () {
    final policy = AgentVisibilityPolicy.fromJson(
      EntryType.creditCard,
      {
        'discoverable': true,
        'fields': {'agentLabel': 'discovery', 'cardNumber': 'onGrantRuntime'},
      },
      content: const {'cardNumber': '4242424242424242'},
    );

    expect(
      AgentVisibilityProjector.grantableFieldIds(
        type: EntryType.creditCard,
        agentLabel: 'Card',
        description: '',
        content: const {'cardNumber': '4242424242424242'},
        policy: policy,
      ),
      isEmpty,
    );
    expect(
      () => AgentVisibilityProjector.grantPayload(
        type: EntryType.creditCard,
        vaultId: '11112222-3333-4444-8555-666677778888',
        agentLabel: 'Card',
        description: '',
        content: const {'cardNumber': '4242424242424242'},
        policy: policy,
        approvedFieldIds: const ['cardNumber'],
      ),
      throwsFormatException,
    );
  });

  test('grant payload defaults a legacy Script ref to its current vault', () {
    const vaultId = '11112222-3333-4444-8555-666677778888';
    final policy = AgentVisibilityPolicy.fromJson(
      EntryType.script,
      {
        'discoverable': true,
        'fields': {'agentLabel': 'discovery', 'refs': 'onGrantRuntime'},
      },
      content: const {
        'refs': [
          {
            'env': 'PASSWORD',
            'entryId': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
            'field': 'password',
          },
        ],
      },
    );

    final payload = AgentVisibilityProjector.grantPayload(
      type: EntryType.script,
      vaultId: vaultId,
      agentLabel: 'Deploy',
      description: '',
      content: const {
        'refs': [
          {
            'env': 'PASSWORD',
            'entryId': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
            'field': 'password',
          },
        ],
      },
      policy: policy,
      approvedFieldIds: const ['refs'],
    );

    expect((payload['fields'] as List).single['value'], [
      {
        'env': 'PASSWORD',
        'vaultId': vaultId,
        'entryId': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        'fieldId': 'credential.password',
      },
    ]);
  });

  test('Script ref preserves an explicit Key URL field identity', () {
    const vaultId = '11112222-3333-4444-8555-666677778888';
    final policy = AgentVisibilityPolicy.fromJson(
      EntryType.script,
      {
        'discoverable': true,
        'fields': {'agentLabel': 'discovery', 'refs': 'onGrantRuntime'},
      },
      content: const {
        'refs': [
          {
            'env': 'SERVICE_URL',
            'entryId': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
            'field': 'key.url',
          },
        ],
      },
    );

    final payload = AgentVisibilityProjector.grantPayload(
      type: EntryType.script,
      vaultId: vaultId,
      agentLabel: 'Deploy',
      description: '',
      content: const {
        'refs': [
          {
            'env': 'SERVICE_URL',
            'entryId': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
            'field': 'key.url',
          },
        ],
      },
      policy: policy,
      approvedFieldIds: const ['refs'],
    );

    expect((payload['fields'] as List).single['value'], [
      {
        'env': 'SERVICE_URL',
        'vaultId': vaultId,
        'entryId': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        'fieldId': 'key.url',
      },
    ]);
  });
}
