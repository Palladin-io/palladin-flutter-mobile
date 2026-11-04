import 'dart:typed_data';

import '../../domain/entities/entry_entity.dart';
import '../../domain/entities/member_index_entry.dart';
import '../../domain/entities/sign_in_method.dart';
import 'local_current_entry_service.dart';
import 'member_sync_service.dart';

/// An existing Palladin Credential the user may explicitly link as the
/// provider account of a sign-in method.
final class SignInProviderCandidate {
  const SignInProviderCandidate({
    required this.reference,
    required this.label,
    required this.account,
  });

  final SignInEntryReference reference;
  final String label;

  /// The revealed Credential's username in stored account form.
  final String account;
}

/// Finds discoverable Credentials of a sign-in provider in the unlocked local
/// Member index. Only index candidates whose AutoFill domain belongs to the
/// provider are opened, one at a time from the local encrypted generation.
/// The revealed head must itself still be a discoverable Credential whose
/// `urlDomain` belongs to the provider and whose username is non-empty; each
/// snapshot is cleared immediately. Nothing is sent to the backend.
class SignInCandidateService {
  SignInCandidateService({
    required MemberIndexReader index,
    required LocalCurrentEntryService entries,
  }) : _index = index,
       _entries = entries;

  /// Bounds the decryption work of one lookup.
  static const maximumOpened = 20;

  final MemberIndexReader _index;
  final LocalCurrentEntryService _entries;

  Future<List<SignInProviderCandidate>> candidates({
    required SignInProvider provider,
    required List<String> vaultIds,
    required SignInEntryReference exclude,
    required Uint8List memberPrivateKey,
  }) async {
    final matches = <(String, MemberIndexEntry)>[];
    for (final vaultId in vaultIds) {
      for (final entry in _index.entries(vaultId)) {
        if (entry.state != MemberEntryState.active ||
            entry.corrupt ||
            entry.entryType != EntryType.credential.index ||
            (vaultId == exclude.vaultId && entry.entryId == exclude.entryId) ||
            !entry.autofillDomains.any((domain) => _owns(provider, domain))) {
          continue;
        }
        matches.add((vaultId, entry));
      }
    }
    final result = <SignInProviderCandidate>[];
    for (final (vaultId, entry) in matches.take(maximumOpened)) {
      final key = Uint8List.fromList(memberPrivateKey);
      try {
        final snapshot = await _entries.revealCurrent(
          vaultId: vaultId,
          entryId: entry.entryId,
          memberPrivateKey: key,
        );
        try {
          // Member sync may have advanced this Entry since the index scan, so
          // every criterion is rechecked on the revealed head itself.
          final policy = snapshot.secret['agentVisibilityPolicy'];
          final urlDomain = snapshot.payload['urlDomain'];
          final account = switch (snapshot.payload['username']) {
            final String username => SignInMethodField.normalizeAccount(
              username,
            ),
            _ => null,
          };
          if (snapshot.secret['entryType'] != EntryType.credential.toWire() ||
              policy is! Map ||
              policy['discoverable'] != true ||
              urlDomain is! String ||
              !_owns(provider, urlDomain) ||
              account == null) {
            continue;
          }
          result.add(
            SignInProviderCandidate(
              reference: SignInEntryReference(
                vaultId: vaultId.toLowerCase(),
                entryId: entry.entryId.toLowerCase(),
              ),
              label: entry.memberLabel,
              account: account,
            ),
          );
        } finally {
          snapshot.clear();
        }
      } catch (_) {
        // An unreadable, stale or over-long candidate is simply not offered.
        continue;
      } finally {
        key.fillRange(0, key.length, 0);
      }
    }
    result.sort(
      (left, right) =>
          left.label.toLowerCase().compareTo(right.label.toLowerCase()),
    );
    return result;
  }

  static bool _owns(SignInProvider provider, String domain) {
    final uri = Uri.tryParse(
      domain.contains('://') ? domain : 'https://$domain',
    );
    final host = uri?.host ?? '';
    return host.isNotEmpty && provider.ownsHost(host);
  }
}
