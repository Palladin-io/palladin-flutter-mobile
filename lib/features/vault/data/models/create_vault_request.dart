import '../../domain/entities/vault_entity.dart';

/// DTO sent to `POST /api/vaults` to create a new vault.
///
/// All fields are JSON-serialized as camelCase. [wrappedVK] is a
/// base64-encoded sealed-box ciphertext — the backend deserializes
/// base64 strings into `byte[]` automatically via FastEndpoints.
class CreateVaultRequest {
  const CreateVaultRequest({
    required this.name,
    this.description,
    this.icon,
    this.color,
    required this.grantMode,
    required this.wrappedVK,
  });

  final String name;
  final String? description;
  final String? icon;
  final String? color;
  final GrantMode grantMode;

  /// Base64-encoded sealed VK. See `VaultCryptoService.generateWrappedVK`.
  final String wrappedVK;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      'grantMode': grantMode.toInt(),
      'wrappedVK': wrappedVK,
    };
  }
}

/// DTO sent to `PUT /api/vaults/{id}` for partial updates.
///
/// Each field is optional — only the supplied (non-null) keys are
/// emitted to JSON, so the backend can patch metadata without callers
/// resending unchanged fields.
class UpdateVaultRequest {
  const UpdateVaultRequest({
    this.name,
    this.description,
    this.icon,
    this.color,
    this.grantMode,
  });

  final String? name;
  final String? description;
  final String? icon;
  final String? color;
  final GrantMode? grantMode;

  Map<String, dynamic> toJson() {
    return {
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (icon != null) 'icon': icon,
      if (color != null) 'color': color,
      if (grantMode != null) 'grantMode': grantMode!.toInt(),
    };
  }
}
