import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/privacy/data/consent_remote_datasource.dart';
import 'package:mobile_palladin/features/privacy/domain/user_consent.dart';
import 'package:mobile_palladin/features/privacy/data/consent_notice_catalog.dart';

void main() {
  test(
    'consumes the versioned Identity consent fixture and sends an explicit decision',
    () async {
      final fixture =
          jsonDecode(File('test/fixtures/consents-v2.json').readAsStringSync())
              as Map<String, dynamic>;
      final calls = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              calls.add(options);
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: options.method == 'GET'
                      ? fixture
                      : (fixture['consents'] as List).first
                            as Map<String, dynamic>,
                ),
              );
            },
          ),
        );
      final remote = ConsentRemoteDataSource(dio);
      final response = await remote.get('en');
      expect(response.maxAgeSeconds, 60);
      expect(response.consents.first.revision, 3);
      expect(response.consents.first.activationRevision, 1);
      expect(response.consents.first.recordedAt, DateTime.utc(2026, 9, 11, 12));
      expect(
        response.consents.first.currentNotice?.text,
        consentNotice('product_analytics', 'en')!.text,
      );
      expect(response.consents.last.status, 'unknown');
      expect(response.consents.last.recordedAt, isNull);
      expect(
        response.consents.last.currentNotice?.version,
        consentNoticeVersion,
      );
      expect(calls.single.queryParameters, {'locale': 'en'});
      expect(calls.single.headers['Cache-Control'], 'no-store');

      await remote.decide(
        const ConsentDecision(
          purpose: 'product_analytics',
          granted: false,
          expectedRevision: 3,
          requestId: '00000000-0000-4000-8000-000000000609',
          noticeVersion: 'test-v1',
          locale: 'en',
          source: 'mobile_settings',
        ),
      );
      expect(calls.last.method, 'PUT');
      expect(calls.last.path, '/api/account/consents/product_analytics');
      expect(calls.last.data, {
        'granted': false,
        'expectedRevision': 3,
        'requestId': '00000000-0000-4000-8000-000000000609',
        'noticeVersion': 'test-v1',
        'locale': 'en',
        'source': 'mobile_settings',
      });
    },
  );
}
