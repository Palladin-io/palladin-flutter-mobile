/// Canonical protocol-2 envelope carrying an Agent's encrypted reason.
final class EncryptedReason {
  const EncryptedReason({
    required this.descriptor,
    required this.encodedSuitePayload,
    required this.wrappedReasonDek,
    required this.agentSignature,
  });

  final Map<String, dynamic> descriptor;
  final String encodedSuitePayload;
  final Map<String, dynamic> wrappedReasonDek;
  final String agentSignature;

  Map<String, dynamic> get scope =>
      Map<String, dynamic>.from(descriptor['scope'] as Map);
  Map<String, dynamic> get binding =>
      Map<String, dynamic>.from(descriptor['binding'] as Map);
  String get organizationId => scope['organizationId'] as String;
  String get vaultId => scope['vaultId'] as String;
  String get entryId => scope['entryId'] as String;
  String get grantRequestId => scope['grantOrRequestId'] as String;
  String get agentId => scope['agentId'] as String;
  String get requestRevision => descriptor['resourceRevision'] as String;
  int get reasonKeyVersion => descriptor['keyVersion'] as int;
  int get memberKeyGeneration => descriptor['memberKeyGeneration'] as int;
  int get agentMessageKeyVersion => binding['recipientKeyVersion'] as int;
  String get recipientAgentMessageKeyFingerprint =>
      binding['recipientKeyFingerprint'] as String;
  int get requestedMethods => binding['requestedMethods'] as int;
}
