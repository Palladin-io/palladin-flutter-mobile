/// Exact protocol-v2 Entry envelope bundle accepted by the backend.
final class EntryEnvelopeBundleModel {
  const EntryEnvelopeBundleModel({
    required this.entryKey,
    required this.memberIndex,
    required this.memberSecret,
    required this.agentDiscovery,
  });

  final Map<String, Object?> entryKey;
  final Map<String, Object?> memberIndex;
  final Map<String, Object?> memberSecret;
  final Map<String, Object?>? agentDiscovery;
}

/// Atomic protocol-v2 create transition.
final class CreateEntryV2Request {
  const CreateEntryV2Request({
    required this.vaultId,
    required this.entryId,
    required this.envelopes,
    this.grantEnvelopes = const [],
  });

  final String vaultId;
  final String entryId;
  final EntryEnvelopeBundleModel envelopes;
  final List<Map<String, Object?>> grantEnvelopes;

  Map<String, Object?> toJson() => {
    'vaultId': vaultId,
    'entryId': entryId,
    'entryKey': envelopes.entryKey,
    'memberIndex': envelopes.memberIndex,
    'memberSecret': envelopes.memberSecret,
    'agentDiscovery': envelopes.agentDiscovery,
    'grantEnvelopes': grantEnvelopes,
  };
}

/// Atomic optimistic protocol-v2 Entry update transition.
final class UpdateEntryV2Request {
  const UpdateEntryV2Request({
    required this.vaultId,
    required this.entryId,
    required this.baseRevision,
    required this.envelopes,
    required this.agentDiscoveryChanged,
    this.grantEnvelopes = const [],
  });

  final String vaultId;
  final String entryId;
  final String baseRevision;
  final EntryEnvelopeBundleModel envelopes;
  final bool agentDiscoveryChanged;
  final List<Map<String, Object?>> grantEnvelopes;

  Map<String, Object?> toJson() => {
    'vaultId': vaultId,
    'entryId': entryId,
    'baseRevision': baseRevision,
    'newEntryKey': envelopes.entryKey,
    'memberIndex': envelopes.memberIndex,
    'memberSecret': envelopes.memberSecret,
    'agentDiscoveryChanged': agentDiscoveryChanged,
    'agentDiscovery': envelopes.agentDiscovery,
    'grantEnvelopes': grantEnvelopes,
  };
}
