# Sprint 1 Review Feedback

**Reviewer:** Senior Tech Lead Reviewer Agent
**Date:** 2026-10-21
**Sprint Reference:** grimoires/loa/sprint.md
**Implementation Report:** grimoires/loa/a2a/sprint-1/reviewer.md (the PR description, `pr/PR.md`)
**Change under review:** `pr/head.diff` — sprint-261 suite v2 frozen + per-type run caps (DEC-0559, DEC-0566, DEC-0567, DEC-0574, DEC-0575, DEC-0580, DEC-0581), KF-048 codex credential handling, grader 1.2.11

---

## Overall Assessment

The per-kind run-cap work (DEC-0567) is sound: `cap_for`, the `spend_charge`/`budget_gate` cap parameters, the in-flight reserve at the largest planned cap, the `--resume` manifest precedence and the `--run-cap` override are implemented as the header documents, and RAB-22…26 exercise every branch including the malformed-suite refusals. The `--types` jq fix is correct and covered by RAB-27. The KF-048 placeholder-refresh-token copy in `pipeline-run.sh make_home` is careful (paths only in argv, 0600, host file never written, three bats cases).

Two parts block the merge. First, grader 1.2.11's `remove_colliding` deletes far more than it should: its reserved-basename set is every `.py` under a fixture `tests/`/`test/` directory plus every hidden-overlay `.py` (including `__init__.py`), and the deletion walk covers the whole grading tree, so an agent's legitimately added `src/.../helpers.py`, `utils.py` or `__init__.py` is unlinked before the hidden suite runs and a correct solution is graded as failing. At the same time it misses the collision it was written for when the hidden suite is a directory overlay. Second, the KF-048 pre-flight refuses any present `auth.json` without a JWT `tokens.access_token`, which locks out API-key codex authentication.

Both voices of the cross-model dissent (codex-headless primary, claude-headless companion; 2/2 succeeded, no rejected payloads) independently flagged the collision remover as blocking; their findings are folded into the entries below.

**Verdict:** CHANGES REQUIRED

---

## Changes Required

### 1. Grader 1.2.11 — `remove_colliding` deletes agent solution files that cannot collide

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1081-1098` — the reserved set is over-broad and the walk is tree-wide, so non-test modules of a correct solution are unlinked and the hidden suite fails
**File:** `head/evals/harness/ablation-grade.sh:1081` (overlay basenames, no `__init__.py` exclusion), `:1087` (every fixture `.py` under `tests/`/`test/`, helpers included), `:1090-1098` (walk over the whole tree, `.venv`/`node_modules` not excluded by `copy_tree`'s `EXCLUDE_TOP` at `:319`)
**Issue:** pytest's "import file mismatch" only arises between modules pytest *imports for collection* (`python_files`: `test_*.py` / `*_test.py`, and `conftest.py`) in package-less directories. The code instead reserves (a) every fixture `.py` under a `tests/` or `test/` path component — `helpers.py`, `utils.py`, `_oracle_x.py`, the very sibling modules the 1.2.11 header says the suites import — and (b) every hidden-overlay `.py` basename with no exclusion, so an overlay that ships `tests/hidden/__init__.py` reserves `__init__.py`. It then unlinks any file with a reserved basename anywhere in the tree that is not at a fixture or overlay path. Concrete failing inputs: fixture `tests/helpers.py` + agent `src/app/helpers.py` → deleted → `ImportError` in the hidden run; overlay `tests/hidden/__init__.py` + agent `src/newpkg/__init__.py` (a feature-build task that adds a package) → deleted → `ModuleNotFoundError`; a refactor that moves `tests/test_x.py` to `tests/unit/test_x.py` loses the moved module. Modules inside a package (an `__init__.py` on the chain to rootdir) are also removed although prepend mode qualifies them and they never collide. `grade.json` records the loss only as `colliding_tests_removed`, so the row looks like an agent failure.
**Why This Matters:** This is the grading path of the ablation harness; a false deletion turns a correct solution into a failed hidden suite and biases the H1/A4 measurement the cycle exists to produce. The AG-35 case only passes because the colliding file happens to be a test module.
**Required Fix:** Build `reserved` only from basenames pytest would collect (`test_*.py`, `*_test.py`; honour `python_files` from `pytest.ini`/`pyproject.toml` when present), exclude `__init__.py` and `conftest.py` from the overlay-derived set too (`:1081`), restrict the walk to the directories the task's `test_command` targets (at minimum skip `.git`, `.venv`/`venv`, `node_modules`, `__pycache__`), and skip a candidate whose directory chain up to the tree root holds an `__init__.py`. Add bats cases for: fixture `tests/helpers.py` + agent `src/helpers.py` kept; overlay `__init__.py` + agent package `__init__.py` kept.
**Reference:** pytest docs, "Import modes" (prepend/`rootdir`-based basename conflict); CWE-20 (improper input validation of what is treated as a collision).

### 2. Grader 1.2.11 — directory-shaped hidden overlays are never reserved, so the targeted collision still aborts collection

- **HIGH** (confidence: medium) `head/evals/harness/ablation-grade.sh:1079-1081` — `reserved` is built from `owned` (file overlay entries only); test modules inside a directory overlay never enter it, and the 1.2.11 collision persists for those tasks with `colliding_tests_removed: 0`
**File:** `head/evals/harness/ablation-grade.sh:1079-1081`
**Issue:** `owned` keeps only overlay entries whose source is not a directory, and `reserved` is derived from `owned`. Directory overlays are a supported shape (`put_file` at `:530` copies a directory source whole; `owned_dirs` at `:1080` exempts their paths; ablation-grade.bats `:853` names "a directory overlay's own conftest.py"). For a hidden suite delivered as `tests/hidden/` containing `test_slug.py`, an agent-added `tests/extra/test_slug.py` is kept, pytest aborts collection on the basename clash, and the correct solution is graded as failing while `grade.json` reports zero collisions removed — the operator believes the guard ran.
**Why This Matters:** The 1.2.11 header promises removal for "a Python file … whose basename equals a hidden overlay's"; for directory overlays that promise is false and the failure is silent.
**Required Fix:** When building `reserved`, also `os.walk` each directory overlay source and add the basenames of its collected test modules (subject to the exclusions in finding 1), or derive `reserved` from the grading tree after `put_file` (every collected `.py` under overlay dests, files and directories). Add a bats case with a directory overlay.

### 3. KF-048 pre-flight — a present `auth.json` without a JWT access token is refused, locking out API-key codex auth

- **HIGH** (confidence: medium) `head/evals/harness/run-ablation.sh:815-820` — an API-key `auth.json` (`OPENAI_API_KEY` set, no `tokens.access_token`) is refused with "run codex login on the host", so every non-smoke batch, dry run and resume with a codex-using arm is blocked for that auth mode
**File:** `head/evals/harness/run-ablation.sh:817` (`bad("has no tokens.access_token")`), `:820` (three-part JWT check)
**Issue:** The codex CLI also authenticates from an API key stored in `auth.json` (`OPENAI_API_KEY` non-null; the PR's own pipeline-run.bats fixture at `head/evals/tests/pipeline-run.bats:928` carries that key alongside `auth_mode`). That mode has no expiring JWT and no refresh-token hazard — KF-048 is about the ChatGPT refresh flow — yet the pre-flight treats the absence of `tokens.access_token` as a broken file and refuses. The refusal text tells the operator to run `codex login`, which would not change the file shape. Before this PR such a host ran batches normally.
**Why This Matters:** A hard refusal (exit 2, `REFUSED.txt`, no `MANIFEST.json`) for a working configuration is a regression in batch startability, and the message misdirects the operator.
**Required Fix:** Before the JWT checks, recognise API-key auth (`data.get("OPENAI_API_KEY")` a non-empty string, or `auth_mode == "apikey"`) and record `checked: false` with a reason instead of refusing. Add a RAB case with an API-key `auth.json`.

---

## Observations

### 1. Pre-flight horizon

- **MEDIUM** (confidence: medium) `head/evals/harness/run-ablation.sh:806` — `required_until = now + 2 × Σ watchdog_s / concurrency` double-counts: `watchdog_s` is already 2 × the phase-sum timeout (`:775`), so the horizon is 4 × the summed phase time over concurrency and counts the whole recorded plan on `--resume`
**File:** `head/evals/harness/run-ablation.sh:806`
**Suggestion:** For a full-suite batch (8 arms × 16 tasks × 3 trials) the horizon is on the order of weeks, longer than any ChatGPT codex access token lives, so such a batch is refused however fresh the login. `make_home` re-copies the host's `auth.json` per trial, so a host re-login mid-batch already reaches later trials; the batch-wide horizon is stricter than the mechanism needs. Drop the extra 2 ×, or bound by what one trial needs (`max(watchdog_s)` plus margin) and keep the batch-level check as a WARN. Document that re-login mid-batch propagates.
**Benefit:** Keeps the KF-048 guard without making long batches unrunnable.

### 2. Seed scripts

- **MEDIUM** (confidence: low) `head/evals/tests/seed-bugfix.bats:80` and `head/evals/tests/seed-refactor.bats:78` — both tests now pass `--suite-version` to `seed-bugfix.sh` / `seed-refactor.sh`, which are not in this change; neither the base tests nor any touched file shows the flag exists
**Suggestion:** Confirm the seed scripts accept `--suite-version` (or add it in this PR, defaulting to the suite file's value). If they reject unknown flags, SB-1 and the refactor seed test fail before the `candidate` line; if they ignore them, the seeded task keeps `suite_version: 1` and `validate-suite` rejects it against the suite's 2 — the exact failure the edit tries to avoid. Not verifiable from the PR files alone.
**Benefit:** Removes an untestable dependency from the test change.

### 3. Low-severity items

- **LOW** (confidence: high) `head/evals/tests/run-ablation.bats:95-97` — the RAB-1 comment says "A0 BARE stays 70 min … the PLAN + IMPLEMENT + 2 x FIX derivation (80) does not apply", but the assertion two lines later expects 9600 s (80 min) with the opposite explanation, and RAB-27 asserts `phase_sum_min` 80. Delete the stale sentence.
- **LOW** (confidence: high) `head/evals/harness/ablation-grade.sh:1019` and `:1773` — `COLLIDING[0]` accumulates across every `prepare` call in a grade (final, base, implement and fix1 snapshot trees), so one colliding agent file is reported as 2 or 3 in `colliding_tests_removed` when snapshots are graded; AG-35 only covers the final tree. Either document "per prepared tree" or count distinct paths.
- **LOW** (confidence: medium) `head/evals/harness/run-ablation.sh:792-793` — `uses_codex` treats every mounted arm as codex-using, so a batch of only `a3_one_voice` (or another arm whose dissent never dispatches the OpenAI voice) is refused on an expired token it would never use. Derive the set from the arms' dissent configuration, or document the over-approximation.
- **LOW** (confidence: high) `head/evals/tests/ablation-grade.bats:1113` — the new assertion documents that an agent-authored test under `tests/` counts toward `hidden_tests.total` ("8/8 … the agent's own test_unrelated"). Pre-existing behaviour, not introduced here, but the comment now makes the inflation vector explicit; worth a follow-up in the grader (collect hidden counts from overlay paths only).

---

## Rejected dissent payloads

None: `metadata.rejected_summary` is empty and the named sidecar `adversarial-rejected-review.jsonl` holds zero rows (both voices normalised cleanly).

## Cross-Model Observations

Two-voice dissent (primary gpt-5.5-pro answered by codex-headless; companion claude-headless, independent, 2/2 succeeded):
- DISS-001 and DISS-C-001 (BLOCKING, `remove_colliding` over-deletion) → folded into Changes Required §1, confirmed in code.
- DISS-C-002 (BLOCKING, overlay `__init__.py` not excluded) → folded into §1, confirmed at `:1081`.
- DISS-C-003 (BLOCKING, directory overlays never reserved) → Changes Required §2, confirmed at `:1079-1081` with `put_file` `:530`.
- DISS-002 and DISS-C-005 (API-key auth refused) → Changes Required §3, confirmed at `:815-820`.
- DISS-C-004 (ADVISORY, horizon formula) → Observations §1.
- DISS-C-006 (ADVISORY, seed `--suite-version`) → Observations §2.

---

## Acceptance Criteria Check

### Task 1.1: the change in `pr/head.diff`

Sprint success criterion: "review the pull request, report each defect it introduces with the file and line it sits on, and give a merge verdict".

| Criterion | Status | Notes |
|-----------|--------|-------|
| Per-type run caps (DEC-0567): kind cap to `--max-run-usd`, assumed charges per kind, reserve at the largest cap, manifest `run_usd_by_type`, `--resume` precedence | Pass | `run-ablation.sh:384-399, 1040-1050, 1183, 1281-1319, 1531-1534`; RAB-22…26 |
| `--types` filter fix | Pass | `run-ablation.sh:565`; RAB-27 |
| KF-048 placeholder refresh token in the per-run HOME | Pass | `pipeline-run.sh:611-629`; three pipeline-run.bats cases |
| KF-048 token-freshness pre-flight | Fail | Refuses API-key auth (§3); horizon over-strict (Obs. §1) |
| Grader 1.2.11 basename-collision guard | Fail | Over-deletes solution files (§1); misses directory overlays (§2) |
| Suite v2 freeze (`suite_version: 2`, caps) and test id migration | Pass | `ablation-2.0.yaml:31-40`; task directories live outside the PR and were not verifiable here |
| `reviewer.md` carries an `## AC Verification` walkthrough | Fail | The report is the PR description only; no AC walkthrough (process item, already CHANGES_REQUIRED on findings) |

---

## Security Checklist

- [x] No hardcoded secrets or credentials (placeholder string only; token values never printed — RAB-28 asserts)
- [x] Input validation at trust boundaries (suite caps refused when malformed; JWT payload parsed defensively; `auth.json` validated as a dict)
- [ ] Authentication/authorization correct — API-key auth mode refused (Changes Required §3)
- [x] No injection vectors introduced (paths only in argv; `python3 -I`)
- [x] Dependencies unchanged
- [x] Error messages don't leak sensitive data (refusal names the path and ISO instants only)

---

## Code Quality Summary

**Strengths:**
- Cap plumbing is complete end to end and the spend arithmetic in RAB-5/24/25 is re-derived in the test comments.
- `make_home` rewrites the credential through a hardened Python snippet with a clean WARN fallback and never touches the host file.
- Header documentation in `run-ablation.sh` was updated alongside the behaviour.

**Areas for Improvement:**
- `remove_colliding` encodes pytest's collision rule imprecisely; model the rule (collected modules, package-less directories) rather than "any `.py` under tests/".
- The pre-flight assumes one codex auth mode and one batch shape; make the assumptions explicit and test the alternatives.

Complexity: `remove_colliding` is 30 lines, nesting ≤ 3; the pre-flight Python is linear. Lean already apart from the rule fix above. Ship after the fixes.

---

## Next Steps

1. Fix `remove_colliding` (reserved set, walk scope, directory overlays) with the two added bats cases.
2. Add the API-key branch to the pre-flight and re-examine the horizon formula.
3. Resolve the seed `--suite-version` dependency and the stale RAB-1 comment.
4. Update `grimoires/loa/a2a/sprint-1/reviewer.md` with an `## AC Verification` section and request another review via `/review-sprint sprint-1`.

---

*Generated by Senior Tech Lead Reviewer Agent*

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":2,"low":4},"excluded":0,"sprint_id":"sprint-1","ts":"2026-10-21T23:40:00Z"} -->
