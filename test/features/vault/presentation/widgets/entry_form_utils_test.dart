import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_form_utils.dart';

void main() {
  group('EntryFormUtils.isValidUrl', () {
    test('accepts empty input (URL is optional)', () {
      expect(EntryFormUtils.isValidUrl(''), isTrue);
      expect(EntryFormUtils.isValidUrl('   '), isTrue);
    });

    test('accepts domain-like hosts with or without scheme', () {
      expect(EntryFormUtils.isValidUrl('example.com'), isTrue);
      expect(EntryFormUtils.isValidUrl('https://example.com'), isTrue);
      expect(EntryFormUtils.isValidUrl('https://stripe.com/path?x=1'), isTrue);
    });

    test('accepts localhost and bare IPs', () {
      expect(EntryFormUtils.isValidUrl('localhost'), isTrue);
      expect(EntryFormUtils.isValidUrl('http://localhost:3000'), isTrue);
      expect(EntryFormUtils.isValidUrl('127.0.0.1'), isTrue);
    });

    test('rejects garbage and bare words without a dot', () {
      expect(EntryFormUtils.isValidUrl('not a url'), isFalse);
      expect(EntryFormUtils.isValidUrl('justaword'), isFalse);
    });
  });

  group('EntryFormUtils.extractDomain', () {
    test('returns null on blank input', () {
      expect(EntryFormUtils.extractDomain(''), isNull);
      expect(EntryFormUtils.extractDomain('   '), isNull);
    });

    test('extracts host from a fully-qualified URL', () {
      expect(
        EntryFormUtils.extractDomain('https://stripe.com/path'),
        'stripe.com',
      );
    });

    test('falls back to first path segment when no scheme', () {
      expect(
        EntryFormUtils.extractDomain('example.com/path'),
        'example.com',
      );
    });
  });

  group('EntryFormUtils.canSubmit', () {
    test('requires a non-empty label regardless of type', () {
      expect(
        EntryFormUtils.canSubmit(
          type: EntryType.credential,
          label: '',
          value: '',
          username: 'jane',
          password: 'pw',
        ),
        isFalse,
      );
    });

    test('key entries need a non-empty value', () {
      expect(
        EntryFormUtils.canSubmit(
          type: EntryType.key,
          label: 'Stripe',
          value: 'sk_live_…',
          username: '',
          password: '',
        ),
        isTrue,
      );
      expect(
        EntryFormUtils.canSubmit(
          type: EntryType.key,
          label: 'Stripe',
          value: '   ',
          username: '',
          password: '',
        ),
        isFalse,
      );
    });

    test('credential entries need both username and password', () {
      expect(
        EntryFormUtils.canSubmit(
          type: EntryType.credential,
          label: 'GitHub',
          value: '',
          username: 'jane',
          password: 'pw',
        ),
        isTrue,
      );
      expect(
        EntryFormUtils.canSubmit(
          type: EntryType.credential,
          label: 'GitHub',
          value: '',
          username: 'jane',
          password: '',
        ),
        isFalse,
      );
    });
  });

  group('EntryFormUtils.buildPayload', () {
    test('key payload uses value + trimmed url/notes', () {
      final json = EntryFormUtils.buildPayload(
        type: EntryType.key,
        value: '  sk_live_x  ',
        username: '',
        password: '',
        url: '  https://stripe.com  ',
        notes: '  remember to rotate  ',
      );
      expect(json['type'], 'KEY');
      expect(json['value'], 'sk_live_x');
      expect(json['url'], 'https://stripe.com');
      expect(json['notes'], 'remember to rotate');
    });

    test('credential payload uses username + password and omits blanks', () {
      final json = EntryFormUtils.buildPayload(
        type: EntryType.credential,
        value: '',
        username: ' jane ',
        password: ' pw ',
        url: '',
        notes: '',
      );
      expect(json['type'], 'CREDENTIAL');
      expect(json['username'], 'jane');
      expect(json['password'], 'pw');
      expect(json.containsKey('url'), isFalse);
      expect(json.containsKey('notes'), isFalse);
    });
  });
}
