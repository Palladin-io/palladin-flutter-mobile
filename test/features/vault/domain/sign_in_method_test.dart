import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/domain/entities/agent_visibility_policy.dart';
import 'package:mobile_palladin/features/vault/domain/entities/custom_field.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/sign_in_method.dart';

const _vaultId = '22222222-2222-4222-8222-222222222222';
const _entryId = '33333333-3333-4333-8333-333333333333';

CustomField _binding(Object? value, {String id = 'a'}) => CustomField(
  id: id,
  label: 'Sign-in method',
  type: CustomFieldType.unknown,
  rawType: SignInMethodField.type,
  value: value,
);

Map<String, Object?> _value({
  Object? provider = 'google',
  Object? account,
  Object? entry,
}) => {'provider': provider, 'account': account, 'entry': entry};

void main() {
  SignInMethodState read(
    List<CustomField> fields, {
    EntryType type = EntryType.credential,
  }) => SignInMethodField.read(entryType: type, fields: fields);

  group('SignInMethodField.read', () {
    test('recognizes every closed provider with and without an account', () {
      for (final provider in SignInProvider.values) {
        final withAccount = read([
          _binding(_value(provider: provider.wireName, account: 'a@b.test')),
        ]);
        expect(
          withAccount,
          isA<SignInMethodRecognized>()
              .having((state) => state.fieldId, 'fieldId', 'a')
              .having(
                (state) => state.binding,
                'binding',
                SignInMethodBinding(provider: provider, account: 'a@b.test'),
              ),
        );
        final withoutAccount = read([
          _binding(_value(provider: provider.wireName)),
        ]);
        expect(
          (withoutAccount as SignInMethodRecognized).binding.account,
          isNull,
        );
      }
    });

    test('recognizes a linked provider Credential', () {
      final state = read([
        _binding(
          _value(
            account: 'a@b.test',
            entry: {'vaultId': _vaultId, 'entryId': _entryId},
          ),
        ),
      ]);
      expect(
        (state as SignInMethodRecognized).binding.entry,
        const SignInEntryReference(vaultId: _vaultId, entryId: _entryId),
      );
    });

    test('absent without a binding field', () {
      expect(
        read([CustomField.text(id: 't', label: 'Team', value: 'qa')]),
        isA<SignInMethodAbsent>(),
      );
    });

    test('ignores a binding on a non-Credential Entry', () {
      for (final type in [
        EntryType.key,
        EntryType.script,
        EntryType.creditCard,
      ]) {
        expect(
          read([_binding(_value())], type: type),
          isA<SignInMethodAbsent>(),
        );
      }
    });

    test('more than one binding field is ambiguous', () {
      expect(
        read([
          _binding(_value(account: 'a@b.test')),
          _binding(_value(provider: 'github'), id: 'b'),
        ]),
        isA<SignInMethodAmbiguous>().having((state) => state.count, 'count', 2),
      );
    });

    for (final (name, value) in <(String, Object?)>[
      ('retired two-key value', {'provider': 'google', 'account': null}),
      ('unknown provider', _value(provider: 'twitter')),
      ('provider case', _value(provider: 'Google')),
      ('non-string provider', _value(provider: 1)),
      ('extra key', {..._value(), 'token': 'x'}),
      ('missing entry key', {'provider': 'google', 'account': 'a', 'x': null}),
      ('non-map value', 'google'),
      ('null value', null),
      ('non-string account', _value(account: 42)),
      ('empty account', _value(account: '')),
      ('untrimmed account', _value(account: ' a@b.test')),
      ('too long account', _value(account: 'a' * 257)),
      ('non-NFC account', _value(account: 'café')),
      ('non-map entry', _value(entry: '$_vaultId/$_entryId')),
      (
        'uppercase entry id',
        _value(
          entry: {
            'vaultId': _vaultId,
            'entryId': 'ABCDEF12-3333-4333-8333-333333333333',
          },
        ),
      ),
      (
        'non-uuid vault id',
        _value(entry: {'vaultId': 'v', 'entryId': _entryId}),
      ),
      (
        'entry extra key',
        _value(entry: {'vaultId': _vaultId, 'entryId': _entryId, 'label': 'x'}),
      ),
      ('entry missing id', _value(entry: {'vaultId': _vaultId})),
    ]) {
      test('rejects $name as unrecognized', () {
        expect(read([_binding(value)]), isA<SignInMethodUnrecognized>());
      });
    }

    test('accepts an account of exactly 256 characters', () {
      expect(
        read([_binding(_value(provider: 'apple', account: 'a' * 256))]),
        isA<SignInMethodRecognized>(),
      );
    });
  });

  group('SignInMethodField policy and Discovery', () {
    test('discovery is allowed only on a Credential with a valid value', () {
      expect(
        SignInMethodField.allowsDiscovery(credential: true, value: _value()),
        isTrue,
      );
      expect(
        SignInMethodField.allowsDiscovery(credential: false, value: _value()),
        isFalse,
      );
      expect(
        SignInMethodField.allowsDiscovery(
          credential: true,
          value: {'provider': 'google', 'account': null},
        ),
        isFalse,
      );
    });

    test('form policy matches the canonical sign-in access rule', () {
      Set<AgentFieldAccess> allowed(EntryType type, Object? value) =>
          AgentVisibilityPolicy.allowedFor(type, 'custom:a', {
            'fields': [
              {'id': 'a', 'type': SignInMethodField.type, 'value': value},
            ],
          });
      expect(allowed(EntryType.credential, _value()), {
        AgentFieldAccess.never,
        AgentFieldAccess.discovery,
      });
      expect(
        allowed(EntryType.credential, {'provider': 'google', 'account': null}),
        {AgentFieldAccess.never},
      );
      expect(allowed(EntryType.key, _value()), {AgentFieldAccess.never});
    });

    test('Discovery value is canonical and never carries the account', () {
      expect(
        SignInMethodField.discoveryValue(
          const SignInMethodBinding(
            provider: SignInProvider.google,
            account: 'alice@example.com',
            entry: SignInEntryReference(vaultId: _vaultId, entryId: _entryId),
          ),
        ),
        '{"entry":{"entryId":"$_entryId","vaultId":"$_vaultId"},'
        '"provider":"google","schema":"palladin.signin.v1"}',
      );
      expect(
        SignInMethodField.discoveryValue(
          const SignInMethodBinding(
            provider: SignInProvider.microsoft,
            account: 'x',
          ),
        ),
        '{"entry":null,"provider":"microsoft","schema":"palladin.signin.v1"}',
      );
    });

    test('provider account domains match registrable domains only', () {
      expect(SignInProvider.google.ownsHost('accounts.google.com'), isTrue);
      expect(SignInProvider.google.ownsHost('google.com'), isTrue);
      expect(SignInProvider.google.ownsHost('notgoogle.com'), isFalse);
      expect(SignInProvider.google.ownsHost('google.com.evil.test'), isFalse);
      expect(
        SignInProvider.microsoft.ownsHost('login.microsoftonline.com'),
        isTrue,
      );
      expect(SignInProvider.microsoft.ownsHost('login.live.com'), isTrue);
      expect(SignInProvider.github.ownsHost('GitHub.com'), isTrue);
      expect(SignInProvider.facebook.ownsHost('fb.com'), isFalse);
    });
  });

  group('SignInMethodField.normalizeAccount', () {
    test('trims, NFC-normalizes and maps blank input to null', () {
      expect(SignInMethodField.normalizeAccount('  '), isNull);
      expect(
        SignInMethodField.normalizeAccount('  café@x.test '),
        'café@x.test',
      );
    });

    test('rejects more than 256 characters', () {
      expect(
        () => SignInMethodField.normalizeAccount('a' * 257),
        throwsA(
          isA<SignInAccountException>().having(
            (error) => error.kind,
            'kind',
            SignInAccountError.tooLong,
          ),
        ),
      );
    });
  });

  group('SignInMethodField.replace', () {
    final other = CustomField.text(id: 't', label: 'Team', value: 'qa');
    final future = CustomField.fromJson({
      'id': 'f',
      'label': 'Future',
      'type': 'palladin.future.v9',
      'value': {'x': 1},
    });

    test('removes every binding and writes exactly one new field', () {
      final next = SignInMethodField.replace(
        [
          _binding(_value()),
          other,
          _binding({'provider': 'twitter'}, id: 'b'),
          future,
        ],
        binding: const SignInMethodBinding(
          provider: SignInProvider.microsoft,
          account: 'qa@x.test',
          entry: SignInEntryReference(vaultId: _vaultId, entryId: _entryId),
        ),
        label: 'Sign-in method',
        newId: 'n',
      );
      expect(next.map((field) => field.id), ['t', 'f', 'n']);
      expect(next.last.toJson(), {
        'id': 'n',
        'label': 'Sign-in method',
        'type': SignInMethodField.type,
        'value': {
          'provider': 'microsoft',
          'account': 'qa@x.test',
          'entry': {'vaultId': _vaultId, 'entryId': _entryId},
        },
      });
      expect(identical(next[1], future), isTrue);
    });

    test('a null binding only removes', () {
      final next = SignInMethodField.replace(
        [other, _binding(_value())],
        binding: null,
        label: 'Sign-in method',
        newId: 'n',
      );
      expect(next, [other]);
    });
  });
}
