import 'dart:io';

import 'package:dio/dio.dart';

import '../datasources/vault_remote_datasource.dart';
import '../models/create_vault_request.dart';

/// Categorised reasons why a custom-icon upload may fail.
///
/// Lives in the data layer so it can carry semantic meaning across
/// service / cubit / UI boundaries without leaking English strings.
/// Translation happens at the presentation layer — see
/// [VaultIconUploadException] consumers for the mapping to ARB keys.
enum VaultIconUploadErrorKind {
  /// File extension / MIME type is not in the allow-list (PNG/JPEG/WebP).
  /// UI: `vaultIconUploadFormatError`.
  unsupportedFormat,

  /// Selected file exceeds the 2 MB byte limit.
  /// UI: `vaultIconUploadSizeError`.
  fileTooLarge,

  /// Generic network / S3 / backend error during presign or upload.
  /// UI: `vaultIconUploadError`.
  network,

  /// Unclassified failure — kept as a safety net so the UI always has a
  /// sensible fallback. Still maps to `vaultIconUploadError`.
  unknown,
}

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
  ///
  /// Throws [VaultIconUploadException] with a typed
  /// [VaultIconUploadErrorKind] on any failure — callers must translate
  /// `kind` to a user-facing message at the presentation layer.
  Future<String> uploadIcon(String vaultId, File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      throw const VaultIconUploadException(
        VaultIconUploadErrorKind.unsupportedFormat,
      );
    }

    final fileSize = await file.length();
    if (fileSize > _maxBytes) {
      throw const VaultIconUploadException(
        VaultIconUploadErrorKind.fileTooLarge,
      );
    }

    try {
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
    } on DioException {
      throw const VaultIconUploadException(VaultIconUploadErrorKind.network);
    } catch (_) {
      throw const VaultIconUploadException(VaultIconUploadErrorKind.unknown);
    }
  }
}

/// Thrown by [VaultIconUploadService.uploadIcon] — carries a typed
/// [VaultIconUploadErrorKind] so the presentation layer can map it to
/// the right ARB key.
class VaultIconUploadException implements Exception {
  const VaultIconUploadException(this.kind);

  final VaultIconUploadErrorKind kind;

  @override
  String toString() => 'VaultIconUploadException(${kind.name})';
}
