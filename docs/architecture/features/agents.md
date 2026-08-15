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
- **Exports:** `AgentAvatar` is reused by `grants` and `notifications`; `AgentStatusBadge` shares its shape with `api_keys`' `ApiKeyStatusBadge` (extract `StatusPill`).

**Cross-feature deps:** consumed by `grants`, `notifications` (which reuse `AgentAvatar` + the approve/deactivate sheets).

**⚠ Architecture smells:** `agent_detail_body.dart:855` defines `_DetailRow`, duplicated in `api_keys` → extract `LabelValueRow`. `_AgentsEmpty` duplicates the empty-card pattern → extract `ListEmptyCard`. AppBar title duplicates `AppBarTitle`. See the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md).
