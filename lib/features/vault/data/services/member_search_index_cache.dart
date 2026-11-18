import 'member_sync_cache.dart';

/// Optional encrypted derived index; canonical Member state owns validity.
abstract interface class MemberSearchIndexCache {
  bool get canWriteSearchIndex;
  Future<String?> readSearchIndex(
    String vaultId,
    MemberSyncCacheState expected,
  );
  Future<bool> writeSearchIndex(
    String vaultId,
    MemberSyncCacheState expected,
    String encoded,
  );
}
