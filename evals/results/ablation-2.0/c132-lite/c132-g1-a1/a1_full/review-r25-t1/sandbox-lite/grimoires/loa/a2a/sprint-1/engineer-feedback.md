# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)

---

## Overall Assessment

The change under review is `pr/head.diff`: 12 files under `evals/` covering (a) grader 1.2.11's basename-collision removal in `ablation-grade.sh`, (b) per-task-kind run caps in `run-ablation.sh` and `lib/arms-common.sh`, (c) the KF-048 codex credential handling in `pipeline-run.sh` and the codex token pre-flight in `run-ablation.sh`, (d) the `--types` jq fix, (e) `suite_version: 2` and `caps.run_usd_by_type` in the suite file, and (f) the test updates to v2 task ids plus new cases RAB-22 through RAB-34, AG-35 and three pipeline-run KF-048 cases.

Most of the runner work is solid and well tested: the per-kind cap chain (override → suite map → single-cap chain), MANIFEST persistence and resume-from-MANIFEST behaviour, the max-cap in-flight reservation, the `--types` fix, and the placeholder refresh-token copy (written through an fd at 0600, failure path removes the file and warns) all read correctly and the new bats cases assert the right things.

One finding blocks: the grader's new `remove_colliding` deletes agent-added source files far beyond the pytest collision it is meant to prevent. It reserves every `.py` basename from the hidden overlay and from the fixture's `tests/` trees (helper modules included, and the grader's own comment says fixture suites rely on `from helpers import …`), then unlinks any agent file anywhere in the tree with that basename. An agent that adds `app/helpers.py` or `pkg/utils.py` has it removed before the test command runs and a correct solution is graded as failing, which is the very failure class 1.2.11 was introduced to fix. The cross-model dissent independently raised the same defect as BLOCKING.

The codex pre-flight horizon formula also has two opposite problems (too loose for a single long trial at high concurrency, far too tight for suite-sized batches) and refuses API-key-mode `auth.json` files; these are recorded as observations with concrete scenarios.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Grader deletes non-test agent source files (functionality / data loss in grading)

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1081-1098` — `remove_colliding` reserves every `.py` basename from the overlay and from any fixture dir with a `tests`/`test` component, then unlinks every agent-added file in the whole tree with that basename; a correct solution that adds `app/helpers.py` while the fixture has `tests/helpers.py` loses the module and its hidden tests ImportError.
**File:** `head/evals/harness/ablation-grade.sh:1081` (overlay basenames), `:1087` (fixture basenames), `:1093-1098` (removal walk)
**Issue:** pytest's "import file mismatch" only arises for modules pytest itself imports by basename: collected test modules (`python_files`, default `test_*.py` / `*_test.py`) in package-less directories, plus `conftest.py`. Helper modules such as `tests/helpers.py`, `tests/_oracle_x.py` (both named in the grader's own 1.2.11 comment at `:226-227` as what fixtures import), `tests/utils.py` or data `.py` under `tests/fixtures/` never collide, yet their basenames are reserved. The walk at `:1090-1098` visits every directory (`src/`, `app/`, an agent-created `.venv/`), so a source module inside a package (imported as `pkg.helpers`, which cannot collide) is deleted.
**Why This Matters:** The file is removed from `grading/final` before `test_command` runs, so the agent's implementation fails to import and the row records a failing solution. `colliding_tests_removed` counts it as a collision, so the metric hides the cause. This is a systematic bias against solutions that use common module names, in the arm comparison the harness exists to measure.
**Required Fix:** Build `reserved` only from names pytest would collect: match overlay/fixture basenames against `test_*.py` / `*_test.py` (or read `python_files` from the fixture's `pytest.ini` / `pyproject.toml` / `setup.cfg`), never from helper or data modules. Restrict the removal walk to candidate test modules in package-less directories (no `__init__.py` beside them), and skip `EXCLUDE_ANY`-style dirs (`.venv`, `node_modules`, `.git`). Add an AG case where the fixture has `tests/helpers.py` and the agent adds `src/pkg/helpers.py`, asserting the file survives and `colliding_tests_removed == 0`.
**Reference:** pytest docs, "Import modes" (prepend/append basename rule); CWE-20 (improper validation of the collision condition before a destructive action).

**Example:**
```python
# Current (problematic): every .py basename under tests/ is reserved
reserved = {d.rsplit("/", 1)[-1] for d in owned if d.endswith(".py")}
...
reserved.update(n for n in fs if n.endswith(".py") and n not in ("__init__.py", "conftest.py"))

# Should be: only modules pytest collects by basename
def is_test_module(n):
    return n.endswith(".py") and (n.startswith("test_") or n.endswith("_test.py"))
reserved = {d.rsplit("/", 1)[-1] for d in owned if is_test_module(d.rsplit("/", 1)[-1])}
...
reserved.update(n for n in fs if is_test_module(n))
# and in the walk: skip files whose directory holds an __init__.py (package-qualified, no collision)
```

---

## Observations

### 1. Grader collision rule — edge cases

- **MEDIUM** (confidence: low) `head/evals/harness/ablation-grade.sh:1081` — the overlay-derived set is not filtered the way the fixture walk at `:1087` is: an overlay entry whose dest is any `__init__.py` reserves that basename, and every agent-added `__init__.py` outside fixture paths (every new package) is deleted.
**Suggestion:** Apply the same `("__init__.py", "conftest.py")` exclusion to the overlay-derived names (or the test-module filter from Changes Required 1, which subsumes it).
**Benefit:** New packages created by the agent survive grading.

- **MEDIUM** (confidence: low) `head/evals/harness/ablation-grade.sh:1079-1081` — `owned` excludes directory overlays (`os.path.isdir(f)`), so test basenames inside a directory overlay are never added to `reserved`; an agent test colliding with one of those still aborts collection, so the 1.2.11 fix does not cover directory overlays while `owned_dirs` at `:1080` shows they are a supported shape.
**Suggestion:** Walk directory overlays (`full`) and reserve their collected-test basenames too.
**Benefit:** The fix is complete for both overlay shapes.

- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1019` and `:1101` — `COLLIDING[0]` accumulates across every `prepare()` call in a grade (final, base, implement and fix1 snapshots), so `colliding_tests_removed` is a sum over trees, and an empty `<tree>.colliding-removed.txt` sidecar is written beside every prepared tree, including the fixture copy at `base`. AG-35 only covers the single-tree case.
**Suggestion:** Attribute the count to `final` only (or document the sum, matching `harness_files_removed`), and write the sidecar only when `found` is non-empty.
**Benefit:** Telemetry says what its name says; no empty sidecars.

### 2. Codex token pre-flight (KF-048)

- **MEDIUM** (confidence: high) `head/evals/harness/run-ablation.sh:806` — `required = now + 2 × Σ watchdog_s / concurrency` has no floor at the longest single trial: one a1_full build trial (watchdog 16800 s) at `--concurrency 9` yields a horizon of 3733 s (62 min) although the trial's phase budget is 140 min and its watchdog 280 min; a token expiring in 90 min passes and then expires mid-trial, degrading every later codex phase with no refresh possible (the placeholder refresh token).
**Suggestion:** `required = now + max(max(watchdog_s), 2 × Σ watchdog_s / min(concurrency, len(plan)))`.
**Benefit:** The guard holds for the small batches the cycle actually runs (24 and 9 rows per the PR).

- **MEDIUM** (confidence: medium) `head/evals/harness/run-ablation.sh:806` — the same formula is far too large for suite-sized batches: `watchdog_s` is already 2 × phase-sum, and the horizon doubles it again and sums over every trial of every arm (including non-codex arms and, on `--resume`, trials already rowed). A full v2 batch (12 build × 3 trials × 7 codex arms at ~16000 s plus review-catch) at concurrency 3 needs a token valid for roughly a month; `codex login` yields roughly ten days (PR text: "token valid to 2026-10-28"), so such a batch is refused unconditionally and the refusal's instruction cannot satisfy it. A `--resume` of a 36-trial batch with two trials left is refused for a token with hours of validity.
**Suggestion:** Base the horizon on remaining (unrowed) codex-using trials and expected duration (phase_sum or `est_next`), or downgrade an exceeded horizon to a WARN recorded in `codex_preflight` plus a per-phase check in `pipeline-run.sh`.
**Benefit:** The check protects against KF-048 without making the batches the runner exists for unrunnable.

- **MEDIUM** (confidence: medium) `head/evals/harness/run-ablation.sh:814-817` — a codex `auth.json` written by API-key login (`{"OPENAI_API_KEY": "sk-…", "tokens": null, …}`) reaches `bad("has no tokens.access_token")` and refuses every non-smoke batch (fresh, `--resume`, `--dry-run`) telling the operator to `codex login`, which does not change an API-key host; `pipeline-run.sh:633-636` would have copied that file untouched and codex would have worked. KF-048 (single-use refresh token) does not apply to API keys.
**Suggestion:** When `tokens` is null/absent and `OPENAI_API_KEY` is a non-empty string, record `checked: false` with a WARN instead of refusing; refuse only when neither an API key nor a decodable access token is present.
**Benefit:** API-key hosts can run batches; the refusal message is only shown when login fixes it.

### 3. Tests and suite file

- **LOW** (confidence: high) `head/evals/tests/run-ablation.bats:93-97` — the comment block says "A0 BARE stays 70 min: … the PLAN + IMPLEMENT + 2 x FIX derivation (80) does not apply", and the very next assertion (and RAB-27 at `:104`) requires 9600 s, i.e. the 80-min derivation. The comment contradicts the assertion it annotates.
**Suggestion:** Delete the two stale sentences; keep the trailing "BARE = 15 + 35 + 2 x 15 on a v2 task" note.
**Benefit:** The next reader does not have to work out which of the two statements the code implements.

- **LOW** (confidence: low) `head/evals/suites/ablation-2.0.yaml:31` — `suite_version: 2` and the v2 task ids used throughout `run-ablation.bats` (`bugfix-v2-02`, `refactor-v2-05`, `feature-v2-01`, …; RAB-27 at `:104` requires exactly twelve build tasks) depend on task directories and `MANIFEST.sha256` under `grimoires/loa/evals/ablation-2.0/`, which are not part of this diff. If the repository at head does not carry them, `validate-suite` fails on every task's `suite_version` and the whole runner suite fails on "task not found". Not verifiable from the PR files.
**Suggestion:** Confirm the frozen v2 task tree and manifest land in the same merge (or are already on the target branch).
**Benefit:** The suite file, the tests and the task tree stay consistent at one commit.

- **LOW** (confidence: low) `head/evals/tests/seed-bugfix.bats:80`, `head/evals/tests/seed-refactor.bats:78` — both tests now pass `--suite-version` to `seed-bugfix.sh` / `seed-refactor.sh`, which are not in the diff; if the seed scripts do not already accept that flag these two tests fail at argument parsing. Not verifiable from the PR files.
**Suggestion:** Confirm the flag exists on the target branch.
**Benefit:** Avoids a red CI on merge.

- **LOW** (confidence: low) `head/evals/suites/ablation-2.0.yaml:41` — `run_usd: 12` stays the single-cap value while the effective caps are 15 and 20; any reader other than `run-ablation.sh` that sizes `--max-usd` or the in-flight reservation from `caps.run_usd` (the comment at `:36-37` points at `spend.sh`) under-reserves by up to 8 USD per in-flight trial.
**Suggestion:** Have single-cap readers take `max(run_usd_by_type[*]) // run_usd`, or raise `run_usd` to 20.
**Benefit:** Single-cap consumers stay conservative against the 1,500 USD cycle cap.

---

## Cross-Model Observations

Envelope: `grimoires/loa/a2a/sprint-1/adversarial-review.json` (status `reviewed`, not degraded; primary `gpt-5.5-pro`, companion `claude-headless`, `counted_as: independent_voice`). Six findings, triaged:

| ID | Severity | Anchor | Triage |
|----|----------|--------|--------|
| DISS-C-001 | BLOCKING | `ablation-grade.sh:1081-1098` | Same defect as Changes Required 1; counted there as the blocking finding. |
| DISS-001 | ADVISORY | `run-ablation.sh:807` (anchor demoted out_of_scope; the line is 806 in head) | Valid; recorded as Observations 2 (MEDIUM, horizon has no single-trial floor). |
| DISS-C-003 | ADVISORY | `run-ablation.sh:806` | Valid; recorded as Observations 2 (MEDIUM, horizon too large for suite-sized batches). |
| DISS-C-002 | ADVISORY | `run-ablation.sh:814` | Valid; recorded as Observations 2 (MEDIUM, API-key auth.json refused). |
| DISS-C-004 | ADVISORY | `ablation-grade.sh:1019` | Valid; recorded as Observations 1 (LOW, count over trees, empty sidecars). |
| DISS-C-005 | ADVISORY | `ablation-2.0.yaml:41` | Plausible but the other readers are not in the diff; recorded as Observations 3 (LOW, confidence low). |

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` is 0 bytes.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

Sprint success criterion: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict".

| Criterion | Status | Notes |
|-----------|--------|-------|
| Grader 1.2.11 removes only true pytest basename collisions | Fail | Reserves helper/non-test basenames and deletes agent source modules (Changes Required 1) |
| Per-kind run caps: chain, dispatch `--max-run-usd`, assumed charges, reservation, MANIFEST, resume | Pass | `run-ablation.sh:500-515`, `:850-854`, `:1043-1055`; RAB-22…26 assert each path |
| `--types` filter works | Pass | `run-ablation.sh:~565` jq uses `.type as $t`; RAB-27 |
| KF-048 placeholder refresh token in the per-run HOME | Pass | `pipeline-run.sh:622-645`; three new pipeline-run cases |
| KF-048 pre-flight refuses a token that expires before the batch horizon | Partial | Implemented and tested (RAB-28…34) but the horizon formula and API-key handling have the defects in Observations 2 |
| Suite file v2 + tests on v2 ids | Unverifiable | Task tree not in the diff (Observations 3) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (placeholder string only; token values never printed; refusal names path and timestamps only)
- [x] Input validation at trust boundaries (`usd_ok` on every cap incl. MANIFEST; `suite_kind_cap` refuses malformed maps; JWT payload decoded defensively, no signature trust implied)
- [x] Credential copy written via `os.open(..., 0o600)` + `fchmod`; host file never written; paths only in argv
- [x] No injection vectors introduced (jq `--arg`, python argv, no eval)
- [x] Error messages do not leak token material (RAB-28 asserts this)
- [ ] Destructive action guarded by a precise condition — no: `remove_colliding` deletes on an over-broad predicate (Changes Required 1)

---

## Code Quality Summary

**Strengths:**
- The cap chain is explicit, refuses malformed suite entries rather than skipping them, and resume reads caps from MANIFEST only, with the `--run-cap`-on-resume case logged and tested.
- `spend_charge` / `budget_gate` gain optional parameters with defaults, so other callers keep their behaviour.
- The KF-048 credential copy is minimal, uses `python3 -I`, and has a clean failure path.
- New bats cases are specific (argv log for `--max-run-usd`, exact spend arithmetic, log-line ordering for the reservation).

**Areas for Improvement:**
- `remove_colliding` applies a destructive rule whose predicate is wider than the failure it targets (see Changes Required 1).
- The pre-flight horizon is a single formula that is both unsafe at one end and unusable at the other; derive it from the trials that will actually run.
- Stale comment in RAB-1.

Complexity: `remove_colliding` is 30 lines, nesting ≤ 3; the pre-flight Python block is ~50 lines straight-line. Lean already. Ship (after the fix).

---

## Next Steps

1. Narrow `remove_colliding` to pytest-collected test-module basenames in package-less directories and add the `tests/helpers.py` vs `src/pkg/helpers.py` regression case.
2. Decide the pre-flight horizon (floor at the longest trial; size from remaining codex trials) and handle API-key `auth.json`.
3. Fix the RAB-1 comment; confirm the v2 task tree and the seed `--suite-version` flag exist on the target branch.
4. Update `grimoires/loa/a2a/sprint-1/reviewer.md` and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":1,"medium":5,"low":5},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T17:05:00Z"} -->
