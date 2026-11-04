import 'package:dio/dio.dart';

import '../models/account_response.dart';

/// Remote data source for the unlock flow.
///
/// Fetches the persisted account material (salt + encrypted private
/// key) from the .NET backend Identity module at `/api/account`.
class AccountRemoteDatasource {
  AccountRemoteDatasource(
    this._dio, {
    int Function()? sessionRevision,
    Future<AccountResponse> Function()? readProtectedUnlock,
  }) : _sessionRevision = sessionRevision,
       _readProtectedUnlock = readProtectedUnlock;

  final Dio _dio;
  final int Function()? _sessionRevision;
  final Future<AccountResponse> Function()? _readProtectedUnlock;
  int? _pendingRevision;
  Future<AccountResponse>? _pending;

  /// Unlock alone can use an independently account-bound protected projection
  /// when offline. Recovery and account management continue to require REST.
  Future<AccountResponse> getUnlockAccount() async {
    final revision = _sessionRevision?.call();
    try {
      return await getAccount();
    } on DioException catch (error) {
      final read = _readProtectedUnlock;
      if (read == null ||
          !const {
            DioExceptionType.connectionError,
            DioExceptionType.connectionTimeout,
            DioExceptionType.sendTimeout,
            DioExceptionType.receiveTimeout,
          }.contains(error.type)) {
        rethrow;
      }
      if (_sessionRevision?.call() != revision) {
        throw StateError('Unlock account session changed');
      }
      final account = await read();
      if (_sessionRevision?.call() != revision) {
        throw StateError('Unlock account session changed');
      }
      return account;
    }
  }

  /// Fetches the current user's account material.
  ///
  /// Returns an [AccountResponse] with base64-encoded salt and
  /// encrypted-private-key ciphertext so the client can derive the
  /// master key and decrypt the private key locally.
  Future<AccountResponse> getAccount() {
    final sessionRevision = _sessionRevision;
    if (sessionRevision == null) return _fetchAccount();
    final revision = sessionRevision();
    final pending = _pending;
    if (pending != null && _pendingRevision == revision) return pending;
    late final Future<AccountResponse> request;
    request = _fetchAccount().whenComplete(() {
      // An old account's response cannot clear a newer request's ownership.
      if (identical(_pending, request)) {
        _pending = null;
        _pendingRevision = null;
      }
    });
    _pendingRevision = revision;
    _pending = request;
    return request;
  }

  Future<AccountResponse> _fetchAccount() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/account');
    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        error: 'Empty response body',
      );
    }
    return AccountResponse.fromJson(data);
  }
}
