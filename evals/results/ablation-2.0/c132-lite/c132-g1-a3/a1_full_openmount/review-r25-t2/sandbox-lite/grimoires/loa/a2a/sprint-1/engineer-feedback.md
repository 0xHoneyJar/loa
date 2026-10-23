# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-22
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, pr/PR.md)

---

## Overall Assessment

The change under review is `pr/head.diff`: 12 files, +719/-164, in the evals harness. It bundles four pieces of work: (1) suite v2 (`suite_version: 2`, the twelve v2 build-task ids threaded through every runner test), (2) per-task-kind run caps (DEC-0567) in `run-ablation.sh` and `lib/arms-common.sh` with new tests RAB-22…26, (3) the KF-048 codex credential handling — a placeholder refresh token in the per-run HOME (`pipeline-run.sh`) and an access-token freshness pre-flight in `run-ablation.sh` (RAB-28…34), and (4) grader 1.2.11, which replaces the reverted `--import-mode=importlib` with a basename-collision file removal (AG-35).

Pieces (1) and (2) are well built: the `--types` jq fix is correct (`.type as $t | … | index($t)`; verified `["bug-fix","refactor"] | index("refactor")` → 1), every former `RUN_CAP` charge site now goes through `cap_for`, `--resume` reads the caps from MANIFEST and ignores `--run-cap` with a note, the in-flight reservation uses the largest cap, and RAB-23/24/25/26 pin dispatch argv, assumed charges and the gate arithmetic. The credential copy in `make_home` is careful (paths only in argv, 0600, `rm -f` on failure, host file never written) and the three pipeline-run tests prove it.

Two defects block the merge, both in the KF-048 / 1.2.11 pieces:

- The grader's new `remove_colliding` reserves far more basenames than the pytest "import file mismatch" it targets and deletes matches anywhere in the graded tree, including `src/`. A correct solution that adds `src/<pkg>/helpers.py` while the fixture suite has `tests/helpers.py` (the 1.2.11 header itself names `from helpers import …` as a fixture-suite pattern) loses that module before `test_command` runs and grades as failing. This is the exact failure class 1.2.11 was written to remove, reintroduced from the other side.
- The codex pre-flight's horizon sums `2 × watchdog_s` over the whole plan — every arm, including `a0_bare` which the same code says never uses codex, and on `--resume` every already-rowed trial. `watchdog_s` is already twice the phase sum, so the horizon is about four times the summed phase time divided by concurrency: 7.3 days for a two-arm, twelve-task build batch, weeks for the full suite. The commit trail records a token lifetime of about ten days, so a full-suite batch is refused whatever the token's age, and a late resume of a large batch is refused with a message ("run codex login on the host") that cannot fix it.

Both the primary (gpt-5.5-pro) and companion (claude-headless) dissent voices independently flagged the same two defects as BLOCKING.

Process note: `reviewer.md` is the PR description and carries no `## AC Verification` section, which under this skill is itself an automatic CHANGES_REQUIRED; the verdict here rests on the two HIGH findings regardless.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Grading correctness — remove_colliding deletes agent source modules

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1081-1097` — the reserved-basename set and the removal walk are both wider than the pytest collision they target, so a correct solution's own source files are deleted before any grading command runs and it grades as failing.
**File:** `head/evals/harness/ablation-grade.sh:1081-1097` (reserved set built at 1081 and 1087; walk over the whole tree at 1090-1097)
**Issue:** Three over-reaches combine. (a) Line 1087 reserves *every* `.py` under a fixture `tests/` or `test/` directory except `__init__.py`/`conftest.py` — including support modules pytest never collects (`helpers.py`, `utils.py`, `fixtures.py`). (b) Line 1081 reserves every hidden-overlay `.py` basename with no exclusion at all, so an overlay that ships `tests/__init__.py` reserves `__init__.py` and every package initializer the agent created is deleted. (c) The walk at 1090-1097 covers the entire tree, not package-less test directories: a match under `src/` is removed even though it is imported as `pkg.helpers` and can never collide with `tests/helpers.py` under pytest's default import mode; a match inside a directory that has an `__init__.py` is removed although pytest names it by package.
**Why This Matters:** Concrete failing input: fixture has `tests/helpers.py` (the 1.2.11 header at line 221 documents that fixture suites rely on `from helpers import …`), the agent implements the feature by adding `src/<pkg>/helpers.py` and importing it from `src/<pkg>/__init__.py`; `prepare()` deletes it, `test_command` raises `ModuleNotFoundError` in every test, `hidden_tests` is 0/N, and `grade.json` only shows `colliding_tests_removed: 1` — labelled as a *test* removal. Arms that add more source modules (the full pipeline) are penalised more than BARE, which biases the H1 contrast the suite exists to measure. The dissent's two voices (DISS-001, DISS-C-001) both rated this BLOCKING.
**Required Fix:** Reserve only the names pytest actually collects by basename: from the fixture, files matching `python_files` (`test_*.py` / `*_test.py`, honouring `pytest.ini` when present); from the overlay, the same filter and never `__init__.py`. Restrict the removal walk to the directories `test_command` collects from (or at minimum exclude any directory that contains an `__init__.py`, and exclude `src/`-style package trees), and keep `.colliding-removed.txt` + the count. Add AG cases for: fixture `tests/helpers.py` + agent `src/pkg/helpers.py` kept; overlay `tests/__init__.py` + agent `src/pkg/__init__.py` kept; agent `tests/pkg/__init__.py` + `tests/pkg/test_slug.py` kept.
**Reference:** pytest docs, "Import modes" (prepend/append: package-less test modules are keyed by basename; modules inside packages by their package path). CWE-754 (improper check for unusual conditions) in spirit — the rule assumes every basename match is a collision.

### 2. Operability — the codex horizon refuses every large batch and late resume

- **HIGH** (confidence: medium) `head/evals/harness/run-ablation.sh:806` — `required_until` sums `2 × watchdog_s` over the whole plan (all arms, all trials, rowed or not), producing horizons of days to weeks that no `codex login` access token outlives, so full-suite batches and late `--resume` runs are refused unconditionally.
**File:** `head/evals/harness/run-ablation.sh:806` (formula), `:792-798` (arm filter is used only to decide *whether* to check, not *what* to sum)
**Issue:** `required = ceil(now + 2 × Σ plan[].watchdog_s / concurrency)`. `watchdog_s` is already `2 × phase_sum × 60` (line 772), so the horizon is about four times the summed phase time per concurrency slot. The sum includes `a0_bare` trials, which line 792 says never run the dissent, and on `--resume` the whole recorded plan (header line 116), not the remaining trials.
**Why This Matters:** With the RAB-1 figures (A1 build 16800 s, A0 build 9600 s, concurrency 3):

| Batch | Σ watchdog_s | required horizon |
|-------|--------------|------------------|
| priority-v2-p1 (a0+a1 × 4 review × 3) | ≈ 172 800 | ≈ 32 h |
| a0+a1 × 12 build tasks × 3 trials | 950 400 | ≈ 7.3 days |
| full suite (8 arms × 16 tasks × 3) | ≈ 5.8 M | ≈ 6 weeks |

The commit trail (DEC-0593) records a fresh token "valid to 2026-10-28", about ten days. The two-arm build batch is therefore refused from day three of a token's life and the full suite always; a `--resume` with three trials left on a large batch is refused the same way; `--dry-run` (where pre-registration manifests come from) is refused too. The refusal text tells the operator to re-login, which cannot satisfy the horizon. Fail-closed, so no data is harmed, but the runner cannot run the batches the suite defines. Both dissent voices flagged it (DISS-C-002 BLOCKING).
**Required Fix:** Sum only trials that will launch (not in the done set on `--resume`) and only for arms where `uses_codex` is true; use the phase sum (or one watchdog) rather than `2 × watchdog`, since a run cannot exceed its watchdog; optionally cap the horizon at the token lifetime the codex CLI itself uses and WARN rather than refuse above it. Add RAB cases: a0-heavy plan with a short token passes when only the a1 share fits; a `--resume` with one trial left needs one trial's horizon.
**Reference:** header lines 110-119 should be updated with the chosen formula.

---

## Observations

### 1. Grading — directory overlays escape the collision rule

- **MEDIUM** (confidence: low) `head/evals/harness/ablation-grade.sh:1079-1081` — `owned` excludes directory overlays and `owned_dirs` is used only as an exemption, so a hidden suite overlaid as a directory contributes no basenames to `reserved`; the pytest "import file mismatch" abort 1.2.11 fixes still occurs for those suites, with `colliding_tests_removed: 0`.
**Suggestion:** Walk directory overlays (`os.walk(full)`) and add their collected-module basenames to `reserved` with the same filter as finding 1.
**Benefit:** The 1.2.11 guarantee holds for every overlay shape `put_file` accepts.

### 2. Configuration — false/null per-kind caps fall back silently

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:502` — jq's `//` swallows `false` and `null`, so `run_usd_by_type: false`, `build: false` or `build: null` select the single-cap fallback without the promised usage error (verified: both expressions print the empty string). The comment at 499 and header line 189 say a present malformed entry is refused.
**Suggestion:** Test presence with `has($k)` and type with `type == "number" or type == "string"` instead of `//`.
**Benefit:** A templated-out or typo'd cap is caught at pre-flight, not discovered in MANIFEST after launch.

### 3. Tests — stale comment contradicts its assertion

- **LOW** (confidence: high) `head/evals/tests/run-ablation.bats:95-97` — the comment says "A0 BARE stays 70 min … (80) does not apply" while the assertion two lines below expects 9600 s = 80 min and its own trailing comment says "BARE = 15 + 35 + 2 x 15".
**Suggestion:** Delete the "stays 70 min" sentence.
**Benefit:** The next reader does not have to re-derive which of the two comments is current.

### 4. SIMPLICITY[shrink] — duplicated manifest field

- **LOW** (confidence: high) `head/evals/harness/run-ablation.sh:903` — `codex_token_exp` repeats `codex_preflight.token_exp` byte for byte; two sources of the same truth in MANIFEST.
**Suggestion:** Keep `codex_preflight` only (RAB-30/31/32 read both; drop the three `codex_token_exp` assertions).
**Benefit:** net: -1 line possible; one field to keep consistent.

### 5. Unverifiable dependencies of the test changes

- **LOW** (confidence: medium) `head/evals/tests/seed-bugfix.bats:80` and `head/evals/tests/seed-refactor.bats:78` — both now pass `--suite-version` to `seed-bugfix.sh` / `seed-refactor.sh`, which are not in this change; likewise every RAB case now depends on `grimoires/loa/evals/ablation-2.0/tasks/*-v2-*` and on `a0_bare` carrying `toggles.loa_mount: false`. None of that is in `pr/`, so I could not run the suites; the review relies on reading the assertions. If the seed scripts lack the flag, SB-1 and SR-1 fail.
**Suggestion:** Confirm `seed-*.sh --suite-version` exists on the base commit; attach a bats run log to the report.

## Cross-Model Observations

Advisory findings from the dissent (`adversarial-review.json`, primary gpt-5.5-pro, companion claude-headless, both succeeded, `counted_as: independent_voice`). Advisory input only; not counted.

- **MEDIUM** (confidence: low) `head/evals/harness/pipeline-run.sh:635` — (DISS-C-005) only `tokens.refresh_token` is rewritten; `last_refresh` is copied verbatim. If the codex CLI refreshes proactively on `last_refresh` age rather than only on a 401, a per-run copy older than that interval attempts a refresh with the placeholder, fails, and the run loses the OpenAI voice despite a passing pre-flight. I could not verify the CLI's refresh policy here; worth a check against the codex CLI source before the next batch.
- DISS-001 / DISS-C-001 and DISS-C-002 duplicate Changes Required 1 and 2 (counted there, once each).
- DISS-002 / DISS-C-003 duplicate Observation 1 — I keep it MEDIUM rather than the primary's BLOCKING because no suite in evidence overlays a directory.
- DISS-003 / DISS-C-004 duplicate Observation 2 — kept LOW: the fallback cap is visible in the plan line and MANIFEST, so the damage is a wrong cap the operator can see, not a silent overspend.

## Rejected dissent payloads

None. `metadata.rejected_summary` is empty and the sidecar `adversarial-rejected-review.jsonl` is 0 bytes.

---

## Incomplete Tasks

| Task | Status | Missing |
|------|--------|---------|
| Task 1.1: the change in `pr/head.diff` | Incomplete | The two HIGH findings above must be fixed before merge |

---

## Acceptance Criteria Check

### Task 1.1: the change in pr/head.diff

| Criterion | Status | Notes |
|-----------|--------|-------|
| "review the pull request" | Pass | All 12 files read in full; head files cross-checked for leftover single-cap uses (none) |
| "report each defect it introduces with the file and line it sits on" | Pass | 2 HIGH, 2 MEDIUM, 4 LOW above, each with `head/<path>:<line>` |
| "give a merge verdict" | Pass | CHANGES_REQUIRED |

---

## Security Checklist

- [x] No hardcoded secrets or credentials — the placeholder `loa-ablation-no-refresh-token` is deliberately non-functional; no token value reaches argv, logs or REFUSED.txt (RAB-28, pipeline-run KF-048 test 1)
- [x] Input validation and sanitization present — caps validated with `usd_ok`; JWT payload decoded without trusting it (exp type-checked, bool excluded)
- [x] Authentication/authorization correct — host `auth.json` is never written; the per-run copy is 0600 under a 0700 HOME
- [x] No SQL/XSS injection vulnerabilities — n/a (shell + Python, paths only in argv)
- [x] Dependencies secure — no new dependencies
- [x] Error messages don't leak sensitive data — refusal text carries the file path and ISO times only

---

## Code Quality Summary

**Strengths:**
- Every spend site (`account_row`, both `collect` fallbacks, `spend_charge`, `budget_gate`) consistently takes the kind's cap; `--resume` is manifest-authoritative (RAB-26).
- The `--types` fix is minimal and the RAB-27 regression test covers both the happy path and the usage error.
- `make_home` writes the credential copy with an `O_CREAT|O_TRUNC` 0600 descriptor and removes it on any failure; tests assert the host hash is unchanged.
- Header documentation is updated alongside every behavioural change (run caps, pre-flight 6, MANIFEST fields).

**Areas for Improvement:**
- `remove_colliding` needs to model what pytest actually collects, not basenames in general (finding 1).
- The pre-flight horizon formula should describe the work that will run, not the plan's worst case (finding 2).
- No CHANGELOG entry is in the diff; the scripts' version headers (grader 1.2.11, row writer) serve that role in this repository, so not counted.

Complexity: `remove_colliding` is 22 lines, the pre-flight Python heredoc 55 lines, both single-purpose with nesting ≤ 3. Beyond the duplicated manifest field (Observation 4): Lean already. Ship — after the two fixes.

---

## Next Steps

1. Fix Changes Required 1 and 2 (grader reserved-set/scope; pre-flight horizon), with the listed regression cases.
2. Run `bats evals/tests/ablation-grade.bats evals/tests/run-ablation.bats evals/tests/pipeline-run.bats` and attach the log.
3. Update the report in `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` section.
4. Request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":2,"medium":2,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-22T00:06:57Z"} -->
