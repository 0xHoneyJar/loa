# Hunks — pr-23

The later fix changed 66 region(s) in 5 of the change's 16 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — evals/harness/ablation-grade.sh — head line 25

Head context (head/evals/harness/ablation-grade.sh, lines 13–37):

~~~~text
    13 | #                     [--image loa-ablation:258] [--docker-bin D]
    14 | #                     [--allow-unfrozen] [--allow-partial]
    15 | #   ablation-grade.sh --self-check base|reference|noisy --task-yaml F [--suite-root DIR]
    16 | #                     [--executor …] [--image …] [--docker-bin D] [--json]
    17 | #                     [--allow-unfrozen] [--allow-partial]
    18 | #
    19 | # Options:
    20 | #   --suite-root DIR   suite root (default grimoires/loa/evals/ablation-2.0; with
    21 | #                      --self-check, the directory two levels above the task dir)
    22 | #   --tasks-dir T      tasks (default) or smoke: the task is <root>/<T>/<task-id>/
    23 | #   --out FILE         where grade.json goes (default <run-dir>/grade.json)
    24 | #   --json             also print grade.json (self-check: the verdict object) on stdout
>   25 | #   --executor MODE    container (default; DEC-0491) or host
    26 | #   --image IMG        the grading image (default loa-ablation:258)
    27 | #   --docker-bin D     docker CLI (default $EVAL_DOCKER_BIN, else docker)
    28 | #   --allow-unfrozen   grade although freeze.sh --check fails or the suite has no
    29 | #                      MANIFEST.sha256 yet (task authoring only); grade.json records
    30 | #                      suite_frozen: false. Without it a drift is exit 2 (DEC-0414).
    31 | #   --allow-partial    passed to freeze.sh --check (fewer than four tasks per type)
    32 | #   --self-check MODE  base | reference | noisy (noisy: review-catch only), see below
    33 | #   --task-yaml F      the task to self-check (<root>/<tasks|smoke>/<id>/task.yaml)
    34 | #
    35 | # Reads ONLY (DEC-0413): <run-dir>/sandbox/, <run-dir>/snapshots/{index.json,<LABEL>.bundle},
    36 | # <run-dir>/transcripts/events-*.jsonl, <run-dir>/eval/adversarial-{review,audit}.json,
    37 | # the task's directory under the suite root (task.yaml, hidden/, fixture/), the suite's
~~~~

The change from head to the fix:

~~~~diff
@@ -25 +25,4 @@
-#   --executor MODE    container (default; DEC-0491) or host
+#   --executor MODE    container (default; DEC-0491) or host. host runs the agent's code on
+#                      this machine as the calling user without isolation and is refused
+#                      (exit 2) unless LOA_EVAL_ALLOW_HOST_GRADING=1; allowed, it prints a
+#                      WARNING and grade.json records executor_mode: host (LOW-A1)
~~~~

## H02 — evals/harness/ablation-grade.sh — insertion after head line 34

Head context (head/evals/harness/ablation-grade.sh, lines 23–46):

~~~~text
    23 | #   --out FILE         where grade.json goes (default <run-dir>/grade.json)
    24 | #   --json             also print grade.json (self-check: the verdict object) on stdout
    25 | #   --executor MODE    container (default; DEC-0491) or host
    26 | #   --image IMG        the grading image (default loa-ablation:258)
    27 | #   --docker-bin D     docker CLI (default $EVAL_DOCKER_BIN, else docker)
    28 | #   --allow-unfrozen   grade although freeze.sh --check fails or the suite has no
    29 | #                      MANIFEST.sha256 yet (task authoring only); grade.json records
    30 | #                      suite_frozen: false. Without it a drift is exit 2 (DEC-0414).
    31 | #   --allow-partial    passed to freeze.sh --check (fewer than four tasks per type)
    32 | #   --self-check MODE  base | reference | noisy (noisy: review-catch only), see below
    33 | #   --task-yaml F      the task to self-check (<root>/<tasks|smoke>/<id>/task.yaml)
    34 | #
    35 | # Reads ONLY (DEC-0413): <run-dir>/sandbox/, <run-dir>/snapshots/{index.json,<LABEL>.bundle},
    36 | # <run-dir>/transcripts/events-*.jsonl, <run-dir>/eval/adversarial-{review,audit}.json,
    37 | # the task's directory under the suite root (task.yaml, hidden/, fixture/), the suite's
    38 | # MANIFEST.sha256 (through freeze.sh) and, for review-catch, the key manifest the task
    39 | # names (review_catch.manifest) and its PR fixture (self-check only). It never reads
    40 | # <run-dir>/meta/, the batch MANIFEST.json, or the sandbox copies of the dissent
    41 | # envelopes (tamperable; the harness copies under eval/ are authoritative). It writes
    42 | # only <run-dir>/grading/ and the --out file; nothing under sandbox/ is ever written.
    43 | #
    44 | # Freeze: freeze.sh --check --root <suite-root> runs first (with --smoke when the
    45 | # suite manifest lists smoke/ paths, so a manifest frozen with --smoke checks as it
    46 | # was frozen); a drift or a missing manifest refuses the grade (exit 2) unless
~~~~

The change from head to the fix:

~~~~diff
@@ -34,0 +38,3 @@
+# Environment: LOA_EVAL_ALLOW_HOST_GRADING=1 (see --executor); LOA_EVAL_GRADE_TIMEOUT_S
+# (1-9999, default 120: the per-command deadline; tests shorten it).
+#
~~~~

## H03 — evals/harness/ablation-grade.sh — head lines 52–53

Head context (head/evals/harness/ablation-grade.sh, lines 40–65):

~~~~text
    40 | # <run-dir>/meta/, the batch MANIFEST.json, or the sandbox copies of the dissent
    41 | # envelopes (tamperable; the harness copies under eval/ are authoritative). It writes
    42 | # only <run-dir>/grading/ and the --out file; nothing under sandbox/ is ever written.
    43 | #
    44 | # Freeze: freeze.sh --check --root <suite-root> runs first (with --smoke when the
    45 | # suite manifest lists smoke/ paths, so a manifest frozen with --smoke checks as it
    46 | # was frozen); a drift or a missing manifest refuses the grade (exit 2) unless
    47 | # --allow-unfrozen.
    48 | #
    49 | # Grading trees (D-4.8) under <run-dir>/grading/<label>/, recreated on every call:
    50 | #   final      sandbox/ as the agent left it, minus the top-level .git .claude CLAUDE.md
    51 | #              .loa.config.yaml grimoires .run .beads .eval pr, every __pycache__ and
>   52 | #              .pytest_cache, and anything that is not a regular file, directory or
>   53 | #              symlink (a FIFO never blocks the copy)
    54 | #   implement  the IMPLEMENT snapshot (snapshots/IMPLEMENT.bundle, commit
    55 | #              index.json.implement): the tree REVIEW read; graded when REVIEW ran or
    56 | #              when AUDIT ran without a fix1 snapshot
    57 | #   fix1       the FIX1 snapshot: the tree AUDIT read; graded when AUDIT ran
    58 | #   base       the task fixture: the baseline for regression_command (and, refactor,
    59 | #              the suite-green-at-base check)
    60 | # A snapshot is extracted with `git bundle unbundle` into a scratch bare repository and
    61 | # `git archive <commit>` (a member that would land outside the tree is skipped). In
    62 | # every tree each grader_protected path is restored from the fixture (a deleted file is
    63 | # recreated, a modified one overwritten, a path the fixture lacks is removed; a
    64 | # symlinked parent is replaced by a directory), then every hidden/manifest.json entry
    65 | # is written at its dest (a same-named file is overwritten, a deleted directory
~~~~

The change from head to the fix:

~~~~diff
@@ -52,2 +58,6 @@
-#              .pytest_cache, and anything that is not a regular file, directory or
-#              symlink (a FIFO never blocks the copy)
+#              .pytest_cache, anything that is not a regular file, directory or
+#              symlink (a FIFO never blocks the copy), every regular file above 16 MiB
+#              (lstat size; counted in oversized_files_skipped, also for snapshot tar
+#              members), and every symlink whose target is
+#              absolute or resolves outside the tree (lexically, then through the other
+#              links; counted in symlinks_dropped); in-tree relative links are kept
~~~~

## H04 — evals/harness/ablation-grade.sh — head lines 58–61

Head context (head/evals/harness/ablation-grade.sh, lines 46–73):

~~~~text
    46 | # was frozen); a drift or a missing manifest refuses the grade (exit 2) unless
    47 | # --allow-unfrozen.
    48 | #
    49 | # Grading trees (D-4.8) under <run-dir>/grading/<label>/, recreated on every call:
    50 | #   final      sandbox/ as the agent left it, minus the top-level .git .claude CLAUDE.md
    51 | #              .loa.config.yaml grimoires .run .beads .eval pr, every __pycache__ and
    52 | #              .pytest_cache, and anything that is not a regular file, directory or
    53 | #              symlink (a FIFO never blocks the copy)
    54 | #   implement  the IMPLEMENT snapshot (snapshots/IMPLEMENT.bundle, commit
    55 | #              index.json.implement): the tree REVIEW read; graded when REVIEW ran or
    56 | #              when AUDIT ran without a fix1 snapshot
    57 | #   fix1       the FIX1 snapshot: the tree AUDIT read; graded when AUDIT ran
>   58 | #   base       the task fixture: the baseline for regression_command (and, refactor,
>   59 | #              the suite-green-at-base check)
>   60 | # A snapshot is extracted with `git bundle unbundle` into a scratch bare repository and
>   61 | # `git archive <commit>` (a member that would land outside the tree is skipped). In
    62 | # every tree each grader_protected path is restored from the fixture (a deleted file is
    63 | # recreated, a modified one overwritten, a path the fixture lacks is removed; a
    64 | # symlinked parent is replaced by a directory), then every hidden/manifest.json entry
    65 | # is written at its dest (a same-named file is overwritten, a deleted directory
    66 | # recreated). Churn (diff_lines, files_changed) compares the final tree against the
    67 | # fixture before any restore: added + removed lines per changed text file (difflib),
    68 | # every added, removed or modified file counted once; null for review-catch.
    69 | #
    70 | # Commands run INSIDE the image (DEC-0491):
    71 | #   docker run --rm --network none --read-only --tmpfs /tmp:rw,size=256m --user <uid>:<gid>
    72 | #     -v <tree>:/workspace:rw -w /workspace -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp
    73 | #     <image> timeout 120 <cmd…>
~~~~

The change from head to the fix:

~~~~diff
@@ -58,4 +68,5 @@
-#   base       the task fixture: the baseline for regression_command (and, refactor,
-#              the suite-green-at-base check)
+#   base       the task fixture: the baseline of the regression check (regression_command;
+#              refactor: test_command, the fixture suite)
 # A snapshot is extracted with `git bundle unbundle` into a scratch bare repository and
-# `git archive <commit>` (a member that would land outside the tree is skipped). In
+# `git archive <commit>` (tarfile.data_filter: a member that would land outside the tree,
+# and a symlink member with an absolute or escaping target, is skipped). In
~~~~

## H05 — evals/harness/ablation-grade.sh — head lines 66–78

Head context (head/evals/harness/ablation-grade.sh, lines 54–90):

~~~~text
    54 | #   implement  the IMPLEMENT snapshot (snapshots/IMPLEMENT.bundle, commit
    55 | #              index.json.implement): the tree REVIEW read; graded when REVIEW ran or
    56 | #              when AUDIT ran without a fix1 snapshot
    57 | #   fix1       the FIX1 snapshot: the tree AUDIT read; graded when AUDIT ran
    58 | #   base       the task fixture: the baseline for regression_command (and, refactor,
    59 | #              the suite-green-at-base check)
    60 | # A snapshot is extracted with `git bundle unbundle` into a scratch bare repository and
    61 | # `git archive <commit>` (a member that would land outside the tree is skipped). In
    62 | # every tree each grader_protected path is restored from the fixture (a deleted file is
    63 | # recreated, a modified one overwritten, a path the fixture lacks is removed; a
    64 | # symlinked parent is replaced by a directory), then every hidden/manifest.json entry
    65 | # is written at its dest (a same-named file is overwritten, a deleted directory
>   66 | # recreated). Churn (diff_lines, files_changed) compares the final tree against the
>   67 | # fixture before any restore: added + removed lines per changed text file (difflib),
>   68 | # every added, removed or modified file counted once; null for review-catch.
>   69 | #
>   70 | # Commands run INSIDE the image (DEC-0491):
>   71 | #   docker run --rm --network none --read-only --tmpfs /tmp:rw,size=256m --user <uid>:<gid>
>   72 | #     -v <tree>:/workspace:rw -w /workspace -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp
>   73 | #     <image> timeout 120 <cmd…>
>   74 | # `python3 -m pytest …` (or `pytest …`) becomes `python3 -I -s -m pytest -p no:cacheprovider
>   75 | # -q --rootdir /workspace -rA …` (one -q: -qq would drop the summary line; -rA lists every
>   76 | # outcome, from which the ids come); `bats …` becomes `bats --tap …` with BATS_LIB_PATH
>   77 | # unset (the -e set is the whole container environment). --executor host runs the same
>   78 | # argv in the tree under `env -i PATH HOME=<scratch> LC_ALL=C TMPDIR=<scratch>
    79 | # PYTHONUSERBASE=<the caller's user base>` with pytest as `python3 -P -m pytest …`:
    80 | # no -I or -s on the host, because the host's pytest lives in the user site (the Sprint
    81 | # 258 smoke found no pytest under `-I -s`); PYTHONUSERBASE is passed for the same reason.
    82 | #
    83 | # Parsing: the pytest summary line (`N passed, M failed, K error …`) or TAP (`1..N`,
    84 | # `ok`/`not ok`). A collection error is expanded to the test functions of its file; the
    85 | # hidden total is never below the static case count of the hidden test files (`def test`
    86 | # / `@test`). A command without a parseable summary counts total = that static count
    87 | # (at least 1), passed = 0 when it exited non-zero (total when it exited 0), with
    88 | # parse_error: true. Ids: "t<k>", k = the 1-based position of the case in file order
    89 | # (pytest: path, then the line of its def; TAP: the test number); regression ids are
    90 | # positions in the base run, newly_failing = failing at final, passing at base.
~~~~

The change from head to the fix:

~~~~diff
@@ -66,13 +77,30 @@
-# recreated). Churn (diff_lines, files_changed) compares the final tree against the
+# recreated). Then (HIGH-A1) every pytest or bats harness file in the tree — conftest.py
+# at any depth, pytest.ini, .pytest.ini, pyproject.toml, setup.cfg, tox.ini,
+# setup_suite.bash, any *helper*.bash or *helper*.sh, any .bash file under a tests/ or test/
+# directory — is removed unless it is a hidden overlay dest or a regular file byte-identical
+# (filecmp, shallow=False) to the fixture's regular file at the same path; a symlink at such
+# a path is always removed. The count goes to harness_files_removed (every tree graded), the
+# paths to grading/<label>.harness-removed.txt beside the tree (never into grade.json).
+# Deleting a grading tree never chmods through a symlink. Churn
+# (diff_lines, files_changed) compares the final tree against the
 # fixture before any restore: added + removed lines per changed text file (difflib),
-# every added, removed or modified file counted once; null for review-catch.
+# every added, removed or modified file counted once (a file above 16 MiB on either side
+# is counted as changed and never read or diffed); null for review-catch.
 #
 # Commands run INSIDE the image (DEC-0491):
-#   docker run --rm --network none --read-only --tmpfs /tmp:rw,size=256m --user <uid>:<gid>
-#     -v <tree>:/workspace:rw -w /workspace -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp
-#     <image> timeout 120 <cmd…>
+#   docker run --rm --init --name ablgrade-<run>-<label>-<pid>-<n> --network none --read-only
+#     --tmpfs /tmp:rw,size=256m --pids-limit 256 --memory 2g --cpus 2 --cap-drop ALL
+#     --security-opt no-new-privileges --user <uid>:<gid> -v <tree>:/workspace:rw -w /workspace
+#     -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp <image> timeout --signal=TERM --kill-after=10 120 <cmd…>
+# (MEDIUM-A1) The docker client gets its own deadline (120 + 10 + 60 s); when it passes, or
+# the grader fails while the client runs, the client's process group is killed and
+# `docker kill <name>` then `docker rm -f <name>` run (errors ignored): the result is
+# timed_out with rc 124. Exit 124, or 137 after the deadline, is timed_out too. Captured
+# output (stdout + stderr) is read in chunks and capped at 4 MiB — the first and the last
+# 2 MiB are kept, so the summary survives — and output_truncated records a cut.
 # `python3 -m pytest …` (or `pytest …`) becomes `python3 -I -s -m pytest -p no:cacheprovider
-# -q --rootdir /workspace -rA …` (one -q: -qq would drop the summary line; -rA lists every
-# outcome, from which the ids come); `bats …` becomes `bats --tap …` with BATS_LIB_PATH
+# -o addopts= -q --rootdir /workspace -rA …` (one -q: -qq would drop the summary line; -rA
+# lists every outcome, from which the ids come; -o addopts= voids an ini file's addopts);
+# `bats …` becomes `bats --tap …` with BATS_LIB_PATH
 # unset (the -e set is the whole container environment). --executor host runs the same
-# argv in the tree under `env -i PATH HOME=<scratch> LC_ALL=C TMPDIR=<scratch>
+# argv (with the same timeout prefix) in the tree under `env -i PATH HOME=<scratch> LC_ALL=C TMPDIR=<scratch>
~~~~

## H06 — evals/harness/ablation-grade.sh — head lines 89–90

Head context (head/evals/harness/ablation-grade.sh, lines 77–102):

~~~~text
    77 | # unset (the -e set is the whole container environment). --executor host runs the same
    78 | # argv in the tree under `env -i PATH HOME=<scratch> LC_ALL=C TMPDIR=<scratch>
    79 | # PYTHONUSERBASE=<the caller's user base>` with pytest as `python3 -P -m pytest …`:
    80 | # no -I or -s on the host, because the host's pytest lives in the user site (the Sprint
    81 | # 258 smoke found no pytest under `-I -s`); PYTHONUSERBASE is passed for the same reason.
    82 | #
    83 | # Parsing: the pytest summary line (`N passed, M failed, K error …`) or TAP (`1..N`,
    84 | # `ok`/`not ok`). A collection error is expanded to the test functions of its file; the
    85 | # hidden total is never below the static case count of the hidden test files (`def test`
    86 | # / `@test`). A command without a parseable summary counts total = that static count
    87 | # (at least 1), passed = 0 when it exited non-zero (total when it exited 0), with
    88 | # parse_error: true. Ids: "t<k>", k = the 1-based position of the case in file order
>   89 | # (pytest: path, then the line of its def; TAP: the test number); regression ids are
>   90 | # positions in the base run, newly_failing = failing at final, passing at base.
    91 | #
    92 | # Review-catch (DEC-0420): grading/gates-combined.md is the arm-neutral reduction: every
    93 | # `path:line[-line]` citation (parser of recall-vs-defects.sh 1.1.2; the LOA-VERDICT
    94 | # trailer removed first) from sandbox/review.md (the A0 contract),
    95 | # sandbox/grimoires/loa/a2a/sprint-1/{engineer-feedback.md,auditor-sprint-feedback.md}
    96 | # and each finding's anchor (and file:line) in eval/adversarial-{review,audit}.json,
    97 | # one normalised `path:line[-line]` line each (pr/head/ → head/, a/ b/ and /workspace/
    98 | # prefixes dropped), duplicates dropped. recall-vs-defects.sh <grading-dir> <pr-NN>
    99 | # gates-combined.md (EVAL_MANIFEST_DIR = the manifest's directory) gives recall;
   100 | # flags = its findings_cited; missed = defect positions ("d2"), never defect ids.
   101 | # false_positives = citations within ±3 of no anchor, deduplicated by cited region
   102 | # (same file, overlapping ±3 windows count once).
~~~~

The change from head to the fix:

~~~~diff
@@ -89,2 +117,19 @@
-# (pytest: path, then the line of its def; TAP: the test number); regression ids are
-# positions in the base run, newly_failing = failing at final, passing at base.
+# (pytest: path, then the line of its def; TAP: the test number). A node path is printed
+# by code under test (MEDIUM-A2): its def lines come from the grader-owned copy (the hidden
+# overlay source, a protected fixture file) when the path has one; else the path must be
+# relative, stay inside the tree and open as a regular file of at most 1 MiB (O_NOFOLLOW |
+# O_NONBLOCK, fstat) — a device, a FIFO, a symlink or a path above the tree orders last
+# (unknown def line) and expands no collection error. Regression ids are
+# positions in the base run, newly_failing = failing at final, passing at base. When
+# either side of the regression check has no parseable summary, regressions.parse_error is
+# true and newly_failing comes from the exit statuses: base unparsed, exit 0, final exit
+# non-zero or timed out → every fallback id; base parsed, final unparsed and failed → every
+# base-passing case; else none. A run is green (all_pass) only when every case passed, the
+# summary parsed, the command exited 0 and did not time out.
+#
+# Hidden assertion per type: bug-fix and feature-build — test_command is hidden_tests,
+# regression_command the regression check; refactor (DEC-0401, AC-5.3) — the structural
+# check (structural_check's overlay dest, run with pytest or bats) is hidden_tests, so the
+# row's hidden_test_pass_rate is the structural pass rate, and test_command (the fixture
+# suite) is the regression check at base and final; structural repeats the structural
+# counts with suite_green_base and suite_green_final.
~~~~

## H07 — evals/harness/ablation-grade.sh — head line 105

Head context (head/evals/harness/ablation-grade.sh, lines 93–117):

~~~~text
    93 | # `path:line[-line]` citation (parser of recall-vs-defects.sh 1.1.2; the LOA-VERDICT
    94 | # trailer removed first) from sandbox/review.md (the A0 contract),
    95 | # sandbox/grimoires/loa/a2a/sprint-1/{engineer-feedback.md,auditor-sprint-feedback.md}
    96 | # and each finding's anchor (and file:line) in eval/adversarial-{review,audit}.json,
    97 | # one normalised `path:line[-line]` line each (pr/head/ → head/, a/ b/ and /workspace/
    98 | # prefixes dropped), duplicates dropped. recall-vs-defects.sh <grading-dir> <pr-NN>
    99 | # gates-combined.md (EVAL_MANIFEST_DIR = the manifest's directory) gives recall;
   100 | # flags = its findings_cited; missed = defect positions ("d2"), never defect ids.
   101 | # false_positives = citations within ±3 of no anchor, deduplicated by cited region
   102 | # (same file, overlapping ±3 windows count once).
   103 | #
   104 | # Verdicts: the last `<!-- LOA-VERDICT {…} -->` trailer of engineer-feedback.md (review)
>  105 | # and auditor-sprint-feedback.md (audit); a gate ran when its feedback file exists.
   106 | # verdict = {source_file, value}: the audit's, else the review's, else review.md's
   107 | # `Verdict:` line (A0), else null. verdict_accuracy_per_gate {review, audit}: build —
   108 | # true when APPROVED and the tree that gate read passes every hidden test, or
   109 | # CHANGES_REQUIRED and it fails one; review-catch — true iff (CHANGES_REQUIRED) ==
   110 | # (the key holds a high or critical defect); a gate without a trailer is false; a gate
   111 | # that did not run is null. verdict_accuracy = audit's, else review's, else null.
   112 | #
   113 | # Contamination (D-4.7, DEC-0493): every tool_use input in transcripts/events-*.jsonl —
   114 | # Bash command; Read/Grep/Glob file_path|path|pattern; Write/Edit/MultiEdit/NotebookEdit
   115 | # file_path|notebook_path; WebFetch url; WebSearch query — is checked for: `hidden` (any
   116 | # case) → hidden; grimoires/loa/evals/ablation-2.0 → suite_path; 0xHoneyJar/loa →
   117 | # repo_name; `git log … --all` or `git reflog` (Bash) → git_history; an absolute path
~~~~

The change from head to the fix:

~~~~diff
@@ -105 +150,6 @@
-# and auditor-sprint-feedback.md (audit); a gate ran when its feedback file exists.
+# and auditor-sprint-feedback.md (audit); a gate ran when its feedback path exists. Every
+# sandbox file the grader reads (the feedback files, review.md) and the eval/ envelopes are
+# read as regular files only, first 2 MiB (O_NOFOLLOW | O_NONBLOCK; sandbox files must also
+# resolve inside sandbox/): a symlinked or otherwise unreadable feedback file is verdict
+# "none" (the gate ran, no readable trailer), a symlinked review.md gives no verdict and no
+# citations (MEDIUM-A3).
~~~~

## H08 — evals/harness/ablation-grade.sh — head line 110

Head context (head/evals/harness/ablation-grade.sh, lines 98–122):

~~~~text
    98 | # prefixes dropped), duplicates dropped. recall-vs-defects.sh <grading-dir> <pr-NN>
    99 | # gates-combined.md (EVAL_MANIFEST_DIR = the manifest's directory) gives recall;
   100 | # flags = its findings_cited; missed = defect positions ("d2"), never defect ids.
   101 | # false_positives = citations within ±3 of no anchor, deduplicated by cited region
   102 | # (same file, overlapping ±3 windows count once).
   103 | #
   104 | # Verdicts: the last `<!-- LOA-VERDICT {…} -->` trailer of engineer-feedback.md (review)
   105 | # and auditor-sprint-feedback.md (audit); a gate ran when its feedback file exists.
   106 | # verdict = {source_file, value}: the audit's, else the review's, else review.md's
   107 | # `Verdict:` line (A0), else null. verdict_accuracy_per_gate {review, audit}: build —
   108 | # true when APPROVED and the tree that gate read passes every hidden test, or
   109 | # CHANGES_REQUIRED and it fails one; review-catch — true iff (CHANGES_REQUIRED) ==
>  110 | # (the key holds a high or critical defect); a gate without a trailer is false; a gate
   111 | # that did not run is null. verdict_accuracy = audit's, else review's, else null.
   112 | #
   113 | # Contamination (D-4.7, DEC-0493): every tool_use input in transcripts/events-*.jsonl —
   114 | # Bash command; Read/Grep/Glob file_path|path|pattern; Write/Edit/MultiEdit/NotebookEdit
   115 | # file_path|notebook_path; WebFetch url; WebSearch query — is checked for: `hidden` (any
   116 | # case) → hidden; grimoires/loa/evals/ablation-2.0 → suite_path; 0xHoneyJar/loa →
   117 | # repo_name; `git log … --all` or `git reflog` (Bash) → git_history; an absolute path
   118 | # (path fields, the Glob pattern, path-shaped Bash words; a one-component `/x/` word
   119 | # is read as a regex) outside /workspace /tmp /home/evaluser /dev /proc /sys /usr /bin
   120 | # /sbin /lib /lib64 /etc /opt /var (container), or outside the sandbox root (the
   121 | # sessions' init cwd and <run-dir>/sandbox), /tmp, those system directories and the
   122 | # caller's ~/.claude ~/.claude.json ~/.codex ~/.aws (host) → outside_path. The first hit
~~~~

The change from head to the fix:

~~~~diff
@@ -110 +160,2 @@
-# (the key holds a high or critical defect); a gate without a trailer is false; a gate
+# (the key holds a high or critical defect); refactor — the tree passes when the
+# structural check AND the fixture suite are green on it; a gate without a trailer is false; a gate
~~~~

## H09 — evals/harness/ablation-grade.sh — head lines 118–122

Head context (head/evals/harness/ablation-grade.sh, lines 106–134):

~~~~text
   106 | # verdict = {source_file, value}: the audit's, else the review's, else review.md's
   107 | # `Verdict:` line (A0), else null. verdict_accuracy_per_gate {review, audit}: build —
   108 | # true when APPROVED and the tree that gate read passes every hidden test, or
   109 | # CHANGES_REQUIRED and it fails one; review-catch — true iff (CHANGES_REQUIRED) ==
   110 | # (the key holds a high or critical defect); a gate without a trailer is false; a gate
   111 | # that did not run is null. verdict_accuracy = audit's, else review's, else null.
   112 | #
   113 | # Contamination (D-4.7, DEC-0493): every tool_use input in transcripts/events-*.jsonl —
   114 | # Bash command; Read/Grep/Glob file_path|path|pattern; Write/Edit/MultiEdit/NotebookEdit
   115 | # file_path|notebook_path; WebFetch url; WebSearch query — is checked for: `hidden` (any
   116 | # case) → hidden; grimoires/loa/evals/ablation-2.0 → suite_path; 0xHoneyJar/loa →
   117 | # repo_name; `git log … --all` or `git reflog` (Bash) → git_history; an absolute path
>  118 | # (path fields, the Glob pattern, path-shaped Bash words; a one-component `/x/` word
>  119 | # is read as a regex) outside /workspace /tmp /home/evaluser /dev /proc /sys /usr /bin
>  120 | # /sbin /lib /lib64 /etc /opt /var (container), or outside the sandbox root (the
>  121 | # sessions' init cwd and <run-dir>/sandbox), /tmp, those system directories and the
>  122 | # caller's ~/.claude ~/.claude.json ~/.codex ~/.aws (host) → outside_path. The first hit
   123 | # in phase order is contaminated: {phase, pattern, excerpt_id: "<phase>:<line>"} (never
   124 | # the text); else null. The scan is a LOWER BOUND on leakage: obfuscated access, reads
   125 | # by programs the agent wrote, and network access by other means are not seen.
   126 | #
   127 | # grade.json (ids only in every summary field: no test name, defect title or excerpt):
   128 | #   {schema_version: 1, grader_version: "1.0.0", task_id, task_type, suite_frozen,
   129 | #    executor_mode, image, snapshots_graded: [labels], hidden_tests {passed, total,
   130 | #    failed_names, parse_error, timed_out}, structural (refactor: {passed, total,
   131 | #    failed_names, parse_error, suite_green_base, suite_green_final}; else null),
   132 | #    regressions ({newly_failing, base {passed, total}, final {passed, total}} or null
   133 | #    without regression_command), snapshot_tests {implement?, fix1?: {passed, total}},
   134 | #    recall (review-catch {defects_seeded, defects_caught, recall, flags, missed}; else
~~~~

The change from head to the fix:

~~~~diff
@@ -118,5 +169,8 @@
-# (path fields, the Glob pattern, path-shaped Bash words; a one-component `/x/` word
-# is read as a regex) outside /workspace /tmp /home/evaluser /dev /proc /sys /usr /bin
+# (path fields, the Glob pattern, path-shaped Bash words; a one-component `/x/` word is
+# read as a regex only right after s, y, =, ~ or a single quote — `cd /root/` is a path)
+# outside /workspace /tmp /home/evaluser /dev /proc /sys /usr /bin
 # /sbin /lib /lib64 /etc /opt /var (container), or outside the sandbox root (the
-# sessions' init cwd and <run-dir>/sandbox), /tmp, those system directories and the
-# caller's ~/.claude ~/.claude.json ~/.codex ~/.aws (host) → outside_path. The first hit
+# sessions' init cwd and <run-dir>/sandbox), /tmp and those system directories (host; no
+# credential store under ~ is exempt: LOW-A2) → outside_path. A path or Bash word starting
+# ~/, $HOME/ or ${HOME}/ is always outside, and /proc/<pid|self|thread-self>/{environ,
+# cmdline,maps,mem} and /var/run are outside although /proc and /var are allowed. The first hit
~~~~

## H10 — evals/harness/ablation-grade.sh — head lines 128–136

Head context (head/evals/harness/ablation-grade.sh, lines 116–148):

~~~~text
   116 | # case) → hidden; grimoires/loa/evals/ablation-2.0 → suite_path; 0xHoneyJar/loa →
   117 | # repo_name; `git log … --all` or `git reflog` (Bash) → git_history; an absolute path
   118 | # (path fields, the Glob pattern, path-shaped Bash words; a one-component `/x/` word
   119 | # is read as a regex) outside /workspace /tmp /home/evaluser /dev /proc /sys /usr /bin
   120 | # /sbin /lib /lib64 /etc /opt /var (container), or outside the sandbox root (the
   121 | # sessions' init cwd and <run-dir>/sandbox), /tmp, those system directories and the
   122 | # caller's ~/.claude ~/.claude.json ~/.codex ~/.aws (host) → outside_path. The first hit
   123 | # in phase order is contaminated: {phase, pattern, excerpt_id: "<phase>:<line>"} (never
   124 | # the text); else null. The scan is a LOWER BOUND on leakage: obfuscated access, reads
   125 | # by programs the agent wrote, and network access by other means are not seen.
   126 | #
   127 | # grade.json (ids only in every summary field: no test name, defect title or excerpt):
>  128 | #   {schema_version: 1, grader_version: "1.0.0", task_id, task_type, suite_frozen,
>  129 | #    executor_mode, image, snapshots_graded: [labels], hidden_tests {passed, total,
>  130 | #    failed_names, parse_error, timed_out}, structural (refactor: {passed, total,
>  131 | #    failed_names, parse_error, suite_green_base, suite_green_final}; else null),
>  132 | #    regressions ({newly_failing, base {passed, total}, final {passed, total}} or null
>  133 | #    without regression_command), snapshot_tests {implement?, fix1?: {passed, total}},
>  134 | #    recall (review-catch {defects_seeded, defects_caught, recall, flags, missed}; else
>  135 | #    null), false_positives, verdict, verdicts {review, audit}, verdict_accuracy,
>  136 | #    verdict_accuracy_per_gate {review, audit}, diff_lines, files_changed, contaminated}
   137 | # No timestamp and no scratch path is written: the same run grades byte-identically.
   138 | #
   139 | # Self-check (DEC-0401; AC-2.3): a synthetic run under mktemp -d built from the task.
   140 | #   base       build: the fixture is the final tree → PASS when at least one hidden test
   141 | #              fails and the fixture suite (regression_command, when set) is green;
   142 | #              refactor: structural check red and suite green; review-catch: an empty
   143 | #              findings file → recall 0.0
   144 | #   reference  build: the fixture with hidden/reference.patch (patch -p1) → every hidden
   145 | #              test passes, suite green; refactor: structural green, suite green;
   146 | #              review-catch: a findings file citing every key anchor → recall 1.0
   147 | #   noisy      review-catch: every line of every pr/head/ file cited → false_positives
   148 | #              greater than the reference findings file's
~~~~

The change from head to the fix:

~~~~diff
@@ -128,9 +182,25 @@
-#   {schema_version: 1, grader_version: "1.0.0", task_id, task_type, suite_frozen,
+#   {schema_version: 1, grader_version: "1.2.0", task_id, task_type, suite_frozen,
 #    executor_mode, image, snapshots_graded: [labels], hidden_tests {passed, total,
-#    failed_names, parse_error, timed_out}, structural (refactor: {passed, total,
-#    failed_names, parse_error, suite_green_base, suite_green_final}; else null),
-#    regressions ({newly_failing, base {passed, total}, final {passed, total}} or null
-#    without regression_command), snapshot_tests {implement?, fix1?: {passed, total}},
-#    recall (review-catch {defects_seeded, defects_caught, recall, flags, missed}; else
-#    null), false_positives, verdict, verdicts {review, audit}, verdict_accuracy,
-#    verdict_accuracy_per_gate {review, audit}, diff_lines, files_changed, contaminated}
+#    failed_names, parse_error, timed_out, rc, output_truncated}, structural (refactor:
+#    {passed, total, failed_names, parse_error, suite_green_base, suite_green_final}; else
+#    null), regressions ({newly_failing, base {passed, total, rc, timed_out,
+#    output_truncated}, final {…}, parse_error, base_green, final_green} or null without a
+#    regression check), snapshot_tests {implement?,
+#    fix1?: {passed, total}} (refactor: the structural check), recall (review-catch
+#    {defects_seeded, defects_caught, recall, flags, missed}; else null),
+#    false_positives, verdict, verdicts {review, audit}, verdict_accuracy,
+#    verdict_accuracy_per_gate {review, audit}, diff_lines, files_changed,
+#    symlinks_dropped, harness_files_removed, oversized_files_skipped, contaminated}
+# grader 1.1.0 (Sprint 259 fix round): refactor hidden_tests = the structural check,
+# exit-status-aware green, symlink filtering; 1.0.0 grades of refactor tasks differ.
+# Round 2: snapshot trees get the same realpath symlink pass as the final copy (counted in
+# symlinks_dropped); regressions carries base_green and final_green (all_pass of each run);
+# the self-check's suite-green rule requires a parsed summary too.
+# grader 1.2.0 (Sprint 259 audit fix round 1): harness files removed before every run and
+# pytest -o addopts= (HIGH-A1); a named, limited, init-wrapped container with a kill
+# deadline, docker kill/rm -f on a hung client and a 4 MiB output cap (MEDIUM-A1);
+# node paths read from grader-owned copies or bounded in-tree regular files (MEDIUM-A2);
+# a 16 MiB copy cap and bounded, symlink-refusing readers (MEDIUM-A3); host mode opt-in
+# (LOW-A1); no credential store exempt and ~/, $HOME/, /proc/*/environ, /var/run flagged
+# (LOW-A2). New fields: harness_files_removed, oversized_files_skipped, output_truncated.
+# A grade that removed a harness file, skipped a file or ran a cheat differs from 1.1.0's.
~~~~

## H11 — evals/harness/ablation-grade.sh — head lines 141–145

Head context (head/evals/harness/ablation-grade.sh, lines 129–157):

~~~~text
   129 | #    executor_mode, image, snapshots_graded: [labels], hidden_tests {passed, total,
   130 | #    failed_names, parse_error, timed_out}, structural (refactor: {passed, total,
   131 | #    failed_names, parse_error, suite_green_base, suite_green_final}; else null),
   132 | #    regressions ({newly_failing, base {passed, total}, final {passed, total}} or null
   133 | #    without regression_command), snapshot_tests {implement?, fix1?: {passed, total}},
   134 | #    recall (review-catch {defects_seeded, defects_caught, recall, flags, missed}; else
   135 | #    null), false_positives, verdict, verdicts {review, audit}, verdict_accuracy,
   136 | #    verdict_accuracy_per_gate {review, audit}, diff_lines, files_changed, contaminated}
   137 | # No timestamp and no scratch path is written: the same run grades byte-identically.
   138 | #
   139 | # Self-check (DEC-0401; AC-2.3): a synthetic run under mktemp -d built from the task.
   140 | #   base       build: the fixture is the final tree → PASS when at least one hidden test
>  141 | #              fails and the fixture suite (regression_command, when set) is green;
>  142 | #              refactor: structural check red and suite green; review-catch: an empty
>  143 | #              findings file → recall 0.0
>  144 | #   reference  build: the fixture with hidden/reference.patch (patch -p1) → every hidden
>  145 | #              test passes, suite green; refactor: structural green, suite green;
   146 | #              review-catch: a findings file citing every key anchor → recall 1.0
   147 | #   noisy      review-catch: every line of every pr/head/ file cited → false_positives
   148 | #              greater than the reference findings file's
   149 | # Prints `self-check <mode> <task-id>: PASS|FAIL <evidence>`.
   150 | #
   151 | # Exit codes: 0 graded / self-check PASS; 1 self-check FAIL; 2 error (usage, missing run
   152 | # dir, task not found, unfrozen suite without --allow-unfrozen, docker or the image
   153 | # missing in container mode, a tool failure).
   154 | #
   155 | # Tested by evals/tests/ablation-grade.bats (docker = evals/tests/fixtures/docker-stub.sh).
   156 | # No .claude/ code is sourced and nothing is sourced or eval'd from a variable (eval.yml
   157 | # trust boundary); hashing is Python hashlib.
~~~~

The change from head to the fix:

~~~~diff
@@ -141,5 +211,5 @@
-#              fails and the fixture suite (regression_command, when set) is green;
-#              refactor: structural check red and suite green; review-catch: an empty
-#              findings file → recall 0.0
+#              fails (refactor: the structural check) and the regression check's final
+#              run (regressions.final) is green — every case, exit 0, no timeout;
+#              review-catch: an empty findings file → recall 0.0
 #   reference  build: the fixture with hidden/reference.patch (patch -p1) → every hidden
-#              test passes, suite green; refactor: structural green, suite green;
+#              test passes with exit 0 (refactor: structural green), suite green;
~~~~

## H12 — evals/harness/ablation-grade.sh — head lines 167–172

Head context (head/evals/harness/ablation-grade.sh, lines 155–184):

~~~~text
   155 | # Tested by evals/tests/ablation-grade.bats (docker = evals/tests/fixtures/docker-stub.sh).
   156 | # No .claude/ code is sourced and nothing is sourced or eval'd from a variable (eval.yml
   157 | # trust boundary); hashing is Python hashlib.
   158 | # =============================================================================
   159 | set -euo pipefail
   160 | export LC_ALL=C
   161 | 
   162 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   163 | REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
   164 | case "${1:-}" in -h|--help) sed -n '3,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
   165 | 
   166 | exec python3 -I - "$SCRIPT_DIR" "$REPO_ROOT" "${EVAL_DOCKER_BIN:-docker}" "$@" <<'PY'
>  167 | import argparse, difflib, json, os, re, shutil, site, stat, subprocess, sys, tarfile, tempfile
>  168 | 
>  169 | GRADER_VERSION = "1.0.0"
>  170 | SCRIPT_DIR, REPO_ROOT, DOCKER_DEFAULT = sys.argv[1], sys.argv[2], sys.argv[3]
>  171 | SPRINT = "sprint-1"
>  172 | TEST_TIMEOUT_S = 120
   173 | EXCLUDE_TOP = {".git", ".claude", "CLAUDE.md", ".loa.config.yaml", "grimoires", ".run", ".beads", ".eval", "pr"}
   174 | EXCLUDE_ANY = {"__pycache__", ".pytest_cache"}
   175 | PHASE_ORDER = ["PLAN", "BARE", "IMPLEMENT", "REVIEW", "FIX1", "AUDIT", "FIX2"]
   176 | 
   177 | 
   178 | class GradeError(Exception):
   179 |     pass
   180 | 
   181 | 
   182 | def die(msg):
   183 |     print(f"ablation-grade: {msg}", file=sys.stderr)
   184 |     sys.exit(2)
~~~~

The change from head to the fix:

~~~~diff
@@ -167,6 +237,16 @@
-import argparse, difflib, json, os, re, shutil, site, stat, subprocess, sys, tarfile, tempfile
+import argparse, difflib, filecmp, json, os, re, shutil, site, stat, subprocess, sys, tarfile, tempfile, threading, time
 
-GRADER_VERSION = "1.0.0"
+GRADER_VERSION = "1.2.0"
 SCRIPT_DIR, REPO_ROOT, DOCKER_DEFAULT = sys.argv[1], sys.argv[2], sys.argv[3]
 SPRINT = "sprint-1"
-TEST_TIMEOUT_S = 120
+_t = os.environ.get("LOA_EVAL_GRADE_TIMEOUT_S", "")
+TEST_TIMEOUT_S = int(_t) if re.fullmatch(r"[1-9][0-9]{0,3}", _t) else 120   # tests shorten it
+KILL_AFTER_S = 10                                    # timeout --kill-after (MEDIUM-A1)
+OUTER_GRACE_S = max(5, min(60, TEST_TIMEOUT_S // 2))  # the client deadline beyond T + KILL_AFTER_S
+OUTPUT_CAP = 4 * 1024 * 1024      # captured stdout per command (MEDIUM-A1)
+FILE_CAP = 16 * 1024 * 1024       # a regular file above this is not copied (MEDIUM-A3)
+READ_CAP = 2 * 1024 * 1024        # verdict, citation and envelope reads (MEDIUM-A3)
+NODE_FILE_CAP = 1024 * 1024       # a test file read for case order (MEDIUM-A2)
+# pytest and bats load these from the tree under test (HIGH-A1); see is_harness()
+HARNESS_NAMES = {"conftest.py", "pytest.ini", ".pytest.ini", "pyproject.toml", "setup.cfg", "tox.ini",
+                 "setup_suite.bash"}
~~~~

## H13 — evals/harness/ablation-grade.sh — head lines 236–242

Head context (head/evals/harness/ablation-grade.sh, lines 224–254):

~~~~text
   224 |         with open(path, encoding="utf-8") as f:
   225 |             return json.load(f)
   226 |     except (OSError, ValueError):
   227 |         return None
   228 | 
   229 | 
   230 | def is_within(path, root):
   231 |     path, root = os.path.realpath(path), os.path.realpath(root)
   232 |     return path == root or path.startswith(root + os.sep)
   233 | 
   234 | 
   235 | def remove_path(p):
>  236 |     if os.path.islink(p) or os.path.isfile(p):
>  237 |         os.unlink(p)
>  238 |     elif os.path.isdir(p):
>  239 |         for r, ds, _fs in os.walk(p):
>  240 |             for d in ds:
>  241 |                 try:
>  242 |                     os.chmod(os.path.join(r, d), 0o700)
   243 |                 except OSError:
   244 |                     pass
   245 |         shutil.rmtree(p)
   246 |     elif os.path.lexists(p):
   247 |         os.unlink(p)
   248 | 
   249 | 
   250 | def safe_rel(rel):
   251 |     if not isinstance(rel, str) or not rel or rel.startswith("/") or "\\" in rel:
   252 |         return None
   253 |     parts = [x for x in rel.split("/") if x not in ("", ".")]
   254 |     if not parts or ".." in parts:
~~~~

The change from head to the fix:

~~~~diff
@@ -236,7 +316,11 @@
+    """delete p; a directory is made writable first, but never through a symlink: a tree
+    the agent shaped may hold `x -> /somewhere`, and os.chmod follows links (DISS-001)"""
     if os.path.islink(p) or os.path.isfile(p):
         os.unlink(p)
     elif os.path.isdir(p):
-        for r, ds, _fs in os.walk(p):
+        for r, ds, _fs in os.walk(p, followlinks=False):
             for d in ds:
+                q = os.path.join(r, d)
                 try:
-                    os.chmod(os.path.join(r, d), 0o700)
+                    if stat.S_ISDIR(os.lstat(q).st_mode):
+                        os.chmod(q, 0o700)
~~~~

## H14 — evals/harness/ablation-grade.sh — insertion after head line 258

Head context (head/evals/harness/ablation-grade.sh, lines 247–270):

~~~~text
   247 |         os.unlink(p)
   248 | 
   249 | 
   250 | def safe_rel(rel):
   251 |     if not isinstance(rel, str) or not rel or rel.startswith("/") or "\\" in rel:
   252 |         return None
   253 |     parts = [x for x in rel.split("/") if x not in ("", ".")]
   254 |     if not parts or ".." in parts:
   255 |         return None
   256 |     return parts
   257 | 
   258 | 
   259 | def ensure_parent(tree, parts):
   260 |     """make every parent component of tree/parts a real directory inside tree"""
   261 |     cur = tree
   262 |     for comp in parts[:-1]:
   263 |         cur = os.path.join(cur, comp)
   264 |         if os.path.islink(cur) or (os.path.lexists(cur) and not os.path.isdir(cur)):
   265 |             os.unlink(cur)
   266 |         if not os.path.isdir(cur):
   267 |             os.mkdir(cur)
   268 |     return os.path.join(cur, parts[-1])
   269 | 
   270 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -258,0 +343,32 @@
+def read_regular(path, cap, whole=False, root=None):
+    """the text of a regular file, opened without following a final symlink and without
+    blocking on a FIFO (O_NOFOLLOW | O_NONBLOCK, then fstat S_ISREG). At most cap bytes are
+    read; whole=True refuses (None) a file larger than cap. root: the path must also
+    resolve inside root (a symlinked parent directory is refused). → str | None"""
+    if root is not None and not is_within(path, root):
+        return None
+    try:
+        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0))
+    except OSError:
+        return None
+    try:
+        st = os.fstat(fd)
+        if not stat.S_ISREG(st.st_mode) or (whole and st.st_size > cap):
+            return None
+        chunks, left = [], cap
+        while left > 0:
+            b = os.read(fd, min(left, 1 << 20))
+            if not b:
+                break
+            chunks.append(b)
+            left -= len(b)
+        return b"".join(chunks).decode("utf-8", "replace")
+    except OSError:
+        return None
+    finally:
+        os.close(fd)
+
+
+OVERSIZED = [0]   # regular files above FILE_CAP skipped by copy_tree / snapshot extraction in this grade
+
+
~~~~

## H15 — evals/harness/ablation-grade.sh — head lines 271–273

Head context (head/evals/harness/ablation-grade.sh, lines 259–285):

~~~~text
   259 | def ensure_parent(tree, parts):
   260 |     """make every parent component of tree/parts a real directory inside tree"""
   261 |     cur = tree
   262 |     for comp in parts[:-1]:
   263 |         cur = os.path.join(cur, comp)
   264 |         if os.path.islink(cur) or (os.path.lexists(cur) and not os.path.isdir(cur)):
   265 |             os.unlink(cur)
   266 |         if not os.path.isdir(cur):
   267 |             os.mkdir(cur)
   268 |     return os.path.join(cur, parts[-1])
   269 | 
   270 | 
>  271 | def copy_tree(src, dst, top_exclude=frozenset()):
>  272 |     """regular files, directories and symlinks only; caches dropped"""
>  273 |     os.makedirs(dst, exist_ok=True)
   274 |     for root, dirs, files in os.walk(src, followlinks=False):
   275 |         rel = os.path.relpath(root, src)
   276 |         keep = []
   277 |         for d in sorted(dirs):
   278 |             if (rel == "." and d in top_exclude) or d in EXCLUDE_ANY:
   279 |                 continue
   280 |             sp = os.path.join(root, d)
   281 |             dp = os.path.join(dst, rel, d)
   282 |             if os.path.islink(sp):
   283 |                 os.symlink(os.readlink(sp), dp)
   284 |                 continue
   285 |             os.makedirs(dp, exist_ok=True)
~~~~

The change from head to the fix:

~~~~diff
@@ -271,3 +387,32 @@
+def link_escapes(target, rel_dir):
+    """a symlink at <tree>/<rel_dir>/<name> pointing at target: absolute, or resolving
+    (lexically) above the tree root"""
+    if not target or os.path.isabs(target):
+        return True
+    n = os.path.normpath(os.path.join(rel_dir, target))
+    return n == ".." or n.startswith("../") or os.path.isabs(n)
+
+
+def drop_escaping_links(tree):
+    """second pass over the copy: any symlink whose full resolution (through the other
+    links) leaves the tree is removed; repeated until stable → number removed"""
+    n, root = 0, os.path.realpath(tree)
+    while True:
+        gone = 0
+        for r, ds, fs in os.walk(tree, followlinks=False):
+            for name in ds + fs:
+                q = os.path.join(r, name)
+                if os.path.islink(q) and not is_within(q, root):
+                    os.unlink(q)
+                    gone += 1
+        if not gone:
+            return n
+        n += gone
+
+
 def copy_tree(src, dst, top_exclude=frozenset()):
-    """regular files, directories and symlinks only; caches dropped"""
+    """regular files, directories and in-tree relative symlinks only; caches dropped. A
+    symlink whose target is absolute or resolves outside dst is not recreated (DISS-001).
+    → the number of symlinks dropped"""
     os.makedirs(dst, exist_ok=True)
+    dropped = 0
~~~~

## H16 — evals/harness/ablation-grade.sh — head line 283

Head context (head/evals/harness/ablation-grade.sh, lines 271–295):

~~~~text
   271 | def copy_tree(src, dst, top_exclude=frozenset()):
   272 |     """regular files, directories and symlinks only; caches dropped"""
   273 |     os.makedirs(dst, exist_ok=True)
   274 |     for root, dirs, files in os.walk(src, followlinks=False):
   275 |         rel = os.path.relpath(root, src)
   276 |         keep = []
   277 |         for d in sorted(dirs):
   278 |             if (rel == "." and d in top_exclude) or d in EXCLUDE_ANY:
   279 |                 continue
   280 |             sp = os.path.join(root, d)
   281 |             dp = os.path.join(dst, rel, d)
   282 |             if os.path.islink(sp):
>  283 |                 os.symlink(os.readlink(sp), dp)
   284 |                 continue
   285 |             os.makedirs(dp, exist_ok=True)
   286 |             keep.append(d)
   287 |         dirs[:] = keep
   288 |         for f in sorted(files):
   289 |             if rel == "." and f in top_exclude:
   290 |                 continue
   291 |             sp, dp = os.path.join(root, f), os.path.join(dst, rel, f)
   292 |             st = os.lstat(sp)
   293 |             if stat.S_ISLNK(st.st_mode):
   294 |                 os.symlink(os.readlink(sp), dp)
   295 |             elif stat.S_ISREG(st.st_mode):
~~~~

The change from head to the fix:

~~~~diff
@@ -283 +428,5 @@
-                os.symlink(os.readlink(sp), dp)
+                target = os.readlink(sp)
+                if link_escapes(target, rel):
+                    dropped += 1
+                else:
+                    os.symlink(target, dp)
~~~~

## H17 — evals/harness/ablation-grade.sh — head lines 294–297

Head context (head/evals/harness/ablation-grade.sh, lines 282–309):

~~~~text
   282 |             if os.path.islink(sp):
   283 |                 os.symlink(os.readlink(sp), dp)
   284 |                 continue
   285 |             os.makedirs(dp, exist_ok=True)
   286 |             keep.append(d)
   287 |         dirs[:] = keep
   288 |         for f in sorted(files):
   289 |             if rel == "." and f in top_exclude:
   290 |                 continue
   291 |             sp, dp = os.path.join(root, f), os.path.join(dst, rel, f)
   292 |             st = os.lstat(sp)
   293 |             if stat.S_ISLNK(st.st_mode):
>  294 |                 os.symlink(os.readlink(sp), dp)
>  295 |             elif stat.S_ISREG(st.st_mode):
>  296 |                 shutil.copyfile(sp, dp)
>  297 |                 os.chmod(dp, (st.st_mode & 0o777) | 0o600)
   298 | 
   299 | 
   300 | def put_file(tree, rel, src):
   301 |     parts = safe_rel(rel)
   302 |     if parts is None:
   303 |         raise GradeError(f"unsafe path: {rel!r}")
   304 |     dst = ensure_parent(tree, parts)
   305 |     if os.path.lexists(dst):
   306 |         remove_path(dst)
   307 |     if os.path.isdir(src) and not os.path.islink(src):
   308 |         copy_tree(src, dst)
   309 |     else:
~~~~

The change from head to the fix:

~~~~diff
@@ -294,4 +443,12 @@
-                os.symlink(os.readlink(sp), dp)
+                target = os.readlink(sp)
+                if link_escapes(target, rel):
+                    dropped += 1
+                else:
+                    os.symlink(target, dp)
             elif stat.S_ISREG(st.st_mode):
+                if st.st_size > FILE_CAP:   # MEDIUM-A3: a sparse 1 TB file must not become a dense write
+                    OVERSIZED[0] += 1
+                    continue
                 shutil.copyfile(sp, dp)
                 os.chmod(dp, (st.st_mode & 0o777) | 0o600)
+    return dropped + drop_escaping_links(dst)
~~~~

## H18 — evals/harness/ablation-grade.sh — insertion after head line 386

Head context (head/evals/harness/ablation-grade.sh, lines 375–398):

~~~~text
   375 |     sc = t.spec.get("structural_check")
   376 |     if sc:
   377 |         sp = safe_rel(sc)
   378 |         if sp is None or sp[0] != "hidden":
   379 |             raise GradeError(f"structural_check must be under hidden/: {sc}")
   380 |         src = "/".join(sp[1:])
   381 |         dest = next((d for s, d, _f in t.overlay if s == src), None)
   382 |         if dest is None:
   383 |             raise GradeError(f"structural_check {sc} is not overlaid by hidden/manifest.json")
   384 |         t.structural = dest
   385 |     if t.type == "refactor" and not t.structural:
   386 |         raise GradeError("refactor task has no structural_check")
   387 |     t.reference_patch = None
   388 |     rp = t.spec.get("reference_patch")
   389 |     if rp:
   390 |         parts = safe_rel(rp)
   391 |         if parts is None:
   392 |             raise GradeError(f"reference_patch: unsafe path {rp!r}")
   393 |         t.reference_patch = os.path.join(t.dir, *parts)
   394 |     # the hidden test files' static case count (structural check excluded)
   395 |     t.static_cases = 0
   396 |     for s, d, full in t.overlay:
   397 |         if d == t.structural or not os.path.isfile(full):
   398 |             continue
~~~~

The change from head to the fix:

~~~~diff
@@ -386,0 +544 @@
+    t.structural_full = next((f for _s, d, f in t.overlay if d == t.structural), None) if t.structural else None
~~~~

## H19 — evals/harness/ablation-grade.sh — insertion after head line 399

Head context (head/evals/harness/ablation-grade.sh, lines 388–411):

~~~~text
   388 |     rp = t.spec.get("reference_patch")
   389 |     if rp:
   390 |         parts = safe_rel(rp)
   391 |         if parts is None:
   392 |             raise GradeError(f"reference_patch: unsafe path {rp!r}")
   393 |         t.reference_patch = os.path.join(t.dir, *parts)
   394 |     # the hidden test files' static case count (structural check excluded)
   395 |     t.static_cases = 0
   396 |     for s, d, full in t.overlay:
   397 |         if d == t.structural or not os.path.isfile(full):
   398 |             continue
   399 |         t.static_cases += count_cases(full)
   400 |     t.rc = None
   401 |     if t.type == "review-catch":
   402 |         rc = t.spec.get("review_catch")
   403 |         if not isinstance(rc, dict) or not rc.get("manifest"):
   404 |             raise GradeError("review-catch task has no review_catch.manifest")
   405 |         t.rc = rc
   406 |         mp = None
   407 |         for cand in (os.path.join(REPO_ROOT, rc["manifest"]), os.path.join(t.suite_root, rc["manifest"]),
   408 |                      os.path.join(t.dir, rc["manifest"])):
   409 |             if os.path.isfile(cand):
   410 |                 mp = os.path.abspath(cand)
   411 |                 break
~~~~

The change from head to the fix:

~~~~diff
@@ -399,0 +558 @@
+    t.structural_cases = count_cases(t.structural_full) if t.structural_full else 0
~~~~

## H20 — evals/harness/ablation-grade.sh — head line 493

Head context (head/evals/harness/ablation-grade.sh, lines 481–505):

~~~~text
   481 | 
   482 | def shape_command(cmd, root):
   483 |     """the argv that runs inside the tree; root = /workspace (container) or the tree (host)"""
   484 |     host = A.executor == "host"
   485 |     rest = None
   486 |     if cmd[:3] == ["python3", "-m", "pytest"]:
   487 |         rest = cmd[3:]
   488 |     elif cmd[0] == "pytest":
   489 |         rest = cmd[1:]
   490 |     if rest is not None:
   491 |         rest = [x for x in rest if x not in ("-q", "--quiet")]
   492 |         pre = ["python3", "-P"] if host else ["python3", "-I", "-s"]
>  493 |         return pre + ["-m", "pytest", "-p", "no:cacheprovider", "-q", "--rootdir", root, "-rA"] + rest, "pytest"
   494 |     if cmd[0] == "bats":
   495 |         rest = cmd[1:]
   496 |         if "--tap" in rest or any(x.startswith("--formatter") or x == "-F" for x in rest):
   497 |             return list(cmd), "tap"
   498 |         return ["bats", "--tap"] + rest, "tap"
   499 |     return list(cmd), "auto"
   500 | 
   501 | 
   502 | def exec_in_tree(tree, cmd):
   503 |     """→ (rc, output, timed_out, kind)"""
   504 |     if A.executor == "container":
   505 |         argv, kind = shape_command(cmd, "/workspace")
~~~~

The change from head to the fix:

~~~~diff
@@ -493 +652,3 @@
-        return pre + ["-m", "pytest", "-p", "no:cacheprovider", "-q", "--rootdir", root, "-rA"] + rest, "pytest"
+        # -o addopts= : an ini file's addopts cannot inject a plugin or deselect (HIGH-A1)
+        return pre + ["-m", "pytest", "-p", "no:cacheprovider", "-o", "addopts=", "-q", "--rootdir", root,
+                      "-rA"] + rest, "pytest"
~~~~

## H21 — evals/harness/ablation-grade.sh — head lines 502–508

Head context (head/evals/harness/ablation-grade.sh, lines 490–520):

~~~~text
   490 |     if rest is not None:
   491 |         rest = [x for x in rest if x not in ("-q", "--quiet")]
   492 |         pre = ["python3", "-P"] if host else ["python3", "-I", "-s"]
   493 |         return pre + ["-m", "pytest", "-p", "no:cacheprovider", "-q", "--rootdir", root, "-rA"] + rest, "pytest"
   494 |     if cmd[0] == "bats":
   495 |         rest = cmd[1:]
   496 |         if "--tap" in rest or any(x.startswith("--formatter") or x == "-F" for x in rest):
   497 |             return list(cmd), "tap"
   498 |         return ["bats", "--tap"] + rest, "tap"
   499 |     return list(cmd), "auto"
   500 | 
   501 | 
>  502 | def exec_in_tree(tree, cmd):
>  503 |     """→ (rc, output, timed_out, kind)"""
>  504 |     if A.executor == "container":
>  505 |         argv, kind = shape_command(cmd, "/workspace")
>  506 |         full = [A.docker_bin, "run", "--rm", "--network", "none", "--read-only", "--tmpfs", "/tmp:rw,size=256m",
>  507 |                 "--user", f"{os.getuid()}:{os.getgid()}", "-v", f"{tree}:/workspace:rw", "-w", "/workspace",
>  508 |                 "-e", "HOME=/tmp", "-e", "LC_ALL=C", "-e", "TMPDIR=/tmp", A.image, "timeout", str(TEST_TIMEOUT_S)] + argv
   509 |         cwd = None
   510 |     else:
   511 |         argv, kind = shape_command(cmd, tree)
   512 |         home = tempfile.mkdtemp(prefix="home.", dir=SCRATCH)
   513 |         full = ["env", "-i", "PATH=" + os.environ.get("PATH", "/usr/bin:/bin"), "HOME=" + home, "LC_ALL=C",
   514 |                 "TMPDIR=" + home, "PYTHONUSERBASE=" + site.getuserbase(), "timeout", str(TEST_TIMEOUT_S)] + argv
   515 |         cwd = tree
   516 |     try:
   517 |         p = subprocess.run(full, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
   518 |                            timeout=TEST_TIMEOUT_S + 60)
   519 |         out, rc = p.stdout.decode("utf-8", "replace"), p.returncode
   520 |     except subprocess.TimeoutExpired as e:
~~~~

The change from head to the fix:

~~~~diff
@@ -502,7 +663,55 @@
+RUN_TAG = ["run"]   # the run directory's basename, sanitised: part of every container name
+EXEC_SEQ = [0]
+
+
+def container_name(tree):
+    """ablgrade-<run>-<label>-<pid>-<n>: letters, digits, '.', '_', '-' only"""
+    EXEC_SEQ[0] += 1
+    raw = f"ablgrade-{RUN_TAG[0]}-{os.path.basename(tree.rstrip('/'))}-{os.getpid()}-{EXEC_SEQ[0]}"
+    return re.sub(r"[^A-Za-z0-9._-]", "-", raw)[:128]
+
+
+def drain(fd, cap, box):
+    """read fd to EOF in chunks, keeping the first and the last cap/2 bytes (the summary
+    and the -rA outcome lines are at the end) → box = [(bytes, truncated)]"""
+    head, tail, half, trunc = bytearray(), bytearray(), cap // 2, False
+    while True:
+        try:
+            b = os.read(fd, 1 << 16)
+        except OSError:
+            break
+        if not b:
+            break
+        if len(head) < half:
+            k = half - len(head)
+            head += b[:k]
+            b = b[k:]
+        if b:
+            tail += b
+            if len(tail) > half:
+                del tail[:len(tail) - half]
+                trunc = True
+    box.append((bytes(head) + (b"\n[output truncated]\n" if trunc else b"") + bytes(tail), trunc))
+
+
+def docker_cleanup(name):
+    for extra in (["kill", name], ["rm", "-f", name]):
+        try:
+            subprocess.run([A.docker_bin] + extra, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
+                           stdin=subprocess.DEVNULL, timeout=60)
+        except (OSError, subprocess.SubprocessError):
+            pass
+
+
 def exec_in_tree(tree, cmd):
-    """→ (rc, output, timed_out, kind)"""
+    """→ (rc, output, timed_out, kind, output_truncated)"""
+    deadline = ["timeout", "--signal=TERM", f"--kill-after={KILL_AFTER_S}", str(TEST_TIMEOUT_S)]
+    name = None
     if A.executor == "container":
         argv, kind = shape_command(cmd, "/workspace")
-        full = [A.docker_bin, "run", "--rm", "--network", "none", "--read-only", "--tmpfs", "/tmp:rw,size=256m",
+        name = container_name(tree)
+        full = [A.docker_bin, "run", "--rm", "--init", "--name", name, "--network", "none", "--read-only",
+                "--tmpfs", "/tmp:rw,size=256m", "--pids-limit", "256", "--memory", "2g", "--cpus", "2",
+                "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
                 "--user", f"{os.getuid()}:{os.getgid()}", "-v", f"{tree}:/workspace:rw", "-w", "/workspace",
-                "-e", "HOME=/tmp", "-e", "LC_ALL=C", "-e", "TMPDIR=/tmp", A.image, "timeout", str(TEST_TIMEOUT_S)] + argv
+                "-e", "HOME=/tmp", "-e", "LC_ALL=C", "-e", "TMPDIR=/tmp", A.image] + deadline + argv
~~~~

## H22 — evals/harness/ablation-grade.sh — head lines 514–524

Head context (head/evals/harness/ablation-grade.sh, lines 502–536):

~~~~text
   502 | def exec_in_tree(tree, cmd):
   503 |     """→ (rc, output, timed_out, kind)"""
   504 |     if A.executor == "container":
   505 |         argv, kind = shape_command(cmd, "/workspace")
   506 |         full = [A.docker_bin, "run", "--rm", "--network", "none", "--read-only", "--tmpfs", "/tmp:rw,size=256m",
   507 |                 "--user", f"{os.getuid()}:{os.getgid()}", "-v", f"{tree}:/workspace:rw", "-w", "/workspace",
   508 |                 "-e", "HOME=/tmp", "-e", "LC_ALL=C", "-e", "TMPDIR=/tmp", A.image, "timeout", str(TEST_TIMEOUT_S)] + argv
   509 |         cwd = None
   510 |     else:
   511 |         argv, kind = shape_command(cmd, tree)
   512 |         home = tempfile.mkdtemp(prefix="home.", dir=SCRATCH)
   513 |         full = ["env", "-i", "PATH=" + os.environ.get("PATH", "/usr/bin:/bin"), "HOME=" + home, "LC_ALL=C",
>  514 |                 "TMPDIR=" + home, "PYTHONUSERBASE=" + site.getuserbase(), "timeout", str(TEST_TIMEOUT_S)] + argv
>  515 |         cwd = tree
>  516 |     try:
>  517 |         p = subprocess.run(full, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
>  518 |                            timeout=TEST_TIMEOUT_S + 60)
>  519 |         out, rc = p.stdout.decode("utf-8", "replace"), p.returncode
>  520 |     except subprocess.TimeoutExpired as e:
>  521 |         out, rc = (e.stdout or b"").decode("utf-8", "replace"), 124
>  522 |     except OSError as e:
>  523 |         raise GradeError(f"cannot run {full[0]}: {e}")
>  524 |     return rc, out, rc == 124, kind
   525 | 
   526 | 
   527 | # ------------------------------------------------------------------ result parsing
   528 | SUMMARY_RX = re.compile(r"^=*\s*((?:\d+ [a-z]+(?:, )?)+) in [0-9.]+s(?: \([^)]*\))?\s*=*\s*$")
   529 | COUNT_RX = re.compile(r"(\d+) ([a-z]+)")
   530 | OUTCOME_RX = re.compile(r"^(PASSED|FAILED|ERROR|XFAIL|XPASS) (\S+)")
   531 | 
   532 | 
   533 | def def_line(tree, path, func, cache):
   534 |     if path not in cache:
   535 |         try:
   536 |             cache[path] = open(os.path.join(tree, path), encoding="utf-8", errors="replace").read().splitlines()
~~~~

The change from head to the fix:

~~~~diff
@@ -514,11 +723,36 @@
-                "TMPDIR=" + home, "PYTHONUSERBASE=" + site.getuserbase(), "timeout", str(TEST_TIMEOUT_S)] + argv
+                "TMPDIR=" + home, "PYTHONUSERBASE=" + site.getuserbase()] + deadline + argv
         cwd = tree
     try:
-        p = subprocess.run(full, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
-                           timeout=TEST_TIMEOUT_S + 60)
-        out, rc = p.stdout.decode("utf-8", "replace"), p.returncode
-    except subprocess.TimeoutExpired as e:
-        out, rc = (e.stdout or b"").decode("utf-8", "replace"), 124
+        proc = subprocess.Popen(full, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
+                                stdin=subprocess.DEVNULL, start_new_session=True)
     except OSError as e:
         raise GradeError(f"cannot run {full[0]}: {e}")
-    return rc, out, rc == 124, kind
+    box = []
+    reader = threading.Thread(target=drain, args=(proc.stdout.fileno(), OUTPUT_CAP, box), daemon=True)
+    reader.start()
+    started, exited, timed_out, rc = time.monotonic(), False, False, 124
+    try:
+        try:
+            rc = proc.wait(timeout=TEST_TIMEOUT_S + KILL_AFTER_S + OUTER_GRACE_S)
+            exited = True
+        except subprocess.TimeoutExpired:
+            timed_out = True
+    finally:
+        if not exited:   # the client is killed; the container (which --rm does not stop) is killed and removed
+            try:
+                os.killpg(proc.pid, 9)
+            except OSError:
+                pass
+            try:
+                proc.wait(timeout=30)
+            except subprocess.TimeoutExpired:
+                pass
+            if name:
+                docker_cleanup(name)
+        reader.join(timeout=30)
+        if not reader.is_alive():
+            proc.stdout.close()
+    out, trunc = box[0] if box else (b"", False)
+    # timeout(1): 124 after TERM; 128+9 when the command outlived --kill-after
+    timed_out = timed_out or rc == 124 or (rc == 137 and time.monotonic() - started >= TEST_TIMEOUT_S)
+    return rc, out.decode("utf-8", "replace"), timed_out, kind, trunc
~~~~

## H23 — evals/harness/ablation-grade.sh — head lines 533–538

Head context (head/evals/harness/ablation-grade.sh, lines 521–550):

~~~~text
   521 |         out, rc = (e.stdout or b"").decode("utf-8", "replace"), 124
   522 |     except OSError as e:
   523 |         raise GradeError(f"cannot run {full[0]}: {e}")
   524 |     return rc, out, rc == 124, kind
   525 | 
   526 | 
   527 | # ------------------------------------------------------------------ result parsing
   528 | SUMMARY_RX = re.compile(r"^=*\s*((?:\d+ [a-z]+(?:, )?)+) in [0-9.]+s(?: \([^)]*\))?\s*=*\s*$")
   529 | COUNT_RX = re.compile(r"(\d+) ([a-z]+)")
   530 | OUTCOME_RX = re.compile(r"^(PASSED|FAILED|ERROR|XFAIL|XPASS) (\S+)")
   531 | 
   532 | 
>  533 | def def_line(tree, path, func, cache):
>  534 |     if path not in cache:
>  535 |         try:
>  536 |             cache[path] = open(os.path.join(tree, path), encoding="utf-8", errors="replace").read().splitlines()
>  537 |         except OSError:
>  538 |             cache[path] = []
   539 |     rx = re.compile(r"^\s*(?:async\s+)?def\s+" + re.escape(func) + r"\s*\(")
   540 |     for i, l in enumerate(cache[path], 1):
   541 |         if rx.match(l):
   542 |             return i
   543 |     return 10 ** 9
   544 | 
   545 | 
   546 | def parse_pytest(out, tree):
   547 |     lines = out.splitlines()
   548 |     summary = None
   549 |     for l in reversed(lines):
   550 |         m = SUMMARY_RX.match(l.strip())
~~~~

The change from head to the fix:

~~~~diff
@@ -533,6 +767,20 @@
+GRADER_SOURCES = {}   # rel path in a grading tree → the grader-owned copy (hidden overlay, protected fixture file)
+
+
+def node_text(tree, path):
+    """the text of a test file a pytest node id names (MEDIUM-A2). The node path comes from the
+    captured stdout, which the agent's code can print: a grader-owned source is read first;
+    else the path must be relative, stay inside the tree and be a regular file of at most
+    NODE_FILE_CAP bytes (never a FIFO, a device or a symlink) → str | None"""
+    parts = safe_rel(path)
+    if parts is None:
+        return None
+    own = GRADER_SOURCES.get("/".join(parts))
+    if own is not None:
+        return read_regular(own, NODE_FILE_CAP, whole=True)
+    return read_regular(os.path.join(tree, *parts), NODE_FILE_CAP, whole=True, root=tree)
+
+
 def def_line(tree, path, func, cache):
     if path not in cache:
-        try:
-            cache[path] = open(os.path.join(tree, path), encoding="utf-8", errors="replace").read().splitlines()
-        except OSError:
-            cache[path] = []
+        cache[path] = (node_text(tree, path) or "").splitlines()
~~~~

## H24 — evals/harness/ablation-grade.sh — head lines 575–577

Head context (head/evals/harness/ablation-grade.sh, lines 563–589):

~~~~text
   563 |         if not m:
   564 |             continue
   565 |         kind, node = m.group(1), m.group(2)
   566 |         if kind == "ERROR" and "::" not in node:
   567 |             coll_err.append(node)
   568 |             continue
   569 |         prev = outcomes.get(node)
   570 |         bad = kind in ("FAILED", "ERROR")
   571 |         outcomes[node] = "bad" if (bad or prev == "bad") else "ok"
   572 |     cache = {}
   573 |     expanded = 0
   574 |     for f in coll_err:
>  575 |         try:
>  576 |             text = open(os.path.join(tree, f), encoding="utf-8", errors="replace").read()
>  577 |         except OSError:
   578 |             continue
   579 |         for fn in re.findall(r"(?m)^\s*(?:async\s+)?def\s+(test\w*)\s*\(", text):
   580 |             outcomes.setdefault(f"{f}::{fn}", "bad")
   581 |             expanded += 1
   582 | 
   583 |     def key(node):
   584 |         path, _, rest = node.partition("::")
   585 |         func = rest.split("::")[-1].split("[")[0]
   586 |         return (path, def_line(tree, path, func, cache), node)
   587 |     order = sorted(outcomes, key=key)
   588 |     total = sum(norm.get(k, 0) for k in ("passed", "failed", "errors", "skipped", "xfailed", "xpassed"))
   589 |     total = total - len(coll_err) + expanded
~~~~

The change from head to the fix:

~~~~diff
@@ -575,3 +823,2 @@
-        try:
-            text = open(os.path.join(tree, f), encoding="utf-8", errors="replace").read()
-        except OSError:
+        text = node_text(tree, f)
+        if text is None:
~~~~

## H25 — evals/harness/ablation-grade.sh — head line 625

Head context (head/evals/harness/ablation-grade.sh, lines 613–637):

~~~~text
   613 |         return None
   614 |     total = plan if plan is not None else len(seen)
   615 |     if total == 0:
   616 |         return None
   617 |     nums = sorted(set(range(1, total + 1)) | set(seen))
   618 |     names = {n: (seen[n][1] if n in seen else f"#{n}") for n in nums}
   619 |     order = [names[n] for n in nums]
   620 |     bad = {names[n] for n in nums if n not in seen or not seen[n][0]}
   621 |     return {"passed": sum(1 for n in seen if seen[n][0]), "total": total, "order": order, "bad": bad}
   622 | 
   623 | 
   624 | def run_suite(tree, cmd, static=0):
>  625 |     rc, out, timed_out, kind = exec_in_tree(tree, cmd)
   626 |     parsed = None
   627 |     if kind in ("pytest", "auto"):
   628 |         parsed = parse_pytest(out, tree)
   629 |     if parsed is None and kind in ("tap", "auto"):
   630 |         parsed = parse_tap(out)
   631 |     if parsed is None:
   632 |         total = max(static, 1)
   633 |         passed = total if rc == 0 else 0
   634 |         order = [f"#{i}" for i in range(1, total + 1)]
   635 |         return {"passed": passed, "total": total, "order": order, "bad": set(order) if rc != 0 else set(),
   636 |                 "parse_error": True, "timed_out": timed_out, "rc": rc}
   637 |     parsed["total"] = max(parsed["total"], static)
~~~~

The change from head to the fix:

~~~~diff
@@ -625 +872 @@
-    rc, out, timed_out, kind = exec_in_tree(tree, cmd)
+    rc, out, timed_out, kind, trunc = exec_in_tree(tree, cmd)
~~~~

## H26 — evals/harness/ablation-grade.sh — head lines 636–638

Head context (head/evals/harness/ablation-grade.sh, lines 624–650):

~~~~text
   624 | def run_suite(tree, cmd, static=0):
   625 |     rc, out, timed_out, kind = exec_in_tree(tree, cmd)
   626 |     parsed = None
   627 |     if kind in ("pytest", "auto"):
   628 |         parsed = parse_pytest(out, tree)
   629 |     if parsed is None and kind in ("tap", "auto"):
   630 |         parsed = parse_tap(out)
   631 |     if parsed is None:
   632 |         total = max(static, 1)
   633 |         passed = total if rc == 0 else 0
   634 |         order = [f"#{i}" for i in range(1, total + 1)]
   635 |         return {"passed": passed, "total": total, "order": order, "bad": set(order) if rc != 0 else set(),
>  636 |                 "parse_error": True, "timed_out": timed_out, "rc": rc}
>  637 |     parsed["total"] = max(parsed["total"], static)
>  638 |     parsed.update(parse_error=False, timed_out=timed_out, rc=rc)
   639 |     return parsed
   640 | 
   641 | 
   642 | def ids_of(res, keys):
   643 |     pos = {k: i for i, k in enumerate(res["order"], 1)}
   644 |     return sorted((f"t{pos[k]}" for k in keys if k in pos), key=lambda s: int(s[1:]))
   645 | 
   646 | 
   647 | def summary(res):
   648 |     return {"passed": res["passed"], "total": res["total"], "failed_names": ids_of(res, res["bad"]),
   649 |             "parse_error": res["parse_error"], "timed_out": res["timed_out"]}
   650 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -636,3 +883,3 @@
-                "parse_error": True, "timed_out": timed_out, "rc": rc}
+                "parse_error": True, "timed_out": timed_out, "rc": rc, "output_truncated": trunc}
     parsed["total"] = max(parsed["total"], static)
-    parsed.update(parse_error=False, timed_out=timed_out, rc=rc)
+    parsed.update(parse_error=False, timed_out=timed_out, rc=rc, output_truncated=trunc)
~~~~

## H27 — evals/harness/ablation-grade.sh — head lines 649–653

Head context (head/evals/harness/ablation-grade.sh, lines 637–665):

~~~~text
   637 |     parsed["total"] = max(parsed["total"], static)
   638 |     parsed.update(parse_error=False, timed_out=timed_out, rc=rc)
   639 |     return parsed
   640 | 
   641 | 
   642 | def ids_of(res, keys):
   643 |     pos = {k: i for i, k in enumerate(res["order"], 1)}
   644 |     return sorted((f"t{pos[k]}" for k in keys if k in pos), key=lambda s: int(s[1:]))
   645 | 
   646 | 
   647 | def summary(res):
   648 |     return {"passed": res["passed"], "total": res["total"], "failed_names": ids_of(res, res["bad"]),
>  649 |             "parse_error": res["parse_error"], "timed_out": res["timed_out"]}
>  650 | 
>  651 | 
>  652 | def all_pass(res):
>  653 |     return res["passed"] >= res["total"] and not res["bad"] and not res["parse_error"]
   654 | 
   655 | 
   656 | # ------------------------------------------------------------------ grading trees
   657 | def prepare(t, tree):
   658 |     for rel in t.protected:
   659 |         src = os.path.join(t.fixture, *rel.split("/"))
   660 |         if os.path.lexists(src) and not os.path.islink(src):
   661 |             put_file(tree, rel, src)
   662 |         else:
   663 |             parts = rel.split("/")
   664 |             cur = tree
   665 |             ok = True
~~~~

The change from head to the fix:

~~~~diff
@@ -649,5 +896,35 @@
-            "parse_error": res["parse_error"], "timed_out": res["timed_out"]}
+            "parse_error": res["parse_error"], "timed_out": res["timed_out"], "rc": res["rc"],
+            "output_truncated": res["output_truncated"]}
 
 
 def all_pass(res):
-    return res["passed"] >= res["total"] and not res["bad"] and not res["parse_error"]
+    """every case passed, the summary parsed, and the command exited 0 within its time
+    (a passing TAP block followed by exit 1, or a timeout, is not green: DISS-002)"""
+    if res is None:
+        return False
+    return (res["passed"] >= res["total"] and not res["bad"] and not res["parse_error"]
+            and res["rc"] == 0 and not res["timed_out"])
+
+
+def run_counts(res):
+    return {"passed": res["passed"], "total": res["total"], "rc": res["rc"], "timed_out": res["timed_out"],
+            "output_truncated": res["output_truncated"]}
+
+
+def regressions(rb, rf):
+    """base run rb vs final run rf of the regression command. Parsed on both sides:
+    newly_failing = base-passing cases failing (or absent) at final. Either side
+    unparseable (DISS-003): base unparsed → every fallback id when the base exited 0 and
+    the final run failed (non-zero exit or timeout); base parsed, final unparsed → every
+    base-passing case when the final run failed; else none. parse_error records it."""
+    final_red = rf["rc"] != 0 or rf["timed_out"]
+    base_ok = [k for k in rb["order"] if k not in rb["bad"]]
+    pe = bool(rb["parse_error"] or rf["parse_error"])
+    if not pe:
+        newly = [k for k in base_ok if k in rf["bad"] or k not in rf["order"]]
+    elif rb["parse_error"]:
+        newly = list(rb["order"]) if (rb["rc"] == 0 and not rb["timed_out"] and final_red) else []
+    else:
+        newly = base_ok if final_red else []
+    return {"newly_failing": ids_of(rb, newly), "base": run_counts(rb), "final": run_counts(rf), "parse_error": pe,
+            "base_green": all_pass(rb), "final_green": all_pass(rf)}
~~~~

## H28 — evals/harness/ablation-grade.sh — insertion after head line 674

Head context (head/evals/harness/ablation-grade.sh, lines 663–686):

~~~~text
   663 |             parts = rel.split("/")
   664 |             cur = tree
   665 |             ok = True
   666 |             for comp in parts[:-1]:
   667 |                 cur = os.path.join(cur, comp)
   668 |                 if os.path.islink(cur) or not os.path.isdir(cur):
   669 |                     ok = False
   670 |                     break
   671 |             if ok and os.path.lexists(os.path.join(tree, *parts)):
   672 |                 remove_path(os.path.join(tree, *parts))
   673 |     for _s, dest, full in t.overlay:
   674 |         put_file(tree, dest, full)
   675 | 
   676 | 
   677 | def git_env(home):
   678 |     return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "LC_ALL": "C",
   679 |             "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
   680 | 
   681 | 
   682 | def extract_snapshot(run_dir, label, commit, tree):
   683 |     snaps = os.path.join(run_dir, "snapshots")
   684 |     bundle = None
   685 |     for name in (label.upper() + ".bundle", label + ".bundle"):
   686 |         p = os.path.join(snaps, name)
~~~~

The change from head to the fix:

~~~~diff
@@ -674,0 +952,49 @@
+    return remove_harness(t, tree)
+
+
+def is_harness(parts):
+    """a file pytest or bats would load from the tree as configuration or helper code"""
+    name = parts[-1]
+    if name in HARNESS_NAMES:
+        return True
+    if "helper" in name and name.endswith((".bash", ".sh")):
+        return True
+    return name.endswith(".bash") and any(p in ("tests", "test") for p in parts[:-1])
+
+
+def same_as_fixture(t, tree, rel):
+    a, b = os.path.join(tree, *rel.split("/")), os.path.join(t.fixture, *rel.split("/"))
+    try:
+        sa, sb = os.lstat(a), os.lstat(b)
+    except OSError:
+        return False
+    if not (stat.S_ISREG(sa.st_mode) and stat.S_ISREG(sb.st_mode)) or not is_within(b, t.fixture):
+        return False
+    return filecmp.cmp(a, b, shallow=False)
+
+
+def remove_harness(t, tree):
+    """HIGH-A1: before any command runs on a grading tree, every harness or config file
+    (is_harness) that is not byte-identical to the fixture's copy at the same path is removed
+    (a symlink always is; the hidden overlay's own dests are kept). The removed paths go to
+    grading/<label>.harness-removed.txt beside the tree, never into grade.json → count"""
+    owned = {d for _s, d, _f in t.overlay}
+    owned_dirs = tuple(d + "/" for _s, d, f in t.overlay if os.path.isdir(f))   # put_file rewrote these whole
+    found = []
+    for r, ds, fs in os.walk(tree, followlinks=False):
+        relr = os.path.relpath(r, tree)
+        for name in sorted(ds + fs):
+            rel = name if relr == "." else relr.replace(os.sep, "/") + "/" + name
+            p = os.path.join(r, name)
+            if rel in owned or rel.startswith(owned_dirs) or not is_harness(rel.split("/")):
+                continue
+            if os.path.isdir(p) and not os.path.islink(p):
+                continue
+            if same_as_fixture(t, tree, rel):
+                continue
+            found.append((rel, p))
+    for _rel, p in found:
+        os.unlink(p)
+    with open(tree.rstrip("/") + ".harness-removed.txt", "w", encoding="utf-8") as f:
+        f.write("".join(rel + "\n" for rel, _p in sorted(found)))
+    return len(found)
~~~~

## H29 — evals/harness/ablation-grade.sh — insertion after head line 681

Head context (head/evals/harness/ablation-grade.sh, lines 670–693):

~~~~text
   670 |                     break
   671 |             if ok and os.path.lexists(os.path.join(tree, *parts)):
   672 |                 remove_path(os.path.join(tree, *parts))
   673 |     for _s, dest, full in t.overlay:
   674 |         put_file(tree, dest, full)
   675 | 
   676 | 
   677 | def git_env(home):
   678 |     return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": home, "LC_ALL": "C",
   679 |             "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
   680 | 
   681 | 
   682 | def extract_snapshot(run_dir, label, commit, tree):
   683 |     snaps = os.path.join(run_dir, "snapshots")
   684 |     bundle = None
   685 |     for name in (label.upper() + ".bundle", label + ".bundle"):
   686 |         p = os.path.join(snaps, name)
   687 |         if os.path.isfile(p) and not os.path.islink(p):
   688 |             bundle = p
   689 |             break
   690 |     if bundle is None or not re.match(r"^[0-9a-f]{7,64}$", commit or ""):
   691 |         return False
   692 |     g = tempfile.mkdtemp(prefix="git.", dir=SCRATCH)
   693 |     env = git_env(g)
~~~~

The change from head to the fix:

~~~~diff
@@ -681,0 +1008,3 @@
+SNAPSHOT_LINKS_DROPPED = [0]   # escaping links removed from snapshot trees in this grade
+
+
~~~~

## H30 — evals/harness/ablation-grade.sh — insertion after head line 708

Head context (head/evals/harness/ablation-grade.sh, lines 697–720):

~~~~text
   697 |         return False
   698 |     tarp = os.path.join(g, "snap.tar")
   699 |     with open(tarp, "wb") as f:
   700 |         if subprocess.run(["git", "-C", g, "archive", "--format=tar", commit], stdout=f, stderr=subprocess.DEVNULL,
   701 |                           env=env).returncode != 0:
   702 |             return False
   703 |     os.makedirs(tree, exist_ok=True)
   704 | 
   705 |     def keep(member, path):
   706 |         parts = safe_rel(member.name)
   707 |         if parts is None or parts[0] in EXCLUDE_TOP or any(x in EXCLUDE_ANY for x in parts):
   708 |             return None
   709 |         try:
   710 |             return tarfile.data_filter(member, path)
   711 |         except tarfile.FilterError:
   712 |             return None
   713 |     with tarfile.open(tarp) as tf:
   714 |         tf.extractall(tree, filter=keep)
   715 |     return True
   716 | 
   717 | 
   718 | # ------------------------------------------------------------------ churn
   719 | def churn(a, b):
   720 |     def listing(root):
~~~~

The change from head to the fix:

~~~~diff
@@ -708,0 +1038,3 @@
+        if member.isfile() and member.size > FILE_CAP:
+            OVERSIZED[0] += 1
+            return None
~~~~

## H31 — evals/harness/ablation-grade.sh — insertion after head line 714

Head context (head/evals/harness/ablation-grade.sh, lines 703–726):

~~~~text
   703 |     os.makedirs(tree, exist_ok=True)
   704 | 
   705 |     def keep(member, path):
   706 |         parts = safe_rel(member.name)
   707 |         if parts is None or parts[0] in EXCLUDE_TOP or any(x in EXCLUDE_ANY for x in parts):
   708 |             return None
   709 |         try:
   710 |             return tarfile.data_filter(member, path)
   711 |         except tarfile.FilterError:
   712 |             return None
   713 |     with tarfile.open(tarp) as tf:
   714 |         tf.extractall(tree, filter=keep)
   715 |     return True
   716 | 
   717 | 
   718 | # ------------------------------------------------------------------ churn
   719 | def churn(a, b):
   720 |     def listing(root):
   721 |         out = {}
   722 |         for r, ds, fs in os.walk(root, followlinks=False):
   723 |             ds[:] = [d for d in ds if d not in EXCLUDE_ANY and not os.path.islink(os.path.join(r, d))]
   724 |             for name in fs + [d for d in os.listdir(r) if os.path.islink(os.path.join(r, d)) and os.path.isdir(os.path.join(r, d))]:
   725 |                 p = os.path.join(r, name)
   726 |                 out[os.path.relpath(p, root)] = p
~~~~

The change from head to the fix:

~~~~diff
@@ -714,0 +1047,3 @@
+    # round 2 DISS-C-001: data_filter judges members in archive order, so a link that escapes
+    # only through a later link slips past it; the same realpath pass as the final copy runs here
+    SNAPSHOT_LINKS_DROPPED[0] += drop_escaping_links(tree)
~~~~

## H32 — evals/harness/ablation-grade.sh — insertion after head line 718

Head context (head/evals/harness/ablation-grade.sh, lines 707–730):

~~~~text
   707 |         if parts is None or parts[0] in EXCLUDE_TOP or any(x in EXCLUDE_ANY for x in parts):
   708 |             return None
   709 |         try:
   710 |             return tarfile.data_filter(member, path)
   711 |         except tarfile.FilterError:
   712 |             return None
   713 |     with tarfile.open(tarp) as tf:
   714 |         tf.extractall(tree, filter=keep)
   715 |     return True
   716 | 
   717 | 
   718 | # ------------------------------------------------------------------ churn
   719 | def churn(a, b):
   720 |     def listing(root):
   721 |         out = {}
   722 |         for r, ds, fs in os.walk(root, followlinks=False):
   723 |             ds[:] = [d for d in ds if d not in EXCLUDE_ANY and not os.path.islink(os.path.join(r, d))]
   724 |             for name in fs + [d for d in os.listdir(r) if os.path.islink(os.path.join(r, d)) and os.path.isdir(os.path.join(r, d))]:
   725 |                 p = os.path.join(r, name)
   726 |                 out[os.path.relpath(p, root)] = p
   727 |         return out
   728 |     def content(p):
   729 |         if os.path.islink(p):
   730 |             return ("link:" + os.readlink(p)).encode()
~~~~

The change from head to the fix:

~~~~diff
@@ -718,0 +1054,3 @@
+OVER = object()   # churn's marker for a file above FILE_CAP
+
+
~~~~

## H33 — evals/harness/ablation-grade.sh — head lines 729–732

Head context (head/evals/harness/ablation-grade.sh, lines 717–744):

~~~~text
   717 | 
   718 | # ------------------------------------------------------------------ churn
   719 | def churn(a, b):
   720 |     def listing(root):
   721 |         out = {}
   722 |         for r, ds, fs in os.walk(root, followlinks=False):
   723 |             ds[:] = [d for d in ds if d not in EXCLUDE_ANY and not os.path.islink(os.path.join(r, d))]
   724 |             for name in fs + [d for d in os.listdir(r) if os.path.islink(os.path.join(r, d)) and os.path.isdir(os.path.join(r, d))]:
   725 |                 p = os.path.join(r, name)
   726 |                 out[os.path.relpath(p, root)] = p
   727 |         return out
   728 |     def content(p):
>  729 |         if os.path.islink(p):
>  730 |             return ("link:" + os.readlink(p)).encode()
>  731 |         try:
>  732 |             return open(p, "rb").read()
   733 |         except OSError:
   734 |             return b""
   735 |     def lines(bs):
   736 |         try:
   737 |             return bs.decode("utf-8").splitlines()
   738 |         except UnicodeDecodeError:
   739 |             return None
   740 |     la, lb = listing(a), listing(b)
   741 |     files = diff = 0
   742 |     for rel in sorted(set(la) | set(lb)):
   743 |         ca = content(la[rel]) if rel in la else None
   744 |         cb = content(lb[rel]) if rel in lb else None
~~~~

The change from head to the fix:

~~~~diff
@@ -729,4 +1067,13 @@
-        if os.path.islink(p):
-            return ("link:" + os.readlink(p)).encode()
         try:
-            return open(p, "rb").read()
+            st = os.lstat(p)
+        except OSError:
+            return b""
+        if stat.S_ISLNK(st.st_mode):
+            return ("link:" + os.readlink(p)).encode()
+        if not stat.S_ISREG(st.st_mode):
+            return b""
+        if st.st_size > FILE_CAP:   # MEDIUM-A3: counted as changed, never read or diffed
+            return OVER
+        try:
+            with open(p, "rb") as f:
+                return f.read(FILE_CAP + 1)
~~~~

## H34 — evals/harness/ablation-grade.sh — insertion after head line 744

Head context (head/evals/harness/ablation-grade.sh, lines 733–756):

~~~~text
   733 |         except OSError:
   734 |             return b""
   735 |     def lines(bs):
   736 |         try:
   737 |             return bs.decode("utf-8").splitlines()
   738 |         except UnicodeDecodeError:
   739 |             return None
   740 |     la, lb = listing(a), listing(b)
   741 |     files = diff = 0
   742 |     for rel in sorted(set(la) | set(lb)):
   743 |         ca = content(la[rel]) if rel in la else None
   744 |         cb = content(lb[rel]) if rel in lb else None
   745 |         if ca == cb:
   746 |             continue
   747 |         files += 1
   748 |         xa = lines(ca) if ca is not None else []
   749 |         xb = lines(cb) if cb is not None else []
   750 |         if xa is None or xb is None:
   751 |             continue
   752 |         for l in difflib.unified_diff(xa, xb, lineterm="", n=0):
   753 |             if l.startswith(("+++", "---", "@@")):
   754 |                 continue
   755 |             if l.startswith(("+", "-")):
   756 |                 diff += 1
~~~~

The change from head to the fix:

~~~~diff
@@ -744,0 +1092,3 @@
+        if ca is OVER or cb is OVER:
+            files += 1
+            continue
~~~~

## H35 — evals/harness/ablation-grade.sh — head lines 764–769

Head context (head/evals/harness/ablation-grade.sh, lines 752–781):

~~~~text
   752 |         for l in difflib.unified_diff(xa, xb, lineterm="", n=0):
   753 |             if l.startswith(("+++", "---", "@@")):
   754 |                 continue
   755 |             if l.startswith(("+", "-")):
   756 |                 diff += 1
   757 |     return diff, files
   758 | 
   759 | 
   760 | # ------------------------------------------------------------------ verdicts
   761 | TRAILER_LINE = re.compile(r"<!-- LOA-VERDICT (\{.*\}) -->\s*$")
   762 | 
   763 | 
>  764 | def gate_verdict(path):
>  765 |     """→ None (no file) | APPROVED | CHANGES_REQUIRED | none"""
>  766 |     if not os.path.isfile(path):
>  767 |         return None
>  768 |     last = None
>  769 |     for l in open(path, encoding="utf-8", errors="replace"):
   770 |         m = TRAILER_LINE.search(l.rstrip("\n"))
   771 |         if m:
   772 |             last = m.group(1)
   773 |     if last is None:
   774 |         return "none"
   775 |     try:
   776 |         v = json.loads(last).get("verdict")
   777 |     except (ValueError, AttributeError):
   778 |         return "none"
   779 |     return v if v in ("APPROVED", "CHANGES_REQUIRED") else "none"
   780 | 
   781 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -764,6 +1114,17 @@
-def gate_verdict(path):
-    """→ None (no file) | APPROVED | CHANGES_REQUIRED | none"""
-    if not os.path.isfile(path):
+def sandbox_text(path, root):
+    """a sandbox file the grader reads (feedback, review.md): a regular in-tree file, first
+    READ_CAP bytes; a symlink, a FIFO or a path through a symlinked parent → None (MEDIUM-A3)"""
+    return read_regular(path, READ_CAP, root=root)
+
+
+def gate_verdict(path, root):
+    """→ None (no file) | APPROVED | CHANGES_REQUIRED | none. A present feedback path that is
+    not a regular in-sandbox file (a symlink, a FIFO) means the gate ran and wrote no
+    readable trailer: none (MEDIUM-A3); only the first READ_CAP bytes are read"""
+    if not os.path.lexists(path):
         return None
+    text = sandbox_text(path, root)
+    if text is None:
+        return "none"
     last = None
-    for l in open(path, encoding="utf-8", errors="replace"):
+    for l in text.splitlines():
~~~~

## H36 — evals/harness/ablation-grade.sh — head lines 782–786

Head context (head/evals/harness/ablation-grade.sh, lines 770–798):

~~~~text
   770 |         m = TRAILER_LINE.search(l.rstrip("\n"))
   771 |         if m:
   772 |             last = m.group(1)
   773 |     if last is None:
   774 |         return "none"
   775 |     try:
   776 |         v = json.loads(last).get("verdict")
   777 |     except (ValueError, AttributeError):
   778 |         return "none"
   779 |     return v if v in ("APPROVED", "CHANGES_REQUIRED") else "none"
   780 | 
   781 | 
>  782 | def review_md_verdict(path):
>  783 |     if not os.path.isfile(path):
>  784 |         return None
>  785 |     v = None
>  786 |     for l in open(path, encoding="utf-8", errors="replace"):
   787 |         m = re.match(r"^\s*\**Verdict:?\**:?\s*\**\s*(APPROVED|CHANGES_REQUIRED)\b", l)
   788 |         if m:
   789 |             v = m.group(1)
   790 |     return v
   791 | 
   792 | 
   793 | # ------------------------------------------------------------------ citations (recall-vs-defects 1.1.2 parser)
   794 | RNG = r'(\d{1,6})(?:[-–](\d{1,6}))?(?![A-Za-z0-9]|[-–]\d)'
   795 | CITE = re.compile(
   796 |     r'(?P<path>[A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6})[`*)]{0,3}:(?P<first>' + RNG
   797 |     + r'(?:[ \t]*,[ \t]*' + RNG + r')*)'
   798 |     r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:"\'{}\[\]*])(?<![A-Za-z0-9_"\'}\]]`)):(?P<bare>' + RNG + r')')
~~~~

The change from head to the fix:

~~~~diff
@@ -782,5 +1143,6 @@
-def review_md_verdict(path):
-    if not os.path.isfile(path):
+def review_md_verdict(path, root):
+    text = sandbox_text(path, root) if os.path.lexists(path) else None
+    if text is None:
         return None
     v = None
-    for l in open(path, encoding="utf-8", errors="replace"):
+    for l in text.splitlines():
~~~~

## H37 — evals/harness/ablation-grade.sh — head line 855

Head context (head/evals/harness/ablation-grade.sh, lines 843–867):

~~~~text
   843 |             return p[len(pre):]
   844 |     return p
   845 | 
   846 | 
   847 | def path_matches(cited, defect_file):
   848 |     cited = strip_side(cited)
   849 |     if cited == defect_file or defect_file.endswith("/" + cited):
   850 |         return True
   851 |     return cited == defect_file.rsplit("/", 1)[-1]
   852 | 
   853 | 
   854 | def envelope_texts(path):
>  855 |     env = read_json(path)
   856 |     if not isinstance(env, dict):
   857 |         return []
   858 |     out = []
   859 |     for f in env.get("findings") or []:
   860 |         if not isinstance(f, dict):
   861 |             continue
   862 |         if isinstance(f.get("anchor"), str):
   863 |             out.append(f["anchor"])
   864 |         fp = f.get("file") or f.get("path")
   865 |         ln = f.get("line") or f.get("line_start") or f.get("start_line")
   866 |         if isinstance(fp, str) and isinstance(ln, int):
   867 |             out.append(f"{fp}:{ln}")
~~~~

The change from head to the fix:

~~~~diff
@@ -855 +1217,5 @@
-    env = read_json(path)
+    text = read_regular(path, READ_CAP)
+    try:
+        env = json.loads(text) if text is not None else None
+    except ValueError:
+        env = None
~~~~

## H38 — evals/harness/ablation-grade.sh — head lines 877–881

Head context (head/evals/harness/ablation-grade.sh, lines 865–893):

~~~~text
   865 |         ln = f.get("line") or f.get("line_start") or f.get("start_line")
   866 |         if isinstance(fp, str) and isinstance(ln, int):
   867 |             out.append(f"{fp}:{ln}")
   868 |     return out
   869 | 
   870 | 
   871 | def combined_findings(run_dir):
   872 |     sb = os.path.join(run_dir, "sandbox")
   873 |     a2a = os.path.join(sb, "grimoires", "loa", "a2a", SPRINT)
   874 |     texts = []
   875 |     for p in (os.path.join(sb, "review.md"), os.path.join(a2a, "engineer-feedback.md"),
   876 |               os.path.join(a2a, "auditor-sprint-feedback.md")):
>  877 |         if os.path.isfile(p) and not os.path.islink(p):
>  878 |             texts.append(open(p, encoding="utf-8", errors="replace").read())
>  879 |     for gate in ("review", "audit"):
>  880 |         p = os.path.join(run_dir, "eval", f"adversarial-{gate}.json")
>  881 |         if os.path.isfile(p) and not os.path.islink(p):
   882 |             texts.extend(envelope_texts(p))
   883 |     seen, cites = set(), []
   884 |     for tx in texts:
   885 |         for c in citations(tx):
   886 |             if c not in seen:
   887 |                 seen.add(c)
   888 |                 cites.append(c)
   889 |     return cites
   890 | 
   891 | 
   892 | def false_positives(cites, defects):
   893 |     anchors = []
~~~~

The change from head to the fix:

~~~~diff
@@ -877,5 +1243,6 @@
-        if os.path.isfile(p) and not os.path.islink(p):
-            texts.append(open(p, encoding="utf-8", errors="replace").read())
+        tx = sandbox_text(p, sb) if os.path.lexists(p) else None
+        if tx is not None:
+            texts.append(tx)
     for gate in ("review", "audit"):
         p = os.path.join(run_dir, "eval", f"adversarial-{gate}.json")
-        if os.path.isfile(p) and not os.path.islink(p):
+        if os.path.lexists(p):
~~~~

## H39 — evals/harness/ablation-grade.sh — insertion after head line 940

Head context (head/evals/harness/ablation-grade.sh, lines 929–952):

~~~~text
   929 |     defects = t.key.get("defects") or []
   930 |     pos = {d.get("id"): i for i, d in enumerate(defects, 1)}
   931 |     recall = {"defects_seeded": det.get("planted", len(defects)), "defects_caught": len(det.get("detected") or []),
   932 |               "recall": det.get("recall"), "flags": det.get("findings_cited"),
   933 |               "missed": [f"d{pos[x]}" for x in det.get("missed") or [] if x in pos]}
   934 |     return recall, false_positives(cites, defects)
   935 | 
   936 | 
   937 | # ------------------------------------------------------------------ contamination
   938 | SYS_DIRS = ["/dev", "/proc", "/sys", "/usr", "/bin", "/sbin", "/lib", "/lib64", "/etc", "/opt", "/var"]
   939 | GIT_HIST = re.compile(r"\bgit\b[^;&|\n]*\blog\b[^;&|\n]*--all\b|\bgit\b[^;&|\n]*\breflog\b")
   940 | ABS_WORD = re.compile(r"(?:(?<=^)|(?<=[\s=:'\"`(<>|;&,]))(/[A-Za-z0-9._@+%=,:~-][A-Za-z0-9._@+%=,:~/-]*)")
   941 | FIELDS = {"Bash": ["command"], "Read": ["file_path", "path"], "Grep": ["path", "pattern"], "Glob": ["path", "pattern"],
   942 |           "Write": ["file_path"], "Edit": ["file_path"], "MultiEdit": ["file_path"], "NotebookEdit": ["notebook_path"],
   943 |           "WebFetch": ["url"], "WebSearch": ["query"]}
   944 | PATH_FIELDS = {"file_path", "path", "notebook_path"}
   945 | 
   946 | 
   947 | def allowed_roots(run_dir, init_cwds):
   948 |     if A.executor == "container":
   949 |         return ["/workspace", "/tmp", "/home/evaluser"] + SYS_DIRS
   950 |     home = os.path.expanduser("~")
   951 |     sb = os.path.join(run_dir, "sandbox")
   952 |     roots = {sb, os.path.realpath(sb), "/tmp"} | set(init_cwds)
~~~~

The change from head to the fix:

~~~~diff
@@ -940,0 +1308,5 @@
+# LOW-A2: home-relative words are always outside (no root under any home is allowed)
+HOME_WORD = re.compile(r"(?:(?<=^)|(?<=[\s=:'\"`(<>|;&,]))(?:~|\$HOME|\$\{HOME\})/")
+HOME_PREFIXES = ("~/", "$HOME/", "${HOME}/")
+# inside allowed system roots, but secrets: another process's environment, memory or argv, and /var/run
+SENSITIVE = re.compile(r"^/proc/(?:\d+|self|thread-self)/(?:environ|cmdline|maps|mem)(?:/|$)|^/var/run(?:/|$)")
~~~~

## H40 — evals/harness/ablation-grade.sh — head lines 950–953

Head context (head/evals/harness/ablation-grade.sh, lines 938–965):

~~~~text
   938 | SYS_DIRS = ["/dev", "/proc", "/sys", "/usr", "/bin", "/sbin", "/lib", "/lib64", "/etc", "/opt", "/var"]
   939 | GIT_HIST = re.compile(r"\bgit\b[^;&|\n]*\blog\b[^;&|\n]*--all\b|\bgit\b[^;&|\n]*\breflog\b")
   940 | ABS_WORD = re.compile(r"(?:(?<=^)|(?<=[\s=:'\"`(<>|;&,]))(/[A-Za-z0-9._@+%=,:~-][A-Za-z0-9._@+%=,:~/-]*)")
   941 | FIELDS = {"Bash": ["command"], "Read": ["file_path", "path"], "Grep": ["path", "pattern"], "Glob": ["path", "pattern"],
   942 |           "Write": ["file_path"], "Edit": ["file_path"], "MultiEdit": ["file_path"], "NotebookEdit": ["notebook_path"],
   943 |           "WebFetch": ["url"], "WebSearch": ["query"]}
   944 | PATH_FIELDS = {"file_path", "path", "notebook_path"}
   945 | 
   946 | 
   947 | def allowed_roots(run_dir, init_cwds):
   948 |     if A.executor == "container":
   949 |         return ["/workspace", "/tmp", "/home/evaluser"] + SYS_DIRS
>  950 |     home = os.path.expanduser("~")
>  951 |     sb = os.path.join(run_dir, "sandbox")
>  952 |     roots = {sb, os.path.realpath(sb), "/tmp"} | set(init_cwds)
>  953 |     roots |= {os.path.join(home, x) for x in (".claude", ".claude.json", ".codex", ".aws")}
   954 |     return sorted(roots) + SYS_DIRS
   955 | 
   956 | 
   957 | def outside(p, roots):
   958 |     p = os.path.normpath(p)
   959 |     return not any(p == r or p.startswith(r.rstrip("/") + "/") for r in roots)
   960 | 
   961 | 
   962 | def check_value(tool, field, val, roots):
   963 |     low = val.lower()
   964 |     if "hidden" in low:
   965 |         return "hidden"
~~~~

The change from head to the fix:

~~~~diff
@@ -950,4 +1322,2 @@
-    home = os.path.expanduser("~")
     sb = os.path.join(run_dir, "sandbox")
-    roots = {sb, os.path.realpath(sb), "/tmp"} | set(init_cwds)
-    roots |= {os.path.join(home, x) for x in (".claude", ".claude.json", ".codex", ".aws")}
+    roots = {sb, os.path.realpath(sb), "/tmp"} | set(init_cwds)   # LOW-A2: no credential store is exempt
~~~~

## H41 — evals/harness/ablation-grade.sh — head line 958

Head context (head/evals/harness/ablation-grade.sh, lines 946–970):

~~~~text
   946 | 
   947 | def allowed_roots(run_dir, init_cwds):
   948 |     if A.executor == "container":
   949 |         return ["/workspace", "/tmp", "/home/evaluser"] + SYS_DIRS
   950 |     home = os.path.expanduser("~")
   951 |     sb = os.path.join(run_dir, "sandbox")
   952 |     roots = {sb, os.path.realpath(sb), "/tmp"} | set(init_cwds)
   953 |     roots |= {os.path.join(home, x) for x in (".claude", ".claude.json", ".codex", ".aws")}
   954 |     return sorted(roots) + SYS_DIRS
   955 | 
   956 | 
   957 | def outside(p, roots):
>  958 |     p = os.path.normpath(p)
   959 |     return not any(p == r or p.startswith(r.rstrip("/") + "/") for r in roots)
   960 | 
   961 | 
   962 | def check_value(tool, field, val, roots):
   963 |     low = val.lower()
   964 |     if "hidden" in low:
   965 |         return "hidden"
   966 |     if "grimoires/loa/evals/ablation-2.0" in val:
   967 |         return "suite_path"
   968 |     if "0xhoneyjar/loa" in low:
   969 |         return "repo_name"
   970 |     if tool == "Bash" and GIT_HIST.search(val):
~~~~

The change from head to the fix:

~~~~diff
@@ -958 +1328,5 @@
+    if p.startswith(HOME_PREFIXES):
+        return True
     p = os.path.normpath(p)
+    if SENSITIVE.match(p):
+        return True
~~~~

## H42 — evals/harness/ablation-grade.sh — head lines 974–978

Head context (head/evals/harness/ablation-grade.sh, lines 962–990):

~~~~text
   962 | def check_value(tool, field, val, roots):
   963 |     low = val.lower()
   964 |     if "hidden" in low:
   965 |         return "hidden"
   966 |     if "grimoires/loa/evals/ablation-2.0" in val:
   967 |         return "suite_path"
   968 |     if "0xhoneyjar/loa" in low:
   969 |         return "repo_name"
   970 |     if tool == "Bash" and GIT_HIST.search(val):
   971 |         return "git_history"
   972 |     cands = []
   973 |     if field in PATH_FIELDS or (tool == "Glob" and field == "pattern"):
>  974 |         if val.startswith("/") and not val.startswith("//"):
>  975 |             cands.append(val)
>  976 |     elif tool == "Bash":
>  977 |         for w in ABS_WORD.findall(val):
>  978 |             if w.startswith("//") or re.match(r"^/[^/]+/$", w):
   979 |                 continue
   980 |             cands.append(w)
   981 |     for c in cands:
   982 |         if outside(c, roots):
   983 |             return "outside_path"
   984 |     return None
   985 | 
   986 | 
   987 | def transcripts(run_dir):
   988 |     d = os.path.join(run_dir, "transcripts")
   989 |     if not os.path.isdir(d):
   990 |         return []
~~~~

The change from head to the fix:

~~~~diff
@@ -974,5 +1348,12 @@
-        if val.startswith("/") and not val.startswith("//"):
+        if (val.startswith("/") and not val.startswith("//")) or val.startswith(HOME_PREFIXES):
             cands.append(val)
     elif tool == "Bash":
-        for w in ABS_WORD.findall(val):
-            if w.startswith("//") or re.match(r"^/[^/]+/$", w):
+        if HOME_WORD.search(val):
+            return "outside_path"
+        for m in ABS_WORD.finditer(val):
+            w = m.group(1)
+            if w.startswith("//"):
+                continue
+            # a one-component /x/ word is a regex only after s y = ~ (sed/perl style) or a single
+            # quote (an awk or grep pattern); anything else (cd /root/) is a path candidate
+            if re.match(r"^/[^/]+/$", w) and m.start(1) > 0 and val[m.start(1) - 1] in "sy=~'":
~~~~

## H43 — evals/harness/ablation-grade.sh — head lines 1055–1056

Head context (head/evals/harness/ablation-grade.sh, lines 1043–1068):

~~~~text
  1043 | 
  1044 | 
  1045 | def grade(t, run_dir, frozen):
  1046 |     run_dir = os.path.abspath(run_dir)
  1047 |     sb = os.path.join(run_dir, "sandbox")
  1048 |     if not os.path.isdir(sb) or os.path.islink(sb):
  1049 |         raise GradeError(f"no sandbox/ under {run_dir}")
  1050 |     if ":" in run_dir or "," in run_dir:
  1051 |         raise GradeError("the run directory path must not contain ':' or ','")
  1052 |     grading = os.path.join(run_dir, "grading")
  1053 |     fresh_dir(grading)
  1054 |     a2a = os.path.join(sb, "grimoires", "loa", "a2a", SPRINT)
> 1055 |     v_review = gate_verdict(os.path.join(a2a, "engineer-feedback.md"))
> 1056 |     v_audit = gate_verdict(os.path.join(a2a, "auditor-sprint-feedback.md"))
  1057 |     if v_audit is not None:
  1058 |         verdict = {"source_file": "auditor-sprint-feedback.md", "value": v_audit}
  1059 |     elif v_review is not None:
  1060 |         verdict = {"source_file": "engineer-feedback.md", "value": v_review}
  1061 |     else:
  1062 |         rv = review_md_verdict(os.path.join(sb, "review.md"))
  1063 |         verdict = {"source_file": "review.md", "value": rv} if rv else None
  1064 |     g = {"schema_version": 1, "grader_version": GRADER_VERSION, "task_id": t.id, "task_type": t.type,
  1065 |          "suite_frozen": frozen, "executor_mode": A.executor,
  1066 |          "image": A.image if A.executor == "container" else None, "snapshots_graded": [],
  1067 |          "hidden_tests": None, "structural": None, "regressions": None, "snapshot_tests": None,
  1068 |          "recall": None, "false_positives": None, "verdict": verdict,
~~~~

The change from head to the fix:

~~~~diff
@@ -1055,2 +1436,2 @@
-    v_review = gate_verdict(os.path.join(a2a, "engineer-feedback.md"))
-    v_audit = gate_verdict(os.path.join(a2a, "auditor-sprint-feedback.md"))
+    v_review = gate_verdict(os.path.join(a2a, "engineer-feedback.md"), sb)
+    v_audit = gate_verdict(os.path.join(a2a, "auditor-sprint-feedback.md"), sb)
~~~~

## H44 — evals/harness/ablation-grade.sh — head line 1062

Head context (head/evals/harness/ablation-grade.sh, lines 1050–1074):

~~~~text
  1050 |     if ":" in run_dir or "," in run_dir:
  1051 |         raise GradeError("the run directory path must not contain ':' or ','")
  1052 |     grading = os.path.join(run_dir, "grading")
  1053 |     fresh_dir(grading)
  1054 |     a2a = os.path.join(sb, "grimoires", "loa", "a2a", SPRINT)
  1055 |     v_review = gate_verdict(os.path.join(a2a, "engineer-feedback.md"))
  1056 |     v_audit = gate_verdict(os.path.join(a2a, "auditor-sprint-feedback.md"))
  1057 |     if v_audit is not None:
  1058 |         verdict = {"source_file": "auditor-sprint-feedback.md", "value": v_audit}
  1059 |     elif v_review is not None:
  1060 |         verdict = {"source_file": "engineer-feedback.md", "value": v_review}
  1061 |     else:
> 1062 |         rv = review_md_verdict(os.path.join(sb, "review.md"))
  1063 |         verdict = {"source_file": "review.md", "value": rv} if rv else None
  1064 |     g = {"schema_version": 1, "grader_version": GRADER_VERSION, "task_id": t.id, "task_type": t.type,
  1065 |          "suite_frozen": frozen, "executor_mode": A.executor,
  1066 |          "image": A.image if A.executor == "container" else None, "snapshots_graded": [],
  1067 |          "hidden_tests": None, "structural": None, "regressions": None, "snapshot_tests": None,
  1068 |          "recall": None, "false_positives": None, "verdict": verdict,
  1069 |          "verdicts": {"review": v_review, "audit": v_audit},
  1070 |          "verdict_accuracy": None, "verdict_accuracy_per_gate": {"review": None, "audit": None},
  1071 |          "diff_lines": None, "files_changed": None, "contaminated": None}
  1072 |     acc = {"review": None, "audit": None}
  1073 |     if t.build:
  1074 |         docker_ready()
~~~~

The change from head to the fix:

~~~~diff
@@ -1062 +1443 @@
-        rv = review_md_verdict(os.path.join(sb, "review.md"))
+        rv = review_md_verdict(os.path.join(sb, "review.md"), sb)
~~~~

## H45 — evals/harness/ablation-grade.sh — head lines 1071–1105

Head context (head/evals/harness/ablation-grade.sh, lines 1059–1117):

~~~~text
  1059 |     elif v_review is not None:
  1060 |         verdict = {"source_file": "engineer-feedback.md", "value": v_review}
  1061 |     else:
  1062 |         rv = review_md_verdict(os.path.join(sb, "review.md"))
  1063 |         verdict = {"source_file": "review.md", "value": rv} if rv else None
  1064 |     g = {"schema_version": 1, "grader_version": GRADER_VERSION, "task_id": t.id, "task_type": t.type,
  1065 |          "suite_frozen": frozen, "executor_mode": A.executor,
  1066 |          "image": A.image if A.executor == "container" else None, "snapshots_graded": [],
  1067 |          "hidden_tests": None, "structural": None, "regressions": None, "snapshot_tests": None,
  1068 |          "recall": None, "false_positives": None, "verdict": verdict,
  1069 |          "verdicts": {"review": v_review, "audit": v_audit},
  1070 |          "verdict_accuracy": None, "verdict_accuracy_per_gate": {"review": None, "audit": None},
> 1071 |          "diff_lines": None, "files_changed": None, "contaminated": None}
> 1072 |     acc = {"review": None, "audit": None}
> 1073 |     if t.build:
> 1074 |         docker_ready()
> 1075 |         final = os.path.join(grading, "final")
> 1076 |         copy_tree(sb, final, EXCLUDE_TOP)
> 1077 |         g["diff_lines"], g["files_changed"] = churn(t.fixture, final)
> 1078 |         prepare(t, final)
> 1079 |         g["snapshots_graded"].append("final")
> 1080 |         res = run_suite(final, t.test_command, t.static_cases)
> 1081 |         g["hidden_tests"] = summary(res)
> 1082 |         base_tree = None
> 1083 |         need_base = t.regression_command is not None or t.type == "refactor"
> 1084 |         if need_base:
> 1085 |             base_tree = os.path.join(grading, "base")
> 1086 |             copy_tree(t.fixture, base_tree)
> 1087 |             prepare(t, base_tree)
> 1088 |         if t.regression_command is not None:
> 1089 |             rb = run_suite(base_tree, t.regression_command)
> 1090 |             rf = run_suite(final, t.regression_command)
> 1091 |             base_ok = [k for k in rb["order"] if k not in rb["bad"]] if not rb["parse_error"] else []
> 1092 |             if rf["parse_error"]:
> 1093 |                 newly = base_ok
> 1094 |             else:
> 1095 |                 newly = [k for k in base_ok if k in rf["bad"] or k not in rf["order"]]
> 1096 |             g["regressions"] = {"newly_failing": ids_of(rb, newly),
> 1097 |                                 "base": {"passed": rb["passed"], "total": rb["total"]},
> 1098 |                                 "final": {"passed": rf["passed"], "total": rf["total"]}}
> 1099 |         if t.type == "refactor":
> 1100 |             scmd = structural_command(t)
> 1101 |             sres = run_suite(final, scmd)
> 1102 |             sbase = run_suite(base_tree, t.test_command, t.static_cases)
> 1103 |             st = summary(sres)
> 1104 |             st.pop("timed_out")
> 1105 |             st.update(suite_green_base=all_pass(sbase), suite_green_final=all_pass(res))
  1106 |             g["structural"] = st
  1107 |         idx = read_json(os.path.join(run_dir, "snapshots", "index.json"))
  1108 |         idx = idx if isinstance(idx, dict) else {}
  1109 |         gates = {}
  1110 |         if v_review is not None:
  1111 |             gates["review"] = "implement"
  1112 |         if v_audit is not None:
  1113 |             gates["audit"] = "fix1" if idx.get("fix1") else "implement"
  1114 |         snap_res = {}
  1115 |         for label in ("implement", "fix1"):
  1116 |             if label not in gates.values():
  1117 |                 continue
~~~~

The change from head to the fix:

~~~~diff
@@ -1071,35 +1452,42 @@
-         "diff_lines": None, "files_changed": None, "contaminated": None}
+         "diff_lines": None, "files_changed": None, "symlinks_dropped": 0, "harness_files_removed": 0,
+         "oversized_files_skipped": 0, "contaminated": None}
     acc = {"review": None, "audit": None}
+    SNAPSHOT_LINKS_DROPPED[0] = 0
+    OVERSIZED[0] = 0
+    RUN_TAG[0] = re.sub(r"[^A-Za-z0-9._-]", "-", os.path.basename(run_dir))[:40] or "run"
+    GRADER_SOURCES.clear()
     if t.build:
+        for rel in t.protected:
+            src = os.path.join(t.fixture, *rel.split("/"))
+            if os.path.isfile(src) and not os.path.islink(src):
+                GRADER_SOURCES[rel] = src
+        GRADER_SOURCES.update({d: f for _s, d, f in t.overlay if os.path.isfile(f)})
         docker_ready()
         final = os.path.join(grading, "final")
-        copy_tree(sb, final, EXCLUDE_TOP)
+        g["symlinks_dropped"] = copy_tree(sb, final, EXCLUDE_TOP)
         g["diff_lines"], g["files_changed"] = churn(t.fixture, final)
-        prepare(t, final)
+        removed = prepare(t, final)
         g["snapshots_graded"].append("final")
-        res = run_suite(final, t.test_command, t.static_cases)
+        # refactor (DEC-0401, AC-5.3; Sprint 259 MEDIUM-1): the structural check is the
+        # hidden assertion and the fixture suite (test_command) the regression check
+        refactor = t.type == "refactor"
+        if refactor:
+            hcmd, hstatic, rcmd = structural_command(t), t.structural_cases, t.test_command
+        else:
+            hcmd, hstatic, rcmd = t.test_command, t.static_cases, t.regression_command
+        res = run_suite(final, hcmd, hstatic)
         g["hidden_tests"] = summary(res)
-        base_tree = None
-        need_base = t.regression_command is not None or t.type == "refactor"
-        if need_base:
+        rb = rf = None
+        if rcmd is not None:
             base_tree = os.path.join(grading, "base")
             copy_tree(t.fixture, base_tree)
-            prepare(t, base_tree)
-        if t.regression_command is not None:
-            rb = run_suite(base_tree, t.regression_command)
-            rf = run_suite(final, t.regression_command)
-            base_ok = [k for k in rb["order"] if k not in rb["bad"]] if not rb["parse_error"] else []
-            if rf["parse_error"]:
-                newly = base_ok
-            else:
-                newly = [k for k in base_ok if k in rf["bad"] or k not in rf["order"]]
-            g["regressions"] = {"newly_failing": ids_of(rb, newly),
-                                "base": {"passed": rb["passed"], "total": rb["total"]},
-                                "final": {"passed": rf["passed"], "total": rf["total"]}}
-        if t.type == "refactor":
-            scmd = structural_command(t)
-            sres = run_suite(final, scmd)
-            sbase = run_suite(base_tree, t.test_command, t.static_cases)
-            st = summary(sres)
+            removed += prepare(t, base_tree)
+            rb = run_suite(base_tree, rcmd)
+            rf = run_suite(final, rcmd)
+            g["regressions"] = regressions(rb, rf)
+        if refactor:
+            st = summary(res)
             st.pop("timed_out")
-            st.update(suite_green_base=all_pass(sbase), suite_green_final=all_pass(res))
+            st.pop("rc")
+            st.pop("output_truncated")
+            st.update(suite_green_base=all_pass(rb), suite_green_final=all_pass(rf))
~~~~

## H46 — evals/harness/ablation-grade.sh — head lines 1121–1133

Head context (head/evals/harness/ablation-grade.sh, lines 1109–1145):

~~~~text
  1109 |         gates = {}
  1110 |         if v_review is not None:
  1111 |             gates["review"] = "implement"
  1112 |         if v_audit is not None:
  1113 |             gates["audit"] = "fix1" if idx.get("fix1") else "implement"
  1114 |         snap_res = {}
  1115 |         for label in ("implement", "fix1"):
  1116 |             if label not in gates.values():
  1117 |                 continue
  1118 |             tree = os.path.join(grading, label)
  1119 |             if not extract_snapshot(run_dir, label, idx.get(label), tree):
  1120 |                 continue
> 1121 |             prepare(t, tree)
> 1122 |             snap_res[label] = run_suite(tree, t.test_command, t.static_cases)
> 1123 |             g["snapshots_graded"].append(label)
> 1124 |         if snap_res:
> 1125 |             g["snapshot_tests"] = {k: {"passed": v["passed"], "total": v["total"]} for k, v in snap_res.items()}
> 1126 |         for gate, v in (("review", v_review), ("audit", v_audit)):
> 1127 |             if v is None or gates.get(gate) not in snap_res:
> 1128 |                 continue
> 1129 |             ok = all_pass(snap_res[gates[gate]])
> 1130 |             acc[gate] = (v == "APPROVED" and ok) or (v == "CHANGES_REQUIRED" and not ok)
> 1131 |     else:
> 1132 |         if os.path.isdir(os.path.join(sb, "pr")) and not os.path.islink(os.path.join(sb, "pr")):
> 1133 |             copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
  1134 |         g["recall"], g["false_positives"] = grade_recall(t, run_dir, grading)
  1135 |         key_cr = any((d.get("severity") or "").lower() in ("high", "critical") for d in t.key.get("defects") or [])
  1136 |         for gate, v in (("review", v_review), ("audit", v_audit)):
  1137 |             if v is not None:
  1138 |                 acc[gate] = (v == "CHANGES_REQUIRED") == key_cr and v in ("APPROVED", "CHANGES_REQUIRED")
  1139 |     g["verdict_accuracy_per_gate"] = acc
  1140 |     g["verdict_accuracy"] = acc["audit"] if acc["audit"] is not None else acc["review"]
  1141 |     g["contaminated"] = contamination(run_dir)
  1142 |     return g
  1143 | 
  1144 | 
  1145 | def structural_command(t):
~~~~

The change from head to the fix:

~~~~diff
@@ -1121,13 +1509,19 @@
-            prepare(t, tree)
-            snap_res[label] = run_suite(tree, t.test_command, t.static_cases)
+            removed += prepare(t, tree)
+            sr = run_suite(tree, hcmd, hstatic)
+            ok = all_pass(sr)
+            if refactor:   # the gate read a tree that must keep the suite green too
+                ok = ok and all_pass(run_suite(tree, t.test_command))
+            snap_res[label] = (sr, ok)
             g["snapshots_graded"].append(label)
+        g["symlinks_dropped"] += SNAPSHOT_LINKS_DROPPED[0]
+        g["harness_files_removed"] = removed
         if snap_res:
-            g["snapshot_tests"] = {k: {"passed": v["passed"], "total": v["total"]} for k, v in snap_res.items()}
+            g["snapshot_tests"] = {k: {"passed": v["passed"], "total": v["total"]} for k, (v, _ok) in snap_res.items()}
         for gate, v in (("review", v_review), ("audit", v_audit)):
             if v is None or gates.get(gate) not in snap_res:
                 continue
-            ok = all_pass(snap_res[gates[gate]])
+            ok = snap_res[gates[gate]][1]
             acc[gate] = (v == "APPROVED" and ok) or (v == "CHANGES_REQUIRED" and not ok)
     else:
         if os.path.isdir(os.path.join(sb, "pr")) and not os.path.islink(os.path.join(sb, "pr")):
-            copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
+            g["symlinks_dropped"] = copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
~~~~

## H47 — evals/harness/ablation-grade.sh — insertion after head line 1138

Head context (head/evals/harness/ablation-grade.sh, lines 1127–1150):

~~~~text
  1127 |             if v is None or gates.get(gate) not in snap_res:
  1128 |                 continue
  1129 |             ok = all_pass(snap_res[gates[gate]])
  1130 |             acc[gate] = (v == "APPROVED" and ok) or (v == "CHANGES_REQUIRED" and not ok)
  1131 |     else:
  1132 |         if os.path.isdir(os.path.join(sb, "pr")) and not os.path.islink(os.path.join(sb, "pr")):
  1133 |             copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
  1134 |         g["recall"], g["false_positives"] = grade_recall(t, run_dir, grading)
  1135 |         key_cr = any((d.get("severity") or "").lower() in ("high", "critical") for d in t.key.get("defects") or [])
  1136 |         for gate, v in (("review", v_review), ("audit", v_audit)):
  1137 |             if v is not None:
  1138 |                 acc[gate] = (v == "CHANGES_REQUIRED") == key_cr and v in ("APPROVED", "CHANGES_REQUIRED")
  1139 |     g["verdict_accuracy_per_gate"] = acc
  1140 |     g["verdict_accuracy"] = acc["audit"] if acc["audit"] is not None else acc["review"]
  1141 |     g["contaminated"] = contamination(run_dir)
  1142 |     return g
  1143 | 
  1144 | 
  1145 | def structural_command(t):
  1146 |     dest = t.structural
  1147 |     if dest.endswith(".bats"):
  1148 |         return ["bats", dest]
  1149 |     if dest.endswith(".py"):
  1150 |         return ["python3", "-m", "pytest", "-q", dest]
~~~~

The change from head to the fix:

~~~~diff
@@ -1138,0 +1533 @@
+    g["oversized_files_skipped"] = OVERSIZED[0]
~~~~

## H48 — evals/harness/ablation-grade.sh — head lines 1209–1224

Head context (head/evals/harness/ablation-grade.sh, lines 1197–1236):

~~~~text
  1197 |                 lines.extend(f"- head/{rel}:{i}" for i in range(1, n + 1))
  1198 |     with open(os.path.join(sb, "review.md"), "w", encoding="utf-8") as f:
  1199 |         f.write("# Findings\n\n" + "".join(l + "\n" for l in lines))
  1200 |     return rd
  1201 | 
  1202 | 
  1203 | def self_check(t, mode, frozen):
  1204 |     if mode == "noisy" and t.build:
  1205 |         raise GradeError("--self-check noisy applies to review-catch tasks only")
  1206 |     root = tempfile.mkdtemp(prefix="selfcheck.", dir=SCRATCH)
  1207 |     g = grade(t, synth_run(t, mode, root), frozen)
  1208 |     ok, ev = False, ""
> 1209 |     if t.type == "refactor":
> 1210 |         st = g["structural"]
> 1211 |         green = st["suite_green_final"]
> 1212 |         ev = f"structural {st['passed']}/{st['total']}, suite {'green' if green else 'red'}"
> 1213 |         if mode == "base":
> 1214 |             ok = st["passed"] < st["total"] and green
> 1215 |         else:
> 1216 |             ok = st["passed"] >= st["total"] and not st["failed_names"] and not st["parse_error"] and green
> 1217 |     elif t.build:
> 1218 |         h, r = g["hidden_tests"], g["regressions"]
> 1219 |         suite_green = r is None or r["final"]["passed"] >= r["final"]["total"]
> 1220 |         ev = f"hidden {h['passed']}/{h['total']}" + ("" if r is None else f", fixture suite {r['final']['passed']}/{r['final']['total']}")
> 1221 |         if mode == "base":
> 1222 |             ok = h["passed"] < h["total"] and suite_green
> 1223 |         else:
> 1224 |             ok = h["passed"] >= h["total"] and not h["failed_names"] and not h["parse_error"] and suite_green
  1225 |     else:
  1226 |         rc = g["recall"]
  1227 |         ev = f"recall {rc['recall']} ({rc['defects_caught']}/{rc['defects_seeded']}), false_positives {g['false_positives']}"
  1228 |         if mode == "base":
  1229 |             ok = rc["defects_caught"] == 0 and (rc["recall"] in (0, 0.0, None))
  1230 |         elif mode == "reference":
  1231 |             ok = rc["defects_seeded"] > 0 and rc["recall"] == 1.0
  1232 |         else:
  1233 |             gr = grade(t, synth_run(t, "reference", root), frozen)
  1234 |             ev += f" vs reference {gr['false_positives']}"
  1235 |             ok = g["false_positives"] > gr["false_positives"]
  1236 |     return ok, ev, g
~~~~

The change from head to the fix:

~~~~diff
@@ -1209,16 +1604,16 @@
-    if t.type == "refactor":
-        st = g["structural"]
-        green = st["suite_green_final"]
-        ev = f"structural {st['passed']}/{st['total']}, suite {'green' if green else 'red'}"
-        if mode == "base":
-            ok = st["passed"] < st["total"] and green
-        else:
-            ok = st["passed"] >= st["total"] and not st["failed_names"] and not st["parse_error"] and green
-    elif t.build:
+    if t.build:
+        # hidden_tests is the structural check for refactor (MEDIUM-1); green = all_pass's
+        # rule on the summary (every case, parsed, exit 0, no timeout: MEDIUM-3)
         h, r = g["hidden_tests"], g["regressions"]
-        suite_green = r is None or r["final"]["passed"] >= r["final"]["total"]
-        ev = f"hidden {h['passed']}/{h['total']}" + ("" if r is None else f", fixture suite {r['final']['passed']}/{r['final']['total']}")
+        h_green = (h["passed"] >= h["total"] and not h["failed_names"] and not h["parse_error"]
+                   and h["rc"] == 0 and not h["timed_out"])
+        f = None if r is None else r["final"]
+        suite_green = f is None or (f["passed"] >= f["total"] and f["rc"] == 0 and not f["timed_out"] and not r["parse_error"])
+        if t.type == "refactor":
+            ev = f"structural {h['passed']}/{h['total']}, suite {'green' if suite_green else 'red'}"
+        else:
+            ev = f"hidden {h['passed']}/{h['total']}" + ("" if f is None else f", fixture suite {f['passed']}/{f['total']}")
         if mode == "base":
             ok = h["passed"] < h["total"] and suite_green
         else:
-            ok = h["passed"] >= h["total"] and not h["failed_names"] and not h["parse_error"] and suite_green
+            ok = h_green and suite_green
~~~~

## H49 — evals/harness/ablation-grade.sh — head line 1240

Head context (head/evals/harness/ablation-grade.sh, lines 1228–1252):

~~~~text
  1228 |         if mode == "base":
  1229 |             ok = rc["defects_caught"] == 0 and (rc["recall"] in (0, 0.0, None))
  1230 |         elif mode == "reference":
  1231 |             ok = rc["defects_seeded"] > 0 and rc["recall"] == 1.0
  1232 |         else:
  1233 |             gr = grade(t, synth_run(t, "reference", root), frozen)
  1234 |             ev += f" vs reference {gr['false_positives']}"
  1235 |             ok = g["false_positives"] > gr["false_positives"]
  1236 |     return ok, ev, g
  1237 | 
  1238 | 
  1239 | # ------------------------------------------------------------------ main
> 1240 | def main():
  1241 |     if A.self_check:
  1242 |         if not A.task_yaml or not os.path.isfile(A.task_yaml):
  1243 |             raise GradeError("--self-check needs --task-yaml <task.yaml>")
  1244 |         tdir = os.path.dirname(os.path.abspath(A.task_yaml))
  1245 |         suite_root = os.path.abspath(A.suite_root) if A.suite_root else os.path.dirname(os.path.dirname(tdir))
  1246 |         t = load_task(A.task_yaml, suite_root)
  1247 |         if t.id != os.path.basename(tdir):
  1248 |             raise GradeError(f"task id {t.id!r} is not its directory name")
  1249 |         frozen = freeze_check(suite_root)
  1250 |         ok, ev, g = self_check(t, A.self_check, frozen)
  1251 |         line = f"self-check {A.self_check} {t.id}: {'PASS' if ok else 'FAIL'} {ev}"
  1252 |         print(line)
~~~~

The change from head to the fix:

~~~~diff
@@ -1240 +1635,15 @@
+def host_gate():
+    """LOW-A1: --executor host runs the agent's tree on this machine as the calling user"""
+    if A.executor != "host":
+        return
+    if os.environ.get("LOA_EVAL_ALLOW_HOST_GRADING") != "1":
+        raise GradeError("--executor host is refused: it runs the agent's code on this host as the calling "
+                         "user with no filesystem, process or network isolation (env -i only; the user site is "
+                         "exposed). Grade in the image, or set LOA_EVAL_ALLOW_HOST_GRADING=1 to accept the risk")
+    print("ablation-grade: WARNING --executor host: the agent's code runs on this host as the calling user "
+          "without isolation (LOA_EVAL_ALLOW_HOST_GRADING=1); grade.json records executor_mode host",
+          file=sys.stderr)
+
+
 def main():
+    host_gate()
~~~~

## H50 — evals/harness/validate-suite.sh — head line 26

Head context (head/evals/harness/validate-suite.sh, lines 14–38):

~~~~text
    14 | #   --suite-file F    suite yaml (default evals/suites/ablation-2.0.yaml): arm ids
    15 | #                     for the leakage check, arms' task_types, suite_version
    16 | #
    17 | # Checks (each violation is one stdout line `<task-id>: <reason>`):
    18 | #   1. schema: id (= directory name), schema_version 1, type (feature-build |
    19 | #      bug-fix | refactor | review-catch), source {kind, date, fix_commit?,
    20 | #      base_commit?, bead?, origin?, churn?} (churn: {files, insertions,
    21 | #      deletions}, non-negative integers; Sprint 259), post_cutoff (bool), fixture (dir under the
    22 | #      root; null only for review-catch), criterion (agent-facing; no path, file
    23 | #      name or test name), success_criterion, test_command (array; null only for
    24 | #      review-catch), regression_command (array | null), reference_patch (hidden/…
    25 | #      | null; required for bug-fix and feature-build), grader_protected (array of
>   26 | #      relative paths present in the fixture), structural_check (hidden/… | null;
    27 | #      required for refactor), bounds {max_turns{}, timeout_min{}} (phase → positive
    28 | #      int), review_catch (null, or {fixture, manifest, labels?} for review-catch,
    29 | #      both present), suite_version (= the suite file's), TASK.md present
    30 | #   2. counts: four tasks of each type under tasks/ (unless --allow-partial)
    31 | #   3. allowlist: test_command[0] and regression_command[0] in python3 | pytest |
    32 | #      bats | bash | node | npx
    33 | #   4. hidden/manifest.json (build types): {"files": [{src, dest}]}; every src
    34 | #      exists under hidden/; every dest is relative, inside the tree, no `..`
    35 | #   5. fixture path rule (build types): check_fixture_path_rule from
    36 | #      lib/sandbox-mount.sh — no .claude/, CLAUDE.md, .loa.config.yaml, grimoires/
    37 | #      or .run/ at the fixture's top level; the reference patch touches none either
    38 | #   6. leakage: TASK.md and criterion (the task-brief text is built from these)
~~~~

The change from head to the fix:

~~~~diff
@@ -26 +26,3 @@
-#      relative paths present in the fixture), structural_check (hidden/… | null;
+#      relative paths present in the fixture; for build types it lists every file
+#      under fixture/tests/, Sprint 259), structural_check (hidden/… | null;
+#      refactor: regression_command must be null — test_command is the regression check),
~~~~

## H51 — evals/harness/validate-suite.sh — head line 58

Head context (head/evals/harness/validate-suite.sh, lines 46–70):

~~~~text
    46 | # Tested by evals/tests/validate-suite.bats.
    47 | # =============================================================================
    48 | set -euo pipefail
    49 | export LC_ALL=C
    50 | 
    51 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    52 | REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    53 | ROOT="$REPO_ROOT/grimoires/loa/evals/ablation-2.0"
    54 | SUITE_FILE="$REPO_ROOT/evals/suites/ablation-2.0.yaml"
    55 | PROMPTS_DIR="${LOA_EVAL_PHASE_PROMPTS_DIR:-$SCRIPT_DIR/lib/phase-prompts}"
    56 | SMOKE=false ALLOW_PARTIAL=false
    57 | 
>   58 | usage() { sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,45p' | sed 's/^# \{0,1\}//' >&2; exit 2; }
    59 | die() { echo "validate-suite: $*" >&2; exit 2; }
    60 | 
    61 | while [[ $# -gt 0 ]]; do
    62 |   case "$1" in
    63 |     --root) ROOT="${2:-}"; shift 2 ;;
    64 |     --smoke) SMOKE=true; shift ;;
    65 |     --allow-partial) ALLOW_PARTIAL=true; shift ;;
    66 |     --suite-file) SUITE_FILE="${2:-}"; shift 2 ;;
    67 |     --help|-h) usage ;;
    68 |     *) die "unknown option: $1 (see --help)" ;;
    69 |   esac
    70 | done
~~~~

The change from head to the fix:

~~~~diff
@@ -58 +60 @@
-usage() { sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,45p' | sed 's/^# \{0,1\}//' >&2; exit 2; }
+usage() { sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,47p' | sed 's/^# \{0,1\}//' >&2; exit 2; }
~~~~

## H52 — evals/harness/validate-suite.sh — insertion after head line 261

Head context (head/evals/harness/validate-suite.sh, lines 250–273):

~~~~text
   250 |     if not isinstance(t.get("success_criterion"), str) or not t.get("success_criterion", "").strip():
   251 |         bad(tid, "schema: success_criterion must be a non-empty string")
   252 |     for key in ("test_command", "regression_command"):
   253 |         v = t.get(key)
   254 |         if v is None:
   255 |             if key == "test_command" and ttype != "review-catch":
   256 |                 bad(tid, "schema: test_command is required for build types")
   257 |             continue
   258 |         if not is_str_list(v) or not v:
   259 |             bad(tid, f"schema: {key} must be a non-empty array of strings or null")
   260 |         elif v[0] not in ALLOW:
   261 |             bad(tid, f"allowlist: {key}[0] '{v[0]}' not in {'|'.join(sorted(ALLOW))}")
   262 |     for key, must in (("reference_patch", ttype in ("bug-fix", "feature-build")), ("structural_check", ttype == "refactor")):
   263 |         v = t.get(key)
   264 |         if v is None:
   265 |             if must:
   266 |                 bad(tid, f"schema: {key} is required for {ttype}")
   267 |             continue
   268 |         if not rel_ok(v) or not v.startswith("hidden/"):
   269 |             bad(tid, f"schema: {key} must be a relative path under hidden/")
   270 |         elif not os.path.isfile(os.path.join(tdir, v)):
   271 |             bad(tid, f"schema: {key} not found: {v}")
   272 |     gp = t.get("grader_protected")
   273 |     if not isinstance(gp, list) or not all(isinstance(x, str) for x in gp):
~~~~

The change from head to the fix:

~~~~diff
@@ -261,0 +264,2 @@
+    if ttype == "refactor" and t.get("regression_command") is not None:
+        bad(tid, "schema: regression_command must be null for refactor (test_command is the regression check)")
~~~~

## H53 — evals/harness/validate-suite.sh — insertion after head line 280

Head context (head/evals/harness/validate-suite.sh, lines 269–292):

~~~~text
   269 |             bad(tid, f"schema: {key} must be a relative path under hidden/")
   270 |         elif not os.path.isfile(os.path.join(tdir, v)):
   271 |             bad(tid, f"schema: {key} not found: {v}")
   272 |     gp = t.get("grader_protected")
   273 |     if not isinstance(gp, list) or not all(isinstance(x, str) for x in gp):
   274 |         bad(tid, "schema: grader_protected must be an array of paths")
   275 |     else:
   276 |         for p in gp:
   277 |             if not rel_ok(p):
   278 |                 bad(tid, f"schema: grader_protected path '{p}' is not a relative path inside the tree")
   279 |             elif fixture_dir and not os.path.exists(os.path.join(fixture_dir, p)):
   280 |                 bad(tid, f"schema: grader_protected path '{p}' is not in the fixture")
   281 |     bounds = t.get("bounds")
   282 |     if not isinstance(bounds, dict) or set(bounds) != {"max_turns", "timeout_min"}:
   283 |         bad(tid, "schema: bounds must be {max_turns: {}, timeout_min: {}}")
   284 |     else:
   285 |         for k in ("max_turns", "timeout_min"):
   286 |             m = bounds[k]
   287 |             if not isinstance(m, dict) or not all(isinstance(x, int) and not isinstance(x, bool) and x > 0 for x in m.values()):
   288 |                 bad(tid, f"schema: bounds.{k} must map phases to positive integers")
   289 |             elif any(p not in ("PLAN", "IMPLEMENT", "REVIEW", "FIX", "AUDIT", "BARE") for p in m):
   290 |                 bad(tid, f"schema: bounds.{k} names an unknown phase")
   291 |     rc = t.get("review_catch")
   292 |     defect_ids = []
~~~~

The change from head to the fix:

~~~~diff
@@ -280,0 +285,12 @@
+        # the fixture's own tests are the regression check: the grader restores every one
+        # (Sprint 259 review MEDIUM-2), so the list must name each file under tests/
+        ftests = os.path.join(fixture_dir, "tests") if (build and fixture_dir) else None
+        if ftests and os.path.isdir(ftests) and not os.path.islink(ftests):
+            listed = {os.path.normpath(p) for p in gp if rel_ok(p)}
+            for r, ds, fs in os.walk(ftests):
+                ds.sort()
+                names = sorted(fs + [d for d in ds if os.path.islink(os.path.join(r, d))])
+                for f in names:
+                    rel = os.path.relpath(os.path.join(r, f), fixture_dir)
+                    if rel not in listed:
+                        bad(tid, f"schema: grader_protected must list every file under fixture/tests/: missing {rel}")
~~~~

## H54 — evals/tests/ablation-grade.bats — insertion after head line 24

Head context (head/evals/tests/ablation-grade.bats, lines 13–36):

~~~~text
    13 | # of grimoires/loa/evals/ablation-2.0/smoke/.
    14 | # =============================================================================
    15 | 
    16 | BATS_BIN="$HOME/.local/dotfiles/tools/diff-so-fancy/test/bats/bin/bats"
    17 | 
    18 | setup() {
    19 |   TESTS_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    20 |   REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
    21 |   GRADER="$REPO_ROOT/evals/harness/ablation-grade.sh"
    22 |   SMOKE="$REPO_ROOT/grimoires/loa/evals/ablation-2.0/smoke"
    23 |   T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/ag.XXXXXX")"
    24 |   S="$T/suite"
    25 |   make_bin
    26 |   make_bf_py
    27 |   make_bf_sh
    28 |   make_rf_py
    29 |   make_rc
    30 | }
    31 | 
    32 | teardown() {
    33 |   chmod -R u+rwx "$T" 2>/dev/null || true
    34 |   find "$T" -mindepth 1 -delete 2>/dev/null || true
    35 |   rmdir "$T" 2>/dev/null || true
    36 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -24,0 +25 @@
+  export LOA_EVAL_ALLOW_HOST_GRADING=1   # grader 1.2.0 (LOW-A1): host mode is opt-in; AG-28 unsets it
~~~~

## H55 — evals/tests/ablation-grade.bats — head lines 246–248

Head context (head/evals/tests/ablation-grade.bats, lines 234–260):

~~~~text
   234 | 
   235 | @test "AG-1 the final tree is graded under grading/final in the image; the sandbox is byte-identical before and after" {
   236 |   RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"; snap "$RD" IMPLEMENT
   237 |   before="$(tree_digest "$RD/sandbox")"
   238 |   grade "$RD" bf-py
   239 |   [ "$status" -eq 0 ]
   240 |   [ "$(tree_digest "$RD/sandbox")" = "$before" ]
   241 |   [ -f "$RD/grading/final/tests/test_slug.py" ] && [ -f "$RD/grade.json" ]
   242 |   [ ! -e "$RD/grading/final/.git" ] && [ ! -e "$RD/grading/final/CLAUDE.md" ] && [ ! -e "$RD/grading/final/grimoires" ]
   243 |   [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "7/7" ]
   244 |   [ "$(G '.executor_mode')" = container ] && [ "$(G '.image')" = "loa-ablation:258" ]
   245 |   [ "$(G '.diff_lines')" = 2 ] && [ "$(G '.files_changed')" = 1 ]
>  246 |   # the docker argv: no network, read-only root, tmpfs, the caller's uid, one rw mount, the pytest shape
>  247 |   argv="$(tr '\0' ' ' < "$T/dlog/run-1.argv")"
>  248 |   [[ "$argv" == *"run --rm --network none --read-only --tmpfs /tmp:rw,size=256m --user $(id -u):$(id -g) -v $RD/grading/final:/workspace:rw -w /workspace -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp loa-ablation:258 timeout 120 python3 -I -s -m pytest -p no:cacheprovider -q --rootdir /workspace -rA tests "* ]]
   249 |   [ "$(tr '\0' '\n' < "$T/dlog/run-1.argv" | grep -cx -- -q)" -eq 1 ]
   250 | }
   251 | 
   252 | @test "AG-2 agent-edited tests/conftest.py, pytest.ini, a bats helper and a Makefile target are replaced by the fixture's copies" {
   253 |   RD="$T/run"; make_run bf-py "$RD"
   254 |   printf 'import sys\n' > "$RD/sandbox/tests/conftest.py"          # would break the import path
   255 |   printf '[pytest]\naddopts = -k existing\n' > "$RD/sandbox/pytest.ini"   # would deselect the hidden tests
   256 |   grade "$RD" bf-py
   257 |   [ "$status" -eq 0 ]
   258 |   cmp "$RD/grading/final/tests/conftest.py" "$S/tasks/bf-py/fixture/tests/conftest.py"
   259 |   cmp "$RD/grading/final/pytest.ini" "$S/tasks/bf-py/fixture/pytest.ini"
   260 |   [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "5/7" ]
~~~~

The change from head to the fix:

~~~~diff
@@ -246,3 +247,4 @@
-  # the docker argv: no network, read-only root, tmpfs, the caller's uid, one rw mount, the pytest shape
+  # the docker argv: init, a name, no network, read-only root, tmpfs, limits, no capabilities, the caller's
+  # uid, one rw mount, a kill deadline, the pytest shape (grader 1.2.0: MEDIUM-A1, HIGH-A1 -o addopts=)
   argv="$(tr '\0' ' ' < "$T/dlog/run-1.argv")"
-  [[ "$argv" == *"run --rm --network none --read-only --tmpfs /tmp:rw,size=256m --user $(id -u):$(id -g) -v $RD/grading/final:/workspace:rw -w /workspace -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp loa-ablation:258 timeout 120 python3 -I -s -m pytest -p no:cacheprovider -q --rootdir /workspace -rA tests "* ]]
+  [[ "$argv" == "run --rm --init --name ablgrade-run-final-"*" --network none --read-only --tmpfs /tmp:rw,size=256m --pids-limit 256 --memory 2g --cpus 2 --cap-drop ALL --security-opt no-new-privileges --user $(id -u):$(id -g) -v $RD/grading/final:/workspace:rw -w /workspace -e HOME=/tmp -e LC_ALL=C -e TMPDIR=/tmp loa-ablation:258 timeout --signal=TERM --kill-after=10 120 python3 -I -s -m pytest -p no:cacheprovider -o addopts= -q --rootdir /workspace -rA tests "* ]]
~~~~

## H56 — evals/tests/ablation-grade.bats — head line 342

Head context (head/evals/tests/ablation-grade.bats, lines 330–354):

~~~~text
   330 |   [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "false,false" ]
   331 |   # A4-shaped: IMPLEMENT only, no gate → null; AUDIT without FIX1 reads implement
   332 |   RD="$T/run-a4"; make_run bf-py "$RD"; apply_ref "$RD"; snap "$RD" IMPLEMENT
   333 |   grade "$RD" bf-py
   334 |   [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "null,null" ]
   335 |   [ "$(G '.verdict_accuracy')" = null ] && [ "$(G '.verdict')" = null ]
   336 |   [ "$(G '.snapshots_graded | join(",")')" = final ]
   337 |   verdict "$RD" audit APPROVED
   338 |   grade "$RD" bf-py
   339 |   [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "null,true" ]
   340 | }
   341 | 
>  342 | @test "AG-7 refactor: structural check and the suite at both ends; bats TAP ids" {
   343 |   RD="$T/run"; make_run rf-py "$RD"; apply_ref "$RD"
   344 |   grade "$RD" rf-py
   345 |   [ "$status" -eq 0 ]
   346 |   [ "$(G '.structural | "\(.passed)/\(.total) \(.suite_green_base) \(.suite_green_final)"')" = "1/1 true true" ]
   347 |   RD="$T/run2"; make_run rf-py "$RD"
   348 |   grade "$RD" rf-py
   349 |   [ "$(G '.structural | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "0/1 t1" ]
   350 |   RD="$T/run-sh"; make_run bf-sh "$RD"; apply_ref "$RD"
   351 |   grade "$RD" bf-sh
   352 |   [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.parse_error)"')" = "3/3 false" ]
   353 |   cat "$T"/dlog/run-*.argv | tr '\0' ' ' | grep -q -- 'timeout 120 bats --tap tests'
   354 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -342 +344 @@
-@test "AG-7 refactor: structural check and the suite at both ends; bats TAP ids" {
+@test "AG-7 refactor: the structural check is hidden_tests, the fixture suite is the regression check at both ends; bats TAP ids" {
~~~~

## H57 — evals/tests/ablation-grade.bats — head lines 347–353

Head context (head/evals/tests/ablation-grade.bats, lines 335–365):

~~~~text
   335 |   [ "$(G '.verdict_accuracy')" = null ] && [ "$(G '.verdict')" = null ]
   336 |   [ "$(G '.snapshots_graded | join(",")')" = final ]
   337 |   verdict "$RD" audit APPROVED
   338 |   grade "$RD" bf-py
   339 |   [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "null,true" ]
   340 | }
   341 | 
   342 | @test "AG-7 refactor: structural check and the suite at both ends; bats TAP ids" {
   343 |   RD="$T/run"; make_run rf-py "$RD"; apply_ref "$RD"
   344 |   grade "$RD" rf-py
   345 |   [ "$status" -eq 0 ]
   346 |   [ "$(G '.structural | "\(.passed)/\(.total) \(.suite_green_base) \(.suite_green_final)"')" = "1/1 true true" ]
>  347 |   RD="$T/run2"; make_run rf-py "$RD"
>  348 |   grade "$RD" rf-py
>  349 |   [ "$(G '.structural | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "0/1 t1" ]
>  350 |   RD="$T/run-sh"; make_run bf-sh "$RD"; apply_ref "$RD"
>  351 |   grade "$RD" bf-sh
>  352 |   [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.parse_error)"')" = "3/3 false" ]
>  353 |   cat "$T"/dlog/run-*.argv | tr '\0' ' ' | grep -q -- 'timeout 120 bats --tap tests'
   354 | }
   355 | 
   356 | @test "AG-18 end to end: a pipeline-run.sh run (stub CLI, stub mount library) grades with its real bundles and gate files" {
   357 |   local H="$T/h/evals/harness" sk
   358 |   mkdir -p "$H/lib" "$T/src/.claude/loa" "$T/home"
   359 |   cp "$REPO_ROOT/evals/harness/pipeline-run.sh" "$REPO_ROOT/evals/harness/fingerprint.sh" "$H/"
   360 |   cp -a "$REPO_ROOT/evals/harness/lib/phase-prompts" "$H/lib/"
   361 |   cp "$TESTS_DIR/fixtures/mount-lib-stub.sh" "$H/lib/sandbox-mount.sh"
   362 |   for sk in planning-sprints implementing-tasks reviewing-code auditing-security; do
   363 |     mkdir -p "$T/src/.claude/skills/$sk"; printf -- '---\nname: %s\neffort: xhigh\n---\nbody\n' "$sk" > "$T/src/.claude/skills/$sk/SKILL.md"
   364 |   done
   365 |   echo loa > "$T/src/.claude/loa/CLAUDE.loa.md"; printf 'flatline_protocol:\n  enabled: true\n' > "$T/src/.loa.config.yaml"
~~~~

The change from head to the fix:

~~~~diff
@@ -347,7 +349,19 @@
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.rc) \(.timed_out)"')" = "1/1 0 false" ]
+  [ "$(G '.regressions | "\(.base.passed)/\(.base.total) \(.final.passed)/\(.final.total) \(.newly_failing | length) \(.parse_error)"')" = "2/2 2/2 0 false" ]
   RD="$T/run2"; make_run rf-py "$RD"
   grade "$RD" rf-py
   [ "$(G '.structural | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "0/1 t1" ]
+  # an untouched tree: the suite is green but the hidden assertion (structural) is red
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "0/1 t1" ]
+  [ "$(G '.regressions.final | "\(.passed)/\(.total)"')" = "2/2" ]
+  # a refactor that breaks behaviour: structural green, the suite case is newly failing by its base id
+  RD="$T/run3"; make_run rf-py "$RD"; apply_ref "$RD"
+  sed -i 's/return a + b/return a - b/' "$RD/sandbox/src/calc/ops.py"
+  grade "$RD" rf-py
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "1/1" ]
+  [ "$(G '.regressions.newly_failing | join(",")')" = "t1,t2" ]
+  [ "$(G '.structural.suite_green_final')" = false ]
   RD="$T/run-sh"; make_run bf-sh "$RD"; apply_ref "$RD"
   grade "$RD" bf-sh
   [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.parse_error)"')" = "3/3 false" ]
-  cat "$T"/dlog/run-*.argv | tr '\0' ' ' | grep -q -- 'timeout 120 bats --tap tests'
+  cat "$T"/dlog/run-*.argv | tr '\0' ' ' | grep -q -- 'timeout --signal=TERM --kill-after=10 120 bats --tap tests'
~~~~

## H58 — evals/tests/ablation-grade.bats — insertion after head line 454

Head context (head/evals/tests/ablation-grade.bats, lines 443–466):

~~~~text
   443 |     [ "$(G '.contaminated | keys | join(",")')" = "excerpt_id,pattern,phase" ]
   444 |   done <<'EOF'
   445 | Bash	{"command": "cat tests/HIDDEN_cases.py"}	hidden
   446 | Read	{"file_path": "/workspace/grimoires/loa/evals/ablation-2.0/tasks/x/task.yaml"}	suite_path
   447 | WebFetch	{"url": "https://github.com/0xHoneyJar/loa/tree/main", "prompt": "read"}	repo_name
   448 | WebFetch	{"url": "https://example.com/hidden/answers", "prompt": "read"}	hidden
   449 | WebSearch	{"query": "0xhoneyjar/loa ablation tasks"}	repo_name
   450 | Bash	{"command": "git log --oneline --all | head"}	git_history
   451 | Bash	{"command": "git reflog"}	git_history
   452 | Read	{"file_path": "/home/operator/code/loa/README.md"}	outside_path
   453 | Bash	{"command": "cat /home/operator/notes.txt 2>/dev/null"}	outside_path
   454 | Glob	{"pattern": "/srv/**/*.py"}	outside_path
   455 | EOF
   456 |   # first hit in phase order: IMPLEMENT before REVIEW whatever the file names sort to
   457 |   RD="$T/order"; make_run rc-x "$RD"
   458 |   tool_use "$RD" REVIEW Bash '{"command": "git reflog"}'
   459 |   tool_use "$RD" IMPLEMENT Bash '{"command": "ls"}'
   460 |   tool_use "$RD" IMPLEMENT Read '{"file_path": "/root/x"}'
   461 |   grade "$RD" rc-x
   462 |   [ "$(G '.contaminated | "\(.phase) \(.pattern) \(.excerpt_id)"')" = "IMPLEMENT outside_path IMPLEMENT:2" ]
   463 |   ! grep -q '/root/x' "$RD/grade.json"
   464 | }
   465 | 
   466 | @test "AG-11 contamination: ordinary container and host commands are clean; host paths are judged against the sandbox root" {
~~~~

The change from head to the fix:

~~~~diff
@@ -454,0 +469,9 @@
+Bash	{"command": "cat ~/.aws/credentials"}	outside_path
+Bash	{"command": "cat $HOME/.ssh/id_rsa"}	outside_path
+Bash	{"command": "cat ${HOME}/.codex/auth.json"}	outside_path
+Bash	{"command": "cat /proc/self/environ"}	outside_path
+Bash	{"command": "tr '\\0' ' ' < /proc/1/cmdline"}	outside_path
+Read	{"file_path": "/proc/self/maps"}	outside_path
+Bash	{"command": "ls /var/run/docker.sock"}	outside_path
+Bash	{"command": "cd /root/ && cat .ssh/id_rsa"}	outside_path
+Read	{"file_path": "~/.aws/credentials"}	outside_path
~~~~

## H59 — evals/tests/ablation-grade.bats — head lines 479–485

Head context (head/evals/tests/ablation-grade.bats, lines 467–497):

~~~~text
   467 |   RD="$T/clean"; make_run rc-x "$RD"
   468 |   tool_use "$RD" IMPLEMENT Bash '{"command": "cat /workspace/src/a.py 2>/dev/null | awk '"'"'/LOA-VERDICT/ {print}'"'"'; ls /usr/bin/env /tmp/x"}'
   469 |   tool_use "$RD" IMPLEMENT Read '{"file_path": "/workspace/src/a.py"}'
   470 |   tool_use "$RD" IMPLEMENT Grep '{"pattern": "^/api", "path": "/workspace"}'
   471 |   tool_use "$RD" IMPLEMENT Glob '{"pattern": "**/*.py"}'
   472 |   tool_use "$RD" IMPLEMENT WebFetch '{"url": "https://docs.python.org/3/library/re.html", "prompt": "x"}'
   473 |   tool_use "$RD" IMPLEMENT Write '{"file_path": "/home/evaluser/.claude/x", "content": "hidden text in content is not scanned"}'
   474 |   grade "$RD" rc-x
   475 |   [ "$status" -eq 0 ]
   476 |   [ "$(G '.contaminated')" = null ]
   477 |   RD="$T/host"; make_run rc-x "$RD"
   478 |   tool_use "$RD" IMPLEMENT Read "$(jq -cn --arg p "$RD/sandbox/lib/x.sh" '{file_path: $p}')"
>  479 |   tool_use "$RD" IMPLEMENT Read "$(jq -cn --arg p "$HOME/.claude/settings.json" '{file_path: $p}')"
>  480 |   run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
>  481 |   [ "$status" -eq 0 ]
>  482 |   [ "$(G '.contaminated')" = null ] && [ "$(G '.image')" = null ] && [ "$(G '.executor_mode')" = host ]
>  483 |   tool_use "$RD" AUDIT Read '{"file_path": "/home/evaluser/x"}'
>  484 |   run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
>  485 |   [ "$(G '.contaminated | "\(.phase) \(.pattern)"')" = "AUDIT outside_path" ]
   486 | }
   487 | 
   488 | # --- the meta/ boundary and id-only summaries (DEC-0413) ---------------------------------------------
   489 | 
   490 | @test "AG-12 meta/ removed → byte-identical grade.json; summary fields carry ids only" {
   491 |   RD="$T/run"; make_run bf-py "$RD"; snap "$RD" IMPLEMENT; verdict "$RD" review CHANGES_REQUIRED
   492 |   apply_ref "$RD"; sed -i 's/"a-b"/"a_b"/' "$RD/sandbox/tests/test_existing.py"; snap "$RD" FIX1; verdict "$RD" audit APPROVED
   493 |   tool_use "$RD" FIX1 Bash '{"command": "cat /home/operator/hidden.txt"}'
   494 |   grade "$RD" bf-py
   495 |   [ "$status" -eq 0 ]
   496 |   cp "$RD/grade.json" "$T/with-meta.json"
   497 |   rm -rf "$RD/meta"
~~~~

The change from head to the fix:

~~~~diff
@@ -479,7 +502,18 @@
-  tool_use "$RD" IMPLEMENT Read "$(jq -cn --arg p "$HOME/.claude/settings.json" '{file_path: $p}')"
+  tool_use "$RD" IMPLEMENT Bash '{"command": "sed s/x/y/ lib/x.sh; sed -i '"'"'s/a/b/'"'"' lib/x.sh; cat /proc/cpuinfo /proc/self/status; ls /var/log"}'
   run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
   [ "$status" -eq 0 ]
   [ "$(G '.contaminated')" = null ] && [ "$(G '.image')" = null ] && [ "$(G '.executor_mode')" = host ]
+  # grader 1.2.0 (LOW-A2): the caller's credential stores are no longer exempt in host mode
+  tool_use "$RD" REVIEW Read "$(jq -cn --arg p "$HOME/.claude/settings.json" '{file_path: $p}')"
+  run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
+  [ "$(G '.contaminated | "\(.phase) \(.pattern)"')" = "REVIEW outside_path" ]
+  RD="$T/host2"; make_run rc-x "$RD"
   tool_use "$RD" AUDIT Read '{"file_path": "/home/evaluser/x"}'
   run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
   [ "$(G '.contaminated | "\(.phase) \(.pattern)"')" = "AUDIT outside_path" ]
+  for c in 'cat ~/.aws/credentials' 'ls ~/.codex/' 'cat $HOME/.claude.json'; do
+    RD="$T/host-$((i = ${i:-0} + 1))"; make_run rc-x "$RD"
+    tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c "$c" '{command: $c}')"
+    run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
+    [ "$(G '.contaminated.pattern')" = outside_path ]
+  done
~~~~

## H60 — evals/tests/ablation-grade.bats — insertion after head line 591

Head context (head/evals/tests/ablation-grade.bats, lines 580–591):

~~~~text
   580 |   [ "$status" -eq 2 ]
   581 |   RD="$T/run"; make_run bf-py "$RD"
   582 |   run "$GRADER" "$RD" no-such-task --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
   583 |   [ "$status" -eq 2 ] && [[ "$output" == *"task not found"* ]]
   584 |   run "$GRADER" "$RD" bf-py --suite-root "$S" --allow-unfrozen --docker-bin "$T/no-docker"
   585 |   [ "$status" -eq 2 ] && [[ "$output" == *"docker CLI not found"* ]]
   586 |   echo 'DOCKER_STUB_NO_IMAGE=1' > "$T/docker.env"
   587 |   run "$GRADER" "$RD" bf-py --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
   588 |   [ "$status" -eq 2 ] && [[ "$output" == *"image not found"* ]]
   589 |   run "$GRADER" "$RD" bf-py --bogus
   590 |   [ "$status" -eq 2 ]
   591 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -591,0 +626,316 @@
+
+# --- Sprint 259 fix round (engineer-feedback HIGH-1, MEDIUM-1, MEDIUM-3, LOW-2) ---------------------
+
+# bf-tap: a bash-runner task; the hidden runner prints a passing TAP block and exits 1 (a
+# teardown failure), the regression check is a bash script with no summary at all
+make_bf_tap() {
+  local d="$S/tasks/bf-tap" w="$T/w-tap"
+  mkdir -p "$d/fixture/lib" "$d/fixture/tests" "$d/hidden/tests"
+  printf 'v=1\n' > "$d/fixture/lib/x.sh"
+  printf 'grep -q "^v=" lib/x.sh\n' > "$d/fixture/tests/reg.sh"
+  printf 'echo 1..1\necho "ok 1 the value is set"\nexit 1\n' > "$d/hidden/tests/run.sh"
+  echo '{"files": [{"src": "tests/run.sh", "dest": "tests/run.sh"}]}' > "$d/hidden/manifest.json"
+  mkdir -p "$w/a" "$w/b"; cp -a "$d/fixture/." "$w/a/"; cp -a "$d/fixture/." "$w/b/"
+  printf 'v=2\n' > "$w/b/lib/x.sh"
+  (cd "$w" && diff -ruN a b > "$d/hidden/reference.patch" || true)
+  printf 'Set the value.\n' > "$d/TASK.md"
+  cat > "$d/task.yaml" <<'YAML'
+id: bf-tap
+schema_version: 1
+type: bug-fix
+fixture: tasks/bf-tap/fixture
+criterion: "the value is two"
+test_command: ["bash", "tests/run.sh"]
+regression_command: ["bash", "tests/reg.sh"]
+reference_patch: hidden/reference.patch
+grader_protected: [tests/reg.sh]
+structural_check: null
+review_catch: null
+suite_version: 1
+YAML
+}
+
+@test "AG-19 symlinks (DISS-001): an absolute or escaping link is never copied, grading twice leaves its target's mode alone; in-tree links survive; snapshot links are filtered" {
+  local probe="$T/probe-dir"
+  mkdir -p "$probe/inner"; chmod 0755 "$probe" "$probe/inner"
+  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
+  ln -s "$probe" "$RD/sandbox/evil"                       # absolute directory link
+  ln -s ../../../probe-dir "$RD/sandbox/src/up"           # relative, climbs out of the tree
+  ln -s ./conftest.py "$RD/sandbox/tests/alias"           # in-tree relative: kept
+  mkdir -p "$RD/sandbox/sub"; ln -s .. "$RD/sandbox/sub/root"   # in-tree (the tree root): kept
+  ln -s sub/root/.. "$RD/sandbox/hop"                     # lexically in-tree, really the parent: dropped
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(stat -c %a "$probe")" = 755 ]                      # (1.0.0: 700 — the second grade chmodded through evil)
+  [ "$(stat -c %a "$probe/inner")" = 755 ]
+  [ ! -L "$RD/grading/final/evil" ] && [ ! -e "$RD/grading/final/evil" ]
+  [ ! -L "$RD/grading/final/src/up" ] && [ ! -L "$RD/grading/final/hop" ]
+  [ "$(readlink "$RD/grading/final/tests/alias")" = ./conftest.py ]
+  [ "$(readlink "$RD/grading/final/sub/root")" = .. ]
+  [ "$(G '.symlinks_dropped')" = 3 ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "7/7" ]
+  # a snapshot carrying the same links: the tar filter skips the absolute and escaping members
+  RD="$T/run-snap"; make_run bf-py "$RD"; apply_ref "$RD"
+  ln -s "$probe" "$RD/sandbox/evil"; ln -s ../../../probe-dir "$RD/sandbox/src/up"; ln -s ./conftest.py "$RD/sandbox/tests/alias"
+  snap "$RD" IMPLEMENT; verdict "$RD" review APPROVED
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.snapshots_graded | join(",")')" = "final,implement" ]
+  [ ! -L "$RD/grading/implement/evil" ] && [ ! -L "$RD/grading/implement/src/up" ]
+  [ -L "$RD/grading/implement/tests/alias" ] && [ "$(readlink "$RD/grading/implement/tests/alias")" = conftest.py ]   # data_filter normalises ./
+  [ "$(stat -c %a "$probe")" = 755 ]
+  [ "$(G '.verdict_accuracy_per_gate.review')" = true ]
+}
+
+@test "AG-20 refactor rows (MEDIUM-1): ablation-row.sh's hidden_test_pass_rate is the structural pass rate; per-gate accuracy needs the structural check and the suite green" {
+  RD="$T/run"; make_run rf-py "$RD"
+  snap "$RD" IMPLEMENT; verdict "$RD" review APPROVED               # untouched: structural red → wrong
+  apply_ref "$RD"; sed -i 's/return a + b/return a - b/' "$RD/sandbox/src/calc/ops.py"
+  snap "$RD" FIX1; verdict "$RD" audit APPROVED                     # structural green, suite red → wrong
+  grade "$RD" rf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.snapshot_tests | "\(.implement.passed)/\(.implement.total) \(.fix1.passed)/\(.fix1.total)"')" = "0/1 1/1" ]
+  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "false,false" ]
+  verdict "$RD" review CHANGES_REQUIRED; verdict "$RD" audit CHANGES_REQUIRED
+  grade "$RD" rf-py
+  [ "$(G '.verdict_accuracy_per_gate | "\(.review),\(.audit)"')" = "true,true" ]
+  run "$REPO_ROOT/evals/harness/ablation-row.sh" --run-dir "$RD" --task-yaml "$S/tasks/rf-py/task.yaml"
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '"\(.hidden_test_pass_rate) \(.regressions)"' <<<"$output")" = "1 2" ]
+  # the untouched tree scores 0 on the primary, not the suite's 1.0
+  RD="$T/run0"; make_run rf-py "$RD"
+  grade "$RD" rf-py
+  [ "$status" -eq 0 ]
+  run "$REPO_ROOT/evals/harness/ablation-row.sh" --run-dir "$RD" --task-yaml "$S/tasks/rf-py/task.yaml"
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '"\(.hidden_test_pass_rate) \(.regressions)"' <<<"$output")" = "0 0" ]
+}
+
+@test "AG-21 exit status (DISS-002): a passing TAP block followed by exit 1 is not green — hidden_tests carries rc, per-gate accuracy and the self-check follow it" {
+  make_bf_tap
+  # round 2 (DISS-001 r2): a green suite needs a parsed summary, so this case's regression command prints TAP
+  printf 'grep -q "^v=" lib/x.sh && echo 1..1 && echo "ok 1 v is set"\n' > "$S/tasks/bf-tap/fixture/tests/reg.sh"
+  RD="$T/run"; make_run bf-tap "$RD"; apply_ref "$RD"; snap "$RD" IMPLEMENT; verdict "$RD" review APPROVED
+  grade "$RD" bf-tap
+  [ "$status" -eq 0 ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.rc) \(.timed_out) \(.parse_error)"')" = "1/1 1 false false" ]
+  [ "$(G '.verdict_accuracy_per_gate.review')" = false ]
+  verdict "$RD" review CHANGES_REQUIRED
+  grade "$RD" bf-tap
+  [ "$(G '.verdict_accuracy_per_gate.review')" = true ]
+  run "$GRADER" --self-check reference --task-yaml "$S/tasks/bf-tap/task.yaml" --allow-unfrozen --docker-bin "$T/docker"
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"self-check reference bf-tap: FAIL hidden 1/1, fixture suite 1/1"* ]]
+  # the same runner exiting 0 passes
+  sed -i 's/^exit 1$/exit 0/' "$S/tasks/bf-tap/hidden/tests/run.sh"
+  run "$GRADER" --self-check reference --task-yaml "$S/tasks/bf-tap/task.yaml" --allow-unfrozen --docker-bin "$T/docker"
+  [ "$status" -eq 0 ]
+}
+
+@test "AG-22 an unparseable regression command (DISS-003): exit 0 at base, 1 at final → every fallback id is newly failing, parse_error true" {
+  make_bf_tap
+  RD="$T/run"; make_run bf-tap "$RD"
+  printf 'broken\n' > "$RD/sandbox/lib/x.sh"
+  grade "$RD" bf-tap
+  [ "$status" -eq 0 ]
+  [ "$(G '.regressions | "\(.newly_failing | join(",")) \(.parse_error) \(.base.rc) \(.final.rc)"')" = "t1 true 0 1" ]
+  [ "$(G '.regressions | "\(.base_green) \(.final_green)"')" = "false false" ]   # round 2 DISS-C-002: the green booleans travel with the counts (an unparseable base run is not green either)
+  [ "$(G '.regressions | "\(.base.passed)/\(.base.total) \(.final.passed)/\(.final.total)"')" = "1/1 0/1" ]
+  # green at both ends: nothing newly failing, still marked unparsed
+  RD="$T/run2"; make_run bf-tap "$RD"; apply_ref "$RD"
+  grade "$RD" bf-tap
+  [ "$(G '.regressions | "\(.newly_failing | length) \(.parse_error)"')" = "0 true" ]
+}
+
+# --- Sprint 259 audit fix round 1 (auditor-sprint-feedback HIGH-A1, MEDIUM-A1…A3, LOW-A1) — grader 1.2.0 ---
+
+# a pytest hookwrapper that turns every failed report into a pass (the agent's cheat)
+flip_conftest() {
+  printf 'import pytest\n\n\n@pytest.hookimpl(hookwrapper=True)\ndef pytest_runtest_makereport(item, call):\n    out = yield\n    r = out.get_result()\n    if r.failed:\n        r.outcome = "passed"\n' > "$1"
+}
+
+@test "AG-23 harness files (HIGH-A1): an agent conftest.py hookwrapper, an ini addopts and a bats setup_suite are removed before every run; the fixture's own copies survive" {
+  # 1.1.0: the root hookwrapper graded the unfixed tree 7/7 and the review that approved it accurate
+  RD="$T/run"; make_run bf-py "$RD"
+  flip_conftest "$RD/sandbox/conftest.py"
+  snap "$RD" IMPLEMENT; verdict "$RD" review APPROVED
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "5/7 t6,t7" ]
+  [ ! -e "$RD/grading/final/conftest.py" ] && [ ! -e "$RD/grading/implement/conftest.py" ]
+  cmp "$RD/grading/final/tests/conftest.py" "$S/tasks/bf-py/fixture/tests/conftest.py"
+  [ "$(cat "$RD/grading/final.harness-removed.txt")" = conftest.py ]
+  [ "$(cat "$RD/grading/implement.harness-removed.txt")" = conftest.py ]
+  [ "$(G '.harness_files_removed')" = 2 ]                   # final + the implement snapshot
+  [ "$(G '.verdict_accuracy_per_gate.review')" = false ]
+  ! grep -q 'conftest' "$RD/grade.json"
+  # the hidden tests overlaid under tests/acceptance/: a conftest beside them; ini files nearer
+  # the test args than the protected pytest.ini (pytest would take tests/pyproject.toml's addopts)
+  sed -i 's|"dest": "tests/test_slug.py"|"dest": "tests/acceptance/test_slug.py"|' "$S/tasks/bf-py/hidden/manifest.json"
+  RD="$T/run2"; make_run bf-py "$RD"
+  mkdir -p "$RD/sandbox/tests/acceptance"; flip_conftest "$RD/sandbox/tests/acceptance/conftest.py"
+  printf '[tool.pytest.ini_options]\naddopts = "-p no:terminal"\n' > "$RD/sandbox/tests/pyproject.toml"
+  printf '[pytest]\naddopts = -p no:terminal\n' > "$RD/sandbox/tests/acceptance/tox.ini"
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.parse_error) \(.failed_names | join(","))"')" = "5/7 false t4,t5" ]   # acceptance/ sorts before test_existing.py
+  [ "$(G '.harness_files_removed')" = 3 ]
+  [ "$(cat "$RD/grading/final.harness-removed.txt" | tr '\n' ' ')" = "tests/acceptance/conftest.py tests/acceptance/tox.ini tests/pyproject.toml " ]
+  [ -f "$RD/grading/final/tests/acceptance/test_slug.py" ] && [ -f "$RD/grading/final/pytest.ini" ]
+  # an untouched tree removes nothing
+  RD="$T/run3"; make_run bf-py "$RD"
+  grade "$RD" bf-py
+  [ "$(G '.harness_files_removed')" = 0 ] && [ ! -s "$RD/grading/final.harness-removed.txt" ]
+  # a directory overlay's own conftest.py is grader-owned and kept
+  mkdir -p "$S/tasks/bf-py/hidden/acc"; cp "$S/tasks/bf-py/hidden/tests/test_slug.py" "$S/tasks/bf-py/hidden/acc/"
+  printf '# grader-owned\n' > "$S/tasks/bf-py/hidden/acc/conftest.py"
+  echo '{"files": [{"src": "acc", "dest": "tests/acceptance"}]}' > "$S/tasks/bf-py/hidden/manifest.json"
+  RD="$T/run4"; make_run bf-py "$RD"
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.harness_files_removed')" = 0 ] && cmp "$RD/grading/final/tests/acceptance/conftest.py" "$S/tasks/bf-py/hidden/acc/conftest.py"
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "5/7" ]
+  # bats: setup_suite.bash writes the fix into the tree before the hidden cases run (1.1.0: 3/3)
+  printf 'corpus() { :; }\n' > "$S/tasks/bf-sh/fixture/tests/corpus-helper.bash"   # an unprotected fixture helper
+  RD="$T/run-sh"; make_run bf-sh "$RD"
+  cat > "$RD/sandbox/tests/setup_suite.bash" <<'EOF'
+setup_suite() { printf '%s\n' 'greet() { echo "Hello, $1!"; }' > lib/greet.sh; }
+EOF
+  ln -s helpers.bash "$RD/sandbox/tests/more-helper.bash"                     # an in-tree link at a helper path
+  printf 'x() { :; }\n' > "$RD/sandbox/tests/extra.bash"
+  grade "$RD" bf-sh
+  [ "$status" -eq 0 ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "2/3 t1" ]
+  [ "$(G '.harness_files_removed')" = 3 ]
+  [ "$(cat "$RD/grading/final.harness-removed.txt" | tr '\n' ' ')" = "tests/extra.bash tests/more-helper.bash tests/setup_suite.bash " ]
+  cmp "$RD/grading/final/tests/helpers.bash" "$S/tasks/bf-sh/fixture/tests/helpers.bash"
+  cmp "$RD/grading/final/tests/corpus-helper.bash" "$S/tasks/bf-sh/fixture/tests/corpus-helper.bash"
+  cmp "$RD/grading/final/lib/greet.sh" "$S/tasks/bf-sh/fixture/lib/greet.sh"
+}
+
+# bf-run: bf-tap with a TAP regression command and the hidden runner replaced by $1 (MEDIUM-A1, MEDIUM-A2)
+make_bf_run() {
+  make_bf_tap
+  printf 'grep -q "^v=" lib/x.sh && echo 1..1 && echo "ok 1 v is set"\n' > "$S/tasks/bf-tap/fixture/tests/reg.sh"
+  printf '%s\n' "$1" > "$S/tasks/bf-tap/hidden/tests/run.sh"
+}
+
+@test "AG-24 container hardening (MEDIUM-A1): a named, limited, init-wrapped container with a kill deadline; a hung client is killed and the container removed by name" {
+  make_bf_run 'sleep 30'
+  RD="$T/run"; make_run bf-tap "$RD"
+  # the in-container deadline fires: 124, timed_out, no cleanup needed
+  LOA_EVAL_GRADE_TIMEOUT_S=1 grade "$RD" bf-tap
+  [ "$status" -eq 0 ]
+  [ "$(G '.hidden_tests | "\(.timed_out) \(.rc) \(.output_truncated)"')" = "true 124 false" ]
+  argv="$(tr '\0' '\n' < "$T/dlog/run-1.argv")"
+  for f in --init --rm --read-only; do grep -qx -- "$f" <<<"$argv"; done
+  [[ "$(tr '\0' ' ' < "$T/dlog/run-1.argv")" == *" --pids-limit 256 --memory 2g --cpus 2 --cap-drop ALL --security-opt no-new-privileges "*" timeout --signal=TERM --kill-after=10 1 bash tests/run.sh "* ]]
+  name="$(grep -A1 -x -- --name <<<"$argv" | tail -1)"
+  [[ "$name" =~ ^ablgrade-run-final-[0-9]+-[0-9]+$ ]]
+  [ ! -e "$T/dlog/kill.log" ] && [ ! -e "$T/dlog/rm.log" ]
+  # every container of the grade has its own name
+  [ "$(cat "$T"/dlog/run-*.argv | tr '\0' '\n' | grep -A1 -x -- --name | grep -c '^ablgrade-')" -eq "$(ls "$T"/dlog/run-*.argv | wc -l)" ]
+  # a container whose deadline never fires (the stub drops the timeout): the client deadline kills it
+  find "$T/dlog" -mindepth 1 -delete; echo 'DOCKER_STUB_HANG=1' > "$T/docker.env"
+  SECONDS=0
+  LOA_EVAL_GRADE_TIMEOUT_S=1 grade "$RD" bf-tap
+  [ "$status" -eq 0 ]
+  [ "$SECONDS" -lt 29 ]
+  [ "$(G '.hidden_tests | "\(.timed_out) \(.rc)"')" = "true 124" ]
+  name="$(tr '\0' '\n' < "$T/dlog/run-1.argv" | grep -A1 -x -- --name | tail -1)"
+  [ "$(cat "$T/dlog/kill.log")" = "kill $name" ]
+  [ "$(cat "$T/dlog/rm.log")" = "rm -f $name" ]
+}
+
+@test "AG-25 output cap (MEDIUM-A1): a command printing 10 MiB is truncated to 4 MiB, keeps its trailing summary, and the row still writes" {
+  make_bf_run 'head -c 10485760 /dev/zero | tr "\0" x; echo; echo 1..1; echo "ok 1 the value is set"'
+  RD="$T/run"; make_run bf-tap "$RD"; apply_ref "$RD"
+  grade "$RD" bf-tap
+  [ "$status" -eq 0 ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.parse_error) \(.output_truncated)"')" = "1/1 false true" ]
+  [ "$(G '.regressions | "\(.base.output_truncated) \(.final.output_truncated)"')" = "false false" ]
+  [ "$(wc -c < "$RD/grade.json")" -lt 4096 ]
+  run "$REPO_ROOT/evals/harness/ablation-row.sh" --run-dir "$RD" --task-yaml "$S/tasks/bf-tap/task.yaml"
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '.hidden_test_pass_rate' <<<"$output")" = 1 ]
+}
+
+@test "AG-26 node paths (MEDIUM-A2): printed node ids naming /dev/zero, a path above the tree and a FIFO are never opened; ids are still assigned" {
+  make_bf_run 'mkfifo tests/fifo.py
+echo "PASSED tests/run_ok.py::test_a"
+echo "ERROR /dev/zero"
+echo "ERROR ../../etc/passwd::test_x"
+echo "ERROR tests/fifo.py"
+echo "FAILED tests/fifo.py::test_y"
+echo "FAILED /dev/zero::test_z"
+echo "==== 1 passed, 2 failed, 3 errors in 0.01s ===="
+exit 1'
+  RD="$T/run"; make_run bf-tap "$RD"
+  run timeout 30 "$GRADER" "$RD" bf-tap --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
+  [ "$status" -eq 0 ]
+  [ -p "$RD/grading/final/tests/fifo.py" ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.parse_error) \(.failed_names | join(","))"')" = "1/4 false t1,t2,t3" ]
+  # a grader-owned source orders the cases even when the tree's copy became a FIFO
+  make_bf_run 'rm -f tests/t.py; mkfifo tests/t.py
+echo "FAILED tests/t.py::test_late"
+echo "PASSED tests/t.py::test_early"
+echo "==== 1 passed, 1 failed in 0.01s ===="
+exit 1'
+  printf 'def test_early():\n    pass\n\n\ndef test_late():\n    pass\n' > "$S/tasks/bf-tap/hidden/tests/t.py"
+  echo '{"files": [{"src": "tests/run.sh", "dest": "tests/run.sh"}, {"src": "tests/t.py", "dest": "tests/t.py"}]}' > "$S/tasks/bf-tap/hidden/manifest.json"
+  RD="$T/run2"; make_run bf-tap "$RD"
+  run timeout 30 "$GRADER" "$RD" bf-tap --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
+  [ "$status" -eq 0 ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total) \(.failed_names | join(","))"')" = "1/2 t2" ]
+}
+
+@test "AG-27 sizes and symlinks (MEDIUM-A3): a 20 MiB sparse file is skipped and counted; a symlinked feedback file or review.md is never followed" {
+  RD="$T/run"; make_run bf-py "$RD"; apply_ref "$RD"
+  truncate -s 20M "$RD/sandbox/big.bin"
+  printf 'x\n' > "$RD/sandbox/small.bin"
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.oversized_files_skipped')" = 1 ]
+  [ ! -e "$RD/grading/final/big.bin" ] && [ -f "$RD/grading/final/small.bin" ]
+  [ "$(G '.hidden_tests | "\(.passed)/\(.total)"')" = "7/7" ]
+  # a symlinked engineer-feedback.md: the gate ran, its trailer is unreadable → none (the target is never read)
+  printf '# x\n<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED"} -->\n' > "$T/outside.md"
+  ln -s "$T/outside.md" "$RD/sandbox/grimoires/loa/a2a/sprint-1/engineer-feedback.md"
+  grade "$RD" bf-py
+  [ "$status" -eq 0 ]
+  [ "$(G '.verdicts.review')" = none ] && [ "$(G '.verdict | "\(.source_file) \(.value)"')" = "engineer-feedback.md none" ]
+  # review-catch: a symlinked review.md gives no verdict and no citations
+  RD="$T/rc"; make_run rc-x "$RD"
+  printf 'head/lib/x.sh:5 guard\nVerdict: APPROVED\n' > "$T/outside-review.md"
+  ln -s "$T/outside-review.md" "$RD/sandbox/review.md"
+  grade "$RD" rc-x
+  [ "$status" -eq 0 ]
+  [ "$(G '.verdict')" = null ] && [ "$(G '.recall.defects_caught')" = 0 ]
+  # a feedback directory behind a symlinked parent is outside the sandbox: none
+  RD="$T/rc2"; make_run rc-x "$RD"
+  mkdir -p "$T/elsewhere/sprint-1"; cp "$T/outside.md" "$T/elsewhere/sprint-1/auditor-sprint-feedback.md"
+  find "$RD/sandbox/grimoires/loa/a2a" -delete; ln -s "$T/elsewhere" "$RD/sandbox/grimoires/loa/a2a"
+  grade "$RD" rc-x
+  [ "$(G '.verdicts.audit')" = none ]
+}
+
+@test "AG-28 host mode is opt-in (LOW-A1): refused with exit 2 unless LOA_EVAL_ALLOW_HOST_GRADING=1; allowed runs warn and record executor_mode host" {
+  RD="$T/run"; make_run rc-x "$RD"; printf 'head/lib/x.sh:5\n' > "$RD/sandbox/review.md"
+  run env -u LOA_EVAL_ALLOW_HOST_GRADING "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
+  [ "$status" -eq 2 ]
+  [[ "$output" == *"--executor host is refused"*"no filesystem, process or network isolation"*"LOA_EVAL_ALLOW_HOST_GRADING=1"* ]]
+  [ ! -e "$RD/grade.json" ]
+  run env LOA_EVAL_ALLOW_HOST_GRADING=yes "$GRADER" --self-check base --task-yaml "$S/tasks/rc-x/task.yaml" --allow-unfrozen --executor host
+  [ "$status" -eq 2 ]
+  run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
+  [ "$status" -eq 0 ]
+  [[ "$output" == *"WARNING --executor host"* ]]
+  [ "$(G '.executor_mode')" = host ]
+  # container mode needs no opt-in
+  run env -u LOA_EVAL_ALLOW_HOST_GRADING "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
+  [ "$status" -eq 0 ] && [ "$(G '.executor_mode')" = container ]
+}
~~~~

## H61 — evals/tests/fixtures/docker-stub.sh — head line 6

Head context (head/evals/tests/fixtures/docker-stub.sh, lines 1–18):

~~~~text
     1 | #!/usr/bin/env bash
     2 | # docker-stub.sh — stand-in for the docker 26.1 CLI in evals/tests/pipeline-run.bats.
     3 | #   docker image inspect --format … <img>  prints $DOCKER_STUB_IMAGE_ID (default
     4 | #                                         sha256:feedface…); exit 1 when
     5 | #                                         DOCKER_STUB_NO_IMAGE=1
>    6 | #   docker kill …                         records and exits 0
     7 | #   (each -v spec and, for the non-/workspace mounts, every path under its source go
     8 | #    to $DOCKER_STUB_LOG/run-<n>.mounts)
     9 | #   docker run <flags> <image> <cmd…>     records argv (NUL-separated) to
    10 | #                                         $DOCKER_STUB_LOG/run-<n>.argv, then runs
    11 | #                                         <cmd…> on the host: /workspace in args and
    12 | #                                         env values maps to the -v source of
    13 | #                                         every mount (/workspace, /home/evaluser),
    14 | #                                         the environment is exactly the -e set
    15 | #                                         (bare `-e KEY` takes the client's value),
    16 | #                                         the command word `claude` maps to
    17 | #                                         $DOCKER_STUB_CLAUDE; when $DOCKER_STUB_PATH is
    18 | #                                         set and no -e PATH was given, PATH=<it> joins
~~~~

The change from head to the fix:

~~~~diff
@@ -6 +6,2 @@
-#   docker kill …                         records and exits 0
+#   docker kill … / docker rm …           records the argv line to $DOCKER_STUB_LOG/kill.log
+#                                         or rm.log and exits 0
~~~~

## H62 — evals/tests/fixtures/docker-stub.sh — head line 20

Head context (head/evals/tests/fixtures/docker-stub.sh, lines 8–32):

~~~~text
     8 | #    to $DOCKER_STUB_LOG/run-<n>.mounts)
     9 | #   docker run <flags> <image> <cmd…>     records argv (NUL-separated) to
    10 | #                                         $DOCKER_STUB_LOG/run-<n>.argv, then runs
    11 | #                                         <cmd…> on the host: /workspace in args and
    12 | #                                         env values maps to the -v source of
    13 | #                                         every mount (/workspace, /home/evaluser),
    14 | #                                         the environment is exactly the -e set
    15 | #                                         (bare `-e KEY` takes the client's value),
    16 | #                                         the command word `claude` maps to
    17 | #                                         $DOCKER_STUB_CLAUDE; when $DOCKER_STUB_PATH is
    18 | #                                         set and no -e PATH was given, PATH=<it> joins
    19 | #                                         the environment (ablation-grade.bats: the
>   20 | #                                         image's python3/bats stand-ins)
    21 | set -euo pipefail
    22 | log="${DOCKER_STUB_LOG:-/dev/null}"
    23 | case "${1:-}" in
    24 |   --version) echo "Docker version 26.1.5 (stub)"; exit 0 ;;
    25 |   image)
    26 |     [[ "${DOCKER_STUB_NO_IMAGE:-0}" == 1 ]] && { echo "Error: No such image" >&2; exit 1; }
    27 |     echo "${DOCKER_STUB_IMAGE_ID:-sha256:feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface}"; exit 0 ;;
    28 |   kill) [[ "$log" != /dev/null ]] && printf '%s\n' "$*" >> "$log/kill.log"; exit 0 ;;
    29 |   run) shift ;;
    30 |   *) echo "docker-stub: unsupported: $*" >&2; exit 2 ;;
    31 | esac
    32 | if [[ "$log" != /dev/null ]]; then
~~~~

The change from head to the fix:

~~~~diff
@@ -20 +21,5 @@
-#                                         image's python3/bats stand-ins)
+#                                         image's python3/bats stand-ins); with
+#                                         DOCKER_STUB_HANG=1 a leading `timeout [opts] T`
+#                                         is dropped from <cmd…> (a container whose
+#                                         deadline never fires: the grader's own client
+#                                         deadline and docker kill/rm -f must act)
~~~~

## H63 — evals/tests/fixtures/docker-stub.sh — insertion after head line 28

Head context (head/evals/tests/fixtures/docker-stub.sh, lines 17–40):

~~~~text
    17 | #                                         $DOCKER_STUB_CLAUDE; when $DOCKER_STUB_PATH is
    18 | #                                         set and no -e PATH was given, PATH=<it> joins
    19 | #                                         the environment (ablation-grade.bats: the
    20 | #                                         image's python3/bats stand-ins)
    21 | set -euo pipefail
    22 | log="${DOCKER_STUB_LOG:-/dev/null}"
    23 | case "${1:-}" in
    24 |   --version) echo "Docker version 26.1.5 (stub)"; exit 0 ;;
    25 |   image)
    26 |     [[ "${DOCKER_STUB_NO_IMAGE:-0}" == 1 ]] && { echo "Error: No such image" >&2; exit 1; }
    27 |     echo "${DOCKER_STUB_IMAGE_ID:-sha256:feedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedfacefeedface}"; exit 0 ;;
    28 |   kill) [[ "$log" != /dev/null ]] && printf '%s\n' "$*" >> "$log/kill.log"; exit 0 ;;
    29 |   run) shift ;;
    30 |   *) echo "docker-stub: unsupported: $*" >&2; exit 2 ;;
    31 | esac
    32 | if [[ "$log" != /dev/null ]]; then
    33 |   mkdir -p "$log"; n=1; while [[ -e "$log/run-$n.argv" ]]; do n=$((n + 1)); done
    34 |   printf '%s\0' run "$@" > "$log/run-$n.argv"
    35 | fi
    36 | ws="" wd="/"
    37 | mounts=() envs=()
    38 | # flags that take a value (docker 26.1 run); everything else before the image is boolean
    39 | while [[ $# -gt 0 ]]; do
    40 |   case "$1" in
~~~~

The change from head to the fix:

~~~~diff
@@ -28,0 +34 @@
+  rm) [[ "$log" != /dev/null ]] && printf '%s\n' "$*" >> "$log/rm.log"; exit 0 ;;
~~~~

## H64 — evals/tests/fixtures/docker-stub.sh — head lines 56–57

Head context (head/evals/tests/fixtures/docker-stub.sh, lines 44–69):

~~~~text
    44 |       # record each mount and, for the non-/workspace mounts, every path under its source
    45 |       if [[ "$log" != /dev/null ]]; then
    46 |         { printf '%s\n' "$2"
    47 |           if [[ "$dst" != /workspace ]]; then (cd "$src" && find . -mindepth 1 | sed 's|^\./|  |' | LC_ALL=C sort); fi
    48 |         } >> "$log/run-$n.mounts"
    49 |       fi
    50 |       shift 2 ;;
    51 |     -e|--env)
    52 |       # KEY=value as given; a bare KEY takes the client's own value (how secrets travel)
    53 |       if [[ "$2" == *=* ]]; then envs+=("$2"); elif [[ -n "${!2+x}" ]]; then envs+=("$2=${!2}"); fi
    54 |       shift 2 ;;
    55 |     -w|--workdir) wd="$2"; shift 2 ;;
>   56 |     --name|--user|--network|--tmpfs|--pids-limit|--memory|--cpus) shift 2 ;;
>   57 |     --rm|--read-only|-i|-t) shift ;;
    58 |     -*) echo "docker-stub: unknown flag $1" >&2; exit 2 ;;
    59 |     *) break ;;
    60 |   esac
    61 | done
    62 | shift   # the image
    63 | [[ -n "$ws" ]] || { echo "docker-stub: no /workspace mount" >&2; exit 2; }
    64 | map() {  # container path → host path, for every mount
    65 |   local s="$1" m dst src
    66 |   for m in "${mounts[@]}"; do dst="${m%%=*}" src="${m#*=}"; s="${s//$dst/$src}"; done
    67 |   printf '%s' "$s"
    68 | }
    69 | cmd=() menv=()
~~~~

The change from head to the fix:

~~~~diff
@@ -56,2 +62,2 @@
-    --name|--user|--network|--tmpfs|--pids-limit|--memory|--cpus) shift 2 ;;
-    --rm|--read-only|-i|-t) shift ;;
+    --name|--user|--network|--tmpfs|--pids-limit|--memory|--cpus|--cap-drop|--security-opt) shift 2 ;;
+    --rm|--read-only|--init|-i|-t) shift ;;
~~~~

## H65 — evals/tests/fixtures/docker-stub.sh — insertion after head line 62

Head context (head/evals/tests/fixtures/docker-stub.sh, lines 51–74):

~~~~text
    51 |     -e|--env)
    52 |       # KEY=value as given; a bare KEY takes the client's own value (how secrets travel)
    53 |       if [[ "$2" == *=* ]]; then envs+=("$2"); elif [[ -n "${!2+x}" ]]; then envs+=("$2=${!2}"); fi
    54 |       shift 2 ;;
    55 |     -w|--workdir) wd="$2"; shift 2 ;;
    56 |     --name|--user|--network|--tmpfs|--pids-limit|--memory|--cpus) shift 2 ;;
    57 |     --rm|--read-only|-i|-t) shift ;;
    58 |     -*) echo "docker-stub: unknown flag $1" >&2; exit 2 ;;
    59 |     *) break ;;
    60 |   esac
    61 | done
    62 | shift   # the image
    63 | [[ -n "$ws" ]] || { echo "docker-stub: no /workspace mount" >&2; exit 2; }
    64 | map() {  # container path → host path, for every mount
    65 |   local s="$1" m dst src
    66 |   for m in "${mounts[@]}"; do dst="${m%%=*}" src="${m#*=}"; s="${s//$dst/$src}"; done
    67 |   printf '%s' "$s"
    68 | }
    69 | cmd=() menv=()
    70 | for a in "$@"; do
    71 |   a="$(map "$a")"
    72 |   [[ "$a" == claude ]] && a="${DOCKER_STUB_CLAUDE:?DOCKER_STUB_CLAUDE unset}"
    73 |   cmd+=("$a")
    74 | done
~~~~

The change from head to the fix:

~~~~diff
@@ -62,0 +69,3 @@
+if [[ "${DOCKER_STUB_HANG:-0}" == 1 && "${1:-}" == timeout ]]; then
+  shift; while [[ "${1:-}" == -* ]]; do shift; done; shift
+fi
~~~~

## H66 — evals/tests/validate-suite.bats — insertion after head line 193

Head context (head/evals/tests/validate-suite.bats, lines 182–193):

~~~~text
   182 |   run "$VS" --root "$R" --allow-partial
   183 |   [ "$status" -eq 1 ]
   184 |   yq -i '.source.churn = "big"' "$R/tasks/refactor-01/task.yaml"
   185 |   run "$VS" --root "$R" --allow-partial
   186 |   [ "$status" -eq 1 ]
   187 |   grep -q 'source.churn must be' <<<"$output"
   188 |   # any other unknown source key is still refused
   189 |   yq -i 'del(.source.churn) | .source.size = 3' "$R/tasks/refactor-01/task.yaml"
   190 |   run "$VS" --root "$R" --allow-partial
   191 |   [ "$status" -eq 1 ]
   192 |   grep -q 'schema: source.size is not a known key' <<<"$output"
   193 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -193,0 +194,45 @@
+
+@test "VS-12 grader_protected lists every file under fixture/tests/ for build types (Sprint 259 MEDIUM-2); review-catch is exempt" {
+  make_task "$R" tasks bug-fix-01 bug-fix
+  make_task "$R" tasks refactor-01 refactor
+  make_task "$R" tasks review-catch-01 review-catch
+  run "$VS" --root "$R" --allow-partial
+  [ "$status" -eq 0 ]
+  local fx
+  for fx in bug-fix-01 refactor-01; do
+    mkdir -p "$R/tasks/$fx/fixture/tests/unit"
+    printf 'def test_one():\n    assert True\n' > "$R/tasks/$fx/fixture/tests/test_existing.py"
+    printf 'def test_two():\n    assert True\n' > "$R/tasks/$fx/fixture/tests/unit/test_deep.py"
+  done
+  run "$VS" --root "$R" --allow-partial
+  [ "$status" -eq 1 ]
+  grep -q 'tasks/bug-fix-01: schema: grader_protected must list every file under fixture/tests/: missing tests/test_existing.py' <<<"$output"
+  grep -q 'tasks/bug-fix-01: schema: grader_protected must list every file under fixture/tests/: missing tests/unit/test_deep.py' <<<"$output"
+  grep -q 'tasks/refactor-01: schema: grader_protected must list every file under fixture/tests/: missing tests/test_existing.py' <<<"$output"
+  [ "$(grep -c 'grader_protected must list' <<<"$output")" -eq 4 ]
+  for fx in bug-fix-01 refactor-01; do
+    yq -i '.grader_protected = ["tests/conftest.py", "tests/test_existing.py", "tests/unit/test_deep.py"]' "$R/tasks/$fx/task.yaml"
+  done
+  run "$VS" --root "$R" --allow-partial
+  [ "$status" -eq 0 ]
+  # a symlink under tests/ is a file to protect too
+  ln -s test_existing.py "$R/tasks/bug-fix-01/fixture/tests/alias.py"
+  run "$VS" --root "$R" --allow-partial
+  [ "$status" -eq 1 ]
+  grep -q 'missing tests/alias.py' <<<"$output"
+}
+
+@test "VS-13 a refactor task with a non-null regression_command is a violation: test_command is the regression check (Sprint 259 review round 2, DISS-C-003)" {
+  make_task "$R" tasks refactor-01 refactor
+  run "$VS" --root "$R" --allow-partial
+  [ "$status" -eq 0 ]
+  yq -i '.regression_command = ["python3", "-m", "pytest", "-q", "tests"]' "$R/tasks/refactor-01/task.yaml"
+  run "$VS" --root "$R" --allow-partial
+  [ "$status" -eq 1 ]
+  grep -q 'tasks/refactor-01: schema: regression_command must be null for refactor (test_command is the regression check)' <<<"$output"
+  # the same command on a bug-fix task is fine
+  make_task "$R" tasks bug-fix-01 bug-fix
+  yq -i '.regression_command = null' "$R/tasks/refactor-01/task.yaml"
+  run "$VS" --root "$R" --allow-partial
+  [ "$status" -eq 0 ]
+}
~~~~
