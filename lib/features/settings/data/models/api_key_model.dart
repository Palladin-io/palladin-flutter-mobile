import '../../domain/entities/api_key.dart';

/// DTO for an item inside `GET /api/api-keys` (`items[]`).
///
/// Uses camelCase keys to match the .NET API. Carries metadata only —
/// the plaintext secret is never present in a list response.
class ApiKeyModel {
  const ApiKeyModel({
    required this.apiKeyId,
    required this.name,
    required this.keySuffix,
    required this.status,
    required this.createdAt,
    this.revokedAt,
  });

  final String apiKeyId;
  final String name;
  final String keySuffix;

  /// Wire-format status string — `"active"` / `"revoked"`.
  final String status;

  final String createdAt;
  final String? revokedAt;

  factory ApiKeyModel.fromJson(Map<String, dynamic> json) {
    return ApiKeyModel(
      apiKeyId: json['apiKeyId'] as String,
      name: json['name'] as String,
      keySuffix: (json['keySuffix'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'revoked',
      createdAt: json['createdAt'] as String,
      revokedAt: json['revokedAt'] as String?,
    );
  }

  ApiKey toEntity() {
    return ApiKey(
      apiKeyId: apiKeyId,
      name: name,
      keySuffix: keySuffix,
      status: ApiKeyStatusExtension.fromWire(status),
      createdAt: DateTime.parse(createdAt),
      revokedAt: revokedAt != null ? DateTime.parse(revokedAt!) : null,
    );
  }
}

/// DTO returned by `POST /api/api-keys` — includes the one-time
/// [plaintext] secret.
///
/// SECURITY: [plaintext] is the only time the secret is ever exposed by
/// the backend. Map it straight into the [NewApiKey] domain object and
/// never persist or log it.
class NewApiKeyModel {
  const NewApiKeyModel({
    required this.apiKeyId,
    required this.name,
    required this.plaintext,
    required this.createdAt,
  });

  final String apiKeyId;
  final String name;
  final String plaintext;
  final String createdAt;

  factory NewApiKeyModel.fromJson(Map<String, dynamic> json) {
    return NewApiKeyModel(
      apiKeyId: json['apiKeyId'] as String,
      name: json['name'] as String,
      plaintext: json['plaintext'] as String,
      createdAt: json['createdAt'] as String,
    );
  }

  NewApiKey toEntity() {
    return NewApiKey(
      apiKeyId: apiKeyId,
      name: name,
      plaintext: plaintext,
      createdAt: DateTime.parse(createdAt),
    );
  }
}
