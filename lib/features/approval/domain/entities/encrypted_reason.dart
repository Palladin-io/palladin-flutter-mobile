/// Authenticated protocol-2 envelope carrying an Agent's encrypted reason.
final class EncryptedReason {
  const EncryptedReason({
    required this.organizationId,
    required this.vaultId,
    required this.entryId,
    required this.grantRequestId,
    required this.agentId,
    required this.requestRevision,
    required this.header,
    required this.reasonKeyVersion,
    required this.agentMessageKeyVersion,
    required this.recipientAgentMessageKeyFingerprint,
    required this.requestedMethods,
    required this.ciphertext,
    required this.agentMessageWrappedReasonDek,
    required this.agentSignature,
  });

  final String organizationId;
  final String vaultId;
  final String entryId;
  final String grantRequestId;
  final String agentId;
  final String requestRevision;
  final Map<String, dynamic> header;
  final int reasonKeyVersion;
  final int agentMessageKeyVersion;
  final String recipientAgentMessageKeyFingerprint;
  final int requestedMethods;
  final String ciphertext;
  final String agentMessageWrappedReasonDek;
  final String agentSignature;
}
