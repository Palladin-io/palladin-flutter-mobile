---
name: pr-review
description: Reviews a pull request in the Claw Vault Flutter mobile app for BLoC pattern compliance, visual consistency, i18n, security, and mobile best practices. Posts findings as a structured GitHub PR comment.
argument-hint: <pr-number>
disable-model-invocation: true
allowed-tools: Read Grep Glob Bash(gh pr view *) Bash(gh pr diff *) Bash(gh pr comment *) Bash(git log *)
effort: high
---

# PR Review — Claw Vault Flutter Mobile

## Pull Request Context

**Metadata:**
!`gh pr view $ARGUMENTS --json number,title,body,author,additions,deletions,changedFiles,baseRefName,headRefName 2>/dev/null || echo "PR metadata unavailable"`

**Changed files:**
!`gh pr diff $ARGUMENTS --name-only 2>/dev/null || echo "No changed files"`

**Diff (first 50 000 chars):**
!`gh pr diff $ARGUMENTS 2>/dev/null | head -c 50000`

---

## How to Conduct the Review

1. Read `CLAUDE.md` — it is the source of truth for all project conventions.
2. Load [criteria.md](criteria.md) — detailed review checklist. Read it fully before starting.
3. For each changed Dart file: use `Read`, `Grep`, `Glob` to explore related files beyond the diff (e.g. ARB files when new strings are added, `app_colors.dart` when colors are used, BLoC state when widget logic changes).
4. Cite **file path and line number** for every issue.
5. One clear sentence per finding.

## Review Focus Areas

Cover all sections from `criteria.md`:
- BLoC pattern: Cubit vs Bloc, state immutability, no logic in widgets
- Visual consistency: shared components, AppColors, dark theme
- i18n: ARB files, no hardcoded strings
- Security: logs, secure storage, key handling
- Analytics: format, UI-only events
- Mobile best practices: widget lifecycle, navigation, DI
- Code quality: DRY, SRP, OCP, Clean Code
- Tests: widget tests, unit tests, coverage
- Over-engineering check

## Output

Submit a proper GitHub pull request review — inline file comments + a final verdict. Do NOT use `gh pr comment`.

### Step 1 — determine the verdict

- `REQUEST_CHANGES` — any Critical or Warning findings
- `APPROVE` — only Suggestions / Highlights, or a clean PR
- `COMMENT` — only when genuinely ambiguous (rare)

### Step 2 — build `/tmp/review.json`

```json
{
  "body": "## 🔍 PR Review — Flutter Mobile\n\n### Summary\n2–3 sentence verdict.\n\n### ✅ Highlights\n- good pattern noted\n\n*(cross-cutting findings that don't map to a single diff line go here too)*",
  "event": "REQUEST_CHANGES",
  "comments": [
    {
      "path": "lib/features/auth/presentation/pages/login_page.dart",
      "line": 42,
      "side": "RIGHT",
      "body": "🚨 **Critical** — one-sentence explanation."
    },
    {
      "path": "lib/features/auth/presentation/pages/login_page.dart",
      "line": 17,
      "side": "RIGHT",
      "body": "⚠️ **Warning** — one-sentence explanation."
    }
  ]
}
```

### Step 3 — submit

```bash
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
gh api "repos/${REPO}/pulls/$ARGUMENTS/reviews" --method POST --input /tmp/review.json
```

### Rules

- **Inline comments** — only on lines present in the diff (`/tmp/pr_diff.patch`). Findings in unchanged files go in `body`.
- **`line`** — file line number (not diff position). **`side`** — always `"RIGHT"` for added/changed lines.
- **Severity prefix** — start each inline `body` with `🚨 Critical —`, `⚠️ Warning —`, or `💡 Suggestion —`.
- **`body`** — overall Summary + Highlights + any cross-cutting findings (e.g. both ARB files missing a key, inline color used in multiple files).
- Omit `"comments"` key entirely if there are no file-level findings.
