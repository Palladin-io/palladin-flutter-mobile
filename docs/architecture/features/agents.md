# agents

Agent lifecycle: approve pending agents, deactivate, reactivate, edit.

- **Cubit:** `AgentsCubit`.
- **Pages:** `AgentsPage` (responsive split view at a 720px breakpoint), `AgentDetailPage`.
- **Widgets:** `AgentCard`, `AgentAvatar`, `AgentStatusBadge`, `AgentDetailBody`, `AgentEditForm`, `ApproveAgentSheet`, `DeactivateAgentSheet`.
- **Layering:** full data / domain / presentation split.
- **Exports:** `AgentAvatar` is reused by `grants` and `notifications`; `AgentStatusBadge` shares its shape with `api_keys`' `ApiKeyStatusBadge` (extract `StatusPill`).

**Cross-feature deps:** consumed by `grants`, `notifications` (which reuse `AgentAvatar` + the approve/deactivate sheets).

**⚠ Architecture smells:** `agent_detail_body.dart:855` defines `_DetailRow`, duplicated in `api_keys` → extract `LabelValueRow`. `_AgentsEmpty` duplicates the empty-card pattern → extract `ListEmptyCard`. AppBar title duplicates `AppBarTitle`. See [../widget-catalog.md](../widget-catalog.md).
