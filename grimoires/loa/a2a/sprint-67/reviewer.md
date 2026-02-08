# Sprint 4 (Global: sprint-67) — Security Hardening (GPT 5.2 Findings)

## Implementation Report

| Task | Title | Status | GPT Review | Files Changed |
|------|-------|--------|------------|---------------|
| 4.1 | Harden endpoint allowlist | DONE | Source: GPT 5.2 Finding #1 | github-cli.ts |
| 4.2 | Eliminate information leakage | DONE | Source: GPT 5.2 Findings #3,#4,#6,#7,#8,#9,#10 | github-cli.ts, anthropic.ts, reviewer.ts |
| 4.3 | Fix double marker insertion | DONE | Source: GPT 5.2 Finding #7 (first run) | reviewer.ts |
| 4.4 | Add repo filtering + network retry | DONE | Source: GPT 5.2 Findings #5,#8 | reviewer.ts, anthropic.ts |

## Source

All findings from GPT 5.2 cross-model code review (PR #248, Comment #6).
Full findings: `/tmp/gpt-review-590/findings-gpt52-full.json`

## Changes

### Task 4.1: Harden endpoint allowlist (`github-cli.ts`)

**Problem**: `assertAllowedArgs()` used `args.find((a) => a.startsWith("/"))` which matched ANY argument starting with `/`, not just the endpoint at `args[1]`. This allowed potential allowlist bypass via argument reordering.

**Fix**:
- Require endpoint at `args[1]` position (not arbitrary arg search)
- Add `FORBIDDEN_FLAGS` set blocking `--hostname`, `-H`/`--header`, `--method`, `-F`/`--field`, `--input`
- Block combined flag forms (`--hostname=evil`)
- Restrict `-X` to only `POST` method
- Require exactly 2 args for `auth status` command

**Lines changed**: 30-85 (replaced entire function + added constant)

### Task 4.2: Eliminate information leakage

**Problem**: Multiple error paths included raw stderr, response bodies, API key prefixes, or sanitizer pattern details that could leak sensitive information.

**Fixes by file**:

**github-cli.ts**:
- `gh()` error (line 112-114): Use exit code only, no stderr content
- `parseJson()` error (line 122-123): Remove `raw.slice(0, 200)` from error message

**anthropic.ts**:
- Constructor (line 21): Remove `sk-ant-...` prefix example from error
- Constructor (line 23-24): Add model validation (empty model guard)
- Retry error (line 71-72): Remove `response.text()` from error
- Non-OK error (line 77-78): Remove `response.text()` from error

**reviewer.ts**:
- Sanitizer strict log (line 181): Log `redactions` count instead of `patterns` content
- Sanitizer warn log (line 200): Log `redactions` count instead of `patterns` content
- Error catch log (line 265-273): Log `code`/`category`/`source` instead of raw `message`

### Task 4.3: Fix double marker insertion

**Problem**: `reviewer.ts` line 191 appended `<!-- marker: sha -->` to the review body, then `postReview()` in `github-cli.ts` line 214 appended it again. This created double markers that could break `hasExistingReview()` detection.

**Fix**: Removed marker appending from `reviewer.ts` (line 204-205). The poster adapter (`github-cli.ts`) is the single owner of marker injection since it also implements `hasExistingReview()`.

### Task 4.4: Inaccessible repo filtering + network retry

**reviewer.ts** — Repo filtering:
- Preflight loop now builds `accessibleRepos` Set (line 76-87)
- Early exit if no repos accessible (line 89-92)
- Items for inaccessible repos skipped with `repo_inaccessible` reason (line 108-113)

**reviewer.ts** — Reviewed count fix:
- `buildSummary()` now counts only `r.posted === true` (line 312)
- Previously counted non-skipped, non-error items which inflated count during dry-run

**anthropic.ts** — Network retry:
- Catch block now retries on `TypeError` (fetch network errors) and common transient errors: `ECONNRESET`, `ENOTFOUND`, `EAI_AGAIN`, `ETIMEDOUT` (line 106-110)
- Previously only retried on `AbortError` (timeout), all other errors were rethrown immediately

## Review Feedback Addressed

### Issue 1: postReview() broken by allowlist hardening (CRITICAL)

**Source**: `engineer-feedback.md` — review caught that `postReview()` placed `-X` at `args[1]` instead of the endpoint, causing `assertAllowedArgs()` to throw on every review post.

**Fix**: Reordered `postReview()` args from `["api", "-X", "POST", endpoint, ...]` to `["api", endpoint, "-X", "POST", ...]` so the endpoint is at `args[1]` where the hardened allowlist expects it.

**Line**: `github-cli.ts:257-268`

## Build Verification

- TypeScript compilation: PASS (zero errors, post-feedback fix)
- All source changes in `.claude/skills/bridgebuilder-review/resources/`
- Compiled output in `.claude/skills/bridgebuilder-review/dist/`

## Files Modified

| File | Lines Changed | Type |
|------|---------------|------|
| `.claude/skills/bridgebuilder-review/resources/adapters/github-cli.ts` | +52/-16 | Security hardening |
| `.claude/skills/bridgebuilder-review/resources/adapters/anthropic.ts` | +14/-7 | Security hardening |
| `.claude/skills/bridgebuilder-review/resources/core/reviewer.ts` | +19/-10 | Bug fix + security |
| `grimoires/loa/sprint.md` | +67 | Sprint plan update |
| `grimoires/loa/ledger.json` | +6 | Sprint registration |
