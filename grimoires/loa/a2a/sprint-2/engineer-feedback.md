All good

Sprint 264 has been reviewed and approved. Observations documented and non-blocking; one dissent round fixed before approval.

# Sprint 264 Review Feedback

**Reviewer:** Fable 5.1 lead (reviewing-code contract; dissent via adversarial-review.sh)
**Date:** 2026-10-20
**Sprint Reference:** grimoires/loa/sprint.md § Sprint 2 (global 264)
**Implementation Report:** grimoires/loa/a2a/sprint-2/reviewer.md

---

## Overall Assessment

Sprint 264's code is small and well-fenced: four review-catch arms declared exactly as the SDD specifies, a validator that takes its vocabulary from the libraries that implement the toggles and rules, an evaluation-only guard that fires before any run directory exists, and a suite root that is a byte-identical copy with one declared change. The arm smoke proved every took-effect rule on every arm and met the batch-entry gates; it also surfaced the first Fable refusal fallback in 44 review-catch rows (KF-051), now handled by the pre-registration rather than by retrying.

The review dissent (gpt-5.5-pro + claude-headless; run 1 of this sprint's three) returned four advisories and no blocker; two were fixed in round r2a (`c0d42907`: the guard also keys on `oracle_open: true` and refuses a non-boolean `eval_only`; the report names evaluation-only arms and their row counts), one was a path exclusion of the dissent driver (the task files are in the commit), one is a maintenance bead (bd-gdl5s). Approved.

**Verdict:** APPROVED (observations documented and non-blocking)

---

## Observations

### 1. Batch-context variable is a convention, not a boundary (pipeline-run.sh)

- **LOW** (confidence: high) `evals/harness/pipeline-run.sh` — `LOA_ABLATION_BATCH_CONTEXT=1` keeps the open-mount arm off any by-hand `pipeline-run.sh` invocation; any operator can set it. That is the intended level (no production surface, not a security boundary) and the header says so.
**Suggestion:** none beyond the header note; the arm is also `eval_only` in the suite and absent from `priority`.

### 2. Rule ids read from took-effect.sh by regex (validate-suite.sh)

- **LOW** (confidence: high) `evals/harness/validate-suite.sh` — the known rule ids are the `rule_<id>()` function names of the script beside it; a rule defined another way (a dispatch table) would silently vanish from the vocabulary and every suite would fail validation loudly (die when none found).
**Suggestion:** a bats case asserting the extracted set contains the suite's rules (VS-14 covers it indirectly).

### 3. Process control in an implementer run

- **LOW** (confidence: high) the implementer ran an unfiltered `pkill -f bats-exec` while stopping its own test run (self-reported); no lead run was affected. Brief rule for future sprints: signal only PIDs you started.

### 4. Report components exclude eval_only arms (DEC-0646)

- **LOW** (confidence: high) `evals/harness/ablation-report.py` — nine components with the cycle-131 control arms; AR-12/AR-23 pins updated; the cycle-130 report file is not regenerated.

### 5. Refusal fallback (KF-051)

- **MEDIUM** (confidence: high) a Fable review session refused (category `cyber`) and ran on Opus 5.5 for the rest of the phase — a model confound inside a "Fable" cell. Handled by the pre-registration (excluded from R5, degraded elsewhere); worth a row-level `models_used` summary in the report's sensitivity table.

## Adversarial dissent (run 1 of three for this sprint)

| Run | Diff | Voices | Findings | Blocking | Disposition |
|---|---|---|---|---|---|
| review 1 | `e93a040a..0281ea57` (13 files, 629 lines) | gpt-5.5-pro + claude-headless, both succeeded | 4 advisories | 0 | C-002 and C-004 fixed in r2a `c0d42907` (pipeline-run.bats case; AR-12 line); C-001 refuted with evidence (`git show --stat 0281ea57` lists the six task files; the dissent driver excludes `grimoires/loa/evals/*/tasks/*` by design); C-003 → bead bd-gdl5s |

Envelope: `grimoires/loa/a2a/sprint-2/adversarial-review.json` (copied from `a2a/sprint-264/`, where it ran under `--sprint-id sprint-264`).

## Rejected dissent payloads

The run's sidecar holds no rows.


---

## Acceptance Criteria Check

See `grimoires/loa/a2a/sprint-2/reviewer.md` § AC Verification: FR-5 AC 1–2 met (arm smoke 4/4 with every rule true); FR-6 AC 1–3 and the one-pin criterion are Task 2.4/2.5 items read after the batches; budget amended by DEC-0645.

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation: suite arms validated for toggle vocabulary (type-exact), rule ids and `eval_only`; `oracle_open ⇒ eval_only`
- [x] No new network calls or dependencies
- [x] The open-mount arm cannot run outside a runner batch or smoke
- [x] Tests cover the new paths (VS-14 … VS-17, pipeline-run +6, RAB-c131-5); evals/tests 528/529 integrated (the one failure a /tmp-contention artefact, green alone)

---

## Code Quality Summary

**Strengths:** the refusal happens before any run directory exists; the validator takes its vocabulary from the libraries that implement it; the suite root is a byte-identical copy with one declared change and a README that names every deviation.

**Areas for Improvement:** observations 2 and 3.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":1,"low":4},"excluded":0,"sprint_id":"sprint-264","ts":"2026-10-20T03:49:43Z"} -->
