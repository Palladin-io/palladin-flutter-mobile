import 'dart:io';

import 'package:dio/dio.dart';

import '../../domain/password_auth_exceptions.dart';
import '../models/login_response.dart';
import '../models/password_session_model.dart';
import '../models/register_request.dart';
import '../models/totp_enroll_model.dart';

/// Remote data source for the email + master-password auth endpoints on
/// the .NET Identity module (`/api/auth/*`, `/api/account/*`).
///
/// Throws the typed domain exceptions from [password_auth_exceptions.dart]
/// so the cubits above never touch Dio directly — network / protocol
/// failures surface as [PasswordAuthServerException], business failures
/// as their specific typed exception.
class PasswordAuthRemoteDatasource {
  PasswordAuthRemoteDatasource(this._dio);

  final Dio _dio;

  /// `POST /api/auth/register` — creates the account and returns an
  /// (unverified) session. Throws [EmailAlreadyRegisteredException] on 409.
  Future<PasswordSessionModel> register(RegisterRequest request) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/register',
        data: request.toJson(),
      );
      return PasswordSessionModel.fromJson(_requireBody(response));
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        throw const EmailAlreadyRegisteredException();
      }
      throw PasswordAuthServerException(_classify(e));
    }
  }

  /// `POST /api/auth/login/salt` — fetches the account's [authSalt] so the
  /// client can derive its auth hash. Returns a deterministic pseudo-salt
  /// for unknown emails (anti-enumeration), never a 404.
  Future<String> fetchLoginSalt(String email) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/login/salt',
        data: {'email': email},
      );
      return _requireBody(response)['authSalt'] as String;
    } on DioException catch (e) {
      throw PasswordAuthServerException(_classify(e));
    }
  }

  /// `POST /api/auth/login` — exchanges the auth hash for a session, or a
  /// TOTP challenge. Throws [InvalidCredentialsException] on 401 and
  /// [LoginRateLimitedException] on 429.
  Future<LoginResponse> login({
    required String email,
    required String authHash,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {'email': email, 'authHash': authHash},
      );
      return LoginResponse.fromJson(_requireBody(response));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) throw const InvalidCredentialsException();
      if (status == 429) throw const LoginRateLimitedException();
      throw PasswordAuthServerException(_classify(e));
    }
  }

  /// `POST /api/auth/login/totp` — completes the TOTP challenge with a
  /// 6-digit code or a recovery code. Throws [TotpInvalidException] on a
  /// wrong / expired code.
  Future<PasswordSessionModel> loginTotp({
    required String challengeToken,
    required String code,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/login/totp',
        data: {'challengeToken': challengeToken, 'code': code},
      );
      return PasswordSessionModel.fromJson(_requireBody(response));
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 400) throw const TotpInvalidException();
      throw PasswordAuthServerException(_classify(e));
    }
  }

  /// `POST /api/auth/verify-email` — consumes the emailed token. Throws
  /// [VerificationTokenException] (expired / invalid) on a bad token.
  Future<void> verifyEmail(String token) async {
    try {
      await _dio.post<dynamic>(
        '/api/auth/verify-email',
        data: {'token': token},
      );
    } on DioException catch (e) {
      final kind = _verificationErrorKind(e);
      if (kind != null) throw VerificationTokenException(kind);
      throw PasswordAuthServerException(_classify(e));
    }
  }

  /// `POST /api/auth/verify-email/resend` (JWT) — re-sends the verification
  /// email. A no-op 204 (already verified / OAuth) is treated as success.
  Future<void> resendVerification() async {
    try {
      await _dio.post<dynamic>('/api/auth/verify-email/resend');
    } on DioException catch (e) {
      throw PasswordAuthServerException(_classify(e));
    }
  }

  /// `POST /api/auth/totp/enroll` (JWT) — begins TOTP enrollment.
  Future<TotpEnrollModel> totpEnroll() async {
    try {
      final response =
          await _dio.post<Map<String, dynamic>>('/api/auth/totp/enroll');
      return TotpEnrollModel.fromJson(_requireBody(response));
    } on DioException catch (e) {
      throw PasswordAuthServerException(_classify(e));
    }
  }

  /// `POST /api/auth/totp/confirm` (JWT) — confirms the pending secret with
  /// a generated [code] and returns the one-time recovery codes. Throws
  /// [TotpInvalidException] on a wrong code.
  Future<List<String>> totpConfirm(String code) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/totp/confirm',
        data: {'code': code},
      );
      final codes = _requireBody(response)['recoveryCodes'] as List<dynamic>?;
      return codes == null
          ? const <String>[]
          : codes.map((c) => c as String).toList(growable: false);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 400) throw const TotpInvalidException();
      throw PasswordAuthServerException(_classify(e));
    }
  }

  /// Changes the master password for the authenticated user (CVT-273).
  ///
  /// NOTE: the auth contract does not yet define an authenticated
  /// change-password endpoint (only register + mnemonic recovery), so this
  /// targets a best-guess `PUT /api/account/password` pending backend
  /// confirmation. The recovery mnemonic is intentionally left untouched.
  Future<void> changePassword({
    required String authHash,
    required String authSaltBase64,
    required String saltBase64,
    required String encryptedPrivateKeyBase64,
  }) async {
    try {
      await _dio.put<dynamic>(
        '/api/account/password',
        data: {
          'authHash': authHash,
          'authSalt': authSaltBase64,
          'salt': saltBase64,
          'encryptedPrivateKey': encryptedPrivateKeyBase64,
        },
      );
    } on DioException catch (e) {
      throw PasswordAuthServerException(_classify(e));
    }
  }

  Map<String, dynamic> _requireBody(Response<Map<String, dynamic>> response) {
    final data = response.data;
    if (data == null) {
      throw const PasswordAuthServerException(
        PasswordAuthServerErrorKind.invalidResponse,
      );
    }
    return data;
  }

  /// Inspects a verify-email error body for the backend's token error keys.
  /// Returns `null` when neither key is present (a non-token failure).
  VerificationTokenErrorKind? _verificationErrorKind(DioException e) {
    if (e.response?.statusCode != 400) return null;
    final body = e.response?.data?.toString() ?? '';
    if (body.contains('verification-token-expired')) {
      return VerificationTokenErrorKind.expired;
    }
    if (body.contains('verification-token-invalid')) {
      return VerificationTokenErrorKind.invalid;
    }
    return null;
  }

  PasswordAuthServerErrorKind _classify(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return PasswordAuthServerErrorKind.serverNotResponding;
    }
    if (e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return PasswordAuthServerErrorKind.cannotConnect;
    }
    if (e.type == DioExceptionType.badResponse) {
      return PasswordAuthServerErrorKind.invalidResponse;
    }
    return PasswordAuthServerErrorKind.connectionFailed;
  }
}
