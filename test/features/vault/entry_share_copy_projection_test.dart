import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/models/entry_v2_contracts.dart';
import 'package:mobile_palladin/features/vault/data/services/canonical_entry_detail_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_copy_projection_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_selection_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_totp_codec.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_v2_crypto_service.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share_copy.dart';
import 'package:mobile_palladin/features/vault/domain/entities/vault_plaintext.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

EntryShareSnapshot _snapshot(
  String type,
  Map<String, String> values, {
  String title = '  Received e\u0301 🔐  ',
  Map<String, String> kinds = const {},
}) => EntryShareSnapshot.fromJson({
  'schema': EntryShareSnapshot.schema,
  'title': title,
  'entryType': type,
  'fields': [
    for (final item in values.entries)
      {
        'id': item.key,
        'label': item.key.startsWith('custom:') ? '  Custom e\u0301  ' : '',
        'type':
            kinds[item.key] ??
            switch (item.key) {
              'key.value' ||
              'credential.password' ||
              'creditCard.cardNumber' => 'concealed',
              'notes' ||
              'description' ||
              'script.source' ||
              'creditCard.billingAddress' => 'multiline',
              'credential.totp' => 'totp',
              _ => 'text',
            },
        'value': item.value,
      },
  ],
});

Matcher _error(EntryShareCopyInputError kind) => throwsA(
  isA<EntryShareCopyInputException>().having((e) => e.kind, 'kind', kind),
);

void _private(MemberSecret secret) {
  expect(secret.discoverable, isFalse);
  expect(secret.agentLabel, isNull);
  expect(secret.icon, isNull);
  expect(secret.color, isNull);
  expect(secret.agentFieldAccess.values, everyElement(AgentFieldAccess.never));
  expect(VaultPlaintextProjector.agentDiscovery(secret), isNull);
  expect(VaultPlaintextProjector.memberIndex(secret).customIndex, isEmpty);
}

void main() {
  const service = EntryShareCopyProjectionService();
  const codec = EntryShareTotpCodec();
  const otp =
      'otpauth://totp/Account?secret=JBSWY3DPEHPK3PXP'
      '&algorithm=SHA256&digits=8&period=45';

  test('credential copies exact selected values with a private policy', () {
    final source = _snapshot('credential', {
      'credential.username': '  member\u0000e\u0301  ',
      'credential.password': '  secret\u0000e\u0301  ',
      'credential.url': 'https://Example.test/path?param=a%20b',
      'description': '  description  ',
      'notes': '  notes\n  ',
    });
    final original = jsonEncode(source.toJson());
    final secret = service.project(snapshot: source);
    final content = secret.content as CredentialSecretContent;
    expect(secret.memberLabel, source.title);
    expect(secret.description, '  description  ');
    expect(content.username, '  member\u0000e\u0301  ');
    expect(content.password, '  secret\u0000e\u0301  ');
    expect(content.url, 'https://Example.test/path?param=a%20b');
    expect(content.urlDomain, 'example.test');
    expect(content.notes, '  notes\n  ');
    expect(content.totp, isNull);
    expect(jsonEncode(source.toJson()), original);
    _private(secret);
  });

  test('omitted required data must be explicitly supplied, not guessed', () {
    final source = _snapshot('credential', {'credential.password': 'secret'});
    expect(service.missingFields(source), ['credential.username']);
    expect(
      () => service.project(snapshot: source),
      _error(EntryShareCopyInputError.missingFields),
    );
    final secret = service.project(
      snapshot: source,
      completedFields: {'credential.username': '  explicit user  '},
    );
    expect(
      (secret.content as CredentialSecretContent).username,
      '  explicit user  ',
    );
    _private(secret);
  });

  test('an intentionally empty selected value is not an omitted field', () {
    final source = _snapshot('credential', {
      'credential.username': '',
      'credential.password': 'secret',
    });
    expect(service.missingFields(source), isEmpty);
    expect(
      (service.project(snapshot: source).content as CredentialSecretContent)
          .username,
      '',
    );
  });

  test('completion cannot replace received fields or inject extra policy', () {
    final source = _snapshot('key', {'key.value': 'original'});
    for (final id in [
      'key.value',
      'agentLabel',
      'script.refs',
      'custom:extra',
    ]) {
      expect(
        () => service.project(snapshot: source, completedFields: {id: 'x'}),
        _error(EntryShareCopyInputError.unexpectedCompletion),
      );
    }
  });

  test('oversize title requires an explicit new title, never truncation', () {
    final source = _snapshot('key', {'key.value': 'secret'}, title: 'x' * 201);
    expect(
      () => service.project(snapshot: source),
      _error(EntryShareCopyInputError.invalidTitle),
    );
    expect(
      service.project(snapshot: source, title: 'New title').memberLabel,
      'New title',
    );
    expect(source.title.length, 201);
    expect(
      () => service.project(snapshot: source, title: '  '),
      _error(EntryShareCopyInputError.invalidTitle),
    );
  });

  test('key URL and optional empty notes remain exact', () {
    final secret = service.project(
      snapshot: _snapshot('key', {
        'key.value': '  secret  ',
        'key.url': 'urn:exact:source',
        'notes': '',
      }),
    );
    final content = secret.content as KeySecretContent;
    expect(content.value, '  secret  ');
    expect(content.url, 'urn:exact:source');
    expect(content.notes, '');
    _private(secret);
  });

  test('a copy cannot create an index that its own reader rejects', () {
    for (final values in [
      {'credential.username': 'x' * 8193, 'credential.password': 'pass'},
      {
        'credential.username': 'user',
        'credential.password': 'pass',
        'description': 'x' * 2049,
      },
    ]) {
      final source = _snapshot('credential', values);
      final before = jsonEncode(source.toJson());
      expect(
        () => service.project(snapshot: source),
        _error(EntryShareCopyInputError.unsupportedContent),
      );
      expect(jsonEncode(source.toJson()), before);
    }
  });

  test('all partially shared types enumerate only missing required fields', () {
    expect(service.missingFields(_snapshot('key', {'notes': 'note'})), [
      'key.value',
    ]);
    expect(service.missingFields(_snapshot('credential', {'notes': 'note'})), [
      'credential.username',
      'credential.password',
    ]);
    expect(service.missingFields(_snapshot('script', {'notes': 'note'})), [
      'script.source',
      'script.interpreter',
      'script.execution.description',
    ]);
    expect(service.missingFields(_snapshot('creditCard', {'notes': 'note'})), [
      'creditCard.cardholderName',
      'creditCard.cardNumber',
      'creditCard.expiryMonth',
      'creditCard.expiryYear',
    ]);
  });

  test('non-HTTP URL remains stored but does not become an autofill host', () {
    final secret = service.project(
      snapshot: _snapshot('credential', {
        'credential.username': 'user',
        'credential.password': 'pass',
        'credential.url': 'androidapp://example.test',
      }),
    );
    final content = secret.content as CredentialSecretContent;
    expect(content.url, 'androidapp://example.test');
    expect(content.urlDomain, isNull);
  });

  test('card copies private exact values without synthesizing CVV or PIN', () {
    final source = _snapshot('creditCard', {
      'creditCard.cardholderName': '  Card holder  ',
      'creditCard.cardNumber': 'synthetic-card-value',
      'creditCard.expiryMonth': '09',
      'creditCard.expiryYear': '2030',
      'creditCard.billingAddress': '  Billing\nAddress  ',
    });
    final secret = service.project(snapshot: source);
    final content = secret.content as CreditCardSecretContent;
    expect(content.cardholderName, '  Card holder  ');
    expect(content.cardNumber, 'synthetic-card-value');
    expect(content.expiryMonth, '09');
    expect(content.expiryYear, '2030');
    expect(content.billingAddress, '  Billing\nAddress  ');
    expect(content.toJson().containsKey('cvv'), isFalse);
    expect(content.toJson().containsKey('pin'), isFalse);
    _private(secret);
  });

  test('script needs local execution description and inherits no refs', () {
    final source = _snapshot('script', {
      'script.source': '  echo "\$EXTERNAL"\n',
      'script.interpreter': 'sh',
    });
    expect(service.missingFields(source), ['script.execution.description']);
    expect(
      () => service.project(snapshot: source),
      _error(EntryShareCopyInputError.missingFields),
    );
    final secret = service.project(
      snapshot: source,
      completedFields: {'script.execution.description': 'My local script'},
    );
    final content = secret.content as ScriptSecretContent;
    expect(content.source, '  echo "\$EXTERNAL"\n');
    expect(content.interpreter, 'sh');
    expect(content.refs, isEmpty);
    expect(content.execution, {
      'contractVersion': 1,
      'description': 'My local script',
      'parameters': [],
      'returnResultToAgent': false,
    });
    _private(secret);
  });

  test('unsupported script interpreter never silently becomes bash', () {
    final source = _snapshot('script', {
      'script.source': 'source',
      'script.interpreter': 'unsupported',
    });
    expect(
      () => service.project(
        snapshot: source,
        completedFields: {'script.execution.description': 'Local'},
      ),
      _error(EntryShareCopyInputError.invalidScript),
    );
  });

  test('custom identities are new, labels and secret values remain exact', () {
    final source = _snapshot(
      'key',
      {'key.value': 'secret', 'custom:foreign-id': '  e\u0301\u0000  '},
      kinds: {'custom:foreign-id': 'concealed'},
    );
    final first = service.project(snapshot: source);
    final second = service.project(snapshot: source);
    final field = first.content.customFields.single;
    expect(
      field.id,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(field.id, isNot(second.content.customFields.single.id));
    expect(field.label, '  Custom e\u0301  ');
    expect(field.value, '  e\u0301\u0000  ');
    expect(field.includeInMemberIndex, isFalse);
    expect(first.agentFieldAccess.containsKey('custom:foreign-id'), isFalse);
    _private(first);
  });

  test(
    'native and custom TOTP retain full config in usable canonical maps',
    () {
      final secret = service.project(
        snapshot: _snapshot(
          'credential',
          {
            'credential.username': 'user',
            'credential.password': 'pass',
            'credential.totp': otp,
            'custom:otp': otp,
          },
          kinds: {'custom:otp': 'totp'},
        ),
      );
      final content = secret.content as CredentialSecretContent;
      expect(content.totp, {
        'secret': 'JBSWY3DPEHPK3PXP',
        'algorithm': 'SHA256',
        'digits': 8,
        'period': 45,
        'account': 'Account',
      });
      expect(content.customFields.single.value, content.totp);
      expect(() => content.totp!['digits'] = 6, throwsUnsupportedError);
      _private(secret);
    },
  );

  test(
    'an invalid custom TOTP never disappears from an otherwise valid copy',
    () {
      final source = _snapshot(
        'key',
        {'key.value': 'secret', 'custom:totp': '$otp&algorithm=MD5'},
        kinds: {'custom:totp': 'totp'},
      );
      expect(
        () => service.project(snapshot: source),
        _error(EntryShareCopyInputError.invalidTotp),
      );
      expect(source.fields.length, 2);
    },
  );

  test(
    'sender to copy roundtrip preserves Unicode, percent and colon labels',
    () {
      for (final issuer in ['', '  Issuer/&? 🦉', 'Issuer:department']) {
        final config = <String, Object?>{
          'secret': 'JBSWY3DPEHPK3PXP',
          'algorithm': 'SHA512',
          'digits': 8,
          'period': 120,
          'issuer': issuer,
          'account': '  user:%25%3A+e\u0301@example.test  ',
        };
        final selection = const EntryShareSelectionService().project(
          CanonicalEntrySnapshot(
            entry: {},
            secret: {'entryType': 1, 'memberLabel': 'Source'},
            payload: {'username': 'user', 'password': 'pass', 'totp': config},
          ),
        );
        final secret = service.project(
          snapshot: selection.select([
            'credential.username',
            'credential.password',
            'credential.totp',
          ]),
        );
        expect((secret.content as CredentialSecretContent).totp, config);
      }
    },
  );

  test(
    'bare seed and omitted standard parameters retain their defined defaults',
    () {
      expect(codec.decode('JBSWY3DPEHPK3PXP'), {
        'secret': 'JBSWY3DPEHPK3PXP',
        'algorithm': 'SHA1',
        'digits': 6,
        'period': 30,
      });
      expect(
        codec.decode('otpauth://totp/Issuer:Account?secret=JBSWY3DPEHPK3PXP'),
        {
          'secret': 'JBSWY3DPEHPK3PXP',
          'algorithm': 'SHA1',
          'digits': 6,
          'period': 30,
          'issuer': 'Issuer',
          'account': 'Account',
        },
      );
    },
  );

  final invalidTotp = [
    otp.replaceFirst('SHA256', 'MD5'),
    otp.replaceFirst('digits=8', 'digits=7'),
    otp.replaceFirst('period=45', 'period=0'),
    otp.replaceFirst('period=45', 'period=121'),
    otp.replaceFirst('period=45', 'period=045'),
    '$otp&algorithm=SHA1',
    '$otp&secret=AAAA',
    '$otp&counter=1',
    '$otp#fragment',
    otp.replaceFirst('/Account', '/A/B'),
    otp.replaceFirst('totp', 'hotp'),
    'otpauth://totp/Other:Account?secret=JBSWY3DPEHPK3PXP&issuer=Issuer',
    'secret-value-that-must-not-appear-in-errors',
    'JBSWY3DPEHPK3PXP ',
  ];
  for (var index = 0; index < invalidTotp.length; index++) {
    test(
      'unsupported TOTP fails without correction or secret diagnostics $index',
      () {
        try {
          codec.decode(invalidTotp[index]);
          fail('Expected a typed rejection');
        } on EntryShareCopyInputException catch (error) {
          expect(error.kind, EntryShareCopyInputError.invalidTotp);
          expect(error.toString(), 'EntryShareCopyInputException(invalidTotp)');
        }
      },
    );
  }

  test(
    'private copy encrypts with fresh Entry keys and no Discovery projection',
    () async {
      final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
      final sodium = configured != null || Platform.isLinux
          ? await sodium_ffi.SodiumSumoInit.init(
              () => DynamicLibrary.open(configured ?? 'libsodium.so'),
            )
          : await SodiumSumoInit.init();
      final crypto = EntryV2CryptoService(sodiumLoader: () async => sodium);
      final vaultKey = sodium.randombytes.buf(32);
      final discoveryKey = sodium.randombytes.buf(32);
      final secret = service.project(
        snapshot: _snapshot('key', {
          'key.value': '  synthetic received copy e\u0301  ',
        }),
      );
      Uint8List? firstKey, secondKey;
      try {
        Future<EntryEnvelopeBundleModel> seal(String id) => crypto.seal(
          organizationId: '11111111-1111-4111-8111-111111111111',
          vaultId: '22222222-2222-4222-8222-222222222222',
          entryId: id,
          revision: 1,
          vaultKeyVersion: 1,
          vdkVersion: 1,
          memberKeyGeneration: 1,
          operation: 1,
          secret: secret,
          vaultKey: vaultKey,
          vaultDiscoveryKey: discoveryKey,
        );
        final first = await seal('33333333-3333-4333-8333-333333333333');
        final second = await seal('44444444-4444-4444-8444-444444444444');
        expect(first.agentDiscovery, isNull);
        expect(second.agentDiscovery, isNull);
        firstKey = await crypto.openEntryDek(
          entryKey: Map<String, dynamic>.from(first.entryKey),
          vaultKey: vaultKey,
        );
        secondKey = await crypto.openEntryDek(
          entryKey: Map<String, dynamic>.from(second.entryKey),
          vaultKey: vaultKey,
        );
        expect(firstKey, isNot(secondKey));
        expect(firstKey, isNot(vaultKey));
        final opened = await crypto.openMemberSecret(
          entryKey: Map<String, dynamic>.from(first.entryKey),
          memberSecret: Map<String, dynamic>.from(first.memberSecret),
          vaultKey: vaultKey,
        );
        expect(opened, secret.toJson());
      } finally {
        firstKey?.fillRange(0, firstKey.length, 0);
        secondKey?.fillRange(0, secondKey.length, 0);
        vaultKey.fillRange(0, vaultKey.length, 0);
        discoveryKey.fillRange(0, discoveryKey.length, 0);
      }
    },
  );
}
