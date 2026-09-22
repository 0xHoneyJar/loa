# Security Audit Report

**PR**: chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting
**Audit type**: Ad-hoc PR audit (no sprint plan / beads / a2a directory present)
**Scope**: `head.diff` — 3 files touched:
- `.claude/hooks/safety/block-destructive-bash.sh`
- `.claude/scripts/lib/invoke-diagnostics.sh`
- `.claude/scripts/workflow-state.sh`

## Executive Summary

This PR frames itself as a pure cleanup/simplification pass, but two of the three changes are functional regressions with real impact, not neutral simplifications. The `invoke-diagnostics.sh` change silently drops secret-redaction coverage for six of seven AWS access-key-ID prefixes (keeping only `AKIA`), meaning STS session keys (`ASIA…`), role keys (`AROA…`) and other AWS credential-ID shapes will now be written to diagnostic logs in plaintext instead of being redacted. The `workflow-state.sh` change reintroduces the classic `grep -c ... || echo` double-output bug: when `sprint.md` exists but contains zero matching sprint headings, the function now emits two lines (`"0\n0"`) instead of one, corrupting every numeric consumer (arithmetic loops, `-ge`/`-gt` comparisons, and the `--json` status output consumed by `/loa`). The `block-destructive-bash.sh` change removes the multi-flag tail loop that scrubbed additional `-m`/`-d`/`--body`/`--title` values beyond the first; analysis shows this does **not** open a bypass (command-substitution payloads remain visible in the scrub-copy regardless of position, because the "gap" text is never redacted), but it does break the exemption for legitimate multi-value carriers (e.g. the common `git commit -m "<subject>" -m "<body>"` idiom), risking false-positive blocks.

**Overall Risk Level**: HIGH (driven by the secret-redaction regression and the malformed state-JSON regression)

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 2 |
| Low | 0 |

## High Priority Issues

### H-1: AWS credential-ID redaction narrowed from 7 prefixes to 1 — secrets now leak into diagnostic logs

- **Component**: `head/.claude/scripts/lib/invoke-diagnostics.sh:50`
- **Before** (`base/.claude/scripts/lib/invoke-diagnostics.sh:47`):
  ```
  -e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
  ```
- **After**:
  ```
  -e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
  ```
- **Description**: `redact_secrets()` is the sole scrubbing pass applied to `model-invoke` diagnostic logs (`setup_invoke_log`/`log_invoke_failure`, per this file's own header) before those logs are surfaced or persisted. The PR description calls this "trimmed back to the documented AWS access-key shape," but the removed prefixes are all real, documented AWS credential-ID classes: `ASIA` (STS/temporary session credentials — the type most likely to appear in cloud-runtime error output, since they rotate and are frequently embedded in SDK stack traces or env dumps), `AROA` (role IDs), `AGPA` (group IDs), `AIPA` (instance-profile IDs), `ANPA`/`ANVA` (policy/version IDs often included in IAM error messages). After this change only long-lived IAM user keys (`AKIA*`) are redacted; any of the other six credential-ID shapes appearing in a failed model-invoke's stderr/stdout will now be written to the log file (and to `/tmp` per `setup_invoke_log`, and to any anywhere that log gets surfaced) in plaintext.
- **Impact**: Credential-ID disclosure (CWE-532, Insertion of Sensitive Information into Log File) — most severe for `ASIA` (temporary session keys), which are functionally live AWS credentials until they expire.
- **PoC**: Any invocation that fails while an AWS SDK or CLI error message containing e.g. `AccessDenied ... for user with access key ASIAABCDEF0123456789 ...` is captured to the invoke log will have that ID printed verbatim (`ASIAABCDEF0123456789`) instead of `ASIA***REDACTED***`.
- **Remediation**: Restore the full alternation: `-e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \`. If the intent was genuinely to scope this to "the documented AWS access-key shape," that documentation itself needs updating — the six removed prefixes are documented AWS-owned ID types, not made up.
- **References**: CWE-532, OWASP A09:2021 (Security Logging and Monitoring Failures — includes over-verbose logs disclosing sensitive data).

### H-2: `get_total_sprints` reintroduces `grep -c || echo` double-output bug — corrupts sprint-count state

- **Component**: `head/.claude/scripts/workflow-state.sh:70-76`
  ```
  69	get_total_sprints() {
  70	    if [[ -f "${SPRINT_FILE}" ]]; then
  71	        grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
  72	    else
  73	        echo "0"
  74	    fi
  75	}
  ```
- **Description**: `grep -c PATTERN FILE` prints the match count to stdout **and** exits with status `1` whenever that count is `0` (standard grep/POSIX behavior — this is not a corner case, it is grep's documented behavior for "no lines matched"). Line 71 does not capture grep's output into a variable before deciding on a fallback (the way the removed `base/` version did: `n=$(grep -c ... || true); echo "${n:-0}"`); it lets grep write directly to the function's stdout and *then* evaluates the `||`. So when `SPRINT_FILE` exists but has zero `## Sprint N` headings, this function now prints **two lines** — `0` from `grep -c` itself, followed by a second `0` from the `|| echo "0"` fallback — instead of the single `0` every caller expects.
- **Downstream impact**: every consumer of `get_total_sprints` treats its output as a scalar integer captured via command substitution:
  - `head/.claude/scripts/workflow-state.sh:86` — `total=$(get_total_sprints)` inside `get_completed_sprints()`, fed into `for ((i = 1; i <= total; i++))` — a two-line string in an arithmetic context is a bash syntax error at runtime (`((...))`: value too great for base / syntax error).
  - `head/.claude/scripts/workflow-state.sh:147,151` — `total_sprints=$(get_total_sprints)` then `[[ "${completed_sprints}" -ge "${total_sprints}" ]]` — `-ge` on a two-line value throws `integer expression expected`.
  - `head/.claude/scripts/workflow-state.sh:369,403` — feeds directly into the `--json` status payload as `"total_sprints": ${total_sprints},`, which is exactly the machine-readable output the Golden Path `/loa` command ("Where am I? What's next?") and Run Mode state recovery consume — this produces invalid JSON (an unquoted multi-line numeric literal) that breaks `jq` parsing for any caller.
  - `head/.claude/scripts/workflow-state.sh:158,376` — `seq 1 "${total_sprints}"` — `seq` will error on a multi-line argument.
- **Trigger condition**: any sprint.md that exists but does not yet contain a line matching `^## Sprint [0-9]` — e.g. immediately after `sprint.md` is created but before the first `## Sprint N` heading is written, or if the heading format ever drifts (e.g. `## Sprint: 1`). Not an exotic edge case for a file that is actively being authored/updated across a run.
- **Remediation**: restore capture-then-default, e.g.:
  ```bash
  local n
  n=$(grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || true)
  echo "${n:-0}"
  ```
  (This is exactly what `base/.claude/scripts/workflow-state.sh:71-73` already did — the PR's "restores the one-line sprint count" claim in fact reintroduces a previously-avoided bug rather than restoring prior-working behavior.)
- **References**: CWE-393 (Return of Wrong Status Code — grep's exit code is misread as "no output produced"); this is also flagged as a known bash gotcha in this repo's own `.claude/rules/shell-conventions.md` ("Arithmetic with `set -e`" section addresses the sibling gotcha of misreading a command's exit status in a counting context).

## Medium Priority Issues

### M-1: Bearer-token redaction no longer covers base64 padding (`=`) — partial token leakage

- **Component**: `head/.claude/scripts/lib/invoke-diagnostics.sh:48`
  ```
  -e 's/(Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g' \
  ```
  vs. `base/.claude/scripts/lib/invoke-diagnostics.sh:45`:
  ```
  -e 's/(Bearer )[A-Za-z0-9=._-]+/\1***REDACTED***/g' \
  ```
- **Description**: RFC 6750 `b64token` syntax explicitly allows trailing `=` padding (`1*( ALPHA / DIGIT / "-" / "." / "_" / "~" / "+" / "/" ) *"="`), and many real bearer tokens (base64url-encoded opaque tokens, some JWTs re-padded by intermediaries) end in `=` or `==`. Dropping `=` from the character class means the substitution now stops matching at the first `=` it encounters. Any Bearer token containing `=` — whether padding at the end or (less commonly) an encoded `=` earlier in an opaque token — is only *partially* redacted: the prefix before the first `=` becomes `***REDACTED***`, but the `=` itself and anything after it (up to the next non-token character) is left in plaintext in the log.
- **Impact**: partial secret disclosure in diagnostic logs (CWE-532). Lower severity than H-1 because typically only the padding characters (1-2 bytes) survive for well-formed base64url tokens, but the character class change also affects any token containing an internal `=`, where a larger unredacted remainder is possible.
- **Remediation**: restore `[A-Za-z0-9=._-]+` for the Bearer pattern.
- **References**: CWE-532; RFC 6750 §2.1.

### M-2: Removal of the multi-flag tail loop degrades the carrier exemption for legitimate multi-value commands (false-positive risk, not a bypass)

- **Component**: `head/.claude/hooks/safety/block-destructive-bash.sh:207-236` (compare `base/.claude/hooks/safety/block-destructive-bash.sh:207-249`, which additionally defined `_bdb_re_tail` and looped over it inside `_bdb_scrub`)
- **Description**: The PR makes two coupled changes to the same mechanism: (1) it removes the quote characters (`'`, `"`) from the exclusion class of the "gap" between keyword and flag (`[^;&|'\"]*` → `[^;&|]*}`) in `_bdb_re_git`/`_bdb_re_brbd`/`_bdb_re_gh`, and (2) it deletes `_bdb_re_tail` and the `while` loop in `_bdb_scrub` that used it to walk additional `-m`/`-d`/`--body`/`--title` occurrences after the first. Combined, this changes which quoted value gets content-gated: because bash `[[ =~ ]]` uses POSIX leftmost-longest matching, and the gap classes no longer stop at a quote character, a command with **multiple** flag occurrences (e.g. `git commit -m "<subject>" -m "<body>"`, a standard git idiom for separating subject/body, or `gh pr create --title "..." --body "..."` — no, title/body are different flags so unaffected there, but `br update --description "a" --description "b"`-style repeats are) now has the regex capture only the **last** occurrence's value for the content gate; every earlier flag+value pair is folded into the unredacted "prefix" text and left byte-for-byte in the scrub-copy (`_cmd_match`) regardless of its own content.
- **Why this is not a bypass**: the content gate's job is to decide whether to *hide* a value from later pattern matching; here, earlier values are never hidden (they're preserved literally either way — via `out+="$pre$m"` when the last value is dangerous, or via `po`, which strips only the trailing captured value, when the last value is safe). So a `$(...)`/backtick payload placed in *any* flag position remains visible in `_cmd_match` and is still eligible to be caught by FR-2 and the other line-based patterns (P2–P12). Verified by tracing `_bdb_scrub`'s two branches at `head/.claude/hooks/safety/block-destructive-bash.sh:228-233`.
- **Why it is still a real regression**: the exemption mechanism's entire purpose is to stop *safe* carrier text from tripping the destructive-pattern detectors below it (P8 `DROP TABLE`, P3 `git reset --hard`, etc., matched against plain substrings of `_cmd_match`). With every flag but the last now left unredacted, a perfectly benign multi-value commit/PR/bead description — e.g. `git commit -m "drop the temp staging table helper" -m "no functional change"` — will leave `"drop the temp staging table helper"` sitting in `_cmd_match` verbatim, which is exactly the shape P8's `drop[[:space:]]+(database|table|schema)` is designed to catch, producing a false-positive block on a harmless commit. This inverts the fix that motivated adding `_bdb_re_tail` in the first place (the removed code's own comment describes it as handling "the multi-flag tail").
- **Remediation**: either restore `_bdb_re_tail` and its loop, or change `_bdb_re_git`/`_bdb_re_brbd`/`_bdb_re_gh`'s inner `[^;&|]*` gaps back to excluding quote characters (`[^;&|'\"]*`) so the primary regex reliably targets the *first* occurrence per segment, and re-add tail scanning for subsequent ones. Add a regression test with two `-m` flags (one benign phrase containing a P8/P3/P6-style keyword) to lock in the desired non-blocking behavior.
- **References**: CWE-1023-adjacent (Incomplete Comparison), general regression-testing gap — no test in this diff exercises the multi-flag path that was removed.

## Security Checklist Status

- [x] Secrets & credential redaction reviewed — **regressed** (H-1, M-1)
- [x] Input validation / carrier scrubbing reviewed — behavior changed, not a bypass, but weakened exemption fidelity (M-2)
- [x] State/counter integrity reviewed — **regressed** (H-2)
- [ ] N/A: Authentication & Authorization — not touched by this diff
- [ ] N/A: Supply chain / dependency changes — none in this diff
- [ ] N/A: Infrastructure/deployment config — none in this diff

## Threat Model Summary

All three touched files are trust-boundary/defense mechanisms rather than product code: a bash-injection-carrier scrubber gating destructive-command blocking, a secret-redaction filter for diagnostic logs, and a state-tracking helper feeding the autonomous Run Mode / Golden Path status surface. A "simplification" PR touching exactly these three files carries disproportionate risk relative to its diff size, because each removed line was load-bearing for either a security guarantee (redaction coverage) or a correctness guarantee (single-line count contract) rather than incidental complexity. None of the three changes were accompanied by tests in this diff.

## Verdict

**CHANGES_REQUIRED**

Required before merge:
1. Restore the full AWS credential-ID alternation in `redact_secrets()` (H-1).
2. Restore `=` in the Bearer-token character class (M-1).
3. Fix `get_total_sprints()` to capture-then-default instead of letting `grep -c`'s stdout leak through before the `||` fallback fires (H-2).
4. Either restore the multi-flag tail-scrub loop in `block-destructive-bash.sh` or otherwise re-verify (with a regression test) that multi-value `-m`/`-d`/`--body`/`--title` carriers are still fully exempted (M-2).

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":0},"sprint_id":"n/a","ts":"2026-09-21T00:00:00Z"} -->
