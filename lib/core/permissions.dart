/// Bitwise permission flag constants mirroring the backend `Permission` enum.
///
/// Convention: `kRead{Resource}` / `kWrite{Resource}` — never per-action.
/// Bits 256/512 are reserved for billing plan feature flags.
abstract final class Permissions {
  /// Manage organization membership and roles.
  static const int organizationManagement = 2;

  /// Manage agents — approve, deactivate, reactivate and edit agents.
  static const int agentManage = 16;

  /// Manage grants — list, view, approve, deny and revoke agent grants.
  static const int grantManage = 32;

  /// View audit logs — read the org/vault/entry audit-log surfaces.
  static const int auditView = 128;

  /// Billing plan flag — may own more than one vault (bit 256). Granted by the
  /// backend; mirrors web `PERMISSION_MULTIPLE_VAULTS`.
  static const int multipleVaults = 256;

  static const int readApiKey = 4096;
  static const int writeApiKey = 8192;
}
