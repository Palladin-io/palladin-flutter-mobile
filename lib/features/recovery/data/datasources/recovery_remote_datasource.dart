import 'package:dio/dio.dart';

import '../../../unlock/data/datasources/account_remote_datasource.dart';
import '../../../unlock/data/models/account_response.dart';
import '../models/recover_account_request.dart';

/// Remote data source for the account-recovery flow.
///
/// Wraps the existing [AccountRemoteDatasource] for the `GET /api/account`
/// call (so both unlock and recovery share a single implementation) and
/// adds the `PUT /api/account/recovery` endpoint that atomically replaces
/// the user's salts and wrapped private keys after a successful recovery.
class RecoveryRemoteDatasource {
  RecoveryRemoteDatasource({
    required Dio dio,
    required AccountRemoteDatasource accountDatasource,
  }) : _dio = dio,
       _accountDatasource = accountDatasource;

  final Dio _dio;
  final AccountRemoteDatasource _accountDatasource;

  /// Fetches the current user's account material — same payload as the
  /// unlock flow. Includes `recoverySalt` and `encryptedPrivateKeyByRecovery`.
  Future<AccountResponse> getAccount() => _accountDatasource.getAccount();

  /// `POST /api/account/recovery/challenge` — issues a fresh one-time
  /// `account-recovery-challenge-v1` package sealed to the account key and
  /// returns its base64url `sealedChallenge`. 404 means the account has no
  /// public key.
  Future<String> createRecoveryChallenge() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/account/recovery/challenge',
    );
    final sealedChallenge = response.data?['sealedChallenge'];
    if (sealedChallenge is! String) {
      throw DioException.badResponse(
        statusCode: response.statusCode ?? 200,
        requestOptions: response.requestOptions,
        response: response,
      );
    }
    return sealedChallenge;
  }

  /// Submits the recovery payload to the backend.
  ///
  /// Returns 204 No Content on success. DioException surfaces raw —
  /// the repository layer classifies network vs. protocol failures.
  Future<Response<dynamic>> recoverAccount(RecoverAccountRequest request) {
    return _dio.put('/api/account/recovery', data: request.toJson());
  }
}
