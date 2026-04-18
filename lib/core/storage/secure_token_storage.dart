import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps [FlutterSecureStorage] to provide typed access to auth tokens
/// and user metadata persisted between app sessions.
class SecureTokenStorage {
  SecureTokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';
  static const _isOnboardedKey = 'is_onboarded';

  /// Persists all auth-related tokens and metadata after a successful login
  /// or token refresh.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required bool isOnboarded,
  }) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
      _storage.write(key: _userIdKey, value: userId),
      _storage.write(key: _isOnboardedKey, value: isOnboarded.toString()),
    ]);
  }

  /// Returns the current access token, or `null` if none is stored.
  Future<String?> get accessToken => _storage.read(key: _accessTokenKey);

  /// Returns the current refresh token, or `null` if none is stored.
  Future<String?> get refreshToken => _storage.read(key: _refreshTokenKey);

  /// Returns the stored user ID, or `null` if not authenticated.
  Future<String?> get userId => _storage.read(key: _userIdKey);

  /// Returns whether the user has completed onboarding.
  Future<bool> get isOnboarded async {
    final value = await _storage.read(key: _isOnboardedKey);
    return value == 'true';
  }

  /// Updates only the access and refresh tokens after a silent token
  /// refresh. Does not touch userId or isOnboarded — those are set once
  /// at login and stay valid for the lifetime of the session.
  Future<void> updateTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await Future.wait([
      _storage.write(key: _accessTokenKey, value: accessToken),
      _storage.write(key: _refreshTokenKey, value: refreshToken),
    ]);
  }

  /// Updates the onboarding flag without touching the access/refresh
  /// tokens. Called after `POST /api/account/setup` succeeds so the
  /// router can redirect to the authenticated home.
  Future<void> setOnboarded(bool value) {
    return _storage.write(key: _isOnboardedKey, value: value.toString());
  }

  /// Removes all stored tokens and metadata. Used on logout.
  Future<void> clearAll() => _storage.deleteAll();
}
