# agents

Agent lifecycle: approve pending agents, deactivate, reactivate, edit.

- **Cubit:** `AgentsCubit`.
- **Pages:** `AgentsPage` (responsive split view at a 720px breakpoint), `AgentDetailPage`.
- **Widgets:** `AgentCard`, `AgentAvatar`, `AgentStatusBadge`, `AgentDetailBody`, `AgentEditForm`, `ApproveAgentSheet`, `DeactivateAgentSheet`.
- **Layering:** full data / domain / presentation split.
- **Refresh ownership:** `AgentsCubit` is the single in-memory source for list
  presentation and audit name resolution. Initial load, lifecycle refresh,
  push refresh, and audit resolution share one in-flight list operation; audit
  falls back to the repository only when no Cubit is supplied. Ordinary
  concurrent consumers still share that operation, while a push/resume
  invalidation received during it queues at most one trailing quiet refresh so
  a response snapshotted before the event cannot leave the list stale.
- **Exports:** `AgentAvatar` is reused by `grants` and `notifications`; it renders glyph keys and uploaded `public-asset:` icons (fetched only from the configured API via `PublicAssetImage`) and shows the initials avatar for any raw `https`/`http`/`file` URL; `AgentStatusBadge` and `ApiKeyStatusBadge` compose the shared `StatusBadge`; feature wrappers own localized labels and semantic colors.

**Cross-feature deps:** consumed by `grants`, `notifications` (which reuse `AgentAvatar` + the approve/deactivate sheets).


Agent Details defaults to shared read-only EntryFieldRow presentation. Status sits beside the identity; an Edit FAB opens the existing form on a root Navigator route above bottom navigation, with a pinned Save footer. Successful Save returns to Details. Active-agent deactivation uses CompactDangerZone and retains the existing confirmation flow.

The root editor observes current AuthBloc permissions and the current Agent record,
so loss of manage permission or deactivation disables editing immediately.
AgentsCubit.updateAgent returns the operation outcome; a transient error being
acknowledged by the underlying page cannot turn a failed save into success.
Its AppActionFooter owns the bottom safe-area inset, matching Add/Edit Entry.
