import '../../domain/entities/agent.dart';

/// DTO for an agent returned by the .NET backend.
///
/// Uses camelCase keys to match the API. Carries metadata only — no
/// secret material is ever present.
class AgentModel {
  const AgentModel({
    required this.agentId,
    required this.name,
    required this.status,
    required this.publicKeySuffix,
    required this.createdAt,
    this.enrolledAt,
    this.enrolledByName,
    this.deactivatedAt,
    this.deactivatedByName,
    this.description,
  });

  final String agentId;
  final String? name;

  /// Wire-format status integer — `1` pending / `2` active /
  /// `3` deactivated.
  final int status;

  final String publicKeySuffix;
  final String createdAt;
  final String? enrolledAt;
  final String? enrolledByName;
  final String? deactivatedAt;
  final String? deactivatedByName;
  final String? description;

  factory AgentModel.fromJson(Map<String, dynamic> json) {
    return AgentModel(
      agentId: json['agentId'] as String,
      name: json['name'] as String?,
      // Default to `3` (deactivated) on a missing/malformed status so a
      // bad payload fails closed rather than rendering as active.
      status: (json['status'] as num?)?.toInt() ?? 3,
      publicKeySuffix: (json['publicKeySuffix'] as String?) ?? '',
      createdAt: json['createdAt'] as String,
      enrolledAt: json['enrolledAt'] as String?,
      enrolledByName: json['enrolledByName'] as String?,
      deactivatedAt: json['deactivatedAt'] as String?,
      deactivatedByName: json['deactivatedByName'] as String?,
      description: json['description'] as String?,
    );
  }

  Agent toEntity() {
    return Agent(
      agentId: agentId,
      name: name,
      status: AgentStatusExtension.fromWire(status),
      publicKeySuffix: publicKeySuffix,
      createdAt: DateTime.parse(createdAt),
      enrolledAt: enrolledAt != null ? DateTime.parse(enrolledAt!) : null,
      enrolledByName: enrolledByName,
      deactivatedAt:
          deactivatedAt != null ? DateTime.parse(deactivatedAt!) : null,
      deactivatedByName: deactivatedByName,
      description: description,
    );
  }
}
