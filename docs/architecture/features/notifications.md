# notifications

Inbox (notification center) + preferences + push/real-time transport.

- **Cubits:** `NotificationCenterCubit`, `NotificationPreferencesCubit`, `PushNavigationCubit`.
- **Pages:** `NotificationCenterPage` (segment: All / Todo / History), `NotificationPreferencesPage`, `InboxGrantsPage`.
- **Widgets:** `NotificationCard`.
- **Transport (data layer):** `NotificationSignalRService` (in-app real-time via `/hubs/notifications`) + `PushNotificationService` (FCM/APNs background). SignalR has no OS notification → must call `showLocalNotification` manually.
- **Layering:** full data / domain / presentation split.

## Generic push and zero-knowledge resolution

- FCM/APNs data accepts exactly `type`, `category`, `subjectId`, and
  `occurredAt`; resource ids, rendered copy, and deep links are rejected.
- Foreground/background duplicates use a bounded, session-memory composite
  key. Nothing from the filter is persisted.
- A tap performs a bounded cursor-based Inbox re-fetch and navigates only when
  the active account's authoritative item matches the structural event.
- Vault and Entry labels resolve only after confirmed unlock from the active
  Vault list and exact Vault-scoped `MemberIndexReader`. Missing, deleted,
  corrupt, forged, and cross-account references remain generic.
- Card routes use an allowlisted type plus authoritative Inbox metadata.
  `actionDeepLink` from transport or Inbox metadata is never trusted.
- Notification logs omit payloads, resource identifiers, and raw exceptions.
- Pending and historical Grant notifications resolve `Reason` from the
  authoritative grant's encrypted envelope and `By` from its actor id plus the
  Vault Member directory. Notification metadata never carries plaintext or
  ciphertext reason, and server-supplied presentation names/free text are
  discarded. The singleton Inbox state keeps decrypted reason only in memory
  and redacts it with locally resolved names whenever the Vault session locks.
- After a confirmed inline action succeeds, the singleton Inbox keeps the
  resolved notification id in session memory so an eventually consistent feed
  or summary response cannot reopen the To-do card or badge. Logout clears this
  guard; a later request uses a new notification id. A missing id retires the
  counter guard only after a complete cursor traversal, and a summary fetched
  alongside the converged feed still uses the guard for that paired response.

**Cross-feature deps (heavy):** `agents` (`AgentAvatar`, `ApproveAgentSheet`, `DeactivateAgentSheet`), `grants` (`GrantDetailRow`), `approval` (`ApproveGrantSheet`, `DenyGrantSheet`).

**⚠ Architecture smell:** `_EmptyCard` duplicates the empty-card pattern → extract `ListEmptyCard` (shared with agents + api_keys). See the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md).
