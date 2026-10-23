# Incidents — pr-26

Things that happened after the change merged and cite one of its files: later fix commits on the main branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.

## I01 — fix-commit — 2026-10-20

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

## I02 — fix-commit — 2026-10-20

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
