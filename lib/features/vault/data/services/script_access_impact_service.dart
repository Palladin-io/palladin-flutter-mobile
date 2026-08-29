import 'package:dio/dio.dart';

final class ScriptAccessImpact {
  const ScriptAccessImpact({
    required this.effectiveAgentCount,
    required this.directAgentCount,
    required this.fullAgentCount,
    required this.hasOverlappingCoverage,
  });

  final int effectiveAgentCount;
  final int directAgentCount;
  final int fullAgentCount;
  final bool hasOverlappingCoverage;

  factory ScriptAccessImpact.fromJson(Map<String, dynamic> json) =>
      ScriptAccessImpact(
        effectiveAgentCount: json['effectiveAgentCount'] as int,
        directAgentCount: json['directAgentCount'] as int,
        fullAgentCount: json['fullAgentCount'] as int,
        hasOverlappingCoverage: json['hasOverlappingCoverage'] as bool,
      );
}

/// Reads value-free Agent counts before a Member changes a Script. The API
/// intentionally returns no Script metadata, reference names, or secrets.
final class ScriptAccessImpactService {
  const ScriptAccessImpactService(this._dio);

  final Dio _dio;

  Future<ScriptAccessImpact> get({
    required String vaultId,
    required String scriptEntryId,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/vaults/$vaultId/scripts/$scriptEntryId/access-impact',
    );
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
    }
    return ScriptAccessImpact.fromJson(data);
  }
}
