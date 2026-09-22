# Security Audit Report

**PR**: chore(hooks,scripts): simplify carrier-value regexes, redaction patterns and sprint counting
**Scope**: `.claude/hooks/safety/block-destructive-bash.sh`, `.claude/scripts/lib/invoke-diagnostics.sh`, `.claude/scripts/workflow-state.sh`
**Auditor**: Paranoid Cypherpunk Auditor

## Executive Summary

This PR bills itself as a pure cleanup ("simplify regexes / trim redaction set / restore a
one-liner"), but two of the three hunks are not cleanups — they are silent reductions in
security coverage, and the PR description actively mischaracterizes one of them. The
`invoke-diagnostics.sh` change drops five of six documented AWS access-key-ID prefixes from
the secret-redaction pattern, including `ASIA` (temporary/STS credentials) — the prefix most
likely to appear in a CI/cloud-runtime environment. The `workflow-state.sh` change reintroduces
a shell double-output bug that corrupts sprint-count arithmetic and the tool's own JSON output
on the (very common) zero-match path. The `block-destructive-bash.sh` hunk is comparatively
benign: it widens a quote-exclusion class in the destructive-bash fence's carrier-scrub regexes
and deletes a supplementary "tail" loop, but the load-bearing anti-bypass check (the
quote-independent `$(`/backtick detector, FR-2) is untouched and out of scope for this diff, so
the net effect there is more conservative (more over-blocking of legitimate multi-flag
commands), not a new bypass.

## Overall Risk Level: **HIGH**

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 1 |
| Low | 1 |

## High Priority Issues

### H-1: AWS temporary/session credential prefixes dropped from secret redaction

- **Component**: `head/.claude/scripts/lib/invoke-diagnostics.sh:50`
- **Severity**: HIGH
- **Category**: Sensitive Data Exposure (CWE-200, CWE-532 Insertion of Sensitive Information into Log File; OWASP A09:2021 Security Logging and Monitoring Failures / A02:2021 Cryptographic Failures)

**Finding**: `redact_secrets()` is documented as the choke point that "strip[s] API keys and
tokens from log output" for `invoke-diagnostics.sh`'s per-invocation debug logs (see
`head/.claude/scripts/lib/invoke-diagnostics.sh:6-8`, `:36-38`). Before this PR the AWS pattern
covered all documented AWS unique-identifier prefixes that denote access-key-shaped secrets:

```
head/.claude/scripts/lib/invoke-diagnostics.sh (base, pre-PR):47
-e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
```

The PR narrows this to `AKIA` only:

```
head/.claude/scripts/lib/invoke-diagnostics.sh:50
-e 's/AKIA[A-Z0-9]{16}/AKIA***REDACTED***/g' \
```

`ASIA` is the prefix for **temporary/STS access key IDs** — exactly the credential shape
produced by `AssumeRole`, EC2/ECS/Lambda instance-role metadata, and GitHub Actions OIDC
role assumption. These are live, secret-bearing values (paired with a secret key and session
token) valid for up to the credential's TTL (commonly 1–36 hours), not mere identifiers.
`AROA`/`AIPA`/`AGPA`/`ANPA`/`ANVA` are role/instance-profile/group/policy unique IDs, which
AWS itself documents alongside `AKIA`/`ASIA` in the same "unique identifier" reference table —
the PR description's claim that `AKIA`-only is "the documented AWS access-key shape" conflates
"has an AWS reference doc" with "is the complete set of access-key-shaped secrets," and drops
the one prefix (`ASIA`) that is unambiguously a live secret and unambiguously common in the
exact CI/cloud environments this Hounfour multi-model routing layer runs in
(`head/.claude/scripts/lib/invoke-diagnostics.sh:2` "Secure error diagnostics for model-invoke
calls").

**Impact**: if any subprocess output captured into `INVOKE_LOG` (stderr from a model-invoke
call, an SDK's verbose/debug trace, an underlying HTTP client's request dump, etc.) contains an
`ASIA*` access key ID, it is no longer redacted before the log is surfaced to
`log_invoke_failure`'s "Details: $log_file" pointer or otherwise persisted/inspected. Given
`setup_invoke_log` deliberately preserves the log file on failure for debugging
(`head/.claude/scripts/lib/invoke-diagnostics.sh:85`), a leaked temporary AWS credential would
sit on disk in a `chmod 600` file until an operator manually cleans it up — a live-exploitable
secret leak, not just a definitional nicety.

**Proof of concept**: pipe representative debug output through the function:

```bash
source .claude/scripts/lib/invoke-diagnostics.sh
printf 'aws sts assume-role output: ASIA1234567890ABCDEF\n' | redact_secrets
# base (pre-PR):  aws sts assume-role output: ASIA***REDACTED***
# head (this PR): aws sts assume-role output: ASIA1234567890ABCDEF   <-- leaked verbatim
```

**Remediation**: restore the full alternation of documented AWS unique-ID prefixes, or at
minimum restore `ASIA` (the only one of the five removed prefixes that is itself a secret
value rather than a non-secret resource identifier):

```sed
-e 's/(AKIA|ASIA|AROA|AGPA|AIPA|ANPA|ANVA)[A-Z0-9]{16}/\1***REDACTED***/g' \
```

## Medium Priority Issues

### M-1: `get_total_sprints` double-emits on the zero-match path, corrupting sprint-count arithmetic and JSON output

- **Component**: `head/.claude/scripts/workflow-state.sh:70-76`
- **Severity**: MEDIUM
- **Category**: Incorrect Error Handling (CWE-393 Return of Wrong Status Code; downstream state-machine corruption)

**Finding**:

```bash
head/.claude/scripts/workflow-state.sh:70-76
get_total_sprints() {
    if [[ -f "${SPRINT_FILE}" ]]; then
        grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}
```

`grep -c PATTERN FILE` always prints a count to stdout, **including `0`**, but exits with
status `1` when the count is zero (GNU/POSIX grep semantics: exit 1 means "no lines
selected", independent of whether `-c` was used). When `SPRINT_FILE` exists but contains no
lines matching `^## Sprint [0-9]` (a freshly-created or as-yet-unpopulated `sprint.md` — a
routine, not exceptional, state), the sequence executes as:

1. `grep -c ...` prints `0\n` to stdout, then exits `1`.
2. Because the exit status is non-zero, `|| echo "0"` fires, printing a second `0\n`.

The function's total output on this path is `"0\n0\n"` — two lines — not the single integer
every caller expects. Every caller does `total_sprints=$(get_total_sprints)`
(`head/.claude/scripts/workflow-state.sh:147`, `:369`, and `local total=$(get_total_sprints)`
at `:86`), so `total_sprints` becomes the literal two-line string `"0\n0"`.

Downstream consequences, all reachable on this same zero-sprint-lines path:

- `head/.claude/scripts/workflow-state.sh:151`: `[[ "${completed_sprints}" -ge "${total_sprints}" ]]` — bash's `-ge` on a non-integer operand raises `integer expression expected` on stderr and evaluates false (silently mis-scoping the state machine rather than crashing, since it's inside an `if`, which `set -e` does not gate on).
- `head/.claude/scripts/workflow-state.sh:158` / `:376`: `for i in $(seq 1 "${total_sprints}")` — `seq 1 "0\n0"` fails (invalid argument), silently producing zero loop iterations, so the "find current sprint" logic never runs and `determine_state` falls through to the wrong default (`STATE_SPRINT_PLANNED`, `head/.claude/scripts/workflow-state.sh:185`) even when sprints exist elsewhere in a different form.
- `head/.claude/scripts/workflow-state.sh:403`: `"total_sprints": ${total_sprints},` in the hand-built JSON heredoc emits **invalid JSON** (`"total_sprints": 0\n0,`), breaking every `--json` consumer (e.g. the cache round-trip at `:360` piping through `jq -r`).

This file backs the golden-path `/loa` status command and the workflow-state detection that the
project's own process-compliance rules (`CLAUDE.loa.md` "Process Compliance" / "Golden Path")
lean on to tell an operator or an autonomous run which gate to execute next; a silently wrong
state determination (e.g. mis-reporting `sprint_planned` instead of the true in-progress state)
undermines the reliability of that gating signal, even though it does not by itself bypass a
gate.

**Proof of concept**:

```bash
printf '# Sprint Plan\n\nNo sprints yet.\n' > /tmp/sprint.md
grep -c "^## Sprint [0-9]" /tmp/sprint.md 2>/dev/null || echo "0"
# prints:
# 0
# 0
```

**Remediation**: restore the base version's pattern, which captures grep's stdout into a
variable first so the `||` only supplies a default for a *missing* value, never appends a
second line:

```bash
get_total_sprints() {
    if [[ -f "${SPRINT_FILE}" ]]; then
        local n
        n=$(grep -c "^## Sprint [0-9]" "${SPRINT_FILE}" 2>/dev/null || true)
        echo "${n:-0}"
    else
        echo "0"
    fi
}
```

## Low Priority Issues

### L-1: `Bearer` token redaction narrowed to exclude `=`, can leave a trailing fragment unredacted

- **Component**: `head/.claude/scripts/lib/invoke-diagnostics.sh:48`
- **Severity**: LOW
- **Category**: Incomplete redaction (CWE-116 Improper Encoding or Escaping of Output, informational)

**Finding**:

```
head/.claude/scripts/lib/invoke-diagnostics.sh:48
-e 's/(Bearer )[A-Za-z0-9._-]+/\1***REDACTED***/g' \
```

vs. base:

```
-e 's/(Bearer )[A-Za-z0-9=._-]+/\1***REDACTED***/g' \
```

Removing `=` from the value character class means the match stops at the first `=` in the
token; any trailing characters after an embedded `=` (most plausibly standard-base64 padding,
which is legal in `Bearer` values that aren't base64url) are left un-redacted after the
`***REDACTED***` marker instead of being consumed. In practice this typically leaks only 1–2
low-entropy padding characters (`=`/`==`), so exploitability is minimal, but it is a real
narrowing of the redaction surface in a function whose entire purpose is secret redaction, and
it is inconsistent with the PR's own updated comment block, which still documents "Bearer —
OAuth/JWT Bearer tokens in headers" as fully covered (`head/.claude/scripts/lib/invoke-diagnostics.sh:35`).

**Remediation**: restore `=` to the character class:

```sed
-e 's/(Bearer )[A-Za-z0-9=._-]+/\1***REDACTED***/g' \
```

## Notes on `block-destructive-bash.sh` (no finding)

`head/.claude/hooks/safety/block-destructive-bash.sh:210-212` widens the carrier-prefix
character class from `[^;&|'"]*` to `[^;&|]*` (permitting quote characters inside the
prefix between e.g. `git ... commit` and the `-m`/`--message` flag) and
`head/.claude/hooks/safety/block-destructive-bash.sh` deletes the supplementary
`_bdb_re_tail` loop that previously re-scrubbed additional sequential
`-m`/`-d`/`--body`/`--title`-style flags after the first carrier match. I traced both changes
against the scrub algorithm (`_bdb_scrub`, `head/.claude/hooks/safety/block-destructive-bash.sh:219-236`)
and the untouched, quote-independent `$(`/backtick boundary check that the file's own header
comment (`head/.claude/hooks/safety/block-destructive-bash.sh:215-217`) identifies as the actual
anti-bypass control:

- The scrub only ever replaces the **trailing captured value** with a space
  (`head/.claude/hooks/safety/block-destructive-bash.sh:231-232`, `po="${m%"$val"}"`); any
  earlier quoted content that the widened prefix now swallows is preserved verbatim in `po`,
  not deleted — so dangerous literal text or an embedded `$(...)`/backtick in an *earlier*
  carrier value in a multi-flag command remains visible to (a) the same content gate on a
  later pass, or (b) the separate FR-2 quote-independent subshell check elsewhere in the file
  (out of this diff's scope, unmodified).
- Because the prefix classes still exclude `;`, `&`, and `|`, per-segment scoping is preserved:
  the scrub still cannot cross a real statement separator, so `echo 'safe' && rm -rf /` is
  unaffected.
- The observable regression is that a command with **more than one** sequential
  `-m`/`--message`/`-d`/`--description`/`--body`/`--title` carrier flag in a single segment now
  gets only its *last* flag's value redacted (the earlier one is left as literal, unredacted
  text) — this makes the fence *more* likely to false-positive-block a legitimate multi-flag
  command (e.g. `git commit --author "a@b.com" -m "..." -m "..."`), not less likely to catch a
  real destructive payload. I did not find a reachable case where the widened prefix or the
  removed tail loop causes a genuinely destructive command to be silently redacted away.

This is a behavioral regression worth the maintainers' awareness (multi-`-m` git commits or
multi-flag `gh`/`br` invocations may now spuriously trip the fence), but it is not a security
finding, so it is not scored in the tally above.

## Security Checklist Status

- [x] Secrets & Credentials — **FAILED** (H-1, L-1)
- [x] Input Validation — N/A for this diff
- [x] Authentication & Authorization — N/A for this diff
- [x] Data Privacy / Logging — **FAILED** (H-1)
- [x] Injection Prevention (destructive-bash fence) — reviewed, no regression found
- [x] Error Handling — **FAILED** (M-1)

## Verdict

**CHANGES_REQUIRED**

Both the AWS-prefix redaction narrowing (H-1) and the mischaracterization of it in the PR
description ("trimmed back to the documented AWS access-key shape") must be reverted/fixed
before merge. M-1's double-output bug should be fixed in the same pass since it reintroduces a
previously-fixed bug shape (the base version explicitly worked around this with the
`n=$(... || true); echo "${n:-0}"` pattern this PR undoes). L-1 should be fixed for
completeness but is not blocking on its own.

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":1,"low":1},"sprint_id":"pr-audit","ts":"2026-09-21T00:00:00Z"} -->
