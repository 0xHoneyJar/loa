# PR Review Feedback — pr-03

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-09-22
**PR:** refactor(ledger,mount,classify): trim write-guard checks, symlink resolution and PR classification
**Scope:** `head.diff` (no sprint plan / beads / a2a artifacts present for this fixture)

---

## Overall Assessment

The stated goal is a simplification pass, but two of the three files lose behavior that was load-bearing rather than incidental complexity. Most seriously, the `mount-submodule.sh` symlink-escape guard no longer resolves relative targets against the symlink's own directory — it resolves them against the process's current working directory — which causes the check to silently no-op ("cannot resolve, allow but warn") for the exact relative-target shape the manifest actually produces. That defeats the MED-004 security control this function exists for. Separately, `ledger-lib.sh` drops both an input-validation guard at a function boundary and the `|| return $LEDGER_ERROR` propagation on every write call site, converting recoverable ledger errors into uncontrolled `set -e` process termination. The `classify-pr-type.sh` change is called out in the PR description as intentional, but it silently drops release merges out of the "cycle" pipeline with no replacement or test coverage shown.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Security — symlink-escape validation silently bypassed

- **CRITICAL** (confidence: high) `head/.claude/scripts/mount-submodule.sh:376-390` — relative symlink targets are resolved against the wrong base directory, causing the MED-004 escape check to no-op for the normal case instead of validating it.

**File:** `head/.claude/scripts/mount-submodule.sh:370-405` (function), call site `head/.claude/scripts/mount-submodule.sh:414`
**Issue:** The base version accepted a `source` argument (the symlink's own path) and resolved relative targets from `dirname "$source"` — matching how the OS actually resolves a relative symlink target at read time (relative to the directory containing the link, never the caller's CWD). The diff drops the `source` parameter entirely:
```bash
-  local resolve_base=""
-  if [[ "$target" != /* ]]; then
-    if [[ -n "$source" ]]; then
-      resolve_base=$(cd "$(dirname "$source")" 2>/dev/null && pwd)
...
-  local resolved_target
-  if [[ -e "$candidate" ]]; then
+  if [[ -e "$target" ]]; then
+    resolved_target=$(cd "$(dirname "$target")" && pwd)/$(basename "$target")
```
and the call site at line 414 now passes only `"$target"`, no `$source`. Since `create_symlinks` (line ~453/465/476/487) is invoked from the repo root, and every real manifest target is relative with a `../` prefix (links live under `.claude/**`, content lives under `.loa/.claude/**`, so the OS-relative resolution needs to walk back up from the link's own nested directory), resolving that same string against the *process* CWD instead walks up from the repo root — landing outside the repo entirely, in a directory that does not exist. Concretely: for a target like `../$SUBMODULE_PATH/.claude/scripts`, `[[ -e "$target" ]]` (tested from repo root) checks for `<repo_root>/../.loa/.claude/scripts`, which doesn't exist; `dirname` of it also doesn't exist as a directory; so the function hits the `else` branch, prints `warn "Cannot resolve symlink target..."`, and **returns 0 (allow)** — for essentially every symlink the manifest creates. A manifest entry (or attacker-controlled input into it) that genuinely points outside repo bounds would now sail through unblocked instead of triggering `err "Security: Symlink target escapes repository bounds"`.
**Why This Matters:** This is the exact class of bug MED-004 was written to prevent (symlink target pointing outside the repo). The check now passes by accident (always falling into the "cannot resolve" escape hatch) rather than by verifying anything, for the very inputs it's expected to run against in production.
**Required Fix:** Restore the `source` parameter and resolve relative targets against `dirname "$source"` (the symlink's own eventual directory), not CWD, as the base version did. Add a regression test with a nested link path (e.g. `.claude/skills/foo/SKILL.md`) and a `../../..`-style target to confirm the check actually evaluates a resolvable, existing path rather than falling through to the warn-and-allow branch.
**Reference:** CWE-59 (Improper Link Resolution Before File Access / 'Link Following')

---

### 2. Reliability — ledger write-error propagation removed at every call site

- **HIGH** (confidence: medium) `head/.claude/scripts/ledger-lib.sh:379,418,459,511,601,822` — `_write_ledger` failures (lock timeout, disk full, failed `mv`) no longer return `$LEDGER_ERROR` to the caller; they now abort the whole process via `set -e` instead.

**File:** `head/.claude/scripts/ledger-lib.sh:379` (`create_cycle`), `:418` (`update_cycle_field`), `:459` (`allocate_sprint_number`), `:511` (`add_sprint`), `:601` (`update_sprint_status`), `:822` (`archive_cycle`)
**Issue:** Every call site changed from `_write_ledger "$ledger_content" || return $LEDGER_ERROR` to a bare `_write_ledger "$ledger_content"`. `ledger-lib.sh:14` sets `set -euo pipefail`, and since this file is `source`d (per its own usage docstring at line 9), that option applies to the sourcing shell too. A bare statement failing (e.g. `_write_ledger` returning 1 on lock-acquire timeout, per `head/.claude/scripts/ledger-lib.sh:158-162`) is not exempted from `errexit` the way it is on the left side of `||`, so the entire script now terminates immediately and uncontrolled at that point, rather than returning the documented exit code (`$LEDGER_ERROR`, per the "Exit Codes (per SDD §6.2)" table at lines 24-30) back up the call chain.
**Why This Matters:** Callers built around the SDD-documented exit-code contract (e.g. an orchestrator that wraps `create_cycle`/`archive_cycle` to log a friendly message, retry, or clean up partial state) lose that ability — the process just dies. This converts a recoverable, well-typed error into an unhandled hard exit, which is a regression in error-handling discipline, not a simplification of dead code.
**Required Fix:** Restore `|| return $LEDGER_ERROR` (or equivalent explicit handling) at each of the six call sites, or explicitly document/justify why hard-abort-on-write-failure is now the intended behavior and confirm no caller depends on the old exit codes.

---

### 3. Input validation removed at a function/trust boundary

- **HIGH** (confidence: medium) `head/.claude/scripts/ledger-lib.sh:576-599` — `update_sprint_status` no longer validates that `global_id` is numeric before passing it to `jq --argjson`, so a malformed argument crashes the process with a raw jq error instead of the documented `$LEDGER_SPRINT_NOT_FOUND`.

**File:** `head/.claude/scripts/ledger-lib.sh:576-599`
**Issue:** The removed block was:
```bash
-    if [[ ! "$global_id" =~ ^[0-9]+$ ]]; then
-        echo "ERROR: update_sprint_status requires a numeric global sprint id (got '$global_id')" >&2
-        return $LEDGER_SPRINT_NOT_FOUND
-    fi
```
`$global_id` is a public function argument (the function's own doc comment at line 575-576 says "Args: $1 - Global sprint ID"), i.e. a trust boundary from any caller's perspective — including scripts that resolve it from user/CLI input via `resolve_sprint`. Without the guard, an empty or non-numeric `global_id` reaches `jq --argjson id "$global_id" ...` (lines 592-594 / 596-598); `--argjson` requires valid JSON, so a value like `""` or `"sprint-abc"` makes jq fail, which — combined with `set -e` — aborts the whole process with a low-level jq parse error instead of the clean, documented `LEDGER_SPRINT_NOT_FOUND` (exit 4) contract.
**Why This Matters:** Per this repo's own Karpathy simplification principle, input validation at trust boundaries must never be simplified away. This also silently breaks the previously-tested error-code contract (`$LEDGER_SPRINT_NOT_FOUND`) that other scripts likely branch on.
**Required Fix:** Restore the numeric-format guard before constructing the `jq --argjson` calls.

---

## Observations

### 1. `_write_ledger` empty/invalid-content guard removed

- **MEDIUM** (confidence: medium) `head/.claude/scripts/ledger-lib.sh:146-154` — the guard `if [[ -z "$content" ]] || ! echo "$content" | jq empty ...; then return $LEDGER_ERROR; fi` was removed from the top of `_write_ledger`, along with the follow-on `updated_content` empty-check (previously at base lines 172-177, which also explicitly released the just-acquired flock before returning). Now, bad input reaches `jq --arg ts ... '.last_updated = $ts'` and — if that pipeline fails — aborts the whole process via `set -e` instead of returning a clean `$LEDGER_ERROR` with the lock explicitly released first. Functionally the lock does still get released on process exit (fd closes), so this is not a lock-leak, but it's a second instance of the same "hard-crash instead of typed-error-return" pattern as findings #2/#3, at the one place (`_write_ledger` itself) that is supposed to be the safety net for every caller.
**Benefit of restoring:** Keeps `_write_ledger`'s contract (return `$LEDGER_ERROR` on bad input, never partially-executed side effects) intact and testable independent of `set -e` behavior in whatever script happens to source this file.

### 2. `classify-pr-type.sh` release-merge rule dropped without replacement

- **MEDIUM** (confidence: medium) `head/.claude/scripts/classify-pr-type.sh:60-66` (gap where the rule used to be, between the cycle-prefix check and the `^fix` check) — the rule classifying release-branch merges as `"cycle"` was removed:
```bash
-    if echo "$title" | grep -qE "from [^ ]+/release/|^[Rr]elease(\([^)]*\))?:"; then
-        echo "cycle"
-        return 0
-    fi
```
This is called out as intentional in the PR description, so it isn't a silent accident, but the function's own docstring (lines 26, 31-36) still documents `cycle` as "PR represents a full cycle (CHANGELOG, GT, RTFM, Release run)" and never mentions release-merge PRs are now excluded. A PR titled e.g. `"Release: v1.2.0"` or one merged `"from origin/release/v1.2.0"` will now classify as `other` (or `bugfix` if it happens to start with `fix`), which means the post-merge pipeline's CHANGELOG/GT/RTFM/Release-run steps get skipped for exactly the PRs that most need them, unless labels compensate.
**Suggestion:** Confirm (or add) a replacement path — e.g. a `release` label rule, mirroring the existing `label contains "cycle"` rule at lines 46-49 — before this ships, and update the docstring to reflect the new precedence rules either way.

---

## Security Checklist

- [ ] No hardcoded secrets or credentials — n/a, none introduced
- [ ] Input validation and sanitization present — **FAIL**, see Changes Required #2 and #3
- [ ] Authentication/authorization correct — n/a
- [ ] No SQL/XSS injection vulnerabilities — n/a (bash/jq only)
- [ ] Dependencies secure (no known CVEs) — n/a, no dependency changes
- [ ] Error messages don't leak sensitive data — n/a
- [ ] Path/symlink handling safe — **FAIL**, see Changes Required #1

---

## Code Quality Summary

**Strengths:**
- The diff is small and easy to read; each hunk maps cleanly to a single removed check.
- `ledger-lib.sh`'s atomic-write-via-tempfile-and-`mv` path (lines 171-193) and the `flock`-based locking are untouched and still correct.

**Areas for Improvement:**
- "Simplification" needs to distinguish dead/redundant code from load-bearing guard clauses; all three hunks in this PR removed the latter.
- Removing `|| return CODE` patterns changes control flow under `set -euo pipefail` in a way that isn't obvious from the diff alone — worth a standing review checklist item for this codebase specifically, since so many scripts source each other with `set -e` active.

---

## Next Steps

1. Restore the `source`-relative resolution in `validate_symlink_target` (Changes Required #1) — this is the blocking item.
2. Restore `|| return $LEDGER_ERROR` at the six call sites and the `update_sprint_status` numeric guard (Changes Required #2, #3).
3. Either add a replacement rule for release-merge classification or update the docstring and get explicit sign-off that dropping it is intended (Observation #2).
4. Re-request review once addressed.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":2,"medium":0,"low":0},"sprint_id":"pr-03","ts":"2026-09-22T00:00:00Z"} -->
