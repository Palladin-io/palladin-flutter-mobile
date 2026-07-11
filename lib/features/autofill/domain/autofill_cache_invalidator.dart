/// Security boundary for revoking all native AutoFill credentials.
abstract interface class AutoFillCacheInvalidator {
  /// Removes native cache ciphertext, its platform key, and provider metadata.
  ///
  /// The future completes only after the native provider is no longer able to
  /// release cached credentials; failures are propagated to the caller.
  Future<void> clear();
}
