---
name: secret-masking-crossbrowser
description: SecretInput masking must be cross-browser via bundled text-security-disc font, not -webkit-text-security alone
metadata:
  type: feedback
---

In the React web panel, `SecretInput` masks secrets WITHOUT `type="password"` (so the
browser password manager never offers to save vault credentials). Masking must work in
EVERY browser including Firefox.

**Rule:** `.secret-mask` (in `src/index.css`) sets `font-family: "text-security-disc"`
(bundled woff2 in `src/assets/fonts/`, no node_modules runtime dep) as the primary,
cross-browser mechanism, with `-webkit-text-security: disc` only as a Chromium hardening.

**Why:** `-webkit-text-security` is Chromium-only and `text-security` is non-standard —
Firefox ignored both and rendered vault secrets in PLAINTEXT (zero-knowledge UX violation,
flagged Critical in PR #24 review). The disc-glyph font renders every char as • everywhere.

**How to apply:** Never rely on `-webkit-text-security` alone for masking secrets. Keep
`autoComplete="off"` + `data-1p-ignore`/`data-lpignore`/`data-bwignore` hints. Reveal toggle
just removes the `secret-mask` class so the normal/mono font returns. Do NOT add a fallback
font in the masked family (a real font would briefly show plaintext during font load).
