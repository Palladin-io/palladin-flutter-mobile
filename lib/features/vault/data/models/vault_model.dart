import '../../domain/entities/vault_entity.dart';

/// DTO returned by the backend's `GET /api/vaults/{id}` and item shape
/// inside `GET /api/vaults`.
///
/// Uses camelCase keys to match the .NET API. Maps to a domain
/// [VaultEntity] via [toEntity] so the rest of the app never sees raw
/// JSON shapes.
class VaultModel {
  const VaultModel({
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
  });

  final String id;
  final String name;
  final String? description;
  final String? icon;
  final String? color;

  /// Wire-format integer (`1 = Full`, `2 = Granular`).
  final int grantMode;

  final String createdAt;
  final String updatedAt;
  final int entryCount;
  final int activeGrantCount;
  final int memberCount;

  factory VaultModel.fromJson(Map<String, dynamic> json) {
    // Counters and memberCount are missing from the create-vault response
    // (only the list endpoint returns them). Default to safe values so
    // newly-created vaults render correctly until the next list refresh.
    return VaultModel(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      grantMode: (json['grantMode'] as int?) ?? 1,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      entryCount: (json['entryCount'] as int?) ?? 0,
      activeGrantCount: (json['activeGrantCount'] as int?) ?? 0,
      memberCount: (json['memberCount'] as int?) ?? 1,
    );
  }

  VaultEntity toEntity() {
    return VaultEntity(
      id: id,
      name: name,
      description: description,
      icon: icon,
      color: color,
      grantMode: GrantModeExtension.fromInt(grantMode),
      createdAt: DateTime.parse(createdAt),
      updatedAt: DateTime.parse(updatedAt),
      entryCount: entryCount,
      activeGrantCount: activeGrantCount,
      memberCount: memberCount,
    );
  }
}
