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

  /// The Credential's username in stored account form, or null when empty.
  final String? account;
}

/// Finds discoverable Credentials of a sign-in provider in the unlocked local
/// Member index. Only index candidates whose AutoFill domain belongs to the
/// provider are opened, one at a time from the local encrypted generation,
/// to read `discoverable` and the username; each snapshot is cleared
/// immediately. Nothing is sent to the backend.
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
          final policy = snapshot.secret['agentVisibilityPolicy'];
          final username = snapshot.payload['username'];
          if (policy is! Map || policy['discoverable'] != true) continue;
          result.add(
            SignInProviderCandidate(
              reference: SignInEntryReference(
                vaultId: vaultId.toLowerCase(),
                entryId: entry.entryId.toLowerCase(),
              ),
              label: entry.memberLabel,
              account: username is String
                  ? SignInMethodField.normalizeAccount(username)
                  : null,
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
