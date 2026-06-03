import 'package:dio/dio.dart';

/// Device platform sent to the backend when registering a push token.
///
/// Serializes to the exact PascalCase values the .NET backend expects
/// (`Ios` / `Android`) — see `POST /api/push-tokens`.
enum PushPlatform {
  ios('Ios'),
  android('Android');

  const PushPlatform(this.wireValue);

  final String wireValue;
}

/// Remote data source for the push-token registration endpoints.
///
/// Communicates with the .NET Notification module:
/// - `POST /api/push-tokens` → registers the device's FCM/APNs token,
///   returns the created record id.
/// - `DELETE /api/push-tokens/{id}` → removes the token on logout.
///
/// Requests are authenticated via the shared [Dio]'s auth interceptor
/// (Bearer JWT). The FCM token is an opaque routing identifier — not a
/// secret — but is still never written to logs.
class PushTokenRemoteDatasource {
  PushTokenRemoteDatasource(this._dio);

  final Dio _dio;

  /// Registers [token] for the current user and returns the server-side
  /// record id, used later for [deleteToken] on logout.
  Future<String> registerToken({
    required String token,
    required PushPlatform platform,
    String? deviceName,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/push-tokens',
      data: <String, dynamic>{
        'token': token,
        'platform': platform.wireValue,
        if (deviceName != null && deviceName.isNotEmpty)
          'deviceName': deviceName,
      },
    );
    final data = response.data;
    final id = data?['id'];
    if (id is! String || id.isEmpty) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'push-tokens response missing id',
      );
    }
    return id;
  }

  /// Removes the token record identified by [id]. Best-effort — callers
  /// run this on logout and tolerate failure.
  Future<void> deleteToken(String id) async {
    await _dio.delete<void>('/api/push-tokens/$id');
  }
}
