/// Grant mode for a vault — controls what level of agent access the
/// vault owner is willing to extend.
///
/// Mirrors the backend `GrantMode` enum (`Full = 1`, `Granular = 2`).
enum GrantMode {
  /// Full mode — agents granted access can read every entry in the
  /// vault. Single approval covers the entire vault.
  full,

  /// Granular mode — every entry needs its own grant. The default and
  /// safer mode for shared vaults.
  granular,
}

extension GrantModeExtension on GrantMode {
  /// Wire-format integer used by the backend API (`Full = 1`,
  /// `Granular = 2`).
  int toInt() => this == GrantMode.full ? 1 : 2;

  static GrantMode fromInt(int value) =>
      value == 1 ? GrantMode.full : GrantMode.granular;
}

/// Domain representation of a single vault.
///
/// Pure domain object created after encrypted metadata is decrypted locally.
class VaultEntity {
  const VaultEntity({
    required this.id,
    required this.name,
    this.description,
    this.icon,
    this.color,
    required this.grantMode,
    required this.createdAt,
    required this.updatedAt,
    required this.entryCount,
    required this.activeGrantCount,
    required this.memberCount,
    this.wrappedVK,
  });

  /// Stable, server-issued identifier.
  final String id;

  /// User-supplied display name.
  final String name;

  /// Optional description, shown on the detail screen.
  final String? description;

  /// Optional emoji icon — single grapheme rendered at the start of
  /// every vault row.
  final String? icon;

  /// Optional accent color in `#RRGGBB` format. Used to tint the icon
  /// chip on the vault card.
  final String? color;

  /// Grant policy for this vault — see [GrantMode].
  final GrantMode grantMode;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Number of password entries currently stored in the vault.
  final int entryCount;

  /// Number of agent grants that are currently active for this vault
  /// (Full grants count as one, Granular grants count per entry).
  final int activeGrantCount;

  /// Number of org members that have access to the vault — currently
  /// always 1 for personal vaults.
  final int memberCount;

  /// Sealed Vault Key wrapped to the owner's public key — base64 string
  /// matching the backend's `byte[]?` wire shape.
  ///
  /// Threaded through from `GET /api/vaults/{id}` so entry create /
  /// reveal flows can decrypt without an extra round-trip. Always `null`
  /// on entries returned from the list endpoint (the list payload omits
  /// `wrappedVK`); presentation code must fall back to a fetch when the
  /// vault was first surfaced via the list.
  ///
  /// SECURITY: transport-only field. Never log, never serialize to disk,
  /// never expose via analytics. The earlier design intentionally kept
  /// `wrappedVK` out of [VaultEntity] to enforce that discipline; the
  /// trade-off taken here (perf gain from skipping a second
  /// `GET /api/vaults/{id}`) only holds while this field is treated as
  /// opaque ciphertext owned by the in-memory auth/vault state.
  final String? wrappedVK;

  VaultEntity copyWith({String? icon}) {
    return VaultEntity(
      id: id,
      name: name,
      description: description,
      icon: icon ?? this.icon,
      color: color,
      grantMode: grantMode,
      createdAt: createdAt,
      updatedAt: updatedAt,
      entryCount: entryCount,
      activeGrantCount: activeGrantCount,
      memberCount: memberCount,
      wrappedVK: wrappedVK,
    );
  }
}
