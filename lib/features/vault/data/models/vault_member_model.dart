import '../../domain/entities/vault_member.dart';

/// Wire DTO for the bounded structural Vault Member directory.
final class VaultMemberModel {
  const VaultMemberModel({
    required this.memberId,
    required this.addedAt,
    required this.deprovisioningStatus,
    this.memberName,
    this.rotationId,
  });

  factory VaultMemberModel.fromJson(Map<String, dynamic> json) =>
      VaultMemberModel(
        memberId: json['memberId'] as String,
        memberName: json['memberName'] as String?,
        addedAt: json['addedAt'] as String,
        deprovisioningStatus: json['deprovisioningStatus'] as String,
        rotationId: json['rotationId'] as String?,
      );

  final String memberId;
  final String? memberName;
  final String addedAt;
  final String deprovisioningStatus;
  final String? rotationId;

  VaultMember toEntity() => VaultMember(
    id: memberId,
    name: memberName?.trim(),
    addedAt: DateTime.parse(addedAt).toLocal(),
    status: VaultMemberStatus.fromWire(deprovisioningStatus),
    rotationId: rotationId,
  );
}
