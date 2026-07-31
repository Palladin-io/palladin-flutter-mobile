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
    this.type,
    this.iconKey,
    this.iconColor,
    this.publicKeyPrefix = '',
    this.publicKey = '',
    this.recipientKeyVersion = 1,
    this.enrolledAt,
    this.enrolledByName,
    this.deactivatedAt,
    this.deactivatedByName,
    this.description,
    this.lastAccessAt,
    this.lastIp,
    this.lastHostname,
  });

  final String agentId;
  final String? name;

  /// Wire-format status — the .NET backend serializes the enum as a
  /// camelCase string (`"pending"` / `"active"` / `"deactivated"`)
  /// thanks to a global `JsonStringEnumConverter(JsonNamingPolicy.CamelCase)`.
  /// We normalize it to an int here (`1` pending / `2` active /
  /// `3` deactivated) and still accept the numeric form for backwards
  /// compatibility with older payloads.
  final int status;

  /// Agent classification — `openClaw` / `claudeCode` / `hermes` /
  /// `other`, or `null` when not set.
  final String? type;

  /// Material icon name chosen for the agent, or `null` when unset.
  final String? iconKey;

  /// Hex color string (e.g. `"#10B981"`) for the icon tint, or `null`.
  final String? iconColor;

  /// First 8 characters of the public key. Defaults to `''` for older
  /// payloads that pre-date this field.
  final String publicKeyPrefix;

  /// Full public key. Defaults to `''` for older payloads that only
  /// exposed the suffix.
  final String publicKey;
  final int recipientKeyVersion;

  final String publicKeySuffix;
  final String createdAt;
  final String? enrolledAt;
  final String? enrolledByName;
  final String? deactivatedAt;
  final String? deactivatedByName;
  final String? description;

  /// ISO-8601 UTC timestamp of the agent's last successful access, or
  /// `null` if the agent has never made a request. Serialized from the
  /// backend's NodaTime `Instant`.
  final String? lastAccessAt;

  /// Last known IP address the agent connected from, or `null` when the
  /// agent has not been seen yet.
  final String? lastIp;

  /// Last known hostname the agent connected from, or `null` when not
  /// reported.
  final String? lastHostname;

  factory AgentModel.fromJson(Map<String, dynamic> json) {
    return AgentModel(
      agentId: json['agentId'] as String,
      name: json['name'] as String?,
      // Backend sends camelCase strings ("pending"/"active"/"deactivated")
      // via JsonStringEnumConverter, but accept ints too for backwards
      // compatibility. Default to `3` (deactivated) on a missing/malformed
      // status so a bad payload fails closed rather than rendering as active.
      status: switch (json['status']) {
        final num n => n.toInt(),
        'pending' => 1,
        'active' => 2,
        'deactivated' => 3,
        'deactivating' => 4,
        _ => 3, // fail closed
      },
      type: json['type'] as String?,
      iconKey: json['iconKey'] as String?,
      iconColor: json['iconColor'] as String?,
      publicKeyPrefix: (json['publicKeyPrefix'] as String?) ?? '',
      publicKey: (json['publicKey'] as String?) ?? '',
      recipientKeyVersion: (json['recipientKeyVersion'] as num?)?.toInt() ?? 1,
      publicKeySuffix: (json['publicKeySuffix'] as String?) ?? '',
      createdAt: json['createdAt'] as String,
      enrolledAt: json['enrolledAt'] as String?,
      enrolledByName: json['enrolledByName'] as String?,
      deactivatedAt: json['deactivatedAt'] as String?,
      deactivatedByName: json['deactivatedByName'] as String?,
      description: json['description'] as String?,
      lastAccessAt: json['lastAccessAt'] as String?,
      lastIp: json['lastIp'] as String?,
      lastHostname: json['lastHostname'] as String?,
    );
  }

  Agent toEntity() {
    return Agent(
      agentId: agentId,
      name: name,
      status: AgentStatusExtension.fromWire(status),
      type: type,
      iconKey: iconKey,
      iconColor: iconColor,
      publicKeyPrefix: publicKeyPrefix,
      publicKey: publicKey,
      recipientKeyVersion: recipientKeyVersion,
      publicKeySuffix: publicKeySuffix,
      createdAt: DateTime.parse(createdAt),
      enrolledAt: enrolledAt != null ? DateTime.parse(enrolledAt!) : null,
      enrolledByName: enrolledByName,
      deactivatedAt: deactivatedAt != null
          ? DateTime.parse(deactivatedAt!)
          : null,
      deactivatedByName: deactivatedByName,
      description: description,
      lastAccessAt: lastAccessAt != null ? DateTime.parse(lastAccessAt!) : null,
      lastIp: lastIp,
      lastHostname: lastHostname,
    );
  }
}
