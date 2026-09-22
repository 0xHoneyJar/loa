# Sprint 3 Review Feedback — round 1

**Reviewer:** Senior Tech Lead Reviewer Agent (Fable 5.1 lead acting as gate; independent input: cross-model dissent, gpt-5.5-pro, four diff chunks)
**Date:** 2026-09-22
**Sprint Reference:** grimoires/loa/sprint.md (Sprint 3, global sprint-237)
**Implementation Report:** grimoires/loa/a2a/sprint-237/reviewer.md

---

## Overall Assessment

The range `da3bd07f..2d82eb40` delivers what the sprint promised mechanically: the budget tool and its gates are green on the live tree (`tools/check-prompt-budget.sh --json` → `ok: true`; largest skill 16,359 B, `CLAUDE.loa.md` 10,222 B, protocols 199,313 B), the no-history and keep-list gates hold, registry-rendered blocks regenerate byte-identically, the 32 parity goldens verify, the reminder hooks are untouched (`git diff 80be4b0f..HEAD -- .claude/hooks` is empty), and every fence and contract name I spot-checked survives in the audited skills (`adversarial-review-gate.sh`, `LOA_ADVERSARIAL_REVIEW_ENFORCE`, `verdict-derive.sh`, `validate-ac-verification.sh`, `run-mode-ice.sh`, `danger-level-enforcer.sh`, the Implementation Guard, the qmd steps, the Flatline invocations). The A/B is real, reproducible from `ab/`, and — this is the strongest part of the report — honest about what it did not achieve: review recall recovered to within tolerance only after one iteration, one clean-PR HIGH remains, and the audit token gate was missed by a wide margin because the gate assumed something false about where tokens go. The report says so in the AC row rather than behind a passing composite.

Two things block approval, both process rather than code. First, the Unreleased section of `CHANGELOG.md` carries Sprint 1 and Sprint 2 entries only; the largest change set of the cycle (the audit, the budget gates, the eval harness, the coverage-first prompts, the effort wiring) has no line, and the documentation rule this skill enforces makes a missing CHANGELOG entry per task blocking. Second, AC-9.2 is reported as partially met with three `✗` sub-gates whose follow-ups are beads; the skill's own automatic rule requires a `✗` to carry a scope-split to a follow-up sprint task, and beads are not visible from the sprint plan. Both are cheap to fix and neither touches `.claude/`, so the A/B record stays valid.

The cross-model dissent raised three BLOCKING findings across four chunks; I verified each against the tree and the artifacts. One is refuted by evidence (the eval executor's tool list — 58 of 61 recorded writes in the A/B rows are `Edit` calls, so the tool was available), two are real but pre-existing at the branch base and outside this range's diff (a frontmatter zone manifest that disagrees with its skill body; a registry-rendered phase sequence that names phases the skill never defined). They are recorded below as observations with beads to file.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Documentation

- **HIGH** (confidence: high) `CHANGELOG.md:3-30` — the `## [Unreleased]` section has no entry for any Sprint 3 task; a reader of the next release notes would not learn that 13 skill prompts, 27 protocols and `CLAUDE.loa.md` changed shape, that a prompt byte budget now gates CI, or that an eval A/B harness exists. The Documentation Verification rule in this skill lists "a CHANGELOG entry per task" as blocking.
**File:** `CHANGELOG.md:3`
**Issue:** Sprint 1 (`feat(catalog)`, ledger isolation, adaptive thinking) and Sprint 2 (wire schemas, `--json-schema`, dissent consumption) are described; Sprint 3 (`72bdb7d2` … `f19dd6d0`) is not.
**Why This Matters:** the post-merge pipeline writes release notes from this section; the operator reviewing the draft PR reads it first; the prompt diet is the most user-visible change in the cycle (every skill reads differently).
**Required Fix:** add Unreleased entries covering the budget gates + keep list + CI workflow, the 49-unit audit (kernel, archivals, protocols total, resources/ moves, new auditor agents), coverage-first review/audit + `excluded` trailer fields + effort dispatch, the eval A/B harness with the measured outcome, and the Sprint 1 fallout fixes (ceiling probe restore, live probe rename, compare.sh JSONL read).

### 2. Acceptance criteria scope-split

- **HIGH** (confidence: high) `grimoires/loa/a2a/sprint-237/reviewer.md:48-60` — AC-9.2 is marked `◐ Partially met` with three `✗` rows (review clean-PR false positives 0.167 vs 0, audit tokens 0.758 vs ≤ 0.5, the implement composite vacuous at 0/0) whose follow-ups are beads bd-a4td / bd-gvxy / bd-azrr only; nothing in `grimoires/loa/sprint.md` names them, so the residual is invisible to the next sprint's planner and the plan's own success metrics (`recall B ≥ A per defect; false positives B ≤ A; audit tokens B ≤ 0.5 × A`) read as simply unmet.
**File:** `grimoires/loa/sprint.md:151` (the untouched sprint-level AC row) and `:164-165`
**Issue:** the skill's automatic-CHANGES_REQUIRED rule ("`✗ Not met` without a scope-split to a follow-up sprint task") is what this row triggers; the honesty of the report is not in question, the traceability is.
**Why This Matters:** a partially met gate without a plan-level split is how a residual gets forgotten between cycles; the A/B gates are the only quality evidence for a 60 % prompt cut.
**Required Fix:** record the scope-split in `grimoires/loa/sprint.md` — a "Sprint 3 follow-ups (carried out of cycle)" block under Sprint 3 naming the three residuals with their beads and the concrete next action for each (severity-calibration re-measure on a widened corpus; token gate re-specified against prompt-attributable tokens; a test-first fixture that can actually pass) — and point the AC-9.2 row in `reviewer.md` at it. Do not tick the sprint-level AC row; the report already says why.

---

## Observations

### 1. Cross-model dissent, verified against the tree

- **MEDIUM** (confidence: high) `.claude/skills/implementing-tasks/SKILL.md:26-28` — frontmatter `zones.app.permission: read` while the body's Zone Constraints say the app zone is **Read/Write** and the objective is to implement code (dissent chunk 4, DISS-001). Identical at the branch base `80be4b0f`; no hook or script reads `zones.app.permission` (`grep -rn 'zones\.app' .claude/hooks .claude/scripts` finds nothing), so nothing enforces the manifest today. Pre-existing and outside this range's diff — file a bead to align the manifest (`read-write`) or make the validator flag body/manifest disagreement.
- **MEDIUM** (confidence: high) `.claude/skills/autonomous-agent/SKILL.md:48` — the registry-rendered constraint "Each phase MUST complete sequentially: 0→1→2→3→3.5→4→4.5→5→6→6.5→7→8" names phases 3.5, 6.5 and 8 that the skill does not define and omits 5.5, which it does (dissent chunk 4, DISS-002). The sequence lives in the `@constraint-generated` block from `.claude/data/constraints.json` and was byte-identical at the base; the audit copied it through as it must. Pre-existing registry/prose drift — file a bead to correct the sequence in `constraints.json` (`0→1→2→3→4→4.5→5→5.5→6→7`) and regenerate.
- **LOW** (confidence: high) `evals/harness/execute-agent.sh:159` — `--allowed-tools "Read,Grep,Glob,Write"` omits `Edit` while the transcript extractor records `Edit`/`MultiEdit` writes (dissent chunk 1, DISS-001, raised as blocking). Refuted as a failure: `--permission-mode acceptEdits` auto-accepts edits regardless of the list, and the A/B rows record 58 `Edit` and 3 `Write` calls across 30 implement trials with `tests_pass` 15/15 in both arms. Still worth aligning the flag with the extractor so the comment on `:21` stops being wrong.

### 2. Complexity

- **MEDIUM** (confidence: high) `evals/harness/compare-ab.py:111-176` — `main()` is 66 lines and `summarize()` (`:51-108`) 58 lines, both new in this range and over the 50-line threshold with no in-code justification. `SIMPLICITY[shrink]`: either split gate evaluation out of `main()` or add the one-line justification the rule asks for. Not a correctness risk — BF-6..BF-9 pin the behaviour.

### 3. Measurement

- **MEDIUM** (confidence: high) `evals/fixtures/implement-tasks/expectations/01.json` … `05.json` — the implement-discipline composite is 0/15 in both arms because `test_first` requires a write under `tests/` before the first write under `src/` and no Sonnet 5 trial did that; the gate `B ≥ A` therefore passes on `0 ≥ 0` and cannot detect a regression in the metric it exists for. The per-check breakdown in the report (surgical 15/15 → 13/15) is the useful signal; the fixture set needs at least one task where test-first is the natural path, or the composite should not be `all_must_pass` for this suite (bd-azrr covers the prompt side, not the fixture side).
- **LOW** (confidence: medium) `grimoires/loa/a2a/sprint-237/ab/compare/review-recall.b2.json` — one high-severity finding on a clean PR in one of six clean trials after the iteration. The finding itself (`butterfreezone-validate-route-false-positive.bats:39`, a fixture route the regex never extracts) is a real observation about test adequacy; high is the wrong severity for it under the calibration sentence the iteration added, which suggests the sentence is not yet strong enough, not that the reviewer is wrong to notice.

### 4. Loose ends the audit inherited

- **LOW** (confidence: high) `.claude/skills/simstim-workflow/SKILL.md` — references a "Phase 6.5" that no section defines (the auditor flagged it as pre-existing and left it). Fold into the same bead as the autonomous-agent sequence.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 3.9: Sprint 3 report | Incomplete | CHANGELOG entries; scope-split of the AC-9.2 residual into the sprint plan |

---

## Acceptance Criteria Check

| Criterion | Status | Notes |
|-----------|--------|-------|
| AC-8.1 budget tool + CI gate | Pass | `check-prompt-budget.sh:53` limits; PB-1..PB-9 green on the live tree; sentinel controls in the workflow |
| AC-8.2 no history in rule text | Pass | NH-1..NH-3 green; MUST/NEVER lines carry their mechanism in every unit report I sampled (reviewing-code, auditing-security, implementing-tasks, run-mode, autonomous-agent) |
| AC-8.3 keep list, archived reports, generated sections, refs, validators, goldens, reminder fence | Pass | 49 reports present; `generate-constraints.sh --dry-run` / `generate-skill-includes.sh --check` clean; PR-1..PR-3 green after checksum regen; 36/36 skills validated; `capture.sh --verify` 32/32; hooks untouched |
| AC-9.1 coverage-first + `excluded` + effort | Pass | `### Coverage` in all four files; `grep -c '≥3 concerns'` = 0; VO-1..VO-11 and ED-1..ED-10 green |
| AC-9.2 A/B | Fail (partial, honestly reported) | review recall ✓ after iteration; review FP ✗ 0.167; audit recall/FP ✓; audit tokens ✗ 0.758; discipline vacuous — scope-split required (Changes Required 2) |
| AC-9.3 suites green | Pass | 38 unit red = 30 pre-existing + 8 time-dependent licence fixtures (green after regeneration); adapter pytest 2276/0; integration 101/101 |
| Sprint-level: validators/lints/bats; dry-run diff empty | Pass | as above |
| Sprint-level: 10 constraint twins gone; `no-backup-files.yml` extended | Pass | `no-constraint-temp-files.bats` green |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (a2a deliverables scanned for `sk-ant-`, `AKIA`, `ghp_`, `ANTHROPIC_API_KEY=` before force-add — none)
- [x] Input validation: eval executor materializes the prompt tree from a pinned sha and records dirty state; graders read hidden manifests never copied into the sandbox
- [x] Fence patterns unchanged (`git diff 80be4b0f..HEAD -- .claude/hooks` empty); fence *documentation* shrank only where the keep list allows
- [x] No SQL/XSS surface in this range
- [x] Dependencies: none added
- [x] Error messages: the dissenter's stderr and the executor's `agent-stderr.log` carry no credentials

---

## Code Quality Summary

**Strengths:**
- The lead gate (generated-block splice, keep-list grep, protected-string re-read, history scan, byte target) turned a 49-unit prompt rewrite into something mechanically checkable; three auditor deletions that a test or a fence rule protects were caught and restored before landing.
- The A/B is valid by its own rules (one tree per arm, `prompt_tree_dirty: false`, same model id) and the two dirty rows were discarded rather than explained away.
- Sprint 1 fallout (the ceiling-probe clobber) was found by running the whole suite and fixed by restoring the original bytes, not by rewriting the tests.

**Areas for Improvement:**
- Run the full unit suite before an A/B arm starts and never during one — two arm-B rows had to be discarded for exactly this.
- The token gate and the discipline composite were specified without checking what they could measure; both need re-specification (beads filed).

---

## Next Steps

1. Add the Sprint 3 CHANGELOG entries and the sprint-plan follow-up block (Changes Required 1 and 2).
2. File the three beads named in Observations 1 and 4; align `execute-agent.sh --allowed-tools` with its extractor; justify or split the two `compare-ab.py` functions.
3. Update `grimoires/loa/a2a/sprint-237/reviewer.md` (AC-9.2 row → follow-up block; testing summary unchanged) and request another review via `/review-sprint sprint-3`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":4,"low":3},"excluded":0,"sprint_id":"sprint-3","ts":"2026-09-22T06:20:00Z"} -->
