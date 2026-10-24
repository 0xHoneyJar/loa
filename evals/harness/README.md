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

## Pipeline version (cycle-133 Sprint 273 pin)

The intermediate pipeline version after Sprint 273 (sdd.md § 7.3; sprint.md Task 2.5) is **the commit that lands this
section** — recorded with its tree hash in `grimoires/loa/decisions.yaml` (DEC-0906) and named by the Sprint 274 smoke
and by `evals/analysis/c132/reproduce.sh --pin` for runs made at it. Later docs-only commits do not invalidate it; a
change under `evals/harness`, `evals/suites`, `evals/graders`, `evals/fixtures` or `evals/analysis` does.

| Component | Value |
|---|---|
| sandbox image | `loa-ablation:259` — `sha256:61e88d02d78519f3ecf20fc3bc162cc1b7a56cd927673ce9d94a7fdb78246dbb` (built from `evals/harness/Dockerfile.ablation` on 2026-10-24) |
| proxy image | `loa-egress-proxy:259` — `sha256:10fc90b6e85ace444896ed01985a1c6c04b57c1cd8f162f99558a60151bba274` (`evals/harness/Dockerfile.proxy`) |
| Claude Code in the image | `2.1.299` (label `org.loa.claude_code_version`, `/etc/loa-claude-code-version`) |
| grader | 1.4.0 (`ablation-grade.sh`) · row writer 1.6 (`ablation-row.sh`) · session library `lib/session-exec.sh` (one copy) |
| egress block | `lib/egress-proxy.sh` + the suite's `egress` key (every arm `blocked`); allowlist from `.claude/defaults/model-config.yaml` `egress_hosts[]` (10 hosts for the default providers and region) |
| self-check | `grimoires/loa/reports/ablation-2.0/self-check-c133.txt` — 49 checks PASS, 0 FAIL: a CONNECT probe per allowlisted host (no credential, no completion token) and every denial case, attribution and the sidecar's netfilter, run on 2026-10-24 against the two images above |
| egress suite | `evals/tests/egress-proxy.bats` EP-1 … 8, EGR-1 … 12 — 20/20 on this host (`~/.cache/loa/cycle-133/tests/s2d2-egress-bats.log`); the release gate for the Sprint 274 smoke |
| supervisor | `lib/batch-supervisor.sh` (`run-ablation.sh --supervised`) |

A live batch at this pin: `egress-proxy.sh allowlist > hosts; egress-proxy.sh up <batch> hosts; egress-proxy.sh
self-check <batch> --image loa-ablation:259; LOA_EVAL_EGRESS_NETWORK=loa-egress-<batch> run-ablation.sh … --image
loa-ablation:259 [--supervised]`; `egress-proxy.sh down <batch> --log-dir <dir>` afterwards. Sprint 274 Task 3.4
completes this README (mount modes, the egress threat model, batch operations, exit codes).
