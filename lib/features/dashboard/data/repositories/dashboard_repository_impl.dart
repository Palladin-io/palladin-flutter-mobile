import '../../domain/entities/onboarding_status.dart';
import '../../domain/entities/recent_entry_entity.dart';
import '../../domain/entities/search_result_entity.dart';
import '../../domain/repositories/dashboard_repository.dart';
import '../datasources/dashboard_remote_datasource.dart';

/// Default [DashboardRepository] backed by the REST data source.
class DashboardRepositoryImpl implements DashboardRepository {
  DashboardRepositoryImpl(this._datasource);

  final DashboardRemoteDatasource _datasource;

  @override
  Future<OnboardingStatus> getOnboardingStatus() async {
    final model = await _datasource.getOnboarding();
    return model.toEntity();
  }

  @override
  Future<List<RecentEntryEntity>> getRecentEntries(int limit) async {
    final models = await _datasource.getRecentEntries(limit);
    return models.map((m) => m.toEntity()).toList(growable: false);
  }

  @override
  Future<List<SearchResultEntity>> globalSearch(
    String q, {
    int limit = 10,
  }) async {
    final models = await _datasource.globalSearch(q, limit);
    return models.map((m) => m.toEntity()).toList(growable: false);
  }
}
