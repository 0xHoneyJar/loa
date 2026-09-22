# Security Audit Report — bug-725: ajv-cli@5+ version probe fix

**Audit Date**: 2026-09-22
**Auditor**: Paranoid Cypherpunk Auditor (auditing-security skill)
**Scope**: `head.diff` — `.claude/scripts/loa-doctor.sh` (production logic) and
`tests/unit/bug-725-ajv-version-probe.bats` (new test coverage)
**Audit Type**: Ad-hoc PR audit (no sprint plan / beads DB / a2a artifacts present — audited from
`PR.md` + `head.diff` + `base/`/`head/` snapshots per `AUDIT-INSTRUCTIONS.md`)

## Executive Summary

The PR replaces a single-line `ajv --version 2>&1 | head -1` probe (which captured ajv-cli v5+'s
usage-error stderr text as if it were the version string) with a dedicated
`_loa_probe_ajv_version()` helper that: (1) tries `ajv --version` and validates the output looks
like a version number, (2) falls back to parsing `ajv --help` for a `version X.Y.Z` string, and
(3) falls back to a labeled placeholder `unknown (ajv-cli@5+)`. The change is read-only (no
mutations), scoped to a single diagnostic helper in `loa-doctor.sh` (a doctor/health-check script,
not a security-control or trust-boundary component), and ships with 10 new bats tests exercising
v4, v5, no-help-version-line, missing-binary, and two dedicated `set -eo pipefail` regression
tests. All external input is a fixed, hardcoded invocation (`ajv --version`, `ajv --help`) with no
interpolation of untrusted data, and downstream consumption of the resulting string uses
`jq --arg`/`jq --arg` (not string-interpolated JSON), so no injection surface is introduced.

No CRITICAL, HIGH, or MEDIUM findings. One LOW-severity code-quality observation below.

## Findings

### LOW — `--help` version regex may match an unrelated dependency's version string

**Component**: `head/.claude/scripts/loa-doctor.sh:253-256`

```bash
    ajv_ver=$(printf '%s\n' "$help_text" \
        | grep -oE 'version [0-9]+\.[0-9]+(\.[0-9]+)?' \
        | head -1 \
        | awk '{print $2}' || true)
```

**Description**: The fallback parses the *first* occurrence of the literal string `version
X.Y[.Z]` anywhere in `ajv --help` output. If a future ajv-cli release's help text lists a plugin
or dependency version before its own (e.g. `ajv-formats version 2.1.1` preceding `ajv-cli version
6.0.0`), the probe would silently report the wrong version. This is a diagnostic/cosmetic
correctness issue, not a security vulnerability — the value is only ever displayed in
`loa-doctor`'s "optional_tools" health-check output (`head/.claude/scripts/loa-doctor.sh:218`,
routed through `jq --arg` at line 639, never `eval`'d or used in a trust decision).

**Impact**: Misleading version string shown to a developer running `loa-doctor`; no security
impact, no exploitability.

**Remediation (optional, not blocking)**: Anchor the parse to a line containing `ajv` and
`version` together (e.g. `grep -oE '\bajv[a-z-]* version [0-9]+\.[0-9]+(\.[0-9]+)?'`) or take the
first match specifically following the string `ajv-cli`. Not required for this PR to merge; noting
for future hardening if ajv-cli's `--help` output format changes again.

## Verification Performed

- Read the full diff (`head.diff`) and the complete post-change function in context
  (`head/.claude/scripts/loa-doctor.sh:214-261`).
- Confirmed the calling script runs under `set -euo pipefail`
  (`head/.claude/scripts/loa-doctor.sh:33`) and traced both fallback paths for errexit/pipefail
  safety:
  - `ajv_ver=$(ajv --version 2>/dev/null) && [[ ... ]]` — command substitution inside an `if`
    condition does not trigger `-e` on non-zero exit (bash semantics), so a v5+ `ajv --version`
    failure correctly falls through rather than aborting the caller.
  - `help_text=$(ajv --help 2>&1 || true)` — neutralizes a non-zero `--help` exit.
  - The `grep | head | awk || true` pipe neutralizes `pipefail` propagation when `grep` finds no
    match, so the `unknown (ajv-cli@5+)` placeholder is reachable rather than aborting the script.
    This matches BB #916 F1's documented concern and the dedicated regression tests
    (`bug-725-9`, `bug-725-10` in `head/tests/unit/bug-725-ajv-version-probe.bats:181-217`).
- Confirmed no untrusted/attacker-controlled input reaches this code path — `ajv --version` and
  `ajv --help` are fixed, hardcoded invocations of a locally-installed binary already reachable via
  `command -v ajv` (unchanged trust boundary from the pre-existing code).
- Confirmed downstream JSON serialization of the resulting version string uses `jq --arg`
  (`head/.claude/scripts/loa-doctor.sh:639-642`), not string concatenation, so the
  `unknown (ajv-cli@5+)` placeholder (containing parentheses) cannot corrupt JSON output or enable
  injection.
- Confirmed the new test file is additive only, does not modify production code, uses hermetic
  stub binaries on a scoped `PATH`, and does not touch System Zone files outside the two changed
  paths (`.claude/scripts/loa-doctor.sh`, `tests/unit/bug-725-ajv-version-probe.bats`).
- Confirmed the diff's blast radius: 41 lines added/changed in one function of one script, no
  changes to auth, secrets handling, network calls, file writes, or any trust boundary.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 1 |

## Security Checklist Status

- [x] No secrets/credentials introduced
- [x] No authN/authZ logic touched
- [x] No injection surface (fixed command invocations, `jq --arg` for output)
- [x] No new file writes or mutations (doctor script remains read-only per its own doc header)
- [x] No shell-strict-mode (`set -euo pipefail`) violations — fallback paths verified errexit/pipefail-safe
- [x] Test coverage present and exercises the failure modes described in the PR (v4, v5, no-version-line, missing binary, pipefail-guard)
- [x] Diff scoped to stated purpose (ajv version probe fix), no unrelated changes

## Verdict

**APPROVED - LET'S FUCKING GO**

No CRITICAL or HIGH findings (tally: 0/0/0/1). The single LOW finding is a cosmetic
diagnostic-output edge case with no security impact and does not block merge.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"sprint_id":"bug-725","ts":"2026-09-22T00:00:00Z"} -->
