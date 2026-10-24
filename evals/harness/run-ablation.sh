#!/usr/bin/env bash
# =============================================================================
# run-ablation.sh — the cycle-130 ablation batch runner (SDD §5.9, §3.4; sprint Task 3.2;
# DEC-0405, DEC-0407, DEC-0413, DEC-0417, DEC-0418, DEC-0428, DEC-0429, DEC-0435, DEC-0545,
# DEC-0553, DEC-0554, DEC-0567)
#
# Plans a batch (arm × applicable task × trial), dispatches every trial to
# pipeline-run.sh against a pinned source tree, checks after each trial that the arm
# took effect and that the CLI version and model ids did not drift, grades the run,
# writes its runs.jsonl row, and keeps MANIFEST.json and STATUS.json for the batch.
#
# Usage:
#   run-ablation.sh --arms CSV --source-commit SHA [--tasks CSV] [--types CSV]
#                   [--trials-build N] [--trials-review N] [--max-usd USD] [--run-cap USD]
#                   [--concurrency 3] [--batch NAME] [--results-root DIR] [--rows F]
#                   [--suite-root DIR] [--suite-file F] [--image IMG] [--executor container|host]
#                   [--pre-registration-ref TEXT] [--seed N] [--self-check-log F]
#                   [--registration F] [--spend-since TS] [--batch-context ID]
#                   [--smoke] [--dry-run] [--resume] [--detach] [--allow-partial] [--clear-arm ID]...
#                   [--clear-drift] [--rerow RUN_ID]... [--rerun RUN_ID]... [--rerun-status S]...
#                   [--pipeline-bin P] [--grade-bin G] [--row-bin R] [--took-effect-bin T]
#                   [--docker-bin D] [--spend-bin S]
#
# Options:
#   --arms CSV           arm ids in the order given (default: the suite's priority minus
#                        every arm declared absent: true); each must be declared
#   --source-commit SHA  the Loa commit the arms run (the pinned source tree)
#   --tasks CSV          task ids (default: every <suite-root>/tasks/<id>/task.yaml;
#                        --smoke: every smoke/<id>/)
#   --types CSV          keep tasks of these types (feature-build, bug-fix, refactor,
#                        review-catch; `build` = the three build types)
#   --trials-build N     trials per build task (default the suite's trials.build; --smoke 1)
#   --trials-review N    trials per review-catch task (default trials.review-catch; --smoke 1)
#   --max-usd USD        batch spend cap (see Spend); no cap when absent
#   --run-cap USD        the single-cap override: one per-run cap for both task kinds (see
#                        Run caps). Without it each kind takes the suite's
#                        caps.run_usd_by_type[<kind>], else evals.ablation.run_cap_usd in
#                        .loa.config.yaml, else the suite's caps.run_usd, else 12. Ignored
#                        (with a stderr note) on --resume: a batch keeps its MANIFEST caps
#   --concurrency N      trials at once, 1-9 (default 3)
#   --batch NAME         batch directory name (default batch-<UTC ts>; --smoke smoke-<UTC ts>;
#                        the smoke- prefix is reserved for --smoke)
#   --results-root DIR   where batch directories live (default
#                        grimoires/loa/reports/ablation-2.0/batches; --smoke
#                        evals/results/ablation-2.0)
#   --rows F             the rows file (default: --smoke <batch>/rows.jsonl; otherwise
#                        grimoires/loa/reports/ablation-2.0/runs.jsonl, the tracked file, or
#                        <results-root>/runs.jsonl when --results-root is given). A smoke
#                        batch never writes the tracked file (DEC-0428: smoke rows decide nothing)
#   --suite-root DIR     suite root (default grimoires/loa/evals/ablation-2.0)
#   --suite-file F       suite file (default evals/suites/ablation-2.0.yaml)
#   --image IMG          container image (default loa-ablation:258)
#   --executor MODE      container (default) or host; passed to pipeline-run.sh and the grader
#                        (host grading needs LOA_EVAL_ALLOW_HOST_GRADING=1, see ablation-grade.sh)
#   --pre-registration-ref TEXT  the NOTES pre-registration heading and timestamp (MANIFEST)
#   --registration F     (cycle-132 FR-7, SDD D-5.2, D-7.2) the batch's REGISTRATION.json (JCS-canonical,
#                        evals/analysis/c132/registration.py): a JSON object with schema_version 1.
#                        Pre-flight refuses (exit 2) when a hash it binds differs from this batch's:
#                        suite_manifest_sha256 (the suite root's MANIFEST.sha256), corpus_sha256sums_sha256
#                        (evals/fixtures/review-prs/SHA256SUMS), pin (the --source-commit, a prefix
#                        match), image_digest (when the registration names one). MANIFEST.json gains
#                        registration_sha256 (sha256 of the file's bytes), registration_path,
#                        preregistration_sha256 and registration {the bound input hashes, pin,
#                        image_digest, cap_usd, kickoff, supersedes}. --resume recomputes the file's
#                        sha256 and exits 2 (`registration changed: <old> ≠ <new>`) when it differs, the file
#                        is gone, or another --registration is given; a batch started without one never
#                        gains one on resume
#   --spend-since TS     (cycle-132 Task 1.7c, the spend gate) with --registration: the cycle meter's kickoff
#                        (default: the registration's kickoff); a fresh batch's --max-usd is then derived at
#                        launch as cap_usd − (spend.sh --since TS --json).total_usd, the smaller of that and
#                        a given --max-usd; MANIFEST spend_gate {cap_usd, since, cycle_spent_usd,
#                        derived_max_usd, max_usd_given, max_usd}. Refused (exit 2): no kickoff, spend.sh
#                        failing or INCOMPLETE, or a derived cap ≤ 0. --resume keeps the MANIFEST max_usd
#   --batch-context ID   (cycle-132 bd-st02i) passed to every pipeline-run.sh as --batch-context ID
#                        (default: the batch name; --resume: the MANIFEST's batch_context); the
#                        eval_only arms' context, recorded in each run's arm-evidence and MANIFEST
#                        batch_context. The LOA_ABLATION_BATCH_CONTEXT variable is no longer set
#   --seed N             shuffle seed (default 20261015)
#   --self-check-log F   the recorded image self-check (default
#                        grimoires/loa/a2a/sprint-259/self-check-image.log)
#   --smoke              smoke batch: smoke/ tasks, one trial each, no hard gate, own rows
#   --dry-run            run the pre-flight, print the plan, write MANIFEST.json only
#                        (MANIFEST.dry-run.json when the batch already has a STATUS.json)
#   --resume             continue --batch NAME from its MANIFEST.json, STATUS.json and rows
#   --allow-partial      (cycle-131 FR-3 a, DEC-0617) the suite root may hold fewer than four
#                        tasks per type: passed to the freeze check (freeze.sh → validate-suite.sh
#                        --allow-partial relaxes exactly that count; schema, leakage and hash
#                        checks stand) and to every grader call (ablation-grade.sh … --allow-partial);
#                        recorded as MANIFEST.json allow_partial true|false. --resume takes the
#                        batch's value from its MANIFEST (absent = false); --allow-partial on a
#                        resume of a batch that started without it is a usage error (exit 2)
#   --detach             re-exec under setsid nohup (log <batch>/driver.log), print the batch
#                        directory and the pid, exit 0
#   --clear-arm ID       with --resume: remove ID from STATUS.json paused_arms (repeatable)
#   --clear-drift        with --resume: re-read the run named by STATUS.json drift (its run dir
#                        <batch>/<arm>/<task>-t<n>, or the highest -r<k> sibling) with the
#                        current drift guard; none → drift null, an entry in drift_cleared[] and
#                        the batch continues; still a drift → exit 2 printing it, nothing written
#   --rerow RUN_ID       with --resume: run the post-run chain (took-effect, drift guard, grade,
#                        ablation-row.sh with the old row's attempts and retry_reason) again
#                        over the run dir of RUN_ID and replace its one row in place, under the
#                        rows file's flock (temp file beside it, --validate, mv); repeatable;
#                        before reconciliation, so spend and per_arm count the new row once.
#                        Refused (exit 2, nothing written) when RUN_ID is not <batch>-… or not
#                        in the plan, has no row or more than one, has no run dir, or its row
#                        is interrupted or transport_error (those trials are reruns)
#   --rerun RUN_ID       with --resume (DEC-0553): launch RUN_ID again, at its plan index, into a
#                        fresh -r<k> run dir; when its new row lands it replaces the old row in
#                        place (replace_row, under the flock) and STATUS.json rerun[] gets
#                        {run_id, from, to, old_cost_usd, at}. The row must be transport_error,
#                        interrupted or infrastructure_error, else exit 2 with nothing written
#                        (also: not <batch>-…, not in the plan, no row or more than one, or the
#                        same id also given to --rerow); repeatable
#   --rerun-status S     with --resume: rerun every row of the batch whose status is S, one of
#                        transport_error, interrupted, infrastructure_error (anything else is a
#                        usage error); read after the rerows, and a --rerow id is never rerun;
#                        repeatable. A flagged row leaves the done set: no counter and no
#                        assumed charge, only its reported cost stays in spent (it moves to
#                        ledger_usd when the replacement lands); the in-flight reservation
#                        covers the new trial and its row is accounted once when it lands
#   --pipeline-bin P, --grade-bin G, --row-bin R, --took-effect-bin T, --docker-bin D, --spend-bin S
#                        the six collaborators (defaults: the scripts beside this one, and
#                        $EVAL_DOCKER_BIN else docker)
#
# Matched cells (cycle-132 FR-3, SDD D-3.1, D-3.2, D-7.3): an arm whose toggles set bare_sessions:
#   matched plans each cell (arm × task × trial; run_id <batch>-<arm>-<task>-t<n>, run dir
#   <batch>/<arm>/<task>-t<n>) as k session work units, k = the task's review_catch.bare_sessions_matched
#   (an arm with bare_model: fable: bare_sessions_matched_fable, else the same k; a planned matched arm on
#   a task without it is a usage error). Session s<i> is one full pipeline-run.sh invocation (run id
#   <run_id>-s<i>, run dir <cell>/sessions/s<i>, a re-run in s<i>-r<n>); --concurrency, the budget gate and
#   --resume apply per session. A session whose outcome is infrastructure — transport (as for trials),
#   cap_failure, interrupted (watchdog or no final record) — is re-run at most twice (3 attempts; every
#   attempt's cost is kept); a session with a refusal fallback (KF-051), a contaminated grade, a took-effect
#   FAIL (the arm is paused), a drift, a failed grade or a pipeline infrastructure_error is kept and marked
#   invalid, never re-run; completed and agent_error sessions that grade clean are valid. Each session's
#   chain is took-effect (its bare rules; bare_sessions_matched reads OK on a session dir), the drift guard
#   and ablation-grade.sh on the session dir; its final record goes to <cell>/meta/sessions/s<i>.json
#   {id, status, valid, invalid_reason, attempts, attempt_statuses, attempt_costs, cost_usd, run_dir}.
#   When all k sessions hold a record the cell is finalised in the driver: <cell>/meta/arm and
#   <cell>/meta/cell.json {schema_version, task_id, trial, k, sessions: [{id, status, valid, invalid_reason,
#   attempts, attempt_statuses, attempt_costs, cost_usd, run_dir}], sessions_valid, sessions_attempted, started,
#   finished} (no run_id and no arm id: the grader reads it; the row's run_id comes from session 1's run id),
#   took-effect.sh --run-dir <cell> --task-yaml (a FAIL rows the
#   cell infrastructure_error and pauses the arm), ablation-grade.sh --union <cell> --task-id <task>
#   (--suite-root, --tasks-dir smoke, --allow-partial as for trials; under the grade deadline), then
#   ablation-row.sh --run-dir <cell> once (the cell is completed with ⌈k/2⌉ valid sessions, else degraded;
#   ablation-row.sh 1.5). The dry run prints a cell's line with ` sessions <k>`; the plan line gains
#   `(<n> session units in <m> matched cells)` when the plan has any. Spend: each session is charged when it
#   ends (every attempt; a non-completed attempt reporting no cost is charged the kind's cap, a cap_failure
#   max(cost, cap)); the cell row adds counters only. --resume relaunches only the sessions without a
#   record (their earlier attempt dirs count toward the 3), charges every recorded session from its record,
#   finalises a cell whose k records exist without a row, and refuses --rerun/--rerow of a cell (exit 2).
# Attempt limit (D-7.3, every unit): a trial keeps its single in-line transport retry; a --rerun or
#   --rerun-status replacement counts the old row's attempts (the replacement row's attempts = the old
#   row's + its own, its in-line retry only while that stays ≤ 3); a row already at 3 attempts is refused by
#   --rerun (exit 2) and skipped by --rerun-status (one log line). ablation-row.sh --prior-spend gets the
#   earlier attempts' spend (all_spend_usd).
# Refusal policy (cycle-133 C-8, FR-8): each arm's suite refusal_policy (exclude | keep | rerun-once, default exclude)
#   is checked at pre-flight and recorded in MANIFEST.json refusal_policy {<arm>: policy}; rerun-once relaunches a
#   refused trial once (<arm>/<task>-t<n>.refusal-1.json records the kept first attempt). The rules sit in the block
#   after the arm checks; the row fields are ablation-row.sh 1.6's; evals/harness/README.md § Refusal policy.
#
# Pre-flight (any refusal: exit 2, nothing written but <batch>/REFUSED.txt with the reason):
#   1. hard gate, non-smoke batches only (DEC-0435): <suite-root>/MANIFEST.sha256 present,
#      the self-check log present with at least 2 × tasks + review-catch tasks lines
#      `…: PASS` (36 for the sixteen-task suite) and no `: FAIL` line, a REVIEW.md in every
#      <suite-root>/tasks/<id>/; their sha256 go to MANIFEST.json gate
#   2. freeze.sh --check --root <suite-root> --suite-file <suite-file> (it runs
#      validate-suite.sh), with --smoke when MANIFEST.sha256 lists a smoke/ path or the batch
#      is a smoke batch (the manifest is checked as it was frozen), and --allow-partial with
#      --allow-partial
#   3. seed-corpus-from-record.sh --check (the review-catch corpus SHA256SUMS)
#   4. container: the docker CLI and the image (`docker image inspect`)
#   5. the pinned source tree: $LOA_ABLATION_SOURCE_TREE when set (tests; must be a git tree
#      at the commit, with .claude/), else a detached worktree
#      $LOA_ABLATION_CACHE/ablation-src-<sha12> (default ~/.cache/loa) cut from
#      $LOA_ABLATION_SOURCE_REPO (default this repository) with git worktree add --detach;
#      it must be at the commit and pristine (git status --porcelain --ignored empty)
#   6. codex token freshness (KF-048), non-smoke batches only (fresh, --resume and --dry-run),
#      after the plan is built, when a planned arm uses codex (every arm except one whose
#      toggles set loa_mount: false; a0_bare never runs the dissent): the exp claim of the JWT
#      tokens.access_token in ${LOA_EVAL_CREDS_HOME:-$HOME}/.codex/auth.json (the file
#      pipeline-run.sh copies with a placeholder refresh token; payload decoded with base64url, no
#      signature check) must be later than required_until = now + 2 x max(S / concurrency, W),
#      S the sum and W the largest of watchdog_s over the trials this invocation counts (the
#      lower bound W: one trial takes its whole watchdog whatever the concurrency, DISS-C-001):
#      every plan entry on a fresh batch or a dry run; on --resume only the entries without a row
#      of this batch, plus the --rerun ids, the rows a --rerun-status names and the run_ids of
#      STATUS.json rerun_pending (never a --rerow id; a paused arm's trials still count). The
#      count is a superset of what the launcher runs: a rerun_pending id that is not flagged
#      again (--rerun / --rerun-status) keeps its old row and is not relaunched, so it lengthens
#      the horizon only (the safe direction); a run_id with two rows is read last-row-wins here,
#      where the launcher refuses the resume on the duplicate after this check (DISS-C-003).
#      $LOA_ABLATION_CODEX_HORIZON_S (positive whole seconds, an operator knob) replaces
#      the computed horizon: required_until = now + that. Refused: exp <= required_until (`codex
#      access token expires <ISO>, before the batch's required horizon <ISO> (now + 2 x
#      max(summed watchdog of <n> trial(s) / concurrency, longest watchdog) | now +
#      LOA_ABLATION_CODEX_HORIZON_S; KF-048) — run codex login on the host`), a present file
#      that is not a JSON object, an access token not a three-part JWT or without a numeric
#      exp, and a file with neither a tokens.access_token nor a non-empty OPENAI_API_KEY (`… — run codex login on the host, or set OPENAI_API_KEY
#      in auth.json`). API-key mode (no usable tokens.access_token, a non-empty OPENAI_API_KEY;
#      pipeline-run.sh copies the key into the per-run HOME only under LOA_EVAL_CODEX_APIKEY_COPY=1,
#      audit DISS-C-001; otherwise that run has no codex credential) passes without reading an exp, with one
#      `run-ablation: codex auth.json is in API-key mode; no token horizon applies (KF-048
#      concerns the ChatGPT refresh token only)` line; the key is never printed. A missing
#      auth.json is no refusal: one `run-ablation: WARN no codex auth.json under <dir>;
#      codex-using arms will run without the OpenAI voice` line.
#   --resume also refuses when the source commit, the suite manifest hash, the image digest
#   or the CLI version differ from MANIFEST.json, or when STATUS.json records a drift
#   (unless --clear-drift re-reads that run clean under the current rule).
#
# Plan: arms × tasks × trials. An arm whose task_types excludes a task's type is dropped for
# that task with one `refused:` line and never dispatched (DEC-0405). The order is
# trial-major (every arm × task once before any second trial); inside each trial block the
# entries (arm-major, tasks by id) are shuffled with one python3 random.Random(<seed>)
# generator, blocks in trial order (Fisher-Yates via random.shuffle: reproducible for a seed
# across CPython 3.x). run_id = <batch>-<arm>-<task>-t<n>; run dir <batch>/<arm>/<task>-t<n>,
# a fresh <…>-r<k> (k ≥ 2) for a transport retry or a resumed rerun (the run_id stays).
# --dry-run prints `plan: …`, the `refused:` lines and one line per trial
# `<arm> <task> <type> <trial> <run_id>`.
#
# Per trial, in order: pipeline-run.sh --task-yaml … --arm … --run-dir … --run-id … --trial …
#   --source-tree <pinned> --suite-file … --executor … --image … --docker-bin …
#   --max-run-usd <the trial kind's run cap> --batch-context <ID>, output to <batch>/<arm>/<task>-t<n>.log
#   (batch and smoke alike; cycle-132 bd-st02i: an argv flag, never an inherited variable):
#   pipeline-run.sh refuses an arm declaring eval_only: true without it (cycle-131 FR-5); then
#   1. status from meta/pipeline.json (missing or `running` → interrupted; a missing record
#      is written as a minimal pipeline.json with synthesized_by: run-ablation.sh)
#   2. transport: agent_error plus a provider signature in the failing phase's
#      stderr-<label>.log or events-<label>.jsonl (lib/arms-common.sh
#      is_pipeline_transport_failure) is retried ONCE after $LOA_ABLATION_RETRY_WAIT_S
#      (default 120) into a fresh run dir: attempts 2, retry_reason; the first attempt writes
#      no row and its spent_usd counts in spend; a second transport failure is rowed
#      transport_error. agent_error without the signature is never retried (DEC-0417)
#   3. took-effect.sh --run-dir D --suite-file F --task-yaml <task.yaml> --json-out D/meta/took-effect.json
#      (cycle-132: the record ablation-row.sh rows as took_effect; a --took-effect-bin must accept it) (completed, agent_error and
#      cap_failure runs; --task-yaml gives oracle_closed the PR fixture):
#      a FAIL rows the trial infrastructure_error and pauses the arm (STATUS.json
#      paused_arms; no further trial of it launches until --resume --clear-arm ID) (DEC-0418).
#      Since cycle-132 addendum 2, a1_full, a1_review_only and a1_full_openmount list dissent_present: a gate
#      that skipped its dissent (budget_exceeded, a refusal, no eval/ envelope, no voice) is such a FAIL.
#      It runs under timeout -s TERM -k 30 $LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S
#      (default 300; unwrapped when timeout is absent): exit 124 or 137 rows the trial
#      infrastructure_error with `run-ablation: took-effect timed out after Ns` in the trial
#      log and took_effect "timeout" in the trial result — the arm is NOT paused (a hang is
#      no evidence about the arm) and the grade does not run
#   4. drift guard (DEC-0407 as amended by DEC-0545): a phase drifts on model grounds only
#      when its model_requested differs from MANIFEST phase_models[name], or when the
#      requested model (else the manifest's) is absent from a non-empty models_used (ids
#      normalised as ablation-row.sh does: no Bedrock region prefix, no -vN:M suffix). Any
#      other models_used key is an extra model, telemetry and not drift (Claude Code's
#      WebFetch summariser or a built-in subagent): one `run-ablation: extra model <id> in
#      <labels> (<N> output tokens; …)` line in the trial log, the trial result's
#      extra_models and STATUS.json extra_models. The transcripts' system/init
#      claude_code_version (or version) equals MANIFEST cli_version (when neither carries a
#      version, pipeline.json image_digest must equal MANIFEST image_digest). A mismatch rows
#      the trial infrastructure_error, records STATUS.json drift, launches nothing more and
#      fails the batch once the running trials end
#   5. ablation-grade.sh D <task> --suite-root … [--tasks-dir smoke] [--allow-partial] --executor … --image …
#      --docker-bin … (scored runs that passed 3 and 4; exit 2 → row infrastructure_error)
#      under timeout -s TERM -k 30 $LOA_ABLATION_GRADE_TIMEOUT_S (default
#      1800; unwrapped when timeout is absent): exit 124 or 137 → row infrastructure_error,
#      `run-ablation: grade timed out after Ns` in the trial log, grade_rc keeps the exit
#      (the pipeline watchdog covers the pipeline only; this is the post-run deadline)
#   6. ablation-row.sh --run-dir D --task-yaml F --manifest <batch>/MANIFEST.json
#      --attempts N [--retry-reason R] [--status S] --out <job row>; the runner appends the
#      row to the rows file under flock and runs ablation-row.sh --validate on it
#      (--allow-ungraded for smoke) and refuses a run_id rowed twice (state failed)
#   Watchdog (DEC-0429): a trial whose pipeline has no final meta/pipeline.json status after
#   twice its phase-sum timeout (the planned phases' timeout_min: task bounds, else the
#   suite's phase_defaults, BARE = PLAN + IMPLEMENT + 2 × FIX) gets SIGTERM to its process
#   group, SIGKILL after $LOA_ABLATION_WATCHDOG_GRACE_S (default 60), and is rowed
#   interrupted. $LOA_ABLATION_WATCHDOG_S replaces the deadline (seconds; tests).
#   Outage breaker (DEC-0554): $LOA_ABLATION_OUTAGE_BREAKER (default 3; 0 disables) consecutive
#   collected trials rowed transport_error (collection order, any arm; any other collected
#   trial resets the count) stop further launches; the running trials end, STATUS.json outage
#   is set and the batch finishes partial (exit 1): `partial (outage breaker): N consecutive
#   transport failures; --resume --rerun-status transport_error after the network is back`.
#
# Run caps (DEC-0559, DEC-0567): each task kind (build = feature-build, bug-fix, refactor;
#   review-catch) has its own per-run cap, cap_for <kind>: --run-cap when given (both kinds),
#   else the suite's caps.run_usd_by_type[<kind>] (a present entry that is not an amount in
#   USD, or a run_usd_by_type that is not a map, is a usage error), else the single-cap chain
#   (evals.ablation.run_cap_usd in .loa.config.yaml, else caps.run_usd, else 12), which is
#   also MANIFEST caps.run_usd. The kind's cap goes to pipeline-run.sh --max-run-usd and is
#   the assumed charge of that kind's trials (Spend). The in-flight reservation per running
#   trial is the largest cap among the plan's kinds (a build-only plan reserves the build
#   cap; a plan with review-catch trials reserves the larger of the two for every running
#   trial, whatever its kind). --resume reads all three from MANIFEST.json caps (a manifest
#   without run_usd_by_type gives both kinds its run_usd), never from the suite file.
#
# Spend (--max-usd, SDD §5.5 reused through lib/arms-common.sh): before each launch,
#   spent + in_flight × reserve_cap + est_next > max waits for a running trial and
#   spent + est_next > max cuts (no further launches; STATUS.json cuts[] gets {reason,
#   spent, in_flight_reserved, max, est_next, trials_launched, at_trial}; exit 1).
#   reserve_cap = the largest run cap among the plan's kinds (Run caps).
#   est_next = the mean cost of this arm's completed trials of the task kind (build |
#   review-catch), else the kind's pooled mean, else the suite's cost_hint[kind]. spent =
#   rows' cost_usd + transport first attempts' spent_usd + assumed charges: a trial ending
#   neither completed nor with a reported cost is charged its kind's run cap, a cap_failure
#   is charged max(cost, its kind's run cap); both count in spend.assumed_cap_trials when
#   the charge exceeds the reported cost.
#
# Files: <results-root>/<batch>/{MANIFEST.json, STATUS.json, run.log, spend.txt,
#   REFUSED.txt, driver.log, .gitignore (non-smoke: the run directories and logs stay out of
#   git), <arm>/<task>-t<n>[-r<k>]/ (pipeline-run.sh run dirs), <arm>/<task>-t<n>.log};
#   rows to the rows file. MANIFEST.json (§3.4): schema_version, suite, batch, dry_run,
#   smoke, created, source_commit, source_worktree, source_commit_dot_claude_delta (git diff
#   --stat 4d69c3c4..<commit> -- .claude/, ≤ 4,000 chars), harness_commit, harness_dirty,
#   suite_file, suite_root, tasks_dir, rows_file, suite_version, suite_manifest_sha256, arms,
#   tasks, refused, trials_per_type, trials_planned, plan, arm_map, shuffle_seed, shuffle,
#   fingerprint, image, image_digest, executor_mode, cli_version (`docker run --rm --network
#   none <image> claude --version`, host: the CLI's), cli_version_raw, tools, phase_models,
#   caps {cycle_usd, run_usd (the single-cap fallback), reserve_usd, max_usd,
#   run_usd_by_type {build, review-catch} (the effective per-kind caps after the chain)},
#   cost_hint, concurrency, retry, overshoot_bound_usd (concurrency × the in-flight reserve cap: the most a
#   running set can pass the cap by), batch_context, bare_sessions_by_task {<arm>: {<task>: k}} ({} without
#   a matched arm), registration_sha256, registration_path, preregistration_sha256, registration (null
#   without --registration), spend_gate (null without --registration),
#   watchdog {multiplier, override_s, grace_s, grade_timeout_s, took_effect_timeout_s},
#   pre_registration_ref, gate (null for smoke), corpus, agy_opt_in, allow_partial (--allow-partial),
#   codex_token_exp (the access token's exp, ISO 8601 UTC, or null when not checked),
#   codex_preflight {checked (true only when the token was read and its exp compared),
#   auth_file_present, codex_arms (the planned arms that use codex, sorted), token_exp,
#   required_until (ISO or null), auth_mode ("chatgpt" | "apikey" | null when the file was not
#   read or not classified), trials_counted (the trials the horizon covers, or null),
#   horizon_source ("plan" | "override" | null when no horizon was computed)} (pre-flight 6;
#   --resume keeps the start's record; STATUS.json codex_preflight holds the latest
#   invocation's; both writers take it from a shell variable, never a scratch file), environment.
#   STATUS.json (§3.4), rewritten after every trial: {schema_version, suite, batch, smoke,
#   state: running|complete|partial|failed, per_arm: {<arm>: {trials_planned, launched,
#   completed, failed (agent_error), excluded (transport_error, infrastructure_error,
#   interrupted, contaminated), cap_failures, degraded, skipped_paused}}, retries: [{run_id,
#   reason, first_attempt_usd}], cuts: [...], paused_arms: {<arm>: reason}, spend: {rows_usd,
#   ledger_usd (transport first attempts, and the reported cost of rows a rerun replaced), spent_usd, max_usd, assumed_cap_trials}, resume_cursor (the
#   index of the first plan entry without a row), drift: null | {run_id, field, expected,
#   got}, drift_cleared: [{run_id, previous, cleared_at, harness_commit}] (--clear-drift),
#   rerowed: [{run_id, from, to, at}] (--rerow), rerun: [{run_id, from, to, old_cost_usd, at}]
#   (--rerun, --rerun-status), rerun_pending: [run_id…] (flagged, no replacement yet), outage:
#   null | {at, consecutive, last_run_id, message} (the breaker), outage_history: [the
#   outages a later --resume cleared], codex_preflight (this invocation's pre-flight 6 record,
#   the MANIFEST shape, null if STATUS.json is written before pre-flight 6 ran; on --resume
#   trials_counted is the remaining trials, rerun_pending included), extra_models: {<raw id>: {runs,
#   output_tokens}} ({} when none; derived from extra_models_by_run: {<run_id>: {<raw id>:
#   output_tokens}}, the per-run source a rerow replaces), rows_invalid, started,
#   finished}. At the end the spend.sh line and a batch line go to <batch>/spend.txt.
#
# --resume: reads MANIFEST.json (plan, arms, suite paths, executor, image, run caps, rows
#   file) and STATUS.json (paused_arms, cuts, retries, first-attempt spend); a plan run_id
#   with a row of this batch is done; a trial without a row reruns into a fresh -r<k> run
#   dir (the stale dir is kept); counters and spend are recomputed from the rows.
#   --max-usd and --concurrency may change on resume; --clear-arm, --clear-drift and
#   --rerow need --resume (order: --clear-drift, --rerow and --rerun are checked before the lock,
#   then --rerow replaces rows, then the counters are recomputed with the rerun-flagged rows left
#   out of the done set; the reruns are dispatched with the plan). A resume clears STATUS.json
#   outage (kept under outage_history[]). A start
#   (fresh or resumed) is refused while a process group recorded under <batch>/.jobs/ by an
#   earlier driver (one killed with SIGKILL) is still alive.
#
# Exit: 0 complete (every trial rowed; none transport_error, infrastructure_error,
#       interrupted or contaminated), 1 partial (cut, the outage breaker, a paused arm with trials left, an
#       excluded row, or the driver was signalled), 2 usage or refused, 3 failed (drift, an
#       invalid or duplicated row, no trial completed without a cut, or every arm of the
#       plan paused)
#
# Env: LOA_ABLATION_SOURCE_TREE, LOA_ABLATION_SOURCE_REPO, LOA_ABLATION_CACHE,
#   LOA_ABLATION_RETRY_WAIT_S, LOA_ABLATION_WATCHDOG_S, LOA_ABLATION_WATCHDOG_GRACE_S,
#   LOA_ABLATION_POLL_S (reap poll, default 1), LOA_ABLATION_OUTAGE_BREAKER (default 3),
#   LOA_ABLATION_GRADE_TIMEOUT_S (grade deadline, default 1800: above the grader's own per-command deadline of
#   120 + 10 s over at most ten container commands per grade, plus the tree copies; the outage breaker counts
#   transport_error rows only, never these infrastructure_error rows) and
#   LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S (took-effect deadline, default 300), both whole seconds
#   1 … 999999 (else exit 2), LOA_ABLATION_CODEX_HORIZON_S (operator override of the codex
#   token horizon of pre-flight 6, whole seconds 1 … 999999999, else exit 2; not a test gate),
#   LOA_EVAL_CREDS_HOME (where .codex/auth.json is read; default $HOME), EVAL_DOCKER_BIN,
#   EVAL_CLAUDE_BIN (host CLI).
# Library: lib/arms-common.sh beside this script, sourced by a literal relative path.
# Tested by evals/tests/run-ablation.bats (stub pipeline, grader and docker; no model call).
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# eval.yml trust boundary: a literal in-tree path, no variable on the source line
pushd "$SCRIPT_DIR" >/dev/null
# shellcheck source=lib/arms-common.sh
source ./lib/arms-common.sh || { popd >/dev/null; echo "run-ablation: lib/arms-common.sh failed to load" >&2; exit 2; }
popd >/dev/null

DELTA_BASE="4d69c3c4"   # v2.0.0-rc.5: the pin's .claude/ delta is reported against it
CACHE_ROOT="${LOA_ABLATION_CACHE:-$HOME/.cache/loa}"
SOURCE_REPO="${LOA_ABLATION_SOURCE_REPO:-$REPO_ROOT}"
SELF_ARGS=("$@")

ARMS_CSV="" SOURCE_COMMIT="" TASKS_CSV="" TYPES_CSV="" TRIALS_BUILD="" TRIALS_REVIEW=""
MAX_USD="" RUN_CAP="" CONCURRENCY=3 BATCH="" RESULTS_ROOT="" ROWS=""
CAP_BUILD="" CAP_REVIEW=""   # the per-kind run caps (DEC-0567; cap_for)
SUITE_ROOT="$REPO_ROOT/grimoires/loa/evals/ablation-2.0"
SUITE_FILE="$REPO_ROOT/evals/suites/ablation-2.0.yaml"
IMAGE="loa-ablation:258" EXECUTOR="container" PRE_REG_REF="" SEED=20261015
SELF_CHECK_LOG="$REPO_ROOT/grimoires/loa/a2a/sprint-259/self-check-image.log"
SMOKE=false DRY_RUN=false RESUME=false DETACH=false ALLOW_PARTIAL=false
CLEAR_ARMS=() REROW_IDS=() CLEAR_DRIFT=false RERUN_IDS=() RERUN_STATUSES=()
PIPELINE_BIN="$SCRIPT_DIR/pipeline-run.sh" GRADE_BIN="$SCRIPT_DIR/ablation-grade.sh"
ROW_BIN="$SCRIPT_DIR/ablation-row.sh" TOOK_BIN="$SCRIPT_DIR/took-effect.sh"
DOCKER_BIN="${EVAL_DOCKER_BIN:-docker}"
FREEZE_BIN="$SCRIPT_DIR/freeze.sh" CORPUS_BIN="$SCRIPT_DIR/seed-corpus-from-record.sh"
SPEND_BIN="$SCRIPT_DIR/spend.sh" FP_BIN="$SCRIPT_DIR/fingerprint.sh"
RETRY_WAIT="${LOA_ABLATION_RETRY_WAIT_S:-120}"
WATCHDOG_OVERRIDE="${LOA_ABLATION_WATCHDOG_S:-}"
WATCHDOG_GRACE="${LOA_ABLATION_WATCHDOG_GRACE_S:-60}"
POLL_S="${LOA_ABLATION_POLL_S:-1}"
OUTAGE_BREAKER="${LOA_ABLATION_OUTAGE_BREAKER:-3}"
GRADE_TIMEOUT_S="${LOA_ABLATION_GRADE_TIMEOUT_S:-1800}"
TOOK_TIMEOUT_S="${LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S:-300}"
CODEX_HORIZON_OVERRIDE="${LOA_ABLATION_CODEX_HORIZON_S:-}"
CODEX_PF_JSON=null   # the pre-flight 6 record (JSON); null until pre-flight 6 sets it (DISS-C-002)
REGISTRATION="" SPEND_SINCE="" BATCH_CONTEXT=""   # cycle-132: --registration, --spend-since, --batch-context
REG_JSON=null REG_SHA="" SPEND_GATE_JSON=null

usage() { sed -n '2,/^# =====.*$/p' "$0" | sed '1d;$d' | sed 's/^# \{0,1\}//' >&2; exit 2; }
die() { echo "run-ablation: $*" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arms) ARMS_CSV="${2:-}"; shift 2 ;;
    --source-commit) SOURCE_COMMIT="${2:-}"; shift 2 ;;
    --tasks) TASKS_CSV="${2:-}"; shift 2 ;;
    --types) TYPES_CSV="${2:-}"; shift 2 ;;
    --trials-build) TRIALS_BUILD="${2:-}"; shift 2 ;;
    --trials-review) TRIALS_REVIEW="${2:-}"; shift 2 ;;
    --max-usd) MAX_USD="${2:-}"; shift 2 ;;
    --run-cap) RUN_CAP="${2:-}"; shift 2 ;;
    --concurrency) CONCURRENCY="${2:-}"; shift 2 ;;
    --batch) BATCH="${2:-}"; shift 2 ;;
    --results-root) RESULTS_ROOT="${2:-}"; shift 2 ;;
    --rows) ROWS="${2:-}"; shift 2 ;;
    --suite-root) SUITE_ROOT="${2:-}"; shift 2 ;;
    --suite-file) SUITE_FILE="${2:-}"; shift 2 ;;
    --image) IMAGE="${2:-}"; shift 2 ;;
    --executor) EXECUTOR="${2:-}"; shift 2 ;;
    --pre-registration-ref) PRE_REG_REF="${2:-}"; shift 2 ;;
    --seed) SEED="${2:-}"; shift 2 ;;
    --self-check-log) SELF_CHECK_LOG="${2:-}"; shift 2 ;;
    --smoke) SMOKE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --resume) RESUME=true; shift ;;
    --detach) DETACH=true; shift ;;
    --allow-partial) ALLOW_PARTIAL=true; shift ;;
    --clear-arm) CLEAR_ARMS+=("${2:-}"); shift 2 ;;
    --clear-drift) CLEAR_DRIFT=true; shift ;;
    --rerow) REROW_IDS+=("${2:-}"); shift 2 ;;
    --rerun) RERUN_IDS+=("${2:-}"); shift 2 ;;
    --rerun-status) RERUN_STATUSES+=("${2:-}"); shift 2 ;;
    --pipeline-bin) PIPELINE_BIN="${2:-}"; shift 2 ;;
    --grade-bin) GRADE_BIN="${2:-}"; shift 2 ;;
    --row-bin) ROW_BIN="${2:-}"; shift 2 ;;
    --took-effect-bin) TOOK_BIN="${2:-}"; shift 2 ;;
    --docker-bin) DOCKER_BIN="${2:-}"; shift 2 ;;
    --spend-bin) SPEND_BIN="${2:-}"; shift 2 ;;
    --registration) REGISTRATION="${2:-}"; [[ -n "$REGISTRATION" ]] || die "--registration needs a file"; shift 2 ;;
    --spend-since) SPEND_SINCE="${2:-}"; shift 2 ;;
    --batch-context) BATCH_CONTEXT="${2:-}"; shift 2 ;;
    --help|-h) usage ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

# --- validate arguments ------------------------------------------------------------
abspath() { case "$1" in /*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
for tool in git jq yq python3 awk; do command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"; done
case "$EXECUTOR" in container|host) ;; *) die "--executor must be container or host" ;; esac
[[ "$CONCURRENCY" =~ ^[1-9]$ ]] || die "--concurrency must be 1-9"
[[ -z "$TRIALS_BUILD" || "$TRIALS_BUILD" =~ ^[1-9]$ ]] || die "--trials-build must be 1-9"
[[ -z "$TRIALS_REVIEW" || "$TRIALS_REVIEW" =~ ^[1-9]$ ]] || die "--trials-review must be 1-9"
[[ "$SEED" =~ ^[0-9]{1,10}$ ]] || die "--seed must be a non-negative integer"
if [[ -n "$MAX_USD" ]]; then usd_ok "$MAX_USD" && [[ "$MAX_USD" != "0" ]] || die "--max-usd must be a positive amount in USD"; fi
[[ -z "$RUN_CAP" ]] || usd_ok "$RUN_CAP" || die "--run-cap must be an amount in USD"
RUN_CAP_OVERRIDE="$RUN_CAP"   # --run-cap: the single-cap override of both kinds
[[ -z "$SOURCE_COMMIT" || "$SOURCE_COMMIT" =~ ^[0-9a-f]{7,40}$ ]] || die "--source-commit must be a hex commit id"
[[ "$IMAGE" =~ ^[A-Za-z0-9._:/@-]{1,200}$ ]] || die "--image has unexpected characters"
[[ "${#PRE_REG_REF}" -le 300 && "$PRE_REG_REF" != *$'\n'* ]] || die "--pre-registration-ref must be one line of at most 300 characters"
[[ -z "$BATCH_CONTEXT" || "$BATCH_CONTEXT" =~ ^[A-Za-z0-9._-]{1,200}$ ]] || die "--batch-context must match ^[A-Za-z0-9._-]{1,200}\$"
[[ -z "$SPEND_SINCE" || "$SPEND_SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}(:[0-9]{2})?Z$ ]] || die "--spend-since must be an ISO-8601 UTC timestamp (2026-10-21T00:23:00Z)"
[[ -z "$SPEND_SINCE" || -n "$REGISTRATION" || "$RESUME" == true ]] || die "--spend-since goes with --registration (the registered cap is what the meter is subtracted from)"
[[ "$RETRY_WAIT" =~ ^[0-9]{1,5}$ ]] || die "LOA_ABLATION_RETRY_WAIT_S must be whole seconds"
[[ -z "$WATCHDOG_OVERRIDE" || "$WATCHDOG_OVERRIDE" =~ ^[1-9][0-9]{0,6}$ ]] || die "LOA_ABLATION_WATCHDOG_S must be positive whole seconds"
[[ "$WATCHDOG_GRACE" =~ ^[0-9]{1,5}$ ]] || die "LOA_ABLATION_WATCHDOG_GRACE_S must be whole seconds"
[[ "$POLL_S" =~ ^[0-9]{1,3}(\.[0-9]{1,3})?$ ]] || die "LOA_ABLATION_POLL_S must be seconds"
if [[ ${#CLEAR_ARMS[@]} -gt 0 && "$RESUME" != true ]]; then die "--clear-arm needs --resume"; fi
for a in ${CLEAR_ARMS[@]+"${CLEAR_ARMS[@]}"}; do [[ "$a" =~ ^[a-z][a-z0-9_]{0,63}$ ]] || die "invalid --clear-arm '$a'"; done
[[ "$CLEAR_DRIFT" != true || "$RESUME" == true ]] || die "--clear-drift needs --resume"
if [[ ${#REROW_IDS[@]} -gt 0 && "$RESUME" != true ]]; then die "--rerow needs --resume"; fi
for r in ${REROW_IDS[@]+"${REROW_IDS[@]}"}; do [[ "$r" =~ ^[A-Za-z0-9._-]{1,200}$ ]] || die "invalid --rerow '$r'"; done
[[ "$(printf '%s\n' ${REROW_IDS[@]+"${REROW_IDS[@]}"} | sort | uniq -d)" == "" ]] || die "--rerow lists a run_id twice"
if [[ ${#RERUN_IDS[@]} -gt 0 && "$RESUME" != true ]]; then die "--rerun needs --resume"; fi
if [[ ${#RERUN_STATUSES[@]} -gt 0 && "$RESUME" != true ]]; then die "--rerun-status needs --resume"; fi
for s in ${RERUN_STATUSES[@]+"${RERUN_STATUSES[@]}"}; do
  case "$s" in transport_error|interrupted|infrastructure_error) ;;
    *) die "--rerun-status must be transport_error, interrupted or infrastructure_error (got '$s')" ;; esac
done
for r in ${RERUN_IDS[@]+"${RERUN_IDS[@]}"}; do
  [[ "$r" =~ ^[A-Za-z0-9._-]{1,200}$ ]] || die "invalid --rerun '$r'"
  for q in ${REROW_IDS[@]+"${REROW_IDS[@]}"}; do [[ "$q" != "$r" ]] || die "--rerun $r is also a --rerow (a run is rowed again or launched again, not both)"; done
done
[[ "$(printf '%s\n' ${RERUN_IDS[@]+"${RERUN_IDS[@]}"} | sort | uniq -d)" == "" ]] || die "--rerun lists a run_id twice"
[[ "$OUTAGE_BREAKER" =~ ^[0-9]{1,4}$ ]] || die "LOA_ABLATION_OUTAGE_BREAKER must be a whole number (0 disables)"
[[ "$GRADE_TIMEOUT_S" =~ ^[1-9][0-9]{0,5}$ ]] || die "LOA_ABLATION_GRADE_TIMEOUT_S must be positive whole seconds (at most 999999)"
[[ "$TOOK_TIMEOUT_S" =~ ^[1-9][0-9]{0,5}$ ]] || die "LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S must be positive whole seconds (at most 999999)"
[[ -z "$CODEX_HORIZON_OVERRIDE" || "$CODEX_HORIZON_OVERRIDE" =~ ^[1-9][0-9]{0,8}$ ]] \
  || die "LOA_ABLATION_CODEX_HORIZON_S must be positive whole seconds (at most 999999999)"
# the post-run deadlines (Sprint 260 LOW-4): unwrapped when timeout(1) is absent
GRADE_TMO=() TOOK_TMO=() TMO_ON=false
if command -v timeout >/dev/null 2>&1; then
  # the portable short flags (GNU and BusyBox; review round 2 DISS-C-003); MANIFEST records null when unwrapped
  GRADE_TMO=(timeout -s TERM -k 30 "$GRADE_TIMEOUT_S")
  TOOK_TMO=(timeout -s TERM -k 30 "$TOOK_TIMEOUT_S")
  TMO_ON=true
fi
[[ "$RESUME" != true || "$DRY_RUN" != true ]] || die "--resume and --dry-run are exclusive"
[[ "$RESUME" == true || -n "$SOURCE_COMMIT" ]] || die "--source-commit is required"

if [[ -z "$BATCH" ]]; then
  [[ "$RESUME" != true ]] || die "--resume needs --batch NAME"
  if [[ "$SMOKE" == true ]]; then BATCH="smoke-$(date -u +%Y%m%dT%H%M%SZ)"; else BATCH="batch-$(date -u +%Y%m%dT%H%M%SZ)"; fi
fi
[[ "$BATCH" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || die "invalid --batch '$BATCH'"
case "$BATCH" in .|..) die "invalid --batch '$BATCH' (a batch is one child directory)" ;; esac
if [[ "$SMOKE" != true && "$BATCH" == smoke-* ]]; then die "invalid --batch '$BATCH': the smoke- prefix is reserved for --smoke"; fi

if [[ -z "$RESULTS_ROOT" ]]; then
  if [[ "$SMOKE" == true ]]; then RESULTS_ROOT="$REPO_ROOT/evals/results/ablation-2.0"
  else RESULTS_ROOT="$REPO_ROOT/grimoires/loa/reports/ablation-2.0/batches"
       [[ -n "$ROWS" ]] || ROWS="$REPO_ROOT/grimoires/loa/reports/ablation-2.0/runs.jsonl"
  fi
fi
RESULTS_ROOT="$(abspath "$RESULTS_ROOT")"
BATCH_DIR="$RESULTS_ROOT/$BATCH"
if [[ -z "$ROWS" ]]; then
  if [[ "$SMOKE" == true ]]; then ROWS="$BATCH_DIR/rows.jsonl"; else ROWS="$RESULTS_ROOT/runs.jsonl"; fi
fi
ROWS="$(abspath "$ROWS")"
if [[ "$SMOKE" == true && "$ROWS" == "$REPO_ROOT/grimoires/loa/reports/ablation-2.0/runs.jsonl" ]]; then
  die "a smoke batch never writes the tracked runs.jsonl (DEC-0428)"
fi
SUITE_FILE="$(abspath "$SUITE_FILE")" SUITE_ROOT="$(abspath "$SUITE_ROOT")" SELF_CHECK_LOG="$(abspath "$SELF_CHECK_LOG")"

# --- --resume: the batch's own settings come from its MANIFEST.json ------------------
MAN_PATH="$BATCH_DIR/MANIFEST.json"
if [[ "$RESUME" == true ]]; then
  [[ -f "$MAN_PATH" && -f "$BATCH_DIR/STATUS.json" ]] || die "batch $BATCH has no MANIFEST.json and STATUS.json to resume ($BATCH_DIR)"
  jq -e '.schema_version == 1 and .dry_run == false' "$MAN_PATH" >/dev/null 2>&1 \
    || die "$MAN_PATH is not a schema_version 1 batch manifest of a real run"
  [[ "$(jq -r '.smoke' "$MAN_PATH")" == "$SMOKE" ]] || die "batch $BATCH smoke=$(jq -r '.smoke' "$MAN_PATH"); pass --smoke exactly as the batch started"
  if [[ "$(jq -r '.drift != null' "$BATCH_DIR/STATUS.json")" == true && "$CLEAR_DRIFT" != true ]]; then
    die "batch $BATCH failed on drift ($(jq -c '.drift' "$BATCH_DIR/STATUS.json")); start a new batch, or --clear-drift when the rule changed (DEC-0545)"
  fi
  man_src="$(jq -r '.source_commit' "$MAN_PATH")"
  if [[ -n "$SOURCE_COMMIT" && "$man_src" != "$SOURCE_COMMIT"* ]]; then die "--source-commit $SOURCE_COMMIT differs from the batch's $man_src"; fi
  SOURCE_COMMIT="$man_src"
  ARMS_CSV="$(jq -r '.arms | join(",")' "$MAN_PATH")"
  SUITE_ROOT="$(jq -r '.suite_root' "$MAN_PATH")" SUITE_FILE="$(jq -r '.suite_file_path' "$MAN_PATH")"
  EXECUTOR="$(jq -r '.executor_mode' "$MAN_PATH")" IMAGE="$(jq -r '.image' "$MAN_PATH")"
  [[ -z "$RUN_CAP_OVERRIDE" ]] || echo "run-ablation: --run-cap $RUN_CAP_OVERRIDE ignored on --resume; batch $BATCH keeps the caps in its MANIFEST.json" >&2
  RUN_CAP="$(jq -r '.caps.run_usd' "$MAN_PATH")" SEED="$(jq -r '.shuffle_seed' "$MAN_PATH")"
  # a manifest written before DEC-0567 has no run_usd_by_type: both kinds keep its run_usd
  CAP_BUILD="$(jq -r '.caps.run_usd_by_type.build // .caps.run_usd' "$MAN_PATH")"
  CAP_REVIEW="$(jq -r '.caps.run_usd_by_type["review-catch"] // .caps.run_usd' "$MAN_PATH")"
  for c in "$RUN_CAP" "$CAP_BUILD" "$CAP_REVIEW"; do usd_ok "$c" || die "$MAN_PATH caps hold a run cap that is not an amount in USD: $c"; done
  ROWS="$(jq -r '.rows_file' "$MAN_PATH")"
  [[ -n "$MAX_USD" ]] || MAX_USD="$(jq -r '.caps.max_usd // empty' "$MAN_PATH")"
  PRE_REG_REF="$(jq -r '.pre_registration_ref // ""' "$MAN_PATH")"
  man_ap="$(jq -r '.allow_partial // false' "$MAN_PATH")"
  if [[ "$ALLOW_PARTIAL" == true && "$man_ap" != true ]]; then
    die "--allow-partial conflicts with batch $BATCH's MANIFEST.json allow_partial $man_ap (a batch keeps the value it started with)"
  fi
  [[ "$man_ap" == true ]] && ALLOW_PARTIAL=true
  # cycle-132 (D-5.2): the batch is bound to the registration it started under
  man_reg_sha="$(jq -r '.registration_sha256 // ""' "$MAN_PATH")" man_reg_path="$(jq -r '.registration_path // ""' "$MAN_PATH")"
  if [[ -n "$man_reg_sha" ]]; then
    if [[ -n "$REGISTRATION" && "$(cd "$(dirname "$REGISTRATION")" 2>/dev/null && pwd)/$(basename "$REGISTRATION")" != "$man_reg_path" ]]; then
      die "--registration $REGISTRATION differs from the batch's $man_reg_path (a batch keeps the registration it started under)"
    fi
    [[ -f "$man_reg_path" ]] || die "registration changed: $man_reg_sha ≠ <missing> ($man_reg_path is gone)"
    now_reg_sha="$(python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$man_reg_path")"
    [[ "$now_reg_sha" == "$man_reg_sha" ]] || die "registration changed: $man_reg_sha ≠ $now_reg_sha ($man_reg_path)"
    REGISTRATION="$man_reg_path"
  elif [[ -n "$REGISTRATION" ]]; then
    die "--registration on --resume: batch $BATCH started without a registration"
  fi
  man_bc="$(jq -r '.batch_context // ""' "$MAN_PATH")"
  if [[ -n "$BATCH_CONTEXT" && -n "$man_bc" && "$BATCH_CONTEXT" != "$man_bc" ]]; then
    die "--batch-context $BATCH_CONTEXT differs from the batch's $man_bc"
  fi
  [[ -n "$man_bc" ]] && BATCH_CONTEXT="$man_bc"
fi
[[ -n "$BATCH_CONTEXT" ]] || BATCH_CONTEXT="$BATCH"   # the default: the batch name (a pre-cycle-132 batch on --resume too)

# --- --detach: re-exec in a new session, then return ---------------------------------
if [[ "$DETACH" == true ]]; then
  mkdir -p "$BATCH_DIR"
  child=()
  for a in "${SELF_ARGS[@]}"; do [[ "$a" == --detach ]] || child+=("$a"); done
  child+=(--batch "$BATCH")
  if command -v setsid >/dev/null 2>&1; then
    setsid nohup "$SCRIPT_DIR/run-ablation.sh" "${child[@]}" > "$BATCH_DIR/driver.log" 2>&1 < /dev/null &
  else
    nohup "$SCRIPT_DIR/run-ablation.sh" "${child[@]}" > "$BATCH_DIR/driver.log" 2>&1 < /dev/null &
  fi
  echo "detached: batch $BATCH_DIR pid $! (log $BATCH_DIR/driver.log)"
  exit 0
fi

if [[ "$RESUME" != true && "$DRY_RUN" != true && -f "$MAN_PATH" ]] \
   && [[ "$(jq -r '.dry_run' "$MAN_PATH" 2>/dev/null)" == false ]]; then
  die "batch $BATCH already holds a real run ($MAN_PATH); use --resume or another --batch"
fi

refuse() {  # refuse <reason> — the pre-flight refusal: REFUSED.txt and exit 2
  mkdir -p "$BATCH_DIR"
  printf 'run-ablation.sh refused batch %s at %s\nreason: %s\n' "$BATCH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" > "$BATCH_DIR/REFUSED.txt"
  echo "run-ablation: refused: $*" >&2
  exit 2
}

[[ -f "$SUITE_FILE" ]] || die "suite file not found: $SUITE_FILE"
[[ -d "$SUITE_ROOT" ]] || die "suite root not found: $SUITE_ROOT"
SUITE_JSON="$(yq -o=json '.' "$SUITE_FILE")" || die "suite file does not parse: $SUITE_FILE"
TASKS_DIR_NAME=tasks; [[ "$SMOKE" == true ]] && TASKS_DIR_NAME=smoke
TDIR="$SUITE_ROOT/$TASKS_DIR_NAME"
[[ -d "$TDIR" ]] || die "no $TASKS_DIR_NAME/ under $SUITE_ROOT"

if [[ -z "$RUN_CAP" ]]; then
  RUN_CAP="$(yq -r '.evals.ablation.run_cap_usd // ""' "$REPO_ROOT/.loa.config.yaml" 2>/dev/null || true)"
  usd_ok "${RUN_CAP:-x}" || RUN_CAP="$(jq -r '.caps.run_usd // ""' <<<"$SUITE_JSON")"
  usd_ok "${RUN_CAP:-x}" || RUN_CAP=12
fi
# per-kind caps (DEC-0567): --run-cap, else the suite's caps.run_usd_by_type[<kind>], else
# RUN_CAP from the chain above (.loa.config.yaml evals.ablation.run_cap_usd, else
# caps.run_usd, else 12). A present but malformed per-kind entry is refused, never skipped.
suite_kind_cap() {  # suite_kind_cap <kind> → the suite's entry, or empty when it has none
  local v
  v="$(jq -r --arg k "$1" '.caps.run_usd_by_type // null
        | if . == null then "" elif type == "object" then (.[$k] // "" | tostring) else "!" end' <<<"$SUITE_JSON")"
  [[ "$v" != "!" ]] || die "suite caps.run_usd_by_type must be a map of task kind to USD ($SUITE_FILE)"
  [[ -z "$v" ]] || usd_ok "$v" || die "suite caps.run_usd_by_type.$1 is not an amount in USD: $v ($SUITE_FILE)"
  printf '%s' "$v"
}
if [[ -z "$CAP_BUILD" ]]; then   # --resume set both from MANIFEST.json
  if [[ -n "$RUN_CAP_OVERRIDE" ]]; then CAP_BUILD="$RUN_CAP_OVERRIDE" CAP_REVIEW="$RUN_CAP_OVERRIDE"
  else
    CAP_BUILD="$(suite_kind_cap build)" || exit 2; CAP_BUILD="${CAP_BUILD:-$RUN_CAP}"
    CAP_REVIEW="$(suite_kind_cap review-catch)" || exit 2; CAP_REVIEW="${CAP_REVIEW:-$RUN_CAP}"
  fi
fi
cap_for() { if [[ "$1" == review-catch ]]; then printf '%s' "$CAP_REVIEW"; else printf '%s' "$CAP_BUILD"; fi; }
hint_for() { local h; h="$(jq -r --arg k "$1" '.cost_hint | if type == "object" then .[$k] // "" else (. // "") end' <<<"$SUITE_JSON")"; usd_ok "${h:-x}" || h=5.0; printf '%s' "$h"; }
HINT_BUILD="$(hint_for build)" HINT_REVIEW="$(hint_for review-catch)"
# est_next's last fallback per kind (the key is "<arm>|<kind>")
est_hint() { if [[ "${1#*|}" == review-catch ]]; then printf '%s' "$HINT_REVIEW"; else printf '%s' "$HINT_BUILD"; fi; }

# --- arms and tasks -----------------------------------------------------------------------
[[ -n "$ARMS_CSV" ]] || ARMS_CSV="$(jq -r '(.arms // [] | map(select(.absent == true) | .id)) as $absent
                                            | [.priority // [] | .[] | select(IN($absent[]) | not)] | join(",")' <<<"$SUITE_JSON")"
IFS=',' read -r -a ARMS <<<"$ARMS_CSV"
[[ ${#ARMS[@]} -gt 0 && -n "${ARMS[0]}" ]] || die "no arms (--arms, or the suite's priority)"
for a in "${ARMS[@]}"; do
  [[ "$a" =~ ^[a-z][a-z0-9_]{0,63}$ ]] || die "invalid arm id '$a'"
  def="$(jq -c --arg a "$a" '[.arms // [] | .[] | select(.id == $a)][0] // empty' <<<"$SUITE_JSON")"
  [[ -n "$def" ]] || die "arm '$a' is not declared in $SUITE_FILE"
  [[ "$(jq -r '.absent // false' <<<"$def")" != true ]] || die "arm '$a' is declared absent: true"
done
[[ "$(printf '%s\n' "${ARMS[@]}" | sort | uniq -d)" == "" ]] || die "--arms lists an arm twice"

# --- cycle-133 C-8 (FR-8, bd-r9abp): the refusal policy ---------------------------------------------------------------
# Every planned arm's suite key refusal_policy (exclude | keep | rerun-once; absent = exclude) is checked here (exit 2
# naming the repair) and recorded in MANIFEST.json refusal_policy {arm: policy} before any trial runs; at run time it
# is read from the MANIFEST only, so a batch whose MANIFEST predates the key runs exclude (cycle-132's behaviour). A
# matched arm (bare_sessions: matched) takes exclude only: a session with a refusal fallback stays invalid.
# rerun-once (trials): an attempt that ended completed, agent_error or cap_failure, without an override, and whose
# pipeline record carries a refusal fallback (KF-051) is left untouched in its run dir and recorded once in
# <batch>/<arm>/<task>-t<n>.refusal-1.json {schema_version, attempt: 1, run_id, run_dir (its basename), status,
# attempts, cost_usd, refusal_fallbacks: [{label, refusal_fallbacks}]} — immutable: hard-linked into place, never
# rewritten. The trial is then relaunched once at the same plan index into a fresh -r<k> run dir under the same
# per-run cap and the D-7.3 attempt limit (no relaunch when its attempts would pass 3: the row reads rerun_not_run).
# Both attempts are charged: the record's cost_usd goes to spent and the ledger when the trial is collected and into
# the row's all_spend_usd (--prior-spend); its attempts count in the row's attempts. A second refusal is never
# relaunched. A driver resumed after the first attempt finds the record and launches only the second attempt (an
# attempt cut off before its record was written is relaunched from the first, like any interrupted trial). The
# relaunch runs in its trial's slot without a second budget-gate check: in the worst case a batch passes --max-usd by
# one run cap per concurrently refused trial. The second attempt's row gets --refusal-attempt 2 --refused-attempt
# <first run dir>; the outcome and denominator rules are ablation-row.sh's (row writer 1.6).
REF_ARMS_TSV="$(jq -r --arg arms "$ARMS_CSV" '($arms | split(",")) as $want | .arms // [] | .[] | select(.id as $i | $want | index($i))
  | [.id, (if has("refusal_policy") then .refusal_policy | tostring else "exclude" end),
     ((.toggles // {}).bare_sessions == "matched" | tostring)] | @tsv' <<<"$SUITE_JSON")" \
  || die "suite arms unreadable for the refusal_policy check ($SUITE_FILE)"
while IFS=$'\t' read -r a pol matched; do
  [[ -n "$a" ]] || continue
  case "$pol" in exclude|keep|rerun-once) ;; *) die "arm '$a': refusal_policy '$pol' is not exclude|keep|rerun-once (fix the arm in $SUITE_FILE)" ;; esac
  [[ "$matched" != true || "$pol" == exclude ]] \
    || die "arm '$a' is a matched arm (bare_sessions: matched): refusal_policy must be exclude, not '$pol' (fix the arm in $SUITE_FILE)"
done <<<"$REF_ARMS_TSV"
refusal_policy_of() {  # refusal_policy_of <arm> → the MANIFEST's policy (exclude when it predates the key)
  jq -r --arg a "$1" '(.refusal_policy // {})[$a] // "exclude"' "$MAN_PATH" || die "MANIFEST.json unreadable: $MAN_PATH"
}
refusal_has_fallback() {  # refusal_has_fallback <run-dir> → 0 when a phase record carries a refusal fallback (KF-051)
  jq -e '[.phases // [] | .[] | select((.refusal_fallbacks // []) | length > 0)] | length > 0' "$1/meta/pipeline.json" >/dev/null 2>&1
}
refusal_record_of() { printf '%s.refusal-1.json' "$1"; }   # <trial base dir> → the immutable first-attempt record
REF_FRESH=0
# refusal_pre <jid> <arm> <base> <prior> <prior_usd> <run_id> — a trial's start: with the first attempt's record present
# (this job's relaunch, or a resume after the first attempt) the trial is the second attempt. REF_PRIOR and
# REF_PRIOR_USD add the record's attempts and spend, and the spend is queued for the collect charge
# (<jid>.refusal), except on a --rerun replacement of the second attempt's row, whose old row already counted them
refusal_pre() {
  REF_PRIOR="$4" REF_PRIOR_USD="$5"
  local rec att usd; rec="$(refusal_record_of "$3")"
  [[ -f "$rec" ]] || return 0
  if [[ "$REF_FRESH" != 1 ]] && is_rerun "$6"; then return 0; fi
  att="$(jq -r '.attempts | tostring' "$rec")" && usd="$(jq -r '.cost_usd | tostring' "$rec")" || die "refusal record unreadable: $rec"
  REF_PRIOR=$((REF_PRIOR + att)) REF_PRIOR_USD="$(fadd "$REF_PRIOR_USD" "$usd")"
  printf '%s\n' "$usd" > "$JOBS_DIR/$1.refusal"
}
# refusal_relaunch <arm> <base> <run-dir> <final status> <override> <prior> <attempts> <first_usd> <log> → 0 when the
# first attempt was just recorded and the trial is to be relaunched once, 1 otherwise
refusal_relaunch() {
  local arm="$1" base="$2" rd="$3" st="$4" ov="$5" prior="$6" att="$7" first="$8" tlog="$9" rec tmp
  [[ -z "$ov" ]] || return 1
  case "$st" in completed|agent_error|cap_failure) ;; *) return 1 ;; esac
  refusal_has_fallback "$rd" || return 1
  [[ "$(refusal_policy_of "$arm")" == rerun-once ]] || return 1
  rec="$(refusal_record_of "$base")"
  [[ ! -e "$rec" ]] || return 1   # this is the second attempt (or an earlier driver's): never a third
  if [[ $((prior + att)) -ge 3 ]]; then
    printf '%s run-ablation: refusal fallback (KF-051) under refusal_policy rerun-once; not relaunched: %d attempts used, the limit is 3 (D-7.3)\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$((prior + att))" >> "$tlog"
    return 1
  fi
  tmp="$rec.tmp.$$"
  jq --arg rd "$(basename "$rd")" --arg st "$st" --argjson att "$att" --arg first "$first" '
      {schema_version: 1, attempt: 1, run_id: (.run_id // null), run_dir: $rd, status: $st, attempts: $att,
       cost_usd: ((.spent_usd // 0 | tonumber? // 0) + ($first | tonumber)),
       refusal_fallbacks: [.phases // [] | .[] | select((.refusal_fallbacks // []) | length > 0)
                           | {label: (.label // .name // null), refusal_fallbacks}]}' "$rd/meta/pipeline.json" > "$tmp" \
    || { rm -f "$tmp"; die "refusal record for $rd could not be written"; }
  if ! ln "$tmp" "$rec" 2>/dev/null; then   # another writer won, or no hard links here: never overwrite, no relaunch
    rm -f "$tmp"
    printf '%s run-ablation: refusal record %s not written (exists or no hard link); not relaunched\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rec" >> "$tlog"
    return 1
  fi
  rm -f "$tmp"
  printf '%s run-ablation: refusal fallback (KF-051) under refusal_policy rerun-once: attempt 1 kept in %s (%s); relaunching once\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rd" "$rec" >> "$tlog"
  REF_FRESH=1
  return 0
}
refusal_row_args() {  # refusal_row_args <run-dir> → REF_ROW_ARGS: the second attempt's ablation-row.sh flags
  REF_ROW_ARGS=()
  local rd="$1" base="$1" rec first
  [[ "$rd" =~ ^(.*)-r[0-9]+$ ]] && base="${BASH_REMATCH[1]}"
  rec="$(refusal_record_of "$base")"
  [[ -f "$rec" ]] || return 0
  first="$(dirname "$base")/$(jq -r '.run_dir' "$rec")" || die "refusal record unreadable: $rec"
  [[ "$first" != "$rd" ]] || return 0
  REF_ROW_ARGS=(--refusal-attempt 2 --refused-attempt "$first")
}
refusal_collect() {  # refusal_collect <jid> — the queued first-attempt spend (rerun-once) to spent and the ledger
  local f="$JOBS_DIR/$1.refusal" u
  [[ -f "$f" ]] || return 0
  u="$(cat "$f")"
  SPENT="$(fadd "$SPENT" "$u")"; LEDGER_USD="$(fadd "$LEDGER_USD" "$u")"
  log "refusal_policy rerun-once: the refused first attempt's USD $u charged to spent"
}

ALL_TASKS=()
while IFS= read -r d; do ALL_TASKS+=("$d"); done < <(cd "$TDIR" && for d in */; do d="${d%/}"; [[ -f "$d/task.yaml" ]] && printf '%s\n' "$d"; done | LC_ALL=C sort)
[[ ${#ALL_TASKS[@]} -gt 0 ]] || die "no tasks under $TDIR"
SEL_TASKS=()
if [[ -n "$TASKS_CSV" && "$RESUME" != true ]]; then
  IFS=',' read -r -a SEL_TASKS <<<"$TASKS_CSV"
  for t in "${SEL_TASKS[@]}"; do
    [[ "$t" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || die "invalid task id '$t'"
    [[ -f "$TDIR/$t/task.yaml" ]] || die "task not found: $TDIR/$t/task.yaml"
  done
else
  SEL_TASKS=("${ALL_TASKS[@]}")
fi
WANT_TYPES=""
if [[ -n "$TYPES_CSV" ]]; then
  IFS=',' read -r -a tl <<<"$TYPES_CSV"
  for ty in "${tl[@]}"; do
    case "$ty" in
      build) WANT_TYPES="$WANT_TYPES feature-build bug-fix refactor" ;;
      feature-build|bug-fix|refactor|review-catch) WANT_TYPES="$WANT_TYPES $ty" ;;
      *) die "invalid --types entry '$ty'" ;;
    esac
  done
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/run-ablation.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
printf '%s\n' "$SUITE_JSON" > "$WORK/suite.json"
for t in "${SEL_TASKS[@]}"; do
  yq -o=json '{"id": .id, "type": .type, "bounds": (.bounds // {}), "bsm": (.review_catch.bare_sessions_matched // null),
               "bsmf": (.review_catch.bare_sessions_matched_fable // null)}' "$TDIR/$t/task.yaml" \
    | jq -c --arg y "$TDIR/$t/task.yaml" --arg want "$WANT_TYPES" \
        'select($want == "" or (.type as $t | ($want | split(" ") | map(select(. != ""))) | index($t)) != null) | with_entries(.) + {yaml: $y}'   # .type is the task'"'"'s, not the list'"'"'s (Sprint 261 dry run; RAB-27)
done | jq -s -c '.' > "$WORK/tasks.json" || die "a task.yaml does not parse"
[[ "$(jq 'length' "$WORK/tasks.json")" -gt 0 ]] || die "no task left after --tasks/--types"
jq -e 'all(.[]; (.type == "feature-build" or .type == "bug-fix" or .type == "refactor" or .type == "review-catch"))' \
  "$WORK/tasks.json" >/dev/null || die "a task has an unknown type"
TB="${TRIALS_BUILD:-}" TR="${TRIALS_REVIEW:-}"
if [[ "$SMOKE" == true ]]; then TB="${TB:-1}" TR="${TR:-1}"; fi
[[ -n "$TB" ]] || TB="$(jq -r '.trials.build // 3' <<<"$SUITE_JSON")"
[[ -n "$TR" ]] || TR="$(jq -r '.trials["review-catch"] // 3' <<<"$SUITE_JSON")"
[[ "$TB" =~ ^[1-9]$ && "$TR" =~ ^[1-9]$ ]] || die "suite trials must be 1-9"

# --- helpers ------------------------------------------------------------------------------
sha_file() { python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1"; }
semver_of() { grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<<"$1" | head -1 || true; }
# drift_check <run-dir> <run_id> → two lines: the drift {run_id, field, expected, got} or null,
# then the extra models {<raw id>: {phases: [<label>…], output_tokens: N}} ({} when none).
# Read-only on the run dir. A phase drifts on model grounds only when its model_requested
# differs from MANIFEST phase_models[name] (BARE: global.anthropic.claude-fable-5-1 when the
# run's arm_toggles set bare_model: fable, cycle-131), or when the requested model (else the manifest's)
# is absent from a non-empty models_used; any other models_used key is an extra model (a
# WebFetch summariser or a built-in subagent: telemetry, DEC-0545)
drift_check() {
  python3 -I - "$1" "$MAN_PATH" "$2" <<'PY'
import glob, json, os, re, sys
rd, man, rid = sys.argv[1:4]
m = json.load(open(man)); p = json.load(open(os.path.join(rd, "meta", "pipeline.json")))
def norm(x):   # ablation-row.sh norm_model
    x = re.sub(r"^([a-z]+\.)?anthropic\.", "", str(x)); return re.sub(r"-v[0-9]+(:[0-9]+)?$", "", x)
pm = dict(m.get("phase_models") or {})
# cycle-131 D-5.1: an arm whose toggles set bare_model: fable runs BARE on Fable 5.1 (pipeline-run.sh)
if (p.get("arm_toggles") or {}).get("bare_model") == "fable":
    pm["BARE"] = "global.anthropic.claude-fable-5-1"
extra, first = {}, None
def hit(field, exp, got):
    global first
    if first is None: first = {"run_id": rid, "field": field, "expected": exp, "got": got}
for ph in p.get("phases") or []:
    if not isinstance(ph, dict) or ph.get("skipped"): continue
    name, label = ph.get("name") or "", ph.get("label") or ph.get("name") or ""
    req = ph.get("model_requested")
    if name in pm and req is not None and norm(req) != norm(pm[name]):
        hit("model_requested." + label, pm[name], req)
    mu = ph.get("models_used") if isinstance(ph.get("models_used"), dict) else {}
    want = req if isinstance(req, str) and req else pm.get(name)
    if not mu or not want: continue
    if norm(want) not in {norm(k) for k in mu}:
        hit("models_used." + label, norm(pm.get(name) or want), sorted(mu))
        continue
    for k in sorted(mu):
        if norm(k) == norm(want): continue
        e = extra.setdefault(k, {"phases": [], "output_tokens": 0})
        e["phases"].append(label)
        v = mu[k]
        if isinstance(v, (int, float)) and not isinstance(v, bool): e["output_tokens"] += int(v)
if first is None:
    want, seen = m.get("cli_version") or "", []
    for f in sorted(glob.glob(os.path.join(rd, "transcripts", "events-*.jsonl"))):
        with open(f, encoding="utf-8", errors="replace") as fh:
            for n, line in enumerate(fh):
                if n > 200: break
                if '"init"' not in line: continue
                try: e = json.loads(line)
                except ValueError: continue
                if isinstance(e, dict) and e.get("type") == "system" and e.get("subtype") == "init":
                    v = e.get("claude_code_version") or e.get("version")
                    if isinstance(v, str) and v: seen.append((os.path.basename(f), v))
                    break
    if seen and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", want):
        for f, v in seen:
            got = re.search(r"[0-9]+\.[0-9]+\.[0-9]+", v)
            if (got.group(0) if got else v) != want: hit("cli_version", want, v); break
    elif not seen and m.get("image_digest") and p.get("image_digest") and m["image_digest"] != p["image_digest"]:
        hit("image_digest", m["image_digest"], p["image_digest"])
print(json.dumps(first) if first is not None else "null")
print(json.dumps(extra, sort_keys=True))
PY
}
LOG=""
log() { local l; l="$(date -u +%H:%M:%SZ) $*"; printf '%s\n' "$l" >&2; [[ -z "$LOG" ]] || printf '%s\n' "$l" >> "$LOG"; }

# --- pre-flight ----------------------------------------------------------------------
GATE_JSON=null
if [[ "$SMOKE" != true ]]; then
  [[ -f "$SUITE_ROOT/MANIFEST.sha256" ]] || refuse "hard gate (DEC-0435): $SUITE_ROOT/MANIFEST.sha256 is missing (freeze the suite first)"
  [[ -f "$SELF_CHECK_LOG" ]] || refuse "hard gate (DEC-0435): the self-check log $SELF_CHECK_LOG is missing"
  n_all=${#ALL_TASKS[@]} n_rc=0
  for t in "${ALL_TASKS[@]}"; do [[ "$(yq -r '.type' "$TDIR/$t/task.yaml")" == review-catch ]] && n_rc=$((n_rc + 1)); done
  want_pass=$(( 2 * n_all + n_rc ))
  got_pass="$(grep -cE ': PASS( |$)' "$SELF_CHECK_LOG" || true)"
  got_fail="$(grep -cE ': FAIL( |$)' "$SELF_CHECK_LOG" || true)"
  [[ "$got_fail" -eq 0 ]] || refuse "hard gate (DEC-0435): the self-check log has $got_fail FAIL line(s)"
  [[ "$got_pass" -ge "$want_pass" ]] || refuse "hard gate (DEC-0435): the self-check log has $got_pass PASS lines, want $want_pass (2 x $n_all tasks + $n_rc review-catch)"
  missing_review=""
  for t in "${ALL_TASKS[@]}"; do [[ -f "$TDIR/$t/REVIEW.md" ]] || missing_review="$missing_review $t"; done
  [[ -z "$missing_review" ]] || refuse "hard gate (DEC-0435): no REVIEW.md in tasks/{${missing_review# }}"
  GATE_JSON="$(python3 -I - "$SUITE_ROOT" "$SELF_CHECK_LOG" "$got_pass" "${ALL_TASKS[@]}" <<'PY'
import hashlib, json, os, sys
root, log, npass, tasks = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4:]
h = lambda p: hashlib.sha256(open(p, "rb").read()).hexdigest()
print(json.dumps({"manifest": os.path.join(root, "MANIFEST.sha256"), "manifest_sha256": h(os.path.join(root, "MANIFEST.sha256")),
                  "self_check_log": log, "self_check_log_sha256": h(log), "self_check_pass_lines": npass,
                  "review_md": {t: h(os.path.join(root, "tasks", t, "REVIEW.md")) for t in tasks}}, sort_keys=True))
PY
)"
fi
FREEZE_ARGS=(--check --root "$SUITE_ROOT" --suite-file "$SUITE_FILE")
if [[ "$SMOKE" == true ]] || grep -q '  smoke/' "$SUITE_ROOT/MANIFEST.sha256" 2>/dev/null; then FREEZE_ARGS+=(--smoke); fi
[[ "$ALLOW_PARTIAL" == true ]] && FREEZE_ARGS+=(--allow-partial)
frc=0; fout="$("$FREEZE_BIN" "${FREEZE_ARGS[@]}" 2>&1)" || frc=$?
[[ $frc -eq 0 ]] || refuse "freeze.sh ${FREEZE_ARGS[*]} failed (exit $frc): $(printf '%s' "$fout" | tail -5 | tr '\n' ' ')"
SUITE_MANIFEST_SHA="$(sha_file "$SUITE_ROOT/MANIFEST.sha256")"
crc=0; cout="$("$CORPUS_BIN" --check 2>&1)" || crc=$?
[[ $crc -eq 0 ]] || refuse "seed-corpus-from-record.sh --check failed (exit $crc): $(printf '%s' "$cout" | tail -3 | tr '\n' ' ')"
CORPUS_SHA="$(sha_file "$REPO_ROOT/evals/fixtures/review-prs/SHA256SUMS" 2>/dev/null || echo "")"

IMAGE_DIGEST=""
if [[ "$EXECUTOR" == container ]]; then
  command -v "$DOCKER_BIN" >/dev/null 2>&1 || [[ -x "$DOCKER_BIN" ]] || refuse "docker CLI not found: $DOCKER_BIN"
  IMAGE_DIGEST="$("$DOCKER_BIN" image inspect --format '{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}{{.Id}}{{end}}' "$IMAGE" 2>/dev/null | head -1 || true)"
  [[ -n "$IMAGE_DIGEST" ]] || refuse "image $IMAGE not found (docker image inspect)"
fi

if [[ -n "${LOA_ABLATION_SOURCE_TREE:-}" ]]; then
  TREE="$(abspath "$LOA_ABLATION_SOURCE_TREE")"
  [[ -d "$TREE/.claude" ]] || refuse "LOA_ABLATION_SOURCE_TREE $TREE has no .claude/"
  SRC_FULL="$(git -C "$TREE" rev-parse --verify --quiet "${SOURCE_COMMIT}^{commit}" 2>/dev/null)" \
    || refuse "source commit $SOURCE_COMMIT is not in $TREE"
  [[ "$(git -C "$TREE" rev-parse HEAD 2>/dev/null)" == "$SRC_FULL" ]] || refuse "$TREE is not at $SRC_FULL"
  DELTA_REPO="$TREE"
else
  SRC_FULL="$(git -C "$SOURCE_REPO" rev-parse --verify --quiet "${SOURCE_COMMIT}^{commit}" 2>/dev/null)" \
    || refuse "source commit $SOURCE_COMMIT is not in $SOURCE_REPO"
  TREE="$CACHE_ROOT/ablation-src-${SRC_FULL:0:12}"
  if [[ -e "$TREE" ]]; then
    [[ "$(git -C "$TREE" rev-parse HEAD 2>/dev/null)" == "$SRC_FULL" ]] || refuse "$TREE exists but is not at $SRC_FULL; remove it with git worktree remove"
  else
    mkdir -p "$CACHE_ROOT"
    git -C "$SOURCE_REPO" worktree add --detach "$TREE" "$SRC_FULL" >/dev/null 2>&1 || refuse "could not create the source worktree at $TREE"
  fi
  DELTA_REPO="$SOURCE_REPO"
fi
[[ -z "$(git -C "$TREE" status --porcelain --ignored 2>/dev/null)" ]] \
  || refuse "$TREE has local or ignored files; the pinned source must be pristine (git -C $TREE status --ignored)"

if [[ "$EXECUTOR" == container ]]; then
  tmo=(); command -v timeout >/dev/null 2>&1 && tmo=(timeout 120)
  CLI_RAW="$(${tmo[@]+"${tmo[@]}"} "$DOCKER_BIN" run --rm --network none "$IMAGE" claude --version 2>/dev/null | head -1 || true)"
else
  CLI_RAW="$("${EVAL_CLAUDE_BIN:-claude}" --version 2>/dev/null | head -1 || true)"
fi
CLI_VERSION="$(semver_of "$CLI_RAW")"; [[ -n "$CLI_VERSION" ]] || CLI_VERSION=unknown
FINGERPRINT="$("$FP_BIN" --source-tree "$TREE" --claude-bin "${EVAL_CLAUDE_BIN:-claude}" 2>/dev/null || echo "")"
[[ "$EXECUTOR" == host ]] && IMAGE_DIGEST="$FINGERPRINT"
DELTA="$(git -C "$DELTA_REPO" diff --stat "$DELTA_BASE..$SRC_FULL" -- .claude/ 2>/dev/null)" \
  || DELTA="unavailable: $DELTA_BASE is not in $DELTA_REPO"
DELTA="${DELTA:0:4000}"

if [[ "$RESUME" == true ]]; then
  for pair in "source_commit|$SRC_FULL" "suite_manifest_sha256|$SUITE_MANIFEST_SHA" "image_digest|$IMAGE_DIGEST" "cli_version|$CLI_VERSION"; do
    k="${pair%%|*}" v="${pair#*|}"
    [[ "$(jq -r --arg k "$k" '.[$k] // ""' "$MAN_PATH")" == "$v" ]] \
      || refuse "resume: $k is now '$v', the batch recorded '$(jq -r --arg k "$k" '.[$k] // ""' "$MAN_PATH")' (DEC-0407)"
  done
fi

# --- cycle-132: the registration binds this batch (D-5.2, D-7.2) and derives its spend gate -----------
if [[ -n "$REGISTRATION" && "$RESUME" != true ]]; then
  REGISTRATION="$(abspath "$REGISTRATION")"
  [[ -f "$REGISTRATION" ]] || refuse "registration not found: $REGISTRATION"
  REG_SHA="$(sha_file "$REGISTRATION")"
  REG_JSON="$(jq -c 'if type == "object" and .schema_version == 1 then
      {preregistration_sha256, corpus_sha256sums_sha256, suite_manifest_sha256, analysis_tree_sha256,
       pin, image_digest, cap_usd, kickoff, supersedes, label_set, seed}
    else error("not a schema_version 1 registration object") end' "$REGISTRATION" 2>/dev/null)" \
    || refuse "registration $REGISTRATION is not a schema_version 1 JSON object"
  reg_val() { jq -r --arg k "$1" '.[$k] // "" | tostring' <<<"$REG_JSON"; }
  [[ "$(reg_val suite_manifest_sha256)" == "$SUITE_MANIFEST_SHA" ]] \
    || refuse "registration binds suite_manifest_sha256 $(reg_val suite_manifest_sha256), the suite root's MANIFEST.sha256 is $SUITE_MANIFEST_SHA"
  [[ "$(reg_val corpus_sha256sums_sha256)" == "$CORPUS_SHA" ]] \
    || refuse "registration binds corpus_sha256sums_sha256 $(reg_val corpus_sha256sums_sha256), the corpus SHA256SUMS is ${CORPUS_SHA:-<absent>}"
  reg_pin="$(reg_val pin)"
  [[ "$reg_pin" =~ ^[0-9a-f]{7,40}$ && "$SRC_FULL" == "$reg_pin"* ]] \
    || refuse "registration binds pin ${reg_pin:-<none>}, the batch runs $SRC_FULL"
  reg_img="$(reg_val image_digest)"
  [[ -z "$reg_img" || "$reg_img" == "$IMAGE_DIGEST" ]] || refuse "registration binds image_digest $reg_img, the image is $IMAGE_DIGEST"
  # the spend gate (Task 1.7c): --max-usd = the registered cap − the cycle meter since the kickoff
  reg_cap="$(reg_val cap_usd)"
  since="${SPEND_SINCE:-$(reg_val kickoff)}"
  [[ -n "$since" ]] || refuse "--registration needs the cycle meter's kickoff: --spend-since TS or the registration's kickoff"
  usd_ok "$reg_cap" || refuse "registration cap_usd ${reg_cap:-<none>} is not an amount in USD"
  sp_rc=0; sp_json="$("$SPEND_BIN" --since "$since" --json 2>/dev/null)" || sp_rc=$?
  sp_total="$(jq -r 'if type == "object" and .complete == true and (.total_usd | type) == "number" then .total_usd | tostring else "" end' <<<"$sp_json" 2>/dev/null || true)"
  [[ $sp_rc -eq 0 && -n "$sp_total" ]] || refuse "spend.sh --since $since --json did not give a complete total (exit $sp_rc); the spend gate cannot be derived"
  derived="$(awk -v c="$reg_cap" -v s="$sp_total" 'BEGIN { printf "%.10g", c - s }')"
  awk -v d="$derived" 'BEGIN { exit !(d > 0) }' || refuse "the registered cap USD $reg_cap minus the cycle spend USD $sp_total since $since leaves USD $derived: no batch budget"
  given="$MAX_USD"
  if [[ -z "$MAX_USD" ]] || awk -v d="$derived" -v m="$MAX_USD" 'BEGIN { exit !(d < m) }'; then MAX_USD="$(awk -v d="$derived" 'BEGIN { printf "%.10g", d }')"; fi
  SPEND_GATE_JSON="$(jq -cn --arg c "$reg_cap" --arg s "$since" --arg t "$sp_total" --arg d "$derived" --arg g "$given" --arg m "$MAX_USD" \
    '{cap_usd: ($c | tonumber), since: $s, cycle_spent_usd: ($t | tonumber), derived_max_usd: ($d | tonumber),
      max_usd_given: (if $g == "" then null else ($g | tonumber) end), max_usd: ($m | tonumber)}')"
  echo "run-ablation: spend gate: registered cap USD $reg_cap − cycle spend USD $sp_total since $since = USD $derived; batch --max-usd $MAX_USD" >&2
fi

# --- the plan ----------------------------------------------------------------------------
if [[ "$RESUME" == true ]]; then
  jq -c '{plan, refused}' "$MAN_PATH" > "$WORK/plan.json"
else
  python3 -I - "$WORK/suite.json" "$WORK/tasks.json" "$ARMS_CSV" "$SEED" "$BATCH" "$TB" "$TR" > "$WORK/plan.json" <<'PY' \
    || die "the plan could not be built (see the line above)"
import json, random, sys
suite = json.load(open(sys.argv[1])); tasks = sorted(json.load(open(sys.argv[2])), key=lambda t: t["id"])
arms, seed, batch, tb, tr = sys.argv[3].split(","), int(sys.argv[4]), sys.argv[5], int(sys.argv[6]), int(sys.argv[7])
defs = {a.get("id"): a for a in suite.get("arms") or []}
BUILTIN = {"PLAN": 15, "IMPLEMENT": 25, "REVIEW": 20, "AUDIT": 20, "FIX": 15, "BARE": 70}
def kind(t): return "review-catch" if t == "review-catch" else "build"
def applies(a, t):
    tt = a.get("task_types")
    tt = ["all"] if tt is None else tt
    return "all" in tt or kind(t) in tt or t in tt
def phases(a, k):   # pipeline-run.sh plan_phases
    p = a.get("phases")
    if p is None: p = (suite.get("phase_sets") or {}).get(k)
    if p is None: p = ["REVIEW", "AUDIT"] if k == "review-catch" else ["PLAN", "IMPLEMENT", "REVIEW", "FIX", "AUDIT", "FIX"]
    tg = a.get("toggles") or {}
    if tg.get("loa_mount") is False: p = ["BARE"]
    if tg.get("sprint_plan") is False: p = [x for x in p if x != "PLAN"]
    if tg.get("gates") is False and "IMPLEMENT" in p: p = p[: p.index("IMPLEMENT") + 1]
    return p
def tmin(name, task):   # pipeline-run.sh phase_cap timeout_min
    v = ((task.get("bounds") or {}).get("timeout_min") or {}).get(name)
    if v is None: v = ((suite.get("phase_defaults") or {}).get("timeout_min") or {}).get(name)
    if v is None and name == "BARE": return tmin("PLAN", task) + tmin("IMPLEMENT", task) + 2 * tmin("FIX", task)
    return int(v if v is not None else BUILTIN.get(name, 20))
def matched_k(a, t):   # cycle-132 FR-3: a matched arm's k for the task, None for any other arm
    d = defs[a]
    if (d.get("toggles") or {}).get("bare_sessions") != "matched":
        return None
    k = t.get("bsm")
    if (d.get("toggles") or {}).get("bare_model") == "fable" and t.get("bsmf") is not None:
        k = t.get("bsmf")
    if not (isinstance(k, int) and not isinstance(k, bool) and 2 <= k <= 30):
        print("run-ablation: matched arm %s needs review_catch.bare_sessions_matched (an integer 2 … 30) on task %s"
              % (a, t["id"]), file=sys.stderr)
        sys.exit(3)
    return k
refused, pairs = [], []
for a in arms:
    d = defs[a]
    for t in tasks:
        if applies(d, t["type"]):
            matched_k(a, t)
            pairs.append((a, t))
        else:
            refused.append({"arm": a, "task_id": t["id"], "type": t["type"], "task_types": d.get("task_types")})
rng = random.Random(seed)
plan = []
for trial in range(1, max(tb, tr) + 1):
    block = [(a, t) for a, t in pairs if trial <= (tr if t["type"] == "review-catch" else tb)]
    rng.shuffle(block)
    for a, t in block:
        ps = phases(defs[a], kind(t["type"]))
        s = sum(tmin(n, t) for n in ps)
        e = {"i": len(plan) + 1, "arm": a, "task_id": t["id"], "type": t["type"], "kind": kind(t["type"]),
             "trial": trial, "run_id": f"{batch}-{a}-{t['id']}-t{trial}", "run_dir": f"{a}/{t['id']}-t{trial}",
             "task_yaml": t["yaml"], "phases": ps, "phase_sum_min": s, "watchdog_s": 2 * s * 60}
        k = matched_k(a, t)
        if k is not None:
            e["bare_sessions"] = k   # k session units; watchdog_s is per session
        plan.append(e)
print(json.dumps({"plan": plan, "refused": refused}))
PY
fi
jq -c '.plan' "$WORK/plan.json" > "$WORK/plan-only.json"
PLAN_N="$(jq 'length' "$WORK/plan-only.json")"
[[ "$PLAN_N" -gt 0 ]] || die "the plan is empty: every arm is refused on every selected task (task_types)"

# --- codex token freshness (KF-048): the access token must outlive the batch's horizon -------
# The per-run HOME carries a placeholder refresh token (pipeline-run.sh), so a container cannot renew an
# expired access token; a batch that would outlive it degrades every codex-using row. Only the
# JWT payload's exp claim is read (no signature check); no token value is printed.
CODEX_AUTH="${LOA_EVAL_CREDS_HOME:-$HOME}/.codex/auth.json"
CODEX_SKIP=false; [[ "$SMOKE" == true ]] && CODEX_SKIP=true
# the trials this invocation launches: every plan entry on a fresh batch (and a dry run); on --resume the
# entries without a row of this batch, plus the --rerun ids, the --rerun-status rows and STATUS.json
# rerun_pending (never a --rerow id)
jq -n --argjson resume "$RESUME" --arg rows "$ROWS" --arg batch "$BATCH" \
  --argjson ids "$(json_array ${RERUN_IDS[@]+"${RERUN_IDS[@]}"})" \
  --argjson sts "$(json_array ${RERUN_STATUSES[@]+"${RERUN_STATUSES[@]}"})" \
  --argjson rerow "$(json_array ${REROW_IDS[@]+"${REROW_IDS[@]}"})" \
  --arg status "$BATCH_DIR/STATUS.json" \
  '{resume: $resume, rows: $rows, batch: $batch, rerun_ids: $ids, rerun_statuses: $sts, rerow_ids: $rerow, status: $status}' > "$WORK/codex-scope.json"
CODEX_PF="$(python3 -I - "$CODEX_AUTH" "$WORK/plan-only.json" "$WORK/suite.json" "$CONCURRENCY" "$CODEX_SKIP" \
  "$WORK/codex-scope.json" "$CODEX_HORIZON_OVERRIDE" <<'PY'
import base64, json, math, os, sys, time
auth, plan_p, suite_p, conc, skip = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5] == "true"
scope = json.load(open(sys.argv[6])); override = int(sys.argv[7]) if sys.argv[7] else None
plan = json.load(open(plan_p)); suite = json.load(open(suite_p))
defs = {a.get("id"): a for a in suite.get("arms") or []}
iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
def uses_codex(a):   # a0_bare (loa_mount: false) never runs the dissent
    return ((defs.get(a) or {}).get("toggles") or {}).get("loa_mount") is not False
arms = sorted({e["arm"] for e in plan if uses_codex(e["arm"])})
present = os.path.isfile(auth)
pf = {"checked": False, "auth_file_present": present, "codex_arms": arms, "token_exp": None, "required_until": None,
      "auth_mode": None, "trials_counted": None, "horizon_source": None}
out = {"preflight": pf, "refuse": None, "warn": None, "note": None}
def done():
    print(json.dumps(out, sort_keys=True)); sys.exit(0)
if skip or not arms:
    done()
if not present:
    out["warn"] = "run-ablation: WARN no codex auth.json under %s; codex-using arms will run without the OpenAI voice" % os.path.dirname(auth)
    done()
def pending():   # STATUS.json rerun_pending: flagged by an earlier invocation, no replacement row yet
    try:
        v = json.load(open(scope["status"], "rb")).get("rerun_pending")
    except Exception:
        return set()
    return {x for x in v if isinstance(x, str) and x} if isinstance(v, list) else set()
def remaining():   # the plan entries this invocation will launch (a superset on rerun_pending; see the header)
    if not scope["resume"] or not os.path.isfile(scope["rows"]):
        return plan
    st = {}
    for line in open(scope["rows"], "rb"):
        try:
            r = json.loads(line.decode("utf-8"))
        except Exception:
            continue
        if isinstance(r, dict) and r.get("batch") == scope["batch"] and isinstance(r.get("run_id"), str):
            st[r["run_id"]] = r.get("status")
    ids, sts, rerow = ({x for x in scope[k] if x} for k in ("rerun_ids", "rerun_statuses", "rerow_ids"))   # json_array of none is [""]
    pend = pending() - rerow
    return [e for e in plan if e["run_id"] not in st or e["run_id"] in ids or e["run_id"] in pend
            or (st[e["run_id"]] in sts and e["run_id"] not in rerow)]
now = time.time()
todo = remaining()
pf["trials_counted"] = len(todo)
if override is not None:
    required = int(math.ceil(now + override)); pf["horizon_source"] = "override"
else:
    # DISS-C-001: never below one trial's own deadline (one trial at concurrency 3 still takes its whole watchdog)
    wds = [float(e.get("watchdog_s") or 0) for e in todo]
    units = [w * int(e.get("bare_sessions") or 1) for w, e in zip(wds, todo)]   # cycle-132: a matched cell is k session units
    required = int(math.ceil(now + 2 * max(sum(units) / max(conc, 1), max(wds or [0]))))
    pf["horizon_source"] = "plan"
pf["required_until"] = iso(required)
REMEDY = "run codex login on the host, or set OPENAI_API_KEY in auth.json"
def bad(why, remedy="run codex login on the host"):
    out["refuse"] = "codex auth.json %s: %s (KF-048) — %s" % (auth, why, remedy); done()
try:
    data = json.loads(open(auth, "rb").read().decode("utf-8"))
except Exception:
    bad("is not JSON", REMEDY)
if not isinstance(data, dict):
    bad("is not a JSON object", REMEDY)
tok = data.get("tokens") or {}
at = tok.get("access_token") if isinstance(tok, dict) else None
if not isinstance(at, str) or not at:
    key = data.get("OPENAI_API_KEY")
    if isinstance(key, str) and key.strip():   # API-key mode: no access token, no refresh, no horizon
        pf["auth_mode"] = "apikey"
        out["note"] = ("run-ablation: codex auth.json is in API-key mode; no token horizon applies "
                       "(KF-048 concerns the ChatGPT refresh token only)")
        done()
    bad("has neither a tokens.access_token nor an OPENAI_API_KEY", REMEDY)
pf["auth_mode"] = "chatgpt"
parts = at.split(".")
if len(parts) != 3:
    bad("tokens.access_token is not a three-part JWT")
try:
    seg = parts[1] + "=" * (-len(parts[1]) % 4)
    claims = json.loads(base64.urlsafe_b64decode(seg.encode("ascii")).decode("utf-8"))
except Exception:
    bad("the access token's JWT payload does not decode")
exp = claims.get("exp") if isinstance(claims, dict) else None
if isinstance(exp, bool) or not isinstance(exp, (int, float)) or not math.isfinite(exp):
    bad("the access token has no numeric exp claim")
exp = int(exp)
pf["checked"] = True; pf["token_exp"] = iso(exp)
if exp <= required:
    how = ("now + LOA_ABLATION_CODEX_HORIZON_S" if override is not None
           else "now + 2 x max(summed watchdog of %d trial(s) / concurrency, longest watchdog)" % len(todo))
    out["refuse"] = ("codex access token expires %s, before the batch's required horizon %s "
                     "(%s; KF-048) — run codex login on the host") % (iso(exp), iso(required), how)
done()
PY
)" || die "the codex token pre-flight failed"
# DISS-C-002: held in a variable, not a $WORK file (write_status may run after cleanup removed $WORK)
CODEX_PF_JSON="$(jq -c '.preflight' <<<"$CODEX_PF")"
CODEX_WARN="$(jq -r '.warn // ""' <<<"$CODEX_PF")"
[[ -z "$CODEX_WARN" ]] || echo "$CODEX_WARN" >&2
CODEX_NOTE="$(jq -r '.note // ""' <<<"$CODEX_PF")"
[[ -z "$CODEX_NOTE" ]] || echo "$CODEX_NOTE" >&2
CODEX_REFUSE="$(jq -r '.refuse // ""' <<<"$CODEX_PF")"
[[ -z "$CODEX_REFUSE" ]] || refuse "$CODEX_REFUSE"
PL_ARM=() PL_TASK=() PL_TYPE=() PL_KIND=() PL_TRIAL=() PL_RUN=() PL_YAML=() PL_WD=() PL_K=()
while IFS=$'\t' read -r a t ty k tr rid y wd bk; do
  PL_ARM+=("$a"); PL_TASK+=("$t"); PL_TYPE+=("$ty"); PL_KIND+=("$k"); PL_TRIAL+=("$tr"); PL_RUN+=("$rid"); PL_YAML+=("$y"); PL_WD+=("$wd")
  PL_K+=("$bk")   # cycle-132: a matched cell's k (0 for a trial)
done < <(jq -r '.[] | [.arm, .task_id, .type, .kind, (.trial | tostring), .run_id, .task_yaml, (.watchdog_s | tostring),
                      ((.bare_sessions // 0) | tostring)] | @tsv' "$WORK/plan-only.json")
EST_TOTAL=0 N_CELLS=0 N_SESSIONS=0
for j in ${PL_KIND[@]+"${!PL_KIND[@]}"}; do
  n_units=1; [[ "${PL_K[$j]}" -gt 0 ]] && { n_units="${PL_K[$j]}"; N_CELLS=$((N_CELLS + 1)); N_SESSIONS=$((N_SESSIONS + n_units)); }
  for _u in $(seq 1 "$n_units"); do EST_TOTAL="$(fadd "$EST_TOTAL" "$(est_hint "x|${PL_KIND[$j]}")")"; done
done
N_TASKS="$(jq 'length' "$WORK/tasks.json")"
# the in-flight reservation per running trial: the largest cap among the plan's kinds (DEC-0567)
RESERVE_CAP=0
for k in ${PL_KIND[@]+"${PL_KIND[@]}"}; do
  c="$(cap_for "$k")"; awk -v c="$c" -v r="$RESERVE_CAP" 'BEGIN { exit !(c > r) }' && RESERVE_CAP="$c"
done
PLAN_UNITS=""; [[ $N_CELLS -gt 0 ]] && PLAN_UNITS=" ($N_SESSIONS session units in $N_CELLS matched cells)"
PLAN_LINE="plan: ${#ARMS[@]} arms, $N_TASKS tasks, $PLAN_N trials$PLAN_UNITS, shuffle seed $SEED, est USD $EST_TOTAL (cap ${MAX_USD:-none}, run caps build $CAP_BUILD review-catch $CAP_REVIEW, in-flight reserve $RESERVE_CAP per trial, reserve $(jq -r '.caps.reserve_usd // "n/a"' <<<"$SUITE_JSON"))"

write_manifest() {  # write_manifest <path> <dry_run>
  local out="$1" dry="$2" harness_commit harness_dirty=false
  harness_commit="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  [[ -n "$(git -C "$REPO_ROOT" status --porcelain -- evals/harness evals/suites grimoires/loa/evals/ablation-2.0 2>/dev/null)" ]] && harness_dirty=true
  mkdir -p "$(dirname "$out")"
  printf '%s' "$DELTA" > "$WORK/delta.txt"
  printf '%s' "$GATE_JSON" > "$WORK/gate.json"
  jq -n \
    --slurpfile plan_f "$WORK/plan.json" --slurpfile suite_f "$WORK/suite.json" --slurpfile tasks_f "$WORK/tasks.json" \
    --slurpfile gate_f "$WORK/gate.json" --rawfile delta "$WORK/delta.txt" --argjson cpf "$CODEX_PF_JSON" \
    --arg batch "$BATCH" --argjson dry "$dry" --argjson smoke "$SMOKE" --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg src "$SRC_FULL" --arg tree "$TREE" --arg hc "$harness_commit" --argjson hd "$harness_dirty" \
    --arg suite_file "${SUITE_FILE#"$REPO_ROOT"/}" --arg suite_file_path "$SUITE_FILE" --arg suite_root "$SUITE_ROOT" \
    --arg tasks_dir "$TASKS_DIR_NAME" --arg rows "$ROWS" --arg msha "$SUITE_MANIFEST_SHA" \
    --argjson arms "$(json_array "${ARMS[@]}")" --argjson tb "$TB" --argjson tr "$TR" --argjson seed "$SEED" \
    --arg fp "$FINGERPRINT" --arg image "$IMAGE" --arg digest "$IMAGE_DIGEST" --arg mode "$EXECUTOR" \
    --arg cli "$CLI_VERSION" --arg cli_raw "$CLI_RAW" --arg max_usd "$MAX_USD" --arg run_cap "$RUN_CAP" --arg cap_b "$CAP_BUILD" --arg cap_r "$CAP_REVIEW" \
    --arg hb "$HINT_BUILD" --arg hr "$HINT_REVIEW" --argjson conc "$CONCURRENCY" --argjson rw "$RETRY_WAIT" \
    --arg wdo "$WATCHDOG_OVERRIDE" --argjson grace "$WATCHDOG_GRACE" --arg gto "$GRADE_TIMEOUT_S" --arg tto "$TOOK_TIMEOUT_S" --argjson tmo "$TMO_ON" --arg prr "$PRE_REG_REF" \
    --arg corpus "$CORPUS_SHA" --arg os "$(uname -srm)" --arg bash_v "$BASH_VERSION" --argjson allow_partial "$ALLOW_PARTIAL" \
    --arg jq_v "$(jq --version 2>/dev/null)" --arg yq_v "$(yq --version 2>/dev/null)" \
    --arg py_v "$(python3 --version 2>/dev/null)" --arg git_v "$(git --version 2>/dev/null)" \
    --arg bctx "$BATCH_CONTEXT" --arg reg_sha "$REG_SHA" --arg reg_path "$REGISTRATION" --argjson reg "$REG_JSON" \
    --argjson sgate "$SPEND_GATE_JSON" --arg reserve "$RESERVE_CAP" '
    $plan_f[0] as $p | $suite_f[0] as $s | $gate_f[0] as $g
    | {schema_version: 1, suite: ($s.name // "ablation-2.0"), batch: $batch, dry_run: $dry, smoke: $smoke, created: $created,
       source_commit: $src, source_worktree: $tree, source_commit_dot_claude_delta: $delta,
       harness_commit: $hc, harness_dirty: $hd, suite_file: $suite_file, suite_file_path: $suite_file_path,
       suite_root: $suite_root, tasks_dir: $tasks_dir, rows_file: $rows,
       suite_version: ($s.suite_version // $s.version // null),
       suite_manifest_sha256: (if $msha == "" then null else $msha end),
       arms: $arms, tasks: [$tasks_f[0][] | {id, type}], refused: $p.refused,
       trials_per_type: {build: $tb, "review-catch": $tr}, trials_planned: ($p.plan | length),
       plan: $p.plan, arm_map: ([$p.plan[] | {(.run_id): .arm}] | add // {}),
       shuffle_seed: $seed, shuffle: "trial-major; python3 random.Random(shuffle_seed).shuffle per trial block, blocks in order",
       fingerprint: (if $fp == "" then null else $fp end), image: $image,
       image_digest: (if $digest == "" then null else $digest end), executor_mode: $mode,
       cli_version: $cli, cli_version_raw: $cli_raw,
       tools: ($s.phase_defaults.tools // null), phase_models: ($s.phase_defaults.models // {}),
       caps: {cycle_usd: ($s.caps.cycle_usd // null), run_usd: ($run_cap | tonumber), reserve_usd: ($s.caps.reserve_usd // null),
              max_usd: (if $max_usd == "" then null else ($max_usd | tonumber) end),
              run_usd_by_type: {build: ($cap_b | tonumber), "review-catch": ($cap_r | tonumber)}},
       cost_hint: {build: ($hb | tonumber), "review-catch": ($hr | tonumber)},
       concurrency: $conc, retry: {transport_retries: 1, wait_s: $rw},
       watchdog: {multiplier: 2, override_s: (if $wdo == "" then null else ($wdo | tonumber) end), grace_s: $grace,
                 grade_timeout_s: (if $tmo then ($gto | tonumber) else null end), took_effect_timeout_s: (if $tmo then ($tto | tonumber) else null end)},
       pre_registration_ref: (if $prr == "" then null else $prr end),
       gate: $g, corpus: {manifest: "evals/fixtures/review-prs/SHA256SUMS", sha256: (if $corpus == "" then null else $corpus end)},
       agy_opt_in: ($s.agy_opt_in // false), allow_partial: $allow_partial,
       codex_token_exp: ($cpf // {}).token_exp, codex_preflight: $cpf,
       overshoot_bound_usd: ($conc * ($reserve | tonumber)), batch_context: $bctx,
       bare_sessions_by_task: (reduce ($p.plan[] | select(.bare_sessions != null)) as $e ({}; .[$e.arm][$e.task_id] = $e.bare_sessions)),
       refusal_policy: (reduce ($s.arms // [] | .[] | select(.id as $i | $arms | index($i))) as $a ({}; .[$a.id] = ($a.refusal_policy // "exclude"))),
       registration_sha256: (if $reg_sha == "" then null else $reg_sha end),
       registration_path: (if $reg_sha == "" then null else $reg_path end),
       preregistration_sha256: (($reg // {}).preregistration_sha256 // null),
       registration: $reg, spend_gate: $sgate,
       environment: {os: $os, bash: $bash_v, jq: $jq_v, yq: $yq_v, python: $py_v, git: $git_v}}' > "$out.tmp"
  mv "$out.tmp" "$out"
}

if [[ "$DRY_RUN" == true ]]; then
  mpath="$MAN_PATH"; [[ -f "$BATCH_DIR/STATUS.json" ]] && mpath="$BATCH_DIR/MANIFEST.dry-run.json"
  write_manifest "$mpath" true
  echo "run-ablation (dry run): batch=$BATCH source=${SRC_FULL:0:12} executor=$EXECUTOR image=$IMAGE cli=$CLI_VERSION tree=$TREE"
  echo "$PLAN_LINE"
  jq -r '.refused[] | "refused: \(.arm) \(.task_id) \(.type) (task_types \(.task_types | tojson)) DEC-0405"' "$WORK/plan.json"
  jq -r '.[] | "\(.arm) \(.task_id) \(.type) \(.trial) \(.run_id)\(if .bare_sessions != null then " sessions \(.bare_sessions)" else "" end)"' "$WORK/plan-only.json"
  echo "manifest: $mpath"
  exit 0
fi

# --- --clear-drift and --rerow: checked read-only before the lock (a refusal writes nothing) --
run_dir_of() {  # run_dir_of <run_id> → <batch>/<arm>/<task>-t<n> or its highest -r<k> sibling; empty when none
  local rel base best k max=1 d
  rel="$(jq -r --arg r "$1" '[.[] | select(.run_id == $r) | .run_dir][0] // ""' "$WORK/plan-only.json")"
  [[ -n "$rel" ]] || return 0
  base="$BATCH_DIR/$rel" best=""
  [[ -d "$base" ]] && best="$base"
  for d in "$base"-r*; do
    [[ -d "$d" ]] || continue
    k="${d##*-r}"; [[ "$k" =~ ^[0-9]+$ ]] || continue
    if [[ $k -gt $max ]]; then max=$k best="$d"; fi
  done
  printf '%s' "$best"
}
CLEAR_PENDING=null
if [[ "$CLEAR_DRIFT" == true ]]; then
  old_drift="$(jq -c '.drift' "$BATCH_DIR/STATUS.json")"
  if [[ "$old_drift" == null ]]; then
    echo "run-ablation: resume: --clear-drift: the batch records no drift; nothing to clear" >&2
  else
    cd_rid="$(jq -r '.run_id // ""' <<<"$old_drift")"
    cd_rd="$(run_dir_of "$cd_rid")"
    [[ -n "$cd_rd" && -f "$cd_rd/meta/pipeline.json" ]] || die "resume: --clear-drift: no run dir with meta/pipeline.json for the drifted run $cd_rid"
    cd_now="$(drift_check "$cd_rd" "$cd_rid" | sed -n 1p)" || cd_now=""
    [[ -n "$cd_now" ]] || die "resume: --clear-drift $cd_rid: the drift guard could not read $cd_rd"
    [[ "$cd_now" == null ]] || die "resume: --clear-drift $cd_rid: the run still drifts under the current rule: $cd_now"
    CLEAR_PENDING="$(jq -cn --arg r "$cd_rid" --argjson prev "$old_drift" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg hc "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)" \
      '{run_id: $r, previous: $prev, cleared_at: $at, harness_commit: $hc}')"
  fi
fi
RR_K=() RR_RD=() RR_FROM=() RR_ATT=() RR_REASON=()
for rid in ${REROW_IDS[@]+"${REROW_IDS[@]}"}; do
  [[ "$rid" == "$BATCH-"* ]] || die "--rerow $rid: not a run of batch $BATCH (<batch>-<arm>-<task>-t<n>)"
  k=-1
  for j in "${!PL_RUN[@]}"; do [[ "${PL_RUN[$j]}" == "$rid" ]] && { k=$j; break; }; done
  [[ $k -ge 0 ]] || die "--rerow $rid: not in the batch's plan"
  [[ -f "$ROWS" ]] || die "--rerow $rid: no rows file $ROWS"
  rr_rows="$(jq -R -c --arg b "$BATCH" --arg r "$rid" 'fromjson? | select(type == "object" and .batch == $b and .run_id == $r)' "$ROWS")"
  rr_n="$(grep -c . <<<"$rr_rows" || true)"
  [[ "$rr_n" -eq 1 ]] || die "--rerow $rid: $rr_n rows in $ROWS (a rerow replaces exactly one)"
  rr_st="$(jq -r '.status' <<<"$rr_rows")"
  [[ "${PL_K[$k]}" -eq 0 ]] || die "--rerow $rid: a matched cell is rowed from its sessions once all k land; it is never rowed again (cycle-132 D-3.2)"
  case "$rr_st" in interrupted|transport_error) die "--rerow $rid: the row is $rr_st; that trial is a rerun (--resume after removing the row), not a rerow" ;; esac
  rr_rd="$(run_dir_of "$rid")"
  [[ -n "$rr_rd" && -f "$rr_rd/meta/pipeline.json" ]] || die "--rerow $rid: no run dir with meta/pipeline.json under $BATCH_DIR"
  RR_K+=("$k"); RR_RD+=("$rr_rd"); RR_FROM+=("$rr_st")
  RR_ATT+=("$(jq -r '.attempts // 1' <<<"$rr_rows")"); RR_REASON+=("$(jq -r '.retry_reason // ""' <<<"$rr_rows")")
done
for rid in ${RERUN_IDS[@]+"${RERUN_IDS[@]}"}; do
  [[ "$rid" == "$BATCH-"* ]] || die "--rerun $rid: not a run of batch $BATCH (<batch>-<arm>-<task>-t<n>)"
  k=-1
  for j in "${!PL_RUN[@]}"; do [[ "${PL_RUN[$j]}" == "$rid" ]] && { k=$j; break; }; done
  [[ $k -ge 0 ]] || die "--rerun $rid: not in the batch's plan"
  [[ -f "$ROWS" ]] || die "--rerun $rid: no rows file $ROWS"
  rn_rows="$(jq -R -c --arg b "$BATCH" --arg r "$rid" 'fromjson? | select(type == "object" and .batch == $b and .run_id == $r)' "$ROWS")"
  rn_n="$(grep -c . <<<"$rn_rows" || true)"
  [[ "$rn_n" -eq 1 ]] || die "--rerun $rid: $rn_n rows in $ROWS (a rerun replaces exactly one)"
  rn_st="$(jq -r '.status' <<<"$rn_rows")"
  case "$rn_st" in transport_error|interrupted|infrastructure_error) ;;
    *) die "--rerun $rid: the row is $rn_st; only transport_error, interrupted or infrastructure_error rows are rerun (DEC-0553)" ;; esac
  [[ "${PL_K[$k]}" -eq 0 ]] || die "--rerun $rid: a matched cell is never rerun as a whole (its sessions re-run within the attempt limit, D-7.3)"
  [[ "$(jq -r '.attempts // 1' <<<"$rn_rows")" -lt 3 ]] || die "--rerun $rid: the row is at $(jq -r '.attempts' <<<"$rn_rows") attempts; the attempt limit is 3 (2 re-runs, D-7.3)"
done

# --- batch directory, lock, manifest ---------------------------------------------------
mkdir -p "$BATCH_DIR"
LOCK="$BATCH_DIR/.lock"
rmdir_lock() { find "$LOCK" -mindepth 1 -delete 2>/dev/null || true; rmdir "$LOCK" 2>/dev/null || true; }
if ! mkdir "$LOCK" 2>/dev/null; then
  oldpid="$(cat "$LOCK/pid" 2>/dev/null || echo "")"
  if [[ -n "$oldpid" ]] && kill -0 "$oldpid" 2>/dev/null; then die "batch $BATCH is locked by pid $oldpid ($LOCK)"; fi
  rm -rf "$LOCK"; mkdir "$LOCK" || die "cannot lock $LOCK"
fi
printf '%s\n' "$$" > "$LOCK/pid"
JOBS_DIR="$BATCH_DIR/.jobs"
# a driver killed with SIGKILL leaves its pipelines running in their own sessions: never start
# a second copy of a trial while the first still spends
for f in "$JOBS_DIR"/*.pgid; do
  [[ -f "$f" ]] || continue
  read -r p _ < "$f" 2>/dev/null || continue
  if [[ "$p" =~ ^[0-9]+$ ]] && kill -0 -- "-$p" 2>/dev/null; then
    rmdir_lock
    die "a pipeline of an earlier driver still runs (process group $p, $f); stop it (kill -TERM -- -$p) or wait, then resume"
  fi
done
rm -rf "$JOBS_DIR"; mkdir -p "$JOBS_DIR"
rm -f "$BATCH_DIR/REFUSED.txt"
LOG="$BATCH_DIR/run.log"
if [[ "$SMOKE" != true && ! -f "$BATCH_DIR/.gitignore" ]]; then
  printf '%s\n' "# run-ablation.sh: run directories, logs and job state stay out of git;" \
    "# MANIFEST.json, STATUS.json and spend.txt are the batch record" "/*/" "/run.log" "/driver.log" "/.lock/" "/.jobs/" \
    > "$BATCH_DIR/.gitignore"
fi
[[ "$RESUME" == true ]] || write_manifest "$MAN_PATH" false
mkdir -p "$(dirname "$ROWS")"

# --- batch state ---------------------------------------------------------------------
STATE=running STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SPENT=0 ASSUMED_CAP=0 CUT_JSON=null LAUNCHED=0 ROWS_USD=0 LEDGER_USD=0 SESSIONS_USD=0 RERUN_PRIOR='{}'
CUTS_JSON='[]' RETRIES_JSON='[]' PAUSED_JSON='{}' DRIFT_JSON=null ROWS_INVALID=null STOP="" SIGNALLED=false
EXTRA_RUNS_JSON='{}' DRIFT_CLEARED_JSON='[]' REROWED_JSON='[]'
RERUN_JSON='[]' RERUN_OLD='{}' OUTAGE_JSON=null OUTAGE_HISTORY_JSON='[]' OUTAGE_RUN=0
DONE_LIST=$'\n' RERUN_LIST=$'\n'
C_PLANNED=() C_LAUNCHED=() C_COMPLETED=() C_FAILED=() C_EXCLUDED=() C_CAP=() C_DEGRADED=() C_SKIPPED=()
for i in "${!ARMS[@]}"; do
  C_PLANNED[$i]=0; C_LAUNCHED[$i]=0; C_COMPLETED[$i]=0; C_FAILED[$i]=0; C_EXCLUDED[$i]=0; C_CAP[$i]=0; C_DEGRADED[$i]=0; C_SKIPPED[$i]=0
done
arm_index() { local i; for i in "${!ARMS[@]}"; do [[ "${ARMS[$i]}" == "$1" ]] && { echo "$i"; return; }; done; echo -1; }
for a in ${PL_ARM[@]+"${PL_ARM[@]}"}; do i="$(arm_index "$a")"; C_PLANNED[$i]=$(( ${C_PLANNED[$i]} + 1 )); done
is_done() { [[ "$DONE_LIST" == *$'\n'"$1"$'\n'* ]]; }
is_rerun() { [[ "$RERUN_LIST" == *$'\n'"$1"$'\n'* ]]; }   # flagged on resume, no replacement row yet
is_paused() { jq -e --arg a "$1" 'has($a)' <<<"$PAUSED_JSON" >/dev/null; }

# account_row <arm> <kind> <run_id> <status> <cost> <degraded> — counters and spend for one row
account_row() {
  local arm="$1" kind="$2" rid="$3" st="$4" cost="$5" deg="$6" i
  i="$(arm_index "$arm")"
  [[ "$cost" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || cost=0
  case "$st" in
    completed) C_COMPLETED[$i]=$(( ${C_COMPLETED[$i]} + 1 )) ;;
    cap_failure) C_CAP[$i]=$(( ${C_CAP[$i]} + 1 )) ;;
    agent_error) C_FAILED[$i]=$(( ${C_FAILED[$i]} + 1 )) ;;
    *) C_EXCLUDED[$i]=$(( ${C_EXCLUDED[$i]} + 1 )) ;;
  esac
  [[ "$deg" == true ]] && C_DEGRADED[$i]=$(( ${C_DEGRADED[$i]} + 1 ))
  ROWS_USD="$(fadd "$ROWS_USD" "$cost")"
  local cap; cap="$(cap_for "$kind")"   # the trial kind's cap (DEC-0567)
  if [[ "$st" == cap_failure ]]; then
    if awk -v c="$cost" -v r="$cap" 'BEGIN { exit !(c < r) }'; then
      SPENT="$(fadd "$SPENT" "$cap")"; ASSUMED_CAP=$((ASSUMED_CAP + 1))
      log "assumed cap: $rid ended cap_failure at USD $cost; USD $cap ($kind cap) charged to spent"
    else
      SPENT="$(fadd "$SPENT" "$cost")"
    fi
  else
    spend_charge "$st" "$cost" "$rid" "$cap"
    if [[ "$st" == completed ]]; then est_record "$arm|$kind" "$kind" "$CHARGED_COST"; fi
  fi
}

resume_cursor() { local k; for k in "${!PL_RUN[@]}"; do is_done "${PL_RUN[$k]}" || { echo "$k"; return; }; done; echo "$PLAN_N"; }
write_status() {
  local per='{}' i finished=null
  for i in "${!ARMS[@]}"; do
    per="$(jq -c --arg a "${ARMS[$i]}" --argjson p "${C_PLANNED[$i]}" --argjson l "${C_LAUNCHED[$i]}" \
      --argjson c "${C_COMPLETED[$i]}" --argjson f "${C_FAILED[$i]}" --argjson x "${C_EXCLUDED[$i]}" \
      --argjson cap "${C_CAP[$i]}" --argjson d "${C_DEGRADED[$i]}" --argjson s "${C_SKIPPED[$i]}" \
      '. + {($a): {trials_planned: $p, launched: $l, completed: $c, failed: $f, excluded: $x, cap_failures: $cap,
                   degraded: $d, skipped_paused: $s}}' <<<"$per")"
  done
  [[ "$STATE" != running ]] && finished="\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  jq -n --arg batch "$BATCH" --argjson smoke "$SMOKE" --arg state "$STATE" --argjson per "$per" \
    --argjson retries "$RETRIES_JSON" --argjson cuts "$CUTS_JSON" --argjson paused "$PAUSED_JSON" \
    --arg rows_usd "$ROWS_USD" --arg ledger "$LEDGER_USD" --arg spent "$SPENT" --arg max "$MAX_USD" \
    --argjson assumed "$ASSUMED_CAP" --argjson cursor "$(resume_cursor)" --argjson drift "$DRIFT_JSON" \
    --argjson invalid "$ROWS_INVALID" --arg started "$STARTED" --argjson finished "$finished" \
    --arg src "$SRC_FULL" --arg rows "$ROWS" --argjson planned "$PLAN_N" --argjson signalled "$SIGNALLED" \
    --argjson ebr "$EXTRA_RUNS_JSON" --argjson cleared "$DRIFT_CLEARED_JSON" --argjson rerowed "$REROWED_JSON" \
    --argjson rerun "$RERUN_JSON" --argjson pending "$(printf '%s' "$RERUN_LIST" | sed '/^$/d' | jq -R . | jq -sc .)" \
    --argjson outage "$OUTAGE_JSON" --argjson ohist "$OUTAGE_HISTORY_JSON" --argjson cpf "$CODEX_PF_JSON" \
    --arg sess_usd "$SESSIONS_USD" --argjson ncells "$N_CELLS" \
    '{schema_version: 1, suite: "ablation-2.0", batch: $batch, smoke: $smoke, state: $state, per_arm: $per,
      retries: $retries, cuts: $cuts, paused_arms: $paused,
      spend: ({rows_usd: ($rows_usd | tonumber), ledger_usd: ($ledger | tonumber), spent_usd: ($spent | tonumber),
              max_usd: (if $max == "" then null else ($max | tonumber) end), assumed_cap_trials: $assumed}
              + (if $ncells > 0 then {sessions_usd: ($sess_usd | tonumber)} else {} end)),
      trials_planned: $planned, resume_cursor: $cursor, drift: $drift, drift_cleared: $cleared, rerowed: $rerowed,
      rerun: $rerun, rerun_pending: $pending, outage: $outage, outage_history: $ohist,
      codex_preflight: $cpf,
      extra_models: ([$ebr | to_entries[] | .value | to_entries[]] | group_by(.key)
                     | map({key: .[0].key, value: {runs: length, output_tokens: (map(.value) | add)}}) | from_entries),
      extra_models_by_run: $ebr, rows_invalid: $invalid, signalled: $signalled,
      source_commit: $src, rows_file: $rows, started: $started, finished: $finished}' > "$BATCH_DIR/STATUS.json.tmp"
  mv "$BATCH_DIR/STATUS.json.tmp" "$BATCH_DIR/STATUS.json"
}

cleanup() {
  local f p
  for f in "$JOBS_DIR"/*.pgid; do
    [[ -f "$f" ]] || continue
    read -r p _ < "$f" || continue
    kill -TERM -- "-$p" 2>/dev/null || kill -TERM "$p" 2>/dev/null || true
  done
  for p in $(jobs -p 2>/dev/null); do kill "$p" 2>/dev/null || true; done
  rm -rf "$JOBS_DIR" "$LOCK" "$WORK" 2>/dev/null || true
}
trap cleanup EXIT

# --- one trial (a background job; its result goes to $JOBS_DIR/<jid>.*) -------------
fresh_dir() { local b="$1" k=2; [[ -e "$b" ]] || { printf '%s' "$b"; return; }; while [[ -e "$b-r$k" ]]; do k=$((k + 1)); done; printf '%s' "$b-r$k"; }
final_status() {  # final_status <run-dir> → the pipeline status, empty when missing or running
  local s; s="$(jq -r '.status // ""' "$1/meta/pipeline.json" 2>/dev/null || true)"
  case "$s" in completed|agent_error|cap_failure|infrastructure_error|interrupted) printf '%s' "$s" ;; *) printf '' ;; esac
}
synthesize_record() {  # synthesize_record <run-dir> <arm> <task> <type> <trial> <run_id> <reason>
  local rd="$1"
  mkdir -p "$rd/meta"
  [[ -f "$rd/meta/arm" ]] || printf '%s\n' "$2" > "$rd/meta/arm"
  if ! jq -e 'type == "object"' "$rd/meta/pipeline.json" >/dev/null 2>&1; then
    jq -n --arg r "$6" --arg a "$2" --arg t "$3" --arg ty "$4" --argjson n "$5" --arg src "$SRC_FULL" --arg why "$7" \
      --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg mode "$EXECUTOR" \
      '{schema_version: 1, run_id: $r, arm: $a, task_id: $t, task_type: $ty, trial: $n, source_commit: $src,
        status: "interrupted", reason: $why, cap_phase: null, spent_usd: 0, executor_mode: $mode, phases: [],
        snapshots: {}, started: $now, finished: $now, synthesized_by: "run-ablation.sh"}' > "$rd/meta/pipeline.json"
  fi
}
# post_run <run-dir> <run_id> <task> <task_yaml> <attempts> <retry_reason> <pipeline_status>
#          <override> <row-out> <log> — the chain after a finished pipeline, shared by a trial
# and by --rerow: took-effect, drift guard, grade (completed, agent_error and cap_failure runs
# without an override), then ablation-row.sh into <row-out>. Results in PR_TE (ok | fail |
# skipped | timeout), PR_TE_REASON, PR_DRIFT (json or null), PR_EXTRA (the extra models, json),
# PR_GRC (null or the grade exit), PR_RRC (the row exit) and PR_OVERRIDE (the final override)
post_run() {
  local rd="$1" rid="$2" task="$3" tyaml="$4" attempts="$5" rr="$6" st="$7" row_out="$9" plog="${10}"
  post_checks "$rd" "$rid" "$task" "$tyaml" "$st" "$8" "$plog"
  local -a r=("$ROW_BIN" --run-dir "$rd" --task-yaml "$tyaml" --manifest "$MAN_PATH" --attempts "$attempts" --out "$row_out")
  [[ -n "$rr" ]] && r+=(--retry-reason "$rr")
  [[ -n "$PR_OVERRIDE" ]] && r+=(--status "$PR_OVERRIDE")
  refusal_row_args "$rd"; r+=(${REF_ROW_ARGS[@]+"${REF_ROW_ARGS[@]}"})   # cycle-133 C-8: the second attempt of rerun-once
  awk -v p="${PR_PRIOR_SPEND:-0}" 'BEGIN { exit !(p > 0) }' && r+=(--prior-spend "$PR_PRIOR_SPEND")   # cycle-132: all_spend_usd
  "${r[@]}" >> "$plog" 2>&1 || PR_RRC=$?
  return 0
}
# post_checks <run-dir> <run_id> <task> <task_yaml> <pipeline_status> <override> <log> — took-effect, the drift
# guard and the grade (completed, agent_error and cap_failure runs without an override), shared by a trial's
# post_run, --rerow and a matched session (cycle-132, which writes no row); sets the PR_* results above
post_checks() {
  local rd="$1" rid="$2" task="$3" tyaml="$4" st="$5" plog="$7"
  PR_OVERRIDE="$6" PR_TE=skipped PR_TE_REASON="" PR_DRIFT=null PR_EXTRA='{}' PR_GRC=null PR_RRC=0
  if [[ -z "$PR_OVERRIDE" ]]; then
    case "$st" in
      completed|agent_error|cap_failure)
        local trc=0 tout dout id
        rm -f "$rd/meta/took-effect.json"   # cycle-132: the row's took_effect comes from this call's record only
        tout="$(${TOOK_TMO[@]+"${TOOK_TMO[@]}"} "$TOOK_BIN" --run-dir "$rd" --suite-file "$SUITE_FILE" --task-yaml "$tyaml" \
          --json-out "$rd/meta/took-effect.json" 2>&1)" || trc=$?
        printf '%s\n' "$tout" >> "$plog"
        if [[ $trc -eq 0 ]]; then PR_TE=ok
        elif [[ ${#TOOK_TMO[@]} -gt 0 && ( $trc -eq 124 || $trc -eq 137 ) ]]; then
          # a hang is infrastructure, not evidence that the arm did not take effect: no pause
          PR_TE=timeout PR_OVERRIDE=infrastructure_error PR_TE_REASON="took-effect timed out after ${TOOK_TIMEOUT_S}s (exit $trc)"
          printf 'run-ablation: took-effect timed out after %ss\n' "$TOOK_TIMEOUT_S" >> "$plog"
        else
          PR_TE=fail PR_OVERRIDE=infrastructure_error
          PR_TE_REASON="took-effect exit $trc: $(grep -E ' FAIL' <<<"$tout" | head -4 | cut -c1-200 | tr '\n' ';' || true)"
        fi
        dout="$(drift_check "$rd" "$rid" 2>>"$plog" || true)"
        PR_DRIFT="$(sed -n 1p <<<"$dout")" PR_EXTRA="$(sed -n 2p <<<"$dout")"
        jq -e . >/dev/null 2>&1 <<<"$PR_DRIFT" || PR_DRIFT=null
        jq -e 'type == "object"' >/dev/null 2>&1 <<<"$PR_EXTRA" || PR_EXTRA='{}'
        while IFS=$'\t' read -r id labels toks; do
          [[ -n "$id" ]] || continue
          printf 'run-ablation: extra model %s in %s (%s output tokens; a WebFetch summariser or built-in subagent, not drift — DEC-0545)\n' \
            "$id" "$labels" "$toks" >> "$plog"
        done < <(jq -r 'to_entries[] | [.key, (.value.phases | join(",")), (.value.output_tokens | tostring)] | @tsv' <<<"$PR_EXTRA")
        if [[ "$PR_DRIFT" != null ]]; then PR_OVERRIDE=infrastructure_error; printf 'run-ablation: drift %s\n' "$PR_DRIFT" >> "$plog"; fi
        if [[ -z "$PR_OVERRIDE" ]]; then
          local -a g=("$GRADE_BIN" "$rd" "$task" --suite-root "$SUITE_ROOT" --executor "$EXECUTOR" --image "$IMAGE" --docker-bin "$DOCKER_BIN")
          [[ "$SMOKE" == true ]] && g+=(--tasks-dir smoke)
          [[ "$ALLOW_PARTIAL" == true ]] && g+=(--allow-partial)
          PR_GRC=0; ${GRADE_TMO[@]+"${GRADE_TMO[@]}"} "${g[@]}" >> "$plog" 2>&1 || PR_GRC=$?
          if [[ ${#GRADE_TMO[@]} -gt 0 && ( $PR_GRC -eq 124 || $PR_GRC -eq 137 ) ]]; then
            PR_OVERRIDE=infrastructure_error; printf 'run-ablation: grade timed out after %ss\n' "$GRADE_TIMEOUT_S" >> "$plog"
          elif [[ $PR_GRC -ne 0 ]]; then PR_OVERRIDE=infrastructure_error; printf 'run-ablation: grade exit %s\n' "$PR_GRC" >> "$plog"; fi
        fi ;;
    esac
  fi
  return 0
}

run_trial() {  # run_trial <jid> <arm> <task> <type> <kind> <trial> <run_id> <task_yaml> <watchdog_s> [<prior attempts> <prior USD>]
  local jid="$1" arm="$2" task="$3" type="$4" kind="$5" trial="$6" rid="$7" tyaml="$8" wds="$9"
  local prior="${10:-0}" prior_usd="${11:-0}"   # cycle-132 D-7.3: a rerun counts the replaced row's attempts
  local base="$BATCH_DIR/$arm/$task-t$trial" tlog="$BATCH_DIR/$arm/$task-t$trial.log"
  local attempt=0 rd="" st="" prc retry_reason="" first_usd=0 sig override="" pid
  local t0 t1
  mkdir -p "$BATCH_DIR/$arm"
  refusal_pre "$jid" "$arm" "$base" "$prior" "$prior_usd" "$rid"; prior="$REF_PRIOR" prior_usd="$REF_PRIOR_USD"   # cycle-133 C-8
  t0="$(date +%s)"
  while [[ $attempt -lt 2 ]]; do
    attempt=$((attempt + 1))
    rd="$(fresh_dir "$base")"
    printf '%s\n' "$rd" > "$JOBS_DIR/$jid.rundir"
    rm -f "$JOBS_DIR/$jid.wd" "$JOBS_DIR/$jid.wdkill"
    printf '%s run-ablation: %s attempt %d run_dir %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rid" "$attempt" "$rd" >> "$tlog"
    local -a cmd=("$PIPELINE_BIN" --task-yaml "$tyaml" --arm "$arm" --run-dir "$rd" --run-id "$rid" --trial "$trial"
                  --source-tree "$TREE" --suite-file "$SUITE_FILE" --executor "$EXECUTOR" --image "$IMAGE"
                  --docker-bin "$DOCKER_BIN" --max-run-usd "$(cap_for "$kind")" --batch-context "$BATCH_CONTEXT")
    # its own process group, so the watchdog can signal the pipeline and everything under it;
    # --batch-context marks the batch context the eval_only arms need (cycle-131 FR-5; an argv flag, bd-st02i)
    if command -v setsid >/dev/null 2>&1; then setsid "${cmd[@]}" >> "$tlog" 2>&1 < /dev/null &
    else "${cmd[@]}" >> "$tlog" 2>&1 < /dev/null &
    fi
    pid=$!
    printf '%s %s %s\n' "$pid" "$(date +%s)" "$wds" > "$JOBS_DIR/$jid.pgid"
    prc=0; wait "$pid" || prc=$?
    rm -f "$JOBS_DIR/$jid.pgid"
    st="$(final_status "$rd")"
    if [[ -f "$JOBS_DIR/$jid.wd" ]]; then
      override=interrupted
      synthesize_record "$rd" "$arm" "$task" "$type" "$trial" "$rid" "watchdog: no final pipeline record after ${wds}s (pipeline exit $prc)"
      break
    fi
    if [[ -z "$st" ]]; then
      override=interrupted
      synthesize_record "$rd" "$arm" "$task" "$type" "$trial" "$rid" "no final pipeline record (pipeline exit $prc)"
      break
    fi
    if [[ "$st" == agent_error ]] && sig="$(is_pipeline_transport_failure "$rd")"; then
      if [[ $attempt -lt 2 && $((prior + attempt)) -lt 3 ]]; then
        first_usd="$(jq -r '(.spent_usd // 0) | tonumber? // 0' "$rd/meta/pipeline.json" 2>/dev/null || echo 0)"
        retry_reason="transport: ${sig% *} in phase ${sig#* }"
        printf '%s run-ablation: %s %s; retrying once after %ss into a fresh run dir\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rid" "$retry_reason" "$RETRY_WAIT" >> "$tlog"
        sleep "$RETRY_WAIT"; continue
      fi
      override=transport_error
    fi
    break
  done
  if refusal_relaunch "$arm" "$base" "$rd" "$st" "$override" "$prior" "$attempt" "$first_usd" "$tlog"; then   # cycle-133 C-8
    run_trial "$jid" "$arm" "$task" "$type" "$kind" "$trial" "$rid" "$tyaml" "$wds" "$prior" "$prior_usd"; return 0
  fi
  PR_PRIOR_SPEND="$(fadd "$prior_usd" "$first_usd")"
  post_run "$rd" "$rid" "$task" "$tyaml" "$((prior + attempt))" "$retry_reason" "$st" "$override" "$JOBS_DIR/$jid.row" "$tlog"
  t1="$(date +%s)"
  jq -n --arg rid "$rid" --arg rd "$rd" --argjson att "$attempt" --arg rr "$retry_reason" --arg first "$first_usd" \
    --arg pst "${st:-}" --arg ov "$PR_OVERRIDE" --arg te "$PR_TE" --arg ter "$PR_TE_REASON" --argjson drift "$PR_DRIFT" \
    --argjson grc "$PR_GRC" --argjson rrc "$PR_RRC" --argjson secs "$(( t1 - t0 ))" --argjson extra "$PR_EXTRA" \
    '{run_id: $rid, run_dir: $rd, attempts: $att, retry_reason: (if $rr == "" then null else $rr end),
      first_attempt_usd: ($first | tonumber? // 0), pipeline_status: $pst, override: $ov, took_effect: $te,
      took_effect_reason: $ter, drift: $drift, grade_rc: $grc, row_rc: $rrc, seconds: $secs,
      extra_models: $extra}' > "$JOBS_DIR/$jid.result.tmp"
  mv "$JOBS_DIR/$jid.result.tmp" "$JOBS_DIR/$jid.result"
}

# --- cycle-132: one session of a matched cell (a background job; D-3.1, D-3.2, D-7.3) ----------------
cell_dir_of() { printf '%s/%s/%s-t%s' "$BATCH_DIR" "${PL_ARM[$1]}" "${PL_TASK[$1]}" "${PL_TRIAL[$1]}"; }
is_infra_outcome() { case "$1" in transport_error|cap_failure|interrupted) return 0 ;; *) return 1 ;; esac; }
# attempt_outcome <run-dir> <watchdog-flag> → interrupted | transport_error | cap_failure | completed | agent_error |
# infrastructure_error (a missing or running record reads interrupted; agent_error with a transport signature
# reads transport_error)
attempt_outcome() {
  local st; st="$(final_status "$1")"
  if [[ "$2" == wd || -z "$st" ]]; then printf interrupted; return 0; fi
  if [[ "$st" == agent_error ]] && is_pipeline_transport_failure "$1" >/dev/null; then printf transport_error; return 0; fi
  printf '%s' "$st"
}
run_session() {  # run_session <jid> <plan-index> <session number>
  local jid="$1" k="$2" i="$3"
  local arm="${PL_ARM[$2]}" task="${PL_TASK[$2]}" type="${PL_TYPE[$2]}" kind="${PL_KIND[$2]}" trial="${PL_TRIAL[$2]}"
  local rid="${PL_RUN[$2]}" tyaml="${PL_YAML[$2]}" wds="${PL_WD[$2]}" cell base tlog srid
  cell="$(cell_dir_of "$k")"; base="$cell/sessions/s$i"; tlog="$cell/sessions/s$i.log"; srid="$rid-s$i"
  mkdir -p "$cell/sessions"
  local attempt=0 rd="" outcome="" prc pid d t0 t1 statuses='[]' costs='[]' cost
  t0="$(date +%s)"
  # the attempts an earlier driver made (a resumed session) count toward the limit of 3
  local -a prior_dirs=()
  [[ -d "$base" ]] && prior_dirs+=("$base")
  local n=2; while [[ -d "$base-r$n" ]]; do prior_dirs+=("$base-r$n"); n=$((n + 1)); done
  for d in ${prior_dirs[@]+"${prior_dirs[@]}"}; do
    attempt=$((attempt + 1)); rd="$d"
    [[ -n "$(final_status "$d")" ]] || synthesize_record "$d" "$arm" "$task" "$type" "$trial" "$srid" "no final pipeline record (an earlier driver ended)"
    outcome="$(attempt_outcome "$d" -)"
    cost="$(jq -r '(.spent_usd // 0) | tonumber? // 0' "$d/meta/pipeline.json" 2>/dev/null || echo 0)"
    statuses="$(jq -c --arg s "$outcome" '. + [$s]' <<<"$statuses")"; costs="$(jq -c --arg c "$cost" '. + [($c | tonumber)]' <<<"$costs")"
    printf '%s run-ablation: %s attempt %d (an earlier driver) in %s: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$srid" "$attempt" "$d" "$outcome" >> "$tlog"
  done
  while [[ $attempt -lt 3 ]]; do
    if [[ $attempt -gt 0 ]] && ! is_infra_outcome "$outcome"; then break; fi
    if [[ $attempt -gt 0 ]]; then
      printf '%s run-ablation: %s ended %s; re-run %d of at most 2 after %ss (D-7.3)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$srid" "$outcome" "$attempt" "$RETRY_WAIT" >> "$tlog"
      sleep "$RETRY_WAIT"
    fi
    attempt=$((attempt + 1))
    rd="$(fresh_dir "$base")"
    printf '%s\n' "$rd" > "$JOBS_DIR/$jid.rundir"
    rm -f "$JOBS_DIR/$jid.wd" "$JOBS_DIR/$jid.wdkill"
    printf '%s run-ablation: %s attempt %d run_dir %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$srid" "$attempt" "$rd" >> "$tlog"
    local -a cmd=("$PIPELINE_BIN" --task-yaml "$tyaml" --arm "$arm" --run-dir "$rd" --run-id "$srid" --trial "$trial"
                  --source-tree "$TREE" --suite-file "$SUITE_FILE" --executor "$EXECUTOR" --image "$IMAGE"
                  --docker-bin "$DOCKER_BIN" --max-run-usd "$(cap_for "$kind")" --batch-context "$BATCH_CONTEXT")
    if command -v setsid >/dev/null 2>&1; then setsid "${cmd[@]}" >> "$tlog" 2>&1 < /dev/null &
    else "${cmd[@]}" >> "$tlog" 2>&1 < /dev/null &
    fi
    pid=$!
    printf '%s %s %s\n' "$pid" "$(date +%s)" "$wds" > "$JOBS_DIR/$jid.pgid"
    prc=0; wait "$pid" || prc=$?
    rm -f "$JOBS_DIR/$jid.pgid"
    local wdf=-; [[ -f "$JOBS_DIR/$jid.wd" ]] && wdf=wd
    if [[ "$wdf" == wd ]]; then
      synthesize_record "$rd" "$arm" "$task" "$type" "$trial" "$srid" "watchdog: no final pipeline record after ${wds}s (pipeline exit $prc)"
    elif [[ -z "$(final_status "$rd")" ]]; then
      synthesize_record "$rd" "$arm" "$task" "$type" "$trial" "$srid" "no final pipeline record (pipeline exit $prc)"
    fi
    outcome="$(attempt_outcome "$rd" "$wdf")"
    cost="$(jq -r '(.spent_usd // 0) | tonumber? // 0' "$rd/meta/pipeline.json" 2>/dev/null || echo 0)"
    statuses="$(jq -c --arg s "$outcome" '. + [$s]' <<<"$statuses")"; costs="$(jq -c --arg c "$cost" '. + [($c | tonumber)]' <<<"$costs")"
  done
  # the session's chain: took-effect, drift, grade on its final attempt (valid outcomes only)
  local status="$outcome" valid=false why=""
  PR_TE=skipped PR_TE_REASON="" PR_DRIFT=null PR_EXTRA='{}' PR_GRC=null PR_OVERRIDE=""
  case "$outcome" in
    completed|agent_error)
      post_checks "$rd" "$srid" "$task" "$tyaml" "$outcome" "" "$tlog"
      if [[ -n "$PR_OVERRIDE" ]]; then status="$PR_OVERRIDE"
        if [[ "$PR_TE" == fail || "$PR_TE" == timeout ]]; then why="took-effect: $PR_TE_REASON"
        elif [[ "$PR_DRIFT" != null ]]; then why="drift"
        else why="grade exit $PR_GRC"; fi
      elif [[ "$(jq -r '.contaminated // null | type' "$rd/grade.json" 2>/dev/null || echo missing)" != null ]]; then
        status=contaminated why="contaminated: $(jq -r '.contaminated.pattern // "grade unreadable"' "$rd/grade.json" 2>/dev/null || echo unreadable)"
      elif jq -e '[.phases // [] | .[] | select((.refusal_fallbacks // []) | length > 0)] | length > 0' "$rd/meta/pipeline.json" >/dev/null 2>&1; then
        why="refusal fallback (KF-051)"
      else valid=true; fi ;;
    *) why="infrastructure: $outcome after $attempt attempt(s)" ;;
  esac
  t1="$(date +%s)"
  jq -n --arg rid "$rid" --arg s "s$i" --argjson k "$k" --arg rd "${rd#"$cell"/}" --argjson att "$attempt" --argjson sts "$statuses" \
    --argjson cs "$costs" --arg st "$status" --argjson v "$valid" --arg why "$why" --arg te "$PR_TE" --arg ter "$PR_TE_REASON" \
    --argjson drift "$PR_DRIFT" --argjson extra "$PR_EXTRA" --argjson grc "$PR_GRC" --argjson secs "$(( t1 - t0 ))" \
    '{kind: "session", run_id: $rid, session: $s, plan_index: $k, run_dir: $rd, attempts: $att, attempt_statuses: $sts,
      attempt_costs: $cs, status: $st, valid: $v, invalid_reason: (if $why == "" then null else $why end),
      took_effect: $te, took_effect_reason: $ter, drift: $drift, extra_models: $extra, grade_rc: $grc, seconds: $secs}' \
    > "$JOBS_DIR/$jid.result.tmp"
  mv "$JOBS_DIR/$jid.result.tmp" "$JOBS_DIR/$jid.result"
}

# session_charge <session record> <kind> → "<USD charged> <assumed charges>": every attempt's cost; a cap_failure
# attempt max(cost, the kind's cap); any other non-completed attempt reporting no cost the kind's cap (Spend)
session_charge() {
  jq -r --arg cap "$(cap_for "$2")" '
    ($cap | tonumber) as $c
    | [range(0; (.attempt_costs | length)) as $j | .attempt_costs[$j] as $x | (.attempt_statuses[$j] // "interrupted") as $s
       | if $s == "cap_failure" then [([$x, $c] | max), (if $x < $c then 1 else 0 end)]
         elif $s != "completed" and $x == 0 then [$c, 1]
         else [$x, 0] end]
    | "\(map(.[0]) | add // 0) \(map(.[1]) | add // 0)"' "$1"
}
charge_session() {  # charge_session <record> <kind> <arm> — spend and the estimate for one recorded session
  local u a
  read -r u a < <(session_charge "$1" "$2")
  SPENT="$(fadd "$SPENT" "$u")"; SESSIONS_USD="$(fadd "$SESSIONS_USD" "$u")"; ASSUMED_CAP=$((ASSUMED_CAP + a))
  if [[ "$(jq -r '.status' "$1")" == completed ]]; then est_record "$3|$2" "$2" "$(jq -r '.attempt_costs | last // 0' "$1")"; fi
}
# account_cell <arm> <status> <degraded> — a matched cell's row: counters only (its sessions were charged)
account_cell() {
  local i; i="$(arm_index "$1")"
  case "$2" in
    completed) C_COMPLETED[$i]=$(( ${C_COMPLETED[$i]} + 1 )) ;;
    cap_failure) C_CAP[$i]=$(( ${C_CAP[$i]} + 1 )) ;;
    agent_error) C_FAILED[$i]=$(( ${C_FAILED[$i]} + 1 )) ;;
    *) C_EXCLUDED[$i]=$(( ${C_EXCLUDED[$i]} + 1 )) ;;
  esac
  [[ "$3" == true ]] && C_DEGRADED[$i]=$(( ${C_DEGRADED[$i]} + 1 ))
  return 0
}
cell_sessions_done() {  # cell_sessions_done <plan-index> → 0 when every session holds a record
  local c i; c="$(cell_dir_of "$1")"
  for i in $(seq 1 "${PL_K[$1]}"); do [[ -f "$c/meta/sessions/s$i.json" ]] || return 1; done
  return 0
}
# finalize_cell <plan-index> — cell.json, the cell's took-effect, the union grade and the one row (in the driver)
finalize_cell() {
  local k="$1" arm="${PL_ARM[$1]}" task="${PL_TASK[$1]}" rid="${PL_RUN[$1]}" tyaml="${PL_YAML[$1]}"
  local cell clog override="" trc=0 tout grc=0 te=ok ter="" rrc=0 st cost deg
  cell="$(cell_dir_of "$k")"; clog="$BATCH_DIR/$arm/$task-t${PL_TRIAL[$k]}.log"
  printf '%s\n' "$arm" > "$cell/meta/arm"
  python3 -I - "$cell" "$rid" "$task" "${PL_TRIAL[$k]}" "${PL_K[$k]}" <<'PY' || { log "FAILED $rid: cell.json could not be assembled"; return 0; }
import json, os, sys
cell, rid, task, trial, k = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
recs = [json.load(open(os.path.join(cell, "meta", "sessions", "s%d.json" % i), encoding="utf-8")) for i in range(1, k + 1)]
keys = ("id", "status", "valid", "invalid_reason", "attempts", "attempt_statuses", "attempt_costs", "cost_usd", "run_dir")
out = {"schema_version": 1, "task_id": task, "trial": trial, "k": k,   # no run_id: it names the arm (the grader reads cell.json)
       "sessions": [{x: r.get(x) for x in keys} for r in recs],
       "sessions_valid": sum(1 for r in recs if r.get("valid") is True),
       "sessions_attempted": sum(1 for r in recs if (r.get("attempts") or 0) >= 1),
       "started": min((r.get("started") or "") for r in recs), "finished": max((r.get("finished") or "") for r in recs)}
tmp = os.path.join(cell, "meta", "cell.json.tmp")
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(out, f, indent=2, sort_keys=True)
    f.write("\n")
os.replace(tmp, os.path.join(cell, "meta", "cell.json"))
PY
  rm -f "$cell/meta/took-effect.json"
  tout="$(${TOOK_TMO[@]+"${TOOK_TMO[@]}"} "$TOOK_BIN" --run-dir "$cell" --suite-file "$SUITE_FILE" --task-yaml "$tyaml" \
    --json-out "$cell/meta/took-effect.json" 2>&1)" || trc=$?
  printf '%s\n' "$tout" >> "$clog"
  if [[ $trc -ne 0 ]]; then
    override=infrastructure_error
    if [[ ${#TOOK_TMO[@]} -gt 0 && ( $trc -eq 124 || $trc -eq 137 ) ]]; then te=timeout; ter="took-effect timed out after ${TOOK_TIMEOUT_S}s (exit $trc)"
    else te=fail; ter="took-effect exit $trc: $(grep -E ' FAIL' <<<"$tout" | head -4 | cut -c1-200 | tr '\n' ';' || true)"; fi
  fi
  if [[ -z "$override" ]]; then
    local -a g=("$GRADE_BIN" --union "$cell" --task-id "$task" --suite-root "$SUITE_ROOT")
    [[ "$SMOKE" == true ]] && g+=(--tasks-dir smoke)
    [[ "$ALLOW_PARTIAL" == true ]] && g+=(--allow-partial)
    ${GRADE_TMO[@]+"${GRADE_TMO[@]}"} "${g[@]}" >> "$clog" 2>&1 || grc=$?
    [[ $grc -eq 0 ]] || { override=infrastructure_error; printf 'run-ablation: union grade exit %s\n' "$grc" >> "$clog"; }
  fi
  local rowf="$JOBS_DIR/cell-$((k + 1)).row"
  rm -f "$rowf"
  local -a r=("$ROW_BIN" --run-dir "$cell" --task-yaml "$tyaml" --manifest "$MAN_PATH" --out "$rowf")
  [[ -n "$override" ]] && r+=(--status "$override")
  "${r[@]}" >> "$clog" 2>&1 || rrc=$?
  apply_flags "$arm" "$rid" "$te" "$ter" null
  if [[ ! -s "$rowf" ]]; then
    log "FAILED $rid: no cell row written (ablation-row.sh exit $rrc; see $clog)"
    return 0
  fi
  IFS=$'\t' read -r st cost deg < <(jq -r '[.status, ((.cost_usd // 0) | tostring), ((.degraded // false) | tostring)] | @tsv' "$rowf")
  if append_and_validate "$rowf" "$rid"; then :; else log "ROWS INVALID after $rid: $(jq -r '.error' <<<"$ROWS_INVALID")"; STOP=invalid; fi
  DONE_LIST="$DONE_LIST$rid"$'\n'
  account_cell "$arm" "$st" "$deg"
  log "done $rid $st sessions_valid $(jq -r '.sessions_valid' "$cell/meta/cell.json") of ${PL_K[$k]} USD $cost (valid sessions; all spend $(jq -r '.all_spend_usd // 0' "$rowf"))"
  rm -f "$rowf"
  return 0
}
collect_session() {  # collect_session <jid> <plan-index> <session number>
  local jid="$1" k="$2" i="$3" res="$JOBS_DIR/$1.result" arm="${PL_ARM[$2]}" kind="${PL_KIND[$2]}" rid="${PL_RUN[$2]}" cell rec
  cell="$(cell_dir_of "$k")"; rec="$cell/meta/sessions/s$i.json"
  if [[ ! -f "$res" ]]; then
    SPENT="$(fadd "$SPENT" "$(cap_for "$kind")")"; ASSUMED_CAP=$((ASSUMED_CAP + 1))
    log "FAILED $rid-s$i (the session job ended without a result; see $cell/sessions/s$i.log); assumed cap: USD $(cap_for "$kind") ($kind cap) charged to spent; --resume re-runs it"
    outage_tick "$rid-s$i" ""
    rm -f "$JOBS_DIR/$jid".*; write_status; return 0
  fi
  mkdir -p "$cell/meta/sessions"
  local started; started="$(jq -r '.started // ""' "$cell/$(jq -r '.run_dir' "$res")/meta/pipeline.json" 2>/dev/null || true)"
  jq --arg started "$started" --arg fin "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{id: .session, status, valid, invalid_reason, attempts, attempt_statuses, attempt_costs,
      cost_usd: (.attempt_costs | last // 0), run_dir, took_effect, started: $started, finished: $fin}' "$res" > "$rec.tmp"
  mv "$rec.tmp" "$rec"
  charge_session "$rec" "$kind" "$arm"
  record_extra "$rid-s$i" "$(jq -c '.extra_models // {}' "$res")"
  log "done $rid-s$i $(jq -r '.status' "$rec") valid $(jq -r '.valid' "$rec") attempts $(jq -r '.attempts' "$rec") USD $(jq -r '.attempt_costs | add // 0' "$rec")$(jq -r 'if .invalid_reason then " (" + .invalid_reason + ")" else "" end' "$rec")"
  outage_tick "$rid-s$i" "$(jq -r '.status' "$rec")"
  apply_flags "$arm" "$rid-s$i" "$(jq -r '.took_effect' "$res")" "$(jq -r '.took_effect_reason' "$res")" "$(jq -c '.drift' "$res")"
  rm -f "$JOBS_DIR/$jid".*
  if ! is_done "$rid" && cell_sessions_done "$k"; then finalize_cell "$k"; fi
  write_status
}

# --- parent: collect a finished job ---------------------------------------------------
append_and_validate() {  # append_and_validate <row-file> <run_id> → 0 ok; 1 invalid (ROWS_INVALID set)
  local rowf="$1" rid="$2" vout vrc=0 n
  local -a v=("$ROW_BIN" --validate "$ROWS"); [[ "$SMOKE" == true ]] && v+=(--allow-ungraded)
  if command -v flock >/dev/null 2>&1; then
    { flock -x 9; cat "$rowf" >> "$ROWS"; vout="$("${v[@]}" 2>&1)" || vrc=$?; } 9>>"$ROWS.lock"
  else
    cat "$rowf" >> "$ROWS"; vout="$("${v[@]}" 2>&1)" || vrc=$?
  fi
  n="$(grep -cF "\"run_id\":\"$rid\"" "$ROWS" || true)"
  if [[ $vrc -ne 0 ]]; then
    ROWS_INVALID="$(jq -cn --arg r "$rid" --arg e "$(printf '%s' "$vout" | tail -1)" '{run_id: $r, error: $e}')"; return 1
  fi
  if [[ "$n" -ne 1 ]]; then
    ROWS_INVALID="$(jq -cn --arg r "$rid" --argjson n "$n" '{run_id: $r, error: "run_id rowed \($n) times"}')"; return 1
  fi
  return 0
}

# apply_flags <arm> <run_id> <took_effect> <reason> <drift> — a took-effect FAIL pauses the
# arm (DEC-0418); the first drift stops the batch (DEC-0407)
apply_flags() {
  if [[ "$3" == fail ]] && ! is_paused "$1"; then
    PAUSED_JSON="$(jq -c --arg a "$1" --arg why "$2: $4" '. + {($a): $why}' <<<"$PAUSED_JSON")"
    log "PAUSED arm $1: $4 (no further trial of $1 launches until --resume --clear-arm $1)"
  fi
  if [[ "$5" != null && "$DRIFT_JSON" == null ]]; then
    DRIFT_JSON="$5"; STOP=drift
    log "DRIFT $2: $5; no further trial launches; the batch fails when the running trials end (DEC-0407)"
  fi
  return 0
}
# record_extra <run_id> <extra models json> — the run's extra models replace its earlier entry
record_extra() {
  EXTRA_RUNS_JSON="$(jq -c --arg r "$1" --argjson e "$2" \
    'if ($e | type) == "object" and ($e | length) > 0 then .[$r] = ($e | map_values(.output_tokens // 0)) else del(.[$r]) end' <<<"$EXTRA_RUNS_JSON")"
}

# outage_tick <run_id> <row status, empty without a row> — the breaker (DEC-0554): consecutive
# collected transport_error trials (collection order, any arm) trip it at $OUTAGE_BREAKER (0 off)
outage_tick() {
  if [[ "$2" == transport_error ]]; then OUTAGE_RUN=$((OUTAGE_RUN + 1)); else OUTAGE_RUN=0; fi
  if [[ "$OUTAGE_BREAKER" -gt 0 && $OUTAGE_RUN -ge $OUTAGE_BREAKER && "$OUTAGE_JSON" == null && -z "$STOP" ]]; then
    STOP=outage
    OUTAGE_JSON="$(jq -cn --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson n "$OUTAGE_RUN" --arg r "$1" \
      '{at: $at, consecutive: $n, last_run_id: $r,
        message: "partial (outage breaker): \($n) consecutive transport failures; --resume --rerun-status transport_error after the network is back"}')"
    log "OUTAGE breaker: $OUTAGE_RUN consecutive transport_error trials (last $1); no further trial launches (DEC-0554)"
  fi
  return 0
}

collect() {  # collect <jid> <plan-index>[:<session number>]
  if [[ "$2" == *:* ]]; then collect_session "$1" "${2%%:*}" "${2#*:}"; return 0; fi
  refusal_collect "$1"   # cycle-133 C-8: a rerun-once trial's refused first attempt
  local jid="$1" k="$2" arm="${PL_ARM[$2]}" rid="${PL_RUN[$2]}" kind="${PL_KIND[$2]}" res="$JOBS_DIR/$1.result"
  if [[ ! -f "$res" ]]; then
    SPENT="$(fadd "$SPENT" "$(cap_for "$kind")")"; ASSUMED_CAP=$((ASSUMED_CAP + 1))
    log "FAILED $rid (the trial job ended without a result; see $BATCH_DIR/$arm/${PL_TASK[$k]}-t${PL_TRIAL[$k]}.log); assumed cap: USD $(cap_for "$kind") ($kind cap) charged to spent"
    outage_tick "$rid" ""
    rm -f "$JOBS_DIR/$jid".*; write_status; return 0
  fi
  local first att rr te ter drift
  first="$(jq -r '.first_attempt_usd' "$res")" att="$(jq -r '.attempts' "$res")" rr="$(jq -r '.retry_reason // ""' "$res")"
  te="$(jq -r '.took_effect' "$res")" ter="$(jq -r '.took_effect_reason' "$res")" drift="$(jq -c '.drift' "$res")"
  record_extra "$rid" "$(jq -c '.extra_models // {}' "$res")"
  if [[ "$att" -ge 2 ]]; then
    RETRIES_JSON="$(jq -c --arg r "$rid" --arg why "$rr" --arg u "$first" '. + [{run_id: $r, reason: $why, first_attempt_usd: ($u | tonumber)}]' <<<"$RETRIES_JSON")"
    SPENT="$(fadd "$SPENT" "$first")"; LEDGER_USD="$(fadd "$LEDGER_USD" "$first")"
  fi
  local st="" cost deg pass
  if [[ -s "$JOBS_DIR/$jid.row" ]]; then
    IFS=$'\t' read -r st cost deg pass < <(jq -r '[.status, ((.cost_usd // 0) | tostring), ((.degraded // false) | tostring),
        ((.hidden_test_pass_rate // .defect_catch_rate // "n/a") | tostring)] | @tsv' "$JOBS_DIR/$jid.row")
    if is_rerun "$rid"; then
      # DEC-0553: the new row replaces the old one in place; the old row's reported cost moves to the ledger
      if replace_row_try "$rid" "$JOBS_DIR/$jid.row"; then
        local from ocost
        from="$(jq -r --arg r "$rid" '.[$r].status' <<<"$RERUN_OLD")" ocost="$(jq -r --arg r "$rid" '.[$r].cost' <<<"$RERUN_OLD")"
        LEDGER_USD="$(fadd "$LEDGER_USD" "$ocost")"
        RERUN_LIST="${RERUN_LIST/$'\n'"$rid"$'\n'/$'\n'}"
        RERUN_JSON="$(jq -c --arg r "$rid" --arg f "$from" --arg t "$st" --arg c "$ocost" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          '. + [{run_id: $r, from: $f, to: $t, old_cost_usd: ($c | tonumber), at: $at}]' <<<"$RERUN_JSON")"
        log "rerun $rid: $from → $st (row replaced in place)"
      else
        ROWS_INVALID="$(jq -cn --arg r "$rid" --arg e "$REPLACE_ERR" '{run_id: $r, error: ("rerun replacement: " + $e)}')"
        log "ROWS INVALID after $rid: $(jq -r '.error' <<<"$ROWS_INVALID")"; STOP=invalid
      fi
    elif append_and_validate "$JOBS_DIR/$jid.row" "$rid"; then :; else
      log "ROWS INVALID after $rid: $(jq -r '.error' <<<"$ROWS_INVALID")"; STOP=invalid
    fi
    DONE_LIST="$DONE_LIST$rid"$'\n'
    account_row "$arm" "$kind" "$rid" "$st" "$cost" "$deg"
    log "done $rid $st pass=$pass USD $cost $(( $(jq -r '.seconds' "$res") / 60 ))m attempts $att${rr:+ ($rr)}"
  else
    SPENT="$(fadd "$SPENT" "$(cap_for "$kind")")"; ASSUMED_CAP=$((ASSUMED_CAP + 1))
    log "FAILED $rid: no row written (ablation-row.sh exit $(jq -r '.row_rc' "$res"); see the trial log); assumed cap: USD $(cap_for "$kind") ($kind cap) charged to spent"
  fi
  outage_tick "$rid" "$st"
  apply_flags "$arm" "$rid" "$te" "$ter" "$drift"
  rm -f "$JOBS_DIR/$jid".*
  write_status
}

PIDS=() PJOB=() PIDX=()
watchdog_tick() {
  local j f pid start wds now rd t0
  now="$(date +%s)"
  for j in ${PJOB[@]+"${PJOB[@]}"}; do
    f="$JOBS_DIR/$j.pgid"; [[ -f "$f" ]] || continue
    read -r pid start wds < "$f" 2>/dev/null || continue
    [[ -n "$WATCHDOG_OVERRIDE" ]] && wds="$WATCHDOG_OVERRIDE"
    [[ $(( now - start )) -gt $wds ]] || continue
    rd="$(cat "$JOBS_DIR/$j.rundir" 2>/dev/null || true)"
    [[ -z "$(final_status "$rd")" ]] || continue
    if [[ ! -f "$JOBS_DIR/$j.wd" ]]; then
      printf '%s\n' "$now" > "$JOBS_DIR/$j.wd"
      log "watchdog: $j has no final pipeline record after ${wds}s (twice its phase-sum timeout); SIGTERM to process group $pid"
      kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
    elif [[ ! -f "$JOBS_DIR/$j.wdkill" ]]; then
      read -r t0 < "$JOBS_DIR/$j.wd" || t0="$now"
      if [[ $(( now - t0 )) -ge $WATCHDOG_GRACE ]]; then
        : > "$JOBS_DIR/$j.wdkill"
        log "watchdog: $j still running ${WATCHDOG_GRACE}s after SIGTERM; SIGKILL to process group $pid"
        kill -KILL -- "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
      fi
    fi
  done
  return 0
}
reap() {  # reap until fewer than $1 jobs run
  local i
  while [[ ${#PIDS[@]} -ge $1 ]]; do
    for i in "${!PIDS[@]}"; do
      if ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
        wait "${PIDS[$i]}" 2>/dev/null || true
        collect "${PJOB[$i]}" "${PIDX[$i]}"
        unset 'PIDS[i]' 'PJOB[i]' 'PIDX[i]'
        PIDS=("${PIDS[@]+"${PIDS[@]}"}"); PJOB=("${PJOB[@]+"${PJOB[@]}"}"); PIDX=("${PIDX[@]+"${PIDX[@]}"}")
        break
      fi
    done
    watchdog_tick
    [[ ${#PIDS[@]} -ge $1 ]] && sleep "$POLL_S"
  done
  return 0
}

on_signal() {
  SIGNALLED=true
  log "interrupted: the driver received a signal; running trials are signalled and will be rerun by --resume"
  STATE=partial; write_status
  exit 1
}

finish() {  # finish <state> <exit> <message>
  STATE="$1"; write_status; log "$3"
  local line
  line="$("$SPEND_BIN" 2>/dev/null | tail -1 || true)"
  {
    printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${line:-spend.sh printed nothing}"
    printf '%s batch %s spend USD %s (rows %s + first attempts %s; %s assumed cap charge(s)); max %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BATCH" "$SPENT" "$ROWS_USD" "$LEDGER_USD" "$ASSUMED_CAP" "${MAX_USD:-none}"
  } >> "$BATCH_DIR/spend.txt"
  echo "run-ablation: $3"
  echo "batch: $BATCH_DIR"
  exit "$2"
}

# --- --rerow: the post-run chain again over a rowed run dir, the row replaced in place ---
# replace_row_try <run_id> <new-row-file> → 0 replaced; 1 with REPLACE_ERR set and the rows file
# untouched (the old row stays). replace_row is the --rerow form: it dies instead
replace_row_try() {
  local rid="$1" newf="$2" tmp="$ROWS.rerow.$$" rc=0 vout="" perr
  REPLACE_ERR=""
  local -a v=("$ROW_BIN" --validate "$tmp"); [[ "$SMOKE" == true ]] && v+=(--allow-ungraded)
  {
    command -v flock >/dev/null 2>&1 && flock -x 9
    perr="$(python3 -I - "$ROWS" "$tmp" "$BATCH" "$rid" "$newf" 2>&1 <<'PY'
import json, sys
rows, tmp, batch, rid, newf = sys.argv[1:6]
new = open(newf, encoding="utf-8").read().strip()
out, n = [], 0
with open(rows, encoding="utf-8") as fh:
    for line in fh:
        try: o = json.loads(line)
        except ValueError: o = None
        if isinstance(o, dict) and o.get("batch") == batch and o.get("run_id") == rid:
            n += 1; out.append(new + "\n")
        else:
            out.append(line if line.endswith("\n") else line + "\n")
if n != 1:
    print("run_id %s has %d rows" % (rid, n), file=sys.stderr); sys.exit(1)
with open(tmp, "w", encoding="utf-8") as fh: fh.writelines(out)
PY
)" || rc=$?
    if [[ $rc -eq 0 ]]; then
      vout="$("${v[@]}" 2>&1)" || rc=$?
      if [[ $rc -eq 0 ]]; then mv "$tmp" "$ROWS"; else REPLACE_ERR="$(printf '%s\n' "$vout" | tail -1)"; fi
    else
      REPLACE_ERR="$(printf '%s\n' "$perr" | tail -1)"
    fi
  } 9>>"$ROWS.lock"
  rm -f "$tmp"
  [[ $rc -eq 0 ]] || { REPLACE_ERR="${REPLACE_ERR:-exit $rc}"; return 1; }
  return 0
}
replace_row() {  # replace_row <run_id> <new-row-file> → 0 replaced; dies (rows file untouched) otherwise
  replace_row_try "$1" "$2" && return 0
  printf '%s\n' "$REPLACE_ERR" >&2
  die "rerow $1: the replacement did not validate or the row moved ($REPLACE_ERR); $ROWS unchanged"
}
rerow_all() {
  local n k rid arm task trial rd tlog newst
  for n in "${!RR_K[@]}"; do
    k="${RR_K[$n]}" rid="${PL_RUN[${RR_K[$n]}]}" arm="${PL_ARM[${RR_K[$n]}]}" task="${PL_TASK[${RR_K[$n]}]}"
    trial="${PL_TRIAL[${RR_K[$n]}]}" rd="${RR_RD[$n]}" tlog="$BATCH_DIR/$arm/$task-t$trial.log"
    printf '%s run-ablation: rerow %s run_dir %s (was %s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rid" "$rd" "${RR_FROM[$n]}" >> "$tlog"
    rm -f "$WORK/rerow-$n.row"
    post_run "$rd" "$rid" "$task" "${PL_YAML[$k]}" "${RR_ATT[$n]}" "${RR_REASON[$n]}" "$(final_status "$rd")" "" "$WORK/rerow-$n.row" "$tlog"
    [[ -s "$WORK/rerow-$n.row" ]] || die "rerow $rid: ablation-row.sh wrote no row (exit $PR_RRC; see $tlog); $ROWS unchanged"
    replace_row "$rid" "$WORK/rerow-$n.row"
    newst="$(jq -r '.status' "$WORK/rerow-$n.row")"
    record_extra "$rid" "$PR_EXTRA"
    apply_flags "$arm" "$rid" "$PR_TE" "$PR_TE_REASON" "$PR_DRIFT"
    REROWED_JSON="$(jq -c --arg r "$rid" --arg f "${RR_FROM[$n]}" --arg t "$newst" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '. + [{run_id: $r, from: $f, to: $t, at: $at}]' <<<"$REROWED_JSON")"
    jq --argjson r "$REROWED_JSON" '.rerowed = $r' "$BATCH_DIR/STATUS.json" > "$BATCH_DIR/STATUS.json.tmp" \
      && mv "$BATCH_DIR/STATUS.json.tmp" "$BATCH_DIR/STATUS.json"
    log "rerow $rid: ${RR_FROM[$n]} → $newst"
  done
  return 0
}

# --- --resume reconciliation: rows on disk are the truth (after --rerow) --------
if [[ "$RESUME" == true ]]; then
  ST_PATH="$BATCH_DIR/STATUS.json"
  STARTED="$(jq -r '.started // empty' "$ST_PATH")"; [[ -n "$STARTED" ]] || STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  CUTS_JSON="$(jq -c '.cuts // []' "$ST_PATH")"; RETRIES_JSON="$(jq -c '.retries // []' "$ST_PATH")"
  PAUSED_JSON="$(jq -c '.paused_arms // {}' "$ST_PATH")"
  LEDGER_USD="$(jq -r '.spend.ledger_usd // 0' "$ST_PATH")"; SPENT="$(fadd "$SPENT" "$LEDGER_USD")"
  EXTRA_RUNS_JSON="$(jq -c '.extra_models_by_run // {} | if type == "object" then . else {} end' "$ST_PATH")"
  DRIFT_CLEARED_JSON="$(jq -c '.drift_cleared // []' "$ST_PATH")"; REROWED_JSON="$(jq -c '.rerowed // []' "$ST_PATH")"
  RERUN_JSON="$(jq -c '.rerun // []' "$ST_PATH")"
  OUTAGE_HISTORY_JSON="$(jq -c '.outage_history // []' "$ST_PATH")"
  if [[ "$(jq -c '.outage // null' "$ST_PATH")" != null ]]; then
    OUTAGE_HISTORY_JSON="$(jq -c --argjson o "$(jq -c '.outage' "$ST_PATH")" '. + [$o]' <<<"$OUTAGE_HISTORY_JSON")"
    log "resume: the outage breaker record $(jq -c '.outage' "$ST_PATH") is cleared (kept under outage_history)"
  fi
  if [[ "$CLEAR_PENDING" != null ]]; then
    DRIFT_CLEARED_JSON="$(jq -c --argjson c "$CLEAR_PENDING" '. + [$c]' <<<"$DRIFT_CLEARED_JSON")"
    log "resume: --clear-drift $(jq -r '.run_id' <<<"$CLEAR_PENDING") (previous drift re-read under the current rule: none)"
  fi
  for a in ${CLEAR_ARMS[@]+"${CLEAR_ARMS[@]}"}; do
    if is_paused "$a"; then PAUSED_JSON="$(jq -c --arg a "$a" 'del(.[$a])' <<<"$PAUSED_JSON")"; log "resume: --clear-arm $a (paused arm released)"
    else log "resume: --clear-arm $a: the arm is not paused"; fi
  done
  # rerows first, so spend and per_arm below come from the final rows
  rerow_all
  if [[ -f "$ROWS" ]]; then
    dup="$(jq -R -r --arg b "$BATCH" 'fromjson? | select(type == "object" and .batch == $b) | .run_id' "$ROWS" | sort | uniq -d | head -3 | tr '\n' ' ')"
    [[ -z "$dup" ]] || refuse "resume: $ROWS holds run_id(s) twice: $dup"
    want_ids=$'\n'; for r in ${RERUN_IDS[@]+"${RERUN_IDS[@]}"}; do want_ids="$want_ids$r"$'\n'; done
    rerow_ids=$'\n'; for r in ${REROW_IDS[@]+"${REROW_IDS[@]}"}; do rerow_ids="$rerow_ids$r"$'\n'; done
    want_st=" ${RERUN_STATUSES[*]+"${RERUN_STATUSES[*]}"} "
    while IFS=$'\t' read -r rid st cost deg; do
      k=-1
      for j in "${!PL_RUN[@]}"; do [[ "${PL_RUN[$j]}" == "$rid" ]] && { k=$j; break; }; done
      [[ $k -ge 0 ]] || continue
      r_att="$(jq -R -r --arg b "$BATCH" --arg r "$rid" 'fromjson? | select(type == "object" and .batch == $b and .run_id == $r) | (.attempts // 1)' "$ROWS" | tail -1)"
      r_all="$(jq -R -r --arg b "$BATCH" --arg r "$rid" 'fromjson? | select(type == "object" and .batch == $b and .run_id == $r) | (.all_spend_usd // .cost_usd // 0)' "$ROWS" | tail -1)"
      if [[ "$want_st" == *" $st "* && "$want_ids" != *$'\n'"$rid"$'\n'* && "$rerow_ids" != *$'\n'"$rid"$'\n'* ]] \
         && { [[ "${PL_K[$k]}" -gt 0 ]] || [[ "${r_att:-1}" -ge 3 ]]; }; then
        # cycle-132 D-7.3: a matched cell is never rerun as a whole; a row at 3 attempts is at the limit
        log "resume: --rerun-status $st skips $rid ($([[ "${PL_K[$k]}" -gt 0 ]] && echo "a matched cell" || echo "at ${r_att} attempts, the limit of 3"))"
        st="__kept__"
      fi
      if [[ "$want_ids" == *$'\n'"$rid"$'\n'* ]] \
         || { [[ "$want_st" == *" $st "* ]] && [[ "$rerow_ids" != *$'\n'"$rid"$'\n'* ]]; }; then
        RERUN_PRIOR="$(jq -c --arg r "$rid" --arg a "${r_att:-1}" --arg u "${r_all:-0}" '.[$r] = {attempts: ($a | tonumber), usd: ($u | tonumber)}' <<<"$RERUN_PRIOR")"
        # DEC-0553: out of the done set, so the plan launches it again; no counter, no assumed charge;
        # its reported cost (real spend) stays in spent
        [[ "$cost" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || cost=0
        RERUN_LIST="$RERUN_LIST$rid"$'\n'; SPENT="$(fadd "$SPENT" "$cost")"
        RERUN_OLD="$(jq -c --arg r "$rid" --arg s "$st" --arg c "$cost" '.[$r] = {status: $s, cost: ($c | tonumber)}' <<<"$RERUN_OLD")"
        continue
      fi
      [[ "$st" == __kept__ ]] && st="$(jq -R -r --arg b "$BATCH" --arg r "$rid" 'fromjson? | select(type == "object" and .batch == $b and .run_id == $r) | .status' "$ROWS" | tail -1)"
      DONE_LIST="$DONE_LIST$rid"$'\n'
      i="$(arm_index "${PL_ARM[$k]}")"; C_LAUNCHED[$i]=$(( ${C_LAUNCHED[$i]} + 1 )); LAUNCHED=$((LAUNCHED + 1))
      if [[ "${PL_K[$k]}" -gt 0 ]]; then account_cell "${PL_ARM[$k]}" "$st" "$deg"   # its sessions are charged below
      else account_row "${PL_ARM[$k]}" "${PL_KIND[$k]}" "$rid" "$st" "$cost" "$deg"; fi
    done < <(jq -R -r --arg b "$BATCH" 'fromjson? | select(type == "object" and .batch == $b)
               | [.run_id, .status, ((.cost_usd // 0) | tostring), ((.degraded // false) | tostring)] | @tsv' "$ROWS")
  fi
  # cycle-132: every recorded session of a matched cell is charged from its record (rowed or not); a cell with a
  # record and no row counts as launched
  for k in "${!PL_RUN[@]}"; do
    [[ "${PL_K[$k]}" -gt 0 ]] || continue
    c="$(cell_dir_of "$k")" any=false
    for f in "$c"/meta/sessions/s*.json; do
      [[ -f "$f" ]] || continue
      any=true; charge_session "$f" "${PL_KIND[$k]}" "${PL_ARM[$k]}"
    done
    if [[ "$any" == true ]] && ! is_done "${PL_RUN[$k]}"; then
      i="$(arm_index "${PL_ARM[$k]}")"; C_LAUNCHED[$i]=$(( ${C_LAUNCHED[$i]} + 1 )); LAUNCHED=$((LAUNCHED + 1))
    fi
  done
  n_rerun="$(printf '%s' "$RERUN_LIST" | grep -c . || true)"
  [[ ${#RERUN_STATUSES[@]} -eq 0 && ${#RERUN_IDS[@]} -eq 0 ]] \
    || log "resume: $n_rerun trial(s) flagged for a rerun (--rerun ${RERUN_IDS[*]+"${RERUN_IDS[*]}"} --rerun-status ${RERUN_STATUSES[*]+"${RERUN_STATUSES[*]}"}; DEC-0553)"
  log "resume: batch $BATCH, $LAUNCHED of $PLAN_N trials rowed, spent $SPENT, paused $(jq -c 'keys' <<<"$PAUSED_JSON")"
fi

# --- dispatch --------------------------------------------------------------------------
log "start batch=$BATCH smoke=$SMOKE source=${SRC_FULL:0:12} executor=$EXECUTOR image=$IMAGE cli=$CLI_VERSION concurrency=$CONCURRENCY rows=$ROWS"
log "$PLAN_LINE"
[[ "$RESUME" == true ]] || jq -r '.refused[] | "refused: \(.arm) \(.task_id) \(.type) (task_types \(.task_types | tojson)) DEC-0405"' "$WORK/plan.json" \
  | while IFS= read -r l; do log "$l"; done
write_status
trap on_signal INT TERM HUP

n=0
for k in "${!PL_RUN[@]}"; do
  rid="${PL_RUN[$k]}" a="${PL_ARM[$k]}"
  is_done "$rid" && continue
  [[ -z "$STOP" ]] || break
  if [[ "${PL_K[$k]}" -gt 0 ]]; then
    # cycle-132: a matched cell — its sessions without a record are the work units, in order
    cell="$(cell_dir_of "$k")" cell_launched=false cut_now=false
    mkdir -p "$cell/meta/sessions"; printf '%s\n' "$a" > "$cell/meta/arm"   # read by the session took-effect
    if cell_sessions_done "$k"; then finalize_cell "$k"; continue; fi
    for f in "$cell"/meta/sessions/s*.json; do [[ -f "$f" ]] && cell_launched=true; done   # counted by the resume
    for s in $(seq 1 "${PL_K[$k]}"); do
      [[ -f "$cell/meta/sessions/s$s.json" ]] && continue
      [[ -z "$STOP" ]] || break
      if is_paused "$a"; then i="$(arm_index "$a")"; C_SKIPPED[$i]=$(( ${C_SKIPPED[$i]} + 1 )); break; fi
      reap "$CONCURRENCY"
      [[ -z "$STOP" ]] || break
      if is_paused "$a"; then i="$(arm_index "$a")"; C_SKIPPED[$i]=$(( ${C_SKIPPED[$i]} + 1 )); break; fi
      if [[ -n "$MAX_USD" ]] && ! budget_gate "$a|${PL_KIND[$k]}" "$((k + 1))" "${PL_KIND[$k]}" "$RESERVE_CAP"; then
        CUTS_JSON="$(jq -c --argjson c "$CUT_JSON" '. + [$c]' <<<"$CUTS_JSON")"; STOP=cut; write_status; cut_now=true; break
      fi
      [[ -z "$STOP" ]] || break
      if is_paused "$a"; then i="$(arm_index "$a")"; C_SKIPPED[$i]=$(( ${C_SKIPPED[$i]} + 1 )); break; fi
      n=$((n + 1)); jid="$(printf 'j%04d' "$n")"
      run_session "$jid" "$k" "$s" &
      PIDS+=("$!"); PJOB+=("$jid"); PIDX+=("$k:$s")
      if [[ "$cell_launched" != true ]]; then
        i="$(arm_index "$a")"; C_LAUNCHED[$i]=$(( ${C_LAUNCHED[$i]} + 1 )); LAUNCHED=$((LAUNCHED + 1))
      fi
      cell_launched=true
      log "launch $rid-s$s ($a ${PL_TASK[$k]} ${PL_TYPE[$k]} t${PL_TRIAL[$k]} session $s of ${PL_K[$k]})"
    done
    [[ "$cut_now" != true ]] || break
    continue
  fi
  if is_paused "$a"; then i="$(arm_index "$a")"; C_SKIPPED[$i]=$(( ${C_SKIPPED[$i]} + 1 )); continue; fi
  reap "$CONCURRENCY"
  [[ -z "$STOP" ]] || break
  if is_paused "$a"; then i="$(arm_index "$a")"; C_SKIPPED[$i]=$(( ${C_SKIPPED[$i]} + 1 )); continue; fi
  if [[ -n "$MAX_USD" ]] && ! budget_gate "$a|${PL_KIND[$k]}" "$((k + 1))" "${PL_KIND[$k]}" "$RESERVE_CAP"; then
    CUTS_JSON="$(jq -c --argjson c "$CUT_JSON" '. + [$c]' <<<"$CUTS_JSON")"; STOP=cut; write_status; break
  fi
  [[ -z "$STOP" ]] || break
  if is_paused "$a"; then i="$(arm_index "$a")"; C_SKIPPED[$i]=$(( ${C_SKIPPED[$i]} + 1 )); continue; fi
  n=$((n + 1)); jid="$(printf 'j%04d' "$n")"
  p_att="$(jq -r --arg r "$rid" '.[$r].attempts // 0' <<<"$RERUN_PRIOR")" p_usd="$(jq -r --arg r "$rid" '.[$r].usd // 0' <<<"$RERUN_PRIOR")"
  run_trial "$jid" "$a" "${PL_TASK[$k]}" "${PL_TYPE[$k]}" "${PL_KIND[$k]}" "${PL_TRIAL[$k]}" "$rid" "${PL_YAML[$k]}" "${PL_WD[$k]}" "$p_att" "$p_usd" &
  PIDS+=("$!"); PJOB+=("$jid"); PIDX+=("$k")
  i="$(arm_index "$a")"; C_LAUNCHED[$i]=$(( ${C_LAUNCHED[$i]} + 1 )); LAUNCHED=$((LAUNCHED + 1))
  log "launch $rid ($a ${PL_TASK[$k]} ${PL_TYPE[$k]} t${PL_TRIAL[$k]})"
done
reap 1

# --- the batch's end state ---------------------------------------------------------------
total_completed=0 left=0 excluded=0
for i in "${!ARMS[@]}"; do total_completed=$(( total_completed + ${C_COMPLETED[$i]} )); excluded=$(( excluded + ${C_EXCLUDED[$i]} )); done
for k in "${!PL_RUN[@]}"; do is_done "${PL_RUN[$k]}" || left=$((left + 1)); done
paused_n="$(jq 'length' <<<"$PAUSED_JSON")"
if [[ "$ROWS_INVALID" != null ]]; then
  finish failed 3 "failed: the rows file is invalid after $(jq -r '.run_id' <<<"$ROWS_INVALID") ($(jq -r '.error' <<<"$ROWS_INVALID"))"
elif [[ "$DRIFT_JSON" != null ]]; then
  finish failed 3 "failed: drift in $(jq -r '.run_id' <<<"$DRIFT_JSON") ($(jq -r '.field' <<<"$DRIFT_JSON"): expected $(jq -c '.expected' <<<"$DRIFT_JSON"), got $(jq -c '.got' <<<"$DRIFT_JSON"))"
elif [[ "$OUTAGE_JSON" != null ]]; then
  finish partial 1 "$(jq -r '.message' <<<"$OUTAGE_JSON")"
elif [[ "$CUTS_JSON" != '[]' && $left -gt 0 ]]; then
  finish partial 1 "partial (cut max_usd): $((PLAN_N - left)) of $PLAN_N rowed, spent $SPENT"
elif [[ $total_completed -eq 0 ]]; then
  finish failed 3 "failed: no trial completed ($((PLAN_N - left)) rowed, $left without a row)"
elif [[ $paused_n -gt 0 && $left -gt 0 ]]; then
  if [[ "$paused_n" -ge "${#ARMS[@]}" ]]; then
    finish failed 3 "failed: every arm is paused by took-effect ($(jq -c 'keys' <<<"$PAUSED_JSON")); $left trials left"
  fi
  finish partial 1 "partial: paused arm(s) $(jq -c 'keys' <<<"$PAUSED_JSON") left $left trials; --resume --clear-arm <id> after reading the cause"
elif [[ $left -gt 0 ]]; then
  finish partial 1 "partial: $left of $PLAN_N trials have no row (see run.log)"
elif [[ $excluded -gt 0 ]]; then
  finish partial 1 "partial: all $PLAN_N trials rowed, $excluded excluded (transport, infrastructure, interrupted or contaminated)"
else
  finish complete 0 "complete: $PLAN_N trials rowed, spent $SPENT"
fi
