# Sprint 1 Security Audit Feedback

**Auditor:** Paranoid Cypherpunk Auditor
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Task:** review-r25 — `/audit-sprint sprint-1`

---

## Verdict: CHANGES_REQUIRED

---

## Pre-flight record

- **Prerequisite deviation.** Phase 0 requires `engineer-feedback.md` to say "All good"; the senior review's verdict is CHANGES_REQUIRED (1 HIGH). The task instruction directs the audit to run regardless, so it ran; this report does not replace the review's required fix.
- **Integrity pre-check:** `.loa.config.yaml` carries no `integrity_enforcement` key; proceeded.
- **Guardrails:** `guardrails-orchestrator.sh` → `PROCEED` (injection check reported `ERROR`, fail-open).
- **Scope:** `pr/head.diff`, 12 files under `evals/` (shell harness with embedded Python, bats tests, one suite yaml). `security-audit-scope.sh --json` found 0 sources/sinks (its patterns target web code); recon done by hand in `grimoires/loa/a2a/audits/2026-10-21/SECURITY_ANALYSIS_TODO.md`.
- **known-failures.md** is absent (session hook warning); triaged without it. `br` is not installed; beads steps skipped.
- **Scope limits:** the v2 task tree (`grimoires/loa/evals/ablation-2.0/`), `seed-*.sh` and `spend.sh` are referenced by the diff but not in it — "Unable to verify" where noted.

---

## Executive Summary

The security posture of the change is sound where it handles credentials: the KF-048 copy in `pipeline-run.sh` writes the per-run `auth.json` through a 0600 fd with `python3 -I` and argv-only paths, replaces the single-use refresh token with a placeholder, never writes the host file, and its failure path removes the partial copy with one WARN (`head/evals/harness/pipeline-run.sh:622-645`). The pre-flight reads only the JWT `exp` claim and prints no token material (RAB-28 asserts this). The per-kind cap chain validates every cap with `usd_ok`, including MANIFEST values on `--resume`, and refuses malformed suite entries rather than skipping them. jq uses `--arg`; no eval, no injection surface introduced.

One finding blocks. The grader's new `remove_colliding` (grader 1.2.11) performs a destructive action — unlinking agent-produced files from the grading tree — on a predicate far wider than the pytest basename collision it targets. It reserves every `.py` basename from the hidden overlay and from every fixture directory under `tests/`/`test/` (helper modules included; the grader's own comment at `:221` says fixtures do `from helpers import …`), then deletes any agent-added file anywhere in the tree with that basename, including package modules that cannot collide. A correct solution adding `src/pkg/helpers.py` loses it before `test_command` runs and grades as failing, and the deletion is recorded as a "collision", hiding the cause. This is an integrity defect in the evaluation data the harness exists to produce. Both dissent rounds raised it independently (review: DISS-C-001 BLOCKING; audit: DISS-C-002 MEDIUM).

The codex pre-flight horizon is unsafe at one end (no floor at the longest single trial) and unusable at the other (sums all trials of all arms, doubles an already-doubled watchdog), and it refuses API-key-mode `auth.json` files. These are MEDIUM: they cause degraded rows or refused batches, not credential exposure.

**Security Issues Found:**
| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 5 |
| Low | 7 |

---

## Critical Security Issues (Must Fix)

None.

---

## High Priority Security Issues (Fix Before Deployment)

### [HIGH-001] Grader deletes non-colliding agent source files before grading

**Severity:** HIGH (confidence: high)
**File:** `head/evals/harness/ablation-grade.sh:1081` (overlay basenames), `:1087` (fixture basenames), `:1090-1100` (removal walk and unlink)
**Issue:** The reserved set is built from every overlay `.py` basename and every fixture `.py` under a `tests`/`test` component:
```python
reserved = {d.rsplit("/", 1)[-1] for d in owned if d.endswith(".py")}                       # :1081
...
reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))   # :1087
```
and the walk at `:1090-1098` visits every directory of the tree (`src/`, `app/`, an agent-created `.venv/`), unlinking at `:1100` any file with a reserved basename that is not an overlay dest, under an overlay dir, or present in the fixture. pytest's "import file mismatch" arises only for modules pytest itself imports by basename: collected test modules (`python_files`, default `test_*.py` / `*_test.py`) in package-less directories, plus `conftest.py`. `tests/helpers.py`, `tests/_oracle_x.py`, `tests/utils.py` or data `.py` under `tests/fixtures/` never collide, yet their names are reserved; a module inside a package (imported as `pkg.helpers`) cannot collide, yet it is deleted.
**Impact:** `prepare()` runs this on `final`, `base`, `implement` and `fix1` trees (`:1019`, callers `:1708`, `:1723`, `:1748`). A correct solution whose new source module shares a basename with any fixture helper is removed from `grading/final`; the hidden suite ImportErrors; the row records a failing solution and `colliding_tests_removed` counts it as a collision. Snapshot trees are affected the same way, so gate verdict accuracy is biased too. This is a systematic bias against solutions that use common module names, invisible in the pass/fail metric, in the arm comparison the harness measures.
**PoC:**
```
fixture: tests/helpers.py, tests/test_slug.py
agent adds: src/pkg/__init__.py, src/pkg/helpers.py   (imported by src/pkg/core.py)
grade → remove_colliding reserves {"helpers.py", "test_slug.py"}; src/pkg/helpers.py is not in fixture → unlinked
test_command → ImportError: cannot import name 'helpers' from 'pkg' → hidden_tests 0/N, colliding_tests_removed 1
```
**Fix:**
```python
def is_test_module(n):
    return n.endswith(".py") and (n.startswith("test_") or n.endswith("_test.py"))
reserved = {d.rsplit("/", 1)[-1] for d in owned if is_test_module(d.rsplit("/", 1)[-1])}
...
reserved.update(n for n in fs if is_test_module(n))
# in the walk: skip files whose directory holds an __init__.py (package-qualified, no collision)
# and skip EXCLUDE_ANY-style dirs (.venv, node_modules)
```
Read `python_files` from the fixture's `pytest.ini` / `pyproject.toml` / `setup.cfg` when present. Add an AG case: fixture `tests/helpers.py`, agent `src/pkg/helpers.py`, assert the file survives and `colliding_tests_removed == 0`.
**Reference:** CWE-20 Improper Input Validation (the collision condition is not validated before a destructive action) — https://cwe.mitre.org/data/definitions/20.html; pytest import modes — https://docs.pytest.org/en/stable/explanation/pythonpath.html
**Cross-model:** Confirmed by cross-model review (review dissent DISS-C-001 BLOCKING; audit dissent DISS-C-002 MEDIUM, claude-headless).

---

## Medium/Low Priority Issues

### [MED-001] Overlay-derived reserved names are not filtered for `__init__.py`
- **Severity:** MEDIUM (confidence: low)
- **File:** `head/evals/harness/ablation-grade.sh:1081`
- **Issue:** The fixture walk at `:1087` excludes `__init__.py` and `conftest.py`; the overlay set at `:1081` excludes nothing (`:1088` discards `conftest.py` only). An overlay dest named `__init__.py` reserves that basename and every agent-added package `__init__.py` outside fixture paths is deleted.
- **Fix:** Apply the same exclusion to the overlay-derived names (the test-module filter of HIGH-001 subsumes it).
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html

### [MED-002] Directory overlays are protected but never reserved
- **Severity:** MEDIUM (confidence: low)
- **File:** `head/evals/harness/ablation-grade.sh:1079-1080`
- **Issue:** `owned` excludes directory overlays (`not os.path.isdir(f)`), so test basenames inside a directory overlay are never added to `reserved`; `owned_dirs` at `:1080` only protects them at `:1096`. A collision with a test delivered as a directory overlay still aborts collection, while `colliding_tests_removed` reports 0.
- **Fix:** Walk directory overlays and reserve their collected-test basenames.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html
- **Cross-model:** Confirmed by cross-model review (audit dissent DISS-C-003 LOW).

### [MED-003] Codex horizon has no floor at the longest single trial
- **Severity:** MEDIUM (confidence: high)
- **File:** `head/evals/harness/run-ablation.sh:806`
- **Issue:** `required = now + 2 × Σ watchdog_s / concurrency`. One a1_full build trial (watchdog 16800 s) at `--concurrency 9` yields a 62-minute horizon although the trial's phase budget is 140 min. A token expiring at 90 min passes and expires mid-trial; with the placeholder refresh token (`pipeline-run.sh:633-636`) the container cannot renew it, so every later codex phase degrades.
- **Fix:** `required = now + max(max(watchdog_s), 2 × Σ watchdog_s / min(conc, len(plan)))`.
- **Reference:** CWE-672 Operation on a Resource after Expiration — https://cwe.mitre.org/data/definitions/672.html

### [MED-004] The same horizon is unsatisfiable for suite-sized or resumed batches
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/run-ablation.sh:806` (header `:116`: "on --resume the whole recorded plan counts")
- **Issue:** `watchdog_s` is already 2 × the phase sum; the horizon doubles it again and sums every trial of every arm, non-codex arms and already-rowed trials included. A full v2 batch needs a token valid for weeks; `codex login` yields about ten days (PR text: "token valid to 2026-10-28"), so the batch is refused unconditionally and the refusal's instruction cannot satisfy it. A `--resume` with two trials left is refused for a token with hours of validity. Operators will route around the guard (`--smoke`, plan edits), defeating KF-048.
- **Fix:** Size the horizon from remaining codex-using trials and an expected duration (phase sum or `est_next`), or downgrade an exceeded horizon to a WARN in `codex_preflight` plus a per-phase check in `pipeline-run.sh`.
- **Reference:** CWE-754 Improper Check for Unusual Conditions — https://cwe.mitre.org/data/definitions/754.html

### [MED-005] API-key-mode `auth.json` is refused
- **Severity:** MEDIUM (confidence: medium)
- **File:** `head/evals/harness/run-ablation.sh:814-817`
- **Issue:** `{"OPENAI_API_KEY": "sk-…", "tokens": null}` reaches `bad("has no tokens.access_token")` and every non-smoke batch (fresh, `--resume`, `--dry-run`) is refused with "run codex login on the host", which changes nothing on an API-key host. `pipeline-run.sh:633-636` copies such a file untouched (tokens is not a dict) and codex works with it; KF-048 does not apply to API keys.
- **Fix:** When `tokens` is null/absent and `OPENAI_API_KEY` is a non-empty string, record `checked: false` with a WARN; refuse only when neither is present.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html
- **Cross-model:** raised by the review dissent (DISS-C-002).

### [LOW-001] Collision count sums over trees; empty sidecars everywhere
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/ablation-grade.sh:1019`, `:1101`
- **Issue:** `COLLIDING[0]` accumulates across `prepare()` on `final`, `base`, `implement`, `fix1`, so `colliding_tests_removed` is a sum over trees; the sidecar at `:1101` is written even when `found` is empty, including `grading/base.colliding-removed.txt` beside the fixture copy. AG-35 covers the single-tree case only.
- **Fix:** Attribute the count to `final` (or document the sum, as `harness_files_removed` does); write the sidecar only when `found` is non-empty.
- **Reference:** CWE-1116 Inaccurate Comments/Documentation — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-002] Stale comment contradicts the assertion it annotates
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/tests/run-ablation.bats:93-97`
- **Issue:** The comment says "A0 BARE stays 70 min … the PLAN + IMPLEMENT + 2 x FIX derivation (80) does not apply"; the assertion on `:97` (and RAB-27 at `:104`) requires 9600 s, which is that 80-min derivation × 2.
- **Fix:** Delete the two stale sentences; keep the trailing "BARE = 15 + 35 + 2 x 15 on a v2 task" note.
- **Reference:** CWE-1116 — https://cwe.mitre.org/data/definitions/1116.html

### [LOW-003] v2 task tree and manifest are outside the diff
- **Severity:** LOW (confidence: low) — Unable to verify
- **File:** `head/evals/suites/ablation-2.0.yaml:31`
- **Issue:** `suite_version: 2` and the v2 ids used throughout `run-ablation.bats` (RAB-27 at `:104` requires exactly twelve build tasks) depend on `grimoires/loa/evals/ablation-2.0/{tasks,MANIFEST.sha256}`, not in this PR. If the target branch lacks them, `validate-suite` fails every task and the runner suite fails on "task not found".
- **Fix:** Confirm the frozen v2 tree lands in the same merge.
- **Reference:** CWE-1059 Insufficient Technical Documentation — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-004] `run_usd` single-cap fallback stays 12 under 15/20 effective caps
- **Severity:** LOW (confidence: low)
- **File:** `head/evals/suites/ablation-2.0.yaml:41`
- **Issue:** Any reader other than `run-ablation.sh` that sizes `--max-usd` or the in-flight reservation from `caps.run_usd` (the comment at `:36-37` names `spend.sh`) under-reserves by up to 8 USD per in-flight trial against the 1,500 USD cycle cap.
- **Fix:** Single-cap readers take `max(run_usd_by_type[*]) // run_usd`, or raise `run_usd` to 20.
- **Reference:** CWE-770 Allocation of Resources Without Limits — https://cwe.mitre.org/data/definitions/770.html
- **Cross-model:** raised by the review dissent (DISS-C-005).

### [LOW-005] `--suite-version` passed to seed scripts outside the diff
- **Severity:** LOW (confidence: low) — Unable to verify
- **File:** `head/evals/tests/seed-bugfix.bats:80`, `head/evals/tests/seed-refactor.bats:78`
- **Issue:** If `seed-bugfix.sh` / `seed-refactor.sh` do not already accept `--suite-version`, both tests fail at argument parsing.
- **Fix:** Confirm the flag exists on the target branch.
- **Reference:** CWE-1059 — https://cwe.mitre.org/data/definitions/1059.html

### [LOW-006] Pre-flight dies on an out-of-range `exp`; EACCES reported as "is not JSON"
- **Severity:** LOW (confidence: high)
- **File:** `head/evals/harness/run-ablation.sh:830` (and `:812-813`)
- **Issue:** `:827` checks type and `isfinite` only; a finite out-of-range value (e.g. `1e300`) passes, `int(exp)` succeeds, and `iso(exp)` → `time.gmtime` raises `OverflowError` uncaught, so the batch dies via `die "the codex token pre-flight failed"` with a traceback and no `REFUSED.txt`. The `except` at `:812` also maps an unreadable file (permissions) to "is not JSON".
- **Fix:** Bound `exp` (e.g. `0 < exp < 10**10`) before `iso()`; catch `OSError` separately with its own message.
- **Reference:** CWE-754 — https://cwe.mitre.org/data/definitions/754.html

### [LOW-007] New cap parameters in the shared spend library are unvalidated
- **Severity:** LOW (confidence: low)
- **File:** `head/evals/harness/lib/arms-common.sh:129`, `:143`, `:146`
- **Issue:** `spend_charge`'s `cap` and `budget_gate`'s `per` go straight to `fadd`/awk without the numeric regex applied to `cost`; a malformed value evaluates to 0 and silently disables the assumed charge or the in-flight reservation. Today's only caller (`run-ablation.sh`) validates with `usd_ok`; `run-arms` uses the default.
- **Fix:** Apply the `cost` regex (or `usd_ok`) to `cap`/`per`, falling back to `RUN_CAP` with a logged warning.
- **Reference:** CWE-20 — https://cwe.mitre.org/data/definitions/20.html
- **Cross-model:** from the audit dissent (DISS-C-004 LOW).

---

## Severity Tally

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 1 |
| Medium | 5 |
| Low | 7 |

Excluded (speculative, low-confidence high/critical): 0. Review trailer `excluded`: 0; confirmed 0 (`excluded_confirmed`: 0).

---

## Observations (not tallied)

- **Pre-existing, narrowed by this PR:** the per-run HOME still carries the live `tokens.access_token` and `tokens.id_token` readable by the agent under evaluation inside the container (`head/evals/harness/pipeline-run.sh:622-645`). The base copied the whole file verbatim, refresh token included; the PR removes the refresh token only. Not introduced here, so not tallied; see Cross-Model DISS-C-001 for the dissent's proposed hardening (copy only for codex-using arms, strip `id_token`).
- `--smoke` skips the pre-flight (`:785`); a smoke batch with an expired token degrades its codex rows. By design per the header; noted.

---

## Cross-Model Security Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-audit.json` — `metadata.status: clean` for the primary (configured `gpt-5.5-pro`, answered by `codex-headless`, no findings), companion `claude-headless` succeeded, `counted_as: independent_voice`, `degraded: false`, two voices succeeded of two planned. Not DEGRADED_SECURITY_REVIEW. Input note: the dissenter's context was truncated to budget (`run-ablation.bats` shown 6 of 28 hunks).

| ID | Severity | Anchor | Triage |
|----|----------|--------|--------|
| DISS-C-001 | MEDIUM (secrets) | `pipeline-run.sh:622-645` | Valid description, but pre-existing behaviour that this PR narrows (refresh token removed). Recorded under Observations, not tallied; hardening suggestions carried forward. |
| DISS-C-002 | MEDIUM | `ablation-grade.sh:1084-1100` | Same defect as HIGH-001; confirmed by cross-model review. Tallied once as HIGH-001. |
| DISS-C-003 | LOW | `ablation-grade.sh:1081` | Same as MED-002; confirmed by cross-model review. |
| DISS-C-004 | LOW | `arms-common.sh:128-129` | Valid defense-in-depth gap; tallied as LOW-007. |

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty, `rejected_sidecars` is `[]`, and no `adversarial-rejected-audit*.jsonl` exists beside the envelope.

---

## Rubric Scores

| Dimension | Score | Basis |
|-----------|-------|-------|
| SEC-IV Input validation | 4 | caps/MANIFEST validated via `usd_ok`; jq `--arg`; LOW-006/007 gaps |
| SEC-CI Confidentiality | 4 | 0600 fd write, placeholder refresh token, no token in logs; access token still in sandbox (pre-existing) |
| SEC-AV Availability | 3 | pre-flight refuses valid configurations (MED-004, MED-005) |
| ARCH-MO Modularity | 4 | `cap_for`, `suite_kind_cap`, optional lib params with defaults |
| CQ-RD / correctness | 2 | destructive predicate wider than its target (HIGH-001); stale comment |
| DevOps / tests | 4 | RAB-22…34, AG-35, three KF-048 pipeline cases; missing the negative case for HIGH-001 |

---

## Security Checklist for This Sprint

- [x] No hardcoded secrets added (placeholder string only; RAB-28 asserts no token material in refusals)
- [x] Input validation at trust boundaries (`usd_ok` on every cap incl. MANIFEST; malformed suite map refused; JWT payload decoded defensively, no signature trust implied)
- [x] Credential copy: `os.open(..., 0o600)` + `fchmod`, `python3 -I`, host file never written, failure path removes the partial copy
- [x] No injection vectors introduced (jq `--arg`, python argv, no eval)
- [x] Error handling doesn't leak token material (paths and timestamps only)
- [ ] Destructive action guarded by a precise condition — **no**: `remove_colliding` (HIGH-001)
- [ ] Tests cover the negative path of the new destructive rule — **no**: AG-35 covers only the true-collision case

---

## Documentation Audit

No `grimoires/loa/a2a/subagent-reports/documentation-coherence-*.md` exist in this frozen workspace; verified manually. The header comments of `run-ablation.sh` (`:31-37`, `:107-121`, `:188-200`, `:219-230`), `pipeline-run.sh` (`:83-88`, `:601-611`) and `ablation-grade.sh` (`:220-226`) and the suite yaml comment (`:35-40`) describe the new behaviour accurately; the security-relevant KF-048 change is documented at the copy site. One inaccurate comment: LOW-002. No secrets or internal URLs in docs or comments.

---

## Acceptance Criteria Check

Sprint criterion: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict".

| Area | Status | Notes |
|------|--------|-------|
| Grader 1.2.11 removes only true pytest collisions | Fail | HIGH-001, MED-001, MED-002 |
| Per-kind run caps (chain, dispatch, charges, reservation, MANIFEST, resume) | Pass | `run-ablation.sh:500-515`, `:850-854`, `:1043-1055`, `:1186`; RAB-22…26 |
| `--types` filter | Pass | `run-ablation.sh:565` (`.type as $t`); RAB-27 |
| KF-048 credential copy | Pass | `pipeline-run.sh:622-645`; three pipeline-run cases |
| KF-048 pre-flight | Partial | implemented and tested (RAB-28…34); horizon and API-key defects MED-003…005 |
| Suite v2 + tests on v2 ids | Unable to verify | task tree not in the diff (LOW-003) |

---

## Next Steps

**CHANGES_REQUIRED:**
1. Fix HIGH-001: narrow `remove_colliding` to pytest-collected test-module basenames in package-less directories; add the `tests/helpers.py` vs `src/pkg/helpers.py` regression case (covers MED-001/MED-002 if the overlay set is built the same way).
2. Rework the pre-flight horizon (floor at the longest trial; size from remaining codex trials) and accept API-key `auth.json` (MED-003…005); bound `exp` (LOW-006).
3. Fix the RAB-1 comment; confirm the v2 task tree and the seed `--suite-version` flag exist on the target branch.
4. Run `/implement sprint-1` for the fixes, then `/review-sprint sprint-1` and re-run `/audit-sprint sprint-1`.

---

*Generated by Paranoid Cypherpunk Auditor Agent*

<!-- LOA-VERDICT {"gate":"audit","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":5,"low":7},"excluded":0,"excluded_confirmed":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:12:00Z"} -->
