import 'package:dio/dio.dart';
import '../domain/user_consent.dart';

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
          .map((value) => _consent(value as Map<String, dynamic>))
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
    return _consent(response.data!);
  }

  UserConsent _consent(Map<String, dynamic> data) {
    final notice = data['currentNotice'] as Map<String, dynamic>?;
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
      currentNotice: notice == null
          ? null
          : ConsentNotice(
              version: notice['version'] as String,
              locale: notice['locale'] as String,
              text: notice['text'] as String,
            ),
    );
  }
}
