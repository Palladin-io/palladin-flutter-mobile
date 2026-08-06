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

  test('ensure batch remains non-blocking when catalog fails', () async {
    final service = WebsiteIconService(_ThrowingRepository());
    expect(await service.ensureBatch(['example.com']), isEmpty);
  });

  test('ensure batch sends all 539 hosts to the repository', () async {
    final repository = _RecordingRepository();
    final service = WebsiteIconService(repository);

    await service.ensureBatch(
      List<String>.generate(539, (index) => 'host-$index.example.com'),
    );

    expect(repository.calls, hasLength(1));
    expect(repository.calls.single, hasLength(539));
    expect(repository.calls.single.last, 'host-538.example.com');
  });

  test(
    'bounded ensure reports readiness and returns only ready assets',
    () async {
      final repository = _ReadyOnSecondRequestRepository();
      final progress = <(int, int)>[];
      final service = WebsiteIconService(
        repository,
        pollInterval: const Duration(milliseconds: 5),
      );

      final result = await service.ensureBatchWithin(
        ['ready.example.com', 'missing.example.com'],
        timeout: const Duration(milliseconds: 15),
        onProgress: (ready, total) => progress.add((ready, total)),
      );

      expect(result.keys, ['ready.example.com']);
      expect(progress.first, (0, 2));
      expect(progress, contains((2, 2)));
    },
  );

  test('repository splits 539 hosts without dropping the final page', () async {
    final remote = _RecordingRemoteDatasource();
    final repository = PublicAssetRepositoryImpl(remote);

    await repository.ensureWebsiteIcons(
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
      final result = await repository.ensureWebsiteIcons(['example.com']);
      expect(
        result.assets['example.com']?.deliveryUrl.toString(),
        'http://bucket.test/icon.webp',
      );
      expect((dio.httpClientAdapter as _FakeAdapter).requestData, {
        'hostnames': ['example.com'],
      });
    },
  );
}

class _ThrowingRepository implements PublicAssetRepository {
  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) =>
      throw Exception();
  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) => throw Exception();
  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) =>
      throw Exception();
}

class _RecordingRepository implements PublicAssetRepository {
  final List<List<String>> calls = [];

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    calls.add(hostnames.toList(growable: false));
    return WebsiteIconEnsureResult(
      assets: const {},
      statuses: {
        for (final hostname in hostnames)
          hostname: WebsiteIconEnsureStatus.pending,
      },
    );
  }

  @override
  Future<PublicAsset?> getById(String assetId, {int? revision}) async => null;

  @override
  Future<List<PublicAsset>> searchWebsiteIcons(String query) async => const [];
}

class _ReadyOnSecondRequestRepository implements PublicAssetRepository {
  int calls = 0;

  @override
  Future<WebsiteIconEnsureResult> ensureWebsiteIcons(
    Iterable<String> hostnames,
  ) async {
    calls++;
    if (calls == 1) {
      return WebsiteIconEnsureResult(
        assets: const {},
        statuses: {
          for (final hostname in hostnames)
            hostname: WebsiteIconEnsureStatus.pending,
        },
      );
    }
    final asset = PublicAsset(
      id: 'ready-id',
      type: 'websiteIcon',
      name: 'Ready',
      revision: 1,
      deliveryUrl: Uri.parse('https://assets.palladin.io/ready.png'),
    );
    return WebsiteIconEnsureResult(
      assets: {'ready.example.com': asset},
      statuses: {
        'ready.example.com': WebsiteIconEnsureStatus.ready,
        'missing.example.com': WebsiteIconEnsureStatus.failed,
      },
    );
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
  Future<List<Map<String, dynamic>>> ensure(List<String> hostnames) async {
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
      '{"items":[{"hostname":"example.com","status":"ready","asset":{"id":"asset-id","type":"websiteIcon","name":"Example","revision":2,"url":"http://bucket.test/icon.webp"}}]}',
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
