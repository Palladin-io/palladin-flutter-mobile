import 'dart:convert';
import 'dart:typed_data';

import '../../vault/data/models/member_sync_models.dart';
import '../../vault/data/services/local_current_entry_service.dart';
import '../../vault/data/services/member_sync_service.dart';
import '../../vault/data/services/member_sync_session_authority_provider.dart';
import '../../vault/domain/entities/entry_entity.dart';
import '../../vault/domain/entities/member_index_entry.dart';
import '../domain/autofill_incremental.dart';
import '../domain/autofill_preparation.dart';
import '../domain/autofill_record.dart';
import 'autofill_cache_bridge.dart';
import '../domain/autofill_domain.dart';

/// Keeps only acknowledged coordinates/revisions in Dart. Unchanged credential
/// bodies remain native ciphertext; writer keys never cross the native bridge.
class AutoFillIncrementalPublisher {
  AutoFillIncrementalPublisher({
    required AutoFillIncrementalCacheBridge bridge,
    required MemberAutoFillMetadataReader metadata,
    required MemberSyncSessionAuthorityProvider authority,
    required LocalCurrentEntryService entries,
  }) : _bridge = bridge,
       _metadata = metadata,
       _authority = authority,
       _entries = entries;

  final AutoFillIncrementalCacheBridge _bridge;
  final MemberAutoFillMetadataReader _metadata;
  final MemberSyncSessionAuthorityProvider _authority;
  final LocalCurrentEntryService _entries;
  int _epoch = 0;
  int? _sessionToken;
  int? _writerEpoch;
  AutoFillCacheBase? _base;
  Map<AutoFillEntryCoordinate, String> _observed = {};
  Set<AutoFillEntryCoordinate> _present = {};
  final Set<String> _denies = {};
  String? _profileBinding;
  int? _acknowledgedReadGeneration;
  int? _acknowledgedContentRevision;
  int? _acknowledgedSessionRevision;
  Set<String> _acknowledgedVaultIds = {};

  bool canCheckWithoutDenial(Iterable<String> vaultIds) {
    final requested = vaultIds.toSet();
    return _base != null &&
        _writerEpoch != null &&
        _denies.isEmpty &&
        _acknowledgedReadGeneration != null &&
        _acknowledgedContentRevision != null &&
        _acknowledgedSessionRevision == _authority.sessionRevision &&
        requested.length == _acknowledgedVaultIds.length &&
        requested.containsAll(_acknowledgedVaultIds) &&
        _metadata.canReuseAutoFillPublication(
          readGeneration: _acknowledgedReadGeneration!,
          contentRevision: _acknowledgedContentRevision!,
          vaultIds: requested,
        );
  }

  Future<void> beginSession(int token) async {
    final ending = endSession();
    final epoch = _epoch;
    await ending;
    if (_epoch != epoch) {
      throw StateError('AutoFill writer activation superseded');
    }
    final writer = await _bridge.beginWriterSession(sessionToken: token);
    if (_epoch != epoch) {
      await _bridge.endWriterSession(writerEpoch: writer);
      throw StateError('AutoFill writer activation superseded');
    }
    _sessionToken = token;
    _writerEpoch = writer;
  }

  Future<void> endSession() {
    ++_epoch;
    final writer = _writerEpoch;
    _writerEpoch = null;
    _sessionToken = null;
    forgetBase();
    return writer == null
        ? Future<void>.value()
        : _bridge.endWriterSession(writerEpoch: writer);
  }

  void forgetBase() {
    _base = null;
    _observed = {};
    _present = {};
    _denies.clear();
    _profileBinding = null;
    _acknowledgedReadGeneration = null;
    _acknowledgedContentRevision = null;
    _acknowledgedSessionRevision = null;
    _acknowledgedVaultIds = {};
  }

  /// Returns false only when no verified native base can be denied. The caller
  /// must commit the existing global deny before any remote mutation starts.
  Future<bool> deny(Set<AutoFillEntryCoordinate>? scope) async {
    final base = _base;
    final writer = _writerEpoch;
    if (base == null || writer == null) return false;
    final epoch = _epoch;
    final coordinates = scope == null
        ? _present.toList()
        : scope.intersection(_present).toList();
    final denial = await _bridge.denyEntries(
      base: base,
      writerEpoch: writer,
      entries: coordinates,
    );
    _requireCurrent(epoch, () => true);
    _requireBase(denial.base);
    _base = denial.base;
    _denies.add(denial.token);
    return true;
  }

  Future<void> synchronize({
    required Uint8List privateKey,
    required Iterable<String> vaultIds,
    required bool Function() isCurrent,
    required void Function(AutoFillPreparation) onProgress,
  }) async {
    final epoch = _epoch;
    _requireCurrent(epoch, isCurrent);
    // Only a synchronous producer proof may preserve provider availability.
    // Unknown/changed authority is denied before the first asynchronous read.
    final checking = canCheckWithoutDenial(vaultIds);
    if (!checking && _base != null && _denies.isEmpty) await deny(null);
    _requireCurrent(epoch, isCurrent);
    final preparationAuthority = await _authority.captureForPreparation();
    preparationAuthority.validateCurrent();
    final claims = preparationAuthority.claims;
    _requireCurrent(epoch, isCurrent);
    if (checking && !canCheckWithoutDenial(vaultIds) && _denies.isEmpty) {
      await deny(null);
      _requireCurrent(epoch, isCurrent);
    }
    final snapshot = await _metadata.readAutoFillMetadata(
      vaultIds: vaultIds,
      authority: claims,
    );
    _requireCurrent(epoch, isCurrent);
    if (claims.offlinePolicy == 'disabled') {
      throw StateError('AutoFill offline access disabled');
    }
    final profile = jsonEncode([
      claims.principalId,
      claims.organizationId,
      claims.organizationMembershipGeneration,
      claims.offlinePolicy,
      claims.offlinePolicyVersion,
    ]);
    final full = _base == null || _profileBinding != profile;
    final candidates = <AutoFillEntryCoordinate, MemberIndexEntry>{};
    final observed = <AutoFillEntryCoordinate, String>{};
    for (final vault in snapshot.vaults.entries) {
      final binding = vault.value.context.toJson()
        ..remove('issuedAt')
        ..remove('notAfter');
      for (final entry in vault.value.entries) {
        if (entry.corrupt ||
            entry.state != MemberEntryState.active ||
            entry.entryType != EntryType.credential.toWire() ||
            entry.autofillDomains.isEmpty) {
          continue;
        }
        final coordinate = AutoFillEntryCoordinate(
          vaultId: vault.key,
          entryId: entry.entryId,
        );
        candidates[coordinate] = entry;
        observed[coordinate] = jsonEncode([
          entry.revision,
          entry.currentKeyVersion,
          binding,
        ]);
      }
    }
    final changed = candidates.keys
        .where((key) => full || _observed[key] != observed[key])
        .toList();
    final noOpCandidate =
        checking &&
        !full &&
        _denies.isEmpty &&
        snapshot.contentRevision == _acknowledgedContentRevision &&
        snapshot.readGeneration == _acknowledgedReadGeneration &&
        changed.isEmpty &&
        _observed.length == observed.length &&
        _observed.keys.every(observed.containsKey);
    if (!noOpCandidate && _base != null && _denies.isEmpty) {
      await deny(null);
      _requireCurrent(epoch, isCurrent);
    }
    final present = full
        ? <AutoFillEntryCoordinate>{}
        : _present.intersection(candidates.keys.toSet());
    final leaseContexts = {
      for (final vault in snapshot.vaults.entries)
        vault.key: vault.value.context,
    };
    final latestIssuedAt = {
      for (final vault in snapshot.vaults.entries)
        vault.key: vault.value.context.issuedAt,
    };
    void includeLease(String vaultId, MemberOfflineAccessContext context) {
      final previous = leaseContexts[vaultId]!;
      if (!_sameAuthority(previous, context) ||
          context.notAfter != context.issuedAt.add(context.leaseDuration)) {
        throw const FormatException('AutoFill authority changed');
      }
      final latest = latestIssuedAt[vaultId]!.isAfter(context.issuedAt)
          ? latestIssuedAt[vaultId]!
          : context.issuedAt;
      final earliest = previous.notAfter.isBefore(context.notAfter)
          ? previous
          : context;
      if (!latest.isBefore(earliest.notAfter)) {
        throw const FormatException('Disjoint AutoFill authority leases');
      }
      latestIssuedAt[vaultId] = latest;
      leaseContexts[vaultId] = earliest;
    }

    final records = <AutoFillRecord>[];
    var completed = 0;
    onProgress(
      AutoFillPreparation(
        noOpCandidate
            ? AutoFillPreparationPhase.checking
            : AutoFillPreparationPhase.preparing,
        examined: 0,
        total: changed.length,
      ),
    );
    try {
      for (final coordinate in changed) {
        _requireCurrent(epoch, isCurrent);
        preparationAuthority.validateCurrent();
        final index = candidates[coordinate]!;
        final revealed = await _entries.revealPreparedWithAuthority(
          authority: preparationAuthority,
          vaultId: coordinate.vaultId,
          entryId: coordinate.entryId,
          memberPrivateKey: privateKey,
        );
        try {
          _requireCurrent(epoch, isCurrent);
          preparationAuthority.validateCurrent();
          final entry = revealed.snapshot.entry;
          if (entry['id'] != coordinate.entryId ||
              entry['vaultId'] != coordinate.vaultId ||
              entry['organizationId'] != claims.organizationId ||
              entry['state'] != 'active' ||
              entry['currentRevision'] != index.revision ||
              entry['currentKeyVersion'] != index.currentKeyVersion ||
              !_sameAuthority(
                revealed.accessContext,
                snapshot.vaults[coordinate.vaultId]!.context,
              )) {
            throw const FormatException('AutoFill revealed authority changed');
          }
          includeLease(coordinate.vaultId, revealed.accessContext);
          final payload = CredentialPayload.fromJson(revealed.snapshot.payload);
          final domains =
              index.autofillDomains
                  .map(normalizeAutoFillDomain)
                  .whereType<String>()
                  .toSet()
                  .toList()
                ..sort();
          if (payload.password.isEmpty || domains.isEmpty) {
            present.remove(coordinate);
          } else {
            present.add(coordinate);
            records.add(
              AutoFillRecord(
                id: coordinate.entryId,
                organizationId: claims.organizationId,
                vaultId: coordinate.vaultId,
                revision: index.revision,
                keyVersion: index.currentKeyVersion,
                label: index.memberLabel,
                username: payload.username,
                password: payload.password,
                domains: domains,
              ),
            );
          }
        } finally {
          revealed.clear();
        }
        onProgress(
          AutoFillPreparation(
            AutoFillPreparationPhase.preparing,
            examined: ++completed,
            total: changed.length,
          ),
        );
      }
      if (present.length > maximumAutoFillRecords) {
        throw StateError('AutoFill cache exceeds device budget');
      }
      // A lease-only sync may finish during a large initial preparation. Re-read
      // complete authority, but preserve every revealed record's original lease.
      final currentSnapshot = await _metadata.readAutoFillMetadata(
        vaultIds: vaultIds,
        authority: claims,
      );
      if ((noOpCandidate &&
              snapshot.contentRevision != currentSnapshot.contentRevision) ||
          snapshot.readGeneration != currentSnapshot.readGeneration ||
          snapshot.vaults.length != currentSnapshot.vaults.length) {
        throw StateError('AutoFill metadata changed');
      }
      for (final vault in snapshot.vaults.entries) {
        final current = currentSnapshot.vaults[vault.key];
        if (current == null ||
            current.sequence != vault.value.sequence ||
            current.entries.length != vault.value.entries.length ||
            !_sameAuthority(vault.value.context, current.context)) {
          throw StateError('AutoFill metadata changed');
        }
        final entriesById = {
          for (final entry in current.entries) entry.entryId: entry,
        };
        if (vault.value.entries.any(
          (entry) => !identical(entriesById[entry.entryId], entry),
        )) {
          throw StateError('AutoFill Entry metadata changed');
        }
        includeLease(vault.key, current.context);
      }
      final leaseSnapshot = MemberAutoFillMetadata(
        readGeneration: currentSnapshot.readGeneration,
        publicationRevision: currentSnapshot.publicationRevision,
        contentRevision: currentSnapshot.contentRevision,
        vaults: {
          for (final vault in currentSnapshot.vaults.entries)
            vault.key: MemberAutoFillVaultMetadata(
              context: leaseContexts[vault.key]!,
              sequence: vault.value.sequence,
              entries: vault.value.entries,
            ),
        },
      );
      await _metadata.revalidateAutoFillMetadata(
        currentSnapshot,
        authority: claims,
      );
      final currentClaims = await _authority.current();
      if (jsonEncode([
            currentClaims.principalId,
            currentClaims.organizationId,
            currentClaims.organizationMembershipGeneration,
            currentClaims.offlinePolicy,
            currentClaims.offlinePolicyVersion,
          ]) !=
          profile) {
        throw StateError('AutoFill session authority changed');
      }
      _requireCurrent(epoch, isCurrent);
      final manifest = _manifest(claims, leaseSnapshot, candidates, present);
      onProgress(
        AutoFillPreparation(
          noOpCandidate
              ? AutoFillPreparationPhase.checking
              : AutoFillPreparationPhase.publishing,
          examined: completed,
          total: changed.length,
        ),
      );
      void validatePublication() {
        preparationAuthority.validateCurrent();
        _metadata.validateAutoFillPublication(currentSnapshot);
        _metadata.validateAutoFillPublication(leaseSnapshot);
        _requireCurrent(epoch, isCurrent);
      }

      validatePublication();
      final AutoFillCacheBase acknowledged;
      if (full) {
        acknowledged = await _bridge.replaceCacheV3(
          AutoFillCachePayload(manifest: manifest, records: records),
          sessionToken: _sessionToken!,
          writerEpoch: _writerEpoch!,
          validatePublication: validatePublication,
          base: _base,
          releasingDenies: _denies.toList(),
        );
      } else {
        acknowledged = await _bridge.applyCacheDelta(
          base: _base!,
          writerEpoch: _writerEpoch!,
          manifest: manifest,
          upserts: records,
          removals: _present.difference(present).toList(),
          releasingDenies: _denies.toList(),
          validatePublication: validatePublication,
        );
      }
      // A completed same-content renewal may have arrived during native I/O.
      // Wait outside the synchronous bridge guard, retaining original leases.
      await _metadata.revalidateAutoFillMetadata(
        currentSnapshot,
        authority: claims,
      );
      validatePublication();
      _requireBase(acknowledged, allowUnchanged: noOpCandidate);
      _base = acknowledged;
      _acknowledgedReadGeneration = currentSnapshot.readGeneration;
      _acknowledgedContentRevision = currentSnapshot.contentRevision;
      _acknowledgedSessionRevision = preparationAuthority.sessionRevision;
      _acknowledgedVaultIds = Set.unmodifiable(currentSnapshot.vaults.keys);
      _observed = observed;
      _present = present;
      _profileBinding = profile;
      _denies.clear();
      onProgress(
        AutoFillPreparation(
          present.isEmpty
              ? AutoFillPreparationPhase.empty
              : AutoFillPreparationPhase.ready,
          examined: completed,
          total: changed.length,
        ),
      );
      return;
    } finally {
      records.clear();
    }
  }

  bool _sameAuthority(
    MemberOfflineAccessContext a,
    MemberOfflineAccessContext b,
  ) {
    final left = a.toJson()
      ..remove('issuedAt')
      ..remove('notAfter');
    final right = b.toJson()
      ..remove('issuedAt')
      ..remove('notAfter');
    return jsonEncode(left) == jsonEncode(right);
  }

  void _requireBase(AutoFillCacheBase base, {bool allowUnchanged = false}) {
    if (base.generation != _sessionToken ||
        (_base != null &&
            (base.revision < _base!.revision ||
                (!allowUnchanged && base.revision == _base!.revision)))) {
      throw const FormatException('AutoFill acknowledgement base mismatch');
    }
  }

  void _requireCurrent(int epoch, bool Function() isCurrent) {
    if (epoch != _epoch ||
        _writerEpoch == null ||
        _sessionToken == null ||
        !isCurrent()) {
      throw StateError('AutoFill writer is no longer current');
    }
  }

  AutoFillCacheManifest _manifest(
    MemberSyncSessionAuthority claims,
    MemberAutoFillMetadata snapshot,
    Map<AutoFillEntryCoordinate, MemberIndexEntry> candidates,
    Set<AutoFillEntryCoordinate> present,
  ) => AutoFillCacheManifest(
    principalId: claims.principalId,
    organizationId: claims.organizationId,
    organizationMembershipGeneration: claims.organizationMembershipGeneration,
    offlinePolicy: claims.offlinePolicy,
    offlinePolicyVersion: claims.offlinePolicyVersion,
    vaults: {
      for (final vault in snapshot.vaults.entries)
        vault.key: _vaultManifest(vault.value.context, {
          for (final coordinate in present.where(
            (item) => item.vaultId == vault.key,
          ))
            coordinate.entryId: AutoFillEntryAuthority(
              revision: candidates[coordinate]!.revision,
              keyVersion: candidates[coordinate]!.currentKeyVersion,
            ),
        }),
    },
  );

  AutoFillVaultAuthority _vaultManifest(
    MemberOfflineAccessContext context,
    Map<String, AutoFillEntryAuthority> entries,
  ) => AutoFillVaultAuthority(
    contextVersion: context.contextVersion,
    memberId: context.memberId,
    memberKeyGeneration: context.memberKeyGeneration,
    vaultKeyVersion: context.vaultKeyVersion,
    memberRecipientKeyVersion: context.memberRecipientKeyVersion,
    memberRecipientKeyFingerprint: context.memberRecipientKeyFingerprint,
    issuedAt: context.issuedAt,
    notAfter: context.notAfter,
    entries: entries,
  );
}
