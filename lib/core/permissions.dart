/// Bitwise permission flag constants mirroring the backend `Permission` enum.
///
/// Convention: `kRead{Resource}` / `kWrite{Resource}` — never per-action.
/// Bits 256/512 are reserved for billing plan feature flags.
abstract final class Permissions {
  static const int readApiKey = 4096;
  static const int writeApiKey = 8192;
}
