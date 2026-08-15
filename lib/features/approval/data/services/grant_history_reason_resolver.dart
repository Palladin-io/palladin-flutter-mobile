import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../grants/data/models/grant_model.dart';
import '../../../grants/data/services/grant_reason_resolver.dart';
import '../../../grants/domain/entities/grant_method.dart';
import '../../../vault/data/datasources/agent_discovery_remote_datasource.dart';
import '../../../vault/data/datasources/vault_remote_datasource.dart';
import '../../../vault/data/models/agent_discovery_provisioning.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_bytes.dart';
import '../../../vault/data/services/vault_protocol/vault_protocol_fingerprint.dart';
import '../../../vault/data/services/vault_rotation_crypto_service.dart';
import '../../domain/entities/encrypted_reason.dart';
import '../models/encrypted_reason_model.dart';
import 'encrypted_reason_crypto_service.dart';

/// Zero-knowledge implementation backed by the authenticated Vault protocol.
final class LocalGrantReasonResolver implements GrantReasonResolver {
  LocalGrantReasonResolver({
    required VaultRemoteDatasource vaults,
    required VaultRotationCryptoService keys,
    required AgentDiscoveryRemote discovery,
    EncryptedReasonCrypto? reasonCrypto,
    Future<String> Function(Uint8List privateKey)? messageKeyFingerprint,
  }) : _vaults = vaults,
       _keys = keys,
       _discovery = discovery,
       _reasonCrypto = reasonCrypto ?? EncryptedReasonCryptoService(),
       _messageKeyFingerprint =
           messageKeyFingerprint ?? _deriveMessageKeyFingerprint;

  final VaultRemoteDatasource _vaults;
  final VaultRotationCryptoService _keys;
  final AgentDiscoveryRemote _discovery;
  final EncryptedReasonCrypto _reasonCrypto;
  final Future<String> Function(Uint8List privateKey) _messageKeyFingerprint;

  @override
  Future<Map<String, String>> resolve({
    required List<GrantModel> grants,
    required Uint8List memberPrivateKey,
  }) async {
    final contexts = <String, _VaultReasonContext>{};
    final output = <String, String>{};
    try {
      for (final grant in grants) {
        final encryptedReasonJson = grant.encryptedReason;
        if (encryptedReasonJson == null ||
            grant.reason?.trim().isNotEmpty == true) {
          continue;
        }
        try {
          final encryptedReason = EncryptedReasonModel.fromJson(
            encryptedReasonJson,
          );
          _validateParent(grant, encryptedReason);
          final context = contexts[grant.vaultId] ??= await _openVaultContext(
            grant.vaultId,
            memberPrivateKey,
          );
          if (context.organizationId != encryptedReason.organizationId) {
            throw const FormatException(
              'Encrypted reason organization mismatch',
            );
          }
          output[grant.id] = await _openReason(encryptedReason, context);
        } catch (error) {
          // Exception messages and request identifiers are intentionally not
          // logged: parser/crypto failures can retain attacker-controlled data.
          AppLogger.w(
            'Grants',
            'Encrypted reason resolution failed (${error.runtimeType})',
          );
        }
      }
      return output;
    } finally {
      for (final context in contexts.values) {
        context.dispose();
      }
    }
  }

  Future<_VaultReasonContext> _openVaultContext(
    String vaultId,
    Uint8List memberPrivateKey,
  ) async {
    Uint8List? vaultKey;
    try {
      final vault = await _vaults.getEncryptedVault(vaultId);
      final memberVaultKey = vault['memberVaultKey'];
      if (memberVaultKey is! Map || vault['organizationId'] is! String) {
        throw const FormatException('Malformed encrypted Vault');
      }
      vaultKey = await _keys.openMemberVaultKey(
        Map<String, dynamic>.from(memberVaultKey),
        memberPrivateKey,
      );
      final discovery = await _discovery.list(vaultId);
      final context = _VaultReasonContext(
        organizationId: vault['organizationId'] as String,
        vault: vault,
        vaultKey: vaultKey,
        discovery: discovery,
      );
      vaultKey = null;
      return context;
    } finally {
      vaultKey?.fillRange(0, vaultKey.length, 0);
    }
  }

  Future<String> _openReason(
    EncryptedReason reason,
    _VaultReasonContext context,
  ) async {
    Uint8List? signingKey;
    Uint8List? reasonKey;
    Uint8List? plaintext;
    try {
      final candidates = context.discovery
          .where((item) => item.agentId == reason.agentId && item.isCurrent)
          .toList(growable: false);
      if (candidates.length != 1) {
        throw const FormatException('Agent identity is not current');
      }
      signingKey = VaultProtocolBytes.base64Decode(
        candidates.single.ed25519PublicKey,
        maximumBytes: 32,
      );
      final messageKey = await _messageKey(reason, context);
      reasonKey = await _reasonCrypto.verifyAndOpenKey(
        reason: reason,
        signingPublicKey: signingKey,
        recipientPrivateKey: messageKey.privateKey,
      );
      if (reasonKey.length != 32) {
        throw const FormatException('Invalid ReasonDEK');
      }
      plaintext = await _reasonCrypto.decrypt(
        reason: reason,
        reasonKey: reasonKey,
      );
      final decoded = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
      if (decoded is! Map ||
          decoded.length != 1 ||
          decoded['reason'] is! String) {
        throw const FormatException('Malformed encrypted reason');
      }
      final text = (decoded['reason'] as String).trim();
      if (text.isEmpty || utf8.encode(text).length > 4096) {
        throw const FormatException('Invalid encrypted reason');
      }
      return text;
    } finally {
      signingKey?.fillRange(0, signingKey.length, 0);
      reasonKey?.fillRange(0, reasonKey.length, 0);
      plaintext?.fillRange(0, plaintext.length, 0);
    }
  }

  Future<_MessageKey> _messageKey(
    EncryptedReason reason,
    _VaultReasonContext context,
  ) async {
    final cached = context.messageKeys[reason.agentMessageKeyVersion];
    if (cached != null) {
      if (cached.fingerprint != reason.recipientAgentMessageKeyFingerprint) {
        throw const FormatException('Encrypted reason recipient mismatch');
      }
      return cached;
    }
    Uint8List? privateKey;
    try {
      final envelope = VaultRotationCryptoService.requirePrivateKeyEnvelope(
        envelopes: context.vault['vaultPrivateKeys'],
        purpose: 'vaultAgentMessagePrivateKey',
        keyVersion: reason.agentMessageKeyVersion,
      );
      privateKey = await _keys.openCanonicalAgentMessagePrivateKey(
        envelope,
        context.vaultKey,
        expectedKeyVersion: reason.agentMessageKeyVersion,
      );
      final fingerprint = await _messageKeyFingerprint(privateKey);
      if (fingerprint != reason.recipientAgentMessageKeyFingerprint) {
        throw const FormatException('Encrypted reason recipient mismatch');
      }
      final result = _MessageKey(
        privateKey: privateKey,
        fingerprint: fingerprint,
      );
      context.messageKeys[reason.agentMessageKeyVersion] = result;
      privateKey = null;
      return result;
    } finally {
      privateKey?.fillRange(0, privateKey.length, 0);
    }
  }

  static Future<String> _deriveMessageKeyFingerprint(
    Uint8List privateKey,
  ) async {
    Uint8List? publicKey;
    final sodium = await SodiumProvider.instance();
    final secret = SecureKey.fromList(sodium, privateKey);
    try {
      publicKey = sodium.crypto.scalarmult.base(n: secret);
      return VaultProtocolBytes.base64UrlEncode(
        vaultPublicKeyFingerprint(
          VaultPublicKeyKind.vaultMessageX25519,
          publicKey,
        ),
      );
    } finally {
      secret.dispose();
      publicKey?.fillRange(0, publicKey.length, 0);
    }
  }

  void _validateParent(GrantModel grant, EncryptedReason reason) {
    if (grant.agentId == null ||
        grant.entryId == null ||
        reason.vaultId != grant.vaultId ||
        reason.entryId != grant.entryId ||
        reason.grantRequestId != grant.id ||
        reason.agentId != grant.agentId ||
        reason.descriptor['protocolVersion'] != 2 ||
        !const {'encryptedReason', 9}.contains(reason.descriptor['purpose']) ||
        reason.requestedMethods != _methodMask(grant.methods)) {
      throw const FormatException('Encrypted reason scope mismatch');
    }
  }

  int _methodMask(String? value) {
    var result = 0;
    for (final method in parseGrantMethods(value)) {
      result |= switch (method) {
        GrantMethod.get => 1,
        GrantMethod.exec => 2,
        GrantMethod.inject => 4,
      };
    }
    return result;
  }
}

final class _VaultReasonContext {
  _VaultReasonContext({
    required this.organizationId,
    required this.vault,
    required this.vaultKey,
    required this.discovery,
  });

  final String organizationId;
  final Map<String, dynamic> vault;
  final Uint8List vaultKey;
  final List<AgentDiscoveryProvisioning> discovery;
  final Map<int, _MessageKey> messageKeys = {};

  void dispose() {
    vaultKey.fillRange(0, vaultKey.length, 0);
    for (final key in messageKeys.values) {
      key.dispose();
    }
    messageKeys.clear();
  }
}

final class _MessageKey {
  const _MessageKey({required this.privateKey, required this.fingerprint});

  final Uint8List privateKey;
  final String fingerprint;

  void dispose() => privateKey.fillRange(0, privateKey.length, 0);
}
