import '../../domain/entities/org.dart';

/// DTO returned by the backend's `GET /api/org`.
///
/// Uses camelCase keys to match the .NET API. Maps to a domain [Org]
/// via [toEntity] so the rest of the app never sees raw JSON shapes.
class OrgModel {
  const OrgModel({
    required this.orgId,
    required this.name,
    required this.planType,
    required this.memberCount,
    required this.seatUsage,
    required this.seatLimit,
  });

  final String orgId;
  final String name;
  final String planType;
  final int memberCount;
  final int seatUsage;
  final int seatLimit;

  factory OrgModel.fromJson(Map<String, dynamic> json) {
    return OrgModel(
      orgId: json['orgId'] as String,
      name: json['name'] as String,
      planType: (json['planType'] as String?) ?? '',
      memberCount: (json['memberCount'] as int?) ?? 1,
      seatUsage: json['seatUsage'] as int,
      seatLimit: json['seatLimit'] as int,
    );
  }

  Org toEntity() {
    return Org(
      orgId: orgId,
      name: name,
      planType: planType,
      memberCount: memberCount,
      seatUsage: seatUsage,
      seatLimit: seatLimit,
    );
  }
}
