/// Domain entity for a pending grant request awaiting the owner's
/// approval, as surfaced by `GET /api/dashboard/pending-grants`
/// (cross-vault).
///
/// Carries the routing identifiers and the agent's public key needed to
/// produce the approval envelope — but never any secret material. The
/// agent public key is, by design, public (it only *seals* data to the
/// agent; it cannot decrypt anything).
class PendingGrant {
  const PendingGrant({
    required this.grantId,
    required this.vaultId,
    required this.agentId,
    required this.entryId,
    required this.agentPublicKey,
    required this.createdAt,
    this.vaultName,
    this.agentName,
    this.entryLabel,
    this.reason,
  });

  final String grantId;
  final String vaultId;
  final String agentId;

  /// Target entry id — always present for a GRANULAR request (an agent
  /// always requests exactly one entry).
  final String entryId;

  /// Base64 X25519 public key of the requesting agent. Used to seal the
  /// per-grant DEK on approval.
  final String agentPublicKey;

  final String? vaultName;
  final String? agentName;
  final String? entryLabel;

  /// Agent-supplied justification — required by the security model.
  final String? reason;

  final DateTime createdAt;
}
