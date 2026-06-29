import '../../domain/entities/onboarding_status.dart';
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
}
