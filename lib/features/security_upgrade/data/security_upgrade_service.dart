import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../core/crypto/envelope/envelope_contract.dart';
import '../../../core/crypto/key_wrapper/key_wrapper.dart';
import '../../../core/crypto/recipient_key_wrapper.dart';
import '../../../core/crypto/sodium_provider.dart';
import '../../../core/storage/account_secret_store.dart';
import '../../auth/data/services/account_key_material_service.dart';
import '../../onboarding/domain/mnemonic.dart' as mnemonic;
import '../../unlock/data/models/account_response.dart';
import '../../unlock/data/services/identity_kdf_service.dart';
import '../../vault/data/datasources/vault_remote_datasource.dart';
import '../../vault/data/services/vault_rotation_crypto_service.dart';
import 'security_upgrade_remote_datasource.dart';

/// Keys of the upgraded account, held in memory only. The caller owns every
/// buffer and calls [dispose] once they are handed to the session.
final class UpgradedAccountKeys {
  UpgradedAccountKeys({
    required this.accountId,
    required this.email,
    required this.masterKey,
    required this.memberPrivateKey,
    required this.memberKeyVersion,
    required this.legacyPrivateKey,
    required this.legacyKeyVersion,
    this.accountSecret,
    this.recoveryMnemonic,
  });

  final String accountId;
  final String email;
  final Uint8List masterKey;
  final Uint8List memberPrivateKey;
  final int memberKeyVersion;
  final Uint8List legacyPrivateKey;
  final int legacyKeyVersion;

  /// Present only right after the commit, for the Emergency Kit step.
  final Uint8List? accountSecret;

  /// Present only right after the commit, for the recovery phrase step.
  final List<String>? recoveryMnemonic;

  void wipeLegacy() =>
      legacyPrivateKey.fillRange(0, legacyPrivateKey.length, 0);

  void dispose() {
    for (final secret in [
      masterKey,
      memberPrivateKey,
      legacyPrivateKey,
      ?accountSecret,
    ]) {
      secret.fillRange(0, secret.length, 0);
    }
  }
}

/// Re-wrap progress for the non-dismissable progress screen.
final class RewrapProgress {
  const RewrapProgress({required this.done, required this.total});
  final int done;
  final int total;
}

/// In-place migration from the password-only profile to security version 2
/// (`identity-kdf/v3` `migration`). Every step is resumable: the commit is
/// idempotent by migration id and re-wrapping skips migrated envelopes.
class SecurityUpgradeService {
  SecurityUpgradeService({
    required SecurityUpgradeRemoteDatasource remote,
    required VaultRemoteDatasource vaults,
    required IdentityKdfService identityKdf,
    required AccountSecretStore accountSecrets,
    Future<SodiumSumo> Function()? sodiumLoader,
  }) : _remote = remote,
       _vaults = vaults,
       _identityKdf = identityKdf,
       _accountSecrets = accountSecrets,
       _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final SecurityUpgradeRemoteDatasource _remote;
  final VaultRemoteDatasource _vaults;
  final IdentityKdfService _identityKdf;
  final AccountSecretStore _accountSecrets;
  final Future<SodiumSumo> Function() _sodiumLoader;

  AccountKeyMaterialService get _material => AccountKeyMaterialService(
    identityKdfService: _identityKdf,
    sodiumLoader: _sodiumLoader,
  );

  /// Builds version-2 material and submits the atomic upgrade. The Secret Key
  /// is stored on this device before the request, so a lost response or a
  /// crash after the commit never strands the account. [migrationId] must be
  /// reused for retries of the same attempt.
  Future<UpgradedAccountKeys> commit({
    required String migrationId,
    required String password,
    required AccountResponse account,
    required Uint8List legacyPrivateKey,
  }) async {
    final kdf = account.kdf;
    final legacyKeyVersion = account.memberKeyVersion;
    if (kdf == null || legacyKeyVersion == null) {
      throw const SecurityUpgradeException(SecurityUpgradeErrorKind.server);
    }
    final currentSalt = _decode(kdf.kdfSalt);
    final current = await _identityKdf.derive(
      password: password,
      accountId: account.userId,
      kdfSalt: currentSalt,
    );
    currentSalt.fillRange(0, currentSalt.length, 0);
    final phrase = mnemonic.generateRecoveryMnemonic();
    AccountKeyMaterialV2? material;
    try {
      material = await _material.build(
        password: password,
        accountId: account.userId,
        recoveryMnemonic: phrase,
      );
      final legacyWrapped = await _material.wrapUnderMasterKey(
        material.masterKey,
        legacyPrivateKey,
      );
      await _accountSecrets.write(account.userId, material.accountSecret);
      final committed = await _remote.upgrade({
        'migrationId': migrationId,
        'accountId': account.userId,
        'sourceSecurityVersion': IdentityKdfProfile.securityVersion,
        'baseCredentialRevision': kdf.credentialRevision,
        'basePrivateKeyWrapRevision': kdf.privateKeyWrapRevision,
        'baseMemberKeyVersion': legacyKeyVersion,
        'currentAuthCredential': _b64(current.authCredential),
        'securityVersion': IdentityKdfProfileV2.securityVersion,
        'minimumSecurityVersion': IdentityKdfProfileV2.securityVersion,
        'kdfProfileId': IdentityKdfProfileV2.id,
        'kdfSalt': _b64(material.kdfSalt),
        'authCredential': _b64(material.authCredential),
        'memberPublicKey': _b64(material.memberPublicKey),
        'memberPublicKeySuite': material.memberKeySuite.wireValue,
        'encryptedPrivateKey': _b64(material.encryptedPrivateKey),
        'recoverySalt': _b64(material.recoverySalt),
        'encryptedPrivateKeyByRecovery': _b64(
          material.encryptedPrivateKeyByRecovery,
        ),
        'legacyMemberKey': {
          'keyVersion': legacyKeyVersion,
          'encryptedPrivateKey': _b64(legacyWrapped),
        },
      });
      final keys = UpgradedAccountKeys(
        accountId: account.userId,
        email: account.email,
        masterKey: Uint8List.fromList(material.masterKey),
        memberPrivateKey: Uint8List.fromList(material.memberPrivateKey),
        memberKeyVersion: committed.memberKeyVersion,
        legacyPrivateKey: Uint8List.fromList(legacyPrivateKey),
        legacyKeyVersion: legacyKeyVersion,
        accountSecret: Uint8List.fromList(material.accountSecret),
        recoveryMnemonic: phrase,
      );
      return keys;
    } finally {
      current.dispose();
      material?.dispose();
    }
  }

  /// Rebuilds the resume keys after a version-2 unlock: the old member key is
  /// opened from its record wrapped under the version-2 master key.
  Future<UpgradedAccountKeys?> resumeKeys({
    required AccountResponse account,
    required Uint8List masterKey,
    required Uint8List memberPrivateKey,
  }) async {
    final legacy = account.legacyMemberKey;
    final memberKeyVersion = account.memberKeyVersion;
    if (legacy == null || memberKeyVersion == null) return null;
    final opened = await _material.openUnderMasterKey(
      masterKey,
      _decode(legacy.encryptedPrivateKey),
    );
    if (opened == null) {
      throw const SecurityUpgradeException(SecurityUpgradeErrorKind.server);
    }
    return UpgradedAccountKeys(
      accountId: account.userId,
      email: account.email,
      masterKey: Uint8List.fromList(masterKey),
      memberPrivateKey: Uint8List.fromList(memberPrivateKey),
      memberKeyVersion: memberKeyVersion,
      legacyPrivateKey: opened,
      legacyKeyVersion: legacy.keyVersion,
    );
  }

  /// Re-wraps every member Vault key still addressed to the old key as the
  /// next member key generation, then deletes the legacy key record once the
  /// backend reports no member envelope left.
  Future<KeyMigrationReport> rewrapMemberEnvelopes(
    UpgradedAccountKeys keys, {
    void Function(RewrapProgress progress)? onProgress,
  }) async {
    final pending = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final page = await _vaults.listEncryptedVaults(offset: offset);
      for (final vault in page.vaults) {
        final descriptor = _descriptorOf(vault.memberVaultKey);
        if (descriptor['wrapperSuiteId'] ==
            WrapperSuite.x25519SealedBoxV1.wireValue) {
          pending.add({'vaultId': vault.id, 'envelope': vault.memberVaultKey});
        }
      }
      offset += page.vaults.length;
      if (page.vaults.isEmpty || offset >= page.total) break;
    }
    onProgress?.call(RewrapProgress(done: 0, total: pending.length));
    final legacyOpen = VaultRotationCryptoService(
      sodiumLoader: _sodiumLoader,
      memberKeySuite: WrapperSuite.x25519SealedBoxV1,
    );
    final sodium = await _sodiumLoader();
    final memberPublic = memberPublicKeyFromPrivate(
      sodium,
      keys.memberPrivateKey,
    );
    for (var index = 0; index < pending.length; index++) {
      final vaultId = pending[index]['vaultId'] as String;
      final envelope = pending[index]['envelope'] as Map<String, dynamic>;
      await _rewrapOne(
        vaultId: vaultId,
        envelope: envelope,
        keys: keys,
        legacyOpen: legacyOpen,
        memberPublic: memberPublic,
      );
      onProgress?.call(RewrapProgress(done: index + 1, total: pending.length));
    }
    final report = await _remote.report();
    if (report.legacyMemberEnvelopes == 0) {
      await _remote.deleteLegacyMemberKey();
    }
    return report;
  }

  Future<void> _rewrapOne({
    required String vaultId,
    required Map<String, dynamic> envelope,
    required UpgradedAccountKeys keys,
    required VaultRotationCryptoService legacyOpen,
    required Uint8List memberPublic,
  }) async {
    final descriptor = _descriptorOf(envelope);
    final scope = Map<String, dynamic>.from(descriptor['scope'] as Map);
    final resourceRevision = int.parse(
      descriptor['resourceRevision'] as String,
    );
    final wrappedKeyVersion = descriptor['wrappedKeyVersion'] as int;
    final generation = descriptor['memberKeyGeneration'] as int;
    final vaultKey = await legacyOpen.openMemberVaultKey(
      envelope,
      keys.legacyPrivateKey,
      expectedVaultId: vaultId,
    );
    try {
      final context = WrapperContext(
        suiteId: WrapperSuite.memberKeySuite,
        purpose: WrapperPurpose.memberVaultKey,
        scope: EnvelopeScope(
          organizationId: EnvelopeId.parse(scope['organizationId'] as String),
          vaultId: EnvelopeId.parse(vaultId),
          memberId: EnvelopeId.parse(scope['memberId'] as String),
        ),
        resourceRevision: resourceRevision + 1,
        wrappedKeyVersion: wrappedKeyVersion,
        memberKeyGeneration: generation + 1,
        recipientKeyKind: RecipientKeyKind.memberEncryption.id,
        recipientKeyVersion: keys.memberKeyVersion,
        recipientFingerprint: recipientFingerprint(
          WrapperSuite.memberKeySuite,
          RecipientKeyKind.memberEncryption.id,
          memberPublic,
        ),
      );
      final sealed = await RecipientKeyWrapper(sodiumLoader: _sodiumLoader)
          .seal(
            key: vaultKey,
            context: context,
            recipient: RecipientPublicKey(
              suite: WrapperSuite.memberKeySuite,
              keyKind: RecipientKeyKind.memberEncryption,
              keyVersion: keys.memberKeyVersion,
              publicKey: memberPublic,
            ),
          );
      final wire = context.toDescriptor();
      await _remote.replaceMemberEnvelope(vaultId, {
        'baseResourceRevision': resourceRevision.toString(),
        'baseMemberKeyGeneration': generation,
        'wrappedVaultKey': {
          'descriptor': {
            ...wire.toJson(),
            'scope': {
              'organizationId': scope['organizationId'],
              'vaultId': vaultId,
              'entryId': null,
              'grantOrRequestId': null,
              'agentId': null,
              'memberId': scope['memberId'],
            },
            'parentDescriptorHash': null,
          },
          'encodedSealedKeyPackage': _b64(sealed),
        },
      });
    } finally {
      vaultKey.fillRange(0, vaultKey.length, 0);
    }
  }

  static Map<String, dynamic> _descriptorOf(Map<String, dynamic> envelope) =>
      Map<String, dynamic>.from(
        (envelope['wrappedVaultKey'] as Map)['descriptor'] as Map,
      );

  static Uint8List _decode(String value) =>
      Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
}
