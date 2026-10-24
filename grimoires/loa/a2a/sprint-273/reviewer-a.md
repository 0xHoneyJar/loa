# Sprint 273 Task 2.1 (implementer A) — session library (SDD C-6, PRD FR-6; bd-wqaj4, bd-g2c5i)
Worktree `loa-wt-s2a` at 38640409e. Patch `~/.cache/loa/cycle-133/patches/s2-a.patch` (and the `.stat` beside it). Nothing committed.

## What was built
- **`evals/harness/lib/session-exec.sh`** holds the one copy of the mechanics; the header (:1-58) is the contract.
  - `ENV_SHIM` (:64) closes every fd above 2 listed in `/proc/self/fd`, except the listing handle and `LOA_KEEP_FDS` (comma-separated decimals, default empty; anything else exits 2). Without `/proc` it falls back to `closerange(3, hard RLIMIT_NOFILE)`, split around kept fds; an infinite, unreadable or ≤ 3 limit becomes 1048576.
  - `SECRET_KEY_PATTERN` (:109), `NON_SECRET_ALLOWLIST` (:110) and `assert_secret_keys` (:112) do the secrecy check.
  - `SESSION_METER_PY` (:129) is one `python3 -I` stdlib program behind `price_for` (:266), `price_events` (:288) and the new `unmetered_tail` (:292). On failure it prints `ERR`, returns 1 and writes one reason line to stderr. `price_events` output is unchanged.
- **`blind-session.sh`**: the secrecy assertion and the price check run before any write (:195-200), and a failure is exit 2. The watchdog (:328) and the final re-price (:348) stop the session on `ERR`, with status `metering_incomplete`, exit 1 (:484). `metering` is recorded in cost.json and the spend row.
- **`pipeline-run.sh`**: the inline copies are removed. It runs `source ./lib/session-exec.sh` after the mount library, then `assert_secret_keys` (:559-568). Every planned phase model is priced before the first launch (:1190). An `ERR` from `price_for`, the watchdog or the final re-price stops the run as `infrastructure_error` 2, reason `metering_incomplete: …` (:984, :999, :1150). Each phase record gets a `metering` field.
- **`tools/check-no-swallowed-jq.sh`**: default mode also walks `evals/harness/lib/*` (:282).

## Tests
- **New `evals/tests/session-exec.bats`: 25 cases.**
  - SE-1…6 cover `price_for`: derivation, malformed table, missing model, 12 bad-price vectors, zero price, pricing.py known and unknown alias.
  - SE-7…16 cover `price_events` and `unmetered_tail`: output contract, parse failure vs partial tail, 8 invalid-token vectors, usage-less completed vs in-flight turn, streaming snapshots and stream_event deltas, cache rates, interrupted turn, refusal rerun, bad prices, budget or file.
  - SE-17…22 cover `ENV_SHIM`: a fd above a lowered soft limit (with a no-shim control), `LOA_KEEP_FDS`, fd 70000 in a subprocess (SE-20), and the simulated fallbacks and listing. SE-20 runs natively when the hard limit allows, else in `loa-ablation:258 --ulimit nofile=200000 --network none`, else it skips with the reason.
  - SE-23 is the pattern unit vector, SE-24 the assertion, SE-25 the scanner lib walk.
- **`blind-session.bats`: 11 → 15.**
  - BS-8 is the drift guard, now a one-copy guard. Callers must source the lib literally, and any inline copy must equal the lib byte for byte.
  - BS-12 refuses an invalid price: exit 2, no CLI call, no out dir, no row; a zero price launches.
  - BS-13 kills a hanging session in under 15 s.
  - BS-14 covers an unmetered attempt, BS-15 the assertion.
- **`pipeline-run.bats`: +7 (PR-c133-1…7).** They cover the literal source and a missing lib, pre-launch refusals with no CLI call, the watchdog stop, an invalid count after a phase, zero prices, an unmetered_attempt record and the assertion. `make_harness` stages the lib.
- **Red → green.**
  - Before (`/tmp/s2a/red.txt`): 18 of 25 SE cases were red. SE-20 showed `70000` reaching the child through the old `closerange(3, 65536)`, and SE-1 got jq's `0.30000000000000004`. All of PR-c133-1…7 were red, and BS-8 stayed red until pipeline-run switched to the lib.
  - After: the 4 affected files pass 152 of 152 (116 baseline + 36 new).
  - Full `evals/tests/*.bats` plus the 4 scanner suites pass 771 of 773, with no skips. The two failures are outside this diff: `analysis-c132` AC-1 pins 129 tests but 176 run (since cc2d5a697), and `manifest-v2` MV-1 compares against the moving `main`.
- **Real data.** I ran the old jq and the new `price_events` over 1,601 transcripts in the lead's `evals/results` and `reports`.
  - 1,565 are byte-identical and 0 differ.
  - The 36 `ERR`s are all stub transcripts under `*/sandbox/.eval/tmp/`, written by agents' own bats runs.
  - Every real assistant event carries integer usage, and repeated events of one message id carry identical usage.

## Acceptance criteria
- **Met: the sentinel** fires for every condition, and zero prices pass (SE-2…5, 8…10, 15, BS-12, PR-c133-5).
- **Met: metering rules** for streaming, cache, interrupted, retries and `unmetered_attempt` (SE-11…14, 16, BS-14, PR-c133-6).
- **Met: `assert_secret_keys`** with the documented pattern and allowlist (SE-23, 24, BS-15, PR-c133-7).
- **Met: `ENV_SHIM`** with `/proc` enumeration, `LOA_KEEP_FDS`, both fallbacks and a fd above 65535 (SE-18…22). SE-20 ran here in the container. A runner without docker and with a hard limit ≤ 65536 skips it, but SE-22 still covers the logic.
- **Met: callers** refuse or stop on `ERR` (BS-12, 13, PR-c133-2…4). pipeline-run sources the lib by literal path and its harness stages `lib/`.
- **Met: the drift test stays** (BS-8), and blind-session and pipeline-run bats are green with one copy.
- **Met: the scanner covers `evals/harness/lib/`** (SE-25; SW-10 green).

## Judgment calls
- **Streaming merge.** Snapshots of one message id merge by the largest count per field, not a sum. Claude Code repeats usage per content block and API `message_delta` usage is cumulative, so a sum double-counts. Real data matches the old last-wins rule.
- **"Completed" turn.** A turn is completed once any later event, or the result, follows it; only the tail is in flight. `stop_reason` was rejected as the marker: it is null on almost every real event.
- **Absent or null token counter = 0.** That is the old `// 0`, and the API historically sent null for "no cache". Anything present must be a non-negative JSON integer. A usage object with no token field is `ERR`.
- **Partial last line.** Only a last line without a newline is skipped. Any other unparseable line is `ERR`; the old silent `fromjson?` was rejected.
- **`unmetered_attempt`.** It means activity (init, thinking, an assistant or stream event), no usage event at all, and no numeric result cost. It is stored as a `metering` field on the existing rows (cost.json, the spend row, the phase record). A new row kind was rejected because spend.sh and ablation-row.sh read those rows as they are.
- **Refusal rerun pricing.** Rerun turns price at the session model, not per `message.model`, which would need a second lookup in the watchdog. Fable to Opus goes to a cheaper model, so the estimate stays conservative, and the result cost stays authoritative.
- **Python for the meter, not jq.** jq cannot tell integer from float or partial from complete lines, and it printed `0.30000000000000004`. Rounding is half-up, like jq `round`.
- **Cache prices.** An absent cache price derives (0.1×, 1.25×). One present as null is `ERR` (C-6: "any of … null").
- **pipeline-run pre-launch check.** It prices every planned phase model, FIX included (FR-6 "coverage validated before launch"). The dry run is unchanged because it launches nothing.
- **pipeline-run exit code.** A metering stop exits 2, the script's existing `infrastructure_error` code, mid-phase too, so a run has one infrastructure code. §5.4's "before any write" fits only the pre-launch case. blind-session uses 2 before launch and 1 for a live stop.
- **`LOA_KEEP_FDS`.** Only the shim reads it, so the child sees it only if named. A malformed list exits 2 instead of being ignored.
- **The 65535 test.** The hard limit is 4096 here and 65536 on GitHub runners. So SE-20 runs native, then in a container, then skips with the reason, and SE-22 covers the logic simulated.
- **Drift test kept as a one-copy guard.** The verbatim comparison stays and a single copy is now required. As written it would fail forever once one copy exists. Task 3.6 deletes it.
- **Default transcripts.** blind-session.bats gives its default and helper transcripts zero-token usage. Editing claude-stub.sh, which other suites share, was rejected: its canned transcript has no usage.
- **Scanner glob.** The scanner walks `evals/harness/lib/*` by glob, like red-team-*, so new lib files are enforced.

## What the lead must do
- **Three edits are outside my ownership.** Each is needed to keep a suite green.
  - A trailing `# check-no-swallowed-jq: ok (…)` marker on `evals/harness/lib/arms-common.sh:67` and `evals/harness/lib/sandbox-mount.sh:379`. Without it SW-10 and SE-25 go red once the lib is walked. The sandbox-mount site fails closed; the arms-common one is classification-only, pending #1025.
  - One `cp …/lib/session-exec.sh` line in `evals/tests/ablation-grade.bats` AG-18 and in `evals/tests/fixtures/ablation-runs/regen.sh`. Both stage a pipeline-run harness, and AG-18 fails without the line. C may touch ablation-grade.bats; the insert rebases trivially.
- **Rebase notes for C and D.**
  - pipeline-run.sh: the inline mechanics are gone and the lib is sourced after the mount library. New code: the `run_phase` pricing/watchdog block, the `metering` phase field, the metering stop after the interrupt check, and the pre-launch price loop.
  - blind-session.sh: the price check moved before `mkdir -p "$OUT"`, and the watchdog loop changed.
- **Fixture regeneration.** The `ablation-runs` fixtures predate the `metering` field and nothing reads it yet. Regenerate them at Task 2.5, not now.
- **No `.claude/` file changed**, so there is no checksum or REPO-MAP regeneration. CHANGELOG, NOTES and the DEC rows are yours.
