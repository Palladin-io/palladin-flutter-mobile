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

Post the review as a GitHub PR comment:

```
gh pr comment $ARGUMENTS --body "REVIEW_BODY_HERE"
```

Use this Markdown structure:

```markdown
## 🔍 PR Review — Flutter Mobile

### Summary
2–3 sentences on what the PR does and your overall verdict.

### 🚨 Critical
*(must fix before merge — security issues, broken BLoC contracts, data persistence of sensitive data)*
- `lib/path/to/file.dart:42` — explanation

### ⚠️ Warnings
*(should fix — hardcoded strings, inline colors, wrong lifecycle usage, missing disposal)*
- `lib/path/to/file.dart:17` — explanation

### 💡 Suggestions
*(non-blocking — clarity improvements, minor DRY, small convention deviations)*
- `lib/path/to/file.dart:8` — explanation

### ✅ Highlights
*(good patterns worth reinforcing)*
- what was done well
```

Omit any section that has no findings. Do not comment on formatting or import ordering.
