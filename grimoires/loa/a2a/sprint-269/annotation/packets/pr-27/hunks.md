# Hunks — pr-27

The later fix changed 28 region(s) in 4 of the change's 35 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — evals/graders/recall-vs-defects.sh — head lines 77–78

Head context (head/evals/graders/recall-vs-defects.sh, lines 65–90):

~~~~text
    65 | #   the line before the next header at the same or lower indentation (markdown: the
    66 | #   same or a higher heading level), else to the end of the file, and no further than
    67 | #   its own end (end-of-definition detection): bash and bats — the first `}` line at
    68 | #   the header's indentation (a one-line `f() { …; }` ends on its header); python —
    69 | #   the last line before the first later non-blank, non-comment line indented no
    70 | #   deeper than the def. Nested definitions resolve to the innermost (the latest
    71 | #   header whose definition holds the line); a line after a definition's end and
    72 | #   before the next header is top-level.
    73 | #   Caps: a definition longer than 400 lines, or a file type with no definition
    74 | #   regex (yaml, json, txt, tsv, …), falls back to ±20 lines around the site (and a
    75 | #   cited line in such a definition has no scope); a site outside every definition
    76 | #   (top-level code, text before the first heading) has no scope (±3 only).
>   77 | #   Head directory: $EVAL_HEAD_DIR, else <manifest dir>/../<fixture>/head, else
>   78 | #   <workspace>/pr/head; with none, or a file absent from it, (ii) never credits.
    79 | #   Three results in details, each with detected[] / missed[] (defect ids):
    80 | #     recall_pm3_v1  the 1.2.0 rule against <manifest dir>/v1/<fixture>.json (the
    81 | #                    original anchors); the current manifest when v1/ has none
    82 | #                    (v1_manifest false)
    83 | #     recall_pm3     the 1.2.0 rule against the current manifest
    84 | #     recall         (i) or (ii) on valid citations against the current manifest —
    85 | #                    pass and score follow it
    86 | #   credits_function_only: ids in detected and not in detected_pm3; rule:
    87 | #   "pm3_or_same_function". findings_cited / findings_refuted / false_positives read
    88 | #   the parsed citations before the validity rules, as in 1.2.0.
    89 | #
    90 | # Clean fixtures (0 planted defects) measure FALSE POSITIVES: the LOA-VERDICT
~~~~

The change from head to the fix:

~~~~diff
@@ -77,2 +77,3 @@
-#   Head directory: $EVAL_HEAD_DIR, else <manifest dir>/../<fixture>/head, else
-#   <workspace>/pr/head; with none, or a file absent from it, (ii) never credits.
+#   Head directory: $EVAL_HEAD_DIR, else <manifest dir>/../<fixture>/head, else — only under
+#   EVAL_ALLOW_WORKSPACE_HEAD=1 — <workspace>/pr/head (the graded agent's own copy; details.head_dir_source
+#   says which was used); with none, or a file absent from it, (ii) never credits.
~~~~

## H02 — evals/graders/recall-vs-defects.sh — head lines 132–141

Head context (head/evals/graders/recall-vs-defects.sh, lines 120–153):

~~~~text
   120 | 
   121 | review="$workspace/$review_name"
   122 | executor="$workspace/.eval/executor.json"
   123 | 
   124 | if [[ ! -f "$review" ]]; then
   125 |   printf '{"pass":false,"score":0,"details":{"error":"review file not found: %s","planted":%s,"detected":[],"recall":0},"grader_version":"1.3.0"}\n' \
   126 |     "$review_name" "$(jq '.defects | length' "$manifest")"
   127 |   exit 1
   128 | fi
   129 | 
   130 | manifest_v1="$MANIFEST_DIR/v1/$fixture.json"
   131 | [[ -f "$manifest_v1" && ! -L "$manifest_v1" ]] || manifest_v1=""
>  132 | head_dir="${EVAL_HEAD_DIR:-}"
>  133 | if [[ -z "$head_dir" ]]; then
>  134 |   if [[ -d "$MANIFEST_DIR/../$fixture/head" ]]; then head_dir="$MANIFEST_DIR/../$fixture/head"
>  135 |   elif [[ -d "$workspace/pr/head" ]]; then head_dir="$workspace/pr/head"
>  136 |   fi
>  137 | fi
>  138 | 
>  139 | python3 -I - "$manifest" "$review" "$executor" "$manifest_v1" "$head_dir" <<'PY'
>  140 | import json, os, re, stat, sys
>  141 | manifest_path, review_path, executor_path, manifest_v1_path, head_dir = sys.argv[1:6]
   142 | man = json.load(open(manifest_path))
   143 | man_v1 = json.load(open(manifest_v1_path)) if manifest_v1_path else man
   144 | text = open(review_path, encoding="utf-8", errors="replace").read()
   145 | 
   146 | # path:line[-line] citations. Path = something with a file extension; the
   147 | # optional trailing range keeps `file.py:10-14` in one token, and the comma
   148 | # list after it (`:776,807`) belongs to the same path. A bare `:N` (or
   149 | # `head:N` / `base:N`) not glued to a word binds to the most recent path.
   150 | # a range dash is unspaced (`a.sh:12 - 40 rows` is prose, not a range) and
   151 | # every number ends at a boundary: no letter or digit, and no hyphen / en dash
   152 | # before another digit, after it (dates such as 2026-10-05 / 2026–10–05 never
   153 | # parse; an open `:369-...` still cites 369) — sprint-250 review run 2, #13
~~~~

The change from head to the fix:

~~~~diff
@@ -132,10 +133,11 @@
-head_dir="${EVAL_HEAD_DIR:-}"
+head_dir="${EVAL_HEAD_DIR:-}"; head_src="env"
 if [[ -z "$head_dir" ]]; then
-  if [[ -d "$MANIFEST_DIR/../$fixture/head" ]]; then head_dir="$MANIFEST_DIR/../$fixture/head"
-  elif [[ -d "$workspace/pr/head" ]]; then head_dir="$workspace/pr/head"
-  fi
+  head_src="none"
+  if [[ -d "$MANIFEST_DIR/../$fixture/head" ]]; then head_dir="$MANIFEST_DIR/../$fixture/head"; head_src="fixture"
+  elif [[ "${EVAL_ALLOW_WORKSPACE_HEAD:-}" == 1 && -d "$workspace/pr/head" ]]; then head_dir="$workspace/pr/head"; head_src="workspace"
+  fi   # the workspace copy is the graded agent's own writable tree: never the default (audit r1 DISS-C-002)
 fi
 
-python3 -I - "$manifest" "$review" "$executor" "$manifest_v1" "$head_dir" <<'PY'
+python3 -I - "$manifest" "$review" "$executor" "$manifest_v1" "$head_dir" "$head_src" <<'PY'
 import json, os, re, stat, sys
-manifest_path, review_path, executor_path, manifest_v1_path, head_dir = sys.argv[1:6]
+manifest_path, review_path, executor_path, manifest_v1_path, head_dir, head_src = sys.argv[1:7]
~~~~

## H03 — evals/graders/recall-vs-defects.sh — head lines 269–271

Head context (head/evals/graders/recall-vs-defects.sh, lines 257–283):

~~~~text
   257 |     if ext == "bats":
   258 |         return "bats"
   259 |     if ext in ("md", "markdown"):
   260 |         return "markdown"
   261 |     if not ext and lines and re.match(r'^#!\s*\S*(?:/env\s+)?(?:ba)?sh\b|^#!\s*\S*/(?:ba)?sh\b', lines[0]):
   262 |         return "bash"
   263 |     return None
   264 | 
   265 | 
   266 | def headers(kind, lines):
   267 |     """[(line, level)]: each definition header's 1-based line and its indentation (markdown: level)"""
   268 |     out = []
>  269 |     for i, l in enumerate(lines, 1):
>  270 |         m = None
>  271 |         if kind == "markdown":
   272 |             m = MD_HDR.match(l)
   273 |             if m:
   274 |                 out.append((i, len(m.group(1))))
   275 |             continue
   276 |         if kind == "python":
   277 |             m = PY_HDR.match(l)
   278 |         else:
   279 |             m = BASH_HDR[0].match(l) or BASH_HDR[1].match(l)
   280 |             if m is None and kind == "bats":
   281 |                 m = BATS_HDR.match(l)
   282 |         if m:
   283 |             out.append((i, len(m.group(1).expandtabs(8))))
~~~~

The change from head to the fix:

~~~~diff
@@ -269,3 +271,16 @@
+    fence = None
     for i, l in enumerate(lines, 1):
         m = None
         if kind == "markdown":
+            fm = re.match(r"^\s{0,3}(`{3,}|~{3,})(.*)$", l)   # a fenced block's `#` lines are code, not headings (review r1 DISS-C-004)
+            if fm:
+                tok, rest = fm.group(1), fm.group(2)
+                if fence is None:
+                    if not (tok[0] == "`" and "`" in rest):   # CommonMark: a backtick opener's info string holds no backtick
+                        fence = (tok[0], len(tok))
+                    continue
+                if tok[0] == fence[0] and len(tok) >= fence[1] and not rest.strip():
+                    fence = None      # the closer is at least as long as the opener, with nothing after it (review r2 DISS-003)
+                continue
+            if fence is not None:
+                continue
~~~~

## H04 — evals/graders/recall-vs-defects.sh — head line 298

Head context (head/evals/graders/recall-vs-defects.sh, lines 286–310):

~~~~text
   286 | 
   287 | CLOSE_ONE = re.compile(r'\{.*\}\s*(?:#.*)?$')
   288 | 
   289 | 
   290 | def close_line(kind, lines, h, lv, end):
   291 |     """end-of-definition detection: bash/bats — the first line after the header that is `}` at the
   292 |     header's indentation (a one-line `f() { …; }` ends on its header); python — the line before the first
   293 |     later non-blank, non-comment line indented at most as far as the def; markdown — none (next heading)"""
   294 |     if kind in ("bash", "bats"):
   295 |         if CLOSE_ONE.search(lines[h - 1]) and "{" in lines[h - 1]:
   296 |             return h
   297 |         for L in range(h + 1, end + 1):
>  298 |             t = lines[L - 1]
   299 |             if t.strip().startswith("}") and len(t) - len(t.lstrip()) == lv:
   300 |                 return L
   301 |         return end
   302 |     if kind == "python":
   303 |         last = h
   304 |         for L in range(h + 1, end + 1):
   305 |             t = lines[L - 1]
   306 |             if not t.strip() or t.lstrip().startswith("#"):
   307 |                 continue
   308 |             if len(t.expandtabs(8)) - len(t.expandtabs(8).lstrip()) <= lv:
   309 |                 return last
   310 |             last = L
~~~~

The change from head to the fix:

~~~~diff
@@ -298 +313 @@
-            t = lines[L - 1]
+            t = lines[L - 1].expandtabs(8)     # the same width headers() measured (review r1 DISS-C-006)
~~~~

## H05 — evals/graders/recall-vs-defects.sh — head lines 303–304

Head context (head/evals/graders/recall-vs-defects.sh, lines 291–316):

~~~~text
   291 |     """end-of-definition detection: bash/bats — the first line after the header that is `}` at the
   292 |     header's indentation (a one-line `f() { …; }` ends on its header); python — the line before the first
   293 |     later non-blank, non-comment line indented at most as far as the def; markdown — none (next heading)"""
   294 |     if kind in ("bash", "bats"):
   295 |         if CLOSE_ONE.search(lines[h - 1]) and "{" in lines[h - 1]:
   296 |             return h
   297 |         for L in range(h + 1, end + 1):
   298 |             t = lines[L - 1]
   299 |             if t.strip().startswith("}") and len(t) - len(t.lstrip()) == lv:
   300 |                 return L
   301 |         return end
   302 |     if kind == "python":
>  303 |         last = h
>  304 |         for L in range(h + 1, end + 1):
   305 |             t = lines[L - 1]
   306 |             if not t.strip() or t.lstrip().startswith("#"):
   307 |                 continue
   308 |             if len(t.expandtabs(8)) - len(t.expandtabs(8).lstrip()) <= lv:
   309 |                 return last
   310 |             last = L
   311 |         return end
   312 |     return end
   313 | 
   314 | 
   315 | _scopes = {}
   316 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -303,2 +318,14 @@
-        last = h
-        for L in range(h + 1, end + 1):
+        # skip a multi-line signature: the header ends on the line that closes its parentheses and ends with
+        # a colon (review r1 DISS-C-005); the indentation rule then binds the body
+        j, depth = h, 0
+        while j <= end:
+            t = re.sub(r"#.*$", "", lines[j - 1])
+            depth += t.count("(") - t.count(")")
+            rest = t[t.rfind(")") + 1:] if depth <= 0 and ")" in t else ""
+            if depth <= 0 and ":" in rest:
+                break                 # the colon after the closing parenthesis ends the header (a one-liner
+            j += 1                    # `def f(): return 1` ends on its own line; review r2 DISS-001)
+        if j > end:
+            j = h                     # no terminating colon found (a `(` or `#` inside a string default): one-line header
+        last = j
+        for L in range(j + 1, end + 1):
~~~~

## H06 — evals/graders/recall-vs-defects.sh — insertion after head line 315

Head context (head/evals/graders/recall-vs-defects.sh, lines 304–327):

~~~~text
   304 |         for L in range(h + 1, end + 1):
   305 |             t = lines[L - 1]
   306 |             if not t.strip() or t.lstrip().startswith("#"):
   307 |                 continue
   308 |             if len(t.expandtabs(8)) - len(t.expandtabs(8).lstrip()) <= lv:
   309 |                 return last
   310 |             last = L
   311 |         return end
   312 |     return end
   313 | 
   314 | 
   315 | _scopes = {}
   316 | 
   317 | 
   318 | def scope_map(rel):
   319 |     """→ (kind, [scope per line, 1-based; index 0 unused]) where a scope is the innermost
   320 |     definition's header line, "long" (a definition above SPAN_CAP lines) or None (no
   321 |     definition); kind None = no regex for the file type, or no head file"""
   322 |     if rel in _scopes:
   323 |         return _scopes[rel]
   324 |     lines = head_lines(rel)
   325 |     kind = lang(rel, lines) if lines is not None else None
   326 |     res = (kind, None)
   327 |     if kind is not None:
~~~~

The change from head to the fix:

~~~~diff
@@ -315,0 +343 @@
+HEADERS_CAP = 5000
~~~~

## H07 — evals/graders/recall-vs-defects.sh — insertion after head line 329

Head context (head/evals/graders/recall-vs-defects.sh, lines 318–341):

~~~~text
   318 | def scope_map(rel):
   319 |     """→ (kind, [scope per line, 1-based; index 0 unused]) where a scope is the innermost
   320 |     definition's header line, "long" (a definition above SPAN_CAP lines) or None (no
   321 |     definition); kind None = no regex for the file type, or no head file"""
   322 |     if rel in _scopes:
   323 |         return _scopes[rel]
   324 |     lines = head_lines(rel)
   325 |     kind = lang(rel, lines) if lines is not None else None
   326 |     res = (kind, None)
   327 |     if kind is not None:
   328 |         n = len(lines)
   329 |         hs = headers(kind, lines)
   330 |         spans = []
   331 |         for k, (h, lv) in enumerate(hs):
   332 |             end = n
   333 |             for h2, lv2 in hs[k + 1:]:
   334 |                 if lv2 <= lv:
   335 |                     end = h2 - 1
   336 |                     break
   337 |             end = min(end, close_line(kind, lines, h, lv, end))
   338 |             spans.append((h, end))
   339 |         sc = [None] * (n + 1)
   340 |         for h, end in spans:            # later (inner) headers overwrite earlier (outer) ones
   341 |             tag = "long" if end - h + 1 > SPAN_CAP else h
~~~~

The change from head to the fix:

~~~~diff
@@ -329,0 +358,3 @@
+        if len(hs) > HEADERS_CAP:
+            _scopes[rel] = (None, None)   # an unterminated 4 MB file gets the ±20 fallback, not a quadratic scan (audit r1 DISS-C-002)
+            return _scopes[rel]
~~~~

## H08 — evals/graders/recall-vs-defects.sh — head line 482

Head context (head/evals/graders/recall-vs-defects.sh, lines 470–492):

~~~~text
   470 | else:
   471 |     ok = false_positives == 0
   472 |     score = 100 if ok else 0
   473 | 
   474 | out = {
   475 |     "pass": ok,
   476 |     "score": score,
   477 |     "details": {
   478 |         "recall": recall, "planted": planted, "detected": detected, "missed": missed,
   479 |         "recall_pm3": rate(det_pm3, man), "detected_pm3": det_pm3, "missed_pm3": mis_pm3,
   480 |         "recall_pm3_v1": rate(det_v1, man_v1), "detected_pm3_v1": det_v1, "missed_pm3_v1": mis_v1,
   481 |         "planted_v1": len(man_v1.get("defects", [])), "v1_manifest": bool(manifest_v1_path),
>  482 |         "credits_function_only": function_only, "rule": "pm3_or_same_function",
   483 |         "false_positives": false_positives, "severity_counts": sev,
   484 |         "citations": len(cites), "model": model, "effort": effort, "tokens": tokens,
   485 |         "findings_cited": len(findings), "findings_refuted": len(refuted),
   486 |         "refuted_share": refuted_share,
   487 |     },
   488 |     "grader_version": "1.3.0",
   489 | }
   490 | print(json.dumps(out))
   491 | sys.exit(0 if ok else 1)
   492 | PY
~~~~

The change from head to the fix:

~~~~diff
@@ -482 +513 @@
-        "credits_function_only": function_only, "rule": "pm3_or_same_function",
+        "credits_function_only": function_only, "rule": "pm3_or_same_function", "head_dir_source": head_src,
~~~~

## H09 — evals/harness/ablation-grade.sh — head line 1629

Head context (head/evals/harness/ablation-grade.sh, lines 1617–1641):

~~~~text
  1617 |             else:
  1618 |                 end = max(end, hi)
  1619 |     return n
  1620 | 
  1621 | 
  1622 | def grade_recall(t, run_dir, grading):
  1623 |     cites = combined_findings(run_dir)
  1624 |     combined = os.path.join(grading, "gates-combined.md")
  1625 |     with open(combined, "w", encoding="utf-8") as f:
  1626 |         f.write("".join(f"{p}:{a}\n" if a == b else f"{p}:{a}-{b}\n" for p, a, b in cites))
  1627 |     env = dict(os.environ, EVAL_MANIFEST_DIR=os.path.dirname(t.key_path), LC_ALL="C")
  1628 |     # 1.3.0: the same-scope clause reads the PR fixture's head/ tree (immutable; never the sandbox pr/)
> 1629 |     env.pop("EVAL_HEAD_DIR", None)
  1630 |     try:
  1631 |         head = os.path.join(resolve_pr_fixture(t), "head")
  1632 |         if os.path.isdir(head):
  1633 |             env["EVAL_HEAD_DIR"] = head
  1634 |     except GradeError:
  1635 |         pass
  1636 |     p = run(["bash", os.path.join(REPO_ROOT, "evals", "graders", "recall-vs-defects.sh"), grading, t.key_id,
  1637 |              "gates-combined.md"], env=env)
  1638 |     try:
  1639 |         det = json.loads(p.stdout)["details"]
  1640 |     except (ValueError, KeyError, TypeError):
  1641 |         raise GradeError(f"recall-vs-defects.sh failed (exit {p.returncode})")
~~~~

The change from head to the fix:

~~~~diff
@@ -1629 +1629,2 @@
-    env.pop("EVAL_HEAD_DIR", None)
+    # the sentinel keeps recall-vs-defects.sh off its $workspace/pr/head fallback (the sandbox copy; review r1 DISS-C-003)
+    env["EVAL_HEAD_DIR"] = os.path.join(grading, ".no-head")
~~~~

## H10 — evals/harness/ablation-grade.sh — head line 1809

Head context (head/evals/harness/ablation-grade.sh, lines 1797–1821):

~~~~text
  1797 | 
  1798 | def check_value(tool, field, val, roots):
  1799 |     low = val.lower()
  1800 |     if tool == "Bash":
  1801 |         stripped = strip_heredocs(val)
  1802 |         if HIDDEN_TOKEN.search(val) or HIDDEN_GLOB.search(stripped) or HIDDEN_FS.search(stripped):   # DEC-0551 token shapes; 1.2.7 globs and 1.2.8 filesystem probes outside heredoc bodies
  1803 |             return "hidden"
  1804 |     elif "hidden" in low:
  1805 |         return "hidden"
  1806 |     if "grimoires/loa/evals/ablation-2.0" in val:
  1807 |         return "suite_path"
  1808 |     if "0xhoneyjar/loa" in low:
> 1809 |         ex = repo_name_exempt(val)
  1810 |         if ex is None:
  1811 |             return "repo_name"
  1812 |         EXEMPT_BUF.extend(ex)   # KF-046 class 7: every occurrence is PR content; the scan goes on
  1813 |     if tool == "Bash" and GIT_HIST.search(val):
  1814 |         HISTORY_PROBES[0] += 1   # DEC-0540: telemetry only; the sandbox has no pre-base history
  1815 |     if tool == "Bash":
  1816 |         HEREDOC_INTERP[0] += count_interpreter_heredocs(val)   # 1.2.6 LOW-3: telemetry only
  1817 |     cands = []
  1818 |     if field in PATH_FIELDS or (tool == "Glob" and field == "pattern"):
  1819 |         if val.startswith("/") and not val.startswith("//"):
  1820 |             cands.append(val)
  1821 |         elif val.startswith(HOME_PREFIXES) and home_word_outside():
~~~~

The change from head to the fix:

~~~~diff
@@ -1809 +1810 @@
-        ex = repo_name_exempt(val)
+        ex = repo_name_exempt(val, tool)
~~~~

## H11 — evals/harness/ablation-grade.sh — head line 1935

Head context (head/evals/harness/ablation-grade.sh, lines 1923–1947):

~~~~text
  1923 |                                 CONTAM_EXEMPT.append(rec)
  1924 |                         EXEMPT_BUF.clear()
  1925 |                         if hit:
  1926 |                             return {"phase": label, "pattern": hit, "excerpt_id": f"{label}:{i}"}
  1927 |     return None
  1928 | 
  1929 | 
  1930 | # ------------------------------------------------------------------ KF-046 class 7 (1.3.0, D-3.2)
  1931 | # A review-catch PR may itself carry the repository's name (a workflow's `if: github.repository ==
  1932 | # '0xHoneyJar/loa'`); quoting that PR content is not a probe of the upstream repository. Each
  1933 | # occurrence's unit is the backtick span holding it (`…`), else its whole line, stripped; an
  1934 | # occurrence is exempt when its unit is a substring of one line of the task's PR fixture (head/**
> 1935 | # files or head.diff, the diff's +/-/space prefix dropped). Every occurrence of a value must be exempt,
  1936 | # else the value is a repo_name hit as before. Exempt values are recorded in contamination_exempt[]
  1937 | # ({phase, excerpt_id, pattern, fixture_line: "head/<path>:<n>" | "head.diff:<n>", line: the fixture
  1938 | # line, 200 characters at most}); build tasks have no PR fixture and no exemption.
  1939 | FIXTURE_TASK = [None]
  1940 | FIXTURE_LINES = []     # [(source, text)] fixture lines holding the token, loaded on first use
  1941 | CONTAM_EXEMPT = []
  1942 | EXEMPT_BUF = []
  1943 | REPO_TOKEN = re.compile(r"0xhoneyjar/loa", re.I)
  1944 | 
  1945 | 
  1946 | def fixture_token_lines():
  1947 |     if FIXTURE_LINES:
~~~~

The change from head to the fix:

~~~~diff
@@ -1935 +1936,2 @@
-# files or head.diff, the diff's +/-/space prefix dropped). Every occurrence of a value must be exempt,
+# files or head.diff, the diff's +/-/space prefix dropped); a backslash-continued command is one logical line, and a
+# bare token standing as the whole line (a for-list word, a list entry) exempts nothing (review r1 DISS-C-002). Every occurrence of a value must be exempt,
~~~~

## H12 — evals/harness/ablation-grade.sh — head lines 1980–1986

Head context (head/evals/harness/ablation-grade.sh, lines 1968–1998):

~~~~text
  1968 |         for src, q, is_diff in files:
  1969 |             text = read_regular(q, FILE_CAP, root=pr)
  1970 |             if text is None or not REPO_TOKEN.search(text):
  1971 |                 continue
  1972 |             for k, line in enumerate(text.split("\n"), 1):
  1973 |                 if REPO_TOKEN.search(line):
  1974 |                     body = line[1:] if is_diff and line[:1] in "+- " else line
  1975 |                     out.append((f"{src}:{k}", body.strip()))
  1976 |     FIXTURE_LINES.append(out)
  1977 |     return out
  1978 | 
  1979 | 
> 1980 | def repo_name_exempt(val):
> 1981 |     """→ [(fixture source, fixture line)] when every repo-name occurrence in val is PR content, else None"""
> 1982 |     fl = fixture_token_lines()
> 1983 |     if not fl:
> 1984 |         return None
> 1985 |     hits = []
> 1986 |     for line in val.split("\n"):
  1987 |         for m in REPO_TOKEN.finditer(line):
  1988 |             unit = None
  1989 |             for span in re.finditer(r"`[^`\n]*`", line):
  1990 |                 if span.start() < m.start() and m.end() < span.end():
  1991 |                     unit = span.group(0)[1:-1].strip()
  1992 |                     break
  1993 |             if unit is None:
  1994 |                 unit = line.strip()
  1995 |             match = next(((src, text) for src, text in fl if unit and unit in text), None)
  1996 |             if match is None:
  1997 |                 return None
  1998 |             hits.append((match[0], match[1][:200]))
~~~~

The change from head to the fix:

~~~~diff
@@ -1980,7 +1982,27 @@
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
-    for line in val.split("\n"):
+    for line in val.replace("\\\n", " ").split("\n"):   # a backslash-continued command is one logical line
~~~~

## H13 — evals/harness/ablation-grade.sh — insertion after head line 1994

Head context (head/evals/harness/ablation-grade.sh, lines 1983–2006):

~~~~text
  1983 |     if not fl:
  1984 |         return None
  1985 |     hits = []
  1986 |     for line in val.split("\n"):
  1987 |         for m in REPO_TOKEN.finditer(line):
  1988 |             unit = None
  1989 |             for span in re.finditer(r"`[^`\n]*`", line):
  1990 |                 if span.start() < m.start() and m.end() < span.end():
  1991 |                     unit = span.group(0)[1:-1].strip()
  1992 |                     break
  1993 |             if unit is None:
  1994 |                 unit = line.strip()
  1995 |             match = next(((src, text) for src, text in fl if unit and unit in text), None)
  1996 |             if match is None:
  1997 |                 return None
  1998 |             hits.append((match[0], match[1][:200]))
  1999 |     return hits
  2000 | 
  2001 | 
  2002 | # ------------------------------------------------------------------ corpus digest (1.3.0)
  2003 | def corpus_sha256(t):
  2004 |     """sha256 of the review corpus's SHA256SUMS (the directory above the key's manifests/), null when absent"""
  2005 |     import hashlib
  2006 |     p = os.path.join(os.path.dirname(os.path.dirname(t.key_path)), "SHA256SUMS")
~~~~

The change from head to the fix:

~~~~diff
@@ -1994,0 +2017,3 @@
+                if len(unit) < len(m.group(0)) + 4:
+                    return None       # a bare token as a whole (logical) line is a command word, not a quotation: it is a
+                                      # substring of every fixture token line and exempts nothing (review r1 DISS-C-002)
~~~~

## H14 — evals/harness/ablation-grade.sh — head lines 2007–2011

Head context (head/evals/harness/ablation-grade.sh, lines 1995–2023):

~~~~text
  1995 |             match = next(((src, text) for src, text in fl if unit and unit in text), None)
  1996 |             if match is None:
  1997 |                 return None
  1998 |             hits.append((match[0], match[1][:200]))
  1999 |     return hits
  2000 | 
  2001 | 
  2002 | # ------------------------------------------------------------------ corpus digest (1.3.0)
  2003 | def corpus_sha256(t):
  2004 |     """sha256 of the review corpus's SHA256SUMS (the directory above the key's manifests/), null when absent"""
  2005 |     import hashlib
  2006 |     p = os.path.join(os.path.dirname(os.path.dirname(t.key_path)), "SHA256SUMS")
> 2007 |     text = read_regular(p, READ_CAP, whole=True)
> 2008 |     if text is None:
> 2009 |         return None
> 2010 |     with open(p, "rb") as f:
> 2011 |         return hashlib.sha256(f.read()).hexdigest()
  2012 | 
  2013 | 
  2014 | # ------------------------------------------------------------------ oracle detector (1.3.0, D-1.3, KF-049)
  2015 | # Did a session read a LATER copy of a file the PR touched? Answer-bearing paths: the paths under .claude/
  2016 | # named by the PR fixture's head.diff headers (`diff --git a/X b/Y` both names, quoted C-style names
  2017 | # unquoted, `--- a/X`, `+++ b/Y`, `rename from|to X`; /dev/null and unsafe paths dropped) or present under
  2018 | # its head/ or base/ tree. Over transcripts/events-{BARE,REVIEW,AUDIT}.jsonl each assistant tool_use is
  2019 | # correlated with its tool_result by id. Paths are resolved against the session's cwd (the system init
  2020 | # event's, default /workspace, which is also the workspace root), `cd DIR` segments, NAME=value
  2021 | # assignments (H=pr/head) and `for V in w…; do` lists; a path inside the workspace and outside pr/ is a
  2022 | # workspace operand, pr/head/X and pr/base/X are PR operands.
  2023 | #   diff form — a Bash segment (split on newline, ; && || | & outside quotes and parentheses; heredoc bodies
~~~~

The change from head to the fix:

~~~~diff
@@ -2007,5 +2032,19 @@
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
~~~~

## H15 — evals/harness/ablation-grade.sh — head line 2035

Head context (head/evals/harness/ablation-grade.sh, lines 2023–2047):

~~~~text
  2023 | #   diff form — a Bash segment (split on newline, ; && || | & outside quotes and parentheses; heredoc bodies
  2024 | #   removed first) whose executable is diff, sdiff or comm, or git with diff and --no-index, without -q
  2025 | #   (alone or in a short-flag cluster), --brief or --quiet, holding a PR operand and a workspace operand that
  2026 | #   names an answer path (or a directory above one); a head.diff operand is never a PR operand. Its result
  2027 | #   is split into per-file sections at `diff `, `--- ` and `*** ` header lines (text no header attributes
  2028 | #   goes to every target of the command); unified `@@ -a,b +c,d @@` and normal `NaM,b` / `N,Mc…` / `Nd…`
  2029 | #   ranges are read (head side, below); a planted site of that file within ±3 of a range, or its must_match
  2030 | #   text (stripped, first 50 characters, at least 12) in the section, marks the defect exposed (how diff);
  2031 | #   a non-empty section that is not only error lines and yields neither ranges nor must_match marks every
  2032 | #   other defect of that file exposed_unknown. Text no header attributes, in a command with several
  2033 | #   targets, exposes a defect only with corroboration: a range near the site AND a line of the fixture's
  2034 | #   head/X within ±3 of the site in that text, or must_match. A diff whose output is discarded or reduced
> 2035 | #   (>/dev/null, | wc, | grep -c|-q|-l, | cmp) and a tool_result flagged is_error print no content.
  2036 | #   read form — a Bash segment whose executable is cat, sed, awk, grep, head, tail, less or python3, or a
  2037 | #   Read (file_path) / Grep (path) tool_use, naming a workspace answer path (a directory for grep or Grep
  2038 | #   covers the answer paths below it), whose result contains a LATER-ONLY line within ±3 of a planted site
  2039 | #   (when the tool_use reads several answer paths, on a result line that names the file's basename):
  2040 | #   a line of the sandbox copy (sandbox/<X>, read bounded and symlink-refusing) present in neither the
  2041 | #   fixture's head/X nor base/X, at least 8 characters stripped, mapped to head coordinates by difflib.
  2042 | # Either form is skipped for a path whose sandbox copy byte-equals the fixture's head/X or base/X (a closed
  2043 | # mount, in either overlay mode: a diff there prints the PR's own change, not a later one).
  2044 | # Ranges are read on the head side only: planted sites are head coordinates, so the side of the pr/head
  2045 | # operand (left when it precedes the workspace operand) is tested; a pr/base operand gives both sides.
  2046 | # grade.json: oracle_exposed_defects (positions d1 … of defects exposed by diff or read),
  2047 | # oracle_exposed_unknown (positions only exposed_unknown), oracle_exposed_events [{phase, event: the
~~~~

The change from head to the fix:

~~~~diff
@@ -2035 +2074,2 @@
-#   (>/dev/null, | wc, | grep -c|-q|-l, | cmp) and a tool_result flagged is_error print no content.
+#   (>/dev/null, &>/dev/null, | wc, | grep with -c|-q|-l anywhere, | cmp; a stat-only git diff) and a tool_result
+#   flagged is_error print no content; `2>&1`, `>&2`, `<&0` and `&>` are redirections, never separators.
~~~~

## H16 — evals/harness/ablation-grade.sh — insertion after head line 2052

Head context (head/evals/harness/ablation-grade.sh, lines 2041–2064):

~~~~text
  2041 | #   fixture's head/X nor base/X, at least 8 characters stripped, mapped to head coordinates by difflib.
  2042 | # Either form is skipped for a path whose sandbox copy byte-equals the fixture's head/X or base/X (a closed
  2043 | # mount, in either overlay mode: a diff there prints the PR's own change, not a later one).
  2044 | # Ranges are read on the head side only: planted sites are head coordinates, so the side of the pr/head
  2045 | # operand (left when it precedes the workspace operand) is tested; a pr/base operand gives both sides.
  2046 | # grade.json: oracle_exposed_defects (positions d1 … of defects exposed by diff or read),
  2047 | # oracle_exposed_unknown (positions only exposed_unknown), oracle_exposed_events [{phase, event: the
  2048 | # tool_use's line number in its events file, how: diff|read|exposed_unknown, path}] and
  2049 | # oracle_exposed_by_form {diff: [positions], read: [positions]}; null for build tasks.
  2050 | # A LOWER BOUND, like the contamination scan: a paraphrase, a copy made by a program and read later, or a
  2051 | # path built at run time is not seen.
  2052 | ORACLE_PHASES = ("BARE", "REVIEW", "AUDIT")
  2053 | DIFF_EXE = {"diff", "sdiff", "comm"}
  2054 | READ_EXE = {"cat", "sed", "awk", "grep", "head", "tail", "less", "python3"}
  2055 | ANSWER_TOP = ".claude/"
  2056 | SEG_KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "{", "(", "!", "time"}
  2057 | PATHISH = re.compile(r"[A-Za-z0-9_./@%+,:=~$-]*[A-Za-z0-9_./@%+:~$-]")
  2058 | HUNK_U = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", re.M)
  2059 | HUNK_N = re.compile(r"^(\d+)(?:,(\d+))?([acd])(\d+)(?:,(\d+))?\s*$", re.M)
  2060 | ERR_LINE = re.compile(r"^(?:diff|sdiff|comm|git|cat|grep|sed|head|tail|awk|less):|^(?:fatal|error|warning):|"
  2061 |                       r"No such file|Is a directory|hook error|BLOCKED|^\s*$|^\s*(?:rc|exit)\s*=\s*\d+\s*$")
  2062 | DIFF_BODY = re.compile(r"^[<>+\- @\\0-9]|^---$")
  2063 | FILEISH = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+|[A-Za-z0-9_-]+\.[A-Za-z0-9]{1,6}\b")
  2064 | # a diff whose stdout is counted, tested or discarded prints no content: | wc, | grep -c/-q/-l, >/dev/null
~~~~

The change from head to the fix:

~~~~diff
@@ -2052,0 +2093,3 @@
+# bounds on agent-authored input (audit r1 DISS-C-003): every dimension the graded session controls is capped
+FORLIST_CAP, EXPAND_CAP, SEG_CAP, WORD_CAP, WORDS_CAP, LINE_CAP, LINES_CAP, DIFF_LINES_CAP = 64, 256, 65536, 4096, 512, 4096, 20000, 20000
+ORACLE_SKIPPED = []   # answer paths whose later-line map was skipped (a side over DIFF_LINES_CAP lines)
~~~~

## H17 — evals/harness/ablation-grade.sh — head lines 2065–2066

Head context (head/evals/harness/ablation-grade.sh, lines 2053–2078):

~~~~text
  2053 | DIFF_EXE = {"diff", "sdiff", "comm"}
  2054 | READ_EXE = {"cat", "sed", "awk", "grep", "head", "tail", "less", "python3"}
  2055 | ANSWER_TOP = ".claude/"
  2056 | SEG_KEYWORDS = {"do", "then", "else", "elif", "if", "while", "until", "{", "(", "!", "time"}
  2057 | PATHISH = re.compile(r"[A-Za-z0-9_./@%+,:=~$-]*[A-Za-z0-9_./@%+:~$-]")
  2058 | HUNK_U = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", re.M)
  2059 | HUNK_N = re.compile(r"^(\d+)(?:,(\d+))?([acd])(\d+)(?:,(\d+))?\s*$", re.M)
  2060 | ERR_LINE = re.compile(r"^(?:diff|sdiff|comm|git|cat|grep|sed|head|tail|awk|less):|^(?:fatal|error|warning):|"
  2061 |                       r"No such file|Is a directory|hook error|BLOCKED|^\s*$|^\s*(?:rc|exit)\s*=\s*\d+\s*$")
  2062 | DIFF_BODY = re.compile(r"^[<>+\- @\\0-9]|^---$")
  2063 | FILEISH = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+|[A-Za-z0-9_-]+\.[A-Za-z0-9]{1,6}\b")
  2064 | # a diff whose stdout is counted, tested or discarded prints no content: | wc, | grep -c/-q/-l, >/dev/null
> 2065 | SILENT_SINK = re.compile(r"^(?:wc|cmp|true|false|test)\b|^grep\s+(?:-[A-Za-z]*[cql][A-Za-z]*|--count|--quiet|--files-with-matches)\b")
> 2066 | DEVNULL = re.compile(r"(?:^|[\s;])(?:1?>|&>|>&)\s*/dev/null")
  2067 | 
  2068 | 
  2069 | def unquote_c(q):
  2070 |     """a git C-quoted path body (between the quotes) → text"""
  2071 |     i, b = 0, bytearray()
  2072 |     while i < len(q):
  2073 |         ch = q[i]
  2074 |         if ch == "\\" and i + 1 < len(q):
  2075 |             n = q[i + 1]
  2076 |             if n in "01234567" and re.match(r"[0-7]{3}", q[i + 1:i + 4]):
  2077 |                 b.append(int(q[i + 1:i + 4], 8))
  2078 |                 i += 4
~~~~

The change from head to the fix:

~~~~diff
@@ -2065,2 +2108,17 @@
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
+    if exe in ("grep", "egrep", "fgrep", "rg"):
+        return any(re.fullmatch(r"-[A-Za-z]*[cqlL][A-Za-z]*", x)
+                   or x in ("--count", "--quiet", "--silent", "--files-with-matches", "--files-without-match")
+                   for x in w[1:])
+    return False
~~~~

## H18 — evals/harness/ablation-grade.sh — head lines 2159–2160

Head context (head/evals/harness/ablation-grade.sh, lines 2147–2172):

~~~~text
  2147 |         elif ch == "\\" and i + 1 < len(cmd):
  2148 |             cur.append(ch + cmd[i + 1])
  2149 |             i += 1
  2150 |         elif ch in "'\"":
  2151 |             q = ch
  2152 |             cur.append(ch)
  2153 |         elif ch == "(":
  2154 |             depth += 1
  2155 |             cur.append(ch)
  2156 |         elif ch == ")":
  2157 |             depth = max(0, depth - 1)
  2158 |             cur.append(ch)
> 2159 |         elif depth == 0 and ch in "\n;&|":
> 2160 |             pipe = ch == "|" and cmd[i + 1:i + 2] != "|" and cmd[i - 1:i] != "|"
  2161 |             segs.append(("".join(cur), "|" if pipe else ";"))
  2162 |             cur = []
  2163 |         else:
  2164 |             cur.append(ch)
  2165 |         i += 1
  2166 |     segs.append(("".join(cur), ";"))
  2167 |     return [(x.strip(), sep) for x, sep in segs if x.strip()]
  2168 | 
  2169 | 
  2170 | def seg_words(seg):
  2171 |     try:
  2172 |         w = shlex.split(seg, comments=False, posix=True)
~~~~

The change from head to the fix:

~~~~diff
@@ -2159,2 +2217,7 @@
+        elif depth == 0 and ch == "&" and (cmd[i - 1:i] in (">", "<") or cmd[i + 1:i + 2] == ">"):
+            cur.append(ch)          # a redirection (2>&1, >&2, <&0, &>f), not a separator (review r1 DISS-001/C-001)
         elif depth == 0 and ch in "\n;&|":
             pipe = ch == "|" and cmd[i + 1:i + 2] != "|" and cmd[i - 1:i] != "|"
+            if ch == "|" and cmd[i + 1:i + 2] == "&":
+                pipe = True           # `|&` is bash's `2>&1 |`: one pipe, no empty segment (review r2 DISS-C-004)
+                i += 1
~~~~

## H19 — evals/harness/ablation-grade.sh — insertion after head line 2204

Head context (head/evals/harness/ablation-grade.sh, lines 2193–2216):

~~~~text
  2193 |         nxt, changed = [], False
  2194 |         for o in outs:
  2195 |             m = re.search(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}|\$([A-Za-z_][A-Za-z0-9_]*)", o)
  2196 |             if not m:
  2197 |                 nxt.append(o)
  2198 |                 continue
  2199 |             name = m.group(1) or m.group(2)
  2200 |             if name not in vars_:
  2201 |                 continue
  2202 |             changed = True
  2203 |             for v in vars_[name]:
  2204 |                 nxt.append(o[:m.start()] + v + o[m.end():])
  2205 |         outs = nxt
  2206 |         if not changed:
  2207 |             break
  2208 |     return [o for o in outs if "$" not in o]
  2209 | 
  2210 | 
  2211 | def classify(tok, cwd, ws):
  2212 |     """→ ("pr", side, rel) | ("ws", rel) | None"""
  2213 |     tok = tok.strip("'\"")
  2214 |     if not tok or tok.startswith("-") or "://" in tok:
  2215 |         return None
  2216 |     if tok.startswith("~") or "*" in tok or "?" in tok:
~~~~

The change from head to the fix:

~~~~diff
@@ -2204,0 +2268,2 @@
+            if len(nxt) > EXPAND_CAP:
+                return []             # a for-list product past the cap resolves nothing (audit r1 DISS-C-003)
~~~~

## H20 — evals/harness/ablation-grade.sh — head lines 2241–2247

Head context (head/evals/harness/ablation-grade.sh, lines 2229–2259):

~~~~text
  2229 | 
  2230 | 
  2231 | def ws_targets(rel, answer, directory_ok):
  2232 |     if rel in answer:
  2233 |         return [rel]
  2234 |     if not directory_ok:
  2235 |         return []
  2236 |     pre = "" if rel in ("", ".") else rel.rstrip("/") + "/"
  2237 |     return sorted(a for a in answer if a.startswith(pre))
  2238 | 
  2239 | 
  2240 | def segment_tokens(seg, vars_, cwd, ws):
> 2241 |     """every path-shaped token of a segment (inside process substitutions too), expanded and classified"""
> 2242 |     out = []
> 2243 |     for m in PATHISH.finditer(seg):
> 2244 |         for v in expand(m.group(0), vars_):
> 2245 |             c = classify(v, cwd, ws)
> 2246 |             if c is not None:
> 2247 |                 out.append((v, c))
  2248 |     return out
  2249 | 
  2250 | 
  2251 | def result_text(blk):
  2252 |     c = blk.get("content")
  2253 |     if isinstance(c, str):
  2254 |         return c
  2255 |     if isinstance(c, list):
  2256 |         return "\n".join(x.get("text", "") for x in c if isinstance(x, dict) and isinstance(x.get("text"), str))
  2257 |     return ""
  2258 | 
  2259 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -2241,7 +2306,14 @@
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
~~~~

## H21 — evals/harness/ablation-grade.sh — insertion after head line 2338

Head context (head/evals/harness/ablation-grade.sh, lines 2327–2350):

~~~~text
  2327 |         return [], [], [], {"diff": [], "read": []}
  2328 |     sb = os.path.join(run_dir, "sandbox")
  2329 |     later, live, near_text = {}, {}, {}
  2330 |     for f in by_file:
  2331 |         cur = read_regular(os.path.join(sb, *f.split("/")), FILE_CAP, root=sb)
  2332 |         hd = read_regular(os.path.join(pr, "head", *f.split("/")), FILE_CAP, root=pr)
  2333 |         bs = read_regular(os.path.join(pr, "base", *f.split("/")), FILE_CAP, root=pr)
  2334 |         live[f] = cur is not None and cur != hd and cur != bs
  2335 |         later[f] = []
  2336 |         if not live[f] or hd is None:
  2337 |             continue
  2338 |         hl, cl = hd.split("\n"), cur.split("\n")
  2339 |         for pos, sites, _mm in by_file[f]:
  2340 |             near_text[(f, pos)] = [hl[L - 1].strip() for s_ in sites for L in range(s_ - 3, s_ + 4)
  2341 |                                    if 1 <= L <= len(hl) and len(hl[L - 1].strip()) >= 8]
  2342 |         known = set(x.strip() for x in hl) | (set(x.strip() for x in bs.split("\n")) if bs is not None else set())
  2343 |         for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, hl, cl, autojunk=False).get_opcodes():
  2344 |             if tag == "equal":
  2345 |                 continue
  2346 |             lo, hi = i1 + 1, max(i2, i1 + 1)
  2347 |             for j in range(j1, j2):
  2348 |                 txt = cl[j].strip()
  2349 |                 if len(txt) >= 8 and txt not in known:
  2350 |                     later[f].append((txt, lo, hi))
~~~~

The change from head to the fix:

~~~~diff
@@ -2338,0 +2411,3 @@
+        if len(hl) > DIFF_LINES_CAP or len(cl) > DIFF_LINES_CAP:
+            ORACLE_SKIPPED.append(f)  # no later-line map for a huge copy: the read form cannot fire for it (audit r1 DISS-C-003)
+            continue
~~~~

## H22 — evals/harness/ablation-grade.sh — head line 2392

Head context (head/evals/harness/ablation-grade.sh, lines 2380–2404):

~~~~text
  2380 |                 continue
  2381 |             for blk in content:
  2382 |                 if not isinstance(blk, dict):
  2383 |                     continue
  2384 |                 if ev.get("type") == "assistant" and blk.get("type") == "tool_use" and isinstance(blk.get("input"), dict):
  2385 |                     plan = oracle_plan(blk.get("name") or "", blk["input"], ws, answer)
  2386 |                     if plan and isinstance(blk.get("id"), str):
  2387 |                         uses[blk["id"]] = (i, plan)
  2388 |                 elif ev.get("type") == "user" and blk.get("type") == "tool_result" and blk.get("tool_use_id") in uses:
  2389 |                     i0, plan = uses.pop(blk["tool_use_id"])
  2390 |                     if blk.get("is_error") is True:
  2391 |                         continue          # the tool failed (a refused command, a hook block): nothing printed
> 2392 |                     res = result_text(blk)
  2393 |                     dtargets = sorted({f for how, f in plan if how.startswith("diff") and live.get(f)})
  2394 |                     rtargets = sorted({f for how, f in plan if how == "read" and live.get(f)})
  2395 |                     if dtargets and res.strip():
  2396 |                         secs_by, loose = sections(res, dtargets)
  2397 |                         # loose text (several targets, no naming header): a range near the site counts only
  2398 |                         # with the head file's own text near that site in the same text, or must_match
  2399 |                         for sec in loose:
  2400 |                             for f in dtargets:
  2401 |                                 rs = ranges_of(sec, plan_sides(plan, f))
  2402 |                                 for pos, sites, mm in by_file.get(f, []):
  2403 |                                     ranged = any(near(sites, lo, hi) for lo, hi in rs)
  2404 |                                     own = any(x in sec for x in near_text.get((f, pos), []))
~~~~

The change from head to the fix:

~~~~diff
@@ -2392 +2467 @@
-                    res = result_text(blk)
+                    res = "\n".join(l[:LINE_CAP] for l in result_text(blk).split("\n")[:LINES_CAP])
~~~~

## H23 — evals/harness/ablation-grade.sh — head line 2467

Head context (head/evals/harness/ablation-grade.sh, lines 2455–2479):

~~~~text
  2455 |             for x in raw:
  2456 |                 m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", x)
  2457 |                 if m:
  2458 |                     vals = expand(m.group(2).strip("'\""), vars_)
  2459 |                     if vals:
  2460 |                         vars_[m.group(1)] = vals[:1]
  2461 |             continue
  2462 |         m = re.match(r"^for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\s+(.*)$", seg)
  2463 |         if m:
  2464 |             words = []
  2465 |             for x in m.group(2).split():
  2466 |                 words += expand(x.strip("'\""), vars_)
> 2467 |             vars_[m.group(1)] = words
  2468 |             continue
  2469 |         if not w:
  2470 |             continue
  2471 |         exe = w[0].rsplit("/", 1)[-1]
  2472 |         if exe == "cd" and len(w) >= 2:
  2473 |             vals = expand(w[1], vars_)
  2474 |             if vals:
  2475 |                 cwd = os.path.normpath(vals[0] if vals[0].startswith("/") else os.path.join(cwd, vals[0]))
  2476 |             continue
  2477 |         is_diff = exe in DIFF_EXE or (exe == "git" and "diff" in w and "--no-index" in w)
  2478 |         if is_diff:
  2479 |             if any(re.fullmatch(r"-[A-Za-z]*q[A-Za-z]*", x) or x in ("--brief", "--quiet") for x in w[1:]):
~~~~

The change from head to the fix:

~~~~diff
@@ -2467 +2542 @@
-            vars_[m.group(1)] = words
+            vars_[m.group(1)] = words[:FORLIST_CAP]
~~~~

## H24 — evals/harness/ablation-grade.sh — head lines 2482–2483

Head context (head/evals/harness/ablation-grade.sh, lines 2470–2495):

~~~~text
  2470 |             continue
  2471 |         exe = w[0].rsplit("/", 1)[-1]
  2472 |         if exe == "cd" and len(w) >= 2:
  2473 |             vals = expand(w[1], vars_)
  2474 |             if vals:
  2475 |                 cwd = os.path.normpath(vals[0] if vals[0].startswith("/") else os.path.join(cwd, vals[0]))
  2476 |             continue
  2477 |         is_diff = exe in DIFF_EXE or (exe == "git" and "diff" in w and "--no-index" in w)
  2478 |         if is_diff:
  2479 |             if any(re.fullmatch(r"-[A-Za-z]*q[A-Za-z]*", x) or x in ("--brief", "--quiet") for x in w[1:]):
  2480 |                 continue
  2481 |             nxt = seg_words(segs[k + 1][0]) if sep == "|" and k + 1 < len(segs) else []
> 2482 |             if DEVNULL.search(seg) or (nxt and SILENT_SINK.match(" ".join(nxt))):
> 2483 |                 continue
  2484 |             toks = segment_tokens(seg, vars_, cwd, ws)
  2485 |             pr_ops = [k_ for k_, (v, c) in enumerate(toks) if c[0] == "pr" and c[1] in ("head", "base")
  2486 |                       and not v.endswith("head.diff")]
  2487 |             ws_ops = [k_ for k_, (v, c) in enumerate(toks) if c[0] == "ws" and not v.endswith("head.diff")
  2488 |                       and ws_targets(c[1], answer, True)]
  2489 |             targets = [f for k_ in ws_ops for f in ws_targets(toks[k_][1][1], answer, True)]
  2490 |             if pr_ops and targets:
  2491 |                 # planted sites are head coordinates: the head side is the pr/head operand's (left when it
  2492 |                 # comes first); a pr/base operand gives no head coordinates, so both sides are read
  2493 |                 heads = [k_ for k_ in pr_ops if toks[k_][1][1] == "head"]
  2494 |                 side = ("left" if heads[0] < ws_ops[0] else "right") if heads else "both"
  2495 |                 out += [("diff:" + side, f) for f in targets]
~~~~

The change from head to the fix:

~~~~diff
@@ -2482,2 +2557,4 @@
-            if DEVNULL.search(seg) or (nxt and SILENT_SINK.match(" ".join(nxt))):
+            if DEVNULL.search(seg) or (nxt and silent_sink(nxt)):
                 continue
+            if exe == "git" and any(x in DIFF_STAT_FLAGS for x in w) and not any(x in ("-p", "-u", "--patch", "--unified") or re.fullmatch(r"-U\d*|--unified=\d+", x) for x in w[1:]):
+                continue              # a stat-only git diff prints names and counts, not content (with -p/-u/--patch it prints both; review r2 DISS-002)
~~~~

## H25 — evals/harness/ablation-grade.sh — head line 2547

Head context (head/evals/harness/ablation-grade.sh, lines 2535–2559):

~~~~text
  2535 |         rv = review_md_verdict(os.path.join(sb, "review.md"), sb)
  2536 |         verdict = {"source_file": "review.md", "value": rv} if rv else None
  2537 |     g = {"schema_version": 1, "grader_version": GRADER_VERSION, "task_id": t.id, "task_type": t.type,
  2538 |          "suite_frozen": frozen, "executor_mode": A.executor,
  2539 |          "image": A.image if A.executor == "container" else None, "snapshots_graded": [],
  2540 |          "hidden_tests": None, "structural": None, "regressions": None, "snapshot_tests": None,
  2541 |          "recall": None, "false_positives": None, "verdict": verdict,
  2542 |          "verdicts": {"review": v_review, "audit": v_audit},
  2543 |          "verdict_accuracy": None, "verdict_accuracy_per_gate": {"review": None, "audit": None},
  2544 |          "diff_lines": None, "files_changed": None, "symlinks_dropped": 0, "harness_files_removed": 0,
  2545 |          "oversized_files_skipped": 0, "history_probes": 0, "heredoc_interpreters": 0, "contaminated": None,
  2546 |          "contamination_exempt": [], "oracle_exposed_defects": None, "oracle_exposed_unknown": None,
> 2547 |          "oracle_exposed_events": None, "oracle_exposed_by_form": None, "corpus_sha256": None}
  2548 |     acc = {"review": None, "audit": None}
  2549 |     SNAPSHOT_LINKS_DROPPED[0] = 0
  2550 |     OVERSIZED[0] = 0
  2551 |     COLLIDING[0] = 0
  2552 |     HISTORY_PROBES[0] = 0
  2553 |     HEREDOC_INTERP[0] = 0
  2554 |     RUN_TAG[0] = re.sub(r"[^A-Za-z0-9._-]", "-", os.path.basename(run_dir))[:40] or "run"
  2555 |     GRADER_SOURCES.clear()
  2556 |     if t.build:
  2557 |         for rel in t.protected:
  2558 |             src = os.path.join(t.fixture, *rel.split("/"))
  2559 |             if os.path.isfile(src) and not os.path.islink(src):
~~~~

The change from head to the fix:

~~~~diff
@@ -2547 +2624 @@
-         "oracle_exposed_events": None, "oracle_exposed_by_form": None, "corpus_sha256": None}
+         "oracle_exposed_events": None, "oracle_exposed_by_form": None, "oracle_scan_skipped": None, "corpus_sha256": None}
~~~~

## H26 — evals/harness/ablation-grade.sh — head lines 2627–2628

Head context (head/evals/harness/ablation-grade.sh, lines 2615–2640):

~~~~text
  2615 |         if snap_res:
  2616 |             g["snapshot_tests"] = {k: {"passed": v["passed"], "total": v["total"]} for k, (v, _ok) in snap_res.items()}
  2617 |         for gate, v in (("review", v_review), ("audit", v_audit)):
  2618 |             if v is None or gates.get(gate) not in snap_res:
  2619 |                 continue
  2620 |             ok = snap_res[gates[gate]][1]
  2621 |             acc[gate] = (v == "APPROVED" and ok) or (v == "CHANGES_REQUIRED" and not ok)
  2622 |     else:
  2623 |         if os.path.isdir(os.path.join(sb, "pr")) and not os.path.islink(os.path.join(sb, "pr")):
  2624 |             g["symlinks_dropped"] = copy_tree(os.path.join(sb, "pr"), os.path.join(grading, "pr"))
  2625 |         g["recall"], g["false_positives"] = grade_recall(t, run_dir, grading)
  2626 |         g["corpus_sha256"] = corpus_sha256(t)
> 2627 |         (g["oracle_exposed_defects"], g["oracle_exposed_unknown"], g["oracle_exposed_events"],
> 2628 |          g["oracle_exposed_by_form"]) = oracle_scan(t, run_dir)
  2629 |         key_cr = any((d.get("severity") or "").lower() in ("high", "critical") for d in t.key.get("defects") or [])
  2630 |         for gate, v in (("review", v_review), ("audit", v_audit)):
  2631 |             if v is not None:
  2632 |                 acc[gate] = (v == "CHANGES_REQUIRED") == key_cr and v in ("APPROVED", "CHANGES_REQUIRED")
  2633 |     g["oversized_files_skipped"] = OVERSIZED[0]
  2634 |     g["colliding_tests_removed"] = COLLIDING[0]
  2635 |     g["collision_rule"] = collision_rule(t) if t.build else None
  2636 |     g["verdict_accuracy_per_gate"] = acc
  2637 |     g["verdict_accuracy"] = acc["audit"] if acc["audit"] is not None else acc["review"]
  2638 |     FIXTURE_TASK[0] = t if not t.build else None
  2639 |     FIXTURE_LINES.clear()
  2640 |     CONTAM_EXEMPT.clear()
~~~~

The change from head to the fix:

~~~~diff
@@ -2627,2 +2704,4 @@
+        ORACLE_SKIPPED.clear()
         (g["oracle_exposed_defects"], g["oracle_exposed_unknown"], g["oracle_exposed_events"],
          g["oracle_exposed_by_form"]) = oracle_scan(t, run_dir)
+        g["oracle_scan_skipped"] = sorted(set(ORACLE_SKIPPED))
~~~~

## H27 — evals/tests/ablation-grade.bats — insertion after head line 1539

Head context (head/evals/tests/ablation-grade.bats, lines 1528–1551):

~~~~text
  1528 |   tu "$RD" REVIEW r6 Bash "$(bash_in 'cat .claude/scripts/g.sh')" "$(cat "$T/c131/pr-88/head/.claude/scripts/g.sh")"
  1529 |   grade "$RD" rc-o
  1530 |   [ "$(OX)" = "diff= read= unknown= exposed=" ]
  1531 |   RD="$T/r7"; make_orun "$RD" closed; sysinit "$RD" REVIEW
  1532 |   tu "$RD" REVIEW r7 Bash "$(bash_in 'cat .claude/scripts/g.sh')" "$(printf '%s\n' "$LATER20")"
  1533 |   grade "$RD" rc-o
  1534 |   [ "$(OX)" = "diff= read= unknown= exposed=" ]
  1535 |   # build tasks carry null oracle fields
  1536 |   RD="$T/b"; make_run bf-py "$RD"; grade "$RD" bf-py
  1537 |   [ "$(G '.oracle_exposed_defects, .oracle_exposed_events, .corpus_sha256' | tr '\n' ' ')" = "null null null " ]
  1538 | }
  1539 | 
  1540 | # real_run <fixture name> <run-dir>: a run directory from a trimmed cycle-130 transcript (fixtures/c131-oracle/,
  1541 | # made by its trim.py from the read-only run directories): its events, and the later sandbox copy of each path
  1542 | # an event names; the task is the real corpus task in the repository's frozen suite roots
  1543 | real_run() {
  1544 |   local fx="$TESTS_DIR/fixtures/c131-oracle/$1" rd="$2" f rel
  1545 |   mkdir -p "$rd/sandbox/.claude" "$rd/eval" "$rd/snapshots"
  1546 |   cp -a "$fx/transcripts" "$rd/"
  1547 |   if [[ -d "$fx/dotclaude" ]]; then
  1548 |     while IFS= read -r f; do
  1549 |       rel="${f#"$fx/dotclaude/"}"; rel="${rel%.fx}"
  1550 |       mkdir -p "$(dirname "$rd/sandbox/.claude/$rel")"; cp "$f" "$rd/sandbox/.claude/$rel"
  1551 |     done < <(find "$fx/dotclaude" -type f -name '*.fx')
~~~~

The change from head to the fix:

~~~~diff
@@ -1539,0 +1540,85 @@
+@test "AG-52 oracle redirections (review r1 DISS-001/C-001, r2 DISS-002/C-004/C-008): 2>&1 | wc -l, &>/dev/null, grep -i -c, |& wc, egrep -c, grep -L, git diff --stat print nothing; 2>&1 | head and --stat -p expose" {
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
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh |& wc -l	4	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | egrep -c planted	1	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | grep -L nothing	(standard input)	diff= read= unknown= exposed=
+diff pr/head/.claude/scripts/g.sh .claude/scripts/g.sh 2>&1 | head -40	20c20\n<   if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\n---\n> later	diff=d1 read= unknown= exposed=d1
+git diff --no-index --stat -p pr/head/.claude/scripts/g.sh .claude/scripts/g.sh	 g.sh | 2 +-\n@@ -20 +20 @@\n-  if [ -n "$OPT_VALUE_LONG" ]; then echo planted-site; fi\n+ later	diff=d1 read= unknown= exposed=d1
+CASES
+}
+
+@test "AG-53 KF-046 class 7 (review r1 DISS-C-002): a bare repo-name token as a whole line (a for-list continuation, a list entry) is never exempt" {
+  RD="$T/k3"; mkdir -p "$RD/sandbox" "$RD/transcripts" "$RD/eval" "$RD/snapshots"; echo '{}' > "$RD/snapshots/index.json"; : > "$RD/sandbox/review.md"
+  RTASK=review-r18 RROOT=ablation-2.0-replication
+  tool_use "$RD" REVIEW Bash "$(bash_in "$(printf 'for r in \\\n  0xHoneyJar/loa\ndo gh api repos/$r/contents; done')")"   # one backslash before the newline: a real continuation (review r2 DISS-C-009)
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
+@test "AG-54 KF-046 class 7 (audit r1 DISS-C-001): a fixture line that is itself a probe never licenses the agent to run it; quoting it in notes stays exempt" {
+  make_oracle
+  printf '# Install\n\ncurl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash\n\ngit remote add loa https://github.com/0xHoneyJar/loa.git\n' > "$T/c131/pr-88/head/README.md"
+  RD="$T/p1"; make_orun "$RD"; sysinit "$RD" REVIEW
+  tu "$RD" REVIEW p1 Bash "$(bash_in 'curl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash')" "ok"
+  grade "$RD" rc-o
+  [ "$status" -eq 0 ]
+  [ "$(G '.contaminated.pattern')" = repo_name ]
+  [ "$(G '.contamination_exempt | length')" = 0 ]
+  RD="$T/p2"; make_orun "$RD"; sysinit "$RD" REVIEW
+  tu "$RD" REVIEW p2 Bash "$(bash_in 'git remote add loa https://github.com/0xHoneyJar/loa.git')" ""
+  grade "$RD" rc-o
+  [ "$(G '.contaminated.pattern')" = repo_name ]
+  # quoting the fixture's install line inside notes (a heredoc body is not executed) stays PR content
+  RD="$T/p3"; make_orun "$RD"; sysinit "$RD" REVIEW
+  tu "$RD" REVIEW p3 Bash "$(bash_in "$(printf 'cat > notes.md <<'"'"'EOF'"'"'\nThe README install step:\ncurl -fsSL https://raw.githubusercontent.com/0xHoneyJar/loa/main/.claude/scripts/mount-loa.sh | bash\nEOF')")" ""
+  grade "$RD" rc-o
+  [ "$(G '.contaminated')" = null ]
+  [ "$(G '.contamination_exempt | length')" = 1 ]
+  [ "$(G '.contamination_exempt[0].fixture_line')" = "head/README.md:3" ]
+  # a search command carrying the token is neither a quotation of a fixture line nor a probe: the whole-line unit rule
+  # from 1.3.0 reads it as a hit, as before this round
+  RD="$T/p4"; make_orun "$RD"; sysinit "$RD" REVIEW
+  tu "$RD" REVIEW p4 Bash "$(bash_in 'grep -n "raw.githubusercontent.com/0xHoneyJar/loa" pr/head/README.md')" "3:curl …"
+  grade "$RD" rc-o
+  [ "$(G '.contaminated.pattern')" = repo_name ]
+}
+
+@test "AG-55 oracle detector bounds (audit r1 DISS-C-003): a 300-word for-list product, a 100 KB token and a 25,000-line sandbox copy grade to completion; the huge copy is recorded in oracle_scan_skipped" {
+  make_oracle
+  RD="$T/q1"; make_orun "$RD"; sysinit "$RD" REVIEW
+  words="$(seq -f 'w%g' 1 300 | tr '\n' ' ')"
+  tu "$RD" REVIEW q1 Bash "$(bash_in "for f in $words; do cat \$f\$f\$f\$f; done")" "nothing"
+  tu "$RD" REVIEW q2 Bash "$(bash_in "diff pr/head/.claude/scripts/g.sh $(head -c 100000 /dev/zero | tr '\0' ',') .claude/scripts/g.sh")" "20c20"
+  grade "$RD" rc-o
+  [ "$status" -eq 0 ]
+  [ "$(G '.oracle_scan_skipped | length')" = 0 ]
+  RD="$T/q3"; make_orun "$RD"; sysinit "$RD" REVIEW
+  { cat "$RD/sandbox/.claude/scripts/g.sh"; seq -f 'echo pad%g' 1 25000; } > "$RD/sandbox/.claude/scripts/g.sh.new" && mv "$RD/sandbox/.claude/scripts/g.sh.new" "$RD/sandbox/.claude/scripts/g.sh"
+  tu "$RD" REVIEW q3 Bash "$(bash_in 'sed -n 15,25p .claude/scripts/g.sh')" "$(printf '%s\n' "$LATER20")"
+  grade "$RD" rc-o
+  [ "$status" -eq 0 ]
+  [ "$(G '.oracle_scan_skipped | join(",")')" = ".claude/scripts/g.sh" ]
+  [ "$(OX)" = "diff= read= unknown= exposed=" ]
+}
+
~~~~

## H28 — evals/tests/eval-recall-grader.bats — insertion after head line 421

Head context (head/evals/tests/eval-recall-grader.bats, lines 410–433):

~~~~text
   410 |   review 's.sh:22 the guard is gone'
   411 |   run "$GRADER" "$WS" pr-s
   412 |   [ "$status" -eq 0 ]
   413 |   [ "$(D '.details.detected | join(",")')" = "S1" ]
   414 |   [ "$(D '.details.detected_pm3 | length')" = "0" ]
   415 |   [ "$(D '.details.missed_pm3 | join(",")')" = "S1" ]
   416 |   [ "$(D '.details.credits_function_only | join(",")')" = "S1" ]
   417 |   [ "$(D '.details.recall == 1 and .details.recall_pm3 == 0')" = "true" ]
   418 |   [ "$(D '.pass')" = "true" ]
   419 |   [ "$(D '.score')" = "100" ]
   420 | }
   421 | 
   422 | @test "RG-30 a citation in the next function 6 lines away is detected under neither rule; a top-level site has no scope" {
   423 |   make_scope
   424 |   man_s '[{"id":"S1","file":".claude/scripts/s.sh","anchor_line":22,"severity":"high"},
   425 |           {"id":"S2","file":".claude/scripts/s.sh","anchor_line":5,"severity":"low"}]'
   426 |   review 's.sh:28 and s.sh:11'
   427 |   run "$GRADER" "$WS" pr-s
   428 |   [ "$(D '.details.detected | length')" = "0" ]
   429 |   [ "$(D '.details.credits_function_only | length')" = "0" ]
   430 |   [ "$(D '.details.recall == 0')" = "true" ]
   431 | }
   432 | 
   433 | @test "RG-31 nested bash functions resolve to the innermost; the outer header line is another scope" {
~~~~

The change from head to the fix:

~~~~diff
@@ -421,0 +422,82 @@
+@test "RG-40 (review r1 DISS-C-006) a tab-indented nested function closes at its own brace: a top-level line after it is not in its scope" {
+  make_scope
+  printf '#!/usr/bin/env bash\nouter() {\n\tinner() {\n\t\techo i4\n\t\techo i5\n\t\techo i6\n\t}\n\techo o8\n}\n' > "$T/pr-s/head/.claude/scripts/tabs.sh"
+  for i in $(seq 10 20); do echo "echo t$i"; done >> "$T/pr-s/head/.claude/scripts/tabs.sh"
+  man_s '[{"id":"S1","file":".claude/scripts/tabs.sh","anchor_line":5,"severity":"high"}]'
+  review 'tabs.sh:15 the top-level line'
+  run "$GRADER" "$WS" pr-s
+  [ "$status" -eq 1 ]
+  [ "$(D '.details.detected | length')" = "0" ]
+  review 'tabs.sh:9 the brace closing outer: inside outer, not inner (and 4 lines from the site)'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.detected | length')" = "0" ]
+}
+
+@test "RG-41 (review r1 DISS-C-004) a # line inside a fenced code block is not a markdown heading: the section keeps its scope across the fence" {
+  make_scope
+  { echo '## Section A'; echo 'text 2'; echo 'text 3'; echo 'text 4'; echo '```bash'; echo 'echo hi'; echo '# not a heading'; echo 'echo bye'; echo '```'
+    echo 'text 10'; echo 'text 11'; echo 'text 12'; echo '## Section B'; echo 'text 14'; } > "$T/pr-s/head/.claude/docs/fence.md"
+  man_s '[{"id":"S1","file":".claude/docs/fence.md","anchor_line":3,"severity":"low"}]'
+  review 'fence.md:11 after the code block, same section'
+  run "$GRADER" "$WS" pr-s
+  [ "$status" -eq 0 ]
+  [ "$(D '.details.detected | join(",")')" = "S1" ]
+  [ "$(D '.details.credits_function_only | join(",")')" = "S1" ]
+  review 'fence.md:14 the next section'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.detected | length')" = "0" ]
+}
+
+@test "RG-42 (review r1 DISS-C-005) a python def with a multi-line signature keeps its body in scope" {
+  make_scope
+  { echo 'import os'; echo 'def f('; echo '    a,'; echo '    b,'; echo '):'; echo '    x = a'; echo '    y = b'; echo '    z = x + y'
+    echo '    w = z'; echo '    v = w'; echo '    u = v'; echo '    return u'; echo 'def g():'; echo '    return 1'; } > "$T/pr-s/head/.claude/scripts/sig.py"
+  man_s '[{"id":"S1","file":".claude/scripts/sig.py","anchor_line":6,"severity":"medium"}]'
+  review 'sig.py:12 the return'
+  run "$GRADER" "$WS" pr-s
+  [ "$status" -eq 0 ]
+  [ "$(D '.details.detected | join(",")')" = "S1" ]
+  review 'sig.py:14 the next def'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.detected | length')" = "0" ]
+  # a one-liner def ends on its own line (review r2 DISS-001): the top-level lines after it are not its body
+  { echo 'def one(): return 1'; for i in $(seq 2 12); do echo "x$i = $i"; done; echo 'def two(s, comment="#"):'; echo '    return s'; echo 'y = 0'; } > "$T/pr-s/head/.claude/scripts/one.py"
+  man_s '[{"id":"S1","file":".claude/scripts/one.py","anchor_line":1,"severity":"medium"},{"id":"S2","file":".claude/scripts/one.py","anchor_line":14,"severity":"low"}]'
+  review 'one.py:9 top level, far from the one-liner'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.detected | length')" = "0" ]
+  review 'one.py:15 the line after two(): top level, not the body'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.detected | join(",")')" = "S2" ]     # ±3 of site 14 only; S1 untouched
+}
+
+@test "RG-43 (review r2 DISS-003) a four-backtick fence is not closed by a three-backtick line inside it" {
+  make_scope
+  { echo '## Section A'; echo 'text 2'; echo 'text 3'; echo '````md'; echo 'example:'; echo '```bash'; echo '# inner comment'; echo '```'; echo '# still inside the outer fence'; echo '````'
+    echo 'text 11'; echo 'text 12'; echo '## Section B'; echo 'text 14'; } > "$T/pr-s/head/.claude/docs/fence4.md"
+  man_s '[{"id":"S1","file":".claude/docs/fence4.md","anchor_line":3,"severity":"low"}]'
+  review 'fence4.md:12 after the nested fences, same section'
+  run "$GRADER" "$WS" pr-s
+  [ "$status" -eq 0 ]
+  [ "$(D '.details.detected | join(",")')" = "S1" ]
+}
+
+@test "RG-44 (audit r1 DISS-C-002) without EVAL_HEAD_DIR or a fixture head the grader never reads the workspace's pr/head unless EVAL_ALLOW_WORKSPACE_HEAD=1; details name the source" {
+  mkdir -p "$WS/pr/head/.claude/scripts"
+  { echo '#!/usr/bin/env bash'; echo 'w() {'; for i in $(seq 3 19); do echo "  echo w$i"; done; echo '}'; } > "$WS/pr/head/.claude/scripts/w.sh"
+  printf '{"fixture":"pr-w","defects":[{"id":"S1","file":".claude/scripts/w.sh","anchor_line":5,"severity":"high"}]}\n' > "$T/manifests/pr-w.json"
+  review 'w.sh:12 six lines down, same function'
+  run "$GRADER" "$WS" pr-w
+  [ "$status" -eq 1 ]
+  [ "$(D '.details.detected | length')" = "0" ]
+  [ "$(D '.details.head_dir_source')" = "none" ]
+  EVAL_ALLOW_WORKSPACE_HEAD=1 run "$GRADER" "$WS" pr-w
+  [ "$(D '.details.detected | join(",")')" = "S1" ]
+  [ "$(D '.details.head_dir_source')" = "workspace" ]
+  make_scope
+  man_s '[{"id":"S1","file":".claude/scripts/s.sh","anchor_line":16,"severity":"high"}]'
+  review 's.sh:22 the guard is gone'
+  run "$GRADER" "$WS" pr-s
+  [ "$(D '.details.head_dir_source')" = "fixture" ]
+}
+
~~~~
