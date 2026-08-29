/// Canonical deterministic mobile budgets for Vault protocol 2 workloads.
///
/// CI validates these structural limits. Wall-clock p95 values are recorded
/// separately on representative physical release devices.
abstract final class VaultPerformanceBudget {
  /// Representative Vault sizes required by the protocol release gate.
  static const representativeEntryCounts = <int>[1000, 10000, 20000];

  /// Maximum decrypted MemberIndex entries retained by one Vault session.
  static const maximumIndexedEntries = 20000;

  /// Requested and accepted Member snapshot/delta page size on mobile.
  static const memberSyncPageItems = 100;

  /// Backend protocol ceiling for any Member sync response page.
  static const maximumMemberSyncPageItems = 200;

  /// Hard UTF-8 wire-size ceiling for one Member sync response.
  static const maximumMemberSyncResponseBytes = 4 * 1024 * 1024;

  /// Maximum simultaneous MemberIndex decrypt operations.
  static const memberIndexDecryptConcurrency = 2;

  /// Protocol-2 hard ceiling for all persisted current Member ciphertext.
  static const maximumMemberSyncProfileCacheBytes = 512 * 1024 * 1024;

  /// Exact delta workload used by the release benchmark: one percent.
  static int onePercentDeltaItems(int entryCount) {
    if (entryCount < 1 || entryCount % 100 != 0) {
      throw ArgumentError.value(entryCount, 'entryCount');
    }
    return entryCount ~/ 100;
  }

  /// Member history stays lazy and is fetched in bounded cursor pages.
  static const historyPageItems = 20;

  /// Maximum history rows retained by the history presentation flow.
  static const maximumLoadedHistoryVersions = 100;

  /// One grant approval opens one current canonical secret on demand.
  static const grantApprovalCanonicalSecrets = 1;
}
