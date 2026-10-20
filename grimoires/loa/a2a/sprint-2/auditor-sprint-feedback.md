# Sprint 264 Security Audit Feedback

**Auditor:** Fable 5.1 lead (auditing-security contract; audit dissent run = this sprint's second of three dissent runs)
**Date:** 2026-10-20
**Sprint Reference:** grimoires/loa/sprint.md § Sprint 2 (global 264)
**Implementation Report:** grimoires/loa/a2a/sprint-2/reviewer.md
**Scope:** `e93a040a..798d88cf` — Tasks 2.1/2.2 `0281ea57`, review round r2a `c0d42907`, audit round r2b `798d88cf` (code only; the suite root's task files, fixtures and planning docs excluded from the dissent diff by the driver)

---

## Verdict: APPROVED - LET'S FUCKING GO

---

## Executive Summary

Sprint 264 adds a declarative surface (four arms), a validator for it, an evaluation-only guard and a frozen suite root; nothing new reaches the harness from the graded agent. The lead's pass found the surface guarded at the validator and at the runtime. The audit dissent (gpt-5.5-pro + claude-headless; this sprint's second of three runs) returned two MEDIUM findings and one LOW, all accepted: a quoted `oracle_open: "true"` would have opened the mount through the loose toggle read while the strict evaluation-only guard stayed false (a one-character suite edit bypass), and the report derived evaluation-only status from the flag alone. Round r2b fixed both test-first (`pipeline-run.sh` holds `toggles.oracle_open` to the JSON-boolean rule; `ablation-report.py` derives evaluation-only status from the toggle too and refuses an open-oracle arm without `eval_only: true`). The LOW — the batch context is an inheritable, unauthenticated environment variable — is accepted at the level it was designed for (an accident guard against by-hand runs of the open mount, not a security boundary; the header says so) and carried as bead bd-st02i (argv flag recorded in the evidence). No open finding above LOW remains.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 1 |

---

## Findings of the audit dissent run and their re-check (round r2b)

| Id | Severity (as found) | Finding | Fix | Re-check |
|---|---|---|---|---|
| MED-001 (DISS-C-001) | MEDIUM | `oracle_open: "true"` (YAML string) opened the mount via `jq -r` text comparison while the strict guard read false | a present `toggles.oracle_open` that is not a JSON boolean is refused (exit 2) before any run directory, like `eval_only` | pipeline-run.bats: quoted toggle → exit 2 with the reason. **Resolved.** |
| MED-002 (DISS-C-002) | MEDIUM | the report excluded only `eval_only: true` arms from components; an open-oracle arm without the flag would have been a component | `is_eval_only(a)` = flag or `toggles.oracle_open is True`; an open-oracle arm without the flag raises `Fail` | AR-12b: a suite with such an arm fails with the message and writes no report. **Resolved.** |
| LOW-001 (DISS-C-003) | LOW | `LOA_ABLATION_BATCH_CONTEXT=1` is inheritable and unauthenticated; `export` in a shell disables the guard for that session | none in this sprint: the guard is documented as an accident guard, the arm is also `eval_only` and absent from `priority`; argv flag + evidence record → bead bd-st02i | **Open, accepted** (observation). |

## Open Issues

LOW-001 (accepted, bead bd-st02i). The severity tally counts it.


## Trust boundaries read (lead pass)

- **Suite file → runner:** the four arms are declarative; `validate-suite.sh` rejects unknown toggles, non-defined values (type-exact), unknown rule ids and a non-boolean `eval_only`, and insists `oracle_open ⇒ eval_only`; `pipeline-run.sh` re-derives the evaluation-only property from `oracle_open` itself and refuses outside the batch context before any run directory exists. The batch-context variable is a convention against accidental by-hand runs of the open mount, not a security boundary, and is documented as such.
- **Rule-id extraction:** `validate-suite.sh` reads `rule_<id>()` names from `took-effect.sh` beside itself (a fixed sibling path, not an argument); an empty set is fatal.
- **Suite root:** `grimoires/loa/evals/ablation-2.0-c131/` is a byte-identical copy of the replication tasks except the declared bounds; frozen (`MANIFEST.sha256`), validated, self-checked in the image (6/6); the README names the copy, the bounds DEC, the run cap and the eval config variant.
- **Credentials and network:** unchanged; no new dependency; no new network call. The arm smoke's rows and envelopes hold no credential material (checked: evidence lines, envelopes, `models_used`).
- **Agent-controlled input:** nothing new reaches the harness from the agent in this sprint (the detector/grader hardening of Sprint 263 stands).

## Security Checklist for This Sprint

- [x] No hardcoded secrets added
- [x] Input validation on the new declarative surface (suite arms) and the new refusal path
- [x] No new privilege; the open-mount arm cannot run outside a runner batch or smoke
- [x] No injection path (yq expressions take env values; jq reads JSON)
- [x] Error messages name arms and paths only
- [x] Tests cover the new paths (VS-14 … VS-17, pipeline-run +7, RAB-c131-5, AR-12 line)

---

## Rejected dissent payloads

The audit dissent's sidecar holds no rows; the review run's sidecar holds no rows.

<!-- LOA-VERDICT {"gate":"audit","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":1},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-264","ts":"2026-10-20T04:01:15Z"} -->
