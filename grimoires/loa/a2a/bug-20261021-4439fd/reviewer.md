# sprint-bug-267 (bug 20261021-4439fd, bead bd-jm55c) — implementer B report

Model: global.anthropic.claude-opus-5-5
Red commit: 06bc53ce (fix: 3ec4e927)

## What was built
- Task 1 (tests): `tests/unit/post-pr-flatline-degraded.bats` (new, 10 tests: PFD-1, 2, 3, 4, 5, 5b, 6a, 6b, 6c, 7). Each behavioural test copies the real orchestrator, state script, compat-lib and the two libs into a scratch project under `$BATS_TEST_TMPDIR`, adds a stub `flatline-orchestrator.sh` (prints a chosen envelope, exits with a chosen code, records argv), inits state via `post-pr-state.sh`, sets state E2E_TESTING and runs `post-pr-orchestrator.sh --resume`. So every case is an end-to-end run to READY_FOR_HITL. No main-guard was needed.
- Task 2 (fix): `.claude/scripts/post-pr-orchestrator.sh`
  - new helper `_flatline_pr_not_green` (:376): phase `failed`, marker FLATLINE-PR-DEGRADED, atomic summary `.run/post-pr-degraded-summary.json` `{state:"DEGRADED", phase:"flatline_pr", status, voices_planned, voices_completed, degraded_models, pr_number, reason}`, log_error, returns 0.
  - `phase_flatline_pr` (:429): clears stale `.run/post-pr-flatline-pr.json` and summary; runs the orchestrator with `--json`, stdout to a temp file then mv (:480); `ok` reads `.verdict_quality.status` with `jq -er` (:500-523): APPROVED → completed + PR-VALIDATED; DEGRADED/FAILED/absent/unparseable → not-green. `timeout` → reason `timeout` (:544); `*` → reason `exit_<code>` (:549). Blocker and orchestrator-error branches unchanged; `enabled: false` keeps `skipped` (:445).
  - `phase_bridgebuilder_review`: its stale-summary `rm -f` now keeps a summary whose `.phase` is `flatline_pr` (otherwise it deleted the Flatline summary before READY_FOR_HITL, even with Bridgebuilder disabled).
  - `surface_degraded_handoff` (:755): names "Flatline PR review (marker FLATLINE-PR-DEGRADED)" when the summary is the Flatline one; Bridgebuilder wording unchanged.
  - `run_orchestration` `--skip-flatline` branch (:856): removes a stale summary.
- Task 3 (docs): phase doc-comment directly above `phase_flatline_pr` (:413-428) and a 3-line note in the file header under the phase list.

## Red run
Against the unmodified orchestrator (commit 03e77312), `~/.cache/loa/cycle-128/s2d/bin/bats tests/unit/post-pr-flatline-degraded.bats`: 1 ok, 9 not ok.
```
not ok 1 PFD-1 ... # line 88: [ "$(_get phases.flatline_pr)" = "failed" ]   (was completed)
ok 2 PFD-2 ... (control, passes today as the triage states)
not ok 3 PFD-3 ... line 88 (was completed)
not ok 4 PFD-4 ... line 88 (was skipped)
not ok 5 PFD-5 ... line 88 (was skipped)
not ok 6 PFD-5b ... line 88 (was skipped)
not ok 7 PFD-6a / 8 PFD-6b / 9 PFD-6c ... line 88 (was completed)
not ok 10 PFD-7 ... line 189: [ "$(grep -c 'flatline_pr skipped' <<<"$body")" -eq 1 ]
```
Line 87 (`[ "$status" -eq 0 ]`) passed in every case, so these are assertion failures, not load failures. The red output matches none of red-test-check.sh's NOT_A_RED patterns.

## How it was tested
`bash -n .claude/scripts/post-pr-orchestrator.sh` → OK. bats (green, all 0 failures, 0 skips):
| file | ok |
|---|---|
| post-pr-flatline-degraded.bats | 10/10 |
| post-pr-state.bats | 11/11 |
| post-pr-bridgebuilder.bats | 35/35 |
| post-pr-bridgebuilder-676.bats | 10/10 |
| post-pr-bridgebuilder-1076.bats | 5/5 |
| post-pr-audit-diff-scope.bats | 6/6 |
| post-pr-e2e-bats.bats | 6/6 |
| post-pr-context-clear-awk-portable.bats | 4/4 |
| bridge-issue-sweep.bats (extra: evals the Bridgebuilder phase and handoff) | 7/7 |
| flatline-exit-classifier.bats (extra) | 12/12 |
`tools/check-no-swallowed-jq.sh` (enforced set) OK; `--root` on the orchestrator shows 9 hits both at base and after (all pre-existing lines, none added). `tools/check-no-raw-sha256sum.sh` OK. shellcheck not installed.

## AC evidence
- DEGRADED never reads green: PASS — PFD-1 (tests/unit/post-pr-flatline-degraded.bats:101), fix post-pr-orchestrator.sh:500-523.
- FAILED verdict: PASS — PFD-3 (:131).
- Timeout reads failed, not skipped: PASS — PFD-4 (:140), fix :542-545.
- Non-blocker failure reads failed: PASS — PFD-5 (:147), PFD-5b (:154), fix :547-550.
- Missing/malformed envelope fails closed: PASS — PFD-6a/b/c (:163-183).
- APPROVED control stays completed + PR-VALIDATED: PASS — PFD-2 (:118).
- Static contract (doc-comment; only disabled branch writes skipped): PASS — PFD-7 (:184), doc :413-428, skipped :445.
- E2E: DEGRADED run ends READY_FOR_HITL with flatline_pr failed, marker FLATLINE-PR-DEGRADED, summary present, handoff names it: PASS — PFD-1 via `_assert_failed_not_green` (:85-99) plus the output check (:116).
- No regressions: PASS — table above.
- Root cause, no new config: PASS — the verdict is read; post-pr-state.sh untouched; no config key.
- Blocker/orchestrator-error branches unchanged: PASS — diff touches neither.
- Fix later than red and does not weaken the test: PENDING — the lead runs red-test-check.sh after committing.

## DECISIONS
- DECISION: drove the phase end to end through `post-pr-orchestrator.sh --resume` from a scratch copy of the scripts dir. No main-guard was added. Rejected sourcing the orchestrator or eval-ing the function, because the E2E criterion needs READY_FOR_HITL.
- DECISION: flatline-orchestrator.sh exits 6 whenever verdict_quality.status is not APPROVED (flatline-orchestrator.sh ~3174), so a real DEGRADED run on main reached the `*)` branch and was recorded `skipped`. Added PFD-5b for exit 6. The summary still carries the envelope's status and voices, with reason `exit_6`. Rejected a special exit-6 class, because the classifier is read-only and `*)` already covers it.
- DECISION: reasons are `verdict_quality_degraded`, `verdict_quality_failed`, `no_verdict_quality`, `timeout` and `exit_<code>`. An unknown status string also fails closed as `no_verdict_quality`.
- DECISION: the summary's `voices_completed` reads `verdict_quality.voices_succeeded`, the real field name in loa_cheval/verdict/quality.py, and falls back to `voices_completed`, the name the triage uses. `degraded_models` reads the top-level `.degraded_models`, else the `voices_dropped[].voice` list.
- DECISION: the summary uses the same path as Bridgebuilder's. The Bridgebuilder stale-clear now keeps a summary whose phase is flatline_pr, and phase_flatline_pr clears stale ones at its start. Without this the summary was deleted before READY_FOR_HITL. If Bridgebuilder itself goes DEGRADED, its summary overwrites the Flatline one; the failed phase and the marker remain in state. Rejected a separate file, because the brief fixed the path.
- DECISION: when flatline is enabled but flatline-orchestrator.sh is absent, the result is now `failed` with reason `no_verdict_quality`. It used to be completed + PR-VALIDATED. A missing reviewer is not a green review.
- DECISION: the handoff line in surface_degraded_handoff names the Flatline review and its marker. The "READY_FOR_HITL includes a DEGRADED" prefix that bridge-issue-sweep.bats asserts is kept.
- DECISION: the `--skip-flatline` branch removes a stale summary, so a skipped phase never inherits an earlier run's Flatline summary.
- DECISION: a failed add-marker or summary write is logged and the run continues (best-effort, same as `_update_phase`). The phase status is written first.

## CHANGELOG entry text
### Fixed
- **Post-PR Flatline review verdict is read (bug 20261021-4439fd, bd-jm55c).** `post-pr-orchestrator.sh` captured nothing from the Flatline run, so a DEGRADED, FAILED, missing or timed-out review read `completed` + PR-VALIDATED or `skipped`. Now only an APPROVED verdict is green. Every other outcome is `failed` with `.run/post-pr-degraded-summary.json` and the marker FLATLINE-PR-DEGRADED, and the flow continues to READY_FOR_HITL.

## What the lead must do
- The full patch is cumulative and also creates the test file. After committing the red patch, apply the rest with `git apply --exclude=tests/unit/post-pr-flatline-degraded.bats ~/.cache/loa/cycle-132/patches/bug-b-full.patch`, or apply the full patch on a clean base.
- reviewer.md sits under the gitignored grimoires/loa/a2a/ and is not in either patch.
- red-test-check.sh runs under `env -i`. The tests need jq and yq on PATH, or setup skips and the red run would read as DECOY. bats is not on PATH; pass its absolute path if the runner check allows it.
- Your list: checksums and REPO-MAP regen, CHANGELOG, KF-039 attempt row, fleet reply.
