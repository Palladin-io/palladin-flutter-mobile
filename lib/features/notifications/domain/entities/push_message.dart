/// Semantic type of an incoming push notification, carried in the FCM
/// `data.type` field by the backend.
///
/// The backend (Firebase Admin SDK) sends a `notification` block
/// (title/body, rendered by the OS) plus a `data` map that drives in-app
/// routing. Each known [PushNotificationType] maps to a destination
/// screen — see the presentation layer for the navigation table.
enum PushNotificationType {
  /// A new grant is awaiting the user's approval.
  grantPending('grant_pending'),

  /// A grant the user requested/owns changed to approved.
  grantApproved('grant_approved'),

  /// A new agent enrolled and is pending approval.
  agentPending('agent_pending'),

  /// An agent was approved — informational update; deep-links to the agent.
  agentApproved('agent_approved'),

  /// An agent's grant was revoked — surfaced in the inbox.
  grantRevoked('grant_revoked'),

  /// An agent reported a credential no longer works (action-required).
  credentialStale('credential_stale'),

  /// Unknown / future type — the app shows the notification but performs
  /// no deep-link navigation.
  unknown('unknown');

  const PushNotificationType(this.wireValue);

  /// The on-the-wire snake_case identifier the backend emits in `data.type`.
  /// Symmetric with [fromRaw] — round-tripping through [wireValue] then
  /// [fromRaw] returns the same enum value.
  final String wireValue;

  /// Maps the raw `data.type` string from the FCM payload to a typed
  /// value. Unrecognized values fall back to [unknown] so a future
  /// backend type never crashes the client.
  static PushNotificationType fromRaw(String? raw) {
    switch (raw) {
      case 'grant_pending':
        return PushNotificationType.grantPending;
      case 'grant_approved':
        return PushNotificationType.grantApproved;
      case 'agent_pending':
        return PushNotificationType.agentPending;
      case 'agent_approved':
        return PushNotificationType.agentApproved;
      case 'grant_revoked':
        return PushNotificationType.grantRevoked;
      case 'credential_stale':
        return PushNotificationType.credentialStale;
      default:
        return PushNotificationType.unknown;
    }
  }
}

/// Parsed, domain-level representation of a push notification.
///
/// Built from a Firebase `RemoteMessage` in the data layer so the
/// presentation layer never touches the raw FCM types directly. Holds
/// only the routing-relevant identifiers — never any secret material.
class PushMessage {
  const PushMessage({
    required this.type,
    required this.category,
    required this.subjectId,
    required this.occurredAt,
  });

  final PushNotificationType type;

  final String category;
  final String subjectId;
  final DateTime occurredAt;

  String get deduplicationKey =>
      '${type.wireValue}\u0000$category\u0000$subjectId\u0000${occurredAt.toUtc().toIso8601String()}';

  /// Builds a [PushMessage] from the FCM `notification` + `data` parts.
  ///
  /// [data] is the raw `RemoteMessage.data` map; [title]/[body] come from
  /// `RemoteMessage.notification`. Missing keys yield `null` — never
  /// throws, so a malformed payload degrades gracefully to [unknown].
  static PushMessage? fromData(Map<String, dynamic> data) {
    const allowed = {'type', 'category', 'subjectId', 'occurredAt'};
    if (data.length != allowed.length ||
        data.keys.any((key) => !allowed.contains(key))) {
      return null;
    }
    String? str(String key) {
      final value = data[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    final type = str('type');
    final category = str('category');
    final subjectId = str('subjectId');
    final occurredAt = DateTime.tryParse(str('occurredAt') ?? '');
    if (type == null ||
        category == null ||
        subjectId == null ||
        occurredAt == null) {
      return null;
    }
    return PushMessage(
      type: PushNotificationType.fromRaw(type),
      category: category,
      subjectId: subjectId,
      occurredAt: occurredAt.toUtc(),
    );
  }

  /// Serializes the routing-relevant fields back to the same shape
  /// [PushMessage.fromData] consumes — so a round-trip through the
  /// local-notification payload preserves the deep-link target.
  Map<String, dynamic> toRoutingData() {
    return <String, dynamic>{
      'type': type.wireValue,
      'category': category,
      'subjectId': subjectId,
      'occurredAt': occurredAt.toUtc().toIso8601String(),
    };
  }
}
