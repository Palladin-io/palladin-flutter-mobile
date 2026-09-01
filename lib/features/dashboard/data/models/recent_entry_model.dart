import '../../domain/entities/recent_entry_entity.dart';

/// DTO for one item in `GET /api/entries?sort=recent` response.
class RecentEntryModel {
  const RecentEntryModel({
    required this.id,
    required this.label,
    required this.vaultId,
    required this.vaultName,
    required this.type,
    required this.currentRevision,
    required this.currentKeyVersion,
    this.icon,
    required this.updatedAt,
    required this.createdAt,
  });

  final String id;
  final String label;
  final String vaultId;
  final String vaultName;
  final int type;
  final String currentRevision;
  final int currentKeyVersion;
  final String? icon;
  final String updatedAt;
  final String createdAt;

  factory RecentEntryModel.fromJson(Map<String, dynamic> json) {
    return RecentEntryModel(
      id: json['id'] as String,
      label: json['label'] as String,
      vaultId: json['vaultId'] as String,
      vaultName: json['vaultName'] as String,
      type: _parseType(json['type']),
      currentRevision: json['currentRevision'] as String,
      currentKeyVersion: json['currentKeyVersion'] as int,
      icon: json['icon'] as String?,
      updatedAt: json['updatedAt'] as String,
      createdAt: json['createdAt'] as String,
    );
  }

  static int _parseType(dynamic raw) {
    if (raw is int) return raw;
    return switch (raw as String) {
      'Key' || 'key' => 0,
      'Credential' || 'credential' => 1,
      _ => 0,
    };
  }

  RecentEntryEntity toEntity() => RecentEntryEntity(
    id: id,
    label: label,
    vaultId: vaultId,
    vaultName: vaultName,
    typeWire: type,
    currentRevision: currentRevision,
    currentKeyVersion: currentKeyVersion,
    icon: icon,
    updatedAt: DateTime.parse(updatedAt),
    createdAt: DateTime.parse(createdAt),
  );
}
