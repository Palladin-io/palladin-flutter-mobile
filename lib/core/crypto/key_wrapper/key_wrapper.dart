import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sodium/sodium_sumo.dart';

import '../kem/xwing.dart';
import '../sodium_provider.dart';

/// Build-time copy of palladin-protocol `contracts/key-wrapper/v1`.
///
/// There is no runtime registration or negotiation: a suite is usable only
/// when it is listed here, and its lifecycle decides whether it may seal.
enum WrapperSuite {
  xwingV1('palladin-xwing-v1', WrapperSuiteStatus.active, 1216, 1168),
  x25519SealedBoxV1(
    'palladin-x25519-sealed-box-v1',
    WrapperSuiteStatus.readOnly,
    32,
    120,
  );

  const WrapperSuite(
    this.wireValue,
    this.status,
    this.publicKeyBytes,
    this.packageBytes,
  );

  final String wireValue;
  final WrapperSuiteStatus status;
  final int publicKeyBytes;
  final int packageBytes;

  /// Suite of every member key at Identity security version 2
  /// (`identity-kdf/v3` `accountKeys.memberEncryptionKeySuite`).
  static const memberKeySuite = WrapperSuite.xwingV1;

  /// The only suite new recipient keys are created on and sealed with.
  static const active = WrapperSuite.xwingV1;

  bool get canSeal => status == WrapperSuiteStatus.active;

  static WrapperSuite? tryParse(Object? value) {
    for (final suite in values) {
      if (suite.wireValue == value) return suite;
    }
    return null;
  }

  static WrapperSuite parse(Object? value) =>
      tryParse(value) ??
      (throw const KeyWrapperException(KeyWrapperError.unsupportedSuite));
}

enum WrapperSuiteStatus { active, readOnly }

/// Registered recipient key kinds; signing kinds are never recipients.
enum RecipientKeyKind {
  agentEncryption(1),
  vaultAgentMessage(4),
  memberEncryption(5),
  organizationApproverMessage(6);

  const RecipientKeyKind(this.id);
  final int id;

  static RecipientKeyKind? tryParse(Object? value) {
    for (final kind in values) {
      if (kind.id == value || kind.name == value) return kind;
    }
    return null;
  }
}

/// Closed wrapper purposes with the registry's scope and field rules.
enum KeyWrapperPurpose {
  memberVaultKey(
    1,
    35,
    [RecipientKeyKind.memberEncryption],
    _Rule.required,
    _Rule.forbidden,
  ),
  agentVaultDiscoveryKey(
    2,
    19,
    [RecipientKeyKind.agentEncryption],
    _Rule.optional,
    _Rule.forbidden,
  ),
  reasonDek(
    3,
    31,
    [RecipientKeyKind.vaultAgentMessage],
    _Rule.optional,
    _Rule.required,
  ),
  grantDek(
    4,
    31,
    [RecipientKeyKind.agentEncryption],
    _Rule.optional,
    _Rule.required,
  ),
  agentVaultKey(
    5,
    27,
    [RecipientKeyKind.agentEncryption],
    _Rule.forbidden,
    _Rule.forbidden,
  ),
  scriptExecutionDek(
    6,
    31,
    [RecipientKeyKind.agentEncryption],
    _Rule.forbidden,
    _Rule.required,
  ),
  submissionDek(
    7,
    25,
    [
      RecipientKeyKind.agentEncryption,
      RecipientKeyKind.organizationApproverMessage,
    ],
    _Rule.forbidden,
    _Rule.required,
  ),
  approverMessagePrivateKey(
    8,
    33,
    [RecipientKeyKind.memberEncryption],
    _Rule.forbidden,
    _Rule.forbidden,
  ),
  approverSigningPrivateKey(
    9,
    33,
    [RecipientKeyKind.memberEncryption],
    _Rule.forbidden,
    _Rule.forbidden,
  );

  const KeyWrapperPurpose(
    this.id,
    this.scopeBitmap,
    this.recipientKeyKinds,
    this._memberKeyGeneration,
    this._parentDescriptorHash,
  );

  final int id;
  final int scopeBitmap;
  final List<RecipientKeyKind> recipientKeyKinds;
  final _Rule _memberKeyGeneration;
  final _Rule _parentDescriptorHash;

  static KeyWrapperPurpose? tryParse(Object? value) {
    for (final purpose in values) {
      if (purpose.id == value) return purpose;
    }
    return null;
  }
}

enum _Rule { required, optional, forbidden }

/// Registry error codes; tests assert them against the shared vectors.
enum KeyWrapperError {
  unsupportedSuite('unsupported-suite'),
  suiteNotAllowedForPurpose('suite-not-allowed-for-purpose'),
  suiteNotWritable('suite-not-writable'),
  unsupportedPurpose('unsupported-purpose'),
  malformedDescriptor('malformed-descriptor'),
  malformedPackage('malformed-package'),
  recipientMismatch('recipient-mismatch'),
  openFailed('open-failed');

  const KeyWrapperError(this.code);
  final String code;
}

class KeyWrapperException implements Exception {
  const KeyWrapperException(this.error);
  final KeyWrapperError error;

  @override
  String toString() => 'KeyWrapperException(${error.code})';
}

/// The recipient's published key is on a read-only suite, so nothing new may
/// be sealed to it until its owner rotates (`key-migration-pending`).
class KeyMigrationPendingException implements Exception {
  const KeyMigrationPendingException();

  @override
  String toString() => 'KeyMigrationPendingException(key-migration-pending)';
}

/// Recipient key taken from an authenticated key directory, never from the
/// envelope being opened.
final class RecipientPublicKey {
  RecipientPublicKey({
    required this.suite,
    required this.keyKind,
    required this.keyVersion,
    required List<int> publicKey,
  }) : _publicKey = Uint8List.fromList(publicKey);

  final WrapperSuite suite;
  final RecipientKeyKind keyKind;
  final int keyVersion;
  final Uint8List _publicKey;
  Uint8List get publicKey => Uint8List.fromList(_publicKey);

  /// Suite fingerprint of this key as bound into wrapper descriptors.
  Uint8List fingerprint({int protocolVersion = 2}) =>
      recipientFingerprint(suite, keyKind.id, _publicKey, protocolVersion);
}

/// Computes the registered suite fingerprint over an authenticated key.
Uint8List recipientFingerprint(
  WrapperSuite suite,
  int keyKind,
  List<int> publicKey, [
  int protocolVersion = 2,
]) {
  if (publicKey.length != suite.publicKeyBytes) {
    throw const KeyWrapperException(KeyWrapperError.recipientMismatch);
  }
  final builder = BytesBuilder(copy: false)
    ..add(ascii.encode('PLDNV2FP'))
    ..add(_u16(protocolVersion))
    ..add(_u16(keyKind));
  if (suite != WrapperSuite.x25519SealedBoxV1) {
    builder
      ..add(_u16(suite.wireValue.length))
      ..add(ascii.encode(suite.wireValue));
  }
  builder.add(publicKey);
  return Uint8List.fromList(sha256.convert(builder.takeBytes()).bytes);
}

/// Exact `key-wrapper/v1` descriptor, validated against its purpose.
final class KeyWrapperDescriptor {
  const KeyWrapperDescriptor({
    this.protocolVersion = 2,
    required this.wrapperSuiteId,
    required this.purpose,
    required this.scope,
    required this.resourceRevision,
    required this.wrappedKeyVersion,
    this.memberKeyGeneration,
    required this.recipientKeyKind,
    required this.recipientKeyVersion,
    required this.recipientFingerprint,
    this.parentDescriptorHash,
    this.hasUnknownFields = false,
  });

  final Object? protocolVersion;
  final Object? wrapperSuiteId;
  final Object? purpose;
  final Object? scope;
  final Object? resourceRevision;
  final Object? wrappedKeyVersion;
  final Object? memberKeyGeneration;
  final Object? recipientKeyKind;
  final Object? recipientKeyVersion;
  final Object? recipientFingerprint;
  final Object? parentDescriptorHash;
  final bool hasUnknownFields;

  static const _fields = {
    'protocolVersion',
    'wrapperSuiteId',
    'purpose',
    'scope',
    'resourceRevision',
    'wrappedKeyVersion',
    'memberKeyGeneration',
    'recipientKeyKind',
    'recipientKeyVersion',
    'recipientFingerprint',
    'parentDescriptorHash',
  };

  factory KeyWrapperDescriptor.fromJson(Map<String, dynamic> json) =>
      KeyWrapperDescriptor(
        protocolVersion: json['protocolVersion'],
        wrapperSuiteId: json['wrapperSuiteId'],
        purpose: json['purpose'],
        scope: json['scope'],
        resourceRevision: json['resourceRevision'],
        wrappedKeyVersion: json['wrappedKeyVersion'],
        memberKeyGeneration: json['memberKeyGeneration'],
        recipientKeyKind: json['recipientKeyKind'],
        recipientKeyVersion: json['recipientKeyVersion'],
        recipientFingerprint: json['recipientFingerprint'],
        parentDescriptorHash: json['parentDescriptorHash'],
        hasUnknownFields: json.keys.any((key) => !_fields.contains(key)),
      );

  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'wrapperSuiteId': wrapperSuiteId,
    'purpose': purpose,
    'scope': scope,
    'resourceRevision': resourceRevision,
    'wrappedKeyVersion': wrappedKeyVersion,
    if (memberKeyGeneration != null) 'memberKeyGeneration': memberKeyGeneration,
    'recipientKeyKind': recipientKeyKind,
    'recipientKeyVersion': recipientKeyVersion,
    'recipientFingerprint': recipientFingerprint,
    if (parentDescriptorHash != null)
      'parentDescriptorHash': parentDescriptorHash,
  };
}

/// Algorithm-neutral seal/open of a 32-byte key for a recipient public key.
class KeyWrapper {
  KeyWrapper({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final Future<SodiumSumo> Function() _sodiumLoader;

  static const _scopeOrder = [
    ('organizationId', 1),
    ('vaultId', 2),
    ('entryId', 4),
    ('grantOrRequestId', 8),
    ('agentId', 16),
    ('memberId', 32),
  ];
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  /// Seals [key] and returns the unpadded base64url package.
  Future<String> seal({
    required KeyWrapperDescriptor descriptor,
    required Uint8List key,
    required RecipientPublicKey recipient,
  }) => _seal(descriptor, key, recipient, null);

  @visibleForTesting
  Future<String> sealDerandomized({
    required KeyWrapperDescriptor descriptor,
    required Uint8List key,
    required RecipientPublicKey recipient,
    required Uint8List encapsulationRandomness,
  }) => _seal(descriptor, key, recipient, encapsulationRandomness);

  /// Opens a package; [descriptor] and [recipient] must come from
  /// authenticated state, never from the package being opened.
  Future<Uint8List> open({
    required KeyWrapperDescriptor descriptor,
    required String encodedPackage,
    required RecipientPublicKey recipient,
    required Uint8List recipientPrivateKey,
  }) async {
    final (suite, purpose) = _resolve(descriptor, seal: false);
    final context = _validate(descriptor, purpose);
    _bindRecipient(suite, context, recipient);
    final package = _decodePackage(encodedPackage, suite);
    final hash = _contextHash(context.encode());
    final sodium = await _sodiumLoader();
    try {
      return switch (suite) {
        WrapperSuite.xwingV1 => _openXWing(
          sodium,
          package,
          recipient.publicKey,
          recipientPrivateKey,
          hash,
        ),
        WrapperSuite.x25519SealedBoxV1 => _openSealedBox(
          sodium,
          package,
          recipient.publicKey,
          recipientPrivateKey,
          hash,
        ),
      };
    } finally {
      package.fillRange(0, package.length, 0);
      hash.fillRange(0, hash.length, 0);
    }
  }

  /// Canonical `PLDNX2W1` context bytes, exposed for contract vectors.
  Uint8List encodeContext(KeyWrapperDescriptor descriptor) {
    final (_, purpose) = _resolve(descriptor, seal: false);
    return _validate(descriptor, purpose).encode();
  }

  Future<String> _seal(
    KeyWrapperDescriptor descriptor,
    Uint8List key,
    RecipientPublicKey recipient,
    Uint8List? randomness,
  ) async {
    final (suite, purpose) = _resolve(descriptor, seal: true);
    final context = _validate(descriptor, purpose);
    _bindRecipient(suite, context, recipient);
    if (key.length != 32) {
      throw const KeyWrapperException(KeyWrapperError.malformedDescriptor);
    }
    final sodium = await _sodiumLoader();
    final hash = _contextHash(context.encode());
    final publicKey = recipient.publicKey;
    final xwing = XWing(sodium);
    final (sharedSecret, kemCiphertext) = randomness == null
        ? xwing.encapsulate(publicKey)
        : xwing.encapsulateDerandomized(publicKey, randomness);
    final aeadKey = _xwingAeadKey(sharedSecret, hash, publicKey, kemCiphertext);
    final secureKey = SecureKey.fromList(sodium, aeadKey);
    try {
      final ciphertext = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
        message: key,
        nonce: Uint8List(24),
        key: secureKey,
        additionalData: _xwingAad(hash),
      );
      return _b64(Uint8List.fromList([...kemCiphertext, ...ciphertext]));
    } finally {
      secureKey.dispose();
      sharedSecret.fillRange(0, sharedSecret.length, 0);
      aeadKey.fillRange(0, aeadKey.length, 0);
      hash.fillRange(0, hash.length, 0);
    }
  }

  (WrapperSuite, KeyWrapperPurpose) _resolve(
    KeyWrapperDescriptor descriptor, {
    required bool seal,
  }) {
    final suite = WrapperSuite.parse(descriptor.wrapperSuiteId);
    if (seal && !suite.canSeal) {
      throw const KeyWrapperException(KeyWrapperError.suiteNotWritable);
    }
    final purpose = KeyWrapperPurpose.tryParse(descriptor.purpose);
    if (purpose == null) {
      throw const KeyWrapperException(KeyWrapperError.unsupportedPurpose);
    }
    // Both registered suites serve every purpose (registry v1).
    return (suite, purpose);
  }

  _Context _validate(KeyWrapperDescriptor d, KeyWrapperPurpose purpose) {
    Never malformed() =>
        throw const KeyWrapperException(KeyWrapperError.malformedDescriptor);
    if (d.hasUnknownFields || d.protocolVersion != 2) malformed();
    final scope = d.scope;
    if (scope is! Map) malformed();
    final known = {for (final (field, _) in _scopeOrder) field};
    if (scope.keys.any((key) => !known.contains(key))) malformed();
    final ids = <Uint8List>[];
    for (final (field, bit) in _scopeOrder) {
      final value = scope[field];
      final required = purpose.scopeBitmap & bit != 0;
      if (required != (value != null)) malformed();
      if (!required) continue;
      if (value is! String || !_uuid.hasMatch(value)) malformed();
      ids.add(_uuidBytes(value));
    }
    final revision = d.resourceRevision;
    if (revision is! String ||
        !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(revision)) {
      malformed();
    }
    final revisionValue = BigInt.parse(revision);
    if (revisionValue > BigInt.parse('18446744073709551615')) malformed();
    if (!_positiveU32(d.wrappedKeyVersion) ||
        !_positiveU32(d.recipientKeyVersion)) {
      malformed();
    }
    final generation = d.memberKeyGeneration;
    final hasGeneration = generation != null;
    if ((purpose._memberKeyGeneration == _Rule.required && !hasGeneration) ||
        (purpose._memberKeyGeneration == _Rule.forbidden && hasGeneration) ||
        (hasGeneration && !_positiveU32(generation))) {
      malformed();
    }
    final hasParent = d.parentDescriptorHash != null;
    if ((purpose._parentDescriptorHash == _Rule.required) != hasParent) {
      malformed();
    }
    final kind = RecipientKeyKind.tryParse(d.recipientKeyKind);
    if (kind == null || !purpose.recipientKeyKinds.contains(kind)) malformed();
    return _Context(
      suiteId: d.wrapperSuiteId! as String,
      purpose: purpose,
      scopeIds: ids,
      resourceRevision: revisionValue,
      wrappedKeyVersion: d.wrappedKeyVersion! as int,
      memberKeyGeneration: generation as int?,
      recipientKeyKind: kind,
      recipientKeyVersion: d.recipientKeyVersion! as int,
      recipientFingerprint: _decodeExact(d.recipientFingerprint, 32),
      parentDescriptorHash: hasParent
          ? _decodeExact(d.parentDescriptorHash, 32)
          : null,
    );
  }

  void _bindRecipient(
    WrapperSuite suite,
    _Context context,
    RecipientPublicKey recipient,
  ) {
    if (recipient.suite != suite ||
        recipient.keyKind != context.recipientKeyKind ||
        recipient.keyVersion != context.recipientKeyVersion ||
        !_constantTimeEqual(
          recipient.fingerprint(),
          context.recipientFingerprint,
        )) {
      throw const KeyWrapperException(KeyWrapperError.recipientMismatch);
    }
  }

  Uint8List _decodePackage(String encoded, WrapperSuite suite) {
    if (!RegExp(r'^[A-Za-z0-9_-]*$').hasMatch(encoded)) {
      throw const KeyWrapperException(KeyWrapperError.malformedPackage);
    }
    final Uint8List bytes;
    try {
      bytes = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(encoded)),
      );
    } on FormatException {
      throw const KeyWrapperException(KeyWrapperError.malformedPackage);
    }
    if (_b64(bytes) != encoded || bytes.length != suite.packageBytes) {
      throw const KeyWrapperException(KeyWrapperError.malformedPackage);
    }
    return bytes;
  }

  Uint8List _openXWing(
    SodiumSumo sodium,
    Uint8List package,
    Uint8List publicKey,
    Uint8List privateKey,
    Uint8List hash,
  ) {
    if (privateKey.length != XWing.seedBytes) {
      throw const KeyWrapperException(KeyWrapperError.recipientMismatch);
    }
    final kemCiphertext = Uint8List.sublistView(
      package,
      0,
      XWing.ciphertextBytes,
    );
    final sharedSecret = XWing(sodium).decapsulate(kemCiphertext, privateKey);
    final aeadKey = _xwingAeadKey(sharedSecret, hash, publicKey, kemCiphertext);
    final secureKey = SecureKey.fromList(sodium, aeadKey);
    try {
      return sodium.crypto.aeadXChaCha20Poly1305IETF.decrypt(
        cipherText: Uint8List.sublistView(package, XWing.ciphertextBytes),
        nonce: Uint8List(24),
        key: secureKey,
        additionalData: _xwingAad(hash),
      );
    } on SodiumException {
      throw const KeyWrapperException(KeyWrapperError.openFailed);
    } finally {
      secureKey.dispose();
      sharedSecret.fillRange(0, sharedSecret.length, 0);
      aeadKey.fillRange(0, aeadKey.length, 0);
    }
  }

  Uint8List _openSealedBox(
    SodiumSumo sodium,
    Uint8List package,
    Uint8List publicKey,
    Uint8List privateKey,
    Uint8List hash,
  ) {
    if (privateKey.length != 32) {
      throw const KeyWrapperException(KeyWrapperError.recipientMismatch);
    }
    final secret = SecureKey.fromList(sodium, privateKey);
    Uint8List? opened;
    try {
      try {
        opened = sodium.crypto.box.sealOpen(
          cipherText: package,
          publicKey: publicKey,
          secretKey: secret,
        );
      } on SodiumException {
        throw const KeyWrapperException(KeyWrapperError.openFailed);
      }
      if (opened.length != 72 ||
          !_constantTimeEqual(opened.sublist(0, 8), ascii.encode('PLDNX2K1')) ||
          !_constantTimeEqual(opened.sublist(40), hash)) {
        throw const KeyWrapperException(KeyWrapperError.openFailed);
      }
      return Uint8List.fromList(opened.sublist(8, 40));
    } finally {
      opened?.fillRange(0, opened.length, 0);
      secret.dispose();
    }
  }

  static Uint8List _xwingAeadKey(
    Uint8List sharedSecret,
    Uint8List contextHash,
    Uint8List publicKey,
    Uint8List kemCiphertext,
  ) => hkdfSha256(
    ikm: sharedSecret,
    salt: Uint8List(0),
    info: Uint8List.fromList([
      ...ascii.encode('PLDNXW1KEY'),
      ...contextHash,
      ...sha256.convert(publicKey).bytes,
      ...sha256.convert(kemCiphertext).bytes,
    ]),
  );

  static Uint8List _xwingAad(Uint8List hash) =>
      Uint8List.fromList([...ascii.encode('PLDNXW1AAD'), ...hash]);

  static Uint8List _contextHash(Uint8List encoded) => Uint8List.fromList(
    sha256.convert([...ascii.encode('PLDNX2CTX'), ...encoded]).bytes,
  );

  static bool _positiveU32(Object? value) =>
      value is int && value > 0 && value <= 0xffffffff;

  static Uint8List _decodeExact(Object? value, int length) {
    if (value is! String || !RegExp(r'^[A-Za-z0-9_-]*$').hasMatch(value)) {
      throw const KeyWrapperException(KeyWrapperError.malformedDescriptor);
    }
    try {
      final bytes = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(value)),
      );
      if (bytes.length == length && _b64(bytes) == value) return bytes;
    } on FormatException {
      // Falls through to the typed contract error.
    }
    throw const KeyWrapperException(KeyWrapperError.malformedDescriptor);
  }
}

final class _Context {
  _Context({
    required this.suiteId,
    required this.purpose,
    required this.scopeIds,
    required this.resourceRevision,
    required this.wrappedKeyVersion,
    required this.memberKeyGeneration,
    required this.recipientKeyKind,
    required this.recipientKeyVersion,
    required this.recipientFingerprint,
    required this.parentDescriptorHash,
  });

  final String suiteId;
  final KeyWrapperPurpose purpose;
  final List<Uint8List> scopeIds;
  final BigInt resourceRevision;
  final int wrappedKeyVersion;
  final int? memberKeyGeneration;
  final RecipientKeyKind recipientKeyKind;
  final int recipientKeyVersion;
  final Uint8List recipientFingerprint;
  final Uint8List? parentDescriptorHash;

  Uint8List encode() {
    final revision = ByteData(8)
      ..setUint32(0, (resourceRevision >> 32).toInt())
      ..setUint32(4, (resourceRevision & BigInt.from(0xffffffff)).toInt());
    final builder = BytesBuilder(copy: false)
      ..add(ascii.encode('PLDNX2W1'))
      ..add(_u16(2))
      ..add(_u16(suiteId.length))
      ..add(ascii.encode(suiteId))
      ..add(_u16(purpose.id))
      ..add(_u16(purpose.scopeBitmap));
    scopeIds.forEach(builder.add);
    builder
      ..add(revision.buffer.asUint8List())
      ..add(_u32(wrappedKeyVersion))
      ..addByte(memberKeyGeneration == null ? 0 : 1);
    if (memberKeyGeneration != null) builder.add(_u32(memberKeyGeneration!));
    builder
      ..add(_u16(recipientKeyKind.id))
      ..add(_u32(recipientKeyVersion))
      ..add(recipientFingerprint)
      ..addByte(parentDescriptorHash == null ? 0 : 1);
    if (parentDescriptorHash != null) builder.add(parentDescriptorHash!);
    return builder.takeBytes();
  }
}

/// RFC 5869 HKDF-SHA-256 with a single 32-byte output block.
Uint8List hkdfSha256({
  required Uint8List ikm,
  required Uint8List salt,
  required Uint8List info,
}) {
  final prk = Uint8List.fromList(
    Hmac(sha256, salt.isEmpty ? Uint8List(32) : salt).convert(ikm).bytes,
  );
  try {
    return Uint8List.fromList(Hmac(sha256, prk).convert([...info, 1]).bytes);
  } finally {
    prk.fillRange(0, prk.length, 0);
  }
}

bool _constantTimeEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

Uint8List _uuidBytes(String value) {
  final hex = value.replaceAll('-', '');
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _u16(int value) =>
    (ByteData(2)..setUint16(0, value)).buffer.asUint8List();

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

/// Public key of the member's own key pair under [suite], derived locally so
/// no envelope or response can choose it.
Uint8List memberPublicKeyFromPrivate(
  SodiumSumo sodium,
  Uint8List privateKey, {
  WrapperSuite suite = WrapperSuite.memberKeySuite,
}) {
  switch (suite) {
    case WrapperSuite.xwingV1:
      return XWing(sodium).publicKeyFromSeed(privateKey);
    case WrapperSuite.x25519SealedBoxV1:
      final secret = SecureKey.fromList(sodium, privateKey);
      try {
        return sodium.crypto.scalarmult.base(n: secret);
      } finally {
        secret.dispose();
      }
  }
}
