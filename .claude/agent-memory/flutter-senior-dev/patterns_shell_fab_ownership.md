---
name: patterns-shell-fab-ownership
description: How the shell-level FAB is owned/shown across pages — ownership stack, FabRegistrar identity, every shell page must register
metadata:
  type: project
---

Shell-level FAB (single `FloatingActionButton` on `AppShell`'s Scaffold, pinned across route transitions) is managed by an **ownership stack**, not a single slot.

**Why:** all authenticated pages live in one `ShellRoute` → `AppShell`. A single shared `_fab` slot leaked: the previously-visited page's FAB stayed when the next page declared a different/no FAB (e.g. API Keys showed "Add Entry"). Root cause was no deterministic owner — `dispose` never cleared, and pages without a registrar never overwrote.

**How it works:**
- `lib/features/shell/presentation/pages/fab_ownership_stack.dart` — pure `FabOwnershipStack` (set/clear/current), unit-tested.
- `AppShell` exposes via `AppShellScope`: `setFab(Widget? fab, Object owner)` and `clearFab(Object owner)`. Shell renders the stack's top entry.
- `FabRegistrar` (`lib/core/widgets/fab_registrar.dart`) is the only thing pages use. Its `State` is the owner token. On mount/update → `setFab(fab, this)` (post-frame). On dispose → `clearFab(this)` via `AppShellScope.maybeOf` (non-dependency lookup, safe in dispose). Push wins; pop resurfaces the covered page's FAB automatically — no re-assert, no null-flash.

**How to apply:**
- EVERY page under the ShellRoute MUST mount a `FabRegistrar` — even pages with no FAB, passing `fab: null` (suppresses a covered page's FAB). For pages with their own Scaffold and no FAB, put `floatingActionButton: const FabRegistrar(fab: null)` on that Scaffold (renders 0×0).
- Cache the FAB widget instance across rebuilds (`_cachedFab ??= ...`) so `FabRegistrar.didUpdateWidget` doesn't re-register every build.
- Do NOT manually call `setFab` to "restore" a FAB after returning from a pushed page — the stack handles it.
- `add_entry`/`entry_detail` are pushed on the ROOT navigator (above shell) so they're not shell children and need no registrar.
