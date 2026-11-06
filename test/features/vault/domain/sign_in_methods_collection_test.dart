import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/domain/entities/custom_field.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/sign_in_method.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_form_utils.dart';

const upper = 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA';
const second = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
CustomField method(
  String id, {
  String type = SignInMethodField.collectionType,
  String account = 'synthetic@example.test',
}) => CustomField(
  id: id,
  label: 'Provider',
  type: CustomFieldType.unknown,
  rawType: type,
  value: {'provider': 'google', 'account': account, 'entry': null},
);

void main() {
  test(
    'mutation addresses an ID, preserves v1 and opaque neighbors, never merges accounts',
    () {
      final legacy = method(upper, type: SignInMethodField.type);
      final opaque = CustomField(
        id: 'opaque',
        label: 'Future',
        type: CustomFieldType.unknown,
        rawType: 'palladin.signin.v9',
        value: {'future': true},
      );
      final added = SignInMethodField.update(
        [legacy, opaque],
        binding: const SignInMethodBinding(
          provider: SignInProvider.google,
          account: 'synthetic@example.test',
        ),
        label: 'Method',
        newId: second,
      );
      expect(added, hasLength(3));
      expect(identical(added.first, legacy), isTrue);
      expect(identical(added[1], opaque), isTrue);
      final edited = SignInMethodField.update(
        added,
        fieldId: upper,
        binding: const SignInMethodBinding(provider: SignInProvider.apple),
        label: 'Ignored',
        newId: 'ignored',
      );
      expect(edited.first.id, upper);
      expect(edited.first.rawType, SignInMethodField.collectionType);
      expect(edited.first.label, legacy.label);
      expect(identical(edited.last, added.last), isTrue);
      final removed = SignInMethodField.update(
        edited,
        fieldId: second,
        binding: null,
        label: 'Ignored',
        newId: 'ignored',
      );
      expect(removed.map((field) => field.id), [upper, 'opaque']);
    },
  );

  test(
    'shared positive fixtures produce byte-equivalent canonical redacted collections',
    () {
      final fixtures =
          jsonDecode(
                File(
                  'test/fixtures/federated_signin_v2/fixtures.json',
                ).readAsStringSync(),
              )
              as Map;
      for (final fixture in fixtures['positive'] as List) {
        final fields = [
          for (final raw in fixture['methods'] as List)
            CustomField(
              id: raw['id'],
              label: 'Synthetic',
              type: CustomFieldType.unknown,
              rawType: SignInMethodField.collectionType,
              value: {
                'provider': raw['provider'],
                'account': 'private account',
                'entry': raw['entry'],
              },
            ),
        ];
        final value = SignInMethodField.collectionDiscovery(fields, {
          for (final field in fields) field.id,
        });
        expect(jsonDecode(value!), fixture);
        expect(
          value,
          utf8.decode(
            canonicalVaultJson(Map<String, Object?>.from(fixture as Map)),
          ),
        );
        expect(value, isNot(contains('private account')));
      }
    },
  );

  test(
    'OAuth-only form is credential-only and reverts validation after removal',
    () {
      final fields = [method(upper)];
      expect(
        EntryFormUtils.canSubmit(
          type: EntryType.credential,
          label: 'Service',
          fields: fields,
        ),
        isTrue,
      );
      expect(
        EntryFormUtils.canSubmit(type: EntryType.credential, label: 'Service'),
        isFalse,
      );
      expect(
        EntryFormUtils.canSubmit(
          type: EntryType.key,
          label: 'Service',
          fields: fields,
        ),
        isFalse,
      );
    },
  );

  test(
    'hidden v2 suppresses singleton and visible legacy joins mixed collection',
    () {
      MemberSecret secret(
        List<VaultCustomField> fields,
        Map<String, AgentFieldAccess> access,
      ) => MemberSecret(
        entryType: VaultEntryType.credential,
        memberLabel: 'Synthetic',
        agentLabel: 'Synthetic',
        description: null,
        icon: null,
        color: null,
        discoverable: true,
        content: CredentialSecretContent(
          username: '',
          password: '',
          url: null,
          urlDomain: null,
          totp: null,
          notes: null,
          customFields: fields,
        ),
        agentFieldAccess: {
          'memberLabel': AgentFieldAccess.never,
          'agentLabel': AgentFieldAccess.discovery,
          'description': AgentFieldAccess.never,
          'icon': AgentFieldAccess.never,
          'color': AgentFieldAccess.never,
          'entryType': AgentFieldAccess.discovery,
          'credential.username': AgentFieldAccess.never,
          'credential.password': AgentFieldAccess.never,
          'credential.url': AgentFieldAccess.never,
          'credential.urlDomain': AgentFieldAccess.never,
          'credential.totp': AgentFieldAccess.never,
          'notes': AgentFieldAccess.never,
          ...access,
        },
      );
      final legacy = VaultCustomField(
        id: upper,
        label: 'Legacy',
        kind: SignInMethodField.type,
        value: method(upper).value,
      );
      final hidden = VaultCustomField(
        id: second,
        label: 'New',
        kind: SignInMethodField.collectionType,
        value: method(second).value,
      );
      final projection = VaultPlaintextProjector.agentDiscovery(
        secret(
          [legacy, hidden],
          {
            'custom:$upper': AgentFieldAccess.discovery,
            'custom:$second': AgentFieldAccess.never,
          },
        ),
      );
      final fields = projection?['fields'] as List;
      expect(fields.where((dynamic field) => field['id'] == 'signIn'), isEmpty);
      final collection =
          jsonDecode(
                (fields.singleWhere(
                          (dynamic field) => field['id'] == 'signInMethods',
                        )
                        as Map)['value']
                    as String,
              )
              as Map;
      expect((collection['methods'] as List).single['id'], 'custom:$upper');
      final hiddenOnly = VaultPlaintextProjector.agentDiscovery(
        secret([hidden], {'custom:$second': AgentFieldAccess.never}),
      );
      expect(hiddenOnly.toString(), isNot(contains('signIn')));
    },
  );
}
