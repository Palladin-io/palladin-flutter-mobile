import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_palladin/features/public_asset_catalog/data/public_asset_remote_datasource.dart';
import 'package:mobile_palladin/features/public_asset_catalog/data/public_asset_repository_impl.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/entities/public_asset.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/public_asset_reference.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/repositories/public_asset_repository.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/services/public_hostname.dart';
import 'package:mobile_palladin/features/public_asset_catalog/domain/services/website_icon_service.dart';

void main() {
  test(
    'parses all icon namespaces without treating private assets as public',
    () {
      expect(
        PublicAssetReference.parse('public-asset:abc'),
        isA<CatalogAssetReference>(),
      );
      expect(
        PublicAssetReference.parse('builtin:language'),
        isA<BuiltinAssetReference>(),
      );
      expect(
        PublicAssetReference.parse('vault-asset:secret'),
        isA<VaultAssetReference>(),
      );
      expect(
        PublicAssetReference.parse('asset:secret:1'),
        isA<VaultAssetReference>(),
      );
    },
  );

  test('datasource rejects noncanonical response wrappers', () async {
    final dio = Dio()..httpClientAdapter = _StaticAdapter('{"results":[]}');
    final remote = PublicAssetRemoteDatasource(dio);

    expect(() => remote.search('stripe'), throwsA(isA<FormatException>()));
  });

  test('datasource rejects search queries above the backend limit', () async {
    final remote = PublicAssetRemoteDatasource(Dio());
    expect(() => remote.search('x' * 201), throwsA(isA<FormatException>()));
  });

  test('normalizes and deduplicates only public DNS hostnames', () {
    expect(
      PublicHostname.normalize('HTTPS://WWW.Example.COM/path'),
      'www.example.com',
    );
    expect(PublicHostname.normalize('localhost'), isNull);
    expect(PublicHostname.normalize('10.0.0.1'), isNull);
    expect(PublicHostname.unique(['Example.com', 'https://example.com/a']), [
      'example.com',
    ]);
  });

  test('resolve batch remains non-blocking when catalog fails', () async {
    final service = WebsiteIconService(_ThrowingRepository());
    expect(await service.resolveBatch(['example.com']), isEmpty);
  });

  test('resolve batch sends all 539 hosts in backend-sized pages', () async {
    final repository = _RecordingRepository();
    final service = WebsiteIconService(repository);

    await service.resolveBatch(
      List<String>.generate(539, (index) => 'host-$index.example.com'),
    );

    expect(repository.calls, hasLength(1));
    expect(repository.calls.single, hasLength(539));
    expect(repository.calls.single.last, 'host-538.example.com');
  });

  test('repository splits 539 hosts without dropping the final page', () async {
    final remote = _RecordingRemoteDatasource();
    final repository = PublicAssetRepositoryImpl(remote);

    await repository.resolveWebsiteIcons(
      List<String>.generate(539, (index) => 'host-$index.example.com'),
    );

    expect(remote.calls.map((call) => call.length), [500, 39]);
    expect(remote.calls.last.last, 'host-538.example.com');
  });

  test(
    'repository sends the canonical API type and parses the server contract',
    () async {
      final dio = Dio()..httpClientAdapter = _FakeAdapter();
      final repository = PublicAssetRepositoryImpl(
        PublicAssetRemoteDatasource(dio),
      );
      final result = await repository.resolveWebsiteIcons(['example.com']);
      expect(
        result['example.com']?.deliveryUrl.toString(),
        'http://bucket.test/icon.webp',
      );
      expect((dio.httpClientAdapter as _FakeAdapter).requestData, {
        'type': 'websiteIcon',
        'hostnames': ['example.com'],
        'acquireMissing': true,
      });

      await repository.resolveWebsiteIcons(['example.com']);
      expect((dio.httpClientAdapter as _FakeAdapter).requestData, {
        'type': 'websiteIcon',
        'hostnames': ['example.com'],
        'acquireMissing': false,
      });
    },
  );
}

class _ThrowingRepository implements PublicAssetRepository {
  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) =>
      throw Exception();
  @override
  Future<Map<String, PublicAsset>> resolveWebsiteIcons(
    Iterable<String> hostnames,
  ) => throw Exception();
  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) =>
      throw Exception();
}

class _RecordingRepository implements PublicAssetRepository {
  final List<List<String>> calls = [];

  @override
  Future<Map<String, PublicAsset>> resolveWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    calls.add(hostnames.toList(growable: false));
    return const {};
  }

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => null;

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => const [];
}

class _RecordingRemoteDatasource extends PublicAssetRemoteDatasource {
  _RecordingRemoteDatasource() : super(Dio());
  final List<List<String>> calls = [];

  @override
  Future<List<Map<String, dynamic>>> resolve(
    List<String> hostnames, {
    required bool acquireMissing,
  }) async {
    calls.add(List.of(hostnames));
    return const [];
  }
}

class _FakeAdapter implements HttpClientAdapter {
  Object? requestData;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestData = options.data;
    return ResponseBody.fromString(
      '{"items":[{"hostname":"example.com","asset":{"id":"asset-id","type":"websiteIcon","name":"Example","revision":2,"url":"http://bucket.test/icon.webp"}}]}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _StaticAdapter implements HttpClientAdapter {
  _StaticAdapter(this.body);
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
