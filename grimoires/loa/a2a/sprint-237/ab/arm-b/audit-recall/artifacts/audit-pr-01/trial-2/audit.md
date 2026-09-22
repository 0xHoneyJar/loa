# Security Audit — PR: chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting

**Scope:** `head.diff` touching `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/lib/invoke-diagnostics.sh`, `.claude/scripts/workflow-state.sh`.
**Method:** Full-file read of `base/` and `head/` versions of all three files; regex behavior traced by hand (no execution harness available in this workspace — no bats/test files were included in the snapshot).

---

## Findings

### HIGH — AWS access-key redaction narrowed to a single prefix, dropping STS/temporary credential coverage

**File:** `head/.claude/scripts/lib/invoke-diagnostics.sh:50`

```sed
-    -e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
+    -e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
```

`redact_secrets()` is the sole scrubber standing between raw model-invoke stderr/stdout and the diagnostic log files this library creates (`setup_invoke_log`, `log_invoke_failure`) — see the file's own header, `head/.claude/scripts/lib/invoke-diagnostics.sh:2` ("Secure error diagnostics"). The PR collapses the AWS access-key-ID alternation from seven documented prefixes down to `AKIA` only. Of the dropped prefixes, **`ASIA`** is the standard prefix for AWS STS temporary/session access-key IDs — exactly the credential shape issued to Lambda executions, assumed roles, and CI/CD OIDC federation, all environments where this diagnostics library is likely to run. A model-invoke failure whose stderr/output contains an `ASIA...` access key (e.g., an SDK error message echoing its own credentials, or a leaked env-var dump) will now be written to the temp log **unredacted**. The PR description's framing — "trimmed back to the documented AWS access-key shape" — is not accurate: AWS documents `ASIA` as an access-key-ID prefix on equal footing with `AKIA` (https://docs.aws.amazon.com/IAM/latest/UserGuide/reference-arns-syntax.html and the well-known AWS prefix table used across leak-detection tooling, e.g. GitHub's own secret scanning patterns, TruffleHog, gitleaks). This is a straightforward reduction of a security control (secret redaction) with no accompanying justification for why STS session keys are out of scope, and no test evidence was found accompanying the change (no test files are part of this PR's touched-file set).

**Failure scenario:** A model provider call fails with an error body containing the caller's temporary AWS credentials (`ASIA...`, 16 trailing alphanumerics) — e.g., a misconfigured Bedrock/Anthropic-via-AWS-Bedrock invocation, or an SDK that includes X-Amz-Security-Token debug output. `setup_invoke_log` writes this via `2>> "$INVOKE_LOG"` (per the module's own usage docstring at `head/.claude/scripts/lib/invoke-diagnostics.sh:15`) and `log_invoke_failure` surfaces it; `redact_secrets` is the only filter applied before the log is treated as safe to reference/attach. The session token now survives redaction and is written in the clear to a file this module itself describes as needing "chmod 600" hygiene (`head/.claude/scripts/lib/invoke-diagnostics.sh:6`) — i.e., the code still treats the log as sensitive enough to lock down at the filesystem layer, while simultaneously weakening the content-level redaction that runs before it.

**Remediation:** Restore the full alternation (`AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA`), or at minimum restore `AKIA|ASIA` (the two prefixes that denote actual *access keys*, long-term and temporary respectively — a defensible narrowing would drop the four resource-ID prefixes that aren't credentials, but not `ASIA`).

---

### MEDIUM — `workflow-state.sh` sprint-count restoration can emit a two-line result, corrupting a downstream arithmetic context

**File:** `head/.claude/scripts/workflow-state.sh:72`

```bash
get_total_sprints() {
    if [[ -f "${SPRINT_FILE}" ]]; then
        grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}
```

`grep -c PATTERN FILE` prints the match count to stdout **regardless of whether any lines matched**, but exits with status `1` when the count is zero (exit `0` only when count > 0). When `SPRINT_FILE` exists but contains zero `## Sprint N` headings, this line both (a) prints `0` from `grep -c` itself, and (b) triggers the `||` fallback because grep's exit status is `1`, printing a **second** `0` from `echo "0"`. The function's output becomes `"0\n0"` instead of `"0"`.

This function feeds directly into an arithmetic context at `head/.claude/scripts/workflow-state.sh:86-88`:

```bash
    total=$(get_total_sprints)
    for ((i = 1; i <= total; i++)); do
```

A two-line value substituted into `(( i <= total ))` is not valid bash arithmetic syntax. Combined with `set -euo pipefail` at the top of the script (`head/.claude/scripts/workflow-state.sh:16`), this either throws a bash arithmetic error or (depending on bash version/context) silently misbehaves — in the exact state (a freshly created, still-empty `sprint.md`) where `get_completed_sprints`/`get_total_sprints` are most likely to be invoked. This is a functional regression, not an attacker-exploitable path (no untrusted input reaches this), but it breaks the "one-line sprint count restore" the PR title claims to be a clean simplification of — the base version's `n=$(... || true); echo "${n:-0}"` avoided exactly this double-print because `|| true` only affects the exit status *of the substitution*, and the surrounding `echo "${n:-0}"` was the single, guaranteed print.

**Remediation:** `grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null` alone (no `||`) already prints `0` on no-match and is safe under `pipefail` as long as the caller doesn't depend on its exit code — check whether anything treats `get_total_sprints`'s exit status as meaningful before dropping the `|| true` guard that made the base version deliberately ignore it.

---

### LOW — Bearer-token redaction character class no longer covers `=`, leaving base64 padding unredacted

**File:** `head/.claude/scripts/lib/invoke-diagnostics.sh:48`

```sed
-    -e 's/(Bearer )[A-Za-z0-9=._-]+/\1***REDACTED***/g' \
+    -e 's/(Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g' \
```

Standard base64 (and base64url with padding) tokens can end in one or two `=` characters. Dropping `=` from the match class means a `Bearer <token>==` value now redacts only up to the first `=`, leaving `==` printed immediately after the `***REDACTED***` marker (e.g., `Bearer ***REDACTED***==`). The leaked fragment carries negligible entropy (padding only, and only when padding falls at the token's tail), so this is low severity, but it is an incomplete redaction of a secret-token pattern that the same commit's own header comment (`head/.claude/scripts/lib/invoke-diagnostics.sh:25`, "Bearer, Authorization") calls out as in scope. No rationale for narrowing this specific class is given in the diff or PR description.

**Remediation:** Restore `=` in the Bearer character class, or confirm (with a test fixture) that no token shape used by this codebase's providers places `=` mid-token before narrowing further.

---

## Observations (not tallied)

- **`block-destructive-bash.sh:210-236`** — the PR removes the quote characters (`'`, `"`) from the carrier-regex prefix classes (`_bdb_re_git`, `_bdb_re_brbd`, `_bdb_re_gh`: `[^;&|'\"]*` → `[^;&|]*`) and deletes the `_bdb_re_tail` sequential-flag loop (which handled a second `-m`/`-d`/`--body`/`--title` occurrence, e.g. `git commit -m "Title" -m "Body"`, without needing to re-match `git ... commit`). Traced by hand: neither change opens a bypass — the load-bearing defense (content-gating any captured value that contains `$(` or a backtick, leaving it un-redacted and thus still subject to the FR-2 quote-independent subshell check) is untouched by both edits, and both changes only ever make the scrub-copy **match less** or leave **more** raw content in place, which is fail-safe (more likely to over-block) rather than fail-open. The practical effect is a functional regression: multi-`-m` git commits and `git -c '...' commit -m "..."` invocations lose the intentional false-positive suppression this carrier scrub exists for (see the file's own rationale at `head/.claude/hooks/safety/block-destructive-bash.sh:148-213`, which still describes "sequential" carrier handling that the code below it no longer implements — the comment block was not updated to match). Flagging as an observation rather than a tallied finding because there is no confirmed exploitable security degradation, only comment/code drift and a plausible false-positive-rate regression for legitimate multi-paragraph commit messages.

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## Verdict

CHANGES_REQUIRED

The AWS credential-redaction narrowing (HIGH) removes coverage for STS/temporary access keys from a diagnostics path whose entire purpose is safe handling of potentially-sensitive model-invoke output; this should be restored (or explicitly justified and scoped) before merge. The `workflow-state.sh` double-echo (MEDIUM) is a real correctness regression in the zero-sprints case and should be fixed in the same pass since it's part of this PR's claimed "restore the one-line sprint count" change. The Bearer-token `=` narrowing (LOW) should be reverted for consistency unless a token-shape audit backs the narrower class.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"ts":"2026-09-22T00:00:00Z"} -->
