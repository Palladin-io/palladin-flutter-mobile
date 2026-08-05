import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_aad.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_envelope_service.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_kdf.dart';
import 'package:mobile_palladin/features/vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';
import 'package:sodium/sodium_sumo.dart' as sodium_ffi;

const _pinnedManifestSha256 =
    'b3cbd9bee6a663789fae4047931e411abb3ad0c15fa2204a747be6c09b54fd9e';

final _fixtureRoot = Directory('test/fixtures/vault_protocol_2');

Map<String, dynamic> _fixture(Directory root, String path) =>
    (jsonDecode(File('${root.path}/$path').readAsStringSync()) as Map)
        .cast<String, dynamic>();

Map<String, Object?> _objectMap(Object? value) =>
    (value as Map).cast<String, Object?>();

VaultAadProfile _profile(String value) => switch (value) {
  'member-vault-metadata' => VaultAadProfile.memberVaultMetadata,
  'member-index' => VaultAadProfile.memberIndex,
  'member-secret' => VaultAadProfile.memberSecret,
  'agent-discovery' => VaultAadProfile.agentDiscovery,
  'entry-key-wrapper' => VaultAadProfile.entryKeyWrapper,
  'vault-private-key' => VaultAadProfile.vaultPrivateKey,
  'vault-discovery-key' => VaultAadProfile.vaultDiscoveryKey,
  'encrypted-reason' => VaultAadProfile.encryptedReason,
  'grant-payload' => VaultAadProfile.grantPayload,
  _ => throw FormatException('unsupported fixture profile: $value'),
};

VaultKdfPurpose _purpose(String value) => switch (value) {
  'member-vault-metadata' => VaultKdfPurpose.memberVaultMetadata,
  'member-index' => VaultKdfPurpose.memberIndex,
  'member-secret' => VaultKdfPurpose.memberSecret,
  'agent-discovery' => VaultKdfPurpose.agentDiscovery,
  'encrypted-asset' => VaultKdfPurpose.encryptedAsset,
  _ => throw FormatException('unsupported fixture purpose: $value'),
};

VaultPublicKeyKind _keyKind(int value) => switch (value) {
  1 => VaultPublicKeyKind.agentX25519,
  2 => VaultPublicKeyKind.agentEd25519,
  3 => VaultPublicKeyKind.vaultSigningEd25519,
  4 => VaultPublicKeyKind.vaultMessageX25519,
  5 => VaultPublicKeyKind.memberX25519,
  _ => throw FormatException('unsupported fixture key kind: $value'),
};

VaultEnvelopeExpectations _expectations(Map<String, Object?> envelope) {
  final header = _objectMap(envelope['header']);
  return VaultEnvelopeExpectations(
    aadContext: envelope,
    minimumMemberKeyGeneration: header['memberKeyGeneration']! as int,
  );
}

void main() {
  final isCi = Platform.environment['CI'] == 'true';
  final root = _fixtureRoot;
  if (!File('${root.path}/manifest.json').existsSync()) {
    test(
      'vendored Vault protocol 2 fixtures are present',
      () => fail(
        'Vendored fixtures are missing from ${root.path}. Restore the tracked '
        'test fixture directory before running the suite.',
      ),
      skip: isCi ? false : 'Vendored protocol fixtures are missing.',
    );
    return;
  }

  final aad = _fixture(root, 'vectors/aad.json');
  final keyDerivation = _fixture(root, 'vectors/key-derivation.json');
  final envelopes = _fixture(root, 'vectors/envelopes.json');
  final rotation = _fixture(root, 'vectors/rotation.json');
  final signatures = _fixture(root, 'vectors/signatures.json');
  final negatives = _fixture(root, 'negative/corruption.json');

  late SodiumSumo sodium;
  late VaultProtocolEnvelopeService envelopeService;
  late VaultProtocolSignatureService signatureService;
  var sodiumAvailable = false;

  setUpAll(() async {
    envelopeService = VaultProtocolEnvelopeService(
      sodiumLoader: () async {
        if (!sodiumAvailable) throw StateError('libsodium unavailable');
        return sodium;
      },
    );
    signatureService = VaultProtocolSignatureService(
      sodiumLoader: () async {
        if (!sodiumAvailable) throw StateError('libsodium unavailable');
        return sodium;
      },
    );
    try {
      final configuredLibrary = Platform.environment['PALLADIN_LIBSODIUM_PATH'];
      if (configuredLibrary != null) {
        sodium = await sodium_ffi.SodiumSumoInit.init(
          () => DynamicLibrary.open(configuredLibrary),
        );
      } else if (Platform.isLinux) {
        sodium = await sodium_ffi.SodiumSumoInit.init(
          () => DynamicLibrary.open('libsodium.so'),
        );
      } else if (Platform.isMacOS &&
          File(
            '/opt/homebrew/opt/libsodium/lib/libsodium.dylib',
          ).existsSync()) {
        sodium = await sodium_ffi.SodiumSumoInit.init(
          () => DynamicLibrary.open(
            '/opt/homebrew/opt/libsodium/lib/libsodium.dylib',
          ),
        );
      } else {
        sodium = await SodiumSumoInit.init();
      }
      sodiumAvailable = true;
    } catch (error) {
      sodiumAvailable = false;
      if (isCi) {
        throw StateError('CI must execute native libsodium fixtures: $error');
      }
    }
  });

  test('pins the vendored fixture manifest', () {
    final bytes = File('${root.path}/manifest.json').readAsBytesSync();
    expect(sha256.convert(bytes).toString(), _pinnedManifestSha256);
    final manifest = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    for (final raw in manifest['files']! as List) {
      final pinned = _objectMap(raw);
      final fixtureBytes = File(
        '${root.path}/${pinned['path']}',
      ).readAsBytesSync();
      expect(
        sha256.convert(fixtureBytes).toString(),
        pinned['sha256'],
        reason: pinned['path']! as String,
      );
    }
  });

  for (final raw in aad['vectors']! as List) {
    final vector = _objectMap(raw);
    test('encodes ${vector['id']} AAD byte-for-byte', () {
      final allAead = [
        ...envelopes['aeadVectors']! as List,
        ...rotation['pendingAeadVectors']! as List,
      ];
      final source = allAead
          .map(_objectMap)
          .firstWhere((item) => item['id'] == vector['id']);
      final encoded = encodeVaultAad(
        _profile(vector['profile']! as String),
        _objectMap(source['envelope']),
      );
      expect(VaultProtocolBytes.hexEncode(encoded), vector['aadHex']);
    });
  }

  for (final raw in keyDerivation['hkdfVectors']! as List) {
    final vector = _objectMap(raw);
    test('derives ${vector['purpose']} projection key byte-for-byte', () {
      final derived = deriveVaultProjectionKey(
        VaultProtocolBytes.hex(vector['baseKeyHex']! as String),
        VaultKdfContext(
          purpose: _purpose(vector['purpose']! as String),
          resourceKind: vector['resourceKind'] == 'vault' ? 1 : 2,
          organizationId: vector['organizationId']! as String,
          vaultId: vector['vaultId']! as String,
          entryId: vector['entryId'] as String?,
          keyVersion: vector['keyVersion']! as int,
          memberKeyGeneration: vector['memberKeyGeneration']! as int,
        ),
      );
      expect(VaultProtocolBytes.hexEncode(derived), vector['outputHex']);
      derived.fillRange(0, derived.length, 0);
    });
  }

  for (final raw in keyDerivation['fingerprintVectors']! as List) {
    final vector = _objectMap(raw);
    test('derives ${vector['name']} fingerprint byte-for-byte', () {
      final fingerprint = vaultPublicKeyFingerprint(
        _keyKind(vector['keyKind']! as int),
        VaultProtocolBytes.hex(vector['publicKeyHex']! as String),
      );
      expect(
        VaultProtocolBytes.hexEncode(fingerprint),
        vector['fingerprintHex'],
      );
      fingerprint.fillRange(0, fingerprint.length, 0);
    });
  }

  final positiveAead = [
    ...envelopes['aeadVectors']! as List,
    ...rotation['pendingAeadVectors']! as List,
  ].map(_objectMap).toList();
  for (final vector in positiveAead) {
    test('decrypts authenticated ${vector['id']} envelope', () async {
      if (!sodiumAvailable) {
        markTestSkipped('libsodium is unavailable in this test host');
        return;
      }
      final envelope = _objectMap(vector['envelope']);
      final plaintext = await envelopeService.decrypt(
        profile: _profile(vector['aadProfile']! as String),
        envelope: envelope,
        key: VaultProtocolBytes.hex(vector['decryptionKeyHex']! as String),
        expected: _expectations(envelope),
      );
      expect(VaultProtocolBytes.hexEncode(plaintext), vector['plaintextHex']);
      plaintext.fillRange(0, plaintext.length, 0);
    });
  }

  final sealedVectors = [
    ...envelopes['sealedBoxVectors']! as List,
    ...rotation['pendingSealedBoxVectors']! as List,
  ].map(_objectMap).toList();
  for (final vector in sealedVectors) {
    test('opens authenticated ${vector['id']} package', () async {
      if (!sodiumAvailable) {
        markTestSkipped('libsodium is unavailable in this test host');
        return;
      }
      final envelope = _objectMap(vector['envelope']);
      final encoded =
          envelope['sealedVaultKeyPackage'] ?? envelope['agentWrappedVdk'];
      final plaintext = await envelopeService.openPackage(
        ciphertext: VaultProtocolBytes.base64UrlDecode(encoded! as String),
        recipientPublicKey: VaultProtocolBytes.hex(
          vector['recipientPublicKeyHex']! as String,
        ),
        recipientPrivateKey: VaultProtocolBytes.hex(
          vector['recipientPrivateKeyHex']! as String,
        ),
      );
      expect(utf8.decode(plaintext), vector['plaintextCanonical']);
      plaintext.fillRange(0, plaintext.length, 0);
    });
  }

  for (final raw in signatures['vectors']! as List) {
    final vector = _objectMap(raw);
    test('verifies canonical ${vector['id']} signature', () async {
      final unsigned = vector['unsignedObject']!;
      expect(
        canonicalizeVaultJson(unsigned),
        vector['canonicalUnsignedObject'],
      );
      expect(
        VaultProtocolBytes.hexEncode(
          vaultSignatureInput(vector['domainPrefixAscii']! as String, unsigned),
        ),
        vector['signatureInputHex'],
      );
      if (!sodiumAvailable) {
        markTestSkipped('libsodium is unavailable in this test host');
        return;
      }
      final signed = _objectMap(vector['signedObject']);
      final encoded = signed['signature'] ?? signed['agentSignature'];
      expect(
        await signatureService.verify(
          domainPrefix: vector['domainPrefixAscii']! as String,
          unsignedObject: unsigned,
          signature: encoded! as String,
          publicKey: VaultProtocolBytes.hex(vector['publicKeyHex']! as String),
        ),
        isTrue,
      );
    });
  }

  test(
    'rejects every concrete AEAD corruption and substitution vector',
    () async {
      if (!sodiumAvailable) {
        markTestSkipped('libsodium is unavailable in this test host');
        return;
      }
      final byId = {for (final vector in positiveAead) vector['id']: vector};
      for (final raw in negatives['cases']! as List) {
        final negative = _objectMap(raw);
        if ({
          'invalid-vault-manifest-signature',
          'sealed-box-wrong-recipient',
        }.contains(negative['id'])) {
          continue;
        }
        final source = byId[negative['sourceVector']]!;
        final target = negative['targetVector'] == null
            ? source
            : byId[negative['targetVector']]!;
        final envelope = _objectMap(negative['envelope']);
        final keyHex =
            negative['decryptionKeyHex'] as String? ??
            source['decryptionKeyHex']! as String;
        await expectLater(
          envelopeService.decrypt(
            profile: _profile(source['aadProfile']! as String),
            envelope: envelope,
            key: VaultProtocolBytes.hex(keyHex),
            expected: _expectations(_objectMap(target['envelope'])),
          ),
          throwsA(anything),
          reason: negative['id']! as String,
        );
      }
    },
  );

  test('rejects invalid signature and wrong sealed-box recipient', () async {
    if (!sodiumAvailable) {
      markTestSkipped('libsodium is unavailable in this test host');
      return;
    }
    final cases = (negatives['cases']! as List).map(_objectMap).toList();
    final invalidSignature = cases.firstWhere(
      (item) => item['id'] == 'invalid-vault-manifest-signature',
    );
    final signatureVector = (signatures['vectors']! as List)
        .map(_objectMap)
        .firstWhere((item) => item['id'] == invalidSignature['sourceVector']);
    final signed = _objectMap(invalidSignature['signedObject']);
    final signature = signed.remove('signature')! as String;
    expect(
      await signatureService.verify(
        domainPrefix: signatureVector['domainPrefixAscii']! as String,
        unsignedObject: signed,
        signature: signature,
        publicKey: VaultProtocolBytes.hex(
          signatureVector['publicKeyHex']! as String,
        ),
      ),
      isFalse,
    );

    final wrongRecipient = cases.firstWhere(
      (item) => item['id'] == 'sealed-box-wrong-recipient',
    );
    final seed = SecureKey.fromList(
      sodium,
      VaultProtocolBytes.hex(wrongRecipient['recipientSeedHex']! as String),
    );
    final keyPair = sodium.crypto.box.seedKeyPair(seed);
    seed.dispose();
    final envelope = _objectMap(wrongRecipient['envelope']);
    await expectLater(
      envelopeService.openPackage(
        ciphertext: VaultProtocolBytes.base64UrlDecode(
          envelope['agentWrappedVdk']! as String,
        ),
        recipientPublicKey: keyPair.publicKey,
        recipientPrivateKey: keyPair.secretKey.extractBytes(),
      ),
      throwsA(anything),
    );
    keyPair.secretKey.dispose();
  });

  test(
    'fails closed before crypto on versions, bounds, and stale generation',
    () async {
      final source = positiveAead.first;
      final envelope = _objectMap(source['envelope']);
      final header = _objectMap(envelope['header']);
      for (final patch in [
        {'protocolVersion': 1},
        {'algorithmSuite': 99},
      ]) {
        final changed = <String, Object?>{
          ...envelope,
          'header': <String, Object?>{...header, ...patch},
        };
        await expectLater(
          envelopeService.decrypt(
            profile: _profile(source['aadProfile']! as String),
            envelope: changed,
            key: Uint8List(32),
            expected: _expectations(envelope),
          ),
          throwsA(anything),
        );
      }
      await expectLater(
        envelopeService.decrypt(
          profile: _profile(source['aadProfile']! as String),
          envelope: envelope,
          key: Uint8List(32),
          expected: VaultEnvelopeExpectations(
            aadContext: envelope,
            minimumMemberKeyGeneration:
                (header['memberKeyGeneration']! as int) + 1,
          ),
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('canonical bytes reject aliases and non-NFC/non-scalar text', () {
    expect(
      () => VaultProtocolBytes.base64UrlDecode('AA=='),
      throwsFormatException,
    );
    expect(
      () => VaultProtocolBytes.utf8Encode('e\u0301'),
      throwsFormatException,
    );
    expect(
      () => VaultProtocolBytes.utf8Encode(String.fromCharCode(0xd800)),
      throwsFormatException,
    );
    expect(canonicalizeVaultJson({'value': '🔐'}), '{"value":"🔐"}');
    expect(
      () => vaultSignatureInput('PLDNV2SIG:UNKNOWN:', const {}),
      throwsFormatException,
    );
  });
}
