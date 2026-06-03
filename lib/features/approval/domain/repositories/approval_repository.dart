import 'dart:typed_data';

import '../entities/pending_grant.dart';

/// The XOR-correct wire representation of a [GrantLimit] — exactly one of
/// the two fields is non-null.
typedef GrantLimitWire = ({String? expiresAt, int? queryLimit});

/// Exactly-one-of expiry / use-limit choice for an approval.
///
/// The backend enforces XOR (`expiresAt` XOR `queryLimit`); this sealed
/// type makes the choice explicit and impossible to under/over-specify in
/// the call site.
sealed class GrantLimit {
  const GrantLimit();

  /// Serializes to the wire pair, guaranteeing the XOR invariant: a
  /// [GrantExpiry] yields `(expiresAt, null)` and a [GrantUseLimit]
  /// yields `(null, queryLimit)`. Used by the repository when building
  /// the approve body so the XOR rule lives in one tested place.
  GrantLimitWire toWire() {
    return switch (this) {
      GrantExpiry(:final expiresAt) => (
          expiresAt: expiresAt.toUtc().toIso8601String(),
          queryLimit: null,
        ),
      GrantUseLimit(:final maxUses) => (
          expiresAt: null,
          queryLimit: maxUses,
        ),
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
  });

  /// Denies [grant] with an optional [reason].
  Future<void> denyGrant({required PendingGrant grant, String? reason});
}
