# s2-e — Sprint 273 Task 2.4b: the batch supervisor (SDD C-9 supervisor half, D-2.5; FR-9; bd-yvjew, KF-052)

**Patch base.** `147b179bb` with `patches/s2-c.patch` applied (C's refusal-policy block is in my base tree). `s2-e.patch` is the diff from that tree, so it applies cleanly after C lands. It does not apply to bare `147b179bb`, because write_manifest's context includes C's `refusal_policy:` line.

## What was built
- **`evals/harness/lib/batch-supervisor.sh`** (new). The header is the contract. Its subcommands are `launch`, `restore`, `stop`, `status` and `run` (the internal loop).
  - `linger_ok` :125 checks the linger precondition and refuses with exit 2 before any write.
  - `take_lock` :138 takes flock on `supervisor.lock` (fd 9), inherited across setsid. The runner gets `9>&-`.
  - `daemonise` :164 uses systemd-run --user --unit loa-batch-<name> --collect, else setsid.
  - `ident_alive` :89 checks durable identity: boot id plus /proc start ticks.
  - `watch` :360 detects exit, a hang or a stop request.
  - `classify` :321 sorts the exit into a retry class.
  - `uncertain_runs` :189, `reclaim` :238, `stop_containers` :217 and `reconcile` :255 run before every resume.
  - `cmd_run` :382 is the loop and the retry cap. `cmd_restore` :492 handles reboot or a lost supervisor. `cmd_stop` :526 is the cancellation.
  - State lives in `supervisor/state.json` and is mirrored to STATUS.json `supervisor` under `flock STATUS.json.lock`.
- **`evals/harness/run-ablation.sh`**
  - header :19, :95–104.
  - parse :414, :461–462.
  - usage checks :535–537. They sit at the argument validation because `--detach` re-execs at :612, before the block.
  - the contiguous block :792–811, directly after C's `refusal_collect`. It execs `batch-supervisor.sh launch`.
  - write_manifest :1258 plus one jq field: MANIFEST `supervisor` gets the args.
  - write_status :1508 keeps `.supervisor` under the status flock.
  - .gitignore :1425.
- **`evals/tests/batch-supervisor.bats`** (new, 13 cases).

## Tests
The first run was red: 13 of 13 `not ok` (the lib was absent). The second run was red on 4 of 13, and those failures were real bugs. `basename | tr` turned the trailing newline into a dash, which broke the container prefix and the unit name (BSV-8, 11, 13). `--detach` ran before the exclusivity check (BSV-12). Both are fixed. The suite is now 13/13 green, `npx --no-install bats evals/tests/batch-supervisor.bats`.
- BSV-1 killed driver resumed once with retry id. BSV-2 second owner refused. BSV-3 linger (no, absent loginctl, yes). BSV-4 retry cap leads to gave_up. BSV-5 six non-retryable classes. BSV-6 infrastructure_error rerun-status. BSV-7 hang. BSV-8 cancellation mid-request. BSV-9 reboot with PID reuse. BSV-10 same-boot PID reuse. BSV-11 systemd-run argv and unit.
- BSV-12 run-ablation usage and the linger refusal.
- BSV-13 is end to end with the real run-ablation.sh. The driver is SIGKILLed while one pipeline is mid-request. The orphan group is killed, only the batch's container is removed, and `req-inflight` is recorded. The batch resumes once and every run_id is rowed exactly once.
- Every evals suite: all 33 `evals/tests/*.bats` files: 768 ok, 0 not ok, run serially per file. This includes run-ablation.bats (59), refusal-policy.bats (12) and pipeline-run.bats (99) with my write_status/write_manifest edits.
- Lints: check-no-swallowed-jq, check-no-raw-sha256sum and check-knob-readers pass in default mode. `--root evals/harness` hits only pre-existing lines. shellcheck is not installed on this host.

## Acceptance criteria (Task 2.4 supervisor part; FR-9 AC-1)
All are Met:
- linger: BSV-3, BSV-12.
- systemd-run or setsid: BSV-11.
- lock held across daemonisation: BSV-2.
- durable identity: BSV-1, 8, 9, 10, 13.
- 30-min hang: BSV-7.
- retry classes: BSV-5, 6.
- groups and containers stopped before resume: BSV-8, 13.
- args persisted for reboot: BSV-13, BSV-9.
- STATUS supervisor entry: BSV-1, 13.
- every listed bats case: BSV-1 to BSV-13.

The egress half belongs to D2.

## Judgment calls
- **Base.** I built on 147b179bb with s2-c applied, so my block sits below `refusal_collect` and rebases cleanly once C lands. Rejected: a bare-147b179bb patch (conflicts at the anchor).
- **Hang signal.** A hang is any batch file at depth ≤ 4 unchanged for 30 min (STATUS.json, run.log, the trial logs, the transcripts' event streams), not STATUS.json alone. The runner rewrites STATUS only once per trial, and a trial's watchdog runs for hours, so a STATUS-only rule would kill healthy trials. Rejected: STATUS-only; a heartbeat in the runner (more runner edits).
- **Run-argument persistence.** `supervisor/args.json` is written by every launch and copied into MANIFEST.json `supervisor` by write_manifest at a fresh start. Restore prefers args.json, the latest launch, and falls back to the MANIFEST. Rejected: the supervisor rewriting MANIFEST after the runner wrote it (an evidence record); an environment hand-off (flags over env vars).
- **Resume argv.** `--resume --batch <name>` plus the launch's --results-root, --smoke, --max-usd, --concurrency, --self-check-log and the --*-bin flags; the MANIFEST supplies everything else. Rejected: replaying the whole argv, which the resume path rejects (--registration and --allow-partial conflicts).
- **Retry classes.** The SDD's two retryable classes are split into named ones. Retried: driver_lost (the process died, or was signalled from outside, with STATUS not final; this covers KF-052's tool-timeout SIGTERM), hang, infrastructure_error (rows of that status or interrupted, resumed with --rerun-status) and incomplete. Never retried: refusal (exit 2), failed (exit 3), budget, outage, metering_incomplete, paused_arm and intentional_stop. The outage breaker is not retried because its own message asks for a resume once the network is back, and an immediate retry would trip it again.
- **Status lock.** A new `STATUS.json.lock` flock is taken by both writers, because the runner had no STATUS flock (only the `.lock` mkdir and the rows flock). Rejected: reusing `$ROWS.lock`, because the rows file is shared across batches (the tracked runs.jsonl).
- **Lingering scope.** I read the SDD's "lingering scope" as a system.slice cgroup, and an absent loginctl is refused. Rejected: INVOCATION_ID, since a user unit without linger still dies at logout; silently accepting hosts without logind.
- **systemd handover.** A flock cannot pass into a transient unit. The launcher writes state `launching` with the attempt id; the unit waits up to 120 s on flock and checks that the attempt id is its own. A second launcher inside that window is refused by the launching record (same boot, under 120 s old).
- **systemd environment.** The unit gets PATH, HOME and the LOA_*/EVAL_* variables whose names do not match KEY, TOKEN, SECRET, PASSWORD or CREDENTIAL, because unit environment is visible in `systemctl show`.
- **Reconciling uncertain requests.** This is recording, not repair. The run dirs whose pipeline.json was missing or running at death are snapshotted before anything is killed, and their cost-ledger request ids and micro-USD go into the retry entry. The runner's resume already charges those trials their cap. An in-flight request with no ledger row yet shows up as its run in uncertain_runs. No provider-side lookup is possible offline.
- **PID reuse.** After a reboot (boot id changed) nothing recorded is signalled, and the stale `.lock/` and `.jobs/` are removed. On the same boot the runner group is killed only when its start ticks match, and live `.jobs` groups are killed (pgid reuse within one boot was judged negligible, and the runner already refuses to start while they live).
- **Episodes.** `launch` starts a new episode: the prior record moves into history[] and retries reset. `restore` continues the episode, so the cap counts across a reboot, and it refuses a record that is not running. There is no automatic restore at boot, because a transient unit does not survive a reboot; restore is one documented command. Rejected: installing a persistent user unit, which writes into the user's systemd config.
- **--max-retries** takes 0 to 9 with a default of 3, matching --concurrency's single digit.
- **Exclusivity.** --supervised is exclusive with --detach and --dry-run. The checks sit with the argument validation because --detach re-execs before the block.
- **Containers.** `docker rm -f` of `loa-abl-<batch>-*` covers every `loa-abl-<run_id>-*` of the batch, since run ids start with the batch name. The supervisor also applies its own exact-prefix match, because docker's name filter is a substring regex (b1 would match b10).
- **Exit codes.** `run` exits 0 complete, 1 halted, gave_up or stopped, 2 refused. `launch` and `restore` exit 0 or 2. These follow § 5.4.
- **Test knobs.** The tests use environment overrides LOA_SUPERVISOR_{POLL_S,HANG_S,GRACE_S,MODE,LOGINCTL,BOOT_ID_FILE}, with the precedent LOA_ABLATION_WATCHDOG_S.

## What the lead must do
- Apply after s2-c. My hunks touch C's write_manifest neighbourhood and sit right after `refusal_collect`. If C's patch changes before landing, regenerate by re-applying my files over C's result. Only run-ablation.sh hunks would need a manual merge.
- Lines outside the one block, all needed. The parse case (2 lines) and its init. Three usage checks at the argument validation, because `--detach` re-execs earlier. Header docs. write_manifest (+5 lines and one jq field). write_status (the flock merge). The .gitignore list.
- `grimoires/loa/a2a/sprint-273/reviewer-e.md` is gitignored (`grimoires/loa/a2a/*`). It is written in the worktree but is not in the patch. Force-add it if wanted.
- This host has Linger=no and no systemd-run. A live `--supervised` batch here needs `loginctl enable-linger merlin` first, and it will run in setsid mode.
- README § batch operations and the CHANGELOG are yours (shared files). The lib header is the contract to cite.
