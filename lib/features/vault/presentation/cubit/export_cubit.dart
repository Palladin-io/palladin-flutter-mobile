import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/analytics/analytics_service.dart';
import '../../../../core/utils/app_logger.dart';
import '../../data/export/export_models.dart';
import '../../data/export/export_serializers.dart';
import '../../data/export/export_sharer.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../../domain/repositories/entry_repository.dart';
import 'export_state.dart';

export 'export_state.dart';

/// Drives the vault export flow: reveal every entry (VK unwrapped once),
/// serialize to CSV or JSON, hand the file to the share sheet, then record
/// the export in the audit log and analytics.
///
/// The plaintext export exists only inside [ExportSharer.share] and is not
/// persisted at a path Palladin controls. Nothing here logs a secret.
class ExportCubit extends Cubit<ExportState> {
  ExportCubit({
    required this.repository,
    required this.sharer,
    AnalyticsService? analytics,
  })  : _analytics = analytics ?? AnalyticsService.instance,
        super(const ExportInitial());

  final EntryRepository repository;
  final ExportSharer sharer;
  final AnalyticsService _analytics;

  /// Exports [vaultId] in [format]. [privateKey] comes from the unlocked
  /// auth state; the caller owns zeroing its copy. [vaultName] labels the
  /// grouping in the output. [sharePositionOrigin] anchors the iPad share
  /// popover.
  Future<void> export({
    required String vaultId,
    required String vaultName,
    required ExportFormat format,
    required Uint8List privateKey,
    String? wrappedVK,
    Rect? sharePositionOrigin,
  }) async {
    if (privateKey.isEmpty) {
      emit(const ExportFailure(ExportFailureReason.crypto));
      return;
    }
    emit(const ExportInProgress());
    try {
      final revealed = await repository.revealAllEntries(
        vaultId: vaultId,
        privateKey: privateKey,
        wrappedVK: wrappedVK,
      );
      if (revealed.isEmpty) {
        emit(const ExportFailure(ExportFailureReason.empty));
        return;
      }

      final records = revealed
          .map((r) => _toRecord(r.entry, r.payload, vaultName))
          .toList();
      final content = format == ExportFormat.csv
          ? ExportSerializer.toPalladinCsv(records)
          : ExportSerializer.toPalladinJson(
              records,
              vaultName: vaultName,
              vaultId: vaultId,
            );

      await sharer.share(
        content: content,
        fileName: _fileNameFor(vaultName, format),
        mimeType: format.mimeType,
        sharePositionOrigin: sharePositionOrigin,
      );

      // Best-effort audit + analytics — do not fail the export if these do.
      await repository.logExportAudit(
        vaultId: vaultId,
        format: format.extension,
        entryCount: records.length,
      );
      _analytics.capture('vault', 'export-completed', properties: {
        'count': records.length,
        'format': format.extension,
      });

      emit(ExportSuccess(entryCount: records.length, format: format));
    } on EntryException catch (e) {
      AppLogger.w('Export', 'export failed: ${e.kind.name}');
      emit(ExportFailure(_mapError(e.kind)));
    } catch (e, s) {
      AppLogger.e('Export', 'export failed unexpectedly', error: e, stackTrace: s);
      emit(const ExportFailure(ExportFailureReason.unknown));
    }
  }

  ExportRecord _toRecord(
    EntryEntity entry,
    Map<String, dynamic> payload,
    String vaultName,
  ) {
    // Both entry types share url/notes; only credentials carry
    // username/password/totp. Keys expose their single secret as the
    // password column so the row still round-trips.
    if (entry.type == EntryType.credential) {
      final cred = CredentialPayload.fromJson(payload);
      return ExportRecord(
        name: entry.label,
        url: entry.urlDomain ?? cred.url,
        username: cred.username.isEmpty ? null : cred.username,
        password: cred.password.isEmpty ? null : cred.password,
        notes: cred.notes,
        totp: cred.totp,
        folder: vaultName,
      );
    }
    final key = KeyPayload.fromJson(payload);
    return ExportRecord(
      name: entry.label,
      url: entry.urlDomain ?? key.url,
      password: key.value.isEmpty ? null : key.value,
      notes: key.notes,
      folder: vaultName,
    );
  }

  String _fileNameFor(String vaultName, ExportFormat format) {
    final slug = vaultName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final base = slug.isEmpty ? 'vault' : slug;
    return 'palladin-$base.${format.extension}';
  }

  ExportFailureReason _mapError(EntryErrorKind kind) => switch (kind) {
        EntryErrorKind.networkError => ExportFailureReason.network,
        EntryErrorKind.cryptoFailure => ExportFailureReason.crypto,
        _ => ExportFailureReason.unknown,
      };
}
