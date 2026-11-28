import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/dashboard/presentation/cubit/search_state.dart';
import 'package:mobile_palladin/features/dashboard/domain/entities/search_result_entity.dart';

import '../../design/mobile/bootstrap.dart';
import '../../design/mobile/vault_adapters.dart';

void main() {
  test(
    'preview search uses current records and preserves the actual Vault',
    () async {
      final cubit = PreviewSearch();
      final original = vaultPreview.records.remove('entry-github')!;
      cubit.query('GitHub');
      expect(cubit.state, isA<SearchEmpty>());
      vaultPreview.records[original.id] = original;
      cubit.query('GitHub');
      final result =
          (cubit.state as SearchResults).results.single as EntrySearchResult;
      expect(result.vaultId, original.vaultId);
      expect(result.currentRevision, original.currentRevision);
      cubit.query('Work');
      expect(
        (cubit.state as SearchResults).results,
        contains(isA<VaultSearchResult>()),
      );
      cubit.query('Claude');
      expect(
        (cubit.state as SearchResults).results,
        contains(isA<AgentSearchResult>()),
      );
      await cubit.close();
    },
  );
}
