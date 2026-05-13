import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/utils/app_logger.dart';
import '../../domain/entities/entry_entity.dart';
import '../../domain/exceptions/entry_exceptions.dart';
import '../../domain/repositories/entry_repository.dart';
import '../datasources/entry_remote_datasource.dart';
import '../datasources/vault_remote_datasource.dart';
import '../models/create_entry_request.dart';
import '../models/entry_model.dart';
import '../models/update_entry_request.dart';
import '../services/entry_crypto_service.dart';

/// Concrete implementation of [EntryRepository].
///
/// Responsibilities:
///   * Translates DioExceptions into typed [EntryException]s so the
///     presentation layer can render localized error messages.
///   * Owns the wrappedVK lifecycle — fetches it from the vault
///     datasource, hands it to [EntryCryptoService.unwrapVK] to derive
///     the VK, and zeroes the plaintext VK in `finally`.
///   * Never lets plaintext VK leak above the data layer.
class EntryRepositoryImpl implements EntryRepository {
  EntryRepositoryImpl({
    required this.entryDatasource,
    required this.vaultDatasource,
    required this.cryptoService,
  });

  final EntryRemoteDatasource entryDatasource;
  final VaultRemoteDatasource vaultDatasource;
  final EntryCryptoService cryptoService;

  @override
  Future<List<EntryEntity>> listEntries(String vaultId) async {
    try {
      AppLogger.d('Entry', 'GET /api/vaults/$vaultId/entries');
      final models = await entryDatasource.listEntries(vaultId);
      for (final m in models) {
        AppLogger.d('Entry', 'entry ${m.id} icon=${m.icon}');
      }
      return models.map((m) => m.toEntity()).toList(growable: false);
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'listEntries failed', error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    }
  }

  @override
  Future<EntryEntity> createEntry({
    required String vaultId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required String encryptedBlob,
    required String nonce,
    String? urlDomain,
  }) async {
    try {
      AppLogger.d('Entry', 'POST /api/vaults/$vaultId/entries');
      final model = await entryDatasource.createEntry(
        vaultId,
        CreateEntryRequest(
          label: label,
          description: description,
          icon: icon,
          type: type.toWire(),
          content: EntryContentModel(
            encryptedBlob: encryptedBlob,
            nonce: nonce,
          ),
          urlDomain: urlDomain,
        ),
      );
      return model.toEntity();
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'createEntry failed', error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    }
  }

  @override
  Future<void> deleteEntry({
    required String vaultId,
    required String entryId,
  }) async {
    try {
      AppLogger.d('Entry', 'DELETE /api/vaults/$vaultId/entries/$entryId');
      await entryDatasource.deleteEntry(vaultId, entryId);
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'deleteEntry failed', error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    }
  }

  @override
  Future<RevealedEntry> revealEntry({
    required String vaultId,
    required String entryId,
    required Uint8List privateKey,
    String? wrappedVK,
  }) async {
    AppLogger.d('Entry', 'Revealing entry id=$entryId');
    final detail = await _fetchDetail(vaultId, entryId);
    // Prefer the wrappedVK threaded down from the vault detail load —
    // falling back to a fetch keeps the call resilient when callers
    // (tests, future flows) don't have it cached.
    final vk = wrappedVK ?? await _fetchWrappedVK(vaultId);

    Uint8List? vaultKey;
    try {
      vaultKey = await cryptoService.unwrapVK(
        wrappedVK: vk,
        privateKey: privateKey,
      );
      final payload = await cryptoService.decryptEntry(
        content: detail.content,
        vaultKey: vaultKey,
      );
      return RevealedEntry(entry: detail.summary.toEntity(), payload: payload);
    } finally {
      if (vaultKey != null) {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
    }
  }

  @override
  Future<EntryEntity> createEntryEncrypted({
    required String vaultId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
    required Uint8List privateKey,
    String? wrappedVK,
  }) async {
    AppLogger.d('Entry', 'Creating encrypted entry in vault $vaultId');
    // See [revealEntry] — same fallback contract.
    final vk = wrappedVK ?? await _fetchWrappedVK(vaultId);

    Uint8List? vaultKey;
    try {
      vaultKey = await cryptoService.unwrapVK(
        wrappedVK: vk,
        privateKey: privateKey,
      );
      final encrypted = await cryptoService.encryptEntry(
        payload: payload,
        vaultKey: vaultKey,
      );
      return await createEntry(
        vaultId: vaultId,
        label: label,
        description: description,
        icon: icon,
        type: type,
        encryptedBlob: encrypted.encryptedBlob,
        nonce: encrypted.nonce,
        urlDomain: urlDomain,
      );
    } finally {
      if (vaultKey != null) {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
    }
  }

  @override
  Future<EntryEntity> updateEntryEncrypted({
    required String vaultId,
    required String entryId,
    required String label,
    String? description,
    String? icon,
    required EntryType type,
    required Map<String, dynamic> payload,
    String? urlDomain,
    required Uint8List privateKey,
    String? wrappedVK,
  }) async {
    AppLogger.d('Entry', 'Updating encrypted entry id=$entryId');
    final vk = wrappedVK ?? await _fetchWrappedVK(vaultId);

    Uint8List? vaultKey;
    try {
      vaultKey = await cryptoService.unwrapVK(
        wrappedVK: vk,
        privateKey: privateKey,
      );
      final encrypted = await cryptoService.encryptEntry(
        payload: payload,
        vaultKey: vaultKey,
      );
      try {
        await entryDatasource.updateEntry(
          vaultId,
          entryId,
          UpdateEntryRequest(
            label: label,
            description: description,
            icon: icon,
            type: type.toWire(),
            content: EntryContentModel(
              encryptedBlob: encrypted.encryptedBlob,
              nonce: encrypted.nonce,
            ),
            urlDomain: urlDomain,
          ),
        );
      } on DioException catch (e, s) {
        AppLogger.e('Entry', 'updateEntry failed', error: e, stackTrace: s);
        throw EntryException(_classifyError(e));
      }
      // Build entity locally — PUT returns 204 No Content.
      return EntryEntity(
        id: entryId,
        vaultId: vaultId,
        label: label,
        description: description,
        icon: icon,
        type: type,
        urlDomain: urlDomain,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
    } finally {
      if (vaultKey != null) {
        vaultKey.fillRange(0, vaultKey.length, 0);
      }
    }
  }

  /// Wraps the vault datasource's wrappedVK lookup with our typed error
  /// classifier so the entry-level cubit only ever sees [EntryException]s.
  Future<String> _fetchWrappedVK(String vaultId) async {
    try {
      return await vaultDatasource.getVaultWrappedKey(vaultId);
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'wrappedVK fetch failed',
          error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    }
  }

  Future<EntryDetailModel> _fetchDetail(String vaultId, String entryId) async {
    try {
      return await entryDatasource.getEntry(vaultId, entryId);
    } on DioException catch (e, s) {
      AppLogger.e('Entry', 'getEntry failed', error: e, stackTrace: s);
      throw EntryException(_classifyError(e));
    }
  }

  /// Maps a [DioException] to a typed [EntryErrorKind].
  EntryErrorKind _classifyError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return EntryErrorKind.networkError;
    }

    final status = e.response?.statusCode;
    return switch (status) {
      404 => EntryErrorKind.notFound,
      403 => EntryErrorKind.forbidden,
      400 => EntryErrorKind.validation,
      _ => EntryErrorKind.unknown,
    };
  }
}
