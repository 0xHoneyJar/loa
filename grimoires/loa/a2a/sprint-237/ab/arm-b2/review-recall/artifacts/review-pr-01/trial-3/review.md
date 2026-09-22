# PR Review: chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-09-22
**Scope:** `head.diff` — 3 files: `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/lib/invoke-diagnostics.sh`, `.claude/scripts/workflow-state.sh`

---

## Overall Assessment

This PR bills itself as a pure cleanup, but two of the three files change observable behavior, and one of those is a genuine functional regression that will crash `workflow-state.sh` under `set -euo pipefail` in the common "sprint.md exists, no `## Sprint` heading yet" state. The AWS-key redaction pattern is also narrowed from 7 documented AWS ID prefixes down to 1, dropping coverage for STS temporary credentials (`ASIA...`) — these are live, frequently-used secrets in CI/cloud contexts, not a cosmetic difference. The `block-destructive-bash.sh` regex simplification is more defensible (it removes a false-positive-suppression path rather than opening a bypass) but still changes behavior for a common git pattern (`-m "title" -m "body"`) without a corresponding test update in this diff.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functional regression — `get_total_sprints` can emit two lines, breaking every arithmetic consumer

- **HIGH** (confidence: high) `head/.claude/scripts/workflow-state.sh:72` — when `sprint.md` exists but contains zero `^## Sprint [0-9]` headings, `get_total_sprints` prints `"0\n0"` instead of `"0"`, and every caller that treats the result as an integer breaks under `set -euo pipefail`.

**File:** `head/.claude/scripts/workflow-state.sh:72`
**Issue:** The old code was:
```bash
local n
n=$(grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || true)
echo "${n:-0}"
```
The new code collapses this to:
```bash
grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
```
`grep -c` prints the match count to stdout **even when the count is 0**, and still exits with status `1` when there were zero matches (GNU/BSD grep both do this). So for a `sprint.md` with no `## Sprint N` heading yet:
1. `grep -c ...` prints `0` to stdout, then exits 1.
2. Because the exit status is 1, the `||` branch also fires, printing a second `0`.
3. Combined output captured by any caller via `$(get_total_sprints)` is the two-line string `"0\n0"`.

This function is consumed as an integer everywhere in this same file:
- `head/.claude/scripts/workflow-state.sh:86-88` — `total=$(get_total_sprints)` feeds `for ((i = 1; i <= total; i++))`, which is a `((...))` arithmetic context. A `"0\n0"` value there is a bash syntax error ("value too great for base" / arithmetic syntax error), and with `set -euo pipefail` (line 16) this exits the whole script non-zero.
- `head/.claude/scripts/workflow-state.sh:151` — `[[ "${total_sprints}" -ge "${total_sprints}" ]]`-style integer test on a multi-line string raises `integer expression expected`.
- `head/.claude/scripts/workflow-state.sh:158,376` — `seq 1 "${total_sprints}"` with a two-line argument.
- `head/.claude/scripts/workflow-state.sh:403` — `"total_sprints": ${total_sprints},` embedded directly into JSON output, producing invalid JSON (`"total_sprints": 0\n0,`).

**Why This Matters:** This is not a rare edge case — it's the state of every project immediately after `/sprint-plan` scaffolds `sprint.md` before the first `## Sprint N` section is written, or any sprint.md that uses a different heading level/format. `workflow-state.sh` backs `/loa` (status) and is read on every session-recovery path per `CLAUDE.loa.md`'s Run Mode Recovery section. Crashing it here breaks the golden-path status command precisely when a user most needs it (early in a cycle).
**Required Fix:** Keep the original two-step form (capture into a variable, then print with a default), e.g.:
```bash
get_total_sprints() {
    if [[ -f "${SPRINT_FILE}" ]]; then
        local n
        n=$(grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null) || true
        echo "${n:-0}"
    else
        echo "0"
    fi
}
```
or equivalent — the key requirement is that exactly one line is ever echoed, regardless of `grep`'s exit status.
**Reference:** GNU grep manual, `-c`/`--count`: "exit status ... is 1 if no lines were selected" while `-c` output is still the (zero) count.

### 2. Security regression — AWS credential redaction narrowed from 7 ID prefixes to 1, dropping STS/session-token coverage

- **HIGH** (confidence: high) `head/.claude/scripts/lib/invoke-diagnostics.sh:50` — `redact_secrets` no longer redacts `ASIA*` (STS temporary access keys), `AROA*` (role IDs), `AGPA*` (group IDs), `AIPA*` (instance-profile IDs), `ANPA*`/`ANVA*` (managed-policy IDs), leaving these secret-shaped values to flow into the diagnostic log unredacted.

**File:** `head/.claude/scripts/lib/invoke-diagnostics.sh:50`
**Issue:** Base pattern:
```bash
-e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
```
New pattern:
```bash
-e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
```
`ASIA` in particular prefixes AWS STS temporary/session access-key IDs — exactly the credential type most likely to show up in CI/automation logs (assumed-role sessions, OIDC-federated credentials), and it is paired with a secret access key + session token that is just as sensitive as a long-term `AKIA` key. Dropping it from the redaction set is a real reduction in the security posture of this diagnostics helper, not a simplification.

The PR's own comment update compounds this: the function docstring at `head/.claude/scripts/lib/invoke-diagnostics.sh:26,37` now reads "Expanded patterns: ... AKIA* (AWS)..." / "AKIA* — AWS IAM access key IDs" — describing the change as an *expansion* when it is actually a *narrowing* from 7 prefixes to 1. A future maintainer reading only the comment (not the diff) would have no signal that STS-key redaction was ever removed.
**Why This Matters:** `redact_secrets` exists specifically to keep model-invoke diagnostic logs (written with `chmod 600` but still plaintext on disk, per `setup_invoke_log`) from leaking credentials. Silently dropping 6 of 7 documented AWS ID-prefix shapes reopens exactly the leak this helper was built to close.
**Required Fix:** Restore the full alternation (`AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA`) unless there is a documented reason (linked issue/decision) that only `AKIA` needs coverage here — if so, that reasoning belongs in the comment, and the docstring must say "narrowed", not "expanded".
**Reference:** CWE-532 (Insertion of Sensitive Information into Log File); AWS docs on IAM unique identifier prefixes.

---

## Observations

### 1. `block-destructive-bash.sh` carrier regex: multi-flag redaction silently drops to single-flag

- **MEDIUM** (confidence: high) `head/.claude/hooks/safety/block-destructive-bash.sh:210-212` — removing `'"` from the carrier prefix's negated class, combined with deleting the `_bdb_re_tail` loop (base lines 214, 236-248), means only the **last** `-m`/`-d`/`--body`/`--title` value in a multi-flag command gets content-gated and scrubbed; earlier values pass through the "prefix" span unredacted.

**File:** `head/.claude/hooks/safety/block-destructive-bash.sh:210-212`
**Suggestion:** For `git commit -m "Fixes: rm -rf bug in docs" -m "See issue #123"` (a very common two-`-m` commit-message convention), the greedy `[^;&|]*` prefix now consumes the entire first `-m "Fixes: rm -rf bug in docs"` segment as unmatched "prefix" text (since quotes no longer break it), leaving that literal `rm -rf` substring in `_cmd_match` unredacted. Only the second/last `-m` value is captured as `val` and content-gated. Downstream destructive-pattern matching therefore still sees `rm -rf` in what should have been a scrubbed, benign commit message, which risks a **false-positive block** of a legitimate multi-paragraph commit.
This is not a bypass — it fails in the safe (over-block) direction, consistent with the file's documented fail-safe philosophy ("empty scrub … fall back to RAW (stricter matching)") — but it is a behavior change from the base file that isn't mentioned in the PR description ("simplify … regexes" undersells "multi-flag messages are no longer redacted"), and there's no test in this diff demonstrating the new single-flag-only behavior is intended.
**Benefit:** Either restore the tail loop (if multi-flag commit messages are a supported case) or explicitly document in the header comment that only the last flag occurrence is now content-gated, so a future contributor doesn't reintroduce the loop believing it was an accidental deletion.

### 2. `Bearer` redaction pattern drops `=` from the allowed value charset

- **LOW** (confidence: medium) `head/.claude/scripts/lib/invoke-diagnostics.sh:48` — `[A-Za-z0-9=._-]+` → `[A-Za-z0-9._-]+` means a standard (non-URL-safe) base64 Bearer token with `=` padding stops matching one character early, leaving the trailing `=`/`==` in the output (e.g. `Bearer ***REDACTED***==`).
**File:** `head/.claude/scripts/lib/invoke-diagnostics.sh:48`
**Suggestion:** The leaked characters are only base64 padding, not secret content, so this isn't a disclosure risk — but it's an unexplained, undocumented narrowing bundled into a "cleanup" commit alongside the AWS pattern change. Worth reverting alongside Finding 2 above, or calling out explicitly if intentional.
**Benefit:** Keeps the redaction pattern's actual character coverage matching its own docstring, and avoids stacking multiple silent regex narrowings in one "trim to documented shape" commit.

---

## Security Checklist

- [ ] No hardcoded secrets or credentials — N/A, no secrets added
- [x] Input validation and sanitization present — not applicable to this diff
- [x] Authentication/authorization correct — not applicable to this diff
- [x] No SQL/XSS injection vulnerabilities — not applicable to this diff
- [x] Dependencies secure (no known CVEs) — no dependency changes
- [ ] Error messages don't leak sensitive data — **FAILS**: see Finding 2 (AWS STS/role/group/policy ID prefixes no longer redacted from diagnostic logs)

---

## Next Steps

1. Fix `get_total_sprints` to always emit exactly one line (Finding 1).
2. Restore full AWS ID-prefix coverage in `redact_secrets`, or justify and correctly document the narrowing (Finding 2).
3. Either restore `_bdb_re_tail` or explicitly document/test the new single-flag-only carrier-scrub behavior (Observation 1).
4. Resubmit for review.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":1,"low":1},"excluded":0,"sprint_id":"pr-review","ts":"2026-09-22T00:00:00Z"} -->
