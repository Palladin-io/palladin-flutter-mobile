import '../domain/entities/audit_log_entry.dart';

/// An agent option for an audit Logs filter dropdown — id plus resolved name.
class AgentOption {
  const AgentOption({required this.id, required this.name});

  final String id;
  final String name;
}

/// A vault option for the org-wide Logs filter dropdown — id plus name.
class VaultOption {
  const VaultOption({required this.id, required this.name});

  final String id;
  final String name;
}

/// A user (human actor) option for the audit filter dropdown — id plus the
/// display name resolved from the entry's denormalized `actorName`. [name] is
/// `null` when the backend supplied no actor name; the presentation layer
/// substitutes a localized "Unknown user" label (never a raw/short id).
class UserOption {
  const UserOption({required this.id, this.name});

  final String id;
  final String? name;
}

/// The full selection returned by the audit filter sheet. Every facet is
/// multi-select: event-type [groups], [agentIds], [userIds] and [vaultIds]
/// plus a date range. An empty set means "all" for that facet; within a facet
/// the values are OR-ed, and the facets are AND-ed together.
class AuditLogFilter {
  const AuditLogFilter({
    this.groups = const {},
    this.agentIds = const {},
    this.userIds = const {},
    this.vaultIds = const {},
    this.fromDate,
    this.toDate,
  });

  final Set<AuditEventGroup> groups;
  final Set<String> agentIds;
  final Set<String> userIds;
  final Set<String> vaultIds;
  final DateTime? fromDate;
  final DateTime? toDate;

  bool get isEmpty =>
      groups.isEmpty &&
      agentIds.isEmpty &&
      userIds.isEmpty &&
      vaultIds.isEmpty &&
      fromDate == null &&
      toDate == null;
}
