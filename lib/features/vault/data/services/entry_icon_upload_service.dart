import 'dart:io';

import 'package:dio/dio.dart';

import '../datasources/entry_remote_datasource.dart';
import 'vault_icon_upload_service.dart' show VaultIconUploadErrorKind, VaultIconUploadException;

/// Handles the two-step custom icon upload for entries:
/// presign → S3 upload → PATCH entry icon.
///
/// Reuses [VaultIconUploadErrorKind] and [VaultIconUploadException] since
/// the error taxonomy is identical to vault icon uploads.
class EntryIconUploadService {
  EntryIconUploadService(this._datasource);

  final EntryRemoteDatasource _datasource;

  static const _allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};
  static const _maxBytes = 2 * 1024 * 1024;

  static final _mimeMap = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
  };

  /// Presigns, uploads [file] to S3, then PATCHes the entry's icon field.
  /// Returns the public URL stored on the entry.
  ///
  /// Throws [VaultIconUploadException] with a typed [VaultIconUploadErrorKind]
  /// on any failure — callers must translate `kind` to a user-facing message
  /// at the presentation layer.
  Future<String> uploadIcon(String vaultId, String entryId, File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      throw const VaultIconUploadException(VaultIconUploadErrorKind.unsupportedFormat);
    }

    final fileSize = await file.length();
    if (fileSize > _maxBytes) {
      throw const VaultIconUploadException(VaultIconUploadErrorKind.fileTooLarge);
    }

    try {
      final presign = await _datasource.presignEntryIcon(vaultId, entryId, ext);

      final bytes = await file.readAsBytes();
      final s3 = Dio();
      await s3.put<void>(
        presign.uploadUrl,
        data: bytes,
        options: Options(
          headers: {
            Headers.contentTypeHeader: _mimeMap[ext] ?? 'image/jpeg',
            Headers.contentLengthHeader: fileSize,
          },
          sendTimeout: const Duration(seconds: 60),
        ),
      );

      await _datasource.updateEntryIcon(vaultId, entryId, presign.publicUrl);

      return presign.publicUrl;
    } on DioException {
      throw const VaultIconUploadException(VaultIconUploadErrorKind.network);
    } catch (_) {
      throw const VaultIconUploadException(VaultIconUploadErrorKind.unknown);
    }
  }
}
