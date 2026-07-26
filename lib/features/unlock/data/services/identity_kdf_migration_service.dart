import 'dart:typed_data';

import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../../../core/crypto/sodium_provider.dart';
import '../../../auth/data/datasources/password_auth_remote_datasource.dart';
import '../../../auth/data/services/password_auth_crypto_service.dart';
import '../datasources/account_remote_datasource.dart';
import '../models/account_response.dart';
import '../models/identity_kdf_migration_request.dart';
import 'identity_kdf_service.dart';

/// Prepared in-memory migration retained only to make an interrupted request
/// idempotently retryable. [dispose] destroys all secret-bearing buffers.
final class PendingIdentityKdfMigration {
  PendingIdentityKdfMigration({
    required this.request,
    required this.accountSecret,
    required this.masterKey,
    required this.privateKey,
  });

  final IdentityKdfMigrationRequest request;
  final Uint8List accountSecret;
  final Uint8List masterKey;
  final Uint8List privateKey;

  void dispose() {
    request.currentAuthCredential.fillRange(
      0,
      request.currentAuthCredential.length,
      0,
    );
    request.newAuthCredential.fillRange(0, request.newAuthCredential.length, 0);
    request.newKdfSalt.fillRange(0, request.newKdfSalt.length, 0);
    request.newEncryptedPrivateKey.fillRange(
      0,
      request.newEncryptedPrivateKey.length,
      0,
    );
    accountSecret.fillRange(0, accountSecret.length, 0);
    masterKey.fillRange(0, masterKey.length, 0);
    privateKey.fillRange(0, privateKey.length, 0);
  }
}

/// Prepares and commits a legacy-to-v2 rewrap without changing the keypair.
class IdentityKdfMigrationService {
  IdentityKdfMigrationService({
    required AccountRemoteDatasource accountDatasource,
    required PasswordAuthRemoteDatasource passwordDatasource,
    required PasswordAuthCryptoService legacyCrypto,
    required IdentityKdfService identityCrypto,
    Future<SodiumSumo> Function()? sodiumLoader,
  }) : _accountDatasource = accountDatasource,
       _passwordDatasource = passwordDatasource,
       _legacyCrypto = legacyCrypto,
       _identityCrypto = identityCrypto,
       _sodiumLoader = sodiumLoader ?? SodiumProvider.instance;

  final AccountRemoteDatasource _accountDatasource;
  final PasswordAuthRemoteDatasource _passwordDatasource;
  final PasswordAuthCryptoService _legacyCrypto;
  final IdentityKdfService _identityCrypto;
  final Future<SodiumSumo> Function() _sodiumLoader;
  PendingIdentityKdfMigration? _pending;

  /// Builds the compare-and-swap operation once and retains it for retry.
  Future<PendingIdentityKdfMigration> prepare({
    required String password,
    required AccountResponse account,
    required Uint8List legacyPrivateKey,
  }) async {
    final existing = _pending;
    if (existing != null) return existing;
    final metadata = account.kdf;
    if (metadata == null ||
        metadata.securityVersion != 1 ||
        metadata.minimumSecurityVersion > 1 ||
        metadata.profileId != IdentityKdfProfile.legacyId) {
      throw const UnsupportedIdentityKdfException('migration-not-applicable');
    }

    Uint8List? currentCredential;
    Uint8List? accountSecret;
    Uint8List? newSalt;
    IdentityKdfOutputs? outputs;
    Uint8List? encryptedPrivateKey;
    try {
      final bootstrap = await _passwordDatasource.fetchLoginKdf(
        account.email,
        profileId: IdentityKdfProfile.legacyId,
      );
      if (bootstrap.profileId != IdentityKdfProfile.legacyId ||
          bootstrap.securityVersion != 1 ||
          bootstrap.memoryKiB != 19456 ||
          bootstrap.iterations != IdentityKdfProfile.iterations ||
          bootstrap.parallelism != IdentityKdfProfile.parallelism ||
          bootstrap.accountSecretRequired) {
        throw const UnsupportedIdentityKdfException('unsupported-kdf-profile');
      }
      currentCredential = await _legacyCrypto.deriveAuthCredentialBytes(
        password: password,
        authSaltBase64: bootstrap.kdfSalt,
      );
      accountSecret = await _identityCrypto.generateAccountSecret();
      newSalt = await _identityCrypto.generateKdfSalt();
      outputs = await _identityCrypto.derive(
        password: password,
        accountSecret: accountSecret,
        accountId: account.userId,
        kdfSalt: newSalt,
      );
      encryptedPrivateKey = await _encryptPrivateKey(
        legacyPrivateKey,
        outputs.masterKey,
      );
      final prepared = PendingIdentityKdfMigration(
        request: IdentityKdfMigrationRequest(
          migrationId: await _migrationId(),
          sourceSecurityVersion: 1,
          baseCredentialRevision: metadata.credentialRevision,
          basePrivateKeyWrapRevision: metadata.privateKeyWrapRevision,
          currentAuthCredential: currentCredential,
          newAuthCredential: outputs.authCredential,
          newKdfSalt: newSalt,
          newEncryptedPrivateKey: encryptedPrivateKey,
        ),
        accountSecret: accountSecret,
        masterKey: outputs.masterKey,
        privateKey: Uint8List.fromList(legacyPrivateKey),
      );
      _pending = prepared;
      currentCredential = null;
      accountSecret = null;
      newSalt = null;
      encryptedPrivateKey = null;
      outputs = null;
      return prepared;
    } finally {
      currentCredential?.fillRange(0, currentCredential.length, 0);
      accountSecret?.fillRange(0, accountSecret.length, 0);
      newSalt?.fillRange(0, newSalt.length, 0);
      encryptedPrivateKey?.fillRange(0, encryptedPrivateKey.length, 0);
      outputs?.dispose();
    }
  }

  /// Commits the retained operation. On transport failure it remains intact
  /// for an exact retry; on success ownership of returned copies passes out.
  Future<({Uint8List masterKey, Uint8List privateKey, Uint8List accountSecret})>
  commit() async {
    final pending = _pending;
    if (pending == null) {
      throw StateError('No Identity KDF migration is prepared');
    }
    await _accountDatasource.migrateIdentityKdf(pending.request);
    final result = (
      masterKey: Uint8List.fromList(pending.masterKey),
      privateKey: Uint8List.fromList(pending.privateKey),
      accountSecret: Uint8List.fromList(pending.accountSecret),
    );
    pending.dispose();
    _pending = null;
    return result;
  }

  /// Aborts the operation and wipes all retained material.
  void abort() {
    _pending?.dispose();
    _pending = null;
  }

  Future<Uint8List> _encryptPrivateKey(
    Uint8List privateKey,
    Uint8List masterKey,
  ) async {
    final sodium = await _sodiumLoader();
    final key = SecureKey.fromList(sodium, masterKey);
    try {
      final nonce = sodium.randombytes.buf(sodium.crypto.secretBox.nonceBytes);
      final cipher = sodium.crypto.secretBox.easy(
        message: privateKey,
        nonce: nonce,
        key: key,
      );
      return Uint8List.fromList([...nonce, ...cipher]);
    } finally {
      key.dispose();
    }
  }

  Future<String> _migrationId() async {
    final sodium = await _sodiumLoader();
    final bytes = sodium.randombytes.buf(16);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    bytes.fillRange(0, bytes.length, 0);
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
