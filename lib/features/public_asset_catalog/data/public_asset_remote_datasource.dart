import 'package:dio/dio.dart';

/// Thin REST datasource for the stable Public Asset Catalog boundary.
class PublicAssetRemoteDatasource {
  const PublicAssetRemoteDatasource(this._dio);
  final Dio _dio;

  Future<List<Map<String, dynamic>>> search(String query) async {
    final response = await _dio.get<Object?>(
      '/api/public-assets/search',
      queryParameters: {'type': 'website-icon', 'q': query},
    );
    return _list(response.data);
  }

  Future<List<Map<String, dynamic>>> resolve(List<String> hostnames) async {
    final response = await _dio.post<Object?>(
      '/api/public-assets/resolve',
      data: {'type': 'website-icon', 'hostnames': hostnames},
    );
    return _list(response.data);
  }

  Future<Map<String, dynamic>?> getById(String assetId, {int? revision}) async {
    final response = await _dio.get<Object?>(
      '/api/public-assets/$assetId',
      queryParameters: revision == null ? null : {'v': revision},
    );
    final data = response.data;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static List<Map<String, dynamic>> _list(Object? data) {
    final raw = switch (data) {
      List<Object?> value => value,
      {'items': final List<Object?> value} => value,
      {'results': final List<Object?> value} => value,
      _ => const <Object?>[],
    };
    return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }
}
