# Sprint 261 implementer K: Task 4.2, per-task-type run caps (DEC-0559, DEC-0567)

Worktree `/home/merlin/Documents/thj/code/loa-wt-s4k` (branch wt/cycle-130-s4k, base de77522a). Patch `~/.cache/loa/cycle-130/patches/s4-k.patch` (+ `.stat`).

## What was built (file:line)
- `evals/suites/ablation-2.0.yaml:34-41`: a commented caps block; `caps: {cycle_usd: 1500, run_usd: 12, reserve_usd: 250, run_usd_by_type: {build: 15, review-catch: 20}}`. No other key changed.
- `evals/harness/run-ablation.sh`
  - header: `--run-cap` option rewritten (:34-38); new "Run caps" paragraph (:176-186); Spend paragraph per kind (:188-199); MANIFEST `caps` fields (run_usd_by_type); `--resume` reads "run caps"; per-trial `--max-run-usd <the trial kind's run cap>`; DEC-0567 in the title.
  - `RUN_CAP_OVERRIDE` captured after parsing (:349).
  - `--resume`: the caps come from MANIFEST.json (:427-432). A manifest without `run_usd_by_type` gives both kinds its `run_usd`. Each value is checked with `usd_ok`. A `--run-cap` on resume prints a stderr note and is ignored.
  - `suite_kind_cap`, the per-kind resolution, and `cap_for <kind>` (:477-495).
  - `RESERVE_CAP`, the largest cap among the plan's kinds, and the plan line (:765-771).
  - MANIFEST `caps.run_usd_by_type` (:812).
  - `account_row` charges the kind's cap for a cap_failure and passes it to `spend_charge` (:959-967).
  - `run_trial` passes `--max-run-usd "$(cap_for "$kind")"` (:1102).
  - `collect` charges the kind's cap for no-result and no-row trials (:1200-1201, :1238-1239).
  - `budget_gate … "$RESERVE_CAP"` (:1450).
- `evals/harness/lib/arms-common.sh:129,143`: `spend_charge <status> <cost> <what> [<cap>]` and `budget_gate <key> <n> [<pool>] [<reserve-per-trial>]`, both defaulting to `$RUN_CAP`. The header documents both. `run-arms.sh` is untouched and keeps its behaviour.
- `evals/tests/fixtures/ablation-pipeline-stub.sh:9,24,48,63`: `STUB_ARGV_LOG` logs `<run_id> max-run-usd <amount|none>`. A new mode `agent_error_nocost` is agent_error with cost 0. Every existing mode is unchanged.
- `evals/tests/run-ablation.bats`: `STUB_ARGV_LOG` is unset in setup, a `logline` helper is added, two assertions are updated, and RAB-22 … RAB-26 are new (:733-850).

## Interface as built
- **Cap chain:** `cap_for <kind>`, where kind is build (feature-build, bug-fix, refactor) or review-catch.
  1. `--run-cap` sets both kinds.
  2. Else the suite's `caps.run_usd_by_type[<kind>]`.
  3. Else RUN_CAP, today's unchanged chain: `.loa.config.yaml evals.ablation.run_cap_usd`, else `caps.run_usd`, else 12. MANIFEST `caps.run_usd` records this RUN_CAP, which is `--run-cap` when given.
  - A present entry that fails `usd_ok`, or a `run_usd_by_type` that is not a map, is exit 2 and writes nothing.
- **Where the cap is used:** `pipeline-run.sh --max-run-usd` gets the trial's kind cap. A cap_failure is charged max(cost, kind cap). A non-completed trial with no reported cost is charged the kind cap. So are a job without a result and a trial whose row failed.
- **Reservation:** the in-flight reservation is running trials × RESERVE_CAP. RESERVE_CAP is the largest `cap_for` over the kinds present anywhere in the plan.
  - With the suite caps, a build-only plan reserves 15 per trial and any plan with a review-catch trial reserves 20.
  - With `--run-cap X` it reserves X.
  - The cut test (spent + est_next > max) is unchanged.
- **MANIFEST.json** caps: `{cycle_usd, run_usd, reserve_usd, max_usd, run_usd_by_type: {build, review-catch}}`.
- **STATUS.json:** unchanged.
- **Plan line:** `… (cap M, run caps build B review-catch R, in-flight reserve X per trial, reserve 250)`.
- **`--resume`:** run_usd and both kind caps come from MANIFEST.json, never the suite file.

## Tests added (all fail on de77522a's harness, all pass after)
- **RAB-22:** the dry-run MANIFEST carries `run_usd_by_type` {15, 20} and the plan line shows it. `--run-cap 9` gives run_usd 9 and both kinds 9. A build-only plan reserves 15. A suite without `run_usd_by_type` gives {12, 12}. A suite missing only review-catch gives {15, 12}. A malformed entry or a list value is exit 2 with the message and no MANIFEST.
- **RAB-23:** the stub argv log shows `max-run-usd 15` for the build trial and `20` for the review-catch trial. With `--run-cap 9`, both show 9.
- **RAB-24:** a review-catch cap_failure is charged 20 and a costless agent_error build trial 15. Rows total 5, spent is 37.5, and assumed_cap_trials is 2. The run.log lines name the kind.
- **RAB-25:** seed 5 puts the build trial first. With a review-catch trial in the plan, `--max-usd 27.99` waits (done before the second launch) and 28 launches concurrently (0 + 1×20 + hint 8 = 28). A build-only plan waits at 21.99 and launches at 22 (0 + 15 + 7). A per-own-kind rule (23) and the old single cap (20, 19) would both launch at 27.99 and 21.99.
- **RAB-26:** a batch runs on a suite copy. The copy's caps are then edited to run_usd 50 and {30, 40}, the rows are removed, and `--resume --run-cap 9` is run. The note is printed, dispatch still passes 15 and 20, MANIFEST caps are byte-equal, and both rows land.
- **Updated:**
  - RAB-1's exact `caps` assertion now includes `run_usd_by_type`.
  - RAB-5's spent changes from 32 to 35, with the comment updated. Its build cap_failure is now charged the build cap 15 instead of 12. This second update follows from the suite change and was not named in the brief.

## bats counts
| | before (de77522a) | after |
|---|---|---|
| evals/tests/ | 378/378 | 383/383 |
| run-ablation.bats | 22 | 27 |
| run-arms.bats | 14 | 14 (green) |

## DECISION bullets
- DECISION: The reservation rule is running trials × the largest cap among the plan's kinds, not per in-flight trial's own kind. It matches sprint.md Task 4.2 ("the largest cap in the plan") and the operator's `--max-usd` formula in DEC-0567. It is conservative and needs no per-PID bookkeeping in the shared library. With the suite caps a mixed plan reserves 20 for a running build trial.
- DECISION: The multiplier stays the count of running trials (`${#PIDS[@]}`), as today, not `--concurrency`. Reserving idle slots would change existing RAB-9 semantics and is what the operator's `--max-usd` arithmetic already covers.
- DECISION: The library takes the cap per call through optional trailing arguments (`spend_charge … [<cap>]`, `budget_gate … [<reserve-per-trial>]`) that default to `$RUN_CAP`. `run-arms.sh` calls them unchanged.
- DECISION: A present but malformed `caps.run_usd_by_type` entry, or a non-map value, is a usage error (exit 2), not a silent fall-through. A pre-registered cap must never quietly become 12. Today's single-cap chain keeps its fall-through.
- DECISION: `--run-cap` on `--resume` is ignored with a stderr note. Before, it was ignored silently. A batch keeps the caps it started with, and RAB-26 proves that.
- DECISION: A MANIFEST without `run_usd_by_type` resumes with both kinds at its `run_usd`, so pre-DEC-0567 batches keep their single cap.
- DECISION: `.loa.config.yaml evals.ablation.run_cap_usd` sits below the suite's per-kind entry, as the brief specified. It only feeds the fallback and MANIFEST `run_usd`.
- DECISION: `reserve_usd: 250` stays in the suite because `spend.sh` reads it. The comment records that DEC-0559 released the reserve.
- DECISION: The stub gained the mode `agent_error_nocost` for the costless failed build trial. A watchdog-interrupted trial would also work but costs seconds per case.
- DECISION: RAB-5's spent assertion was updated from 32 to 35. It reads the real suite file, so its build cap_failure is now charged 15. The test still proves "a cap failure charges the cap".

## Could not do / limitations
- shellcheck is not installed on this host, so the scripts were not linted. `bash -n` passes on all three.
- The `.loa.config.yaml` rung of the chain has no case, because no test config sets it, the same as before.

## Handoff notes for the lead
- **Applying onto your checkout:** your HEAD b7e9967a landed after this dispatch and touches run-ablation.sh next to my manifest edit. `git apply --check --3way --exclude=evals/suites/ablation-2.0.yaml s4-k.patch` is clean on all four other files. The suite hunk needs a hand edit, because your uncommitted `suite_version: 2` makes the working file differ from the index.
- **Merged tree verified:** a scratch tree at b7e9967a with the patch merged in (`git merge-file` for run-ablation.sh and the suite file) runs evals/tests/ 383/383.
- **Report copy:** the worktree copy at `grimoires/loa/a2a/sprint-261/reviewer-k.md` is git-ignored (`.gitignore:193 grimoires/loa/a2a/*`), so it is not in the patch.
- **Applying the patch:** the suite-file hunk's context includes `suite_version: 1`, which your checkout already changed to 2. Use `git apply --3way`, or re-apply the one caps line and comment by hand.
- **v1 task ids:** run-ablation.bats, including RAB-22 … RAB-26, uses v1 ids (bugfix-01, bugfix-02, refactor-01, review-01) from the frozen suite. Once the v1 build directories leave `tasks/` (Task 4.3), the whole file needs the v2 ids. That affects every RAB case, not only these.
- **For the re-pre-registration entry (Task 4.7):**
  - The caps as built are build 15 and review-catch 20, with run_usd 12 as the fallback, recorded in MANIFEST `caps.run_usd_by_type`.
  - The reservation is running trials × 20 for any plan containing review-catch trials, so 3 × 20 at concurrency 3.
  - A cap_failure is charged max(cost, kind cap). A costless non-completed trial is charged the kind cap.
  - `--run-cap` overrides both kinds and must not be passed for priority-v2-p1.
  - `--resume` keeps the batch's caps.
