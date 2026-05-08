import '../../domain/entities/entry_entity.dart';

/// DTO for an entry summary returned by the list endpoint
/// (`GET /api/vaults/{vaultId}/entries`).
///
/// Camel-case keys to match the .NET API. Maps to a domain
/// [EntryEntity] via [toEntity] so the rest of the app never sees raw
/// JSON shapes. The encrypted payload is intentionally absent on the
/// list response — it is fetched lazily from the detail endpoint on
/// reveal.
class EntryModel {
  const EntryModel({
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

  final String id;
  final String vaultId;
  final String label;
  final String? description;
  final String? icon;

  /// Wire format — `'KEY'` / `'CREDENTIAL'`.
  final String type;

  final String? urlDomain;
  final String createdAt;
  final String updatedAt;
  final String? lastAccessedAt;
  final int accessCount;

  factory EntryModel.fromJson(Map<String, dynamic> json) {
    return EntryModel(
      id: json['id'] as String,
      vaultId: json['vaultId'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
      icon: json['icon'] as String?,
      type: json['type'] as String,
      urlDomain: json['urlDomain'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      lastAccessedAt: json['lastAccessedAt'] as String?,
      accessCount: (json['accessCount'] as int?) ?? 0,
    );
  }

  EntryEntity toEntity() {
    return EntryEntity(
      id: id,
      vaultId: vaultId,
      label: label,
      description: description,
      icon: icon,
      type: EntryTypeExtension.fromWire(type),
      urlDomain: urlDomain,
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      lastAccessedAt:
          lastAccessedAt != null ? DateTime.parse(lastAccessedAt!) : null,
      accessCount: accessCount,
    );
  }
}

/// Detail-shape DTO returned by `GET /api/vaults/{vaultId}/entries/{id}`.
///
/// Extends the list shape with the encrypted payload so callers can
/// decrypt on-device. The blob is split into `encryptedBlob` (ciphertext
/// + auth tag) and the matching `nonce` — both base64-encoded.
class EntryDetailModel {
  const EntryDetailModel({
    required this.summary,
    required this.encryptedBlob,
    required this.nonce,
  });

  final EntryModel summary;

  /// Base64-encoded ciphertext (`crypto_secretbox_easy` output).
  final String encryptedBlob;

  /// Base64-encoded nonce (24 random bytes for `crypto_secretbox_easy`).
  final String nonce;

  factory EntryDetailModel.fromJson(Map<String, dynamic> json) {
    return EntryDetailModel(
      summary: EntryModel.fromJson(json),
      encryptedBlob: json['encryptedBlob'] as String,
      nonce: json['nonce'] as String,
    );
  }
}
