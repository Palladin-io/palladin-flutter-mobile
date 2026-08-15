import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';

void main() {
  const icon = GlyphVaultIcon('key');
  final credential = MemberSecret(
    entryType: VaultEntryType.credential,
    memberLabel: 'GitHub work',
    agentLabel: 'GitHub work account',
    description: 'Engineering',
    icon: icon,
    color: '#123ABC',
    discoverable: true,
    content: const CredentialSecretContent(
      username: 'patryk@example.com',
      password: 'secret',
      url: 'https://github.com/login',
      urlDomain: 'github.com',
      totp: {
        'secret': 'JBSWY3DPEHPK3PXP',
        'algorithm': 'SHA1',
        'digits': 6,
        'period': 30,
      },
      notes: null,
      customFields: [
        VaultCustomField(
          id: 'd9428888-122b-11e1-b85c-61cd3cbb3210',
          label: 'Tenant',
          kind: 'text',
          value: 'Acme',
          includeInMemberIndex: true,
        ),
      ],
    ),
    agentFieldAccess: const {
      'memberLabel': AgentFieldAccess.never,
      'agentLabel': AgentFieldAccess.discovery,
      'description': AgentFieldAccess.never,
      'icon': AgentFieldAccess.never,
      'color': AgentFieldAccess.never,
      'entryType': AgentFieldAccess.discovery,
      'credential.username': AgentFieldAccess.discovery,
      'credential.password': AgentFieldAccess.onGrantValue,
      'credential.url': AgentFieldAccess.onGrantValue,
      'credential.urlDomain': AgentFieldAccess.discovery,
      'credential.totp': AgentFieldAccess.onGrantDerived,
      'notes': AgentFieldAccess.never,
      'custom:d9428888-122b-11e1-b85c-61cd3cbb3210':
          AgentFieldAccess.onGrantValue,
    },
  );

  test('metadata rejects unknown fields and non-canonical color', () {
    final valid = <String, Object?>{
      'schema': MemberVaultMetadata.schema,
      'name': 'Personal',
      'description': null,
      'icon': null,
      'color': '#AABBCC',
      'grantMode': 'granular',
    };
    expect(MemberVaultMetadata.fromJson(valid).name, 'Personal');
    expect(
      () => MemberVaultMetadata.fromJson({...valid, 'future': true}),
      throwsA(isA<VaultPlaintextFormatException>()),
    );
    expect(
      () => MemberVaultMetadata.fromJson({...valid, 'color': '#aabbcc'}),
      throwsA(isA<VaultPlaintextFormatException>()),
    );
  });

  test('unknown closed enum values fail closed', () {
    expect(
      () => VaultEntryType.parse('future'),
      throwsA(isA<VaultPlaintextFormatException>()),
    );
    expect(
      () => AgentFieldAccess.parse('visible'),
      throwsA(isA<VaultPlaintextFormatException>()),
    );
  });

  test('icon references preserve their canonical namespace', () {
    expect(
      VaultPlaintextIcon.fromReference(
        'public-asset:11111111-1111-4111-8111-111111111111|1|https%3A%2F%2Fassets.palladin.io%2Fstripe.png',
      ),
      isA<PublicAssetVaultIcon>(),
    );
    expect(
      VaultPlaintextIcon.fromReference(
        'asset:11111111-1111-4111-8111-111111111111',
      ),
      isA<EncryptedAssetVaultIcon>(),
    );
    expect(
      () => VaultPlaintextIcon.fromReference('https://stripe.com/icon.png'),
      throwsA(isA<VaultPlaintextFormatException>()),
    );
  });

  test('MemberIndex contains only safe list projection fields', () {
    final index = VaultPlaintextProjector.memberIndex(credential).toJson();
    expect(index['username'], 'patryk@example.com');
    expect(index['urlDomain'], 'github.com');
    expect(jsonEncode(index), isNot(contains('secret')));
    expect(jsonEncode(index), isNot(contains('JBSWY3')));
    expect(jsonEncode(index), isNot(contains('https://')));
  });

  test('MemberIndex accepts bounded legacy app URLs used by web imports', () {
    final androidUrl =
        'android://${'a' * 300}@com.example.application/some/deep/link';
    final parsed = MemberIndex.fromJson({
      'schema': MemberIndex.schema,
      'entryType': 'credential',
      'memberLabel': 'Imported application',
      'description': null,
      'icon': null,
      'color': null,
      'username': null,
      'urlDomain': androidUrl,
      'customIndex': const <Object>[],
    });

    expect(parsed.urlDomain, androidUrl);
  });

  test('Discovery contains only discovery fields in ASCII order', () {
    final discovery = VaultPlaintextProjector.agentDiscovery(credential)!;
    final fields = discovery['fields']! as List<Object?>;
    expect(fields, [
      {'id': 'credential.urlDomain', 'value': 'github.com'},
      {'id': 'credential.username', 'value': 'patryk@example.com'},
    ]);
    expect(jsonEncode(discovery), isNot(contains('password')));
  });

  test('Grant is sorted, filtered and carries exact result modes', () {
    final grant = VaultPlaintextProjector.grantPayload(credential, {
      'credential.totp',
      'credential.password',
    });
    expect(grant.containsKey('capabilities'), isFalse);
    expect(grant['fields'], [
      {
        'id': 'credential.password',
        'kind': 'concealed',
        'mode': 'value',
        'value': 'secret',
      },
      {
        'id': 'credential.totp',
        'kind': 'totp',
        'mode': 'derived',
        'value': {
          'secret': 'JBSWY3DPEHPK3PXP',
          'algorithm': 'SHA1',
          'digits': 6,
          'period': 30,
        },
      },
    ]);
    expect(
      () => VaultPlaintextProjector.grantPayload(credential, {
        'credential.username',
      }),
      throwsA(isA<VaultPlaintextFormatException>()),
    );
  });

  test(
    'wire MemberSecret projection is byte-equivalent to typed projection',
    () {
      final typed = VaultPlaintextProjector.grantPayload(credential, {
        'credential.password',
        'credential.totp',
      });
      final wire = VaultPlaintextProjector.grantPayloadFromJson(
        Map<String, dynamic>.from(credential.toJson()),
        {'credential.password', 'credential.totp'},
      );
      expect(canonicalVaultJson(wire), canonicalVaultJson(typed));
    },
  );

  test('canonical JSON sorts object keys recursively', () {
    expect(
      utf8.decode(
        canonicalVaultJson({
          'z': {'b': 2, 'a': 1},
          'a': true,
        }),
      ),
      '{"a":true,"z":{"a":1,"b":2}}',
    );
  });

  test('policy must exactly cover the typed content union', () {
    expect(
      () => MemberSecret(
        entryType: VaultEntryType.key,
        memberLabel: 'Key',
        agentLabel: null,
        description: null,
        icon: null,
        color: null,
        discoverable: false,
        content: const KeySecretContent(
          value: 'secret',
          notes: null,
          customFields: [],
        ),
        agentFieldAccess: const {
          'memberLabel': AgentFieldAccess.never,
          'agentLabel': AgentFieldAccess.never,
          'description': AgentFieldAccess.never,
          'icon': AgentFieldAccess.never,
          'color': AgentFieldAccess.never,
          'entryType': AgentFieldAccess.never,
          'key.value': AgentFieldAccess.onGrantValue,
          // notes deliberately absent
        },
      ),
      throwsA(isA<VaultPlaintextFormatException>()),
    );
  });
}
