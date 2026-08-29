import 'dart:typed_data';

/// Security boundary for revoking all native AutoFill credentials.
abstract interface class AutoFillCacheInvalidator {
  /// Commits a durable native deny fence before returning.
  ///
  /// Physical ciphertext/key and identity cleanup may finish asynchronously;
  /// the confirmed fence must already prevent every provider release. This
  /// security-critical operation bypasses queued identity maintenance so
  /// logout never depends on a previously wedged synchronization task.
  Future<void> revokeAccess();

  /// Removes native cache ciphertext, its platform key, and provider metadata.
  ///
  /// The future completes only after the native provider is no longer able to
  /// release cached credentials; failures are propagated to the caller.
  Future<void> clear();
}

/// Rebuilds the native derivative strictly from already committed local data.
abstract interface class AutoFillPreparedCacheSynchronizer {
  Future<void> synchronizePrepared({
    required Uint8List privateKey,
    required Iterable<String> vaultIds,
  });
}
