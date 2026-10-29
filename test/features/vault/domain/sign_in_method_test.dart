import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/domain/entities/custom_field.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/domain/entities/sign_in_method.dart';

CustomField _binding(Object? value, {String id = 'a'}) => CustomField(
  id: id,
  label: 'Sign-in method',
  type: CustomFieldType.unknown,
  rawType: SignInMethodField.type,
  value: value,
);

void main() {
  SignInMethodState read(
    List<CustomField> fields, {
    EntryType type = EntryType.credential,
  }) => SignInMethodField.read(entryType: type, fields: fields);

  group('SignInMethodField.read', () {
    test('recognizes every closed provider with and without an account', () {
      for (final provider in SignInProvider.values) {
        final withAccount = read([
          _binding({'provider': provider.wireName, 'account': 'a@b.test'}),
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
          _binding({'provider': provider.wireName, 'account': null}),
        ]);
        expect(
          (withoutAccount as SignInMethodRecognized).binding.account,
          isNull,
        );
      }
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
          read([
            _binding({'provider': 'google', 'account': null}),
          ], type: type),
          isA<SignInMethodAbsent>(),
        );
      }
    });

    test('more than one binding field is ambiguous', () {
      expect(
        read([
          _binding({'provider': 'google', 'account': 'a@b.test'}),
          _binding({'provider': 'github', 'account': null}, id: 'b'),
        ]),
        isA<SignInMethodAmbiguous>().having((state) => state.count, 'count', 2),
      );
    });

    for (final (name, value) in <(String, Object?)>[
      ('unknown provider', {'provider': 'twitter', 'account': null}),
      ('provider case', {'provider': 'Google', 'account': null}),
      ('non-string provider', {'provider': 1, 'account': null}),
      ('extra key', {'provider': 'google', 'account': null, 'token': 'x'}),
      ('missing account key', {'provider': 'google'}),
      ('missing provider key', {'account': 'a@b.test'}),
      ('non-map value', 'google'),
      ('null value', null),
      ('non-string account', {'provider': 'google', 'account': 42}),
      ('empty account', {'provider': 'google', 'account': ''}),
      ('untrimmed account', {'provider': 'google', 'account': ' a@b.test'}),
      ('too long account', {'provider': 'google', 'account': 'a' * 257}),
      ('non-NFC account', {'provider': 'google', 'account': 'café'}),
    ]) {
      test('rejects $name as unrecognized', () {
        expect(read([_binding(value)]), isA<SignInMethodUnrecognized>());
      });
    }

    test('accepts an account of exactly 256 characters', () {
      expect(
        read([
          _binding({'provider': 'apple', 'account': 'a' * 256}),
        ]),
        isA<SignInMethodRecognized>(),
      );
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
          _binding({'provider': 'google', 'account': null}),
          other,
          _binding({'provider': 'twitter'}, id: 'b'),
          future,
        ],
        binding: const SignInMethodBinding(
          provider: SignInProvider.microsoft,
          account: 'qa@x.test',
        ),
        label: 'Sign-in method',
        newId: 'n',
      );
      expect(next.map((field) => field.id), ['t', 'f', 'n']);
      expect(next.last.toJson(), {
        'id': 'n',
        'label': 'Sign-in method',
        'type': SignInMethodField.type,
        'value': {'provider': 'microsoft', 'account': 'qa@x.test'},
      });
      expect(identical(next[1], future), isTrue);
    });

    test('a null binding only removes', () {
      final next = SignInMethodField.replace(
        [
          other,
          _binding({'provider': 'google', 'account': null}),
        ],
        binding: null,
        label: 'Sign-in method',
        newId: 'n',
      );
      expect(next, [other]);
    });
  });
}
