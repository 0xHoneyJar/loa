# Sprint 2 (global 242) Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1, inline under `/run sprint-plan`)
**Date:** 2026-09-23
**Sprint Reference:** grimoires/loa/sprint.md — Sprint 2: Sectioned artefacts
**Implementation Report:** grimoires/loa/a2a/sprint-242/reviewer.md
**Reviewed commit:** `161ccd9a` · cross-model dissent `adversarial-review.json` (gpt-5.5-pro): `status: clean`, 0 findings, 0 rejected

---

## Overall Assessment

The reader is the right shape — one index pass, one shared cap/footer path, the NOTES default untouched and pinned by the legacy cases — and the byte-budget work is honest (the include measured as net bytes against all ten carriers, trims that keep every rule). I read the three scripts, replayed the reader against this repository's artefacts and hand-built edge files, and traced the upgrade path for both install modes. One functional gap blocks: the vendored (`standard`) install mode `exec`s `update.sh` inside `main()`'s `case`, so the new post-refresh rotation is unreachable for exactly half of the fleet's install shapes, while the report and the migration addendum promise it for "update-loa". Three MEDIUMs are correctness edges in the new addressing; two LOWs are cosmetic.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Upgrade path — rotation unreachable in vendored mode

- **HIGH** (confidence: high) `.claude/scripts/update-loa.sh:551-557` — `standard) … exec "$update_script" "$@"` replaces the process before the `case` ends, so `rotate_oversized_notes` (`:596`, after the `case`) never runs for a vendored install. A vendored repository upgrading with a 200 KiB NOTES.md keeps the file over the line and its first append on the new version is refused by the rc.1 fences — the exact scenario FR-2 AC 4 exists to prevent. `grimoires/loa/sprint.md` Sprint 2 AC: "`update-loa` rotation bats with a generated ≥ 200 KiB fixture" — the fixture proves the submodule path only.
**Required Fix:** run the vendored refresh without `exec`, keep its exit code, run `rotate_oversized_notes` on success, then `exit` with that code (the remaining submodule-only steps stay skipped). Make the vendored script path overridable (`LOA_VENDORED_UPDATE_SCRIPT`) so a bats case can drive `main()` with a stub and prove both the refresh and the rotation ran, and that a failing refresh propagates its code without rotating.

---

## Observations

### 1. Section addressing edges

- **MEDIUM** (confidence: high) `.claude/scripts/notes-guard.sh:131-133` — `Sprint N` uses the boundary `([^0-9]|$)`, so `--section 'Sprint 2'` on a plan that lists `## Sprint 2.5: hotfix` before `## Sprint 2: …` returns the hotfix block (verified on a two-heading file). An implementer would read the wrong acceptance criteria. Boundary should be `([^0-9.]|$)`; add the dotted twin to NG-14.
- **MEDIUM** (confidence: high) `.claude/scripts/notes-guard.sh:84-101,115-124` — the heading is the fifth of six tab-separated fields; a TAB inside a heading shifts `bytes` into field 7, so `--index` prints `0B` and a truncated heading (verified: `## A<TAB>B heading` → `L9-L11  0B  ## A`), and `find_section` cannot match it. Put the heading last and rebuild it from the sixth field onward.
- **MEDIUM** (confidence: medium) `.claude/scripts/notes-guard.sh:137-138` — the substring spec is passed with `awk -v s=…`, which processes backslash escapes; `--section 'A\tB'` searches for a TAB. Pass the spec through `ENVIRON`.

### 2. Cosmetic

- **LOW** (confidence: high) `.claude/scripts/notes-guard.sh:186` — a directory given as `--file` reports "does not exist"; say "is not a regular file".
- **LOW** (confidence: high) `.claude/scripts/notes-guard.sh:92-99` — the per-block byte count adds one newline per line, so a file without a trailing newline over-counts its last block by one byte. Acceptable for a budget hint; note it in the header if not fixed.

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| `notes-guard.bats` matrix (FR-2 AC 1) | Pass | NG-13…NG-21 green; NOTES default pinned by NG-1/2/19 |
| prd/sdd by section ≤ 100 KiB (FR-2 AC 2) | Pass | NG-20 iterates every H2 of the three artefacts |
| budgets + keeplist (FR-2 AC 3) | Pass | max skill 16,354 B; keeplist 3/3; `generate-skill-includes.sh --check` current |
| update-loa rotation bats + addendum (FR-2 AC 4) | Fail | proven for the submodule path only; vendored path never reaches the step (HIGH above) |

---

## Security Checklist

- [x] No secrets; reader only reads the file it is given; rotation archive-first, no stash
- [x] `--file` validated as a regular file (rotate unchanged); reader refuses nothing dangerous because it writes nothing
- [x] No new dependencies; awk/sed/stat as before

---

## Code Quality Summary

**Strengths:** `emit_capped` extraction; `find_section` grammar mirrors the sprint-discovery grep; the include tightening is a better answer than the plan's literal "+≤100 B"; tests run the real repository artefacts.

**Areas for Improvement:** field-separated interchange between awk and bash should keep free text last; `main()` paths that `exec` should be audited whenever a post-step is added.

---

*Generated by Senior Tech Lead Reviewer Agent*
<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":3,"low":2},"excluded":0,"sprint_id":"sprint-242","ts":"2026-09-23T04:40:00Z"} -->
