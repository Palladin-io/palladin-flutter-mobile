# shell

Navigation shell: bottom nav, FAB ownership stack, settings end-drawer.

- **State:** no BLoC — uses `AppShellScope` (an `InheritedWidget`) so descendants can open the settings drawer and register a FAB.
- **Pages:** `AppShell`, `FabOwnershipStack`, `PlaceholderPage`. **Widgets:** `AppBottomNav` (5 slots + badge counts), `SettingsDrawer`.
- **Layering:** presentation only — no data/domain (it is pure navigation chrome).
- **FAB ownership:** any page that shows a FAB registers it via `FabRegistrar` (pass `fab: null` to suppress a leaked FAB from a covered page). The shell renders the registered FAB in one place.

The scrollable settings drawer groups destinations under Organization and
Account. It derives visibility from the authenticated permission mask: Team and
General remain visible to every member, while Permissions, API Keys and Audit
Logs are omitted when the caller lacks the corresponding read permission.
Billing is an explicit placeholder. Security consolidates password and TOTP;
Data Import links to the existing local import flow. Session actions (lock and
sign out) remain separate from settings destinations. Drawer navigation uses
the centralized `AppRoutes` paths; route guards independently enforce the same
authorization rules.

**Cross-feature deps:** hosts all tab features (vault, agents, notifications).
Settings drawer routes to settings, API keys, and audit. Descendants open the
drawer via `AppShellScope.of(context)` — never mount a duplicate `endDrawer`.
