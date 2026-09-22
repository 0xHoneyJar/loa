All good

Approved with noted concerns (non-blocking) — see Adversarial Analysis below.

# PR Review: fix(bug-725): handle ajv-cli@5+ in loa-doctor version probe

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-09-22
**PR:** `head.diff` — `.claude/scripts/loa-doctor.sh`, `tests/unit/bug-725-ajv-version-probe.bats`

---

## Overall Assessment

The fix correctly addresses the root cause: ajv-cli@5+ dropped `--version`, and the old
`ajv --version 2>&1 | head -1 || echo "unknown"` captured the v5 usage-error stderr text as if
it were a version string. The new `_loa_probe_ajv_version()` (`head/.claude/scripts/loa-doctor.sh:228-261`)
replaces that with a three-tier probe (v4 `--version` happy path → v5+ `--help` text parse →
labeled placeholder), extracted into a standalone, independently testable function. The `|| true`
guards on the `--help` capture and the parse pipeline (lines 252, 256) are the right fix for the
`set -e`/`pipefail` interaction the comments describe — I traced both failure paths (help text has
no version line; `ajv --help` itself exits non-zero) by hand and both correctly fall through to the
placeholder instead of aborting the caller. The bats suite (10 cases) exercises the real production
function via `awk` extraction rather than a hand-copied replica, which is the right call for keeping
tests honest.

**Verdict:** APPROVED (with noted concerns — see Adversarial Analysis; none are blocking)

---

## Non-Critical Improvements (Recommended)

### 1. v4 happy path drops the `head -1` truncation every sibling probe keeps

**File:** `head/.claude/scripts/loa-doctor.sh:245`
**Suggestion:** `ajv_ver=$(ajv --version 2>/dev/null)` captures the *entire* stdout of `ajv --version`,
not just the first line. Every other version probe in this file truncates explicitly:
`git` (`:143`, `head -1`), `jq` (`:154`, `head -1`), `yq` (`:169`, `head -1`), `br` (`:199`, `head -1`),
`sqlite3` (`:208`, `head -1`). If a v4-era `ajv --version` ever emits more than one line (a trailing
blank line, a deprecation notice, etc.), the multi-line value flows straight into
`_doctor_add_check "optional_tools" "ajv" "ok" ... "$ajv_ver"` and then into
`display_text="$name ($version)"` (`:550`), embedding a raw newline inside what's assumed to be a
single-line table row.
**Benefit:** A one-token fix (`ajv --version 2>/dev/null | head -1`) restores parity with every
sibling probe and removes the only version-capture in this function that isn't first-line-bounded.
No existing test would catch this today — `bug-725-1`'s stub only ever returns a single line.

### 2. Placeholder can render with doubled parens

**File:** `head/.claude/scripts/loa-doctor.sh:258`, display logic at `:549-559`
**Suggestion:** The placeholder value itself is `"unknown (ajv-cli@5+)"`, and the display formatter
wraps *any* version string in its own parens (`"$name ($version)"`). The rendered line reads
`ajv (unknown (ajv-cli@5+))` — cosmetically odd nested parens. Test `bug-725-3` only asserts on the
raw `ajv_ver=` value, not the final rendered `display_text`, so this wasn't caught. Minor; consider
a placeholder without embedded parens, e.g. `"unknown, ajv-cli@5+"`.

### 3. `awk`-range test extraction is a strict textual contract with the production function

**File:** `head/tests/unit/bug-725-ajv-version-probe.bats:107` (`awk '/^_loa_probe_ajv_version\(\)/,/^}/'`)
**Suggestion:** This works today because the function's signature line starts in column 0 as
`_loa_probe_ajv_version() {` and its body never puts a bare `}` at column 0 before the real close —
verified by hand. It's a reasonable pattern per the comment (matches the existing bug-899
precedent), but it's worth a one-line note that adding *any* nested function or a nested nested-block
`}` on its own column-0 line inside `_loa_probe_ajv_version` would silently truncate the extraction
and desync the tests from what actually ships. Not a blocker — just a fragility worth naming so the
next editor doesn't trip it.

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] No injection surface introduced (no `eval`/interpolation of untrusted `ajv` output into a
      shell command; `$ajv_ver`/`$help_text` are only ever compared, grepped, and printed)
- N/A Authentication/authorization (local diagnostic script only)
- [x] No SQL/XSS vectors
- [x] No new dependencies
- [x] Errors from `ajv` don't leak anything sensitive — worst case is a garbled version string in a
      local doctor report

---

## Code Quality Summary

**Strengths:**
- Root cause correctly diagnosed and fixed (v5's dropped `--version`), not papered over.
- Extraction into `_loa_probe_ajv_version()` makes the fix independently testable without running
  `check_optional_tools`'s side effects — good testability instinct.
- The `set -e`/`pipefail` interaction is genuinely non-obvious and the in-code comments explaining
  *why* the `|| true` guards exist are exactly the kind of comment this codebase's own conventions
  ask for (explains a hidden constraint, not what the code visibly does).
- Test suite has a real positive control (`bug-725-4`, tool absent) and two independent tests for
  the pipefail-abort scenario (`bug-725-9`, `bug-725-10`) plus anti-regression source greps
  (`bug-725-5`, `-6`, `-7`, `-8`) pinning the fix shape so it can't silently regress.
- Fully surgical — only touches the ajv block plus adds the new helper; doesn't touch `br`/`sqlite3`/
  `jq`/`yq` probes even though they share the same `head -1`-truncation pattern this PR partially
  departs from.

**Areas for Improvement:**
- See Non-Critical Improvements above — the `head -1` omission on the v4 path and the
  double-parens cosmetic issue.

---

## Adversarial Analysis

### Concerns Identified (minimum 3)

1. **Correctness (edge case)** — `head/.claude/scripts/loa-doctor.sh:245`
   The v4 `--version` capture is not bounded to the first line, unlike every sibling probe
   (`git`, `jq`, `yq`, `br`, `sqlite3` all pipe through `head -1`). A multi-line `--version` output
   would inject a raw newline into the doctor report's single-line display row.

2. **Display formatting** — `head/.claude/scripts/loa-doctor.sh:258` + `:550`
   The `"unknown (ajv-cli@5+)"` placeholder combined with the `"$name ($version)"` wrapper produces
   nested parens in the rendered output — a real, reproducible cosmetic defect, just not tested at
   the display layer.

3. **Test/production coupling** — `head/tests/unit/bug-725-ajv-version-probe.bats:107`
   The `awk` range-extraction technique ties test correctness to the exact textual shape of the
   function (no bare `}` at column 0 before the true close). It works today but is a latent trap for
   the next person who edits the function without realizing the test harness depends on its literal
   layout.

4. **Unverified real-world assumption** — `head/.claude/scripts/loa-doctor.sh:254`
   The `--help` regex `version [0-9]+\.[0-9]+(\.[0-9]+)?` assumes ajv-cli@5+'s actual `--help` text
   contains the literal substring `version X.Y.Z`. This is plausible (matches the PR's own stub) but
   is not verified against a real installed ajv-cli@5+ binary anywhere in this diff — only against
   hermetic fixtures the author wrote to match their own assumption.

### Assumptions Challenged (minimum 1)

- **Assumption**: ajv-cli@5+'s `--help` output stably includes a `"version X.Y.Z"` substring across
  all 5.x releases, and that this is the most reliable way to recover the installed version.
- **Risk if wrong**: If a given 5.x point release's `--help` text doesn't include that exact
  substring (e.g., it's reformatted, localized, or moved to a `-V` short flag), the probe silently
  degrades to the `"unknown (ajv-cli@5+)"` placeholder — which is a safe failure mode (no garbage
  displayed), but the fix would then provide no more information than before for that release.
- **Recommendation**: The graceful degradation to a placeholder already bounds the blast radius, so
  this is acceptable as shipped. Worth validating once against a real `npm install -g ajv-cli`
  environment before/soon after merge to confirm the `--help` format assumption holds for the
  actual v5/v6 releases in the wild, rather than only against self-authored stub fixtures.

### Alternatives Not Considered (minimum 1)

- **Alternative**: Resolve the version authoritatively via the installed package metadata instead of
  parsing CLI output — e.g. `node -p "require('ajv-cli/package.json').version"` or
  `npm ls -g ajv-cli --depth=0 --json`, walking from `command -v ajv` to its `package.json`.
- **Tradeoff**: This is immune to any future CLI output reformatting (the whole class of bug this PR
  fixes), but adds a dependency on Node/npm being on `PATH` and being able to resolve the global
  install location, which isn't guaranteed for every way `ajv` might land on `PATH` (e.g. a shell
  wrapper, a non-npm install). The current text-parsing approach is more portable at the cost of
  being coupled to CLI output shape.
- **Verdict**: Current approach is a reasonable tradeoff for a "nice-to-have" doctor diagnostic —
  not worth the added Node/npm coupling for a version string that's purely informational. No change
  requested.

### Adversarial Verdict

NON-BLOCKING — all four concerns are edge cases or cosmetic issues with safe failure modes (worst
case is a placeholder string or a minor display artifact, never a crash or misleading "ok" status
for a broken installation). Recommend picking up items 1 and 2 as trivial follow-up polish, but they
don't block approval.

---

## Next Steps

1. Optional follow-up: add `| head -1` to the v4 `--version` capture at
   `head/.claude/scripts/loa-doctor.sh:245` for parity with the other probes in this file.
2. Optional follow-up: adjust the placeholder string to avoid nested parens in the rendered display.
3. No action required before merge — both are non-blocking polish items.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":2},"sprint_id":"pr-10","ts":"2026-09-22T00:00:00Z"} -->
