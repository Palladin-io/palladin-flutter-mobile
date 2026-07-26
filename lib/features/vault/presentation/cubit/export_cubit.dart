import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/export/canonical_export_service.dart';
import '../../data/export/export_models.dart';
import '../../data/export/export_sharer.dart';
import '../../data/export/protected_export_staging.dart';
import 'export_state.dart';

export 'export_state.dart';

/// Drives an explicitly confirmed, unlocked, local plaintext export.
class ExportCubit extends Cubit<ExportState> {
  ExportCubit({
    required CanonicalExportService service,
    required ExportSharer sharer,
    required ProtectedExportStaging staging,
  }) : _service = service,
       _sharer = sharer,
       _staging = staging,
       super(const ExportInitial());

  final CanonicalExportService _service;
  final ExportSharer _sharer;
  final ProtectedExportStaging _staging;

  Future<void> export({
    required String vaultId,
    required String vaultName,
    required ExportOptions options,
    required Uint8List privateKey,
    Rect? sharePositionOrigin,
  }) async {
    if (privateKey.length != 32) {
      emit(const ExportFailure(ExportErrorKind.locked));
      return;
    }
    emit(const ExportInProgress());
    ExportResult? result;
    try {
      result = await _service.export(
        vaultId: vaultId,
        vaultName: vaultName,
        options: options,
        memberPrivateKey: privateKey,
      );
      await _sharer.share(
        path: result.path,
        mimeType: options.format.mimeType,
        sharePositionOrigin: sharePositionOrigin,
      );
      if (!isClosed) {
        emit(
          ExportSuccess(entryCount: result.entryCount, format: options.format),
        );
      }
    } on ExportException catch (error) {
      if (!isClosed) emit(ExportFailure(error.kind));
    } catch (_) {
      if (!isClosed) emit(const ExportFailure(ExportErrorKind.staging));
    } finally {
      final path = result?.path;
      if (path != null) {
        try {
          await _staging.delete(path);
        } catch (_) {
          /* stale sweep */
        }
      }
    }
  }

  void cancel() {
    _service.cancel();
    if (!isClosed) emit(const ExportInitial());
  }

  @override
  Future<void> close() {
    _service.cancel();
    return super.close();
  }
}
