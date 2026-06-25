---
name: S3 icon cache busting (mobile)
description: How to handle re-uploads of S3 icons in Flutter when the public URL stays the same across uploads
metadata:
  type: feedback
---

S3 reuses the same object key on every icon re-upload (e.g.
`agent-icons/{agentId}/icon.png`), so the public URL is byte-for-byte
identical across uploads. Without cache busting Flutter serves the stale
image from `imageCache`, and any `_isDirty` check that compares URL
strings returns `false` — Save stays disabled.

**Why:** the agent re-upload bug — user couldn't update a custom agent
icon because the new URL matched the saved one, dirty check failed, and
the image cache served the old bytes.

**How to apply:**

1. **At upload site** (form's `onPickCustom` callback): after the upload
   service returns the public URL, append `?v=${DateTime.now().millisecondsSinceEpoch}`
   before storing in form state. This makes every upload produce a
   unique string → dirty check flips → Save button enables. Also evict
   the canonical (`NetworkImage(publicUrl)`) from `imageCache` so
   already-rendered avatars refetch.

2. **On save**: strip the `?v=` query before sending to the API (the
   server should store the canonical URL only — otherwise re-uploads
   chain query strings). Pass the `?v=` URL as `iconKeyDisplay` so the
   cubit emits an agent state whose avatar URL forces a refetch.

3. **In the cubit**: when `iconKeyDisplay` differs from the fresh agent
   returned by `getAgent`, override `iconKey` with the display URL in
   the emitted state. Also evict both canonical and `?v=` variants from
   `PaintingBinding.instance.imageCache` so list / detail avatars
   refresh. **Wrap eviction in try/catch** — `PaintingBinding.instance`
   throws in unit tests that don't call `WidgetsFlutterBinding.ensureInitialized()`.

4. **`updateAgent` uses `getAgent`, not `listAgents`** — the list
   endpoint may omit detail fields like `iconKey`, causing avatars to
   revert after save. After a successful PATCH, fetch only the one
   touched agent via `getAgent(agentId)` and patch it into the loaded
   list.

5. **For backends without `UpdatedAt`** (Agents domain, as of 2026-05):
   use a client-side `DateTime.now().millisecondsSinceEpoch` rather
   than a server-issued timestamp. For backends that do expose it
   (Vault entries), prefer `entity.updatedAt.millisecondsSinceEpoch` —
   see `vault_entries_tab.dart` `_EntryIconWidget`.

Reference: [[reference_s3_icon_patterns]] for the server-side bucket
config and presigned-PUT headers.
