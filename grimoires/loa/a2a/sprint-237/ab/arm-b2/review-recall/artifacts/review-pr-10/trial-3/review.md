All good

Sprint {N} has been reviewed and approved. All acceptance criteria met. See Observations below for two non-blocking notes.

**PR:** fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe
**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-09-22

---

## Overall Assessment

The PR replaces the single-line `ajv --version 2>&1 | head -1 || echo "unknown"` probe in `check_optional_tools()` (`head/.claude/scripts/loa-doctor.sh:214-221` pre-change) with a dedicated `_loa_probe_ajv_version()` helper (`head/.claude/scripts/loa-doctor.sh:228-261`). The bug was real: ajv-cli v5+ removed `--version`/`-V` and exits non-zero with a usage error on stderr, and the old code's `2>&1` merged that error text into stdout, so `loa-doctor` displayed the literal error message as the "version."

I traced the new function by hand against all four behavioral branches (v4 happy path, v5 with a parseable `--help`, v5 without one, and the errexit/pipefail interaction the PR calls out) and it holds up:

- `ajv_ver=$(ajv --version 2>/dev/null) && [[ "$ajv_ver" =~ ^[0-9]+\.[0-9]+ ]]` (`head/.claude/scripts/loa-doctor.sh:245`) discards stderr and requires the captured text to actually look like a version, so v5's usage error can no longer leak through even though the file is under `set -euo pipefail` (`head/.claude/scripts/loa-doctor.sh:33`) — the check runs inside an `if` condition, where errexit never fires regardless of exit code.
- The `--help` fallback pipeline (`head/.claude/scripts/loa-doctor.sh:253-256`) is correctly guarded: `help_text=$(ajv --help 2>&1 || true)` neutralizes a non-zero `ajv --help` exit, and the trailing `|| true` on the `grep | head | awk` pipe neutralizes `grep`'s exit 1 on no-match before `pipefail` can propagate it up through `set -e`. I confirmed this is a real hazard class (bash's `pipefail` reports the pipeline's status as the rightmost command that exited non-zero, which here is `grep`, not `head`/`awk`) and confirmed the guard actually closes it.
- Final fallback to the literal `"unknown (ajv-cli@5+)"` placeholder (`head/.claude/scripts/loa-doctor.sh:257-258`) means the check never regresses to a hard failure — worst case is an uninformative but harmless string.

I manually re-derived what each of the four bats fixtures (`head/tests/unit/bug-725-ajv-version-probe.bats:117-263`) exercises and matched it against the traced behavior above; all four align. I could not execute the suite directly (no `bats` binary in this sandbox and shell execution was gated), so I hand-validated the trickiest regex instead: the source-anchor test at `head/tests/unit/bug-725-ajv-version-probe.bats:156` (`grep -qE "version \[0-9\]\+\\\\\.\[0-9\]\+" ...`) does match the literal `version [0-9]+\.[0-9]+(\.[0-9]+)?` text present at `head/.claude/scripts/loa-doctor.sh:254` — verified with a standalone `grep -E` invocation against the real file rather than trusting the escaping by eye.

No security concerns (no secrets, no injection surface — this only shells out to a locally-resolved `ajv` binary the same way the pre-existing code did), no zone violations (this is a legitimate, self-contained fix to the framework's own doctor script), and the diff is surgical: it touches only the one probe and adds a test file, no unrelated refactoring.

**Verdict:** APPROVED

---

## Observations

### 1. Unverified assumption about ajv-cli's `--help` text

- **LOW** (confidence: low) `head/.claude/scripts/loa-doctor.sh:249-254` — the v5+ fallback assumes `ajv --help` prints a literal `version X.Y.Z` line; I do not have network access in this environment to confirm that against the real `ajv-cli@5+` package, so I can't independently verify the assumption the PR description states as its own finding. If the real `--help` text formats the version differently (e.g. `ajv-cli/5.6.0` with no word "version"), the parse would simply fail to find a match and correctly fall through to the `"unknown (ajv-cli@5+)"` placeholder (`head/.claude/scripts/loa-doctor.sh:257-258`) — a display-quality miss, not a functional regression, since the surrounding code already treats "unknown" gracefully. Non-blocking; worth a one-time manual confirmation against a real `ajv-cli@5+` install if convenient.

### 2. Optional-tool status stays "ok" even when the version is genuinely unknown

- **LOW** (confidence: medium) `head/.claude/scripts/loa-doctor.sh:218` — when `_loa_probe_ajv_version` falls all the way to the `"unknown (ajv-cli@5+)"` placeholder, `check_optional_tools` still records status `"ok"` (as it did before this PR for the `"unknown"` placeholder). This is defensible — `ajv` is genuinely installed and usable, only the version string is unknown — but a `warn`/`info` status alongside the placeholder text would make `loa-doctor`'s output more informative for a user seeing the vague version. Cosmetic; not a functional defect and outside the stated scope of bug-725 (which was specifically about not displaying garbage, not about status severity).

---

## Code Quality Summary

**Strengths:**
- Clear three-tier fallback with each tier's rationale documented inline, including the specific `pipefail`/`errexit` interaction being guarded against (`head/.claude/scripts/loa-doctor.sh:237-242`).
- Test coverage is thorough for a shell-script fix: happy path, both fallback branches, a positive control for the "not installed" case, two dedicated regression tests for the pipefail hazard (stub `--help` with no match, and stub `--help` itself failing), and two source-level anti-regression greps (one confirming the fix's markers are present, one confirming the old broken one-liner did not resurface).
- The extraction into a standalone `_loa_probe_ajv_version()` function is exactly the right shape for testability — the bats harness sources the real function via `awk` extraction rather than re-implementing the logic, so the tests validate production code, not a parallel reimplementation.

**Areas for Improvement:**
- None blocking. See Observations above for two minor, non-blocking notes.

---

## Next Steps

None required for merge. The two Observations above are optional follow-ups, not gating.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"excluded":0,"sprint_id":"pr-10","ts":"2026-09-22T00:00:00Z"} -->
