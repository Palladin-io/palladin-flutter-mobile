/// Type of vault entry — drives icon, payload schema, and reveal-panel
/// layout.
///
/// Mirrors the backend `EntryType` enum (`Key = 0`, `Credential = 1`).
/// Wire format is the integer ordinal stored on the row-level `type`
/// column. The decrypted payload schema is selected by [EntryType] on
/// the client; the JSONB content envelope itself carries no
/// discriminator.
enum EntryType {
  /// Single secret value — API key, token, etc.
  key,

  /// Username + password (+ optional URL).
  credential,
}

extension EntryTypeExtension on EntryType {
  /// Wire format used by the .NET API (int ordinal: `Key = 0`,
  /// `Credential = 1`).
  int toWire() => switch (this) {
        EntryType.key => 0,
        EntryType.credential => 1,
      };

  static EntryType fromWire(int value) => switch (value) {
        0 => EntryType.key,
        1 => EntryType.credential,
        // Default to credential for unknown wire values — surfaces the
        // safer two-field reveal panel rather than the single-secret
        // panel, matching the backend default.
        _ => EntryType.credential,
      };
}

/// Domain representation of a single vault entry's metadata.
///
/// Encrypted payload (the actual secret) is intentionally NOT part of
/// this entity — it is loaded lazily from `GET /api/vaults/{vaultId}/entries/{id}`
/// when the user reveals the entry, and decrypted on-device.
class EntryEntity {
  const EntryEntity({
    required this.id,
    required this.vaultId,
    required this.label,
    this.description,
    this.icon,
    required this.type,
    this.urlDomain,
    required this.createdAt,
    required this.updatedAt,
    this.lastAccessedAt,
    this.accessCount = 0,
  });

  /// Stable, server-issued identifier.
  final String id;

  /// Vault this entry belongs to.
  final String vaultId;

  /// User-supplied display label (e.g. "Stripe API Key").
  final String label;

  /// Optional description shown under the label in the row.
  final String? description;

  /// Optional icon name — same identifier vocabulary as
  /// `VaultVisuals.iconChoices` (`shield`, `code`, `cloud`, …).
  final String? icon;

  /// Entry type — see [EntryType].
  final EntryType type;

  /// Plaintext URL domain (e.g. `stripe.com`) shown as meta line. The
  /// full URL lives inside the encrypted payload.
  final String? urlDomain;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Timestamp of the most recent reveal/decrypt — null when never
  /// accessed.
  final DateTime? lastAccessedAt;

  /// Total number of reveals server-side.
  final int accessCount;

  EntryEntity copyWith({String? icon}) => EntryEntity(
        id: id,
        vaultId: vaultId,
        label: label,
        description: description,
        icon: icon ?? this.icon,
        type: type,
        urlDomain: urlDomain,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastAccessedAt: lastAccessedAt,
        accessCount: accessCount,
      );
}

/// Plaintext payload shape for a `KEY` entry. Lives only in memory
/// after decryption — never persisted in plaintext.
class KeyPayload {
  const KeyPayload({required this.value, this.url, this.notes});

  /// The secret itself (token, API key, …).
  final String value;

  /// Optional associated URL (documentation link, service URL, …).
  final String? url;

  final String? notes;

  Map<String, dynamic> toJson() => {
        'type': 'KEY',
        'value': value,
        if (url != null) 'url': url,
        if (notes != null) 'notes': notes,
      };

  factory KeyPayload.fromJson(Map<String, dynamic> json) => KeyPayload(
        value: (json['value'] as String?) ?? '',
        url: json['url'] as String?,
        notes: json['notes'] as String?,
      );
}

/// Plaintext payload shape for a `CREDENTIAL` entry. Lives only in
/// memory after decryption — never persisted in plaintext.
class CredentialPayload {
  const CredentialPayload({
    required this.username,
    required this.password,
    this.url,
    this.notes,
  });

  final String username;
  final String password;
  final String? url;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'type': 'CREDENTIAL',
        'username': username,
        'password': password,
        if (url != null) 'url': url,
        if (notes != null) 'notes': notes,
      };

  factory CredentialPayload.fromJson(Map<String, dynamic> json) =>
      CredentialPayload(
        username: (json['username'] as String?) ?? '',
        password: (json['password'] as String?) ?? '',
        url: json['url'] as String?,
        notes: json['notes'] as String?,
      );
}
