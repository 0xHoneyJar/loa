# Software Design Document: Loa 2.0 Component Ablation (cycle-130)

**Version:** 1.0
**Date:** 2026-10-15
**Author:** Architecture Agent (Claude Fable 5.1, unattended)
**PRD Reference:** `grimoires/loa/prd.md` (cycle-130, FR-1 … FR-10, Appendix E D1–D24 = DEC-0355 … DEC-0378)
**Status:** Draft — autonomous run; design-level decisions taken on the operator's behalf are listed in §11.3 and recorded as `proposed` DEC rows DEC-0379 … DEC-0390
**Component under test:** `v2.0.0-rc.5` (tag commit `4d69c3c4`) plus the #1267 mount fix — the arms pin the Sprint 258 completion commit; MANIFEST records `git diff --stat 4d69c3c4..<pin> -- .claude/` (DEC-0392)
**Branch:** `feature/cycle-130-ablation-2.0` from `main 9e53d5d2`

---

## Table of Contents

1. [Project Architecture](#1-project-architecture)
2. [Software Stack](#2-software-stack)
3. [Database Design](#3-database-design)
4. [UI Design](#4-ui-design)
5. [API Specifications](#5-api-specifications)
6. [Error Handling Strategy](#6-error-handling-strategy)
7. [Testing Strategy](#7-testing-strategy)
8. [Development Phases](#8-development-phases)
9. [Known Risks and Mitigation](#9-known-risks-and-mitigation)
10. [Open Questions](#10-open-questions)
11. [Appendix](#11-appendix)

---

## 1. Project Architecture

### 1.1 Principle
Measurement stays outside Loa. The agent under test never sees a hidden test, a defect key or an arm label; the grader never sees an arm label; the arm toggles edit a sandbox copy and prove they took effect; the decision rules are written down before the first run and applied by a script. Everything the brief asks the harness to record (model, effort requested and effective, voices run, tokens, cost, wall-clock) is read from artefacts the run produced, never from what the agent said it did.

### 1.2 Sprint shape
Five sprints (global 258 … 262). Sprint 258 fixes the mount (#1267), adds the spend-cap mechanism, the arm profiles, the pipeline executor, the row writer, and smokes every arm on two existing fixtures. Sprint 259 freezes the sixteen tasks with their hidden tests, builds the grader, proves it on a known-good and a known-bad patch per task, and closes bd-8o5rx. Sprint 260 pre-registers the rules in NOTES, smokes the frozen suite, calibrates the budget from the smoke, runs the priority batch detached, posts spend after every batch, and records every cut. Sprint 261 grades blind, bootstraps, applies the rules, writes the report, and runs the one bounded extension. Sprint 262 moves removable components to opt-in, writes the migration addendum and the measured-lift sentences, re-runs the pruned default on the reserve set, decides bd-2txz1, and validates G-1 … G-6 end to end. Each sprint ends with review and audit on Fable 5.1 and at most three dissent runs; Sprint 260's gates run only between batches (KF-037).

### 1.3 Component map

| Component | Kind | New or changed | FR |
|---|---|---|---|
| `tools/gen-checksums.sh` | bash | new (tracked-tree manifest generator, `--check`) | FR-1 |
| `tools/check-manifest-paths.sh` | bash | new (CI: every manifest path tracked, present, not a build/cache/runtime class) | FR-1 |
| `.claude/scripts/check-loa.sh` `check_integrity` | bash | mount-scoped `not-mounted` class | FR-1 |
| `tools/fresh-mount-proof.sh` | bash | new (temp-dir submodule mount, Aleph absent, `check-loa.sh`) | FR-1 |
| `.claude/checksums.json`, `.loa-version.json`, `CLAUDE.loa.md` marker | data | regenerated; `2.0.0-rc.5` | FR-1 |
| `.github/workflows/bats-tests.yml` Shell Tests | CI | manifest-paths step | FR-1 |
| `evals/harness/run-arms.sh` | bash | `--max-usd`, `--screen`, `cut_reason` | FR-2 |
| `evals/harness/spend.sh` | bash | new (cycle spend: rows + ledger since kickoff) | FR-2 |
| `evals/suites/ablation-2.0.yaml` | yaml | new (nine arms, toggles, `task_types`, took-effect checks) | FR-3 |
| `evals/harness/execute-agent.sh` | bash | toggles `loa_mount`, `effort`, `gates`, `flatline`; skill-effort strip | FR-3 |
| `evals/harness/pipeline-run.sh` | bash | new (sandbox repo with mount; phases as sessions; cap abort; `pipeline.json`) | FR-4 |
| `evals/harness/lib/phase-prompts/*.md` | prompts | new (PLAN, IMPLEMENT, REVIEW, FIX, AUDIT, BARE, ONE_WINDOW) | FR-4 |
| `evals/harness/fingerprint.sh` | bash | new (toolchain fingerprint = image digest) | FR-4 |
| `grimoires/loa/evals/ablation-2.0/` | tracked data | new (tasks, hidden tests, reviews, `MANIFEST.sha256`) | FR-5 |
| `evals/harness/freeze.sh` | bash | new (manifest hash; `--check`) | FR-5 |
| `evals/harness/seed-bugfix-tasks.sh`, `seed-refactor-tasks.sh` | bash | new (Loa-history task seeders with red/green proof) | FR-5 |
| `evals/harness/ablation-grade.sh` | bash | new (hidden tests after the run; recall; verdict accuracy; regressions; `--self-check`) | FR-6 |
| `evals/harness/ablation-row.sh` | bash | new (`runs.jsonl` row; `--validate`) | FR-6 |
| `evals/harness/run-ablation.sh` | bash | new (plan, randomise, dispatch to the executor, grade, append; `--smoke`, `--dry-run`, `--resume`, `--max-usd`) | FR-7 |
| `evals/harness/took-effect.sh` | bash | new (per-arm evidence check from artefacts) | FR-7 |
| `evals/harness/ablation-report.py` | python 3 stdlib | new (bootstrap, rules, report) | FR-8 |
| `grimoires/loa/reports/ablation-2.0/{runs.jsonl,report.md,smoke.md}` | tracked | new | FR-6, FR-7, FR-8 |
| `.loa.config.yaml.example`, `.claude/data/profiles.yaml`, component docs | config, docs | opt-in moves and measured-lift sentences | FR-9 |
| `docs/migration/v2.0-ablation-addendum.md` | doc | new | FR-9 |
| `evals/harness/seed-corpus-from-record.sh` + 8 manifests + `SHA256SUMS` | bash, data | generated paths excluded from `fix_regions` | FR-10 |
| `grimoires/loa/reports/release-notes-2.0.0-rc.6.md` | report | new | FR-9 |

### 1.4 Executor design (D-4)

One executor, `pipeline-run.sh`, runs every task type; the phase set depends on the task type and the arm (D-4.1). The cycle-129 single-skill path (`run-arms.sh` → `execute-agent.sh`) is kept unchanged for the recall suites and is the code the new toggles are added to, because `pipeline-run.sh` reuses its materialisation and toggle functions through a shared library (`evals/harness/lib/sandbox-mount.sh`, extracted from `execute-agent.sh` without behaviour change; `execute-agent.bats` and `arm-toggles.bats` stay green).

**D-4.1 Phase sets.**

| Task type | A1 phases | Notes |
|---|---|---|
| review-catch | REVIEW → AUDIT | the PR is the sandbox's `pr/` directory (`base/`, `head/`, `head.diff`, `PR.md`); `sprint.md` describes it as sprint-1 and `a2a/sprint-1/reviewer.md` carries the PR body as the implementation report; the gates diff `pr/head.diff` (`adversarial-review.sh --diff-file pr/head.diff`); "any gate" = the review file, the audit file and both dissent envelopes |
| bug-fix, refactor, feature-build | PLAN → IMPLEMENT → REVIEW → FIX? → AUDIT → FIX? | the fixture tree is the sandbox repository root with the Loa mount beside it; FIX runs once per gate when its verdict is CHANGES_REQUIRED |

**D-4.2 Arms as phase-set and toggle edits.**

| Arm | Phase-set change | Toggles (sandbox copy) | Took-effect evidence |
|---|---|---|---|
| `a0_bare` | one BARE session: task text, same tools and environment, `--effort high`, `--max-turns` = PLAN + IMPLEMENT + 2 × FIX caps (170), timeout = their sum (70 min) (DEC-0403) | `loa_mount: false` | sandbox has no `.claude/`, no `CLAUDE.md`, argv has no `--append-system-prompt-file`, no hooks ran (no `.run/audit.jsonl`), argv shows the summed caps |
| `a1_full` | as D-4.1 | none | `pipeline.json` lists every phase; `check-loa.sh` integrity green inside the sandbox mount (DEC-0392) |
| `a2_no_sprint_plan` | PLAN removed; IMPLEMENT reads `grimoires/loa/context/task-brief.md` (the prompt says there is no sprint plan) | `sprint_plan: false` | no PLAN record; no `sprint.md` before IMPLEMENT |
| `a3_one_voice` | as A1 | `companion_voice: false` (existing toggle) | both dissent envelopes: `companion_voice.planned == false`, one counted voice |
| `a4_no_gates` | ends after IMPLEMENT (self-report = `reviewer.md`); build tasks only (DEC-0400) | `gates: false` (`code_review.enabled`, `security_audit.enabled` false; `LOA_ADVERSARIAL_REVIEW_ENFORCE=false` in the phase env) | no REVIEW/AUDIT record; the env var in the captured phase environment |
| `a5_no_flatline` | PLAN runs without the Flatline call | `flatline: false` (`flatline_protocol.enabled: false`) | no `flatline-orchestrator` rows in the sandbox MODELINV; `sprint.md` present |
| `a6_one_window` | the implementer's session is continuous: PLAN, IMPLEMENT and both FIX rounds run as `claude -p --resume <session_id>` continuations of one Opus 5.5 session; REVIEW and AUDIT run exactly as A1 (separate Fable sessions with dissent) (DEC-0391) | `context_resets: false` | one `session_id` across PLAN, IMPLEMENT and FIX records; distinct ids on REVIEW and AUDIT |
| `a7_effort_medium` | as A1 | `effort: medium` (`--effort medium` on every session; `effort:` lines stripped from every sandbox `SKILL.md` frontmatter; `default_effort: medium` in the sandbox model-config with its `.checksum` refreshed) | argv has `--effort medium` per phase; `grep -L '^effort:' sandbox/.claude/skills/*/SKILL.md` lists every skill |
| `a8_no_ceremonies` | not run | — | suite entry `absent: true` with the grep evidence |

A1 passes no `--effort`: Loa's shipped efforts (skill frontmatter) are the default under test; A0 passes `--effort high`, the brief's baseline (D-4.3).

**D-4.3 Session invocation.** Every phase runs inside the ablation container when the Sprint 258 smoke proves the route works there, else on the host sandbox with the limit stated (D-4.9, DEC-0411). Every phase is `claude -p "<phase prompt>" --output-format stream-json --verbose --model <id> --permission-mode bypassPermissions --dangerously-skip-permissions --setting-sources project --tools Bash,Read,Grep,Glob,Write,Edit --max-turns <phase cap>` (A6 continuations add `--resume <session_id>`), cwd = the sandbox root, run under `env -i` with exactly this allowlist (DEC-0394): `PATH`, `HOME`, `LANG`, `LC_ALL`, `TERM`, `TMPDIR=<ws>/.eval/tmp`, `CLAUDE_CODE_USE_BEDROCK`, `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_PROFILE`, `CLAUDE_CODE_SUBAGENT_MODEL=<phase model>`, `LOA_MODELINV_LOG_PATH=<ws>/.eval/model-invoke.jsonl`, `LOA_COST_LEDGER_PATH=<ws>/.eval/cost-ledger.jsonl`, plus the arm's own variables (`LOA_ADVERSARIAL_REVIEW_ENFORCE=false` for A4). No access key or API key is present; the Bedrock route and the codex CLI authenticate from the operator's profile files under `HOME`. Network and `HOME` cannot be isolated without breaking the CLI's own route; the contamination scan (D-4.7) is the mechanical mitigation and the report states the limit. The launcher also sets `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` and `GH_CONFIG_DIR=<empty dir in the sandbox>`, never passes `SSH_AUTH_SOCK` or `BASH_ENV`, and closes every descriptor above 2 before exec (DEC-0412). The phase argv and the captured environment are recorded under `<run-dir>/meta/phase-<name>.argv.json` for `took-effect.sh`. The tools list `Bash,Read,Grep,Glob,Write,Edit,Task,WebFetch` is identical for every arm, A0 included, and the report header states it. `--setting-sources project` makes the sandbox's own `.claude/settings.json` (the pinned tree's hooks) the only settings, so the harness under test runs its hooks and the operator's user settings never do. Phase models: PLAN, IMPLEMENT, FIX = `global.anthropic.claude-opus-5-5`; REVIEW, AUDIT = `global.anthropic.claude-fable-5-1` (the brief: Fable 5.1 as reviewer); BARE = Opus 5.5. `--max-turns`: PLAN 30, IMPLEMENT 60, REVIEW 60, FIX 40, AUDIT 60, BARE 170 (= PLAN + IMPLEMENT + 2 × FIX); timeouts PLAN 15, IMPLEMENT 25, REVIEW 30, FIX 15, AUDIT 30, BARE 70 minutes (the gate budgets were 40 / 20 at planning; the Sprint 258 smoke saw a review-catch AUDIT exhaust 40 turns after writing its verdict, DEC-0490); a gate that exhausts its turns after its LOA-VERDICT trailer exists counts as completed with `turn_cap_hit: true` (`cli_exit` keeps the CLI's code); any other phase at the cap is `agent_error`; A6's continued session carries the per-phase caps of the phase it is in.

**D-4.4 Phase prompts** (files under `evals/harness/lib/phase-prompts/`, materialised with the sprint id and task id substituted):
- PLAN: read `grimoires/loa/context/task-brief.md`; write `grimoires/loa/sprint.md` as a one-sprint plan on the planning-sprints template with a `## Success Criteria` section copied from the brief's criterion; when Flatline is on, run `.claude/scripts/flatline-orchestrator.sh --doc grimoires/loa/sprint.md --phase sprint --autonomous --json` and integrate its HIGH_CONSENSUS items; register the sprint in `grimoires/loa/ledger.json` with `ledger-lib.sh add_sprint`.
- IMPLEMENT: `/implement sprint-1` (the skill; beads initialised by the materialiser with one task bead; the gate marker comes from the skill's own `run-checkpoint.sh mark`).
- REVIEW: `/review-sprint sprint-1`; for review-catch tasks the sprint plan names `pr/head.diff` as the change and instructs `--diff-file pr/head.diff`.
- FIX: `/implement sprint-1` (the skill's feedback-first path).
- AUDIT: `/audit-sprint sprint-1`.
- BARE (A0): the task text, the test command, "write your changes in place; run the tests; stop when they pass" (build) or the fixture's REVIEW-INSTRUCTIONS text asking for `review.md` with `head/<path>:<line>` citations and a verdict line (review-catch).
- A6 uses the A1 prompts; the implementer-side prompts are sent to one session with `--resume`, so the PLAN, IMPLEMENT and FIX prompts arrive in one accumulating context.
- A2: the materialiser writes `grimoires/loa/context/task-brief.md` (the agent-facing `criterion`) and no `sprint.md`; the IMPLEMENT, REVIEW and AUDIT prompts say the brief is the sprint's definition (DEC-0423). For every arm the materialiser registers sprint-1 `planned` in the sandbox ledger; the PLAN prompt only writes `sprint.md`.
- Review-catch `TASK.md` output contract (DEC-0403): findings file path (`review.md` for A0; the gates write their own files), one `path:line — description` per line, a final verdict line; `ablation-grade.sh` reduces every gate file and both dissent envelopes to that shape (`gates-combined.md`) before `recall-vs-defects.sh`.

**D-4.5 Sandbox materialisation** (`lib/sandbox-mount.sh mount_sandbox <ws> <task> <arm>`): copy the fixture tree (build) or `pr/` (review-catch); `git init` + commit the tree as `base` (build) so the gates have a range; copy `.claude/` from the pinned worktree (never a symlink), `CLAUDE.md` → `@.claude/loa/CLAUDE.loa.md`, `.loa.config.yaml` = the pinned tree's `.loa.config.yaml` with the arm's toggles applied (D-A2 below), `grimoires/loa/{ledger.json (one cycle, sprint-1 planned), NOTES.md (empty header), context/task-brief.md, a2a/}`, `.run/` with `zone-guard-authorization.json` absent (the agent must not edit `.claude/`), `br init --prefix bd --no-daemon` plus one task bead when `br` is on PATH, else the beads opt-out marker; `.eval/` for artefacts. The hidden directory of the task is never read by the materialiser (a bats case asserts its absence). A build task's fixture tree, tests and reference patch never touch `.claude/`, `CLAUDE.md`, `.loa.config.yaml`, `grimoires/` or `.run/` — the mount owns those paths (DEC-0396); the materialiser refuses a fixture that does. After IMPLEMENT and after each FIX the driver commits the sandbox tree (`snapshot/<phase>`) so the grader can score each gate against the tree it reviewed (DEC-0402). The last materialisation step for every arm is `tools/gen-checksums.sh --root <ws>`, so the sandbox manifest matches the toggled tree and no integrity reader inside the sandbox reports Tampered; the digest goes to `arm_evidence` (DEC-0421). Arm-aware files (`pipeline.json`, argv captures, the arm id) are written under `<run-dir>/meta/`; the agent's tree, snapshots and transcripts under `<run-dir>/sandbox/` and `<run-dir>/snapshots/` (DEC-0413).

**D-4.6 Cap abort.** After every phase the driver adds the result event's `total_cost_usd` and the sandbox cost ledger's rows since the phase started; when the sum ≥ `--max-run-usd` (12) the run stops, `pipeline.json.status = cap_failure`, `cap_phase = <name>`; the grader still grades what exists (the raw score stays in the row as evidence) and the report scores the run 0 on every applicable primary (DEC-0393, A12). A run whose phase process is killed (SIGTERM/SIGKILL, reboot) is `status: interrupted`: `pipeline.json` written, no `grade.json`, not counted, listed, rerun by `--resume` when budget allows (DEC-0405).

**D-4.9 Container executor (DEC-0411).** `evals/harness/Dockerfile.ablation` extends `Dockerfile.sandbox` (pinned node base) with the Claude Code CLI 2.1.299, codex 0.162.1, python3 + pytest, bats, yq, jq, git, as a non-root user. `pipeline-run.sh` runs every phase as `docker run --rm --network bridge --read-only --tmpfs /tmp --pids-limit 512 --memory 4g --cpus 2 -v <run-dir>/sandbox:/workspace:rw -v <run-dir>/creds/aws:/home/evaluser/.aws:ro -v <run-dir>/creds/claude:/home/evaluser/.claude:ro -v <run-dir>/creds/codex:/home/evaluser/.codex:ro <image> …` where `<run-dir>/creds/*` are per-run copies of the operator's `~/.aws`, `~/.claude` and `~/.codex` made by the driver and deleted after the run (token refreshes land in the copy); no other host path is mounted, so the repository, the hidden directories, the results tree, `~/.ssh` and `~/.config/gh` are unreachable; the image digest (`docker image inspect --format '{{index .RepoDigests 0}}'` or the image id) fills `image_digest`. The Sprint 258 smoke decides once for the cycle: a phase that authenticates and completes inside the container → container for every arm; else host sandbox with the limit stated in the report and `image_digest` = the fingerprint (A11). `pipeline-run.bats` exercises the launcher with a stub `docker` recording its argv (mount set, flags, no extra host path).

**D-4.10 Cost watchdog (DEC-0422).** The driver tails each phase's stream-json events, prices every assistant turn's usage from the catalog (`pricing.py`) and sends SIGTERM when that running estimate plus the run's spent cost would pass `--max-run-usd`; the phase is recorded `cap_failure` with the turn count; after exit the result event's `total_cost_usd` is authoritative; the report states the largest single-turn overshoot observed.

**D-4.7 Contamination scan (DEC-0395).** `ablation-grade.sh` reads only `<run-dir>/sandbox/`, `<run-dir>/snapshots/` and the task's hidden directory in the main checkout (never `meta/`; `ablation-grade.bats` grades a fixture run with `meta/` removed and asserts byte-identical `grade.json`, DEC-0413), runs `freeze.sh --check` before grading and refuses on drift (DEC-0414), and scans every phase's `events.jsonl` tool-use inputs (Bash commands, Read/Grep/Glob paths, Write/Edit paths) for: an absolute path outside the sandbox root (the CLI's own `~/.claude`, `~/.codex`, `~/.aws` configuration reads excepted), the string `hidden`, the repository's suite path (`grimoires/loa/evals/ablation-2.0`), or `git log --all` / `git reflog`. A hit sets `grade.json.contaminated = {phase, pattern, excerpt_id}` and the row `status: contaminated`; the run is excluded pairwise and listed with a per-arm count. The scan is a lower bound on leakage and the report says so.

**D-4.8 Grading tree (DEC-0395, DEC-0491).** The grader never runs tests inside the sandbox: it copies the agent's final tree (or the gate snapshot) to `<run-dir>/grading/<snapshot>/`, restores every `grader_protected` file from the frozen fixture reference, overlays `hidden/tests/**` at the paths in `hidden/manifest.json`, and runs the task's `test_command` and `regression_command` INSIDE the ablation image (`docker run --rm --network none --read-only --tmpfs /tmp --user <uid>:<gid> -v <grading tree>:/workspace:rw -w /workspace -e HOME=/tmp -e LC_ALL=C loa-ablation:258 timeout 120 …`), so the toolchain the agent built against is the toolchain that grades it and the host's user-site packages never matter (the Sprint 258 smoke showed `env -i … python3 -I -s -m pytest` has no pytest on this host); `--executor host` graders fall back to the host command under `env -i` with the same flags; Python runs as `python3 -I -s -m pytest -p no:cacheprovider --rootdir <tree> -q`, bats as `bats <files>` with `BATS_LIB_PATH` unset. Counts are parsed from the pytest summary or the TAP lines.

### 1.5 Data flow

```
suite yaml ─┐                              hidden/ (repo, never copied) ─┐
tasks/ ─────┼─▶ run-ablation.sh ─▶ pipeline-run.sh ─▶ .eval/{pipeline.json, MODELINV, cost} ─▶ ablation-grade.sh ─▶ grade.json ─┐
pinned tree ┘        │ randomised plan, retries, --max-usd                                                         ablation-row.sh ─▶ runs.jsonl ─▶ ablation-report.py ─▶ report.md
                     └─▶ MANIFEST.json (arm map, fingerprint, shuffle seed) ────────────────────────────────────────────────────────┘ (joins the arm label here)
```

### 1.6 Floor statement
No task in this cycle edits `adversarial-review.sh`, `verdict-derive.sh`, `adversarial-review-gate.sh`, the deny list, fence FR-1.2b, the System-Zone rules or the operator-only commands; `floor-snapshot.bats` is green on every commit. A4 informs the sensitivity check and the report (DEC-0367).

---

## 2. Software Stack

| Layer | Choice | Version pinned by | Note |
|---|---|---|---|
| Executor CLI | Claude Code CLI 2.1.299 (`claude`, Bedrock route) | fingerprint, MANIFEST.json | models `global.anthropic.claude-opus-5-5`, `global.anthropic.claude-fable-5-1` |
| Cross-model voice | codex CLI 0.162.1 (`codex-headless`; Sprint 258 amendment: Codex on a ChatGPT plan withdrew every gpt-5.x name, DEC-0485 / KF-044) | fingerprint | OpenAI family |
| Harness scripts | Bash 5.2, `set -euo pipefail`, `LC_ALL=C` | shell-compat lint | bash 3.2-safe arrays as `run-arms.sh` |
| Report | Python 3.13 stdlib (`json`, `random`, `statistics`) | fingerprint | no third-party imports (T1.15 import guard: no `urllib.parse` token) |
| YAML/JSON | yq 4.44, jq 1.7 | fingerprint | yq via env(), jq --arg |
| Tests | bats 1.13 (harness), pytest 9.0 (Python fixtures), bats for Loa-history tasks | fingerprint | hidden tests run under `env -i PATH HOME TMPDIR LC_ALL` |
| Sandbox | host temp-dir (`/tmp/loa-eval-*`), `sandbox.sh` | — | Docker 26.1 `Dockerfile.sandbox` unused by the executor (DEC-0362) |

---

## 3. Database Design

### 3.1 `grimoires/loa/reports/ablation-2.0/runs.jsonl` (tracked, one row per run)

```json
{"schema_version": 1, "run_id": "abl-<batch>-<arm>-<task>-t<n>", "batch": "priority-1", "arm": "a1_full",
 "task_id": "bugfix-02", "task_type": "bug-fix", "trial": 2, "source_commit": "4d69c3c4…", "suite_manifest_sha256": "…",
 "host_fingerprint": "…", "image_digest": "fp:…", "agy_opt_in": false, "started": "…Z", "finished": "…Z",
 "phases": [{"name": "IMPLEMENT", "session_id": "…", "model_requested": "global.anthropic.claude-opus-5-5",
             "models_used": {"global.anthropic.claude-opus-5-5": 18211}, "effort_requested": "xhigh", "effort_effective": "xhigh",
             "tokens_in": 410233, "tokens_out": 18211, "cost_usd": 1.92, "duration_ms": 812000, "num_turns": 31, "exit": 0,
             "refusal_fallbacks": []}],
 "voices_run": {"review": {"planned": 2, "completed": 2, "quality": "APPROVED"}, "audit": {"planned": 2, "completed": 2, "quality": "APPROVED"}},
 "hidden_tests": {"passed": 7, "total": 8}, "hidden_test_pass_rate": 0.875,
 "defects_seeded": null, "defects_caught": null, "defect_catch_rate": null, "flags": null, "false_positives": null,
 "verdict": "APPROVED", "verdict_accuracy": false, "regressions": 0, "diff_lines": 118, "files_changed": 3,
 "cost_usd": 6.41, "wall_clock_ms": 2411000, "tokens_in": 1211000, "tokens_out": 61200, "stalls": 0, "attempts": 1, "retry_reason": null,
 "degraded": false, "degraded_reason": null, "status": "completed"}
```

`status` ∈ {`completed`, `cap_failure`, `agent_error`, `transport_error`, `infrastructure_error`, `interrupted`, `contaminated`}; treatment (DEC-0417): `completed` graded; `cap_failure` 0 on every applicable primary; `agent_error` (a phase exited non-zero or timed out on the model's own account) scores what its final tree earns; `transport_error` (after the one retry), `infrastructure_error` (incl. a failed took-effect check), `interrupted`, `degraded` and `contaminated` are excluded pairwise and listed; a transport-failed first attempt writes no row, `attempts` counts it and its sandbox ledger cost counts in spend; nullability by arm: `verdict*`, `voices_run` null for A0 and A4; `hidden_tests` null for review-catch rows; defect fields null for build rows; `effort_requested` per phase is the resolved value (A1: the sandbox skill frontmatter; A0 `high`; A7 `medium`) and `effort_effective` comes from the sandbox MODELINV where a cheval hop exists, else null (DEC-0419); phases also record `cache_read_tokens` and `cache_creation_tokens`; `zone_violations: {dot_claude_writes[]}` from the transcript; rows also carry `suite_version`, `snapshots: {implement, fix1, fix2}` (sandbox commit ids), `verdict_accuracy_review`, `verdict_accuracy_audit` (per-gate, against the snapshot each gate reviewed; `verdict_accuracy` = audit's else review's), `contaminated: {phase, pattern} | null`; `degraded` is true when any phase's `models_used` has a key other than `model_requested`, `refusal_fallbacks` is non-empty, a MODELINV `effort_effective` differs from the requested effort, or a dissent envelope's `verdict_quality` is DEGRADED or its completed voices are fewer than planned; `degraded_reason` names which. Review-catch rows fill the defect fields and leave `hidden_tests` null; build rows the reverse. `ablation-row.sh --validate` enforces presence and types.

### 3.2 `grimoires/loa/evals/ablation-2.0/tasks/<id>/task.yaml`

```yaml
id: bugfix-02
schema_version: 1
type: bug-fix            # feature-build | bug-fix | refactor | review-catch
source: {kind: loa-history, fix_commit: "abcd1234", base_commit: "abcd1233", date: "2026-09-21"}
post_cutoff: true
fixture: fixtures/bugfix-02        # the tree the sandbox starts from (base state)
criterion: "the batch runner stops launching trials once the recorded spend would pass a given ceiling and says so in its status file"   # agent-facing: behaviour, never a path or test name (DEC-0424)
success_criterion: "hidden/tests/unit/x.bats passes (12 of 12) and the regression command is green"   # grader-facing
test_command: ["bats", "hidden-tests/x.bats"]       # allowlisted first token; hidden/ is copied to hidden-tests/ by the grader
regression_command: ["bats", "tests/unit/y.bats"]  # green at base; newly failing cases count
reference_patch: hidden/reference.patch           # for --self-check only
bounds: {max_turns: {IMPLEMENT: 60}, timeout_min: {IMPLEMENT: 25}}
grader_protected: [tests/conftest.py, pytest.ini]   # restored from the frozen reference before grading (DEC-0395)
structural_check: null     # refactor tasks: a hidden bats/pytest case red at base, green at the reference (DEC-0401)
suite_version: 1           # bumped with the manifest when a task changes after the smoke (DEC-0404)
review_catch: null        # review-catch tasks: {fixture: review-prs/pr-14, manifest: evals/fixtures/review-prs/manifests/pr-14.json}
```

`hidden/` holds `tests/…`, `manifest.json` (destination paths), `reference.patch` and, for review-catch tasks, nothing (the corpus manifest is the key). `REVIEW.md` is the fairness record. `MANIFEST.sha256` covers every file under `tasks/` and is the suite's frozen identity; `freeze.sh --check` runs before any trial and before every grading. `evals/harness/validate-suite.sh` (DEC-0424) checks every `task.yaml` against the schema, the four-by-four type counts, the `test_command` allowlist (`python3`, `pytest`, `bats`, `bash`, `node`, `npx`), `hidden/manifest.json` destinations inside the tree, the fixture path rule, and the absence of hidden paths, defect keys or arm ids in `TASK.md`, `criterion`, task-brief text and phase prompts; `freeze.sh --check` and `run-ablation.sh` call it. The schema, `freeze.sh` and `validate-suite.sh` land in Sprint 258 so the smoke runs on real task files.

### 3.3 `evals/suites/ablation-2.0.yaml`

```yaml
name: ablation-2.0
version: 1
source_commit: "4d69c3c4e68059a8837403a1489977a9caaa7caa"
agy_opt_in: false
tasks: {root: grimoires/loa/evals/ablation-2.0/tasks, manifest: grimoires/loa/evals/ablation-2.0/MANIFEST.sha256}
suite_version: 1
trials: {build: 3, review-catch: 3}      # D-A4: review-catch trials 3, not 5, under the gate pipeline
cut_ladder: ["A5, A6, A7 not run", "A2 and A3 build trials 3 -> 2", "A3 review-catch trials 3 -> 2"]   # DEC-0397; A0, A1, A4 keep 3
caps: {cycle_usd: 1500, run_usd: 12, reserve_usd: 250}   # reserve released to A7 when the re-verification rule needs no run (DEC-0398)
priority: [a0_bare, a1_full, a2_no_sprint_plan, a3_one_voice, a4_no_gates, a7_effort_medium, a5_no_flatline, a6_one_window]
arms:
  - {id: a0_bare, label: A0, task_types: [all], toggles: {loa_mount: false}, phases: [BARE], effort: high,
     took_effect: [no_dot_claude, no_system_prompt, no_audit_rows]}
  - {id: a1_full, label: A1, task_types: [all], toggles: {}, took_effect: [all_phases_present]}
  - {id: a2_no_sprint_plan, label: A2, task_types: [build], toggles: {sprint_plan: false}, took_effect: [no_plan_phase]}
  - {id: a3_one_voice, label: A3, task_types: [all], toggles: {companion_voice: false}, took_effect: [one_voice_planned]}
  - {id: a4_no_gates, label: A4, task_types: [build], toggles: {gates: false}, took_effect: [no_gate_phases, enforce_env_false]}   # build only: on a review-catch task the gates are the task (DEC-0400)
  - {id: a5_no_flatline, label: A5, task_types: [build], toggles: {flatline: false}, took_effect: [no_flatline_rows]}
  - {id: a6_one_window, label: A6, task_types: [build], toggles: {context_resets: false}, took_effect: [implementer_single_session, gates_separate_sessions]}
  - {id: a7_effort_medium, label: A7, task_types: [all], toggles: {effort: medium}, took_effect: [effort_flag_medium, skill_effort_stripped]}
  - {id: a8_no_ceremonies, label: A8, absent: true,
     evidence: "no /meeting command, skill or sosyete config key at 4d69c3c4 (grep -rli sosyete .claude/ docs/; ls .claude/commands .claude/skills)"}
rules:   # D-A5: pre-registered, mirrored in NOTES
  threshold_points: 0.03
  cost_lower_pct: 15
  bootstrap: {resamples: 10000, level: 0.90, paired: true, units: {hidden_test_pass_rate: tasks, defect_catch_rate: defects}, also_report: {defect_catch_rate: tasks}}   # DEC-0399
  primaries_by_arm: {build_only: [hidden_test_pass_rate], all_types: [hidden_test_pass_rate, defect_catch_rate]}   # DEC-0400
  cap_failure: counts_as_failed            # 0 on each applicable primary (DEC-0393)
  exclusion: {statuses: [degraded, contaminated, interrupted], mode: pairwise, inconclusive_above_share: 0.25}
  sensitivity_figure: cap_failures_excluded  # printed, never decides
  multiple_comparisons: none                 # expected false positives at 0.90 over 6 components printed
  drift_guard: {cli_version: fixed_per_batch, model_ids: fixed_per_batch}   # DEC-0407
  order: trial_major_seeded_shuffle_within_block
  took_effect_per_trial: true                # a miss → infrastructure_error, arm paused until --clear-arm (DEC-0418)
  predicates:                                # DEC-0416; d = arm − A1 point estimate, [lo, hi] its 90 % interval, c/w = cost/wall-clock Δ %
    investigate: "any applicable primary has lo > 0"
    keep: "else any applicable primary has d < -0.03 and hi < 0"
    inconclusive: "else any applicable primary has d < -0.03, or the arm's excluded share > 0.25, or no valid pair"
    remove: "else every applicable primary has d >= -0.03 and (c <= -15 or w <= -15)"
    simplify: "else (every applicable primary within -0.03, cost similar)"
  review_catch: {defect_counts_once_across_gates: true, false_positive_dedupe: cited_region, verdict_accurate_iff: "CHANGES_REQUIRED when the key holds a high or critical defect, APPROVED when none"}   # DEC-0420
  inconclusive_extension_trials: 2
  h1: "a1_full beats a0_bare on at least one primary with the interval excluding zero, else halt before promotion"
  a4_sensitivity: "a4_no_gates worse than a1_full on hidden_test_pass_rate with the interval excluding zero, else harden tasks before acting on other arms"
```

### 3.4 `MANIFEST.json` and `STATUS.json` per batch
`MANIFEST.json` as `run-arms.sh` writes it, plus `arm_map` (run_id → arm; the grader never reads this file), `shuffle_seed`, `fingerprint`, `image_digest`, `executor_mode: container|host`, `tools`, `trials_per_type`, `caps`, `pre_registration_ref` (the NOTES heading and its timestamp), `suite_manifest_sha256`, `suite_version`, `source_commit_dot_claude_delta` (the `git diff --stat 4d69c3c4..<pin> -- .claude/` text). `STATUS.json`: `{state, per_arm: {trials_planned, launched, completed, failed, excluded, cap_failures}, retries, cuts: [{reason, spent, in_flight_reserved, max, at_trial}], paused_arms, spend: {rows_usd, ledger_usd}, resume_cursor, started, finished}`.

### 3.5 `pipeline.json` (per run, under `.eval/`)
`{schema_version, run_id, arm, task_id, trial, source_commit, phases: [...as §3.1], status, cap_phase, sandbox_fingerprint, started, finished}`; the stream-json events of every phase are kept as `.eval/events-<phase>.jsonl` (artefacts dir, not the record), the dissent envelopes copied from `grimoires/loa/a2a/sprint-1/adversarial-*.json`.

### 3.6 `grade.json` (per run)
`{hidden_tests: {passed, total, failed_names[]}, regressions: {newly_failing[]}, recall: {...recall-vs-defects details}, false_positives, verdict: {source_file, value}, verdict_accuracy, diff_lines, files_changed, grader_version}`.

### 3.7 Changes to existing data
- `.claude/checksums.json` regenerated from `git ls-files .claude` (about 1,975 entries, down from 3,387).
- `evals/fixtures/review-prs/manifests/pr-11 … pr-18.json` `fix_regions` without generated paths; `SHA256SUMS` refrozen; the cycle-129 batch-1 refuted share regraded into `a2a/sprint-259/regrade-batch-1.md`.
- `grimoires/loa/ledger.json`: cycle-130 with sprints 258–262 (done in the plan commit).

---

## 4. UI Design

### 4.1 Script output lines
- `run-ablation.sh`: `plan: 8 arms, 16 tasks, 236 trials, shuffle seed 20261015, est USD 1,310 (cap 1,500, reserve 150)`; per trial `done abl-… a1_full bugfix-02 t2 pass=0.875 USD 6.41 40m`; `cut: max_usd 1270.0 reached after 212 trials (reason recorded in STATUS.json)`.
- `took-effect.sh`: `arm a7_effort_medium: --effort medium on 6/6 phases; skill effort lines stripped 6/6 — OK` or `FAIL arm a3_one_voice: review envelope companion_voice.planned=true`.
- `spend.sh`: `cycle spend USD 812.40 (runs 760.10 + ledger 52.30 since 2026-10-14T13:50Z); cap 1,500; headroom 687.60; reserve 150`.

### 4.2 `report.md` shape
Header (source commit, suite manifest, fingerprint, pre-registration pointer, exclusions); H1 and A4 verdict lines; one decision table (component | arm | n | pass-rate Δ [90 % CI] | catch-rate Δ [90 % CI] | cost Δ % | wall-clock Δ % | decision | rule matched | rows); per-arm detail tables; excluded runs with reasons; cuts with figures; the lead's reading; re-verification table (Sprint 262).

### 4.3 Sprint task line
As cycle-129: `- [ ] Task N.M: … → **[G-x]** ⇐ deps · kind: mechanical|judgment`.

---

## 5. API Specifications

### 5.1 `tools/gen-checksums.sh [--check] [--root DIR]`
Writes `.claude/checksums.json` `{generated, algorithm: sha256, files: {<path>: <sha256>}}` over `git -C root ls-files .claude` minus `.claude/overrides/*` and the manifest; `--check` regenerates to a temp file and compares the `files` map (exit 0 same, 1 drift with the first ten differing paths, 2 usage). Deterministic order (`LC_ALL=C sort`).

### 5.2 `tools/check-manifest-paths.sh [--manifest F] [--root DIR]`
Exit 0 when every manifest path is tracked and exists and none matches `(^|/)(__pycache__|\.pytest_cache|node_modules|\.run)(/|$)|\.pyc$|\.lock$`; exit 1 with the offending paths grouped by class; exit 2 usage.

### 5.3 `check-loa.sh` integrity (changed)
When `.loa/.claude` exists (submodule mount) and a manifest path is absent locally but present under `.loa/.claude/`, count it as `not-mounted` and print one summary line; a path absent in both is `Missing`; a hash mismatch is `Tampered`. Exit code unchanged otherwise (fail on Tampered or Missing).

### 5.4 `tools/fresh-mount-proof.sh [--ref REF] [--keep]`
Clones this repository at `REF` into a temp dir as the downstream's `.loa/` submodule, runs the submodule mount (`mount-submodule.sh` path), sets `aleph.enabled: false`, runs `check-loa.sh`, prints the integrity summary and exits with its code; `--keep` leaves the temp dir.

### 5.5 `run-arms.sh --max-usd <usd> | --screen [--screen-tasks N]` (added)
`--max-usd`: before launching a trial, if `spent + in_flight × run_cap + est_next > max` (in-flight trials reserve the per-run cap each; est_next = the mean of completed trials of the same arm × task type when one exists, else the pooled mean, else the suite's `cost_hint`) stop launching, wait for running jobs, write `STATUS.json.cut = {reason: max_usd, spent, max, trials_launched}`, exit 1. `--screen`: one trial of the first N tasks per arm, prints the per-arm cost/recall table, writes to `<results>/screen/`, never touches the suite `STATUS.json`. **Sprint 258 amendment (audit MEDIUM-A2, DEC-0497):** a trial that ends without `completed` and without a reported cost, or that writes no row, is charged `run_cap` to the batch spend (never to `est_next`'s means) and counted in `STATUS.json.spend.assumed_cap_trials`; the suite aggregate excludes screen batches by the `screen: true` marker, and `--batch screen-*` without `--screen` is refused (review LOW-3).

### 5.6 `pipeline-run.sh --task-yaml F --arm ID --workspace WS --run-id R --trial N --source-tree DIR --suite-file F [--max-run-usd 12] [--phase-timeouts JSON] [--claude-bin B]`
Exit 0 run finished (any verdict), 1 agent error (a phase exited non-zero or timed out; `pipeline.json` written), 2 infrastructure (CLI missing, mount failed, toggle could not take effect), 3 cap failure (run stopped at the cap; `pipeline.json` written). Env: `EVAL_CLAUDE_BIN`, `LOA_EVAL_PHASE_MODELS` (JSON override for tests), `LOA_EVAL_ARM_TOGGLES` ignored unless set by the suite resolver (cycle-129 DISS-C-001 rule). **Sprint 258 amendment (audit MEDIUM-A1, LOW-A2):** each gate's dissent envelope is copied to `eval/adversarial-<gate>.json` once, when that gate's phase ends (never overwritten, a symlink never copied), and the gate record carries `envelope_copied` and `envelope_sha256`; the sha256 of `CLAUDE.md` and `.loa.config.yaml` is recorded at materialisation (`arm_evidence`) and compared at finish into `pipeline.json.mount_integrity` (`ok|changed|absent`).

### 5.7 `ablation-grade.sh <run-dir> <task-id> [--self-check base|reference] [--json]`
Builds the grading tree per D-4.8 for the final tree and for every gate snapshot, runs `test_command` and `regression_command`, parses pytest (`N passed, M failed`) or TAP (`ok`/`not ok`) counts, runs `recall-vs-defects.sh` on `gates-combined.md` (the arm-neutral reduction of `review.md`, `engineer-feedback.md`, `auditor-sprint-feedback.md` and the cited findings of both dissent envelopes) for review-catch tasks, scores verdict accuracy per gate against its snapshot, runs the contamination scan (D-4.7), writes `grade.json` with ids only (no test names or defect titles in summary fields). `--self-check reference` grades the reference patch (bug-fix, feature-build: pass; refactor: structural check green and suite green; review-catch: a findings file citing every key anchor → recall 1) and `--self-check base` the base tree (bug-fix, feature-build: fail; refactor: structural check red; review-catch: an empty findings file → recall 0) (DEC-0401). Exit 0 graded, 2 error. Never reads `MANIFEST.json`.

### 5.8 `ablation-row.sh --run-dir D --task-yaml F --grade grade.json --manifest MANIFEST.json --out runs.jsonl | --validate runs.jsonl`
Joins `pipeline.json`, `grade.json`, the sandbox MODELINV and cost ledger (per-phase `effort_effective`, tokens, cost of voice calls) and the manifest (arm, fingerprint) into one row; `--validate` checks every field's presence and type and exits 1 on the first bad row. **Sprint 258 amendment (review MEDIUM-2, audit MEDIUM-A1, LOW-A2, LOW-A5):** every run-scaled input reaches jq through `--slurpfile`; the envelopes are read from `eval/` first (the sandbox copy only for legacy runs) and `zone_violations` carries `dot_claude_writes`, `bash_mount_refs` (write-shaped Bash commands naming the mount; a heuristic), `mount_changed` and `envelope_mismatch`; the arm must match `^[a-z][a-z0-9_]{0,63}$` in the writer and in `--validate`.

### 5.9 `run-ablation.sh --arms CSV --source-commit SHA [--tasks CSV] [--types CSV] [--trials-build N] [--trials-review N] [--max-usd USD] [--concurrency 3] [--batch NAME] [--smoke] [--dry-run] [--resume] [--detach]`
Verifies `freeze.sh --check` (which runs `validate-suite.sh`) and the corpus `SHA256SUMS`, runs `took-effect.sh` after every trial (a miss → `infrastructure_error`, the arm paused in `STATUS.json.paused_arms` until `--clear-arm <id>`), builds the plan (arm × applicable task × trial; an arm on a task type outside its `task_types` is refused at planning, DEC-0405), orders it trial-major and shuffles inside each trial block with a recorded seed (DEC-0407), refuses to continue a batch whose CLI version or phase model ids differ from `MANIFEST.json`, runs trials through `pipeline-run.sh` (bounded concurrency; one transport retry), grades, appends rows, maintains `STATUS.json` as `run-arms.sh` does, posts the spend line at the end. `--smoke`: one review-catch and one build task, one trial, every runnable arm, then `took-effect.sh`. `--resume`: reconciles `STATUS.json` from rows on disk and continues the plan. Exit 0 complete, 1 partial or cut, 2 usage/refused, 3 failed or took-effect failure.

### 5.10 `took-effect.sh --batch-dir D [--arm ID]`
Reads `pipeline.json`, phase argv captures, sandbox MODELINV, dissent envelopes and the sandbox tree listing recorded at mount time; prints one line per arm and exits 0 only when every arm's evidence list is satisfied.

### 5.11 `spend.sh [--since TS] [--runs F] [--ledger F] [--cap USD] [--json]`
Sums `cost_usd` over rows and `cost_micro_usd` over ledger rows with `ts ≥ since`; prints total, components, cap, headroom, reserve. **Sprint 258 amendment (review LOW-2):** a skipped (unparseable) line marks the total `INCOMPLETE (N skipped)` with exit 1 and `complete: false`; a run rowed twice counts its larger `cost_usd`.

### 5.12 `ablation-report.py --runs F --manifests DIR --suite F --out report.md [--seed 20261015] [--exclude-degraded true]`
Metrics per arm (task-mean of trial means), paired bootstrap of the arm − A1 difference over tasks (10,000 resamples, 5th/95th percentiles), cost and wall-clock deltas, rule application in the order Investigate → Keep → Inconclusive → Remove → Simplify (first match on the pre-registered conditions), H1 and A4 lines, exclusions, cuts; `--json` twin.

### 5.13 `freeze.sh [--check]`
Writes `MANIFEST.sha256` over every file under `tasks/` (sorted, `LC_ALL=C`); `--check` recomputes and diffs (exit 1 on drift). **Sprint 258 amendment (review LOW-4):** a symlink or a newline path under a covered directory is refused (exit 1) before hashing, on write and `--check` alike.

### 5.14 `seed-bugfix-tasks.sh --since DATE --select N --out DIR` and `seed-refactor-tasks.sh`
Lists Loa fix commits whose diff touched a test file; for each candidate materialises base (parent) and reference (the commit) trees for the touched paths plus their runners, proves red at base and green at reference under `env -i`, writes `task.yaml`, `TASK.md` (subject plus the test names, no solution text), `hidden/`; the lead selects four with the written criteria (judgment). The refactor seeder selects commits whose test files are unchanged, green at both ends, touching ≥ 2 source files, and records churn.

### 5.15 Config keys added
`evals.ablation.cycle_cap_usd`, `evals.ablation.run_cap_usd` (defaults 1500, 12) read by the scripts when the flags are absent; nothing else. Sprint 262's opt-in moves use existing keys and `profiles.yaml` only.

---

## 6. Error Handling Strategy

| Condition | Handling |
|---|---|
| Toggle cannot take effect | trial exit 2 before any model call; row `infrastructure_error`; batch continues |
| Took-effect evidence missing after a trial | row `infrastructure_error`; arm paused until `--clear-arm`; batch continues on other arms |
| Container cannot authenticate or complete the smoke run | executor mode `host` for the whole cycle; limit stated in the report; `image_digest` = fingerprint |
| Phase CLI non-zero or timeout | phase `exit` recorded; run `agent_error`; no retry unless the stderr classifier (cycle-129 transport patterns, CLI stderr only) says transport → one retry after `--retry-wait` |
| Cap reached | `cap_failure`, `cap_phase`; graded (raw score kept); scored 0 on every applicable primary; cost counts in spend |
| Phase killed (SIGTERM/SIGKILL, reboot) | `interrupted`; no grade; not counted; listed; `--resume` reruns when budget allows |
| Contamination scan hit | `contaminated`; excluded pairwise; listed per arm; cost counts in spend |
| CLI version or model id differs from the batch manifest | batch `failed` (drift); rows kept and listed; new batch needed |
| Hidden test files missing or unreadable | grader exit 2 → row `infrastructure_error`; the batch's STATUS lists it; the lead fixes the task and reruns that cell |
| Suite drift (`freeze.sh --check` ≠ 0) or corpus drift | refuse to start (exit 2) |
| `--max-usd` reached | stop launching, finish running jobs, `cut` recorded, exit 1 |
| Degraded phase (model fallback, effort mismatch, DEGRADED envelope, fewer voices than planned) | row `degraded: true` with reason; excluded pairwise (the task-trial cell leaves both arms); an arm over 25 % excluded reads Inconclusive-by-degradation; listed; cost counts in spend |
| Dissent voice unavailable (breaker OPEN, provider down) | the envelope says so (`voices_planned` vs completed) → degraded; not retried as transport |
| Host reboot mid-batch | `--resume` reconciles from rows and `pipeline.json` files; a run without `pipeline.json` is rerun |
| Sandbox contains a hidden path | grader refuses (exit 2) and names it; bats pins |

Exit codes follow the tables in §5; every refusal names the reason on one stderr line.

---

## 7. Testing Strategy

| Seam | Test | Catches | Misses |
|---|---|---|---|
| `gen-checksums.sh` on a fixture repo with untracked and overrides files | `tests/unit/gen-checksums.bats` | untracked entries, overrides included, non-determinism, `--check` drift | — |
| `check-manifest-paths.sh` on fixture manifests | `tests/unit/check-manifest-paths.bats` | untracked path, absent path, each forbidden class | a tracked build artefact |
| `check-loa.sh` integrity on a fixture submodule layout | `tests/unit/check-loa-mount-scope.bats` | not-mounted vs Missing vs Tampered, exit codes | real `update-loa.sh` layouts other than the fixture |
| `fresh-mount-proof.sh` | live run recorded in the sprint report | the #1267 class end to end | network-dependent |
| container launcher with a stub `docker` (26.1 CLI shape) | `evals/tests/pipeline-run.bats` | mount set (sandbox rw, three credential copies ro, nothing else), flags, image id recorded | real container behaviour (the smoke) |
| `validate-suite.sh` on fixture suites | `evals/tests/validate-suite.bats` | schema, counts, allowlist, destinations, leakage strings, path rule | task quality |
| grader with `meta/` removed | `evals/tests/ablation-grade.bats` | any read of an arm-aware file | — |
| `run-arms.sh --max-usd`, `--screen` | `evals/tests/run-arms.bats` (stub executor) | cut before the third USD 5 trial, `cut_reason`, screen writes no suite STATUS | real cost estimates |
| toggles `loa_mount`, `effort`, `gates`, `flatline` + skill effort strip | `evals/tests/arm-toggles.bats` | toggle leaves text/config; baseline takes none; env var leak | prompt-cache effects |
| `pipeline-run.sh` with a stub CLI | `evals/tests/pipeline-run.bats` | phase order per arm, one session for A6, no PLAN for A2, stop after IMPLEMENT for A4, cap abort, hidden path absent, credential unset, `--setting-sources project` | live model behaviour |
| `ablation-grade.sh` on fixture runs | `evals/tests/ablation-grade.bats` | hidden tests applied after the run, deleted test dir restored, verdict accuracy truth table, review combined file, self-check both directions | grading quality of real reviews |
| `ablation-row.sh --validate` | `evals/tests/ablation-row.bats` | missing field, wrong type, degraded derivation | — |
| `run-ablation.sh --dry-run`, `--resume` on a fixture batch | `evals/tests/run-ablation.bats` | plan shape, shuffle seed recorded, applicability refusal, resume reconciliation, freeze refusal | provider behaviour |
| `took-effect.sh` on fixture artefacts | `evals/tests/took-effect.bats` | each evidence rule's pass and fail | evidence the artefacts do not carry |
| `spend.sh` on fixture rows and ledger | `evals/tests/spend.bats` | sums, since filter, headroom | — |
| `ablation-report.py` on a planted `runs.jsonl` | `evals/tests/ablation-report.bats` | each rule branch, H1 and A4 lines, exclusion list, applicability | real-data edge cases |
| `freeze.sh` | `evals/tests/freeze.bats` | drift of one byte | — |
| `seed-bugfix-tasks.sh` on a fixture repo | `evals/tests/seed-bugfix.bats` | red/green proof, solution leak check (no diff hunk text in TASK.md) | task quality (the fairness review) |
| `seed-corpus-from-record.sh` fix_regions exclusion | `evals/tests/seed-corpus.bats` (+ cases) | generated path in `fix_regions` | — |
| floor | `tests/unit/floor-snapshot.bats`, `profile-floor.bats` | any floor file changed | — |
| CI | Shell Tests job runs the new bats files and `check-manifest-paths.sh`; `check-no-raw-sha256sum.sh`, shell-compat lint, `sync-fixtures.sh --check` before every commit | — | — |

Live checks recorded, not asserted by CI: the Sprint 258 smoke on `pr-01` and `implement-tasks/01`; the Sprint 259 self-check 16/16; the Sprint 260 smoke and took-effect on the frozen suite; the Sprint 262 re-verification.

---

## 8. Development Phases

### Sprint 1 (global 258): mount integrity and harness plumbing
FR-1 (gen-checksums, check-manifest-paths, mount-scoped check-loa, fresh-mount proof, version markers), FR-2 (`--max-usd`, `--screen`, `spend.sh`), FR-3 (suite file, toggles), FR-4 (pipeline executor, container launcher and image, phase prompts, fingerprint, watchdog), FR-5 schema, `freeze.sh`, `validate-suite.sh`, FR-6 row writer and validator, smoke on two task files built from the existing fixtures with `took-effect.sh`; the container-or-host decision. Exit: fresh mount green; smoke shows each arm's config in its artefacts.

### Sprint 2 (global 259): task suite and grader
FR-5 (schema, freeze, seeders, sixteen tasks, fairness reviews), FR-6 grader and `--self-check` 16/16, FR-10 bd-8o5rx. Exit: manifest hash committed; grader scores known-good and known-bad correctly on every task.

### Sprint 3 (global 260): runs
FR-7: pre-registration in NOTES, smoke on the frozen suite, cap-fit read (DEC-0378), budget calibration from smoke actuals (D-A4), priority batch detached (`setsid nohup`, logs under `~/.cache/loa/cycle-130/`), spend posted after every batch, A4 sensitivity and H1 read, A7/A5/A6 if room, cuts recorded. Exit: all planned runs recorded or cut with reason.

### Sprint 4 (global 261): analysis
FR-8: `ablation-report.py`, blind grading pass, bootstrap, rules, `report.md`, inconclusive extension once, Decision Log entries after. Exit: one decision per component.

### Sprint 5 (global 262): prune and document
FR-9, FR-10: opt-in moves, addendum, measured-lift sentences, `a1_pruned` re-verification on the reserve set, bd-2txz1 decision, release-notes report, E2E (G-1 … G-6). Exit: pruned default within −0.03 of old A1 on both primaries.

---

## 9. Known Risks and Mitigation

| Risk | Mitigation in the design |
|---|---|
| The implementing skill asks a question in a headless phase (Success Criteria gate, beads) | PLAN writes `## Success Criteria`; the materialiser writes it for A2 into the brief and the IMPLEMENT prompt names it; `br init` + one bead; the phase timeout bounds a stall and records `stalls` |
| A phase edits `.claude/` in the sandbox | no zone marker in the sandbox; the fence and zone guard are live under `--setting-sources project`; the grader counts `.claude/` writes as a zone violation in `grade.json` (reported, not a metric) |
| Fable refuses a review phase and the CLI falls back | `models_used` ≠ requested → degraded, excluded, listed; contingency pre-registered: if more than 20 % of A1 gate phases degrade in the smoke, the gates run on Opus 5.5 for every arm (recorded before the batch) |
| Prompt-cache or provider load differences between arms | randomised interleaving with a recorded seed; one host, one route |
| `--max-usd` estimate wrong | the estimate uses completed trials' actuals; the cap is checked before each launch and the running jobs can overshoot by at most concurrency × run cap (stated in the report) |
| Record fixtures too large for a Fable review phase under the cap | review-catch trials at 3; the smoke measures; a fixture whose A1 trial exceeds USD 9 is swapped for a smaller one before the batch (DEC-0378 analogue, recorded) |
| Hidden tests leak via the agent's own `git log` in a Loa-history fixture | fixtures are materialised as trees, not clones; `git init` starts a fresh history at base |
| A Bash agent on the same host reads the repository's `hidden/` or alters test infrastructure | container executor with read-only credential copies and no other host mount (D-4.9); grading tree with restored `grader_protected` files; contamination scan; if the container cannot run, the limit is stated in the report |
| A task under `.claude/` collides with the mount | fixture path rule refused by the seeders and the materialiser |

---

## 10. Open Questions

None blocking. Two items are decided by data inside the cycle and recorded when known: the budget calibration after the smoke (which arms beyond A0–A4 run) and the gate-model contingency (Fable refusals above 20 % in the smoke).

---

## 11. Appendix

### 11.1 File inventory
New: `tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`, `tools/fresh-mount-proof.sh`, `evals/suites/ablation-2.0.yaml`, `evals/harness/{pipeline-run.sh,run-ablation.sh,ablation-grade.sh,ablation-row.sh,took-effect.sh,spend.sh,fingerprint.sh,freeze.sh,seed-bugfix-tasks.sh,seed-refactor-tasks.sh,ablation-report.py}`, `evals/harness/lib/{sandbox-mount.sh,phase-prompts/*.md}`, `grimoires/loa/evals/ablation-2.0/**`, `grimoires/loa/reports/ablation-2.0/**`, `docs/migration/v2.0-ablation-addendum.md`, `tests/unit/{gen-checksums,check-manifest-paths,check-loa-mount-scope}.bats`, `evals/tests/{pipeline-run,ablation-grade,ablation-row,run-ablation,took-effect,spend,ablation-report,freeze,seed-bugfix}.bats`. Changed: `.claude/scripts/check-loa.sh`, `.claude/checksums.json`, `.loa-version.json`, `.claude/loa/CLAUDE.loa.md` marker, `.github/workflows/bats-tests.yml`, `evals/harness/{run-arms.sh,execute-agent.sh,seed-corpus-from-record.sh}`, `evals/fixtures/review-prs/{manifests/*.json,SHA256SUMS}`, `evals/tests/{run-arms,arm-toggles,seed-corpus}.bats`, `.loa.config.yaml.example`, `.claude/data/profiles.yaml`, component reference docs, `CHANGELOG.md`.

### 11.2 PRD → SDD map

| PRD | SDD |
|---|---|
| FR-1 | §5.1–5.4, §3.7 |
| FR-2 | §5.5, §5.11, §1.4 D-4.6 |
| FR-3 | §3.3, §1.4 D-4.2 |
| FR-4 | §1.4 D-4.1–D-4.6, §5.6 |
| FR-5 | §3.2, §5.13, §5.14 |
| FR-6 | §3.1, §3.6, §5.7, §5.8 |
| FR-7 | §5.9, §5.10, §3.4 |
| FR-8 | §5.12, §4.2 |
| FR-9 | §8 Sprint 5, §5.15 |
| FR-10 | §3.7 |

### 11.3 Decisions taken on the operator's behalf (this SDD, `proposed` rows)

| # | Decision | Alternative | Why |
|---|---|---|---|
| A1 (DEC-0379) | One executor (`pipeline-run.sh`) runs every task type; review-catch tasks run the gate phases (REVIEW → AUDIT) so the dissent voices count as gates; the cycle-129 single-skill path stays for the recall suites | single-skill review for review-catch | with Read/Grep/Glob/Write no dissent runs, so A3 would remove nothing (cycle-129's `no_companion` showed that) |
| A2 (DEC-0380) | The arm config is the pinned tree's `.loa.config.yaml` (this repository's) with the arm's toggles applied, as cycle-129 materialised it | the shipped example config | the example's route defaults do not run on this host; the repository config is what the harness runs with here, identically for every arm |
| A3 (DEC-0381) | A1 passes no `--effort` (Loa's skill-frontmatter efforts are the default under test); A0 passes `--effort high`; A7 strips `effort:` from every sandbox SKILL.md, passes `--effort medium` and sets `default_effort: medium` in the sandbox catalog | `--effort high` on A1 too | the brief's A1 is "default config"; the skills' efforts are part of it |
| A4 (DEC-0382) | Review-catch trials are 3, not 5; budget is recalibrated from smoke actuals before the batch, with a written projection | 5 as the brief says | under the gate pipeline a review-catch trial costs as much as a build run; the brief's 5 assumed cheaper trials |
| A5 (DEC-0383) | Rules live in the suite file and are mirrored in NOTES; `ablation-report.py` reads the suite file | rules only in prose | a script applies them; prose is for the record |
| A6 (DEC-0384) | Sandbox sessions use `--setting-sources project` so only the mounted tree's settings and hooks apply | inherit the operator's settings | the operator's user settings are not part of any arm |
| A7 (DEC-0385) | Fixture trees are materialised as files with a fresh `git init` at base, never as clones | clone at the pinned commit | the fix commit (the answer) would be reachable in history |
| A8 (DEC-0386) | Gate phases run on Fable 5.1 as the brief says, with a pre-registered contingency to Opus 5.5 for every arm if more than 20 % of A1 gate phases degrade in the smoke | Opus gates from the start | the brief names Fable as reviewer; the contingency keeps homogeneity if it refuses |
| A9 (DEC-0387) | The fairness reviewer is a separate Opus 5.5 session per task that runs the hidden tests red-then-green itself | a read-only review | running is the check that catches an unsolvable or leaked task |
| A10 (DEC-0388) | `grimoires/loa/reports/ablation-2.0/runs.jsonl` and `report.md` are tracked; raw run artefacts stay under `evals/results/ablation/` (gitignored) and go to the record branch | track the artefacts | megabytes of transcripts per run |
| A11 (DEC-0389) | The `image_digest` row field is `fp:<sha256 of toolchain versions + source tree id>` | leave it empty | the brief asks for a digest per run; the fingerprint is what one host can honestly record |
| A12 (DEC-0390) | A cap-failed run keeps whatever hidden-test score its tree earns but its `status` makes it a failed run in every primary (counted as 0 for pass rate and catch rate) | exclude cap failures | the brief: a cap failure is a failure, not a discard |

### 11.4 PRD Flatline integration carried into this SDD (2026-10-15)
The PRD Flatline run's twenty integration decisions (DEC-0391 … DEC-0410; PRD Appendix G) are reflected above: D-4.2 (A6 continuous implementer session, A0 budget, A4 build-only), D-4.3 (environment allowlist), D-4.5 (fixture path rule, snapshots), D-4.6 (interrupted), D-4.7 (contamination scan), D-4.8 (grading tree), §3.1 (statuses, per-gate accuracy, `suite_version`), §3.3 (rules block: units, applicability, exclusion, cut ladder, drift guard), §5.5 (in-flight reservation), §5.7 (self-check definitions), §5.9 (planner guard, ordering), §6 (new conditions).

### 11.5 SDD Flatline review integration (2026-10-15)
Run: `flatline-orchestrator.sh --doc grimoires/loa/sdd.md --phase sdd --autonomous` on the pre-F SDD; two voices, Phase 1 2/2, cross-scoring degraded (KF-041 shape), 8 blockers, 52 improvements. Integrated by judgment; rows DEC-0411 … DEC-0424.

| # | Blocker / item | Integration | DEC |
|---|---|---|---|
| S1 | SKP-004, SKP-001, SKP-002: host access, credentials, cross-sandbox interference, Bedrock spend outside the ledger | container executor with per-run read-only credential copies, no other host mount; host fallback recorded (user namespaces refused on this host) | DEC-0411 |
| S2 | SKP-002: git credential helper, ssh agent, startup files, descriptors | `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, `GH_CONFIG_DIR` empty, no `SSH_AUTH_SOCK`/`BASH_ENV`, fds > 2 closed | DEC-0412 |
| S3 | SKP-003, gpt IMP-004/008, opus IMP-008: `pipeline.json` carries the arm beside the grader's inputs | `meta/` boundary; grader reads `sandbox/`, `snapshots/`, hidden only; bats with `meta/` removed | DEC-0413 |
| S4 | SKP-002, SKP-004: freeze check only at batch start; hidden artefacts across retries | `freeze.sh --check` before every grading; hidden read from the checkout; fresh sandbox per attempt | DEC-0414 |
| S5 | SKP-003: cap bias | rule stands (DEC-0393); per-arm failure counts and the labelled cap-free figure printed | DEC-0415 |
| S6 | opus IMP-001/005, gpt IMP-005/006: predicates | executable predicates in the rules block and the report | DEC-0416 |
| S7 | gpt IMP-002/011, opus IMP-002/018: status treatment, retries | status→metric table; retry accounting | DEC-0417 |
| S8 | opus IMP-012, gpt IMP-007: took-effect only at smoke | per-trial evidence; arm paused on a miss | DEC-0418 |
| S9 | gpt IMP-013, opus IMP-013: effort fields, nullability | sources and nulls stated | DEC-0419 |
| S10 | gpt IMP-017, opus IMP-031: review-catch combination and verdict | defect once across gates; FP dedupe; severity-based verdict truth | DEC-0420 |
| S11 | opus IMP-004: sandbox manifest after toggles | `gen-checksums.sh` regenerates for every arm | DEC-0421 |
| S12 | opus IMP-028: in-phase overshoot | per-turn cost watchdog | DEC-0422 |
| S13 | opus IMP-006/026: A2 reads; PLAN ledger step | brief as the sprint for A2; materialiser registers the sprint | DEC-0423 |
| S14 | opus IMP-010/022/023, gpt IMP-003/009: criterion leak; suite validation; smoke task files | `criterion` vs `success_criterion`; `validate-suite.sh`; schema and freeze in Sprint 258 | DEC-0424 |

Also adopted without a row: `est_next` per arm × type (opus IMP-024), `zone_violations` in the row (IMP-025), cache token fields (IMP-016), the tools list stated and identical across arms (IMP-020), the A0/A1 model-mix confound stated in the report header (IMP-021: A0 is bare Opus 5.5 at `high`; A1 is Loa as shipped with Fable gates and skill efforts — H1 compares those two, as the brief defines them), the Fable-refusal contingency read over at least ten gate phases across the Sprint 258 and 260 smokes (IMP-027), `not-mounted` never changes the exit code (IMP-029), forbidden classes are diagnostics on untracked paths and a tracked path is never flagged (IMP-030), `STATUS.json` schema (gpt IMP-016), regression command proven green at base under `env -i` by the seeders (opus IMP-011). Not adopted: re-running AUDIT after the last FIX (opus IMP-009) — the per-gate snapshot accuracy answers the staleness question without a seventh phase under the cap.
