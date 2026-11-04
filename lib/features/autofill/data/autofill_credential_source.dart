import 'dart:typed_data';

import '../../vault/data/models/member_sync_models.dart';
import '../../vault/data/services/local_current_entry_service.dart';
import '../../vault/data/services/member_sync_service.dart';
import '../../vault/domain/entities/member_index_entry.dart';
import '../domain/autofill_domain.dart';

enum AutoFillCredentialFailure {
  invalidHost,
  staleSelection,
  bindingMismatch,
  expired,
  disposed,
}

final class AutoFillCredentialException implements Exception {
  const AutoFillCredentialException(this.kind);
  final AutoFillCredentialFailure kind;
}

final class AutoFillCandidate {
  const AutoFillCandidate._({
    required this.vaultId,
    required this.entryId,
    required this.label,
    required this.revision,
    required this.keyVersion,
    required this.domains,
    required Object owner,
    required void Function() validateRequest,
  }) : _validateRequest = validateRequest,
       _owner = owner;
  final String vaultId;
  final String entryId;
  final String label;
  final String revision;
  final int keyVersion;
  final List<String> domains;
  final void Function() _validateRequest;
  final Object _owner;
}

final class AutoFillSelectedCredential {
  AutoFillSelectedCredential._(
    this.candidate,
    this.selectedHost,
    this._reveal,
    this._validate,
  );
  final AutoFillCandidate candidate;
  final String selectedHost;
  final LocalCurrentEntryReveal _reveal;
  final void Function() _validate;
  bool _open = true;
  MemberOfflineAccessContext get accessContext => _reveal.accessContext;
  String get username => _field('username');
  String get password => _field('password');
  String _field(String name) {
    if (!_open) {
      throw const AutoFillCredentialException(
        AutoFillCredentialFailure.disposed,
      );
    }
    _validate();
    return _reveal.snapshot.payload[name] as String;
  }
}

class AutoFillCredentialSource {
  AutoFillCredentialSource({
    required MemberIndexReader memberIndex,
    required LocalCurrentEntryService localEntries,
  }) : _memberIndex = memberIndex,
       _localEntries = localEntries;
  final MemberIndexReader _memberIndex;
  final LocalCurrentEntryService _localEntries;

  Future<List<AutoFillCandidate>> candidates({
    required Iterable<String> vaultIds,
    required Set<String> verifiedHosts,
    required void Function() validateRequest,
  }) async {
    // Origin verification belongs to the native request owner. This boundary
    // accepts exact canonical hosts, never URLs that could hide HTTP transport.
    if (verifiedHosts.any((host) => normalizeAutoFillDomain(host) != host)) {
      throw const AutoFillCredentialException(
        AutoFillCredentialFailure.invalidHost,
      );
    }
    final hosts = Set<String>.of(verifiedHosts);
    return _candidates(
      vaultIds,
      validateRequest,
      (domain) => hosts.contains(domain),
    );
  }

  Future<List<AutoFillCandidate>> manualCandidates({
    required Iterable<String> vaultIds,
    required void Function() validateRequest,
  }) => _candidates(vaultIds, validateRequest, (_) => true);

  Future<List<AutoFillCandidate>> _candidates(
    Iterable<String> vaultIds,
    void Function() validateRequest,
    bool Function(String) matches,
  ) async {
    validateRequest();
    final result = <AutoFillCandidate>[];
    for (final vaultId in vaultIds.toSet()) {
      await _memberIndex.waitForCurrent(vaultId);
      validateRequest();
      for (final entry in _memberIndex.entries(vaultId)) {
        if (!_eligible(entry)) continue;
        final domains = _domains(entry).where(matches).toList()..sort();
        if (domains.isEmpty) continue;
        result.add(
          AutoFillCandidate._(
            vaultId: vaultId,
            entryId: entry.entryId,
            label: entry.memberLabel,
            revision: entry.revision,
            keyVersion: entry.currentKeyVersion,
            domains: List.unmodifiable(domains),
            owner: this,
            validateRequest: validateRequest,
          ),
        );
      }
    }
    validateRequest();
    result.sort((a, b) {
      final label = a.label.compareTo(b.label);
      if (label != 0) return label;
      final vault = a.vaultId.compareTo(b.vaultId);
      return vault != 0 ? vault : a.entryId.compareTo(b.entryId);
    });
    return List.unmodifiable(result);
  }

  /// The completion owner rechecks native origin and durable revocation under
  /// its handoff fence. No caller may retain the credential beyond this scope.
  Future<void> withCredential({
    required AutoFillCandidate candidate,
    required String selectedHost,
    required Uint8List memberPrivateKey,
    required void Function() validateRequest,
    required Future<void> Function(AutoFillSelectedCredential) complete,
  }) async {
    void validate() {
      candidate._validateRequest();
      validateRequest();
      if (!identical(candidate._owner, this) ||
          !candidate.domains.contains(selectedHost) ||
          !_memberIndex
              .entries(candidate.vaultId)
              .any(
                (entry) =>
                    _eligible(entry) &&
                    entry.entryId == candidate.entryId &&
                    entry.revision == candidate.revision &&
                    entry.currentKeyVersion == candidate.keyVersion &&
                    _domains(entry).contains(selectedHost),
              )) {
        throw const AutoFillCredentialException(
          AutoFillCredentialFailure.staleSelection,
        );
      }
    }

    validate();
    LocalCurrentEntryReveal? reveal;
    AutoFillSelectedCredential? credential;
    try {
      reveal = await _localEntries.revealCurrentWithAuthority(
        vaultId: candidate.vaultId,
        entryId: candidate.entryId,
        memberPrivateKey: memberPrivateKey,
      );
      validate();
      final snapshot = reveal.snapshot;
      final context = reveal.accessContext;
      if (snapshot.entry['id'] != candidate.entryId ||
          snapshot.entry['vaultId'] != candidate.vaultId ||
          context.vaultId != candidate.vaultId ||
          snapshot.entry['organizationId'] != context.organizationId ||
          snapshot.entry['currentRevision'] != candidate.revision ||
          snapshot.entry['currentKeyVersion'] != candidate.keyVersion ||
          snapshot.entry['state'] != 'active' ||
          snapshot.payload['username'] is! String ||
          snapshot.payload['password'] is! String) {
        throw const AutoFillCredentialException(
          AutoFillCredentialFailure.bindingMismatch,
        );
      }
      void validateHandoff() {
        validate();
        final now = DateTime.now().toUtc();
        if (context.offlinePolicy == 'disabled' ||
            now.isBefore(context.issuedAt) ||
            !now.isBefore(context.notAfter)) {
          throw const AutoFillCredentialException(
            AutoFillCredentialFailure.expired,
          );
        }
      }

      validateHandoff();
      credential = AutoFillSelectedCredential._(
        candidate,
        selectedHost,
        reveal,
        validateHandoff,
      );
      await complete(credential);
    } finally {
      if (credential != null) credential._open = false;
      reveal?.clear();
    }
  }

  static bool _eligible(MemberIndexEntry entry) =>
      !entry.corrupt &&
      entry.state == MemberEntryState.active &&
      entry.entryType == 1;
  static Set<String> _domains(MemberIndexEntry entry) => entry.autofillDomains
      .map(normalizeAutoFillDomain)
      .whereType<String>()
      .toSet();
}
