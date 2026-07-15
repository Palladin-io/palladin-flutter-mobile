/// Security boundary for revoking all native AutoFill credentials.
abstract interface class AutoFillCacheInvalidator {
  /// Immediately removes the native cache ciphertext and its platform key.
  ///
  /// This security-critical operation bypasses queued identity maintenance so
  /// logout never depends on a previously wedged synchronization task.
  Future<void> revokeAccess();

  /// Removes native cache ciphertext, its platform key, and provider metadata.
  ///
  /// The future completes only after the native provider is no longer able to
  /// release cached credentials; failures are propagated to the caller.
  Future<void> clear();
}
