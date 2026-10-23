# Incidents — pr-24

Things that happened after the change merged and cite one of its files: later fix commits on the main branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.

## I01 — kf — 2026-10-19

- reference: KF-046
- files: evals/harness/ablation-grade.sh

Summary:

## KF-046: ablation-grade.sh contamination scan flags ordinary agent text and shell idioms as outside_path or git_history (slash commands, git log --all, heredoc prose, sed address ranges, container home) **Status**: active **Feature**: evals/harness/ablation-grade.sh check_value / ABS_WORD (D-4.7 contamination scan) **Symptom**: grade.json contaminated {phase, pattern: outside_path|git_history,…

Evidence:

~~~~~text
~~~~markdown
## KF-046: ablation-grade.sh contamination scan flags ordinary agent text and shell idioms as outside_path or git_history (slash commands, git log --all, heredoc prose, sed address ranges, container home)

**Status**: active
**Feature**: evals/harness/ablation-grade.sh check_value / ABS_WORD (D-4.7 contamination scan)
**Symptom**: grade.json contaminated {phase, pattern: outside_path|git_history, excerpt_id: <PHASE>:<line>} and the row status contaminated on a run that never left the sandbox; the excerpt line holds a Loa slash command (/review-sprint), git log --all, prose inside a heredoc, ls ~/.cargo/bin in the container, a sed range /,/ or /re1/,/re2/p
**First observed**: 2026-10-15 cycle-130 Sprint 260 calibration smoke calib-frozen-01 (10 of 12 rows), then priority batch P1 review-04 REVIEW:39
**Recurrence count**: 10
**Current workaround**: re-grade the run directories under the current grader (no agent re-run) and re-row: run-ablation.sh --resume --rerow <run_id> (DEC-0547); the grader fixes are 1.2.1 (DEC-0540), 1.2.2 (DEC-0541), 1.2.3 (DEC-0546)
**Upstream issue**: none (harness heuristic; structural: a path-word regex over free-form Bash text cannot be made exact; the scan is a lower bound by design, D-4.7)
**Related visions / lore**: DEC-0540, DEC-0541, DEC-0546, DEC-0547; KF-045

### Attempts

| Date | What we tried | Outcome | Evidence |
|------|---------------|---------|----------|
| 2026-10-15 | grader 1.2.1 (one-component words, history probes), 1.2.2 (heredoc bodies, container home, /x/ delimiters), 1.2.3 (sed address ranges) | calibration rows 10 contaminated to 0; P1 review-04 re-rowed under 1.2.3 | commits 2ef83aa8, ae9df520; a2a/sprint-260/smoke.md; NOTES 2026-10-15T11:18:02Z |
| 2026-10-15 | grader 1.2.4 prepared (DEC-0551): words beginning with /, (range remnant after a spaced first address) and words carrying = are regex-shaped, not paths; applied after P1 ends, then --rerow of every contaminated row | pending (P1 running; a1_full review-02-t1 AUDIT:86 is the fourth false-positive class: sed -n '/=== VERIFY python ValueError ===/,/=== scanner usage ===/p') | grimoires/loa/reports/ablation-2.0/batches/priority-p1/a1_full/review-02-t1/grade.json; ~/.cache/loa/cycle-130/grader-124-patch.py |
| 2026-10-15 | fifth class: the hidden keyword matched ordinary English in a reviewer heredoc (a1_full bugfix-04-t1 REVIEW:148 'any hidden interaction'); grader 1.2.4 also narrows hidden in Bash text to token shapes (DEC-0551) | pending (applied after P1 ends; rows re-rowed) | grimoires/loa/reports/ablation-2.0/batches/priority-p1/a1_full/bugfix-04-t1/grade.json; ~/.cache/loa/cycle-130/grader-124-patch.py |
| 2026-10-16 | grader 1.2.4 applied (6c454de7) after P1 stopped; the seven contaminated P1 rows re-graded clean in scratch copies and were re-rowed on the resume | 0 of 7 contaminated under 1.2.4 (review-03-t1 reads cap_failure, the rest completed) | a2a/sprint-260/reviewer.md; grimoires/loa/reports/ablation-2.0/batches/priority-p1/STATUS.json rerowed[] |
| 2026-10-16 | sixth class: a path tail after a closing quote glued to its token ("$D"/evals/harness/x) read as an absolute outside path (a1_full feature-01-t2 AUDIT:122, grader 1.2.4); grader 1.2.5 prepared (DEC-0557), applied after P1 ends, the row re-rowed | pending | grimoires/loa/reports/ablation-2.0/batches/priority-p1/a1_full/feature-01-t2-r3/grade.json; ~/.cache/loa/cycle-130/grader-125-patch.py |
| 2026-10-16 | grader 1.2.5 applied (bf155cc7) after P1 completed; both rows re-rowed; P1 ends with 0 contaminated rows after six grader rounds (1.2.1–1.2.5) | 0 of 132 P1 rows contaminated; every contaminated row of the cycle so far was a scan false positive, none a real reach | grimoires/loa/reports/ablation-2.0/batches/priority-p1/STATUS.json rerowed[] (11 entries); runs.jsonl |
| 2026-10-16 | grader 1.2.8 (Sprint 260 audit fix) treated a [ after a one-component absolute word as a glob metacharacter so the word stayed a path candidate; re-scan of the 132 graded P1 run dirs under 1.2.8 | two new false positives (a1_full feature-03-t2-r3 AUDIT:115 grep '/home[^"]*loader.py' regex; refactor-04-t2-r3 IMPLEMENT:47 sed 's/job\["status"\]…'): a bracket after the word is a regex bracket expression in agent commands, not a glob — grader 1.2.9 reads * and ? only and keeps a quoted one-component pattern exempt; the re-scan is back to 0 changes | rescan-p1-126.py over priority-p1 under 1.2.8 vs the stored grade.json (2 changed) and under 1.2.9 (0 changed); commit 60503096 (1.2.8) and the 1.2.9 commit that follows; a2a/sprint-260/auditor-sprint-feedback.md round 2 |
| 2026-10-17 | grader 1.2.11 on the suite v2 round-2 calibration (calib-v2-02a, a0_bare x 10 tasks x 2) | one row contaminated (refactor-v2-07 t1, BARE:145 outside_path): the bare agent passed JSON Pointer literals (get clit/d.json /a/1, /a/9) as CLI arguments while differential-testing a JSON Patch package — a two-component word indistinguishable from an absolute path by shape; read by hand, not a reach; pass rate 1.0 either way, so the hardness read is unchanged; no grader change (a pointer-literal exemption would also exempt real paths); the task is not run in the v2 batch | evals/results/ablation-2.0/calib-v2-02a/a0_bare/refactor-v2-07-t1/grade.json contaminated BARE:145; commit bde0c22e (grader 1.2.11) |
| 2026-10-19 | seventh class, batch replication-01 (deep analysis): pattern repo_name fired on the reviewer's own heredoc text quoting the PR's CI workflow clause github.repository == '0xHoneyJar/loa' (pr-18 head/.github/workflows/check-glossary-terms.yml); rows a1_full review-r18-t2 (REVIEW:320, reviewer-concerns.md heredoc) and review-r18-t3 (AUDIT:332, auditor-sprint-feedback.md heredoc) read contaminated | read by hand: the string is the PR's own content, not a reach outside the sandbox; no grader change in this analysis task (code edits out of scope), so the two rows stay contaminated under the pre-registered rule (a1 excluded share 2/6 = 0.33 > 0.25 -> the replication's pre-registered read is inconclusive by degradation) and the hand-read sensitivity with the two rows included is reported beside it; grader fix (exempt a repo name that occurs in pr/head or head.diff) is a cycle-131 candidate | evals/results/ablation-2.0/replication-01/a1_full/review-r18-t2/grade.json contaminated REVIEW:320; evals/results/ablation-2.0/replication-01/a1_full/review-r18-t3/grade.json contaminated AUDIT:332; a2a/analysis-2026-10/replication.md |
| 2026-10-20 | cycle-131 B2a rows under grader 1.3.0 (class 7 + r1a/r1c rules): a0_bare × review-r18 t1 and a1_full × review-r18 t1 read contaminated | a0_bare r18 t1 (BARE:96) is a TRUE positive: curl -sfL … raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/loa/CLAUDE.loa.md to fill a missing file (repo_name, correctly never exempt). a1_full r18 t1 (AUDIT:303) is an outside_path hit on a reproduction: the auditor built a scratch git repo + venv under $HOME/tmp/venvrepro.XXXX to reproduce the PR's venv claim — no upstream fetch, no answer path; class 8 candidate (scratch-dir reproduction under $HOME/tmp). Both rows excluded by the pre-registered validity rule; a labelled sensitivity re-includes class-8 rows (NOTES 2026-10-20, defined before the reads) | evals/results/ablation-2.0/c131-b2-control-prices-a/{a0_bare,a1_full}/review-r18-t1/grade.json; pin 798d88cf |

### Reading guide

A contaminated row is a claim to verify, not a verdict: print the excerpt line (sed -n '<line>p' <run-dir>/transcripts/events-<PHASE>.jsonl | jq '.message.content[] | select(.type=="tool_use") | .input') and ask whether the word reaches a path outside the sandbox, the container home, /tmp or the system dirs. Shell idioms seen so far: slash commands, sed/awk delimiters and ranges, heredoc prose, regexes beginning with = or a letter. If it is an idiom: fix the grader (bump GRADER_VERSION, extend AG-10), re-grade every affected run directory, --rerow. If it is a real reach: the exclusion stands. Recurrence 3 in one day means the heuristic is structural: budget a re-read of every contaminated row before the report.

~~~~
~~~~~

## I02 — issue — 2026-10-19

- reference: #1285
- files: .gitignore

Summary:

docs(cycle-130): deep analysis of the review-side lift + out-of-sample replication — ## Summary Analysis only: no shipped number changes. Follow-on to PR #1283 / v2.0.0-rc.6 asking where the review-side lift (+0.263 on `defect_catch_rate`, DEC-0597) comes from, recomputed from the raw run directories, plus a pre-registered out-of-sample replication on two corpus PRs nobody had used (pr-17, pr-18)…

Evidence:

~~~~~text
# pull request #1285: docs(cycle-130): deep analysis of the review-side lift + out-of-sample replication

- url: https://github.com/0xHoneyJar/loa/pull/1285
- created_at: 2026-10-19T04:36:08Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
## Summary

Analysis only: no shipped number changes. Follow-on to PR #1283 / v2.0.0-rc.6 asking where the review-side lift (+0.263 on `defect_catch_rate`, DEC-0597) comes from, recomputed from the raw run directories, plus a pre-registered out-of-sample replication on two corpus PRs nobody had used (pr-17, pr-18).

**Findings (`grimoires/loa/reports/ablation-2.0/analysis.md`, ELI5 at the top):**
- 57 paired defect-trials: full-only catches 15, bare-only 0; the whole lift sits on pr-12; cluster bootstrap by PR [+0.056, +0.437].
- No dissent envelope carries a numeric line anchor, so the dissent is credited with 0 citations in 36 runs; 10 of the 15 lift catches are the Fable reviewer alone, 2 the audit gate, at most 3 dissent-influenced. Dissent = 17 % of a full run's cost, audit gate 49 %.
- Two measurement artefacts: the ±3-line window (bare cites the bug line, labels sit on function headers; same-function rule → +0.140) and **KF-049**, the mounted-framework oracle (the full arm's sandbox mounts a later copy that already holds every fix; the reviewer diffed against it on planted sites in 1 of 12 original and 2 of 6 replication runs; bare has no such mount).
- 61 "false positives" hand-labelled blind by two Opus labelers (kappa 0.88): wrong ≈ 0; corrected precision bare 0.44 [0.36, 0.51], full 0.16 [0.10, 0.22].
- Replication (`replication-01`, USD 88.81, pre-registered DEC-0602/0603): the lift reappears and is larger (+0.452 [+0.310, +0.595] with two scanner-false-positive rows hand-read in; +0.333 [+0.190, +0.476] with every oracle-exposed catch zeroed), formally inconclusive by degradation under the rule as written (KF-046 recurrence 9). The dissent never ran at a review gate (budget gate), so the comparison is Fable twice with the skill's checklist against Opus once.
- Five ranked `cycle-131-candidate` changes (DEC-0604…0608 + beads bd-mlg9s, bd-5rmmf, bd-pacqf, bd-ba54i, bd-zv4og; harness follow-ups bd-9lfns, bd-1ohfe).

**Tracked in this PR:** `analysis.md`; the replication suite root `grimoires/loa/evals/ablation-2.0-replication/` (frozen `cffc7079`, fairness REVIEW.md PASS); the `priority-v2-p1b` batch `.gitignore`; `decisions.yaml` (DEC-0602…0608); `known-failures.md` (KF-049 new; KF-046 recurrence 9). Working files, data, labels, transcripts readings and the replication batch records go on `record/cycle-130-analysis` after merge.

**Process:** no `.claude/` or `evals/` code edits; the replication batch ran under an out-of-repo copy of `run-ablation.sh` that only adds `--allow-partial` to the freeze check and the grader call (DEC-0603, diff on the record branch); `evals/tests/` run locally at the close.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
~~~~
~~~~~

## I03 — fix-commit — 2026-10-20

- reference: 596627f46e02
- files: evals/harness/ablation-grade.sh,evals/tests/ablation-grade.bats

Summary:

fix(cycle-131): sprint-263 review round r1a — the oracle detector keeps shell redirections out of its command splitter; class 7 bare-line tokens never exempt; scope-map fixes; pr-17 smoke bounds Review dissent run 1 (gpt-5.5-pro + claude-headless, 9 findings, 2 BLOCKING; DEC-0642): - ablation-grade.sh split_segments: the ampersand of 2>&1 / >&2 / <&0 / &> is a redirection, not a separator, so a d…

Evidence:

~~~~diff
commit 596627f46e02fb40a9476fe1d597a763292cb366
Date: 2026-10-20T12:18:35+11:00

fix(cycle-131): sprint-263 review round r1a — the oracle detector keeps shell redirections out of its command splitter; class 7 bare-line tokens never exempt; scope-map fixes; pr-17 smoke bounds

Review dissent run 1 (gpt-5.5-pro + claude-headless, 9 findings, 2 BLOCKING; DEC-0642):
- ablation-grade.sh split_segments: the ampersand of 2>&1 / >&2 / <&0 / &> is a redirection, not a separator, so a
  diff reduced through `2>&1 | wc -l` or discarded with `&>/dev/null` is no longer planned as a content-printing
  diff (DISS-001, DISS-C-001); silent_sink() scans every grep flag and the long forms; a stat-only git diff
  (--stat, --numstat, --shortstat, --name-only, --name-status, --compact-summary) prints no content.
- KF-046 class 7: backslash continuations join into one logical line; a bare token standing as the whole line
  exempts nothing; a backticked quotation in prose stays PR content (DISS-C-002).
- grade_recall passes a non-existent EVAL_HEAD_DIR sentinel when the fixture head is unavailable (DISS-C-003).
- recall-vs-defects.sh: bash/bats closing brace measured with expandtabs(8) (DISS-C-006); markdown fences hide
  their # lines from heading detection (DISS-C-004); a python def with a multi-line signature keeps its body
  (DISS-C-005).
- Tests: AG-52, AG-53, RG-40, RG-41, RG-42 (test-first). evals/tests 512/512. The 36-run re-grade re-run on the
  fixed grader changes no row (0 of 36); AG-50's detector pins are unchanged.
- Smoke root: review-r17 task bounds REVIEW 50 / AUDIT 40 (DEC-0640), re-frozen; smoke read DEC-0641;
  follow-up beads bd-jszcp (DISS-C-007), bd-9zmfn (DISS-C-008).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/ablation-grade.sh b/evals/harness/ablation-grade.sh
index 1208bfde..4100de30 100755
--- a/evals/harness/ablation-grade.sh
+++ b/evals/harness/ablation-grade.sh
@@ -1626,7 +1626,8 @@ def grade_recall(t, run_dir, grading):
         f.write("".join(f"{p}:{a}\n" if a == b else f"{p}:{a}-{b}\n" for p, a, b in cites))
     env = dict(os.environ, EVAL_MANIFEST_DIR=os.path.dirname(t.key_path), LC_ALL="C")
     # 1.3.0: the same-scope clause reads the PR fixture's head/ tree (immutable; never the sandbox pr/)
-    env.pop("EVAL_HEAD_DIR", None)
+    # the sentinel keeps recall-vs-defects.sh off its $workspace/pr/head fallback (the sandbox copy; review r1 DISS-C-003)
+    env["EVAL_HEAD_DIR"] = os.path.join(grading, ".no-head")
     try:
         head = os.path.join(resolve_pr_fixture(t), "head")
         if os.path.isdir(head):
@@ -1932,7 +1933,8 @@ def contamination(run_dir):
 # '0xHoneyJar/loa'`); quoting that PR content is not a probe of the upstream repository. Each
 # occurrence's unit is the backtick span holding it (`…`), else its whole line, stripped; an
 # occurrence is exempt when its unit is a substring of one line of the task's PR fixture (head/**
-# files or head.diff, the diff's +/-/space prefix dropped). Every occurrence of a value must be exempt,
+# files or head.diff, the diff's +/-/space prefix dropped); a backslash-continued command is one logical line, and a
+# bare token standing as the whole line (a for-list word, a list entry) exempts nothing (review r1 DISS-C-002). Every occurrence of a value must be exempt,
 # else the value is a repo_name hit as before. Exempt values are recorded in contamination_exempt[]
 # ({phase, excerpt_id, pattern, fixture_line: "head/<path>:<n>" | "head.diff:<n>", line: the fixture
 # line, 200 characters at most}); build tasks have no PR fixture and no exemption.
@@ -1983,7 +1985,7 @@ def repo_name_exempt(val):
     if not fl:
         return None
     hits = []
-    for line in val.split("\n"):
+    for line in val.replace("\\\n", " ").split("\n"):   # a backslash-continued command is one logical line
         for m in REPO_TOKEN.finditer(line):
             unit = None
             for span in re.finditer(r"`[^`\n]*`", line):
@@ -1992,6 +1994,9 @@ def repo_name_exempt(val):
                     break
             if unit is None:
                 unit = line.strip()
+                if len(unit) < len(m.group(0)) + 4:
+                    return None       # a bare token as a whole (logical) line is a command word, not a quotation: it is a
+                                      # substring of every fixture token line and exempts nothing (review r1 DISS-C-002)
             match = next(((src, text) for src, text in fl if unit and unit in text), None)
             if match is None:
                 return None
@@ -2032,7 +2037,8 @@ def corpus_sha256(t):
 #   other defect of that file exposed_unknown. Text no header attributes, in a command with several
 #   targets, exposes a defect only with corroboration: a range near the site AND a line of the fixture's
 #   head/X within ±3 of the site in that text, or must_match. A diff whose output is discarded or reduced
-#   (>/dev/null, | wc, | grep -c|-q|-l, | cmp) and a tool_result flagged is_error print no content.
+#   (>/dev/null, &>/dev/null, | wc, | grep with -c|-q|-l anywhere, | cmp; a stat-only git diff) and a tool_result
+#   flagged is_error print no content; `2>&1`, `>&2`, `<&0` and `&>` are redirections, never separators.
 #   read form — a Bash segment whose executable is cat, sed, awk, grep, head, tail, less or python3, or a
 #   Read (file_path) / Grep (path) tool_use, naming a workspace answer path (a directory for grep or Grep
 #   covers the answer paths below it), whose result contains a LATER-ONLY line within ±3 of a planted site
@@ -2062,8 +2068,22 @@ ERR_LINE = re.compile(r"^(?:diff|sdiff|comm|git|cat|grep|sed|head|tail|awk|less)
 DIFF_BODY = re.compile(r"^[<>+\- @\\0-9]|^---$")
 FILEISH = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+|[A-Za-z0-9_-]+\.[A-Za-z0-9]{1,6}\b")
 # a diff whose stdout is counted, tested or discarded prints no content: | wc, | grep -c/-q/-l, >/dev/null
-SILENT_SINK = re.compile(r"^(?:wc|cmp|true|false|test)\b|^grep\s+(?:-[A-Za-z]*[cql][A-Za-z]*|--count|--quiet|--files-with-matches)\b")
 DEVNULL = re.compile(r"(?:^|[\s;])(?:1?>|&>|>&)\s*/dev/null")
+DIFF_STAT_FLAGS = {"--stat", "--numstat", "--shortstat", "--name-only", "--name-status", "--compact-summary"}
+
+
+def silent_sink(w):
+    """the piped-into command prints no diff content: wc, cmp, true/false/test, or grep with a counting /
+    quiet / files-only flag anywhere among its words (review r1 DISS-C-001: `grep -i -c` counts too)"""
+    if not w:
+        return False
+    exe = w[0].rsplit("/", 1)[-1]
+    if exe in ("wc", "cmp", "true", "false", "test"):
+        return True
+    if exe == "grep":
+        return any(re.fullmatch(r"-[A-Za-z]*[cql][A-Za-z]*", x) or x in ("--count", "--quiet", "--silent", "--files-with-matches")
+                   for x in w[1:])
+    return False
 
 
 def unquote_c(q):
@@ -2156,6 +2176,8 @@ def split_segments(cmd):
         elif ch == ")":
             depth = max(0, depth - 1)
             cur.append(ch)
+        elif depth == 0 and ch == "&" and (cmd[i - 1:i] in (">", "<") or cmd[i + 1:i + 2] == ">"):
+            cur.append(ch)          # a redirection (2>&1, >&2, <&0, &>f), not a separator (review r1 DISS-001/C-001)
         elif depth == 0 and ch in "\n;&|":
             pipe = ch == "|" and cmd[i + 1:i + 2] != "|" and cmd[i - 1:i] != "|"
             segs.append(("".join(cur), "|" if pipe else ";"))
@@ -2479,8 +2501,10 @@ def oracle_plan(tool, inp, ws, answer):
             if any(re.fullmatch(r"-[A-Za-z]*q[A-Za-z]*", x) or x in ("--brief", "--quiet") for x in w[1:]):
                 continue
             nxt = seg_words(segs[k + 1][0]) if sep == "|" and k + 1 < len(segs) else []
-            if DEVNULL.search(seg) or (nxt and SILENT_SINK.match(" ".join(nxt))):
+            if DEVNULL.search(seg) or (nxt and silent_sink(nxt)):
                 continue
+            if exe == "git" and any(x in DIFF_STAT_FLAGS for x in w):
+                continue              # a stat-only git diff prints names and counts, not content
             toks = segment_tokens(seg, vars_, cwd, ws)
             pr_ops = [k_ for k_, (v, c) in enumerate(toks) if c[0] == "pr" and c[1] in ("head", "base")
                       and not v.endswith("head.diff")]
diff --git a/evals/tests/ablation-grade.bats b/evals/tests/ablation-grade.bats
index bd318fe3..0d3b0ce1 100644
--- a/evals/tests/ablation-grade.bats
+++ b/evals/tests/ablation-grade.bats
@@ -1537,6 +1537,41 @@ CASES
   [ "$(G '.oracle_exposed_defects, .oracle_exposed_events, .corpus_sha256' | tr '\n' ' ')" = "null null null " ]
 }
 
+@test "AG-52 oracle redirections (review r1 DISS-001/C-001): 2>&1 | wc -l, &>/dev/null, 2>&1 | grep -i -c, git diff --stat print nothing; 2>&1 | head still exposes" {
+  make_oracle
+  local i=0 cmd res want
+  while IFS=$'\t' read -r cmd res want; do
+    i=$((i + 1)); RD="$T/x$i"; make_orun "$RD"; sysinit "$RD" REVIEW
+    tu "$RD" REVIEW "x$i" Bash "$(bash_in "$cmd")" "$(printf '%b' "$res")" false
+    grade "$RD" rc-o
+    [ "$status" -eq 0 ]
+    [ "$(OX)" = "$want" ] || { echo "case $i ($cmd): $(OX) want $want"; return 1; }
+  done <<'CASES'
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | wc -l	4	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh &>/dev/null; echo rc=$?	rc=1	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | grep -i -c planted	1	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>/dev/null | grep --count '^>'	2	diff= read= unknown= exposed=
+git diff --no-index --stat pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	 .claude/scripts/g.sh | 2 +-\n 1 file changed	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | head -40	20c20\n<   if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\n---\n> later	diff=d1 read= unknown= exposed=d1
+CASES
+}
+
+@test "AG-53 KF-046 class 7 (review r1 DISS-C-002): a bare repo-name token as a whole line (a for-list continuation, a list entry) is never exempt" {
+  RD="$T/k3"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
+  RTASK=review-r18 RROOT=ablation-2.0-replication
+  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'for r in \\\\\n  0xHoneyJar/loa\ndo gh api repos/$r/contents; done')")"
+  rgrade "$RD"
+  [ "$status" -eq 0 ]
+  [ "$(G '.contaminated.pattern')" = repo_name ]
+  [ "$(G '.contamination_exempt | length')" = 0 ]
+  RD="$T/k4"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
+  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'cat > repos.txt <<'"'"'EOF'"'"'\n0xHoneyJar/loa\nEOF\nxargs -a repos.txt -I{} gh api repos/{}/pulls')")"
+  rgrade "$RD"
+  [ "$(G '.contaminated.pattern')" = repo_name ]
+  [ "$(G '.contamination_exempt | length')" = 0 ]
+  # a backticked quotation of the name in prose stays PR content (AG-51's second line)
+}
+
 # real_run <fixture name> <run-dir>: a run directory from a trimmed cycle-130 transcript (fixtures/c131-oracle/,
 # made by its trim.py from the read-only run directories): its events, and the later sandbox copy of each path
 # an event names; the task is the real corpus task in the repository's frozen suite roots
~~~~

## I04 — fix-commit — 2026-10-20

- reference: baea80244306
- files: evals/harness/ablation-grade.sh,evals/tests/ablation-grade.bats

Summary:

fix(cycle-131): sprint-263 review round r1b — one-liner python defs, fence lengths, stat-only git diff, |&, grep-family sinks Review dissent run 2 on the r1a diff (12 findings, 3 BLOCKING, all at the edges of r1a; DEC-0643): - recall-vs-defects.sh: a python signature ends at the colon after its closing parenthesis, so `def f(): return 1` ends on its own line (and a header with no terminator falls…

Evidence:

~~~~diff
commit baea80244306d0bee0334ba5f8238777c7cdb1e7
Date: 2026-10-20T12:39:13+11:00

fix(cycle-131): sprint-263 review round r1b — one-liner python defs, fence lengths, stat-only git diff, |&, grep-family sinks

Review dissent run 2 on the r1a diff (12 findings, 3 BLOCKING, all at the edges of r1a; DEC-0643):
- recall-vs-defects.sh: a python signature ends at the colon after its closing parenthesis, so `def f(): return 1`
  ends on its own line (and a header with no terminator falls back to one line); a markdown fence closes only on a
  same-character fence at least as long with nothing after it, and a backtick opener whose info string holds a
  backtick is not a fence (RG-42 extended, RG-43).
- ablation-grade.sh: a stat-only git diff needs a stat flag and none of -p/-u/--patch/--unified/-U<n>; `|&` is one
  pipe with no empty segment; silent sinks include -L / --files-without-match and the egrep/fgrep/rg family
  (AG-52 extended); AG-53's printf now emits a real line continuation.
- Re-grade of the 36 cycle-130 runs on this grader: 36/36 regression, 0 rows changed.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/ablation-grade.sh b/evals/harness/ablation-grade.sh
index 4100de30..7c6765a2 100755
--- a/evals/harness/ablation-grade.sh
+++ b/evals/harness/ablation-grade.sh
@@ -2080,8 +2080,9 @@ def silent_sink(w):
     exe = w[0].rsplit("/", 1)[-1]
     if exe in ("wc", "cmp", "true", "false", "test"):
         return True
-    if exe == "grep":
-        return any(re.fullmatch(r"-[A-Za-z]*[cql][A-Za-z]*", x) or x in ("--count", "--quiet", "--silent", "--files-with-matches")
+    if exe in ("grep", "egrep", "fgrep", "rg"):
+        return any(re.fullmatch(r"-[A-Za-z]*[cqlL][A-Za-z]*", x)
+                   or x in ("--count", "--quiet", "--silent", "--files-with-matches", "--files-without-match")
                    for x in w[1:])
     return False
 
@@ -2180,6 +2181,9 @@ def split_segments(cmd):
             cur.append(ch)          # a redirection (2>&1, >&2, <&0, &>f), not a separator (review r1 DISS-001/C-001)
         elif depth == 0 and ch in "\n;&|":
             pipe = ch == "|" and cmd[i + 1:i + 2] != "|" and cmd[i - 1:i] != "|"
+            if ch == "|" and cmd[i + 1:i + 2] == "&":
+                pipe = True           # `|&` is bash's `2>&1 |`: one pipe, no empty segment (review r2 DISS-C-004)
+                i += 1
             segs.append(("".join(cur), "|" if pipe else ";"))
             cur = []
         else:
@@ -2503,8 +2507,8 @@ def oracle_plan(tool, inp, ws, answer):
             nxt = seg_words(segs[k + 1][0]) if sep == "|" and k + 1 < len(segs) else []
             if DEVNULL.search(seg) or (nxt and silent_sink(nxt)):
                 continue
-            if exe == "git" and any(x in DIFF_STAT_FLAGS for x in w):
-                continue              # a stat-only git diff prints names and counts, not content
+            if exe == "git" and any(x in DIFF_STAT_FLAGS for x in w) and not any(x in ("-p", "-u", "--patch", "--unified") or re.fullmatch(r"-U\d*|--unified=\d+", x) for x in w[1:]):
+                continue              # a stat-only git diff prints names and counts, not content (with -p/-u/--patch it prints both; review r2 DISS-002)
             toks = segment_tokens(seg, vars_, cwd, ws)
             pr_ops = [k_ for k_, (v, c) in enumerate(toks) if c[0] == "pr" and c[1] in ("head", "base")
                       and not v.endswith("head.diff")]
diff --git a/evals/tests/ablation-grade.bats b/evals/tests/ablation-grade.bats
index 0d3b0ce1..1116e74a 100644
--- a/evals/tests/ablation-grade.bats
+++ b/evals/tests/ablation-grade.bats
@@ -1537,7 +1537,7 @@ CASES
   [ "$(G '.oracle_exposed_defects, .oracle_exposed_events, .corpus_sha256' | tr '\n' ' ')" = "null null null " ]
 }
 
-@test "AG-52 oracle redirections (review r1 DISS-001/C-001): 2>&1 | wc -l, &>/dev/null, 2>&1 | grep -i -c, git diff --stat print nothing; 2>&1 | head still exposes" {
+@test "AG-52 oracle redirections (review r1 DISS-001/C-001, r2 DISS-002/C-004/C-008): 2>&1 | wc -l, &>/dev/null, grep -i -c, |& wc, egrep -c, grep -L, git diff --stat print nothing; 2>&1 | head and --stat -p expose" {
   make_oracle
   local i=0 cmd res want
   while IFS=$'\t' read -r cmd res want; do
@@ -1552,14 +1552,18 @@ diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh &>/dev/null; echo rc=$?	r
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | grep -i -c planted	1	diff= read= unknown= exposed=
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>/dev/null | grep --count '^>'	2	diff= read= unknown= exposed=
 git diff --no-index --stat pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	 .claude/scripts/g.sh | 2 +-\n 1 file changed	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh |& wc -l	4	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | egrep -c planted	1	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | grep -L nothing	(standard input)	diff= read= unknown= exposed=
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | head -40	20c20\n<   if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\n---\n> later	diff=d1 read= unknown= exposed=d1
+git diff --no-index --stat -p pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	 g.sh | 2 +-\n@@ -20 +20 @@\n-  if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\n+ later	diff=d1 read= unknown= exposed=d1
 CASES
 }
 
 @test "AG-53 KF-046 class 7 (review r1 DISS-C-002): a bare repo-name token as a whole line (a for-list continuation, a list entry) is never exempt" {
   RD="$T/k3"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
   RTASK=review-r18 RROOT=ablation-2.0-replication
-  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'for r in \\\\\n  0xHoneyJar/loa\ndo gh api repos/$r/contents; done')")"
+  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'for r in \\\n  0xHoneyJar/loa\ndo gh api repos/$r/contents; done')")"   # one backslash before the newline: a real continuation (review r2 DISS-C-009)
   rgrade "$RD"
   [ "$status" -eq 0 ]
   [ "$(G '.contaminated.pattern')" = repo_name ]
~~~~

## I05 — fix-commit — 2026-10-20

- reference: cddec3677a58
- files: evals/harness/ablation-grade.sh,evals/tests/ablation-grade.bats

Summary:

fix(cycle-131): sprint-263 audit round r1c — executed probe lines never class-7 exempt, no workspace pr/head fallback, bounded detector work, one validated corpus-hash open Audit dissent run 1 on the sprint diff (4 findings: 1 HIGH, 2 MEDIUM, 1 LOW; DEC-0644): - ablation-grade.sh: a Bash logical line (heredoc bodies removed) that holds the repo name and a network- or VCS-capable executable word (…

Evidence (first 200 of 252 lines):

~~~~diff
commit cddec3677a58f26e8986f034419f03f559782648
Date: 2026-10-20T13:13:11+11:00

fix(cycle-131): sprint-263 audit round r1c — executed probe lines never class-7 exempt, no workspace pr/head fallback, bounded detector work, one validated corpus-hash open

Audit dissent run 1 on the sprint diff (4 findings: 1 HIGH, 2 MEDIUM, 1 LOW; DEC-0644):
- ablation-grade.sh: a Bash logical line (heredoc bodies removed) that holds the repo name and a network- or
  VCS-capable executable word (git, gh, curl, wget, pip, npm, npx, ssh, scp, nc, docker, rsync, python -c …) is
  never KF-046 class 7 exempt — pr-13 and pr-16 carry `curl … 0xHoneyJar/loa … | bash` lines the old rule would
  have licensed; quoting such a line in notes stays PR content (AG-54). Every agent-controlled dimension of the
  oracle detector is bounded (for-list 64, expansion 256, segment 64 KB, word 4,096 / 512 per segment, result
  lines clipped, difflib skipped above 20,000 lines → grade.json oracle_scan_skipped) (AG-55). corpus_sha256
  hashes the bytes of one O_NOFOLLOW open with an fstat regular-file and size check.
- recall-vs-defects.sh: the $workspace/pr/head fallback is gone unless EVAL_ALLOW_WORKSPACE_HEAD=1;
  details.head_dir_source ∈ env|fixture|workspace|none; above 5,000 headers the ±20 fallback replaces the scope
  map (RG-44).
- sprint.md: Sprint 1 deliverables, criteria and tasks ticked (two criteria annotated: FR-1 AC 4 PARTIAL by
  DEC-0632; FR-3 AC 3 is the Sprint 3 read).
- evals/tests 516/516; the 36-run re-grade on this grader: 36/36 regression, 0 rows changed (as after r1a, r1b).
- Review APPROVED (engineer-feedback.md), audit APPROVED after this round (auditor-sprint-feedback.md).

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/ablation-grade.sh b/evals/harness/ablation-grade.sh
index 7c6765a2..9ea0f455 100755
--- a/evals/harness/ablation-grade.sh
+++ b/evals/harness/ablation-grade.sh
@@ -1807,7 +1807,7 @@ def check_value(tool, field, val, roots):
     if "grimoires/loa/evals/ablation-2.0" in val:
         return "suite_path"
     if "0xhoneyjar/loa" in low:
-        ex = repo_name_exempt(val)
+        ex = repo_name_exempt(val, tool)
         if ex is None:
             return "repo_name"
         EXEMPT_BUF.extend(ex)   # KF-046 class 7: every occurrence is PR content; the scan goes on
@@ -1979,11 +1979,31 @@ def fixture_token_lines():
     return out
 
 
-def repo_name_exempt(val):
-    """→ [(fixture source, fixture line)] when every repo-name occurrence in val is PR content, else None"""
+NET_EXE = {"git", "gh", "curl", "wget", "pip", "pip3", "npm", "npx", "pnpm", "yarn", "ssh", "scp", "sftp", "nc", "ncat",
+           "telnet", "docker", "podman", "rsync", "svn", "hg", "aria2c", "http", "https", "fetch", "gem", "cargo", "go"}
+
+
+def executes_network(line):
+    """a Bash logical line that could reach the network or a VCS remote: a word whose basename is a network- or
+    VCS-capable executable, or python/node/perl/ruby with an inline program (audit r1 DISS-C-001)"""
+    words = re.findall(r"[A-Za-z0-9_./-]+", line)
+    base = [w.rsplit("/", 1)[-1] for w in words]
+    if any(b in NET_EXE for b in base):
+        return True
+    return any(b in ("python", "python3", "node", "perl", "ruby") and ("-c" in words or "-e" in words) for b in base)
+
+
+def repo_name_exempt(val, tool=None):
+    """→ [(fixture source, fixture line)] when every repo-name occurrence in val is PR content, else None.
+    A Bash command is executed text: an occurrence on a logical line that could reach the network or a VCS remote
+    is never exempt, whatever the fixture holds (pr-13 and pr-16 carry `curl … 0xHoneyJar/loa … | bash` lines)."""
     fl = fixture_token_lines()
     if not fl:
         return None
+    if tool == "Bash":   # the executed text is the command with its heredoc bodies removed (a quoted line in notes is not run)
+        for line in strip_heredocs(val).replace("\\\n", " ").split("\n"):
+            if REPO_TOKEN.search(line) and executes_network(line):
+                return None
     hits = []
     for line in val.replace("\\\n", " ").split("\n"):   # a backslash-continued command is one logical line
         for m in REPO_TOKEN.finditer(line):
@@ -2009,11 +2029,25 @@ def corpus_sha256(t):
     """sha256 of the review corpus's SHA256SUMS (the directory above the key's manifests/), null when absent"""
     import hashlib
     p = os.path.join(os.path.dirname(os.path.dirname(t.key_path)), "SHA256SUMS")
-    text = read_regular(p, READ_CAP, whole=True)
-    if text is None:
+    try:   # one O_NOFOLLOW open, fstat regular + size bound, hash those bytes (audit r1 DISS-C-004)
+        fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | getattr(os, "O_CLOEXEC", 0))
+    except OSError:
         return None
-    with open(p, "rb") as f:
-        return hashlib.sha256(f.read()).hexdigest()
+    try:
+        st = os.fstat(fd)
+        if not stat.S_ISREG(st.st_mode) or st.st_size > READ_CAP:
+            return None
+        h = hashlib.sha256()
+        while True:
+            b = os.read(fd, 1 << 20)
+            if not b:
+                break
+            h.update(b)
+        return h.hexdigest()
+    except OSError:
+        return None
+    finally:
+        os.close(fd)
 
 
 # ------------------------------------------------------------------ oracle detector (1.3.0, D-1.3, KF-049)
@@ -2056,6 +2090,9 @@ def corpus_sha256(t):
 # A LOWER BOUND, like the contamination scan: a paraphrase, a copy made by a program and read later, or a
 # path built at run time is not seen.
 ORACLE_PHASES = ("BARE", "REVIEW", "AUDIT")
+# bounds on agent-authored input (audit r1 DISS-C-003): every dimension the graded session controls is capped
+FORLIST_CAP, EXPAND_CAP, SEG_CAP, WORD_CAP, WORDS_CAP, LINE_CAP, LINES_CAP, DIFF_LINES_CAP = 64, 256, 65536, 4096, 512, 4096, 20000, 20000
+ORACLE_SKIPPED = []   # answer paths whose later-line map was skipped (a side over DIFF_LINES_CAP lines)
 DIFF_EXE = {"diff", "sdiff", "comm"}
 READ_EXE = {"cat", "sed", "awk", "grep", "head", "tail", "less", "python3"}
 ANSWER_TOP = ".claude/"
@@ -2228,6 +2265,8 @@ def expand(tok, vars_):
             changed = True
             for v in vars_[name]:
                 nxt.append(o[:m.start()] + v + o[m.end():])
+            if len(nxt) > EXPAND_CAP:
+                return []             # a for-list product past the cap resolves nothing (audit r1 DISS-C-003)
         outs = nxt
         if not changed:
             break
@@ -2264,13 +2303,20 @@ def ws_targets(rel, answer, directory_ok):
 
 
 def segment_tokens(seg, vars_, cwd, ws):
-    """every path-shaped token of a segment (inside process substitutions too), expanded and classified"""
+    """every path-shaped token of a segment (inside process substitutions too), expanded and classified;
+    bounded against agent-authored bulk (audit r1 DISS-C-003): a segment over SEG_CAP bytes, a word over
+    WORD_CAP characters or past the WORDS_CAP-th word is not read"""
     out = []
-    for m in PATHISH.finditer(seg):
-        for v in expand(m.group(0), vars_):
-            c = classify(v, cwd, ws)
-            if c is not None:
-                out.append((v, c))
+    if len(seg) > SEG_CAP:
+        return out
+    for word in seg.split()[:WORDS_CAP]:
+        if len(word) > WORD_CAP:
+            continue
+        for m in PATHISH.finditer(word):
+            for v in expand(m.group(0), vars_):
+                c = classify(v, cwd, ws)
+                if c is not None:
+                    out.append((v, c))
     return out
 
 
@@ -2362,6 +2408,9 @@ def oracle_scan(t, run_dir):
         if not live[f] or hd is None:
             continue
         hl, cl = hd.split("\n"), cur.split("\n")
+        if len(hl) > DIFF_LINES_CAP or len(cl) > DIFF_LINES_CAP:
+            ORACLE_SKIPPED.append(f)  # no later-line map for a huge copy: the read form cannot fire for it (audit r1 DISS-C-003)
+            continue
         for pos, sites, _mm in by_file[f]:
             near_text[(f, pos)] = [hl[L - 1].strip() for s_ in sites for L in range(s_ - 3, s_ + 4)
                                    if 1 <= L <= len(hl) and len(hl[L - 1].strip()) >= 8]
@@ -2415,7 +2464,7 @@ def oracle_scan(t, run_dir):
                     i0, plan = uses.pop(blk["tool_use_id"])
                     if blk.get("is_error") is True:
                         continue          # the tool failed (a refused command, a hook block): nothing printed
-                    res = result_text(blk)
+                    res = "\n".join(l[:LINE_CAP] for l in result_text(blk).split("\n")[:LINES_CAP])
                     dtargets = sorted({f for how, f in plan if how.startswith("diff") and live.get(f)})
                     rtargets = sorted({f for how, f in plan if how == "read" and live.get(f)})
                     if dtargets and res.strip():
@@ -2490,7 +2539,7 @@ def oracle_plan(tool, inp, ws, answer):
             words = []
             for x in m.group(2).split():
                 words += expand(x.strip("'\""), vars_)
-            vars_[m.group(1)] = words
+            vars_[m.group(1)] = words[:FORLIST_CAP]
             continue
         if not w:
             continue
@@ -2572,7 +2621,7 @@ def grade(t, run_dir, frozen):
          "diff_lines": None, "files_changed": None, "symlinks_dropped": 0, "harness_files_removed": 0,
          "oversized_files_skipped": 0, "history_probes": 0, "heredoc_interpreters": 0, "contaminated": None,
          "contamination_exempt": [], "oracle_exposed_defects": None, "oracle_exposed_unknown": None,
-         "oracle_exposed_events": None, "oracle_exposed_by_form": None, "corpus_sha256": None}
+         "oracle_exposed_events": None, "oracle_exposed_by_form": None, "oracle_scan_skipped": None, "corpus_sha256": None}
     acc = {"review": None, "audit": None}
     SNAPSHOT_LINKS_DROPPED[0] = 0
     OVERSIZED[0] = 0
@@ -2652,8 +2701,10 @@ def grade(t, run_dir, frozen):
             g["symlinks_dropped"] = copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
         g["recall"], g["false_positives"] = grade_recall(t, run_dir, grading)
         g["corpus_sha256"] = corpus_sha256(t)
+        ORACLE_SKIPPED.clear()
         (g["oracle_exposed_defects"], g["oracle_exposed_unknown"], g["oracle_exposed_events"],
          g["oracle_exposed_by_form"]) = oracle_scan(t, run_dir)
+        g["oracle_scan_skipped"] = sorted(set(ORACLE_SKIPPED))
         key_cr = any((d.get("severity") or "").lower() in ("high", "critical") for d in t.key.get("defects") or [])
         for gate, v in (("review", v_review), ("audit", v_audit)):
             if v is not None:
diff --git a/evals/tests/ablation-grade.bats b/evals/tests/ablation-grade.bats
index 1116e74a..7100f899 100644
--- a/evals/tests/ablation-grade.bats
+++ b/evals/tests/ablation-grade.bats
@@ -1576,6 +1576,52 @@ CASES
~~~~

## I06 — fix-commit — 2026-10-20

- reference: c0d429074f26
- files: evals/harness/ablation-report.py,evals/tests/ablation-report.bats

Summary:

fix(cycle-131): sprint-264 review round r2a — eval_only derived from oracle_open and type-checked in pipeline-run; the report names evaluation-only arms Review dissent run 1 on e93a040a..0281ea57 (4 advisories, 0 blocking): - pipeline-run.sh treats an arm whose toggles set oracle_open: true as evaluation-only whatever the suite says, and refuses a present eval_only that is not a JSON boolean (DIS…

Evidence:

~~~~diff
commit c0d429074f263b22f3643eb44bfd4a38eac7b6bf
Date: 2026-10-20T14:49:27+11:00

fix(cycle-131): sprint-264 review round r2a — eval_only derived from oracle_open and type-checked in pipeline-run; the report names evaluation-only arms

Review dissent run 1 on e93a040a..0281ea57 (4 advisories, 0 blocking):
- pipeline-run.sh treats an arm whose toggles set oracle_open: true as evaluation-only whatever the suite says, and
  refuses a present eval_only that is not a JSON boolean (DISS-C-002; pipeline-run.bats case added).
- ablation-report.py prints 'Evaluation-only arms (not components): <arm> (<n> rows) …' under the decisions and
  records them in report.json (DISS-C-004; AR-12 asserts the line).
- DISS-C-001 (task files not in the dissent diff) is the dissent driver's path exclusion, not a missing commit;
  DISS-C-003 (hand-maintained toggle vocabulary) → bead bd-gdl5s.
- KF-051 (Fable refusal fallback mid-phase) recorded; DEC-0646, DEC-0647.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/ablation-report.py b/evals/harness/ablation-report.py
index dafe3e62..b192da6c 100755
--- a/evals/harness/ablation-report.py
+++ b/evals/harness/ablation-report.py
@@ -1925,6 +1925,11 @@ def build(args):
     h1_comps, a4 = P["h1_comps"], P["a4"]
 
     k = len(components)
+    eval_only_arms = [a["id"] for a in arms if a.get("eval_only") is True and not a.get("absent")]
+    eval_only_counts = {aid: sum(1 for r in P.get("rows", []) if r.get("arm") == aid) for aid in eval_only_arms}
+    eval_only_line = ("Evaluation-only arms (not components): " +
+                      (", ".join(f"{aid} ({n} rows)" for aid, n in eval_only_counts.items()) if eval_only_counts else "none") +
+                      " — read by their own pre-registered contrast, never by a decision here.")
     efp = k * (1.0 - args.level) / 2.0
     efp_line = (f"Expected false positives at level {args.level:.2f} over {k} components: "
                 f"{k} × (1 − {args.level:.2f}) / 2 = {efp:.2f} one-sided per direction "
@@ -1996,6 +2001,7 @@ def build(args):
     L("")
     render_decisions(L, P, absent, rules)
     L(efp_line)
+    L(eval_only_line)
     L("")
 
     L("## Per-arm detail")
@@ -2171,7 +2177,8 @@ def build(args):
                     "evidence": a.get("evidence")} for a in absent],
         "h1": h1_json(P, rules),
         "a4": a4_json(P, rules),
-        "expected_false_positives": {"components": k, "per_direction": j6(efp), "line": efp_line},
+        "expected_false_positives": {"components": k, "per_direction": j6(efp), "line": efp_line,
+                                     "eval_only_arms": eval_only_counts},
         "arms": arms_json(metrics),
         "exclusions": exclusions_json(P),
         "listed": listed_json(P),
diff --git a/evals/tests/ablation-report.bats b/evals/tests/ablation-report.bats
index cd129ad1..b15fbcfd 100644
--- a/evals/tests/ablation-report.bats
+++ b/evals/tests/ablation-report.bats
@@ -187,6 +187,7 @@ report() {  # report <scenario> <out-prefix> [extra args]
 
 @test "AR-12 the expected-false-positive sentence and the Method section quoting the suite rules block verbatim" {
   grep -qF 'Expected false positives at level 0.90 over 9 components: 9 × (1 − 0.90) / 2 = 0.45 one-sided per direction (0.90 in either direction); no multiple-comparison correction is applied (multiple_comparisons: none).' "$FX/main/report.md"   # 9 = a2 … a7 + the three cycle-131 control arms; a1_full_openmount is eval_only and not a component
+  grep -qF 'Evaluation-only arms (not components): a1_full_openmount (0 rows) — read by their own pre-registered contrast, never by a decision here.' "$FX/main/report.md"   # review r1 DISS-C-004
   python3 -I - "$SUITE" "$FX/main/report.md" <<'PY'
 import re, sys
 suite = open(sys.argv[1], encoding="utf-8").read().splitlines()
~~~~

## I07 — fix-commit — 2026-10-20

- reference: 798d88cfc920
- files: evals/harness/ablation-report.py,evals/tests/ablation-report.bats

Summary:

fix(cycle-131): sprint-264 audit round r2b — toggles.oracle_open held to the JSON-boolean rule; the report derives evaluation-only status from the toggle and refuses an open oracle without the flag Audit dissent run on e93a040a..c0d42907 (2 MEDIUM, 1 LOW): - pipeline-run.sh refuses a present toggles.oracle_open that is not a JSON boolean, so the strict eval_only guard and the loose mount read can…

Evidence:

~~~~diff
commit 798d88cfc920a95ce896a527145b21ca72d0ab18
Date: 2026-10-20T15:01:43+11:00

fix(cycle-131): sprint-264 audit round r2b — toggles.oracle_open held to the JSON-boolean rule; the report derives evaluation-only status from the toggle and refuses an open oracle without the flag

Audit dissent run on e93a040a..c0d42907 (2 MEDIUM, 1 LOW):
- pipeline-run.sh refuses a present toggles.oracle_open that is not a JSON boolean, so the strict eval_only guard
  and the loose mount read can never disagree on a quoted "true" (DISS-C-001; pipeline-run.bats case).
- ablation-report.py: is_eval_only(a) = the flag or toggles.oracle_open is True; an open-oracle arm without
  eval_only: true raises Fail before any report is written (DISS-C-002; AR-12b).
- DISS-C-003 (inheritable batch-context env var) accepted as the designed accident guard → bead bd-st02i.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/ablation-report.py b/evals/harness/ablation-report.py
index b192da6c..d6a5cc1b 100755
--- a/evals/harness/ablation-report.py
+++ b/evals/harness/ablation-report.py
@@ -1910,7 +1910,12 @@ def build(args):
 
     # components: every runnable arm but the two baselines; an eval_only arm (cycle-131 FR-5: the open-mount
     # oracle A/B) is an evaluation control, never a shipped-default decision, so it is not a component here
-    components = [a["id"] for a in arms if a["id"] not in (CONTROL, BARE) and not a.get("absent") and a.get("eval_only") is not True]
+    def is_eval_only(a):   # the flag, or the property it protects (audit r1 DISS-C-002)
+        return a.get("eval_only") is True or (a.get("toggles") or {}).get("oracle_open") is True
+    for a in arms:
+        if not a.get("absent") and (a.get("toggles") or {}).get("oracle_open") is True and a.get("eval_only") is not True:
+            raise Fail(f"suite arm {a.get('id')} opens the oracle (toggles.oracle_open: true) without eval_only: true")
+    components = [a["id"] for a in arms if a["id"] not in (CONTROL, BARE) and not a.get("absent") and not is_eval_only(a)]
     absent = [a for a in arms if a.get("absent")]
     seed = args.seed
     groups, primary, unversioned = partition(rows, args.suite_version, mans,
@@ -1925,7 +1930,7 @@ def build(args):
     h1_comps, a4 = P["h1_comps"], P["a4"]
 
     k = len(components)
-    eval_only_arms = [a["id"] for a in arms if a.get("eval_only") is True and not a.get("absent")]
+    eval_only_arms = [a["id"] for a in arms if is_eval_only(a) and not a.get("absent")]
     eval_only_counts = {aid: sum(1 for r in P.get("rows", []) if r.get("arm") == aid) for aid in eval_only_arms}
     eval_only_line = ("Evaluation-only arms (not components): " +
                       (", ".join(f"{aid} ({n} rows)" for aid, n in eval_only_counts.items()) if eval_only_counts else "none") +
diff --git a/evals/tests/ablation-report.bats b/evals/tests/ablation-report.bats
index b15fbcfd..f0e8bbd5 100644
--- a/evals/tests/ablation-report.bats
+++ b/evals/tests/ablation-report.bats
@@ -324,6 +324,14 @@ PY
   grep -qF 'degradation guard first' "$T/r.md"
 }
 
+@test "AR-12b (audit r1 DISS-C-002) the report refuses a suite arm that opens the oracle without eval_only, and counts an eval_only arm by its toggle too" {
+  SUITE_SRC="$SUITE" yq -o=json '.arms += [{"id": "x_open", "label": "XO", "task_types": ["review-catch"], "toggles": {"oracle_open": true}, "took_effect": ["integrity_clean"]}]' "$SUITE" > "$T/bad-suite.json"
+  run python3 -I "$REPORT" --runs "$FX/main/runs.jsonl" --manifests "$FX/main/manifests" --suite "$T/bad-suite.json" --out "$T/bad.md"
+  [ "$status" -ne 0 ]
+  grep -q "suite arm x_open opens the oracle (toggles.oracle_open: true) without eval_only: true" <<<"$output"
+  [ ! -e "$T/bad.md" ]
+}
+
 @test "AR-23 two suite_versions are never pooled: main sections on v2 (catch-rate H1, pass rate and A4 not testable), v1 in its own section; --suite-version 1 flips the primary" {
   J="$FX/versions/report.json"; M="$FX/versions/report.md"
   [ "$(jq -r .primary_suite_version "$J")" = "2" ]
~~~~

## I08 — fix-commit — 2026-10-20

- reference: aac80f4cfea6
- files: evals/harness/ablation-grade.sh,evals/tests/ablation-grade.bats,evals/tests/fixtures/ablation-pipeline-stub.sh

Summary:

fix(cycle-131): PR #1286 Bridgebuilder round r4 — the closed mount refuses an unavailable fix commit (F001); grader 1.3.1 scans error-marked tool results (F002); 63 re-grades unchanged F001 (HIGH, accepted): `lib/sandbox-mount.sh overlay_answer_paths` exits 2 before writing anything when fixture.yaml's fix_commit is not in the source tree. Sprint 263 logged fix_commit_unavailable, overlaid the PR…

Evidence (first 200 of 213 lines):

~~~~diff
commit aac80f4cfea6c8e865ad194f713efd6cf1f8804d
Date: 2026-10-20T22:13:56+11:00

fix(cycle-131): PR #1286 Bridgebuilder round r4 — the closed mount refuses an unavailable fix commit (F001); grader 1.3.1 scans error-marked tool results (F002); 63 re-grades unchanged

F001 (HIGH, accepted): `lib/sandbox-mount.sh overlay_answer_paths` exits 2 before writing anything when
fixture.yaml's fix_commit is not in the source tree. Sprint 263 logged fix_commit_unavailable, overlaid the
PR paths only and `check_mount_closed` called the mount closed with the fix-only paths still at the later
copy. `check_mount_closed` and `took-effect.sh` rule oracle_closed now fail on overlay_fix_commit=unavailable.
Premise check: overlay_fix_commit=available on all 18 closed-mount cycle-131 runs, none on the 4 without a
fix commit — no recorded run took this path.

F002 (MEDIUM, accepted): grader 1.3.1. A differing diff exits 1 and Claude Code marks the result is_error
with the output after an "Exit code N" line; 1.3.0 skipped every such result. The detector now strips that
line and scans the rest: the diff form needs printed ranges near a planted site (no must_match-only credit
from an error result), the read form later-only text, and an error-marked section without ranges is never
oracle_exposed_unknown. Recall and contamination unchanged. Re-graded under 1.3.1, the 36 cycle-130 and
27 cycle-131 review-catch runs are identical on every oracle field, recall and contamination (63/63); the
26 error-marked results carrying diff ranges all compare pr/base with pr/head or read head.diff. The pinned
1.3.0 rows stay the main read (DEC-0648); the 1.3.1 grades are a labelled sensitivity
(~/.cache/loa/cycle-131/regrade-131/compare.tsv).

Tests: sandbox-mount.bats (the unavailable-commit test now expects the refusal, an untouched sandbox and a
failing check), took-effect.bats (overlay_fix_commit=unavailable FAIL clause), ablation-grade.bats (AG-48
loses the is_error row; AG-56 covers error-marked differing diffs, a hook block, a tool error, unranged
text, the read form and the unchanged non-error unknown case; version asserts 1.3.1).

The check keeps its evidence rule only (overlay_fix_commit=unavailable fails); a recomputation rule was dropped
because a check-time repository without the fix commit already fails clause (a) on the path count, and would
have turned a shallow post-run clone into a false FAIL. The runner tests' pipeline stub overlays from a
fixture copy without fix_commit when its throwaway source tree lacks the commit (RAB-c131-2 on pr-17/pr-18).

Also: grimoires/loa/REPO-MAP.md regenerated (repo-map-gen.sh) — CI's BATS Tests on a3289c2b failed only on
`repo-map: --validate passes against the committed REPO-MAP.md` (stale after the Sprint 263 edits to
adversarial-review.sh and its resources; the separate REPO-MAP Drift Gate workflow had passed).

Records: DEC-0655; KF-049 attempt row; CHANGELOG "### Fixed"; suite README. Bead bd-cxdsm.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/ablation-grade.sh b/evals/harness/ablation-grade.sh
index 9ea0f455..a70e62eb 100755
--- a/evals/harness/ablation-grade.sh
+++ b/evals/harness/ablation-grade.sh
@@ -232,6 +232,12 @@
 #    (1.3.0: the oracle detector below; null for build tasks), corpus_sha256 (1.3.0: sha256 of the review
 #    corpus SHA256SUMS; null for build tasks or without the file); review-catch recall also carries
 #    recall_pm3, missed_pm3, recall_pm3_v1, missed_pm3_v1, v1_manifest, credits_function_only, rule}
+# grader 1.3.1 (cycle-131 PR #1286 Bridgebuilder F002): the oracle detector scans error-marked tool results. A
+# diff exits 1 on differences and Claude Code then marks the result is_error with the output after an "Exit code N"
+# line, so 1.3.0 never saw a differing diff's hunks. 1.3.1 strips that line and scans the rest: the diff form
+# needs printed ranges near a site (must_match alone does not count there), the read form later-only text; an
+# error-marked section without ranges is never exposed_unknown (a refusal or a hook block names the command's
+# paths and prints no diff). Recall, contamination and every other field are unchanged from 1.3.0.
 # grader 1.3.0 (cycle-131 Sprint 263 Tasks 1.3, 1.4; DEC-0615, DEC-0616, DEC-0617): three recall results
 # (the same-scope rule, recall-vs-defects.sh 1.3.0), numeric dissent anchors, corpus_sha256, the oracle
 # detector (diff and read forms, KF-049) and the KF-046 class 7 line-level exemption. recall_pm3_v1 equals
@@ -346,7 +352,7 @@ import argparse, configparser, difflib, filecmp, fnmatch, json, os, re, shlex, s
 # TERM; names carry this pid, so a later grade never collides)
 signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(143))
 
-GRADER_VERSION = "1.3.0"
+GRADER_VERSION = "1.3.1"
 SCRIPT_DIR, REPO_ROOT, DOCKER_DEFAULT = sys.argv[1], sys.argv[2], sys.argv[3]
 SPRINT = "sprint-1"
 _t = os.environ.get("LOA_EVAL_GRADE_TIMEOUT_S", "")
@@ -2100,6 +2106,7 @@ SEG_KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "{", "(",
 PATHISH = re.compile(r"[A-Za-z0-9_./@%+,:=~$-]*[A-Za-z0-9_./@%+:~$-]")
 HUNK_U = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", re.M)
 HUNK_N = re.compile(r"^(\d+)(?:,(\d+))?([acd])(\d+)(?:,(\d+))?\s*$", re.M)
+EXIT_CODE_LINE = re.compile(r"\AExit code \d+\n?")   # 1.3.1: Claude Code's preamble on a failed Bash tool result
 ERR_LINE = re.compile(r"^(?:diff|sdiff|comm|git|cat|grep|sed|head|tail|awk|less):|^(?:fatal|error|warning):|"
                       r"No such file|Is a directory|hook error|BLOCKED|^\s*$|^\s*(?:rc|exit)\s*=\s*\d+\s*$")
 DIFF_BODY = re.compile(r"^[<>+\- @\\0-9]|^---$")
@@ -2462,9 +2469,14 @@ def oracle_scan(t, run_dir):
                         uses[blk["id"]] = (i, plan)
                 elif ev.get("type") == "user" and blk.get("type") == "tool_result" and blk.get("tool_use_id") in uses:
                     i0, plan = uses.pop(blk["tool_use_id"])
-                    if blk.get("is_error") is True:
-                        continue          # the tool failed (a refused command, a hook block): nothing printed
-                    res = "\n".join(l[:LINE_CAP] for l in result_text(blk).split("\n")[:LINES_CAP])
+                    # 1.3.1 (PR #1286 F002): a failed tool (diff exits 1 on differences, a refusal, a hook block) still
+                    # carries its output after an "Exit code N" line; scan it, but no unknown and no must_match-only
+                    # credit from it — a refusal names the command's paths without printing a diff
+                    errored = blk.get("is_error") is True
+                    res = result_text(blk)
+                    if errored:
+                        res = EXIT_CODE_LINE.sub("", res, count=1)
+                    res = "\n".join(l[:LINE_CAP] for l in res.split("\n")[:LINES_CAP])
                     dtargets = sorted({f for how, f in plan if how.startswith("diff") and live.get(f)})
                     rtargets = sorted({f for how, f in plan if how == "read" and live.get(f)})
                     if dtargets and res.strip():
@@ -2477,7 +2489,7 @@ def oracle_scan(t, run_dir):
                                 for pos, sites, mm in by_file.get(f, []):
                                     ranged = any(near(sites, lo, hi) for lo, hi in rs)
                                     own = any(x in sec for x in near_text.get((f, pos), []))
-                                    if (ranged and own) or (mm and mm in sec):
+                                    if (ranged and own) or (not errored and mm and mm in sec):
                                         note(label, i0, "diff", f, pos)
                         for f, secs in secs_by.items():
                             for sec in secs:
@@ -2487,10 +2499,10 @@ def oracle_scan(t, run_dir):
                                 rs = ranges_of(sec, plan_sides(plan, f))
                                 hit_any = False
                                 for pos, sites, mm in by_file.get(f, []):
-                                    if any(near(sites, lo, hi) for lo, hi in rs) or (mm and mm in sec):
+                                    if any(near(sites, lo, hi) for lo, hi in rs) or (not errored and mm and mm in sec):
                                         note(label, i0, "diff", f, pos)
                                         hit_any = True
-                                if not rs and not hit_any:
+                                if not rs and not hit_any and not errored:
                                     for pos, _s, _m in by_file.get(f, []):
                                         note(label, i0, "exposed_unknown", f, pos)
                     single = len({f for how, f in plan if how == "read"}) == 1
diff --git a/evals/tests/ablation-grade.bats b/evals/tests/ablation-grade.bats
index 7100f899..0f778863 100644
--- a/evals/tests/ablation-grade.bats
+++ b/evals/tests/ablation-grade.bats
@@ -1146,7 +1146,7 @@ bash_case() {
   [ "$status" -eq 0 ]
   [ "$(G '.contaminated')" = null ]
   [ "$(G '.heredoc_interpreters')" = 5 ]
-  [ "$(G '.grader_version')" = 1.3.0 ]
+  [ "$(G '.grader_version')" = 1.3.1 ]
 }
 
 # --- grader 1.2.12: the collision removal reaches only pytest-collectable, package-less test modules --------------
@@ -1416,7 +1416,7 @@ OX() { jq -r '"diff=\(.oracle_exposed_by_form.diff | join(",")) read=\(.oracle_e
   printf 'pr/head/.claude/scripts/g.sh:26 the option guard\n' > "$RD/sandbox/review.md"   # 6 from O1, inside check()
   grade "$RD" rc-o
   [ "$status" -eq 0 ]
-  [ "$(G '.grader_version')" = 1.3.0 ]
+  [ "$(G '.grader_version')" = 1.3.1 ]
   [ "$(G '.recall | "\(.recall) \(.recall_pm3) \(.recall_pm3_v1) \(.v1_manifest) \(.rule)"')" = "0.3333 0.0 0.0 false pm3_or_same_function" ]
   [ "$(G '.recall | "\(.credits_function_only | join(",")) \(.missed | join(",")) \(.missed_pm3 | join(",")) \(.missed_pm3_v1 | join(","))"')" = "d1 d2,d3 d1,d2,d3 d1,d2,d3" ]
   [ "$(G '.recall.defects_caught')" = 1 ]
@@ -1479,7 +1479,7 @@ CASES
   [ "$(G '.oracle_exposed_events | length')" = 0 ]
 }
 
-@test "AG-48 oracle non-hits: diff -q, --brief, the word head.diff, cat pr/head.diff, a diff piped to wc or grep -c, >/dev/null, an is_error result, pr/ vs pr/" {
+@test "AG-48 oracle non-hits: diff -q, --brief, the word head.diff, cat pr/head.diff, a diff piped to wc or grep -c, >/dev/null, pr/ vs pr/" {
   make_oracle
   local i=0 cmd res err
   while IFS=$'\t' read -r cmd res err; do
@@ -1497,12 +1497,46 @@ diff pr/head.diff .claude/scripts/g.sh	20c20	false
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh | wc -l	4	false
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh | grep -c '^[<>]'	3	false
 diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh >/dev/null; echo rc=$?	rc=1	false
-diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	20c20\n< a\n---\n> b	true
 diff pr/base/.claude/scripts/g.sh pr/head/.claude/scripts/g.sh	20c20\n< a\n---\n> b	false
 cat > /tmp/notes.md <<'EOF'\ndiff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh\nEOF	20c20	false
 CASES
 }
 
+@test "AG-56 grader 1.3.1 error-marked results (PR #1286 F002): a differing diff (exit 1) exposes in normal and unified form, so does a read; a refusal, a tool error or unranged text naming the paths is neither a hit nor unknown" {
+  make_oracle
+  local i=0 cmd res want
+  while IFS=$'\t' read -r cmd res want; do
+    i=$((i + 1)); RD="$T/e$i"; make_orun "$RD"; sysinit "$RD" REVIEW
+    tu "$RD" REVIEW "e$i" Bash "$(bash_in "$cmd")" "$(printf '%b' "$res")" true
+    grade "$RD" rc-o
+    [ "$status" -eq 0 ]
+    [ "$(G '.grader_version')" = 1.3.1 ]
+    [ "$(OX)" = "$want" ] || { echo "case $i ($cmd): $(OX) want $want"; return 1; }
+  done <<'CASES'
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\n20c20\n< a\n---\n> b	diff=d1 read= unknown= exposed=d1
+diff -u pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\n--- pr/head/.claude/scripts/g.sh\n+++ .claude/scripts/g.sh\n@@ -20 +20 @@\n-a\n+b	diff=d1 read= unknown= exposed=d1
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 2\nBLOCKED by hook FR-9: diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh compares the mount	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 2\ndiff: .claude/scripts/g.sh: Permission denied	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\nleft text | right text	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	Exit code 1\nrefused: the sandbox forbids comparing .claude/scripts/g.sh with pr/head/.claude/scripts/g.sh\nif [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi	diff= read= unknown= exposed=
+CASES
+  # the read form on an error-marked result
+  RD="$T/er"; make_orun "$RD"; sysinit "$RD" REVIEW
+  tu "$RD" REVIEW er Bash "$(bash_in 'cat .claude/scripts/g.sh; false')" "$(printf 'Exit code 1\n%s\n' "$LATER20")" true
+  grade "$RD" rc-o
+  [ "$(OX)" = "diff= read=d1 unknown= exposed=d1" ]
+  # the same unranged text on a result not marked as an error is still unknown (unchanged from 1.3.0)
+  RD="$T/eu"; make_orun "$RD"; sysinit "$RD" REVIEW
+  tu "$RD" REVIEW eu Bash "$(bash_in 'diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh')" "left text | right text" false
+  grade "$RD" rc-o
+  [ "$(OX)" = "diff= read= unknown=d1,d2 exposed=" ]
+  # the event record names the error-marked result like any other
+  RD="$T/ee"; make_orun "$RD"; sysinit "$RD" AUDIT
+  tu "$RD" AUDIT ee Bash "$(bash_in 'diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh')" "$(printf 'Exit code 1\n20c20\n< a\n---\n> b')" true
+  grade "$RD" rc-o
+  [ "$(G '.oracle_exposed_events[0] | "\(.phase) \(.event) \(.how) \(.path)"')" = "AUDIT 2 diff .claude/scripts/g.sh" ]
+}
+
 @test "AG-49 oracle read form: a later-only line near a site in a Bash read or a Read result exposes; the PR copy, a line far from every site and a closed mount do not" {
   make_oracle
   RD="$T/r1"; make_orun "$RD"; sysinit "$RD" REVIEW
diff --git a/evals/tests/fixtures/ablation-pipeline-stub.sh b/evals/tests/fixtures/ablation-pipeline-stub.sh
index 092c8d41..76a5fb8b 100755
--- a/evals/tests/fixtures/ablation-pipeline-stub.sh
+++ b/evals/tests/fixtures/ablation-pipeline-stub.sh
@@ -109,6 +109,14 @@ if [[ "$KIND" == review-catch && "$(jq -r '.toggles.loa_mount' <<<"$DEF")" != fa
    && [[ "$MODE" != bad_overlay ]]; then
~~~~
