# Sprint Plan: Loa 2.0 Component Ablation (cycle-130)

**Version:** 1.0
**Date:** 2026-10-15
**Author:** Sprint Planner Agent (Claude Fable 5.1, unattended)
**PRD Reference:** grimoires/loa/prd.md
**SDD Reference:** grimoires/loa/sdd.md
**Ledger:** cycle `cycle-130-ablation-2.0`, sprints global 258 / 259 / 260 / 261 / 262 (local sprint-1 … sprint-5)
**Execution:** `/run sprint-plan`, push AUTO; Opus 5.5 implementers in linked worktrees returning `git diff --cached --binary` patches; the lead applies, reviews and audits on Fable 5.1; at most three dissent runs per sprint; no dissent while an arm batch runs (KF-037)
**Task kinds:** every task carries `kind: mechanical | judgment | operator` (DEC-0144); no `operator` task exists because the operator's instruction authorised the cycle end to end and every operator decision is a `proposed` DEC row
**Spend:** cycle cap USD 1,500; per-run cap USD 12 for the suite v1 batches (Sprints 1–3) and, from Sprint 4 on, a per-task-type run cap — build USD 15, review-catch USD 20 (DEC-0559; suite `caps.run_usd_by_type`); the USD 250 reserve is released to the Sprint 4 rerun (DEC-0559) — a re-verification run, if pruning happens, comes out of what remains; the cap covers executor-reported run cost plus cost-ledger rows (arm, smoke, extension and re-verification runs; planning Flatline, dissent, Bridgebuilder); the lead's interactive session and its Agent-tool subagents are unmetered and outside the cap (DEC-0430); smokes run under `--max-usd` ≤ 120; a batch's `--max-usd` = cap − spend so far − concurrency × the largest applicable type cap (DEC-0429 with the reserve released); spend posted in NOTES after every smoke and batch
**Re-scope (2026-10-17, DEC-0559):** suite v1's twelve build tasks saturate (every arm 1.000) and the USD 12 cap stopped five of A1's twelve review runs in AUDIT; the pre-registered H1 and A4 reads halted the cycle (DEC-0558) and the operator chose to harden before acting. Sprint 4 becomes suite v2 and the A0/A1/A4 rerun; Sprint 5 becomes analysis, report, documentation and rc.6, with pruning only if the v2 reads allow it
**Source commit for the arms:** the Sprint 258 completion commit (rc.5 plus the #1267 mount fix); the `.claude/` delta against `4d69c3c4` is recorded in every manifest (DEC-0392)
**Flatline integration:** PRD run → DEC-0391 … DEC-0410 (PRD Appendix G); SDD and sprint runs → Appendix D

---

## Executive Summary

Five sprints measure which components of Loa `v2.0.0-rc.5` still earn their cost on Opus 5.5 and Fable 5.1, and prune the ones that do not before the 2.0.0 promotion. Sprint 1 makes the measurement possible: the #1267 mount fix, the spend caps as scripts, the nine arm profiles with toggles that prove they took effect, a pipeline executor that runs Loa's phases as separate sessions inside a sandbox repository, and the row writer. Sprint 2 freezes sixteen tasks with hidden tests outside the agent tree and a grader that scores a known-good and a known-bad patch correctly on every one. Sprint 3 pre-registers the decision rules, smokes every arm, calibrates the budget from actuals and runs the priority arms A0, A1 and A4 detached under the caps — and halts on the pre-registered reads, because suite v1's build tasks saturate and the per-run cap binds on the gated arm (DEC-0558). Sprint 4, re-scoped under DEC-0559, pre-registers a hardness criterion, authors twelve harder build tasks as suite v2 with per-type run caps, re-pre-registers, and reruns A0, A1 and A4 for the H1 and A4 reads. Sprint 5 re-grades everything under one grader, writes the report (the v1 rows in their own section), documents, ships rc.6, and prunes only if the v2 reads allow it, with the re-verification only then. The floor is never touched.

> Sources: prd.md §Executive Summary, §Timeline; sdd.md §1.2, §8

---

## Sprint Overview

| Sprint | Global | Theme | Key Deliverables | Dependencies |
|--------|--------|-------|------------------|--------------|
| 1 | 258 | Mount integrity and harness plumbing | `gen-checksums.sh`, `check-manifest-paths.sh`, mount-scoped `check-loa.sh`, fresh-mount proof, version markers; `run-arms.sh --max-usd/--screen`, `spend.sh`; `ablation-2.0.yaml` arms and toggles; task schema, `freeze.sh`, `validate-suite.sh`; `pipeline-run.sh` + container image and launcher + phase prompts + `fingerprint.sh` + watchdog; `ablation-row.sh`, `took-effect.sh`; smoke on two task files from existing fixtures; the container-or-host decision | None |
| 2 | 259 | Task suite and grader | task schema, `freeze.sh`, seeders, 16 frozen tasks with hidden tests and `REVIEW.md`, `ablation-grade.sh --self-check` 16/16, bd-8o5rx | Sprint 1 (executor, row writer) |
| 3 | 260 | Runs | NOTES pre-registration, smoke on the frozen suite, cap-fit and budget calibration, priority batch A0–A4 detached, spend posts, A4/H1 reads, A7/A5/A6 if room, cuts recorded | Sprint 2 (frozen suite) |
| 4 | 261 | Suite v2: harder build tasks, per-type caps, re-pre-registration, A0/A1/A4 rerun, reads | pre-registered hardness criterion and caps, `caps.run_usd_by_type` in the harness, twelve harder build tasks with fairness reviews, `suite_version: 2` frozen with the image self-check, calibration smoke, re-pre-registration entry, batch `priority-v2-p1` (A0, A1, A4 at 2 trials per cell), `reads-v2.md` (H1, A4) | Sprint 3 (harness, the v1 reads, DEC-0559) |
| 5 | 262 | Analysis, report, documentation, rc.6 | one-grader re-grade (byte-identical), `report.md`/`report.json` with the v1 section and the cuts, report hardening (bd-yz1rd, bd-m0hw7, bd-wqbz3), Decision Log after the runs, CHANGELOG Sprints 260–262, release notes rc.6, README rerun recipe, beads close-out, E2E; opt-in moves, addendum and re-verification ONLY if the v2 reads allow pruning | Sprint 4 (v2 rows and reads) |

> Sources: prd.md §Timeline & Milestones; sdd.md §8

---

## Sprint 1: Mount integrity and harness plumbing

**Global ID:** 258 · **Epic:** bd-g1cg2 · **Beads:** bd-20fle, bd-iniru, bd-z4mj5, bd-hprvr, bd-d2tkl, bd-tqv4l, bd-jx6mx, bd-rpr5a, bd-91wxm, bd-dm6x0, bd-yk5uf, bd-u89yk, bd-0dks4

### Sprint Goal
Make every later measurement trustworthy: a clean mount, caps as scripts, arms that prove their toggles took effect, an executor that can remove the components the brief names, and one row schema.

### Deliverables
- `tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`, the mount-scoped `check_integrity` in `check-loa.sh`, `tools/fresh-mount-proof.sh`, `.claude/checksums.json` regenerated, `.loa-version.json` and the `CLAUDE.loa.md` marker at `2.0.0-rc.5`, the Shell Tests step (SDD §5.1–5.4)
- `run-arms.sh --max-usd` and `--screen`, `evals/harness/spend.sh` (SDD §5.5, §5.11)
- `evals/suites/ablation-2.0.yaml`; `execute-agent.sh` toggles `loa_mount`, `effort`, `gates`, `flatline` and the skill-effort strip; `evals/harness/lib/sandbox-mount.sh` extracted (SDD §3.3, D-4.2)
- `evals/harness/pipeline-run.sh`, `lib/phase-prompts/*.md`, `fingerprint.sh`, `Dockerfile.ablation` and the container launcher, the per-turn cost watchdog (SDD D-4.1–D-4.10, §5.6)
- Task schema (`task.yaml` with `criterion` and `success_criterion`, `grader_protected`, `structural_check`, `suite_version`), `evals/harness/freeze.sh`, `evals/harness/validate-suite.sh` (SDD §3.2, §5.13; DEC-0424)
- `evals/harness/ablation-row.sh` with `--validate`; `took-effect.sh` (SDD §3.1, §5.8, §5.10)
- Smoke of every runnable arm on two task files built from `review-prs/pr-01` and `implement-tasks/01` (one trial), `took-effect.sh` green, the container-or-host decision, recorded in `a2a/sprint-258/smoke.md`
- CHANGELOG Sprint 1 entries, REPO-MAP, checksums, `sync-fixtures.sh --check`

### Acceptance Criteria
- [ ] AC-1.1 `gen-checksums.sh --check` exits 0 on the committed manifest; the manifest has no entry outside `git ls-files .claude`; entry count equals the tracked count minus `overrides/` and the manifest (PRD AC-1.1)
- [ ] AC-1.2 `check-manifest-paths.sh` fails on a fixture manifest with one untracked path and on one with a `__pycache__` entry, passes on the committed one, and runs as a Shell Tests step (PRD AC-1.2)
- [ ] AC-1.3 `fresh-mount-proof.sh` exits 0 with Aleph absent: 0 Tampered, 0 Missing-should-link, `not-mounted` counted; the proof log is in the sprint report (PRD AC-1.3)
- [ ] AC-1.4 `.loa-version.json` and the `CLAUDE.loa.md` marker read `2.0.0-rc.5`; `check-prompt-budget.sh` rc 0 recorded (PRD AC-1.4)
- [ ] AC-1.5 `run-arms.bats`: a stub executor at USD 5 per trial under `--max-usd 12` launches two, cuts before the third, writes `cut_reason`, exits 1; `--screen` writes no suite `STATUS.json`; `spend.sh` sums fixture rows and ledger with `--since` (PRD AC-2.1, AC-2.3, AC-2.4)
- [ ] AC-1.6 `arm-toggles.bats`: `a0_bare` sandbox has no `.claude/` or `CLAUDE.md` and the stub receives no `--append-system-prompt-file`; `a7_effort_medium` passes `--effort medium`, no sandbox `SKILL.md` carries `effort:` and the sandbox catalog says `default_effort: medium` with its `.checksum` refreshed; `a4_no_gates` leaves both `enabled` keys false and the env var set; `a5_no_flatline` leaves `flatline_protocol.enabled: false`; `a3_one_voice` leaves `companion_voice: false` in both gate blocks; `a1_full` takes no toggles; every arm's sandbox manifest is regenerated after its toggles and `check-loa.sh` integrity is green in each; a fixture tree touching `.claude/` or `grimoires/` is refused by the materialiser; the cycle-129 toggle cases still pass (PRD AC-3.1, AC-5.6; DEC-0431, DEC-0433)
- [ ] AC-1.7 `pipeline-run.bats` (stub CLI): A1 six phases in order with one `pipeline.json` record each and sandbox snapshots after IMPLEMENT and each FIX; A2 no PLAN; A4 ends after IMPLEMENT; A3's REVIEW and AUDIT envelopes carry `companion_voice.planned: false`; A6 one session id across PLAN, IMPLEMENT and FIX with `--resume` on the continuations and distinct ids on REVIEW and AUDIT; A0 one phase, no `.claude/`, `--max-turns 170` and the summed timeout; the cap abort after the phase that passes USD 12 writes `status: cap_failure` and `cap_phase`; a phase killed by SIGTERM yields `status: interrupted` and no grade; no hidden path in the sandbox; `--setting-sources project` on every argv and the captured environment equal to the allowlist (no `AWS_ACCESS_KEY_ID`, `GH_TOKEN`, `GITHUB_TOKEN`, `OPENAI_API_KEY`, Google key) (PRD AC-2.2, AC-4.1, AC-4.2, AC-4.3, AC-4.5)
- [ ] AC-1.8 `ablation-row.sh --validate` rejects a row missing any §3.1 field (incl. `suite_version`, `snapshots`, per-gate `verdict_accuracy_*`, the seven `status` values); rows carry per-phase `effort_effective` from the sandbox MODELINV and `voices_run` from the envelopes; a phase whose model or effort differs sets `degraded` with the reason; `took-effect.sh` evaluates every evidence rule in the suite file incl. `implementer_single_session`, `gates_separate_sessions` and the A1 integrity check (PRD AC-6.3, AC-3.3)
- [ ] AC-1.9 The smoke ran every runnable arm on the two existing fixtures; `took-effect.sh` prints OK for each; A1's `pipeline.json` carries `effort_effective` per phase and the envelopes' voices under REVIEW and AUDIT; costs per arm recorded in `smoke.md` (PRD AC-4.4, AC-3.3)
- [ ] AC-1.10 The suite file declares `task_types` per arm and `absent: true` for A8 with the grep evidence; the report refuses an arm on a type outside its declaration (PRD AC-3.2)
- [ ] AC-1.11 Every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree; `floor-snapshot.bats` green; toolchain readiness recorded
- [ ] AC-1.12 `pipeline-run.bats` with a stub `docker`: the launcher mounts the sandbox read-write and the three per-run credential copies read-only and nothing else, passes `--read-only --network bridge --pids-limit --memory --cpus`, records the image id; the launcher sets `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, an empty `GH_CONFIG_DIR`, no `SSH_AUTH_SOCK`/`BASH_ENV`, and no descriptor above 2 (DEC-0411, DEC-0412); the smoke records whether a phase authenticated and completed inside the container and the executor mode chosen for the cycle
- [ ] AC-1.13 `validate-suite.bats` and `freeze.bats`: schema, four-by-four counts (relaxed for the two smoke tasks by `--allow-partial`), allowlist, destinations, leakage strings and the fixture path rule; `freeze.sh --check` fails on one changed byte (DEC-0424)
- [ ] AC-1.14 `pipeline-run.bats`: arm-aware files only under `meta/`; `gen-checksums.sh` regenerates the sandbox manifest after toggles for every arm; the per-turn watchdog kills a stub phase whose priced usage would pass the run cap and records `cap_failure` with the turn count (DEC-0413, DEC-0421, DEC-0422)

### Implementers and shared files
| Owner | Tasks | Worktree | Shared-file notes |
|-------|-------|----------|-------------------|
| lead | 1.0, 1.9 (run the smoke), 1.10 | main checkout | the only writer of the ledger, `CHANGELOG.md`, REPO-MAP and `checksums.json` |
| A (Opus 5.5) | 1.1, 1.2, 1.3 | `../loa-wt-s1a` | owns `tools/gen-checksums.sh`, `check-manifest-paths.sh`, `fresh-mount-proof.sh`, `check-loa.sh`, the workflow step, the version markers |
| B (Opus 5.5) | 1.4, 1.5, 1.6 | `../loa-wt-s1b` | owns `run-arms.sh`, `spend.sh`, `ablation-2.0.yaml`, `execute-agent.sh` toggles, `lib/sandbox-mount.sh` |
| C (Opus 5.5) | 1.7, 1.8, 1.12 | `../loa-wt-s1c` | owns `pipeline-run.sh`, `Dockerfile.ablation`, the launcher, `lib/phase-prompts/`, `fingerprint.sh`, `ablation-row.sh`, `took-effect.sh`; consumes B's `sandbox-mount.sh` interface as written in SDD D-4.5 |
| B (Opus 5.5) | 1.11 | `../loa-wt-s1b` | also owns the task schema, `freeze.sh`, `validate-suite.sh` |

Sequencing: B's 1.6 (the shared mount library and the toggle set) lands first in B's patch; C codes against the SDD interface and the lead resolves any drift at apply time; A is independent.

### Technical Tasks
- [ ] Task 1.0: Toolchain readiness recorded in the sprint report (claude 2.1.299 on the Bedrock route, codex 0.137.0, python 3.13, node 22, yq, jq, bats path, Docker present but unused, `v2.0.0-rc.5` tag fetched, breaker states) → **[G-2]** ⇐ none · kind: mechanical
- [ ] Task 1.1: `tools/gen-checksums.sh` (tracked-tree manifest, deterministic, `--check`) and `tools/check-manifest-paths.sh` (tracked, present, forbidden classes) with `tests/unit/gen-checksums.bats` and `check-manifest-paths.bats`; regenerate `.claude/checksums.json`; add the Shell Tests step → **[G-3]** ⇐ none · kind: mechanical
- [ ] Task 1.2: `check-loa.sh` `check_integrity` mount-scoped `not-mounted` class with `tests/unit/check-loa-mount-scope.bats`; `tools/fresh-mount-proof.sh` (temp-dir submodule mount at a ref, Aleph absent, prints the summary); run it on this branch and record the log → **[G-3]** ⇐ 1.1 · kind: mechanical
- [ ] Task 1.3: `.loa-version.json` and the `CLAUDE.loa.md` managed marker to `2.0.0-rc.5`; `check-prompt-budget.sh` run on the tag recorded → **[G-3]** ⇐ none · kind: mechanical
- [ ] Task 1.4: `run-arms.sh --max-usd` (estimate from completed actuals, stop launching, `cut` in STATUS.json, exit 1) and `--screen [--screen-tasks N]`; `run-arms.bats` cases → **[G-4]** ⇐ none · kind: mechanical
- [ ] Task 1.5: `evals/harness/spend.sh` (rows + ledger since a timestamp; total, components, cap, headroom, reserve; `--json`) with `evals/tests/spend.bats` → **[G-4]** ⇐ none · kind: mechanical
- [ ] Task 1.6: `evals/suites/ablation-2.0.yaml` (nine arms, toggles, `task_types` with A4 build-only, took-effect lists, the rules block of SDD §3.3 incl. units, applicability, exclusion, cut ladder, drift guard, A8 `absent`); `execute-agent.sh` toggles `loa_mount`, `effort` (flag + skill-frontmatter strip + catalog `default_effort` with `.checksum`), `gates`, `flatline`; extract `lib/sandbox-mount.sh` without behaviour change, with the fixture path rule (SDD D-4.5); `arm-toggles.bats` cases; `execute-agent.bats` still green → **[G-2]** ⇐ none · kind: mechanical
- [ ] Task 1.7: `evals/harness/pipeline-run.sh` (SDD D-4.1–D-4.6: sandbox repo with mount, beads init, phase sessions under the `env -i` allowlist with `--setting-sources project`, per-phase records and argv/env captures, snapshots after IMPLEMENT and FIX, cap abort, `interrupted`, A0 bare with the summed budget, A2/A4/A5 phase-set edits, A6 `--resume` continuations, A3/A7 toggles), `lib/phase-prompts/{PLAN,IMPLEMENT,REVIEW,FIX,AUDIT,BARE}.md`, `fingerprint.sh`; `evals/tests/pipeline-run.bats` with a stub CLI → **[G-2]** ⇐ 1.6 · kind: mechanical
- [ ] Task 1.8: `evals/harness/ablation-row.sh` (§3.1 row from `pipeline.json`, `grade.json`, MODELINV, cost ledger, manifest; `degraded` derivation; seven statuses; `--validate`) and `took-effect.sh` (every per-arm evidence rule of the suite file incl. the A6 session rules and the A1 sandbox integrity check) with `ablation-row.bats` and `took-effect.bats` → **[G-2]** ⇐ 1.7 · kind: mechanical
- [ ] Task 1.9: Smoke every arm on the two smoke task files where its `task_types` allow (the applicability refusal is itself an evidence line; one trial each) inside the container under `--max-usd 100`, read the took-effect evidence, the degraded phases and whether the container authenticated and completed, decide the executor mode for the cycle and whether the gate-model contingency sample is building, and record costs and the evidence table in `a2a/sprint-258/smoke.md` → **[G-2]** ⇐ 1.7, 1.8, 1.11, 1.12 · kind: judgment
- [ ] Task 1.10: CHANGELOG Sprint 1 entries, REPO-MAP and `.checksum`, `checksums.json` via `gen-checksums.sh`, `sync-fixtures.sh --check`, `check-no-raw-sha256sum.sh`, shell-compat lint → **[G-3]** ⇐ 1.1 … 1.9, 1.11, 1.12 · kind: mechanical
- [ ] Task 1.11: Task schema (`task.yaml` with `criterion`, `success_criterion`, `grader_protected`, `structural_check`, `suite_version`, `hidden/manifest.json`), `evals/harness/freeze.sh` with `freeze.bats`, `evals/harness/validate-suite.sh` with `validate-suite.bats`, and the two smoke task files under `grimoires/loa/evals/ablation-2.0/smoke/` built from `review-prs/pr-01` and `implement-tasks/01` → **[G-6]** ⇐ none · kind: mechanical
- [ ] Task 1.12: `evals/harness/Dockerfile.ablation` (pinned node base, Claude CLI 2.1.299, codex 0.137.0, python3 + pytest, bats, yq, jq, git, non-root), the container launcher in `pipeline-run.sh` (per-run read-only credential copies, sandbox rw, nothing else, resource flags, image id), the phase hygiene (git/gh config, descriptors), the per-turn cost watchdog, `meta/` boundary, sandbox manifest regeneration; stub-`docker` bats cases → **[G-2]** ⇐ 1.7 · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `gen-checksums.sh` on a fixture repo with untracked and overrides files | untracked entries, overrides, drift, order | a tracked build artefact | `tests/unit/guard-origins.bats` (fixture repo) |
| `check-loa.sh` on a fixture submodule layout | not-mounted vs Missing vs Tampered | other mount layouts | `tests/unit/check-loa*.bats` |
| `run-arms.sh --max-usd` with a stub executor | cut timing, `cut_reason`, exit code | real cost estimates | `evals/tests/run-arms.bats` |
| toggles on a sandbox tree | text or config left behind; env leak | prompt-cache effects | `evals/tests/arm-toggles.bats` |
| `pipeline-run.sh` with a stub CLI and a stub `docker` | phase order per arm, cap abort, watchdog, hidden path, environment allowlist, setting sources, mount set, `meta/` boundary | live model and container behaviour (the smoke) | `evals/tests/execute-agent.bats` |
| `ablation-row.sh --validate` | missing field, wrong type, degraded derivation | — | new |
| `took-effect.sh` on fixture artefacts | each evidence rule pass/fail | evidence the artefacts lack | new |

### Dependencies
- The `v2.0.0-rc.5` tag fetched (done); `br` 0.2.6 on PATH for sandbox beads; codex CLI authenticated for the dissent voice; Bedrock route live
- `evals/harness/execute-agent.sh` and `run-arms.sh` as landed in cycle-129

### Security Considerations
- Hidden paths never enter a sandbox; `pipeline-run.bats` asserts it.
- Phase environments unset every operator credential except the CLI's own route; the codex voice uses its own auth; nothing is written into an image.
- The sandbox has no zone marker, so the mounted fence and zone guard refuse `.claude/` edits by the agent under test; `--setting-sources project` keeps the operator's settings out.
- `gen-checksums.sh` reads `git ls-files` only; no path from a manifest is executed.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| The implementing skill stalls on a question in a headless phase | Med | High | PLAN writes Success Criteria; A2 brief carries it; `br init` + one bead; phase timeout records `stalls` |
| B and C drift on the mount library interface | Med | Med | SDD D-4.5 names the function and its arguments; the lead reconciles at apply |
| Fresh-mount proof needs network | Low | Low | `file://` clone of this branch; `--ref` |
| Fable refuses a gate phase in the smoke | Med | Med | degraded recorded; the gate-model contingency (SDD A8, DEC-0386) is read over at least ten gate phases across the Sprint 1 and Sprint 3 smokes |

### Success Metrics
- New bats suites green; `execute-agent.bats`, `arm-toggles.bats`, `run-arms.bats`, `floor-snapshot.bats` green; every existing suite green
- `fresh-mount-proof.sh` exit 0; `check-manifest-paths.sh` in CI
- Smoke: every applicable arm OK in `took-effect.sh`; smoke spend posted
- Review and audit APPROVED; COMPLETED marker

---

## Sprint 2: Task suite and grader

**Global ID:** 259 · **Epic:** bd-b9hy5 · **Beads:** bd-xmlfg, bd-bo1na, bd-6civd, bd-swzw3, bd-b727a, bd-tnd3q, bd-lwtwi, bd-bhl22, bd-r941l, bd-tqaen

### Sprint Goal
Freeze sixteen tasks whose answers live outside the agent tree, and prove the grader tells a known-good from a known-bad patch on every one.

### Deliverables
- `grimoires/loa/evals/ablation-2.0/` with `tasks/<id>/{task.yaml,TASK.md,hidden/,REVIEW.md}`, `fixtures/`, `MANIFEST.sha256`, `README.md`; `evals/harness/freeze.sh` (SDD §3.2, §5.13)
- `seed-bugfix-tasks.sh`, `seed-refactor-tasks.sh` with red/green proof (SDD §5.14); four bug-fix, four refactor, four feature-build, four review-catch tasks
- `evals/harness/ablation-grade.sh` with `--self-check` (SDD §5.7, §3.6)
- Fairness reviews (`REVIEW.md`) by non-author Opus 5.5 sessions
- bd-8o5rx: generated paths out of `fix_regions`; manifests and `SHA256SUMS` regenerated; cycle-129 batch-1 refuted share regraded
- CHANGELOG Sprint 2 entries, REPO-MAP, checksums

### Acceptance Criteria
- [ ] AC-2.1 `freeze.sh --check` exits 0 on the committed suite and 1 after any byte changes under `tasks/`; the manifest hash is in the sprint report (PRD AC-5.1)
- [ ] AC-2.2 Every `task.yaml` names a one-line mechanical `success_criterion`, an allowlisted `test_command`, `post_cutoff: true` with the commit date, and its `type`; the four types have four tasks each (PRD AC-5.2)
- [ ] AC-2.3 `ablation-grade.sh --self-check` passes 16/16: hidden tests fail at base and pass at the reference patch for bug-fix and feature-build tasks; each refactor task's structural assertion is red at base and green at the reference while the unchanged suite is green at both, churn recorded; review-catch known-good (a findings file citing every key anchor) scores recall 1.0, known-bad (an empty findings file) 0.0, and a known-noisy file (every head line flagged) scores a false-positive count above the known-good file's (PRD AC-5.3, AC-6.4; DEC-0432)
- [ ] AC-2.4 Every task has a `REVIEW.md` from a session other than its author answering the three checks (no solution leak, red-then-green run, criterion mechanical) (PRD AC-5.4)
- [ ] AC-2.5 `ablation-grade.bats`: grading runs in a fresh grading tree, never in the sandbox; agent-edited `conftest.py`, `pytest.ini`, bats helpers and Makefile targets are replaced by the frozen reference; a deleted test dir is restored; a same-named file is overwritten by the hidden copy; per-gate verdict accuracy against each gate's snapshot incl. `null` when no gate ran; the arm-neutral combined findings file reduces the four gate outputs; a transcript naming a path outside the sandbox, `hidden`, the suite path or `git log --all` yields `contaminated`; `grade.json` summary fields carry ids only (PRD AC-6.1, AC-6.2)
- [ ] AC-2.6 No hidden path appears under any sandbox created for a task (`pipeline-run.bats` case extended to the frozen suite layout) (PRD AC-5.5)
- [ ] AC-2.7 `seed-corpus.bats` pins the generated-path exclusion; the eight regenerated manifests carry no generated `fix_regions`; `SHA256SUMS` refrozen; the regraded batch-1 refuted shares are in the sprint report with recall unchanged (PRD AC-10.1)
- [ ] AC-2.8 All sixteen tasks come from code dated 2026-08-01 or later; the dates are in `task.yaml` (PRD FR-5; DEC-0432)
- [ ] AC-2.9 No build task's fixture, tests or reference patch touches `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/` or `.run/`; the seeders refuse such a candidate by name; every `task.yaml` lists `grader_protected`; every review-catch `TASK.md` carries the output contract; the README states the freeze and `suite_version` protocol (PRD AC-5.6, DEC-0404)
- [ ] AC-2.10 Every existing suite green on the final tree; `floor-snapshot.bats` green

### Implementers and shared files
| Owner | Tasks | Worktree | Shared-file notes |
|-------|-------|----------|-------------------|
| lead | 2.0, 2.7 (dispatch the fairness reviewers), 2.9 | main checkout | ledger, CHANGELOG, REPO-MAP, checksums, `MANIFEST.sha256` final freeze |
| D (Opus 5.5) | 2.1, 2.2, 2.3 | `../loa-wt-s2d` | owns the schema, `freeze.sh`, the seeders, the bug-fix and refactor tasks |
| E (Opus 5.5) | 2.4, 2.5 | `../loa-wt-s2e` | owns the feature-build and review-catch tasks; never edits D's seeders |
| F (Opus 5.5) | 2.6, 2.8 | `../loa-wt-s2f` | owns `ablation-grade.sh`, its bats, the `pipeline-run.bats` extension for the frozen-suite layout, `seed-corpus-from-record.sh` change and regrade |

Sequencing: the task schema landed in Sprint 258 (Task 1.11), so D, E and F code against it from their briefs (the lead writes every shared interface into the briefs and reconciles at apply time, DEC-0436); F's grader runs the self-check on D's and E's tasks after the lead applies all three patches; the fairness reviews (2.7) run after the tasks exist and before the freeze.

### Technical Tasks
- [ ] Task 2.0: Candidate survey recorded: Loa fix commits dated 2026-08-01 or later under `tools/`, `evals/` and `tests/` touching tests, refactor commits with unchanged tests, open beads at rc.5 whose code lives under `evals/` or `tools/`, with mechanical criteria → **[G-1]** ⇐ none · kind: judgment
- [ ] Task 2.1: `grimoires/loa/evals/ablation-2.0/README.md` (layout, the freeze, `suite_version` and hardening protocol, the rerun recipe), `validate-suite.sh` full four-by-four counts enforced, the `fixtures/` layout for the sixteen tasks, the smoke tasks kept outside the frozen set → **[G-6]** ⇐ none · kind: mechanical
- [ ] Task 2.2: `seed-bugfix-tasks.sh` (fix commit → base tree, hidden tests, red/green proof under `env -i`, TASK.md without solution text, refusal of candidates under the mount paths) with `seed-bugfix.bats`; survey `tools/`, `evals/` and `tests/` history since 2026-08; select and write four bug-fix tasks → **[G-1]** ⇐ 2.1 · kind: judgment
- [ ] Task 2.3: `seed-refactor-tasks.sh` (unchanged green tests, ≥ 2 source files outside the mount paths, churn recorded); author one structural hidden assertion per task (red at base, green at the reference); select and write four refactor tasks → **[G-1]** ⇐ 2.1 · kind: judgment
- [ ] Task 2.4: Four feature-build tasks from open beads at rc.5 whose code lives under `evals/` or `tools/` (bd-j4lwr `--max-usd`/`--screen`, bd-8o5rx, two more by the survey criteria or synthetic features on the Python fixtures; bd-yzzb9 excluded — its code is under `.claude/adapters/`) with TASK.md, hidden bats, reference patch, bounds, `grader_protected` → **[G-1]** ⇐ 2.1 · kind: judgment
- [ ] Task 2.5: Four review-catch tasks (two planted, two record fixtures) as frozen references with `review_catch` fields, the arm-neutral output contract in TASK.md, the gate sprint plan and `reviewer.md` stub the materialiser writes → **[G-1]** ⇐ 2.1 · kind: mechanical
- [ ] Task 2.6: `evals/harness/ablation-grade.sh` (reads `sandbox/`, `snapshots/` and the checkout's hidden directory only; `freeze.sh --check` first; grading tree with restored `grader_protected` files and `python3 -I -s`; hidden tests; regressions; recall over the arm-neutral `gates-combined.md` with a defect counted once across gates and false positives deduplicated by region; per-gate verdict accuracy against snapshots and the review-catch severity rule; contamination scan; `zone_violations`; churn; id-only summaries; `--self-check base|reference` per task type) with `ablation-grade.bats` incl. the `meta/`-removed case → **[G-2]** ⇐ 2.1 · kind: mechanical
- [ ] Task 2.7: Fairness review of every task's hidden tests by a non-author Opus 5.5 session; `REVIEW.md` per task; defects fed back to the author before the freeze → **[G-2]** ⇐ 2.2, 2.3, 2.4, 2.5 · kind: judgment
- [ ] Task 2.8: bd-8o5rx — exclude generated paths from `fix_regions` in `seed-corpus-from-record.sh`, regenerate the eight manifests and `SHA256SUMS`, regrade cycle-129 batch 1 (`a2a/sprint-259/regrade-batch-1.md`), `seed-corpus.bats` case → **[G-2]** ⇐ none · kind: mechanical
- [ ] Task 2.9: `ablation-grade.sh --self-check` 16/16 recorded; `freeze.sh` run and `MANIFEST.sha256` committed; CHANGELOG Sprint 2 entries, REPO-MAP, checksums, `sync-fixtures.sh --check` → **[G-2]** ⇐ 2.6, 2.7, 2.8 · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `seed-bugfix-tasks.sh` on a fixture repo with one fix commit | red/green proof, solution leak in TASK.md | task difficulty | `evals/tests/seed-corpus.bats` |
| `ablation-grade.sh` on fixture run dirs | after-run application, restoration, truth table | real review quality | `evals/tests/eval-recall-grader.bats` |
| `freeze.sh` | one-byte drift | — | `SHA256SUMS` practice |
| `seed-corpus-from-record.sh` fix_regions | generated path in a region | — | `evals/tests/seed-corpus.bats` |

### Dependencies
- Sprint 1's `pipeline-run.sh` (for the self-check's sandbox shape) and `ablation-row.sh`
- `origin/record/cycle-126..128-a2a` for the record fixtures (fetched in cycle-129)

### Security Considerations
- Task text is control-stripped; fixture trees pass `no-secrets.sh` at seeding; hidden directories are read by the grader only.
- Fixture trees are files with a fresh `git init` at base, never clones (the answer must not be in history).

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Too few Loa fix commits with clean red/green tests | Med | Med | the survey lists ≥ 8 candidates per type before selection; synthetic Python fixtures (cycle-124 style) are the fallback, recorded |
| Feature-build tasks too large for the per-run cap | Med | High | bounds in `task.yaml`; the Sprint 3 cap-fit rule sends them back |
| Fairness reviewer rubber-stamps | Low | Med | it must run the tests itself and paste the red/green output |

### Success Metrics
- `MANIFEST.sha256` committed; `--self-check` 16/16; `REVIEW.md` 16/16
- New bats green; every existing suite green
- Review and audit APPROVED; COMPLETED marker

---

## Sprint 3: Runs

**Global ID:** 260 · **Epic:** bd-uhgrg · **Beads:** bd-27jw2, bd-nnt3a, bd-37emj, bd-m8a1q, bd-kjfku, bd-rjeq1, bd-2riyg, bd-khz4a

### Sprint Goal
Run the priority arms on the frozen suite under the caps, with the rules written down before the smoke, the chosen trial counts written down before the first batch row, and every cut recorded with its figure.

### Deliverables
- `evals/harness/run-ablation.sh` (SDD §5.9) with `run-ablation.bats`; `evals/harness/ablation-report.py` (SDD §5.12) with `ablation-report.bats` on planted rows (moved here from Sprint 4 so the early reads use a tested script, DEC-0426)
- NOTES § Decision Log pre-registration (rules, applicability, cut order, budget plan, contingencies) timestamped before the first row
- `a2a/sprint-260/smoke.md` (frozen-suite smoke, took-effect, A1 cost per build task, calibration), `batch-plan.md` (projection and trial counts), `spend.md` (after every batch)
- `grimoires/loa/reports/ablation-2.0/runs.jsonl` rows for every planned run or a recorded cut
- A4 sensitivity and H1 reads with the escalation decision

### Acceptance Criteria
- [ ] AC-3.1 The NOTES pre-registration entry (rules, predicates, applicability, cut ladder, caps, reserve, contingencies, drift guard, `suite_version` protocol, H1 / A4 fail path, manifest hash) is timestamped before the Sprint 3 smoke; the batch-plan entry (chosen rung, trial counts, MDE, concurrency, `--max-usd`) is timestamped before the first priority-batch row; smoke rows live in the smoke batch and decide nothing (PRD AC-7.1; DEC-0428)
- [ ] AC-3.2 `run-ablation.sh --dry-run` prints the randomised plan with its shuffle seed and writes `MANIFEST.json` with source commit, model ids, fingerprint, `agy_opt_in: false`, arms, tasks, trials, caps, `pre_registration_ref` (PRD AC-7.2)
- [ ] AC-3.3 `smoke.md` lists every runnable arm with took-effect evidence and A1's cost per build task; the cap-fit read is recorded (median vs USD 9) and acted on (PRD AC-7.3)
- [ ] AC-3.4 `batch-plan.md` projects the priority batch from smoke actuals, states the trial counts and the arms beyond A0–A4 that fit; the batch command shows `--max-usd`
- [ ] AC-3.5 Every row carries `attempts`/`retry_reason`; model failures are `agent_error` and never retried; cap failures are `cap_failure`; a trial with no row after twice its phase-sum timeout is killed and recorded `interrupted` (PRD AC-7.4; DEC-0429)
- [ ] AC-3.6 Spend posted in NOTES after every batch from `spend.sh`; the cycle total never exceeds USD 1,500; every cut names its reason and figure (PRD G-4)
- [ ] AC-3.7 `run-ablation.bats`: plan shape, applicability refusal, shuffle seed, freeze refusal, the hard gate (a non-smoke batch refuses without the manifest hash, the self-check output and sixteen `REVIEW.md` files, and records their hashes in `MANIFEST.json`), `--resume` reconciliation, a took-effect miss pauses the arm and `--clear-arm` resumes it, `STATUS.json` carries the §3.4 fields incl. `paused_arms` and `cuts[].in_flight_reserved` (DEC-0435)
- [ ] AC-3.10 `ablation-report.bats` on planted rows: each rule branch incl. exactly-at-threshold rows (−0.03 inclusive for Remove and Simplify, `hi < 0` strict for Keep, −15 % inclusive for cost), `Not run (cut)` and `Inconclusive-by-power` states, H1 and A4 lines, cap failure as 0, pairwise exclusion, the 25 % guard, build-only arms on the pass rate alone, defects as the catch-rate unit, the labelled sensitivity figure (PRD AC-8.1; DEC-0434)
- [ ] AC-3.8 The A4 sensitivity and H1 reads are recorded with their intervals and the resulting action (continue, harden, or halt before promotion)
- [ ] AC-3.9 No dissent run started while a batch was running (log timestamps in the sprint report)

### Implementers and shared files
| Owner | Tasks | Worktree | Shared-file notes |
|-------|-------|----------|-------------------|
| lead | 3.1, 3.3, 3.4, 3.5, 3.6, 3.7 | main checkout | the batches, NOTES, spend posts, reads |
| G (Opus 5.5) | 3.2 | `../loa-wt-s3g` | owns `run-ablation.sh` and its bats; reuses `run-arms.sh` functions by extraction into `lib/arms-common.sh` without behaviour change |
| H (Opus 5.5) | 3.8 | `../loa-wt-s3h` | owns `ablation-report.py` and its bats |

Sequencing: G's runner and H's report script land before the smoke; the lead runs pre-registration → smoke → calibration entry → batch → reads.

### Technical Tasks
- [ ] Task 3.1: Pre-register in NOTES § Decision Log, quoting the suite file's rules block: thresholds (0.03, 15 %), bootstrap (10,000 / 90 %; defects for the catch rate, tasks for the pass rate), primaries per arm, cap-failure and pairwise-exclusion rules with the 25 % guard, the sensitivity figure, no correction with the expected false positives, applicability matrix, priority and cut ladder, trial counts, caps and reserve, contingencies (cap fit, gate model), the drift guard, the `suite_version` protocol, the H1 / A4 fail path, the suite manifest hash → **[G-1]** ⇐ none · kind: judgment
- [ ] Task 3.2: `evals/harness/run-ablation.sh` (freeze, `validate-suite.sh` and corpus checks, applicability guard at planning, trial-major plan with a seeded shuffle inside each block, dispatch to `pipeline-run.sh`, bounded concurrency with per-run-cap reservation and per-arm × type `est_next` under `--max-usd`, one transport retry, drift guard on CLI version and model ids, `took-effect.sh` per trial with arm pausing and `--clear-arm`, grade, `ablation-row.sh`, STATUS (SDD §3.4 schema) and MANIFEST with `suite_version`, executor mode and the `.claude/` delta, `--smoke`, `--dry-run`, `--resume` (interrupted runs rerun, no duplicate rows), `--detach`) with `run-ablation.bats`; `lib/arms-common.sh` extracted → **[G-2]** ⇐ none · kind: mechanical
- [ ] Task 3.3: Smoke on the frozen suite (every runnable arm, one review-catch and one build task, one trial); read the took-effect evidence, A1 cost per build task, the cap-fit rule and the gate-model contingency; decide and record in `smoke.md` → **[G-2]** ⇐ 3.1, 3.2 · kind: judgment
- [ ] Task 3.4: Budget calibration from smoke actuals; `batch-plan.md` and the second NOTES entry with the arm × type × trials × unit-cost table, the chosen rung of the cut ladder, the minimum detectable effect from smoke variance (an arm whose MDE at affordable trials exceeds 0.10 is pre-declared Inconclusive-by-power and not run), the wall-clock estimate at the chosen concurrency, the batch `--max-usd` from the formula, and the arms that fit → **[G-4]** ⇐ 3.3 · kind: judgment
- [ ] Task 3.5: Priority batch A0–A4 detached (`setsid nohup … --max-usd … --concurrency 3`), monitored; spend posted after the batch; retries and failures summarised → **[G-1]** ⇐ 3.4 · kind: mechanical
- [ ] Task 3.6: A4 sensitivity read and H1 read from `ablation-report.py --partial` (Task 3.8's script, read-only on the rows so far); when H1 is not established or A4 is insensitive, record that no pruning happens, that the report ships with rc.6, and the hardening cost estimate for the operator → **[G-1]** ⇐ 3.5 · kind: judgment
- [ ] Task 3.7: A5, A6 (and A7 when the reserve is not needed, else A7 waits for Sprint 5) batches if `batch-plan.md` allows after actuals, else the cut recorded as `Not run (cut)` with figures; spend posted → **[G-4]** ⇐ 3.6 · kind: judgment
- [ ] Task 3.8: `evals/harness/ablation-report.py` (stdlib; task-mean of trial means; paired bootstrap 10,000/90 % with defects as the catch-rate unit and tasks as the pass-rate unit; cap failures as 0; pairwise exclusion with the 25 % guard; primaries per arm; the executable predicates in the fixed order; `Not run (cut)` and `Inconclusive-by-power`; H1 and A4 lines; sensitivity figure; expected false positives; exclusions; cuts; run_id, `suite_version`, source commit and manifest hash citations; `--partial`; `--json`) with `ablation-report.bats` on planted `runs.jsonl` fixtures incl. threshold-boundary rows → **[G-1]** ⇐ none · kind: mechanical

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `run-ablation.sh --dry-run` on the frozen suite | plan size, applicability, seed, manifest fields, the hard gate | provider behaviour | `evals/tests/run-arms.bats` |
| `ablation-report.py` on planted rows | each rule branch, boundary rows, states, exclusions | real-data edge cases | `evals/harness/arms-report.py` + `arms-report.bats` |
| `--resume` on a fixture batch with partial rows | reconciliation, no duplicate rows | — | new |
| `--max-usd` on the runner | cut before overspend | overshoot by running jobs (stated) | Sprint 1 `run-arms.bats` |

### Dependencies
- Sprint 2's frozen suite and grader; Sprint 1's executor
- Bedrock and OpenAI routes live for about a day; breakers CLOSED at batch start

### Security Considerations
- Batch logs under `~/.cache/loa/cycle-130/`; no credential in any log (the executor unsets them); the record branch gets the a2a records, never the raw transcripts.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| A1 costs more than USD 9 per build run | Med | High | cap-fit rule shrinks tasks (back to Sprint 2 tasks 2.2–2.4 as a fix round) |
| Provider rate limits | Med | Med | concurrency 3, interleaving, retry once, `--resume` |
| A4 ≈ A1 | Med | High | the brief's rule: harden before acting; recorded as escalation |

### Success Metrics
- Every planned priority run has a row or a recorded cut; spend ≤ cap
- `run-ablation.bats` green; `took-effect.sh` OK on the smoke
- Review and audit APPROVED between batches; COMPLETED marker

---

## Sprint 4: Suite v2 — harder build tasks, per-type caps, re-pre-registration, A0/A1/A4 rerun, reads

**Global ID:** 261 · **Epic:** bd-ykvu4 · **Beads:** bd-w77l6 (4.1), bd-jbcup (4.2), bd-t6tt8 (4.3), bd-glnu2 (4.4), bd-d9ph8 (4.5), bd-l7quj (4.6), bd-fla84 (4.7), bd-t8u8h (4.8), bd-vroqq (4.9) — created at the re-scope (labels `epic:bd-ykvu4,cycle-130,sprint-261`); bd-sigxm, bd-xlvu2, bd-nn4yn, bd-80ewp closed as superseded by DEC-0559 (their report-hardening remainder moved to Sprint 5 with bd-yz1rd, bd-m0hw7, bd-wqbz3)

> Re-scoped 2026-10-17 under DEC-0559 after the Sprint 3 halt (DEC-0558): suite v1's twelve build tasks saturate at 1.000 on every arm and the USD 12 per-run cap stopped five of A1's twelve review runs in AUDIT, so v1 cannot support a pruning decision. The original Sprint 4 (analysis) text is in git history at `4c279606`.

### Sprint Goal
Make the suite able to separate the arms (a hardness criterion written down before the tasks are authored), fit the gated arm under per-type run caps, re-pre-register, and rerun A0, A1 and A4 on suite v2 for the H1 and A4 reads — halting again, with the operator's options, if H1 fails.

### Deliverables
- NOTES § Decision Log: the hardness criterion and the per-type caps, timestamped before the first v2 task is authored (Task 4.1); the re-pre-registration entry, timestamped before the first batch row (Task 4.7)
- Harness: per-task-type run caps — suite `caps.run_usd_by_type {build: 15, review-catch: 20}`; `run-ablation.sh` reserves, dispatches (`pipeline-run.sh --max-run-usd <type cap>`) and assumes charges per type; `MANIFEST.json`/`STATUS.json` carry the caps; `run-ablation.bats`
- Twelve harder build tasks under `grimoires/loa/evals/ablation-2.0/tasks/` with v2 ids (`bugfix-v2-01` … `feature-v2-04`; the v1 build task directories removed from `tasks/`, kept in git history and cited by the `suite_version` 1 rows through the v1 manifest hash), each with hidden tests, a `REVIEW.md` fairness review PASS and a reference patch; the four review-catch tasks unchanged
- `suite_version: 2` frozen (`MANIFEST.sha256`, README freeze-protocol entry), the image self-check 36/36 logged for the hard gate, `source_commit: ba11b860` unchanged
- `a2a/sprint-261/smoke-v2.md` (calibration smoke `calib-v2-01`: the hardness read, swap rounds if any, the cap-fit read), `batch-plan-v2.md`
- `grimoires/loa/reports/ablation-2.0/runs.jsonl` rows for batch `priority-v2-p1` (A0, A1, A4; `suite_version` 2) or a recorded cut
- `a2a/sprint-261/reads-v2.md`: the H1 and A4 reads with intervals and the action

### Acceptance Criteria
- [ ] AC-4.1 The hardness criterion (a0_bare's calibration pass rate ≤ 0.5 on each task over 2 trials; the twelve together a0_bare mean ≤ 0.75 with at least six tasks below 1.0; a failing task is swapped, at most two authoring rounds; the reference still passes the hidden tests; the fixture suite green at base and reference) and the caps (build USD 15, review-catch USD 20; cap fit: A1's median cost per run on the smoke ≤ 0.75 × the type's cap, else the tasks shrink or the cap rises before the re-pre-registration) are timestamped in NOTES before the first v2 task is authored; the re-pre-registration entry (suite_version 2 and its manifest hash, the caps, the hardness result, the rules unchanged, the H1/A4 halt conditions, trials per cell, `--max-usd`, the MDE from P1's paired variance, the breaker, the outage clause, A2/A3/A5/A6/A7 pre-declared `Not run (cut)` with figures) is timestamped before the first `priority-v2-p1` row; smoke rows decide nothing (DEC-0428, DEC-0559)
- [ ] AC-4.2 `run-ablation.sh --dry-run` on suite v2 prints the plan with the per-type caps and writes `MANIFEST.json` with `caps.run_usd_by_type`, `suite_version: 2`, the v2 manifest hash and `source_commit ba11b860`; `run-ablation.bats` covers the per-type cap on dispatch (`--max-run-usd` per task type), on the in-flight reservation and on the assumed charge; the hard gate still requires sixteen `REVIEW.md` files and 36 PASS lines
- [ ] AC-4.3 Every v2 build task: the reference touches 3–6 files and is 80–200 lines; hidden tests exercise interactions and edge cases the brief does not spell out, red at base and green at reference inside `loa-ablation:258` (`--self-check` logged); `regression_command` green at both ends; `grader_protected` covers every file under `fixture/tests/`; no cache directory in the fixture; no `hidden` token in agent-facing text (TASK.md, fixture, brief); bounds `{max_turns: {IMPLEMENT: 80}, timeout_min: {IMPLEMENT: 35}}`; `validate-suite.sh` valid; `freeze.sh --check` OK; a `REVIEW.md` PASS by an Opus reviewer who did not author the task (DEC-0435)
- [ ] AC-4.4 On the frozen v2 set the calibration smoke's a0_bare pass rates satisfy the pre-registered criterion, or every swap round and the final read are recorded in `smoke-v2.md`; A1's median cost per run on the smoke ≤ 0.75 × the type's cap, or the recorded adjustment and its re-pre-registration
- [ ] AC-4.5 Every `priority-v2-p1` row carries `attempts`/`retry_reason`, `suite_version` 2, the v2 manifest hash and `cap_phase` when capped; cap failures are `cap_failure`; outage rows are rerun by `--resume --rerun-status`; contaminated rows are hand-read (KF-046) and, when the hit is an idiom, the grader is bumped and the row re-rowed; no dissent run started while the batch ran (timestamps in the sprint report); spend posted after the batch from `spend.sh`; the cycle total ≤ USD 1,500 (PRD G-4)
- [ ] AC-4.6 `reads-v2.md` records H1 (a1_full − a0_bare on either primary, interval excluding zero) and A4 (a4_no_gates − a1_full on the pass rate, interval excluding zero) with their intervals and the action; H1 fails → the halt is recorded (DEC row, NOTES, PR #1283 body) and the operator is reported to with options; A4 not worse than A1 → "no pruning of A4" recorded and the cycle continues to the report

### Implementers and shared files
| Owner | Tasks | Worktree | Shared-file notes |
|-------|-------|----------|-------------------|
| lead | 4.1, 4.5 (freeze, self-check in the image), 4.6, 4.7, 4.8, 4.9 | main checkout | NOTES, the suite file, the batches, reads |
| K (Opus 5.5) | 4.2 | `../loa-wt-s4k` | owns `run-ablation.sh`, `run-ablation.bats`, the suite file's `caps` block (the lead integrates); `pipeline-run.sh` only for the cap argument if needed |
| D2 (Opus 5.5) | 4.3 (bugfix-v2-01 … 04, feature-v2-01, feature-v2-02) | `../loa-wt-s4d` | owns its six task directories; the seeders read-only |
| E2 (Opus 5.5) | 4.3 (refactor-v2-01 … 04, feature-v2-03, feature-v2-04) | `../loa-wt-s4e` | owns its six task directories |
| R1, R2 (Opus 5.5) | 4.4 | read-only on the integrated tree | one `REVIEW.md` per task, each reviewer on the other author's tasks |

Sequencing: 4.1 first (the criterion precedes authoring); K's caps land before the smoke; D2/E2 author in parallel; R1/R2 review after integration; freeze → smoke → swap rounds (re-freeze) → re-pre-registration → batch → reads. Harness files are edited only while no batch runs (KF-037, Sprint 258 lesson).

### Technical Tasks
- [ ] Task 4.1: Pre-register in NOTES § Decision Log, before any v2 task is authored: the hardness criterion (per task a0_bare ≤ 0.5 over 2 trials; the twelve a0_bare mean ≤ 0.75 with ≥ six tasks below 1.0; swap rule, ≤ two authoring rounds; reference passes hidden; fixture suite green at both ends; the four review-catch tasks stay) and the per-type caps (build 15, review-catch 20) with the cap-fit rule (A1 median per run ≤ 0.75 × cap on the smoke) → **[G-1]** ⇐ none · kind: judgment
- [ ] Task 4.2: Per-type run caps in the harness: suite `caps.run_usd_by_type`; `run-ablation.sh` reads the task type's cap for `pipeline-run.sh --max-run-usd`, the in-flight reservation (`concurrency × the largest cap in the plan`), the cap-failure and assumed charges, `MANIFEST.json caps.run_usd_by_type` and `STATUS.json`; `--run-cap` keeps its meaning as the single-cap override; `run-ablation.bats` cases (dispatch argument per type, reservation, assumed charge, MANIFEST) → **[G-4]** ⇐ none · kind: mechanical
- [ ] Task 4.3: Twelve harder build tasks (four bug-fix, four refactor, four feature-build; v2 ids): multi-file changes (3–6 files), reference patches 80–200 lines, hidden tests on interactions and unstated edge cases, `regression_command` green at both ends, `grader_protected` covering every fixture test file, no caches, no `hidden` tokens in agent-facing text, fixtures under `tasks/<id>/fixture/`, bounds `{max_turns: {IMPLEMENT: 80}, timeout_min: {IMPLEMENT: 35}}`, `source.kind: synthetic` dated the authoring day unless the seeders find real candidates with `--since 2026-06-01`; the v1 build task directories removed from `tasks/` → **[G-2]** ⇐ 4.1 · kind: mechanical
- [ ] Task 4.4: Fairness reviews: two Opus reviewers, one `REVIEW.md` per v2 task (PASS required; the DEC-0435 hard gate needs sixteen), each reviewer on the other author's tasks; findings fixed by the author before the freeze → **[G-2]** ⇐ 4.3 · kind: judgment
- [ ] Task 4.5: Freeze v2: `suite_version: 2` in `evals/suites/ablation-2.0.yaml` (`source_commit: ba11b860` unchanged), `validate-suite.sh`, `freeze.sh` (new `MANIFEST.sha256`), `ablation-grade.sh --self-check base|reference` for every task inside `loa-ablation:258` (36/36; the log recorded for the hard gate), README freeze-protocol entry naming the v1 → v2 reason → **[G-2]** ⇐ 4.4 · kind: mechanical
- [ ] Task 4.6: Calibration smoke `calib-v2-01` (decides nothing): a0_bare × twelve build tasks × 2 trials and a1_full × two build + two review-catch tasks × 1 trial under `--results-root evals/results/ablation-2.0 --max-usd 120`; the hardness read per the criterion; failing tasks swapped (≤ two rounds; the a0 part repeated on the swapped tasks only) and the suite re-frozen; the cap-fit read; `smoke-v2.md` and `batch-plan-v2.md` → **[G-4]** ⇐ 4.5 · kind: judgment
- [ ] Task 4.7: Re-pre-registration NOTES entry before any `priority-v2-p1` row: suite_version 2 and its manifest hash, the caps, the hardness result, the rules unchanged (0.03 / 15 % / 10,000 / 90 % / cap failure = 0 / pairwise exclusion / 25 % guard first), the H1 and A4 halt conditions, trials 2 per cell for A0/A1/A4 (3 if the smoke actuals fit the ceiling), `--max-usd` = 1,500 − spend so far − 3 × 20, the MDE from P1's paired variance, the breaker on, the outage clause, A2/A3/A5/A6/A7 pre-declared `Not run (cut)` with figures → **[G-1]** ⇐ 4.6 · kind: judgment
- [ ] Task 4.8: Batch `priority-v2-p1` (`--arms a0_bare,a1_full,a4_no_gates --trials-build 2 --trials-review 2 --concurrency 3 --detach`; dry run first), watched; outage → `--resume --rerun-status transport_error`; contaminated rows hand-read (KF-046) and re-rowed after a grader bump when the hit is an idiom; never a harness edit while the driver runs; spend posted → **[G-1]** ⇐ 4.7 · kind: mechanical
- [ ] Task 4.9: `reads-v2.md` from `ablation-report.py --partial`: H1 and A4 with intervals and the action (H1 fails → halt: DEC row, NOTES, PR body, the operator's options; A4 not worse → "no pruning of A4", continue) → **[G-1]** ⇐ 4.8 · kind: judgment

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `run-ablation.sh --dry-run` on suite v2 | per-type caps in the plan and the manifest, the hard gate at sixteen tasks | provider behaviour | `evals/tests/run-ablation.bats` RAB-1, RAB-3 |
| `ablation-grade.sh --self-check` inside the image on every v2 task | a reference that does not pass, a structural check green at base | real-agent code shapes | the Sprint 259 self-check bats cases |
| `validate-suite.sh`, `freeze.sh --check` | missing `grader_protected` entries, unlisted fixture tests, a `hidden` token in agent-facing text | task difficulty | Sprint 259 VS-12/VS-13 |
| calibration smoke a0_bare × 2 | tasks a bare agent solves every time (the saturation that halted v1) | arm behaviour on other tasks | Sprint 260 `smoke.md` |

### Dependencies
- Sprint 3's harness (runner, grader 1.2.6, report script, row writer) and its P1 reads (DEC-0558); DEC-0559
- Bedrock live for about a day; the image `loa-ablation:258`

### Security Considerations
- Hidden tests stay outside the agent tree (`tasks/<id>/hidden/`, never mounted); fixtures carry no credential and no `.claude/`; batch logs under `~/.cache/loa/cycle-130/`; the record branch gets the a2a records, never the raw transcripts.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Harder tasks still saturate for a0_bare | Med | High | the pre-registered criterion with ≤ two swap rounds; the read is recorded either way |
| A1 exceeds the per-type cap on the harder tasks | Med | High | the cap-fit rule on the smoke (median ≤ 0.75 × cap) before the re-pre-registration; shrink or raise, recorded |
| H1 fails again on v2 | Med | High | the halt path is pre-registered; the report ships with the v1 and v2 reads; the operator decides |
| Authoring leaks a `hidden` token or a cache into the fixture | Low | Med | `validate-suite.sh`, the fairness reviews, the self-check |

### Success Metrics
- Twelve v2 tasks frozen with sixteen `REVIEW.md` PASS and the self-check 36/36; the criterion read recorded
- Every planned `priority-v2-p1` run has a row or a recorded cut; spend ≤ cap; `reads-v2.md` written
- Review and audit APPROVED between batches; COMPLETED marker

---

## Sprint 5 (Final): Analysis, report, documentation, rc.6

**Global ID:** 262 · **Epic:** bd-u3ns5 · **Beads:** bd-4b6dr, bd-eraro, bd-r3cui, bd-9psha, bd-26vid, bd-sveja, bd-0qmri (retitled at the re-scope) + bd-yz1rd, bd-m0hw7, bd-wqbz3 (report hardening, moved from Sprint 4)

> Re-scoped 2026-10-17 under DEC-0559: the pruning and re-verification work of the original Sprint 5 becomes conditional on the v2 reads (Task 5.4); the analysis of the original Sprint 4 lands here. The original text is in git history at `4c279606`.

### Sprint Goal
Turn the v2 rows into the report by the rules written before the runs, keep the v1 rows in their own section, document the cycle and ship rc.6 — pruning, and then re-verifying, only if the v2 reads allow it.

### Deliverables
- The one-grader re-grade of every run directory (v1 and v2, arm map withheld) with the byte-identical check and every difference listed
- Report hardening (H2): bd-yz1rd (`defects_missed` row field), bd-m0hw7 (`regressions.final_green`), bd-wqbz3 (n = 0 wording), the sensitivity figure's H1/A4 lines, a batch-record section from `STATUS.json`, the `suite_version` partition (v1 rows in their own section, never pooled with v2), with `ablation-report.bats` cases
- `grimoires/loa/reports/ablation-2.0/report.md` and `report.json` (`--cuts` naming A2, A3, A5, A6, A7 `Not run (cut)` with figures), the lead's reading, NOTES § Decision Log entries after the runs
- Conditional (only if the v2 reads allow pruning): opt-in moves, measured-lift sentences, `docs/migration/v2.0-ablation-addendum.md`, the re-verification per the three-case rule and `report.md §Re-verification`; otherwise that section states that no pruning was made
- `grimoires/loa/reports/release-notes-2.0.0-rc.6.md`, CHANGELOG (Sprints 260–262), the 2.0.0 notes stub link, README rerun recipe and v2 freeze entry, REPO-MAP, checksums
- bd-2txz1 decision applied or closed with the reading; bd-yzzb9 fix if budget allows; bd-j4lwr, bd-8o5rx closed
- `a2a/sprint-262/e2e.md` validating G-1 … G-6; PR #1283 title and body replaced; Bridgebuilder; admin merge on green CI; rc.6 publish; record branch; archive

### Acceptance Criteria
- [ ] AC-5.1 The re-grade of every run directory (v1 `priority-p1`, v2 `priority-v2-p1`, arm map withheld) under one grader produced `grade.json` byte-identical to the inline grades, except where a later grader's contamination exemption changed a verdict, each such difference listed with the row it moved (DEC-0427)
- [ ] AC-5.2 `report.md` lists per arm n runs, excluded runs with reasons, both primaries with intervals, secondaries, cost per task, wall-clock, tokens, the decision and the rule line; the decision table has one row per component A2–A7 (`Not run (cut)` with figures for A2, A3, A5, A6, A7), a row for A8 reading component-absent, and the H1 and A4 verdict lines; the sensitivity figure prints the H1 and A4 lines too; the v1 P1 rows are reported in their own section under `suite_version` 1 and never pooled with v2 (PRD AC-8.1, AC-8.2, AC-8.3)
- [ ] AC-5.3 Report hardening landed with tests: `defects_missed` carried by `ablation-row.sh` (bd-yz1rd), `regressions.final_green` consumed (bd-m0hw7), the n = 0 wording (bd-wqbz3), the sensitivity H1/A4 lines, the batch-record section, the `suite_version` partition; `ablation-report.bats` and `ablation-row.bats` green
- [ ] AC-5.4 NOTES Decision Log carries the after-run decisions with the report's figures; CHANGELOG carries Sprints 260–262; REPO-MAP regenerated and checksums current; `release-notes-2.0.0-rc.6.md` links `report.md` and the 2.0.0 notes stub carries the same link (PRD AC-9.4)
- [ ] AC-5.5 bd-2txz1 closed or re-scoped with the arm reading; bd-j4lwr, bd-8o5rx closed; bd-yzzb9 closed or commented (PRD AC-10.3)
- [ ] AC-5.6 `run-ablation.sh --source-commit <sha>` is documented in `evals/ablation-2.0/README.md` as the regression check for the next model bump, with the v2 freeze entry (PRD G-6)
- [ ] AC-5.7 `e2e.md` records G-1 … G-6 with evidence (G-5 reads "no pruning made" when H1 is not established or A4 is not worse than A1); every existing suite green; the zone marker is deleted at the end
- [ ] AC-5.8 Conditional on the v2 reads allowing pruning: every Remove or Simplify decision maps to a config key or profile knob change with its restore key in the addendum, `floor-snapshot.bats` and `profile-floor.bats` green, every Keep component's reference doc carries its measured-lift sentence, and `report.md §Re-verification` names the rule case and shows the pruned default within −0.03 of the control on each applicable primary with the interval and the MDE printed, or the prune reverted or held back with the reason; no dissent ran during a re-verification batch (PRD AC-9.1, AC-9.2, AC-9.3; DEC-0398, DEC-0409, DEC-0425, DEC-0436). When the reads do not allow pruning the section states so and this criterion reads not applicable

### Implementers and shared files
| Owner | Tasks | Worktree | Shared-file notes |
|-------|-------|----------|-------------------|
| lead | 5.1, 5.3, 5.4 (if it fires: the re-verification batch), 5.5, 5.6, 5.E2E | main checkout | NOTES, ledger, CHANGELOG, release notes, the PR |
| H2 (Opus 5.5) | 5.2 | `../loa-wt-s5h` | owns `ablation-report.py`, `ablation-row.sh` (the `defects_missed` field only) and their bats |
| I (Opus 5.5, only if 5.4 fires) | 5.4 (config, profiles, docs, addendum) | `../loa-wt-s5i` | never a floor file |

### Technical Tasks
- [ ] Task 5.1: Re-grade every run directory from scratch under one grader with the arm map withheld; assert byte-identical `grade.json` or list each difference with its cause (a contamination exemption added after the inline grade) and the row it moved → **[G-2]** ⇐ none · kind: mechanical
- [ ] Task 5.2: Report hardening: bd-yz1rd, bd-m0hw7, bd-wqbz3, the sensitivity figure's H1/A4 lines, a batch-record section (`extra_models`, `rerowed`, `rerun`, `drift_cleared`, `outage_history`, grader versions per row), the `suite_version` partition with the v1 section; planted-row bats for each → **[G-1]** ⇐ none · kind: mechanical
- [ ] Task 5.3: `report.md`/`report.json` generated (`--cuts` for A2, A3, A5, A6, A7 with the figures that stopped them); the lead's reading of missed labels, failed, degraded and contaminated runs; NOTES § Decision Log entries after the runs with the report's figures; `runs.jsonl` and the report committed → **[G-1]** ⇐ 5.1, 5.2 · kind: judgment
- [ ] Task 5.4: Conditional on 5.3's reads allowing pruning: Remove and Simplify decisions as opt-in moves (`.loa.config.yaml.example`, `profiles.yaml`, this repository's config where a default changes), measured-lift sentences for Keep components, `docs/migration/v2.0-ablation-addendum.md`, then the re-verification per the three-case rule (the pruned arm's rows, or `a1_pruned` interleaved with a fresh `a1_full` control at one trial per task under `--max-usd`, or only the largest-saving removal) and `report.md §Re-verification`; otherwise the section states that no pruning was made → **[G-5]** ⇐ 5.3 · kind: judgment
- [ ] Task 5.5: `release-notes-2.0.0-rc.6.md`, CHANGELOG Sprints 260–262 and the 2.0.0 notes stub link; `evals/ablation-2.0/README.md` rerun recipe and the v2 freeze entry; REPO-MAP, checksums, `sync-fixtures.sh --check` → **[G-6]** ⇐ 5.3 · kind: mechanical
- [ ] Task 5.6: Beads closed or commented (bd-j4lwr `--max-usd`/`--screen`; bd-8o5rx fix regions; bd-2txz1 kernel deletions; bd-yzzb9 metering guard; the cycle's follow-ups); ledger sprint statuses; DEC rows for every after-run decision; PR #1283 title and body replaced (REST PATCH, KF-031), Bridgebuilder, admin merge on green CI, rc.6 publish, record branch, archive → **[G-1]** ⇐ 5.5 · kind: mechanical

### Task 5.E2E: End-to-End Goal Validation
- [ ] Task 5.E2E: Validate G-1 … G-6 on the integrated tree (decision table complete with the v1 and v2 reads; grader blind and hidden tests outside the tree; fresh mount green; caps mechanical with the spend record; G-5 either within −0.03 or "no pruning made"; rerun recipe works with `--dry-run` on a new source commit) and write `a2a/sprint-262/e2e.md` → **[G-1 … G-6]** ⇐ 5.1 … 5.6 · kind: judgment

### Seams Under Test
| Seam | Catches | Misses | Prior art |
|------|---------|--------|-----------|
| `ablation-report.py` on planted rows with two `suite_version` values | pooling v1 with v2; the n = 0 wording; the sensitivity H1/A4 lines | real-data edge cases | Sprint 260 `ablation-report.bats` |
| the one-grader re-grade against the inline `grade.json` | a grader-version drift that moved a verdict | — | Sprint 259 `regrade-batch-1.md` |
| `profile-floor.bats`, `floor-snapshot.bats` after any opt-in move | a floor key reachable or changed | — | cycle-129 |
| `run-ablation.sh --dry-run --source-commit <other>` | the rerun recipe | live rerun | Sprint 3 bats |

### Dependencies
- Sprint 4's v2 rows and `reads-v2.md`; the v1 rows and reads (DEC-0558)

### Security Considerations
- The report prints ids, numbers and the lead's prose; no run output is embedded unescaped. No floor file changes; every default change (if any) has a restore key; the addendum is the operator's notice.

### Risks & Mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| The v2 reads do not allow pruning | Med | Med | the report ships with both reads; Task 5.4 records "no pruning made"; the harness and the suite are the cycle's deliverable |
| A pruned default (if any) misses the −0.03 bound | Low | High | revert the prune; record; the suite stays |
| Budget short for a re-verification batch | Med | Med | the reserve is released (DEC-0559); the three-case rule's cheapest case applies, or the prune is held back with the reason |

### Success Metrics
- `report.md` with one decision or `Not run (cut)` per component, the H1 and A4 lines for v1 and v2, the v1 section
- Documentation, release notes and the rerun recipe present; e2e.md G-1 … G-6 PASS
- Review and audit APPROVED; COMPLETED marker; PR merged; rc.6 published
- Review and audit APPROVED; COMPLETED marker; PR, Bridgebuilder, merge, rc.6

---

## Risk Register

| # | Risk | Sprint | Owner | Mitigation |
|---|------|--------|-------|------------|
| R1 | A1 pipeline runs exceed the per-run cap | 3 | lead | cap-fit rule, one fix round per gate, task shrink as a fix round that bumps `suite_version` and re-freezes |
| R2 | Suite too easy (A4 ≈ A1) — materialised on v1 (DEC-0558) | 3–4 | lead | sensitivity rule; harden before acting: suite v2 with a pre-registered hardness criterion and at most two swap rounds (Sprint 4, DEC-0559) |
| R3 | Budget short for A5–A7 and the re-verification | 3–5 | lead | priority order; A5–A7 pre-declared `Not run (cut)`; the reserve released to the v2 rerun; a re-verification only if pruning happens; cuts recorded |
| R9 | H1 fails again on suite v2 | 4 | lead | the halt path is pre-registered; the report ships with both reads; the operator decides |
| R4 | Headless skill stalls on a prompt | 1 | C | Success Criteria written; beads init; timeouts |
| R5 | Fable gate refusals | 1, 3 | lead | degraded flag; the gate-model contingency to Opus gates read over ≥ 10 gate phases |
| R6 | Hidden test leak | 2 | F | tests outside the tree; bats asserts |
| R7 | Provider drift during the batch day | 3 | lead | randomised interleaving, retry once, resume |
| R8 | Flatline planning runs degrade (KF-041) | plan | lead | integrate by judgment |

> Sources: prd.md §Risks & Mitigation; sdd.md §9

## Success Metrics Summary

| Goal | Metric | Sprint |
|------|--------|--------|
| G-1 | 6 of 6 measurable components with one of the five rule outcomes, or `Not run (cut)` / `Inconclusive-by-power` with the figure that stopped them; A8 component-absent; the H1 and A4 lines for v1 and v2 | 3, 4, 5 |
| G-2 | grader self-check 16/16 on v1 and on v2; blind layout; degraded runs listed; the one-grader re-grade | 2, 4, 5 |
| G-3 | fresh mount exit 0; CI manifest step | 1 |
| G-4 | spend ≤ USD 1,500; cap failures recorded; spend posts; per-type caps from Sprint 4 | 3, 4 |
| G-5 | `a1_pruned` within −0.03, or "no pruning made" when the reads do not allow it | 5 |
| G-6 | rerun recipe documented and dry-run proven | 5 |

> Sources: prd.md §Goals & Success Metrics

## Dependencies Map

```
Sprint 1 (258) ──▶ Sprint 2 (259) ──▶ Sprint 3 (260) ──▶ Sprint 4 (261) ──▶ Sprint 5 (262)
 executor, caps      frozen suite v1,    pre-reg, smoke,     suite v2, caps,    re-grade, report,
 toggles, row        grader 16/16        P1 batch, HALT      re-pre-reg, rerun  docs, rc.6, E2E
                                         (DEC-0558)          A0/A1/A4, reads    (prune only if allowed)
```

> Sources: sdd.md §1.2, §8

## Appendix

### A. PRD Feature Mapping
| FR | Sprint tasks |
|----|--------------|
| FR-1 | 1.1, 1.2, 1.3, 1.10 |
| FR-2 | 1.4, 1.5; cap abort in 1.7; 3.5; 4.2 (per-type caps) |
| FR-3 | 1.6, 1.9 |
| FR-4 | 1.7, 1.9 |
| FR-5 | 2.0–2.5, 2.7, 2.9; 4.1, 4.3, 4.4, 4.5 (suite v2) |
| FR-6 | 1.8, 2.6, 2.9; 5.1 (re-grade) |
| FR-7 | 3.1–3.7; 4.6–4.9 (the v2 smoke, re-pre-registration, batch and reads) |
| FR-8 | 3.8, 5.2, 5.3 |
| FR-9 | 5.4 (conditional), 5.5, 5.6, 5.E2E |
| FR-10 | plan commit (bd-s93s8), 1.4 (bd-j4lwr), 2.8 (bd-8o5rx), 5.6 (bd-2txz1, bd-yzzb9) |

### B. SDD Component Mapping
| SDD | Sprint tasks |
|-----|--------------|
| §5.1–5.4 mount integrity | 1.1, 1.2, 1.3 |
| §5.5, §5.11 caps | 1.4, 1.5 |
| §3.3, D-4.2 arms | 1.6 |
| D-4.1–D-4.6, §5.6 executor | 1.7 |
| §3.1, §5.8, §5.10 rows and evidence | 1.8 |
| §3.2, §5.13, §5.14 suite | 2.1–2.5; 4.3–4.5 (v2) |
| §5.7, §3.6 grader | 2.6; 5.1 |
| §5.9 runner | 3.2; 4.2 (per-type caps) |
| §5.12 report | 3.8, 5.2, 5.3 |
| §8 Sprint 5 | 5.4 (conditional), 5.5, 5.6 |

### C. PRD Goal Mapping
| Goal | Tasks |
|------|-------|
| G-1 | 2.0, 2.2–2.5, 3.1, 3.5–3.7, 4.1, 4.3, 4.6–4.9, 5.2, 5.3, 5.6, 5.E2E |
| G-2 | 1.0, 1.6–1.9, 2.6–2.9, 3.2, 3.3, 4.3–4.5, 5.1 |
| G-3 | 1.1, 1.2, 1.3, 1.10 |
| G-4 | 1.4, 1.5, 3.4, 3.7, 4.2, 4.6, 4.8 |
| G-5 | 5.4 |
| G-6 | 2.1, 5.5 |

### D. Flatline review integration (2026-10-15)
Sprint-plan run (`--phase sprint`, two voices, cross-scoring degraded, 10 blockers, 46 improvements): DEC-0425 … DEC-0436 reflected above — re-verification with an interleaved same-day control and `a1_pruned` as the shipped tree (P1), `ablation-report.py` in Sprint 3 (P2), inline grading plus a Sprint 4 re-grade (P3), pre-registration before the smoke and a batch-plan entry before the first batch row (P4), the batch `--max-usd` formula, smoke caps and a hang watchdog (P5), the cap's coverage stated (P6), A3 test cases and one name for the gate-model contingency (P7), one task date rule and a known-noisy self-check file (P8), integrity-clean sandboxes for every arm and one evidence table (P9), `Not run (cut)` and `Inconclusive-by-power` with the MDE go/no-go (P10), the hard gate before live runs and schema versions (P11), housekeeping incl. the rc.6 markers left to the pipeline (P12). Accepted without change: behavioural drift cannot be detected by id (randomised interleaving spreads it); the measurement infrastructure is validated by the self-check and the smokes before any decision. SDD run: DEC-0411 … DEC-0424 reflected above (container executor and launcher, phase hygiene, `meta/` boundary, per-trial took-effect, watchdog, schema and `validate-suite.sh` in Sprint 258, status table, review-catch combination rule). PRD run: DEC-0391 … DEC-0410 reflected in Sprints 1–5 above (A6 continuous implementer session, A4 build-only, environment allowlist, snapshots and per-gate accuracy, grading tree and contamination scan, fixture path rule, structural refactor checks, cut ladder, three-case re-verification, drift guard, `suite_version`, interrupted runs). SDD and sprint-plan runs: filled after they complete (see NOTES § Decision Log — cycle-130 planning).

> Sources: prd.md §Functional Requirements, §Goals; sdd.md §1.3, §11.2
