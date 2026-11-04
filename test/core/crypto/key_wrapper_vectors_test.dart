import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/key_wrapper/key_wrapper.dart';

import '../../support/native_sodium.dart';

void main() {
  final vectors = readJsonFixture('test/fixtures/key-wrapper-v1/vectors.json');
  final registry = readJsonFixture(
    'test/fixtures/key-wrapper-v1/registry.json',
  );
  late KeyWrapper wrapper;

  setUpAll(() async {
    final sodium = await loadTestSodium();
    wrapper = KeyWrapper(sodiumLoader: () async => sodium);
  });

  KeyWrapperDescriptor descriptorOf(Map<String, dynamic> vector) =>
      KeyWrapperDescriptor.fromJson(
        Map<String, dynamic>.from(vector['descriptor'] as Map),
      );

  RecipientPublicKey recipientOf(Map<String, dynamic> vector) {
    final recipient = vector['recipient'] as Map<String, dynamic>;
    return RecipientPublicKey(
      suite: WrapperSuite.parse(recipient['directorySuiteId']),
      keyKind: RecipientKeyKind.tryParse(recipient['keyKind'])!,
      keyVersion: recipient['keyVersion'] as int,
      publicKey: hexBytes(recipient['publicKeyHex'] as String),
    );
  }

  Uint8List privateKeyOf(Map<String, dynamic> vector) =>
      hexBytes((vector['recipient'] as Map)['privateKeyHex'] as String);

  test('the build-time registry mirrors the protocol registry', () {
    final suites = {
      for (final suite in registry['suites'] as List)
        (suite as Map)['id']: suite['status'],
    };
    expect(suites, {
      for (final suite in WrapperSuite.values)
        suite.wireValue: suite.status == WrapperSuiteStatus.active
            ? 'active'
            : 'read-only',
    });
    for (final purpose in registry['purposes'] as List) {
      final local = KeyWrapperPurpose.tryParse((purpose as Map)['id'])!;
      expect(local.scopeBitmap, purpose['scopeBitmap']);
      expect(
        local.recipientKeyKinds.map((kind) => kind.id).toList(),
        purpose['recipientKeyKinds'],
      );
    }
    expect(KeyWrapperPurpose.values, hasLength(9));
    expect(WrapperSuite.memberKeySuite, WrapperSuite.xwingV1);
  });

  for (final vector in [
    ...vectors['positive'] as List,
    ...vectors['legacy'] as List,
  ].cast<Map<String, dynamic>>()) {
    test('opens ${vector['name']}', () async {
      final descriptor = descriptorOf(vector);
      expect(
        toHex(wrapper.encodeContext(descriptor)),
        vector['expectedContextHex'],
      );
      final opened = await wrapper.open(
        descriptor: descriptor,
        encodedPackage: vector['encodedSealedKeyPackage'] as String,
        recipient: recipientOf(vector),
        recipientPrivateKey: privateKeyOf(vector),
      );
      expect(toHex(opened), vector['wrappedKeyHex']);
    });
  }

  for (final vector
      in (vectors['positive'] as List).cast<Map<String, dynamic>>().where(
        (vector) =>
            (vector['descriptor'] as Map)['wrapperSuiteId'] ==
            'palladin-xwing-v1',
      )) {
    test('seals and reopens ${vector['name']}', () async {
      final descriptor = descriptorOf(vector);
      final key = hexBytes(vector['wrappedKeyHex'] as String);
      final sealed = await wrapper.seal(
        descriptor: descriptor,
        key: key,
        recipient: recipientOf(vector),
      );
      expect(b64urlBytes(sealed), hasLength(1168));
      expect(sealed, isNot(vector['encodedSealedKeyPackage']));
      expect(
        await wrapper.open(
          descriptor: descriptor,
          encodedPackage: sealed,
          recipient: recipientOf(vector),
          recipientPrivateKey: privateKeyOf(vector),
        ),
        key,
      );
    });
  }

  for (final vector
      in (vectors['negative'] as List).cast<Map<String, dynamic>>()) {
    test('rejects ${vector['name']} as ${vector['expectedError']}', () async {
      Future<Object?> run() => vector['operation'] == 'seal'
          ? wrapper.seal(
              descriptor: descriptorOf(vector),
              key: Uint8List(32),
              recipient: recipientOf(vector),
            )
          : wrapper.open(
              descriptor: descriptorOf(vector),
              encodedPackage: vector['encodedSealedKeyPackage'] as String,
              recipient: recipientOf(vector),
              recipientPrivateKey: privateKeyOf(vector),
            );
      await expectLater(
        run,
        throwsA(
          isA<KeyWrapperException>().having(
            (error) => error.error.code,
            'code',
            vector['expectedError'],
          ),
        ),
      );
    });
  }
}
