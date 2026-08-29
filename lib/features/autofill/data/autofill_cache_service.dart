import 'package:flutter/services.dart';

import '../../../core/utils/app_logger.dart';
import '../../vault/data/models/member_sync_models.dart';
import '../../vault/data/services/local_current_entry_service.dart';
import '../../vault/domain/entities/entry_entity.dart';
import '../../vault/domain/entities/member_index_entry.dart';
import '../../vault/data/services/member_index_preparation_service.dart';
import '../../vault/data/services/member_sync_service.dart';
import '../domain/autofill_cache_invalidator.dart';
import '../domain/autofill_record.dart';
import 'autofill_cache_bridge.dart';

/// Builds the native AutoFill cache from server ciphertext while the vault is
/// already unlocked. Native code immediately re-encrypts the records with a
/// dedicated platform key; this service never persists plaintext or key
/// material and never sends it to analytics or logs.
class AutoFillCacheService
    implements AutoFillCacheInvalidator, AutoFillPreparedCacheSynchronizer {
  AutoFillCacheService({
    required MemberIndexPreparer indexPreparation,
    required LocalCurrentEntryService localEntries,
    required AutoFillCacheBridge bridge,
    required MemberIndexReader memberIndex,
  }) : _indexPreparation = indexPreparation,
       _localEntries = localEntries,
       _bridge = bridge,
       _memberIndex = memberIndex;

  final MemberIndexPreparer _indexPreparation;
  final LocalCurrentEntryService _localEntries;
  final AutoFillCacheBridge _bridge;
  final MemberIndexReader _memberIndex;

  Future<void> _pendingOperation = Future<void>.value();
  Future<void> _sessionActivation = Future<void>.value();
  int _generation = 0;
  bool _accessRevoked = true;
  bool _nativeBridgeUnavailable = false;
  int? _sessionToken;
  int? _cleanupToken;

  Future<void> beginSession() {
    final generation = ++_generation;
    _accessRevoked = false;
    _nativeBridgeUnavailable = false;
    _sessionToken = null;
    _cleanupToken = null;
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
        await _synchronizeOnce(
          privateKey,
          generation,
          sessionToken,
          ensureFreshIndex: false,
        );
      }),
    );
  }

  @override
  Future<void> revokeAccess() async {
    final operationGeneration = ++_generation;
    _accessRevoked = true;
    final previousSessionToken = _sessionToken;
    _sessionToken = null;
    _cleanupToken = previousSessionToken ?? _cleanupToken;
    _sessionActivation = Future<void>.value();
    try {
      // Intentionally bypass [_pendingOperation]. Native code serializes this
      // key/file revocation against a replacement but does not wait for the
      // credential-identity API, which may never call back on a broken host.
      final cleanupToken = await _bridge.revokeCacheAccess();
      if (operationGeneration == _generation && _accessRevoked) {
        _cleanupToken = cleanupToken;
        _nativeBridgeUnavailable = false;
      }
    } on MissingPluginException {
      // Test hosts and unsupported platforms have no credential provider, so
      // there is no native cache or key left to revoke.
      if (operationGeneration == _generation && _accessRevoked) {
        _nativeBridgeUnavailable = true;
      }
    }
    // Detach future sessions from an identity-maintenance call that may still
    // be waiting for an OS callback. Native session tokens make every late
    // mutation from the previous queue stale and therefore harmless.
    if (operationGeneration == _generation && _accessRevoked) {
      _pendingOperation = Future<void>.value();
    }
  }

  @override
  Future<void> clear() async {
    // A mutation can race the fire-and-forget unlock synchronization. Await
    // the raw activation future so a failed native session cannot turn this
    // security boundary into a successful no-op.
    await _sessionActivation;
    ++_generation;
    final token = _sessionToken ?? _cleanupToken;
    if (token == null) {
      if (_nativeBridgeUnavailable) return;
      if (_accessRevoked) {
        _cleanupToken = await _bridge.revokeCacheAccess();
        return;
      }
      throw StateError('AutoFill cache session is unavailable');
    }
    await _enqueue(() async {
      try {
        await _clearNative(token);
      } catch (_) {
        if (!_accessRevoked) rethrow;
        // A failed/timed-out revoke may have committed a newer native fence,
        // making the old session token stale. Commit another idempotent revoke
        // as the emergency deny; never treat a stale-token no-op as success.
        _cleanupToken = await _bridge.revokeCacheAccess();
      }
    });
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
        await _synchronizeOnce(
          privateKey,
          generation,
          sessionToken,
          ensureFreshIndex: true,
        );
      }),
    );
  }

  /// Rebuilds from indexes already installed by the combined Member sync.
  /// This path performs no HTTP request and is used for delta/reconnect repair.
  ///
  /// Unlike foreground warm-up synchronization, this authoritative repair
  /// propagates every failure. Callers must not acknowledge a remote
  /// invalidation until the native provider has confirmed the deny/rebuild.
  @override
  Future<void> synchronizePrepared({
    required Uint8List privateKey,
    required Iterable<String> vaultIds,
  }) async {
    if (privateKey.isEmpty) {
      await clear();
      return;
    }
    if (_accessRevoked) return;
    final generation = ++_generation;
    final activation = _sessionActivation;
    final preparedVaultIds = Set<String>.unmodifiable(vaultIds);
    await _enqueue(() async {
      await activation;
      if (_accessRevoked) return;
      if (generation != _generation) {
        throw StateError('AutoFill repair was superseded');
      }
      final sessionToken = _sessionToken;
      if (sessionToken == null) {
        throw StateError('AutoFill cache session is unavailable');
      }
      await _clearNative(sessionToken);
      if (_accessRevoked) return;
      if (generation != _generation) {
        throw StateError('AutoFill repair was superseded');
      }
      final completed = await _replaceFromCurrentIndexes(
        privateKey,
        generation,
        sessionToken,
        preparedVaultIds,
      );
      if (!completed) {
        throw StateError('AutoFill repair was superseded');
      }
    });
  }

  Future<void> _activateSession(int generation) async {
    try {
      final token = await _bridge.beginCacheSession();
      if (_accessRevoked) {
        _cleanupToken = await _bridge.revokeCacheAccess();
        return;
      }
      if (generation != _generation) {
        // A newer active beginSession already rotated the native generation.
        // Revoking globally here would let the old callback deny that newer
        // session. Its stale token is unusable and generation cleanup is native.
        return;
      }
      _cleanupToken = null;
      _nativeBridgeUnavailable = false;
      _sessionToken = token;
    } on MissingPluginException {
      if (generation == _generation) {
        _accessRevoked = true;
        _nativeBridgeUnavailable = true;
      }
      return;
    } catch (_) {
      if (generation == _generation) {
        _accessRevoked = true;
        _nativeBridgeUnavailable = false;
      }
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
    int sessionToken, {
    required bool ensureFreshIndex,
  }) async {
    try {
      final vaults = ensureFreshIndex
          ? await _indexPreparation.prepare(privateKey, ensureFresh: true)
          : await _indexPreparation.prepare(privateKey);
      await _replaceFromCurrentIndexes(
        privateKey,
        generation,
        sessionToken,
        vaults.map((vault) => vault.id).toSet(),
      );
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

  Future<bool> _replaceFromCurrentIndexes(
    Uint8List privateKey,
    int generation,
    int sessionToken,
    Set<String> vaultIds,
  ) async {
    final records = <AutoFillRecord>[];
    final authority = _AutoFillManifestBuilder();
    for (final vaultId in vaultIds) {
      if (_accessRevoked || generation != _generation) return false;
      final eligible = {
        for (final entry in _memberIndex.entries(vaultId))
          if (!entry.corrupt &&
              entry.state == MemberEntryState.active &&
              entry.entryType == EntryType.credential.toWire() &&
              entry.autofillDomains.isNotEmpty)
            entry.entryId: entry,
      };
      if (eligible.isEmpty) continue;
      for (final index in eligible.values) {
        LocalCurrentEntryReveal? revealed;
        try {
          revealed = await _localEntries.revealCurrentWithAuthority(
            vaultId: vaultId,
            entryId: index.entryId,
            memberPrivateKey: privateKey,
          );
          final snapshot = revealed.snapshot;
          final entry = snapshot.entry;
          if (entry['id'] != index.entryId ||
              entry['organizationId'] !=
                  revealed.accessContext.organizationId ||
              entry['vaultId'] != vaultId ||
              entry['state'] != 'active' ||
              entry['currentRevision'] != index.revision ||
              entry['currentKeyVersion'] != index.currentKeyVersion) {
            throw const FormatException(
              'Local AutoFill Entry authority mismatch',
            );
          }
          if (revealed.accessContext.offlinePolicy == 'disabled') continue;
          final payload = CredentialPayload.fromJson(snapshot.payload);
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
          authority.add(
            context: revealed.accessContext,
            entryId: index.entryId,
            revision: index.revision,
            keyVersion: index.currentKeyVersion,
          );
          records.add(
            AutoFillRecord(
              id: index.entryId,
              organizationId: revealed.accessContext.organizationId,
              vaultId: vaultId,
              revision: index.revision,
              keyVersion: index.currentKeyVersion,
              label: index.memberLabel,
              username: payload.username,
              password: payload.password,
              domains: domains,
            ),
          );
        } finally {
          revealed?.clear();
        }
      }
    }
    if (_accessRevoked || generation != _generation) return false;
    if (records.isEmpty) return true;
    await _bridge.replaceCache(
      AutoFillCachePayload(manifest: authority.build(), records: records),
      sessionToken: sessionToken,
    );
    AppLogger.i('AutoFill', 'Native cache synchronized');
    return true;
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

final class _AutoFillManifestBuilder {
  MemberOfflineAccessContext? _profile;
  final Map<String, MemberOfflineAccessContext> _vaultContexts = {};
  final Map<String, Map<String, AutoFillEntryAuthority>> _entries = {};

  void add({
    required MemberOfflineAccessContext context,
    required String entryId,
    required String revision,
    required int keyVersion,
  }) {
    final profile = _profile;
    if (profile != null && !_sameProfile(profile, context)) {
      throw const FormatException('AutoFill profile authority mismatch');
    }
    final currentVault = _vaultContexts[context.vaultId];
    if (currentVault != null && !_sameVault(currentVault, context)) {
      throw const FormatException('AutoFill Vault authority mismatch');
    }
    _profile ??= context;
    _vaultContexts[context.vaultId] = context;
    final entries = _entries.putIfAbsent(
      context.vaultId,
      () => <String, AutoFillEntryAuthority>{},
    );
    if (entries.containsKey(entryId)) {
      throw const FormatException('Duplicate AutoFill Entry authority');
    }
    entries[entryId] = AutoFillEntryAuthority(
      revision: revision,
      keyVersion: keyVersion,
    );
  }

  AutoFillCacheManifest build() {
    final profile = _profile;
    if (profile == null || _entries.isEmpty) {
      throw const FormatException('Missing AutoFill cache authority');
    }
    return AutoFillCacheManifest(
      principalId: profile.principalId,
      organizationId: profile.organizationId,
      organizationMembershipGeneration:
          profile.organizationMembershipGeneration,
      offlinePolicy: profile.offlinePolicy,
      offlinePolicyVersion: profile.offlinePolicyVersion,
      vaults: {
        for (final entry in _entries.entries)
          entry.key: AutoFillVaultAuthority(
            contextVersion: _vaultContexts[entry.key]!.contextVersion,
            memberId: _vaultContexts[entry.key]!.memberId,
            memberKeyGeneration: _vaultContexts[entry.key]!.memberKeyGeneration,
            vaultKeyVersion: _vaultContexts[entry.key]!.vaultKeyVersion,
            memberRecipientKeyVersion:
                _vaultContexts[entry.key]!.memberRecipientKeyVersion,
            memberRecipientKeyFingerprint:
                _vaultContexts[entry.key]!.memberRecipientKeyFingerprint,
            issuedAt: _vaultContexts[entry.key]!.issuedAt,
            notAfter: _vaultContexts[entry.key]!.notAfter,
            entries: Map<String, AutoFillEntryAuthority>.unmodifiable(
              entry.value,
            ),
          ),
      },
    );
  }

  bool _sameProfile(
    MemberOfflineAccessContext left,
    MemberOfflineAccessContext right,
  ) =>
      left.principalId == right.principalId &&
      left.organizationId == right.organizationId &&
      left.organizationMembershipGeneration ==
          right.organizationMembershipGeneration &&
      left.offlinePolicy == right.offlinePolicy &&
      left.offlinePolicyVersion == right.offlinePolicyVersion;

  bool _sameVault(
    MemberOfflineAccessContext left,
    MemberOfflineAccessContext right,
  ) =>
      _sameProfile(left, right) &&
      left.contextVersion == right.contextVersion &&
      left.vaultId == right.vaultId &&
      left.memberId == right.memberId &&
      left.memberKeyGeneration == right.memberKeyGeneration &&
      left.vaultKeyVersion == right.vaultKeyVersion &&
      left.memberRecipientKeyVersion == right.memberRecipientKeyVersion &&
      left.memberRecipientKeyFingerprint ==
          right.memberRecipientKeyFingerprint &&
      left.issuedAt == right.issuedAt &&
      left.notAfter == right.notAfter;
}
