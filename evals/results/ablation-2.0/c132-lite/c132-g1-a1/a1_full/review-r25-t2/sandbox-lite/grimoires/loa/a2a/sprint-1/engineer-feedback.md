# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff`: grader 1.2.11 (basename-collision removal), per-task-kind run caps (DEC-0567) threaded through `run-ablation.sh` and `lib/arms-common.sh`, the KF-048 codex credential handling (placeholder refresh token in `pipeline-run.sh`, access-token pre-flight in `run-ablation.sh`), the `--types` jq fix, suite v2 (`suite_version: 2`, `run_usd_by_type`), and the bats coverage for all of it.

Most of it is sound and well tested. The cap chain (`--run-cap` > suite `run_usd_by_type[kind]` > config > suite `run_usd` > 12) is implemented as documented, `--resume` reads caps from MANIFEST only, the in-flight reservation uses the largest cap over the plan's kinds, `spend_charge`/`budget_gate` keep their `RUN_CAP` defaults for other callers, the `--types` filter precedence is correct (RAB-27 proves it), the auth.json copy is written 0600 with the host file byte-identical and no token in argv (verified by the new pipeline-run tests), and the pre-flight prints no token material.

Two findings block merge. First, the new `remove_colliding` rule in the grader is broader than the pytest failure it fixes: it unlinks any agent-added `.py` anywhere in the tree whose basename matches a fixture `tests/` helper or an overlay module, which pytest never collides on; I reproduced that `tests/helpers.py` and `src/app/helpers.py` coexist under pytest's default import mode, so the grader would delete a correct solution's module and grade it failing — the exact harm 1.2.11 was written to prevent. Second, the KF-048 pre-flight horizon doubles an already-doubled watchdog and sums the whole plan, so the pre-registered A0/A1/A4 × 3-trial batch needs a token valid ~10.4 days ahead (the PR's own DEC-0593 token lived 10 days) while the batch's real wall time is ~2.6 days; the check also fires under `--executor host`, where `make_home` is not used and the CLI can refresh.

`reviewer.md` carries no `## AC Verification` section (it is the PR description), so the automatic CHANGES_REQUIRED rule applies as well; the code findings decide the verdict regardless.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Grader correctness — `remove_colliding` deletes non-colliding agent modules

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1087` — `reserved` takes every `.py` basename under the fixture's `tests/`/`test/` directories (helpers, oracles, support modules), and line 1093 removes any agent-added file in the whole tree with that basename, although pytest only collides on modules it collects (`test_*.py`, `*_test.py`, `conftest.py`) in package-less directories.
**File:** `head/evals/harness/ablation-grade.sh:1081-1098`
**Issue:** The PR's own commit text says fixture suites do `from helpers import …`, so fixtures ship `tests/helpers.py`-style modules. An agent that adds `src/<pkg>/helpers.py` (or `utils.py`, or any basename a fixture support module uses) as part of a correct solution has it unlinked from `grading/final` before `test_command` runs; the hidden tests then `ImportError` and the run is graded failing. Verified: with `tests/helpers.py`, `tests/test_a.py` (`from helpers import h`) and `src/app/helpers.py`, `python3 -m pytest tests` passes 2/2 — there is no pytest collision to prevent. The same over-breadth removes an agent's test module placed in a directory that has `__init__.py` (no collision under prepend mode either, verified 3/3 passing) and, because the walk is the entire tree with only `EXCLUDE_TOP`/`__pycache__` pruned, any same-named module inside a vendored tree or virtualenv in the snapshot (dissent DISS-C-003), inflating `colliding_tests_removed`.
**Why This Matters:** A correct solution graded as failing is silent measurement corruption in the H1/A4 ablation; 1.2.11 exists to remove exactly this class of false negative and re-introduces it in another shape.
**Required Fix:** Restrict `reserved` to basenames pytest actually imports by basename: the fixture-walk and the overlay set should keep only `test_*.py` / `*_test.py` (plus the existing conftest handling), and candidates should be limited to `.py` files that are themselves test modules in package-less directories (no `__init__.py` on the path from the collection root). Prune `.git`, `.venv`/`venv`, `node_modules`, `site-packages` from the walk. Add an AG case asserting that `src/app/helpers.py` survives beside a fixture `tests/helpers.py`.

### 2. Pre-flight — the codex horizon refuses batches the token would outlive, and fires in host mode

- **HIGH** (confidence: medium) `head/evals/harness/run-ablation.sh:806` — `required = now + 2 × Σ watchdog_s / concurrency`, but `watchdog_s` is already 2 × the phase-sum timeout (RAB-1: 16800 s for a 140-min phase sum), so the horizon is ~4 × the serial phase time / concurrency, and it is computed for every executor although only container mode (`pipeline-run.sh:648`, `make_home`) carries the non-refreshable placeholder credential.
**File:** `head/evals/harness/run-ablation.sh:780-838`
**Issue:** With the suite's own numbers (a0 build 9600 s, a1 build 16800 s, a4 build 6000 s, a1 review-catch 7200 s, a0 review-catch 8400 s; 12 build + 4 review tasks; 3 trials; concurrency 3) the pre-registered A0/A1/A4 batch sums to roughly 1.35 M s of watchdog, so `required_until` is about 10.4 days out while the batch's expected wall time is about 2.6 days. The PR's own DEC-0593 token was valid for 10 days after login, so a freshly logged-in operator is refused and told to `run codex login`, which cannot help. `--dry-run` is refused the same way (RAB-34 makes that deliberate). Under `--executor host` the check runs although `make_home` is never called and the host CLI refreshes its own token.

| Plan (3 trials, conc 3) | Σ watchdog_s | required horizon | expected wall time |
|---|---|---|---|
| A0 + A1 + A4, 12 build + 4 review | ≈1,353,600 | ≈10.4 d | ≈2.6 d |
| A0 + A1, 12 build | ≈950,400 | ≈7.3 d | ≈1.8 d |

**Why This Matters:** The runner refuses the batches it exists to launch, with a remediation message that is wrong for the case; operators will split batches or hand-edit to work around it, defeating the pre-registration discipline.
**Required Fix:** Compute the horizon from the phase-sum budget (Σ watchdog_s / 2, or the plan's `phase_sum_min`) with a bounded safety margin rather than another ×2; skip the check (record `checked: false`, reason `host`) when `EXECUTOR != container`; when `exp` is earlier than the horizon but later than a fresh login could ever reach, say so ("the batch outlives any codex token; split it") instead of prescribing `codex login`. Tie RAB-30's expected `required_until` to the new formula.

---

## Observations

### 1. `remove_colliding` — remaining gaps in the collision rule

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1081` — the overlay-derived basenames are not filtered for `__init__.py` while the fixture walk at line 1087 is; a hidden overlay that ships `tests/<dir>/__init__.py` makes every agent-added package `__init__.py` in the tree a removal target (a new package under `src/` loses its marker and its imports fail).
**Suggestion:** Apply the same `("__init__.py", "conftest.py")` exclusion to the overlay set (or adopt the test-module-only rule from Changes Required §1, which subsumes this).
**Benefit:** Removes a second path to grading a correct solution as failing.

- **MEDIUM** (confidence: medium) `head/evals/harness/ablation-grade.sh:1079` — directory overlays (`os.path.isdir(f)`) contribute nothing to `reserved`, so an agent test module whose basename collides with a test inside a directory overlay is not removed and the collection abort 1.2.11 targets still happens for those tasks.
**Suggestion:** Walk directory overlays for `test_*.py` basenames when building `reserved`.
**Benefit:** The fix covers every overlay shape the manifest format allows.

### 2. Pre-flight scope

- **MEDIUM** (confidence: high) `head/evals/harness/run-ablation.sh:794` — `codex_arms` is derived from the whole recorded plan, so a `--resume` that only re-rows (`--rerow …`) or resumes a batch with no trial left to launch is refused on an expired token although no pipeline call would run. The PR's own history re-rowed 24 rows under row writer 1.2; with a lapsed token that bookkeeping step would have been blocked until a re-login.
**Suggestion:** On `--resume`, derive `codex_arms` and the horizon from the trials that will actually launch (plan entries without a row, plus `--rerun` targets); skip the check when that set is empty.
**Benefit:** Bookkeeping resumes never depend on a live credential.

- **LOW** (confidence: low) `head/evals/harness/run-ablation.sh:793` — `uses_codex` treats every arm with `loa_mount != false` as codex-using; an arm whose toggles disable the review/audit gates (a4_no_gates) never runs the dissent, so an a4-only batch is refused on an expired token although it would not use the OpenAI voice.
**Suggestion:** Derive codex use from the toggles that actually drive the dissent (gates/dissent on), not from `loa_mount` alone.
**Benefit:** Fewer needless refusals; `codex_arms` in MANIFEST becomes accurate.

### 3. Per-kind cap validation (dissent DISS-001, accepted at reduced severity)

- **MEDIUM** (confidence: high) `head/evals/harness/run-ablation.sh:503` — `(.[$k] // "" | tostring)` maps a present `false` or `null` entry (and an empty string) to "", which the caller treats as "no entry" and silently falls back to `RUN_CAP`, contradicting the header's "a present entry that is not an amount in USD … is a usage error" (line 191) and RAB-22's intent. `run_usd_by_type: {build: ~}` launches build trials at 12 and records 12 as the effective cap.
**Suggestion:** Use `has($k)` to distinguish absent from present and validate every present value with `usd_ok`.
**Benefit:** A broken spend-control setting is refused instead of recorded as intentional.

### 4. Tests

- **LOW** (confidence: high) `head/evals/tests/run-ablation.bats:95` — the comment says "A0 BARE stays 70 min … the derivation (80) does not apply" while line 97 asserts 9600 s (= 2 × 80 min) with a trailing comment that says the opposite. One of the two is stale.
**Suggestion:** Delete the 70-min sentence.
**Benefit:** The next reader of the watchdog maths is not misled.

- **LOW** (confidence: low) `head/evals/tests/run-ablation.bats:828` — RAB-25 decides pass/fail by the relative order of `launch` and `done` lines in `run.log` with a stub that finishes in milliseconds and a 0.2 s poll; the "launches" branches (max 28 / 22) depend on the second launch being logged before the first trial's collection.
**Suggestion:** Give the stub a short sleep in these cases (or assert on `in_flight_reserved` in a cut record) so the ordering is deterministic.
**Benefit:** No intermittent failure in CI.

- **LOW** (confidence: low) `head/evals/tests/seed-bugfix.bats:80` and `head/evals/tests/seed-refactor.bats:78` — the tests now pass `--suite-version` to the seed scripts, and RAB-* reference `bugfix-v2-*`/`refactor-v2-*`/`feature-v2-*` task directories and the suite MANIFEST.sha256 under `grimoires/loa/evals/ablation-2.0/`; neither the seed scripts nor the frozen task set is in this diff, so this review could not confirm the flag exists or that the frozen tasks carry `suite_version: 2` (validate-suite compares each task to the suite file).
**Suggestion:** Confirm in the PR description that the seed scripts already accept `--suite-version` and that the frozen task set was re-frozen at suite_version 2.
**Benefit:** Closes the only part of the test surface this review could not execute or read.

### 5. Dissent advisories not adopted as findings

- **LOW** (confidence: low) `head/evals/harness/ablation-grade.sh:1100` — DISS-C-002 (claude-headless) says a read-only parent directory makes `os.unlink` raise and abort the grade. True, but `remove_harness` at line 1065 uses the same bare `os.unlink` on the same trees, so this is pre-existing behaviour, not something the change introduces; the dissent's claim that `remove_harness` goes through `remove_path` is incorrect. Worth a shared helper with `try/except OSError` when `remove_colliding` is reworked.

---

## Rejected dissent payloads

- None: `rejected_summary` is empty and `adversarial-rejected-review.jsonl` has zero rows. Both voices (gpt-5.5-pro primary, claude-headless companion) succeeded; envelope `grimoires/loa/a2a/sprint-1/adversarial-review.json`.

## Cross-Model Observations

- DISS-001 (gpt-5.5-pro, BLOCKING) — accepted as MEDIUM, Observations §3: real, but the fallback cap is sane and the input is a malformed suite file.
- DISS-C-001 (claude-headless, BLOCKING) — accepted as HIGH, Changes Required §2, after re-deriving the horizon from the suite's numbers and checking `make_home` is container-only.
- DISS-C-002 (claude-headless, ADVISORY) — recorded in Observations §5; pre-existing pattern.
- DISS-C-003 (claude-headless, ADVISORY) — folded into Changes Required §1 (the walk is the whole tree).

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The two HIGH findings above; no `## AC Verification` in the implementation report |

---

## Acceptance Criteria Check

### Task 1.1: review the pull request

| Criterion | Status | Notes |
|-----------|--------|-------|
| Each defect the change introduces reported with file and line | Pass | Changes Required §1–2, Observations §1–5 |
| Merge verdict given | Pass | CHANGES_REQUIRED |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (placeholder string only; host auth.json never written; token values absent from argv/refusals — RAB-28, pipeline-run KF-048 tests)
- [x] Input validation and sanitization present (`usd_ok` on caps; JWT payload decoded without signature trust and used only for `exp`) — see Observations §3 for the `false`/`null` gap
- [x] Authentication/authorization correct (0600 per-run auth.json; placeholder refresh token can only fail to refresh — KF-048 recurrence 2 addressed)
- [x] No SQL/XSS injection vulnerabilities (n/a)
- [x] Dependencies secure (stdlib only)
- [x] Error messages don't leak sensitive data (paths only)

---

## Code Quality Summary

**Strengths:**
- Cap chain, resume semantics and reservation rule are documented in the header and pinned by RAB-22…26 with exact spend arithmetic.
- KF-048 handling is defensive at both ends (copy and pre-flight), with the failure story recorded inline.
- The `--types` fix comes with a regression test that exercises both the alias and a bad entry.

**Areas for Improvement:**
- `remove_colliding` should model what pytest actually collides on, not "any .py with a reserved basename".
- The pre-flight horizon should be derived from the phase budget, scoped to container mode and to the trials that will launch.

Complexity: `remove_colliding` and the pre-flight Python block are each under 50 lines, nesting ≤ 3. `SIMPLICITY[shrink]`: the pre-flight's horizon can reuse the plan's `phase_sum_min` instead of re-deriving from `watchdog_s`. Lean already otherwise. net: -4 lines possible.

---

## Next Steps

1. Address the two HIGH findings (grader collision rule; pre-flight horizon and executor scope) and add the AG/RAB cases named above.
2. Pick up the MEDIUM observations while in those functions (`__init__.py`/dir-overlay reservation, resume scope, `has($k)` validation).
3. Add an `## AC Verification` section to `grimoires/loa/a2a/sprint-1/reviewer.md`.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":4,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:35:00Z"} -->
