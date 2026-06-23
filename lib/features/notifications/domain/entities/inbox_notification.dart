/// Category of an inbox notification — mirrors the backend `category` field.
///
/// `actionRequired` items land in the To-do segment; everything else
/// (`update`) lands in History. Unknown future values degrade to [update]
/// so a new backend category never hides an item.
enum NotificationCategory {
  actionRequired,
  update;

  static NotificationCategory fromWire(String? raw) {
    switch (raw) {
      // Backend serializes camelCase (`actionRequired`); the others are
      // tolerant fallbacks for PascalCase / snake_case just in case.
      case 'actionRequired':
      case 'ActionRequired':
      case 'action_required':
        return NotificationCategory.actionRequired;
      default:
        return NotificationCategory.update;
    }
  }
}

/// Lifecycle of an action-required item, projected server-side from the
/// owning module's state (see Notification Center design decision A):
/// `pending` while the action is still open, `resolved` once it has been
/// approved/denied/expired anywhere, `none` for items that never had an
/// action (plain updates).
enum NotificationActionState {
  pending,
  resolved,
  none;

  static NotificationActionState fromWire(String? raw) {
    switch (raw) {
      case 'Pending':
      case 'pending':
        return NotificationActionState.pending;
      case 'Resolved':
      case 'resolved':
        return NotificationActionState.resolved;
      default:
        return NotificationActionState.none;
    }
  }
}

/// A durable, user-visible notification returned by `GET /api/notifications`.
///
/// Per the frozen contract the backend never sends rendered copy — it sends a
/// [titleKey] (i18n key) plus [metadata] (safe presentational names + ids, no
/// secrets). The client renders the localized string from those. Notification
/// [type] is an open string so source modules can add new types without a
/// mobile release.
class InboxNotification {
  const InboxNotification({
    required this.id,
    required this.type,
    required this.category,
    required this.titleKey,
    required this.metadata,
    required this.actionState,
    required this.occurredAt,
    this.readAt,
  });

  final String id;

  /// Open string, e.g. `grant_pending`, `agent_pending`, `credential_stale`.
  final String type;

  final NotificationCategory category;

  /// i18n key from the contract. The presentation layer currently renders copy
  /// keyed off [type] (see `notification_format.dart`) because each type needs
  /// distinct title/subtitle/rows, so [titleKey] is retained from the wire for
  /// forward-compatibility / debugging rather than read directly.
  final String titleKey;

  /// Safe presentational data — names + resource ids (vaultId/entryId/
  /// agentId/grantId, agentName/entryLabel/vaultName/actorName, …). Never
  /// secrets or plaintext.
  final Map<String, dynamic> metadata;

  final NotificationActionState actionState;

  final DateTime occurredAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// An open action belongs in the To-do segment with live action buttons.
  ///
  /// Only the two pending-request types carry an in-app action (Approve /
  /// Deny). Informational alerts like `credential_stale` may arrive as
  /// `actionRequired` from the backend, but they have no inline action on
  /// mobile — they are notifications, not To-do items — so they are
  /// excluded here and surface in All / History with a "View" link only.
  bool get isOpenAction =>
      category == NotificationCategory.actionRequired &&
      actionState == NotificationActionState.pending &&
      (type == 'grant_pending' || type == 'agent_pending');

  /// A pending-request type (grant/agent) that has since been resolved. The
  /// backend collapses these server-side; the client hides them too as
  /// defense-in-depth so a resolved "approve" card never lingers in History.
  bool get isCollapsedPending =>
      actionState == NotificationActionState.resolved &&
      (type == 'grant_pending' || type == 'agent_pending');

  /// Convenience metadata accessors (null when absent / empty).
  String? get grantId => _str('grantId');
  String? get vaultId => _str('vaultId');
  String? get entryId => _str('entryId');
  String? get agentId => _str('agentId');

  String? _str(String key) {
    final value = metadata[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  InboxNotification copyWith({
    NotificationActionState? actionState,
    DateTime? readAt,
    bool markRead = false,
  }) {
    return InboxNotification(
      id: id,
      type: type,
      category: category,
      titleKey: titleKey,
      metadata: metadata,
      actionState: actionState ?? this.actionState,
      occurredAt: occurredAt,
      readAt: markRead ? (readAt ?? DateTime.now()) : (readAt ?? this.readAt),
    );
  }
}

/// One page of the inbox feed (cursor-based, `InstantCursor`).
class NotificationPage {
  const NotificationPage({required this.items, this.nextCursor});

  final List<InboxNotification> items;
  final String? nextCursor;
}

/// Counts for `GET /api/notifications/summary`.
///
/// [unreadCount] drives the bottom-nav badge; [pendingActionCount] drives the
/// To-do segment header count.
class NotificationSummary {
  const NotificationSummary({
    required this.unreadCount,
    required this.pendingActionCount,
  });

  final int unreadCount;
  final int pendingActionCount;
}
