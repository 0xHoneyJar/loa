# Sprint 258 (local sprint-1) — implementation report (lead)

**Sprint:** sprint-258 · **Cycle:** cycle-130-ablation-2.0 · **Branch:** feature/cycle-130-ablation-2.0 · **Plan commit:** 252501b4 · **Implementers:** A (Opus 5.5, `../loa-wt-s1a`, Tasks 1.1–1.3), B (Opus 5.5, `../loa-wt-s1b`, Tasks 1.4, 1.5, 1.6, 1.11), C (Opus 5.5, `../loa-wt-s1c`, Tasks 1.7, 1.8, 1.12; two fix rounds), lead (1.0, 1.9, 1.10 and the integration fixes below) · **Reports:** reviewer-a.md, reviewer-b.md, reviewer-c.md (this directory), toolchain.md, smoke.md

## Executive Summary

Sprint 258 makes the measurement possible. The #1267 mount defect is closed at the source: the integrity manifest is generated from the tracked `.claude/` tree (1,973 entries, down from 3,387), a CI step fails on any manifest path that is untracked or absent, `check-loa.sh` scopes a submodule mount's unlinked paths as `not-mounted`, and a fresh-mount proof from this branch passes with 0 Tampered / 0 Missing / 423 not-mounted where the rc.5 tree failed with 1,835 Missing. The spend caps are scripts (`run-arms.sh --max-usd` with in-flight reservation, `--screen`, `spend.sh`). The ablation suite file declares the nine arms with toggles, applicability, took-effect evidence rules and the pre-registered rules block; `execute-agent.sh` gains four toggles and its materialisation moves into `lib/sandbox-mount.sh`; the task schema, `freeze.sh` and `validate-suite.sh` land with two smoke tasks. The pipeline executor runs Loa's phases as separate container sessions with snapshots, a cost watchdog, an environment allowlist that carries only the CLI's Bedrock route, and every arm-aware file under `meta/`; `ablation-row.sh` and `took-effect.sh` turn a run into a validated row with its evidence.

Integration found four defects the implementers could not have seen and fixed them at the lead's desk: C's first patch sourced `.claude/` libraries through variables and used one `eval` (the eval-workflow trust-boundary scan; C's second patch removed them); the executor's environment allowlist dropped the host's Bedrock bearer-token route, so the CLI fell back to the geo-blocked Anthropic API (fixed in C's second patch with a per-run writable HOME); the image lacked cheval's declared Python dependencies (added); and, host-wide and new, **Codex on the operator's ChatGPT plan refuses every gpt-5.x model**, which left the dissent with one voice — the catalog's codex hop now points at `gpt-6.1-sol` (KF-044, DEC-0485), a provider-forced model change the pre-registration and the report will name. The live smoke shows A0 and A1 completing inside the container with hidden tests passing; the full matrix is recorded in smoke.md.

## AC Verification

### AC-1.1
- Criterion: AC-1.1 `gen-checksums.sh --check` exits 0 on the committed manifest; the manifest has no entry outside `git ls-files .claude`; entry count equals the tracked count minus `overrides/` and the manifest (PRD AC-1.1)
- Status: ✓ Met
- Evidence: tools/gen-checksums.sh:12 (git ls-files source), tools/gen-checksums.sh:28 (--check); `bash tools/gen-checksums.sh --check` → "OK (1973 entries match)"; tracked .claude files 1,976 − 2 overrides − the manifest = 1,973 (implementer A report §AC-1.1 counts)

### AC-1.2
- Criterion: AC-1.2 `check-manifest-paths.sh` fails on a fixture manifest with one untracked path and on one with a `__pycache__` entry, passes on the committed one, and runs as a Shell Tests step (PRD AC-1.2)
- Status: ✓ Met
- Evidence: tools/check-manifest-paths.sh:14 (classes); tests/unit/check-manifest-paths.bats:1 (7 cases); .github/workflows/bats-tests.yml:175 (step "Integrity manifest gate"); `bash tools/check-manifest-paths.sh` → "1973 entries, 0 untracked, 0 missing"

### AC-1.3
- Criterion: AC-1.3 `fresh-mount-proof.sh` exits 0 with Aleph absent: 0 Tampered, 0 Missing-should-link, `not-mounted` counted; the proof log is in the sprint report (PRD AC-1.3)
- Status: ✓ Met
- Evidence: tools/fresh-mount-proof.sh:16 (mount-submodule entry point); .claude/scripts/check-loa.sh:51 (not-mounted class); live run from the main checkout (`bash tools/fresh-mount-proof.sh --worktree`): "Tampered=0 Missing=0 not-mounted=423 check-loa-rc=0", exit 0 (log /tmp/fresh-mount-proof-main.txt; implementer A report pastes the worktree run; the rc.5 baseline at 252501b4 was 1,835 Missing, exit 1)

### AC-1.4
- Criterion: AC-1.4 `.loa-version.json` and the `CLAUDE.loa.md` marker read `2.0.0-rc.5`; `check-prompt-budget.sh` rc 0 recorded (PRD AC-1.4)
- Status: ✓ Met
- Evidence: .loa-version.json:2 (framework_version 2.0.0-rc.5, last_sync 2026-10-14T12:33:18Z); .claude/loa/CLAUDE.loa.md:1 (marker version 2.0.0-rc.5); `bash tools/check-prompt-budget.sh` rc 0 (CLAUDE.loa.md 9,189 B of 9,445)

### AC-1.5
- Criterion: AC-1.5 `run-arms.bats`: a stub executor at USD 5 per trial under `--max-usd 12` launches two, cuts before the third, writes `cut_reason`, exits 1; `--screen` writes no suite `STATUS.json`; `spend.sh` sums fixture rows and ledger with `--since` (PRD AC-2.1, AC-2.3, AC-2.4)
- Status: ✓ Met
- Evidence: evals/harness/run-arms.sh:15 (--max-usd, --screen), evals/harness/run-arms.sh:18 (in-flight reservation); evals/tests/run-arms.bats:1 (RA-6 two trials then cut, RA-8 screen writes no suite STATUS, RA-9 reservation); evals/harness/spend.sh:24 (headroom); evals/tests/spend.bats:1 (SP-1…SP-6)

### AC-1.6
- Criterion: AC-1.6 `arm-toggles.bats`: `a0_bare` sandbox has no `.claude/` or `CLAUDE.md` and the stub receives no `--append-system-prompt-file`; `a7_effort_medium` passes `--effort medium`, no sandbox `SKILL.md` carries `effort:` and the sandbox catalog says `default_effort: medium` with its `.checksum` refreshed; `a4_no_gates` leaves both `enabled` keys false and the env var set; `a5_no_flatline` leaves `flatline_protocol.enabled: false`; `a3_one_voice` leaves `companion_voice: false` in both gate blocks; `a1_full` takes no toggles; every arm's sandbox manifest is regenerated after its toggles and `check-loa.sh` integrity is green in each; a fixture tree touching `.claude/` or `grimoires/` is refused by the materialiser; the cycle-129 toggle cases still pass (PRD AC-3.1, AC-5.6; DEC-0431, DEC-0433)
- Status: ✓ Met
- Evidence: evals/harness/lib/sandbox-mount.sh:33 (loa_mount), :37 (default_effort + .checksum), :42 (LOA_ADVERSARIAL_REVIEW_ENFORCE), :376 (regen_sandbox_manifest), :423 (check_fixture_path_rule); evals/tests/arm-toggles.bats:1 (AT-13…AT-24 incl. A3 companion_voice false in both gates and AT-20 integrity in every arm; AT-1…AT-12 unchanged); evals/tests/execute-agent.bats 12/12

### AC-1.7
- Criterion: AC-1.7 `pipeline-run.bats` (stub CLI): A1 six phases in order with one `pipeline.json` record each and sandbox snapshots after IMPLEMENT and each FIX; A2 no PLAN; A4 ends after IMPLEMENT; A3's REVIEW and AUDIT envelopes carry `companion_voice.planned: false`; A6 one session id across PLAN, IMPLEMENT and FIX with `--resume` on the continuations and distinct ids on REVIEW and AUDIT; A0 one phase, no `.claude/`, `--max-turns 170` and the summed timeout; the cap abort after the phase that passes USD 12 writes `status: cap_failure` and `cap_phase`; a phase killed by SIGTERM yields `status: interrupted` and no grade; no hidden path in the sandbox; `--setting-sources project` on every argv and the captured environment equal to the allowlist (no `AWS_ACCESS_KEY_ID`, `GH_TOKEN`, `GITHUB_TOKEN`, `OPENAI_API_KEY`, Google key) (PRD AC-2.2, AC-4.1, AC-4.2, AC-4.3, AC-4.5)
- Status: ✓ Met
- Evidence: evals/harness/pipeline-run.sh:19 (--resume continuations), :50 (snapshots), :61 (--setting-sources project), :67 (environment allowlist incl. the Bedrock route variables, token value never recorded), :94 (cap_failure), :102 (interrupted), :624 (os.closerange exec shim); evals/tests/pipeline-run.bats:1 (52 cases: A1 six phases, FIX on the trailer, A2 no PLAN, A4 ends after IMPLEMENT, A3 envelopes planned false, A6 one implementer session with --resume and separate gates, A0 170 turns / 70 min, cap abort, interrupted, no hidden path, argv, env equals the allowlist)

### AC-1.8
- Criterion: AC-1.8 `ablation-row.sh --validate` rejects a row missing any §3.1 field (incl. `suite_version`, `snapshots`, per-gate `verdict_accuracy_*`, the seven `status` values); rows carry per-phase `effort_effective` from the sandbox MODELINV and `voices_run` from the envelopes; a phase whose model or effort differs sets `degraded` with the reason; `took-effect.sh` evaluates every evidence rule in the suite file incl. `implementer_single_session`, `gates_separate_sessions` and the A1 integrity check (PRD AC-6.3, AC-3.3)
- Status: ✓ Met
- Evidence: evals/harness/ablation-row.sh:40 (--validate), :29 (degraded_reason derivation); evals/tests/ablation-row.bats:1 (18 cases: each field removed fails, seven statuses, four degraded causes, arm never from sandbox/); evals/harness/took-effect.sh:26 (implementer_single_session, gates_separate_sessions), :34 (integrity_clean); evals/tests/took-effect.bats:1 (21 cases); live: `took-effect.sh --run-dir <A1 smoke>` → "arm a1_full: OK" and `ablation-row.sh --allow-ungraded` → a validating row with degraded=true "review envelope 1 of 4 voices completed; audit envelope 1 of 4 voices completed"

### AC-1.9
- Criterion: AC-1.9 The smoke ran every runnable arm on the two existing fixtures; `took-effect.sh` prints OK for each; A1's `pipeline.json` carries `effort_effective` per phase and the envelopes' voices under REVIEW and AUDIT; costs per arm recorded in `smoke.md` (PRD AC-4.4, AC-3.3)
- Status: ✓ Met
- Evidence: grimoires/loa/a2a/sprint-258/smoke.md:1 (every applicable arm ran one trial on smoke-build-01 and smoke-review-01 inside the container; `took-effect.sh` OK for every arm; per-run costs and the 20-row table; degraded rows listed with causes); executor mode container (DEC-0481); gate-model contingency does not fire (26 Fable gate phases, 0 refusal fallbacks); A1 cost per build task USD 4.88 and 6.28 (cap-fit OK); evals/results/ablation-2.0/smoke-258/rows.jsonl:1 (20 validated rows)

### AC-1.10
- Criterion: AC-1.10 The suite file declares `task_types` per arm and `absent: true` for A8 with the grep evidence; the report refuses an arm on a type outside its declaration (PRD AC-3.2)
- Status: ✓ Met
- Evidence: evals/suites/ablation-2.0.yaml:12 (task_types per arm), :72 (a8_no_ceremonies absent: true with the grep evidence), :87 (predicates); live: `pipeline-run.sh --arm a2_no_sprint_plan` on smoke-review-01 → "refused: arm does not apply to task type review-catch (task_types [build])"; evals/tests/pipeline-run.bats (refusal record case)

### AC-1.11
- Criterion: AC-1.11 Every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree; `floor-snapshot.bats` green; toolchain readiness recorded
- Status: ✓ Met
- Evidence: eval suites 256/256 (`bats evals/tests/`, 198 s); unit: gen-checksums, check-manifest-paths, check-loa-mount-scope, floor-snapshot, profile-floor, aleph-opt-in, known-failures-seed 46/46; check-loa callers 74/74 (implementer A set); fence corpus, catalog pytest subset, catalog and hook-wiring bats, sync-fixtures and lints as listed in Testing Summary; toolchain recorded in grimoires/loa/a2a/sprint-258/toolchain.md:1

### AC-1.12
- Criterion: AC-1.12 `pipeline-run.bats` with a stub `docker`: the launcher mounts the sandbox read-write and the three per-run credential copies read-only and nothing else, passes `--read-only --network bridge --pids-limit --memory --cpus`, records the image id; the launcher sets `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1`, an empty `GH_CONFIG_DIR`, no `SSH_AUTH_SOCK`/`BASH_ENV`, and no descriptor above 2 (DEC-0411, DEC-0412); the smoke records whether a phase authenticated and completed inside the container and the executor mode chosen for the cycle
- Status: ✓ Met
- Evidence: evals/harness/pipeline-run.sh:75 (docker run with exactly two mounts: sandbox rw and the per-run HOME rw), :77 (meta/home), :67 (git/gh hygiene, no SSH_AUTH_SOCK/BASH_ENV), :624 (descriptors above 2 closed); evals/tests/pipeline-run.bats (mount set, flags, image id, HOME deleted at exit and on interrupt, Bedrock token present by name only, descriptor case); live: the A1 smoke authenticated and completed every phase inside the container; executor mode for the cycle = container (DEC-0411, DEC-0481)

### AC-1.13
- Criterion: AC-1.13 `validate-suite.bats` and `freeze.bats`: schema, four-by-four counts (relaxed for the two smoke tasks by `--allow-partial`), allowlist, destinations, leakage strings and the fixture path rule; `freeze.sh --check` fails on one changed byte (DEC-0424)
- Status: ✓ Met
- Evidence: evals/harness/validate-suite.sh:23 (leakage incl. hidden stems), evals/harness/freeze.sh:12 (--check); evals/tests/validate-suite.bats:1 (VS-1…VS-10 incl. leaked word, disallowed token, .. dest, fixture under .claude/, counts without --allow-partial); evals/tests/freeze.bats:1 (FZ-2 one changed byte → exit 1); `validate-suite.sh --smoke --allow-partial` → OK 2 tasks; `freeze.sh --smoke --allow-partial --check` → OK (10 files, sha256 e0461665…)

### AC-1.14
- Criterion: AC-1.14 `pipeline-run.bats`: arm-aware files only under `meta/`; `gen-checksums.sh` regenerates the sandbox manifest after toggles for every arm; the per-turn watchdog kills a stub phase whose priced usage would pass the run cap and records `cap_failure` with the turn count (DEC-0413, DEC-0421, DEC-0422)
- Status: ✓ Met
- Evidence: evals/harness/pipeline-run.sh:77 (arm-aware files under meta/ only); evals/harness/lib/sandbox-mount.sh:376 (manifest regenerated after toggles for every arm; took-effect integrity_clean verified 3,390 entries on the A1 smoke); evals/harness/pipeline-run.sh:94 (watchdog cap_failure with cap_turn; bats case "watchdog kill with cap_turn 3")

## Tasks Completed

- Task 1.0 (lead): toolchain readiness — toolchain.md.
- Task 1.1 (A): `tools/gen-checksums.sh`, `tools/check-manifest-paths.sh`, regenerated `.claude/checksums.json`, Shell Tests step, `preflight.sh` count rule, two bats files.
- Task 1.2 (A): `check-loa.sh` not-mounted scoping (and `return 0` so later checks run), `tools/fresh-mount-proof.sh` (`--ref`, `--worktree`, `--keep`), `check-loa-mount-scope.bats`; live proof pasted in reviewer-a.md and re-run by the lead.
- Task 1.3 (A): `.loa-version.json` and the `CLAUDE.loa.md` marker at 2.0.0-rc.5.
- Task 1.4 (B): `run-arms.sh --max-usd`, `--run-cap`, `--screen`, `--screen-tasks`; STATUS `cut`, `cut_reason`, `spend`, `screen`; RA-6…RA-10.
- Task 1.5 (B): `spend.sh` with `spend.bats`.
- Task 1.6 (B): `evals/suites/ablation-2.0.yaml`; `execute-agent.sh` toggles `loa_mount`, `effort`, `gates`, `flatline`; `lib/sandbox-mount.sh` (seven functions, contract in reviewer-b.md); AT-13…AT-24.
- Task 1.7 + 1.12 (C): `pipeline-run.sh`, six phase prompts, `fingerprint.sh`, `Dockerfile.ablation`, container launcher with a per-run HOME, watchdog, `meta/` boundary; `pipeline-run.bats` 52 cases with stub `claude`, `docker` and mount library.
- Task 1.8 (C): `ablation-row.sh`, `took-effect.sh`, 18 + 21 bats cases, fixture run directories under `evals/tests/fixtures/ablation-runs/` (`regen.sh` rebuilds them).
- Task 1.9 (lead): smoke matrix — smoke.md.
- Task 1.10 (lead): CHANGELOG Sprint 1 entries, REPO-MAP, `checksums.json` via `gen-checksums.sh`, lints; the Shell Tests step that runs `evals/tests/` (DEC-0483).
- Task 1.11 (B): task schema, `freeze.sh`, `validate-suite.sh`, two smoke tasks (`smoke-review-01` with the arm-neutral output contract; `smoke-build-01` with the hidden test and a red/green reference patch).
- Lead integration fixes outside the task list: image dependencies (DEC-0482); codex catalog repoint (DEC-0485, KF-044); beads opt-out in every sandbox (DEC-0486); host codex 0.162.1 (DEC-0487); eval bats in CI (DEC-0483).

## Technical Highlights

- One executor for every task type; review-catch tasks run the gates on the PR under `pr/`; every phase is a fresh `claude -p --setting-sources project` session inside `loa-ablation:258`; A6 continues one implementer session with `--resume`.
- The environment allowlist carries the Bedrock bearer-token route by name only; captures record `<set>`; a `python3 -I` exec shim closes descriptors above 2 and replaces `env -i` so no secret touches argv.
- Hidden material is never in a sandbox; arm-aware files live only under `meta/`; the grader (Sprint 259) reads `sandbox/`, `snapshots/`, `transcripts/`, `eval/` and the checkout's hidden directory.
- The manifest is regenerated inside every sandbox after the toggles, so `check-loa.sh` reads clean in every arm (A1 smoke: 3,390 entries verified).

## Testing Summary

| Check | Result |
|---|---|
| `bats evals/tests/` (CI directory form) | 256 ok, 0 failed, 198 s |
| `tests/unit/{gen-checksums,check-manifest-paths,check-loa-mount-scope,floor-snapshot,profile-floor,aleph-opt-in,known-failures-seed}.bats` | 46 ok |
| check-loa callers (A's set incl. integration suite) | 74 ok |
| `tools/gen-checksums.sh --check`, `tools/check-manifest-paths.sh` | OK, 1,973 entries |
| `tools/fresh-mount-proof.sh --worktree` | exit 0; Tampered 0, Missing 0, not-mounted 423 |
| eval.yml trust-boundary scan (local reproduction) | 0 violations |
| `tools/check-no-raw-sha256sum.sh`, `check-no-swallowed-jq.sh`, `check-no-raw-curl.sh`, `check-glossary-terms.sh`, `check-prompt-budget.sh` | rc 0 (see the lead's verification log in NOTES) |
| `tools/regen-model-artifacts.sh` after the codex repoint | regenerated and drift-free |
| fence corpus, catalog pytest subset, catalog and hook-wiring bats, `sync-fixtures.sh --check` | recorded in NOTES at the sprint close |
| image `loa-ablation:258` | claude 2.1.299, codex 0.162.1, node 20.11, Python 3.11 + pytest 9.0.2 + cheval deps, bats 1.13; no br |
| live smoke | smoke.md |

## Known Limitations

- The dissent's OpenAI voice runs on `gpt-6.1-sol` (Codex default) because the ChatGPT plan no longer serves gpt-5.x; the HTTP API still lists gpt-5.5 and gpt-5.5-pro but is not used in the sandbox (secret and price). cheval misclassifies the refusal as AUTH_REVOKED (KF-044; a later fix).
- No `br` inside the sandbox: the implementing skill takes its documented NOT_INSTALLED path (opt-out marker) in every arm.
- The smoke materialised the lead's dirty working tree (3,459 `.claude` files, 80 MB); batches pin a pristine worktree.
- Host codex is now 0.162.1; the image pins the same; the host Claude CLI is 2.1.300 while the image pins 2.1.299 — the container's versions are the batch's (fingerprint).
- The watchdog sees a turn when its event arrives; one turn can overshoot the cap. Docker on this kernel discards `--memory`.

## Verification Steps

1. `bash tools/gen-checksums.sh --check && bash tools/check-manifest-paths.sh`
2. `bash tools/fresh-mount-proof.sh --worktree`
3. `bash -c '~/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats --print-output-on-failure evals/tests/'`
4. `docker build -t loa-ablation:258 - < evals/harness/Dockerfile.ablation` then `pipeline-run.sh --dry-run` on a smoke task and arm; `took-effect.sh --run-dir <run>`; `ablation-row.sh --run-dir <run> --task-yaml … --allow-ungraded --out /dev/stdout | ablation-row.sh --validate /dev/stdin --allow-ungraded`
5. `bash tools/regen-model-artifacts.sh --check`

## Lead decisions
Recorded as `proposed` DEC rows at integration (sources name this section):
- L1 DEC-0480 Bedrock bearer-token route variables pass through the phase environment (amends DEC-0394).
- L2 DEC-0481 one per-run writable HOME, no subscription credentials, two mounts (amends DEC-0411).
- L3 DEC-0482 the image installs cheval's declared dependencies.
- L4 DEC-0483 the Shell Tests job runs `evals/tests/`.
- L5 DEC-0484 host constraint: the Anthropic API is geo-blocked from this egress; every Claude call stays on Bedrock.
- L6 DEC-0485 the codex-headless hop points at `gpt-6.1-sol` (KF-044).
- L7 DEC-0486 no `br` in the image; beads opt-out in every arm.
- L8 DEC-0487 host codex 0.137.0 → 0.162.1; the image pins the same.
- L9 DEC-0488 smoke materialised the dirty tree; batches pin a pristine worktree.
- L10 DEC-0489 placeholder `gpt-6.1-sol` catalog entry with a chain to codex-headless (bead bd-i1sop for the rate card).
- L11 DEC-0490 gate turn budgets 60/30 min; a gate at the cap with its trailer counts as completed (`turn_cap_hit`); the sandbox project is pre-trusted.
- L12 DEC-0491 the grader runs hidden tests inside the image.
Follow-up beads: bd-i1sop (rate card), bd-9v732 (c124-1.3-5 Bedrock-env sensitivity).

## Feedback Addressed

(review and audit rounds append here)

## Feedback Addressed — review round 1 (fix commit `0c200dd6`)

Round 1 (`engineer-feedback-r1.md`, dissent `adversarial-review-r1.json`) returned CHANGES_REQUIRED with two medium and five low findings. One Opus 5.5 implementer fixed all seven in `../loa-wt-s1-fix` (report `reviewer-fix.md`); the lead applied the patch, corrected `CHANGELOG.md:17` and `grimoires/loa/sdd.md:112,139` (codex 0.162.1) and recorded DEC-0492 … DEC-0495.

| Finding | Fix | Test (fails on 05442536, passes now) |
|---|---|---|
| MEDIUM-1 dead `brbuild` stage | `Dockerfile.ablation` lines 19-20 deleted; one `FROM` | `pipeline-run.bats` "Dockerfile.ablation: a single build stage, no cargo install" |
| MEDIUM-2 `--argjson` of run-scaled inputs | `ablation-row.sh` writes pipeline, task, grade, manifest, MODELINV, envelopes and the write list under a `mktemp -d` and binds them with `--slurpfile`; scalars stay `--arg` | `ablation-row.bats` "a MODELINV ledger over 200 KB reaches jq as a file" (old code: `Argument list too long`, exit 126) |
| LOW-1 jq aborts outside the contract | `ms()` try/catch, `obj`/`boolish` guards, `voices()` object guards, writer defaults for `name`/`model_requested`/`models_used`, boolean-or-null `verdict_accuracy*`, `ROW=… \|\| usage "row build failed for <run_id>"` | three `ablation-row.bats` cases (empty `finished` + boolean `companion_voice`; offset timestamp + array `models_used` + string `verdict_accuracy`; row program abort → exit 2) |
| LOW-2 `spend.sh` silent skips, first-seen dedup | ` INCOMPLETE (N skipped)` + exit 1; `--json` `complete`; max `cost_usd` per `run_id`; no-`run_id` rows counted once with one warning per file | `spend.bats` SP-4 (changed), SP-7, SP-8, SP-9 |
| LOW-3 screen batches excluded by path | `aggregate_status` filters `map(select(.screen != true))`; `--batch screen-*` without `--screen` is exit 2 | `run-arms.bats` RA-11, RA-12 |
| LOW-4 `freeze.sh` skips symlinks | `find … \( -type f -o -type l \)`; a symlink or newline path is refused (exit 1) before hashing, on write and `--check` | `freeze.bats` FZ-7, FZ-8 |
| LOW-5 codex 0.137.0 drift | `pipeline-run.sh:85`, `CHANGELOG.md:17`, `sdd.md:112,139` → 0.162.1 | `pipeline-run.bats` "header names the codex version Dockerfile.ablation pins" |

`evals/tests/` 269/269 (13 new), `tests/unit/{gen-checksums,check-manifest-paths,check-loa-mount-scope}.bats` 20/20, trust-boundary scan clean, `check-manifest-paths.sh` / `gen-checksums.sh --check` unchanged (no `.claude/` edit). No image rebuild is needed: BuildKit had already skipped the deleted stage, so `loa-ablation:258` is byte-identical in content.

## Feedback Addressed — audit round 1 (fix commit `ffe162ef`)

Round 1 (`auditor-sprint-feedback-r1.md`, dissent `adversarial-audit.json`) returned CHANGES_REQUIRED with two medium and six low findings. One Opus 5.5 implementer fixed all eight in `../loa-wt-s1-afix` (report `reviewer-afix.md`, with the addendum that narrowed `bash_mount_refs` to write-shaped commands after the lead saw it list every read of the mount on the real smoke runs); the lead applied both patches, rebuilt `loa-ablation:258` from the pinned Dockerfile (id `4e37cb5f…`, build exit 0), regenerated the 20 smoke rows under the new writer (all validate), amended SDD §5.5/5.6/5.8/5.11/5.13 and the CHANGELOG, and recorded DEC-0496/DEC-0497.

| Finding | Fix | Test (fails on 0c200dd6, passes now) |
|---|---|---|
| MEDIUM-A1 envelope read from the sandbox | `pipeline-run.sh` copies each gate's envelope to `eval/` once at gate end (`envelope_copied`, `envelope_sha256`; symlink never copied; the every-phase copy loop is gone); `ablation-row.sh`/`took-effect.sh` read `eval/` first; `zone_violations.envelope_mismatch` | `pipeline-run.bats` ×2 (FIX/AUDIT rewrite leaves eval/ unchanged; symlink refused), `ablation-row.bats` (tampered sandbox → eval/ values + mismatch), `took-effect.bats` (eval/-first) |
| MEDIUM-A2 failed trial costs the ceiling 0 | `run-arms.sh collect()` charges `RUN_CAP` for a non-completed row with no cost and for a no-row trial; `spend.assumed_cap_trials` | `run-arms.bats` RA-13 (cut at trial 5 instead of 8), RA-14 |
| LOW-A1 effort whitelist | `execute-agent.sh` re-validates `arm_effort` (exit 2) | `execute-agent.bats` EA-14 |
| LOW-A2 Bash self-modification invisible | `mount_integrity` (CLAUDE.md, .loa.config.yaml sha at mount and finish) + `bash_mount_refs` (write-shaped commands only) + `mount_changed` | `pipeline-run.bats` (ok/changed/absent/null), `ablation-row.bats` ×2 |
| LOW-A3 inherited ENFORCE in baseline | unset in every mode; `executor.json.adversarial_review_enforce` | `execute-agent.bats` EA-13, `arm-toggles.bats` AT-17 |
| LOW-A4 dotfiles bats fallback | removed; `bats=absent` | `pipeline-run.bats` fingerprint case |
| LOW-A5 arm grammar | writer exit 2 + `--validate` | `ablation-row.bats` |
| LOW-A6 pip ranges / bats tag | exact pins; `ARG BATS_COMMIT` + rev-parse check; image rebuilt | `pipeline-run.bats` Dockerfile case |

`evals/tests/` 284/284 (15 new), unit 20/20, trust-boundary scan clean, `evals/results/ablation-2.0/smoke-258/rows.jsonl` 20/20 valid under the new `--validate`.
