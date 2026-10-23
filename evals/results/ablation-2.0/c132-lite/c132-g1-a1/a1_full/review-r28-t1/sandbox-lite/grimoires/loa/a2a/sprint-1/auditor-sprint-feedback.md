# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (= pr/PR.md)
**Change under review:** pr/head.diff — "feat(cycle-131): sprint-264 — four review-catch arms, eval_only batch-context refusal, validate-suite arm schema, the cycle-131 suite root (bounds 50/40) with its image self-check" (11 files)
**Review gate:** grimoires/loa/a2a/sprint-1/engineer-feedback.md — CHANGES_REQUIRED (0 critical, 1 high, 5 medium, 4 low, excluded 0)

Paths below are cited as `head/<path>:<line>` with line numbers from `pr/head/`.

---

## Verdict: CHANGES_REQUIRED

---

## Executive Summary

The security posture of the change is sound. The eval_only refusal runs before any side effect (`head/evals/harness/pipeline-run.sh:259-262`; the run directory is first created at `:356`), only the exact string `1` opens it, run-ablation.sh sets the variable on the single trial launch site and never exports it to its own shell (`head/evals/harness/run-ablation.sh:1300-1301`), and the agent under test never sees it: the launch environment is an explicit allowlist passed through an env shim (`head/evals/harness/pipeline-run.sh:833-868`, `:897`). All suite values enter jq via `--arg` or heredocs, `took-effect.sh` rule ids are read by a fixed regex into a `python3 -I` set, and the validator's type-exact comparison rejects `0` for `false`. No secret, injection, or path-handling issue was found.

The sprint fails on correctness of its deliverable, and the review's blocking finding is confirmed here independently: the three new component arms declare `task_types: [review-catch]`, `primaries()` hands any arm with `review-catch` both primaries, the pass-rate comparison has no build cells to pair, and `decide()` therefore always ends in "inconclusive: no valid pair" — `remove` and `simplify` are unreachable for exactly the arms the sprint adds. Both dissent voices in the review and my own trace agree. The remaining findings are evaluation-integrity and hygiene items: the refusal fences the flag rather than the behaviour that opens the oracle, a bare-model arm is counted as a component, the default batch never runs the new decision arms, and the PR title claims a suite root, bounds and an image self-check that the diff does not contain.

Scope limits: the workspace holds only the eleven touched files. `lib/sandbox-mount.sh`, `took-effect.sh`, the suite root and the fixtures are absent, so no bats suite was executed; claims about those libraries are read from the touched files' references. The review gate's verdict is CHANGES_REQUIRED, not "All good"; the audit proceeds on the task's explicit instruction and records the Phase 0 deviation here.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 4 |
| Low | 7 |

Prerequisites: `grimoires/loa/a2a/sprint-1/adversarial-review.json` carries `metadata.model` (gpt-5.5-pro) with status `reviewed`. No documentation-coherence reports exist under `grimoires/loa/a2a/subagent-reports/` (directory absent); documentation was checked manually against the touched headers and the suite comments.

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] review-catch-only component arms can never reach a decision

**Severity:** HIGH (confidence: high; confirmed by cross-model review — DISS-001 gpt-5.5-pro and DISS-C-001 claude-headless in the review gate)
**File:** `head/evals/harness/ablation-report.py:656-658` (the arms: `head/evals/suites/ablation-2.0.yaml:98-103`; the component list: `head/evals/harness/ablation-report.py:1913`)
**Issue:** `primaries()` reads

```python
if "all" in types or REVIEW in types:
    return list(pba.get("all_types") or [PASS, CATCH])
return list(pba.get("build_only") or [PASS])
```

so a0_bare_fable, a1_review_only and a1_no_dissent (`task_types: [review-catch]`) get `[hidden_test_pass_rate, defect_catch_rate]`. `arm_report()` (`:889-891`) builds `compare(arm, a1_full, hidden_test_pass_rate)`; in `compare()` (`:731-760`) the task set is `BUILD_TYPES`, the arm has no build cell, every task lands in `unpaired` and `n == 0`, so `usable()` (`:577-579`) is False. In `decide()` (`:846-887`) that sets `nopair` (`:850`); after the `investigate` and `keep` tests it always appends "no valid pair (hidden_test_pass_rate)" (`:874`) and returns `inconclusive`. The `remove` and `simplify` branches are dead for these arms and `out["decidable"]` (`:922`) is False. The H1/A4 path has a `not_testable` read for this situation (`assess()`, `:1200-1204`); the component path has none, and the suite's `primaries_by_arm` (`head/evals/suites/ablation-2.0.yaml:113`) knows only `build_only` and `all_types`.
**Concrete failure:** a complete cycle-131 batch of a1_review_only on the four review-catch tasks with defect_catch_rate within −0.03 of a1_full and cost 30 % lower — the intended "the AUDIT gate can be removed" outcome — prints "inconclusive: no valid pair (hidden_test_pass_rate: …)" with `decidable: false`, while the expected-false-positive line (`:1927-1932`) counts the arm as a real comparison.
**Blast radius:** the three arms are the deliverable of FR-5; every batch run on them produces an undecidable report. No test plants rows for a review-catch-only component: AR-12 and the `by_suite_version` case (`head/evals/tests/ablation-report.bats:189,342`) assert only the count 9 on arms in the `no_rows` state.
**Fix:** add `review_only: [defect_catch_rate]` to `rules.primaries_by_arm` and branch on it in `primaries()` when `task_types` holds `review-catch` and no build type (keep `all_types` for `all`, or for review-catch combined with a build type). Add an ablation-report.bats case that plants review-catch rows for a review-catch-only component and asserts `decidable: true` with a reachable `remove`/`simplify`/`keep`. Re-check the `k` in AR-12 after deciding MED-002.
**Reference:** CWE-682 Incorrect Calculation — https://cwe.mitre.org/data/definitions/682.html; Karpathy 4 (goal-driven: non-trivial logic without a runnable check that fails when it breaks).

---

## Medium/Low Priority Issues

### [MED-001] The refusal fences the `eval_only` flag, not the `oracle_open` behaviour
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:258-259`
- **Issue:** `if [[ "$EVAL_ONLY" == true && "${LOA_ABLATION_BATCH_CONTEXT:-}" != 1 ]]` reads the arm's `eval_only` flag. The invariant "oracle_open ⇒ eval_only" lives only in `head/evals/harness/validate-suite.sh:179-180`, which pipeline-run.sh never runs, and `--suite-file` accepts any file. A suite with `eval_only` deleted from a1_full_openmount (the shape VS-17 rejects) runs the open mount — answer paths visible to the agent — outside a batch with no check. Impact is bounded: such rows carry no batch manifest, so `list_reason` (`head/evals/harness/ablation-report.py:1108-1123`) lists them and they never enter a cell. Confirmed by the review's DISS-C-002.
- **Fix:** also refuse, outside the batch context, when `SUITE_TOGGLES.oracle_open == true`, so the fence sits on the toggle that exposes the oracle.
- **Reference:** CWE-693 Protection Mechanism Failure — https://cwe.mitre.org/data/definitions/693.html

### [MED-002] a0_bare_fable is a baseline counted as a component
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/ablation-report.py:1913` (suite comment `head/evals/suites/ablation-2.0.yaml:94-95`, arm `:98`)
- **Issue:** `components = [... if a["id"] not in (CONTROL, BARE) and not a.get("absent") and a.get("eval_only") is not True]` excludes only `a0_bare`; the suite describes a0_bare_fable as "A0 on the review model", a bare baseline. It therefore gets a keep/remove/simplify row against a1_full — a "remove: a0_bare_fable" decision has no meaning — and inflates `k` and the AR-12 expectation by one.
- **Fix:** mark baseline arms (a `baseline: true` key, or `loa_mount: false`) and exclude them from `components`; render a0_bare_fable beside H1 as the Fable-side bare contrast, or document in the suite why a bare-model arm is a component decision.
- **Reference:** CWE-1068 Inconsistency Between Implementation and Documented Design — https://cwe.mitre.org/data/definitions/1068.html

### [MED-003] `priority` not extended: the new decision arms never run by default
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/suites/ablation-2.0.yaml:55`
- **Issue:** run-ablation.sh defaults `--arms` to `priority` minus absent arms (`head/evals/harness/run-ablation.sh:570-571`). a0_bare_fable, a1_review_only and a1_no_dissent are absent from `priority`, so a batch without `--arms` never runs them, while the report counts `k = 9` in the pre-registered expected-false-positive line and prints a `no_rows` decision for each.
- **Fix:** add the three decision arms to `priority` (not a1_full_openmount), or have the report count only arms the batch planned and document that cycle-131 arms are opt-in.
- **Reference:** CWE-684 Incorrect Provision of Specified Functionality — https://cwe.mitre.org/data/definitions/684.html

### [MED-004] PR description claims work absent from the diff
- **Severity:** MEDIUM (confidence: high)
- **File:** `pr/PR.md:1`
- **Issue:** the title names "the cycle-131 suite root (bounds 50/40) with its image self-check"; none of the 11 files in `pr/head.diff` touches a suite root, bounds or an image self-check. Those are evaluation-integrity controls; either the diff is incomplete or the title overstates. The merge record must match the merged content.
- **Fix:** reconcile the title with the diff, or add the missing files and their tests.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-001] Dry-run `config_edits` hand-duplicates the mount library's mapping
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:341-345`
- **Issue:** the dry-run line re-implements apply_arm_toggles' toggle→config mapping in jq from the raw `SUITE_TOGGLES`, whereas the run uses the library-resolved `TOGGLES` (`:510-515`); karpathy_block, rule_files and audit_delta_instruction are not listed, so a mapping change in lib/sandbox-mount.sh makes the dry run misreport the sandbox.
- **Fix:** expose the planned edits from the library (a `describe_arm_toggles` call) and print that, or state in the header that the line summarises four toggles only.
- **Reference:** CWE-1041 Use of Redundant Code — https://cwe.mitre.org/data/definitions/1041.html

### [LOW-002] Hand-copied toggle vocabulary in the validator
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/validate-suite.sh:137-139`
- **Issue:** `TOGGLE_VALUES` copies lib/sandbox-mount.sh's vocabulary while `RULE_IDS` (`:87`) is derived from took-effect.sh; a toggle added to the library without this edit is rejected with an "unknown toggle" message that points at the suite rather than the copy.
- **Fix:** derive the vocabulary from the library the way `RULE_IDS` is derived.
- **Reference:** CWE-1041 — https://cwe.mitre.org/data/definitions/1041.html

### [LOW-003] Stale comment: "over 6 components"
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/suites/ablation-2.0.yaml:117`
- **Issue:** `k` is now 9 (AR-12 asserts it) and AR-12 quotes the rules block verbatim into every report's Method section, so the wrong figure is reproduced in the report.
- **Fix:** update after deciding MED-002 and MED-003.
- **Reference:** CWE-1116 Inaccurate Comments — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-004] `eval_only` is read with different type rules by its three readers
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/pipeline-run.sh:258` (and `head/evals/harness/ablation-report.py:1913`)
- **Issue:** `[[ "$(jq -r '.eval_only // false' <<<"$ARM_DEF")" == true ]]` treats the YAML string `"true"` as eval_only (fail-closed) but `1` or `"yes"` as not eval_only (fail-open), while the report's `a.get("eval_only") is not True` keeps a string-valued arm as a component. validate-suite.sh rejects non-booleans and run-ablation.sh runs it as the hard gate for non-smoke batches, so the gap is confined to hand-run suites.
- **Fix:** read with `jq -e '.eval_only == true'` so only the boolean opens the eval_only path, matching the validator and the report.
- **Reference:** CWE-1287 Improper Validation of Specified Type of Input — https://cwe.mitre.org/data/definitions/1287.html

### [LOW-005] The open-mount A/B arm is never rendered
- **Severity:** LOW (confidence: medium)
- **File:** `head/evals/harness/ablation-report.py:2003`
- **Issue:** a1_full_openmount's rows pass `list_reason` and enter cells, but `detail_arms = [BARE, CONTROL] + components` holds neither it nor a section for eval_only arms, so the open-mount A/B that is run and paid for never appears; only its oracle-exposed rows surface in the sensitivity count (`:1624`). (Review DISS-C-004, confirmed as a gap outside this sprint's stated scope.)
- **Fix:** render eval_only arms in an evaluation-controls section beside the sensitivities.
- **Reference:** CWE-684 — https://cwe.mitre.org/data/definitions/684.html

### [LOW-006] The batch-context variable is a misuse guard, documented as a batch-only control
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/suites/ablation-2.0.yaml:96-97` (header `head/evals/harness/validate-suite.sh:50-53`)
- **Issue:** `LOA_ABLATION_BATCH_CONTEXT=1` is self-attested — any shell can set it, and pipeline-run.sh's own header (`head/evals/harness/pipeline-run.sh:141-146`) documents the operator doing so for dry runs — yet the suite comment says the arm is "refused outside a run-ablation.sh batch or smoke". Rows produced ad hoc have no batch manifest and are listed, never celled, by the report, which bounds the consequence. Raised independently by this audit's companion voice (DISS-C-001).
- **Fix:** reword the suite comment to name the variable as the fence; optionally record `eval_only` and the batch id in `meta/pipeline.json` so the report can quarantine eval_only rows lacking batch provenance.
- **Reference:** CWE-807 Reliance on Untrusted Inputs in a Security Decision — https://cwe.mitre.org/data/definitions/807.html

### [LOW-007] Implementation report carries no self-check evidence
- **Severity:** LOW (confidence: high)
- **File:** `pr/PR.md:3`
- **Issue:** the report is a title and a file count: no AC verification, no record that the bats suites, shellcheck or the formatter ran, no stated assumptions. The bats suites could not be executed here, so the audit cannot confirm they pass.
- **Fix:** add the self-check evidence and an AC walkthrough on resubmission.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

---

## Review demotions confirmed

The review trailer carries `excluded: 0`: no high was demoted to Observations, so there is nothing to confirm or re-tally. `excluded_confirmed` is 0.

---

## Cross-Model Security Observations

Dissent envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — status `clean`, two voices (primary gpt-5.5-pro, companion claude-headless, `counted_as: independent_voice`, `voices_succeeded: 2`), `degraded: false`, no DEGRADED_SECURITY_REVIEW. The envelope's `model_attempts` names gpt-5.5-pro while `voices_succeeded_ids` and `companion_voice.primary_succeeded_model` name codex-headless; both are OpenAI-family, so independence from the Anthropic companion holds. Advisory voices: none.

- DISS-C-001 (LOW, claude-headless): the eval_only refusal is gated on a self-attested environment variable and the wording implies a trust boundary that does not exist → **LOW-006** above (confirmed; impact bounded by the manifest requirement in `list_reason`).
- DISS-C-002 (LOW, claude-headless): `LOA_ABLATION_BATCH_CONTEXT` may be inherited by the agent executor → **not a defect**. The agent's environment is built from the explicit `envkv` allowlist (`head/evals/harness/pipeline-run.sh:833-847`), filtered again by `ENV_SHIM` (`:797`, applied at `:858` for the container and `:868` for the host), and the only dynamic additions are `LOA_*` lines the mount library writes to `ARM_ENV_FILE` (`:844-847`); the variable is in none of them, so the model under test never sees it.
- Primary voice (gpt-5.5-pro): no finding met the bar — "not an approval of unreviewed surface". Agreed: the surface was traced in `grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md`.

## Rejected dissent payloads

None — `metadata.rejected_summary` is empty, `metadata.rejected_sidecars` is empty, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Input validation at the trust boundary: suite values type-checked (`validate-suite.sh:157-180`); env value compared to the exact string `1`; rule ids read by a fixed regex from a sibling path into a `python3 -I` set
- [x] No shell injection: arm ids and suite values flow through `jq --arg`/heredocs/argv, never into eval'd strings
- [x] Error handling doesn't leak info: refusal names arm id and reason only
- [x] Agent isolation preserved: the batch-context variable never reaches the agent (allowlist + env shim)
- [x] Tests cover the refusal paths: exact-value rule, no run dir, no argv log, dry run refused (`pipeline-run.bats:1223-1244`); batch and smoke launches marked, non-vacuous `<unset>` check (`run-ablation.bats:1189-1209`)
- [ ] Tests cover the report path for the new arms with data — missing (HIGH-001)
- [ ] n/a: authentication, SQL/XSS, dependency CVEs (no such surfaces in the change)
- Note: `LOA_ABLATION_BATCH_CONTEXT` is an operator misuse guard, not a security boundary (LOW-006); the open-mount leak is bounded because ad hoc rows have no batch manifest.

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input Validation | 4 | type-exact validator; pipeline-run reads `eval_only` loosely (LOW-004) |
| SEC-AZ Authorization | 4 | refusal before side effects; fence on the flag, not the behaviour (MED-001) |
| SEC-CI Confidentiality/Integrity | 5 | agent env allowlisted; oracle rows labelled |
| SEC-IN Injection Prevention | 5 | jq `--arg`, heredocs, `python3 -I` |
| SEC-AV Availability | 4 | no new resource paths |
| ARCH-MO Modularity | 3 | two hand-copied vocabularies (LOW-001, LOW-002) |
| ARCH-ST Standards Compliance | 3 | baseline counted as component; priority not extended (MED-002, MED-003) |
| CQ-TC Test Coverage | 2 | report path of FR-5 untested with data (HIGH-001) |
| CQ-DC Documentation | 3 | PR title mismatch; stale comment; overstated fence (MED-004, LOW-003, LOW-006) |
| DO-DS Deployment Safety | 4 | refusal and dry run honour the same gate |

Security 4.4 · Architecture 3.3 · Code Quality 3.0 · DevOps 4.0 — overall 3.7, risk MODERATE. Machine-readable findings: `grimoires/loa/a2a/audits/2026-10-21/findings.jsonl`.

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001: give review-catch-only arms a review-only primary set in `primaries()` and the suite rules; add a data-bearing ablation-report.bats case for a review-catch-only component.
2. Decide a0_bare_fable's role and whether the new arms join `priority` (MED-002, MED-003); update the AR-12 constant and the suite comment at `:117`.
3. Fence `oracle_open` outside the batch context in pipeline-run.sh (MED-001); align the `eval_only` read with the validator (LOW-004).
4. Reconcile the PR title with the diff and add self-check evidence to the report (MED-004, LOW-007).
5. Run `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and `/audit-sprint sprint-1` again.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":4,"low":7},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:14:12Z"} -->
