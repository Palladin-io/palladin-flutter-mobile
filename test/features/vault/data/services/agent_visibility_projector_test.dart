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
        agentLabel: 'Account',
        description: '',
        content: {'password': 'secret'},
        policy: policy,
        approvedFieldIds: const ['password'],
      ),
      throwsFormatException,
    );
  });

  test('Credit card fields stay runtime-only while methods remain generic', () {
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

    expect(discovery['capabilities'], const ['get', 'exec', 'inject']);
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
      agentLabel: 'API key',
      description: '',
      content: {'value': 'secret', 'notes': null},
      policy: policy,
    );
    final payload = AgentVisibilityProjector.grantPayload(
      type: EntryType.key,
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
}
