# Implementation Report — Sprint 3: Run preflight and resume (cycle-125, global sprint 243)

**Cycle:** cycle-125 friction-floor · **PRD:** `grimoires/loa/prd.md` FR-3 · **SDD:** `grimoires/loa/sdd.md` §1.4 D-3.1–D-3.3 · **Plan:** `grimoires/loa/sprint.md` Sprint 3
**Implementer:** Fable 5.1 lead (`/run sprint-plan`, run-20260923-282c32ce, unattended) · **Date:** 2026-09-23 · **Epic:** bd-2yh1 (tasks bd-rq4e, bd-9d4j, bd-wcu6, bd-73wx, bd-enx0, bd-4slp)

## Summary

Usage mining (F3) showed unattended runs that started and could not finish — prompts auto-denied under the wrong permission mode, no usable review voice, a tripped breaker, a stale `RUNNING` state nobody was told how to resume. This sprint puts one checklist at the entry of every run path (`run-preflight.sh`, eight predicates, `--unattended` strictness, `--resume` inversion, `--json`), mirrors task progress into `sprint-plan-state.json` as a locked, atomic, beads-validated checkpoint, and tells the next session exactly how to resume: a SessionStart line, the same line in `/loa`, and `/run-resume` outranking the phase suggestion in `workflow-state.sh`. Re-entry was proven against the real `br` rather than assumed. No new config key; inputs are settings files, environment and existing state.

Assumptions (Karpathy rule 1): a fresh `RUNNING` (< 12 h) is a live run, so the preflight refuses to start a second one and the surface stays silent (the session-title hook already names it); credential *presence* is the only thing the preflight may know — it reads `.env.local` / `.env` for a non-empty `KEY=` line and never the value; the model→provider map comes from the catalog's `aliases` block with a name heuristic as fallback, because the flatline chains name aliases, not `provider:model` pairs; the composed helpers (`check-permissions.sh`, `beads-health.sh`, `run-mode-ice.sh`) read the real repository, so fixtures drive them through a bats-gated helpers directory (the same gate class as every other test seam in this repository); yq exists in two flavours on operator machines (KF-027), so the script detects which one it has.

## Changes

| File | Change |
|---|---|
| `.claude/scripts/run-preflight.sh` (new, ~300 lines) | CLI + usage (`:1-58`); bats-gated helper resolution (`:61-68`); yq flavour detection and `cfg` (`:71-82`); P2 (`:99-107`), P1 with settings precedence and the P2-conditional rule (`:109-128`); P3 `cred_present` (presence only, env → `.env.local` → `.env`), `cli_for`, `provider_of` (catalog alias → heuristic), per-stage usable/missing, `STAGE_ONLY` for P4 (`:130-191`); P4 breaker buckets from filenames, OPEN age, only-usable-provider rule (`:193-206`); P5 via `notes-guard.sh check` (`:208-218`); P6 three state files, 12 h staleness, `--resume` inversion, unparseable = FAIL (`:220-249`); P7 capture-then-parse (`:251-262`); P8 (`:263-271`); checklist / JSON output, exit 0/1 (`:273-295`) |
| `.claude/scripts/run-checkpoint.sh` (new) | `write` (`:43-61`): jq → `F.tmp.$$` → `mv -f` under `flock -w 5` on `F.lock`, sets `schema_version 2`, `checkpoint {sprint, task, phase, ts}`, `last_activity`; refuses a missing run (2) and never replaces a file with unparseable output (3). `read` (`:63-95`): schema 1 / no checkpoint → "sprint granularity"; a task-bearing checkpoint is trusted only when `br show <task> --json` reports `closed`, else discarded with a logged line; `--json` |
| `.claude/hooks/session-start/loa-run-state-surface.sh` (new) | one `Run: <label> <STATE> (<age>) → <command>` line per resumable state (`surface()` `:46-61`: HALTED/INTERRUPTED; RUNNING idle ≥ 12 h with the beads-truth note; simstim → `/simstim --resume`), plus the session-limit-reset line when `reset_at_epoch ≤ now` (`:66-73`); control bytes stripped; exit 0 always; `--root`, `--line` |
| `.claude/settings.json`, `.claude/hooks/settings.hooks.json` | SessionStart entry `hook-guard.sh … loa-run-state-surface.sh`, `once: true` (5-line diff each, template parity kept) |
| `.claude/scripts/workflow-state.sh:195-210` | `get_suggested_command` returns the surface line's command (`/run-resume`, `/simstim --resume`) ahead of the phase suggestion |
| `.claude/scripts/loa-status.sh:671,717-726` | `display_run_line` after the Artefacts line; nothing for a clean tree or a live run |
| `.claude/skills/run-mode/SKILL.md:69-77` | pre-flight steps 2–5 collapsed onto `run-preflight.sh --unattended` + the beads-health record call; main loop steps 3/6 carry `checkpoint(phase: …)` and the footnote defines it (`:106,112,121-124`); **15,761 → 15,372 B (net −389 B)** |
| `.claude/skills/run-mode/resources/sprint-plan-mode.md:14-18,29-40` | Pre-flight references the script; sprint-advance checkpoint write; schema note; checkpoint discipline paragraph |
| `.claude/skills/run-mode/resources/halt-resume.md:47-48,63-66` | `run-resume` pre-flight step 0 (`--resume`); resume execution reports `run-checkpoint.sh read` and resumes at the first open bead |
| `.claude/skills/run-mode/resources/state-schemas.md:75-101` | `schema_version: 2` + `checkpoint` in the sprint-plan schema, readers accept 1 and 2 |
| `.claude/skills/run-bridge/SKILL.md:93-94` | Phase 2 runs the preflight first |
| `.claude/skills/implementing-tasks/SKILL.md:213` (+ trim `:168`) | per-task checkpoint write after `br close` in run mode; 16,372 B after a compensating trim (12 B headroom — noted) |
| `.claude/loa/reference/hooks-reference.md` | SessionStart row for the new hook |
| `CHANGELOG.md` `[Unreleased]` | one entry |
| `tests/unit/run-preflight.bats` (new, 14) | PF-0 healthy fixture; PF-J JSON shape; PF-1/1b P1 incl. precedence and the P2-conditional rule; PF-2; PF-3 voices (fail / CLI hop / env key / `.env.local` key; no value printed); PF-4 breakers (only-usable FAIL, other WARN with age, CLOSED silent, ICE breaker ignored); PF-5; PF-6/6b state (fresh / stale / HALTED / JACKED_OUT / `--resume` / three files / unparseable); PF-7 beads incl. exit-4 DEGRADED contract and both overrides; PF-8; PF-M no short-circuit + usage; PF-S seam gated |
| `tests/unit/run-checkpoint.bats` (new, 6) | write fields + no residue; read trusted/discarded/unknown with stub `br`; phase-only + schema 1; refusal paths; 12 concurrent writers under the lock; usage |
| `tests/unit/run-state-surface.bats` (new, 7) | silent cases; HALTED line; stale RUNNING + INTERRUPTED + state.json; simstim; session-limit past/future; malformed/control bytes; wiring in both settings files behind hook-guard, once |
| `tests/integration/implement-reentry.bats` (new, 2) | real `br init` in a temp workspace: after one close, `br ready` lists only the open beads; the checkpoint helper trusts the closed task and discards an open one |
| `grimoires/loa/REPO-MAP.md` (+checksum), `.claude/checksums.json` | regenerated (validate consistent; 3261 tracked, 0 drift) |

## Test-first record

- Task 3.1 wrote `run-preflight.bats` before the script existed (14 red by construction: script missing → every case fails).
- First green run: 11/14 → three failures traced to the fixture, not the predicates: the minimal PATH still reached the operator's `~/.local/bin` (where both Mike Farah `yq` and `claude` live), so P3 saw a CLI hop; and a `VAR=x fn` prefix does not export into `run`'s child (switched to `export`). While fixing PATH the script gained yq-flavour detection: `/usr/bin/yq` on this host is the Python jq-wrapper (`yq 3.4.3`) and silently returned nothing for `yq eval`, which made every stage look "not enabled" and P3 pass vacuously — a real robustness hole, now covered by the flavour probe.
- Live smoke on this repository (unattended): P1 PASS (home settings), P2 PASS, P3 PASS (four usable voices), P4 WARN (anthropic/headless OPEN 1h, google/http_api OPEN 1902h), P5 PASS, **P6 FAIL** "run already in progress" (correct — this run is RUNNING), P7 came out `DEGRADED\nUNKNOWN` → FAIL: `beads-health.sh` exits 4 for DEGRADED by design and the `cmd | jq || echo` shape under `pipefail` appended the fallback. Fixed to capture-then-parse; the stub now mirrors the real exit codes (0/4/2) so PF-7 pins it. `--resume`: P6 PASS. Surface line: nothing (fresh RUNNING). `run-checkpoint.sh read` on the live state: "schema_version 1 → sprint granularity".
- Final: `run-preflight` 14/14, `run-checkpoint` 6/6, `run-state-surface` 7/7, `implement-reentry` 2/2 (real `br`), plus `hook-wiring`, `loa-status-artefacts`, `agent-ergonomics-workflow-state`, `agent-ergonomics-loa-status`, `loa-status-stale-worktree`, `prompt-audit-keeplist`, `skill-capabilities`, `prompt-audit-generated-blocks`, `skill-includes`, `notes-guard` → 131/131 in one run (the preflight suite re-run at 14/14 after the P7 capture fix). Two self-review hardenings landed before hand-off: model ids are shape-checked before they reach a yq expression (`provider_of`), and `.env` presence strips one layer of quotes so `KEY=""` does not count while `KEY="sk-…"` does. `tools/check-prompt-budget.sh`: run-mode 15,372 B, run-bridge 14,237 B, implementing-tasks 16,372 B, no FAIL. `lint-invariants.sh`: 0 error (the system-zone WARN is the uncommitted tree). `generate-skill-includes.sh --check`: current.

## AC Verification (sprint.md)

### `run-preflight.bats`: one passing and one failing fixture per predicate; checklist names predicate and fix; `--json` shape (prd.md FR-3 AC 1)
- **Status**: ✓ Met
- **Evidence**: PF-1…PF-8 each assert a `[PASS] Pn` and a `[FAIL] Pn … → fix:` line (`run-preflight.sh:109-128,99-107,130-191,193-206,208-218,220-249,251-262,263-271`); PF-J asserts `mode/ok/pass/warn/fail/checks[{id,name,status,detail,fix}]/ts` and the P1…P8 order (`:273-295`).

### Checkpoint written after each task and phase; resume restarts at the recorded task in the integration fixture (prd.md FR-3 AC 2)
- **Status**: ✓ Met
- **Evidence**: write points — per task in `implementing-tasks/SKILL.md:213`, per phase in `run-mode/SKILL.md:106,112` and per sprint advance in `sprint-plan-mode.md:29-31`; mechanics in `run-checkpoint.sh:43-61` (CK-1, CK-5); the integration fixture `implement-reentry.bats` RE-2 writes a checkpoint for the closed task, `read` returns it, then a checkpoint for an open task is discarded and `br ready` names that open task as the restart point (beads truth, SDD D-3.2).

### `loa-status.sh` prints the resume line for a stale state and nothing for a clean one; `hook-wiring.bats` covers the new SessionStart line (prd.md FR-3 AC 3)
- **Status**: ✓ Met
- **Evidence**: `loa-status.sh:717-726` prints the surface's lines; RSS-1 (nothing) / RSS-2/3 (line) pin the producer; RSS-7 asserts both settings files carry the hook behind `hook-guard.sh` with `once: true`; `hook-wiring.bats` W10 (template ↔ live SessionStart parity) is green with the new entry.

### No new config key; inputs are settings files, env and existing state (prd.md FR-3 AC 4)
- **Status**: ✓ Met
- **Evidence**: `run-preflight.sh` reads `.claude/settings*.json`, `~/.claude/settings.json`, `.loa.config.yaml` (existing keys only), `.env.local`/`.env` presence, `.run/*.json`, `grimoires/loa/NOTES.md`; `grep -n "yq eval\|cfg " run-preflight.sh` shows only `run_mode`, `flatline_protocol.*`, `beads.autonomous.requires_beads`; `.loa.config.yaml.example` untouched.

## Deviations from the plan, stated

- P4 reads the breaker files with `jq` instead of importing `loa_cheval.routing.circuit_breaker.list_buckets` (SDD D-3.1 table): same file schema, no Python start-up in a pre-flight that runs on every `/run`, and the symlink/lock exclusions are reproduced (`:195-197`). The Sprint 4 `--list` work will expose the Python listing for operators.
- The task-close write point lives in `implementing-tasks/SKILL.md` (one clause) rather than only in the run-mode resources, because `/implement` is the process that closes beads; run-mode's resources carry the phase and sprint-advance points.

## Out of scope, noted

- `run-preflight.sh` is invoked by the skills' prose (run-mode, run-sprint-plan, run-bridge, run-resume); the `/run` command files are thin routers and were not changed.
- `session-limit-capture.sh` output is consumed read-only by the surface; the one-shot `post-session-limit-reminder.sh` behaviour is unchanged.
