# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under audit:** `pr/head.diff` — sprint-264 of cycle-131: four review-catch arms in `evals/suites/ablation-2.0.yaml`, the `eval_only` batch-context refusal in `pipeline-run.sh`, the arm-schema check in `validate-suite.sh`, the `eval_only` component exclusion in `ablation-report.py`, and their tests (11 files, all under `evals/`).

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight and scope notes

- **Prerequisite not met, audit run anyway by task instruction.** Phase 0 requires `engineer-feedback.md` to say "All good". The review gate's verdict is CHANGES REQUIRED (`grimoires/loa/a2a/sprint-1/engineer-feedback.md`, trailer `"verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":4},"excluded":0`). The task brief for review-r28 directs the audit to run autonomously on the frozen PR, so this audit proceeds and records the deviation here. No COMPLETED marker is written.
- **Dissent envelope present with model.** `adversarial-review.json` carries `metadata.model: gpt-5.5-pro` (the gate's COMPLETED check), so the review's Phase 2.5 ran.
- **Scope limits.** Only the eleven touched files are present (`pr/base/`, `pr/head/`). `lib/sandbox-mount.sh`, `took-effect.sh`, the suite root under `grimoires/loa/evals/ablation-2.0/` and the bats runner are not in the workspace, so no test suite or shellcheck was executed here (FAST-GATE: unverifiable). Findings that depend on those files are marked `[ASSUMPTION]`.
- **Known-failures surface degraded.** `grimoires/loa/known-failures.md` does not exist (startup hook KF-SURFACE warning); triage ran without it.
- **Input guardrails:** `guardrails-orchestrator.sh --skill auditing-security` returned `action: PROCEED`.
- **Workspace artefact, not a PR defect:** `pr/head/.run/audit.jsonl` is an untracked one-line Write-hook log left by the review session (its cwd was `pr/head`). It is not in `pr/head.diff` and is ignored here.

---

## Executive Summary

The harness plumbing this PR adds is sound from a security standpoint. No secret, credential or privileged path is introduced. Every new interpolation is data-only: arm ids flow into stderr messages, `jq` receives data through heredocs with static filters, the validator's `RULE_IDS` is restricted by its `sed` character class to `[a-z_][a-z0-9_]*` before it reaches `python3 -I` as an argument, and `LOA_ABLATION_BATCH_CONTEXT=1` is set on the trial's command line only (`head/evals/harness/run-ablation.sh:1300-1301`), never exported into the runner's shell. The `eval_only` refusal sits after arm resolution and before `mkdir -p "$RUN_DIR"` (`head/evals/harness/pipeline-run.sh:258-262` vs `:356`), so the "no pipeline.json" claim holds. The validator's type-exact comparison (`:168`) correctly refuses `0` for `false` and `"yes"`/`1` for a boolean.

The defects are in the analysis and scheduling layers, where the new arm shape (review-catch-only, eval-only) meets unchanged code. Two HIGH findings carry over from the review, independently re-derived here from the head code: the three review-catch-only arms are admitted as components whose decisions are structurally pinned to "inconclusive", and the eval_only arm's valid rows are rendered nowhere. This audit adds a MEDIUM the review did not see: the four arms are never scheduled by a default `run-ablation.sh` batch because the suite's `priority` list, which is the runner's default arm set, was not extended. The two-voice security dissent found no CRITICAL/HIGH; its MEDIUM (the refusal keys on the declarative `eval_only` flag rather than on `oracle_open`) is adopted below as a finding of this audit.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 4 |
| Low | 5 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Review-catch-only components can never reach a null decision

**Severity:** HIGH (confidence: high) — Confirmed by cross-model review (review dissent DISS-001 / DISS-C-001).
**File:** `head/evals/harness/ablation-report.py:653-658`; `head/evals/suites/ablation-2.0.yaml:98-103`; `head/evals/harness/ablation-report.py:1913`
**Issue:** `primaries()` reads

```python
if "all" in types or REVIEW in types:
    return list(pba.get("all_types") or [PASS, CATCH])
return list(pba.get("build_only") or [PASS])
```

(`ablation-report.py:656-658`). a0_bare_fable, a1_review_only and a1_no_dissent declare `task_types: [review-catch]` (suite `:98-103`) and are counted as components (`:1913`), so each is compared on `hidden_test_pass_rate` against a1_full. `compare()` collects only build tasks for that metric (`:733`), finds no arm cell for any of them, and leaves `n == 0`; `usable()` (`:577-579`) is false, `decide()` sets `nopair` (`:850`) and, unless `defect_catch_rate` alone fires `investigate` or `keep`, returns `inconclusive: no valid pair (hidden_test_pass_rate)`. The `remove` (`:885`) and `simplify` (`:887`) branches are unreachable for these arms and `out["decidable"]` (`:922`) is always False. The PR's own tests pin this shape: `head/evals/tests/ablation-report.bats:189` asserts nine components and `:342` nine decisions, with no assertion on any review-catch-only arm's predicate state. The rules block has no `review_only` key in `primaries_by_arm` (suite `:113`).
**Impact:** Every batch spends review-catch trials on three arms whose Decisions rows are structurally fixed at "Inconclusive". The null result these arms exist to detect ("dissent does not matter", "the AUDIT gate adds nothing") can never be produced; the expected-false-positive line counts them in `k = 9` as if they were decidable tests.
**Fix:** Derive primaries from applicability: an arm whose task_types are review-catch-only gets `[defect_catch_rate]`; `all` keeps both; build-only keeps `[hidden_test_pass_rate]`. Add `review_only: [defect_catch_rate]` beside `build_only`/`all_types` in `rules.primaries_by_arm` so the pre-registration names it. Add a bats case feeding valid review-catch rows for a1_no_dissent equal to a1_full and asserting `decidable: true`, decision `simplify`/`remove`, and `primaries == ["defect_catch_rate"]`.
**Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [HIGH-002] The eval_only arm's valid rows vanish from the report

**Severity:** HIGH (confidence: medium) — Confirmed by cross-model review (review dissent DISS-002 / DISS-C-002).
**File:** `head/evals/harness/ablation-report.py:1913`; `head/evals/harness/ablation-report.py:2003`; `head/evals/harness/ablation-report.py:1108-1123`
**Issue:** The new filter

```python
components = [a["id"] for a in arms if a["id"] not in (CONTROL, BARE) and not a.get("absent") and a.get("eval_only") is not True]
```

(`:1913`) removes a1_full_openmount from `components`, hence from `decisions` (`analyse()`, `:1665`) and from `detail_arms = [BARE, CONTROL] + components` (`:2003`). It is neither CONTROL nor BARE nor `absent`, and `list_reason()` (`:1108-1123`) returns None for it (declared arm, applies to review-catch), so its valid rows enter `cells` via `_classify` (`:660-690`) and are surfaced by no section of report.md and no key of report.json. Only its excluded rows appear, in the Exclusions table (`:1806-1814`).
**Impact:** The PR's own comment (`:1911-1912`) calls the arm "the open-mount oracle A/B … an evaluation control". After this change the A/B is computed nowhere and the row-treatment contract (`:116-128`: every row is decided, excluded pairwise, or listed with a reason) is silently violated for an entire arm. Confidence is medium because a dedicated evaluation-controls section may be a later sprint's deliverable; the silent drop is a defect regardless.
**Fix:** Give `eval_only` arms an explicit, non-decision rendering path: an "Evaluation controls" section and JSON key reporting `defect_catch_rate` of the arm against CONTROL with its interval and `decision: none (eval_only)`, excluded from `decisions`, `k` and `decidable`; or at minimum list its rows under "Rows listed, never decided" with reason `eval_only arm`. Add a bats case with valid a1_full_openmount rows asserting where they appear.
**Reference:** CWE-684 Incorrect Provision of Specified Functionality — https://cwe.mitre.org/data/definitions/684.html

---

## Medium/Low Priority Issues

### [MED-001] The four new arms are never scheduled by a default batch: `priority` was not extended

- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/suites/ablation-2.0.yaml:55`; `head/evals/harness/run-ablation.sh:570-571`; `head/evals/harness/run-ablation.sh:24-25`
- **Issue:** The runner's default arm set is "the suite's priority minus every arm declared absent: true" (`run-ablation.sh:24-25`, implemented at `:570-571`: `[.priority // [] | .[] | select(IN($absent[]) | not)]`). The suite's `priority:` (`:55`) is unchanged from base (`pr/base/evals/suites/ablation-2.0.yaml:52`) and names only a0_bare … a7_effort_medium. a0_bare_fable, a1_review_only, a1_no_dissent and a1_full_openmount are therefore dropped from every batch and smoke that does not pass `--arms` explicitly. The PR's own test documents this: `head/evals/tests/run-ablation.bats:389` pins the batch MANIFEST arm list to the eight pre-existing arms. Neither `validate-suite.sh` nor `run-ablation.sh` checks that every non-absent arm appears in `priority`, so the omission is silent. `[ASSUMPTION]` the arms are meant to run in the cycle-131 batch; if a later sprint owns the batch plan, this becomes a documentation gap in `PR.md`.
- **Impact:** The suite declares four arms that the batch runner never runs by default; operators who follow the documented default get rows for none of them and the FR-5 questions go unmeasured, with no refusal, warning or listing.
- **Fix:** Add the four arms to `priority` (and the `cut_ladder` if their trials are cuttable), or state in the suite header and `PR.md` that FR-5 arms run only via `--arms`. Add a validator check that every non-absent arm appears in `priority` exactly once and that every `priority` id is declared.
- **Reference:** CWE-684 — https://cwe.mitre.org/data/definitions/684.html

### [MED-002] The eval_only refusal keys on the declarative flag, not on `oracle_open`

- **Severity:** MEDIUM (confidence: medium) — Cross-model finding DISS-C-001 (claude-headless, companion voice), adopted as a finding of this audit.
- **File:** `head/evals/harness/pipeline-run.sh:258-262`; `head/evals/harness/validate-suite.sh:179-180`
- **Issue:** `EVAL_ONLY` is read from `.eval_only` alone (`:258`). The property that actually exposes the oracle is `toggles.oracle_open == true`, which skips the answer-path overlay (`:337`, `sb_overlay="none(oracle_open)"`). The invariant "oracle_open: true ⇒ eval_only: true" lives only in the validator (`validate-suite.sh:179-180`), which nothing on the run path invokes; `pipeline-run.sh` accepts any `--suite-file`. A suite with `toggles: {oracle_open: true}` and no `eval_only` key runs the open mount with `EVAL_ONLY=false` outside any batch context, and `ablation-report.py:1913` then counts the arm as a component because the suite def has no `eval_only`.
- **Impact:** Answer-exposed trials can be run and reported as a shipped-default component without touching `LOA_ABLATION_BATCH_CONTEXT`, contaminating the ablation decision. Defence-in-depth gap rather than an exploit: the committed suite is valid and CI runs the validator.
- **Fix:** Set `EVAL_ONLY=true` when `.eval_only == true` OR `.toggles.oracle_open == true` (or refuse an arm with `oracle_open` but no `eval_only`), and have `ablation-report.py` treat `toggles.oracle_open == true` as eval_only too. Optionally have `run-ablation.sh` invoke `validate-suite.sh` on the suite file before planning.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [MED-003] A bare baseline is counted as a component

- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/suites/ablation-2.0.yaml:98`; `head/evals/harness/ablation-report.py:1913`
- **Issue:** a0_bare_fable has `toggles: {loa_mount: false, bare_model: fable}` and is "A0 on the review model" (suite `:94-95`), yet `:1913` treats it as a component with keep/remove/simplify semantics relative to a1_full and it inflates `k` in the expected-false-positive line (`:1927-1931`). "Remove" or "simplify" a baseline is not a meaningful decision; the analogous read for a0_bare is H1.
- **Impact:** The Decisions table carries a nonsense row and the error-budget sentence counts a non-test as a test.
- **Fix:** Mark baseline arms (e.g. `role: baseline`, or extend the BARE exclusion to any arm with `toggles.loa_mount == false`) and render an H1-style line for them; then correct the component count in `head/evals/tests/ablation-report.bats:189,342`.
- **Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html

### [MED-004] PR description claims deliverables the diff does not contain; no AC verification or test evidence

- **Severity:** MEDIUM (confidence: high)
- **File:** `grimoires/loa/a2a/sprint-1/reviewer.md:3` (= `pr/PR.md:1`)
- **Issue:** The title promises "the cycle-131 suite root (bounds 50/40) with its image self-check"; the diff holds no suite root, bounds or self-check artefact (11 files, all under `evals/`). The report has no `## AC Verification` section and does not state that `bats evals/tests/*.bats` or `shellcheck` ran. The five new took-effect rule ids are validated against `took-effect.sh`, which is outside the PR (see LOW-004).
- **Impact:** Reviewers and this gate cannot trace what shipped; the undelivered suite root is either missing scope or a misleading title.
- **Fix:** Add the suite-root files or trim the title; add the AC walkthrough and test-run output to the implementation report.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-001] Stale component count in the pre-registered rules block

- **File:** `head/evals/suites/ablation-2.0.yaml:117`
- **Issue:** `# expected false positives at 0.90 over 6 components printed` while the report prints nine (`head/evals/tests/ablation-report.bats:189`); AR-12 quotes the rules block verbatim into the Method section, so the report contradicts itself.
- **Fix:** Update the comment or drop the hard-coded number.
- **Reference:** CWE-1053 Missing Documentation for Design — https://cwe.mitre.org/data/definitions/1053.html

### [LOW-002] Toggle vocabulary and config-edit mapping are hand copies of the mount library

- **File:** `head/evals/harness/validate-suite.sh:137-139`; `head/evals/harness/pipeline-run.sh:341-345`
- **Issue:** `TOGGLE_VALUES` duplicates `lib/sandbox-mount.sh apply_arm_toggles`' vocabulary by hand (the header `:45-49` says it is "the vocabulary of lib/sandbox-mount.sh"), while `RULE_IDS` (`:87`) is correctly read from `took-effect.sh`. The dry-run `sb_edits` jq (`pipeline-run.sh:341-345`) duplicates the toggle→config-edit mapping the same way. The new bats cases compare against literal strings, not the lib's real edits. `[ASSUMPTION]` the lib is not in the PR; parity is unverified.
- **Fix:** Export the vocabulary and edit map from the lib (validate-suite already sources it) and consume them in both places, or add a parity test.
- **Reference:** CWE-1041 Use of Redundant Code — https://cwe.mitre.org/data/definitions/1041.html

### [LOW-003] Arm-level `effort` and `phases` remain unchecked by the validator

- **File:** `head/evals/harness/validate-suite.sh:157-180`; `head/evals/harness/pipeline-run.sh:314-315`
- **Issue:** Check 8 validates `toggles.effort` but not the arm-level `effort:` key a0_bare and a0_bare_fable use (suite `:78`, `:98`), nor `phases`. `pipeline-run.sh:314` reads `.effort // .toggles.effort` and dies with exit 2 at `:315` on a bad value, before a run dir exists, so a suite typo surfaces as a batch of interrupted rows instead of a validation failure. Pre-existing gap the PR's new arm-schema check leaves open.
- **Fix:** Validate arm-level `effort` against the same enum and `phases` against the known phase names in the same block.
- **Reference:** CWE-20 Improper Input Validation — https://cwe.mitre.org/data/definitions/20.html

### [LOW-004] took-effect rule ids are parsed from a source file this PR does not touch, by definition shape

- **File:** `head/evals/harness/validate-suite.sh:87`
- **Issue:** `RULE_IDS` is the `sed` extraction of single-line `rule_<id>() {` definitions. The committed suite now names five new ids (`oracle_closed`, `oracle_open_recorded`, `bare_model_fable`, `review_only_phases`, `no_review_dissent_envelope`) that must exist in that exact shape in `took-effect.sh`, which is absent from `pr/base` and `pr/head`. `[ASSUMPTION]` Sprint 263 defined them; otherwise VS-14/VS-16 fail and the validator rejects the committed suite. A `function rule_x` or brace-on-next-line definition is silently dropped. The character class does keep the value shell- and argv-safe.
- **Fix:** Confirm the five functions exist on the merge target; prefer a `--list-rules` mode in `took-effect.sh` over parsing its source.
- **Reference:** CWE-1068 — https://cwe.mitre.org/data/definitions/1068.html

### [LOW-005] The batch-context guard leaves no provenance in the run record

- **Severity:** LOW (confidence: medium) — Cross-model finding DISS-C-002 (claude-headless), see below.
- **File:** `head/evals/harness/pipeline-run.sh:259`
- **Issue:** `LOA_ABLATION_BATCH_CONTEXT=1` is a constant, unauthenticated environment variable the header tells operators to set by hand for dry runs (`:141-146`). An operator who `export`s it once disables the guard for every later manual call, and nothing in `meta/` distinguishes a guarded batch launch from a manual bypass. Consistent with the stated design ("operator guard against accidental runs"); not an enforcement boundary and not claimed as one.
- **Fix:** Record the context in `meta/arm-evidence` (e.g. `batch_context=1` plus the launching batch id) so the report can exclude eval_only rows without batch provenance; a per-batch token from `run-ablation.sh` would be stronger than a constant.
- **Reference:** CWE-807 — https://cwe.mitre.org/data/definitions/807.html

---

## Cross-Model Security Observations

Security dissent ran with two voices (`grimoires/loa/a2a/sprint-1/adversarial-audit.json`: primary `gpt-5.5-pro` answered by `codex-headless`, status `clean`, zero findings; companion `claude-headless`, `counted_as: independent_voice`, two findings). `verdict_quality`: consensus, 2/2 voices succeeded, `chain_health: ok`, `degraded: false`; no `locality.degraded_security_review` marker. Not a DEGRADED_SECURITY_REVIEW.

- **DISS-C-001 (MEDIUM, `pipeline-run.sh:258-262`)** — adopted as [MED-002] above.
- **DISS-C-002 (LOW, `pipeline-run.sh:259`)** — adopted as [LOW-005] above.
- Neither voice raised a CRITICAL or HIGH; the two HIGH findings of this audit come from the review gate's dissent (`adversarial-review.json` DISS-001/002 and DISS-C-001/002), independently re-derived from the head code here.

## Rejected dissent payloads

- none — `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is empty, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

---

## Review demotions confirmed

The review trailer records `excluded: 0` — no HIGH was demoted to Observations as speculative. Nothing to confirm; `excluded_confirmed: 0`.

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 4 |
| Low | 5 |

One-way rule: critical + high = 2 > 0 ⇒ CHANGES_REQUIRED.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added — none in the diff; `LOA_ABLATION_BATCH_CONTEXT` is a boolean operator flag.
- [x] Input validation at trust boundaries — `validate-suite.sh` check 8 is type-exact (`:168`); `eval_only` parse is literal-`true` (`pipeline-run.sh:258`); `RULE_IDS` constrained to `[a-z_][a-z0-9_]*` before reaching `python3 -I` argv (`validate-suite.sh:87`, `:122`). Gap: [MED-002], [LOW-003].
- [x] Authentication / authorization — n/a; the harness runs under the operator. The env guard is advisory by design ([LOW-005]).
- [x] No injection — arm ids are interpolated into messages only; every `jq` takes data via heredoc with a static filter; `yq` in tests loads a repo-path file through `strenv`.
- [x] Error handling doesn't leak info — refusal messages name the arm and reason only.
- [x] Trust boundary preserved — `pipeline-run.sh` still sources no `.claude/` code; `took-effect.sh` is resolved by a literal path beside the script.
- [ ] Tests cover security paths — the refusal and the exact-value semantics are tested (`pipeline-run.bats:1227-1248`); the oracle_open-without-eval_only path through `pipeline-run.sh` is not ([MED-002]).

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 4 | Type-exact validator; gaps in arm-level `effort`/`phases` and the run-path `oracle_open` invariant |
| SEC-AZ Authorization | 4 | Advisory env guard, documented as such; no privilege path touched |
| SEC-IN Injection Prevention | 5 | Data-only interpolation throughout |
| ARCH-MO Modularity | 3 | Two hand-copied vocabularies of the mount lib |
| CQ Correctness | 2 | Two HIGH analysis-layer defects; default scheduling omits the new arms |
| CQ Testing | 3 | Plumbing well tested; analysis tests pin counts, not predicate states |

## Documentation Audit

No `documentation-coherence-task-*.md` or `documentation-coherence-sprint-*.md` reports exist under `grimoires/loa/a2a/subagent-reports/` (frozen-PR workspace; noted, not counted). Header comments for the refusal, the dry-run lines and the arm schema were added and are accurate; the stale rules comment is [LOW-001]; the PR title mismatch is [MED-004].

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix `primaries()` for review-catch-only arms and give `eval_only` arms a reporting path ([HIGH-001], [HIGH-002]), with bats cases asserting predicate state and row placement.
2. Decide whether the four arms join `priority` ([MED-001]) and whether a0_bare_fable is a baseline or a component ([MED-003]); correct the pinned counts in `ablation-report.bats:189,342`.
3. Key the eval_only refusal and the report exclusion on `oracle_open` as well as the flag ([MED-002]).
4. Reconcile the PR title with the diff and add AC/test evidence to the report ([MED-004]).
5. Run `/implement sprint-1` to fix, then `/review-sprint sprint-1` and `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":4,"low":5},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T12:25:00Z"} -->
