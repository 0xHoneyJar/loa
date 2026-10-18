# Sprint 261 review — round 2 (cycle-130 Sprint 4) — CHANGES_REQUIRED

**Reviewer:** Senior Technical Lead (Claude Fable 5.1, `global.anthropic.claude-fable-5-1`)
**Date:** 2026-10-18 (2026-10-18T09:37:53Z)
**Implementation:** round-2 fixes `4af3294b..43ab4768` on top of round 1 (`4434d450..4af3294b`): grader 1.2.12 (`625999a6`, implementer G, `reviewer-g.md`), the codex pre-flight refinements (`43ab4768`, implementer P, `reviewer-p.md`), the suite README table and task ids (`e37215e5`, `9d1b2a26`). Round 1 feedback archived as `engineer-feedback-r1.md`.
**Dissent:** `adversarial-review.json` (run 2 of ≤ 3, `--type review`, the fix diff `4af3294b..43ab4768` harness-only: 5 files / 549 lines; run 1's envelope archived as `adversarial-review-r1.json`): two voices (`gpt-5.5-pro` primary, `claude-headless` companion; 2 of 2), six findings — 1 BLOCKING (DISS-001) + 5 ADVISORY; all six accepted (none rejected), severities set by the lead below.
**Local checks:** `evals/tests/` **423/423** on `43ab4768`; the official image self-check **36/36 under grader 1.2.12** (`self-check-image-v2-grader-1.2.12.log`); **the blind re-grade of every run directory (Sprint 262 Task 5.1, `~/.cache/loa/cycle-130/regrade-1212/summary.txt`): 132 v1 + 24 + 9 v2 run directories re-graded under 1.2.12 against their frozen suites (v1 from `ba11b860`, manifest 30e1f2ad…; v2 ddd200b3…) are identical to the inline grades on every key except `grader_version` and the two keys later graders added (`colliding_tests_removed`, `heredoc_interpreters`, both counters 0 on every v1 grade)** — no contamination-exemption difference, no score moved.

## Round 1 items
- **HIGH-1 closed** (grader 1.2.12: collectable basenames only, from file overlays, directory overlays and fixture test trees; removal only in a package-less directory; AG-36 … AG-40; self-check 36/36; re-grade identical). **MEDIUM-1 closed** (directory overlays walked; AG-39). **MEDIUM-2 closed** (the --resume horizon counts only the trials the resume launches, `trials_counted`; `LOA_ABLATION_CODEX_HORIZON_S` override with `horizon_source`; RAB-37/RAB-38). **LOW-1 closed** (API-key auth accepted, `auth_mode`; both remedies named; RAB-35/RAB-36). **LOW-2 closed** (README table: round-1 v2 retired with no rows, the frozen v2 row; the task-id line). **LOW-3** → bead bd-85o9e (unchanged, follow-up). **LOW-4** → bead bd-ocovl (disclosed in reads-v2.md).

## Round 2 findings (on the fixes)

### MEDIUM-1 — 1.2.12's `__init__.py` exemption misses same-import-name collisions (DISS-001; CONFIRMED in principle, no v2 shape hits it)
Under pytest's `prepend` mode a test module's import name is its path from the first ancestor without `__init__.py`; `tests/hidden/pkg/test_x.py` and an agent's `tests/pkg/test_x.py` both import as `pkg.test_x` when each `pkg/` has `__init__.py` and the parents do not, and 1.2.12 now keeps that collision. Every hidden dest in the frozen suite is package-less (the lead checked the overlays and the fixtures), so no real grade is affected. **Required:** grader 1.2.13 compares pytest import names (basedir walk) for protected and candidate modules; AG cases with a packaged collision removed and a differently-named package kept.

### MEDIUM-2 — the narrowed horizon can be shorter than one trial (DISS-C-001; CONFIRMED)
`now + 2 × Σ w / concurrency` over one or two remaining trials at concurrency 3 is below one trial's own watchdog. **Required:** `now + 2 × max(Σ w / concurrency, max w)`; RAB case; header and refusal text.

### MEDIUM-3 — `write_status`/`write_manifest` depend on a scratch file (DISS-C-002; CONFIRMED narrow)
Both pass `--slurpfile cpf_f "/codex-preflight.json"`, which exists only after pre-flight 6; a SIGTERM during the hard gate (`on_signal` → `write_status`) would make jq fail and the partial state would not be recorded (`cleanup` itself does not write STATUS; the window is seconds). **Required:** capture the record in a shell variable (`null` before pre-flight 6) and pass `--argjson`; a case that writes STATUS before pre-flight 6.

### LOW-1 — `remaining()` does not count `rerun_pending` (DISS-C-003)
Trials flagged on a previous invocation with no replacement yet are relaunched by --resume but not counted toward the horizon. **Required:** count STATUS.json `rerun_pending` ids (minus --rerow ids); document the remaining divergences.

### LOW-2 — fixture `python_files` not read (DISS-C-004)
No fixture in the frozen suite overrides `python_files`; the rule is right for the suite as frozen. **Required (with 1.2.13):** parse `python_files` from the fixture's pytest config files, defaults otherwise, recorded in grade.json.

### LOW-3 — package-less helper shadowing (DISS-C-005)
A package-less agent helper beside a collectable test module puts its directory on `sys.path`; a protected sibling import of the same bare name (`import _oracle_x`) could resolve to it. Narrow (the hidden suites import `_oracle_*` names only). **Required (with 1.2.13):** remove such a file only when its directory is package-less AND holds a collectable test module; `src/app/helpers.py` stays.

## What was verified as sound in round 2
Grader 1.2.12's rule as stated in `reviewer-g.md` (read against the code: `collectable()`, the three reserved sources, the owned/fixture exclusions, the package-less test); AG-36 … AG-40 fail on 1.2.11 (the implementer swapped graders to prove it). The pre-flight: API-key mode decided by content, both remedies in the credential-less refusal, the resume set mirrors the reconciliation loop (no row + --rerun + --rerun-status − --rerow), the override validated like the other knobs and still compared (never a skip), STATUS carries the resume's record while MANIFEST keeps the start's; no secret printed (RAB-35 asserts the dummy key never appears). The README rows match the frozen manifest and the batches that ran.

## Verdict

CHANGES_REQUIRED — round 3: grader 1.2.13 (MEDIUM-1, LOW-2, LOW-3) and the pre-flight refinements (MEDIUM-2, MEDIUM-3, LOW-1) with tests that fail before and pass after; the official image self-check re-run under 1.2.13 and the blind re-grade repeated; dissent run 3 is the audit (`--type audit`) on the full sprint diff, so round 3 is verified by the lead directly and by the audit dissent.

<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":0,"medium":3,"low":3},"excluded":0,"sprint_id":"sprint-261","ts":"2026-10-18T09:37:53Z"} -->
