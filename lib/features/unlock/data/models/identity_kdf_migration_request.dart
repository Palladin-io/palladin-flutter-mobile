import 'dart:convert';
import 'dart:typed_data';

import '../services/identity_kdf_service.dart';

/// Ciphertext-only compare-and-swap request for a legacy KDF migration.
final class IdentityKdfMigrationRequest {
  const IdentityKdfMigrationRequest({
    required this.migrationId,
    required this.sourceSecurityVersion,
    required this.baseCredentialRevision,
    required this.basePrivateKeyWrapRevision,
    required this.currentAuthCredential,
    required this.newAuthCredential,
    required this.newKdfSalt,
    required this.newEncryptedPrivateKey,
  });

  final String migrationId;
  final int sourceSecurityVersion;
  final int baseCredentialRevision;
  final int basePrivateKeyWrapRevision;
  final Uint8List currentAuthCredential;
  final Uint8List newAuthCredential;
  final Uint8List newKdfSalt;
  final Uint8List newEncryptedPrivateKey;

  Map<String, dynamic> toJson() => {
    'migrationId': migrationId,
    'sourceSecurityVersion': sourceSecurityVersion,
    'baseCredentialRevision': baseCredentialRevision,
    'basePrivateKeyWrapRevision': basePrivateKeyWrapRevision,
    'targetProfileId': IdentityKdfProfile.id,
    'currentAuthCredential': _encode(currentAuthCredential),
    'newAuthCredential': _encode(newAuthCredential),
    'newKdfSalt': _encode(newKdfSalt),
    'newEncryptedPrivateKey': _encode(newEncryptedPrivateKey),
  };

  String _encode(Uint8List value) =>
      base64Url.encode(value).replaceAll('=', '');
}
