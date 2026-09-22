# Security Audit Report — chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting

**Audit type**: Ad-hoc PR audit (no sprint plan / beads / a2a directory present)
**Scope**: `head.diff` — 3 files changed:
- `.claude/hooks/safety/block-destructive-bash.sh`
- `.claude/scripts/lib/invoke-diagnostics.sh`
- `.claude/scripts/workflow-state.sh`

## Executive Summary

This PR is framed as a "cleanup pass" but two of its three hunks are **security-control regressions dressed as simplifications**. The first hunk removes the quote characters from the excluded-character classes in `block-destructive-bash.sh`'s carrier-value regexes. Because bash's `[[ =~ ]]` uses the system (glibc) regex engine, which implements POSIX **leftmost-longest** matching, this change lets the carrier match span across an entire earlier quoted argument and its true content, causing a genuinely destructive payload (e.g. `rm -rf /`, `DROP TABLE`) hidden in an early `-m`/`-d`/`--body` value to be silently redacted away before any of the destructive-command patterns (FR-2, P8/P9/P10, etc.) ever see it — a full fence bypass for the exact class of attack the carrier-redaction logic exists to police (command-substitution smuggling). The second hunk narrows the AWS access-key redaction pattern in `invoke-diagnostics.sh` from seven documented AWS key-ID prefixes down to one (`AKIA` only), dropping coverage for `ASIA` (STS/temporary session keys — the most common shape in CI/role-assumption environments), `AROA`, `AGPA`, `AIPA`, `ANPA`, `ANVA`. Diagnostic logs that previously redacted these will now leak them in the clear. The third hunk (`workflow-state.sh`) is a correctness regression, not a security one, but it can corrupt sprint-progress state used by workflow gating.

Overall Risk Level: **CRITICAL** (Finding 1 is a live, reproducible bypass of the repository's primary destructive-command safety fence).

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 1 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## Findings

### [CRITICAL] FR-2/carrier-scrub regression: quote-permissive carrier regex lets destructive payloads hide inside an earlier quoted commit/PR/bead argument

**Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:210-212` (also exercised via `_bdb_scrub` at `head/.claude/hooks/safety/block-destructive-bash.sh:219-236`)

**Description**: The diff narrows the excluded-character class in all three carrier regexes from `[^;&|'\"]*` to `[^;&|]*`:

```
head/.claude/hooks/safety/block-destructive-bash.sh:210:_bdb_re_git="(^|[^[:alnum:]_])git[[:space:]][^;&|]*commit[^;&|]*(-m|--message)[[:space:]]+${_bdb_qval_perm}"
head/.claude/hooks/safety/block-destructive-bash.sh:211:_bdb_re_brbd="(^|[^[:alnum:]_])(br|bd)[[:space:]][^;&|]*(create|update)[^;&|]*(-d|--description)[[:space:]]+${_bdb_qval_perm}"
head/.claude/hooks/safety/block-destructive-bash.sh:212:_bdb_re_gh="(^|[^[:alnum:]_])gh[[:space:]][^;&|]*(issue|pr)[^;&|]*create[^;&|]*(--body|--title)[[:space:]]+${_bdb_qval_perm}"
```

The comment directly above (`head/.claude/hooks/safety/block-destructive-bash.sh:207-208`, unchanged prose left over from before the edit) still says *"[^;&|]* keeps the prefix within one segment"* — but prior to this PR the character class was `[^;&|'\"]*`, i.e. it ALSO stopped at quote characters, which is what actually bounded the match to a single quoted value. The comment was already describing the post-PR behavior while the code still had the stronger class, so the PR appears to have "fixed" the code to match a stale/aspirational comment rather than the other way around.

Bash's `[[ str =~ ere ]]` compiles the pattern with the host's regex library (glibc on Linux), which — per this very file's own header (`head/.claude/hooks/safety/block-destructive-bash.sh:24-29`) — implements POSIX ERE semantics, i.e. **leftmost-longest** overall match, not Perl/PCRE leftmost-first backtracking. Once quotes are permitted inside `[^;&|]*`, the greedy prefix can walk across an entire earlier quoted value (including one containing `$(...)`) to reach a *later* occurrence of the same flag, because doing so produces a strictly longer overall match, which POSIX prefers.

`_bdb_scrub` (`head/.claude/hooks/safety/block-destructive-bash.sh:219-236`) then applies its content gate **only to the trailing captured value** (`vi=$(( ${#BASH_REMATCH[@]} - 1 ))`), and when that gate passes (no `$(` / backtick in the *last* value), it replaces the **entire matched span** — which now includes the earlier, dangerous quoted value — with a single space. The dangerous text is erased from `_cmd_match` before FR-2 (`rm -rf`, derived from `_cmd_match` at line ~800: `_fr2_cmd=$(printf '%s' "$_cmd_match" | ...)`), P8 (`DROP`), P9 (`TRUNCATE`), or P10 (`DELETE FROM`) ever run.

**Failure scenario (PoC)**:
```
git commit -m "$(rm -rf /)" -m "chore: routine cleanup"
```
- Pre-PR: `_bdb_re_git` cannot cross the quote after `"$(rm -rf /)"`, so it matches only the first `-m` occurrence; the content gate sees `$(` in that value and leaves the match **intact** (per the "command-sub value — leave INTACT" branch at line 229/231), so the raw `rm -rf /` text survives into `_cmd_match` and is caught by the FR-2 `rm -rf` gate at line 782-783 → command is **blocked**.
- Post-PR: `_bdb_re_git`'s prefix classes can now consume through the first quoted value, so POSIX leftmost-longest matching binds `(-m|--message)` to the **second** `-m` and captures `"chore: routine cleanup"` as the trailing value. That value contains no `$(`/backtick, so the *entire* matched span — `git commit -m "$(rm -rf /)" -m "chore: routine cleanup"` — is replaced by a single space in `_cmd_match`. `rm -rf /` never reaches any pattern (FR-2, P8/P9/P10, etc.) and the hook exits 0 (allow). The destructive command **executes**.

The same shape applies to the `br|bd ... -d ... -d` and `gh ... create ... --body ... --body` carriers (lines 211, 212) — e.g. `gh pr create --body "$(DROP TABLE users;)" --body "release notes"` would likewise be scrubbed whole.

This is the exact attack (command-substitution smuggled inside an allow-listed "inert data carrier") that the surrounding comment block (`head/.claude/hooks/safety/block-destructive-bash.sh:164-184`) explicitly calls out as the fence's one load-bearing bypass concern, and that the content gate exists to catch. The PR removes the boundary that made the content gate's "only inspect the trailing value" simplification safe.

**Remediation**: Restore the quote exclusion in all three carrier regexes (`[^;&|'\"]*` instead of `[^;&|]*`) so each match cannot span more than one quoted value. If multi-flag consolidation (the removed `_bdb_re_tail` loop) was the actual goal of this cleanup, that loop should be restored too, or replaced with an explicit test that only ever redacts the *single* value immediately following the matched flag — never a swallow across value boundaries. Add a regression test asserting that `git commit -m "$(rm -rf /)" -m "safe"` is still blocked.

**References**: CWE-184 (Incomplete List of Disallowed Inputs), CWE-693 (Protection Mechanism Failure), OWASP A03:2021 (Injection) — the fence exists specifically to prevent shell command injection/destructive execution via LLM-agent-issued Bash commands.

---

### [HIGH] AWS access-key redaction narrowed to a single prefix, dropping STS/temporary-credential coverage

**Component**: `head/.claude/scripts/lib/invoke-diagnostics.sh:50`

**Description**: 
```
head/.claude/scripts/lib/invoke-diagnostics.sh:50:    -e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
```
replaces the prior:
```
base/.claude/scripts/lib/invoke-diagnostics.sh:39:    -e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
```
`redact_secrets()` is documented at `head/.claude/scripts/lib/invoke-diagnostics.sh:6-9` as the function that "strip[s] API keys and tokens from log output" for model-invoke diagnostic logs (`setup_invoke_log`/`log_invoke_failure`), and its own comment block still lists (`head/.claude/scripts/lib/invoke-diagnostics.sh:37`) `AKIA* — AWS IAM access key IDs` as the only documented shape, but AWS defines multiple key-ID prefixes sharing the same `[A-Z0-9]{16}` suffix shape: `AKIA` (long-term IAM user keys), `ASIA` (STS temporary/session credentials — the default shape issued by role assumption, which is the dominant credential shape in CI and cloud-native environments), `AROA` (role IDs), `AGPA` (group IDs), `AIPA` (instance-profile IDs), `ANPA`/`ANVA` (Amazon-managed policy/version IDs, sometimes appearing alongside key material in IAM-related error output).

**Failure scenario**: A model-invoke call fails while a temporary AWS session token (`ASIA...`) is present in its stderr (e.g. an SDK exception embedding the offending credential, or a misconfigured provider echoing its env), and the failure is captured via `log_invoke_failure` into an `INVOKE_LOG` file. Pre-PR, `redact_secrets` would have matched and redacted the `ASIA...` key ID. Post-PR, the same key ID passes through `redact_secrets` untouched and is persisted in the diagnostic log file (created via `setup_invoke_log`, `head/.claude/scripts/lib/invoke-diagnostics.sh:66-75`, world-unreadable via `chmod 600` per its own docstring but still an unredacted secret at rest, subject to later log aggregation/sharing/bug-report attachment where the `Bearer`/`ghp_`/etc. handling elsewhere in this same function implies the log's content is expected to be safe to move around).

**Remediation**: Restore the alternation `(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}` (or at minimum re-add `ASIA`, the highest-prevalence dropped prefix). If the intent was genuinely to scope to "the documented AWS access-key shape," update the *documentation* to state the full set rather than removing coverage — the comment block already only claimed `AKIA*` even before this PR, which was already an under-statement of the base regex's actual (correct, broader) coverage.

**References**: CWE-532 (Insertion of Sensitive Information into Log File), CWE-200 (Exposure of Sensitive Information).

---

### [MEDIUM] `get_total_sprints` can emit two lines instead of one, breaking arithmetic consumers

**Component**: `head/.claude/scripts/workflow-state.sh:70-76`

**Description**:
```
head/.claude/scripts/workflow-state.sh:71-76:
    if [[ -f "${SPRINT_FILE}" ]]; then
        grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
```
`grep -c PATTERN FILE` prints the match count to stdout **and** exits with status 1 whenever that count is zero (GNU grep: exit 0 only when at least one match was found). When `SPRINT_FILE` exists but contains no `## Sprint N` headings, `grep -c` prints `0` to stdout and exits 1, which then also triggers the `|| echo "0"` fallback — producing **two** lines of output (`"0\n0"`) instead of one. The prior form (`base/.claude/scripts/workflow-state.sh:71-73`, `n=$(grep -c ... || true); echo "${n:-0}"`) avoided this because `n` only ever holds grep's own stdout and the fallback `echo` was reached solely through `${n:-0}`, which can't double-emit.

**Failure scenario**: `get_completed_sprints()` (`head/.claude/scripts/workflow-state.sh:83-88`) does `total=$(get_total_sprints); for ((i = 1; i <= total; i++))`. When `get_total_sprints` returns `"0\n0"` for an existing sprint plan file with zero recognized `## Sprint N` headings (e.g. a malformed or in-progress sprint.md), the arithmetic `for` condition `i <= total` receives a two-line string, which bash's arithmetic evaluator rejects (`syntax error: invalid arithmetic operator` / similar), aborting the script (or, under `set -e` callers, the whole invocation) instead of the intended "zero sprints, loop doesn't run" behavior. Any other caller that expects a single-line integer (progress percentage math, `/loa` status display, run-mode gating) is equally exposed.

**Remediation**: Keep the base behavior: capture into a variable first, then apply a single unconditional `echo`, e.g. `local n; n=$(grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null) || true; echo "${n:-0}"`.

**References**: CWE-393 (Return of Wrong Status Code) — not attacker-controlled, but a self-inflicted denial-of-service on workflow-state tooling.

---

### [LOW] Bearer-token redaction regex no longer matches `=` in the token body

**Component**: `head/.claude/scripts/lib/invoke-diagnostics.sh:48`

**Description**:
```
head/.claude/scripts/lib/invoke-diagnostics.sh:48:    -e 's/(Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g' \
```
previously:
```
base/.claude/scripts/lib/invoke-diagnostics.sh:37:    -e 's/(Bearer )[A-Za-z0-9=._-]+/\1***REDACTED***/g' \
```
Standard (non-URL-safe) base64-encoded opaque bearer tokens commonly end in `=`/`==` padding. With `=` removed from the character class, `sed`'s match stops at the first `=`, so a token such as `Bearer YWJjMTIzNDU2Nzg5MA==` is redacted only up to the padding: `Bearer ***REDACTED***==`. The leaked suffix is pure base64 padding (no entropy — it is a deterministic function of the pre-padding length modulo 3), so the practical secrecy impact is minimal, but it is a real narrowing of the redaction pattern's coverage relative to its stated purpose, and is not mentioned in the PR description or the file's own "Expanded patterns" comment.

**Remediation**: Restore `=` in the character class: `[A-Za-z0-9=._-]+`.

**References**: CWE-532 (Insertion of Sensitive Information into Log File) — minimal-impact instance.

## Security Checklist Status

- [ ] Destructive-command fence (block-destructive-bash.sh) resists the command-substitution-in-carrier bypass — **FAILED** (Finding 1)
- [ ] Secret redaction covers all documented AWS credential prefixes — **FAILED** (Finding 2)
- [x] No hardcoded secrets introduced
- [x] No new SQL/shell injection sinks introduced (this PR only touches existing regex-based fences)
- [ ] Diagnostic redaction regexes cover previously-covered character shapes — **FAILED** (Finding 4, minor)
- [ ] Workflow-state helper functions preserve single-value stdout contract — **FAILED** (Finding 3)

## Verdict

**CHANGES_REQUIRED** — Finding 1 is a critical, reproducible bypass of the repository's primary destructive-command safety hook, and Finding 2 is a high-severity regression in secret redaction. Both must be reverted/fixed before this PR merges. Findings 3 and 4 should be fixed in the same PR since they are trivial one-line reversions to the prior, correct behavior.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":1,"high":1,"medium":1,"low":1},"sprint_id":"pr-audit","ts":"2026-09-21T00:00:00Z"} -->
