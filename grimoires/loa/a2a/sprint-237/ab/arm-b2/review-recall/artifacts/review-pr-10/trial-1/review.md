All good

Sprint reviewed and approved. See below for review of PR "fix(bug-725): handle ajv-cli@5+ in
loa-doctor version probe". Observations documented and non-blocking. See Observations below.

# PR Review: fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-09-22
**Scope:** `head.diff` — `.claude/scripts/loa-doctor.sh`, `tests/unit/bug-725-ajv-version-probe.bats`

---

## Overall Assessment

The fix replaces a single-line `ajv --version 2>&1 | head -1` probe (which captured ajv-cli@5+'s
usage-error stderr text as a fake "version") with a three-tier `_loa_probe_ajv_version()` helper:
try `--version` and validate it looks numeric, fall back to parsing a `version X.Y.Z` token out of
`--help`, and finally fall back to a labeled placeholder. The new helper is extracted for
testability and correctly guards the `--help`-parsing pipe against the script's own
`set -euo pipefail` (`head/.claude/scripts/loa-doctor.sh:33`) — grep's exit 1 on no-match would
otherwise abort the caller under pipefail before the placeholder could be assigned, and the code
explicitly handles that (`head/.claude/scripts/loa-doctor.sh:252-256`). The accompanying bats
suite exercises the real production function (via `awk` extraction, not a hand-written replica),
covers the v4 happy path, the v5+ `--help`-fallback path, the placeholder path, a missing-binary
control, and two explicit regressions for the errexit/pipefail interaction (BB #916 F1). This is a
well-scoped, well-tested bug fix with no security, correctness, or complexity issues that rise to
blocking.

**Verdict:** APPROVED

---

## Observations

### 1. Fragility of `--help` version-string parsing

- **LOW** (confidence: low) `head/.claude/scripts/loa-doctor.sh:253-256` — the regex
`version [0-9]+\.[0-9]+(\.[0-9]+)?` scans the entire captured `--help` (stdout+stderr) text for
the first token matching `version X.Y[.Z]`. If a future ajv-cli version's help text contains an
unrelated `version N.N` string before its own version line (e.g. a Node.js engine requirement
line), the probe could silently report the wrong number instead of falling through to the
placeholder. Impact is cosmetic (a diagnostic/doctor display value, not a control-flow input), and
the failure mode degrades to a misleading-but-harmless string rather than a crash, so this is
non-blocking. Worth a short follow-up test fixture if ajv-cli's actual v5+ `--help` text is ever
confirmed to include multiple `version` tokens.

### 2. Minor test redundancy

- **LOW** (confidence: high) `head/tests/unit/bug-725-ajv-version-probe.bats:172` and
`head/tests/unit/bug-725-ajv-version-probe.bats:199` — tests `bug-725-3` and `bug-725-9` both stub
`--help` output with no `version` line and assert the same placeholder outcome; `bug-725-9`'s
docstring frames it as covering the BB #916 F1 pipefail path specifically, but `bug-725-3` already
exercises the same code path under the same `set -eo pipefail` harness (`_run_probe`). Harmless
duplication, not a defect — leaving both is fine for anti-regression coverage, but they could be
merged if the suite grows unwieldy.

---

## Code Quality Summary

**Strengths:**
- Correctly reasons about `set -e`/`pipefail` interaction and guards it explicitly, with comments
  that state the invariant being protected (`head/.claude/scripts/loa-doctor.sh:237-242`).
- Extracted the probe into a standalone, single-purpose function under the existing 50-line
  complexity budget, with only two levels of nesting.
- Tests hit the real production code path (via extraction) rather than a reimplementation, and
  include a source-level anti-regression test (`bug-725-8-source`) that fails if the old
  single-line buggy pattern ever reappears on a live code line.

**Areas for Improvement:**
- None blocking. See Observations above for two low-severity, non-blocking notes.

---

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":2},"excluded":0,"sprint_id":"pr-10","ts":"2026-09-22T00:00:00Z"} -->
