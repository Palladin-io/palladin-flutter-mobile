/// Bitwise permission flag constants mirroring the backend `Permission` enum.
///
/// Convention: `kRead{Resource}` / `kWrite{Resource}` — never per-action.
/// Bits 256/512 are reserved for billing plan feature flags.
abstract final class Permissions {
  /// Manage agents — approve, deactivate, reactivate and edit agents.
  static const int agentManage = 16;

  static const int readApiKey = 4096;
  static const int writeApiKey = 8192;
}
