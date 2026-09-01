/// Domain representation of the current user's organization.
///
/// Pure domain object — no JSON / DTO concerns. Created from
/// `OrgModel.toEntity()` at the data layer boundary.
class Org {
  const Org({
    required this.orgId,
    required this.name,
    required this.planType,
    required this.memberCount,
    required this.seatUsage,
    required this.seatLimit,
  });

  /// Stable, server-issued identifier.
  final String orgId;

  /// User-supplied organization display name.
  final String name;

  /// Billing plan label (`Free`, `Pro`, …) returned by the backend.
  final String planType;

  /// Number of members that belong to the organization.
  final int memberCount;

  /// Authoritative number of seats consumed by members and pending invitations.
  final int seatUsage;

  /// Authoritative seat capacity assigned to the organization.
  final int seatLimit;

  Org copyWith({String? name}) {
    return Org(
      orgId: orgId,
      name: name ?? this.name,
      planType: planType,
      memberCount: memberCount,
      seatUsage: seatUsage,
      seatLimit: seatLimit,
    );
  }
}
