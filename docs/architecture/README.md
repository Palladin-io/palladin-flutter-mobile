# Mobile Architecture Reference

Per-feature and shared-widget reference for the Palladin Flutter app. These docs are the source of truth for **what already exists** so you don't rebuild it.

## Reuse-first philosophy

**Before building any widget, check the catalog.** If a matching shared widget exists, use it. If a pattern appears **2+ times** anywhere in the codebase, extract it to `lib/core/widgets/` and use it everywhere — duplicating an input/button/card/sheet style inline is a bug, not a style choice.

Order of operations for any new UI:
1. Read the **Shared Widget Catalog** section in [`../../CLAUDE.md`](../../CLAUDE.md) — does a shared widget already cover this?
2. Read the feature doc under [`features/`](features/) for the feature you're touching.
3. Only after both: build. If you're about to copy a `Container`/`Column`/sheet block you've seen elsewhere, stop and extract instead.

**Never inline** `Color(0x..)` (use `AppColors.*`) or bare spacing numbers (use `AppSpacing.*`). Never reinvent a skeleton, a sheet drag handle, or a status pill — see the catalog's "Widgets to extract" subsection.

## Docs index

The **shared widget catalog lives in [`../../CLAUDE.md`](../../CLAUDE.md)** (section "Shared Widget Catalog") so it is always loaded — it covers every `lib/core/widgets/` widget, the cross-feature widgets, the widgets still to extract, and the reuse rules. The per-feature docs are here:

| Doc | Covers |
|-----|--------|
| [features/auth.md](features/auth.md) | OAuth login |
| [features/unlock.md](features/unlock.md) | Master-password + biometric unlock |
| [features/onboarding.md](features/onboarding.md) | Account-setup wizard (master password, mnemonic) |
| [features/recovery.md](features/recovery.md) | Mnemonic-based account recovery |
| [features/shell.md](features/shell.md) | Navigation shell, bottom nav, FAB ownership, settings drawer |
| [features/vault.md](features/vault.md) | Vaults and entries (list, detail, create, edit) |
| [features/agents.md](features/agents.md) | Agent lifecycle (approve, deactivate, reactivate) |
| [features/approval.md](features/approval.md) | Zero-knowledge grant approval/denial sheets |
| [features/grants.md](features/grants.md) | Org grant history feed + per-context grants tab |
| [features/notifications.md](features/notifications.md) | Inbox, preferences, FCM/SignalR |
| [features/audit.md](features/audit.md) | Audit log viewer (global page + embedded tabs) |
| [features/settings.md](features/settings.md) | Org/user settings (hosts the `ApiKey` domain) |
| [features/api_keys.md](features/api_keys.md) | API key list/detail/generate/revoke |

**Rule: before working on a feature, read `docs/architecture/features/<feature>.md` first.** It tells you the cubit/bloc, the existing pages and widgets, the layering, and the cross-feature dependencies — so you extend rather than duplicate.
