import 'package:dio/dio.dart';
import '../domain/user_consent.dart';
import 'consent_notice_catalog.dart';

class ConsentRemoteDataSource {
  ConsentRemoteDataSource(this._dio);
  final Dio _dio;

  Future<UserConsents> get(String locale, {CancelToken? cancelToken}) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/account/consents',
      queryParameters: {'locale': locale},
      cancelToken: cancelToken,
      options: Options(headers: {'Cache-Control': 'no-store'}),
    );
    final data = response.data!;
    return UserConsents(
      (data['consents'] as List)
          .map((value) => _consent(value as Map<String, dynamic>, locale))
          .toList(),
      data['maxAgeSeconds'] as int,
    );
  }

  Future<UserConsent> decide(
    ConsentDecision decision, {
    CancelToken? cancelToken,
  }) async {
    final response = await _dio.put<Map<String, dynamic>>(
      '/api/account/consents/${decision.purpose}',
      cancelToken: cancelToken,
      data: {
        'granted': decision.granted,
        'expectedRevision': decision.expectedRevision,
        'requestId': decision.requestId,
        'noticeVersion': decision.noticeVersion,
        'locale': decision.locale,
        'source': decision.source,
      },
    );
    return _consent(response.data!, decision.locale);
  }

  UserConsent _consent(Map<String, dynamic> data, String locale) {
    return UserConsent(
      purpose: data['purpose'] as String,
      scope: data['scope'] as String,
      status: data['status'] as String,
      revision: data['revision'] as int,
      activationRevision: data['activationRevision'] as int,
      recordedAt: data['recordedAt'] == null
          ? null
          : DateTime.parse(data['recordedAt'] as String),
      noticeVersion: data['noticeVersion'] as String?,
      noticeLocale: data['noticeLocale'] as String?,
      currentNotice: consentNotice(data['purpose'] as String, locale),
    );
  }
}
