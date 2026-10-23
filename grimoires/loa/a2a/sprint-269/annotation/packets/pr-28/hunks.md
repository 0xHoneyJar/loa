# Hunks — pr-28

The later fix changed 9 region(s) in 4 of the change's 11 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — evals/harness/ablation-report.py — head line 1913

Head context (head/evals/harness/ablation-report.py, lines 1901–1925):

~~~~text
  1901 |         rows = kept
  1902 |     mans = load_manifests(args.manifests)
  1903 |     arms = [a for a in suite["arms"] if isinstance(a, dict) and a.get("id")]
  1904 |     arm_ids = [a["id"] for a in arms]
  1905 |     labels = {str(a.get("label", a["id"])).upper(): a["id"] for a in arms}
  1906 |     cuts = load_cuts(args.cuts, args.not_run, set(arm_ids), labels)
  1907 |     for need in (CONTROL, BARE):
  1908 |         if need not in arm_ids:
  1909 |             raise Fail(f"suite has no arm {need}")
  1910 | 
  1911 |     # components: every runnable arm but the two baselines; an eval_only arm (cycle-131 FR-5: the open-mount
  1912 |     # oracle A/B) is an evaluation control, never a shipped-default decision, so it is not a component here
> 1913 |     components = [a["id"] for a in arms if a["id"] not in (CONTROL, BARE) and not a.get("absent") and a.get("eval_only") is not True]
  1914 |     absent = [a for a in arms if a.get("absent")]
  1915 |     seed = args.seed
  1916 |     groups, primary, unversioned = partition(rows, args.suite_version, mans,
  1917 |                                              {a["id"]: a for a in arms})
  1918 |     versions = sorted(groups, key=part_order(groups), reverse=True)
  1919 |     others = [v for v in versions if v != primary]
  1920 |     VS = {v: analyse(suite, groups[v], mans, args, cuts, components, v) for v in versions}
  1921 |     # version-less rows that never reach a decision: listed under the primary version (report 1.2.1)
  1922 |     VS[primary]["main"].listed.extend(unversioned)
  1923 |     P = VS[primary]
  1924 |     main, decisions, sens_rows = P["main"], P["decisions"], P["sens_rows"]
  1925 |     h1_comps, a4 = P["h1_comps"], P["a4"]
~~~~

The change from head to the fix:

~~~~diff
@@ -1913 +1913,6 @@
-    components = [a["id"] for a in arms if a["id"] not in (CONTROL, BARE) and not a.get("absent") and a.get("eval_only") is not True]
+    def is_eval_only(a):   # the flag, or the property it protects (audit r1 DISS-C-002)
+        return a.get("eval_only") is True or (a.get("toggles") or {}).get("oracle_open") is True
+    for a in arms:
+        if not a.get("absent") and (a.get("toggles") or {}).get("oracle_open") is True and a.get("eval_only") is not True:
+            raise Fail(f"suite arm {a.get('id')} opens the oracle (toggles.oracle_open: true) without eval_only: true")
+    components = [a["id"] for a in arms if a["id"] not in (CONTROL, BARE) and not a.get("absent") and not is_eval_only(a)]
~~~~

## H02 — evals/harness/ablation-report.py — insertion after head line 1927

Head context (head/evals/harness/ablation-report.py, lines 1916–1939):

~~~~text
  1916 |     groups, primary, unversioned = partition(rows, args.suite_version, mans,
  1917 |                                              {a["id"]: a for a in arms})
  1918 |     versions = sorted(groups, key=part_order(groups), reverse=True)
  1919 |     others = [v for v in versions if v != primary]
  1920 |     VS = {v: analyse(suite, groups[v], mans, args, cuts, components, v) for v in versions}
  1921 |     # version-less rows that never reach a decision: listed under the primary version (report 1.2.1)
  1922 |     VS[primary]["main"].listed.extend(unversioned)
  1923 |     P = VS[primary]
  1924 |     main, decisions, sens_rows = P["main"], P["decisions"], P["sens_rows"]
  1925 |     h1_comps, a4 = P["h1_comps"], P["a4"]
  1926 | 
  1927 |     k = len(components)
  1928 |     efp = k * (1.0 - args.level) / 2.0
  1929 |     efp_line = (f"Expected false positives at level {args.level:.2f} over {k} components: "
  1930 |                 f"{k} × (1 − {args.level:.2f}) / 2 = {efp:.2f} one-sided per direction "
  1931 |                 f"({2 * efp:.2f} in either direction); no multiple-comparison correction is applied "
  1932 |                 f"(multiple_comparisons: {rules.get('multiple_comparisons', 'none')}).")
  1933 | 
  1934 |     # provenance
  1935 |     used = [m for b, m in sorted(mans.items()) if any(r["batch"] == b for r in rows)] or \
  1936 |         [m for _, m in sorted(mans.items())]
  1937 | 
  1938 |     def distinct(key, rowkey=None):
  1939 |         vals = {str(m.get(key)) for m in used if m.get(key) not in (None, "")}
~~~~

The change from head to the fix:

~~~~diff
@@ -1927,0 +1933,5 @@
+    eval_only_arms = [a["id"] for a in arms if is_eval_only(a) and not a.get("absent")]
+    eval_only_counts = {aid: sum(1 for r in P.get("rows", []) if r.get("arm") == aid) for aid in eval_only_arms}
+    eval_only_line = ("Evaluation-only arms (not components): " +
+                      (", ".join(f"{aid} ({n} rows)" for aid, n in eval_only_counts.items()) if eval_only_counts else "none") +
+                      " — read by their own pre-registered contrast, never by a decision here.")
~~~~

## H03 — evals/harness/ablation-report.py — insertion after head line 1998

Head context (head/evals/harness/ablation-report.py, lines 1987–2010):

~~~~text
  1987 | 
  1988 |     def mark(v, pre):
  1989 |         return "" if v == pre else f" (NOT the pre-registered {pre})"
  1990 | 
  1991 |     L(f"- bootstrap: {args.resamples} resamples{mark(args.resamples, int(pre_res))}, level {args.level:.2f}"
  1992 |       f"{mark(args.level, float(pre_lvl))}, seed {seed}; exclusion statuses "
  1993 |       f"{', '.join(sorted(main.ex_statuses))}; degraded rows excluded: {str(args.exclude_degraded).lower()}")
  1994 |     L("")
  1995 |     L("## Decisions")
  1996 |     L("")
  1997 |     render_decisions(L, P, absent, rules)
  1998 |     L(efp_line)
  1999 |     L("")
  2000 | 
  2001 |     L("## Per-arm detail")
  2002 |     L("")
  2003 |     detail_arms = [BARE, CONTROL] + components
  2004 |     metrics = render_per_arm(L, P, detail_arms, "###")
  2005 | 
  2006 |     render_exclusions(L, P, dups, "##", "###")
  2007 | 
  2008 |     L("## Cuts")
  2009 |     L("")
  2010 |     pw = [d for d in decisions if d["state"] == "inconclusive_by_power" and d["arm"] not in cuts]
~~~~

The change from head to the fix:

~~~~diff
@@ -1998,0 +2009 @@
+    L(eval_only_line)
~~~~

## H04 — evals/harness/ablation-report.py — head line 2174

Head context (head/evals/harness/ablation-report.py, lines 2162–2186):

~~~~text
  2162 |                        "suite_versions": distinct("suite_version"), "image_digests": distinct("image_digest"),
  2163 |                        "batches": [{"batch": b, "smoke": m.get("smoke") is True, "shuffle_seed": m.get("shuffle_seed"),
  2164 |                                     "pre_registration_ref": m.get("pre_registration_ref"),
  2165 |                                     "source_commit": m.get("source_commit"), "image_digest": m.get("image_digest"),
  2166 |                                     "cli_version": cli(m), "manifest": m["_path"]} for b, m in sorted(mans.items())]},
  2167 |         "bootstrap": {"resamples": args.resamples, "level": args.level, "seed": seed},
  2168 |         "exclude_degraded": bool(args.exclude_degraded),
  2169 |         "decisions": decisions_json(decisions),
  2170 |         "absent": [{"arm": a["id"], "label": a.get("label"), "state": "component_absent",
  2171 |                     "evidence": a.get("evidence")} for a in absent],
  2172 |         "h1": h1_json(P, rules),
  2173 |         "a4": a4_json(P, rules),
> 2174 |         "expected_false_positives": {"components": k, "per_direction": j6(efp), "line": efp_line},
  2175 |         "arms": arms_json(metrics),
  2176 |         "exclusions": exclusions_json(P),
  2177 |         "listed": listed_json(P),
  2178 |         "duplicates": dups,
  2179 |         "cap_failures": [r["run_id"] for r in P["caps"]],
  2180 |         "cuts": [dict(arm=a, **cuts[a]) for a in sorted(cuts)],
  2181 |         "sensitivity": dict(sens_json(P), label=SENS_LABEL),
  2182 |         "sensitivities": extra_json(P),
  2183 |         "decision_statistic": CATCH, "beside": [CATCH_PM3, CATCH_PM3_V1], "min_valid_cells": main.min_cells,
  2184 |         "pin": args.pin, "pin_dropped_rows": pin_dropped,
  2185 |         "oracle_exposed_in_main": "excluded" if args.exclude_oracle_exposed == "true" else "included",
  2186 |         "budget_matched": budget_json(P["budget"]),
~~~~

The change from head to the fix:

~~~~diff
@@ -2174 +2185,2 @@
-        "expected_false_positives": {"components": k, "per_direction": j6(efp), "line": efp_line},
+        "expected_false_positives": {"components": k, "per_direction": j6(efp), "line": efp_line,
+                                     "eval_only_arms": eval_only_counts},
~~~~

## H05 — evals/harness/pipeline-run.sh — head line 141

Head context (head/evals/harness/pipeline-run.sh, lines 129–153):

~~~~text
   129 | # eval-only open-mount arm) skips the overlay and the check and records mount_overlay=none.
   130 | # Every mounted arm runs the cycle-131 eval config variant (both gates' budget_scale: diff,
   131 | # budget_cents_max 600; evidence config_variant=eval). Toggle bare_model: fable runs the BARE
   132 | # phase on global.anthropic.claude-fable-5-1 (it wins over --phase-models and the suite's
   133 | # phase_defaults for BARE). All evidence reaches meta/arm-evidence.txt before the first phase.
   134 | # Mount integrity (audit LOW-A2): after materialisation the sha256 of sandbox/CLAUDE.md
   135 | # and sandbox/.loa.config.yaml go to arm_evidence (claude_md_sha256, loa_config_sha256 =
   136 | # <hex>|absent); at finish both are recomputed into pipeline.json.mount_integrity =
   137 | # {claude_md, loa_config} each ok|changed|absent (loa_mount: false → both absent; null
   138 | # when the run stopped before materialisation). `.claude/` itself is covered by
   139 | # took-effect.sh integrity_clean.
   140 | #
>  141 | # eval_only arms (cycle-131 FR-5): an arm declaring `eval_only: true` (a1_full_openmount) is
   142 | # refused — exit 2, `refused: arm '<id>': eval_only arm outside an evaluation batch`, before the
   143 | # run directory exists, so no pipeline.json and no infrastructure_error is ever written — unless
   144 | # LOA_ABLATION_BATCH_CONTEXT=1 (exactly 1). run-ablation.sh exports it to every trial it launches
   145 | # (batch and smoke); --dry-run honours the same variable, so the operator dry-runs the
   146 | # open-mount arm with `LOA_ABLATION_BATCH_CONTEXT=1 pipeline-run.sh … --dry-run`.
   147 | #
   148 | # Env: EVAL_CLAUDE_BIN, EVAL_DOCKER_BIN, LOA_EVAL_PHASE_MODELS, LOA_EVAL_PRICING_JSON,
   149 | # LOA_EVAL_WATCHDOG_POLL_S, LOA_EVAL_CREDS_HOME (where ~/.codex is read; default $HOME),
   150 | # LOA_EVAL_CONTAINER_CLAUDE_BIN (default claude), LOA_EVAL_EXECUTOR, LOA_ABLATION_BATCH_CONTEXT.
   151 | #
   152 | # Mount library: lib/sandbox-mount.sh beside this script, sourced by a literal path.
   153 | # Exported to it: ARM_EVIDENCE_FILE, ARM_ENV_FILE (meta/arm-env), LOA_EVAL_SUITE_FILE.
~~~~

The change from head to the fix:

~~~~diff
@@ -141 +141,2 @@
-# eval_only arms (cycle-131 FR-5): an arm declaring `eval_only: true` (a1_full_openmount) is
+# eval_only arms (cycle-131 FR-5): an arm declaring `eval_only: true` (a1_full_openmount), or whose
+# toggles set `oracle_open: true`, is
~~~~

## H06 — evals/harness/pipeline-run.sh — head line 258

Head context (head/evals/harness/pipeline-run.sh, lines 246–270):

~~~~text
   246 |   REFUSAL="arm '$ARM' is not declared in the suite"
   247 | elif [[ "$(jq -r '.absent // false' <<<"$ARM_DEF")" == "true" ]]; then
   248 |   REFUSAL="arm '$ARM' is declared absent: true"
   249 | elif ! jq -e --arg k "$KIND" --arg t "$TASK_TYPE" \
   250 |        '(.task_types // ["all"]) as $tt | ($tt | index("all")) or ($tt | index($k)) or ($tt | index($t))' \
   251 |        >/dev/null <<<"$ARM_DEF"; then
   252 |   REFUSAL="arm '$ARM' does not apply to task type '$TASK_TYPE' (task_types $(jq -c '.task_types' <<<"$ARM_DEF"))"
   253 | fi
   254 | [[ -n "$ARM_DEF" ]] || ARM_DEF='{}'
   255 | SUITE_TOGGLES="$(jq -c '.toggles // {}' <<<"$ARM_DEF")"
   256 | # eval_only (cycle-131 FR-5): refused before anything is created, dry run included, unless the
   257 | # runner marks the batch context; no pipeline.json, so no infrastructure_error row is possible
>  258 | EVAL_ONLY=false; [[ "$(jq -r '.eval_only // false' <<<"$ARM_DEF")" == true ]] && EVAL_ONLY=true
   259 | if [[ "$EVAL_ONLY" == true && "${LOA_ABLATION_BATCH_CONTEXT:-}" != 1 ]]; then
   260 |   echo "pipeline-run.sh: refused: arm '$ARM': eval_only arm outside an evaluation batch (run-ablation.sh exports LOA_ABLATION_BATCH_CONTEXT=1 to its trials)" >&2
   261 |   exit 2
   262 | fi
   263 | 
   264 | # plan_phases <toggles-json> → JSON array of {name,label}
   265 | plan_phases() {
   266 |   jq -c -n --argjson arm "$ARM_DEF" --argjson suite "$SUITE_JSON" --argjson tg "$1" --arg kind "$KIND" '
   267 |     ( if $kind == "review-catch" then ["REVIEW","AUDIT"] else ["PLAN","IMPLEMENT","REVIEW","FIX","AUDIT","FIX"] end ) as $dflt
   268 |     | ( $arm.phases // $suite.phase_sets[$kind] // $dflt ) as $p0
   269 |     | ( if ($tg.loa_mount == false) then ["BARE"] else $p0 end ) as $p1
   270 |     | ( if ($tg.sprint_plan == false) then ($p1 | map(select(. != "PLAN"))) else $p1 end ) as $p2
~~~~

The change from head to the fix:

~~~~diff
@@ -258 +259,15 @@
-EVAL_ONLY=false; [[ "$(jq -r '.eval_only // false' <<<"$ARM_DEF")" == true ]] && EVAL_ONLY=true
+# eval_only is derived from the property it protects as well as from the flag (review r1 DISS-C-002): an arm whose
+# toggles open the mount (oracle_open: true) is evaluation-only whatever the suite says; a present eval_only that is
+# not a JSON boolean is refused rather than read as false
+case "$(jq -r 'if has("eval_only") then (.eval_only | type) else "absent" end' <<<"$ARM_DEF")" in
+  absent|boolean) ;;
+  *) echo "pipeline-run.sh: refused: arm '$ARM': eval_only must be a JSON boolean (true|false)" >&2; exit 2 ;;
+esac
+# the toggle that opens the mount is held to the same type rule, so the strict `== true` below and the mount
+# path's loose text read can never disagree on a quoted "true" (audit r1 DISS-C-001)
+case "$(jq -r 'if (.toggles // {}) | has("oracle_open") then (.toggles.oracle_open | type) else "absent" end' <<<"$ARM_DEF")" in
+  absent|boolean) ;;
+  *) echo "pipeline-run.sh: refused: arm '$ARM': toggles.oracle_open must be a JSON boolean (true|false)" >&2; exit 2 ;;
+esac
+EVAL_ONLY=false
+[[ "$(jq -r '(.eval_only == true) or (.toggles.oracle_open == true)' <<<"$ARM_DEF")" == true ]] && EVAL_ONLY=true
~~~~

## H07 — evals/tests/ablation-report.bats — insertion after head line 189

Head context (head/evals/tests/ablation-report.bats, lines 178–201):

~~~~text
   178 | 
   179 | @test "AR-11 H1 established and A4 holds (main); H1 not established and A4 fails (boundary)" {
   180 |   [ "$(jq -r '.h1.line' "$FX/main/report.json")" = "H1: established" ]
   181 |   [ "$(jq -r '.a4.line' "$FX/main/report.json")" = "A4 sensitivity: holds" ]
   182 |   grep -qF '**H1: established** — a1_full − a0_bare: hidden_test_pass_rate +0.200 [+0.200, +0.200] (n = 12 tasks)' "$FX/main/report.md"
   183 |   [ "$(jq -r '.h1.line' "$FX/boundary/report.json")" = "H1: not established — halt before promotion" ]
   184 |   [ "$(jq -r '.a4.line' "$FX/boundary/report.json")" = "A4 sensitivity: fails — harden tasks before acting on other arms" ]
   185 |   grep -qF 'Rule (rules.h1): "a1_full beats a0_bare on at least one primary with the interval excluding zero, else halt before promotion"' "$FX/boundary/report.md"
   186 | }
   187 | 
   188 | @test "AR-12 the expected-false-positive sentence and the Method section quoting the suite rules block verbatim" {
   189 |   grep -qF 'Expected false positives at level 0.90 over 9 components: 9 × (1 − 0.90) / 2 = 0.45 one-sided per direction (0.90 in either direction); no multiple-comparison correction is applied (multiple_comparisons: none).' "$FX/main/report.md"   # 9 = a2 … a7 + the three cycle-131 control arms; a1_full_openmount is eval_only and not a component
   190 |   python3 -I - "$SUITE" "$FX/main/report.md" <<'PY'
   191 | import re, sys
   192 | suite = open(sys.argv[1], encoding="utf-8").read().splitlines()
   193 | start = next(i for i, l in enumerate(suite) if l.startswith("rules:"))
   194 | end = next((i for i in range(start + 1, len(suite)) if suite[i].strip() and not suite[i][0].isspace() and not suite[i].startswith("#")), len(suite))
   195 | block = "\n".join(suite[start:end]).rstrip()
   196 | md = open(sys.argv[2], encoding="utf-8").read()
   197 | method = md[md.index("## Method"):]
   198 | assert "```yaml\n" + block + "\n```" in method, "rules block not quoted verbatim"
   199 | PY
   200 | }
   201 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -189,0 +190 @@
+  grep -qF 'Evaluation-only arms (not components): a1_full_openmount (0 rows) — read by their own pre-registered contrast, never by a decision here.' "$FX/main/report.md"   # review r1 DISS-C-004
~~~~

## H08 — evals/tests/ablation-report.bats — insertion after head line 325

Head context (head/evals/tests/ablation-report.bats, lines 314–337):

~~~~text
   314 | 
   315 | @test "AR-22 the degradation guard also preempts Keep: the same 30.6 % excluded arm at -0.10 (hi < 0) reads Inconclusive-by-degradation" {
   316 |   cp -R "$FX/exclusions" "$T/ex"
   317 |   jq -c 'if .arm == "a5_no_flatline" and .status == "completed" then .hidden_test_pass_rate -= 0.15 else . end' \
   318 |     "$FX/exclusions/runs.jsonl" > "$T/ex/runs.jsonl"
   319 |   run python3 -I "$REPORT" --runs "$T/ex/runs.jsonl" --manifests "$T/ex/manifests" --suite "$SUITE" --out "$T/r.md" --json "$T/r.json"
   320 |   [ "$status" -eq 0 ]
   321 |   [ "$(jq -r '.decisions[] | select(.arm == "a5_no_flatline") | .comparisons[0] | (.d | . * 1000 | round) == -100 and .hi < 0' "$T/r.json")" = "true" ]
   322 |   [ "$(jq -r '.decisions[] | select(.arm == "a5_no_flatline") | .label' "$T/r.json")" = "Inconclusive-by-degradation" ]
   323 |   grep -qF 'degradation guard first' "$T/r.md"
   324 | }
   325 | 
   326 | @test "AR-23 two suite_versions are never pooled: main sections on v2 (catch-rate H1, pass rate and A4 not testable), v1 in its own section; --suite-version 1 flips the primary" {
   327 |   J="$FX/versions/report.json"; M="$FX/versions/report.md"
   328 |   [ "$(jq -r .primary_suite_version "$J")" = "2" ]
   329 |   [ "$(jq -r '.by_suite_version | keys | join(",")' "$J")" = "1,2" ]
   330 |   [ "$(jq -r .h1.line "$J")" = "H1: established" ]
   331 |   [ "$(jq -r '.h1.comparisons[] | select(.metric == "hidden_test_pass_rate") | .read' "$J")" = "not_testable" ]
   332 |   [ "$(jq -r '.h1.comparisons[] | select(.metric == "defect_catch_rate") | .d' "$J")" = "0.444444" ]
   333 |   [ "$(jq -r .a4.line "$J")" = "A4 sensitivity: not testable on suite_version 2 — no admissible build task" ]
   334 |   [ "$(jq -r .a4.state "$J")" = "not_testable" ]
   335 |   # the same task ids and trials in both versions: no duplicate-cell collision, no pooled rows
   336 |   [ "$(jq '.exclusions | length' "$J")" -eq 0 ]
   337 |   [ "$(jq -r .arms.a1_full.rows "$J")" -eq 12 ]
~~~~

The change from head to the fix:

~~~~diff
@@ -325,0 +327,8 @@
+@test "AR-12b (audit r1 DISS-C-002) the report refuses a suite arm that opens the oracle without eval_only, and counts an eval_only arm by its toggle too" {
+  SUITE_SRC="$SUITE" yq -o=json '.arms += [{"id": "x_open", "label": "XO", "task_types": ["review-catch"], "toggles": {"oracle_open": true}, "took_effect": ["integrity_clean"]}]' "$SUITE" > "$T/bad-suite.json"
+  run python3 -I "$REPORT" --runs "$FX/main/runs.jsonl" --manifests "$FX/main/manifests" --suite "$T/bad-suite.json" --out "$T/bad.md"
+  [ "$status" -ne 0 ]
+  grep -q "suite arm x_open opens the oracle (toggles.oracle_open: true) without eval_only: true" <<<"$output"
+  [ ! -e "$T/bad.md" ]
+}
+
~~~~

## H09 — evals/tests/pipeline-run.bats — insertion after head line 1245

Head context (head/evals/tests/pipeline-run.bats, lines 1234–1257):

~~~~text
  1234 |   [ ! -e "$T/log/call-1.argv" ]
  1235 |   # only the exact value 1 marks the context
  1236 |   for v in 0 yes true ""; do
  1237 |     LOA_ABLATION_BATCH_CONTEXT="$v" run_pr a1_full_openmount "$REVIEWC"
  1238 |     [ "$status" -eq 2 ]
  1239 |     [ ! -e "$T/run" ]
  1240 |   done
  1241 |   # an arm without eval_only is never refused for it
  1242 |   run_pr a1_no_dissent "$REVIEWC"
  1243 |   [ "$status" -eq 0 ]
  1244 | }
  1245 | 
  1246 | @test "eval_only: inside the batch context (LOA_ABLATION_BATCH_CONTEXT=1) the open-mount arm runs REVIEW and AUDIT and completes" {
  1247 |   c131_arms
  1248 |   LOA_ABLATION_BATCH_CONTEXT=1 run_pr a1_full_openmount "$REVIEWC"
  1249 |   [ "$status" -eq 0 ] || { echo "$output"; false; }
  1250 |   [ "$(jq -r '.status' "$T/run/meta/pipeline.json")" = completed ]
  1251 |   [ "$(labels)" = "REVIEW,AUDIT" ]
  1252 |   [ "$(evline mount_overlay)" = none ]
  1253 |   [ "$(evline oracle_open)" = true ]
  1254 | }
  1255 | 
  1256 | @test "a1_review_only (c131): a run records exactly one REVIEW phase and never launches AUDIT" {
  1257 |   c131_arms
~~~~

The change from head to the fix:

~~~~diff
@@ -1245,0 +1246,19 @@
+@test "eval_only (review r1 DISS-C-002): an arm whose toggles open the mount is refused outside the batch context even without eval_only; a non-boolean eval_only is refused as malformed" {
+  c131_arms
+  unset LOA_ABLATION_BATCH_CONTEXT
+  yq -i '.arms += [{"id": "x_open", "label": "XO", "task_types": ["review-catch"], "toggles": {"oracle_open": true}, "took_effect": ["integrity_clean"]}]' "$T/suite.yaml"
+  dryrun_rc x_open
+  [ "$status" -eq 2 ]
+  grep -q "refused: arm 'x_open': eval_only arm outside an evaluation batch" <<<"$output"
+  [ ! -e "$T/run" ]
+  yq -i '(.arms[] | select(.id == "a1_full_openmount") | .eval_only) = "yes"' "$T/suite.yaml"
+  LOA_ABLATION_BATCH_CONTEXT=1 dryrun_rc a1_full_openmount
+  [ "$status" -eq 2 ]
+  grep -q "eval_only must be a JSON boolean" <<<"$output"
+  # a quoted "true" on the toggle is refused too (audit r1 DISS-C-001): the strict guard and the loose mount read never disagree
+  yq -i '(.arms[] | select(.id == "a1_full_openmount") | .eval_only) = true | (.arms[] | select(.id == "a1_full_openmount") | .toggles.oracle_open) = "true"' "$T/suite.yaml"
+  LOA_ABLATION_BATCH_CONTEXT=1 dryrun_rc a1_full_openmount
+  [ "$status" -eq 2 ]
+  grep -q "toggles.oracle_open must be a JSON boolean" <<<"$output"
+}
+
~~~~
