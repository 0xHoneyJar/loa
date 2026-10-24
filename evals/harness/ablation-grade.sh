#!/usr/bin/env bash
# =============================================================================
# ablation-grade.sh — the cycle-130 ablation grader (SDD §3.6, §5.7, D-4.7, D-4.8;
# PRD FR-6 AC-6.1/6.2/6.4; DEC-0401, DEC-0413, DEC-0414, DEC-0420, DEC-0491, DEC-0493)
#
# Grades ONE run directory written by pipeline-run.sh against its task and writes
# grade.json (the input ablation-row.sh joins into the runs.jsonl row), or
# self-checks a task (--self-check) on a synthetic run built from the task itself.
#
# Usage:
#   ablation-grade.sh <run-dir> <task-id> [--suite-root DIR] [--tasks-dir tasks|smoke]
#                     [--out FILE] [--json] [--executor container|host]
#                     [--image loa-ablation:259] [--docker-bin D]
#                     [--allow-unfrozen] [--allow-partial] [--judge-verdicts FILE [--run-id ID]]
#   ablation-grade.sh --self-check base|reference|noisy --task-yaml F [--suite-root DIR]
#                     [--executor …] [--image …] [--docker-bin D] [--json]
#                     [--allow-unfrozen] [--allow-partial]
#   ablation-grade.sh --union <cell-dir> --task-id T [--suite-root DIR] [--tasks-dir T]
#                     [--out FILE] [--json] [--allow-unfrozen] [--allow-partial] [--judge-verdicts FILE [--run-id ID]]
#
# Options:
#   --suite-root DIR   suite root (default grimoires/loa/evals/ablation-2.0; with
#                      --self-check, the directory two levels above the task dir)
#   --tasks-dir T      tasks (default) or smoke: the task is <root>/<T>/<task-id>/
#   --out FILE         where grade.json goes (default <run-dir>/grade.json)
#   --json             also print grade.json (self-check: the verdict object) on stdout
#   --executor MODE    container (default; DEC-0491) or host. host runs the agent's code on
#                      this machine as the calling user without isolation and is refused
#                      (exit 2) unless LOA_EVAL_ALLOW_HOST_GRADING=1; allowed, it prints a
#                      WARNING and grade.json records executor_mode: host (LOW-A1)
#   --image IMG        the grading image (default loa-ablation:259, the pinned pipeline image)
#   --docker-bin D     docker CLI (default $EVAL_DOCKER_BIN, else docker)
#   --allow-unfrozen   grade although freeze.sh --check fails or the suite has no
#                      MANIFEST.sha256 yet (task authoring only); grade.json records
#                      suite_frozen: false. Without it a drift is exit 2 (DEC-0414).
#   --allow-partial    passed to freeze.sh --check (fewer than four tasks per type)
#   --self-check MODE  base | reference | noisy (noisy: review-catch only), see below
#   --task-yaml F      the task to self-check (<root>/<tasks|smoke>/<id>/task.yaml)
#   --union DIR        (1.3.2) grade a matched cell (see "Union" below); --task-id names its task
#   --judge-verdicts F (1.5.0) the judge's verdicts JSONL, bound to this grade's credited pairs (see "grader 1.5.0"
#                      below); review-catch run and union grades only (a build task or --self-check is exit 2)
#   --run-id ID        (1.5.0) the run id the verdict rows must name (default: the run or cell directory's name)
#
# Environment: LOA_EVAL_ALLOW_HOST_GRADING=1 (see --executor); LOA_EVAL_GRADE_TIMEOUT_S
# (1-9999, default 120: the per-command deadline; tests shorten it).
#
# Reads ONLY (DEC-0413): <run-dir>/sandbox/, <run-dir>/snapshots/{index.json,<LABEL>.bundle},
# <run-dir>/transcripts/events-*.jsonl, <run-dir>/eval/adversarial-{review,audit}.json,
# the task's directory under the suite root (task.yaml, hidden/, fixture/), the suite's
# MANIFEST.sha256 (through freeze.sh) and, for review-catch, the key manifest the task
# names (review_catch.manifest), its v1/ snapshot when present, the corpus SHA256SUMS above
# it (hashed into corpus_sha256) and the task's PR fixture (head/ for the same-scope rule;
# head.diff, head/ and base/ for the oracle detector and the KF-046 class 7 exemption; the
# whole fixture for the self-check), never the agent-writable sandbox pr/; the oracle detector
# also reads sandbox/<answer path> (bounded, symlink-refusing) as the later copy. It never reads
# <run-dir>/meta/, the batch MANIFEST.json, or the sandbox copies of the dissent
# envelopes (tamperable; the harness copies under eval/ are authoritative). It writes
# only <run-dir>/grading/ and the --out file; nothing under sandbox/ is ever written.
#
# Freeze: freeze.sh --check --root <suite-root> runs first (with --smoke when the
# suite manifest lists smoke/ paths, so a manifest frozen with --smoke checks as it
# was frozen); a drift or a missing manifest refuses the grade (exit 2) unless
# --allow-unfrozen.
#
# Grading trees (D-4.8) under <run-dir>/grading/<label>/, recreated on every call:
#   final      sandbox/ as the agent left it, minus the top-level .git .claude CLAUDE.md
#              .loa.config.yaml grimoires .run .beads .eval pr, every __pycache__ and
#              .pytest_cache, anything that is not a regular file, directory or
#              symlink (a FIFO never blocks the copy), every regular file above 16 MiB
#              (lstat size; counted in oversized_files_skipped, also for snapshot tar
#              members), and every symlink whose target is
#              absolute or resolves outside the tree (lexically, then through the other
#              links; counted in symlinks_dropped); in-tree relative links are kept
#   implement  the IMPLEMENT snapshot (snapshots/IMPLEMENT.bundle, commit
#              index.json.implement): the tree REVIEW read; graded when REVIEW ran or
#              when AUDIT ran without a fix1 snapshot
#   fix1       the FIX1 snapshot: the tree AUDIT read; graded when AUDIT ran
#   base       the task fixture: the baseline of the regression check (regression_command;
#              refactor: test_command, the fixture suite)
# A snapshot is extracted with `git bundle unbundle` into a scratch bare repository and
# `git archive <commit>` (tarfile.data_filter: a member that would land outside the tree,
# and a symlink member with an absolute or escaping target, is skipped). In
# every tree each grader_protected path is restored from the fixture (a deleted file is
# recreated, a modified one overwritten, a path the fixture lacks is removed; a
# symlinked parent is replaced by a directory), then every hidden/manifest.json entry
# is written at its dest (a same-named file is overwritten, a deleted directory
# recreated). Then (HIGH-A1) every pytest or bats harness file in the tree — conftest.py
# at any depth, pytest.ini, .pytest.ini, pyproject.toml, setup.cfg, tox.ini,
# setup_suite.bash, any *helper*.bash or *helper*.sh, any .bash file under a tests/ or test/
# directory — is removed unless it is a hidden overlay dest or a regular file byte-identical
# (filecmp, shallow=False) to the fixture's regular file at the same path; a symlink at such
# a path is always removed. The count goes to harness_files_removed (every tree graded), the
# paths to grading/<label>.harness-removed.txt beside the tree (never into grade.json).
# Deleting a grading tree never chmods through a symlink. Churn
# (diff_lines, files_changed) compares the final tree against the
# fixture before any restore: added + removed lines per changed text file (difflib),
# every added, removed or modified file counted once (a file above 16 MiB on either side
# is counted as changed and never read or diffed); null for review-catch.
#
# Commands run INSIDE the image (DEC-0491):
#   docker run --rm --init --name ablgrade-<run>-<label>-<pid>-<n> --network none --read-only
#     --tmpfs /tmp:rw,size=256m --pids-limit 256 --memory 2g --cpus 2 --cap-drop ALL
#     --security-opt no-new-privileges --user <uid>:<gid> -v <tree>:/workspace:rw -w /workspace
#     -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp <image> timeout --signal=TERM --kill-after=10 120 <cmd…>
# (MEDIUM-A1) The docker client gets its own deadline (120 + 10 + 60 s); when it passes, or
# the grader fails while the client runs, the client's process group is killed and
# `docker kill <name>` then `docker rm -f <name>` run (errors ignored): the result is
# timed_out with rc 124. Exit 124, or 137 after the deadline, is timed_out too. Captured
# output (stdout + stderr) is read in chunks and capped at 4 MiB — the first and the last
# 2 MiB are kept, so the summary survives — and output_truncated records a cut.
# `python3 -m pytest …` (or `pytest …`) becomes `python3 -I -s -m pytest -p no:cacheprovider
# -o addopts= -q --rootdir /workspace -rA …` (one -q: -qq would drop the summary line; -rA
# lists every outcome, from which the ids come; -o addopts= voids an ini file's addopts);
# `bats …` becomes `bats --tap …` with BATS_LIB_PATH
# unset (the -e set is the whole container environment). --executor host runs the same
# argv (with the same timeout prefix) in the tree under `env -i PATH HOME=<scratch> LC_ALL=C TMPDIR=<scratch>
# PYTHONUSERBASE=<the caller's user base>` with pytest as `python3 -P -m pytest …`:
# no -I or -s on the host, because the host's pytest lives in the user site (the Sprint
# 258 smoke found no pytest under `-I -s`); PYTHONUSERBASE is passed for the same reason.
#
# Parsing: the pytest summary line (`N passed, M failed, K error …`) or TAP (`1..N`,
# `ok`/`not ok`). A collection error is expanded to the test functions of its file; the
# hidden total is never below the static case count of the hidden test files (`def test`
# / `@test`). A command without a parseable summary counts total = that static count
# (at least 1), passed = 0 when it exited non-zero (total when it exited 0), with
# parse_error: true. Ids: "t<k>", k = the 1-based position of the case in file order
# (pytest: path, then the line of its def; TAP: the test number). A node path is printed
# by code under test (MEDIUM-A2): its def lines come from the grader-owned copy (the hidden
# overlay source, a protected fixture file) when the path has one; else the path must be
# relative, stay inside the tree and open as a regular file of at most 1 MiB (O_NOFOLLOW |
# O_NONBLOCK, fstat) — a device, a FIFO, a symlink or a path above the tree orders last
# (unknown def line) and expands no collection error. Regression ids are
# positions in the base run, newly_failing = failing at final, passing at base. When
# either side of the regression check has no parseable summary, regressions.parse_error is
# true and newly_failing comes from the exit statuses: base unparsed, exit 0, final exit
# non-zero or timed out → every fallback id; base parsed, final unparsed and failed → every
# base-passing case; else none. A run is green (all_pass) only when every case passed, the
# summary parsed, the command exited 0 and did not time out.
#
# Hidden assertion per type: bug-fix and feature-build — test_command is hidden_tests,
# regression_command the regression check; refactor (DEC-0401, AC-5.3) — the structural
# check (structural_check's overlay dest, run with pytest or bats) is hidden_tests, so the
# row's hidden_test_pass_rate is the structural pass rate, and test_command (the fixture
# suite) is the regression check at base and final; structural repeats the structural
# counts with suite_green_base and suite_green_final.
#
# Review-catch (DEC-0420): grading/gates-combined.md is the arm-neutral reduction: every
# `path:line[-line]` citation (parser of recall-vs-defects.sh 1.1.2; the LOA-VERDICT
# trailer removed first) from sandbox/review.md (the A0 contract),
# sandbox/grimoires/loa/a2a/sprint-1/{engineer-feedback.md,auditor-sprint-feedback.md}
# and each finding's anchor (and file:line) in eval/adversarial-{review,audit}.json,
# one normalised `path:line[-line]` line each (pr/head/ → head/, a/ b/ and /workspace/
# prefixes dropped), duplicates dropped. recall-vs-defects.sh <grading-dir> <pr-NN>
# gates-combined.md (EVAL_MANIFEST_DIR = the manifest's directory, EVAL_HEAD_DIR = the PR
# fixture's head/) gives recall; flags = its findings_cited; missed = defect positions ("d2"),
# never defect ids. Grader 1.3.0 (cycle-131 FR-2, recall-vs-defects.sh 1.3.0): recall /
# defects_caught / missed follow the rule "pm3_or_same_function" (±3 of a site, or a valid
# citation inside the site's enclosing definition); recall_pm3 / missed_pm3 keep the 1.2.0 ±3
# rule on the current manifest and recall_pm3_v1 / missed_pm3_v1 the 1.2.0 rule on
# manifests/v1/<pr>.json (v1_manifest false: the current manifest stood in);
# credits_function_only lists the positions only the scope clause credited; rule names it. A
# finding's numeric anchor (anchor_line, anchor_line_end: integers >= 1, end > start for a
# range) is cited as <the anchor's path part, else the finding's file>:line[-end].
# false_positives = citations within ±3 of no anchor, deduplicated by cited region
# (same file, overlapping ±3 windows count once).
#
# Verdicts: the last `<!-- LOA-VERDICT {…} -->` trailer of engineer-feedback.md (review)
# and auditor-sprint-feedback.md (audit); a gate ran when its feedback path exists. Every
# sandbox file the grader reads (the feedback files, review.md) and the eval/ envelopes are
# read as regular files only, first 2 MiB (O_NOFOLLOW | O_NONBLOCK; sandbox files must also
# resolve inside sandbox/): a symlinked or otherwise unreadable feedback file is verdict
# "none" (the gate ran, no readable trailer), a symlinked review.md gives no verdict and no
# citations (MEDIUM-A3).
# verdict = {source_file, value}: the audit's, else the review's, else review.md's
# `Verdict:` line (A0), else null. verdict_accuracy_per_gate {review, audit}: build —
# true when APPROVED and the tree that gate read passes every hidden test, or
# CHANGES_REQUIRED and it fails one; review-catch — true iff (CHANGES_REQUIRED) ==
# (the key holds a high or critical defect); refactor — the tree passes when the
# structural check AND the fixture suite are green on it; a gate without a trailer is false; a gate
# that did not run is null. verdict_accuracy = audit's, else review's, else null.
#
# Contamination (D-4.7, DEC-0493): every tool_use input in transcripts/events-*.jsonl —
# Bash command; Read/Grep/Glob file_path|path|pattern; Write/Edit/MultiEdit/NotebookEdit
# file_path|notebook_path; WebFetch url; WebSearch query — is checked for: `hidden` (any
# case; in a Bash command only as a token: HIDDEN, or hidden in any case next to / . _ = - * ?,
# or hidden followed by a capital (hiddenTests) — 1.2.4 DEC-0551, 1.2.6 LOW-2; accepted gap: a
# bare `hidden` argument is not a probe in a suite whose briefs are about hidden state —
# refactor-03's agents run pytest -k hidden for their own test_no_hidden_state) → hidden; grimoires/loa/evals/ablation-2.0 → suite_path; 0xHoneyJar/loa →
# repo_name; `git log … --all` or `git reflog` (Bash) → counted in history_probes, NOT a
# contamination hit (1.2.1, DEC-0540: the sandbox is a fresh git init at base, so there is no
# history to leak; the count is telemetry); an absolute path
# (path fields, the Glob pattern, path-shaped Bash words; a one-component `/x/` word is
# read as a regex only right after s, y, =, ~ or a single quote — `cd /root/` is a path; a
# one-component `/word` with no second slash is a command token — Loa slash commands such as
# `/review-sprint sprint-1` in report text — unless the component is root, home, mnt, media or
# srv, 1.2.1 DEC-0540; such a sensitive one-component word is skipped only inside a quoted
# string with other text — grep -E ' /tmp | /home ' — while the word that is the whole quoted
# argument, cd "/root", ls '/home', cd '/root/', grep '/root' f, is a candidate: a quote state
# machine, not a parity count, 1.2.6 LOW-1; accepted gaps: a one-component word inside longer
# quoted text, echo "cd /root", and $'…' strings read as plain single quotes. Heredoc bodies
# are stripped; the operator line is scanned — cat <<'EOF' > /root/x is a hit, 1.2.6
# MEDIUM-1. Heredoc bodies are not path-scanned even when the operator line's command is an
# interpreter (python3, python, bash, sh, node, perl, ruby; python3 - <<'PY'): that code
# opens whatever it names, but the cycle grades the container executor only (DEC-0411; host
# grading needs LOA_EVAL_ALLOW_HOST_GRADING=1), where /root, /mnt, /media and /srv hold
# nothing, so the gap is a missed signal, not a missed leak; widening the scan would re-open
# the written-prose false positives of KF-046. The hidden/suite/repo substring scans still
# read every body, and grade.json heredoc_interpreters counts these heredocs, 1.2.6 LOW-3)
# outside /workspace /tmp /home/evaluser /dev /proc /sys /usr /bin
# /sbin /lib /lib64 /etc /opt /var (container), or outside the sandbox root (the
# sessions' init cwd and <run-dir>/sandbox), /tmp and those system directories (host; no
# credential store under ~ is exempt: LOW-A2) → outside_path. A path or Bash word starting
# ~/, $HOME/ or ${HOME}/ is always outside, and /proc/<pid|self|thread-self>/{environ,
# cmdline,maps,mem} and /var/run are outside although /proc and /var are allowed. The first hit
# in phase order is contaminated: {phase, pattern, excerpt_id: "<phase>:<line>"} (never
# the text); else null. The scan is a LOWER BOUND on leakage: obfuscated access, reads
# by programs the agent wrote, and network access by other means are not seen.
#
# grade.json (ids only in every summary field: no test name, defect title or excerpt):
#   {schema_version: 1, grader_version: "1.2.0", task_id, task_type, suite_frozen,
#    executor_mode, image, snapshots_graded: [labels], hidden_tests {passed, total,
#    failed_names, parse_error, timed_out, rc, output_truncated}, structural (refactor:
#    {passed, total, failed_names, parse_error, suite_green_base, suite_green_final}; else
#    null), regressions ({newly_failing, base {passed, total, rc, timed_out,
#    output_truncated}, final {…}, parse_error, base_green, final_green} or null without a
#    regression check), snapshot_tests {implement?,
#    fix1?: {passed, total}} (refactor: the structural check), recall (review-catch
#    {defects_seeded, defects_caught, recall, flags, missed}; else null),
#    false_positives, verdict, verdicts {review, audit}, verdict_accuracy,
#    verdict_accuracy_per_gate {review, audit}, diff_lines, files_changed,
#    symlinks_dropped, harness_files_removed, oversized_files_skipped, history_probes,
#    heredoc_interpreters (1.2.6: heredocs in Bash inputs whose operator line's command, the
#    first word after the last ; & | ( or { before << and after NAME=value assignments, by
#    basename, is python3, python3.N, python, bash, sh, node, perl or ruby; counted up to the
#    first contamination hit, like history_probes; telemetry, not a row field), contaminated,
#    contamination_exempt [{phase, excerpt_id, pattern, fixture_line, line}] (1.3.0: KF-046 class 7; 1.3.8 and 1.4.0:
#    {phase, excerpt_id, pattern, class} for repo_name_pr_native, repo_name_pr_native_report, home_mount_probe),
#    label_set (cycle-132 FR-2, D-2.3: c131, v1 or review for a key in manifests/c131/, v1/ or review/, else v2;
#    a set key's v1 snapshot is manifests/v1/<pr>.json and corpus_sha256 hashes the SHA256SUMS above manifests/),
#    labels_meta [{defect: d<n>, label_source, agreement, review_driven}] (the key's per-defect provenance,
#    null where the key has none); both null for build tasks,
#    oracle_exposed_defects, oracle_exposed_unknown, oracle_exposed_events, oracle_exposed_by_form
#    (1.3.0: the oracle detector below; null for build tasks), corpus_sha256 (1.3.0: sha256 of the review
#    corpus SHA256SUMS; null for build tasks or without the file); review-catch recall also carries
#    recall_pm3, missed_pm3, recall_pm3_v1, missed_pm3_v1, v1_manifest, credits_function_only, rule}
# grader 1.5.0 (cycle-133 Sprint 274 Task 3.2; SDD C-11, D-3.2 DEC-0849; PRD FR-11): --judge-verdicts. Without the flag a
# grade is 1.4.0's, grader_version aside (evals/tests/fixtures/grader-1.5/regress.sh grades every fixture shape of
# evals/tests/ablation-grade.bats with the 1.4.0 grader of the Sprint 2 head and compares). A credited pair is (citation,
# defect) for every citation within ±3 of a site of the defect (pm3, the decision rule; DEC-0638); its finding is the
# citation's canonical reference {id, file, anchor_line[, anchor_line_end]} (file without head/ or base/; id
# F-<first 6 hex of sha256("<file>:<anchor_line>:")>, the C-11 derivation with no title — the same file and line are one
# finding). The verdicts file is JSONL, one object per line (blank lines skipped), exactly the keys {run_id, finding_id,
# finding_sha256, defect_key (d<n>), fixture_sha256, grader_version, verdict (describes | does_not_describe), judge_model,
# judge_prompt_sha256, blind (boolean), ts (ISO 8601)} plus an optional supersedes; every row is validated before any
# grading (a malformed row is exit 2). Hashes are sha256 of the RFC 8785 text: finding_sha256 of the reference,
# fixture_sha256 of the task's key manifest, a row's own identity of the row. Binding is one-to-one by (run_id,
# finding_id, defect_key): rows naming another run id are ignored and counted (judge.rows_other_runs); a row of this run
# whose grader_version is not this grader's, whose fixture_sha256 or finding_sha256 is not the current one, or whose pair
# this grade does not credit is stale and rejects the grade (exit 2, no grade.json written); a second row for a pair is
# refused unless it names an earlier row of the same pair in supersedes (the sha256 of that row), and a row is superseded
# at most once. Fields (only with the flag; review-catch): fixture_sha256, credited_pairs [{finding_id, finding_sha256,
# defect_key, verdict, blind}] (null verdict and blind when unjudged; ordered by defect, then finding id), recall_judged
# (defects with a blind `describes` verdict on a credited pair / defects_seeded, 4 decimals), recall_judged_unblind (the
# same with blind: false verdicts counted too), judged_pairs (blind verdicts), judged_pairs_unblind, unjudged_pairs
# (credited pairs with no verdict), judge {run_id, verdicts_sha256 (the file's bytes), rows_this_run, rows_other_runs,
# rows_superseded, judge_models, judge_prompt_sha256 (sorted, of the effective verdicts)}. An empty verdicts file lists
# the pairs to judge. A union grade (--union) binds its union citations the same way.
# grader 1.4.0 (cycle-133 Sprint 273 Task 2.3; SDD C-8; PRD FR-8; bd-kddde shapes 1 and 2): two contamination exemptions;
# every other class and field are unchanged, except that a value the exemptions clear no longer stops the scan, so
# contaminated may name a later hit and history_probes / heredoc_interpreters (counted up to the first hit) may grow
# (evals/tests/ablation-grade.bats AG-c133-5 re-grades each shape with the cycle-132 pin's 1.3.8 grader and compares;
# evals/tests/fixtures/grader-1.4/regress.sh does it for every grade the bats file takes). (1) class 7: with the token PR-native, a report written
# by heredoc is exempt as the Write tool's content already is (never scanned): cat or tee writing a .md, .markdown or .txt
# local path, every token inside the heredoc body, the heredoc neither piped on nor fed to an interpreter, no command
# substitution in an unquoted body, no other writer argument, no network-capable line beside it (heredoc_report_write;
# contamination_exempt class repo_name_pr_native_report). (2) outside_path: in container mode a bare /home word (/home,
# /home/; unglobbed) that is the argument of findmnt, df or mountpoint is exempt when every bare /home word of the value
# is one (home_mount_probe; contamination_exempt {pattern: outside_path, class: home_mount_probe}); ls /home, cd /home,
# H=/home, du and host mode are unchanged. bd-kddde's shapes (3) to (6) are not 1.4.0 rules (SDD C-8 names two).
# grader 1.3.8 (cycle-132 Sprint 269 round 12, PREREGISTRATION §12 addendum 8): class 7 (repo_name) gains a PR-native
# exemption. When the repository token occurs in the task's PR content (grade.json repo_token_pr_native true|false), a
# read-only local look at files that names the token (grep, rg, cat, sed without -i, awk, head, tail, less, find without
# -exec/-delete, ls, wc; no URL, GitHub host, fetcher token or output redirection; local path arguments only; or a
# Grep/Read/Glob input on a local path) is reading that PR content: recorded in contamination_exempt with class
# repo_name_pr_native. A fetch stays class 9; a heredoc fed to an interpreter naming the token stays class 7; build
# tasks (no PR) never qualify. Every other class and field is unchanged.
# grader 1.3.7 (cycle-132 Sprint 269 round 11, PREREGISTRATION §12 addendum 7): the `suite_path` class (a value naming
# grimoires/loa/evals/ablation-2.0) is scoped like `hidden`: build tasks only. A review-catch sandbox holds no suite root,
# and five registered PRs name that path in their own code (pr-23 created it); contamination_classes_skipped is
# ["hidden", "suite_path"] for review-catch and union grades, [] for build. Every other class and field is unchanged.
# grader 1.3.6 (cycle-132 Sprint 269 round 8, PREREGISTRATION §12 addendum 4): the `hidden` contamination class
# (HIDDEN_TOKEN, HIDDEN_GLOB, HIDDEN_FS and the non-Bash substring branch) applies to build tasks only (feature-build,
# bug-fix, refactor: the tasks graded against hidden/ tests). A review-catch sandbox holds no hidden tests, and a
# reviewer quoting a PR that implements a hidden-test check (pr-23) was excluded as contaminated; for review-catch the
# class is skipped and grade.json records contamination_classes_skipped ["hidden"] ([] for build tasks; a union grade
# ["hidden"]). Every other class (suite_path, repo_name with its class 7 exemption, outside_path, network_egress) and
# every non-contamination field are unchanged; a 1.3.5 review-catch grade may differ only in contaminated.
# grader 1.3.5 (cycle-132 Sprint 269 round 4, audit A1–A4): class 9 also recurses into bash|sh|zsh|dash|ksh -c strings;
# EGRESS_HOST matches any host ending in github.com, githubusercontent.com or github.io (codeload., gist., objects., www.
# included) and the python libraries add http.client, httpx, aiohttp, pycurl, socket and urllib3; class 9's own word
# reading (egress_words) drops leading shell keywords and the wrappers time, nohup, xargs, sudo, setsid, stdbuf, busybox,
# nice, env, command, exec and timeout (seg_words and the oracle detector are unchanged); <( … ) reads like $( … ); a
# heredoc piped into an interpreter (cat <<'EOF' | bash) is fed to it; inside one heredoc-stripped simple command a host
# with a fetcher token anywhere (curl, wget, git fetch|clone|pull|ls-remote, gh api|pr|issue|repo, pip|npm|go install)
# is egress; a pipeline whose curl/wget stage gets a host from another stage is egress. Heredoc bodies stay data unless
# fed to an interpreter. --union refuses a valid session graded by another grader version and per_session[] records
# grader_version. Recall and every non-egress field are unchanged.
# grader 1.3.4 (cycle-132 Sprint 269 round 3, dissent DISS-001/DISS-C-001/DISS-C-003): class 9 is judged per simple
# command on the heredoc-stripped text with the egress program in command position (see network egress above): 1.3.2's
# whole-value python clause flagged reviewer prose and combined words from separate commands. Recall, false positives
# and every non-egress field are unchanged; a 1.3.3 grade may differ only in contaminated (fewer class 9 hits).
# grader 1.3.3 (cycle-132 Sprint 269 round 2, recall-vs-defects.sh 1.3.1): the citation parser (CITE) and a numeric
# dissent anchor's path part accept an extension of up to 12 characters (was 6): a finding on .loa.config.yaml.example
# or Dockerfile.ablation is credited (the image self-check's reference read 0 on review-r16/r20/r22). A citation that
# parsed under 1.3.2 parses the same; the oracle detector's FILEISH token rule is unchanged.
# grader 1.3.2 (cycle-132 Sprint 269 Task 1.7b; SDD D-4.1, D-7.3; PRD FR-3, FR-5 (g), FR-11): additive; recall,
# the citation rule (DEC-0638: recall_pm3 is the decision statistic), false_positives, verdicts and every 1.3.1 field
# keep their 1.3.1 values on any run without a class 9 hit (evals/tests/ablation-grade.bats AG-c132-5 re-grades a run
# with the plan commit's 1.3.1 grader and compares).
#   false_positive_rule  "pm3" on every review-catch grade (null for build): false_positives counts citations within
#                  ±3 of no anchor of the task's manifest, deduplicated by cited region — the rule of recall_pm3, the
#                  decision statistic, so a precision read pairs recall_pm3's caught count with false_positives under one
#                  rule (bd-9zmfn). recall-vs-defects.sh's findings_refuted (details only) uses the same ±3 windows
#                  plus the fix regions. recall (pm3_or_same_function) is reported, never paired with false_positives.
#   multi_credit_citations  the distinct citations that credited two or more distinct defects under pm3 (a defect is
#                  distinct by id with its anchor set, credited at most once per run; one citation may credit every
#                  defect whose sites it hits; SKP-022); null for build tasks
#   network egress (class 9, PRD D15, bd-eriso): read FIRST for every tool input, so the KF-046 class 7 PR-content
#                  exemption never applies to it. Since 1.3.4 a Bash command is read as simple commands (newline, ;,
#                  &&, ||, | outside quotes) of its heredoc-stripped text, each judged by the program in command
#                  position: curl or wget naming github.com, raw.githubusercontent.com or api.github.com; git fetch|
#                  clone|pull|ls-remote naming a host; gh api|pr|issue|repo naming a host or 0xHoneyJar/loa; python -c
#                  code using urllib or requests and naming a host; a curl/wget in $( … ) or backticks naming a host; a
#                  heredoc body only when fed to an interpreter (python: urllib/requests and a host; bash/sh: its
#                  commands by the same rule). A WebFetch url or WebSearch query naming a host or the repository →
#                  contaminated {pattern: "network_egress"}, plus (round 10 telemetry, not a rule change) repo_named
#                  (REPO_TOKEN in the flagged command, segment, body or input), host (its first GitHub host) and url
#                  (its first URL, ≤ 200 characters): a third-party tool download from a GitHub host reads repo_named
#                  false. grep/rg/echo naming a host, prose in a cat heredoc, and
#                  words on separate commands never combine into a hit. A lower bound: an egress the transcript cannot
#                  show (a program the agent wrote, a remote fetched by name) is not seen.
#   Union (--union <cell-dir> --task-id T; SDD D-3.1): a matched cell is k independent BARE sessions under
#                  <cell>/sessions/s<i>/ (first attempt; re-runs in s<i>-r<n>), each already graded on its own. The
#                  union reads <cell>/meta/cell.json (the runner's record, run-ablation.sh finalize_cell: {schema_version,
#                  task_id, trial, k, sessions: [{id, status, valid, invalid_reason, attempts, attempt_statuses,
#                  attempt_costs, cost_usd, run_dir}], sessions_valid, sessions_attempted, started, finished}; no arm id
#                  and no run_id — the one meta/ file this grader reads, so it stays blind to the arm; the grader uses k,
#                  sessions[].id/valid/status/cost_usd/run_dir, and ablation-row.sh the attempt fields) and, for
#                  the sessions it marks valid only, their grading/gates-combined.md and grade.json; it writes
#                  <cell>/grading/gates-combined.md (each valid session's citations under a `## session s<i>` line) and
#                  grades it with the same reduction: each defect credited at most once, strays deduplicated by cited
#                  region across sessions. grade.json: union true, bare_sessions k, sessions_valid, sessions_graded,
#                  recall / false_positives / false_positive_rule / multi_credit_citations of the union, per_session[]
#                  {session, status, valid, cost_usd, recall, recall_pm3, detected, detected_pm3 (positions),
#                  false_positives, verdict, grader_version} (figures null for an invalid session), recall_session1 /
#                  recall_pm3_session1 (session 1 alone; null when it is invalid), precision_session1 = its pm3 caught
#                  ÷ (caught + false_positives) (null when invalid or 0 ÷ 0), oracle_exposed_defects / _unknown the
#                  union of the valid sessions', label_set / labels_meta copied from the first valid session's grade,
#                  verdict, verdicts and verdict_accuracy null (k verdicts: per_session carries them), contaminated null.
#                  Exit 2: no readable cell.json, k or the ids not s1 … sk, the session directories not exactly s1 …
#                  sk, a valid session without grade.json (with recall) or grading/gates-combined.md, a valid session
#                  whose grade is contaminated, a valid session whose grade.json grader_version is not this grader's
#                  (1.3.5: one grader across the union). With no valid session the union recall is null.
# grader 1.3.1 (cycle-131 PR #1286 Bridgebuilder F002): the oracle detector scans error-marked tool results. A
# diff exits 1 on differences and Claude Code then marks the result is_error with the output after an "Exit code N"
# line, so 1.3.0 never saw a differing diff's hunks. 1.3.1 strips that line and scans the rest: the diff form
# needs printed ranges near a site (must_match alone does not count there), the read form later-only text; an
# error-marked section without ranges is never exposed_unknown (a refusal or a hook block names the command's
# paths and prints no diff). Recall, contamination and every other field are unchanged from 1.3.0.
# grader 1.3.0 (cycle-131 Sprint 263 Tasks 1.3, 1.4; DEC-0615, DEC-0616, DEC-0617): three recall results
# (the same-scope rule, recall-vs-defects.sh 1.3.0), numeric dissent anchors, corpus_sha256, the oracle
# detector (diff and read forms, KF-049) and the KF-046 class 7 line-level exemption. recall_pm3_v1 equals
# a 1.2.x grade's recall on the same run; recall may differ (more credits by scope, fewer through the
# citation validity rules); contaminated may differ only by class 7 exemptions.
# grader 1.2.1 (Sprint 260 calibration, DEC-0540): git history probes are telemetry; a
# one-component absolute word is a command token unless it names root, home, mnt, media or srv.
# grader 1.2.13 (Sprint 261 dissent run 2 DISS-001, DISS-C-004, DISS-C-005): the removal compares pytest import
# names, not basenames. Under the default prepend import mode a test module imports by its dotted path from its basedir
# (the first ancestor without __init__.py), so tests/hidden/pkg/test_x.py and an agent tests/pkg/test_x.py are both
# pkg.test_x when each pkg/ is a package: 1.2.12 kept such a file and collection still aborted. Protected modules (the
# hidden overlay file dests, files inside directory overlays, the fixture's tests/ or test/ files) are named from the
# overlay-or-fixture view of __init__.py files; an agent-added (unowned) collectable module is named from the grading
# tree's real __init__.py files and removed when its name is a protected collectable module's. A narrow helper rule
# removes an unowned non-collectable module whose stem is a protected helper's (a package-less protected .py beside a
# protected collectable module or conftest.py, or at the root: what import _oracle_x reaches) only when its directory
# is package-less and also holds a collectable module (the one case pytest puts it on sys.path and the agent's copy
# can answer the protected import), and removes the unowned test modules in that directory with it (the helper alone
# would leave their import _oracle_x an ImportError that aborts collection). Collectable means pytest's python_files: -o python_files=… or a
# -c file visible in test_command, else the fixture root's pytest.ini, .pytest.ini, pyproject.toml
# ([tool.pytest.ini_options]), tox.ini ([pytest]) or setup.cfg ([tool:pytest]), else test_*.py and *_test.py;
# grade.json collision_rule {python_files, source} records the patterns used (null for review-catch).
# grader 1.2.12 (Sprint 261 dissent DISS-001/DISS-C-001/DISS-002/DISS-C-002; superseded by 1.2.13): the 1.2.11 removal is narrowed to
# what pytest's import file mismatch actually hits. Reserved basenames are only pytest-collectable ones (test_*.py,
# *_test.py; never __init__.py, conftest.py or helper modules), taken from the hidden overlay files, the .py files
# inside directory overlays (unprotected under 1.2.11) and the fixture's tests/ or test/ files. A grading-tree file is
# removed only when its basename is reserved, it is at no owned overlay path and no fixture path, and its directory
# has no __init__.py (pytest's default prepend mode imports only package-less test modules by bare basename). Under
# 1.2.11 an agent's src/app/helpers.py beside a fixture tests/helpers.py was deleted and a correct solution failed.
# grader 1.2.11 (Sprint 261, narrowed by 1.2.12): 1.2.10's --import-mode=importlib is reverted (it broke the sibling-module imports hidden
# suites and fixture suites rely on: import _oracle_x, from helpers import …); instead a Python file the agent added
# (no fixture file and no hidden overlay at its path) whose basename equals a hidden overlay's or a fixture test file's
# basename is removed before any command runs (counted in grade.json colliding_tests_removed, paths beside the tree in
# grading/<label>.colliding-removed.txt): under pytest's default import mode two test modules with one basename in
# package-less directories abort collection (import file mismatch) and would grade a correct solution as failing.
# grader 1.2.10 (Sprint 261, superseded by 1.2.11): pytest ran with --import-mode=importlib.
# grader 1.2.9 (Sprint 260 audit round 2): the glob rule reads * and ? only — a [ after a one-component word
# is a regex bracket expression (two P1 commands read as contaminated under 1.2.8: grep '/home[^"]*…',
# sed 's/job\["status"\]…'; KF-046 recurrence 7) — and a quoted one-component pattern stays exempt.
# grader 1.2.8 (Sprint 260 audit round 1, DISS-C-001, C-002): the dot-directory skip applies after
# os.path.normpath (/./root/x is /root/x); an empty quoted string before a path is not a glued token
# (''/root/x); a one-component word followed by a glob metacharacter stays a candidate (/roo*, /ro?t);
# a bare hidden that is the direct argument of cd, ls, cat, stat, tree, head, tail, less, more, du, file
# or of find -name/-path/-wholename is a hit (filesystem probe), while -k hidden, grep hidden and prose stay
# exempt. A 1.2.7 grade may differ in contaminated on those shapes (more hits).
# grader 1.2.7 (Sprint 260 review round 2, DISS-C-001, C-002, C-006): the glob shapes of the hidden token
# (* and ? beside the word) are read on the heredoc-stripped command only, so "Is any state hidden?" and
# "**hidden**" in written prose are clean; the camelCase branch accepts PascalCase (HiddenTests/); SIGTERM
# runs the finally (SCRATCH removed). A 1.2.6 grade may differ in contaminated on those prose shapes.
# grader 1.2.6 (Sprint 260 review round 1, DISS-C-001 … C-005): the heredoc operator line's
# remainder after <<WORD is scanned and the heredoc regex is linear (one line per body
# iteration, no re.S); a sensitive word that is the whole quoted argument is a candidate (a
# quote state machine); hidden adjacency is case-insensitive with camelCase and glob shapes;
# heredoc_interpreters counted. Contamination exemptions only: a 1.2.5 grade may differ in
# contaminated (mostly more hits; a word parity counting flagged inside quoted text is skipped).
# grader 1.2.5 (DEC-0557, P1 resume): a Bash path word right after a closing quote glued to the
# preceding token ("$D"/evals/x, pr/'"$v"'/.claude/y) is a path tail, not an absolute path.
# grader 1.2.4 (DEC-0551, priority batch P1): a Bash word beginning with /, (a sed-range remnant
# after a first address holding a space) or carrying = (regex / key=value token) is not a path.
# grader 1.2.3 (DEC-0546, priority batch P1): a Bash word shaped /re1/,/re2/… (a sed address
# range) is a regex pair, not a path candidate (seen: sed -n '/======TEMPLATE/,/======STAT/p').
# grader 1.2.2 (DEC-0541): heredoc bodies are stripped before the path-word scan (written file
# text is data; the hidden/suite/repo scans still read it); ~/, $HOME/ and ${HOME}/ are outside
# in host mode only (the container home /home/evaluser is an allowed root); a one-component
# word with a trailing slash (/,/ /x/ sed and awk delimiters) follows the same single-component rule.
# grader 1.1.0 (Sprint 259 fix round): refactor hidden_tests = the structural check,
# exit-status-aware green, symlink filtering; 1.0.0 grades of refactor tasks differ.
# Round 2: snapshot trees get the same realpath symlink pass as the final copy (counted in
# symlinks_dropped); regressions carries base_green and final_green (all_pass of each run);
# the self-check's suite-green rule requires a parsed summary too.
# grader 1.2.0 (Sprint 259 audit fix round 1): harness files removed before every run and
# pytest -o addopts= (HIGH-A1); a named, limited, init-wrapped container with a kill
# deadline, docker kill/rm -f on a hung client and a 4 MiB output cap (MEDIUM-A1);
# node paths read from grader-owned copies or bounded in-tree regular files (MEDIUM-A2);
# a 16 MiB copy cap and bounded, symlink-refusing readers (MEDIUM-A3); host mode opt-in
# (LOW-A1); no credential store exempt and ~/, $HOME/, /proc/*/environ, /var/run flagged
# (LOW-A2). New fields: harness_files_removed, oversized_files_skipped, output_truncated.
# A grade that removed a harness file, skipped a file or ran a cheat differs from 1.1.0's.
# No timestamp and no scratch path is written: the same run grades byte-identically.
#
# Self-check (DEC-0401; AC-2.3): a synthetic run under mktemp -d built from the task.
#   base       build: the fixture is the final tree → PASS when at least one hidden test
#              fails (refactor: the structural check) and the regression check's final
#              run (regressions.final) is green — every case, exit 0, no timeout;
#              review-catch: an empty findings file → recall 0.0
#   reference  build: the fixture with hidden/reference.patch (patch -p1) → every hidden
#              test passes with exit 0 (refactor: structural green), suite green;
#              review-catch: a findings file citing every key anchor → recall 1.0
#   noisy      review-catch: every line of every pr/head/ file cited → false_positives
#              greater than the reference findings file's
# Prints `self-check <mode> <task-id>: PASS|FAIL <evidence>`.
#
# Exit codes: 0 graded / self-check PASS; 1 self-check FAIL; 2 error (usage, missing run
# dir, task not found, unfrozen suite without --allow-unfrozen, docker or the image
# missing in container mode, a tool failure).
#
# Tested by evals/tests/ablation-grade.bats (docker = evals/tests/fixtures/docker-stub.sh).
# No .claude/ code is sourced and nothing is sourced or eval'd from a variable (eval.yml
# trust boundary); hashing is Python hashlib.
# =============================================================================
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
case "${1:-}" in -h|--help) sed -n '3,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac

exec python3 -I - "$SCRIPT_DIR" "$REPO_ROOT" "${EVAL_DOCKER_BIN:-docker}" "$@" <<'PY'
import argparse, configparser, difflib, filecmp, fnmatch, json, os, re, shlex, shutil, signal, site, stat, subprocess, sys, tarfile, tempfile, threading, time, tomllib
# 1.2.7 (Sprint 260 review round 2, DISS-C-002): a SIGTERM (the runner's post-run deadline) becomes SystemExit so
# the finally below removes SCRATCH; a running docker command ends at its own in-container deadline (--init forwards
# TERM; names carry this pid, so a later grade never collides)
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(143))

GRADER_VERSION = "1.5.0"
HIDDEN_CLASS = [True]   # whether the build-only classes (hidden 1.3.6, suite_path 1.3.7) apply to the task being graded
BUILD_ONLY_CLASSES = ["hidden", "suite_path"]
SCRIPT_DIR, REPO_ROOT, DOCKER_DEFAULT = sys.argv[1], sys.argv[2], sys.argv[3]
SPRINT = "sprint-1"
_t = os.environ.get("LOA_EVAL_GRADE_TIMEOUT_S", "")
TEST_TIMEOUT_S = int(_t) if re.fullmatch(r"[1-9][0-9]{0,3}", _t) else 120   # tests shorten it
KILL_AFTER_S = 10                                    # timeout --kill-after (MEDIUM-A1)
OUTER_GRACE_S = max(5, min(60, TEST_TIMEOUT_S // 2))  # the client deadline beyond T + KILL_AFTER_S
OUTPUT_CAP = 4 * 1024 * 1024      # captured stdout per command (MEDIUM-A1)
FILE_CAP = 16 * 1024 * 1024       # a regular file above this is not copied (MEDIUM-A3)
READ_CAP = 2 * 1024 * 1024        # verdict, citation and envelope reads (MEDIUM-A3)
NODE_FILE_CAP = 1024 * 1024       # a test file read for case order (MEDIUM-A2)
# pytest and bats load these from the tree under test (HIGH-A1); see is_harness()
HARNESS_NAMES = {"conftest.py", "pytest.ini", ".pytest.ini", "pyproject.toml", "setup.cfg", "tox.ini",
                 "setup_suite.bash"}
EXCLUDE_TOP = {".git", ".claude", "CLAUDE.md", ".loa.config.yaml", "grimoires", ".run", ".beads", ".eval", "pr"}
EXCLUDE_ANY = {"__pycache__", ".pytest_cache"}
PHASE_ORDER = ["PLAN", "BARE", "IMPLEMENT", "REVIEW", "FIX1", "AUDIT", "FIX2"]


class GradeError(Exception):
    pass


def die(msg):
    print(f"ablation-grade: {msg}", file=sys.stderr)
    sys.exit(2)


ap = argparse.ArgumentParser(prog="ablation-grade.sh", add_help=False)
ap.add_argument("run_dir", nargs="?")
ap.add_argument("task_id", nargs="?")
ap.add_argument("--suite-root")
ap.add_argument("--tasks-dir", choices=["tasks", "smoke"])
ap.add_argument("--out")
ap.add_argument("--json", action="store_true")
ap.add_argument("--executor", choices=["container", "host"], default="container")
ap.add_argument("--image", default="loa-ablation:259")
ap.add_argument("--docker-bin", default=DOCKER_DEFAULT)
ap.add_argument("--allow-unfrozen", action="store_true")
ap.add_argument("--allow-partial", action="store_true")
ap.add_argument("--self-check", choices=["base", "reference", "noisy"])
ap.add_argument("--task-yaml")
ap.add_argument("--union")      # 1.3.2 (cycle-132 FR-3): a matched cell directory, graded as the union of its sessions
ap.add_argument("--task-id", dest="union_task_id")    # the task of --union
ap.add_argument("--judge-verdicts")   # 1.5.0 (cycle-133 C-11): the judge's verdicts JSONL, bound to this grade's credited pairs
ap.add_argument("--run-id")           # 1.5.0: the run id the verdict rows name (default: the run or cell directory's name)
try:
    A = ap.parse_args(sys.argv[4:])
except SystemExit:
    sys.exit(2)


# ------------------------------------------------------------------ small helpers
def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def load_yaml(path):
    p = run(["yq", "-o=json", ".", path])
    if p.returncode != 0:
        raise GradeError(f"task yaml does not parse: {path}")
    try:
        return json.loads(p.stdout)
    except ValueError:
        raise GradeError(f"task yaml does not parse: {path}")


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def is_within(path, root):
    path, root = os.path.realpath(path), os.path.realpath(root)
    return path == root or path.startswith(root + os.sep)


def remove_path(p):
    """delete p; a directory is made writable first, but never through a symlink: a tree
    the agent shaped may hold `x -> /somewhere`, and os.chmod follows links (DISS-001)"""
    if os.path.islink(p) or os.path.isfile(p):
        os.unlink(p)
    elif os.path.isdir(p):
        for r, ds, _fs in os.walk(p, followlinks=False):
            for d in ds:
                q = os.path.join(r, d)
                try:
                    if stat.S_ISDIR(os.lstat(q).st_mode):
                        os.chmod(q, 0o700)
                except OSError:
                    pass
        shutil.rmtree(p)
    elif os.path.lexists(p):
        os.unlink(p)


def safe_rel(rel):
    if not isinstance(rel, str) or not rel or rel.startswith("/") or "\\" in rel:
        return None
    parts = [x for x in rel.split("/") if x not in ("", ".")]
    if not parts or ".." in parts:
        return None
    return parts


def read_regular(path, cap, whole=False, root=None):
    """the text of a regular file, opened without following a final symlink and without
    blocking on a FIFO (O_NOFOLLOW | O_NONBLOCK, then fstat S_ISREG). At most cap bytes are
    read; whole=True refuses (None) a file larger than cap. root: the path must also
    resolve inside root (a symlinked parent directory is refused). → str | None"""
    if root is not None and not is_within(path, root):
        return None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0))
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or (whole and st.st_size > cap):
            return None
        chunks, left = [], cap
        while left > 0:
            b = os.read(fd, min(left, 1 << 20))
            if not b:
                break
            chunks.append(b)
            left -= len(b)
        return b"".join(chunks).decode("utf-8", "replace")
    except OSError:
        return None
    finally:
        os.close(fd)


OVERSIZED = [0]   # regular files above FILE_CAP skipped by copy_tree / snapshot extraction in this grade


def ensure_parent(tree, parts):
    """make every parent component of tree/parts a real directory inside tree"""
    cur = tree
    for comp in parts[:-1]:
        cur = os.path.join(cur, comp)
        if os.path.islink(cur) or (os.path.lexists(cur) and not os.path.isdir(cur)):
            os.unlink(cur)
        if not os.path.isdir(cur):
            os.mkdir(cur)
    return os.path.join(cur, parts[-1])


def link_escapes(target, rel_dir):
    """a symlink at <tree>/<rel_dir>/<name> pointing at target: absolute, or resolving
    (lexically) above the tree root"""
    if not target or os.path.isabs(target):
        return True
    n = os.path.normpath(os.path.join(rel_dir, target))
    return n == ".." or n.startswith("../") or os.path.isabs(n)


def drop_escaping_links(tree):
    """second pass over the copy: any symlink whose full resolution (through the other
    links) leaves the tree is removed; repeated until stable → number removed"""
    n, root = 0, os.path.realpath(tree)
    while True:
        gone = 0
        for r, ds, fs in os.walk(tree, followlinks=False):
            for name in ds + fs:
                q = os.path.join(r, name)
                if os.path.islink(q) and not is_within(q, root):
                    os.unlink(q)
                    gone += 1
        if not gone:
            return n
        n += gone


def copy_tree(src, dst, top_exclude=frozenset()):
    """regular files, directories and in-tree relative symlinks only; caches dropped. A
    symlink whose target is absolute or resolves outside dst is not recreated (DISS-001).
    → the number of symlinks dropped"""
    os.makedirs(dst, exist_ok=True)
    dropped = 0
    for root, dirs, files in os.walk(src, followlinks=False):
        rel = os.path.relpath(root, src)
        keep = []
        for d in sorted(dirs):
            if (rel == "." and d in top_exclude) or d in EXCLUDE_ANY:
                continue
            sp = os.path.join(root, d)
            dp = os.path.join(dst, rel, d)
            if os.path.islink(sp):
                target = os.readlink(sp)
                if link_escapes(target, rel):
                    dropped += 1
                else:
                    os.symlink(target, dp)
                continue
            os.makedirs(dp, exist_ok=True)
            keep.append(d)
        dirs[:] = keep
        for f in sorted(files):
            if rel == "." and f in top_exclude:
                continue
            sp, dp = os.path.join(root, f), os.path.join(dst, rel, f)
            st = os.lstat(sp)
            if stat.S_ISLNK(st.st_mode):
                target = os.readlink(sp)
                if link_escapes(target, rel):
                    dropped += 1
                else:
                    os.symlink(target, dp)
            elif stat.S_ISREG(st.st_mode):
                if st.st_size > FILE_CAP:   # MEDIUM-A3: a sparse 1 TB file must not become a dense write
                    OVERSIZED[0] += 1
                    continue
                shutil.copyfile(sp, dp)
                os.chmod(dp, (st.st_mode & 0o777) | 0o600)
    return dropped + drop_escaping_links(dst)


def put_file(tree, rel, src):
    parts = safe_rel(rel)
    if parts is None:
        raise GradeError(f"unsafe path: {rel!r}")
    dst = ensure_parent(tree, parts)
    if os.path.lexists(dst):
        remove_path(dst)
    if os.path.isdir(src) and not os.path.islink(src):
        copy_tree(src, dst)
    else:
        shutil.copyfile(src, dst)
        os.chmod(dst, (os.stat(src).st_mode & 0o777) | 0o600)


# ------------------------------------------------------------------ task loading
class Task:
    pass


def load_task(task_yaml, suite_root):
    t = Task()
    t.yaml = os.path.abspath(task_yaml)
    t.dir = os.path.dirname(t.yaml)
    t.suite_root = os.path.abspath(suite_root)
    t.spec = load_yaml(t.yaml)
    if not isinstance(t.spec, dict):
        raise GradeError(f"task yaml is not a mapping: {task_yaml}")
    t.id = t.spec.get("id") or ""
    t.type = t.spec.get("type") or ""
    if t.type not in ("bug-fix", "feature-build", "refactor", "review-catch"):
        raise GradeError(f"unknown task type: {t.type!r}")
    t.build = t.type != "review-catch"
    t.fixture = None
    if t.build:
        rel = t.spec.get("fixture")
        if not isinstance(rel, str) or not rel:
            raise GradeError("build task has no fixture")
        for cand in (os.path.join(t.suite_root, rel), os.path.join(t.dir, rel)):
            if os.path.isdir(cand):
                t.fixture = os.path.realpath(cand)
                break
        if t.fixture is None:
            raise GradeError(f"fixture not found: {rel}")
        if not is_within(t.fixture, t.dir):
            raise GradeError(f"fixture must be inside the task directory: {rel}")
    t.hidden = os.path.join(t.dir, "hidden")
    man = read_json(os.path.join(t.hidden, "manifest.json")) if t.build else None
    t.overlay = []
    if t.build:
        if not isinstance(man, dict) or not isinstance(man.get("files"), list):
            raise GradeError("hidden/manifest.json missing or malformed")
        for e in man["files"]:
            src, dest = (e or {}).get("src"), (e or {}).get("dest")
            sp = safe_rel(src)
            if sp is None or safe_rel(dest) is None:
                raise GradeError(f"hidden/manifest.json: unsafe entry {e!r}")
            full = os.path.join(t.hidden, *sp)
            if not os.path.exists(full):
                raise GradeError(f"hidden/manifest.json: src not found: {src}")
            t.overlay.append(("/".join(sp), "/".join(safe_rel(dest)), full))
    t.protected = []
    for p in t.spec.get("grader_protected") or []:
        parts = safe_rel(p)
        if parts is None:
            raise GradeError(f"grader_protected: unsafe path {p!r}")
        t.protected.append("/".join(parts))
    t.test_command = t.spec.get("test_command")
    t.regression_command = t.spec.get("regression_command")
    for k in ("test_command", "regression_command"):
        v = getattr(t, k)
        if v is not None and (not isinstance(v, list) or not v or not all(isinstance(x, str) for x in v)):
            raise GradeError(f"{k} must be a non-empty array of strings or null")
    if t.build and not t.test_command:
        raise GradeError("build task has no test_command")
    t.structural = None
    sc = t.spec.get("structural_check")
    if sc:
        sp = safe_rel(sc)
        if sp is None or sp[0] != "hidden":
            raise GradeError(f"structural_check must be under hidden/: {sc}")
        src = "/".join(sp[1:])
        dest = next((d for s, d, _f in t.overlay if s == src), None)
        if dest is None:
            raise GradeError(f"structural_check {sc} is not overlaid by hidden/manifest.json")
        t.structural = dest
    if t.type == "refactor" and not t.structural:
        raise GradeError("refactor task has no structural_check")
    t.structural_full = next((f for _s, d, f in t.overlay if d == t.structural), None) if t.structural else None
    t.reference_patch = None
    rp = t.spec.get("reference_patch")
    if rp:
        parts = safe_rel(rp)
        if parts is None:
            raise GradeError(f"reference_patch: unsafe path {rp!r}")
        t.reference_patch = os.path.join(t.dir, *parts)
    # the hidden test files' static case count (structural check excluded)
    t.static_cases = 0
    for s, d, full in t.overlay:
        if d == t.structural or not os.path.isfile(full):
            continue
        t.static_cases += count_cases(full)
    t.structural_cases = count_cases(t.structural_full) if t.structural_full else 0
    t.rc = None
    if t.type == "review-catch":
        rc = t.spec.get("review_catch")
        if not isinstance(rc, dict) or not rc.get("manifest"):
            raise GradeError("review-catch task has no review_catch.manifest")
        t.rc = rc
        mp = None
        for cand in (os.path.join(REPO_ROOT, rc["manifest"]), os.path.join(t.suite_root, rc["manifest"]),
                     os.path.join(t.dir, rc["manifest"])):
            if os.path.isfile(cand):
                mp = os.path.abspath(cand)
                break
        if mp is None:
            raise GradeError(f"review-catch manifest not found: {rc['manifest']}")
        t.key_path = mp
        t.key = read_json(mp)
        if not isinstance(t.key, dict) or not isinstance(t.key.get("defects"), list):
            raise GradeError(f"review-catch manifest malformed: {rc['manifest']}")
        t.key_id = os.path.basename(mp)[:-5] if mp.endswith(".json") else os.path.basename(mp)
    return t


def count_cases(path):
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return 0
    if path.endswith(".bats"):
        return len(re.findall(r"(?m)^\s*@test\s", text))
    if path.endswith(".py"):
        return len(re.findall(r"(?m)^\s*(?:async\s+)?def\s+test\w*\s*\(", text))
    return 0


def resolve_pr_fixture(t):
    rel = (t.rc or {}).get("fixture") or ""
    for cand in (os.path.join(t.dir, rel), os.path.join(t.suite_root, rel), os.path.join(REPO_ROOT, rel),
                 os.path.join(REPO_ROOT, "evals", "fixtures", rel)):
        if rel and os.path.isdir(cand):
            return os.path.abspath(cand)
    raise GradeError(f"review-catch fixture not found: {rel}")


# ------------------------------------------------------------------ freeze
def freeze_check(suite_root):
    manifest = os.path.join(suite_root, "MANIFEST.sha256")
    if not os.path.isfile(manifest):
        if A.allow_unfrozen:
            print("ablation-grade: WARNING suite has no MANIFEST.sha256; grading unfrozen (--allow-unfrozen)", file=sys.stderr)
            return False
        raise GradeError(f"suite is not frozen: no MANIFEST.sha256 in {suite_root} (--allow-unfrozen while authoring)")
    smoke = any(l.split("  ", 1)[-1].startswith("smoke/") for l in open(manifest, encoding="utf-8") if l.strip())
    cmd = ["bash", os.path.join(SCRIPT_DIR, "freeze.sh"), "--root", suite_root, "--check"]
    if smoke:
        cmd.append("--smoke")
    if A.allow_partial:
        cmd.append("--allow-partial")
    p = run(cmd)
    if p.returncode == 0:
        return True
    detail = (p.stdout + p.stderr).strip().splitlines()
    if A.allow_unfrozen:
        print("ablation-grade: WARNING freeze.sh --check failed; grading unfrozen (--allow-unfrozen)", file=sys.stderr)
        return False
    raise GradeError("freeze.sh --check failed (exit %d); refusing to grade: %s" % (p.returncode, " | ".join(detail[:6])))


# ------------------------------------------------------------------ command execution
SCRATCH = tempfile.mkdtemp(prefix="ablation-grade.")


def docker_ready():
    if A.executor != "container":
        return
    d = A.docker_bin
    if not (shutil.which(d) or (os.path.isfile(d) and os.access(d, os.X_OK))):
        raise GradeError(f"docker CLI not found: {d} (container mode)")
    p = run([d, "image", "inspect", "--format", "{{.Id}}", A.image])
    if p.returncode != 0:
        raise GradeError(f"image not found: {A.image}")


def shape_command(cmd, root):
    """the argv that runs inside the tree; root = /workspace (container) or the tree (host)"""
    host = A.executor == "host"
    rest = None
    if cmd[:3] == ["python3", "-m", "pytest"]:
        rest = cmd[3:]
    elif cmd[0] == "pytest":
        rest = cmd[1:]
    if rest is not None:
        rest = [x for x in rest if x not in ("-q", "--quiet")]
        pre = ["python3", "-P"] if host else ["python3", "-I", "-s"]
        # -o addopts= : an ini file's addopts cannot inject a plugin or deselect (HIGH-A1)
        return pre + ["-m", "pytest", "-p", "no:cacheprovider", "-o", "addopts=", "-q", "--rootdir", root,
                      "-rA"] + rest, "pytest"
    if cmd[0] == "bats":
        rest = cmd[1:]
        if "--tap" in rest or any(x.startswith("--formatter") or x == "-F" for x in rest):
            return list(cmd), "tap"
        return ["bats", "--tap"] + rest, "tap"
    return list(cmd), "auto"


RUN_TAG = ["run"]   # the run directory's basename, sanitised: part of every container name
EXEC_SEQ = [0]


def container_name(tree):
    """ablgrade-<run>-<label>-<pid>-<n>: letters, digits, '.', '_', '-' only"""
    EXEC_SEQ[0] += 1
    raw = f"ablgrade-{RUN_TAG[0]}-{os.path.basename(tree.rstrip('/'))}-{os.getpid()}-{EXEC_SEQ[0]}"
    return re.sub(r"[^A-Za-z0-9._-]", "-", raw)[:128]


def drain(fd, cap, box):
    """read fd to EOF in chunks, keeping the first and the last cap/2 bytes (the summary
    and the -rA outcome lines are at the end) → box = [(bytes, truncated)]"""
    head, tail, half, trunc = bytearray(), bytearray(), cap // 2, False
    while True:
        try:
            b = os.read(fd, 1 << 16)
        except OSError:
            break
        if not b:
            break
        if len(head) < half:
            k = half - len(head)
            head += b[:k]
            b = b[k:]
        if b:
            tail += b
            if len(tail) > half:
                del tail[:len(tail) - half]
                trunc = True
    box.append((bytes(head) + (b"\n[output truncated]\n" if trunc else b"") + bytes(tail), trunc))


def docker_cleanup(name):
    for extra in (["kill", name], ["rm", "-f", name]):
        try:
            subprocess.run([A.docker_bin] + extra, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           stdin=subprocess.DEVNULL, timeout=60)
        except (OSError, subprocess.SubprocessError):
            pass


def exec_in_tree(tree, cmd):
    """→ (rc, output, timed_out, kind, output_truncated)"""
    deadline = ["timeout", "--signal=TERM", f"--kill-after={KILL_AFTER_S}", str(TEST_TIMEOUT_S)]
    name = None
    if A.executor == "container":
        argv, kind = shape_command(cmd, "/workspace")
        name = container_name(tree)
        full = [A.docker_bin, "run", "--rm", "--init", "--name", name, "--network", "none", "--read-only",
                "--tmpfs", "/tmp:rw,size=256m", "--pids-limit", "256", "--memory", "2g", "--cpus", "2",
                "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
                "--user", f"{os.getuid()}:{os.getgid()}", "-v", f"{tree}:/workspace:rw", "-w", "/workspace",
                "-e", "HOME=/tmp", "-e", "LC_ALL=C", "-e", "TMPDIR=/tmp", A.image] + deadline + argv
        cwd = None
    else:
        argv, kind = shape_command(cmd, tree)
        home = tempfile.mkdtemp(prefix="home.", dir=SCRATCH)
        full = ["env", "-i", "PATH=" + os.environ.get("PATH", "/usr/bin:/bin"), "HOME=" + home, "LC_ALL=C",
                "TMPDIR=" + home, "PYTHONUSERBASE=" + site.getuserbase()] + deadline + argv
        cwd = tree
    try:
        proc = subprocess.Popen(full, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, start_new_session=True)
    except OSError as e:
        raise GradeError(f"cannot run {full[0]}: {e}")
    box = []
    reader = threading.Thread(target=drain, args=(proc.stdout.fileno(), OUTPUT_CAP, box), daemon=True)
    reader.start()
    started, exited, timed_out, rc = time.monotonic(), False, False, 124
    try:
        try:
            rc = proc.wait(timeout=TEST_TIMEOUT_S + KILL_AFTER_S + OUTER_GRACE_S)
            exited = True
        except subprocess.TimeoutExpired:
            timed_out = True
    finally:
        if not exited:   # the client is killed; the container (which --rm does not stop) is killed and removed
            try:
                os.killpg(proc.pid, 9)
            except OSError:
                pass
            try:
                proc.wait(timeout=30)
            except subprocess.TimeoutExpired:
                pass
            if name:
                docker_cleanup(name)
        reader.join(timeout=30)
        if not reader.is_alive():
            proc.stdout.close()
    out, trunc = box[0] if box else (b"", False)
    # timeout(1): 124 after TERM; 128+9 when the command outlived --kill-after
    timed_out = timed_out or rc == 124 or (rc == 137 and time.monotonic() - started >= TEST_TIMEOUT_S)
    return rc, out.decode("utf-8", "replace"), timed_out, kind, trunc


# ------------------------------------------------------------------ result parsing
SUMMARY_RX = re.compile(r"^=*\s*((?:\d+ [a-z]+(?:, )?)+) in [0-9.]+s(?: \([^)]*\))?\s*=*\s*$")
COUNT_RX = re.compile(r"(\d+) ([a-z]+)")
OUTCOME_RX = re.compile(r"^(PASSED|FAILED|ERROR|XFAIL|XPASS) (\S+)")


GRADER_SOURCES = {}   # rel path in a grading tree → the grader-owned copy (hidden overlay, protected fixture file)


def node_text(tree, path):
    """the text of a test file a pytest node id names (MEDIUM-A2). The node path comes from the
    captured stdout, which the agent's code can print: a grader-owned source is read first;
    else the path must be relative, stay inside the tree and be a regular file of at most
    NODE_FILE_CAP bytes (never a FIFO, a device or a symlink) → str | None"""
    parts = safe_rel(path)
    if parts is None:
        return None
    own = GRADER_SOURCES.get("/".join(parts))
    if own is not None:
        return read_regular(own, NODE_FILE_CAP, whole=True)
    return read_regular(os.path.join(tree, *parts), NODE_FILE_CAP, whole=True, root=tree)


def def_line(tree, path, func, cache):
    if path not in cache:
        cache[path] = (node_text(tree, path) or "").splitlines()
    rx = re.compile(r"^\s*(?:async\s+)?def\s+" + re.escape(func) + r"\s*\(")
    for i, l in enumerate(cache[path], 1):
        if rx.match(l):
            return i
    return 10 ** 9


def parse_pytest(out, tree):
    lines = out.splitlines()
    summary = None
    for l in reversed(lines):
        m = SUMMARY_RX.match(l.strip())
        if m:
            summary = {k: int(n) for n, k in COUNT_RX.findall(m.group(1))}
            break
    if summary is None:
        return None
    norm = {}
    for k, v in summary.items():
        k = {"error": "errors", "warning": "warnings"}.get(k, k)
        norm[k] = norm.get(k, 0) + v
    outcomes, coll_err = {}, []
    for l in lines:
        m = OUTCOME_RX.match(l)
        if not m:
            continue
        kind, node = m.group(1), m.group(2)
        if kind == "ERROR" and "::" not in node:
            coll_err.append(node)
            continue
        prev = outcomes.get(node)
        bad = kind in ("FAILED", "ERROR")
        outcomes[node] = "bad" if (bad or prev == "bad") else "ok"
    cache = {}
    expanded = 0
    for f in coll_err:
        text = node_text(tree, f)
        if text is None:
            continue
        for fn in re.findall(r"(?m)^\s*(?:async\s+)?def\s+(test\w*)\s*\(", text):
            outcomes.setdefault(f"{f}::{fn}", "bad")
            expanded += 1

    def key(node):
        path, _, rest = node.partition("::")
        func = rest.split("::")[-1].split("[")[0]
        return (path, def_line(tree, path, func, cache), node)
    order = sorted(outcomes, key=key)
    total = sum(norm.get(k, 0) for k in ("passed", "failed", "errors", "skipped", "xfailed", "xpassed"))
    total = total - len(coll_err) + expanded
    passed = norm.get("passed", 0)
    if total <= 0 and passed == 0:
        return None
    return {"passed": passed, "total": max(total, len(order)), "order": order,
            "bad": {n for n, v in outcomes.items() if v == "bad"}}


TAP_RX = re.compile(r"^(not )?ok (\d+)\b ?(?:- )?(.*)$")


def parse_tap(out):
    plan, seen = None, {}
    for l in out.splitlines():
        m = re.match(r"^1\.\.(\d+)", l)
        if m and plan is None:
            plan = int(m.group(1))
            continue
        m = TAP_RX.match(l)
        if m:
            n = int(m.group(2))
            desc = re.sub(r"\s+#\s*(?:skip|SKIP|todo|TODO).*$", "", m.group(3)).strip()
            seen[n] = (m.group(1) is None, desc or f"#{n}")
    if plan is None and not seen:
        return None
    total = plan if plan is not None else len(seen)
    if total == 0:
        return None
    nums = sorted(set(range(1, total + 1)) | set(seen))
    names = {n: (seen[n][1] if n in seen else f"#{n}") for n in nums}
    order = [names[n] for n in nums]
    bad = {names[n] for n in nums if n not in seen or not seen[n][0]}
    return {"passed": sum(1 for n in seen if seen[n][0]), "total": total, "order": order, "bad": bad}


def run_suite(tree, cmd, static=0):
    rc, out, timed_out, kind, trunc = exec_in_tree(tree, cmd)
    parsed = None
    if kind in ("pytest", "auto"):
        parsed = parse_pytest(out, tree)
    if parsed is None and kind in ("tap", "auto"):
        parsed = parse_tap(out)
    if parsed is None:
        total = max(static, 1)
        passed = total if rc == 0 else 0
        order = [f"#{i}" for i in range(1, total + 1)]
        return {"passed": passed, "total": total, "order": order, "bad": set(order) if rc != 0 else set(),
                "parse_error": True, "timed_out": timed_out, "rc": rc, "output_truncated": trunc}
    parsed["total"] = max(parsed["total"], static)
    parsed.update(parse_error=False, timed_out=timed_out, rc=rc, output_truncated=trunc)
    return parsed


def ids_of(res, keys):
    pos = {k: i for i, k in enumerate(res["order"], 1)}
    return sorted((f"t{pos[k]}" for k in keys if k in pos), key=lambda s: int(s[1:]))


def summary(res):
    return {"passed": res["passed"], "total": res["total"], "failed_names": ids_of(res, res["bad"]),
            "parse_error": res["parse_error"], "timed_out": res["timed_out"], "rc": res["rc"],
            "output_truncated": res["output_truncated"]}


def all_pass(res):
    """every case passed, the summary parsed, and the command exited 0 within its time
    (a passing TAP block followed by exit 1, or a timeout, is not green: DISS-002)"""
    if res is None:
        return False
    return (res["passed"] >= res["total"] and not res["bad"] and not res["parse_error"]
            and res["rc"] == 0 and not res["timed_out"])


def run_counts(res):
    return {"passed": res["passed"], "total": res["total"], "rc": res["rc"], "timed_out": res["timed_out"],
            "output_truncated": res["output_truncated"]}


def regressions(rb, rf):
    """base run rb vs final run rf of the regression command. Parsed on both sides:
    newly_failing = base-passing cases failing (or absent) at final. Either side
    unparseable (DISS-003): base unparsed → every fallback id when the base exited 0 and
    the final run failed (non-zero exit or timeout); base parsed, final unparsed → every
    base-passing case when the final run failed; else none. parse_error records it."""
    final_red = rf["rc"] != 0 or rf["timed_out"]
    base_ok = [k for k in rb["order"] if k not in rb["bad"]]
    pe = bool(rb["parse_error"] or rf["parse_error"])
    if not pe:
        newly = [k for k in base_ok if k in rf["bad"] or k not in rf["order"]]
    elif rb["parse_error"]:
        newly = list(rb["order"]) if (rb["rc"] == 0 and not rb["timed_out"] and final_red) else []
    else:
        newly = base_ok if final_red else []
    return {"newly_failing": ids_of(rb, newly), "base": run_counts(rb), "final": run_counts(rf), "parse_error": pe,
            "base_green": all_pass(rb), "final_green": all_pass(rf)}


# ------------------------------------------------------------------ grading trees
def prepare(t, tree):
    for rel in t.protected:
        src = os.path.join(t.fixture, *rel.split("/"))
        if os.path.lexists(src) and not os.path.islink(src):
            put_file(tree, rel, src)
        else:
            parts = rel.split("/")
            cur = tree
            ok = True
            for comp in parts[:-1]:
                cur = os.path.join(cur, comp)
                if os.path.islink(cur) or not os.path.isdir(cur):
                    ok = False
                    break
            if ok and os.path.lexists(os.path.join(tree, *parts)):
                remove_path(os.path.join(tree, *parts))
    for _s, dest, full in t.overlay:
        put_file(tree, dest, full)
    n = remove_harness(t, tree)
    COLLIDING[0] += remove_colliding(t, tree)
    return n


def is_harness(parts):
    """a file pytest or bats would load from the tree as configuration or helper code"""
    name = parts[-1]
    if name in HARNESS_NAMES:
        return True
    if "helper" in name and name.endswith((".bash", ".sh")):
        return True
    return name.endswith(".bash") and any(p in ("tests", "test") for p in parts[:-1])


def same_as_fixture(t, tree, rel):
    a, b = os.path.join(tree, *rel.split("/")), os.path.join(t.fixture, *rel.split("/"))
    try:
        sa, sb = os.lstat(a), os.lstat(b)
    except OSError:
        return False
    if not (stat.S_ISREG(sa.st_mode) and stat.S_ISREG(sb.st_mode)) or not is_within(b, t.fixture):
        return False
    return filecmp.cmp(a, b, shallow=False)


def remove_harness(t, tree):
    """HIGH-A1: before any command runs on a grading tree, every harness or config file
    (is_harness) that is not byte-identical to the fixture's copy at the same path is removed
    (a symlink always is; the hidden overlay's own dests are kept). The removed paths go to
    grading/<label>.harness-removed.txt beside the tree, never into grade.json → count"""
    owned = {d for _s, d, _f in t.overlay}
    owned_dirs = tuple(d + "/" for _s, d, f in t.overlay if os.path.isdir(f))   # put_file rewrote these whole
    found = []
    for r, ds, fs in os.walk(tree, followlinks=False):
        relr = os.path.relpath(r, tree)
        for name in sorted(ds + fs):
            rel = name if relr == "." else relr.replace(os.sep, "/") + "/" + name
            p = os.path.join(r, name)
            if rel in owned or rel.startswith(owned_dirs) or not is_harness(rel.split("/")):
                continue
            if os.path.isdir(p) and not os.path.islink(p):
                continue
            if same_as_fixture(t, tree, rel):
                continue
            found.append((rel, p))
    for _rel, p in found:
        os.unlink(p)
    with open(tree.rstrip("/") + ".harness-removed.txt", "w", encoding="utf-8") as f:
        f.write("".join(rel + "\n" for rel, _p in sorted(found)))
    return len(found)


COLLIDING = [0]   # agent-added modules removed for an import-name collision or a helper shadow in this grade (1.2.11; 1.2.12; 1.2.13)
PYTEST_DEFAULT_FILES = ["test_*.py", "*_test.py"]   # pytest's default python_files
PYTEST_INI_ORDER = (("pytest.ini", "pytest"), (".pytest.ini", "pytest"), ("pyproject.toml", None),
                    ("tox.ini", "pytest"), ("setup.cfg", "tool:pytest"))   # pytest's inifile precedence at one directory


def _ini_section(path, section):
    """configparser read of one ini file → (section found, python_files value or None); unreadable → (False, None)"""
    cp = configparser.ConfigParser(interpolation=None)
    try:
        with open(path, encoding="utf-8") as f:
            cp.read_file(f)
    except (OSError, UnicodeError, configparser.Error):
        return False, None
    if not cp.has_section(section):
        return False, None
    return True, cp.get(section, "python_files", fallback=None)


def _toml_section(path):
    """tomllib read of pyproject.toml → (tool.pytest.ini_options found, python_files value or None)"""
    try:
        with open(path, "rb") as f:
            doc = tomllib.load(f)
    except (OSError, ValueError):
        return False, None
    tool = doc.get("tool")
    pt = tool.get("pytest") if isinstance(tool, dict) else None
    opts = pt.get("ini_options") if isinstance(pt, dict) else None
    if not isinstance(opts, dict):
        return False, None
    return True, opts.get("python_files")


def _patterns(v):
    """an ini value is pytest's args type (shell-split); a TOML array is taken as is → list or None"""
    if isinstance(v, list):
        return [x for x in v if isinstance(x, str)]
    if isinstance(v, str):
        try:
            return shlex.split(v)
        except ValueError:
            return v.split()
    return None


def collision_rule(t):
    """1.2.13 (DISS-C-004): the python_files patterns pytest uses for this task → {python_files, source}. A -o/--override-ini
    python_files=… in test_command wins (source "test_command"); else -c/--config-file <fixture-relative file> in
    test_command is read alone; else the first of pytest.ini, .pytest.ini, pyproject.toml ([tool.pytest.ini_options]),
    tox.ini ([pytest]), setup.cfg ([tool:pytest]) at the fixture root that pytest would pick; the defaults when the picked
    file sets no python_files or no file is picked (source "default"). Cached on the task."""
    if getattr(t, "_collision_rule", None) is not None:
        return t._collision_rule
    cmd = list(t.test_command or [])
    override, cfg = None, None
    for i, a in enumerate(cmd):
        nxt = cmd[i + 1] if i + 1 < len(cmd) else None
        val = None
        if a in ("-o", "--override-ini"):
            val = nxt
        elif a.startswith("--override-ini="):
            val = a.split("=", 1)[1]
        elif a.startswith("-o") and not a.startswith("--"):
            val = a[2:]
        if isinstance(val, str) and val.startswith("python_files="):
            override = _patterns(val.split("=", 1)[1]) or []
        if a in ("-c", "--config-file") and nxt:
            cfg = nxt
        elif a.startswith("--config-file="):
            cfg = a.split("=", 1)[1]
    rule = {"python_files": list(PYTEST_DEFAULT_FILES), "source": "default"}
    fx = t.fixture or ""
    if override is not None:
        rule = {"python_files": override, "source": "test_command"}
    elif fx and os.path.isdir(fx):
        if cfg is not None:
            parts = safe_rel(cfg)
            name = parts[-1] if parts else ""
            cands = [("/".join(parts), None if name.endswith(".toml") else ("tool:pytest" if name == "setup.cfg" else "pytest"))] if parts else []
            explicit = True
        else:
            cands, explicit = list(PYTEST_INI_ORDER), False
        for rel, section in cands:
            p = os.path.join(fx, *rel.split("/"))
            if os.path.islink(p) or not os.path.isfile(p) or not is_within(p, fx):
                continue
            found, val = _toml_section(p) if section is None else _ini_section(p, section)
            if not (found or explicit or rel in ("pytest.ini", ".pytest.ini")):
                continue   # pyproject.toml, tox.ini and setup.cfg count only with their pytest section; pytest.ini always
            pats = _patterns(val)
            if pats is not None:
                rule = {"python_files": pats, "source": rel}
            break
    t._collision_rule = rule
    return rule


def collectable(rel, pats):
    """a .py file pytest collects as a test module under python_files pats (pytest's fnmatch_ex: a pattern without / is
    matched against the basename, one with / against the path); __init__.py and conftest.py never"""
    name = rel.rsplit("/", 1)[-1]
    if not name.endswith(".py") or name in ("__init__.py", "conftest.py"):
        return False
    for pat in pats:
        if "/" in pat:
            if fnmatch.fnmatchcase("/" + rel, pat if pat.startswith("/") else "*/" + pat):
                return True
        elif fnmatch.fnmatchcase(name, pat):
            return True
    return False


def import_name(rel, has_init):
    """pytest's prepend-mode module name of rel: walk up while the directory has an __init__.py (has_init(dir-rel));
    the dotted path from that basedir, without .py"""
    parts = rel.split("/")
    names, dirs = [parts[-1][:-3]], parts[:-1]
    while dirs and has_init("/".join(dirs)):
        names.insert(0, dirs[-1])
        dirs = dirs[:-1]
    return ".".join(names)


def remove_colliding(t, tree):
    """1.2.13 (DISS-001, DISS-C-005, DISS-C-004). Protected modules are the hidden overlay file dests, the files inside
    directory overlays (at their dests) and the fixture's files under a tests/ or test/ directory. Each protected .py
    gets its prepend-mode import name, with __init__.py presence read from the overlay-or-fixture view (an overlay file
    dest, a file inside a directory overlay, or a fixture file). A candidate is a .py in the grading tree that is not
    owned (no overlay file dest, not inside a directory overlay, no fixture file at that path).
    (1) collision: a candidate pytest collects (collision_rule's python_files) whose import name, from the tree's real
    __init__.py files, equals a protected collectable module's import name is removed (import file mismatch).
    (2) helper shadow: a protected helper is a non-collectable protected .py (never __init__.py or conftest.py) in a
    package-less directory of the view that pytest puts on sys.path (the tree root, or a directory holding a protected
    collectable module or conftest.py), so a protected module can import it by bare name. A non-collectable candidate
    (never __init__.py or conftest.py) whose stem is such a helper's, in a package-less directory that also holds a
    collectable module after (1), is removed together with the unowned collectable modules in that directory (pytest
    puts that directory on sys.path and, when an agent module there imports the helper first, the agent's copy answers
    the protected import; removing the helper alone would turn that import into a collection-aborting ImportError). Paths go to grading/<label>.colliding-removed.txt beside the tree → count"""
    pats = collision_rule(t)["python_files"]
    owned = {d for _s, d, f in t.overlay if not os.path.isdir(f)}
    owned_dirs = tuple(d + "/" for _s, d, f in t.overlay if os.path.isdir(f))
    fx = t.fixture or ""
    prot = set(owned)
    for _s, d, f in t.overlay:
        if os.path.isdir(f) and not os.path.islink(f):
            for r, _ds, fs in os.walk(f, followlinks=False):
                relr = os.path.relpath(r, f).replace(os.sep, "/")
                prot.update(d + "/" + (n if relr == "." else relr + "/" + n) for n in fs)
    view = set(prot)   # the overlay-or-fixture view (for __init__.py lookups)
    if fx and os.path.isdir(fx):
        for r, _ds, fs in os.walk(fx, followlinks=False):
            relr = os.path.relpath(r, fx).replace(os.sep, "/")
            rels = [n if relr == "." else relr + "/" + n for n in fs]
            view.update(rels)
            if any(p in ("tests", "test") for p in relr.split("/")):
                prot.update(rels)

    def view_init(dr):
        return (dr + "/__init__.py") in view

    def tree_init(dr):
        return os.path.isfile(os.path.join(tree, *dr.split("/"), "__init__.py"))

    prot_coll, prot_help, live_dirs = set(), set(), {""}
    for rel in prot:
        dr, _sep, name = rel.rpartition("/")
        if name == "conftest.py" or (name.endswith(".py") and name != "__init__.py" and collectable(rel, pats)):
            live_dirs.add(dr)   # pytest imports this module, so a package-less dr is on sys.path
        if not name.endswith(".py") or name in ("__init__.py", "conftest.py"):
            continue
        if collectable(rel, pats):
            prot_coll.add(import_name(rel, view_init))
    for rel in prot:
        dr, _sep, name = rel.rpartition("/")
        if name.endswith(".py") and name not in ("__init__.py", "conftest.py") and not collectable(rel, pats) \
                and dr in live_dirs and not (dr and view_init(dr)):
            prot_help.add(name[:-3])   # a helper a protected module imports by bare name (import _oracle_x)
    cands = []
    for r, _ds, fs in os.walk(tree, followlinks=False):
        relr = os.path.relpath(r, tree).replace(os.sep, "/")
        for name in sorted(fs):
            rel = name if relr == "." else relr + "/" + name
            if not name.endswith(".py") or rel in owned or rel.startswith(owned_dirs):
                continue
            if fx and os.path.lexists(os.path.join(fx, *rel.split("/"))):
                continue
            cands.append(rel)
    cand_set = set(cands)
    found = [rel for rel in cands if collectable(rel, pats) and import_name(rel, tree_init) in prot_coll]
    gone = set(found)
    for rel in cands:
        if rel in gone or collectable(rel, pats) or rel.rsplit("/", 1)[-1] in ("__init__.py", "conftest.py"):
            continue
        dr, _sep, name = rel.rpartition("/")
        if name[:-3] not in prot_help or (dr and tree_init(dr)):
            continue
        d_abs = os.path.join(tree, *dr.split("/")) if dr else tree
        try:
            sib = os.listdir(d_abs)
        except OSError:
            continue
        sib_rels = [n if not dr else dr + "/" + n for n in sorted(sib)]
        live = [x for x in sib_rels if x not in gone and os.path.isfile(os.path.join(tree, *x.split("/"))) and collectable(x, pats)]
        if live:
            # the helper and the unowned test modules beside it go together: a module that imports the helper and
            # stays would abort collection with an ImportError (pytest 9, checked by hand), worse than the shadow
            for x in [rel] + [x for x in live if x in cand_set]:
                if x not in gone:
                    gone.add(x)
                    found.append(x)
    for rel in found:
        os.unlink(os.path.join(tree, *rel.split("/")))
    with open(tree.rstrip("/") + ".colliding-removed.txt", "w", encoding="utf-8") as f:
        f.write("".join(rel + "\n" for rel in sorted(found)))
    return len(found)


def git_env(home):
    return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "LC_ALL": "C",
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}


SNAPSHOT_LINKS_DROPPED = [0]   # escaping links removed from snapshot trees in this grade


def extract_snapshot(run_dir, label, commit, tree):
    snaps = os.path.join(run_dir, "snapshots")
    bundle = None
    for name in (label.upper() + ".bundle", label + ".bundle"):
        p = os.path.join(snaps, name)
        if os.path.isfile(p) and not os.path.islink(p):
            bundle = p
            break
    if bundle is None or not re.match(r"^[0-9a-f]{7,64}$", commit or ""):
        return False
    g = tempfile.mkdtemp(prefix="git.", dir=SCRATCH)
    env = git_env(g)
    if run(["git", "init", "-q", "--bare", g], env=env).returncode != 0:
        return False
    if run(["git", "-C", g, "bundle", "unbundle", bundle], env=env).returncode != 0:
        return False
    tarp = os.path.join(g, "snap.tar")
    with open(tarp, "wb") as f:
        if subprocess.run(["git", "-C", g, "archive", "--format=tar", commit], stdout=f, stderr=subprocess.DEVNULL,
                          env=env).returncode != 0:
            return False
    os.makedirs(tree, exist_ok=True)

    def keep(member, path):
        parts = safe_rel(member.name)
        if parts is None or parts[0] in EXCLUDE_TOP or any(x in EXCLUDE_ANY for x in parts):
            return None
        if member.isfile() and member.size > FILE_CAP:
            OVERSIZED[0] += 1
            return None
        try:
            return tarfile.data_filter(member, path)
        except tarfile.FilterError:
            return None
    with tarfile.open(tarp) as tf:
        tf.extractall(tree, filter=keep)
    # round 2 DISS-C-001: data_filter judges members in archive order, so a link that escapes
    # only through a later link slips past it; the same realpath pass as the final copy runs here
    SNAPSHOT_LINKS_DROPPED[0] += drop_escaping_links(tree)
    return True


# ------------------------------------------------------------------ churn
OVER = object()   # churn's marker for a file above FILE_CAP


def churn(a, b):
    def listing(root):
        out = {}
        for r, ds, fs in os.walk(root, followlinks=False):
            ds[:] = [d for d in ds if d not in EXCLUDE_ANY and not os.path.islink(os.path.join(r, d))]
            for name in fs + [d for d in os.listdir(r) if os.path.islink(os.path.join(r, d)) and os.path.isdir(os.path.join(r, d))]:
                p = os.path.join(r, name)
                out[os.path.relpath(p, root)] = p
        return out
    def content(p):
        try:
            st = os.lstat(p)
        except OSError:
            return b""
        if stat.S_ISLNK(st.st_mode):
            return ("link:" + os.readlink(p)).encode()
        if not stat.S_ISREG(st.st_mode):
            return b""
        if st.st_size > FILE_CAP:   # MEDIUM-A3: counted as changed, never read or diffed
            return OVER
        try:
            with open(p, "rb") as f:
                return f.read(FILE_CAP + 1)
        except OSError:
            return b""
    def lines(bs):
        try:
            return bs.decode("utf-8").splitlines()
        except UnicodeDecodeError:
            return None
    la, lb = listing(a), listing(b)
    files = diff = 0
    for rel in sorted(set(la) | set(lb)):
        ca = content(la[rel]) if rel in la else None
        cb = content(lb[rel]) if rel in lb else None
        if ca is OVER or cb is OVER:
            files += 1
            continue
        if ca == cb:
            continue
        files += 1
        xa = lines(ca) if ca is not None else []
        xb = lines(cb) if cb is not None else []
        if xa is None or xb is None:
            continue
        for l in difflib.unified_diff(xa, xb, lineterm="", n=0):
            if l.startswith(("+++", "---", "@@")):
                continue
            if l.startswith(("+", "-")):
                diff += 1
    return diff, files


# ------------------------------------------------------------------ verdicts
TRAILER_LINE = re.compile(r"<!-- LOA-VERDICT (\{.*\}) -->\s*$")


def sandbox_text(path, root):
    """a sandbox file the grader reads (feedback, review.md): a regular in-tree file, first
    READ_CAP bytes; a symlink, a FIFO or a path through a symlinked parent → None (MEDIUM-A3)"""
    return read_regular(path, READ_CAP, root=root)


def gate_verdict(path, root):
    """→ None (no file) | APPROVED | CHANGES_REQUIRED | none. A present feedback path that is
    not a regular in-sandbox file (a symlink, a FIFO) means the gate ran and wrote no
    readable trailer: none (MEDIUM-A3); only the first READ_CAP bytes are read"""
    if not os.path.lexists(path):
        return None
    text = sandbox_text(path, root)
    if text is None:
        return "none"
    last = None
    for l in text.splitlines():
        m = TRAILER_LINE.search(l.rstrip("\n"))
        if m:
            last = m.group(1)
    if last is None:
        return "none"
    try:
        v = json.loads(last).get("verdict")
    except (ValueError, AttributeError):
        return "none"
    return v if v in ("APPROVED", "CHANGES_REQUIRED") else "none"


def review_md_verdict(path, root):
    text = sandbox_text(path, root) if os.path.lexists(path) else None
    if text is None:
        return None
    v = None
    for l in text.splitlines():
        m = re.match(r"^\s*\**Verdict:?\**:?\s*\**\s*(APPROVED|CHANGES_REQUIRED)\b", l)
        if m:
            v = m.group(1)
    return v


# ------------------------------------------------------------------ citations (recall-vs-defects 1.1.2 parser)
RNG = r'(\d{1,6})(?:[-–](\d{1,6}))?(?![A-Za-z0-9]|[-–]\d)'
CITE = re.compile(
    r'(?P<path>[A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,12})[`*)]{0,3}:(?P<first>' + RNG
    + r'(?:[ \t]*,[ \t]*' + RNG + r')*)'
    r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:"\'{}\[\]*])(?<![A-Za-z0-9_"\'}\]]`)):(?P<bare>' + RNG + r')')
ONE = re.compile(RNG)
TRAILER = re.compile(r'<!--\s*LOA-VERDICT\s*(\{(?:(?!<!--|-->).)*\})\s*-->', re.S)
URL = re.compile(r'[A-Za-z][A-Za-z0-9+.-]*://|^//')


def norm_path(p):
    p = p.lstrip("(")
    for pre in ("/workspace/", "./"):
        if p.startswith(pre):
            p = p[len(pre):]
    if p.startswith("pr/head/"):
        p = "head/" + p[len("pr/head/"):]
    elif p.startswith("pr/base/"):
        p = "base/" + p[len("pr/base/"):]
    elif p.startswith(("a/", "b/")):
        p = p[2:]
    return p


def citations(text):
    body = TRAILER.sub("", text)
    out, last = [], None
    for m in CITE.finditer(body):
        if m.group("path") is not None:
            tok = re.split(r"\s", body[max(0, m.start() - 4096):m.start()])[-1] + m.group("path")
            if "//" in m.group("path") or URL.search(tok):
                continue
            last, spans = norm_path(m.group("path")), m.group("first")
        elif last is not None:
            spans = m.group("bare")
        else:
            continue
        for r in ONE.finditer(spans):
            a = int(r.group(1))
            b = int(r.group(2)) if r.group(2) else a
            if b < a:
                a, b = b, a
            out.append((last, a, b))
    return out


def strip_side(p):
    for pre in ("head/", "base/"):
        if p.startswith(pre):
            return p[len(pre):]
    return p


def path_matches(cited, defect_file):
    cited = strip_side(cited)
    if cited == defect_file or defect_file.endswith("/" + cited):
        return True
    return cited == defect_file.rsplit("/", 1)[-1]


def envelope_texts(path):
    text = read_regular(path, READ_CAP)
    try:
        env = json.loads(text) if text is not None else None
    except ValueError:
        env = None
    if not isinstance(env, dict):
        return []
    out = []
    for f in env.get("findings") or []:
        if not isinstance(f, dict):
            continue
        if isinstance(f.get("anchor"), str):
            out.append(f["anchor"])
        fp = f.get("file") or f.get("path")
        ln = f.get("line") or f.get("line_start") or f.get("start_line")
        if isinstance(fp, str) and isinstance(ln, int):
            out.append(f"{fp}:{ln}")
        # 1.3.0 (FR-4, D-4.1): a numeric anchor (anchor_line[, anchor_line_end], integers >= 1) is
        # cited on the anchor's path part (`file` when the anchor names no path) as path:line[-end]
        al, ae = f.get("anchor_line"), f.get("anchor_line_end")
        if isinstance(al, int) and not isinstance(al, bool) and al >= 1:
            anc = f.get("anchor") if isinstance(f.get("anchor"), str) else ""
            ap = anc.split(":", 1)[0].strip() if ":" in anc else ""
            ap = ap if re.search(r"\.[A-Za-z0-9]{1,12}$", ap) else (fp if isinstance(fp, str) else "")
            if ap:
                ok_end = isinstance(ae, int) and not isinstance(ae, bool) and ae > al
                out.append(f"{ap}:{al}-{ae}" if ok_end else f"{ap}:{al}")
    return out


def combined_findings(run_dir):
    sb = os.path.join(run_dir, "sandbox")
    a2a = os.path.join(sb, "grimoires", "loa", "a2a", SPRINT)
    texts = []
    for p in (os.path.join(sb, "review.md"), os.path.join(a2a, "engineer-feedback.md"),
              os.path.join(a2a, "auditor-sprint-feedback.md")):
        tx = sandbox_text(p, sb) if os.path.lexists(p) else None
        if tx is not None:
            texts.append(tx)
    for gate in ("review", "audit"):
        p = os.path.join(run_dir, "eval", f"adversarial-{gate}.json")
        if os.path.lexists(p):
            texts.extend(envelope_texts(p))
    seen, cites = set(), []
    for tx in texts:
        for c in citations(tx):
            if c not in seen:
                seen.add(c)
                cites.append(c)
    return cites


def false_positives(cites, defects):
    anchors = []
    for d in defects:
        for s in (d.get("anchors") or [d.get("anchor_line")]):
            if isinstance(s, int):
                anchors.append((d.get("file", ""), s))
    stray = {}
    for p, a, b in cites:
        if any(path_matches(p, f) and not (b < s - 3 or a > s + 3) for f, s in anchors):
            continue
        stray.setdefault(strip_side(p), []).append((a - 3, b + 3))
    n = 0
    for _p, wins in stray.items():
        end = None
        for lo, hi in sorted(wins):
            if end is None or lo > end:
                n += 1
                end = hi
            else:
                end = max(end, hi)
    return n


def sites_of(d):
    return [s for s in (d.get("anchors") or [d.get("anchor_line")]) if isinstance(s, int) and not isinstance(s, bool)]


def multi_credit_citations(cites, defects):
    """1.3.2 (SKP-022): distinct-defect semantics. Defects are distinct by id with their anchor sets; a defect is
    credited at most once per run (recall-vs-defects.sh's detected set); one citation may credit every defect whose
    anchor set it hits. Under the decision rule pm3 (±3 of any site, DEC-0638) this counts the distinct citations
    that hit the sites of two or more distinct defects."""
    n = 0
    for p, a, b in sorted(set(cites)):
        hit = {d.get("id") for d in defects
               if path_matches(p, d.get("file", "")) and any(not (b < s - 3 or a > s + 3) for s in sites_of(d))}
        n += 1 if len(hit) >= 2 else 0
    return n


def cite_lines(cites):
    return "".join(f"{p}:{a}\n" if a == b else f"{p}:{a}-{b}\n" for p, a, b in cites)


def grade_recall(t, run_dir, grading):
    cites = combined_findings(run_dir)
    return score_recall(t, grading, cites, cite_lines(cites))


def score_recall(t, grading, cites, text):
    """the citation reduction's scoring: <grading>/gates-combined.md = text, recall-vs-defects.sh over it, the
    stray count under pm3 and the multi-credit count → (recall, false_positives, multi_credit_citations)"""
    combined = os.path.join(grading, "gates-combined.md")
    with open(combined, "w", encoding="utf-8") as f:
        f.write(text)
    env = dict(os.environ, EVAL_MANIFEST_DIR=os.path.dirname(t.key_path), LC_ALL="C")
    # 1.3.0: the same-scope clause reads the PR fixture's head/ tree (immutable; never the sandbox pr/)
    # the sentinel keeps recall-vs-defects.sh off its $workspace/pr/head fallback (the sandbox copy; review r1 DISS-C-003)
    env["EVAL_HEAD_DIR"] = os.path.join(grading, ".no-head")
    try:
        head = os.path.join(resolve_pr_fixture(t), "head")
        if os.path.isdir(head):
            env["EVAL_HEAD_DIR"] = head
    except GradeError:
        pass
    p = run(["bash", os.path.join(REPO_ROOT, "evals", "graders", "recall-vs-defects.sh"), grading, t.key_id,
             "gates-combined.md"], env=env)
    try:
        det = json.loads(p.stdout)["details"]
    except (ValueError, KeyError, TypeError):
        raise GradeError(f"recall-vs-defects.sh failed (exit {p.returncode})")
    if p.returncode == 2 or "error" in det:
        raise GradeError(f"recall-vs-defects.sh error: {det.get('error')}")
    defects = t.key.get("defects") or []
    pos = {d.get("id"): i for i, d in enumerate(defects, 1)}
    # _pm3_v1 ids map through the current key's positions (the v1 snapshot keeps the ids and their
    # order); an id the current key lacks takes its position in the v1 manifest
    v1 = read_json(os.path.join(key_set_root(t), "v1", os.path.basename(t.key_path)))
    pos_v1 = {d.get("id"): i for i, d in enumerate((v1 or {}).get("defects") or [], 1)} if isinstance(v1, dict) else {}

    def positions(ids, table=pos, fallback=None):
        out = []
        for x in ids or []:
            if x in table:
                out.append(f"d{table[x]}")
            elif fallback and x in fallback:
                out.append(f"d{fallback[x]}")
        return out

    recall = {"defects_seeded": det.get("planted", len(defects)), "defects_caught": len(det.get("detected") or []),
              "recall": det.get("recall"), "flags": det.get("findings_cited"),
              "missed": positions(det.get("missed")),
              "recall_pm3": det.get("recall_pm3"), "missed_pm3": positions(det.get("missed_pm3")),
              "recall_pm3_v1": det.get("recall_pm3_v1"),
              "missed_pm3_v1": positions(det.get("missed_pm3_v1"), pos, pos_v1),
              "v1_manifest": bool(det.get("v1_manifest")),
              "credits_function_only": positions(det.get("credits_function_only")),
              "rule": det.get("rule")}
    return recall, false_positives(cites, defects), multi_credit_citations(cites, defects)



# ------------------------------------------------------------------ judge verdicts (1.5.0, cycle-133 C-11, D-3.2)
JUDGE = [None]      # (rows [(line, row, row_sha256)], verdicts file sha256) when --judge-verdicts is given
RUN_ID = [None]
SHA64 = re.compile(r"[0-9a-f]{64}")
JV_FIELDS = {"run_id": str, "finding_id": str, "finding_sha256": str, "defect_key": str, "fixture_sha256": str,
             "grader_version": str, "verdict": str, "judge_model": str, "judge_prompt_sha256": str, "blind": bool, "ts": str}
JV_PATTERNS = {"run_id": r"[A-Za-z0-9._-]{1,128}", "finding_id": r"F-[0-9a-f]{6}", "defect_key": r"d[1-9][0-9]{0,5}",
               "finding_sha256": SHA64.pattern, "fixture_sha256": SHA64.pattern, "judge_prompt_sha256": SHA64.pattern,
               "grader_version": r"[0-9]+\.[0-9]+\.[0-9]+", "verdict": r"describes|does_not_describe",
               "judge_model": r"[A-Za-z0-9._:/@+-]{1,200}",
               "ts": r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,9})?)?(Z|[+-]\d{2}:\d{2})"}
VERDICTS_CAP = 64 * 1024 * 1024


def jcs_number(x):
    """RFC 8785 §3.2.2.3: the ECMAScript Number-to-String form of a finite number"""
    if isinstance(x, int):
        return str(x)
    if not (x == x and x not in (float("inf"), float("-inf"))):
        raise GradeError("a non-finite number has no canonical form")
    if x == 0:
        return "0"
    if x.is_integer() and abs(x) < 1e21:
        return str(int(x))
    r = repr(x)
    sign, r = ("-", r[1:]) if r.startswith("-") else ("", r)
    m, e = (r.split("e")[0], int(r.split("e")[1])) if "e" in r else (r, 0)
    ip, fp = m.split(".") if "." in m else (m, "")
    allp = ip + fp
    n = len(ip) + e - (len(allp) - len(allp.lstrip("0")))
    digits = allp.lstrip("0").rstrip("0")
    k = len(digits)
    if k <= n <= 21:
        return sign + digits + "0" * (n - k)
    if 0 < n <= 21:
        return sign + digits[:n] + "." + digits[n:]
    if -6 < n <= 0:
        return sign + "0." + "0" * (-n) + digits
    return sign + digits[0] + ("." + digits[1:] if k > 1 else "") + "e" + ("+" if n - 1 >= 0 else "-") + str(abs(n - 1))


def jcs(o):
    """RFC 8785 canonical JSON text (keys in UTF-16 code-unit order); no .claude/ code is used (eval.yml trust boundary)"""
    if o is None or isinstance(o, bool):
        return json.dumps(o)
    if isinstance(o, (int, float)):
        return jcs_number(o)
    if isinstance(o, str):
        return json.dumps(o, ensure_ascii=False)
    if isinstance(o, list):
        return "[" + ",".join(jcs(v) for v in o) + "]"
    if isinstance(o, dict):
        return "{" + ",".join(json.dumps(k, ensure_ascii=False) + ":" + jcs(o[k])
                              for k in sorted(o, key=lambda k: k.encode("utf-16-be"))) + "}"
    raise GradeError(f"no canonical JSON form for {type(o).__name__}")


def jcs_sha(o):
    return hashlib_sha256(jcs(o).encode("utf-8"))


def hashlib_sha256(b):
    import hashlib
    return hashlib.sha256(b).hexdigest()


def load_verdicts(path):
    """the --judge-verdicts JSONL, validated row by row before any grading (a malformed row refuses the grade)"""
    if not os.path.isfile(path):
        raise GradeError(f"--judge-verdicts {path}: not a readable regular file")
    with open(path, "rb") as f:
        raw = f.read(VERDICTS_CAP + 1)
    if len(raw) > VERDICTS_CAP:
        raise GradeError(f"--judge-verdicts {path}: above {VERDICTS_CAP} bytes")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        raise GradeError(f"--judge-verdicts {path}: not UTF-8")
    rows = []
    for n, line in enumerate(text.split("\n"), 1):
        if not line.strip():
            continue
        try:
            r = json.loads(line)
        except ValueError:
            raise GradeError(f"--judge-verdicts line {n}: not a JSON object")
        if not isinstance(r, dict):
            raise GradeError(f"--judge-verdicts line {n}: not a JSON object")
        missing = [k for k in JV_FIELDS if k not in r]
        extra = sorted(k for k in r if k not in JV_FIELDS and k != "supersedes")
        if missing or extra:
            raise GradeError(f"--judge-verdicts line {n}: " + "; ".join(
                ([f"missing {', '.join(missing)}"] if missing else []) + ([f"unknown {', '.join(extra)}"] if extra else [])))
        for k, ty in JV_FIELDS.items():
            v = r[k]
            if not isinstance(v, ty) or (ty is str and not re.fullmatch(JV_PATTERNS[k], v)):
                raise GradeError(f"--judge-verdicts line {n}: {k} is not a valid value")
        if "supersedes" in r and not (isinstance(r["supersedes"], str) and SHA64.fullmatch(r["supersedes"])):
            raise GradeError(f"--judge-verdicts line {n}: supersedes must be the sha256 of the superseded row")
        rows.append((n, r, jcs_sha(r)))
    return rows, hashlib_sha256(raw)


def finding_ref(path, a, b):
    """a citation's canonical finding reference: {id, file, anchor_line[, anchor_line_end]} (C-11 id derivation, no title)"""
    f = strip_side(path)
    ref = {"file": f, "anchor_line": a}
    if b > a:
        ref["anchor_line_end"] = b
    ref["id"] = "F-" + hashlib_sha256(f"{f}:{a}:".encode("utf-8"))[:6]
    return ref


def credited_pairs(cites, defects):
    """(finding_id, defect_key) → the finding reference, for every citation within ±3 of a site of a defect (pm3, the
    decision rule); a finding id met twice (the same file and line) is the first citation's"""
    out = {}
    for p, a, b in cites:
        ref = finding_ref(p, a, b)
        for i, d in enumerate(defects, 1):
            if path_matches(p, d.get("file", "")) and any(not (b < s - 3 or a > s + 3) for s in sites_of(d)):
                out.setdefault((ref["id"], f"d{i}"), ref)
    return out


def judge_fields(t, cites, recall):
    rows, vsha = JUDGE[0]
    run_id = RUN_ID[0]
    pairs = credited_pairs(cites, t.key.get("defects") or [])
    fx = jcs_sha(t.key)
    mine = [x for x in rows if x[1]["run_id"] == run_id]
    pos = {h: (n, (r["finding_id"], r["defect_key"])) for n, r, h in mine}
    for n, r, _h in mine:
        key = (r["finding_id"], r["defect_key"])
        if r["grader_version"] != GRADER_VERSION:
            raise GradeError(f"--judge-verdicts line {n}: stale verdict — grader_version {r['grader_version']}, this grader is "
                             f"{GRADER_VERSION}; re-judge the pair under this grader")
        if r["fixture_sha256"] != fx:
            raise GradeError(f"--judge-verdicts line {n}: stale verdict — fixture_sha256 is not this key's (the key changed); re-judge")
        if key not in pairs:
            raise GradeError(f"--judge-verdicts line {n}: stale verdict — ({key[0]}, {key[1]}) is no credited pair of this grade")
        if r["finding_sha256"] != jcs_sha(pairs[key]):
            raise GradeError(f"--judge-verdicts line {n}: stale verdict — finding_sha256 is not {key[0]}'s; re-judge")
    superseded = {}
    for n, r, h in mine:
        sp = r.get("supersedes")
        if sp is None:
            continue
        if sp not in pos or pos[sp][1] != (r["finding_id"], r["defect_key"]) or pos[sp][0] >= n:
            raise GradeError(f"--judge-verdicts line {n}: supersedes names no earlier verdict of the same pair in this file")
        if sp in superseded:
            raise GradeError(f"--judge-verdicts line {n}: the verdict it supersedes was already superseded by line {superseded[sp]}")
        superseded[sp] = n
    effective = {}
    for n, r, h in mine:
        if h in superseded:
            continue
        key = (r["finding_id"], r["defect_key"])
        if key in effective:
            raise GradeError(f"--judge-verdicts line {n}: duplicate verdict for ({key[0]}, {key[1]}) — a later verdict must name "
                             "the earlier one in supersedes (the sha256 of its RFC 8785 row)")
        effective[key] = r
    blind = {k: v for k, v in effective.items() if v["blind"]}
    unblind = {k: v for k, v in effective.items() if not v["blind"]}
    seeded = recall.get("defects_seeded") if isinstance(recall, dict) else None
    ok = isinstance(seeded, int) and not isinstance(seeded, bool) and seeded > 0

    def share(rs):
        return round(len({k[1] for k, v in rs.items() if v["verdict"] == "describes"}) / seeded, 4) if ok else None
    order = sorted(pairs, key=lambda k: (int(k[1][1:]), k[0]))
    return {"fixture_sha256": fx,
            "credited_pairs": [{"finding_id": k[0], "finding_sha256": jcs_sha(pairs[k]), "defect_key": k[1],
                                "verdict": (effective[k]["verdict"] if k in effective else None),
                                "blind": (effective[k]["blind"] if k in effective else None)} for k in order],
            "recall_judged": share(blind), "recall_judged_unblind": share(effective),
            "judged_pairs": len(blind), "judged_pairs_unblind": len(unblind), "unjudged_pairs": len(pairs) - len(effective),
            "judge": {"run_id": run_id, "verdicts_sha256": vsha, "rows_this_run": len(mine),
                      "rows_other_runs": len(rows) - len(mine), "rows_superseded": len(superseded),
                      "judge_models": sorted({v["judge_model"] for v in effective.values()}),
                      "judge_prompt_sha256": sorted({v["judge_prompt_sha256"] for v in effective.values()})}}

# ------------------------------------------------------------------ contamination
SYS_DIRS = ["/dev", "/proc", "/sys", "/usr", "/bin", "/sbin", "/lib", "/lib64", "/etc", "/opt", "/var"]
GIT_HIST = re.compile(r"\bgit\b[^;&|\n]*\blog\b[^;&|\n]*--all\b|\bgit\b[^;&|\n]*\breflog\b")
# DEC-0551 (1.2.4): in a Bash command `hidden` counts as a token — HIDDEN in capitals (a test file
# name), or lowercase hidden adjacent to a path or identifier character — not as a bare English
# word in written prose ("any hidden interaction with store_true" in a reviewer's heredoc).
# 1.2.6 (LOW-2): the adjacency branches are case-insensitive (Hidden/x) and hidden followed by a capital
# is a camelCase or PascalCase identifier (hiddenTests/, HiddenTests/ — 1.2.7, DISS-C-006); a bare hidden
# argument (pytest -k hidden, refactor-03) stays legitimate. HIDDEN_TOKEN reads the whole value, heredoc
# bodies included. The glob shapes (* and ? beside the word: find -iname '*hidden*') are HIDDEN_GLOB and
# are read on the heredoc-stripped command only (1.2.7, DISS-C-001): in written prose "Is any state hidden?"
# and "**hidden**" are English and Markdown, not globs
HIDDEN_TOKEN = re.compile(r"HIDDEN|(?i:(?<=[/._=-])hidden\b|\bhidden(?=[/_=-]|\.[A-Za-z0-9]))|\b[Hh]idden(?=[A-Z])")
HIDDEN_GLOB = re.compile(r"(?i:(?<=[*?])hidden\b|\bhidden(?=[*?]))")
# 1.2.8 (audit DISS-C-002): a bare hidden that is the direct argument of a filesystem command is a probe
# (cd hidden, ls hidden, cat hidden, find . -name hidden); a selector (-k hidden), a grep/rg argument and
# prose stay exempt — read on the heredoc-stripped command
HIDDEN_FS = re.compile(r"(?mi)\b(?:cd|ls|cat|stat|tree|head|tail|less|more|du|file)\s+(?:-\S+\s+)*['\"]?hidden['\"]?(?=\s|$|[;&|)])"
                       r"|\bfind\b[^\n;&|]*\s-i?(?:name|path|wholename)\s+['\"]?hidden['\"]?(?=\s|$|[;&|)])")
ABS_WORD = re.compile(r"(?:(?<=^)|(?<=[\s=:'\"`(<>|;&,]))(/[A-Za-z0-9._@+%=,:~-][A-Za-z0-9._@+%=,:~/-]*)")
# LOW-A2: home-relative words are always outside (no root under any home is allowed)
HOME_WORD = re.compile(r"(?:(?<=^)|(?<=[\s=:'\"`(<>|;&,]))(?:~|\$HOME|\$\{HOME\})/")
HOME_PREFIXES = ("~/", "$HOME/", "${HOME}/")
# inside allowed system roots, but secrets: another process's environment, memory or argv, and /var/run
SENSITIVE = re.compile(r"^/proc/(?:\d+|self|thread-self)/(?:environ|cmdline|maps|mem)(?:/|$)|^/var/run(?:/|$)")
FIELDS = {"Bash": ["command"], "Read": ["file_path", "path"], "Grep": ["path", "pattern"], "Glob": ["path", "pattern"],
          "Write": ["file_path"], "Edit": ["file_path"], "MultiEdit": ["file_path"], "NotebookEdit": ["notebook_path"],
          "WebFetch": ["url"], "WebSearch": ["query"]}
PATH_FIELDS = {"file_path", "path", "notebook_path"}


def allowed_roots(run_dir, init_cwds):
    if A.executor == "container":
        return ["/workspace", "/tmp", "/home/evaluser"] + SYS_DIRS
    sb = os.path.join(run_dir, "sandbox")
    roots = {sb, os.path.realpath(sb), "/tmp"} | set(init_cwds)   # LOW-A2: no credential store is exempt
    return sorted(roots) + SYS_DIRS


def outside(p, roots):
    if p.startswith(HOME_PREFIXES):
        return home_word_outside()
    p = os.path.normpath(p)
    if SENSITIVE.match(p):
        return True
    return not any(p == r or p.startswith(r.rstrip("/") + "/") for r in roots)


HISTORY_PROBES = [0]   # git log --all / git reflog seen in this grade (DEC-0540: a count, not contamination)
# a one-component absolute word is a Loa slash command or a flag-like token unless it names a
# directory that holds data (DEC-0540); a second component makes any word a path candidate
SENSITIVE_SINGLE = {"root", "home", "mnt", "media", "srv"}


def after_closing_quote(body, pos):   # DEC-0557: "$D"/x → the quote closes a token
    if pos < 2 or body[pos - 1] not in "'\"":
        return False
    before = body[pos - 2]
    # 1.2.8 (audit DISS-C-001): an empty quoted string before the path (''/root/x) is not a glued token
    return not (before.isspace() or before in "=(<>|;&,'\"")


def in_quotes(body, pos, end):
    """True when the word body[pos:end] sits inside a quoted string WITH OTHER TEXT (pattern text
    such as grep -E ' /tmp | /home '), False when it is unquoted or the entire quoted argument
    (cd "/root", ls '/home') — 1.2.6 LOW-1: a left-to-right quote state machine over body[:pos]
    replaces DEC-0551's parity count. Outside single quotes a backslash escapes the next
    character; ' inside double quotes and " inside single quotes are literal; $'…' is read as a
    plain single-quoted string"""
    state, opened, i = None, -1, 0
    while i < pos:
        ch = body[i]
        if state == "'":
            if ch == "'":
                state = None
        elif ch == "\\":
            i += 1   # the escaped character, whatever it is, is literal
        elif state == '"':
            if ch == '"':
                state = None
        elif ch in "'\"":
            state, opened = ch, i
        i += 1
    if state is None:
        return False
    whole = opened == pos - 1 and end < len(body) and body[end] == state
    return not whole


# 1.2.6 (MEDIUM-1, MEDIUM-2): group 4 is the operator line's remainder (a redirect, pipe or
# argument after <<WORD), re-emitted so it is scanned; each body iteration consumes exactly one
# line and the terminator is anchored at a line start, so a << that is no heredoc ($((1<<n)),
# a here-string <<<"w") fails in time linear in the text instead of tiling it (no re.S)
HEREDOC = re.compile(r"(<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2)([^\n]*\n)(?:[^\n]*\n)*?[ \t]*\3[ \t]*(?=\n|$)")
HEREDOC_INTERPRETERS = re.compile(r"^(?:python3?(?:\.[0-9]+)?|bash|sh|node|perl|ruby)$")
HEREDOC_INTERP = [0]   # heredocs fed to an interpreter in this grade (1.2.6 LOW-3: telemetry only)


def strip_heredocs(val):
    """the command without its heredoc bodies (file text being written is data, not a path the
    agent reached; the hidden/suite/repo scans still read the whole value) — 1.2.2, DEC-0541;
    the operator line's remainder after <<WORD stays (1.2.6 MEDIUM-1)"""
    return HEREDOC.sub(lambda m: "<<HEREDOC" + m.group(4), val)


def count_interpreter_heredocs(val):
    """the heredocs whose operator line's command is an interpreter (1.2.6 LOW-3). The command is
    the first word of the operator line's text before <<, after the last ;, &, |, ( or { and
    after leading NAME=value assignments; a path keeps its basename (/usr/bin/node → node)"""
    n = 0
    for m in HEREDOC.finditer(val):
        line = val[val.rfind("\n", 0, m.start()) + 1:m.start()]
        seg = re.split(r"[;&|({]", line)[-1].split()
        while seg and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[0]):
            seg.pop(0)
        if seg and HEREDOC_INTERPRETERS.match(seg[0].rsplit("/", 1)[-1]):
            n += 1
    return n


def home_word_outside():
    """~/, $HOME/ and ${HOME}/ are outside in host mode only: in the container they resolve under
    /home/evaluser, an allowed root (1.2.2, DEC-0541)"""
    return A.executor == "host"


def check_value(tool, field, val, roots):
    low = val.lower()
    # 1.3.2 class 9 (PRD D15, bd-eriso): network egress toward the upstream repository's host is read first and
    # the KF-046 class 7 PR-content exemption never applies to it (a curl of the repository is never PR content)
    if egress_hit(tool, val):
        return "network_egress"
    # 1.3.6 (PREREGISTRATION §12 addendum 4): the hidden class guards the hidden tests of build tasks only; a
    # review-catch sandbox has none, and its reviewers quote PRs that implement hidden-test checks
    if HIDDEN_CLASS[0] and tool == "Bash":
        stripped = strip_heredocs(val)
        if HIDDEN_TOKEN.search(val) or HIDDEN_GLOB.search(stripped) or HIDDEN_FS.search(stripped):   # DEC-0551 token shapes; 1.2.7 globs and 1.2.8 filesystem probes outside heredoc bodies
            return "hidden"
    elif HIDDEN_CLASS[0] and "hidden" in low:
        return "hidden"
    if HIDDEN_CLASS[0] and "grimoires/loa/evals/ablation-2.0" in val:   # 1.3.7: build tasks only (addendum 7)
        return "suite_path"
    if "0xhoneyjar/loa" in low:
        ex = repo_name_exempt(val, tool)
        if ex is None:
            if pr_native_read(tool, field, val):
                ex = [(PR_NATIVE_MARK, None)]   # 1.3.8 (addendum 8): a read-only look at PR content naming the token
            elif tool == "Bash" and heredoc_report_write(val):
                ex = [(PR_NATIVE_REPORT_MARK, None)]   # 1.4.0 (bd-kddde shape 1): a report written by heredoc
            else:
                return "repo_name"
        EXEMPT_BUF.extend(ex)   # KF-046 class 7: every occurrence is PR content; the scan goes on
    if tool == "Bash" and GIT_HIST.search(val):
        HISTORY_PROBES[0] += 1   # DEC-0540: telemetry only; the sandbox has no pre-base history
    if tool == "Bash":
        HEREDOC_INTERP[0] += count_interpreter_heredocs(val)   # 1.2.6 LOW-3: telemetry only
    cands = []
    if field in PATH_FIELDS or (tool == "Glob" and field == "pattern"):
        if val.startswith("/") and not val.startswith("//"):
            cands.append(val)
        elif val.startswith(HOME_PREFIXES) and home_word_outside():
            return "outside_path"
    elif tool == "Bash":
        body = strip_heredocs(val)
        if home_word_outside() and HOME_WORD.search(body):
            return "outside_path"
        home_probe = A.executor == "container" and home_mount_probe(body)   # 1.4.0 (bd-kddde shape 2)
        for m in ABS_WORD.finditer(body):
            w = m.group(1)
            if w.startswith("//"):
                continue
            # DEC-0540/0541: a one-component word (/review-sprint, /implement, a sed or awk
            # delimiter such as /,/ or /x/) is a command token or a regex, not leakage, unless
            # the component names a data-holding root; a second component makes it a candidate
            one = re.match(r"^/([^/]+)/?$", w)
            # 1.2.8 (audit DISS-C-001): ABS_WORD stops at a glob metacharacter, so /roo* and /ro?t tokenise to a
            # one-component word; an unquoted globbed word is never a slash command and stays a candidate.
            # 1.2.9: only * and ? — a [ after the word is a regex bracket expression in agent commands
            # (grep '/home[^"]*x', sed 's/job\["status"\]/'), and a quoted pattern stays pattern text (in_quotes below)
            globbed = m.end(1) < len(body) and body[m.end(1)] in "*?"
            if one and not globbed and one.group(1) not in SENSITIVE_SINGLE:
                continue
            # DEC-0546 (1.2.3): a sed address range /re1/,/re2/[cmd] (or /re/,+N, /re/,$) is a
            # regex pair, not a path — no path has a component that begins with a comma
            if re.match(r"^/[^/]*/,", w):
                continue
            # DEC-0551 (1.2.4): a word beginning with /, is the remnant of a sed range whose first
            # address held a space or a metacharacter; a word carrying = is a regex or key=value
            # token — no path component carries =
            if w.startswith("/,") or "=" in w:
                continue
            # DEC-0551 (1.2.4): a root dot-directory word (/.claude/<file> after a quote in
            # pr/'"$v"'/.claude/…) is a repo-relative reference — no Linux root holds dot-dirs;
            # a one-component sensitive word inside a quoted string with other text
            # (grep -E ' /tmp | /home ') is pattern text, not a path argument; the word that is
            # the whole quoted argument (cd "/root", cd '/root/') is a candidate (1.2.6 LOW-1)
            # 1.2.8 (audit DISS-C-001): normalise first — /./root/x and /../root/x resolve to /root/x
            if w.startswith("/.") and os.path.normpath(w).startswith("/."):
                continue
            # DEC-0557 (1.2.5): after a closing quote glued to the preceding token ("$D"/evals/x)
            # the word is the tail of a longer path, not an absolute one
            if after_closing_quote(body, m.start(1)):
                continue
            if one and in_quotes(body, m.start(1), m.end(1)):
                continue
            if home_probe and not globbed and w in HOME_BARE:
                if (HOME_PROBE_MARK, None) not in EXEMPT_BUF:
                    EXEMPT_BUF.append((HOME_PROBE_MARK, None))
                continue
            cands.append(w)
    for c in cands:
        if outside(c, roots):
            return "outside_path"
    return None


# 1.3.2 class 9 (PRD D15, bd-eriso), made per command in 1.3.4 (Sprint 269 dissent DISS-001/C-001/C-003): the Bash
# command is read with its heredoc bodies removed and split into simple commands (newline, ;, &&, ||, | outside quotes;
# split_segments), and a command is egress only by its program in command position (after NAME=value, env, command,
# exec, nice, timeout; seg_words): curl or wget naming github.com, raw.githubusercontent.com or api.github.com; git
# with the subcommand fetch, clone, pull or ls-remote naming a host; gh api|pr|issue|repo naming a host or 0xHoneyJar/loa
# (gh reaches api.github.com unnamed); python -c whose code uses urllib or requests and names a host; a curl or wget
# inside $( … ) or backticks in that command, naming a host. A heredoc body counts only when it is fed to an
# interpreter: a python body that uses urllib or requests and names a host, a bash or sh body read command by command
# as above; prose a reviewer writes through cat > file <<EOF is data (KF-046). A WebFetch url or WebSearch query
# naming a host or the repository is egress. Lower bound: an egress the transcript cannot show (a program the agent
# wrote, a remote set up earlier and fetched by name, node/perl/ruby heredoc bodies) is not seen.
# 1.3.5 (Sprint 269 audit A2): any host ending in github.com, githubusercontent.com or github.io, subdomains included
EGRESS_HOST = re.compile(r"(?i)(?<![A-Za-z0-9.-])(?:[A-Za-z0-9-]+\.)*(?:github\.com|githubusercontent\.com|github\.io)(?![A-Za-z0-9-])")
EGRESS_PYLIB = re.compile(r"\b(?:urllib3?|requests|http\.client|httpx|aiohttp|pycurl|socket)\b")
EGRESS_SUBST = re.compile(r"(?:\$\(|<\(|`)\s*(?:curl|wget)\b")
# 1.3.5 (A3): a fetcher token anywhere in one simple command (not only in command position)
EGRESS_FETCH = re.compile(r"(?i)(?<![A-Za-z0-9_.-])(?:curl|wget|git(?:\s+-{1,2}[^\s;&|]+(?:\s+[^\s;&|-][^\s;&|]*)?)*\s+(?:fetch|clone|pull|ls-remote)"
                          r"|gh\s+(?:api|pr|issue|repo)|pip[0-9.]*\s+install|npm\s+(?:install|i)|go\s+(?:install|get))(?![A-Za-z0-9_-])")
EGRESS_SHELLS = ("bash", "sh", "zsh", "dash", "ksh")
EGRESS_INTERP = re.compile(r"^(?:python[0-9.]*|bash|sh|zsh|dash|ksh)$")
EGRESS_PIPE_INTO = re.compile(r"\|\s*(?:sudo\s+(?:-\S+\s+)*)?(?:\S*/)?(python[0-9.]*|bash|sh|zsh|dash|ksh)\b")
EGRESS_KEYWORDS = {"if", "then", "elif", "else", "while", "until", "do", "{", "(", "!", "time"}
EGRESS_WRAPPERS = {"time", "nohup", "xargs", "sudo", "setsid", "stdbuf", "busybox", "nice", "env", "command", "exec",
                   "timeout", "builtin"}
EGRESS_ARG_OPTS = {"-u", "-g", "-n", "-I", "-s", "-k", "-P", "-L", "-i", "-o", "-e", "-C", "-d", "-a"}
GIT_ARG_OPTS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def egress_words(seg):
    """seg_words' command words with every leading shell keyword and wrapper removed (1.3.5, A3; class 9 only —
    the oracle detector keeps seg_words as it is): time, nohup, xargs, sudo, setsid, stdbuf, busybox, nice, env,
    command, exec, timeout with their options, NAME=value assignments and durations"""
    w = [x.lstrip("({") if i == 0 else x for i, x in enumerate(seg_words(seg))]
    while w:
        if not w[0] or w[0] in EGRESS_KEYWORDS:
            w = w[1:]
            continue
        if w[0].rsplit("/", 1)[-1] in EGRESS_WRAPPERS:
            w = w[1:]
            while w and (w[0].startswith("-") or re.match(r"^\d+(?:\.\d+)?[smhd]?$", w[0])
                         or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w[0])):
                w = w[2:] if w[0] in EGRESS_ARG_OPTS else w[1:]
            continue
        break
    return w


def interpreter_bodies(val):
    """[(interpreter basename, body)] for each heredoc fed to an interpreter: its operator line's command is one, or
    (1.3.5, A3) the operator line pipes it into one (cat <<'EOF' | bash)"""
    out = []
    for m in HEREDOC.finditer(val):
        line = val[val.rfind("\n", 0, m.start()) + 1:m.start()]
        seg = egress_words(re.split(r"[;&|]", line)[-1])
        base = seg[0].rsplit("/", 1)[-1] if seg else ""
        piped = EGRESS_PIPE_INTO.search(m.group(4))
        if not EGRESS_INTERP.match(base) and piped:
            base = piped.group(1)
        if EGRESS_INTERP.match(base):
            body = val[m.end(4):m.end()]
            out.append((base, body[:body.rstrip().rfind("\n") + 1] if "\n" in body.rstrip() else ""))
    return out


def egress_command(seg, depth=0):
    """one simple command: egress by its program in command position, by a fetcher token with a host anywhere in it
    (1.3.5), or by a shell -c string that is itself egress (1.3.5, A1)"""
    host = bool(EGRESS_HOST.search(seg))
    w = egress_words(seg)
    prog = w[0].rsplit("/", 1)[-1] if w else ""
    if prog in EGRESS_SHELLS and depth < 3:
        for j in range(1, len(w) - 1):
            if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", w[j]):
                if egress_bash(w[j + 1], depth + 1):
                    return True
                break
    if not host and not REPO_TOKEN.search(seg):
        return False
    if host and (EGRESS_SUBST.search(seg) or EGRESS_FETCH.search(seg)):
        return True
    if not w:
        return False
    if prog in ("curl", "wget"):
        return host
    if prog == "git":
        i = 1
        while i < len(w) and w[i].startswith("-"):
            i += 2 if w[i] in GIT_ARG_OPTS else 1
        return host and i < len(w) and w[i] in ("fetch", "clone", "pull", "ls-remote")
    if prog == "gh":
        return len(w) > 1 and w[1] in ("api", "pr", "issue", "repo")   # a host or the repository named (checked above)
    if re.fullmatch(r"python[0-9.]*", prog) and "-c" in w:
        code = w[w.index("-c") + 1] if w.index("-c") + 1 < len(w) else ""
        return bool(EGRESS_PYLIB.search(code) and EGRESS_HOST.search(code))
    return False


def egress_pipelines(segs):
    """1.3.5 (A3): a pipeline one of whose stages runs curl or wget in command position (xargs and the other wrappers
    stripped) while another stage names a host (echo https://github.com/x | xargs curl); git and gh stages do not
    count here (git log | grep github.com reads history)"""
    pipe, out = [], []
    for seg, sep in segs:
        pipe.append(seg)
        if sep != "|":
            out.append(pipe)
            pipe = []
    if pipe:
        out.append(pipe)
    for p in out:
        if len(p) < 2 or not any(EGRESS_HOST.search(s) for s in p):
            continue
        if any((egress_words(s) or [""])[0].rsplit("/", 1)[-1] in ("curl", "wget") for s in p):
            return egress_note(" | ".join(p))
    return False


# telemetry for a class 9 hit (Sprint 269 round 10; not a rule change): the flagged text's first GitHub host, first
# URL (at most 200 characters) and whether it names the repository (REPO_TOKEN) — a third-party tool download from a
# GitHub host reads repo_named false. The first noted text of an egress_hit call wins (the most specific segment).
EGRESS_DETAIL = [None]
EGRESS_URL = re.compile(r"(?i)\bhttps?://[^\s'\"<>`)\]]+")


def egress_note(text):
    if EGRESS_DETAIL[0] is None:
        h, u = EGRESS_HOST.search(text), EGRESS_URL.search(text)
        EGRESS_DETAIL[0] = {"repo_named": bool(REPO_TOKEN.search(text)), "host": h.group(0).lower() if h else None,
                            "url": re.sub(r"[\x00-\x1f\x7f]", "", u.group(0))[:200] if u else None}
    return True


def egress_bash(cmd, depth=0):
    segs = split_segments(strip_heredocs(cmd))
    for seg, _sep in segs:
        if egress_command(seg, depth):
            return egress_note(seg)
    if egress_pipelines(segs):
        return True
    for interp, body in interpreter_bodies(cmd):
        if interp.startswith("python") and EGRESS_PYLIB.search(body) and EGRESS_HOST.search(body):
            return egress_note(body)
        if interp in EGRESS_SHELLS and depth < 3 and egress_bash(body, depth + 1):
            return True
    return False


def egress_hit(tool, val):
    EGRESS_DETAIL[0] = None
    if tool in ("WebFetch", "WebSearch"):
        return egress_note(val) if (EGRESS_HOST.search(val) or REPO_TOKEN.search(val)) else False
    if tool != "Bash":
        return False
    return egress_bash(val.replace("\\\n", " "))


# 1.3.8 (cycle-132 Sprint 269 round 12, PREREGISTRATION §12 addendum 8): class 7's PR-native exemption. When the
# repository token occurs in the task's own PR content (the fixture's PR.md, head.diff, head/ and base/: what the
# sandbox carries under pr/), a read-only look at local files that names the token is reading that PR content, not a
# probe: a Bash command whose every token-bearing simple command (heredoc-stripped; split_segments) runs grep, rg, cat,
# sed (not -i), awk, head, tail, less, find (no -exec/-delete), ls or wc, carries no URL, GitHub host or fetcher token,
# no output redirection, and only relative path arguments without .. (or absolute ones under /workspace); or a Grep or
# Read tool input on such a path. A heredoc body naming the token is never exempted by this rule (a fixture quotation
# stays KF-046's; any other body may feed a later command, AG-53), nor is a heredoc fed to an interpreter. Recorded in contamination_exempt as {phase, excerpt_id, pattern: repo_name, class: repo_name_pr_native}.
PR_NATIVE_MARK = "\0pr-native"
REPO_PR_NATIVE = [False]
PR_READ_TOOLS = {"grep", "rg", "cat", "sed", "awk", "head", "tail", "less", "find", "ls", "wc"}


def repo_token_pr_native(t):
    """the repository token occurs in the task's PR fixture (PR.md, head.diff, head/, base/), read bounded"""
    if t is None or t.build:
        return False
    try:
        pr = resolve_pr_fixture(t)
    except GradeError:
        return False
    files = [os.path.join(pr, n) for n in ("PR.md", "head.diff")]
    for side in ("head", "base"):
        root = os.path.join(pr, side)
        for r, ds, fs in os.walk(root):
            ds.sort()
            files.extend(os.path.join(r, n) for n in sorted(fs))
    for q in files:
        if os.path.isfile(q) and not os.path.islink(q):
            text = read_regular(q, FILE_CAP, root=pr)
            if text is not None and REPO_TOKEN.search(text):
                return True
    return False


def local_path_ok(word):
    w = word.strip("'\"")
    if w.startswith("/"):
        return w == "/workspace" or w.startswith("/workspace/")
    return ".." not in w.split("/") and not w.startswith("~") and not w.startswith("$")


def pr_native_read(tool, field, val):
    if not REPO_PR_NATIVE[0]:
        return False
    if tool in ("Grep", "Read", "Glob"):
        target = val if field in PATH_FIELDS else None
        return target is None or local_path_ok(target)   # a pattern naming the token, or a local path
    if tool != "Bash":
        return False
    if any(REPO_TOKEN.search(body) for _i, body in interpreter_bodies(val)):
        return False
    flat = val.replace("\\\n", " ")
    stripped = strip_heredocs(flat)
    if not REPO_TOKEN.search(stripped) or len(REPO_TOKEN.findall(stripped)) != len(REPO_TOKEN.findall(flat)):
        return False   # a token in a heredoc body that is not a fixture quotation feeds a later command (AG-53)
    for seg, _sep in split_segments(stripped):
        if not REPO_TOKEN.search(seg):
            continue
        if EGRESS_HOST.search(seg) or EGRESS_URL.search(seg) or EGRESS_FETCH.search(seg):
            return False
        if re.search(r"(?<![0-9&])>(?!&|\s*/dev/null)", seg):   # an output redirection writes somewhere
            return False
        w = egress_words(seg)
        prog = w[0].rsplit("/", 1)[-1] if w else ""
        if prog not in PR_READ_TOOLS:
            return False
        if prog == "sed" and any(re.match(r"^-[A-Za-z]*i", x) or x.startswith("--in-place") for x in w[1:]):
            return False
        if prog == "find" and any(x in ("-exec", "-execdir", "-delete", "-ok", "-fprint", "-fprintf") for x in w[1:]):
            return False
        for x in w[1:]:
            if x.startswith("-") or REPO_TOKEN.search(x) or "/" not in x and not x.startswith("~"):
                continue
            if not local_path_ok(x):
                return False
    return True


# 1.4.0 (cycle-133 FR-8, SDD C-8, bd-kddde shape 1): class 7's PR-native exemption covers a report written by heredoc,
# as it already covers the Write tool (whose content is never scanned): with the token PR-native, a Bash value is exempt
# when every token occurrence sits in the body of a heredoc that cat or tee writes to a report file (.md, .markdown,
# .txt; a local path by local_path_ok, no $ or backtick in it), the heredoc is not piped on (<<'EOF' | bash) and not fed
# to an interpreter, an unquoted delimiter's body holds no $( or backtick (no command substitution runs), the writer
# takes no other argument (only >, >>, >|, 2>/dev/null, 2>&1, tee -a and tee's own targets; tee >/dev/null), and no
# logical line of the heredoc-stripped command could reach the network (executes_network: AG-53's
# `xargs … gh api` beside the write stays repo_name). Recorded as class repo_name_pr_native_report.
PR_NATIVE_REPORT_MARK = "\0pr-native-report"
REPORT_EXTS = (".md", ".markdown", ".txt")
REPORT_WRITERS = {"cat", "tee"}


def report_target_ok(t):
    return (bool(t) and "$" not in t and "`" not in t and local_path_ok(t)
            and t.lower().endswith(REPORT_EXTS) and not t.endswith("/"))


def heredoc_report_write(val):
    if not REPO_PR_NATIVE[0]:
        return False
    stripped = strip_heredocs(val)
    if REPO_TOKEN.search(stripped):
        return False   # a token outside every heredoc body is the read rule's (pr_native_read) or a hit
    if any(executes_network(line) for line in stripped.replace("\\\n", " ").split("\n")):
        return False
    if any(REPO_TOKEN.search(body) for _i, body in interpreter_bodies(val)):
        return False
    found = False
    for m in HEREDOC.finditer(val):
        body = val[m.end(4):m.end()]
        if not REPO_TOKEN.search(body):
            continue
        if not m.group(2) and ("$(" in body or "`" in body):
            return False   # an unquoted delimiter runs the body's command substitutions
        rest = m.group(4)
        if "|" in rest:
            return False   # piped on: the body feeds another program
        line = val[val.rfind("\n", 0, m.start()) + 1:m.start()]
        w = egress_words(re.split(r"[;&|({]", line)[-1] + " " + re.split(r"[;&]", rest)[0])
        prog = w[0].rsplit("/", 1)[-1] if w else ""
        if prog not in REPORT_WRITERS:
            return False
        targets, j = [], 1
        while j < len(w):
            x = w[j]
            if x in (">", ">>", ">|"):
                if j + 1 >= len(w):
                    return False
                targets.append(w[j + 1])
                j += 2
                continue
            r = re.match(r"^(?:>>|>\||>)(.+)$", x)
            if r:
                targets.append(r.group(1))
            elif x in ("2>/dev/null", "2>&1") or (prog == "tee" and x in ("-a", "--append")):
                pass
            elif prog == "tee" and not x.startswith("-"):
                targets.append(x)
            else:
                return False   # another file, an option, a here-string: not a plain report write
            j += 1
        if prog == "tee":
            targets = [x for x in targets if x != "/dev/null"]
        if not targets or not all(report_target_ok(x) for x in targets):
            return False
        found = True
    return found


# 1.4.0 (cycle-133 FR-8, SDD C-8, bd-kddde shape 2): in container mode a bare /home word (/home or /home/, unglobbed)
# that is the argument of a mount-metadata probe (findmnt, df, mountpoint) is not outside_path: the container's /home
# holds only /home/evaluser (an allowed root) and the probe prints mount options or usage, never contents. Every bare
# /home word of the value must be such an argument (ls /home, cd /home, H=/home stay outside_path); host mode is
# unchanged. Recorded in contamination_exempt as {phase, excerpt_id, pattern: outside_path, class: home_mount_probe}.
HOME_PROBE_MARK = "\0home-mount-probe"
HOME_BARE = ("/home", "/home/")
HOME_PROBE_TOOLS = {"findmnt", "df", "mountpoint"}


def home_mount_probe(body):
    n_all = sum(1 for m in ABS_WORD.finditer(body) if m.group(1) in HOME_BARE)
    if not n_all:
        return False
    n_probe = 0
    for seg, _sep in split_segments(body):
        w = egress_words(seg)
        n = sum(1 for x in w[1:] if x in HOME_BARE)
        if n and w[0].rsplit("/", 1)[-1] in HOME_PROBE_TOOLS:
            n_probe += n
    return n_probe == n_all


def transcripts(run_dir):
    d = os.path.join(run_dir, "transcripts")
    if not os.path.isdir(d):
        return []
    files = []
    for n in os.listdir(d):
        m = re.match(r"^events-(.+)\.jsonl$", n)
        p = os.path.join(d, n)
        if m and os.path.isfile(p) and not os.path.islink(p):
            files.append((m.group(1), p))
    rank = lambda lbl: (PHASE_ORDER.index(lbl) if lbl in PHASE_ORDER else len(PHASE_ORDER), lbl)
    return sorted(files, key=lambda x: rank(x[0]))


def tool_uses(ev):
    if not isinstance(ev, dict) or ev.get("type") != "assistant":
        return
    content = (ev.get("message") or {}).get("content") if isinstance(ev.get("message"), dict) else None
    for blk in content or []:
        if isinstance(blk, dict) and blk.get("type") == "tool_use" and isinstance(blk.get("input"), dict):
            yield blk.get("name") or "", blk["input"]


def contamination(run_dir):
    files = transcripts(run_dir)
    events, cwds = [], set()
    for label, p in files:
        rows = []
        for i, line in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if isinstance(ev, dict) and ev.get("type") == "system" and isinstance(ev.get("cwd"), str):
                if ev["cwd"].startswith("/"):
                    cwds.add(ev["cwd"])
            rows.append((i, ev))
        events.append((label, rows))
    roots = allowed_roots(run_dir, cwds)
    for label, rows in events:
        for i, ev in rows:
            for tool, inp in tool_uses(ev):
                for field in FIELDS.get(tool, []):
                    val = inp.get(field)
                    if isinstance(val, str) and val:
                        EXEMPT_BUF.clear()
                        hit = check_value(tool, field, val, roots)
                        for src, text in EXEMPT_BUF:
                            if src == PR_NATIVE_MARK:
                                rec = {"phase": label, "excerpt_id": f"{label}:{i}", "pattern": "repo_name",
                                       "class": "repo_name_pr_native"}
                            elif src == PR_NATIVE_REPORT_MARK:   # 1.4.0
                                rec = {"phase": label, "excerpt_id": f"{label}:{i}", "pattern": "repo_name",
                                       "class": "repo_name_pr_native_report"}
                            elif src == HOME_PROBE_MARK:   # 1.4.0
                                rec = {"phase": label, "excerpt_id": f"{label}:{i}", "pattern": "outside_path",
                                       "class": "home_mount_probe"}
                            else:
                                rec = {"phase": label, "excerpt_id": f"{label}:{i}", "pattern": "repo_name",
                                       "fixture_line": src, "line": text}
                            if rec not in CONTAM_EXEMPT:
                                CONTAM_EXEMPT.append(rec)
                        EXEMPT_BUF.clear()
                        if hit:
                            rec = {"phase": label, "pattern": hit, "excerpt_id": f"{label}:{i}"}
                            if hit == "network_egress" and EGRESS_DETAIL[0] is not None:
                                rec.update(EGRESS_DETAIL[0])   # round 10 telemetry: repo_named, host, url
                            return rec
    return None


# ------------------------------------------------------------------ KF-046 class 7 (1.3.0, D-3.2)
# A review-catch PR may itself carry the repository's name (a workflow's `if: github.repository ==
# '0xHoneyJar/loa'`); quoting that PR content is not a probe of the upstream repository. Each
# occurrence's unit is the backtick span holding it (`…`), else its whole line, stripped; an
# occurrence is exempt when its unit is a substring of one line of the task's PR fixture (head/**
# files or head.diff, the diff's +/-/space prefix dropped); a backslash-continued command is one logical line, and a
# bare token standing as the whole line (a for-list word, a list entry) exempts nothing (review r1 DISS-C-002). Every occurrence of a value must be exempt,
# else the value is a repo_name hit as before. Exempt values are recorded in contamination_exempt[]
# ({phase, excerpt_id, pattern, fixture_line: "head/<path>:<n>" | "head.diff:<n>", line: the fixture
# line, 200 characters at most}); build tasks have no PR fixture and no exemption.
FIXTURE_TASK = [None]
FIXTURE_LINES = []     # [(source, text)] fixture lines holding the token, loaded on first use
CONTAM_EXEMPT = []
EXEMPT_BUF = []
REPO_TOKEN = re.compile(r"0xhoneyjar/loa", re.I)


def fixture_token_lines():
    if FIXTURE_LINES:
        return FIXTURE_LINES[0]
    out = []
    t = FIXTURE_TASK[0]
    pr = None
    if t is not None:
        try:
            pr = resolve_pr_fixture(t)
        except GradeError:
            pr = None
    if pr:
        files = []
        hd = os.path.join(pr, "head.diff")
        if os.path.isfile(hd) and not os.path.islink(hd):
            files.append(("head.diff", hd, True))
        head = os.path.join(pr, "head")
        for r, ds, fs in os.walk(head):
            ds.sort()
            for n in sorted(fs):
                q = os.path.join(r, n)
                files.append(("head/" + os.path.relpath(q, head), q, False))
        for src, q, is_diff in files:
            text = read_regular(q, FILE_CAP, root=pr)
            if text is None or not REPO_TOKEN.search(text):
                continue
            for k, line in enumerate(text.split("\n"), 1):
                if REPO_TOKEN.search(line):
                    body = line[1:] if is_diff and line[:1] in "+- " else line
                    out.append((f"{src}:{k}", body.strip()))
    FIXTURE_LINES.append(out)
    return out


NET_EXE = {"git", "gh", "curl", "wget", "pip", "pip3", "npm", "npx", "pnpm", "yarn", "ssh", "scp", "sftp", "nc", "ncat",
           "telnet", "docker", "podman", "rsync", "svn", "hg", "aria2c", "http", "https", "fetch", "gem", "cargo", "go"}


def executes_network(line):
    """a Bash logical line that could reach the network or a VCS remote: a word whose basename is a network- or
    VCS-capable executable, or python/node/perl/ruby with an inline program (audit r1 DISS-C-001)"""
    words = re.findall(r"[A-Za-z0-9_./-]+", line)
    base = [w.rsplit("/", 1)[-1] for w in words]
    if any(b in NET_EXE for b in base):
        return True
    return any(b in ("python", "python3", "node", "perl", "ruby") and ("-c" in words or "-e" in words) for b in base)


def repo_name_exempt(val, tool=None):
    """→ [(fixture source, fixture line)] when every repo-name occurrence in val is PR content, else None.
    A Bash command is executed text: an occurrence on a logical line that could reach the network or a VCS remote
    is never exempt, whatever the fixture holds (pr-13 and pr-16 carry `curl … 0xHoneyJar/loa … | bash` lines)."""
    fl = fixture_token_lines()
    if not fl:
        return None
    if tool == "Bash":   # the executed text is the command with its heredoc bodies removed (a quoted line in notes is not run)
        for line in strip_heredocs(val).replace("\\\n", " ").split("\n"):
            if REPO_TOKEN.search(line) and executes_network(line):
                return None
    hits = []
    for line in val.replace("\\\n", " ").split("\n"):   # a backslash-continued command is one logical line
        for m in REPO_TOKEN.finditer(line):
            unit = None
            for span in re.finditer(r"`[^`\n]*`", line):
                if span.start() < m.start() and m.end() < span.end():
                    unit = span.group(0)[1:-1].strip()
                    break
            if unit is None:
                unit = line.strip()
                if len(unit) < len(m.group(0)) + 4:
                    return None       # a bare token as a whole (logical) line is a command word, not a quotation: it is a
                                      # substring of every fixture token line and exempts nothing (review r1 DISS-C-002)
            match = next(((src, text) for src, text in fl if unit and unit in text), None)
            if match is None:
                return None
            hits.append((match[0], match[1][:200]))
    return hits


# ------------------------------------------------------------------ label set (cycle-132 FR-2, D-2.3)
KEY_SETS = ("c131", "v1", "review")   # the label-set directories under manifests/ (round 3: DISS-C-005)


def label_set(t):
    """c131 | v1 | review | v2 from the key's directory: manifests/c131/<pr>.json (the frozen cycle-131 set),
    manifests/v1/<pr>.json (the original anchors), manifests/review/<pr>.json (the review-derived set of the
    newer fixtures), anything else the current (v2) key."""
    d = os.path.dirname(t.key_path)
    if os.path.basename(os.path.dirname(d)) == "manifests" and os.path.basename(d) in KEY_SETS:
        return os.path.basename(d)
    return "v2"


def key_set_root(t):
    """the manifests/ directory a key belongs to: a set key's parent (its v1 snapshot is manifests/v1/<pr>.json,
    the key itself for the v1 set, and the corpus SHA256SUMS sits above manifests/), else the key's own directory"""
    d = os.path.dirname(t.key_path)
    return os.path.dirname(d) if label_set(t) != "v2" else d


def labels_meta(t):
    """per defect, by position (grade.json never names a defect id): the key's provenance fields"""
    return [{"defect": f"d{i}", "label_source": d.get("label_source"), "agreement": d.get("agreement"),
             "review_driven": d.get("review_driven")}
            for i, d in enumerate(t.key.get("defects") or [], 1) if isinstance(d, dict)]


# ------------------------------------------------------------------ corpus digest (1.3.0)
def corpus_sha256(t):
    """sha256 of the review corpus's SHA256SUMS (the directory above the key's manifests/), null when absent"""
    import hashlib
    p = os.path.join(os.path.dirname(key_set_root(t)), "SHA256SUMS")
    try:   # one O_NOFOLLOW open, fstat regular + size bound, hash those bytes (audit r1 DISS-C-004)
        fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0))
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode) or st.st_size > READ_CAP:
            return None
        h = hashlib.sha256()
        while True:
            b = os.read(fd, 1 << 20)
            if not b:
                break
            h.update(b)
        return h.hexdigest()
    except OSError:
        return None
    finally:
        os.close(fd)


# ------------------------------------------------------------------ oracle detector (1.3.0, D-1.3, KF-049)
# Did a session read a LATER copy of a file the PR touched? Answer-bearing paths: the paths under .claude/
# named by the PR fixture's head.diff headers (`diff --git a/X b/Y` both names, quoted C-style names
# unquoted, `--- a/X`, `+++ b/Y`, `rename from|to X`; /dev/null and unsafe paths dropped) or present under
# its head/ or base/ tree. Over transcripts/events-{BARE,REVIEW,AUDIT}.jsonl each assistant tool_use is
# correlated with its tool_result by id. Paths are resolved against the session's cwd (the system init
# event's, default /workspace, which is also the workspace root), `cd DIR` segments, NAME=value
# assignments (H=pr/head) and `for V in w…; do` lists; a path inside the workspace and outside pr/ is a
# workspace operand, pr/head/X and pr/base/X are PR operands.
#   diff form — a Bash segment (split on newline, ; && || | & outside quotes and parentheses; heredoc bodies
#   removed first) whose executable is diff, sdiff or comm, or git with diff and --no-index, without -q
#   (alone or in a short-flag cluster), --brief or --quiet, holding a PR operand and a workspace operand that
#   names an answer path (or a directory above one); a head.diff operand is never a PR operand. Its result
#   is split into per-file sections at `diff `, `--- ` and `*** ` header lines (text no header attributes
#   goes to every target of the command); unified `@@ -a,b +c,d @@` and normal `NaM,b` / `N,Mc…` / `Nd…`
#   ranges are read (head side, below); a planted site of that file within ±3 of a range, or its must_match
#   text (stripped, first 50 characters, at least 12) in the section, marks the defect exposed (how diff);
#   a non-empty section that is not only error lines and yields neither ranges nor must_match marks every
#   other defect of that file exposed_unknown. Text no header attributes, in a command with several
#   targets, exposes a defect only with corroboration: a range near the site AND a line of the fixture's
#   head/X within ±3 of the site in that text, or must_match. A diff whose output is discarded or reduced
#   (>/dev/null, &>/dev/null, | wc, | grep with -c|-q|-l anywhere, | cmp; a stat-only git diff) and a tool_result
#   flagged is_error print no content; `2>&1`, `>&2`, `<&0` and `&>` are redirections, never separators.
#   read form — a Bash segment whose executable is cat, sed, awk, grep, head, tail, less or python3, or a
#   Read (file_path) / Grep (path) tool_use, naming a workspace answer path (a directory for grep or Grep
#   covers the answer paths below it), whose result contains a LATER-ONLY line within ±3 of a planted site
#   (when the tool_use reads several answer paths, on a result line that names the file's basename):
#   a line of the sandbox copy (sandbox/<X>, read bounded and symlink-refusing) present in neither the
#   fixture's head/X nor base/X, at least 8 characters stripped, mapped to head coordinates by difflib.
# Either form is skipped for a path whose sandbox copy byte-equals the fixture's head/X or base/X (a closed
# mount, in either overlay mode: a diff there prints the PR's own change, not a later one).
# Ranges are read on the head side only: planted sites are head coordinates, so the side of the pr/head
# operand (left when it precedes the workspace operand) is tested; a pr/base operand gives both sides.
# grade.json: oracle_exposed_defects (positions d1 … of defects exposed by diff or read),
# oracle_exposed_unknown (positions only exposed_unknown), oracle_exposed_events [{phase, event: the
# tool_use's line number in its events file, how: diff|read|exposed_unknown, path}] and
# oracle_exposed_by_form {diff: [positions], read: [positions]}; null for build tasks.
# A LOWER BOUND, like the contamination scan: a paraphrase, a copy made by a program and read later, or a
# path built at run time is not seen.
ORACLE_PHASES = ("BARE", "REVIEW", "AUDIT")
# bounds on agent-authored input (audit r1 DISS-C-003): every dimension the graded session controls is capped
FORLIST_CAP, EXPAND_CAP, SEG_CAP, WORD_CAP, WORDS_CAP, LINE_CAP, LINES_CAP, DIFF_LINES_CAP = 64, 256, 65536, 4096, 512, 4096, 20000, 20000
ORACLE_SKIPPED = []   # answer paths whose later-line map was skipped (a side over DIFF_LINES_CAP lines)
DIFF_EXE = {"diff", "sdiff", "comm"}
READ_EXE = {"cat", "sed", "awk", "grep", "head", "tail", "less", "python3"}
ANSWER_TOP = ".claude/"
SEG_KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "{", "(", "!", "time"}
PATHISH = re.compile(r"[A-Za-z0-9_./@%+,:=~$-]*[A-Za-z0-9_./@%+:~$-]")
HUNK_U = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", re.M)
HUNK_N = re.compile(r"^(\d+)(?:,(\d+))?([acd])(\d+)(?:,(\d+))?\s*$", re.M)
EXIT_CODE_LINE = re.compile(r"\AExit code \d+\n?")   # 1.3.1: Claude Code's preamble on a failed Bash tool result
ERR_LINE = re.compile(r"^(?:diff|sdiff|comm|git|cat|grep|sed|head|tail|awk|less):|^(?:fatal|error|warning):|"
                      r"No such file|Is a directory|hook error|BLOCKED|^\s*$|^\s*(?:rc|exit)\s*=\s*\d+\s*$")
DIFF_BODY = re.compile(r"^[<>+\- @\\0-9]|^---$")
FILEISH = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+|[A-Za-z0-9_-]+\.[A-Za-z0-9]{1,6}\b")
# a diff whose stdout is counted, tested or discarded prints no content: | wc, | grep -c/-q/-l, >/dev/null
DEVNULL = re.compile(r"(?:^|[\s;])(?:1?>|&>|>&)\s*/dev/null")
DIFF_STAT_FLAGS = {"--stat", "--numstat", "--shortstat", "--name-only", "--name-status", "--compact-summary"}


def silent_sink(w):
    """the piped-into command prints no diff content: wc, cmp, true/false/test, or grep with a counting /
    quiet / files-only flag anywhere among its words (review r1 DISS-C-001: `grep -i -c` counts too)"""
    if not w:
        return False
    exe = w[0].rsplit("/", 1)[-1]
    if exe in ("wc", "cmp", "true", "false", "test"):
        return True
    if exe in ("grep", "egrep", "fgrep", "rg"):
        return any(re.fullmatch(r"-[A-Za-z]*[cqlL][A-Za-z]*", x)
                   or x in ("--count", "--quiet", "--silent", "--files-with-matches", "--files-without-match")
                   for x in w[1:])
    return False


def unquote_c(q):
    """a git C-quoted path body (between the quotes) → text"""
    i, b = 0, bytearray()
    while i < len(q):
        ch = q[i]
        if ch == "\\" and i + 1 < len(q):
            n = q[i + 1]
            if n in "01234567" and re.match(r"[0-7]{3}", q[i + 1:i + 4]):
                b.append(int(q[i + 1:i + 4], 8))
                i += 4
                continue
            b.extend({"n": b"\n", "t": b"\t", '"': b'"', "\\": b"\\"}.get(n, n.encode()))
            i += 2
            continue
        b.extend(ch.encode())
        i += 1
    return b.decode("utf-8", "replace")


def answer_paths(pr):
    names = set()
    text = read_regular(os.path.join(pr, "head.diff"), 64 * 1024 * 1024, root=pr) or ""
    Q = r'"((?:[^"\\]|\\.)*)"'
    for line in text.split("\n"):
        if line.startswith("diff --git "):
            rest = line[len("diff --git "):]
            m = re.fullmatch(Q.replace("((", "a/((", 1) + " " + Q.replace("((", "b/((", 1), rest) or None
            if m:
                names.update(unquote_c(x) for x in m.groups())
                continue
            m = re.fullmatch(r"a/(\S+) b/(\S+)", rest)
            if m:
                names.update(m.groups())
                continue
            half = (len(rest) - 1) // 2   # unquoted names with spaces: "a/X b/X" with X twice
            if rest[:2] == "a/" and rest[half + 1:half + 3] == "b/" and rest[2:half] == rest[half + 3:]:
                names.add(rest[2:half])
        elif line.startswith(("--- ", "+++ ")):
            body = line[4:].split("\t", 1)[0]
            if body.startswith('"') and body.endswith('"'):
                body = unquote_c(body[1:-1])
            if body.startswith(("a/", "b/")):
                names.add(body[2:])
        elif line.startswith(("rename from ", "rename to ", "copy from ", "copy to ")):
            body = line.split(" ", 2)[2]
            names.add(unquote_c(body[1:-1]) if body.startswith('"') and body.endswith('"') else body)
    for side in ("head", "base"):
        root = os.path.join(pr, side)
        for r, ds, fs in os.walk(root):
            for n in fs:
                names.add(os.path.relpath(os.path.join(r, n), root).replace(os.sep, "/"))
    out = set()
    for n in names:
        parts = safe_rel(n)
        if parts and n != "/dev/null":
            rel = "/".join(parts)
            if rel.startswith(ANSWER_TOP):
                out.add(rel)
    return out


def split_segments(cmd):
    """[(segment, separator after it)]: split on newline ; & | (&& || included) outside quotes and
    parentheses; the separator is "|" for a pipe into the next segment, else ";" """
    segs, cur, q, depth, i = [], [], None, 0, 0
    while i < len(cmd):
        ch = cmd[i]
        if q == "'":
            cur.append(ch)
            if ch == "'":
                q = None
        elif q == '"':
            cur.append(ch)
            if ch == "\\" and i + 1 < len(cmd):
                cur.append(cmd[i + 1])
                i += 1
            elif ch == '"':
                q = None
        elif ch == "\\" and i + 1 < len(cmd):
            cur.append(ch + cmd[i + 1])
            i += 1
        elif ch in "'\"":
            q = ch
            cur.append(ch)
        elif ch == "(":
            depth += 1
            cur.append(ch)
        elif ch == ")":
            depth = max(0, depth - 1)
            cur.append(ch)
        elif depth == 0 and ch == "&" and (cmd[i - 1:i] in (">", "<") or cmd[i + 1:i + 2] == ">"):
            cur.append(ch)          # a redirection (2>&1, >&2, <&0, &>f), not a separator (review r1 DISS-001/C-001)
        elif depth == 0 and ch in "\n;&|":
            pipe = ch == "|" and cmd[i + 1:i + 2] != "|" and cmd[i - 1:i] != "|"
            if ch == "|" and cmd[i + 1:i + 2] == "&":
                pipe = True           # `|&` is bash's `2>&1 |`: one pipe, no empty segment (review r2 DISS-C-004)
                i += 1
            segs.append(("".join(cur), "|" if pipe else ";"))
            cur = []
        else:
            cur.append(ch)
        i += 1
    segs.append(("".join(cur), ";"))
    return [(x.strip(), sep) for x, sep in segs if x.strip()]


def seg_words(seg):
    try:
        w = shlex.split(seg, comments=False, posix=True)
    except ValueError:
        w = seg.split()
    while w and (w[0] in SEG_KEYWORDS):
        w = w[1:]
    while w and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w[0]) and len(w) > 1:
        w = w[1:]
    while w and w[0] in ("command", "env", "builtin", "exec", "nice"):
        w = w[1:]
    if w and w[0] == "timeout":
        w = w[1:]
        while w and (w[0].startswith("-") or re.match(r"^\d+[smhd]?$", w[0])):
            w = w[1:]
    return w


def expand(tok, vars_):
    """$NAME / ${NAME} expansion → list of strings (a loop variable expands to every word); an unknown
    variable leaves the token unresolved (dropped)"""
    outs = [tok]
    for _ in range(4):
        nxt, changed = [], False
        for o in outs:
            m = re.search(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)", o)
            if not m:
                nxt.append(o)
                continue
            name = m.group(1) or m.group(2)
            if name not in vars_:
                continue
            changed = True
            for v in vars_[name]:
                nxt.append(o[:m.start()] + v + o[m.end():])
            if len(nxt) > EXPAND_CAP:
                return []             # a for-list product past the cap resolves nothing (audit r1 DISS-C-003)
        outs = nxt
        if not changed:
            break
    return [o for o in outs if "$" not in o]


def classify(tok, cwd, ws):
    """→ ("pr", side, rel) | ("ws", rel) | None"""
    tok = tok.strip("'\"")
    if not tok or tok.startswith("-") or "://" in tok:
        return None
    if tok.startswith("~") or "*" in tok or "?" in tok:
        return None
    full = os.path.normpath(tok if tok.startswith("/") else os.path.join(cwd, tok))
    if full != ws and not full.startswith(ws.rstrip("/") + "/"):
        return None
    rel = "" if full == ws else full[len(ws.rstrip("/")) + 1:]
    if rel == "pr" or rel.startswith("pr/"):
        rest = rel[3:]
        for side in ("head", "base"):
            if rest == side or rest.startswith(side + "/"):
                return ("pr", side, rest[len(side) + 1:])
        return ("pr", None, rest)
    return ("ws", rel)


def ws_targets(rel, answer, directory_ok):
    if rel in answer:
        return [rel]
    if not directory_ok:
        return []
    pre = "" if rel in ("", ".") else rel.rstrip("/") + "/"
    return sorted(a for a in answer if a.startswith(pre))


def segment_tokens(seg, vars_, cwd, ws):
    """every path-shaped token of a segment (inside process substitutions too), expanded and classified;
    bounded against agent-authored bulk (audit r1 DISS-C-003): a segment over SEG_CAP bytes, a word over
    WORD_CAP characters or past the WORDS_CAP-th word is not read"""
    out = []
    if len(seg) > SEG_CAP:
        return out
    for word in seg.split()[:WORDS_CAP]:
        if len(word) > WORD_CAP:
            continue
        for m in PATHISH.finditer(word):
            for v in expand(m.group(0), vars_):
                c = classify(v, cwd, ws)
                if c is not None:
                    out.append((v, c))
    return out


def result_text(blk):
    c = blk.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict) and isinstance(x.get("text"), str))
    return ""


def ranges_of(text, sides=("left", "right")):
    """the printed line ranges of a unified or normal diff on the given sides (left = first operand)"""
    rs = []
    for m in HUNK_U.finditer(text):
        a, n = int(m.group(1)), int(m.group(2) or 1)
        c, k = int(m.group(3)), int(m.group(4) or 1)
        if "left" in sides:
            rs.append((a, a + max(n, 1) - 1))
        if "right" in sides:
            rs.append((c, c + max(k, 1) - 1))
    for m in HUNK_N.finditer(text):
        a = int(m.group(1))
        c = int(m.group(4))
        if "left" in sides:
            rs.append((a, int(m.group(2) or a)))
        if "right" in sides:
            rs.append((c, int(m.group(5) or c)))
    return rs


def sections(text, targets):
    """{target: [section body]}: the result split at header lines — a diff header (diff, ---, +++, ***) or
    a line that is not diff body and names a file (an `echo "=== $f"` marker); a header naming a target
    (the longest one it holds) opens that target's section, any other header a dropped one; text before
    the first header belongs to the sole target. Text no header attributes (several targets) is returned
    as the loose list. Header lines are not part of a body. → (sections, loose)"""
    out = {f: [] for f in targets}
    loose = []
    cur = targets[0] if len(targets) == 1 else None
    buf = []

    def flush():
        if buf:
            (out[cur] if cur is not None else loose).append("\n".join(buf))

    for line in text.split("\n"):
        diff_hdr = line.startswith(("diff ", "--- ", "*** ", "+++ "))
        if diff_hdr or (not DIFF_BODY.match(line) and FILEISH.search(line)):
            named = sorted((f for f in targets if f in line), key=len, reverse=True)
            hit = named[0] if named else None
            if line.startswith("+++ ") and hit == cur:
                continue
            if hit is not None or diff_hdr or len(targets) > 1:
                flush()
                buf = []
                cur = hit
                continue
        buf.append(line)
    flush()
    return out, loose


def oracle_scan(t, run_dir):
    try:
        pr = resolve_pr_fixture(t)
    except GradeError:
        return [], [], [], {"diff": [], "read": []}
    answer = answer_paths(pr)
    defects = t.key.get("defects") or []
    by_file = {}
    for i, d in enumerate(defects, 1):
        f = d.get("file")
        if isinstance(f, str) and f in answer:
            sites = [s for s in (d.get("anchors") or [d.get("anchor_line")]) if isinstance(s, int) and not isinstance(s, bool)]
            mm = (d.get("must_match") or "").strip()[:50] if isinstance(d.get("must_match"), str) else ""
            by_file.setdefault(f, []).append((f"d{i}", sites, mm if len(mm) >= 12 else ""))
    if not by_file:
        return [], [], [], {"diff": [], "read": []}
    sb = os.path.join(run_dir, "sandbox")
    later, live, near_text = {}, {}, {}
    for f in by_file:
        cur = read_regular(os.path.join(sb, *f.split("/")), FILE_CAP, root=sb)
        hd = read_regular(os.path.join(pr, "head", *f.split("/")), FILE_CAP, root=pr)
        bs = read_regular(os.path.join(pr, "base", *f.split("/")), FILE_CAP, root=pr)
        live[f] = cur is not None and cur != hd and cur != bs
        later[f] = []
        if not live[f] or hd is None:
            continue
        hl, cl = hd.split("\n"), cur.split("\n")
        if len(hl) > DIFF_LINES_CAP or len(cl) > DIFF_LINES_CAP:
            ORACLE_SKIPPED.append(f)  # no later-line map for a huge copy: the read form cannot fire for it (audit r1 DISS-C-003)
            continue
        for pos, sites, _mm in by_file[f]:
            near_text[(f, pos)] = [hl[L - 1].strip() for s_ in sites for L in range(s_ - 3, s_ + 4)
                                   if 1 <= L <= len(hl) and len(hl[L - 1].strip()) >= 8]
        known = set(x.strip() for x in hl) | (set(x.strip() for x in bs.split("\n")) if bs is not None else set())
        for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, hl, cl, autojunk=False).get_opcodes():
            if tag == "equal":
                continue
            lo, hi = i1 + 1, max(i2, i1 + 1)
            for j in range(j1, j2):
                txt = cl[j].strip()
                if len(txt) >= 8 and txt not in known:
                    later[f].append((txt, lo, hi))
    exposed, unknown, events, by_form = {}, {}, [], {"diff": set(), "read": set()}

    def note(phase, ev, how, path, pos):
        rec = {"phase": phase, "event": ev, "how": how, "path": path}
        if rec not in events:
            events.append(rec)
        (exposed if how != "exposed_unknown" else unknown).setdefault(pos, True)
        if how in by_form:
            by_form[how].add(pos)

    def near(sites, lo, hi):
        return any(not (hi < s - 3 or lo > s + 3) for s in sites)

    for label, path in transcripts(run_dir):
        if label not in ORACLE_PHASES:
            continue
        ws, uses = "/workspace", {}
        for i, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if not isinstance(ev, dict):
                continue
            if ev.get("type") == "system" and isinstance(ev.get("cwd"), str) and ev["cwd"].startswith("/"):
                ws = os.path.normpath(ev["cwd"])
                continue
            content = (ev.get("message") or {}).get("content") if isinstance(ev.get("message"), dict) else None
            if not isinstance(content, list):
                continue
            for blk in content:
                if not isinstance(blk, dict):
                    continue
                if ev.get("type") == "assistant" and blk.get("type") == "tool_use" and isinstance(blk.get("input"), dict):
                    plan = oracle_plan(blk.get("name") or "", blk["input"], ws, answer)
                    if plan and isinstance(blk.get("id"), str):
                        uses[blk["id"]] = (i, plan)
                elif ev.get("type") == "user" and blk.get("type") == "tool_result" and blk.get("tool_use_id") in uses:
                    i0, plan = uses.pop(blk["tool_use_id"])
                    # 1.3.1 (PR #1286 F002): a failed tool (diff exits 1 on differences, a refusal, a hook block) still
                    # carries its output after an "Exit code N" line; scan it, but no unknown and no must_match-only
                    # credit from it — a refusal names the command's paths without printing a diff
                    errored = blk.get("is_error") is True
                    res = result_text(blk)
                    if errored:
                        res = EXIT_CODE_LINE.sub("", res, count=1)
                    res = "\n".join(l[:LINE_CAP] for l in res.split("\n")[:LINES_CAP])
                    dtargets = sorted({f for how, f in plan if how.startswith("diff") and live.get(f)})
                    rtargets = sorted({f for how, f in plan if how == "read" and live.get(f)})
                    if dtargets and res.strip():
                        secs_by, loose = sections(res, dtargets)
                        # loose text (several targets, no naming header): a range near the site counts only
                        # with the head file's own text near that site in the same text, or must_match
                        for sec in loose:
                            for f in dtargets:
                                rs = ranges_of(sec, plan_sides(plan, f))
                                for pos, sites, mm in by_file.get(f, []):
                                    ranged = any(near(sites, lo, hi) for lo, hi in rs)
                                    own = any(x in sec for x in near_text.get((f, pos), []))
                                    if (ranged and own) or (not errored and mm and mm in sec):
                                        note(label, i0, "diff", f, pos)
                        for f, secs in secs_by.items():
                            for sec in secs:
                                body = [l for l in sec.split("\n") if not ERR_LINE.search(l)]
                                if not body:
                                    continue
                                rs = ranges_of(sec, plan_sides(plan, f))
                                hit_any = False
                                for pos, sites, mm in by_file.get(f, []):
                                    if any(near(sites, lo, hi) for lo, hi in rs) or (not errored and mm and mm in sec):
                                        note(label, i0, "diff", f, pos)
                                        hit_any = True
                                if not rs and not hit_any and not errored:
                                    for pos, _s, _m in by_file.get(f, []):
                                        note(label, i0, "exposed_unknown", f, pos)
                    single = len({f for how, f in plan if how == "read"}) == 1
                    for f in rtargets:
                        base = f.rsplit("/", 1)[-1]
                        lines = [l for l in res.split("\n") if single or base in l]
                        for pos, sites, _mm in by_file.get(f, []):
                            if any(near(sites, lo, hi) and any(txt in l for l in lines) for txt, lo, hi in later[f]):
                                note(label, i0, "read", f, pos)
    order = {f"d{i}": i for i in range(1, len(defects) + 1)}
    ex = sorted(exposed, key=order.get)
    unk = sorted((p for p in unknown if p not in exposed), key=order.get)
    events.sort(key=lambda e: (ORACLE_PHASES.index(e["phase"]), e["event"], e["how"], e["path"]))
    return ex, unk, events, {k: sorted(v, key=order.get) for k, v in by_form.items()}


def oracle_plan(tool, inp, ws, answer):
    """[(how, answer path)] a tool_use could expose: diff or read; [] when it names no answer path"""
    out = []
    if tool in ("Read", "Grep"):
        v = inp.get("file_path") if tool == "Read" else inp.get("path")
        if isinstance(v, str) and v:
            c = classify(v, ws, ws)
            if c and c[0] == "ws":
                out += [("read", f) for f in ws_targets(c[1], answer, tool == "Grep")]
        return out
    if tool != "Bash" or not isinstance(inp.get("command"), str):
        return out
    cmd = strip_heredocs(inp["command"])
    cwd, vars_ = ws, {}
    segs = split_segments(cmd)
    for k, (seg, sep) in enumerate(segs):
        w = seg_words(seg)
        raw = seg.split()
        # bookkeeping: assignments, cd, for-lists
        if raw and all(re.match(r"^(?:export\s+)?[A-Za-z_][A-Za-z0-9_]*=", x) or x == "export" for x in raw):
            for x in raw:
                m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", x)
                if m:
                    vals = expand(m.group(2).strip("'\""), vars_)
                    if vals:
                        vars_[m.group(1)] = vals[:1]
            continue
        m = re.match(r"^for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\s+(.*)$", seg)
        if m:
            words = []
            for x in m.group(2).split():
                words += expand(x.strip("'\""), vars_)
            vars_[m.group(1)] = words[:FORLIST_CAP]
            continue
        if not w:
            continue
        exe = w[0].rsplit("/", 1)[-1]
        if exe == "cd" and len(w) >= 2:
            vals = expand(w[1], vars_)
            if vals:
                cwd = os.path.normpath(vals[0] if vals[0].startswith("/") else os.path.join(cwd, vals[0]))
            continue
        is_diff = exe in DIFF_EXE or (exe == "git" and "diff" in w and "--no-index" in w)
        if is_diff:
            if any(re.fullmatch(r"-[A-Za-z]*q[A-Za-z]*", x) or x in ("--brief", "--quiet") for x in w[1:]):
                continue
            nxt = seg_words(segs[k + 1][0]) if sep == "|" and k + 1 < len(segs) else []
            if DEVNULL.search(seg) or (nxt and silent_sink(nxt)):
                continue
            if exe == "git" and any(x in DIFF_STAT_FLAGS for x in w) and not any(x in ("-p", "-u", "--patch", "--unified") or re.fullmatch(r"-U\d*|--unified=\d+", x) for x in w[1:]):
                continue              # a stat-only git diff prints names and counts, not content (with -p/-u/--patch it prints both; review r2 DISS-002)
            toks = segment_tokens(seg, vars_, cwd, ws)
            pr_ops = [k_ for k_, (v, c) in enumerate(toks) if c[0] == "pr" and c[1] in ("head", "base")
                      and not v.endswith("head.diff")]
            ws_ops = [k_ for k_, (v, c) in enumerate(toks) if c[0] == "ws" and not v.endswith("head.diff")
                      and ws_targets(c[1], answer, True)]
            targets = [f for k_ in ws_ops for f in ws_targets(toks[k_][1][1], answer, True)]
            if pr_ops and targets:
                # planted sites are head coordinates: the head side is the pr/head operand's (left when it
                # comes first); a pr/base operand gives no head coordinates, so both sides are read
                heads = [k_ for k_ in pr_ops if toks[k_][1][1] == "head"]
                side = ("left" if heads[0] < ws_ops[0] else "right") if heads else "both"
                out += [("diff:" + side, f) for f in targets]
        elif exe in READ_EXE:
            for v, c in segment_tokens(seg, vars_, cwd, ws):
                if c[0] == "ws":
                    out += [("read", f) for f in ws_targets(c[1], answer, exe == "grep")]
    return sorted(set(out))


def plan_sides(plan, f):
    sides = set()
    for how, g in plan:
        if g == f and how.startswith("diff:"):
            sides |= {"left", "right"} if how == "diff:both" else {how[5:]}
    return tuple(sorted(sides))


# ------------------------------------------------------------------ the grade
def fresh_dir(p):
    if os.path.lexists(p):
        remove_path(p)
    os.makedirs(p)


def grade(t, run_dir, frozen):
    run_dir = os.path.abspath(run_dir)
    sb = os.path.join(run_dir, "sandbox")
    if not os.path.isdir(sb) or os.path.islink(sb):
        raise GradeError(f"no sandbox/ under {run_dir}")
    if ":" in run_dir or "," in run_dir:
        raise GradeError("the run directory path must not contain ':' or ','")
    grading = os.path.join(run_dir, "grading")
    fresh_dir(grading)
    a2a = os.path.join(sb, "grimoires", "loa", "a2a", SPRINT)
    v_review = gate_verdict(os.path.join(a2a, "engineer-feedback.md"), sb)
    v_audit = gate_verdict(os.path.join(a2a, "auditor-sprint-feedback.md"), sb)
    if v_audit is not None:
        verdict = {"source_file": "auditor-sprint-feedback.md", "value": v_audit}
    elif v_review is not None:
        verdict = {"source_file": "engineer-feedback.md", "value": v_review}
    else:
        rv = review_md_verdict(os.path.join(sb, "review.md"), sb)
        verdict = {"source_file": "review.md", "value": rv} if rv else None
    g = {"schema_version": 1, "grader_version": GRADER_VERSION, "task_id": t.id, "task_type": t.type,
         "suite_frozen": frozen, "executor_mode": A.executor,
         "image": A.image if A.executor == "container" else None, "snapshots_graded": [],
         "hidden_tests": None, "structural": None, "regressions": None, "snapshot_tests": None,
         "recall": None, "false_positives": None, "verdict": verdict,
         "verdicts": {"review": v_review, "audit": v_audit},
         "verdict_accuracy": None, "verdict_accuracy_per_gate": {"review": None, "audit": None},
         "diff_lines": None, "files_changed": None, "symlinks_dropped": 0, "harness_files_removed": 0,
         "oversized_files_skipped": 0, "history_probes": 0, "heredoc_interpreters": 0, "contaminated": None,
         "contamination_exempt": [], "oracle_exposed_defects": None, "oracle_exposed_unknown": None,
         "oracle_exposed_events": None, "oracle_exposed_by_form": None, "oracle_scan_skipped": None, "corpus_sha256": None}
    acc = {"review": None, "audit": None}
    SNAPSHOT_LINKS_DROPPED[0] = 0
    OVERSIZED[0] = 0
    COLLIDING[0] = 0
    HISTORY_PROBES[0] = 0
    HEREDOC_INTERP[0] = 0
    RUN_TAG[0] = re.sub(r"[^A-Za-z0-9._-]", "-", os.path.basename(run_dir))[:40] or "run"
    GRADER_SOURCES.clear()
    if t.build:
        for rel in t.protected:
            src = os.path.join(t.fixture, *rel.split("/"))
            if os.path.isfile(src) and not os.path.islink(src):
                GRADER_SOURCES[rel] = src
        GRADER_SOURCES.update({d: f for _s, d, f in t.overlay if os.path.isfile(f)})
        docker_ready()
        final = os.path.join(grading, "final")
        g["symlinks_dropped"] = copy_tree(sb, final, EXCLUDE_TOP)
        g["diff_lines"], g["files_changed"] = churn(t.fixture, final)
        removed = prepare(t, final)
        g["snapshots_graded"].append("final")
        # refactor (DEC-0401, AC-5.3; Sprint 259 MEDIUM-1): the structural check is the
        # hidden assertion and the fixture suite (test_command) the regression check
        refactor = t.type == "refactor"
        if refactor:
            hcmd, hstatic, rcmd = structural_command(t), t.structural_cases, t.test_command
        else:
            hcmd, hstatic, rcmd = t.test_command, t.static_cases, t.regression_command
        res = run_suite(final, hcmd, hstatic)
        g["hidden_tests"] = summary(res)
        rb = rf = None
        if rcmd is not None:
            base_tree = os.path.join(grading, "base")
            copy_tree(t.fixture, base_tree)
            removed += prepare(t, base_tree)
            rb = run_suite(base_tree, rcmd)
            rf = run_suite(final, rcmd)
            g["regressions"] = regressions(rb, rf)
        if refactor:
            st = summary(res)
            st.pop("timed_out")
            st.pop("rc")
            st.pop("output_truncated")
            st.update(suite_green_base=all_pass(rb), suite_green_final=all_pass(rf))
            g["structural"] = st
        idx = read_json(os.path.join(run_dir, "snapshots", "index.json"))
        idx = idx if isinstance(idx, dict) else {}
        gates = {}
        if v_review is not None:
            gates["review"] = "implement"
        if v_audit is not None:
            gates["audit"] = "fix1" if idx.get("fix1") else "implement"
        snap_res = {}
        for label in ("implement", "fix1"):
            if label not in gates.values():
                continue
            tree = os.path.join(grading, label)
            if not extract_snapshot(run_dir, label, idx.get(label), tree):
                continue
            removed += prepare(t, tree)
            sr = run_suite(tree, hcmd, hstatic)
            ok = all_pass(sr)
            if refactor:   # the gate read a tree that must keep the suite green too
                ok = ok and all_pass(run_suite(tree, t.test_command))
            snap_res[label] = (sr, ok)
            g["snapshots_graded"].append(label)
        g["symlinks_dropped"] += SNAPSHOT_LINKS_DROPPED[0]
        g["harness_files_removed"] = removed
        if snap_res:
            g["snapshot_tests"] = {k: {"passed": v["passed"], "total": v["total"]} for k, (v, _ok) in snap_res.items()}
        for gate, v in (("review", v_review), ("audit", v_audit)):
            if v is None or gates.get(gate) not in snap_res:
                continue
            ok = snap_res[gates[gate]][1]
            acc[gate] = (v == "APPROVED" and ok) or (v == "CHANGES_REQUIRED" and not ok)
    else:
        if os.path.isdir(os.path.join(sb, "pr")) and not os.path.islink(os.path.join(sb, "pr")):
            g["symlinks_dropped"] = copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
        g["recall"], g["false_positives"], mc = grade_recall(t, run_dir, grading)
        g["false_positive_rule"], g["multi_credit_citations"] = "pm3", mc   # 1.3.2: bd-9zmfn, SKP-022
        if JUDGE[0] is not None:   # 1.5.0: only with --judge-verdicts (without it the grade is 1.4.0's, grader_version aside)
            g.update(judge_fields(t, combined_findings(run_dir), g["recall"]))
        g["corpus_sha256"] = corpus_sha256(t)
        ORACLE_SKIPPED.clear()
        (g["oracle_exposed_defects"], g["oracle_exposed_unknown"], g["oracle_exposed_events"],
         g["oracle_exposed_by_form"]) = oracle_scan(t, run_dir)
        g["oracle_scan_skipped"] = sorted(set(ORACLE_SKIPPED))
        key_cr = any((d.get("severity") or "").lower() in ("high", "critical") for d in t.key.get("defects") or [])
        for gate, v in (("review", v_review), ("audit", v_audit)):
            if v is not None:
                acc[gate] = (v == "CHANGES_REQUIRED") == key_cr and v in ("APPROVED", "CHANGES_REQUIRED")
    g["oversized_files_skipped"] = OVERSIZED[0]
    g["colliding_tests_removed"] = COLLIDING[0]
    g.setdefault("false_positive_rule", None); g.setdefault("multi_credit_citations", None)   # 1.3.2: build tasks
    g["collision_rule"] = collision_rule(t) if t.build else None
    g["verdict_accuracy_per_gate"] = acc
    g["verdict_accuracy"] = acc["audit"] if acc["audit"] is not None else acc["review"]
    # cycle-132 FR-2 (D-2.3): the key's label set and per-defect provenance; null for build tasks
    g["label_set"] = label_set(t) if t.rc else None
    g["labels_meta"] = labels_meta(t) if t.rc else None
    FIXTURE_TASK[0] = t if not t.build else None
    FIXTURE_LINES.clear()
    CONTAM_EXEMPT.clear()
    HIDDEN_CLASS[0] = bool(t.build)   # 1.3.6/1.3.7: build tasks only (their sandbox is graded against hidden/ tests and a suite root)
    REPO_PR_NATIVE[0] = repo_token_pr_native(t)   # 1.3.8: class 7's PR-native exemption needs the token in the PR
    g["contaminated"] = contamination(run_dir)
    g["contamination_classes_skipped"] = [] if t.build else list(BUILD_ONLY_CLASSES)
    g["repo_token_pr_native"] = REPO_PR_NATIVE[0]
    g["contamination_exempt"] = list(CONTAM_EXEMPT)
    g["history_probes"] = HISTORY_PROBES[0]
    g["heredoc_interpreters"] = HEREDOC_INTERP[0]
    return g


# ------------------------------------------------------------------ union (1.3.2, cycle-132 FR-3, SDD D-3.1, D-7.3)
def pos_list(v):
    return [x for x in v if isinstance(x, str) and re.fullmatch(r"d[1-9][0-9]*", x)] if isinstance(v, list) else None


def detected_of(rc, key):
    """the defect positions a session caught under the rule of recall[key] (missed / missed_pm3)"""
    n, missed = rc.get("defects_seeded"), pos_list(rc.get(key))
    if not isinstance(n, int) or isinstance(n, bool) or missed is None:
        return None
    return [f"d{i}" for i in range(1, n + 1) if f"d{i}" not in missed]


def pos_union(lists):
    vals = [v for v in lists if isinstance(v, list)]
    if not vals:
        return None
    return sorted({x for v in vals for x in v}, key=lambda x: (len(x), x))


def grade_union(t, cell, frozen):
    """A matched cell: k sessions, each graded on its own (DEC-0413 invariants per session); the union reads only the
    sessions the cell record (cell.json) marks valid — their grading/gates-combined.md and grade.json — never a
    sandbox, a transcript or a session's runner files. cell.json is the runner's record of the cell (k, session ids, status,
    validity, cost) and names no arm, so the grader stays blind to the arm."""
    cell = os.path.abspath(cell)
    if ":" in cell or "," in cell:
        raise GradeError("the cell directory path must not contain ':' or ','")
    text = read_regular(os.path.join(cell, "meta", "cell.json"), READ_CAP, whole=True, root=cell)
    try:
        cj = json.loads(text) if text is not None else None
    except ValueError:
        cj = None
    if not isinstance(cj, dict):
        raise GradeError(f"no readable cell.json under {cell}")
    k, sess = cj.get("k"), cj.get("sessions")
    if not isinstance(k, int) or isinstance(k, bool) or k < 1 or not isinstance(sess, list):
        raise GradeError("cell.json has no integer k >= 1 and sessions list")
    if len(sess) != k or [s.get("id") if isinstance(s, dict) else None for s in sess] != [f"s{i}" for i in range(1, k + 1)]:
        raise GradeError(f"cell.json lists sessions that are not s1 … s{k} (k {k})")
    sroot = os.path.join(cell, "sessions")
    if any(not os.path.isdir(os.path.join(sroot, f"s{i}")) for i in range(1, k + 1)) or os.path.lexists(os.path.join(sroot, f"s{k + 1}")):
        raise GradeError(f"the session directories under sessions/ do not match k {k} of cell.json")
    grading = os.path.join(cell, "grading")
    fresh_dir(grading)
    parts, cites, seen, per, grades = [], [], set(), [], {}
    for s in sess:
        sid, valid = s["id"], s.get("valid") is True
        entry = {"session": sid, "status": s.get("status"), "valid": valid,
                 "cost_usd": s.get("cost_usd") if isinstance(s.get("cost_usd"), (int, float)) and not isinstance(s.get("cost_usd"), bool) else None,
                 "recall": None, "recall_pm3": None, "detected": None, "detected_pm3": None, "false_positives": None,
                 "verdict": None, "grader_version": None}
        if valid:
            rd = s.get("run_dir")
            rdp = os.path.realpath(os.path.join(cell, rd)) if isinstance(rd, str) and rd else ""
            if not (rdp.startswith(os.path.realpath(sroot) + os.sep) and os.path.isdir(rdp)):
                raise GradeError(f"session {sid}: run_dir is not a directory under sessions/")
            gtext = read_regular(os.path.join(rdp, "grade.json"), READ_CAP, whole=True, root=rdp)
            ctext = read_regular(os.path.join(rdp, "grading", "gates-combined.md"), READ_CAP, whole=True, root=rdp)
            try:
                sg = json.loads(gtext) if gtext is not None else None
            except ValueError:
                sg = None
            if not isinstance(sg, dict) or not isinstance(sg.get("recall"), dict) or ctext is None:
                raise GradeError(f"session {sid} is marked valid but has no grade (grade.json with recall, grading/gates-combined.md)")
            if sg.get("contaminated") is not None:
                raise GradeError(f"session {sid} is marked valid but its grade is contaminated")
            if sg.get("grader_version") != GRADER_VERSION:   # 1.3.5 (audit A4): one grader across the union
                raise GradeError(f"session {sid} was graded by grader {sg.get('grader_version')!r}, not {GRADER_VERSION} "
                                 "(re-grade the session before the union)")
            grades[sid] = sg
            rc = sg["recall"]
            entry.update(recall=rc.get("recall"), recall_pm3=rc.get("recall_pm3"), detected=detected_of(rc, "missed"),
                         detected_pm3=detected_of(rc, "missed_pm3"), false_positives=sg.get("false_positives"),
                         verdict=(sg.get("verdict") or {}).get("value") if isinstance(sg.get("verdict"), dict) else None,
                         grader_version=sg.get("grader_version"))
            parts.append(f"## session {sid}\n" + ctext + ("" if ctext.endswith("\n") or not ctext else "\n"))
            for c in citations(ctext):
                if c not in seen:
                    seen.add(c)
                    cites.append(c)
        per.append(entry)
    valid_ids = [s["id"] for s in sess if s.get("valid") is True]
    g = {"schema_version": 1, "grader_version": GRADER_VERSION, "task_id": t.id, "task_type": t.type,
         "suite_frozen": frozen, "union": True, "bare_sessions": k, "sessions_valid": len(valid_ids),
         "sessions_graded": valid_ids, "hidden_tests": None, "structural": None, "regressions": None,
         "snapshot_tests": None, "recall": None, "false_positives": None, "false_positive_rule": "pm3",
         "multi_credit_citations": None, "verdict": None, "verdicts": {"review": None, "audit": None},
         "verdict_accuracy": None, "verdict_accuracy_per_gate": {"review": None, "audit": None},
         "diff_lines": None, "files_changed": None, "contaminated": None, "contamination_exempt": [],
         "contamination_classes_skipped": list(BUILD_ONLY_CLASSES),
         "oracle_exposed_defects": pos_union([grades[i].get("oracle_exposed_defects") for i in valid_ids]),
         "oracle_exposed_unknown": pos_union([grades[i].get("oracle_exposed_unknown") for i in valid_ids]),
         "corpus_sha256": corpus_sha256(t)}
    if valid_ids:
        g["recall"], g["false_positives"], g["multi_credit_citations"] = score_recall(t, grading, cites, "".join(parts))
        if JUDGE[0] is not None:   # 1.5.0: the union's credited pairs (its citations), bound like a run's
            g.update(judge_fields(t, cites, g["recall"]))
        first = grades[valid_ids[0]]
        for key in ("label_set", "labels_meta"):   # the task's label set (implementer B's fields), one per task
            if key in first:
                g[key] = first[key]
    else:
        with open(os.path.join(grading, "gates-combined.md"), "w", encoding="utf-8") as f:
            f.write("")
    g["per_session"] = per
    s1 = per[0]
    g["recall_session1"] = s1["recall"] if s1["valid"] else None
    g["recall_pm3_session1"] = s1["recall_pm3"] if s1["valid"] else None
    prec = None
    if s1["valid"] and isinstance(s1["detected_pm3"], list) and isinstance(s1["false_positives"], int):
        den = len(s1["detected_pm3"]) + s1["false_positives"]
        prec = round(len(s1["detected_pm3"]) / den, 4) if den > 0 else None
    g["precision_session1"] = prec
    return g


def structural_command(t):
    dest = t.structural
    if dest.endswith(".bats"):
        return ["bats", dest]
    if dest.endswith(".py"):
        return ["python3", "-m", "pytest", "-q", dest]
    return [t.test_command[0], dest]


def write_grade(g, out):
    text = json.dumps(g, indent=2) + "\n"
    d = os.path.dirname(os.path.abspath(out))
    os.makedirs(d, exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, out)
    return text


# ------------------------------------------------------------------ self-check
def synth_run(t, mode, root):
    rd = os.path.join(root, f"run-{mode}")
    sb = os.path.join(rd, "sandbox")
    os.makedirs(sb)
    if t.build:
        copy_tree(t.fixture, sb)
        if mode == "reference":
            if not t.reference_patch or not os.path.isfile(t.reference_patch):
                raise GradeError("self-check reference needs hidden/reference.patch (task.yaml reference_patch)")
            p = subprocess.run(["patch", "-p1", "--batch", "--forward", "--no-backup-if-mismatch", "-s", "-i",
                                t.reference_patch], cwd=sb, capture_output=True, text=True)
            if p.returncode != 0:
                raise GradeError("reference.patch does not apply to the fixture: " + (p.stdout + p.stderr).strip()[:300])
        return rd
    pr = resolve_pr_fixture(t)
    copy_tree(pr, os.path.join(sb, "pr"))
    lines = []
    if mode == "reference":
        for d in t.key.get("defects") or []:
            for s in (d.get("anchors") or [d.get("anchor_line")]):
                lines.append(f"- head/{d['file']}:{s}")
    elif mode == "noisy":
        head = os.path.join(sb, "pr", "head")
        for r, ds, fs in os.walk(head):
            ds.sort()
            for f in sorted(fs):
                p = os.path.join(r, f)
                if os.path.islink(p):
                    continue
                n = len(open(p, "rb").read().splitlines())
                rel = os.path.relpath(p, head)
                lines.extend(f"- head/{rel}:{i}" for i in range(1, n + 1))
    with open(os.path.join(sb, "review.md"), "w", encoding="utf-8") as f:
        f.write("# Findings\n\n" + "".join(l + "\n" for l in lines))
    return rd


def self_check(t, mode, frozen):
    if mode == "noisy" and t.build:
        raise GradeError("--self-check noisy applies to review-catch tasks only")
    root = tempfile.mkdtemp(prefix="selfcheck.", dir=SCRATCH)
    g = grade(t, synth_run(t, mode, root), frozen)
    ok, ev = False, ""
    if t.build:
        # hidden_tests is the structural check for refactor (MEDIUM-1); green = all_pass's
        # rule on the summary (every case, parsed, exit 0, no timeout: MEDIUM-3)
        h, r = g["hidden_tests"], g["regressions"]
        h_green = (h["passed"] >= h["total"] and not h["failed_names"] and not h["parse_error"]
                   and h["rc"] == 0 and not h["timed_out"])
        f = None if r is None else r["final"]
        suite_green = f is None or (f["passed"] >= f["total"] and f["rc"] == 0 and not f["timed_out"] and not r["parse_error"])
        if t.type == "refactor":
            ev = f"structural {h['passed']}/{h['total']}, suite {'green' if suite_green else 'red'}"
        else:
            ev = f"hidden {h['passed']}/{h['total']}" + ("" if f is None else f", fixture suite {f['passed']}/{f['total']}")
        if mode == "base":
            ok = h["passed"] < h["total"] and suite_green
        else:
            ok = h_green and suite_green
    else:
        rc = g["recall"]
        ev = f"recall {rc['recall']} ({rc['defects_caught']}/{rc['defects_seeded']}), false_positives {g['false_positives']}"
        if mode == "base":
            ok = rc["defects_caught"] == 0 and (rc["recall"] in (0, 0.0, None))
        elif mode == "reference":
            ok = rc["defects_seeded"] > 0 and rc["recall"] == 1.0
        else:
            gr = grade(t, synth_run(t, "reference", root), frozen)
            ev += f" vs reference {gr['false_positives']}"
            ok = g["false_positives"] > gr["false_positives"]
    return ok, ev, g


# ------------------------------------------------------------------ main
def host_gate():
    """LOW-A1: --executor host runs the agent's tree on this machine as the calling user"""
    if A.executor != "host":
        return
    if os.environ.get("LOA_EVAL_ALLOW_HOST_GRADING") != "1":
        raise GradeError("--executor host is refused: it runs the agent's code on this host as the calling "
                         "user with no filesystem, process or network isolation (env -i only; the user site is "
                         "exposed). Grade in the image, or set LOA_EVAL_ALLOW_HOST_GRADING=1 to accept the risk")
    print("ablation-grade: WARNING --executor host: the agent's code runs on this host as the calling user "
          "without isolation (LOA_EVAL_ALLOW_HOST_GRADING=1); grade.json records executor_mode host",
          file=sys.stderr)


def judge_setup(target):
    """1.5.0: --judge-verdicts is read and validated before any grading; --run-id defaults to the directory's name"""
    if A.run_id is not None and A.judge_verdicts is None:
        raise GradeError("--run-id goes with --judge-verdicts")
    if A.judge_verdicts is None:
        return
    RUN_ID[0] = A.run_id if A.run_id is not None else os.path.basename(os.path.abspath(target))
    if not re.fullmatch(JV_PATTERNS["run_id"], RUN_ID[0]):
        raise GradeError(f"--run-id {RUN_ID[0]!r}: 1-128 of [A-Za-z0-9._-]")
    JUDGE[0] = load_verdicts(A.judge_verdicts)


def main():
    host_gate()
    if A.self_check and (A.judge_verdicts is not None or A.run_id is not None):
        raise GradeError("--judge-verdicts grades a run or a union, never a self-check")
    if A.self_check:
        if not A.task_yaml or not os.path.isfile(A.task_yaml):
            raise GradeError("--self-check needs --task-yaml <task.yaml>")
        tdir = os.path.dirname(os.path.abspath(A.task_yaml))
        suite_root = os.path.abspath(A.suite_root) if A.suite_root else os.path.dirname(os.path.dirname(tdir))
        t = load_task(A.task_yaml, suite_root)
        if t.id != os.path.basename(tdir):
            raise GradeError(f"task id {t.id!r} is not its directory name")
        frozen = freeze_check(suite_root)
        ok, ev, g = self_check(t, A.self_check, frozen)
        line = f"self-check {A.self_check} {t.id}: {'PASS' if ok else 'FAIL'} {ev}"
        print(line)
        if A.json:
            print(json.dumps({"mode": A.self_check, "task_id": t.id, "result": "PASS" if ok else "FAIL",
                              "evidence": ev, "grade": g}, indent=2))
        return 0 if ok else 1
    if A.union:
        if A.run_dir or A.task_id or not A.union_task_id:
            raise GradeError("usage: ablation-grade.sh --union <cell-dir> --task-id T [options] (see --help)")
        if not re.match(r"^[a-z0-9][a-z0-9-]{0,63}$", A.union_task_id):
            raise GradeError(f"invalid task id: {A.union_task_id}")
        if not os.path.isdir(A.union):
            raise GradeError(f"cell directory not found: {A.union}")
        suite_root = os.path.abspath(A.suite_root or os.path.join(REPO_ROOT, "grimoires", "loa", "evals", "ablation-2.0"))
        ty = os.path.join(suite_root, A.tasks_dir or "tasks", A.union_task_id, "task.yaml")
        if not os.path.isfile(ty):
            raise GradeError(f"task not found: {ty}")
        t = load_task(ty, suite_root)
        if t.id != A.union_task_id or t.build:
            raise GradeError(f"--union grades a review-catch task; {A.union_task_id!r} is not one")
        judge_setup(A.union)
        g = grade_union(t, A.union, freeze_check(suite_root))
        out = A.out or os.path.join(os.path.abspath(A.union), "grade.json")
        text = write_grade(g, out)
        if A.json:
            sys.stdout.write(text)
        else:
            rc = g["recall"] or {}
            print(f"graded {t.id} (union of {g['sessions_valid']}/{g['bare_sessions']} sessions): recall {rc.get('recall')} "
                  f"false_positives {g['false_positives']}; session 1 recall {g['recall_session1']} → {out}")
        return 0
    if A.union_task_id:
        raise GradeError("--task-id goes with --union (the run mode takes <run-dir> <task-id>)")
    if not A.run_dir or not A.task_id:
        raise GradeError("usage: ablation-grade.sh <run-dir> <task-id> [options] (see --help)")
    if not re.match(r"^[a-z0-9][a-z0-9-]{0,63}$", A.task_id):
        raise GradeError(f"invalid task id: {A.task_id}")
    if not os.path.isdir(A.run_dir):
        raise GradeError(f"run directory not found: {A.run_dir}")
    suite_root = os.path.abspath(A.suite_root or os.path.join(REPO_ROOT, "grimoires", "loa", "evals", "ablation-2.0"))
    ty = os.path.join(suite_root, A.tasks_dir or "tasks", A.task_id, "task.yaml")
    if not os.path.isfile(ty):
        raise GradeError(f"task not found: {ty}")
    t = load_task(ty, suite_root)
    if t.id != A.task_id:
        raise GradeError(f"task.yaml id {t.id!r} differs from {A.task_id!r}")
    if t.build and (A.judge_verdicts is not None or A.run_id is not None):
        raise GradeError("--judge-verdicts applies to review-catch grades only (a build task has no credited pairs)")
    judge_setup(A.run_dir)
    frozen = freeze_check(suite_root)
    g = grade(t, A.run_dir, frozen)
    out = A.out or os.path.join(os.path.abspath(A.run_dir), "grade.json")
    text = write_grade(g, out)
    if A.json:
        sys.stdout.write(text)
    else:
        h = g["hidden_tests"]
        part = (f"hidden {h['passed']}/{h['total']}" if h else
                f"recall {g['recall']['recall']} false_positives {g['false_positives']}")
        print(f"graded {t.id}: {part}; verdict_accuracy {g['verdict_accuracy']}; "
              f"contaminated {g['contaminated']['pattern'] if g['contaminated'] else 'no'} → {out}")
    return 0


try:
    rc = main()
except GradeError as e:
    print(f"ablation-grade: {e}", file=sys.stderr)
    rc = 2
except Exception as e:  # an unexpected shape is an error (2), never a self-check FAIL (1)
    print(f"ablation-grade: internal error: {type(e).__name__}: {e}", file=sys.stderr)
    rc = 2
finally:
    try:
        remove_path(SCRATCH)
    except OSError:
        pass
sys.exit(rc)
PY
