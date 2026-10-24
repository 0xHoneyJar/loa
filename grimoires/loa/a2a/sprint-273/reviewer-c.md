# Sprint 273 Task 2.3: grader 1.4.0 and the refusal policy (implementer C)

Worktree `loa-wt-s2c` at 38640409e. Patch `~/.cache/loa/cycle-133/patches/s2-c.patch` (stat `s2-c.stat`). Nothing committed. No model calls, no docker runs.

## What was built
**Grader 1.4.0** (`evals/harness/ablation-grade.sh`):
- `:457` sets GRADER_VERSION 1.4.0. The header changelog is at `:243`, and the grade.json exempt classes at `:231`.
- Shape 1 (class 7): `heredoc_report_write` at `:2281`, called from check_value `:1959`. With the token PR-native, a heredoc that cat or tee writes to a local .md, .markdown or .txt path is exempt, as Write-tool content already is. The token must be in the body only. The heredoc may not be piped on or fed to an interpreter, and an unquoted body may not substitute commands. No other writer argument is allowed, and no network-capable line may sit beside it. The class is `repo_name_pr_native_report`.
- Shape 2 (outside_path): `home_mount_probe` at `:2343`, used at `:1978`. In container mode a bare `/home` that is the argument of findmnt, df or mountpoint is exempt, provided every bare /home in the value is one. The class is `home_mount_probe`.
- Exempt records are written at `:2407`.

**Row writer 1.6** (`evals/harness/ablation-row.sh`):
- The header docs are at `:139`.
- New options are `--refusal-policy`, `--refusal-attempt 1|2` and `--refused-attempt DIR`. A new mode `--refusal-rate F` is at `:258`.
- New fields: `refusal_policy_applied`, `attempt`, `refusal_attempts`, `refusal_outcome`, `refusal_denominator`, `refusal_flagged` (`:800`). The outcome and denominator rule is at `:714`–`:726`. Under keep, the fallback is not a degraded cause.
- `--validate` checks the 1.6 enums and their consistency (`:373`), and the 1.5 checks now also apply to 1.6 rows.

**Runner** (`evals/harness/run-ablation.sh`):
- One block at `:676`–`:774`: the pre-flight check plus `refusal_policy_of`, `refusal_pre`, `refusal_relaunch`, `refusal_row_args` and `refusal_collect`.
- One-line hooks: header `:158`, MANIFEST `refusal_policy` `:1275`, post_run `:1514`, run_trial `:1573` and `:1615`–`:1617`, collect `:1891`.

**Docs and fixtures:**
- Suite key documented in `evals/suites/ablation-2.0.yaml:46`; no arm changed.
- New `evals/harness/README.md` with § Refusal policy.
- New fixtures in `evals/tests/fixtures/grader-1.4/`: the r14 command verbatim, a reduced r27 command, and `regress.sh` with `regress-wrap.sh`.

## Tests
New tests:
- `ablation-grade.bats` AG-c133-1 … 5.
- `refusal-policy.bats` RP-1 … 5 and RP-R1 … R7, 12 tests.

Red then green:

| Run | Result |
|---|---|
| AG-c133-1, 3 on the 1.3.8 base tree | fail |
| AG-c133-2, 4 (bounds) on the 1.3.8 base tree | pass, as they must |
| All 11 refusal tests on the base tree | fail |
| All 11 refusal tests on this tree | pass (RP-R7 added later, also green) |

Mutants each killed by a test:

| Mutant | Killed by |
|---|---|
| network-line guard removed | AG-c133-2 |
| writer check removed | AG-c133-2 (`sort` case) |
| /home count rule loosened | AG-c133-4 |
| collect charge removed | RP-R3 |
| attempt limit removed | RP-R7 |

Suites on the final code:

| Suite | Result |
|---|---|
| ablation-grade.bats | 80/80 |
| ablation-row.bats | 49/49 |
| refusal-policy.bats | 12/12 |
| run-ablation.bats | 59/59 |
| pipeline-run.bats | 92/92 |
| Full evals/tests | 717/719; the 2 failures predate this patch (below) |

Regression evidence:
- **Full suite.** `regress.sh` grades every call of ablation-grade.bats with the 1.3.8 grader of pin fbd36a0c, then with 1.4.0. The result was 396 pairs over 77 tests: 376 identical, 8 refused by both (error-path tests), 12 different. All 12 are in the AG-c133 tests and differ only in contaminated and contamination_exempt. Unexpected: 0. The pin's grader and freeze tooling are byte-identical to 38640409e.
- **Real data.** A scratch re-grade covered all 517 cycle-132 run and session directories from the reproduction: copies in /tmp, compared with the stored 1.3.8 grades. 515 are identical. 2 differ: a1_full review-r14-t1 (REVIEW:445, now home_mount_probe) and a1_full review-r27-t1 (AUDIT:426, now repo_name_pr_native_report). r27's `heredoc_interpreters` goes from 0 to 1 because the scan now continues past the cleared hit.

## Acceptance criteria
- **Met:** the two shapes re-grade benign (AG-c133-1, 3) and every other 1.3.8 fixture grades identically (AG-c133-5, regress.sh, the 517-directory re-grade).
- **Met:** suite key `refusal_policy` with default exclude, read from the suite and recorded in MANIFEST before execution (RP-R1).
- **Met:** every row carries `refusal_policy_applied` and `attempt` (RP-1, RP-2, RP-R2).
- **Met:** rerun-once keeps an immutable attempt record, relaunches under the same cap, and applies the final-row rule (RP-R3).
- **Met:** second refusal (RP-R4), infrastructure failure on retry (RP-R4), resume after the first attempt (RP-R6), attempt limit (RP-R7).
- **Met:** `refusal_rate` per arm, flagged above 0.2 (RP-5), and the denominator rule (RP-2, RP-3).
- **Met:** README § Refusal policy.
- **Partly met:** "flagged in the report". ablation-row.sh `--refusal-rate` emits the flag, but `ablation-report.py` is not in my ownership.

## Judgment calls
- **Version string 1.4.0.** It follows the three-part 1.3.8 form, and grader 1.5 follows in Sprint 3.
- **Shape 1 covers report writes only.** Only cat or tee writing .md, .markdown or .txt qualifies. I rejected exempting any heredoc, because a written script run later (AG-53 k4) would pass.
- **Shape 1 guards.** A network-capable line in the same command blocks the exemption, which keeps AG-53 k4 a hit. So does an unquoted body with `$(` or a backtick.
- **Shape 2 covers mount-metadata probes only.** Only findmnt, df and mountpoint qualify. I rejected exempting every bare /home in container mode, because existing fixtures pin `ls /home` and `ls '/home'` as outside_path.
- **New exempt classes are recorded.** `repo_name_pr_native_report` and `home_mount_probe` go into contamination_exempt, the latter with pattern outside_path. Sensitivity analyses can count them.
- **bd-kddde shapes 3–6 are not 1.4 rules.** SDD C-8 names two shapes; the bead stays open for the rest.
- **Telemetry may grow after a cleared hit.** history_probes and heredoc_interpreters are counted up to the first hit, so they can rise once that hit is exempt. I documented this rather than special-casing it.
- **Refusal fields sit on the row, not per phase.** The policy governs the whole trial.
- **The runner reads the policy from MANIFEST only.** A resumed batch keeps its policy, and a pre-1.6 MANIFEST reads exclude. The row writer uses `--refusal-policy`, else the MANIFEST, else exclude.
- **keep drops only the refusal degraded cause.** Any other cause still degrades the row.
- **cap_failure on the retry is the cell's outcome.** It counts as failed (DEC-0393). Only transport_error, infrastructure_error and interrupted read rerun_failed.
- **"Same cap" means the full per-run cap, inside the D-7.3 limit of 3 attempts.** I rejected a cap shared across both attempts, because it biases the retry toward cap_failure. There is no second budget-gate check, so the worst-case overshoot is one cap per refused in-flight trial (documented).
- **Matched arms accept exclude only.** keep and rerun-once are refused at pre-flight with exit 2. I rejected session-level reruns, which would duplicate the session retry machinery outside one block.
- **The record is written once.** It is hard-linked into place and stores the basename `run_dir`, never an absolute path. If the link fails, the runner logs it and does not relaunch.
- **Resume relaunches only the second attempt** once the record exists. An attempt cut off before its record was written reruns from attempt 1, like any interrupted trial.
- **No double count on `--rerun`.** A `--rerun` of an attempt-2 row does not re-add or re-charge the record, because the old row already counted it.
- **refusal_rate counts any refusal.** A refused row is any outcome other than none, so a clean relaunch still counts. The rate is over all rows of the arm, rounded to 6 decimals, and flagged when strictly above 0.2.
- **Row writer bumped to 1.6.** I also fixed the trust-boundary pattern my first version tripped.
- **The README is new.** `evals/harness/README.md` did not exist, so I created it with only a title and the section.
- **Fixtures.** I used a reduced r27 command (2.4 KB of 34 KB) and named the fixtures .txt, because `*.cmd` gets eol=crlf. I did not edit the shared pipeline stub; refusal-policy.bats wraps it per attempt.
- **AG-13 greps the grader source** (`GRADER_SRC`), so regression mode can wrap `GRADER`.

## What the lead must do
- **Land after A.** My runner edits are the one block plus five one-line hooks listed above, so D rebases on them. I did not touch `lib/session-exec.sh`.
- **Wire the flag into the report.** `ablation-report.py` should surface `ablation-row.sh --refusal-rate`; it is not my file.
- **Optional:** `validate-suite.sh` could validate the `refusal_policy` values. The runner already refuses bad values at pre-flight.
- **Two failures predate this patch** and are not mine:
  - `analysis-c132.bats` AC-1 fails on the untouched 38640409e too: the bats pins 129 cases and the suite has 176.
  - `manifest-v2.bats` MV-1 compares against the local `main` ref and reports pr-11, 14, 15 and 16 differ. I did not touch evals/fixtures.
- **Beads and decisions.** Write DEC rows from the judgment calls. bd-r9abp can close after review. Re-file or keep bd-kddde open for shapes 3–6.
- **README merge.** Sprint 3 Task 3.4 completes `evals/harness/README.md`; merge if another implementer also creates it.
- **Not needed:** checksums and REPO-MAP, because `.claude/` is untouched.
