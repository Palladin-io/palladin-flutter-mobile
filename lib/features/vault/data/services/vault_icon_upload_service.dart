import 'dart:io';

import 'package:dio/dio.dart';

import '../datasources/vault_remote_datasource.dart';
import '../models/create_vault_request.dart';

class VaultIconUploadService {
  VaultIconUploadService(this._datasource);

  final VaultRemoteDatasource _datasource;

  static const _allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};
  static const _maxBytes = 2 * 1024 * 1024;

  static final _mimeMap = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
  };

  /// Presigns, uploads the [file] to S3, then PATCHes the vault icon.
  /// Returns the public URL stored on the vault.
  Future<String> uploadIcon(String vaultId, File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      throw const VaultIconUploadException('Unsupported format. Use PNG, JPEG or WebP.');
    }

    final fileSize = await file.length();
    if (fileSize > _maxBytes) {
      throw const VaultIconUploadException('File exceeds 2 MB limit.');
    }

    final presign = await _datasource.presignVaultIcon(vaultId, ext);

    // Use a bare Dio instance — no auth interceptors, no JWT sent to S3.
    final s3 = Dio();
    await s3.put<void>(
      presign.uploadUrl,
      data: file.openRead(),
      options: Options(
        headers: {
          Headers.contentTypeHeader: _mimeMap[ext] ?? 'image/jpeg',
          Headers.contentLengthHeader: fileSize,
        },
        sendTimeout: const Duration(seconds: 60),
      ),
    );

    await _datasource.updateVault(
      vaultId,
      UpdateVaultRequest(icon: presign.publicUrl),
    );

    return presign.publicUrl;
  }
}

class VaultIconUploadException implements Exception {
  const VaultIconUploadException(this.message);
  final String message;
  @override
  String toString() => message;
}
