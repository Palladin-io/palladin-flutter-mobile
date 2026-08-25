import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_grant_projection.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';

void main() {
  final memberSecret = <String, Object?>{
    'schema': 'palladin.member-secret.v1',
    'entryType': 'credential',
    'memberLabel': 'Database root',
    'agentLabel': 'Database',
    'description': null,
    'icon': null,
    'color': null,
    'discoverable': true,
    'content': {
      'username': 'agent_user',
      'password': 'selected-password',
      'url': 'postgres://db.internal',
      'urlDomain': 'db.internal',
      'totp': 'UNRELATED-TOTP-SENTINEL',
      'notes': 'UNRELATED-NOTES-SENTINEL',
      'customFields': [
        {
          'id': 'tenant',
          'label': 'Tenant',
          'kind': 'text',
          'value': 'UNRELATED-CUSTOM-SENTINEL',
          'includeInMemberIndex': false,
        },
      ],
    },
    'agentFieldAccess': {
      'credential.username': 'onGrantValue',
      'credential.password': 'onGrantValue',
      'credential.url': 'never',
      'credential.urlDomain': 'discovery',
      'credential.totp': 'onGrantDerived',
      'notes': 'never',
      'custom:tenant': 'onGrantValue',
    },
  };

  test('projects only selected values into the canonical grant payload', () {
    final result = projectCanonicalGrantPayload(
      canonicalVaultJson(memberSecret),
      {'credential.password', 'credential.username'},
    );

    expect(
      result,
      canonicalVaultJson({
        'schema': 'palladin.grant-payload.v1',
        'entryType': 'credential',
        'fields': [
          {
            'id': 'credential.password',
            'kind': 'concealed',
            'mode': 'value',
            'value': 'selected-password',
          },
          {
            'id': 'credential.username',
            'kind': 'text',
            'mode': 'value',
            'value': 'agent_user',
          },
        ],
      }),
    );
    final wire = utf8.decode(result);
    expect(wire, isNot(contains('UNRELATED-TOTP-SENTINEL')));
    expect(wire, isNot(contains('UNRELATED-NOTES-SENTINEL')));
    expect(wire, isNot(contains('UNRELATED-CUSTOM-SENTINEL')));
  });

  test('fails closed for a selected field without grant authorization', () {
    expect(
      () => projectCanonicalGrantPayload(canonicalVaultJson(memberSecret), {
        'credential.url',
      }),
      throwsFormatException,
    );
  });

  test('fails closed when a requested field is missing from the payload', () {
    expect(
      () => projectCanonicalGrantPayload(canonicalVaultJson(memberSecret), {
        'credential.password',
        'custom:missing',
      }),
      throwsFormatException,
    );
  });
}
