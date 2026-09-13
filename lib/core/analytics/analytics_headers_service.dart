/// The API needs only a fixed product component tag. Analytics session,
/// device, OS and build metadata are never attached to backend requests.
class AnalyticsHeadersService {
  AnalyticsHeadersService._();
  static final AnalyticsHeadersService instance = AnalyticsHeadersService._();
  Future<void> init() async {}
  Future<Map<String, String>> getHeaders() async => {'x-platform': 'mobile'};
}
