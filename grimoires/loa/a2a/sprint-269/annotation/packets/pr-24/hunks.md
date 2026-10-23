# Hunks — pr-24

The later fix changed 31 region(s) in 5 of the change's 17 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — evals/harness/ablation-grade.sh — head lines 167–168

Head context (head/evals/harness/ablation-grade.sh, lines 155–180):

~~~~text
   155 | # citations (MEDIUM-A3).
   156 | # verdict = {source_file, value}: the audit's, else the review's, else review.md's
   157 | # `Verdict:` line (A0), else null. verdict_accuracy_per_gate {review, audit}: build —
   158 | # true when APPROVED and the tree that gate read passes every hidden test, or
   159 | # CHANGES_REQUIRED and it fails one; review-catch — true iff (CHANGES_REQUIRED) ==
   160 | # (the key holds a high or critical defect); refactor — the tree passes when the
   161 | # structural check AND the fixture suite are green on it; a gate without a trailer is false; a gate
   162 | # that did not run is null. verdict_accuracy = audit's, else review's, else null.
   163 | #
   164 | # Contamination (D-4.7, DEC-0493): every tool_use input in transcripts/events-*.jsonl —
   165 | # Bash command; Read/Grep/Glob file_path|path|pattern; Write/Edit/MultiEdit/NotebookEdit
   166 | # file_path|notebook_path; WebFetch url; WebSearch query — is checked for: `hidden` (any
>  167 | # case; in a Bash command only as a token: HIDDEN, or hidden next to / . _ = - — 1.2.4,
>  168 | # DEC-0551) → hidden; grimoires/loa/evals/ablation-2.0 → suite_path; 0xHoneyJar/loa →
   169 | # repo_name; `git log … --all` or `git reflog` (Bash) → counted in history_probes, NOT a
   170 | # contamination hit (1.2.1, DEC-0540: the sandbox is a fresh git init at base, so there is no
   171 | # history to leak; the count is telemetry); an absolute path
   172 | # (path fields, the Glob pattern, path-shaped Bash words; a one-component `/x/` word is
   173 | # read as a regex only right after s, y, =, ~ or a single quote — `cd /root/` is a path; a
   174 | # one-component `/word` with no second slash is a command token — Loa slash commands such as
   175 | # `/review-sprint sprint-1` in report text — unless the component is root, home, mnt, media or
   176 | # srv, 1.2.1 DEC-0540)
   177 | # outside /workspace /tmp /home/evaluser /dev /proc /sys /usr /bin
   178 | # /sbin /lib /lib64 /etc /opt /var (container), or outside the sandbox root (the
   179 | # sessions' init cwd and <run-dir>/sandbox), /tmp and those system directories (host; no
   180 | # credential store under ~ is exempt: LOW-A2) → outside_path. A path or Bash word starting
~~~~

The change from head to the fix:

~~~~diff
@@ -167,2 +167,4 @@
-# case; in a Bash command only as a token: HIDDEN, or hidden next to / . _ = - — 1.2.4,
-# DEC-0551) → hidden; grimoires/loa/evals/ablation-2.0 → suite_path; 0xHoneyJar/loa →
+# case; in a Bash command only as a token: HIDDEN, or hidden in any case next to / . _ = - * ?,
+# or hidden followed by a capital (hiddenTests) — 1.2.4 DEC-0551, 1.2.6 LOW-2; accepted gap: a
+# bare `hidden` argument is not a probe in a suite whose briefs are about hidden state —
+# refactor-03's agents run pytest -k hidden for their own test_no_hidden_state) → hidden; grimoires/loa/evals/ablation-2.0 → suite_path; 0xHoneyJar/loa →
~~~~

## H02 — evals/harness/ablation-grade.sh — head line 176

Head context (head/evals/harness/ablation-grade.sh, lines 164–188):

~~~~text
   164 | # Contamination (D-4.7, DEC-0493): every tool_use input in transcripts/events-*.jsonl —
   165 | # Bash command; Read/Grep/Glob file_path|path|pattern; Write/Edit/MultiEdit/NotebookEdit
   166 | # file_path|notebook_path; WebFetch url; WebSearch query — is checked for: `hidden` (any
   167 | # case; in a Bash command only as a token: HIDDEN, or hidden next to / . _ = - — 1.2.4,
   168 | # DEC-0551) → hidden; grimoires/loa/evals/ablation-2.0 → suite_path; 0xHoneyJar/loa →
   169 | # repo_name; `git log … --all` or `git reflog` (Bash) → counted in history_probes, NOT a
   170 | # contamination hit (1.2.1, DEC-0540: the sandbox is a fresh git init at base, so there is no
   171 | # history to leak; the count is telemetry); an absolute path
   172 | # (path fields, the Glob pattern, path-shaped Bash words; a one-component `/x/` word is
   173 | # read as a regex only right after s, y, =, ~ or a single quote — `cd /root/` is a path; a
   174 | # one-component `/word` with no second slash is a command token — Loa slash commands such as
   175 | # `/review-sprint sprint-1` in report text — unless the component is root, home, mnt, media or
>  176 | # srv, 1.2.1 DEC-0540)
   177 | # outside /workspace /tmp /home/evaluser /dev /proc /sys /usr /bin
   178 | # /sbin /lib /lib64 /etc /opt /var (container), or outside the sandbox root (the
   179 | # sessions' init cwd and <run-dir>/sandbox), /tmp and those system directories (host; no
   180 | # credential store under ~ is exempt: LOW-A2) → outside_path. A path or Bash word starting
   181 | # ~/, $HOME/ or ${HOME}/ is always outside, and /proc/<pid|self|thread-self>/{environ,
   182 | # cmdline,maps,mem} and /var/run are outside although /proc and /var are allowed. The first hit
   183 | # in phase order is contaminated: {phase, pattern, excerpt_id: "<phase>:<line>"} (never
   184 | # the text); else null. The scan is a LOWER BOUND on leakage: obfuscated access, reads
   185 | # by programs the agent wrote, and network access by other means are not seen.
   186 | #
   187 | # grade.json (ids only in every summary field: no test name, defect title or excerpt):
   188 | #   {schema_version: 1, grader_version: "1.2.0", task_id, task_type, suite_frozen,
~~~~

The change from head to the fix:

~~~~diff
@@ -176 +178,13 @@
-# srv, 1.2.1 DEC-0540)
+# srv, 1.2.1 DEC-0540; such a sensitive one-component word is skipped only inside a quoted
+# string with other text — grep -E ' /tmp | /home ' — while the word that is the whole quoted
+# argument, cd "/root", ls '/home', cd '/root/', grep '/root' f, is a candidate: a quote state
+# machine, not a parity count, 1.2.6 LOW-1; accepted gaps: a one-component word inside longer
+# quoted text, echo "cd /root", and $'…' strings read as plain single quotes. Heredoc bodies
+# are stripped; the operator line is scanned — cat <<'EOF' > /root/x is a hit, 1.2.6
+# MEDIUM-1. Heredoc bodies are not path-scanned even when the operator line's command is an
+# interpreter (python3, python, bash, sh, node, perl, ruby; python3 - <<'PY'): that code
+# opens whatever it names, but the cycle grades the container executor only (DEC-0411; host
+# grading needs LOA_EVAL_ALLOW_HOST_GRADING=1), where /root, /mnt, /media and /srv hold
+# nothing, so the gap is a missed signal, not a missed leak; widening the scan would re-open
+# the written-prose false positives of KF-046. The hidden/suite/repo substring scans still
+# read every body, and grade.json heredoc_interpreters counts these heredocs, 1.2.6 LOW-3)
~~~~

## H03 — evals/harness/ablation-grade.sh — head lines 200–202

Head context (head/evals/harness/ablation-grade.sh, lines 188–214):

~~~~text
   188 | #   {schema_version: 1, grader_version: "1.2.0", task_id, task_type, suite_frozen,
   189 | #    executor_mode, image, snapshots_graded: [labels], hidden_tests {passed, total,
   190 | #    failed_names, parse_error, timed_out, rc, output_truncated}, structural (refactor:
   191 | #    {passed, total, failed_names, parse_error, suite_green_base, suite_green_final}; else
   192 | #    null), regressions ({newly_failing, base {passed, total, rc, timed_out,
   193 | #    output_truncated}, final {…}, parse_error, base_green, final_green} or null without a
   194 | #    regression check), snapshot_tests {implement?,
   195 | #    fix1?: {passed, total}} (refactor: the structural check), recall (review-catch
   196 | #    {defects_seeded, defects_caught, recall, flags, missed}; else null),
   197 | #    false_positives, verdict, verdicts {review, audit}, verdict_accuracy,
   198 | #    verdict_accuracy_per_gate {review, audit}, diff_lines, files_changed,
   199 | #    symlinks_dropped, harness_files_removed, oversized_files_skipped, history_probes,
>  200 | #    contaminated}
>  201 | # grader 1.2.1 (Sprint 260 calibration, DEC-0540): git history probes are telemetry; a
>  202 | # one-component absolute word is a command token unless it names root, home, mnt, media or srv.
   203 | # grader 1.2.5 (DEC-0557, P1 resume): a Bash path word right after a closing quote glued to the
   204 | # preceding token ("$D"/evals/x, pr/'"$v"'/.claude/y) is a path tail, not an absolute path.
   205 | # grader 1.2.4 (DEC-0551, priority batch P1): a Bash word beginning with /, (a sed-range remnant
   206 | # after a first address holding a space) or carrying = (regex / key=value token) is not a path.
   207 | # grader 1.2.3 (DEC-0546, priority batch P1): a Bash word shaped /re1/,/re2/… (a sed address
   208 | # range) is a regex pair, not a path candidate (seen: sed -n '/======TEMPLATE/,/======STAT/p').
   209 | # grader 1.2.2 (DEC-0541): heredoc bodies are stripped before the path-word scan (written file
   210 | # text is data; the hidden/suite/repo scans still read it); ~/, $HOME/ and ${HOME}/ are outside
   211 | # in host mode only (the container home /home/evaluser is an allowed root); a one-component
   212 | # word with a trailing slash (/,/ /x/ sed and awk delimiters) follows the same single-component rule.
   213 | # grader 1.1.0 (Sprint 259 fix round): refactor hidden_tests = the structural check,
   214 | # exit-status-aware green, symlink filtering; 1.0.0 grades of refactor tasks differ.
~~~~

The change from head to the fix:

~~~~diff
@@ -200,3 +214,25 @@
-#    contaminated}
+#    heredoc_interpreters (1.2.6: heredocs in Bash inputs whose operator line's command, the
+#    first word after the last ; & | ( or { before << and after NAME=value assignments, by
+#    basename, is python3, python3.N, python, bash, sh, node, perl or ruby; counted up to the
+#    first contamination hit, like history_probes; telemetry, not a row field), contaminated}
 # grader 1.2.1 (Sprint 260 calibration, DEC-0540): git history probes are telemetry; a
 # one-component absolute word is a command token unless it names root, home, mnt, media or srv.
+# grader 1.2.9 (Sprint 260 audit round 2): the glob rule reads * and ? only — a [ after a one-component word
+# is a regex bracket expression (two P1 commands read as contaminated under 1.2.8: grep '/home[^"]*…',
+# sed 's/job\["status"\]…'; KF-046 recurrence 7) — and a quoted one-component pattern stays exempt.
+# grader 1.2.8 (Sprint 260 audit round 1, DISS-C-001, C-002): the dot-directory skip applies after
+# os.path.normpath (/./root/x is /root/x); an empty quoted string before a path is not a glued token
+# (''/root/x); a one-component word followed by a glob metacharacter stays a candidate (/roo*, /ro?t);
+# a bare hidden that is the direct argument of cd, ls, cat, stat, tree, head, tail, less, more, du, file
+# or of find -name/-path/-wholename is a hit (filesystem probe), while -k hidden, grep hidden and prose stay
+# exempt. A 1.2.7 grade may differ in contaminated on those shapes (more hits).
+# grader 1.2.7 (Sprint 260 review round 2, DISS-C-001, C-002, C-006): the glob shapes of the hidden token
+# (* and ? beside the word) are read on the heredoc-stripped command only, so "Is any state hidden?" and
+# "**hidden**" in written prose are clean; the camelCase branch accepts PascalCase (HiddenTests/); SIGTERM
+# runs the finally (SCRATCH removed). A 1.2.6 grade may differ in contaminated on those prose shapes.
+# grader 1.2.6 (Sprint 260 review round 1, DISS-C-001 … C-005): the heredoc operator line's
+# remainder after <<WORD is scanned and the heredoc regex is linear (one line per body
+# iteration, no re.S); a sensitive word that is the whole quoted argument is a candidate (a
+# quote state machine); hidden adjacency is case-insensitive with camelCase and glob shapes;
+# heredoc_interpreters counted. Contamination exemptions only: a 1.2.5 grade may differ in
+# contaminated (mostly more hits; a word parity counting flagged inside quoted text is skipped).
~~~~

## H04 — evals/harness/ablation-grade.sh — head lines 256–258

Head context (head/evals/harness/ablation-grade.sh, lines 244–270):

~~~~text
   244 | # Tested by evals/tests/ablation-grade.bats (docker = evals/tests/fixtures/docker-stub.sh).
   245 | # No .claude/ code is sourced and nothing is sourced or eval'd from a variable (eval.yml
   246 | # trust boundary); hashing is Python hashlib.
   247 | # =============================================================================
   248 | set -euo pipefail
   249 | export LC_ALL=C
   250 | 
   251 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   252 | REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
   253 | case "${1:-}" in -h|--help) sed -n '3,/^# =====/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;; esac
   254 | 
   255 | exec python3 -I - "$SCRIPT_DIR" "$REPO_ROOT" "${EVAL_DOCKER_BIN:-docker}" "$@" <<'PY'
>  256 | import argparse, difflib, filecmp, json, os, re, shutil, site, stat, subprocess, sys, tarfile, tempfile, threading, time
>  257 | 
>  258 | GRADER_VERSION = "1.2.5"
   259 | SCRIPT_DIR, REPO_ROOT, DOCKER_DEFAULT = sys.argv[1], sys.argv[2], sys.argv[3]
   260 | SPRINT = "sprint-1"
   261 | _t = os.environ.get("LOA_EVAL_GRADE_TIMEOUT_S", "")
   262 | TEST_TIMEOUT_S = int(_t) if re.fullmatch(r"[1-9][0-9]{0,3}", _t) else 120   # tests shorten it
   263 | KILL_AFTER_S = 10                                    # timeout --kill-after (MEDIUM-A1)
   264 | OUTER_GRACE_S = max(5, min(60, TEST_TIMEOUT_S // 2))  # the client deadline beyond T + KILL_AFTER_S
   265 | OUTPUT_CAP = 4 * 1024 * 1024      # captured stdout per command (MEDIUM-A1)
   266 | FILE_CAP = 16 * 1024 * 1024       # a regular file above this is not copied (MEDIUM-A3)
   267 | READ_CAP = 2 * 1024 * 1024        # verdict, citation and envelope reads (MEDIUM-A3)
   268 | NODE_FILE_CAP = 1024 * 1024       # a test file read for case order (MEDIUM-A2)
   269 | # pytest and bats load these from the tree under test (HIGH-A1); see is_harness()
   270 | HARNESS_NAMES = {"conftest.py", "pytest.ini", ".pytest.ini", "pyproject.toml", "setup.cfg", "tox.ini",
~~~~

The change from head to the fix:

~~~~diff
@@ -256,3 +292,7 @@
-import argparse, difflib, filecmp, json, os, re, shutil, site, stat, subprocess, sys, tarfile, tempfile, threading, time
+import argparse, difflib, filecmp, json, os, re, shutil, signal, site, stat, subprocess, sys, tarfile, tempfile, threading, time
+# 1.2.7 (Sprint 260 review round 2, DISS-C-002): a SIGTERM (the runner's post-run deadline) becomes SystemExit so
+# the finally below removes SCRATCH; a running docker command ends at its own in-container deadline (--init forwards
+# TERM; names carry this pid, so a later grade never collides)
+signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(143))
 
-GRADER_VERSION = "1.2.5"
+GRADER_VERSION = "1.2.9"
~~~~

## H05 — evals/harness/ablation-grade.sh — head lines 1328–1329

Head context (head/evals/harness/ablation-grade.sh, lines 1316–1341):

~~~~text
  1316 |     pos = {d.get("id"): i for i, d in enumerate(defects, 1)}
  1317 |     recall = {"defects_seeded": det.get("planted", len(defects)), "defects_caught": len(det.get("detected") or []),
  1318 |               "recall": det.get("recall"), "flags": det.get("findings_cited"),
  1319 |               "missed": [f"d{pos[x]}" for x in det.get("missed") or [] if x in pos]}
  1320 |     return recall, false_positives(cites, defects)
  1321 | 
  1322 | 
  1323 | # ------------------------------------------------------------------ contamination
  1324 | SYS_DIRS = ["/dev", "/proc", "/sys", "/usr", "/bin", "/sbin", "/lib", "/lib64", "/etc", "/opt", "/var"]
  1325 | GIT_HIST = re.compile(r"\bgit\b[^;&|\n]*\blog\b[^;&|\n]*--all\b|\bgit\b[^;&|\n]*\breflog\b")
  1326 | # DEC-0551 (1.2.4): in a Bash command `hidden` counts as a token — HIDDEN in capitals (a test file
  1327 | # name), or lowercase hidden adjacent to a path or identifier character — not as a bare English
> 1328 | # word in written prose ("any hidden interaction with store_true" in a reviewer's heredoc)
> 1329 | HIDDEN_TOKEN = re.compile(r"HIDDEN|(?<=[/._=-])hidden\b|\bhidden(?=[/_=-]|\.[A-Za-z0-9])")
  1330 | ABS_WORD = re.compile(r"(?:(?<=^)|(?<=[\s=:'\"`(<>|;&,]))(/[A-Za-z0-9._@+%=,:~-][A-Za-z0-9._@+%=,:~/-]*)")
  1331 | # LOW-A2: home-relative words are always outside (no root under any home is allowed)
  1332 | HOME_WORD = re.compile(r"(?:(?<=^)|(?<=[\s=:'\"`(<>|;&,]))(?:~|\$HOME|\$\{HOME\})/")
  1333 | HOME_PREFIXES = ("~/", "$HOME/", "${HOME}/")
  1334 | # inside allowed system roots, but secrets: another process's environment, memory or argv, and /var/run
  1335 | SENSITIVE = re.compile(r"^/proc/(?:\d+|self|thread-self)/(?:environ|cmdline|maps|mem)(?:/|$)|^/var/run(?:/|$)")
  1336 | FIELDS = {"Bash": ["command"], "Read": ["file_path", "path"], "Grep": ["path", "pattern"], "Glob": ["path", "pattern"],
  1337 |           "Write": ["file_path"], "Edit": ["file_path"], "MultiEdit": ["file_path"], "NotebookEdit": ["notebook_path"],
  1338 |           "WebFetch": ["url"], "WebSearch": ["query"]}
  1339 | PATH_FIELDS = {"file_path", "path", "notebook_path"}
  1340 | 
  1341 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -1328,2 +1368,14 @@
-# word in written prose ("any hidden interaction with store_true" in a reviewer's heredoc)
-HIDDEN_TOKEN = re.compile(r"HIDDEN|(?<=[/._=-])hidden\b|\bhidden(?=[/_=-]|\.[A-Za-z0-9])")
+# word in written prose ("any hidden interaction with store_true" in a reviewer's heredoc).
+# 1.2.6 (LOW-2): the adjacency branches are case-insensitive (Hidden/x) and hidden followed by a capital
+# is a camelCase or PascalCase identifier (hiddenTests/, HiddenTests/ — 1.2.7, DISS-C-006); a bare hidden
+# argument (pytest -k hidden, refactor-03) stays legitimate. HIDDEN_TOKEN reads the whole value, heredoc
+# bodies included. The glob shapes (* and ? beside the word: find -iname '*hidden*') are HIDDEN_GLOB and
+# are read on the heredoc-stripped command only (1.2.7, DISS-C-001): in written prose "Is any state hidden?"
+# and "**hidden**" are English and Markdown, not globs
+HIDDEN_TOKEN = re.compile(r"HIDDEN|(?i:(?<=[/._=-])hidden\b|\bhidden(?=[/_=-]|\.[A-Za-z0-9]))|\b[Hh]idden(?=[A-Z])")
+HIDDEN_GLOB = re.compile(r"(?i:(?<=[*?])hidden\b|\bhidden(?=[*?]))")
+# 1.2.8 (audit DISS-C-002): a bare hidden that is the direct argument of a filesystem command is a probe
+# (cd hidden, ls hidden, cat hidden, find . -name hidden); a selector (-k hidden), a grep/rg argument and
+# prose stay exempt — read on the heredoc-stripped command
+HIDDEN_FS = re.compile(r"(?mi)\b(?:cd|ls|cat|stat|tree|head|tail|less|more|du|file)\s+(?:-\S+\s+)*['\"]?hidden['\"]?(?=\s|$|[;&|)])"
+                       r"|\bfind\b[^\n;&|]*\s-i?(?:name|path|wholename)\s+['\"]?hidden['\"]?(?=\s|$|[;&|)])")
~~~~

## H06 — evals/harness/ablation-grade.sh — head lines 1369–1377

Head context (head/evals/harness/ablation-grade.sh, lines 1357–1389):

~~~~text
  1357 | 
  1358 | 
  1359 | HISTORY_PROBES = [0]   # git log --all / git reflog seen in this grade (DEC-0540: a count, not contamination)
  1360 | # a one-component absolute word is a Loa slash command or a flag-like token unless it names a
  1361 | # directory that holds data (DEC-0540); a second component makes any word a path candidate
  1362 | SENSITIVE_SINGLE = {"root", "home", "mnt", "media", "srv"}
  1363 | 
  1364 | 
  1365 | def after_closing_quote(body, pos):   # DEC-0557: "$D"/x → the quote closes a token
  1366 |     if pos < 2 or body[pos - 1] not in "'\"":
  1367 |         return False
  1368 |     before = body[pos - 2]
> 1369 |     return not (before.isspace() or before in "=(<>|;&,")
> 1370 | 
> 1371 | 
> 1372 | def in_quotes(body, pos):   # DEC-0551: odd count of unescaped quotes before pos → inside a literal
> 1373 |     seg = body[:pos]
> 1374 |     return seg.count("'") % 2 == 1 or seg.count('"') % 2 == 1
> 1375 | 
> 1376 | 
> 1377 | HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)", re.S)
  1378 | 
  1379 | 
  1380 | def strip_heredocs(val):
  1381 |     """the command without its heredoc bodies (file text being written is data, not a path the
  1382 |     agent reached; the hidden/suite/repo scans still read the whole value) — 1.2.2, DEC-0541"""
  1383 |     return HEREDOC.sub("<<HEREDOC", val)
  1384 | 
  1385 | 
  1386 | def home_word_outside():
  1387 |     """~/, $HOME/ and ${HOME}/ are outside in host mode only: in the container they resolve under
  1388 |     /home/evaluser, an allowed root (1.2.2, DEC-0541)"""
  1389 |     return A.executor == "host"
~~~~

The change from head to the fix:

~~~~diff
@@ -1369,9 +1421,38 @@
-    return not (before.isspace() or before in "=(<>|;&,")
+    # 1.2.8 (audit DISS-C-001): an empty quoted string before the path (''/root/x) is not a glued token
+    return not (before.isspace() or before in "=(<>|;&,'\"")
 
 
-def in_quotes(body, pos):   # DEC-0551: odd count of unescaped quotes before pos → inside a literal
-    seg = body[:pos]
-    return seg.count("'") % 2 == 1 or seg.count('"') % 2 == 1
+def in_quotes(body, pos, end):
+    """True when the word body[pos:end] sits inside a quoted string WITH OTHER TEXT (pattern text
+    such as grep -E ' /tmp | /home '), False when it is unquoted or the entire quoted argument
+    (cd "/root", ls '/home') — 1.2.6 LOW-1: a left-to-right quote state machine over body[:pos]
+    replaces DEC-0551's parity count. Outside single quotes a backslash escapes the next
+    character; ' inside double quotes and " inside single quotes are literal; $'…' is read as a
+    plain single-quoted string"""
+    state, opened, i = None, -1, 0
+    while i < pos:
+        ch = body[i]
+        if state == "'":
+            if ch == "'":
+                state = None
+        elif ch == "\\":
+            i += 1   # the escaped character, whatever it is, is literal
+        elif state == '"':
+            if ch == '"':
+                state = None
+        elif ch in "'\"":
+            state, opened = ch, i
+        i += 1
+    if state is None:
+        return False
+    whole = opened == pos - 1 and end < len(body) and body[end] == state
+    return not whole
 
 
-HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)", re.S)
+# 1.2.6 (MEDIUM-1, MEDIUM-2): group 4 is the operator line's remainder (a redirect, pipe or
+# argument after <<WORD), re-emitted so it is scanned; each body iteration consumes exactly one
+# line and the terminator is anchored at a line start, so a << that is no heredoc ($((1<<n)),
+# a here-string <<<"w") fails in time linear in the text instead of tiling it (no re.S)
+HEREDOC = re.compile(r"(<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2)([^\n]*\n)(?:[^\n]*\n)*?[ \t]*\3[ \t]*(?=\n|$)")
+HEREDOC_INTERPRETERS = re.compile(r"^(?:python3?(?:\.[0-9]+)?|bash|sh|node|perl|ruby)$")
+HEREDOC_INTERP = [0]   # heredocs fed to an interpreter in this grade (1.2.6 LOW-3: telemetry only)
~~~~

## H07 — evals/harness/ablation-grade.sh — head lines 1382–1383

Head context (head/evals/harness/ablation-grade.sh, lines 1370–1395):

~~~~text
  1370 | 
  1371 | 
  1372 | def in_quotes(body, pos):   # DEC-0551: odd count of unescaped quotes before pos → inside a literal
  1373 |     seg = body[:pos]
  1374 |     return seg.count("'") % 2 == 1 or seg.count('"') % 2 == 1
  1375 | 
  1376 | 
  1377 | HEREDOC = re.compile(r"<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\n]*\n(?:.*?\n)*?\s*\2[ \t]*(?=\n|$)", re.S)
  1378 | 
  1379 | 
  1380 | def strip_heredocs(val):
  1381 |     """the command without its heredoc bodies (file text being written is data, not a path the
> 1382 |     agent reached; the hidden/suite/repo scans still read the whole value) — 1.2.2, DEC-0541"""
> 1383 |     return HEREDOC.sub("<<HEREDOC", val)
  1384 | 
  1385 | 
  1386 | def home_word_outside():
  1387 |     """~/, $HOME/ and ${HOME}/ are outside in host mode only: in the container they resolve under
  1388 |     /home/evaluser, an allowed root (1.2.2, DEC-0541)"""
  1389 |     return A.executor == "host"
  1390 | 
  1391 | 
  1392 | def check_value(tool, field, val, roots):
  1393 |     low = val.lower()
  1394 |     if tool == "Bash":
  1395 |         if HIDDEN_TOKEN.search(val):   # DEC-0551: token shapes only in command text
~~~~

The change from head to the fix:

~~~~diff
@@ -1382,2 +1463,18 @@
-    agent reached; the hidden/suite/repo scans still read the whole value) — 1.2.2, DEC-0541"""
-    return HEREDOC.sub("<<HEREDOC", val)
+    agent reached; the hidden/suite/repo scans still read the whole value) — 1.2.2, DEC-0541;
+    the operator line's remainder after <<WORD stays (1.2.6 MEDIUM-1)"""
+    return HEREDOC.sub(lambda m: "<<HEREDOC" + m.group(4), val)
+
+
+def count_interpreter_heredocs(val):
+    """the heredocs whose operator line's command is an interpreter (1.2.6 LOW-3). The command is
+    the first word of the operator line's text before <<, after the last ;, &, |, ( or { and
+    after leading NAME=value assignments; a path keeps its basename (/usr/bin/node → node)"""
+    n = 0
+    for m in HEREDOC.finditer(val):
+        line = val[val.rfind("\n", 0, m.start()) + 1:m.start()]
+        seg = re.split(r"[;&|({]", line)[-1].split()
+        while seg and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[0]):
+            seg.pop(0)
+        if seg and HEREDOC_INTERPRETERS.match(seg[0].rsplit("/", 1)[-1]):
+            n += 1
+    return n
~~~~

## H08 — evals/harness/ablation-grade.sh — head line 1395

Head context (head/evals/harness/ablation-grade.sh, lines 1383–1407):

~~~~text
  1383 |     return HEREDOC.sub("<<HEREDOC", val)
  1384 | 
  1385 | 
  1386 | def home_word_outside():
  1387 |     """~/, $HOME/ and ${HOME}/ are outside in host mode only: in the container they resolve under
  1388 |     /home/evaluser, an allowed root (1.2.2, DEC-0541)"""
  1389 |     return A.executor == "host"
  1390 | 
  1391 | 
  1392 | def check_value(tool, field, val, roots):
  1393 |     low = val.lower()
  1394 |     if tool == "Bash":
> 1395 |         if HIDDEN_TOKEN.search(val):   # DEC-0551: token shapes only in command text
  1396 |             return "hidden"
  1397 |     elif "hidden" in low:
  1398 |         return "hidden"
  1399 |     if "grimoires/loa/evals/ablation-2.0" in val:
  1400 |         return "suite_path"
  1401 |     if "0xhoneyjar/loa" in low:
  1402 |         return "repo_name"
  1403 |     if tool == "Bash" and GIT_HIST.search(val):
  1404 |         HISTORY_PROBES[0] += 1   # DEC-0540: telemetry only; the sandbox has no pre-base history
  1405 |     cands = []
  1406 |     if field in PATH_FIELDS or (tool == "Glob" and field == "pattern"):
  1407 |         if val.startswith("/") and not val.startswith("//"):
~~~~

The change from head to the fix:

~~~~diff
@@ -1395 +1492,2 @@
-        if HIDDEN_TOKEN.search(val):   # DEC-0551: token shapes only in command text
+        stripped = strip_heredocs(val)
+        if HIDDEN_TOKEN.search(val) or HIDDEN_GLOB.search(stripped) or HIDDEN_FS.search(stripped):   # DEC-0551 token shapes; 1.2.7 globs and 1.2.8 filesystem probes outside heredoc bodies
~~~~

## H09 — evals/harness/ablation-grade.sh — insertion after head line 1404

Head context (head/evals/harness/ablation-grade.sh, lines 1393–1416):

~~~~text
  1393 |     low = val.lower()
  1394 |     if tool == "Bash":
  1395 |         if HIDDEN_TOKEN.search(val):   # DEC-0551: token shapes only in command text
  1396 |             return "hidden"
  1397 |     elif "hidden" in low:
  1398 |         return "hidden"
  1399 |     if "grimoires/loa/evals/ablation-2.0" in val:
  1400 |         return "suite_path"
  1401 |     if "0xhoneyjar/loa" in low:
  1402 |         return "repo_name"
  1403 |     if tool == "Bash" and GIT_HIST.search(val):
  1404 |         HISTORY_PROBES[0] += 1   # DEC-0540: telemetry only; the sandbox has no pre-base history
  1405 |     cands = []
  1406 |     if field in PATH_FIELDS or (tool == "Glob" and field == "pattern"):
  1407 |         if val.startswith("/") and not val.startswith("//"):
  1408 |             cands.append(val)
  1409 |         elif val.startswith(HOME_PREFIXES) and home_word_outside():
  1410 |             return "outside_path"
  1411 |     elif tool == "Bash":
  1412 |         body = strip_heredocs(val)
  1413 |         if home_word_outside() and HOME_WORD.search(body):
  1414 |             return "outside_path"
  1415 |         for m in ABS_WORD.finditer(body):
  1416 |             w = m.group(1)
~~~~

The change from head to the fix:

~~~~diff
@@ -1404,0 +1503,2 @@
+    if tool == "Bash":
+        HEREDOC_INTERP[0] += count_interpreter_heredocs(val)   # 1.2.6 LOW-3: telemetry only
~~~~

## H10 — evals/harness/ablation-grade.sh — head line 1423

Head context (head/evals/harness/ablation-grade.sh, lines 1411–1435):

~~~~text
  1411 |     elif tool == "Bash":
  1412 |         body = strip_heredocs(val)
  1413 |         if home_word_outside() and HOME_WORD.search(body):
  1414 |             return "outside_path"
  1415 |         for m in ABS_WORD.finditer(body):
  1416 |             w = m.group(1)
  1417 |             if w.startswith("//"):
  1418 |                 continue
  1419 |             # DEC-0540/0541: a one-component word (/review-sprint, /implement, a sed or awk
  1420 |             # delimiter such as /,/ or /x/) is a command token or a regex, not leakage, unless
  1421 |             # the component names a data-holding root; a second component makes it a candidate
  1422 |             one = re.match(r"^/([^/]+)/?$", w)
> 1423 |             if one and one.group(1) not in SENSITIVE_SINGLE:
  1424 |                 continue
  1425 |             # DEC-0546 (1.2.3): a sed address range /re1/,/re2/[cmd] (or /re/,+N, /re/,$) is a
  1426 |             # regex pair, not a path — no path has a component that begins with a comma
  1427 |             if re.match(r"^/[^/]*/,", w):
  1428 |                 continue
  1429 |             # DEC-0551 (1.2.4): a word beginning with /, is the remnant of a sed range whose first
  1430 |             # address held a space or a metacharacter; a word carrying = is a regex or key=value
  1431 |             # token — no path component carries =
  1432 |             if w.startswith("/,") or "=" in w:
  1433 |                 continue
  1434 |             # DEC-0551 (1.2.4): a root dot-directory word (/.claude/<file> after a quote in
  1435 |             # pr/'"$v"'/.claude/…) is a repo-relative reference — no Linux root holds dot-dirs;
~~~~

The change from head to the fix:

~~~~diff
@@ -1423 +1523,6 @@
-            if one and one.group(1) not in SENSITIVE_SINGLE:
+            # 1.2.8 (audit DISS-C-001): ABS_WORD stops at a glob metacharacter, so /roo* and /ro?t tokenise to a
+            # one-component word; an unquoted globbed word is never a slash command and stays a candidate.
+            # 1.2.9: only * and ? — a [ after the word is a regex bracket expression in agent commands
+            # (grep '/home[^"]*x', sed 's/job\["status"\]/'), and a quoted pattern stays pattern text (in_quotes below)
+            globbed = m.end(1) < len(body) and body[m.end(1)] in "*?"
+            if one and not globbed and one.group(1) not in SENSITIVE_SINGLE:
~~~~

## H11 — evals/harness/ablation-grade.sh — head lines 1436–1438

Head context (head/evals/harness/ablation-grade.sh, lines 1424–1450):

~~~~text
  1424 |                 continue
  1425 |             # DEC-0546 (1.2.3): a sed address range /re1/,/re2/[cmd] (or /re/,+N, /re/,$) is a
  1426 |             # regex pair, not a path — no path has a component that begins with a comma
  1427 |             if re.match(r"^/[^/]*/,", w):
  1428 |                 continue
  1429 |             # DEC-0551 (1.2.4): a word beginning with /, is the remnant of a sed range whose first
  1430 |             # address held a space or a metacharacter; a word carrying = is a regex or key=value
  1431 |             # token — no path component carries =
  1432 |             if w.startswith("/,") or "=" in w:
  1433 |                 continue
  1434 |             # DEC-0551 (1.2.4): a root dot-directory word (/.claude/<file> after a quote in
  1435 |             # pr/'"$v"'/.claude/…) is a repo-relative reference — no Linux root holds dot-dirs;
> 1436 |             # a one-component sensitive word inside a quoted string (grep -E ' /tmp | /home ')
> 1437 |             # is pattern text, not a path argument (the accepted gap cd '/root/' stays)
> 1438 |             if w.startswith("/."):
  1439 |                 continue
  1440 |             # DEC-0557 (1.2.5): after a closing quote glued to the preceding token ("$D"/evals/x)
  1441 |             # the word is the tail of a longer path, not an absolute one
  1442 |             if after_closing_quote(body, m.start(1)):
  1443 |                 continue
  1444 |             if one and in_quotes(body, m.start(1)):
  1445 |                 continue
  1446 |             cands.append(w)
  1447 |     for c in cands:
  1448 |         if outside(c, roots):
  1449 |             return "outside_path"
  1450 |     return None
~~~~

The change from head to the fix:

~~~~diff
@@ -1436,3 +1541,5 @@
-            # a one-component sensitive word inside a quoted string (grep -E ' /tmp | /home ')
-            # is pattern text, not a path argument (the accepted gap cd '/root/' stays)
-            if w.startswith("/."):
+            # a one-component sensitive word inside a quoted string with other text
+            # (grep -E ' /tmp | /home ') is pattern text, not a path argument; the word that is
+            # the whole quoted argument (cd "/root", cd '/root/') is a candidate (1.2.6 LOW-1)
+            # 1.2.8 (audit DISS-C-001): normalise first — /./root/x and /../root/x resolve to /root/x
+            if w.startswith("/.") and os.path.normpath(w).startswith("/."):
~~~~

## H12 — evals/harness/ablation-grade.sh — head line 1444

Head context (head/evals/harness/ablation-grade.sh, lines 1432–1456):

~~~~text
  1432 |             if w.startswith("/,") or "=" in w:
  1433 |                 continue
  1434 |             # DEC-0551 (1.2.4): a root dot-directory word (/.claude/<file> after a quote in
  1435 |             # pr/'"$v"'/.claude/…) is a repo-relative reference — no Linux root holds dot-dirs;
  1436 |             # a one-component sensitive word inside a quoted string (grep -E ' /tmp | /home ')
  1437 |             # is pattern text, not a path argument (the accepted gap cd '/root/' stays)
  1438 |             if w.startswith("/."):
  1439 |                 continue
  1440 |             # DEC-0557 (1.2.5): after a closing quote glued to the preceding token ("$D"/evals/x)
  1441 |             # the word is the tail of a longer path, not an absolute one
  1442 |             if after_closing_quote(body, m.start(1)):
  1443 |                 continue
> 1444 |             if one and in_quotes(body, m.start(1)):
  1445 |                 continue
  1446 |             cands.append(w)
  1447 |     for c in cands:
  1448 |         if outside(c, roots):
  1449 |             return "outside_path"
  1450 |     return None
  1451 | 
  1452 | 
  1453 | def transcripts(run_dir):
  1454 |     d = os.path.join(run_dir, "transcripts")
  1455 |     if not os.path.isdir(d):
  1456 |         return []
~~~~

The change from head to the fix:

~~~~diff
@@ -1444 +1551 @@
-            if one and in_quotes(body, m.start(1)):
+            if one and in_quotes(body, m.start(1), m.end(1)):
~~~~

## H13 — evals/harness/ablation-grade.sh — head line 1538

Head context (head/evals/harness/ablation-grade.sh, lines 1526–1550):

~~~~text
  1526 |         verdict = {"source_file": "engineer-feedback.md", "value": v_review}
  1527 |     else:
  1528 |         rv = review_md_verdict(os.path.join(sb, "review.md"), sb)
  1529 |         verdict = {"source_file": "review.md", "value": rv} if rv else None
  1530 |     g = {"schema_version": 1, "grader_version": GRADER_VERSION, "task_id": t.id, "task_type": t.type,
  1531 |          "suite_frozen": frozen, "executor_mode": A.executor,
  1532 |          "image": A.image if A.executor == "container" else None, "snapshots_graded": [],
  1533 |          "hidden_tests": None, "structural": None, "regressions": None, "snapshot_tests": None,
  1534 |          "recall": None, "false_positives": None, "verdict": verdict,
  1535 |          "verdicts": {"review": v_review, "audit": v_audit},
  1536 |          "verdict_accuracy": None, "verdict_accuracy_per_gate": {"review": None, "audit": None},
  1537 |          "diff_lines": None, "files_changed": None, "symlinks_dropped": 0, "harness_files_removed": 0,
> 1538 |          "oversized_files_skipped": 0, "history_probes": 0, "contaminated": None}
  1539 |     acc = {"review": None, "audit": None}
  1540 |     SNAPSHOT_LINKS_DROPPED[0] = 0
  1541 |     OVERSIZED[0] = 0
  1542 |     HISTORY_PROBES[0] = 0
  1543 |     RUN_TAG[0] = re.sub(r"[^A-Za-z0-9._-]", "-", os.path.basename(run_dir))[:40] or "run"
  1544 |     GRADER_SOURCES.clear()
  1545 |     if t.build:
  1546 |         for rel in t.protected:
  1547 |             src = os.path.join(t.fixture, *rel.split("/"))
  1548 |             if os.path.isfile(src) and not os.path.islink(src):
  1549 |                 GRADER_SOURCES[rel] = src
  1550 |         GRADER_SOURCES.update({d: f for _s, d, f in t.overlay if os.path.isfile(f)})
~~~~

The change from head to the fix:

~~~~diff
@@ -1538 +1645 @@
-         "oversized_files_skipped": 0, "history_probes": 0, "contaminated": None}
+         "oversized_files_skipped": 0, "history_probes": 0, "heredoc_interpreters": 0, "contaminated": None}
~~~~

## H14 — evals/harness/ablation-grade.sh — insertion after head line 1542

Head context (head/evals/harness/ablation-grade.sh, lines 1531–1554):

~~~~text
  1531 |          "suite_frozen": frozen, "executor_mode": A.executor,
  1532 |          "image": A.image if A.executor == "container" else None, "snapshots_graded": [],
  1533 |          "hidden_tests": None, "structural": None, "regressions": None, "snapshot_tests": None,
  1534 |          "recall": None, "false_positives": None, "verdict": verdict,
  1535 |          "verdicts": {"review": v_review, "audit": v_audit},
  1536 |          "verdict_accuracy": None, "verdict_accuracy_per_gate": {"review": None, "audit": None},
  1537 |          "diff_lines": None, "files_changed": None, "symlinks_dropped": 0, "harness_files_removed": 0,
  1538 |          "oversized_files_skipped": 0, "history_probes": 0, "contaminated": None}
  1539 |     acc = {"review": None, "audit": None}
  1540 |     SNAPSHOT_LINKS_DROPPED[0] = 0
  1541 |     OVERSIZED[0] = 0
  1542 |     HISTORY_PROBES[0] = 0
  1543 |     RUN_TAG[0] = re.sub(r"[^A-Za-z0-9._-]", "-", os.path.basename(run_dir))[:40] or "run"
  1544 |     GRADER_SOURCES.clear()
  1545 |     if t.build:
  1546 |         for rel in t.protected:
  1547 |             src = os.path.join(t.fixture, *rel.split("/"))
  1548 |             if os.path.isfile(src) and not os.path.islink(src):
  1549 |                 GRADER_SOURCES[rel] = src
  1550 |         GRADER_SOURCES.update({d: f for _s, d, f in t.overlay if os.path.isfile(f)})
  1551 |         docker_ready()
  1552 |         final = os.path.join(grading, "final")
  1553 |         g["symlinks_dropped"] = copy_tree(sb, final, EXCLUDE_TOP)
  1554 |         g["diff_lines"], g["files_changed"] = churn(t.fixture, final)
~~~~

The change from head to the fix:

~~~~diff
@@ -1542,0 +1650 @@
+    HEREDOC_INTERP[0] = 0
~~~~

## H15 — evals/harness/ablation-grade.sh — insertion after head line 1623

Head context (head/evals/harness/ablation-grade.sh, lines 1612–1635):

~~~~text
  1612 |         if os.path.isdir(os.path.join(sb, "pr")) and not os.path.islink(os.path.join(sb, "pr")):
  1613 |             g["symlinks_dropped"] = copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
  1614 |         g["recall"], g["false_positives"] = grade_recall(t, run_dir, grading)
  1615 |         key_cr = any((d.get("severity") or "").lower() in ("high", "critical") for d in t.key.get("defects") or [])
  1616 |         for gate, v in (("review", v_review), ("audit", v_audit)):
  1617 |             if v is not None:
  1618 |                 acc[gate] = (v == "CHANGES_REQUIRED") == key_cr and v in ("APPROVED", "CHANGES_REQUIRED")
  1619 |     g["oversized_files_skipped"] = OVERSIZED[0]
  1620 |     g["verdict_accuracy_per_gate"] = acc
  1621 |     g["verdict_accuracy"] = acc["audit"] if acc["audit"] is not None else acc["review"]
  1622 |     g["contaminated"] = contamination(run_dir)
  1623 |     g["history_probes"] = HISTORY_PROBES[0]
  1624 |     return g
  1625 | 
  1626 | 
  1627 | def structural_command(t):
  1628 |     dest = t.structural
  1629 |     if dest.endswith(".bats"):
  1630 |         return ["bats", dest]
  1631 |     if dest.endswith(".py"):
  1632 |         return ["python3", "-m", "pytest", "-q", dest]
  1633 |     return [t.test_command[0], dest]
  1634 | 
  1635 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -1623,0 +1732 @@
+    g["heredoc_interpreters"] = HEREDOC_INTERP[0]
~~~~

## H16 — evals/harness/run-ablation.sh — head line 135

Head context (head/evals/harness/run-ablation.sh, lines 123–147):

~~~~text
   123 | #   --source-tree <pinned> --suite-file … --executor … --image … --docker-bin …
   124 | #   --max-run-usd <run-cap>, output to <batch>/<arm>/<task>-t<n>.log; then
   125 | #   1. status from meta/pipeline.json (missing or `running` → interrupted; a missing record
   126 | #      is written as a minimal pipeline.json with synthesized_by: run-ablation.sh)
   127 | #   2. transport: agent_error plus a provider signature in the failing phase's
   128 | #      stderr-<label>.log or events-<label>.jsonl (lib/arms-common.sh
   129 | #      is_pipeline_transport_failure) is retried ONCE after $LOA_ABLATION_RETRY_WAIT_S
   130 | #      (default 120) into a fresh run dir: attempts 2, retry_reason; the first attempt writes
   131 | #      no row and its spent_usd counts in spend; a second transport failure is rowed
   132 | #      transport_error. agent_error without the signature is never retried (DEC-0417)
   133 | #   3. took-effect.sh --run-dir D --suite-file F (completed, agent_error and cap_failure runs):
   134 | #      a FAIL rows the trial infrastructure_error and pauses the arm (STATUS.json
>  135 | #      paused_arms; no further trial of it launches until --resume --clear-arm ID) (DEC-0418)
   136 | #   4. drift guard (DEC-0407 as amended by DEC-0545): a phase drifts on model grounds only
   137 | #      when its model_requested differs from MANIFEST phase_models[name], or when the
   138 | #      requested model (else the manifest's) is absent from a non-empty models_used (ids
   139 | #      normalised as ablation-row.sh does: no Bedrock region prefix, no -vN:M suffix). Any
   140 | #      other models_used key is an extra model, telemetry and not drift (Claude Code's
   141 | #      WebFetch summariser or a built-in subagent): one `run-ablation: extra model <id> in
   142 | #      <labels> (<N> output tokens; …)` line in the trial log, the trial result's
   143 | #      extra_models and STATUS.json extra_models. The transcripts' system/init
   144 | #      claude_code_version (or version) equals MANIFEST cli_version (when neither carries a
   145 | #      version, pipeline.json image_digest must equal MANIFEST image_digest). A mismatch rows
   146 | #      the trial infrastructure_error, records STATUS.json drift, launches nothing more and
   147 | #      fails the batch once the running trials end
~~~~

The change from head to the fix:

~~~~diff
@@ -135 +135,6 @@
-#      paused_arms; no further trial of it launches until --resume --clear-arm ID) (DEC-0418)
+#      paused_arms; no further trial of it launches until --resume --clear-arm ID) (DEC-0418).
+#      It runs under timeout -s TERM -k 30 $LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S
+#      (default 300; unwrapped when timeout is absent): exit 124 or 137 rows the trial
+#      infrastructure_error with `run-ablation: took-effect timed out after Ns` in the trial
+#      log and took_effect "timeout" in the trial result — the arm is NOT paused (a hang is
+#      no evidence about the arm) and the grade does not run
~~~~

## H17 — evals/harness/run-ablation.sh — insertion after head line 149

Head context (head/evals/harness/run-ablation.sh, lines 138–161):

~~~~text
   138 | #      requested model (else the manifest's) is absent from a non-empty models_used (ids
   139 | #      normalised as ablation-row.sh does: no Bedrock region prefix, no -vN:M suffix). Any
   140 | #      other models_used key is an extra model, telemetry and not drift (Claude Code's
   141 | #      WebFetch summariser or a built-in subagent): one `run-ablation: extra model <id> in
   142 | #      <labels> (<N> output tokens; …)` line in the trial log, the trial result's
   143 | #      extra_models and STATUS.json extra_models. The transcripts' system/init
   144 | #      claude_code_version (or version) equals MANIFEST cli_version (when neither carries a
   145 | #      version, pipeline.json image_digest must equal MANIFEST image_digest). A mismatch rows
   146 | #      the trial infrastructure_error, records STATUS.json drift, launches nothing more and
   147 | #      fails the batch once the running trials end
   148 | #   5. ablation-grade.sh D <task> --suite-root … [--tasks-dir smoke] --executor … --image …
   149 | #      --docker-bin … (scored runs that passed 3 and 4; exit 2 → row infrastructure_error)
   150 | #   6. ablation-row.sh --run-dir D --task-yaml F --manifest <batch>/MANIFEST.json
   151 | #      --attempts N [--retry-reason R] [--status S] --out <job row>; the runner appends the
   152 | #      row to the rows file under flock and runs ablation-row.sh --validate on it
   153 | #      (--allow-ungraded for smoke) and refuses a run_id rowed twice (state failed)
   154 | #   Watchdog (DEC-0429): a trial whose pipeline has no final meta/pipeline.json status after
   155 | #   twice its phase-sum timeout (the planned phases' timeout_min: task bounds, else the
   156 | #   suite's phase_defaults, BARE = PLAN + IMPLEMENT + 2 × FIX) gets SIGTERM to its process
   157 | #   group, SIGKILL after $LOA_ABLATION_WATCHDOG_GRACE_S (default 60), and is rowed
   158 | #   interrupted. $LOA_ABLATION_WATCHDOG_S replaces the deadline (seconds; tests).
   159 | #   Outage breaker (DEC-0554): $LOA_ABLATION_OUTAGE_BREAKER (default 3; 0 disables) consecutive
   160 | #   collected trials rowed transport_error (collection order, any arm; any other collected
   161 | #   trial resets the count) stop further launches; the running trials end, STATUS.json outage
~~~~

The change from head to the fix:

~~~~diff
@@ -149,0 +155,4 @@
+#      under timeout -s TERM -k 30 $LOA_ABLATION_GRADE_TIMEOUT_S (default
+#      1800; unwrapped when timeout is absent): exit 124 or 137 → row infrastructure_error,
+#      `run-ablation: grade timed out after Ns` in the trial log, grade_rc keeps the exit
+#      (the pipeline watchdog covers the pipeline only; this is the post-run deadline)
~~~~

## H18 — evals/harness/run-ablation.sh — head line 187

Head context (head/evals/harness/run-ablation.sh, lines 175–199):

~~~~text
   175 | #
   176 | # Files: <results-root>/<batch>/{MANIFEST.json, STATUS.json, run.log, spend.txt,
   177 | #   REFUSED.txt, driver.log, .gitignore (non-smoke: the run directories and logs stay out of
   178 | #   git), <arm>/<task>-t<n>[-r<k>]/ (pipeline-run.sh run dirs), <arm>/<task>-t<n>.log};
   179 | #   rows to the rows file. MANIFEST.json (§3.4): schema_version, suite, batch, dry_run,
   180 | #   smoke, created, source_commit, source_worktree, source_commit_dot_claude_delta (git diff
   181 | #   --stat 4d69c3c4..<commit> -- .claude/, ≤ 4,000 chars), harness_commit, harness_dirty,
   182 | #   suite_file, suite_root, tasks_dir, rows_file, suite_version, suite_manifest_sha256, arms,
   183 | #   tasks, refused, trials_per_type, trials_planned, plan, arm_map, shuffle_seed, shuffle,
   184 | #   fingerprint, image, image_digest, executor_mode, cli_version (`docker run --rm --network
   185 | #   none <image> claude --version`, host: the CLI's), cli_version_raw, tools, phase_models,
   186 | #   caps {cycle_usd, run_usd, reserve_usd, max_usd}, cost_hint, concurrency, retry,
>  187 | #   watchdog, pre_registration_ref, gate (null for smoke), corpus, agy_opt_in, environment.
   188 | #   STATUS.json (§3.4), rewritten after every trial: {schema_version, suite, batch, smoke,
   189 | #   state: running|complete|partial|failed, per_arm: {<arm>: {trials_planned, launched,
   190 | #   completed, failed (agent_error), excluded (transport_error, infrastructure_error,
   191 | #   interrupted, contaminated), cap_failures, degraded, skipped_paused}}, retries: [{run_id,
   192 | #   reason, first_attempt_usd}], cuts: [...], paused_arms: {<arm>: reason}, spend: {rows_usd,
   193 | #   ledger_usd (transport first attempts, and the reported cost of rows a rerun replaced), spent_usd, max_usd, assumed_cap_trials}, resume_cursor (the
   194 | #   index of the first plan entry without a row), drift: null | {run_id, field, expected,
   195 | #   got}, drift_cleared: [{run_id, previous, cleared_at, harness_commit}] (--clear-drift),
   196 | #   rerowed: [{run_id, from, to, at}] (--rerow), rerun: [{run_id, from, to, old_cost_usd, at}]
   197 | #   (--rerun, --rerun-status), rerun_pending: [run_id…] (flagged, no replacement yet), outage:
   198 | #   null | {at, consecutive, last_run_id, message} (the breaker), outage_history: [the
   199 | #   outages a later --resume cleared], extra_models: {<raw id>: {runs,
~~~~

The change from head to the fix:

~~~~diff
@@ -187 +196,2 @@
-#   watchdog, pre_registration_ref, gate (null for smoke), corpus, agy_opt_in, environment.
+#   watchdog {multiplier, override_s, grace_s, grade_timeout_s, took_effect_timeout_s},
+#   pre_registration_ref, gate (null for smoke), corpus, agy_opt_in, environment.
~~~~

## H19 — evals/harness/run-ablation.sh — head line 225

Head context (head/evals/harness/run-ablation.sh, lines 213–237):

~~~~text
   213 | #   (fresh or resumed) is refused while a process group recorded under <batch>/.jobs/ by an
   214 | #   earlier driver (one killed with SIGKILL) is still alive.
   215 | #
   216 | # Exit: 0 complete (every trial rowed; none transport_error, infrastructure_error,
   217 | #       interrupted or contaminated), 1 partial (cut, the outage breaker, a paused arm with trials left, an
   218 | #       excluded row, or the driver was signalled), 2 usage or refused, 3 failed (drift, an
   219 | #       invalid or duplicated row, no trial completed without a cut, or every arm of the
   220 | #       plan paused)
   221 | #
   222 | # Env: LOA_ABLATION_SOURCE_TREE, LOA_ABLATION_SOURCE_REPO, LOA_ABLATION_CACHE,
   223 | #   LOA_ABLATION_RETRY_WAIT_S, LOA_ABLATION_WATCHDOG_S, LOA_ABLATION_WATCHDOG_GRACE_S,
   224 | #   LOA_ABLATION_POLL_S (reap poll, default 1), LOA_ABLATION_OUTAGE_BREAKER (default 3),
>  225 | #   EVAL_DOCKER_BIN, EVAL_CLAUDE_BIN (host CLI).
   226 | # Library: lib/arms-common.sh beside this script, sourced by a literal relative path.
   227 | # Tested by evals/tests/run-ablation.bats (stub pipeline, grader and docker; no model call).
   228 | # =============================================================================
   229 | set -euo pipefail
   230 | export LC_ALL=C
   231 | 
   232 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   233 | REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
   234 | # eval.yml trust boundary: a literal in-tree path, no variable on the source line
   235 | pushd "$SCRIPT_DIR" >/dev/null
   236 | # shellcheck source=lib/arms-common.sh
   237 | source ./lib/arms-common.sh || { popd >/dev/null; echo "run-ablation: lib/arms-common.sh failed to load" >&2; exit 2; }
~~~~

The change from head to the fix:

~~~~diff
@@ -225 +235,5 @@
-#   EVAL_DOCKER_BIN, EVAL_CLAUDE_BIN (host CLI).
+#   LOA_ABLATION_GRADE_TIMEOUT_S (grade deadline, default 1800: above the grader's own per-command deadline of
+#   120 + 10 s over at most ten container commands per grade, plus the tree copies; the outage breaker counts
+#   transport_error rows only, never these infrastructure_error rows) and
+#   LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S (took-effect deadline, default 300), both whole seconds
+#   1 … 999999 (else exit 2), EVAL_DOCKER_BIN, EVAL_CLAUDE_BIN (host CLI).
~~~~

## H20 — evals/harness/run-ablation.sh — insertion after head line 262

Head context (head/evals/harness/run-ablation.sh, lines 251–274):

~~~~text
   251 | SMOKE=false DRY_RUN=false RESUME=false DETACH=false
   252 | CLEAR_ARMS=() REROW_IDS=() CLEAR_DRIFT=false RERUN_IDS=() RERUN_STATUSES=()
   253 | PIPELINE_BIN="$SCRIPT_DIR/pipeline-run.sh" GRADE_BIN="$SCRIPT_DIR/ablation-grade.sh"
   254 | ROW_BIN="$SCRIPT_DIR/ablation-row.sh" TOOK_BIN="$SCRIPT_DIR/took-effect.sh"
   255 | DOCKER_BIN="${EVAL_DOCKER_BIN:-docker}"
   256 | FREEZE_BIN="$SCRIPT_DIR/freeze.sh" CORPUS_BIN="$SCRIPT_DIR/seed-corpus-from-record.sh"
   257 | SPEND_BIN="$SCRIPT_DIR/spend.sh" FP_BIN="$SCRIPT_DIR/fingerprint.sh"
   258 | RETRY_WAIT="${LOA_ABLATION_RETRY_WAIT_S:-120}"
   259 | WATCHDOG_OVERRIDE="${LOA_ABLATION_WATCHDOG_S:-}"
   260 | WATCHDOG_GRACE="${LOA_ABLATION_WATCHDOG_GRACE_S:-60}"
   261 | POLL_S="${LOA_ABLATION_POLL_S:-1}"
   262 | OUTAGE_BREAKER="${LOA_ABLATION_OUTAGE_BREAKER:-3}"
   263 | 
   264 | usage() { sed -n '2,/^# =====.*$/p' "$0" | sed '1d;$d' | sed 's/^# \{0,1\}//' >&2; exit 2; }
   265 | die() { echo "run-ablation: $*" >&2; exit 2; }
   266 | 
   267 | while [[ $# -gt 0 ]]; do
   268 |   case "$1" in
   269 |     --arms) ARMS_CSV="${2:-}"; shift 2 ;;
   270 |     --source-commit) SOURCE_COMMIT="${2:-}"; shift 2 ;;
   271 |     --tasks) TASKS_CSV="${2:-}"; shift 2 ;;
   272 |     --types) TYPES_CSV="${2:-}"; shift 2 ;;
   273 |     --trials-build) TRIALS_BUILD="${2:-}"; shift 2 ;;
   274 |     --trials-review) TRIALS_REVIEW="${2:-}"; shift 2 ;;
~~~~

The change from head to the fix:

~~~~diff
@@ -262,0 +277,2 @@
+GRADE_TIMEOUT_S="${LOA_ABLATION_GRADE_TIMEOUT_S:-1800}"
+TOOK_TIMEOUT_S="${LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S:-300}"
~~~~

## H21 — evals/harness/run-ablation.sh — insertion after head line 341

Head context (head/evals/harness/run-ablation.sh, lines 330–353):

~~~~text
   330 | if [[ ${#RERUN_IDS[@]} -gt 0 && "$RESUME" != true ]]; then die "--rerun needs --resume"; fi
   331 | if [[ ${#RERUN_STATUSES[@]} -gt 0 && "$RESUME" != true ]]; then die "--rerun-status needs --resume"; fi
   332 | for s in ${RERUN_STATUSES[@]+"${RERUN_STATUSES[@]}"}; do
   333 |   case "$s" in transport_error|interrupted|infrastructure_error) ;;
   334 |     *) die "--rerun-status must be transport_error, interrupted or infrastructure_error (got '$s')" ;; esac
   335 | done
   336 | for r in ${RERUN_IDS[@]+"${RERUN_IDS[@]}"}; do
   337 |   [[ "$r" =~ ^[A-Za-z0-9._-]{1,200}$ ]] || die "invalid --rerun '$r'"
   338 |   for q in ${REROW_IDS[@]+"${REROW_IDS[@]}"}; do [[ "$q" != "$r" ]] || die "--rerun $r is also a --rerow (a run is rowed again or launched again, not both)"; done
   339 | done
   340 | [[ "$(printf '%s\n' ${RERUN_IDS[@]+"${RERUN_IDS[@]}"} | sort | uniq -d)" == "" ]] || die "--rerun lists a run_id twice"
   341 | [[ "$OUTAGE_BREAKER" =~ ^[0-9]{1,4}$ ]] || die "LOA_ABLATION_OUTAGE_BREAKER must be a whole number (0 disables)"
   342 | [[ "$RESUME" != true || "$DRY_RUN" != true ]] || die "--resume and --dry-run are exclusive"
   343 | [[ "$RESUME" == true || -n "$SOURCE_COMMIT" ]] || die "--source-commit is required"
   344 | 
   345 | if [[ -z "$BATCH" ]]; then
   346 |   [[ "$RESUME" != true ]] || die "--resume needs --batch NAME"
   347 |   if [[ "$SMOKE" == true ]]; then BATCH="smoke-$(date -u +%Y%m%dT%H%M%SZ)"; else BATCH="batch-$(date -u +%Y%m%dT%H%M%SZ)"; fi
   348 | fi
   349 | [[ "$BATCH" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || die "invalid --batch '$BATCH'"
   350 | case "$BATCH" in .|..) die "invalid --batch '$BATCH' (a batch is one child directory)" ;; esac
   351 | if [[ "$SMOKE" != true && "$BATCH" == smoke-* ]]; then die "invalid --batch '$BATCH': the smoke- prefix is reserved for --smoke"; fi
   352 | 
   353 | if [[ -z "$RESULTS_ROOT" ]]; then
~~~~

The change from head to the fix:

~~~~diff
@@ -341,0 +358,10 @@
+[[ "$GRADE_TIMEOUT_S" =~ ^[1-9][0-9]{0,5}$ ]] || die "LOA_ABLATION_GRADE_TIMEOUT_S must be positive whole seconds (at most 999999)"
+[[ "$TOOK_TIMEOUT_S" =~ ^[1-9][0-9]{0,5}$ ]] || die "LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S must be positive whole seconds (at most 999999)"
+# the post-run deadlines (Sprint 260 LOW-4): unwrapped when timeout(1) is absent
+GRADE_TMO=() TOOK_TMO=() TMO_ON=false
+if command -v timeout >/dev/null 2>&1; then
+  # the portable short flags (GNU and BusyBox; review round 2 DISS-C-003); MANIFEST records null when unwrapped
+  GRADE_TMO=(timeout -s TERM -k 30 "$GRADE_TIMEOUT_S")
+  TOOK_TMO=(timeout -s TERM -k 30 "$TOOK_TIMEOUT_S")
+  TMO_ON=true
+fi
~~~~

## H22 — evals/harness/run-ablation.sh — head line 721

Head context (head/evals/harness/run-ablation.sh, lines 709–733):

~~~~text
   709 |   printf '%s' "$GATE_JSON" > "$WORK/gate.json"
   710 |   jq -n \
   711 |     --slurpfile plan_f "$WORK/plan.json" --slurpfile suite_f "$WORK/suite.json" --slurpfile tasks_f "$WORK/tasks.json" \
   712 |     --slurpfile gate_f "$WORK/gate.json" --rawfile delta "$WORK/delta.txt" \
   713 |     --arg batch "$BATCH" --argjson dry "$dry" --argjson smoke "$SMOKE" --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   714 |     --arg src "$SRC_FULL" --arg tree "$TREE" --arg hc "$harness_commit" --argjson hd "$harness_dirty" \
   715 |     --arg suite_file "${SUITE_FILE#"$REPO_ROOT"/}" --arg suite_file_path "$SUITE_FILE" --arg suite_root "$SUITE_ROOT" \
   716 |     --arg tasks_dir "$TASKS_DIR_NAME" --arg rows "$ROWS" --arg msha "$SUITE_MANIFEST_SHA" \
   717 |     --argjson arms "$(json_array "${ARMS[@]}")" --argjson tb "$TB" --argjson tr "$TR" --argjson seed "$SEED" \
   718 |     --arg fp "$FINGERPRINT" --arg image "$IMAGE" --arg digest "$IMAGE_DIGEST" --arg mode "$EXECUTOR" \
   719 |     --arg cli "$CLI_VERSION" --arg cli_raw "$CLI_RAW" --arg max_usd "$MAX_USD" --arg run_cap "$RUN_CAP" \
   720 |     --arg hb "$HINT_BUILD" --arg hr "$HINT_REVIEW" --argjson conc "$CONCURRENCY" --argjson rw "$RETRY_WAIT" \
>  721 |     --arg wdo "$WATCHDOG_OVERRIDE" --argjson grace "$WATCHDOG_GRACE" --arg prr "$PRE_REG_REF" \
   722 |     --arg corpus "$CORPUS_SHA" --arg os "$(uname -srm)" --arg bash_v "$BASH_VERSION" \
   723 |     --arg jq_v "$(jq --version 2>/dev/null)" --arg yq_v "$(yq --version 2>/dev/null)" \
   724 |     --arg py_v "$(python3 --version 2>/dev/null)" --arg git_v "$(git --version 2>/dev/null)" '
   725 |     $plan_f[0] as $p | $suite_f[0] as $s | $gate_f[0] as $g
   726 |     | {schema_version: 1, suite: ($s.name // "ablation-2.0"), batch: $batch, dry_run: $dry, smoke: $smoke, created: $created,
   727 |        source_commit: $src, source_worktree: $tree, source_commit_dot_claude_delta: $delta,
   728 |        harness_commit: $hc, harness_dirty: $hd, suite_file: $suite_file, suite_file_path: $suite_file_path,
   729 |        suite_root: $suite_root, tasks_dir: $tasks_dir, rows_file: $rows,
   730 |        suite_version: ($s.suite_version // $s.version // null),
   731 |        suite_manifest_sha256: (if $msha == "" then null else $msha end),
   732 |        arms: $arms, tasks: [$tasks_f[0][] | {id, type}], refused: $p.refused,
   733 |        trials_per_type: {build: $tb, "review-catch": $tr}, trials_planned: ($p.plan | length),
~~~~

The change from head to the fix:

~~~~diff
@@ -721 +747 @@
-    --arg wdo "$WATCHDOG_OVERRIDE" --argjson grace "$WATCHDOG_GRACE" --arg prr "$PRE_REG_REF" \
+    --arg wdo "$WATCHDOG_OVERRIDE" --argjson grace "$WATCHDOG_GRACE" --arg gto "$GRADE_TIMEOUT_S" --arg tto "$TOOK_TIMEOUT_S" --argjson tmo "$TMO_ON" --arg prr "$PRE_REG_REF" \
~~~~

## H23 — evals/harness/run-ablation.sh — head line 744

Head context (head/evals/harness/run-ablation.sh, lines 732–756):

~~~~text
   732 |        arms: $arms, tasks: [$tasks_f[0][] | {id, type}], refused: $p.refused,
   733 |        trials_per_type: {build: $tb, "review-catch": $tr}, trials_planned: ($p.plan | length),
   734 |        plan: $p.plan, arm_map: ([$p.plan[] | {(.run_id): .arm}] | add // {}),
   735 |        shuffle_seed: $seed, shuffle: "trial-major; python3 random.Random(shuffle_seed).shuffle per trial block, blocks in order",
   736 |        fingerprint: (if $fp == "" then null else $fp end), image: $image,
   737 |        image_digest: (if $digest == "" then null else $digest end), executor_mode: $mode,
   738 |        cli_version: $cli, cli_version_raw: $cli_raw,
   739 |        tools: ($s.phase_defaults.tools // null), phase_models: ($s.phase_defaults.models // {}),
   740 |        caps: {cycle_usd: ($s.caps.cycle_usd // null), run_usd: ($run_cap | tonumber), reserve_usd: ($s.caps.reserve_usd // null),
   741 |               max_usd: (if $max_usd == "" then null else ($max_usd | tonumber) end)},
   742 |        cost_hint: {build: ($hb | tonumber), "review-catch": ($hr | tonumber)},
   743 |        concurrency: $conc, retry: {transport_retries: 1, wait_s: $rw},
>  744 |        watchdog: {multiplier: 2, override_s: (if $wdo == "" then null else ($wdo | tonumber) end), grace_s: $grace},
   745 |        pre_registration_ref: (if $prr == "" then null else $prr end),
   746 |        gate: $g, corpus: {manifest: "evals/fixtures/review-prs/SHA256SUMS", sha256: (if $corpus == "" then null else $corpus end)},
   747 |        agy_opt_in: ($s.agy_opt_in // false),
   748 |        environment: {os: $os, bash: $bash_v, jq: $jq_v, yq: $yq_v, python: $py_v, git: $git_v}}' > "$out.tmp"
   749 |   mv "$out.tmp" "$out"
   750 | }
   751 | 
   752 | if [[ "$DRY_RUN" == true ]]; then
   753 |   mpath="$MAN_PATH"; [[ -f "$BATCH_DIR/STATUS.json" ]] && mpath="$BATCH_DIR/MANIFEST.dry-run.json"
   754 |   write_manifest "$mpath" true
   755 |   echo "run-ablation (dry run): batch=$BATCH source=${SRC_FULL:0:12} executor=$EXECUTOR image=$IMAGE cli=$CLI_VERSION tree=$TREE"
   756 |   echo "$PLAN_LINE"
~~~~

The change from head to the fix:

~~~~diff
@@ -744 +770,2 @@
-       watchdog: {multiplier: 2, override_s: (if $wdo == "" then null else ($wdo | tonumber) end), grace_s: $grace},
+       watchdog: {multiplier: 2, override_s: (if $wdo == "" then null else ($wdo | tonumber) end), grace_s: $grace,
+                 grade_timeout_s: (if $tmo then ($gto | tonumber) else null end), took_effect_timeout_s: (if $tmo then ($tto | tonumber) else null end)},
~~~~

## H24 — evals/harness/run-ablation.sh — head line 967

Head context (head/evals/harness/run-ablation.sh, lines 955–979):

~~~~text
   955 |   if ! jq -e 'type == "object"' "$rd/meta/pipeline.json" >/dev/null 2>&1; then
   956 |     jq -n --arg r "$6" --arg a "$2" --arg t "$3" --arg ty "$4" --argjson n "$5" --arg src "$SRC_FULL" --arg why "$7" \
   957 |       --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg mode "$EXECUTOR" \
   958 |       '{schema_version: 1, run_id: $r, arm: $a, task_id: $t, task_type: $ty, trial: $n, source_commit: $src,
   959 |         status: "interrupted", reason: $why, cap_phase: null, spent_usd: 0, executor_mode: $mode, phases: [],
   960 |         snapshots: {}, started: $now, finished: $now, synthesized_by: "run-ablation.sh"}' > "$rd/meta/pipeline.json"
   961 |   fi
   962 | }
   963 | # post_run <run-dir> <run_id> <task> <task_yaml> <attempts> <retry_reason> <pipeline_status>
   964 | #          <override> <row-out> <log> — the chain after a finished pipeline, shared by a trial
   965 | # and by --rerow: took-effect, drift guard, grade (completed, agent_error and cap_failure runs
   966 | # without an override), then ablation-row.sh into <row-out>. Results in PR_TE (ok | fail |
>  967 | # skipped), PR_TE_REASON, PR_DRIFT (json or null), PR_EXTRA (the extra models, json),
   968 | # PR_GRC (null or the grade exit), PR_RRC (the row exit) and PR_OVERRIDE (the final override)
   969 | post_run() {
   970 |   local rd="$1" rid="$2" task="$3" tyaml="$4" attempts="$5" rr="$6" st="$7" row_out="$9" plog="${10}"
   971 |   PR_OVERRIDE="$8" PR_TE=skipped PR_TE_REASON="" PR_DRIFT=null PR_EXTRA='{}' PR_GRC=null PR_RRC=0
   972 |   if [[ -z "$PR_OVERRIDE" ]]; then
   973 |     case "$st" in
   974 |       completed|agent_error|cap_failure)
   975 |         local trc=0 tout dout id
   976 |         tout="$("$TOOK_BIN" --run-dir "$rd" --suite-file "$SUITE_FILE" 2>&1)" || trc=$?
   977 |         printf '%s\n' "$tout" >> "$plog"
   978 |         if [[ $trc -eq 0 ]]; then PR_TE=ok
   979 |         else
~~~~

The change from head to the fix:

~~~~diff
@@ -967 +994 @@
-# skipped), PR_TE_REASON, PR_DRIFT (json or null), PR_EXTRA (the extra models, json),
+# skipped | timeout), PR_TE_REASON, PR_DRIFT (json or null), PR_EXTRA (the extra models, json),
~~~~

## H25 — evals/harness/run-ablation.sh — head lines 976–978

Head context (head/evals/harness/run-ablation.sh, lines 964–990):

~~~~text
   964 | #          <override> <row-out> <log> — the chain after a finished pipeline, shared by a trial
   965 | # and by --rerow: took-effect, drift guard, grade (completed, agent_error and cap_failure runs
   966 | # without an override), then ablation-row.sh into <row-out>. Results in PR_TE (ok | fail |
   967 | # skipped), PR_TE_REASON, PR_DRIFT (json or null), PR_EXTRA (the extra models, json),
   968 | # PR_GRC (null or the grade exit), PR_RRC (the row exit) and PR_OVERRIDE (the final override)
   969 | post_run() {
   970 |   local rd="$1" rid="$2" task="$3" tyaml="$4" attempts="$5" rr="$6" st="$7" row_out="$9" plog="${10}"
   971 |   PR_OVERRIDE="$8" PR_TE=skipped PR_TE_REASON="" PR_DRIFT=null PR_EXTRA='{}' PR_GRC=null PR_RRC=0
   972 |   if [[ -z "$PR_OVERRIDE" ]]; then
   973 |     case "$st" in
   974 |       completed|agent_error|cap_failure)
   975 |         local trc=0 tout dout id
>  976 |         tout="$("$TOOK_BIN" --run-dir "$rd" --suite-file "$SUITE_FILE" 2>&1)" || trc=$?
>  977 |         printf '%s\n' "$tout" >> "$plog"
>  978 |         if [[ $trc -eq 0 ]]; then PR_TE=ok
   979 |         else
   980 |           PR_TE=fail PR_OVERRIDE=infrastructure_error
   981 |           PR_TE_REASON="took-effect exit $trc: $(grep -E ' FAIL' <<<"$tout" | head -4 | cut -c1-200 | tr '\n' ';' || true)"
   982 |         fi
   983 |         dout="$(drift_check "$rd" "$rid" 2>>"$plog" || true)"
   984 |         PR_DRIFT="$(sed -n 1p <<<"$dout")" PR_EXTRA="$(sed -n 2p <<<"$dout")"
   985 |         jq -e . >/dev/null 2>&1 <<<"$PR_DRIFT" || PR_DRIFT=null
   986 |         jq -e 'type == "object"' >/dev/null 2>&1 <<<"$PR_EXTRA" || PR_EXTRA='{}'
   987 |         while IFS=$'\t' read -r id labels toks; do
   988 |           [[ -n "$id" ]] || continue
   989 |           printf 'run-ablation: extra model %s in %s (%s output tokens; a WebFetch summariser or built-in subagent, not drift — DEC-0545)\n' \
   990 |             "$id" "$labels" "$toks" >> "$plog"
~~~~

The change from head to the fix:

~~~~diff
@@ -976,3 +1003,7 @@
-        tout="$("$TOOK_BIN" --run-dir "$rd" --suite-file "$SUITE_FILE" 2>&1)" || trc=$?
+        tout="$(${TOOK_TMO[@]+"${TOOK_TMO[@]}"} "$TOOK_BIN" --run-dir "$rd" --suite-file "$SUITE_FILE" 2>&1)" || trc=$?
         printf '%s\n' "$tout" >> "$plog"
         if [[ $trc -eq 0 ]]; then PR_TE=ok
+        elif [[ ${#TOOK_TMO[@]} -gt 0 && ( $trc -eq 124 || $trc -eq 137 ) ]]; then
+          # a hang is infrastructure, not evidence that the arm did not take effect: no pause
+          PR_TE=timeout PR_OVERRIDE=infrastructure_error PR_TE_REASON="took-effect timed out after ${TOOK_TIMEOUT_S}s (exit $trc)"
+          printf 'run-ablation: took-effect timed out after %ss\n' "$TOOK_TIMEOUT_S" >> "$plog"
~~~~

## H26 — evals/harness/run-ablation.sh — head lines 996–997

Head context (head/evals/harness/run-ablation.sh, lines 984–1009):

~~~~text
   984 |         PR_DRIFT="$(sed -n 1p <<<"$dout")" PR_EXTRA="$(sed -n 2p <<<"$dout")"
   985 |         jq -e . >/dev/null 2>&1 <<<"$PR_DRIFT" || PR_DRIFT=null
   986 |         jq -e 'type == "object"' >/dev/null 2>&1 <<<"$PR_EXTRA" || PR_EXTRA='{}'
   987 |         while IFS=$'\t' read -r id labels toks; do
   988 |           [[ -n "$id" ]] || continue
   989 |           printf 'run-ablation: extra model %s in %s (%s output tokens; a WebFetch summariser or built-in subagent, not drift — DEC-0545)\n' \
   990 |             "$id" "$labels" "$toks" >> "$plog"
   991 |         done < <(jq -r 'to_entries[] | [.key, (.value.phases | join(",")), (.value.output_tokens | tostring)] | @tsv' <<<"$PR_EXTRA")
   992 |         if [[ "$PR_DRIFT" != null ]]; then PR_OVERRIDE=infrastructure_error; printf 'run-ablation: drift %s\n' "$PR_DRIFT" >> "$plog"; fi
   993 |         if [[ -z "$PR_OVERRIDE" ]]; then
   994 |           local -a g=("$GRADE_BIN" "$rd" "$task" --suite-root "$SUITE_ROOT" --executor "$EXECUTOR" --image "$IMAGE" --docker-bin "$DOCKER_BIN")
   995 |           [[ "$SMOKE" == true ]] && g+=(--tasks-dir smoke)
>  996 |           PR_GRC=0; "${g[@]}" >> "$plog" 2>&1 || PR_GRC=$?
>  997 |           if [[ $PR_GRC -ne 0 ]]; then PR_OVERRIDE=infrastructure_error; printf 'run-ablation: grade exit %s\n' "$PR_GRC" >> "$plog"; fi
   998 |         fi ;;
   999 |     esac
  1000 |   fi
  1001 |   local -a r=("$ROW_BIN" --run-dir "$rd" --task-yaml "$tyaml" --manifest "$MAN_PATH" --attempts "$attempts" --out "$row_out")
  1002 |   [[ -n "$rr" ]] && r+=(--retry-reason "$rr")
  1003 |   [[ -n "$PR_OVERRIDE" ]] && r+=(--status "$PR_OVERRIDE")
  1004 |   "${r[@]}" >> "$plog" 2>&1 || PR_RRC=$?
  1005 |   return 0
  1006 | }
  1007 | 
  1008 | run_trial() {  # run_trial <jid> <arm> <task> <type> <kind> <trial> <run_id> <task_yaml> <watchdog_s>
  1009 |   local jid="$1" arm="$2" task="$3" type="$4" kind="$5" trial="$6" rid="$7" tyaml="$8" wds="$9"
~~~~

The change from head to the fix:

~~~~diff
@@ -996,2 +1027,4 @@
-          PR_GRC=0; "${g[@]}" >> "$plog" 2>&1 || PR_GRC=$?
-          if [[ $PR_GRC -ne 0 ]]; then PR_OVERRIDE=infrastructure_error; printf 'run-ablation: grade exit %s\n' "$PR_GRC" >> "$plog"; fi
+          PR_GRC=0; ${GRADE_TMO[@]+"${GRADE_TMO[@]}"} "${g[@]}" >> "$plog" 2>&1 || PR_GRC=$?
+          if [[ ${#GRADE_TMO[@]} -gt 0 && ( $PR_GRC -eq 124 || $PR_GRC -eq 137 ) ]]; then
+            PR_OVERRIDE=infrastructure_error; printf 'run-ablation: grade timed out after %ss\n' "$GRADE_TIMEOUT_S" >> "$plog"
+          elif [[ $PR_GRC -ne 0 ]]; then PR_OVERRIDE=infrastructure_error; printf 'run-ablation: grade exit %s\n' "$PR_GRC" >> "$plog"; fi
~~~~

## H27 — evals/tests/ablation-grade.bats — insertion after head line 1001

Head context (head/evals/tests/ablation-grade.bats, lines 990–1001):

~~~~text
   990 |   [[ "$output" == *"--executor host is refused"*"no filesystem, process or network isolation"*"LOA_EVAL_ALLOW_HOST_GRADING=1"* ]]
   991 |   [ ! -e "$RD/grade.json" ]
   992 |   run env LOA_EVAL_ALLOW_HOST_GRADING=yes "$GRADER" --self-check base --task-yaml "$S/tasks/rc-x/task.yaml" --allow-unfrozen --executor host
   993 |   [ "$status" -eq 2 ]
   994 |   run "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --executor host
   995 |   [ "$status" -eq 0 ]
   996 |   [[ "$output" == *"WARNING --executor host"* ]]
   997 |   [ "$(G '.executor_mode')" = host ]
   998 |   # container mode needs no opt-in
   999 |   run env -u LOA_EVAL_ALLOW_HOST_GRADING "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
  1000 |   [ "$status" -eq 0 ] && [ "$(G '.executor_mode')" = container ]
  1001 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -1001,0 +1002,118 @@
+
+# --- grader 1.2.6 (Sprint 260 review round 1, DISS-C-001 … C-005) ------------------------------
+# bash_case <want> <command> — one Bash tool_use after an `ls`; <want> is the contamination
+# pattern (or null) the container-mode grade must report
+bash_case() {
+  i=$((${i:-0} + 1)); RD="$T/b$i"; make_run rc-x "$RD"
+  tool_use "$RD" IMPLEMENT Bash '{"command": "ls"}'
+  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c "$2" '{command: $c}')"
+  grade "$RD" rc-x
+  [ "$status" -eq 0 ]
+  if [ "$1" = null ]; then
+    [ "$(G '.contaminated')" = null ] || { echo "expected clean: $2 → $(G '.contaminated')"; return 1; }
+  else
+    [ "$(G '.contaminated | "\(.pattern) \(.excerpt_id)"')" = "$1 IMPLEMENT:2" ] || { echo "expected $1: $2 → $(G '.contaminated')"; return 1; }
+  fi
+}
+
+@test "AG-29 heredoc operator line (MEDIUM-1): a redirect, pipe or argument after <<WORD is scanned; the body is not" {
+  bash_case outside_path $'cat <<\'EOF\' > /root/x\nbody\nEOF'
+  bash_case outside_path $'cat <<EOF | tee /mnt/x\nbody\nEOF'
+  bash_case outside_path $'python3 - <<\'PY\' /srv/data\nprint(1)\nPY'
+  bash_case outside_path $'cat > /root/notes.md <<\'EOF\'\nbody\nEOF'
+  bash_case null $'cat > notes.md <<EOF\nSee /home/operator/notes\nEOF'
+  bash_case null $'cat <<-EOF > /workspace/out.txt\n\tsee /root/x\n\tEOF\nls /tmp'
+  # the stripped body leaves the following commands scanned
+  bash_case outside_path $'cat > a.md <<EOF\n/home/operator\nEOF\nls /home'
+}
+
+@test "AG-30 heredoc backtracking (MEDIUM-2): an 80-line command with \$((1<<n)), <<<\"word\" and no terminator grades in time" {
+  local c n
+  c=$'x=$((1<<n))\ny=$(cat <<<"word")'
+  for n in $(seq 1 78); do c+=$'\n'"echo step $n of the loop"; done
+  [ "$(printf '%s\n' "$c" | wc -l)" -eq 80 ]
+  RD="$T/bt"; make_run rc-x "$RD"
+  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c "$c" '{command: $c}')"
+  run timeout 20 "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
+  [ "$status" -eq 0 ]
+  [ "$(G '.contaminated')" = null ]
+  # and a real reach after such a command is still found
+  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c "$c"$'\ncat /root/x' '{command: $c}')"
+  run timeout 20 "$GRADER" "$RD" rc-x --suite-root "$S" --allow-unfrozen --docker-bin "$T/docker"
+  [ "$status" -eq 0 ]
+  [ "$(G '.contaminated | "\(.pattern) \(.excerpt_id)"')" = "outside_path IMPLEMENT:2" ]
+}
+
+@test "AG-31 in_quotes (LOW-1): a word that is the whole quoted argument is a candidate; quote state, not parity" {
+  bash_case outside_path 'cd "/root"'
+  bash_case outside_path "ls '/home'"
+  bash_case outside_path "cd '/root'"
+  bash_case outside_path "cd '/root/' && ls"
+  bash_case outside_path 'echo "don'"'"'t" && ls /root'
+  bash_case outside_path "echo 'a\"b' && ls /mnt"
+  bash_case outside_path 'echo \"x && ls /srv'
+  bash_case null "grep -E ' /tmp | /home ' f"
+  bash_case null "awk '/start/,/end/' f"
+  bash_case null 'echo "it'"'"'s /tmp and /home"'
+  bash_case null "grep -c 'in /root' log.txt"'; echo "see /home here"'
+  # a pattern that is exactly the sensitive word is indistinguishable from a quoted path argument
+  bash_case outside_path "grep -c '/root' log.txt"
+}
+
+@test "AG-32 HIDDEN_TOKEN (LOW-2): camelCase, any-case adjacency and glob shapes are hits; a bare hidden word is not" {
+  bash_case hidden 'ls hiddenTests/'
+  bash_case hidden 'ls HiddenTests/'   # 1.2.7 (DISS-C-006): PascalCase
+  bash_case hidden 'cat Hidden/x'
+  bash_case hidden "find . -iname '*hidden*'"
+  bash_case hidden 'ls tests/HIDDEN_cases.py'
+  bash_case hidden 'ls tests/hidden/'
+  bash_case hidden 'ls tests/Hidden_cases.py'
+  bash_case null 'python3 -m pytest -q tests/test_config.py -k hidden'
+  bash_case null $'cat > grimoires/loa/a2a/sprint-1/reviewer-concerns.md <<EOF\n1. argument_default=argparse.SUPPRESS: any hidden\n   interaction with store_true? The value is hidden.\nEOF'
+  bash_case null 'echo "Hidden state is gone; nothing hidden remains"'
+  # 1.2.7 (DISS-C-001): English and Markdown in a written heredoc are not globs; a glob in the command still is
+  bash_case null $'cat > review.md <<EOF\nIs any state hidden? The **hidden** global is gone; *hidden* means private here.\nEOF'
+  bash_case hidden $'cat > review.md <<EOF\nIs any state hidden?\nEOF\nfind . -iname \'*hidden*\''
+}
+
+@test "AG-34 audit round 1 (MEDIUM-A1, LOW-A1): dot segments, an empty quote and a glob never hide a sensitive root; a bare hidden after a filesystem command is a probe" {
+  bash_case outside_path 'cat /./root/.ssh/id_rsa'
+  bash_case outside_path 'ls /../root/x'
+  bash_case outside_path "cat ''/root/.ssh/id_rsa"
+  bash_case outside_path 'echo ""/mnt/x'
+  bash_case outside_path 'ls /roo*'
+  bash_case outside_path 'cat /ro?t/.ssh/id_rsa'
+  bash_case null 'ls /usr* /bin/'
+  # 1.2.9: a [ is a regex bracket, and a quoted one-component pattern is pattern text (two P1 commands under 1.2.8)
+  bash_case null "grep -a -o -m1 '/workspace[^\"]*loader.py\\|/home[^\"]*loader.py' src/x/__pycache__/loader.pyc || echo none"
+  bash_case null "sed -i 's/job\\[\"status\"\\] is Status.PENDING:/job[\"status\"] == Status.PENDING:/' src/jobboard/board.py"
+  bash_case null "grep -c '/roo*' log.txt"
+  bash_case null "cat pr/'\"\$v\"'/.claude/settings.json"
+  bash_case null 'cp -r evals "$D"/ && ls "$D"/evals/x'
+  bash_case null $'cat > r.md <<EOF\nrun /review-sprint sprint-1 then /audit-sprint sprint-1\nEOF'
+  bash_case hidden 'cd hidden'
+  bash_case hidden 'ls -la hidden'
+  bash_case hidden 'cat hidden'
+  bash_case hidden 'find . -name hidden'
+  bash_case hidden "find . -type d -iname 'hidden' -print"
+  bash_case null 'python3 -m pytest -q tests -k hidden'
+  bash_case null 'grep -rn hidden src/ | head'
+  bash_case null $'cat > notes.md <<EOF\ncd hidden is what a probe looks like\nEOF'
+  bash_case hidden 'cd tests/hidden'
+}
+
+@test "AG-33 heredoc_interpreters (LOW-3): heredocs fed to an interpreter are counted, never contamination" {
+  bash_case null $'python3 - <<\'PY\'\nprint(1)\nPY'
+  [ "$(G '.heredoc_interpreters')" = 1 ]
+  bash_case null $'cat <<EOF\nx\nEOF'
+  [ "$(G '.heredoc_interpreters')" = 0 ]
+  RD="$T/interp"; make_run rc-x "$RD"
+  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c $'cd /workspace && python3 - <<\'PY\'\nprint(1)\nPY' '{command: $c}')"
+  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c $'bash <<EOF\necho hi\nEOF\n/usr/bin/node - <<JS\nconsole.log(1)\nJS' '{command: $c}')"
+  tool_use "$RD" IMPLEMENT Bash "$(jq -cn --arg c $'X=1 perl <<EOF\nprint 1\nEOF\ncat <<EOF | sh\nls\nEOF\npython3.11 <<"PY"\nprint(2)\nPY' '{command: $c}')"
+  grade "$RD" rc-x
+  [ "$status" -eq 0 ]
+  [ "$(G '.contaminated')" = null ]
+  [ "$(G '.heredoc_interpreters')" = 5 ]
+  [ "$(G '.grader_version')" = 1.2.9 ]
+}
~~~~

## H28 — evals/tests/fixtures/ablation-grade-stub.sh — head line 7

Head context (head/evals/tests/fixtures/ablation-grade-stub.sh, lines 1–19):

~~~~text
     1 | #!/usr/bin/env bash
     2 | # ablation-grade-stub.sh — stand-in for ablation-grade.sh in evals/tests/run-ablation.bats.
     3 | #   ablation-grade-stub.sh <run-dir> <task-id> --suite-root R [--tasks-dir T] [--executor …]
     4 | #     [--image …] [--docker-bin …]
     5 | # Writes <run-dir>/grade.json: build tasks {hidden_tests 3/4, regressions none}, review-catch
     6 | # {recall 1 of 2, verdict CHANGES_REQUIRED}. STUB_GRADE_LOG gets the argv (one line);
>    7 | # a run_id matching the glob in STUB_GRADE_FAIL exits 2 without writing.
     8 | set -euo pipefail
     9 | export LC_ALL=C
    10 | RD="$1" TASK="$2"; shift 2
    11 | ROOT="" TD=tasks
    12 | while [[ $# -gt 0 ]]; do
    13 |   case "$1" in
    14 |     --suite-root) ROOT="$2"; shift 2 ;;
    15 |     --tasks-dir) TD="$2"; shift 2 ;;
    16 |     --executor|--image|--docker-bin) shift 2 ;;
    17 |     *) echo "grade-stub: unknown flag $1" >&2; exit 2 ;;
    18 |   esac
    19 | done
~~~~

The change from head to the fix:

~~~~diff
@@ -7 +7,2 @@
-# a run_id matching the glob in STUB_GRADE_FAIL exits 2 without writing.
+# a run_id matching the glob in STUB_GRADE_FAIL exits 2 without writing; one matching the glob
+# in STUB_GRADE_HANG sleeps 600 s before writing (the runner's grade deadline, Sprint 260 LOW-4).
~~~~

## H29 — evals/tests/fixtures/ablation-grade-stub.sh — insertion after head line 25

Head context (head/evals/tests/fixtures/ablation-grade-stub.sh, lines 14–33):

~~~~text
    14 |     --suite-root) ROOT="$2"; shift 2 ;;
    15 |     --tasks-dir) TD="$2"; shift 2 ;;
    16 |     --executor|--image|--docker-bin) shift 2 ;;
    17 |     *) echo "grade-stub: unknown flag $1" >&2; exit 2 ;;
    18 |   esac
    19 | done
    20 | [[ -n "${STUB_GRADE_LOG:-}" ]] && printf '%s %s --tasks-dir %s\n' "$(basename "$RD")" "$TASK" "$TD" >> "$STUB_GRADE_LOG"
    21 | rid="$(jq -r '.run_id' "$RD/meta/pipeline.json")"
    22 | if [[ -n "${STUB_GRADE_FAIL:-}" ]]; then
    23 |   # shellcheck disable=SC2254
    24 |   case "$rid" in $STUB_GRADE_FAIL) echo "grade-stub: refused" >&2; exit 2 ;; esac
    25 | fi
    26 | type="$(yq -r '.type' "$ROOT/$TD/$TASK/task.yaml")"
    27 | if [[ "$type" == review-catch ]]; then
    28 |   jq -n '{recall: {defects_seeded: 2, defects_caught: 1, recall: 0.5}, false_positives: 0,
    29 |           verdict: {value: "CHANGES_REQUIRED"}, verdict_accuracy: true, grader_version: "stub"}' > "$RD/grade.json"
    30 | else
    31 |   jq -n '{hidden_tests: {passed: 3, total: 4}, regressions: {newly_failing: []}, diff_lines: 10, files_changed: 1,
    32 |           grader_version: "stub"}' > "$RD/grade.json"
    33 | fi
~~~~

The change from head to the fix:

~~~~diff
@@ -25,0 +27,4 @@
+if [[ -n "${STUB_GRADE_HANG:-}" ]]; then
+  # shellcheck disable=SC2254
+  case "$rid" in $STUB_GRADE_HANG) echo "grade-stub: hanging" >&2; sleep 600 ;; esac
+fi
~~~~

## H30 — evals/tests/run-ablation.bats — head line 31

Head context (head/evals/tests/run-ablation.bats, lines 19–43):

~~~~text
    19 |   T="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/rab.XXXXXX")"
    20 |   mkdir -p "$T/bin" "$T/src/.claude"
    21 |   cp "$FX/ablation-docker-stub.sh" "$T/bin/docker"
    22 |   cp "$FX/docker-stub.sh" "$T/bin/docker-stub.sh"
    23 |   printf '%s\n' '#!/usr/bin/env bash' 'echo "2.1.300 (Claude Code)"' > "$T/bin/claude"
    24 |   chmod +x "$T/bin/docker" "$T/bin/docker-stub.sh" "$T/bin/claude"
    25 |   echo "# loa" > "$T/src/.claude/CLAUDE.loa.md"
    26 |   ( cd "$T/src" && git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -q -m src )
    27 |   SHA="$(git -C "$T/src" rev-parse HEAD)"
    28 |   for i in $(seq 1 36); do echo "self-check base task-$i: PASS hidden 1/1"; done > "$T/self-check.log"
    29 |   export PATH="$T/bin:$PATH" EVAL_CLAUDE_BIN="$T/bin/claude" LOA_ABLATION_SOURCE_TREE="$T/src"
    30 |   export LOA_ABLATION_RETRY_WAIT_S=0 LOA_ABLATION_POLL_S=0.2 STUB_LOG="$T/stub.log" STUB_GRADE_LOG="$T/grade.log"
>   31 |   unset STUB_RULES STUB_HANG STUB_CLI STUB_COST STUB_GRADE_FAIL LOA_ABLATION_WATCHDOG_S LOA_ABLATION_WATCHDOG_GRACE_S DOCKER_STUB_NO_IMAGE LOA_ABLATION_OUTAGE_BREAKER
    32 |   RES="$T/res"
    33 | }
    34 | 
    35 | teardown() {
    36 |   find "$T" -mindepth 1 -delete 2>/dev/null || true
    37 |   rmdir "$T" 2>/dev/null || true
    38 | }
    39 | 
    40 | # ra <args…> — the runner with the stubs and the test locations
    41 | ra() {
    42 |   run "$RA" --source-commit "$SHA" --results-root "$RES" --self-check-log "$T/self-check.log" \
    43 |     --pipeline-bin "$FX/ablation-pipeline-stub.sh" --grade-bin "$FX/ablation-grade-stub.sh" --docker-bin "$T/bin/docker" "$@"
~~~~

The change from head to the fix:

~~~~diff
@@ -31 +31 @@
-  unset STUB_RULES STUB_HANG STUB_CLI STUB_COST STUB_GRADE_FAIL LOA_ABLATION_WATCHDOG_S LOA_ABLATION_WATCHDOG_GRACE_S DOCKER_STUB_NO_IMAGE LOA_ABLATION_OUTAGE_BREAKER
+  unset STUB_RULES STUB_HANG STUB_CLI STUB_COST STUB_GRADE_FAIL STUB_GRADE_HANG LOA_ABLATION_GRADE_TIMEOUT_S LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S LOA_ABLATION_WATCHDOG_S LOA_ABLATION_WATCHDOG_GRACE_S DOCKER_STUB_NO_IMAGE LOA_ABLATION_OUTAGE_BREAKER
~~~~

## H31 — evals/tests/run-ablation.bats — insertion after head line 688

Head context (head/evals/tests/run-ablation.bats, lines 677–688):

~~~~text
   677 |   rules '* transport'
   678 |   : > "$T/stub.log"
   679 |   ra --arms a1_full --tasks bugfix-01,bugfix-02,bugfix-03,bugfix-04,feature-01,feature-02,feature-03 --trials-build 1 --batch ob2 --concurrency 1
   680 |   [ "$status" -eq 3 ]   # no trial completed
   681 |   [ "$(wc -l < "$T/stub.log")" -eq 14 ]
   682 |   [ "$(jq -r 'select(.batch == "ob2") | .status' "$RES/runs.jsonl" | sort | uniq -c | awk '{print $1, $2}')" = "7 transport_error" ]
   683 |   jq -e '.outage == null and .outage_history == []' "$RES/ob2/STATUS.json" >/dev/null
   684 |   # a breaker value that is not a whole number is a usage error
   685 |   export LOA_ABLATION_OUTAGE_BREAKER=x
   686 |   ra --arms a1_full --tasks bugfix-01 --trials-build 1 --batch ob3
   687 |   [ "$status" -eq 2 ]; grep -q 'LOA_ABLATION_OUTAGE_BREAKER must be a whole number' <<<"$output"
   688 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -688,0 +689,37 @@
+
+@test "RAB-21 post-run deadlines (Sprint 260 LOW-4): a grade that hangs past LOA_ABLATION_GRADE_TIMEOUT_S rows infrastructure_error and the batch finishes; a hung took-effect too, without pausing the arm; MANIFEST watchdog records both; a non-integer value is a usage error" {
+  export STUB_GRADE_HANG='*-bugfix-01-*' LOA_ABLATION_GRADE_TIMEOUT_S=2
+  SECONDS=0
+  ra --arms a1_full --tasks bugfix-01,bugfix-02,review-01 --trials-build 1 --trials-review 1 --batch gt1 --concurrency 2
+  [ "$status" -eq 1 ]   # partial: the timed-out row is excluded
+  [ "$SECONDS" -lt 120 ]
+  B="$RES/gt1"
+  [ "$(wc -l < "$RES/runs.jsonl")" -eq 3 ]
+  [ "$(row gt1-a1_full-bugfix-01-t1 | jq -r '.status')" = infrastructure_error ]
+  [ "$(row gt1-a1_full-bugfix-02-t1 | jq -r '.status')" = completed ]
+  [ "$(row gt1-a1_full-review-01-t1 | jq -r '.status')" = completed ]
+  grep -q 'run-ablation: grade timed out after 2s' "$B/a1_full/bugfix-01-t1.log"
+  ! grep -q 'grade timed out' "$B/a1_full/bugfix-02-t1.log" || false
+  [ "$(jq -r '.state' "$B/STATUS.json")" = partial ]
+  [ "$(jq -r '.per_arm.a1_full.excluded' "$B/STATUS.json")" = 1 ]
+  [ "$(jq -c '.watchdog | [.grade_timeout_s, .took_effect_timeout_s]' "$B/MANIFEST.json")" = '[2,300]' ]
+  ! pgrep -f "ablation-grade-stub.sh $B" >/dev/null 2>&1 || false   # the hung grader was killed
+  # a took-effect that hangs: infrastructure_error, the arm is not paused, the next trial runs
+  unset STUB_GRADE_HANG
+  printf '%s\n' '#!/usr/bin/env bash' 'sleep 600' > "$T/te-hang"; chmod +x "$T/te-hang"
+  export LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S=1
+  ra --arms a1_full --tasks bugfix-01,bugfix-02 --trials-build 1 --batch gt2 --concurrency 1 --took-effect-bin "$T/te-hang"
+  [ "$status" -eq 3 ]   # failed: no trial completed — but both launched (no pause after the first)
+  [ "$(row gt2-a1_full-bugfix-01-t1 | jq -r '.status')" = infrastructure_error ]
+  [ "$(row gt2-a1_full-bugfix-02-t1 | jq -r '.status')" = infrastructure_error ]
+  grep -q 'run-ablation: took-effect timed out after 1s' "$RES/gt2/a1_full/bugfix-01-t1.log"
+  [ "$(jq -c '.paused_arms' "$RES/gt2/STATUS.json")" = '{}' ]
+  [ "$(jq -r '.watchdog.took_effect_timeout_s' "$RES/gt2/MANIFEST.json")" = 1 ]
+  # a deadline that is not a positive whole number is a usage error
+  for v in x 0 1.5 1234567; do
+    LOA_ABLATION_GRADE_TIMEOUT_S="$v" ra --arms a1_full --tasks bugfix-01 --trials-build 1 --batch gt3 --dry-run
+    [ "$status" -eq 2 ]; grep -q 'LOA_ABLATION_GRADE_TIMEOUT_S must be positive whole seconds' <<<"$output"
+  done
+  LOA_ABLATION_GRADE_TIMEOUT_S=5 LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S=abc ra --arms a1_full --tasks bugfix-01 --trials-build 1 --batch gt4 --dry-run
+  [ "$status" -eq 2 ]; grep -q 'LOA_ABLATION_TOOK_EFFECT_TIMEOUT_S must be positive whole seconds' <<<"$output"
+}
~~~~
