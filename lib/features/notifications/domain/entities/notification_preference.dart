/// A per-type notification preference, as returned by
/// `GET /api/notifications/preferences`.
///
/// Three independent channels — inbox, realtime (SignalR), push (FCM/APNs).
/// [mandatory] types lock the inbox + realtime channels on; only [pushEnabled]
/// stays mutable for them (see Notification Center design: `agent_pending`,
/// `grant_pending`, `grant_revoked`).
class NotificationPreference {
  const NotificationPreference({
    required this.type,
    required this.category,
    required this.inboxEnabled,
    required this.signalREnabled,
    required this.pushEnabled,
    required this.mandatory,
  });

  /// Open string, matches [InboxNotification.type].
  final String type;

  /// `ActionRequired` | `Update` — used only to group rows in the UI.
  final String category;

  final bool inboxEnabled;
  final bool signalREnabled;
  final bool pushEnabled;

  /// When true, inbox + realtime are locked on; push remains mutable.
  final bool mandatory;

  NotificationPreference copyWith({
    bool? inboxEnabled,
    bool? signalREnabled,
    bool? pushEnabled,
  }) {
    return NotificationPreference(
      type: type,
      category: category,
      inboxEnabled: inboxEnabled ?? this.inboxEnabled,
      signalREnabled: signalREnabled ?? this.signalREnabled,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      mandatory: mandatory,
    );
  }
}

/// The three toggleable delivery channels.
enum NotificationChannel { inbox, realtime, push }
