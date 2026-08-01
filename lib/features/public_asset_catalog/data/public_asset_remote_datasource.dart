import 'package:dio/dio.dart';

/// Thin REST datasource for the stable Public Asset Catalog boundary.
class PublicAssetRemoteDatasource {
  const PublicAssetRemoteDatasource(this._dio);
  final Dio _dio;

  Future<List<Map<String, dynamic>>> search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty || normalized.length > 200) {
      throw const FormatException('Invalid public asset search query');
    }
    final response = await _dio.get<Object?>(
      '/api/public-assets/search',
      queryParameters: {'type': 'websiteIcon', 'q': normalized},
    );
    return _list(response.data);
  }

  Future<List<Map<String, dynamic>>> ensure(List<String> hostnames) async {
    final response = await _dio.post<Object?>(
      '/api/public-assets/website-icons/ensure',
      data: {'hostnames': hostnames},
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
    if (data is! Map || data['items'] is! List) {
      throw const FormatException('Malformed public asset response');
    }
    final raw = data['items'] as List;
    if (raw.any((item) => item is! Map)) {
      throw const FormatException('Malformed public asset item');
    }
    return raw
        .cast<Map>()
        .map(Map<String, dynamic>.from)
        .toList(growable: false);
  }
}
