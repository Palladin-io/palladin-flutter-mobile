# notifications

Inbox (notification center) + preferences + push/real-time transport.

- **Cubits:** `NotificationCenterCubit`, `NotificationPreferencesCubit`, `PushNavigationCubit`.
- **Pages:** `NotificationCenterPage` (segment: All / Todo / History), `NotificationPreferencesPage`, `InboxGrantsPage`.
- **Widgets:** `NotificationCard`.
- **Transport (data layer):** `NotificationSignalRService` (in-app real-time via `/hubs/notifications`) + `PushNotificationService` (FCM/APNs background). SignalR has no OS notification → must call `showLocalNotification` manually.
- **Layering:** full data / domain / presentation split.

**Cross-feature deps (heavy):** `agents` (`AgentAvatar`, `ApproveAgentSheet`, `DeactivateAgentSheet`), `grants` (`GrantDetailRow`), `approval` (`ApproveGrantSheet`, `DenyGrantSheet`).

**⚠ Architecture smell:** `_EmptyCard` duplicates the empty-card pattern → extract `ListEmptyCard` (shared with agents + api_keys). See [../widget-catalog.md](../widget-catalog.md).
