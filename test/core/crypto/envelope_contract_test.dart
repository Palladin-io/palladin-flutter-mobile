import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/core/crypto/asymmetric_keys.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_contract.dart';
import 'package:mobile_palladin/core/crypto/envelope/envelope_suite.dart';
import 'package:mobile_palladin/core/crypto/x25519_key_wrapper.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

void main() {
  test(
    'parses the closed backend enum names and numeric protocol purposes',
    () {
      expect(
        WrapperPurpose.parseWire('memberVaultKey'),
        WrapperPurpose.memberVaultKey,
      );
      expect(
        EnvelopePurpose.parseWire('vaultDiscoveryKey'),
        EnvelopePurpose.vaultDiscoveryKeyByVk,
      );
      expect(
        EnvelopePurpose.parseWire(2),
        EnvelopePurpose.vaultDiscoveryKeyByVk,
      );
      expect(
        () => EnvelopePurpose.parseWire('vaultDiscoveryKeyByVk'),
        throwsA(isA<EnvelopeException>()),
      );
    },
  );

  final scope = EnvelopeScope(
    organizationId: EnvelopeId.parse('11111111-1111-4111-8111-111111111111'),
    vaultId: EnvelopeId.parse('22222222-2222-4222-8222-222222222222'),
    entryId: EnvelopeId.parse('33333333-3333-4333-8333-333333333333'),
  );

  EnvelopeDescriptor memberSecret({int revision = 7}) => EnvelopeDescriptor(
    purpose: EnvelopePurpose.memberSecret,
    scope: scope,
    resourceRevision: revision,
    keyVersion: 2,
    memberKeyGeneration: 3,
    purposeData: const MemberSecretPurposeData(operation: 5),
  );

  test('member-secret AAD and HKDF info match the frozen byte vector', () {
    expect(
      _hex(memberSecret().encodeAad()),
      '504c444e454e56320002001970616c6c6164696e2d7661756c742d786368616368612d7631'
      '00060007111111111111411181111111111111112222222222224222822222222222222233333333333343338333333333333333'
      '00000000000000070000000201000000030005',
    );
    expect(
      _hex(memberSecret().encodeKdfInfo()),
      '504c444e4b4446320002001970616c6c6164696e2d7661756c742d786368616368612d7631'
      '00060007111111111111411181111111111111112222222222224222822222222222222233333333333343338333333333333333'
      '000000020100000003',
    );
  });

  test('field-set commitment sorts ordinally and rejects ambiguity', () {
    expect(
      _hex(computeFieldSetCommitment(['username', 'password'])),
      'f4efe1b64791880d2f2bcd96905ae75bb39a8c5212a9b77831e9376699372708',
    );
    expect(
      computeFieldSetCommitment(['password', 'username']),
      computeFieldSetCommitment(['username', 'password']),
    );
    expect(
      () => computeFieldSetCommitment(['password', 'password']),
      throwsA(isA<EnvelopeException>()),
    );
    expect(
      () => computeFieldSetCommitment(['bad field']),
      throwsA(isA<EnvelopeException>()),
    );
  });

  test('grant descriptor matches the canonical backend byte vector', () {
    final descriptor = EnvelopeDescriptor(
      purpose: EnvelopePurpose.grant,
      scope: EnvelopeScope(
        organizationId: EnvelopeId.parse(
          '00112233-4455-6677-8899-aabbccddeeff',
        ),
        vaultId: EnvelopeId.parse('11112222-3333-4444-8555-666677778888'),
        entryId: EnvelopeId.parse('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'),
        grantOrRequestId: EnvelopeId.parse(
          '12345678-1234-4234-8234-1234567890ab',
        ),
        agentId: EnvelopeId.parse('fedcba98-7654-4321-8765-abcdefabcdef'),
      ),
      resourceRevision: 7,
      keyVersion: 3,
      memberKeyGeneration: 9,
      purposeData: GrantPurposeData(
        entryRevision: 6,
        recipientKeyVersion: 4,
        recipientFingerprint: Uint8List.fromList(List.filled(32, 0x5a)),
        methods: 3,
        fieldSetCommitment: Uint8List.fromList(List.filled(32, 0xa5)),
        expiresAtSeconds: 1700000000,
        expiresAtNanoseconds: 123456789,
        remainingUses: 5,
      ),
    );
    expect(
      _hex(descriptor.encodeAad()),
      '504c444e454e56320002001970616c6c6164696e2d7661756c742d786368616368612d7631000a001f'
      '00112233445566778899aabbccddeeff11112222333344448555666677778888aaaaaaaabbbb4ccc8dddeeeeeeeeeeee'
      '123456781234423482341234567890abfedcba98765443218765abcdefabcdef0000000000000007000000030100000009'
      '0000000000000006001d70616c6c6164696e2d7832353531392d7365616c65642d626f782d763100000004'
      '5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a0003'
      'a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a501000000006553f100075bcd150100000005',
    );
  });

  test('copied Rust fixture and Flutter HKDF output remain byte-identical', () {
    final fixtureBytes = File(
      'test/fixtures/crypto/envelope-xchacha-hkdf.json',
    ).readAsBytesSync();
    expect(
      _hex(Uint8List.fromList(sha256.convert(fixtureBytes).bytes)),
      '8f632a8f1035fa92e58d95cd079efe3c3e75f7ab0929085f7edf42b99b051b23',
    );
    final fixture =
        jsonDecode(utf8.decode(fixtureBytes)) as Map<String, dynamic>;
    final expected = fixture['expected'] as Map<String, dynamic>;
    final descriptor = _fixtureGrantDescriptor();
    expect(_hex(descriptor.encodeAad()), expected['descriptorAadHex']);
    expect(_hex(descriptor.encodeKdfInfo()), expected['kdfContextHex']);
    final suite = XChaChaVaultEnvelopeSuite();
    final key = suite.deriveSubkey(
      rootKey: _fromHex(fixture['inputKeyMaterialHex'] as String),
      descriptor: descriptor,
    );
    try {
      expect(_hex(key), expected['derivedKeyHex']);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  });

  test('X25519 wrapper context matches the canonical Rust fixture', () {
    final fixtureBytes = File(
      'test/fixtures/crypto/x25519-sealed-box.json',
    ).readAsBytesSync();
    expect(
      _hex(Uint8List.fromList(sha256.convert(fixtureBytes).bytes)),
      '96e673b82bfc9a795aca4bc5e4942c40a7dd62a958e8716906f566463a21dd42',
    );
    final fixture =
        jsonDecode(utf8.decode(fixtureBytes)) as Map<String, dynamic>;
    expect(
      _hex(_fixtureWrapperContext().encode()),
      fixture['expectedContextHex'],
    );
  });

  test(
    'X25519 wrapper rejects a caller-supplied plain SHA-256 fingerprint',
    () async {
      final publicKey = _fromHex(
        'ff2ee45601ec1b67310c7790404585ae697331eee1c1f8cf2419731c1fff3e6b',
      );
      final plainFingerprint = Uint8List.fromList(
        sha256.convert(publicKey).bytes,
      );
      final valid = _fixtureWrapperContext();
      final invalid = WrapperContext(
        purpose: valid.purpose,
        scope: valid.scope,
        resourceRevision: valid.resourceRevision,
        wrappedKeyVersion: valid.wrappedKeyVersion,
        memberKeyGeneration: valid.memberKeyGeneration,
        recipientKeyKind: valid.recipientKeyKind,
        recipientKeyVersion: valid.recipientKeyVersion,
        recipientFingerprint: plainFingerprint,
        parentDescriptorHash: valid.parentDescriptorHash,
      );
      await expectLater(
        X25519SealedBoxKeyWrapper().seal(
          key: Uint8List(32),
          context: invalid,
          recipient: X25519PublicKey(publicKey),
        ),
        throwsA(isA<EnvelopeException>()),
      );
    },
  );

  test(
    'canonical XChaCha and X25519 OPEN vectors run when sodium is available',
    () async {
      late SodiumSumo sodium;
      try {
        sodium = await SodiumSumoInit.init();
      } catch (_) {
        markTestSkipped('libsodium is unavailable in this Flutter test host');
        return;
      }
      final envelopeFixture =
          jsonDecode(
                File(
                  'test/fixtures/crypto/envelope-xchacha-hkdf.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final envelopeExpected =
          envelopeFixture['expected'] as Map<String, dynamic>;
      final suite = XChaChaVaultEnvelopeSuite(sodiumLoader: () async => sodium);
      final payload = await suite.seal(
        descriptor: _fixtureGrantDescriptor(),
        rootKey: _fromHex(envelopeFixture['inputKeyMaterialHex'] as String),
        plaintext: _fromHex(envelopeFixture['plaintextHex'] as String),
        nonce: _fromHex(envelopeFixture['nonceHex'] as String),
      );
      expect(_hex(payload.bytes), envelopeExpected['encodedSuitePayloadHex']);

      final wrapperFixture =
          jsonDecode(
                File(
                  'test/fixtures/crypto/x25519-sealed-box.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final wrapper = X25519SealedBoxKeyWrapper(
        sodiumLoader: () async => sodium,
      );
      final opened = await wrapper.open(
        wrapped: _fromHex(wrapperFixture['sealedPackageHex'] as String),
        context: _fixtureWrapperContext(),
        recipientSecretKey: _fromHex(
          wrapperFixture['recipientPrivateKeyHex'] as String,
        ),
      );
      expect(_hex(opened), wrapperFixture['wrappedKeyHex']);
      await expectLater(
        wrapper.open(
          wrapped: _fromHex(wrapperFixture['sealedPackageHex'] as String),
          context: _fixtureWrapperContext(resourceRevision: 8),
          recipientSecretKey: _fromHex(
            wrapperFixture['recipientPrivateKeyHex'] as String,
          ),
        ),
        throwsA(isA<EnvelopeException>()),
      );
    },
  );

  test('purpose-specific scope and extension mismatches fail closed', () {
    expect(
      () => EnvelopeDescriptor(
        purpose: EnvelopePurpose.memberSecret,
        scope: EnvelopeScope(
          organizationId: scope.organizationId,
          vaultId: scope.vaultId,
        ),
        resourceRevision: 1,
        keyVersion: 1,
        memberKeyGeneration: 1,
        purposeData: const MemberSecretPurposeData(operation: 1),
      ),
      throwsA(isA<EnvelopeException>()),
    );
    expect(
      () => EnvelopeDescriptor(
        protocolVersion: 1,
        purpose: EnvelopePurpose.memberSecret,
        scope: scope,
        resourceRevision: 1,
        keyVersion: 1,
        memberKeyGeneration: 1,
        purposeData: const MemberSecretPurposeData(operation: 1),
      ),
      throwsA(isA<EnvelopeException>()),
    );
  });

  test('opaque payload accepts only canonical bounded base64url', () {
    final bytes = Uint8List(XChaChaVaultEnvelopeSuite.minimumPayloadBytes);
    final payload = EncodedSuitePayload.fromBytes(bytes);
    expect(payload.toBase64Url(), isNot(contains('=')));
    expect(
      EncodedSuitePayload.fromBase64Url(payload.toBase64Url()).bytes,
      bytes,
    );
    expect(
      () => EncodedSuitePayload.fromBase64Url('${payload.toBase64Url()}='),
      throwsA(isA<EnvelopeException>()),
    );
    expect(
      () => EncodedSuitePayload.fromBytes(Uint8List(39)),
      throwsA(isA<EnvelopeException>()),
    );
  });

  test('suite registry rejects an unregistered wire identifier', () {
    final registry = CryptoSuiteRegistry();
    expect(
      () => registry.resolveWire('palladin-vault-xsalsa-legacy'),
      throwsA(isA<EnvelopeException>()),
    );
  });

  test(
    'revision substitution changes AAD but not the versioned HKDF key info',
    () {
      expect(
        memberSecret(revision: 8).encodeAad(),
        isNot(memberSecret().encodeAad()),
      );
      expect(
        memberSecret(revision: 8).encodeKdfInfo(),
        memberSecret().encodeKdfInfo(),
      );
    },
  );

  test(
    'XChaCha authenticates every descriptor field when sodium is available',
    () async {
      late SodiumSumo sodium;
      try {
        sodium = await SodiumSumoInit.init();
      } catch (_) {
        markTestSkipped('libsodium is unavailable in this Flutter test host');
        return;
      }
      final suite = XChaChaVaultEnvelopeSuite(sodiumLoader: () async => sodium);
      final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
      final nonce = Uint8List.fromList(
        List<int>.generate(24, (index) => index + 32),
      );
      final plaintext = Uint8List.fromList(
        utf8.encode('cross-client member secret'),
      );
      final encrypted = await suite.seal(
        descriptor: memberSecret(),
        rootKey: key,
        plaintext: plaintext,
        nonce: nonce,
      );
      expect(
        await suite.open(
          descriptor: memberSecret(),
          rootKey: key,
          payload: encrypted,
        ),
        plaintext,
      );
      await expectLater(
        suite.open(
          descriptor: memberSecret(revision: 8),
          rootKey: key,
          payload: encrypted,
        ),
        throwsA(isA<EnvelopeException>()),
      );
    },
  );

  test('wrapper context requires parent binding only for reason and grant', () {
    final reasonScope = EnvelopeScope(
      organizationId: scope.organizationId,
      vaultId: scope.vaultId,
      entryId: scope.entryId,
      grantOrRequestId: EnvelopeId.parse(
        '44444444-4444-4444-8444-444444444444',
      ),
      agentId: EnvelopeId.parse('55555555-5555-4555-8555-555555555555'),
    );
    expect(
      () => WrapperContext(
        purpose: WrapperPurpose.reasonDek,
        scope: reasonScope,
        resourceRevision: 1,
        wrappedKeyVersion: 1,
        memberKeyGeneration: 1,
        recipientKeyVersion: 1,
        recipientFingerprint: Uint8List.fromList(List.filled(32, 1)),
      ),
      throwsA(isA<EnvelopeException>()),
    );
    final context = WrapperContext(
      purpose: WrapperPurpose.reasonDek,
      scope: reasonScope,
      resourceRevision: 1,
      wrappedKeyVersion: 1,
      memberKeyGeneration: 1,
      recipientKeyVersion: 1,
      recipientFingerprint: Uint8List.fromList(List.filled(32, 1)),
      parentDescriptorHash: WrapperContext.hashParent(memberSecret()),
    );
    expect(ascii.decode(context.encode().sublist(0, 8)), 'PLDNX2W1');
  });
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String value) => Uint8List.fromList([
  for (var index = 0; index < value.length; index += 2)
    int.parse(value.substring(index, index + 2), radix: 16),
]);

EnvelopeDescriptor _fixtureGrantDescriptor() => EnvelopeDescriptor(
  purpose: EnvelopePurpose.grant,
  scope: EnvelopeScope(
    organizationId: EnvelopeId.parse('00112233-4455-6677-8899-aabbccddeeff'),
    vaultId: EnvelopeId.parse('11112222-3333-4444-8555-666677778888'),
    entryId: EnvelopeId.parse('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'),
    grantOrRequestId: EnvelopeId.parse('12345678-1234-4234-8234-1234567890ab'),
    agentId: EnvelopeId.parse('fedcba98-7654-4321-8765-abcdefabcdef'),
  ),
  resourceRevision: 7,
  keyVersion: 3,
  memberKeyGeneration: 9,
  purposeData: GrantPurposeData(
    entryRevision: 6,
    recipientKeyVersion: 4,
    recipientFingerprint: Uint8List.fromList(List.filled(32, 0x5a)),
    methods: 3,
    fieldSetCommitment: Uint8List.fromList(List.filled(32, 0xa5)),
    expiresAtSeconds: 1700000000,
    expiresAtNanoseconds: 123456789,
    remainingUses: 5,
  ),
);

WrapperContext _fixtureWrapperContext({
  int resourceRevision = 7,
}) => WrapperContext(
  purpose: WrapperPurpose.grantDek,
  scope: EnvelopeScope(
    organizationId: EnvelopeId.parse('00112233-4455-6677-8899-aabbccddeeff'),
    vaultId: EnvelopeId.parse('11112222-3333-4444-8555-666677778888'),
    entryId: EnvelopeId.parse('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'),
    grantOrRequestId: EnvelopeId.parse('12345678-1234-4234-8234-1234567890ab'),
    agentId: EnvelopeId.parse('fedcba98-7654-4321-8765-abcdefabcdef'),
  ),
  resourceRevision: resourceRevision,
  wrappedKeyVersion: 3,
  memberKeyGeneration: 9,
  recipientKeyKind: 1,
  recipientKeyVersion: 4,
  recipientFingerprint: _fromHex(
    '6ee7d311db166b64408da843b80079758357b575c322561237da2fd3b3cb75d1',
  ),
  parentDescriptorHash: _fromHex(
    '4d15139ad8889449aa2d4d50fe916ed63397c16bbe20c2c06f3d74e4368ad374',
  ),
);
