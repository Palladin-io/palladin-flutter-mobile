import 'package:flutter/services.dart';

import '../../../core/utils/app_logger.dart';
import '../../vault/domain/entities/entry_entity.dart';
import '../../vault/domain/entities/member_index_entry.dart';
import '../../vault/domain/repositories/entry_repository.dart';
import '../../vault/data/services/member_index_preparation_service.dart';
import '../../vault/data/services/member_sync_service.dart';
import '../domain/autofill_cache_invalidator.dart';
import '../domain/autofill_record.dart';
import 'autofill_cache_bridge.dart';

/// Builds the native AutoFill cache from server ciphertext while the vault is
/// already unlocked. Native code immediately re-encrypts the records with a
/// dedicated platform key; this service never persists plaintext or key
/// material and never sends it to analytics or logs.
class AutoFillCacheService implements AutoFillCacheInvalidator {
  AutoFillCacheService({
    required MemberIndexPreparer indexPreparation,
    required EntryRepository entryRepository,
    required AutoFillCacheBridge bridge,
    required MemberIndexReader memberIndex,
  }) : _indexPreparation = indexPreparation,
       _entryRepository = entryRepository,
       _bridge = bridge,
       _memberIndex = memberIndex;

  final MemberIndexPreparer _indexPreparation;
  final EntryRepository _entryRepository;
  final AutoFillCacheBridge _bridge;
  final MemberIndexReader _memberIndex;

  Future<void> _pendingOperation = Future<void>.value();
  Future<void> _sessionActivation = Future<void>.value();
  int _generation = 0;
  bool _accessRevoked = true;
  int? _sessionToken;
  int? _cleanupToken;

  Future<void> beginSession() {
    final generation = ++_generation;
    _accessRevoked = false;
    _sessionToken = null;
    final activation = _activateSession(generation);
    _sessionActivation = activation;
    return _bestEffort(activation);
  }

  Future<void> synchronize({required Uint8List privateKey}) {
    if (privateKey.isEmpty || _accessRevoked) return Future<void>.value();
    final generation = ++_generation;
    final activation = _sessionActivation;
    return _bestEffort(
      _enqueue(() async {
        await activation;
        if (_accessRevoked || generation != _generation) return;
        final sessionToken = _sessionToken;
        if (sessionToken == null) return;
        await _clearNative(sessionToken);
        if (_accessRevoked || generation != _generation) return;
        await _synchronizeOnce(privateKey, generation, sessionToken);
      }),
    );
  }

  @override
  Future<void> revokeAccess() async {
    ++_generation;
    _accessRevoked = true;
    _sessionToken = null;
    _sessionActivation = Future<void>.value();
    try {
      // Intentionally bypass [_pendingOperation]. Native code serializes this
      // key/file revocation against a replacement but does not wait for the
      // credential-identity API, which may never call back on a broken host.
      _cleanupToken = await _bridge.revokeCacheAccess();
    } on MissingPluginException {
      // Test hosts and unsupported platforms have no credential provider, so
      // there is no native cache or key left to revoke.
    }
    // Detach future sessions from an identity-maintenance call that may still
    // be waiting for an OS callback. Native session tokens make every late
    // mutation from the previous queue stale and therefore harmless.
    _pendingOperation = Future<void>.value();
  }

  @override
  Future<void> clear() {
    ++_generation;
    final token = _sessionToken ?? _cleanupToken;
    if (token == null) return Future<void>.value();
    return _enqueue(() => _clearNative(token));
  }

  Future<void> clearAndSynchronize({required Uint8List privateKey}) {
    if (privateKey.isEmpty) return clear();
    if (_accessRevoked) return Future<void>.value();
    final generation = ++_generation;
    final activation = _sessionActivation;
    return _bestEffort(
      _enqueue(() async {
        await activation;
        if (_accessRevoked || generation != _generation) return;
        final sessionToken = _sessionToken;
        if (sessionToken == null) return;
        await _clearNative(sessionToken);
        if (_accessRevoked || generation != _generation) return;
        await _synchronizeOnce(privateKey, generation, sessionToken);
      }),
    );
  }

  Future<void> _activateSession(int generation) async {
    try {
      final token = await _bridge.beginCacheSession();
      if (_accessRevoked || generation != _generation) {
        _cleanupToken = await _bridge.revokeCacheAccess();
        return;
      }
      _cleanupToken = null;
      _sessionToken = token;
    } on MissingPluginException {
      return;
    } catch (_) {
      if (generation == _generation) _accessRevoked = true;
      rethrow;
    }
  }

  Future<void> _clearNative(int sessionToken) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 1; attempt <= _clearAttempts; attempt++) {
      try {
        await _bridge.clearCache(sessionToken: sessionToken);
        return;
      } on MissingPluginException {
        // Unit/widget test hosts do not install the native bridge.
        return;
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        AppLogger.w(
          'AutoFill',
          'Native cache clear failed '
              '(attempt $attempt/$_clearAttempts): ${error.runtimeType}',
        );
      }
    }
    if (lastError != null && lastStackTrace != null) {
      Error.throwWithStackTrace(lastError, lastStackTrace);
    }
  }

  Future<void> _bestEffort(Future<void> operation) async {
    try {
      await operation;
    } catch (error) {
      AppLogger.w(
        'AutoFill',
        'Cache synchronization aborted: ${error.runtimeType}',
      );
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _pendingOperation.then((_) => operation());
    _pendingOperation = next.catchError((_) {});
    return next;
  }

  Future<void> _synchronizeOnce(
    Uint8List privateKey,
    int generation,
    int sessionToken,
  ) async {
    try {
      final records = <AutoFillRecord>[];
      final vaults = await _indexPreparation.prepare(privateKey);
      for (final vault in vaults) {
        if (_accessRevoked || generation != _generation) return;
        final eligible = {
          for (final entry in _memberIndex.entries(vault.id))
            if (!entry.corrupt &&
                entry.state == MemberEntryState.active &&
                entry.entryType == EntryType.credential.toWire() &&
                entry.autofillDomains.isNotEmpty)
              entry.entryId: entry,
        };
        if (eligible.isEmpty) continue;
        final revealed = await _entryRepository.revealAutoFillCredentials(
          vaultId: vault.id,
          privateKey: privateKey,
          wrappedVK: vault.wrappedVK,
        );
        for (final item in revealed) {
          final index = eligible[item.entry.id];
          if (index == null || item.entry.currentRevision != index.revision) {
            continue;
          }
          final payload = CredentialPayload.fromJson(item.payload);
          final domains =
              index.autofillDomains
                  .map(normalizeDomain)
                  .whereType<String>()
                  .toSet()
                  .toList(growable: false)
                ..sort();
          if (domains.isEmpty || payload.password.isEmpty) continue;
          if (records.length >= maximumRecords) {
            throw StateError('AutoFill cache exceeds the device budget');
          }
          records.add(
            AutoFillRecord(
              id: item.entry.id,
              label: index.memberLabel,
              username: payload.username,
              password: payload.password,
              domains: domains,
            ),
          );
        }
      }
      if (_accessRevoked || generation != _generation) return;
      await _bridge.replaceCache(records, sessionToken: sessionToken);
      AppLogger.i('AutoFill', 'Native cache synchronized');
    } on MissingPluginException {
      // Unit/widget test hosts do not install the native bridge.
    } catch (error) {
      // Keep errors typed-only: platform exceptions can contain native data.
      AppLogger.w(
        'AutoFill',
        'Cache synchronization failed: ${error.runtimeType}',
      );
    }
  }

  static String? normalizeDomain(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    try {
      if (value.codeUnits.any((unit) => unit > 0x7f)) return null;
      if (RegExp(
        r'^[a-z][a-z0-9+.-]*://[^/?#]+:[0-9]+(?:[/?#]|$)',
        caseSensitive: false,
      ).hasMatch(value)) {
        return null;
      }
      final uri = Uri.parse(value.contains('://') ? value : 'https://$value');
      if (uri.scheme != 'http' && uri.scheme != 'https') return null;
      if (uri.userInfo.isNotEmpty ||
          uri.hasPort ||
          uri.authority.contains(':')) {
        return null;
      }
      var host = uri.host.toLowerCase();
      while (host.endsWith('.')) {
        host = host.substring(0, host.length - 1);
      }
      if (host.isEmpty ||
          !host.contains('.') ||
          host.contains('..') ||
          host.startsWith('.') ||
          host
              .split('.')
              .any(
                (label) =>
                    label.isEmpty ||
                    label.length > 63 ||
                    label.startsWith('-') ||
                    label.endsWith('-') ||
                    !RegExp(r'^[a-z0-9-]+$').hasMatch(label),
              )) {
        return null;
      }
      return host;
    } on FormatException {
      return null;
    }
  }

  static const _clearAttempts = 3;
  static const maximumRecords = 2000;
}
