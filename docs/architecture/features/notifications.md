# notifications

Inbox (notification center) + preferences + push/real-time transport.

## Entry sharing receipts (CVT-644, feature branch)

`entry_share_received` has localized EN/PL title, filter, subtitle and receipt
details. It uses the existing card and success token, not an Agent avatar or
approval actions. Source Entry/Vault labels come only from the existing unlocked
local resolver; forged presentation/deep links are ignored and lock redacts
labels and destination ids. The share id is shown as `prefix…suffix`.

Receipt text distinguishes display confirmation from proof of human reading.
It wraps fully at 320px/150% text scale; the date sits below the subtitle so it
cannot squeeze the explanation. `GrantDetailRow` allows unlimited lines for
these details without changing other cards.

The backend creates this sender-only Inbox item after the first confirmed receipt
only when selected by the sender. This adds no push, SignalR or email channel;
audit remains unconditional. The localized `View sharing` footer opens the
existing Entry Detail page directly on Sharing, not on the secret Details tab.
Local presentation tests do not prove live delivery or device acceptance.

### Receipt navigation

Only the allowlisted receipt type and structural Vault/Entry ids select the
destination; supplied URLs and presentation labels are never used. The current
verified, unlocked account must have VaultManage and the Vault in its loaded
list. `NotificationSharingEntryResolver` uses the existing
`MemberEntryListLoader`, so an unopened Vault is synchronized through the normal
encrypted Member path rather than incorrectly treated as absent. It maps only
an exact, unambiguous, readable active/archived local MemberIndex row. Missing,
deleted, corrupt or unavailable entries produce a localized generic message.

Independent Member authority is checked before and after loading. Pending work
cannot navigate after account, organization/membership generation, key session,
Inbox generation, Vault-list snapshot, foreground or current-route changes.
The resolver owns no new crypto or persistent cache. Sharing retains its own
authoritative API access check. Existing Entry Detail callers still start on
Details. Tests cover mounted EN/PL Inbox-to-tab navigation without initializing
the secret editor, substituted Member loading and delayed security transitions;
these are not real backend/device delivery tests.

## Foreground repair and session fencing

`PalladinApp` owns `NotificationForegroundRepair`. It refreshes immediately when
foreground account/Vault context becomes ready, then every 30 seconds. Only a
verified, onboarded, unlocked account with a loaded Vault list can repair. The
existing Member session authority independently supplies account/organization;
late authority after auth, Vault, lifecycle or disposal changes cannot start a
request. One repair per generation may run at a time. Background/lock/disposal
cancel the timer and redact local presentation; account replacement resets the
Inbox. This is bounded repair of the durable Inbox, not a new delivery channel.

`NotificationCenterCubit` fences awaited feed, summary, pagination and local-name
resolution with a session generation. Newer first-page and summary requests win;
old pagination cannot append to a replaced feed. Read mutation failures never
restore another session or overwrite a newer feed. An ambiguous failed read is
reconciled by the next authoritative refresh. Same-context configuration is a
no-op, so it does not cancel an unrelated read action. Inbox bootstrap also checks
the current auth/Vault snapshot and foreground state after asynchronous token
reads and before continuing. Tests use delayed repositories, real local-label
resolution with a substituted index, and a controlled timer; device/backend
acceptance remains required.

- **Cubits:** `NotificationCenterCubit`, `NotificationPreferencesCubit`, `PushNavigationCubit`.
- **Pages:** `NotificationCenterPage` (segment: All / Todo / History), `NotificationPreferencesPage`, `InboxGrantsPage`.
- **Widgets:** `NotificationCard`.
- **Transport (data layer):** `NotificationSignalRService` (in-app real-time via `/hubs/notifications`) + `PushNotificationService` (FCM/APNs background). SignalR has no OS notification → must call `showLocalNotification` manually.
- **Layering:** full data / domain / presentation split.

## Generic push and zero-knowledge resolution

- FCM/APNs data accepts exactly `type`, `category`, `subjectId`, and
  `occurredAt`; resource ids, rendered copy, and deep links are rejected.
- Future category strings still trigger the authoritative Inbox refresh; they
  do not gain an action or a deep link merely by being accepted.
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
  Each summary request snapshots the guard before its asynchronous fetch so an
  older overlapping response cannot restore a badge cleared by a newer feed.

**Cross-feature deps (heavy):** `agents` (`AgentAvatar`, `ApproveAgentSheet`, `DeactivateAgentSheet`), `grants` (`GrantDetailRow`), `approval` (`ApproveGrantSheet`, `DenyGrantSheet`).

**⚠ Architecture smell:** `_EmptyCard` duplicates the empty-card pattern → extract `ListEmptyCard` (shared with agents + api_keys). See the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md).
