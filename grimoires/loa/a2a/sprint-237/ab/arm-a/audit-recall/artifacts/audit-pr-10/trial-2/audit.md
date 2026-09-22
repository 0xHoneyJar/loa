# Security Audit Report

**PR**: fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe
**Audit type**: Ad-hoc PR audit (no sprint plan / beads / a2a directory present)
**Scope**: `head/.claude/scripts/loa-doctor.sh`, `head/tests/unit/bug-725-ajv-version-probe.bats`
**Auditor**: auditing-security skill

## Executive Summary

This PR fixes a version-detection bug in `loa-doctor.sh`'s optional `ajv` health check. The old
one-liner (`ajv --version 2>&1 | head -1 || echo "unknown"`) captured ajv-cli@5+'s stderr usage-error
text ("error: parameter -s is required...") as if it were a version string, because the `|| echo`
fallback only fires on a `head -1` failure (which essentially never happens) rather than on `ajv`
itself failing. The fix extracts a new helper, `_loa_probe_ajv_version()`
(`head/.claude/scripts/loa-doctor.sh:228`), that: (1) tries `ajv --version` and validates the output
looks like `X.Y[.Z]`; (2) falls back to parsing a `version X.Y.Z` string out of `ajv --help`; (3)
falls back to a labeled placeholder `"unknown (ajv-cli@5+)"`. The change is read-only, local-only
(no network, no privileged operations, no user-controlled input), confined to a diagnostic/reporting
code path, and comes with a dedicated bats suite (`head/tests/unit/bug-725-ajv-version-probe.bats`)
covering the v4 path, the v5+ `--help` fallback, the no-match placeholder path, a missing-tool
control, and two explicit `errexit`/`pipefail` regression tests (BB #916 F1).

No CRITICAL, HIGH, or MEDIUM findings. Two LOW/informational observations below, neither blocking.

## Findings

### LOW-1 — `command -v ajv` / helper invocation is not a single atomic check (informational, no exploitable impact)

**Location**: `head/.claude/scripts/loa-doctor.sh:215-219`

```
215:    if command -v ajv &>/dev/null; then
216:        local ajv_ver
217:        ajv_ver=$(_loa_probe_ajv_version)
```

Between the `command -v ajv` gate at line 215 and the invocation of `ajv` inside the helper at line
245, there is a theoretical TOCTOU window if something removes `ajv` from `PATH` mid-run. This is
pre-existing behavior (the old code had the same shape) and is not a security boundary — `loa-doctor.sh`
is a local, read-only diagnostic tool with no elevated privileges, and a missing binary at line 245
would simply produce a non-zero exit from the `ajv --version` command substitution, which is already
handled by the `if ajv_ver=$(...) && [[ ... ]]` guard (falls through to the `--help` branch, which
would then also fail harmlessly and resolve to `"unknown (ajv-cli@5+)"`). No action required.

### LOW-2 — Test harness `eval`s an `awk`-extracted function body from the production script

**Location**: `head/tests/unit/bug-725-ajv-version-probe.bats:31-33`

```
31:        eval \"\$(awk '/^_loa_probe_ajv_version\\(\\)/,/^}/' '$PROJECT_ROOT/.claude/scripts/loa-doctor.sh')\"
```

The test extracts `_loa_probe_ajv_version()` out of the shipped script via an `awk` range match and
`eval`s it inside a `bash -c` subshell. This is standard practice for this codebase (the test comment
notes it mirrors an existing bug-899 pattern) and only ever operates on the repository's own
trusted source file under test — it is not reachable with attacker-controlled input and does not
run in production. Flagged for completeness only; no remediation needed. Worth keeping in mind if
this extraction pattern is ever reused against a file path that could be influenced by untrusted
input (e.g., a plugin or user-supplied script), which is not the case here.

## Verification of Fix Correctness

- The `--version` happy path requires both a zero exit status *and* a `X.Y` regex match before
  accepting the output (`head/.claude/scripts/loa-doctor.sh:245`), which correctly rejects ajv-cli@5+'s
  non-zero-exit stderr usage text — the original bug's root cause.
- The `--help` fallback capture (`help_text=$(ajv --help 2>&1 || true)`, line 252) and the parse
  pipeline (`grep -oE ... | head -1 | awk ... || true`, lines 253-256) are both explicitly guarded
  against `set -e`/`pipefail` callers per the in-code comment and BB #916 F1 — verified by
  `bug-725-9` and `bug-725-10` in the bats suite, which simulate a caller with `set -eo pipefail`
  and confirm the function returns the placeholder instead of aborting.
- No new secrets, network calls, credentials, `eval` of untrusted data, or elevated-privilege
  operations are introduced. `ajv` remains a locally-resolved binary gated by a prior `command -v`
  check, consistent with the rest of the file's optional-tool probes (`br`, `sqlite3`).
- Anti-regression test `bug-725-8-source` guards against the exact legacy buggy pattern
  (`ajv --version 2>&1 | head -1`) reappearing on a live code line.

## Security Checklist Status

- [x] No secrets or credentials introduced
- [x] No injection vectors (command, SQL, template) introduced
- [x] No unsanitized external/user input reaches a sink (input is local-tool-only, not user-controlled)
- [x] No privilege escalation or elevated file/network access introduced
- [x] Error handling correctness for `set -e`/`pipefail` callers verified by tests
- [x] Change is scoped to the stated bug; no unrelated modifications
- [x] Test coverage added for the new logic (positive, negative, and edge-case paths)
- N/A Authentication/authorization — not applicable to this diagnostic script

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 2 |

## Verdict

APPROVED - LET'S FUCKING GO

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"sprint_id":"n/a","ts":"2026-09-22T00:00:00Z"} -->
