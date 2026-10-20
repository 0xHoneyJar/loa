All good

Sprint 263 has been reviewed and approved. Observations documented and non-blocking; two dissent rounds fixed before approval.

# Sprint 263 Review Feedback

**Reviewer:** Fable 5.1 lead (reviewing-code contract; dissent via adversarial-review.sh run 1)
**Date:** 2026-10-19
**Sprint Reference:** grimoires/loa/sprint.md § Sprint 1 (global 263)
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md

---

## Overall Assessment

Sprint 263 delivers the four measurement fixes the cycle set out to make — the closed review-catch mount, grader 1.3.0 with three results and an oracle detector, dissent line anchors with a diff-scaled budget, and the curated multi-site labels — plus the lead's re-grade, adjudication and seven-PR smoke. The implementation is careful at the trust boundaries (path normalisation, transcript parsing without execution, bounded anchors) and the measurement discipline held: the adjudication went against the lead's own earlier recommendation and was recorded as such (DEC-0638); the smoke's two per-task failures were predicted or pre-registered before being read (DEC-0631, DEC-0640).

Two dissent runs (gpt-5.5-pro primary, claude-headless companion) found five BLOCKING defects in the oracle detector and the grader's scope map — all real, all fixed test-first in rounds r1a (`596627f4`) and r1b (this round), each re-validated against the 36 cycle-130 runs (no row changed) and the full `evals/tests/` suite. The remaining items are observations.

**Verdict:** APPROVED (observations documented and non-blocking)

---

## Observations

### 1. Configuration edge (adversarial-review.sh)

- **LOW** (confidence: high) `.claude/scripts/adversarial-review.sh:_adv_conf_budget_scale` — `budget_cents_max: 0` passes the whole-number check, so under `diff` every gate is refused with `reason: budget`.
**File:** `.claude/scripts/adversarial-review.sh` (`_adv_conf_budget_scale`)
**Suggestion:** treat a maximum below the configured budget (or below 1) as malformed → `fixed` with the WARN.
**Benefit:** a typo cannot silently switch every dissent off; operator-only key, so not blocking.

### 2. Row semantics for failed voices (ablation-row.sh)

- **MEDIUM** (confidence: high) `evals/harness/ablation-row.sh` dissent precedence — an envelope that exists with `status: api_failure` and 0/N voices completed reads `degraded` with `dissent_absent_gates: []` (smoke pr-12). The SDD's `dissent_absent_reason: error` was meant for this case too.
**Suggestion:** either map zero-completed-voice envelopes to `dissent_absent_reason: error`, or keep the split and read both columns (the Sprint 264 pre-registration now defines the sensitivity as the union, NOTES 08:29Z; DEC-0640).
**Benefit:** one column answers "did the dissent contribute?"; no code change required before the batches because the pre-registration already names the union.

### 3. Data-coupled test (ablation-grade.bats AG-50)

- **LOW** (confidence: high) `evals/tests/ablation-grade.bats` AG-50 pins the detector against the live corpus manifests; D's curation moved d10 into the r17-t1 diff-form set and the lead updated the expectation with a comment.
**Suggestion:** pin AG-50 to a fixture-local manifest copy so a future curation does not fail an unrelated test.
**Benefit:** the detector test stops moving with the corpus; the corpus is frozen by SHA256SUMS so this is hygiene, not a defect.

### 4. Partial-overlay import skew (design; KF-050)

- **MEDIUM** (confidence: high) `evals/harness/lib/sandbox-mount.sh` `expected()` — a fix-commit path outside the PR rewound to `head_commit` beside pinned importers that need its later symbols breaks the mounted cheval (pr-12, `private_workspace_base`); every voice failed on that PR in the smoke.
**Suggestion:** a pre-launch `mount_cheval=ok|broken:<reason>` evidence line (bead bd-56nn6) so the row names the cause; pr-12 stays re-grade-only (DEC-0611/0631).
**Benefit:** the next skewed PR is caught at launch, not read out of a MODELINV that never emitted.

### 5. REVIEW cap vs the priced-in dissent (pipeline bounds)

- **MEDIUM** (confidence: high) the 30-minute REVIEW cap is binding once the dissent actually runs on a 200 KB diff (smoke pr-17: 24 turns, waited on the background dissent). Handled by the per-task bounds of DEC-0640 and a re-smoke; not a code defect.

### 6. Scope clause silently skipped without a head file (recall-vs-defects.sh)

- **LOW** (confidence: medium) `evals/graders/recall-vs-defects.sh:hit_new` — when the head file is absent the scope clause is skipped without a note in `details`.
**Suggestion:** record `scope_unavailable: [files]` in details.
**Benefit:** a read can tell "no same-scope credit possible" from "none earned". Moot for the decision statistic now that `recall_pm3` decides (DEC-0638).

### 7. Scope clause silent without a fixture head (run 2 DISS-C-002)

- **LOW** (confidence: high) `evals/harness/ablation-grade.sh:grade_recall` — the `.no-head` sentinel keeps the grader off the sandbox copy, and the scope clause then silently yields nothing; the harness always resolves the fixture head, so this is a reporting gap, not a grading one.
**Suggestion:** fold into bead bd-9zmfn's details note (`scope_unavailable`).

### 8. Class 7 fixture index by physical line (run 2 DISS-C-001)

- **LOW** (confidence: medium) `evals/harness/ablation-grade.sh:repo_name_exempt` — the agent side joins backslash continuations, the fixture side does not; a verbatim quotation of a continued fixture command would read as a hit (stricter, never looser).
**Suggestion:** index the fixture lines joined the same way when a corpus PR carries a continued command with the repo name (none does today).

## Rejected dissent payloads

The sidecar `grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl` beside this file holds one row; this sprint's two review dissent runs (envelopes `adversarial-review-r1.json`, `adversarial-review.json`, copied from `a2a/sprint-263/` where they ran under `--sprint-id sprint-263`) rejected nothing (their sidecar holds 0 rows).

| # | Row | Triage |
|---|---|---|
| 1 | `ts_utc 2026-10-19T07:29:35Z`, `sprint_id sprint-1`, `model gpt-5.3-codex`, `reject_reason severity-not-in-enum (got: INVALID)`, payload `{"id":"DISS-001","severity":"INVALID","category":"injection","description":"test","failure_mode":"crash"}`, `repair_attempted true`, `repair_succeeded false`, `schema_enforced false` | **Not a defect of this sprint and not a dropped finding:** a synthetic payload (`description: "test"`, the retired `gpt-5.3-codex` voice) written at 07:29:35Z, the minute the lead ran `tests/unit/adversarial-review-*.bats` on the integrated tree — a unit test exercising the severity-enum rejection wrote its sidecar into the repository's real `a2a/sprint-1/` instead of its temp dir (observation 9, bead below). The row carries no finding to count. |

### 9. Unit test writes a sidecar into the repository's a2a directory

- **LOW** (confidence: high) `tests/unit/adversarial-review-*.bats` — one case (the severity-enum rejection with a `gpt-5.3-codex` voice; candidates: `adversarial-review-schema-enforced.bats`, which names `grimoires/loa/a2a/sprint-1`, `-repair-loop.bats`, `-companion.bats`) writes `adversarial-rejected-review.jsonl` into the real `grimoires/loa/a2a/sprint-1/` rather than `$BATS_TEST_TMPDIR`.
**Suggestion:** pin `PROJECT_ROOT`/the a2a dir to the test's temp dir in that case; a guard test that fails when a run leaves files under the repository's `grimoires/loa/a2a/`.
**Benefit:** sidecars beside a real sprint's feedback stay the sprint's own; `verdict-derive.sh` stops asking a reviewer to triage test fixtures. Pre-existing (the test predates this sprint), so recorded, not blocking.

## Adversarial dissent (two runs, cap three per sprint)

| Run | Diff | Voices | Findings | Blocking | Disposition |
|---|---|---|---|---|---|
| review 1 | `7600bd7d..bb03e931` (38 files, 5,936 lines) | gpt-5.5-pro + claude-headless, both succeeded | 9 | 2 (DISS-001, DISS-C-001: `split_segments` broke on `2>&1`/`&>`) | fixed in r1a `596627f4` (AG-52); C-002 class 7 bare token fixed (AG-53); C-003 EVAL_HEAD_DIR sentinel; C-004/C-005/C-006 scope-map fixes (RG-40 … RG-42); C-007, C-008 → beads bd-jszcp, bd-9zmfn (DEC-0642) |
| review 2 | `bb03e931..596627f4` (5 files, 262 lines) | same, both succeeded | 12 | 3 (one-liner `def` swallowed the file; `--stat -p` prints the patch; 4-backtick fence closed by 3) | fixed in r1b (RG-42 extended, RG-43, AG-52 extended, AG-53 printf); C-004 `|&`, C-008 `-L`/egrep/rg fixed; C-001, C-002, C-007 observations (DEC-0643) |

Envelopes: `grimoires/loa/a2a/sprint-263/adversarial-review-r1.json`, `adversarial-review.json` (run 2). Every finding was checked against the code before disposition; none was dismissed without a test or a recorded reason.

### Previous feedback status (round 1 → r1a → r1b)

| Issue | Status | Notes |
|---|---|---|
| DISS-001 / C-001 redirection ampersands split the command | Resolved | r1a; AG-52 |
| DISS-C-002 bare repo-name token exempt | Resolved | r1a; AG-53 (prose quotation stays exempt, AG-51) |
| DISS-C-003 fallback to sandbox pr/head | Resolved | r1a sentinel; observation C-002 (run 2) on its silence recorded |
| DISS-C-004/005/006 markdown fences, python signatures, tab indentation | Resolved | r1a + r1b (RG-40 … RG-43) |
| run 2 DISS-001/002/003 (edges of the r1a fixes) | Resolved | r1b |
| DISS-C-007 (run 1) dissent `disabled` from the sandbox config | Deferred | bead bd-jszcp; the Sprint 264 sensitivity reads `degraded` and `dissent_absent` together |
| DISS-C-008 (run 1) false_positives stays ±3 | Deferred | bead bd-9zmfn; `recall_pm3` decides, so ±3 is the comparable rule |


---

## Acceptance Criteria Check

See `grimoires/loa/a2a/sprint-1/reviewer.md` § AC Verification (every sprint.md criterion verbatim with evidence). Summary: FR-1 AC 1–3, 5, 6 met; AC 4 PARTIAL by ruling (DEC-0632); FR-2 AC 1–4 met (adjudication outcome: rule not adopted, DEC-0638); FR-3 AC 1–2 met, AC 3 is a Sprint 3 read; FR-4 AC 1–3 met; tests green (`evals/tests/` 507/507, unit sets 652/652 + 172/172, wire pytest 11/11).

---

## Security Checklist

- [x] No hardcoded secrets or credentials (the eval config variant writes only budget keys; codex credential handling unchanged)
- [x] Input validation at trust boundaries (overlay path normalisation refuses absolute, `..`, control bytes and symlink components; the detector parses transcript JSON and never executes it; `anchor_line` bounded 1..10,000,000; `budget_cents_max` whole-number check)
- [x] Zone boundaries respected (System Zone edits under the recorded marker and DEC-0625; checksums regenerated; implementers wrote only their listed files)
- [x] No new network calls; no new dependencies
- [x] Error messages carry paths and hashes only (no credential content)

---

## Code Quality Summary

**Strengths:**
- The overlay/check pair uses one Python core for the pre-launch check and the took-effect rule, so both compare the same way; evidence lines make every mount auditable.
- The grader keeps the old ruler byte-for-byte (36/36 regression) beside the new one; nothing pooled across rules.
- The dissent change is backward-compatible on the wire (symbol-only envelopes normalise identically; absent key → identical envelope), with the fixtures proving it.
- Blind curation and blind adjudication were kept blind; the adjudication result went against the lead's own prior recommendation and was recorded as such.

**Areas for Improvement:**
- Observations 1–3 above; the row-writer semantics (2) is the one worth a follow-up bead before the Sprint 265 reads.

---

## Next Steps

1. Audit gate (`/audit-sprint` contract) after the audit dissent run.
2. Sprint 264 pre-registrations carry: `recall_pm3` as the decision statistic (DEC-0638), the union dissent-absence sensitivity, the DEC-0640 bounds, the re-derived per-run costs.

<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":3,"low":6},"excluded":0,"sprint_id":"sprint-263","ts":"2026-10-20T01:38:00Z"} -->
