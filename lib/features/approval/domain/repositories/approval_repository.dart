import 'dart:typed_data';

import '../../../grants/domain/entities/grant_method.dart';
import '../entities/pending_grant.dart';

/// The wire representation of a [GrantLimit]: at most one of the two fields
/// is non-null — `(expiresAt, null)` for a TTL, `(null, queryLimit)` for a
/// use-count, and `(null, null)` for a lifetime (unlimited) grant.
typedef GrantLimitWire = ({String? expiresAt, int? queryLimit});

/// Access-policy choice for an approval: a TTL, a use-count, or lifetime
/// (unlimited) — the three options the web approve dialog offers.
///
/// The backend treats `expiresAt`/`queryLimit` as mutually exclusive (and
/// neither = lifetime); this sealed type makes the choice explicit and
/// impossible to over-specify at the call site.
sealed class GrantLimit {
  const GrantLimit();

  /// Serializes to the wire pair: a [GrantExpiry] yields `(expiresAt, null)`,
  /// a [GrantUseLimit] yields `(null, queryLimit)`, and a [GrantLifetime]
  /// yields `(null, null)` (the datasource omits null fields → lifetime).
  /// Kept in one tested place so the invariant lives in a single spot.
  GrantLimitWire toWire() {
    return switch (this) {
      GrantExpiry(:final expiresAt) => (
        expiresAt: expiresAt.toUtc().toIso8601String(),
        queryLimit: null,
      ),
      GrantUseLimit(:final maxUses) => (expiresAt: null, queryLimit: maxUses),
      GrantLifetime() => (expiresAt: null, queryLimit: null),
    };
  }
}

/// Time-to-live limit — the grant expires at [expiresAt].
class GrantExpiry extends GrantLimit {
  const GrantExpiry(this.expiresAt);

  /// Absolute expiry in UTC.
  final DateTime expiresAt;
}

/// Use-count limit — the grant allows [maxUses] reads.
class GrantUseLimit extends GrantLimit {
  const GrantUseLimit(this.maxUses);

  final int maxUses;
}

/// Lifetime (unlimited) grant — no TTL and no use cap; the agent keeps access
/// until the owner revokes it. Serializes to neither wire field.
class GrantLifetime extends GrantLimit {
  const GrantLifetime();
}

/// Abstract approval repository. Implemented in the data layer; throws a
/// typed `ApprovalException` on failure.
abstract interface class ApprovalRepository {
  /// Lists cross-vault pending grant requests for the current user.
  Future<List<PendingGrant>> listPendingGrants();

  /// Approves [grant] by producing the zero-knowledge envelope on-device
  /// and submitting it with the chosen [limit].
  ///
  /// [privateKey] is the owner's X25519 private key from the unlocked
  /// in-memory auth state — required to unwrap the VK. Never persisted.
  Future<void> approveGrant({
    required PendingGrant grant,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
    required List<String> fieldIds,
    required String reviewedEntryRevision,
  });

  /// Denies [grant] without any plaintext request or denial reason.
  Future<void> denyGrant({required PendingGrant grant});

  /// Proactively creates FULL access with one current Vault-key wrapper.
  /// [privateKey] is the owner's in-memory X25519 key and is never persisted
  /// or logged. This contract cannot accept per-Entry material.
  Future<void> createFullGrant({
    required String vaultId,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  });

  /// Proactively creates GRANULAR access with one revision-bound Entry
  /// envelope. [privateKey] is used in memory only. This contract cannot
  /// accept whole-Vault key material.
  Future<void> createGranularGrant({
    required String vaultId,
    required String entryId,
    List<String>? selectedFieldIds,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
    required List<GrantMethod> methods,
  });

  /// Proactively creates direct Script execution access with one complete,
  /// revision-bound package. This contract cannot accept GRANULAR envelopes
  /// or a whole-Vault key wrapper.
  Future<void> createScriptExecutionGrant({
    required String vaultId,
    required String scriptEntryId,
    required String agentId,
    required String agentPublicKey,
    required int recipientKeyVersion,
    required int agentAccessEpoch,
    required Uint8List privateKey,
    required GrantLimit limit,
  });
}
