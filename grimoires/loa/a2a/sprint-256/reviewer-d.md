# Implementation Report: Sprint 256 (cycle-129 Sprint 2), implementer D

**Date:** 2026-10-14
**Engineer:** Sprint Task Implementer Agent, implementer D (model id `global.anthropic.claude-opus-5-5`, Opus 5.5)
**Sprint Reference:** grimoires/loa/sprint.md, Sprint 2, Tasks 2.10, 2.5, 2.1 (in that order)
**Worktree:** `/home/merlin/Documents/thj/code/loa-wt-s2a` (branch `wt/cycle-129-s2a` at `b6802e4f`), not committed
**Patch:** `~/.cache/loa/cycle-129/patches/s2-d.patch`

---

## Executive Summary

The run position now comes from files. `run-checkpoint.sh derive` rebuilds `.run/sprint-plan-state.json` and `.run/circuit-breaker.json` from the COMPLETED markers, the LOA-VERDICT trailers, the ledger and git, following the D-5.1a decision table with its terminal and sticky rules. Every `write` checkpoint refreshes the cache, and `run_mode.file_authoritative: false` turns the write path into a report.

The breaker is a script. `run-checkpoint.sh record-round` computes the same-issue hash exactly as the SKILL prose did, updates the counters atomically, and on a trip writes `OPEN` and `HALTED`, prints `TRIPPED: <trigger>: <reason>` and exits 10. `derive` raises the counters from the ordered feedback history, so a forgotten call cannot leave the breaker at zero.

The implement gate has three modes. `ask` stays the default and now logs one row per ask. `telemetry` and `deny` are opt-ins. Three sanction paths each log their own row: a fresh derived RUNNING cache, a fresh implementing-skill marker, and the operator override. Under `deny` an unknown position falls back to `ask`. Trust-input writes ask in every mode. This repository's live `.loa.config.yaml` was not touched and stays on `ask`.

**Key Accomplishments:**
- `derive [--json] [--write] [--root DIR]`, `record-round`, and `mark`/`unmark` verbs in `.claude/scripts/run-checkpoint.sh`; `write` and `read` keep their behaviour
- `implement_gate.mode` ask | telemetry | deny, the `claims: authoritative` modifier, sanction rows, `replay: true` under `LOA_AUDIT_REPLAY=1`, and `--effective-mode` for `/loa`
- `/loa` prints a drift-only Run line and the Gate line; run-resume derives on drift; the jack-out step writes `.state`; the run-mode SKILL breaker prose is replaced by the call
- 3 suites: `run-checkpoint-derive.bats` (22), `run-checkpoint-record-round.bats` (8), and `implement-gate.bats` extended to 33 cases (a 288-cell matrix)

---

## AC Verification

### AC-2.1
"`implement-gate.bats` covers the matrix mode × claims × write class × sanction state: `deny` returns a deny decision only for an unsanctioned App-Zone write; derived RUNNING, a fresh marker and the override sanction with a logged row each; a stale marker does not; `telemetry` writes one row and prints nothing; `ask` unchanged; trust-input writes ask in every cell (PRD AC-4.1)"
- Status: ✓ Met
- Evidence: `.claude/hooks/compliance/implement-gate.sh:582-596` (sanction order run, marker, override; `stale_marker` row at :593), `:616-648` (decision per mode: allow row :618, telemetry :625, deny :631, unknown_position :637, ask :645), `:340` (trust inputs, now including `.run/implement-active.json`), `:600-612` (claims modifier: tighten-only, deny still applies)
- Test: `tests/unit/implement-gate.bats:573` `run_mode_matrix` over mode {unset, ask, telemetry, deny} × claims {plain, authoritative} × write {app, trust} × sanction {none, run_fresh, run_stale, marker_fresh, marker_stale, override} × cache {fresh, stale, missing, unparseable}; IG-24…IG-27 at :614-626. Each cell checks the decision, the single decision row (`action/decision`), the stale_marker row, `replay: true` on every row, and that telemetry prints nothing on stdout or stderr. The expectations live in `expect_cell` (:551). A mutation of the telemetry row value made IG-26 fail, so the matrix is live.
- Notes: the existing IG-12 now expects one `sanctioned_run` row where it expected no audit file (`tests/unit/implement-gate.bats:162-166`), because every sanction now logs.

### AC-2.6
"`record-round` increments `cycle_count.current`, sets `same_issue.last_hash`, appends `history` on a trip and writes `OPEN` and `HALTED`; `derive` over a fixture a2a directory recomputes the counters from the feedback history (PRD AC-4.6)"
- Status: ✓ Met
- Evidence: `.claude/scripts/run-checkpoint.sh:479-532` (`cmd_record_round`: hash via `fb_parse`, counters, trigger order, `state: OPEN` and history on a trip, `.run/state.json` `.state = "HALTED"`, exit 10), `:276-312` (`recompute`, `merge_breaker`: counters raised, never lowered)
- Test: `tests/unit/run-checkpoint-record-round.bats:46` RCR-1 (count and hash equal to the SKILL formula), :87 RCR-4 (trip → OPEN, one history entry, HALTED, exit 10), :122 RCR-6 (APPROVED leaves counters); `tests/unit/run-checkpoint-derive.bats:231` RCD-9 (two `-r1` files with a zeroed breaker give 2/2/1), :258 RCD-10 (derived trip)

### AC-2.7
"`run-checkpoint-derive.bats` has one case per decision-table row: the drift fixture derives to the file-derived state; a stale marker whose trailer names another sprint does not count; terminal states are never moved back to RUNNING; each known reader has a fixture case; `run_mode.file_authoritative: false` makes `derive` report-only; the jack-out step writes `.state` (PRD AC-5.1 … AC-5.4)"
- Status: ✓ Met
- Evidence: `.claude/scripts/run-checkpoint.sh:314-329` (`resolve`, the run-state table), `:331-477` (`cmd_derive`), `:174` (`write` calls `derive --write`); `.claude/skills/run-mode/resources/completion-modes.md:40` (§Jack-out writes `.state` and mirrors `.status`)
- Test: `tests/unit/run-checkpoint-derive.bats` RCD-1 drift :80, RCD-2 stale marker :101, RCD-3 legacy :122, RCD-4 awaiting_marker :135, RCD-5 JACKED_OUT terminal :154, RCD-6 HALTED sticky :175, RCD-7 COMPLETE never back to RUNNING :189, RCD-8 RUNNING/INTERRUPTED :207, RCD-11 schema tolerance :272, RCD-12 report-only knob :291, RCD-13 exit 4 :312, RCD-16 jack-out doc :358; readers RCD-R1 surface hook :379, RCD-R2 run-preflight P6 and `--resume` :400, RCD-R3 golden-path :419, RCD-R4 implement gate :431, RCD-R5 `/loa` :453
- Notes: PRD AC-5.1 says the drift fixture derives to JACKED_OUT; the SDD D-5.4 and this task's prompt say COMPLETE. The implementation follows the SDD, because the table only reaches JACKED_OUT from the cache or `.completion.merged_sha`.

### AC-2.11 (implementer D's half)
"`implement_gate.mode` and the new keys are documented in the example with a config-key table in the report; the hooks reference describes the gate as a fence only under `deny`; this repository still reads `ask` at sprint end"
- Status: ✓ Met for D's half. The hooks-reference wording is Task 2.9, the lead's.
- Evidence: `.loa.config.yaml.example:613` (`implement_gate:` block, documented comment above it, says "The hook is a fence only in this mode"), `:559` `run_mode.file_authoritative`, `:563` `run_mode.stale_hours`; the gate header documents modes, sanctions, override and rows (`implement-gate.sh:8-47`); this repository's `.loa.config.yaml` is untouched (`git status` lists only the example)
- Test: `tests/unit/implement-gate.bats:477` IG-11 (the block names the three modes, claims, the marker, the override, `stale_hours`, "fence only", and `yq` reads `ask`)

Config keys added (all read by a test):

| Key | Documented default | Validation | Reader test |
|-----|--------------------|-----------|-------------|
| `implement_gate.mode` | `ask` | `ask`/`telemetry`/`deny`; `authoritative` = ask + claims; anything else = ask | IG-24…IG-27, IG-30 |
| `implement_gate.claims` | unset (plain) | only `authoritative` changes behaviour | IG-24…IG-27 (claims column), IG-29 |
| `run_mode.stale_hours` | 12 | integer 1…8760, else 12 | RCD-8, IG-33 |
| `run_mode.file_authoritative` | true | only the literal `false` turns it off | RCD-12 |
| env `LOA_IMPLEMENT_GATE_OVERRIDE` | unset | only `1` sanctions | matrix `override` column |

### AC-2.12
"After each patch apply the fence corpus and the hook bats were run before the next tool call relied on them, recorded in the report; every existing bats, pytest, vitest and fence-corpus suite is green on the sprint's final tree"
- Status: ⚠ Partial (lead-owned). The apply-time smoke runs happen in the main checkout, after the lead applies this patch. This worktree did not change the fence or its corpus.
- Evidence: in the worktree, the hook bats and every suite that reads the touched files pass (Testing Summary).

---

## Tasks Completed

- **Task 2.10**: `derive` with the decision table, terminal and sticky states, schema tolerance, the breaker recompute and the `file_authoritative` knob; `write` → `derive --write`; jack-out writes `.state` (`completion-modes.md` §Jack-out, `sprint-plan-mode.md` points at it, its failure step mirrors `.status`); `/loa` Run and Gate lines (`loa-status.sh:986`, one function and one call site at :677); run-resume step 0a derives on drift, and `--reset-ice` stamps `reset_at` (`halt-resume.md:49`, :81); the schemas doc covers the derived keys, the breaker additions and the marker (`state-schemas.md`).
- **Task 2.5**: `record-round`; the run-mode SKILL §Circuit Breaker is now the call plus two lines, and §Issue Hash Tracking is gone (`run-mode/SKILL.md:130-134`). The SKILL drops from 15372 B to 13682 B. The golden-path doc-lock now pins the recipe in the script (`golden-path-c8-verdict-trailer.bats:442`).
- **Task 2.1**: gate modes, sanctions, rows, replay flag, `--effective-mode`, example block, header; `implementing-tasks` and `bug-triaging` call `run-checkpoint.sh mark` at start and `unmark` at the end. `mark` writes the marker and runs `derive --write` when a run exists. Both skills stay within budget: `implementing-tasks` 16348 B, `bug-triaging` 16373 B, limit 16384.

---

## Technical Highlights: the decision tables as implemented

**Sprint state** (`run-checkpoint.sh` per-sprint jq). M = marker present and a feedback trailer names this sprint (`sprint-<gid>` or the local label). Stale = marker present and any trailer or `sprint:` line names another sprint. R/A = verdict-derive exit 0 with APPROVED for this sprint. L = ledger `completed`.

| Condition | Sprint state |
|-----------|--------------|
| M ∧ R ∧ A ∧ L | `complete` |
| ¬M ∧ R ∧ A (a stale marker counts as ¬M) | `awaiting_marker` |
| otherwise (legacy feedback: no verdict) | `in_progress` |

**Run state** (`resolve`, first match wins):

| # | Condition | State |
|---|-----------|-------|
| 1 | cache `.state` or `.status` is JACKED_OUT, or `.completion.merged_sha` is set | `JACKED_OUT` (terminal; contradicting files become a note) |
| 2 | breaker OPEN (after the recompute) or cache HALTED | `HALTED` (sticky until run-resume) |
| 3 | every ledger sprint `complete` | `COMPLETE` |
| 4 | cache COMPLETE and no incomplete sprint missing from `derivation.sprint_ids` (else `sprints.list[].id`) | `COMPLETE` (kept, note) |
| 5 | `timestamps.last_activity` within `run_mode.stale_hours` (12; ≤ 300 s ahead) | `RUNNING` |
| 6 | otherwise | `INTERRUPTED` |

**Breaker recompute** (active sprint = first incomplete, else last). Rounds come from `-rN` files plus the current file, unless the current file is byte-identical to the top `-rN`. They are sorted by trailer ts, then round, then gate. Rounds at or before `reset_at` are dropped. Over the non-APPROVED rounds: cycle = count; same_issue = run of equal hashes; no_progress = run of equal counts. Each cached counter becomes max(cache, recomputed). OPEN is set when same_issue, no_progress or cycle_count meets its threshold, with a history entry `source: derive`.

**Implement gate** (unsanctioned App-Zone write; sanction first):

| Mode | Cache fresh (parses, `derived_at` within stale_hours) | Cache stale, missing, not derived or unparseable |
|------|------|------|
| ask (default, unset, unknown) | ask, row `ask/ask` | ask, row `ask/ask` |
| telemetry | allow silently, row `telemetry/outside_run` | same |
| deny | deny, row `deny/deny` | ask, row `ask/unknown_position` |

Sanctioned writes allow with row `allow/sanctioned_run|sanctioned_marker|override`. A non-implementation claim under `claims: authoritative` asks, or under deny with a fresh cache and no sanction is denied; its `model_signal` row is the decision row. Trust inputs ask with row `ask/trust_input` in every cell.

---

## Testing Summary

Bats binary from `~/.cache/loa/cycle-128/bats-path`, run with `LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1`.

| Suite | Result |
|-------|--------|
| `tests/unit/implement-gate.bats` (23 existing + 10 new) | 33/33 |
| `tests/unit/run-checkpoint-derive.bats` (new) | 22/22 |
| `tests/unit/run-checkpoint-record-round.bats` (new) | 8/8 |
| `tests/unit/run-checkpoint.bats`, `tests/integration/implement-reentry.bats`, `tests/unit/golden-path-c8-verdict-trailer.bats` | pass (72 together with the two new suites) |
| 48 unit files matching run-, loa-status, golden, implement, guard-, skill-cap, preflight, checkpoint, circuit, state, no-history, post-compact, config | 748/748 |
| 9 bats files that read `.loa.config.yaml.example` | 336/336 |
| `.claude/adapters` pytest (catalog floor, auth metadata validator) | 60 passed |
| `bash tools/check-prompt-budget.sh` | exit 0 |
| `bash .claude/scripts/validate-skill-capabilities.sh` | 37 passed, 0 errors, 3 warnings (pre-existing) |
| `bash tools/check-no-raw-sha256sum.sh` | OK |
| `bash .claude/scripts/guard-yield.sh --check` | in sync (95 guards) |

`tests/integration/run-mode.bats` fails to load at HEAD as well, because `tests/test_helper` does not exist (`load '../test_helper'`). The failure predates this patch and is unrelated to it.

---

## Known Limitations

- `detect-platform-features.sh --line` still prints "Implement gate: heuristic|authoritative" beside the new Gate line. The two lines can disagree in wording (for example "heuristic" next to `deny`). The script is not in D's file list.
- `derive` does not evaluate the timeout trigger, which stays with `record-round`. A clock-based trip at every checkpoint would halt long multi-sprint runs that `record-round` would not.
- Deny reads only `.run/sprint-plan-state.json` as the position. A `/run sprint-N` run with only `.run/state.json` is an unknown position under deny, so it asks.
- The jack-out and run-resume changes are skill prose, so a model still has to follow them. `derive --write` at the next checkpoint repairs a missed `.status` or `.state`.
- A marker and trailer forged together with the right sprint id still pass. This is the seam the sprint plan names as missed.

---

## Verification Steps

```bash
cd /home/merlin/Documents/thj/code/loa-wt-s2a
BATS=$(cat ~/.cache/loa/cycle-128/bats-path)
LOA_HARNESS_CHECK=0 LOA_AUDIT_REPLAY=1 $BATS tests/unit/implement-gate.bats tests/unit/run-checkpoint-derive.bats tests/unit/run-checkpoint-record-round.bats tests/unit/run-checkpoint.bats
bash .claude/scripts/run-checkpoint.sh derive --json --root /home/merlin/Documents/thj/code/loa   # read-only
bash .claude/hooks/compliance/implement-gate.sh --effective-mode /home/merlin/Documents/thj/code/loa/.loa.config.yaml
bash tools/check-prompt-budget.sh
```

---

## Assumptions

- [ASSUMPTION fact] verdict-derive's `--json` output carries no `sprint_id`, so derive reads the sprint id and ts from the last `<!-- LOA-VERDICT {...} -->` line itself.
- [ASSUMPTION fact] The COMPLETED marker has no LOA-VERDICT trailer, as `a2a/sprint-255/COMPLETED` shows. "The marker's trailer" is read as the feedback trailers in the same directory, plus the marker's `sprint:` line when present.
- [ASSUMPTION fact] `golden-path.sh:874` reads `.run/bugs/*/state.json`, not the sprint-plan cache. Its reader case therefore proves that a derived cache beside the bug state changes nothing (RCD-R3).
- [ASSUMPTION fact] `completion-modes.md` already wrote `.state` on `.run/state.json`. The cycle-128 defect was the sprint-plan cache's jack-out (`update_state(state: JACKED_OUT)`), which the new §Jack-out fixes.
- [ASSUMPTION decision] A sprint's trailer may name it as `sprint-<gid>` or its ledger local label (SDD D-5.1). A stale-cycle trailer that happens to use the same local label is the documented "forged with the right id" miss.
- [ASSUMPTION decision] The run-state "cache" is `.run/sprint-plan-state.json`. JACKED_OUT is matched on `.state` OR `.status`, so the kickoff file shape (`state: RUNNING`, `status: JACKED_OUT`) derives JACKED_OUT with a disagreement note.
- [ASSUMPTION decision] "A new incomplete sprint" means a ledger sprint whose `sprint-<gid>` and local label are both absent from `derivation.sprint_ids`, or from `sprints.list[].id` when the cache was never derived.
- [ASSUMPTION decision] Only APPROVED with verdict-derive exit 0 counts as APPROVED, in derive and in record-round. An inconsistent trailer counts as findings, as the SKILL's main loop says.
- [ASSUMPTION decision] "APPROVED leaves counts" is read as: an APPROVED record-round writes nothing. The breaker file stays byte-identical, and same_issue and no_progress compare only non-APPROVED rounds.
- [ASSUMPTION decision] no_progress starts at 0 on the first round and counts consecutive equal counts. The previous counts are stored as `triggers.no_progress.last_counts`, a JSON string, so legacy rounds with null counts compare too.
- [ASSUMPTION decision] A record-round on an already-OPEN breaker prints `TRIPPED: open: breaker already OPEN` and exits 10 without a second history entry, so a caller that missed the first trip still halts.
- [ASSUMPTION decision] A record-round call with a missing feedback file exits 2 instead of hashing `none`, because it is a caller error.
- [ASSUMPTION decision] `--reset-ice` now stamps `reset_at`, and derive ignores rounds at or before it. Without this, derive would raise the counters right back after a reset.
- [ASSUMPTION decision] derive writes nothing when the cache file is missing (no run) or unparseable (kept as evidence). It creates the breaker file from the schema defaults when only the breaker is missing.
- [ASSUMPTION decision] derive does not touch `.sprints.list` or `.sprints.completed`. Only `.state`, `.status`, `derived_at`, `derivation` and a defaulted `schema_version` are written, per the task's key list.
- [ASSUMPTION decision] A cache without `derived_at` is an unknown position for deny, so it asks. When `derived_at` is present it must also be fresh for the run sanction. When it is absent, today's 24 h `last_activity` rule alone decides the sanction.
- [ASSUMPTION decision] Freshness for `derived_at` and the marker allows at most 300 s of clock skew ahead. The existing 24 h window for `last_activity` stays symmetric.
- [ASSUMPTION decision] The sanction order is run, then marker, then override. The override row appears only when nothing else sanctioned, so the register counts real overrides.
- [ASSUMPTION decision] `.run/implement-active.json` joins the trust inputs, so a Write-tool write to it asks. The skills write it through `run-checkpoint.sh mark` (Bash), which the gate never sees. This is tighten-only.
- [ASSUMPTION decision] Under `claims: authoritative` a non-implementation claim is denied, not asked, when deny would deny anyway. An ask there would loosen deny, and the modifier is tighten-only.
- [ASSUMPTION decision] The deny reason ends "or set implement_gate.mode: ask", per D-4.1 and the task prompt. SDD §4.3 says "telemetry", and D-4.1 is the more specific design text.
- [ASSUMPTION decision] Trust-input rows keep their `compliance.state_write` shape and gain `hook`, `action: ask`, `decision: trust_input` and `mode`, so the register counts those asks too.
- [ASSUMPTION decision] The marker is managed by new verbs, `run-checkpoint.sh mark|unmark`. This keeps the two skill sentences inside their byte budgets and the write atomic.
- [ASSUMPTION decision] To fit the budget, `implementing-tasks/SKILL.md` lost three redundant phrases: the inline br command list that the lifecycle line repeats, the second "fall back to markdown" sentence, and "patterns," in "architecture, patterns, conventions".
- [ASSUMPTION decision] IG-11 used to pin the key as undocumented (cycle-126). It now pins it as documented, and the README and docs grep was dropped, since D-4.1 supersedes it.
- [ASSUMPTION decision] The `/loa` Gate line comes from `implement-gate.sh --effective-mode`, so `/loa` and the hook share one parser. The config path reuses the existing `LOA_STATUS_CONFIG_FILE` seam, and a new bats-gated `LOA_STATUS_DERIVE_ROOT` seam points derive at a fixture.
- [ASSUMPTION decision] Scripts use `set -euo pipefail` and `LC_ALL=C` per the conventions. `run-checkpoint.sh` used to run without `-e`, so its `bead_closed` call was rewritten to capture the exit code safely.
