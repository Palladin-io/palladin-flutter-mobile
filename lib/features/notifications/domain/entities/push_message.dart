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
    this.title,
    this.body,
    this.notificationId,
    this.grantId,
    this.agentId,
    this.entryId,
  });

  final PushNotificationType type;

  /// Inbox notification id (frozen contract: push carries `notificationId` +
  /// `type`). Used to deep-link to `/inbox?focus=<id>` and mark it read.
  final String? notificationId;

  /// Notification title (for the in-app foreground banner only — the OS
  /// renders the background/terminated notification itself).
  final String? title;

  /// Notification body (foreground banner only).
  final String? body;

  final String? grantId;
  final String? agentId;
  final String? entryId;

  /// Builds a [PushMessage] from the FCM `notification` + `data` parts.
  ///
  /// [data] is the raw `RemoteMessage.data` map; [title]/[body] come from
  /// `RemoteMessage.notification`. Missing keys yield `null` — never
  /// throws, so a malformed payload degrades gracefully to [unknown].
  factory PushMessage.fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    String? str(String key) {
      final value = data[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return PushMessage(
      type: PushNotificationType.fromRaw(str('type')),
      title: title,
      body: body,
      notificationId: str('notificationId'),
      grantId: str('grantId'),
      agentId: str('agentId'),
      entryId: str('entryId'),
    );
  }

  /// Serializes the routing-relevant fields back to the same shape
  /// [PushMessage.fromData] consumes — so a round-trip through the
  /// local-notification payload preserves the deep-link target.
  Map<String, dynamic> toRoutingData() {
    return <String, dynamic>{
      'type': type.wireValue,
      if (notificationId != null) 'notificationId': notificationId,
      if (grantId != null) 'grantId': grantId,
      if (agentId != null) 'agentId': agentId,
      if (entryId != null) 'entryId': entryId,
    };
  }
}
