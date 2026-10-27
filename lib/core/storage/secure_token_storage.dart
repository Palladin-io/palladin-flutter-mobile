import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wraps [FlutterSecureStorage] to provide typed access to auth tokens
/// and user metadata persisted between app sessions.
class SecureTokenStorage {
  SecureTokenStorage(this._storage);

  final FlutterSecureStorage _storage;
  Future<void> _tokenMutation = Future<void>.value();
  int _tokenGeneration = 0;

  Future<void> _mutateTokens(Future<void> Function() operation) {
    final next = _tokenMutation.then((_) => operation());
    _tokenMutation = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';
  static const _isOnboardedKey = 'is_onboarded';
  static const _authProviderKey = 'auth_provider';
  static const _defaultVaultProvisionedKey = 'default_vault_provisioned';

  /// Persists all auth-related tokens and metadata after a successful login
  /// or token refresh.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
    required String userId,
    required bool isOnboarded,
  }) {
    ++_tokenGeneration;
    return _mutateTokens(() async {
      await Future.wait([
        _storage.write(key: _accessTokenKey, value: accessToken),
        _storage.write(key: _refreshTokenKey, value: refreshToken),
        _storage.write(key: _userIdKey, value: userId),
        _storage.write(key: _isOnboardedKey, value: isOnboarded.toString()),
      ]);
    });
  }

  /// Returns the current access token, or `null` if none is stored.
  Future<String?> get accessToken async {
    await _tokenMutation;
    return _storage.read(key: _accessTokenKey);
  }

  /// Returns the current refresh token, or `null` if none is stored.
  Future<String?> get refreshToken async {
    await _tokenMutation;
    return _storage.read(key: _refreshTokenKey);
  }

  /// Returns the stored user ID, or `null` if not authenticated.
  Future<String?> get userId async {
    await _tokenMutation;
    return _storage.read(key: _userIdKey);
  }

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
  }) {
    final generation = _tokenGeneration;
    return _mutateTokens(() async {
      if (generation != _tokenGeneration) return;
      await Future.wait([
        _storage.write(key: _accessTokenKey, value: accessToken),
        _storage.write(key: _refreshTokenKey, value: refreshToken),
      ]);
    });
  }

  /// Updates the onboarding flag without touching the access/refresh
  /// tokens. Called after `POST /api/account/setup` succeeds so the
  /// router can redirect to the authenticated home.
  Future<void> setOnboarded(bool value) {
    return _storage.write(key: _isOnboardedKey, value: value.toString());
  }

  /// Records how the session was authenticated (`AuthProviderId.*`). Set at
  /// login / registration; used to gate password-only account actions. Not
  /// a secret — it holds a provider label, never credentials.
  Future<void> setAuthProvider(String provider) {
    return _storage.write(key: _authProviderKey, value: provider);
  }

  /// Returns the stored auth-provider label, or `null` when unknown (e.g. a
  /// session established before this marker existed).
  Future<String?> get authProvider => _storage.read(key: _authProviderKey);

  /// Whether this account's encrypted default vault has been provisioned.
  ///
  /// `null` means the session predates this marker. The value contains no key
  /// material - it only makes the idempotent provisioning retry survive an
  /// application restart.
  Future<bool?> get defaultVaultProvisioned async {
    final value = await _storage.read(key: _defaultVaultProvisionedKey);
    return switch (value) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  Future<void> setDefaultVaultProvisioned(bool value) {
    return _storage.write(
      key: _defaultVaultProvisionedKey,
      value: value.toString(),
    );
  }

  /// Removes all stored tokens and metadata. Used on logout.
  Future<void> clearAll() {
    // Invalidate queued refreshes before waiting for any native writes in flight.
    ++_tokenGeneration;
    return _mutateTokens(_storage.deleteAll);
  }
}
