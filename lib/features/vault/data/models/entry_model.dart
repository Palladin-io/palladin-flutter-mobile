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

  /// Wire format — int ordinal of [EntryType] (`Key = 0`, `Credential = 1`).
  final int type;

  final String? urlDomain;
  final String createdAt;
  final String updatedAt;
  final String? lastAccessedAt;
  final int accessCount;

  /// Parses a full entry JSON object.
  ///
  /// [contextVaultId] is required when the JSON does not include a
  /// `vaultId` field — e.g. the `ListEntries` endpoint omits it from
  /// each item because it is implied by the URL. The detail endpoint
  /// (`GetEntry`) does include it, so callers can omit [contextVaultId]
  /// in that case.
  factory EntryModel.fromJson(
    Map<String, dynamic> json, {
    String? contextVaultId,
  }) {
    return EntryModel(
      id: json['id'] as String,
      vaultId: contextVaultId ?? json['vaultId'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
      icon: json['icon'] as String?,
      type: json['type'] as int,
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

/// JSONB content envelope sent and received with an entry.
///
/// Matches the backend `EntryContent` flat record — both
/// [encryptedBlob] and [nonce] are base64-encoded; the backend stores
/// them as `bytea` columns inside the JSONB payload and never sees the
/// plaintext. The schema for the decrypted payload is determined by the
/// row-level [EntryModel.type] column, not by a discriminator on this
/// envelope.
class EntryContentModel {
  const EntryContentModel({
    required this.encryptedBlob,
    required this.nonce,
  });

  /// Base64-encoded ciphertext (`crypto_secretbox_easy` output).
  final String encryptedBlob;

  /// Base64-encoded 24-byte nonce that was used to seal [encryptedBlob].
  final String nonce;

  factory EntryContentModel.fromJson(Map<String, dynamic> json) =>
      EntryContentModel(
        encryptedBlob: json['encryptedBlob'] as String,
        nonce: json['nonce'] as String,
      );

  Map<String, dynamic> toJson() => {
        'encryptedBlob': encryptedBlob,
        'nonce': nonce,
      };
}

/// Detail-shape DTO returned by `GET /api/vaults/{vaultId}/entries/{id}`.
///
/// Extends the list shape with the encrypted [content] envelope so
/// callers can decrypt on-device.
class EntryDetailModel {
  const EntryDetailModel({
    required this.summary,
    required this.content,
  });

  final EntryModel summary;

  /// JSONB envelope holding the encrypted payload.
  final EntryContentModel content;

  factory EntryDetailModel.fromJson(Map<String, dynamic> json) {
    return EntryDetailModel(
      summary: EntryModel.fromJson(json),
      content: EntryContentModel.fromJson(
        json['content'] as Map<String, dynamic>,
      ),
    );
  }
}
