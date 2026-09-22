# Security Audit — fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe

**Scope**: `head.diff` (2 files) — `.claude/scripts/loa-doctor.sh` (production probe logic) and new test file `tests/unit/bug-725-ajv-version-probe.bats`.

**Context**: No sprint plan / beads / grimoires artifacts exist in this workspace; audited directly against `PR.md` + `head.diff` + `base/`/`head/` snapshots per `AUDIT-INSTRUCTIONS.md`.

## Summary

This PR replaces a single-line `ajv --version 2>&1 | head -1 || echo "unknown"` probe with a new helper function `_loa_probe_ajv_version()` (`head/.claude/scripts/loa-doctor.sh:228`) that handles ajv-cli's v5+ behavior change (dropped `--version`/`-V`/`version` subcommand). The change is confined to a **read-only diagnostic script** (`loa-doctor.sh` — see its own header at `head/.claude/scripts/loa-doctor.sh:5`: "Design: Read-only checks, educational output, no mutations"). It invokes a locally-installed, user-chosen CLI tool (`ajv`) that is already on `PATH`, parses its stdout/stderr with a bounded regex, and stores the result in an array for later display via `jq -nc --arg` (parameterized, injection-safe — `head/.claude/scripts/loa-doctor.sh:637-641`) or plain variable interpolation in terminal output. No attacker-controlled input reaches this code path in any realistic threat model for this script's usage (a developer running `loa-doctor.sh` locally already trusts every binary on their own `PATH`).

## Findings

None that meet the bar for `critical`/`high`/`medium`. No injection, privilege-escalation, or data-handling defects were found. Two low-severity/quality observations below.

## Observations (excluded from tally — no exploitable path)

1. **`head/.claude/scripts/loa-doctor.sh:253-256`** — The `--help` parse takes the *first* `version X.Y.Z`-shaped match anywhere in `ajv --help` output via `grep -oE 'version [0-9]+\.[0-9]+(\.[0-9]+)?' | head -1`. If a future ajv-cli help screen contained an unrelated "version X.Y" substring (e.g., in a "requires node version 18.0" hint) before the real CLI version line, the probe would report the wrong string. This is a **cosmetic misreporting risk only** — the result is inert diagnostic text, never evaluated or used for a trust decision. Not a security finding; `speculative`/`low confidence`.
2. **`head/.claude/scripts/loa-doctor.sh:245`** — `ajv_ver=$(ajv --version 2>/dev/null)` discards stderr on the v4 path (intentional, matches the documented three-tier design) — no behavior change of concern; noting only that a v4 binary emitting its version on stderr with exit 0 would fall through to the `--help` path rather than the fast path. Purely a UX/coverage nuance, not a defect.

Both observations are non-exploitable display-text nuances in a local, read-only dev-tool script; they do not affect security posture. `excluded: 2`.

## Verification Notes

- Confirmed `_loa_probe_ajv_version` (defined `head/.claude/scripts/loa-doctor.sh:228`) is defined before `main` (`head/.claude/scripts/loa-doctor.sh:692`, invoked `head/.claude/scripts/loa-doctor.sh:747`) and before its only caller `check_optional_tools` (`head/.claude/scripts/loa-doctor.sh:195`) is ever invoked (`head/.claude/scripts/loa-doctor.sh:725`) — no forward-reference/ordering bug.
- Confirmed the `set -e` / `pipefail`-safety claims in the inline comment (`head/.claude/scripts/loa-doctor.sh:239-242`) are correctly implemented: `help_text=$(ajv --help 2>&1 || true)` (`head/.claude/scripts/loa-doctor.sh:251`) and the parse pipeline ending `|| true` (`head/.claude/scripts/loa-doctor.sh:256`) both neutralize non-zero exit codes from `grep`/`awk` before assignment, so a caller running under `set -eo pipefail` cannot abort mid-probe.
- Confirmed downstream consumption is injection-safe: JSON output path uses `jq -nc --arg v "$version"` (`head/.claude/scripts/loa-doctor.sh:637-641`), not string concatenation or `eval`.
- New test file (`tests/unit/bug-725-ajv-version-probe.bats`) exercises the production function directly via `awk` extraction (not a hand-written replica), covering the v4 happy path, v5+ `--help` fallback, placeholder fallback, missing-tool control, and two explicit `pipefail`-abort regression tests (`bug-725-9`, `bug-725-10`). Test design is sound and matches the code under test.
- No changes to any trust boundary, credential handling, network I/O, file-system mutation, or the System/State/App zone model — this PR touches only diagnostic output formatting.

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

## Verdict

**APPROVED - LET'S FUCKING GO**

No security-relevant defects found. The change is a well-scoped, well-tested bugfix to a read-only local diagnostic script, with correct `set -e`/`pipefail` handling and injection-safe downstream consumption.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":2,"ts":"2026-09-22T00:00:00Z"} -->
