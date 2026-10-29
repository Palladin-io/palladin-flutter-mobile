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

  test(
    'an optional catalog icon without identity cannot corrupt a saved index',
    () {
      final icon = VaultPlaintextIcon.fromReference(
        'public-asset:|1|https%3A%2F%2Fassets.example.com%2Ficon.png',
      );
      final roundTrip = MemberIndex.fromJson({
        ...VaultPlaintextProjector.memberIndex(credential).toJson(),
        'icon': icon?.toJson(),
      });
      expect(roundTrip.icon, isNull);
    },
  );

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

  test('canonical JSON preserves finite fractional numbers', () {
    expect(
      utf8.decode(
        canonicalVaultJson({
          'fractional': 1.5,
          'negativeZero': -0.0,
          'whole': 1.0,
        }),
      ),
      '{"fractional":1.5,"negativeZero":0,"whole":1}',
    );
    expect(
      () => canonicalVaultJson({'invalid': double.infinity}),
      throwsA(isA<VaultPlaintextFormatException>()),
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

  group('canonical custom fields', () {
    const unknownId = '55555555-5555-4555-8555-555555555555';
    MemberSecret withUnknown(AgentFieldAccess access) => MemberSecret(
      entryType: VaultEntryType.credential,
      memberLabel: credential.memberLabel,
      agentLabel: credential.agentLabel,
      description: credential.description,
      icon: credential.icon,
      color: credential.color,
      discoverable: true,
      content: CredentialSecretContent(
        username: 'patryk@example.com',
        password: '',
        url: null,
        urlDomain: null,
        totp: null,
        notes: null,
        customFields: const [
          VaultCustomField(
            id: unknownId,
            label: 'Sign-in method',
            kind: 'palladin.signin.v1',
            value: {'provider': 'github', 'account': null},
          ),
        ],
      ),
      agentFieldAccess: {
        'memberLabel': AgentFieldAccess.never,
        'agentLabel': AgentFieldAccess.discovery,
        'description': AgentFieldAccess.never,
        'icon': AgentFieldAccess.never,
        'color': AgentFieldAccess.never,
        'entryType': AgentFieldAccess.discovery,
        'credential.username': AgentFieldAccess.onGrantValue,
        'credential.password': AgentFieldAccess.never,
        'credential.url': AgentFieldAccess.never,
        'credential.urlDomain': AgentFieldAccess.never,
        'credential.totp': AgentFieldAccess.never,
        'notes': AgentFieldAccess.never,
        'custom:$unknownId': access,
      },
    );

    test('serialize in the canonical shape without local flags', () {
      final fields =
          (credential.toJson()['content']! as Map)['customFields'] as List;
      expect(fields, [
        {
          'id': 'custom:d9428888-122b-11e1-b85c-61cd3cbb3210',
          'label': 'Tenant',
          'type': 'text',
          'value': 'Acme',
        },
      ]);
    });

    test('unknown types are preserved with never access only', () {
      final secret = withUnknown(AgentFieldAccess.never);
      final field =
          ((secret.toJson()['content']! as Map)['customFields'] as List).single;
      expect(field, {
        'id': 'custom:$unknownId',
        'label': 'Sign-in method',
        'type': 'palladin.signin.v1',
        'value': {'provider': 'github', 'account': null},
      });
      expect(VaultPlaintextProjector.memberIndex(secret).customIndex, isEmpty);
      expect(
        jsonEncode(VaultPlaintextProjector.agentDiscovery(secret)),
        isNot(contains('github')),
      );
      expect(
        () =>
            VaultPlaintextProjector.grantPayload(secret, {'custom:$unknownId'}),
        throwsA(isA<VaultPlaintextFormatException>()),
      );
    });

    for (final access in [
      AgentFieldAccess.discovery,
      AgentFieldAccess.onGrantValue,
      AgentFieldAccess.onGrantDerived,
      AgentFieldAccess.onGrantRuntime,
    ]) {
      test('unknown types reject ${access.name} access', () {
        expect(
          () => withUnknown(access),
          throwsA(isA<VaultPlaintextFormatException>()),
        );
      });
    }
  });

  group('sign-in method policy and Discovery', () {
    const signInId = '55555555-5555-4555-8555-555555555555';
    const otherSignInId = '66666666-6666-4666-8666-666666666666';
    const teamId = '44444444-4444-4444-8444-444444444444';
    const vaultId = '22222222-2222-4222-8222-222222222222';
    const entryId = '33333333-3333-4333-8333-333333333333';
    const linked = {
      'provider': 'google',
      'account': 'alice@example.com',
      'entry': {'vaultId': vaultId, 'entryId': entryId},
    };

    MemberSecret secretWith({
      VaultEntryType type = VaultEntryType.credential,
      List<VaultCustomField> fields = const [],
      Map<String, AgentFieldAccess> custom = const {},
    }) => MemberSecret(
      entryType: type,
      memberLabel: 'Example',
      agentLabel: 'Example agent',
      description: null,
      icon: null,
      color: null,
      discoverable: true,
      content: type == VaultEntryType.credential
          ? CredentialSecretContent(
              username: 'service-user',
              password: '',
              url: 'https://example.test',
              urlDomain: 'example.test',
              totp: null,
              notes: null,
              customFields: fields,
            )
          : KeySecretContent(value: 'k', notes: null, customFields: fields),
      agentFieldAccess: {
        'memberLabel': AgentFieldAccess.never,
        'agentLabel': AgentFieldAccess.discovery,
        'description': AgentFieldAccess.never,
        'icon': AgentFieldAccess.never,
        'color': AgentFieldAccess.never,
        'entryType': AgentFieldAccess.discovery,
        if (type == VaultEntryType.credential) ...{
          'credential.username': AgentFieldAccess.onGrantValue,
          'credential.password': AgentFieldAccess.never,
          'credential.url': AgentFieldAccess.never,
          'credential.urlDomain': AgentFieldAccess.discovery,
          'credential.totp': AgentFieldAccess.never,
        } else
          'key.value': AgentFieldAccess.never,
        'notes': AgentFieldAccess.never,
        ...custom,
      },
    );

    VaultCustomField signIn(Object? value, {String id = signInId}) =>
        VaultCustomField(
          id: id,
          label: 'Sign-in method',
          kind: 'palladin.signin.v1',
          value: value,
        );

    test('a valid Credential binding allows never and discovery', () {
      for (final access in [
        AgentFieldAccess.never,
        AgentFieldAccess.discovery,
      ]) {
        expect(
          () => secretWith(
            fields: [signIn(linked)],
            custom: {'custom:$signInId': access},
          ),
          returnsNormally,
        );
      }
    });

    for (final access in [
      AgentFieldAccess.onGrantValue,
      AgentFieldAccess.onGrantDerived,
      AgentFieldAccess.onGrantRuntime,
    ]) {
      test('a valid binding rejects ${access.name}', () {
        expect(
          () => secretWith(
            fields: [signIn(linked)],
            custom: {'custom:$signInId': access},
          ),
          throwsA(isA<VaultPlaintextFormatException>()),
        );
      });
    }

    for (final (name, type, value) in <(String, VaultEntryType, Object?)>[
      (
        'retired two-key value',
        VaultEntryType.credential,
        {'provider': 'google', 'account': null},
      ),
      ('non-Credential Entry', VaultEntryType.key, linked),
    ]) {
      test('$name allows only never', () {
        expect(
          () => secretWith(
            type: type,
            fields: [signIn(value)],
            custom: {'custom:$signInId': AgentFieldAccess.never},
          ),
          returnsNormally,
        );
        expect(
          () => secretWith(
            type: type,
            fields: [signIn(value)],
            custom: {'custom:$signInId': AgentFieldAccess.discovery},
          ),
          throwsA(isA<VaultPlaintextFormatException>()),
        );
      });
    }

    test('other unknown types still allow only never', () {
      expect(
        () => secretWith(
          fields: const [
            VaultCustomField(
              id: signInId,
              label: 'Future',
              kind: 'palladin.future.v9',
              value: 'x',
            ),
          ],
          custom: {'custom:$signInId': AgentFieldAccess.discovery},
        ),
        throwsA(isA<VaultPlaintextFormatException>()),
      );
    });

    test('Discovery emits the canonical signIn string and no account', () {
      final secret = secretWith(
        fields: [
          signIn(linked),
          const VaultCustomField(
            id: teamId,
            label: 'Team',
            kind: 'text',
            value: 'qa',
          ),
        ],
        custom: {
          'custom:$signInId': AgentFieldAccess.discovery,
          'custom:$teamId': AgentFieldAccess.discovery,
        },
      );
      final discovery = VaultPlaintextProjector.agentDiscovery(secret)!;
      const signInValue =
          '{"entry":{"entryId":"$entryId","vaultId":"$vaultId"},'
          '"provider":"google","schema":"palladin.signin.v1"}';
      expect(discovery['fields'], [
        {'id': 'credential.urlDomain', 'value': 'example.test'},
        {'id': 'custom:$teamId', 'value': 'qa'},
        {'id': 'signIn', 'value': signInValue},
      ]);
      expect(
        utf8.decode(canonicalVaultJson(discovery)),
        '{"agentLabel":"Example agent",'
        '"capabilities":["get","exec","inject"],'
        '"entryType":"credential",'
        '"fields":['
        '{"id":"credential.urlDomain","value":"example.test"},'
        '{"id":"custom:$teamId","value":"qa"},'
        '{"id":"signIn","value":${jsonEncode(signInValue)}}'
        '],'
        '"schema":"palladin.agent-discovery.v1"}',
      );
      expect(jsonEncode(discovery), isNot(contains('alice')));
      expect(jsonEncode(discovery), isNot(contains('custom:$signInId')));
    });

    test('a never binding is hidden and an unlinked one has a null entry', () {
      final hidden = secretWith(
        fields: [signIn(linked)],
        custom: {'custom:$signInId': AgentFieldAccess.never},
      );
      expect(
        jsonEncode(VaultPlaintextProjector.agentDiscovery(hidden)),
        isNot(contains('signIn')),
      );
      final unlinked = secretWith(
        fields: [
          signIn({'provider': 'github', 'account': null, 'entry': null}),
        ],
        custom: {'custom:$signInId': AgentFieldAccess.discovery},
      );
      expect(
        (VaultPlaintextProjector.agentDiscovery(unlinked)!['fields'] as List)
            .last,
        {
          'id': 'signIn',
          'value':
              '{"entry":null,"provider":"github",'
              '"schema":"palladin.signin.v1"}',
        },
      );
    });

    test('two discoverable bindings are ambiguous and not exposed', () {
      final secret = secretWith(
        fields: [
          signIn(linked),
          signIn({
            'provider': 'apple',
            'account': null,
            'entry': null,
          }, id: otherSignInId),
        ],
        custom: {
          'custom:$signInId': AgentFieldAccess.discovery,
          'custom:$otherSignInId': AgentFieldAccess.discovery,
        },
      );
      expect(VaultPlaintextProjector.agentDiscovery(secret)!['fields'], [
        {'id': 'credential.urlDomain', 'value': 'example.test'},
      ]);
    });
  });
}
