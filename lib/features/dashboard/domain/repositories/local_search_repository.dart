import 'dart:typed_data';

import '../entities/recent_entry_entity.dart';
import '../entities/search_result_entity.dart';

/// Runtime-only search over already decrypted Vault v2 projections.
abstract interface class LocalSearchRepository {
  /// Loads and decrypts the current Vault/Entry search projections in memory.
  /// The private key is never retained by the repository.
  Future<void> prepare(Uint8List memberPrivateKey);

  List<SearchResultEntity> search(String query, {int limit = 10});

  List<RecentEntryEntity> recentEntries({int limit = 5});
}
