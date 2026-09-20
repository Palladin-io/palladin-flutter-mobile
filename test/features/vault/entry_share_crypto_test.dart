import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_crypto_service.dart';
import 'package:mobile_palladin/features/vault/data/services/entry_sharing/entry_share_secrets.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/domain/entities/entry_share.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;
import 'package:sodium_libs/sodium_libs_sumo.dart';

final _fixture =
    jsonDecode(
          File('test/fixtures/crypto/entry-share-v1.json').readAsStringSync(),
        )
        as Map<String, dynamic>;

EntryShareScope _scope([Map<String, String> changes = const {}]) {
  final values = {..._fixture['scope'] as Map<String, dynamic>, ...changes};
  return EntryShareScope(
    shareId: values['shareId'] as String,
    organizationId: values['organizationId'] as String,
    vaultId: values['vaultId'] as String,
    entryId: values['entryId'] as String,
    sourceRevision: values['sourceRevision'] as String,
    expiresAt: values['expiresAt'] as String,
  );
}

Map<String, dynamic> _snapshotJson() =>
    jsonDecode(jsonEncode(_fixture['snapshot'])) as Map<String, dynamic>;

final _invalidSnapshot = throwsA(
  isA<EntryShareException>().having(
    (error) => error.kind,
    'kind',
    EntryShareErrorKind.invalidSnapshot,
  ),
);
final _invalidLink = throwsA(
  isA<EntryShareException>().having(
    (error) => error.kind,
    'kind',
    EntryShareErrorKind.invalidLink,
  ),
);

Future<SodiumSumo> _loadSodium() {
  final configured = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
  if (configured != null || Platform.isLinux) {
    return sodium_ffi.SodiumSumoInit.init(
      () => DynamicLibrary.open(configured ?? 'libsodium.so'),
    );
  }
  return SodiumSumoInit.init();
}

void main() {
  late SodiumSumo sodium;
  late EntryShareCryptoService service;
  late Uint8List key;
  late EntryShareCiphertext packet;

  setUpAll(() async {
    // A missing native library fails this suite; security tests never skip.
    sodium = await _loadSodium();
    service = EntryShareCryptoService(sodiumLoader: () async => sodium);
  });
  setUp(() {
    key = VaultProtocolBytes.hex(_fixture['keyHex'] as String);
    packet = EntryShareCiphertext(
      nonce: _fixture['nonce'] as String,
      ciphertext: _fixture['ciphertext'] as String,
    );
  });
  tearDown(() => key.fillRange(0, key.length, 0));

  Future<EntryShareSnapshot> open({
    EntryShareScope? scope,
    EntryShareCiphertext? input,
    Uint8List? inputKey,
    String? requestedId,
  }) => service.open(
    packet: input ?? packet,
    authority: scope ?? _scope(),
    requestedShareId: requestedId ?? _scope().shareId,
    key: inputKey ?? key,
  );

  test('AAD exactly matches independent nanosecond and >2^53 fixture', () {
    expect(
      VaultProtocolBytes.hexEncode(entryShareAad(_scope())),
      _fixture['aadHex'],
    );
  });

  test(
    'opens the independently generated web fixture without changing values',
    () async {
      expect((await open()).toJson(), _fixture['snapshot']);
      expect(key, VaultProtocolBytes.hex(_fixture['keyHex'] as String));
    },
  );

  test(
    'producer opens with independent AAD, fresh material and explicit disposal',
    () async {
      final snapshot = EntryShareSnapshot.fromJson(_snapshotJson());
      final first = await service.prepare(scope: _scope(), snapshot: snapshot);
      final second = await service.prepare(scope: _scope(), snapshot: snapshot);
      final secure = SecureKey.fromList(sodium, first.secrets.key);
      Uint8List? plaintext;
      try {
        expect(first.secrets.key, isNot(second.secrets.key));
        expect(first.secrets.accessToken, isNot(second.secrets.accessToken));
        expect(first.packet.nonce, isNot(second.packet.nonce));
        expect(first.secrets.key, isNot(first.secrets.accessToken));
        plaintext = sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
          cipherText: base64Decode(first.packet.ciphertext),
          nonce: base64Decode(first.packet.nonce),
          key: secure,
          additionalData: VaultProtocolBytes.hex(_fixture['aadHex'] as String),
        );
        expect(jsonDecode(utf8.decode(plaintext)), _fixture['snapshot']);
        await expectLater(
          open(input: first.packet, inputKey: first.secrets.accessToken),
          _invalidSnapshot,
        );
      } finally {
        secure.dispose();
        plaintext?.fillRange(0, plaintext.length, 0);
        first.dispose();
        second.dispose();
      }
      expect(first.secrets.key, everyElement(0));
      expect(first.secrets.accessToken, everyElement(0));
      expect(first.secrets.toFragment, _invalidLink);
    },
  );

  test('preserves decomposed Unicode, NUL, whitespace and emoji', () async {
    final json = _snapshotJson();
    (json['fields'] as List).first['value'] = '  e\u0301\u0000🔐\n ';
    final prepared = await service.prepare(
      scope: _scope(),
      snapshot: EntryShareSnapshot.fromJson(json),
    );
    try {
      expect(
        (await open(
          input: prepared.packet,
          inputKey: prepared.secrets.key,
        )).toJson(),
        json,
      );
    } finally {
      prepared.dispose();
    }
  });

  for (final field in [
    'shareId',
    'organizationId',
    'vaultId',
    'entryId',
    'sourceRevision',
    'expiresAt',
  ]) {
    test('authenticates independently supplied $field', () async {
      final changed = switch (field) {
        'sourceRevision' => '9007199254740994',
        'expiresAt' => '2026-09-21T12:00:00.123456790Z',
        _ => '99992233-4455-4677-8899-aabbccddeeff',
      };
      final scope = _scope({field: changed});
      await expectLater(
        open(scope: scope, requestedId: scope.shareId),
        _invalidSnapshot,
      );
    });
  }

  test(
    'delivery authority must match requested share, not its own wrapper',
    () async {
      await expectLater(
        open(requestedId: '99992233-4455-4677-8899-aabbccddeeff'),
        _invalidSnapshot,
      );
    },
  );

  test(
    'copies borrowed key before async initialization without wiping caller',
    () async {
      final pending = Completer<SodiumSumo>();
      final delayed = EntryShareCryptoService(
        sodiumLoader: () => pending.future,
      );
      final result = delayed.open(
        packet: packet,
        authority: _scope(),
        requestedShareId: _scope().shareId,
        key: key,
      );
      key.fillRange(0, key.length, 0);
      pending.complete(sodium);
      expect((await result).toJson(), _fixture['snapshot']);
      expect(key, everyElement(0));
    },
  );

  test('rejects tampered keys, nonces and ciphertext', () async {
    key[0] ^= 1;
    await expectLater(open(), _invalidSnapshot);
    key[0] ^= 1;
    final nonce = base64Decode(packet.nonce)..[0] ^= 1;
    await expectLater(
      open(
        input: EntryShareCiphertext(
          nonce: base64Encode(nonce),
          ciphertext: packet.ciphertext,
        ),
      ),
      _invalidSnapshot,
    );
    final ciphertext = base64Decode(packet.ciphertext)..[0] ^= 1;
    await expectLater(
      open(
        input: EntryShareCiphertext(
          nonce: packet.nonce,
          ciphertext: base64Encode(ciphertext),
        ),
      ),
      _invalidSnapshot,
    );
  });

  test(
    'rejects malformed encodings, wrong lengths and oversized packets',
    () async {
      for (final nonce in [
        '',
        '${packet.nonce}\n',
        base64Encode(Uint8List(23)),
        base64Encode(Uint8List(25)),
      ]) {
        await expectLater(
          open(
            input: EntryShareCiphertext(
              nonce: nonce,
              ciphertext: packet.ciphertext,
            ),
          ),
          _invalidSnapshot,
        );
      }
      for (final ciphertext in [
        '',
        'AA==',
        '${packet.ciphertext}\n',
        base64Encode(Uint8List(262145)),
      ]) {
        await expectLater(
          open(
            input: EntryShareCiphertext(
              nonce: packet.nonce,
              ciphertext: ciphertext,
            ),
          ),
          _invalidSnapshot,
        );
      }
      await expectLater(open(inputKey: Uint8List(31)), _invalidSnapshot);
      await expectLater(open(inputKey: Uint8List(33)), _invalidSnapshot);
    },
  );

  test('checks encoded producer budget before sodium initialization', () async {
    var calls = 0;
    final bounded = EntryShareCryptoService(
      sodiumLoader: () async {
        calls++;
        return sodium;
      },
    );
    final json = _snapshotJson();
    (json['fields'] as List).first['value'] = '🔐' * 100000;
    await expectLater(
      bounded.prepare(
        scope: _scope(),
        snapshot: EntryShareSnapshot.fromJson(json),
      ),
      _invalidSnapshot,
    );
    expect(calls, 0);
  });

  test('crypto failures never expose diagnostics or sensitive input', () async {
    final failing = EntryShareCryptoService(
      sodiumLoader: () =>
          Future.error(StateError('sensitive-fixture-diagnostic')),
    );
    await expectLater(
      failing.open(
        packet: packet,
        authority: _scope(),
        requestedShareId: _scope().shareId,
        key: key,
      ),
      throwsA(
        isA<EntryShareException>().having(
          (error) => error.toString(),
          'redacted error',
          'EntryShareException(invalidSnapshot)',
        ),
      ),
    );
  });

  for (final expiry in [
    '2026-02-30T12:00:00Z',
    '2026-09-21T24:00:00Z',
    '2026-09-21T12:00:60Z',
    '1969-12-31T23:59:59Z',
    '2026-09-21T12:00:00.1234567890Z',
    '2026-09-21T12:00:00+00:00',
  ]) {
    test('rejects non-contract instant $expiry', () {
      expect(
        () => entryShareAad(_scope({'expiresAt': expiry})),
        _invalidSnapshot,
      );
    });
  }
  for (final revision in ['-1', '01', '1.0', ' 1', '18446744073709551616']) {
    test('rejects non-u64 revision $revision', () {
      expect(
        () => entryShareAad(_scope({'sourceRevision': revision})),
        _invalidSnapshot,
      );
    });
  }
  test(
    'supports canonical UUIDv7/v8 without changing frozen Vault UUID profile',
    () {
      for (final version in ['7', '8']) {
        final id = '00112233-4455-${version}677-8899-aabbccddeeff';
        expect(entryShareUuid(id), hasLength(16));
        expect(() => VaultProtocolBytes.uuid(id), throwsFormatException);
        expect(() => entryShareUuid(id.toUpperCase()), _invalidSnapshot);
      }
    },
  );

  test('canonical fragment round-trips and wiping invalidates its owner', () {
    final owner = EntryShareSecrets(
      key: Uint8List.fromList(key),
      accessToken: Uint8List(32),
    );
    final fragment = owner.toFragment();
    final parsed = EntryShareSecrets.fromFragment(fragment);
    expect(parsed.key, key);
    expect(parsed.toFragment(), fragment);
    owner.dispose();
    owner.dispose();
    expect(owner.key, everyElement(0));
    expect(owner.accessToken, everyElement(0));
    expect(owner.toFragment, _invalidLink);
    expect(parsed.key, key);
    parsed.dispose();
  });

  test('rejects ambiguous or noncanonical fragments', () {
    final zeros = 'A' * 43;
    for (final fragment in [
      '#v=2&key=$zeros&access=$zeros',
      '#v=1&access=$zeros&key=$zeros',
      '#v=1&key=$zeros&access=$zeros&key=$zeros',
      '#v=1&key=$zeros&access=$zeros&extra=1',
      '#v=1&key=$zeros=&access=$zeros',
      '#v=1&key=${'A' * 42}B&access=$zeros',
      '#v=1&key=$zeros&access=${'A' * 42}B',
      '#v=1&key=%41${'A' * 42}&access=$zeros',
      'v=1&key=$zeros&access=$zeros',
      '#v=1&key=$zeros&access=$zeros\n',
    ]) {
      expect(() => EntryShareSecrets.fromFragment(fragment), _invalidLink);
    }
  });

  test(
    'authenticated but invalid plaintext never reaches a snapshot',
    () async {
      final secure = SecureKey.fromList(sodium, key);
      final invalid = [
        Uint8List.fromList([0xc3, 0x28]),
        utf8.encode('not JSON: synthetic-secret'),
        utf8.encode(jsonEncode({..._snapshotJson(), 'agentPolicy': {}})),
        utf8.encode(
          jsonEncode({
            ..._snapshotJson(),
            'fields': [
              {
                'id': 'credential.password',
                'label': '',
                'type': 'text',
                'value': 'synthetic-secret',
              },
            ],
          }),
        ),
      ];
      try {
        for (final plaintext in invalid) {
          final nonce = sodium.randombytes.buf(24);
          final encrypted = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
            message: plaintext,
            nonce: nonce,
            key: secure,
            additionalData: VaultProtocolBytes.hex(
              _fixture['aadHex'] as String,
            ),
          );
          await expectLater(
            open(
              input: EntryShareCiphertext(
                nonce: base64Encode(nonce),
                ciphertext: base64Encode(encrypted),
              ),
            ),
            _invalidSnapshot,
          );
        }
      } finally {
        secure.dispose();
        for (final plaintext in invalid) {
          plaintext.fillRange(0, plaintext.length, 0);
        }
      }
    },
  );

  test('equivalent timestamp precision has the same AAD', () {
    expect(
      entryShareAad(_scope({'expiresAt': '2026-09-21T12:00:00Z'})),
      entryShareAad(_scope({'expiresAt': '2026-09-21T12:00:00.000000000Z'})),
    );
    expect(
      entryShareAad(_scope({'expiresAt': '2026-09-21T12:00:00.1Z'})),
      entryShareAad(_scope({'expiresAt': '2026-09-21T12:00:00.100000000Z'})),
    );
    expect(
      entryShareAad(_scope({'sourceRevision': '18446744073709551615'})),
      hasLength(103),
    );
  });

  test(
    'all native field types and explicit custom fields retain exact values',
    () {
      final native = {
        'key': {'key.value': 'concealed', 'key.url': 'text'},
        'credential': {
          'credential.username': 'text',
          'credential.password': 'concealed',
          'credential.url': 'text',
          'credential.totp': 'totp',
        },
        'script': {'script.source': 'multiline', 'script.interpreter': 'text'},
        'creditCard': {
          'creditCard.cardholderName': 'text',
          'creditCard.cardNumber': 'concealed',
          'creditCard.expiryMonth': 'text',
          'creditCard.expiryYear': 'text',
          'creditCard.billingAddress': 'multiline',
        },
      };
      for (final entry in native.entries) {
        final json = {
          'schema': EntryShareSnapshot.schema,
          'title': '  title  ',
          'entryType': entry.key,
          'fields': [
            for (final field in {
              ...entry.value,
              'notes': 'multiline',
              'description': 'multiline',
            }.entries)
              {
                'id': field.key,
                'label': '',
                'type': field.value,
                'value': '  preserved\n',
              },
            for (final type in ['text', 'multiline', 'concealed', 'totp'])
              {'id': 'custom:$type', 'label': type, 'type': type, 'value': ''},
          ],
        };
        final snapshot = EntryShareSnapshot.fromJson(json);
        expect(snapshot.toJson(), json);
        expect(() => snapshot.fields.clear(), throwsUnsupportedError);
      }
    },
  );

  test(
    'snapshot rejects extra metadata, duplicate fields and type downgrades',
    () {
      final mutations = <void Function(Map<String, dynamic>)>[
        (json) => json['agentPolicy'] = {},
        (json) => json['entryType'] = 'key',
        (json) => (json['fields'] as List).add((json['fields'] as List).first),
        (json) => (json['fields'] as List).first['type'] = 'text',
        (json) => (json['fields'] as List).first['id'] = 'custom:',
        (json) => (json['fields'] as List).first['policy'] = 'allowed',
        (json) => json['fields'] = [],
        (json) => json['fields'] = List.generate(
          257,
          (i) => {'id': 'custom:$i', 'label': '', 'type': 'text', 'value': ''},
        ),
        (json) => json['title'] = '',
        (json) => json['title'] = 'x' * 513,
      ];
      for (final mutate in mutations) {
        final json = _snapshotJson();
        mutate(json);
        expect(() => EntryShareSnapshot.fromJson(json), _invalidSnapshot);
      }
    },
  );
}
