import '../entities/recent_entry_entity.dart';
import '../entities/search_result_entity.dart';

/// Runtime-only search over already decrypted Vault v2 projections.
abstract interface class LocalSearchRepository {
  List<SearchResultEntity> search(String query, {int limit = 10});

  List<RecentEntryEntity> recentEntries({int limit = 5});
}
