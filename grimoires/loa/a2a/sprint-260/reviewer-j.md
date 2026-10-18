# Sprint 260 implementer J: `--rerun` / `--rerun-status` for outage rows on resume, and the outage breaker

Worktree `/home/merlin/Documents/thj/code/loa-wt-s3j` at `84de21df`; nothing committed, no docker, no model call, nothing written under the lead's checkout, `ablation-grade.sh` untouched.
Patch: `~/.cache/loa/cycle-130/patches/s3-j.patch` (stat beside it, `s3-j.stat`). No new files, so no `git add -N` was needed. `git apply --check` passes at both `84de21df` and the lead's current `19731570`.

## What was built (landmarks in the patched `evals/harness/run-ablation.sh`)
- **Header**: the usage line, the `--rerun` / `--rerun-status` options (:75), the outage breaker paragraph after the watchdog, the new STATUS fields (`rerun`, `rerun_pending`, `outage`, `outage_history`; `ledger_usd` wording), the `--resume` paragraph (pre-lock checks, flagged rows out of the done set, outage cleared), exit 1 naming the breaker, and the env list (`LOA_ABLATION_OUTAGE_BREAKER`). DEC-0553/0554 added to the header citation.
- **Parsing and usage checks**: `RERUN_IDS`, `RERUN_STATUSES`, `OUTAGE_BREAKER`. Both flags need `--resume`. A status outside `transport_error | interrupted | infrastructure_error` is a usage error. An id must match the `--rerow` id regex. The same id twice, or an id given to both `--rerun` and `--rerow`, is a usage error. A non-integer breaker value is a usage error.
- **Pre-lock `--rerun` validation** (:811), read-only like I's `--rerow` block. It refuses (exit 2, nothing written) an id that is not `<batch>-…`, not in the plan, has no rows file, has a row count other than 1, or whose row status is not one of the three.
- **State**: `RERUN_LIST` (newline set, bash 3.2 style like `DONE_LIST`), `RERUN_OLD` (json `{run_id: {status, cost}}`), `RERUN_JSON`, `OUTAGE_JSON`, `OUTAGE_HISTORY_JSON`, `OUTAGE_RUN`; `is_rerun`.
- **`write_status`** (:925) adds `rerun`, `rerun_pending`, `outage` and `outage_history`.
- **`outage_tick`** (:1106) is the breaker. A `transport_error` row increments the count. Anything else collected resets it, including a job with no row or no result. At `count >= LOA_ABLATION_OUTAGE_BREAKER` (when > 0, no outage yet, `STOP` empty) it sets `STOP=outage` and `OUTAGE_JSON`, and logs `OUTAGE breaker: …`. Both exits of `collect` call it.
- **`collect`** (:1139) reads the row's status first. For a pending rerun it calls `replace_row_try` instead of `append_and_validate`. On success it moves the old row's reported cost into `LEDGER_USD`, drops the id from `RERUN_LIST`, appends `{run_id, from, to, old_cost_usd, at}` to `rerun[]`, and logs `rerun <id>: <from> → <to> (row replaced in place)`. On failure it sets `ROWS_INVALID` and `STOP=invalid`, leaving the old row in place. Then the new row goes through `account_row` once, as any row does.
- **`replace_row_try` / `replace_row`** (:1236, :1271): I's function is split. `replace_row_try` returns 1 with `REPLACE_ERR` set. `replace_row`, the `--rerow` form, still dies with the same message shape. The flock, the python in-place rewrite, the `--validate` of the temp file and the `mv` are unchanged.
- **Reconciliation**: loads `rerun[]` and `outage_history[]`. A non-null `outage` is appended to `outage_history` and dropped, with a log line. In the rows loop (:1335), a row is flagged when its id is in `--rerun`, or when its status is in `--rerun-status` and it is not a `--rerow` id. A flagged row goes to `RERUN_LIST`/`RERUN_OLD`, and only its reported cost is added to `SPENT`. It gets no `DONE_LIST` entry, no counters, no `rows_usd` and no assumed charge. A log line counts the flagged trials. This runs after `rerow_all`, so the status selection reads the rerowed rows.
- **End state** (:1393): an outage record finishes `partial` with exit 1 and its message. It is checked after invalid and drift, and before the cut and "no trial completed" branches.
- Dispatch is unchanged. A flagged id is not done, so the loop launches it at its plan index, and `fresh_dir` picks the next `-r<k>`. The in-flight reservation in `budget_gate` covers it like any trial.

## Interface as built
```
--rerun RUN_ID          (repeatable; needs --resume)
--rerun-status STATUS   (repeatable; needs --resume; transport_error | interrupted | infrastructure_error)
LOA_ABLATION_OUTAGE_BREAKER=N   (default 3; 0 disables)
```
New STATUS.json fields:
- `rerun: [{run_id, from, to, old_cost_usd, at}]`, default `[]`, carried across resumes.
- `rerun_pending: [run_id…]` lists ids flagged with no replacement yet, for example after a cut or a pause.
- `outage: null | {at, consecutive, last_run_id, message}`.
- `outage_history: [...]`.

The run.log and stdout message is exactly `partial (outage breaker): N consecutive transport failures; --resume --rerun-status transport_error after the network is back`.

## Tests added (`evals/tests/run-ablation.bats`)
- **RAB-19** builds a 4-trial batch with two `transport` trials, breaker off. Their `cost_usd` is zeroed to the P1 shape, so reconciliation would charge them the cap. It then checks the refusals, each exiting 2 with the rows file byte-identical and no lock left:
  - `--rerun` without `--resume`;
  - `--rerun-status completed`;
  - `--rerun <completed id>`;
  - one id given to both `--rerun` and `--rerow`.

  The rerun itself makes exactly two pipeline calls, into the `-r3` dirs. The rows file keeps the same run_id order, every row is completed, and the new rows have `attempts 1` and `retry_reason null`. It validates. `rerun[]` holds both ids with `from transport_error`, `to completed` and `old_cost_usd 0`, with timestamps. Spend reads rows 10, ledger 5, spent 15, assumed 0, and `spent == rows + ledger`. The state is complete with `trials_planned 4`, `resume_cursor 4` and `rerun_pending` empty. `per_arm` shows launched 4, completed 4, excluded 0, and both `retries[]` entries are kept. The log lines are present and no temp file is left. A follow-on case reruns an `interrupted` row while the stub still fails it as transport. The row becomes `transport_error` with attempts 2, in the same position. `rerun[-1]` reads `interrupted → transport_error`, and the `-r4`/`-r5` dirs exist.
- **RAB-19b** combines rerow and rerun in one resume. One `extra_model` run is rowed `infrastructure_error` (I's RAB-18 shape), and one transport row is left. The command is `--rerow x --rerun-status transport_error --rerun-status infrastructure_error`. It makes one pipeline call, for the transport id into `-r3`. The rerowed id is not launched, because the status selection reads the rows after the rerow. It makes two grade calls and keeps row order, and every row is completed. `rerowed[]` holds x and `rerun[]` holds y. The state is complete with rows 7.5, assumed 0 and completed 3.
- **RAB-20** checks the breaker. The 7-trial plan order is read from a dry run. The rules make the order transport, transport, ok, then transport, transport, transport, then ok. So the ok at position 3 resets the count, and position 6 trips it.
  - The trip leaves the state partial (exit 1) with `outage.consecutive 3`, and `last_run_id` names the sixth trial. Six of seven trials launched, and the seventh never reached the pipeline. The message appears in run.log and on stdout, and there is no cut or drift.
  - `--resume --rerun-status transport_error` with the stub ok makes 6 pipeline calls: 5 reruns plus the unlaunched trial. It leaves 7 unique rows, all completed. `outage` is null, `outage_history[0].consecutive` is 3, `rerun` has 5 entries, and the clear log line is present.
  - With `LOA_ABLATION_OUTAGE_BREAKER=0` and every trial transport, all 7 trials run, with 14 pipeline calls counting the retries. The batch exits 3 because nothing completed. Every row is transport_error, `outage` is null and `outage_history` is `[]`.
  - A non-integer breaker value is a usage error.
- **Edited existing lines**: only `setup()`, which now also unsets `LOA_ABLATION_OUTAGE_BREAKER`. No RAB-1 … RAB-18 assertion changed. The stub needed no new mode.

## bats counts

| Run | 84de21df (clean export) | patched |
|---|---|---|
| `evals/tests/run-ablation.bats` | 18/18 | 21/21 |
| `evals/tests/` (whole) | 369/369 | 372/372 |

The baseline ran in a clean `git archive` export of HEAD under `/tmp`. My first baseline run in the worktree overlapped my edit, so I discarded it.

## Mutation spot-check
Each mutation was applied to the script, RAB-10 … RAB-20 were run, and the file was restored and checked with `cmp`.

| Mutation | Red |
|---|---|
| a flagged row still added to the done set | RAB-19, RAB-19b, RAB-20 |
| replace-instead-of-append disabled (`if false`) | RAB-19, RAB-19b, RAB-20 |
| reconciliation accounts a flagged row (`account_row` in place of the skip) | RAB-19, RAB-19b, RAB-20 |
| breaker counter never reset | RAB-20 |

RAB-10 … RAB-18 stayed green under every mutation.

## DECISION bullets
- DECISION: a flagged row's **reported** cost stays in `spent`, and the assumed-cap charge is dropped. The brief reads "contributes nothing to spent (no cost, …)". DEC-0553 as recorded says "no assumed-cap charge", which is what is built. A reported cost is real API spend; dropping it would understate spend against `--max-usd`. When the replacement lands, that cost moves into `ledger_usd`, so `spent = rows_usd + ledger_usd + assumed` still holds. Ledger then means attempts with no standing row: transport first attempts plus replaced rows. For P1 this makes no numeric difference, because every transport row reports 0. RAB-19 zeroes the costs to that shape, and its `spent == rows + ledger` assertion holds either way.
- DECISION: the old cost goes into `ledger_usd` only **when the replacement lands**, not at reconciliation. A rerun that never lands (cut, pause or no row) then leaves the old row standing. The next resume re-reads it from scratch with no double count.
- DECISION: `--rerun-status` is evaluated **after** the rerows, against the rows as they then stand, and never selects a `--rerow` id. An id in both `--rerun` and `--rerow` is a usage error.
- DECISION: the breaker counts in collection order. Any collected trial that is not `transport_error` resets it, including a job with no row. `outage.consecutive` is the count at the trip; trials still running that end afterwards do not change it. The breaker only trips while `STOP` is empty, so a drift, invalid rows or a cut keeps its own end state.
- DECISION: the outage end state is checked before "no trial completed". So an all-transport batch that trips the breaker reads partial (exit 1) with the resume hint, not failed (exit 3). With the breaker off, the same batch is failed (exit 3) as before.
- DECISION: a failed in-place replacement during a rerun sets `ROWS_INVALID` and `STOP=invalid` and ends the batch failed (exit 3) with the old row kept. It does not die mid-dispatch, which would kill running trials. `--rerow` keeps I's dying behaviour.
- DECISION: added `rerun_pending` to STATUS. The brief did not ask for it, but it shows which flagged trials still await a new row after a cut or pause. It is additive.
- DECISION: the reruns' own transport retries append new `retries[]` entries and add their first-attempt cost to `ledger_usd`, as any trial does. The old `retries[]` entries are kept.

## Could not do / limitations
- A flagged trial whose arm is paused is skipped, and its old row stays in the file. It is not counted in `per_arm` (excluded is one lower) until a later resume reruns it or drops the flag. Its id stays in `rerun_pending`. Not covered by a bats case.
- A cut during the reruns leaves the unlanded ones in `rerun_pending` and their old rows in place. The next resume needs `--rerun-status` again, because flags are not persisted as intent. Not covered by a case.
- No case forces the replacement temp file to fail validation, the same gap I noted for `--rerow`.
- shellcheck is not installed on this host, so no lint was run.

## Handoff notes for the lead
1. Apply on the current HEAD (`git apply --check` passes at 19731570). Before resuming, confirm the `priority-p1` driver is gone: no `.lock` with a live pid, and no live `.jobs/*.pgid` process group. The runner refuses either.
2. The command, with the seven contaminated run_ids as rerows:
   ```
   evals/harness/run-ablation.sh --batch priority-p1 --resume --rerun-status transport_error \
     --rerow priority-p1-a1_full-review-02-t1 --rerow priority-p1-a1_full-bugfix-04-t1 \
     --rerow priority-p1-a4_no_gates-bugfix-04-t1 --rerow priority-p1-a4_no_gates-refactor-03-t1 \
     --rerow priority-p1-a1_full-refactor-04-t1 --rerow priority-p1-a1_full-review-01-t1 \
     --rerow priority-p1-a1_full-review-03-t1 --max-usd 799 --concurrency 3 --detach
   ```
   These are the seven `contaminated` rows in the lead's runs.jsonl as read today. Check them against your list.
3. **`--max-usd` on resume is the batch's total ceiling.** `spent` is rebuilt from every standing row, plus `ledger_usd` read from STATUS (the first attempts), plus new spend. The budget gate compares `spent + in_flight × 12 + est_next` against 799.
4. **`spent` right after reconciliation** should read about **USD 240.67**: ledger 21.70, plus completed 150.52, contaminated 56.35 (costs unchanged by the rerows) and cap_failure 12.10, plus the 67 transport rows' reported 0. `assumed_cap_trials` should be 0: the cap_failure's 12.10 is above the 12 cap, and no rerowed row has a zero cost. A rerowed row that ends non-completed with cost 0 would add one assumed charge, but none of the seven has a zero cost. This matches DEC-0552's 240.67. Headroom is about USD 558 for 80 launches: 67 reruns plus the 13 never launched, with indices 120 to 132 still unrowed.
5. The old `cuts[0]` is still in STATUS. If this resume ends with every trial rowed, it finishes complete or partial on exclusions as usual. If trials are left, the end state reads "partial (cut max_usd)" even without a new cut. That behaviour predates this patch.
6. The breaker is on by default at 3 during the resume, and the transport retry wait stays at 120 s. If the network fails again, the batch stops after three consecutive transport rows, and the same command, minus the `--rerow` ids already done, resumes it. Re-passing a `--rerow` id is also valid; it re-grades that run again.
7. Rerun dirs for the 67 outage trials will be `-r3` (the originals used the base dir and `-r2`), or `-r4` on a transport retry.
