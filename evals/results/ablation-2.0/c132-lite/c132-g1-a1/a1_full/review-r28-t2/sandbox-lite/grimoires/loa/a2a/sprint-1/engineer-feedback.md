# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)

---

## Overall Assessment

The change under review is the sprint-264 pull request in `pr/` (11 files under `evals/`): four review-catch arms added to `evals/suites/ablation-2.0.yaml`, an `eval_only` refusal in `pipeline-run.sh` keyed on `LOA_ABLATION_BATCH_CONTEXT=1` that `run-ablation.sh` sets on every trial it launches, a suite-arm schema (toggles vocabulary, took-effect rule ids, `eval_only`) in `validate-suite.sh`, and the report excluding `eval_only` arms from its components. I read every head file against its base, verified the test assertions against the code they exercise, and ran the cross-model dissent on `pr/head.diff`.

The harness side is sound: the refusal sits before the run directory is created (`head/evals/harness/pipeline-run.sh:258-262` vs `mkdir -p "$RUN_DIR"` at 356), only the exact value `1` opens it, the `--help` range (`2,156p`) matches the grown header (its closing rule is line 157), the batch context is set on the trial command only (`head/evals/harness/run-ablation.sh:1300-1301`), and the validator's type-exact toggle check and the `oracle_open ⇒ eval_only` coupling (`head/evals/harness/validate-suite.sh:165-180`) do what the header promises. The bats additions exercise the refusal matrix, the dry-run plans and the batch-context propagation.

The defect is on the report side. The PR adds the first review-catch-only decision arms (`a0_bare_fable`, `a1_review_only`, `a1_no_dissent`) to `components`, but `Analysis.primaries()` was not taught about them: any arm whose `task_types` contains `review-catch` is decided on both primaries, and the pass-rate comparison can never pair for an arm that runs no build task. `decide()` therefore appends `no valid pair (hidden_test_pass_rate)` on every run, `decidable` is permanently false, and `remove` / `simplify` — the very verdicts `a1_review_only` and `a1_no_dissent` exist to reach — are unreachable. The expected-false-positive line and the decisions-count assertions were updated to 9, but no test drives a review-catch-only component through a decision, which is why this went unnoticed.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Functionality — review-catch-only components can never be decided

- **HIGH** (confidence: high) `head/evals/harness/ablation-report.py:1913` — the three review-catch-only arms become components, but `primaries()` (`head/evals/harness/ablation-report.py:653-658`) returns `[hidden_test_pass_rate, defect_catch_rate]` for any arm with `review-catch` in `task_types`; `compare()` restricts the pass-rate metric to build-type tasks (`:731-733`), the arm has no cell on any of them, so every pass-rate comparison is `n == 0`, `usable()` (`:577-579`) is false, `decide()` sets `nopair` (`:849-850`) and returns `inconclusive: … no valid pair (hidden_test_pass_rate)` (`:873-877`) unless `investigate`/`keep` fired first on the catch rate; `decidable` (`:922`) is always false.
**File:** `head/evals/harness/ablation-report.py:1913` (root cause `:653-658`)
**Issue:** The suite's `rules.primaries_by_arm` (`head/evals/suites/ablation-2.0.yaml:113`) knows only `build_only` and `all_types`; the code maps "contains review-catch" to `all_types`. Before this PR no runnable arm was review-catch-only, so the gap was latent. This PR makes it live for three decision arms.
**Why This Matters:** Concrete failing input: a batch where `a1_review_only` matches `a1_full` on `defect_catch_rate` (d within ±0.03, interval straddling 0) at 40 % lower cost — the pre-registered `remove` predicate (`ablation-2.0.yaml:126`) is satisfied, yet the report prints `**Inconclusive** — inconclusive: no valid pair (hidden_test_pass_rate)` with `pass-rate Δ` = `no pair`. The same holds for `a1_no_dissent` and `a0_bare_fable`. The arms can only ever land on `investigate`, `keep` or `inconclusive`, and each inconclusive triggers `inconclusive_extension_trials: 2` (`:129`) — spend with no possible payoff.
**Required Fix:** Decide a review-catch-only arm on the catch rate alone. Add `review_only: [defect_catch_rate]` to `rules.primaries_by_arm` and make `primaries()` return it when `task_types` has `review-catch` and neither `all` nor any build type; render `n/a (review-only)` for the pass-rate column (the three `"n/a (build-only)"` sites at `:1634`, `:1649`, `:1699` need the symmetric branch). Then add a `gen-fixtures.py` scenario with planted rows for a review-catch-only component that reaches `remove` (and one that reaches `keep`), and assert `.decidable == true` and the `.primaries` list for `a1_review_only` in `ablation-report.bats` the way AR-6 does for build-only arms.
**Reference:** GOAL-DRIVEN (Karpathy 4): the non-trivial branch added here — nine components, three of a new shape — left no runnable check that fails when it breaks; AR-12 and the `decisions | length` assertion only count rows.

---

## Observations

### 1. Report semantics

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:1913` — `a0_bare_fable` is a baseline variant (`loa_mount: false`, BARE on Fable), yet it is counted as a component: it inflates `k` in the expected-false-positives line (now 9) and will be handed a `keep` / `remove` / `simplify` verdict that has no meaning for a bare arm. The PR's own test comment (`head/evals/tests/ablation-report.bats:189`) calls the three new arms "control arms".
**Suggestion:** Mark decision arms explicitly (e.g. `decision_arm: false` on `a0_bare_fable`, or exclude `toggles.loa_mount == false` arms from `components` as `a0_bare` already is by id) and report A0F beside A0 in the H1 section instead.
**Benefit:** The pre-registered component count and the decision table stay honest.

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-report.py:2003` — `a1_full_openmount` rows pass `_classify` and are kept in `arm_rows`, but the arm is in neither `components` nor `detail_arms`, so apart from the oracle-exposed sensitivity count (`:1624`, `:1685`) its rows are rendered nowhere. The open-mount A/B the arm exists for (cycle-131 FR-5) has no output in the report.
**Suggestion:** Render eval_only arms in a dedicated "Evaluation-only arms" table (catch rate vs `a1_full`, cost), explicitly labelled as deciding nothing.
**Benefit:** The arm's spend produces a readable result.

### 2. Duplication / SIMPLICITY

- **MEDIUM** (confidence: medium) `head/evals/harness/pipeline-run.sh:341-345` — SIMPLICITY[shrink]: the dry run re-implements `apply_arm_toggles`' config-edit mapping in jq (`companion_voice`, `gates`, `dissent`, `flatline` → `.loa.config.yaml` keys). The library (`lib/sandbox-mount.sh`, not in this diff) is the source of truth; when it changes, the dry run reports edits that will not happen, and the three dry-run tests (`head/evals/tests/pipeline-run.bats:1195-1221`) pin the copy, not the library.
**Suggestion:** Have the library expose the planned edit list (a `plan_arm_config_edits <toggles>` function the dry run and `apply_arm_toggles` both call) and print that. `net: -12 lines possible`.
**Benefit:** One mapping, one place to change.

### 3. Scheduling

- **MEDIUM** (confidence: high) `head/evals/suites/ablation-2.0.yaml:55` — `priority` does not list the four new arms, and `run-ablation.sh` defaults `--arms` to the priority list minus absent arms (`head/evals/harness/run-ablation.sh:570-571`). A default batch never schedules `a0_bare_fable`, `a1_review_only`, `a1_no_dissent` or `a1_full_openmount`; they run only when named on `--arms`. `cut_ladder` (`:46`) is silent on them too.
**Suggestion:** Either append them to `priority` (and say where the cut ladder drops them) or state in the arms comment that they are `--arms`-only.
**Benefit:** The operator learns the arms exist from the plan, not from a missing row.

### 4. Report / scope

- **MEDIUM** (confidence: medium) `grimoires/loa/a2a/sprint-1/reviewer.md:3` (= `pr/PR.md`) — the title claims "the cycle-131 suite root (bounds 50/40) with its image self-check"; no file under `grimoires/loa/evals/` is in `pr/head.diff`, so either the title overstates the change or the change is incomplete. The report also carries no `## AC Verification` walkthrough, which the review gate treats as an automatic CHANGES_REQUIRED on its own. Three of the new tests depend on repository state outside the diff that I could not verify here: the `rule_<id>()` functions `bare_model_fable`, `review_only_phases`, `no_review_dissent_envelope`, `oracle_closed`, `oracle_open_recorded` in `took-effect.sh` (VS-14/VS-16), and the committed suite root's freeze covering `smoke/` (RAB-c131-5's `cp -r` without a re-freeze, `head/evals/tests/run-ablation.bats:1196`).
**Suggestion:** Trim the title to what the diff contains, or add the suite-root files; add the AC walkthrough with `file:line` evidence.
**Benefit:** The report matches the change the gates reviewed.

### 5. Low

- **LOW** (confidence: high) `head/evals/suites/ablation-2.0.yaml:117` — the `multiple_comparisons` comment still says "over 6 components"; the report now prints 9.
**Suggestion:** Update the comment, or drop the number from it.
**Benefit:** The pre-registered rules block stays consistent with the report.

- **LOW** (confidence: medium) `head/evals/tests/run-ablation.bats:1189` — the test title asserts "the runner's own environment is unchanged", but no assertion inspects the runner's environment after the run (only the stub's view is checked). The claim is true by construction (the assignment is a command prefix), but the test does not prove it.
**Suggestion:** Drop the clause from the title, or add an env probe after `ra` returns.
**Benefit:** Test titles stay literal.

- **LOW** (confidence: medium) `head/evals/harness/validate-suite.sh:87-88` — the rule-id set is scraped with `^rule_\([a-z_][a-z0-9_]*\)() *{`; a rule written `rule_x () {` or `rule_x()\n{` vanishes silently and the committed suite then fails with a misleading "unknown rule id". `[[ -n "$RULE_IDS" ]]` only catches the all-missing case.
**Suggestion:** Accept optional whitespace before `()` and either brace style, or ask `took-effect.sh` to print its rule list (`--list-rules`).
**Benefit:** The validator fails on real drift, not on formatting.

### Security checklist notes

`LOA_ABLATION_BATCH_CONTEXT` is an unauthenticated environment flag; it guards against an accidental open-mount run, not against an operator who sets it. That matches the header's framing (`head/evals/harness/pipeline-run.sh:141-147`) and is acceptable for an evaluation harness; the sentence belongs in the suite comment too so nobody reads it as a security boundary. No secrets, no new trust-boundary inputs: the validator reads the suite file and `took-effect.sh` from the tree and passes the rule ids as a single argv to `python3 -I`.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The three review-catch-only decision arms cannot reach a `remove`/`simplify` decision (Changes Required §1); the suite root / image self-check named in the title is not in the diff |

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff` (criteria = the PR title's claims)

| Criterion | Status | Notes |
|-----------|--------|-------|
| Four review-catch arms declared | Pass | `head/evals/suites/ablation-2.0.yaml:98-105`; AT-13 pins the id order and `task_types` |
| `eval_only` batch-context refusal | Pass | `head/evals/harness/pipeline-run.sh:258-262` before `mkdir` at 356; `run-ablation.sh:1300-1301` sets it per trial; tests `pipeline-run.bats:1223-1254`, `run-ablation.bats:1189` |
| validate-suite arm schema | Pass | `head/evals/harness/validate-suite.sh:86-88`, `:150-180`; VS-14…VS-17 |
| Report: eval_only not a component | Pass | `head/evals/harness/ablation-report.py:1913` |
| Report: the new arms are decidable components | Fail | `primaries()` gives them a pass-rate primary that never pairs — Changes Required §1 |
| Cycle-131 suite root (bounds 50/40) with image self-check | Fail | Not in `pr/head.diff` |

---

## Security Checklist

- [x] No hardcoded secrets or credentials
- [x] Input validation and sanitization present (type-exact toggle values, boolean `eval_only`, rule-id allowlist)
- [x] Authentication/authorization correct (n/a — env flag is a guard, not a boundary; documented)
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Dependencies secure (no new dependencies)
- [x] Error messages don't leak sensitive data

---

## Code Quality Summary

**Strengths:**
- The refusal is placed so that no artefact exists for a refused eval_only run, and the test proves it for the dry run, the real run and four non-`1` values.
- `c131_arms` now loads the committed arm definitions instead of a hand-written copy, so the pipeline tests exercise the real suite shape.
- The validator's value check is type-exact (`gates: 0` is rejected) and the `oracle_open ⇒ eval_only` rule closes the obvious misuse.

**Areas for Improvement:**
- The report's arm model (`primaries_by_arm`, `components`) was extended by adding arms without extending the code that classifies them.
- The dry-run printer duplicates library logic.
- The implementation report claims more than the diff delivers and carries no AC walkthrough.

---

## Next Steps

1. Fix `primaries()` for review-catch-only arms and add the fixture scenario that proves a `remove`/`keep` decision is reachable for `a1_review_only`.
2. Decide whether `a0_bare_fable` is a component or a baseline, and give the eval_only arm a rendered table.
3. Reconcile the PR title with the diff (add the suite-root files or trim the title) and add `## AC Verification` to the report.
4. Request another review via `/review-sprint sprint-1`.

---

## Cross-Model Observations

Phase 2.5 dissent on `pr/head.diff`: two voices (`gpt-5.5-pro` via `codex-headless`, companion `claude-headless`), `verdict_quality.consensus_outcome: consensus`, `voices_succeeded: 2`, `hallucination_filter.downgraded: 0`. Envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json`. Triage (advisory input; nothing here is counted beyond the findings above):

- **DISS-001 / DISS-C-001 (BLOCKING)** — review-catch-only components inherit the pass-rate primary and are permanently undecidable. Independently found by both voices and by this review; it is Changes Required §1 (the one HIGH). The companion's extra point stands: the `decisions | length == 9` assertion passes while all three new decisions are undecidable, and the k=9 EFP sentence counts comparisons that cannot fire.
- **DISS-002 / DISS-C-003** — `a1_full_openmount` rows are kept but never rendered. Agreed; Observations §1 (second MEDIUM).
- **DISS-C-002** — `a0_bare_fable` counted as a component. Agreed; Observations §1 (first MEDIUM).
- **DISS-C-004** — dry-run duplicates the toggle→config mapping. Agreed; Observations §2. Its sub-claim that `karpathy_block`, `rule_files`, `audit_delta_instruction`, `context_resets`, `sprint_plan` are "config edits this jq does not report" is only partly right: those toggles act on the prompt surface and the phase plan, not on `.loa.config.yaml`, so their absence from `config_edits=` is correct today — which is exactly why a single shared mapping matters.
- **DISS-C-005** — new arms absent from `priority`. Agreed; Observations §3. Its second half (a non-`run_trial` call of `pipeline-run.sh` would lack the batch context) is checked and does not apply: `"$PIPELINE_BIN"` is invoked once, at `head/evals/harness/run-ablation.sh:1295`, inside `run_trial`.
- **DISS-C-006** — duplicate arm ids. Half right. The claimed run-time effect does not occur: `head/evals/harness/pipeline-run.sh:242` selects `[... select(.id == $a)][0]`, so a duplicated id yields exactly one object and the `eval_only` test at `:258` sees one token. What stands is that `validate-suite.sh` still has no duplicate-arm-id rule (its duplicate check at `:239` is for task ids); recorded as a LOW below, since the new per-arm loop is the natural place for it.
- **DISS-C-007** — the real-suite `c131_arms` would break Sprint 263 tests that run `a0_bare_fable` on `$BUILD`. Refuted: every use of the four arms in `head/evals/tests/pipeline-run.bats` (`:1055`, `:1097`, `:1106`, `:1109`, `:1177-1259`) runs `$REVIEWC` or a review-catch dry run; none passes `$BUILD`.

### Additional observation from the dissent triage

- **LOW** (confidence: high) `head/evals/harness/validate-suite.sh:157-160` — the new per-arm schema loop does not reject two arms sharing an `id`; `arm_ids` at `:146` is a set, so the leakage check silently dedupes too. A duplicated id passes validation; `pipeline-run.sh` then runs whichever definition appears first (`:242`), and `run-ablation.sh` likewise (`head/evals/harness/run-ablation.sh:576`), so the second definition is dead without a word.
**Suggestion:** Count ids before the loop and emit `arm <id> is declared twice`.
**Benefit:** A copy-paste in the arms block fails at validation, not at analysis.

## Rejected dissent payloads

None. `metadata.rejected_summary` is `[]`, `rejected_count` is 0, and the only sidecar the envelope names (`grimoires/loa/a2a/sprint-1/adversarial-rejected-review.jsonl`) is empty (0 bytes); the companion wrote no sidecar (`companion_voice.rejected_sidecar: null`).

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":5,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T18:05:10Z"} -->
