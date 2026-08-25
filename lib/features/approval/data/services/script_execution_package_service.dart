import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/asymmetric_keys.dart';
import '../../../../core/crypto/envelope/envelope_contract.dart';
import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/crypto/x25519_key_wrapper.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_signature_service.dart';
import '../../../vault/domain/entities/entry_entity.dart';
import '../../../vault/domain/entities/vault_plaintext.dart';

final class ScriptExecutionPackageEntryInput {
  const ScriptExecutionPackageEntryInput({
    required this.entryId,
    required this.entryRevision,
    required this.encodedMemberSecret,
  });

  final String entryId;
  final String entryRevision;
  final Uint8List encodedMemberSecret;
}

class ScriptExecutionPackageService {
  ScriptExecutionPackageService({Future<SodiumSumo> Function()? sodiumLoader})
    : _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  static const int contractVersion = 1;
  final Future<SodiumSumo> Function() _sodiumLoader;

  Future<Map<String, dynamic>> seal({
    required String grantId,
    required int packageRevision,
    required String agentId,
    required int agentAccessEpoch,
    required Uint8List agentPublicKey,
    required int recipientAgentKeyVersion,
    required int vaultSigningKeyVersion,
    required Uint8List vaultSigningPrivateKey,
    required Map<String, dynamic> scriptEntry,
    required Map<String, dynamic> scriptPayload,
    required List<ScriptExecutionPackageEntryInput> referencedEntries,
  }) async {
    if (packageRevision <= 0 ||
        agentAccessEpoch <= 0 ||
        recipientAgentKeyVersion <= 0 ||
        vaultSigningKeyVersion <= 0 ||
        agentPublicKey.length != 32 ||
        (vaultSigningPrivateKey.length != 32 &&
            vaultSigningPrivateKey.length != 64) ||
        referencedEntries.length > 64) {
      throw const FormatException('Invalid Script package context');
    }
    final organizationId = scriptEntry['organizationId'] as String;
    final vaultId = scriptEntry['vaultId'] as String;
    final scriptEntryId = scriptEntry['id'] as String;
    final scriptRevision = scriptEntry['currentRevision'] as String;
    final executionRaw = scriptPayload['execution'];
    if (executionRaw is! Map) {
      throw const FormatException('Missing Script execution metadata');
    }
    final execution = ScriptExecutionMetadata.fromJson(
      Map<String, dynamic>.from(executionRaw),
    );
    final refs = ScriptRef.listFromPayload(scriptPayload);
    _validateReferences(refs, vaultId, scriptEntryId);

    final snapshotsById = <String, ScriptExecutionPackageEntryInput>{
      for (final entry in referencedEntries) entry.entryId: entry,
    };
    if (snapshotsById.length != referencedEntries.length ||
        refs.any((ref) => !snapshotsById.containsKey(ref.entryId)) ||
        snapshotsById.keys.any(
          (id) => refs.every((reference) => reference.entryId != id),
        )) {
      throw const FormatException('Incomplete Script package references');
    }

    final manifestReferences =
        refs.map((ref) {
          final target = snapshotsById[ref.entryId]!;
          return <String, Object?>{
            'env': ref.env,
            'vaultId': vaultId,
            'entryId': ref.entryId,
            'fieldId': ref.field,
            'entryRevision': target.entryRevision,
          };
        }).toList()..sort(
          (left, right) => _referenceKey(left).compareTo(_referenceKey(right)),
        );
    final parameters =
        execution.parameters
            .map((value) => <String, Object?>{...value.toJson()})
            .toList()
          ..sort(
            (left, right) =>
                (left['name'] as String).compareTo(right['name'] as String),
          );
    final manifest = <String, Object?>{
      'schema': 'palladin.script-execution-manifest.v1',
      'contractVersion': contractVersion,
      'organizationId': organizationId,
      'agentId': agentId,
      'agentAccessEpoch': agentAccessEpoch,
      'vaultId': vaultId,
      'scriptEntryId': scriptEntryId,
      'scriptRevision': scriptRevision,
      'description': execution.description.trim(),
      'parameters': parameters,
      'returnResultToAgent': execution.returnResultToAgent,
      'interpreter': scriptPayload['interpreter'] as String,
      'scriptSource': scriptPayload['script'] as String,
      'references': manifestReferences,
    };

    Uint8List? manifestBytes;
    Uint8List? digestInput;
    Uint8List? fingerprint;
    Uint8List? vaultSigningPublicKey;
    Uint8List? normalizedVaultSigningPrivateKey;
    Uint8List? vaultSigningFingerprint;
    Uint8List? aad;
    Uint8List? parentHashInput;
    Uint8List? parentHash;
    Uint8List? plaintext;
    Uint8List? packageDek;
    Uint8List? nonce;
    Uint8List? suitePayload;
    Uint8List? sealedDek;
    Uint8List? containerBytes;
    final projectedPayloads = <Uint8List>[];
    try {
      manifestBytes = canonicalVaultJson(manifest);
      digestInput = Uint8List.fromList([
        ...ascii.encode('PLDNSCRIPT1'),
        ...manifestBytes,
      ]);
      final manifestDigest = _b64(sha256.convert(digestInput).bytes);
      final scopes = <Map<String, Object?>>[
        {
          'vaultId': vaultId,
          'entryId': scriptEntryId,
          'fieldId': 'script.source',
          'entryRevision': scriptRevision,
        },
        ...manifestReferences.map(
          (ref) => <String, Object?>{
            'vaultId': ref['vaultId'],
            'entryId': ref['entryId'],
            'fieldId': ref['fieldId'],
            'entryRevision': ref['entryRevision'],
          },
        ),
      ]..sort((left, right) => _scopeKey(left).compareTo(_scopeKey(right)));
      final binding = <String, Object?>{
        'schema': 'palladin.script-execution-package-binding.v1',
        'contractVersion': contractVersion,
        'organizationId': organizationId,
        'agentId': agentId,
        'agentAccessEpoch': agentAccessEpoch,
        'vaultId': vaultId,
        'scriptEntryId': scriptEntryId,
        'scriptRevision': scriptRevision,
        'manifestDigest': manifestDigest,
        'authorization': {'source': 'scriptExecution', 'grantId': grantId},
        'scopes': scopes,
      };
      final transportScopesById = <String, Map<String, Object?>>{};
      for (final scope in scopes) {
        final entryId = scope['entryId'] as String;
        final candidate = <String, Object?>{
          'entryId': entryId,
          'entryRevision': scope['entryRevision'],
          'isScript': entryId == scriptEntryId,
        };
        final current = transportScopesById[entryId];
        if (current != null &&
            current['entryRevision'] != candidate['entryRevision']) {
          throw const FormatException('Conflicting Script scope revisions');
        }
        transportScopesById[entryId] = candidate;
      }
      final transportScopes = transportScopesById.values.toList()
        ..sort(
          (left, right) =>
              (left['entryId'] as String).compareTo(right['entryId'] as String),
        );
      fingerprint = vaultPublicKeyFingerprint(
        VaultPublicKeyKind.agentX25519,
        agentPublicKey,
      );
      final sodium = await _sodiumLoader();
      final signing = _normalizeSigningKey(sodium, vaultSigningPrivateKey);
      vaultSigningPublicKey = signing.publicKey;
      normalizedVaultSigningPrivateKey = signing.privateKey;
      vaultSigningFingerprint = vaultPublicKeyFingerprint(
        VaultPublicKeyKind.vaultSigningEd25519,
        vaultSigningPublicKey,
      );
      final transport = <String, Object?>{
        'contractVersion': contractVersion,
        'organizationId': organizationId,
        'vaultId': vaultId,
        'grantId': grantId,
        'agentId': agentId,
        'agentAccessEpoch': agentAccessEpoch,
        'scriptEntryId': scriptEntryId,
        'scriptRevision': scriptRevision,
        'packageRevision': packageRevision.toString(),
        'recipientAgentKeyVersion': recipientAgentKeyVersion,
        'recipientAgentKeyFingerprint': _b64(fingerprint),
        'vaultSigningKeyVersion': vaultSigningKeyVersion,
        'vaultSigningKeyFingerprint': _b64(vaultSigningFingerprint),
        'manifestDigest': manifestDigest,
        'scopes': transportScopes,
      };
      final entries = <Map<String, Object?>>[];
      final sortedEntries = [...referencedEntries]
        ..sort((left, right) => left.entryId.compareTo(right.entryId));
      final fieldIdsByEntry = <String, Set<String>>{};
      for (final ref in refs) {
        fieldIdsByEntry
            .putIfAbsent(ref.entryId, () => <String>{})
            .add(ref.field);
      }
      for (final entry in sortedEntries) {
        final decoded = jsonDecode(utf8.decode(entry.encodedMemberSecret));
        if (decoded is! Map) {
          throw const FormatException('Referenced MemberSecret is invalid');
        }
        final fieldIds = fieldIdsByEntry[entry.entryId];
        if (fieldIds == null) {
          throw const FormatException('Referenced field projection is missing');
        }
        final projection = VaultPlaintextProjector.grantPayloadFromJson(
          Map<String, dynamic>.from(decoded),
          fieldIds,
        );
        final encodedProjection = canonicalVaultJson(projection);
        projectedPayloads.add(encodedProjection);
        entries.add({
          'entryId': entry.entryId,
          'entryRevision': entry.entryRevision,
          'encodedGrantPayload': _b64(encodedProjection),
        });
      }
      plaintext = canonicalVaultJson({
        'schema': 'palladin.script-execution-package-payload.v1',
        'binding': binding,
        'manifest': manifest,
        'entries': entries,
      });
      if (plaintext.length > 1024 * 1024 - 40) {
        throw const FormatException('Script package exceeds plaintext limit');
      }
      aad = canonicalVaultJson(transport);
      parentHashInput = Uint8List.fromList([
        ...ascii.encode('PLDNSCRIPTAAD1'),
        ...aad,
      ]);
      parentHash = Uint8List.fromList(sha256.convert(parentHashInput).bytes);
      packageDek = sodium.randombytes.buf(32);
      nonce = sodium.randombytes.buf(24);
      final key = SecureKey.fromList(sodium, packageDek);
      try {
        final ciphertext = sodium.crypto.aeadXChaCha20Poly1305IETF.encrypt(
          message: plaintext,
          nonce: nonce,
          key: key,
          additionalData: aad,
        );
        suitePayload = Uint8List.fromList([...nonce, ...ciphertext]);
      } finally {
        key.dispose();
      }
      final wrapper = WrapperContext(
        purpose: WrapperPurpose.scriptExecutionDek,
        scope: EnvelopeScope(
          organizationId: EnvelopeId.parse(organizationId),
          vaultId: EnvelopeId.parse(vaultId),
          entryId: EnvelopeId.parse(scriptEntryId),
          grantOrRequestId: EnvelopeId.parse(grantId),
          agentId: EnvelopeId.parse(agentId),
        ),
        resourceRevision: packageRevision,
        wrappedKeyVersion: 1,
        recipientKeyVersion: recipientAgentKeyVersion,
        recipientFingerprint: fingerprint,
        parentDescriptorHash: parentHash,
      );
      sealedDek = await X25519SealedBoxKeyWrapper(sodiumLoader: _sodiumLoader)
          .seal(
            key: packageDek,
            context: wrapper,
            recipient: X25519PublicKey(agentPublicKey),
          );
      containerBytes = canonicalVaultJson({
        'schema': 'palladin.script-execution-package-ciphertext.v1',
        'contractVersion': contractVersion,
        'packageRevision': packageRevision.toString(),
        'encodedSealedPackageDek': _b64(sealedDek),
        'encodedSuitePayload': _b64(suitePayload),
      });
      if (containerBytes.length > 2 * 1024 * 1024) {
        throw const FormatException('Script package exceeds transport limit');
      }
      final unsignedPackage = <String, Object?>{
        ...transport,
        'encodedPackageCiphertext': _b64(containerBytes),
      };
      final producerSignature =
          await VaultProtocolSignatureService(sodiumLoader: _sodiumLoader).sign(
            domainPrefix: 'PLDNV2SIG:SCRIPT-EXECUTION-PACKAGE:',
            unsignedObject: unsignedPackage,
            privateKey: normalizedVaultSigningPrivateKey,
          );
      return <String, dynamic>{
        ...unsignedPackage,
        'producerSignature': producerSignature,
      };
    } finally {
      for (final bytes in [
        manifestBytes,
        digestInput,
        fingerprint,
        vaultSigningPublicKey,
        normalizedVaultSigningPrivateKey,
        vaultSigningFingerprint,
        aad,
        parentHashInput,
        parentHash,
        plaintext,
        packageDek,
        nonce,
        suitePayload,
        sealedDek,
        containerBytes,
      ]) {
        bytes?.fillRange(0, bytes.length, 0);
      }
      for (final bytes in projectedPayloads) {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
  }

  void _validateReferences(
    List<ScriptRef> refs,
    String vaultId,
    String scriptEntryId,
  ) {
    if (refs.length > 64) {
      throw const FormatException('Too many Script references');
    }
    final names = <String>{};
    for (final ref in refs) {
      if (ref.vaultId != vaultId ||
          ref.entryId == scriptEntryId ||
          !isScriptReferenceFieldId(ref.field) ||
          !isAllowedScriptReferenceEnvironment(ref.env) ||
          !names.add(ref.env.toUpperCase())) {
        throw const FormatException('Invalid Script reference');
      }
    }
  }

  String _referenceKey(Map<String, Object?> value) =>
      '${value['env']}\u0000${value['entryId']}\u0000${value['fieldId']}';

  String _scopeKey(Map<String, Object?> value) =>
      '${value['vaultId']}\u0000${value['entryId']}\u0000${value['fieldId']}\u0000${value['entryRevision']}';

  String _b64(List<int> value) => base64UrlEncode(value).replaceAll('=', '');

  ({Uint8List publicKey, Uint8List privateKey}) _normalizeSigningKey(
    SodiumSumo sodium,
    Uint8List value,
  ) {
    if (value.length == sodium.crypto.sign.seedBytes) {
      final seed = SecureKey.fromList(sodium, value);
      try {
        final pair = sodium.crypto.sign.seedKeyPair(seed);
        try {
          return (
            publicKey: Uint8List.fromList(pair.publicKey),
            privateKey: Uint8List.fromList(pair.secretKey.extractBytes()),
          );
        } finally {
          pair.secretKey.dispose();
        }
      } finally {
        seed.dispose();
      }
    }
    if (value.length != sodium.crypto.sign.secretKeyBytes) {
      throw const FormatException('Vault signing key length is invalid');
    }
    final secretKey = SecureKey.fromList(sodium, value);
    try {
      return (
        publicKey: Uint8List.fromList(sodium.crypto.sign.skToPk(secretKey)),
        privateKey: Uint8List.fromList(value),
      );
    } finally {
      secretKey.dispose();
    }
  }
}
