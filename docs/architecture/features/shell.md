# shell

Navigation shell: bottom nav, FAB ownership stack, settings end-drawer.

- **State:** no BLoC — uses `AppShellScope` (an `InheritedWidget`) so descendants can open the settings drawer and register a FAB.
- **Pages:** `AppShell`, `FabOwnershipStack`, `PlaceholderPage`. **Widgets:** `AppBottomNav` (5 slots + badge counts), `SettingsDrawer`.
- **Layering:** presentation only — no data/domain (it is pure navigation chrome).
- **FAB ownership:** any page that shows a FAB registers it via `FabRegistrar` (pass `fab: null` to suppress a leaked FAB from a covered page). The shell renders the registered FAB in one place.

**Cross-feature deps:** hosts all tab features (vault, agents, notifications). Settings drawer routes to `settings` and `api_keys`. Descendants open the drawer via `AppShellScope.of(context)` — never mount a duplicate `endDrawer`.
