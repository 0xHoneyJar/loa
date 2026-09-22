# Security Audit Report — fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe

**Audit date**: 2026-09-22
**Auditor**: auditing-security skill (paranoid cypherpunk auditor)
**Scope**: `head.diff` — `.claude/scripts/loa-doctor.sh`, `tests/unit/bug-725-ajv-version-probe.bats`

## Executive Summary

This PR replaces a single-line `ajv --version 2>&1 | head -1 || echo "unknown"` probe (which
misreported ajv-cli v5+ usage-error stderr text as a version string) with a new
`_loa_probe_ajv_version()` helper that tries `ajv --version` first, falls back to parsing
`ajv --help` output, and finally falls back to a labeled placeholder. The change is small,
self-contained to a diagnostic/read-only tool (`loa-doctor.sh`), and ships a 10-case bats
regression suite exercising both the happy path and the `errexit`/`pipefail` interaction the
prior BB #916 review flagged (F1).

No command injection, path traversal, privilege, or data-exposure issues were found. The probed
version string is always consumed as a `printf`/`jq --arg` **argument**, never as a format string
or shell-evaluated value, so untrusted-looking `ajv --help` output cannot escalate to code
execution or JSON corruption. The `errexit`/`pipefail` interaction that the referenced BB #916 F1
finding called out is correctly closed in this diff (`|| true` guards on both the `--help`
capture and the parsing pipeline), and is exercised end-to-end by `bug-725-9`/`bug-725-10`.

**Overall Risk Level: LOW**

## Key Statistics

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 1 |
| Info | 1 |

## Findings

### LOW-1: Sibling `br`/`sqlite3` probes retain the same fragile single-line pattern the PR just fixed for `ajv`

- **Component**: `head/.claude/scripts/loa-doctor.sh:199` (`br_ver=$(br --version 2>&1 | head -1 || echo "unknown")`) and `head/.claude/scripts/loa-doctor.sh:208` (`sqlite_ver=$(sqlite3 --version 2>&1 | head -1 | awk '{print $1}')`)
- **Description**: The bug this PR fixes (bug-725) was exactly this shape: a tool changes its CLI surface (drops/alters `--version`), the `2>&1 | head -1` pattern silently captures stderr usage-error text and displays it as if it were a version. `br` and `sqlite3` still use this brittle pattern. `sqlite3`'s variant is additionally slightly worse: it has no `|| echo "unknown"` fallback at all if the whole pipeline exits non-zero in a context where that mattered (though under the script's global `set -euo pipefail`, this specific call is fine today only because `sqlite3 --version` conventionally exits 0).
- **Impact**: Cosmetic/informational only (`loa-doctor` is a read-only diagnostic tool; worst case is a misleading version string in `--json`/text output). Not exploitable.
- **Why LOW and not part of this PR's required scope**: Neither `br` nor `sqlite3` is touched by this diff, and the PR's stated scope is the ajv regression (bug-725). Flagging for awareness, not blocking.
- **Remediation**: When either tool's CLI next changes shape, apply the same three-tier `_loa_probe_*_version()` extraction pattern this PR just established for ajv. No action required for this PR to merge.

### INFO-1: Test harness `eval`s a script fragment extracted via `awk`

- **Component**: `head/tests/unit/bug-725-ajv-version-probe.bats:35` (`eval "$(awk '/^_loa_probe_ajv_version\(\)/,/^}/' '$PROJECT_ROOT/.claude/scripts/loa-doctor.sh')"`)
- **Description**: The test extracts the production function body from the tracked, first-party `loa-doctor.sh` via `awk` range-match and `eval`s it inside a `bash -c` subshell to test the real implementation instead of a hand-copied replica (this is explicitly called out as a BB #916 F-001 closure in the comments). The extracted source is first-party and already committed to the repo at test time — not attacker-influenced input — so this is not an injection vector.
- **Impact**: None under current usage. Noted only because `eval` on dynamically-derived text is a pattern worth a second look in any audit; here the "dynamic" text is just the developer's own script re-sliced by line range, equivalent in trust level to `source`-ing the file.
- **Remediation**: None required. Informational note only.

## Security Checklist Status

- [x] No secrets, credentials, or tokens introduced or logged
- [x] No user-controlled input reaches a shell/eval sink (probe only reads local `ajv` binary output)
- [x] No path traversal / file-write surface changed
- [x] Version string only ever flows into `printf '%s' ARG` / `jq --arg` (never as a format string, never `eval`'d, never concatenated into a command line)
- [x] `set -e` / `pipefail` interaction reviewed — `|| true` guards close the abort-before-placeholder-assignment gap (BB #916 F1); verified in-diff via test cases `bug-725-9` and `bug-725-10`
- [x] New function's only external dependency (`ajv`) is invoked with fixed, literal flags (`--version`, `--help`) — no user input reaches argv
- [x] Regression tests use hermetic PATH-stubbed fixtures, no network/filesystem side effects outside `mktemp -d`
- [x] Anti-regression test (`bug-725-8-source`) guards against the exact legacy vulnerable-looking pattern reappearing on a code line
- [x] Change is confined to a read-only diagnostic script; no framework/System Zone semantics altered beyond the one function body

## Threat Model Summary

`loa-doctor.sh` is a local, read-only health-check script. The `_loa_probe_ajv_version` function
executes a fixed, non-attacker-controlled binary (`ajv`, resolved via `command -v` from the
invoking user's own `PATH`) with two hardcoded flags and parses its stdout/stderr with `grep`/`awk`
using fixed patterns. There is no remote input, no privilege boundary crossed, and no persistence
of the parsed value beyond in-memory arrays consumed by the same script's own text/JSON
formatters (which treat the value as a plain argument, not code). The realistic worst case of a
parsing bug here is a wrong or garbled string shown to the user in a diagnostic report — not
memory corruption, injection, or privilege escalation.

## Recommendations

- **Immediate (before merge)**: None. No blocking issues found.
- **Short-term**: Consider backporting the `_loa_probe_*_version()` pattern to `br`/`sqlite3` the next time either tool's version-flag output changes shape (see LOW-1) — proactive, not required.
- **Long-term**: None specific to this change.

## Verdict

**APPROVED - LET'S FUCKING GO**

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"sprint_id":"bug-725","ts":"2026-09-22T00:13:12Z"} -->
