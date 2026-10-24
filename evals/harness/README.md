# evals/harness

## Refusal policy

A Fable 5.1 review or audit session can refuse a PR whose code is security tooling, and Claude Code then continues the session on a fallback model (KF-051). Such a row is not the arm it claims to be. The suite key `refusal_policy` decides, per arm, what that row counts as (cycle-133 SDD C-8, PRD FR-8, bead bd-r9abp).

The key sits on an arm in `evals/suites/ablation-2.0.yaml` and takes one of three values. An arm without it runs `exclude`, which was cycle-132's behaviour.

| Policy | What happens to a refused trial | The row | The denominator |
|---|---|---|---|
| `exclude` | nothing more | invalid: `degraded`, reason `<phase>: refusal fallback` | excluded |
| `keep` | nothing more | valid and flagged: the fallback is not a degraded cause, `refusal_flagged: true` | included |
| `rerun-once` | relaunched once at the same plan index | the second attempt's row is the cell when it has no fallback | included when the second attempt is clean, else excluded |

Under `rerun-once`, the cell is invalid and both attempts stay recorded in three cases:

- **A second refusal.** The relaunch is never relaunched again.
- **An infrastructure failure on the retry.** This covers `transport_error`, `infrastructure_error` and `interrupted`.
- **No room for the relaunch.** The attempt limit of 3 (D-7.3) leaves none, so the row reads `rerun_not_run`.

**Recorded before execution.** `run-ablation.sh` checks every planned arm's value at pre-flight. An unknown value is refused with exit 2, and so is any policy but `exclude` on a `bare_sessions: matched` arm. Such an arm's refused session stays invalid inside its cell. The runner then writes `MANIFEST.json` `refusal_policy {<arm>: policy}` before any trial runs. At run time it reads the policy from the MANIFEST only, so a resumed batch keeps the policy it started with. A MANIFEST written before the key existed reads `exclude`.

**The relaunch.** The refused attempt's run directory is left untouched and never graded. Its record goes to `<batch>/<arm>/<task>-t<n>.refusal-1.json`, which is written once by a hard link and never rewritten. The relaunch runs into a fresh `-r<k>` directory under the same per-run cap. Both attempts are charged. The first attempt's spend goes to the batch's spent and ledger totals and into the row's `all_spend_usd`, and its attempts count in the row's `attempts`. A driver resumed after the first attempt finds the record and launches only the second.

One limit is accepted. The relaunch runs in its trial's slot without a second budget-gate check, so in the worst case a batch passes `--max-usd` by one run cap per refused trial in flight.

**The row fields.** `ablation-row.sh` row writer 1.6 writes these fields on every row:

- `refusal_policy_applied`: the arm's policy.
- `attempt`: 1, or 2 for the relaunch. This differs from `attempts`, which counts transport retries and re-runs.
- `refusal_attempts`: the refused first attempt `{attempt, run_dir, status, cost_usd, refusal_fallbacks}`, with the original and fallback model ids per phase.
- `refusal_outcome`: one of `none`, `excluded`, `kept`, `rerun_not_run`, `rerun_clean`, `rerun_refused`, `rerun_failed` or `sessions_excluded`. The last one marks a matched cell with a refused session.
- `refusal_denominator`: `included` or `excluded`.
- `refusal_flagged`: true on a kept row.

`refusal_denominator` is the refusal policy's verdict alone. Every other exclusion rule of the pre-registration still applies to the row.

**The rate.** `ablation-row.sh --refusal-rate runs.jsonl` prints, per arm, the rows, the refused rows and `refusal_rate = refused / rows`. A refused row is one whose `refusal_outcome` is not `none`, so a clean relaunch still counts as a refusal. Rows from before 1.6 count by their phase records. An arm above 0.2 is flagged with one stderr line.
