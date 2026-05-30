import 'dart:io';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../datasources/agents_remote_data_source.dart';

/// Categorised reasons why an agent icon upload may fail.
enum AgentIconUploadErrorKind {
  unsupportedFormat,
  fileTooLarge,
  network,
  unknown,
}

/// Thrown by [AgentIconUploadService.uploadIcon].
class AgentIconUploadException implements Exception {
  const AgentIconUploadException(this.kind);

  final AgentIconUploadErrorKind kind;

  @override
  String toString() => 'AgentIconUploadException(${kind.name})';
}

/// Presigns and uploads a custom icon image for an agent to S3.
///
/// Returns the public URL to store as the agent's `iconKey`. Callers are
/// responsible for persisting it via
/// [AgentsRepository.updateAgent(iconKey: url)] — this service only handles
/// the file upload, not the PATCH.
class AgentIconUploadService {
  AgentIconUploadService(this._datasource);

  final AgentsRemoteDataSource _datasource;

  static const _allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};
  static const _maxBytes = 2 * 1024 * 1024;
  static final _mimeMap = {
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
  };

  Future<String> uploadIcon(String agentId, File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(ext)) {
      throw const AgentIconUploadException(
        AgentIconUploadErrorKind.unsupportedFormat,
      );
    }
    final fileSize = await file.length();
    if (fileSize > _maxBytes) {
      throw const AgentIconUploadException(
        AgentIconUploadErrorKind.fileTooLarge,
      );
    }
    try {
      AppLogger.d('AgentIconUpload', 'presign agentId=$agentId ext=$ext');
      final presign = await _datasource.presignAgentIcon(agentId, ext);
      AppLogger.d('AgentIconUpload', 'uploadUrl=${presign.uploadUrl}');

      final bytes = await file.readAsBytes();
      final s3 = Dio();
      await s3.put<void>(
        presign.uploadUrl,
        data: bytes,
        options: Options(
          headers: {
            Headers.contentTypeHeader: _mimeMap[ext] ?? 'image/jpeg',
          },
          sendTimeout: const Duration(seconds: 60),
        ),
      );
      AppLogger.i('AgentIconUpload', 'S3 PUT done, publicUrl=${presign.publicUrl}');
      return presign.publicUrl;
    } on DioException catch (e) {
      AppLogger.e('AgentIconUpload', 'upload failed', error: e);
      throw const AgentIconUploadException(AgentIconUploadErrorKind.network);
    } catch (e, s) {
      AppLogger.e('AgentIconUpload', 'unexpected error', error: e, stackTrace: s);
      throw const AgentIconUploadException(AgentIconUploadErrorKind.unknown);
    }
  }
}
