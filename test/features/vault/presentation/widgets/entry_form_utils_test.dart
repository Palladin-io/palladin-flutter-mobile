import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_palladin/features/vault/domain/entities/entry_entity.dart';
import 'package:mobile_palladin/features/vault/presentation/widgets/entry_form_utils.dart';

void main() {
  test('Script requires a description and writes execution metadata', () {
    expect(
      EntryFormUtils.canSubmit(
        type: EntryType.script,
        label: 'Users',
        script: 'echo ok',
      ),
      isFalse,
    );
    final parameter = ScriptParameterDefinition(
      name: 'team_id',
      description: 'Team identifier',
      type: ScriptParameterType.string,
      required: true,
    );
    expect(
      EntryFormUtils.canSubmit(
        type: EntryType.script,
        label: 'Users',
        description: 'Lists users',
        script: 'echo ok',
        scriptParameters: [parameter],
      ),
      isTrue,
    );
    final payload = EntryFormUtils.buildPayload(
      type: EntryType.script,
      script: 'echo ok',
      scriptDescription: 'Lists users',
      scriptParameters: [parameter],
    );
    expect(payload['execution'], {
      'contractVersion': 1,
      'description': 'Lists users',
      'parameters': [parameter.toJson()],
      'returnResultToAgent': true,
    });
  });

  test('Script reference environments reject process-control variables', () {
    expect(isAllowedScriptReferenceEnvironment('DB_PASSWORD'), isTrue);
    expect(isAllowedScriptReferenceEnvironment('NODE_OPTIONS'), isFalse);
    expect(isAllowedScriptReferenceEnvironment('palladin_token'), isFalse);
    expect(isAllowedScriptReferenceEnvironment('LD_LIBRARY_PATH'), isFalse);
  });

  test('legacy Script result delivery defaults to false', () {
    final metadata = ScriptExecutionMetadata.fromJson({
      'contractVersion': 1,
      'description': 'Legacy script',
      'parameters': const [],
    });
    expect(metadata.returnResultToAgent, isFalse);
  });

  test('Script metadata rejects a malformed parameter array', () {
    expect(
      () => ScriptExecutionMetadata.fromJson({
        'contractVersion': 1,
        'description': 'Lists users',
        'parameters': [
          {
            'name': 'team_id',
            'description': 'Team identifier',
            'type': 'string',
            'required': true,
          },
          'malformed',
        ],
        'returnResultToAgent': true,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('Script validates the actual description bounds', () {
    expect(
      EntryFormUtils.canSubmit(
        type: EntryType.script,
        label: 'Users',
        description: 'x' * 4097,
        script: 'echo ok',
      ),
      isFalse,
    );
  });

  test('credit card payload is normalized and validated', () {
    expect(
      EntryFormUtils.canSubmit(
        type: EntryType.creditCard,
        label: 'Travel card',
        cardholderName: 'Ada',
        cardNumber: '4242 4242 4242 4242',
        expiryMonth: '12',
        expiryYear: '2030',
      ),
      isTrue,
    );
    final payload = EntryFormUtils.buildPayload(
      type: EntryType.creditCard,
      cardholderName: ' Ada ',
      cardNumber: '4242 4242 4242 4242',
      expiryMonth: '12',
      expiryYear: '2030',
    );
    expect(payload['cardNumber'], '4242424242424242');
    expect(payload.containsKey('securityCode'), isFalse);
    expect(payload.containsKey('pin'), isFalse);
    expect(payload['type'], 'CREDIT_CARD');
  });
  test(
    'Key payload never accepts a URL outside the frozen canonical schema',
    () {
      final payload = EntryFormUtils.buildPayload(
        type: EntryType.key,
        value: 'secret',
        url: 'https://example.com',
      );
      expect(payload.containsKey('url'), isFalse);
    },
  );
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
      expect(EntryFormUtils.extractDomain('example.com/path'), 'example.com');
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
    test('key payload uses value and notes but omits unsupported URL', () {
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
      expect(json.containsKey('url'), isFalse);
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
