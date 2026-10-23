# Bug Triage: post-pr-orchestrator marks a degraded or failed Flatline PR review green (`completed` + PR-VALIDATED, or `skipped`); the kind:cli Claude prompt-size failure behind it is fixed upstream since rc.3 (bd-jm55c, KF-039 rec 2)

## Metadata
- **schema_version**: 1
- **bug_id**: 20261021-4439fd
- **classification**: logic_bug (a phase verdict is not read; a failed phase is recorded as skipped) + upstream-fixed transport defect (fleet mount behind)
- **severity**: medium
- **eligibility_score**: 3
- **eligibility_reasoning**: Error log from a production incident (+1): fleet mailbox message `20261020T013120Z-ono-sendai-4fc390b2` (run `flatline-22501-13348`, 2026-10-20T01:24Z) with the verbatim `[cheval] PROVIDER_UNAVAILABLE … [Errno 7] Argument list too long` line, `verdict_quality DEGRADED` (1 of 3 voices) and `READY_FOR_HITL` reached green with `flatline_pr` not failed. Reproducible steps (+2): on main `16e0b48b` a stub `flatline-orchestrator.sh` that exits 0 with a `verdict_quality.status: DEGRADED` envelope makes `phase_flatline_pr` record `completed` and add the `PR-VALIDATED` marker (post-pr-orchestrator.sh:423-427); a stub that times out or exits non-zero is recorded `skipped` (:447-456) although `post-pr-state.sh` has carried a `failed` status since #1076 (:55-58). Premise check: the transport half (argv prompt over MAX_ARG_STRLEN) is **not** on main — `ClaudeHeadlessAdapter._prepare_invocation` has sent every prompt on stdin since `398859ad` / `10436350` (rc.3; `claude_headless_adapter.py:285-296`, `TestPromptTransport`); the reporter's `.loa` is v2.0.0-rc.2 (`764d80f8`, 2026-09-24) whose adapter has no override and whose `headless_cli.py:98` is the default argv transport. No disqualifier.
- **test_type**: unit
- **risk_level**: low
- **created**: 2026-10-21T00:52:00Z

## Reproduction
### Steps
1. In a scratch project with `.loa.config.yaml` `flatline_protocol.enabled: true`, a `post-pr-state.sh` state in phase FLATLINE_PR (mode autonomous) and `SCRIPT_DIR` pointed at a stub directory whose `flatline-orchestrator.sh` prints `{"verdict_quality":{"status":"DEGRADED","voices_planned":3,"voices_completed":1}, "blockers":[]}` and exits 0, run `phase_flatline_pr` (via `post-pr-orchestrator.sh --resume` or the function under `bats`).
2. Same, with a stub that sleeps past `TIMEOUT_FLATLINE_PR` or exits 3.
3. Fleet side (reference only, not reproducible on main): ono-sendai `.loa` at `764d80f8` (rc.2), `post-pr-orchestrator.sh --resume` on PR hosaka-fm/ono-sendai#34 with `--doc grimoires/loa/sdd.md` of 128,759 bytes.

### Expected Behavior
- Step 1: the phase reads the verdict-quality envelope; `DEGRADED` (or `FAILED`) records `flatline_pr` as `failed`, writes a degraded summary (`.run/post-pr-degraded-summary.json`, the shape the Bridgebuilder phase already writes), adds a non-green marker (`FLATLINE-PR-DEGRADED`) and never adds `PR-VALIDATED`; the flow continues to `READY_FOR_HITL` with the non-green marker visible in the final report (the fleet rule: count the voices).
- Step 2: timeout or failure records `failed` with a reason, never `skipped` (`skipped` means the phase was not enabled or was not run on purpose).
- Step 3: the prompt rides stdin at every size (true on ≥ rc.3); the fleet repo updates its mount.

### Actual Behavior
- Step 1 (code read 2026-10-21, post-pr-orchestrator.sh:409-427): the orchestrator's JSON output is not captured (`run_with_timeout … flatline-orchestrator.sh --doc … --phase pr --autonomous 2> >(tee …)`); exit 0 → `classify_flatline_exit` → `ok` → `log_success "Flatline PR review completed"`, `_update_phase flatline_pr completed`, `add-marker "PR-VALIDATED"`. The incident run reached `READY_FOR_HITL` green over one voice of three.
- Step 2 (:447-456): `timeout) … _update_phase flatline_pr skipped; return 0` and `*) … failed (exit: …), continuing; _update_phase flatline_pr skipped; return 0`.
- Step 3 (incident 2026-10-20T01:24Z, rc.2): `[cheval] PROVIDER_UNAVAILABLE: Provider 'anthropic' unavailable: claude -p spawn failed (ARG_MAX / ENOMEM / exec error?): [Errno 7] Argument list too long: '/home/merlin/.local/bin/claude-fallback'`; the same prompt on main's adapter goes to stdin (`_prepare_invocation` yields `{"input": prompt, "cwd": workspace}`).

### Environment
Reporter: ono-sendai (`/home/merlin/Documents/thj/code/hosaka/ono-sendai`), Loa submodule `.loa` = `764d80f8` v2.0.0-rc.2; Linux, `claude-fallback` wrapper on PATH. This repository: main `16e0b48b`, branch `fix/cycle-132-bugs`; `post-pr-state.sh` `VALID_PHASE_STATUSES=("pending" "in_progress" "completed" "skipped" "failed")`.

## Analysis
### Suspected Files
| File | Line(s) | Confidence | Reason |
|------|---------|------------|--------|
| `.claude/scripts/post-pr-orchestrator.sh` | 370-460 | high | `phase_flatline_pr` never reads the verdict-quality envelope; `ok` ⇒ completed + PR-VALIDATED; timeout/failure ⇒ `skipped` |
| `.claude/scripts/post-pr-orchestrator.sh` | 476-610 | medium | the Bridgebuilder phase's degraded-summary and `failed` handling is the pattern to mirror (`.run/post-pr-degraded-summary.json`, `_update_phase … failed`) |
| `.claude/scripts/lib/flatline-exit-classifier.sh` | 38- | medium | `classify_flatline_exit` classes: ok / flatline_blocker / flatline_orchestrator_error / timeout / other — gains no class; the vq read happens after `ok` |
| `.claude/scripts/flatline-orchestrator.sh` | 813-910, 1161-1240 | medium | the `--json` output carries `verdict_quality` (status APPROVED / DEGRADED / FAILED per `lib/verdict-quality.sh`), `degraded`, `degraded_models` — the fields the orchestrator must read |
| `.claude/scripts/post-pr-state.sh` | 55-58 | low | `failed` is already a valid phase status (#1076 d4) |
| `.claude/adapters/loa_cheval/providers/claude_headless_adapter.py` | 285-296 | low (verified fixed) | stdin transport at every size since rc.3; nothing to change; the KF-039 ledger gets the attempt row and the fleet gets the version answer |
| `grimoires/loa/known-failures.md` | KF-039 | medium | attempts row: fleet report resolved as "mount behind rc.3"; orchestrator half fixed here |

### Related Tests
| Test File | Coverage |
|-----------|----------|
| `tests/unit/post-pr-bridgebuilder-1076.bats` | static contract: the Bridgebuilder phase marks `failed`, not `skipped`, and halts loud — the pattern for this phase's contract tests |
| `tests/unit/post-pr-state.bats` | phase status vocabulary and transitions |
| `tests/unit/post-pr-bridgebuilder.bats`, `post-pr-bridgebuilder-676.bats` | orchestrator phases driven with stubs |
| `.claude/adapters/tests/test_claude_headless_adapter.py::TestPromptTransport` | the prompt is on stdin at every size (small, >100 KB, wide, NUL) — stays as is |
| (none) | `phase_flatline_pr` verdict-quality handling |

### Test Target
New `tests/unit/post-pr-flatline-degraded.bats`, failing first:
- PFD-1 stub orchestrator exits 0 with `verdict_quality.status: DEGRADED` → `flatline_pr` status `failed`, marker `FLATLINE-PR-DEGRADED` present, `PR-VALIDATED` absent, `.run/post-pr-degraded-summary.json` names the phase, voices planned/completed and the reason; the phase function returns 0 (flow continues) (fails today: `completed` + PR-VALIDATED).
- PFD-2 stub exits 0 with `APPROVED` and all voices → `completed` + `PR-VALIDATED` (control; passes today).
- PFD-3 stub exits 0 with `FAILED` → `failed`, no PR-VALIDATED (fails today).
- PFD-4 stub times out → `failed` with reason `timeout`, not `skipped` (fails today).
- PFD-5 stub exits 3 (non-blocker failure) → `failed`, not `skipped` (fails today).
- PFD-6 stub output is not JSON or lacks `verdict_quality` → `failed` with reason `no_verdict_quality` (fail closed; fails today).
- PFD-7 static contract (1076 pattern): the phase doc-comment states the vq rule; no `_update_phase flatline_pr skipped` remains except the `enabled: false` branch.

### Constraints
- The flow is not halted on DEGRADED: KF-041 (recurrence 4) degrades the cross-scoring on most planning reviews, so a halt would stop every fleet post-PR run; the consortium choice is a non-green, visible `failed` phase with the summary, continuing to `READY_FOR_HITL` (alternatives — halt on DEGRADED; keep `skipped` — rejected; DEC row).
- `flatline_blocker` and `flatline_orchestrator_error` branches keep their existing halt behaviour; `enabled: false` keeps `skipped`.
- The orchestrator's JSON output is captured to a file under `.run/` (`post-pr-flatline-pr.json`), read with `jq`; a missing or malformed envelope fails closed.
- No new configuration key; `post-pr-state.sh` unchanged (statuses already exist); markers are strings in the existing marker list.
- Transport half: no adapter change on main (verified); KF-039 attempt row with evidence (`398859ad`, `10436350`, the reporter's `764d80f8`); fleet reply via `hosaka/.mailbox/bin/send.sh --from loa --to ono-sendai --kind reply --reply-to 20261020T013120Z-ono-sendai-4fc390b2` stating the fix version and this orchestrator change.
- System Zone edit under `/bug`: `.claude/scripts/post-pr-orchestrator.sh`, header; `.claude/checksums.json`, `grimoires/loa/REPO-MAP.md` regeneration.

## Fix Strategy
Capture the Flatline orchestrator's `--json` output to `.run/post-pr-flatline-pr.json`; after an `ok` exit, read `.verdict_quality.status` (and voices planned/completed): `APPROVED` → `completed` + `PR-VALIDATED` as today; `DEGRADED` or `FAILED` → `_update_phase flatline_pr failed`, write `.run/post-pr-degraded-summary.json` `{state, phase: "flatline_pr", status, voices_planned, voices_completed, degraded_models, pr_number}`, add marker `FLATLINE-PR-DEGRADED`, log an error line, return 0; a missing/unparseable envelope is `failed` with reason `no_verdict_quality`. Change the `timeout` and `*` branches to `failed` with the reason in the summary (no halt). Add the bats file. Record KF-039 attempt row and send the fleet reply (upstream fix version rc.3; current rc.6; this orchestrator fix in the next rc).

### Fix Hints
Structured hints for multi-model handoff (each hint targets one file change):

| File | Action | Target | Constraint |
|------|--------|--------|------------|
| `.claude/scripts/post-pr-orchestrator.sh` | fix | `phase_flatline_pr`: capture `--json` output; read `verdict_quality.status`; DEGRADED/FAILED/missing ⇒ `failed` + summary + `FLATLINE-PR-DEGRADED`, no `PR-VALIDATED`; timeout/other ⇒ `failed` | no halt on DEGRADED; blocker/orchestrator-error branches unchanged; `enabled: false` stays `skipped` |
| `.claude/scripts/post-pr-orchestrator.sh` | fix | header/phase doc-comment: the verdict-quality rule and the marker | one paragraph |
| `tests/unit/post-pr-flatline-degraded.bats` | add | PFD-1 … PFD-7 | stub orchestrator + scratch state; never the live `.run/` |
| `grimoires/loa/known-failures.md` | add | KF-039 attempts row (fleet report; mount at rc.2; fixed since rc.3; orchestrator half here) | via `kf-write-lib.sh attempt` with evidence |
| fleet mailbox | add | reply to ono-sendai | `send.sh --from loa --to ono-sendai --kind reply` |
