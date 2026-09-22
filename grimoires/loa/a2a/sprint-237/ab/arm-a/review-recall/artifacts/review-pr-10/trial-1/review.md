All good

Reviewed `fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe` as a standalone PR (no sprint plan / beads / a2a context in this workspace — reviewed against the diff, the surrounding file, and general Loa conventions). Approved with non-blocking concerns noted below.

## Overall Assessment

The fix correctly diagnoses the root cause: `ajv --version 2>&1 | head -1 || echo "unknown"` (base behavior) captured ajv-cli@5+'s usage-error stderr text as if it were a version string, because v5 dropped the `--version` flag/subcommand. The replacement `_loa_probe_ajv_version()` (`head/.claude/scripts/loa-doctor.sh:228-261`) is a three-tier probe (real `--version` → `--help` text parse → labeled placeholder) that is careful about the exact hazard this repository calls out in its own conventions: `set -euo pipefail` (`head/.claude/scripts/loa-doctor.sh:32`) combined with a `grep`-terminated pipe that can return non-zero on "no match." The `|| true` guards at `head/.claude/scripts/loa-doctor.sh:252` and `head/.claude/scripts/loa-doctor.sh:253-256`, and keeping the `ajv --version` probe inside an `if` condition (`head/.claude/scripts/loa-doctor.sh:245`, which is errexit-safe by construction regardless of the `&&` chaining), are correct and deliberate. Test coverage is unusually thorough for a doctor-script patch: hermetic PATH stubs exercise the v4 happy path, the v5 `--help`-fallback path, the "no version line found" placeholder path, the missing-tool control, and two dedicated regression tests for the errexit/pipefail hazard itself (`head/tests/unit/bug-725-ajv-version-probe.bats:224-263`), plus source-level anti-regression checks that the old buggy one-liner does not resurface (`head/tests/unit/bug-725-ajv-version-probe.bats:265-278`). The change is surgical — it touches only the ajv probe and adds tests, nothing else in the 700+ line script is disturbed.

## Adversarial Analysis

### Concerns Identified

1. **Lost `head -1` truncation on the v4 fast path** — `head/.claude/scripts/loa-doctor.sh:245-247`. Every other version probe in this file (`br` at `head/.claude/scripts/loa-doctor.sh:199`, `sqlite3` at `head/.claude/scripts/loa-doctor.sh:208`, `git` at `head/.claude/scripts/loa-doctor.sh:143`, and the *original* ajv probe this PR replaces) pipes through `head -1` to guard against multi-line stdout landing in a single-line "version" field. The new v4-path `ajv_ver=$(ajv --version 2>/dev/null)` captures the entire stdout stream verbatim. If a future ajv-cli release (or an npm update-notifier writing to stdout rather than stderr) emits a second line, that multi-line string flows straight into `_doctor_add_check "optional_tools" "ajv" "ok" ... "$ajv_ver"` (`head/.claude/scripts/loa-doctor.sh:218`) and then into `output_text`'s single-line rendering (`head/.claude/scripts/loa-doctor.sh:489` onward), which is not designed to expect embedded newlines. Low likelihood, but it's a real (and easy) regression versus the surrounding pattern this file otherwise follows consistently.
2. **`--help` text parsing is an assumption, not a verified fact** — `head/.claude/scripts/loa-doctor.sh:253-256`. The fallback assumes ajv-cli@5+'s `--help` output contains a literal `"version X.Y.Z"` substring. This is exercised only against hand-authored bats stubs (`head/tests/unit/bug-725-ajv-version-probe.bats:132-165`), not a captured transcript from a real ajv-cli@5 install. `--help` text is UI copy, not a documented stable interface, and is not guaranteed to keep that exact wording across ajv-cli releases. If it doesn't match, the failure mode is safe (falls to the "unknown (ajv-cli@5+)" placeholder rather than crashing or showing garbage), but the PR's stated goal — "handle ajv-cli@5+" by surfacing its real version — is then only partially met for that release: it degrades gracefully to "unknown" rather than actually resolving the version.
3. **Anti-regression tests rely on very fragile hand-escaped grep patterns** — `head/tests/unit/bug-725-ajv-version-probe.bats:212-218` and `:265-278`. `bug-725-6-source`'s pattern `"version \[0-9\]\+\\\\\.\[0-9\]\+"` requires tracing two layers of escaping (bash double-quote collapsing, then ERE metacharacter escaping) to confirm it actually matches the production regex literal `version [0-9]+\.[0-9]+`. It does match (verified by hand), but a pattern this easy to get subtly wrong — and that would fail silently (always-true or always-false) rather than loudly — is a maintenance hazard for whoever next touches the probe's regex.

### Assumptions Challenged

- **Assumption**: ajv-cli@5+'s `--help` output reliably contains a `"version X.Y.Z"` line that can be parsed with a regex, for all v5.x releases.
- **Risk if wrong**: Not a correctness bug (safe fallback to the labeled placeholder), but a silent under-delivery of the PR's headline promise for real-world v5 installs whose `--help` text doesn't match the assumed shape.
- **Recommendation**: Non-blocking as shipped, since the fallback is safe. Worth validating against an actual `ajv-cli@5` or `@6` install's `--help` output before/soon after merge, and noting in the commit/PR that the `--help` shape was inferred rather than confirmed against upstream.

### Alternatives Not Considered

- **Alternative**: Resolve the installed ajv-cli's version from its `package.json` (e.g. via `npm ls -g ajv-cli --json`, or resolving the `ajv` binary's real path and reading the adjacent package metadata) instead of parsing `--help` prose.
- **Tradeoff**: More robust against `--help` wording changes across releases, since `package.json`'s `version` field is a stable, documented source of truth. But it adds an npm-resolution dependency and more code/edge cases (global vs. local install, non-npm install methods) to a "nice-to-have" doctor check.
- **Verdict**: Current approach is a reasonable, pragmatic choice for an optional diagnostic — parsing `--help` text is simpler and self-contained, and the safe placeholder fallback bounds the downside. Not a reason to hold up this PR.

## Non-Critical Improvements

- Consider re-adding a `head -1` (or equivalent single-line normalization) on the v4 fast path at `head/.claude/scripts/loa-doctor.sh:245-247` to match the defensive pattern used everywhere else in this file, closing the concern above cheaply.
- If/when convenient, capture a real `ajv --help` transcript from an installed ajv-cli@5+ (or @6+) and add it as a fixture-backed test case alongside the current hand-authored stubs, to close the gap between "the regex works against our guess of the format" and "the regex works against the real tool."

## Karpathy / Process Notes

- Simplicity: appropriately scoped — no speculative generality added, the three-tier fallback is exactly what the bug requires.
- Surgical: diff is limited to the ajv probe extraction and its tests; no drive-by changes elsewhere in the 700+ line script.
- Goal-driven: the bug (garbage version text shown for ajv-cli@5+) has a clear, direct regression test (`bug-725-2`, `bug-725-3`) plus two tests specifically targeting the `set -e`/pipefail hazard class this repo has been burned by before (`bug-725-9`, `bug-725-10`), which is good practice given `.claude/rules/stash-safety.md`'s documented history of exactly this class of silent failure elsewhere in the repo.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"sprint_id":"bug-725","ts":"2026-09-22T00:00:00Z"} -->
