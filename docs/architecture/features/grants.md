# grants

Org-wide grant history feed + per-context grants tab (vault / entry / agent).

- **Cubit:** `OrgGrantsCubit`.
- **Pages:** none standalone — `ContextGrantsTab` is embedded inside vault/entry/agent detail screens.
- **Widgets:** `OrgGrantCard`, `ContextGrantsTab`, `RevokeGrantSheet`, and `GrantDetailRow` (exported, also used by `notifications`).
- **Layering:** full data / domain / presentation split. Holds the grant domain entities consumed by `approval`.

**Cross-feature deps:** `agents` (`AgentAvatar`), `approval` (consumes grant entities). Embedded by `vault`.

**⚠ Architecture smell:** `RevokeGrantSheet` inlines the drag handle → extract `SheetDragHandle`. `GrantDetailRow` is a 76px-label variant of the duplicated label/value row pattern — fold into `LabelValueRow` if generalizing. See the Shared Widget Catalog in [../../../CLAUDE.md](../../../CLAUDE.md).
