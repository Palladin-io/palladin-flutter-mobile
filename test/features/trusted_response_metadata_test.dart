import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/dashboard/data/datasources/dashboard_remote_datasource.dart';
import 'package:mobile_palladin/features/public_asset_catalog/data/public_asset_remote_datasource.dart';
import 'package:mobile_palladin/features/public_asset_catalog/data/public_asset_repository_impl.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/repositories/public_asset_repository.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/services/website_icon_service.dart';
import 'package:mobile_palladin/features/vault/data/datasources/vault_members_remote_datasource.dart';

Dio _response(Map<String, dynamic> data) => Dio()
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        handler.resolve(Response(requestOptions: request, data: data));
      },
    ),
  );

void main() {
  test(
    'optional icon preparation does not poll unknown or omitted statuses forever',
    () async {
      final repository = PublicAssetRepositoryImpl(
        PublicAssetRemoteDatasource(
          _response({
            'items': [
              {
                'hostname': 'future.example.com',
                'status': 'future',
                'asset': null,
              },
            ],
          }),
        ),
      );
      final cancellation = WebsiteIconPreparationCancellation();
      try {
        final result = await WebsiteIconService(repository)
            .ensureBatchUntilResolved([
              'future.example.com',
              'omitted.example.com',
            ], cancellation: cancellation)
            .timeout(const Duration(milliseconds: 500));
        expect(result, isEmpty);
      } finally {
        cancellation.cancel();
      }
    },
  );

  test('member page does not repeat the backend page-size rule', () async {
    final page = await VaultMembersRemoteDatasource(
      _response({
        'items': List.generate(
          101,
          (index) => {
            'memberId': 'member-$index',
            'addedAt': '2026-09-19T12:00:00Z',
            'deprovisioningStatus': 'future',
          },
        ),
        'nextAfterId': null,
      }),
    ).list('vault');
    expect(page.items, hasLength(101));
    expect(page.items.last.deprovisioningStatus, 'future');
  });

  test(
    'search keeps all returned rows including empty display names',
    () async {
      final results = await DashboardRemoteDatasource(
        _response({
          'results': [
            {'type': 'agent', 'id': 'agent', 'name': ''},
            {'type': 'future', 'id': 'future', 'name': 'Future'},
          ],
        }),
      ).globalSearch('query', 1, cancelToken: CancelToken());
      expect(results, hasLength(2));
      expect(results.first.toEntity().name, '');
    },
  );

  test(
    'catalog unknown statuses and unusable icons do not reject a batch',
    () async {
      final repository = PublicAssetRepositoryImpl(
        PublicAssetRemoteDatasource(
          _response({
            'items': [
              {
                'hostname': 'future.example.com',
                'status': 'future',
                'asset': null,
              },
              {
                'hostname': 'bad.example.com',
                'status': 'ready',
                'asset': {
                  'id': 'bad',
                  'type': 'websiteIcon',
                  'name': 'Bad',
                  'revision': 1,
                  'deliveryUrl': 'file:///private/icon',
                },
              },
              {
                'hostname': 'good.example.com',
                'status': 'ready',
                'asset': {
                  'id': 'good',
                  'type': 'websiteIcon',
                  'name': '',
                  'revision': 1,
                  'deliveryUrl': 'https://assets.example.com/icon',
                },
              },
            ],
          }),
        ),
      );
      final result = await repository.ensureWebsiteIcons([
        'future.example.com',
        'bad.example.com',
        'good.example.com',
      ]);
      expect(
        result.statuses['future.example.com'],
        WebsiteIconEnsureStatus.unknown,
      );
      expect(result.assets.keys, ['good.example.com']);
    },
  );
}
