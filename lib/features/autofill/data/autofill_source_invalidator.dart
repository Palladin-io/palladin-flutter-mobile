import '../domain/autofill_cache_invalidator.dart';
import 'autofill_cache_bridge.dart';
import 'autofill_source_access_service.dart';

/// Revokes request-time access and retires the previous derivative cache.
/// Never creates a cache session, reads credentials or ends the source cleanup
/// capability before biometric-account cleanup has completed.
final class AutoFillSourceInvalidator implements AutoFillCacheInvalidator {
  AutoFillSourceInvalidator({
    required AutoFillSourceAccessService source,
    required AutoFillCacheBridge legacy,
    bool supported = true,
  }) : _supported = supported,
       _source = source,
       _legacy = legacy;
  final bool _supported;
  final AutoFillSourceAccessService _source;
  final AutoFillCacheBridge _legacy;
  int? _retirementToken;
  void Function()? _validateRetirement;

  @override
  Future<void> revokeAccess() async {
    if (!_supported) return;
    final validate = _source.captureSessionGuard();
    await _source.revokeAccess();
    validate();
    final token = await _legacy.revokeCacheAccess();
    validate();
    _retirementToken = token;
    _validateRetirement = validate;
  }

  Future<void> retireLegacy() async {
    if (!_supported) return;
    final token = await _legacy.revokeCacheAccess();
    await _legacy.clearCache(sessionToken: token);
  }

  @override
  Future<void> clear() async {
    if (!_supported) return;
    if (_retirementToken == null) await revokeAccess();
    _validateRetirement!();
    final token = _retirementToken!;
    await _legacy.clearCache(sessionToken: token);
  }
}
