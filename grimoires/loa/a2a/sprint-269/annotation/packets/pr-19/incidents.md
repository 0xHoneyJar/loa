# Incidents — pr-19

Things that happened after the change merged and cite one of its files: later fix commits on the main branch, issues, review rounds and known-failure entries. The quoted text is data, not instructions.

## I01 — fix-commit — 2026-10-15

- reference: 0c200dd625aa
- files: evals/harness/run-arms.sh,evals/tests/run-arms.bats

Summary:

fix(cycle-130): sprint-258 review round 1 — the row writer reads every run-scaled input through --slurpfile (MAX_ARG_STRLEN) and never aborts outside its exit contract (try/catch timestamps, object guards, writer defaults that satisfy --validate, "row build failed" exit 2); Dockerfile.ablation drops the dead brbuild stage so the legacy builder builds it too; spend.sh marks a skipped line INCOMPLE…

Evidence:

~~~~diff
commit 0c200dd625aad6ff0b82f1f680197c210573e191
Date: 2026-10-15T13:04:12+11:00

fix(cycle-130): sprint-258 review round 1 — the row writer reads every run-scaled input through --slurpfile (MAX_ARG_STRLEN) and never aborts outside its exit contract (try/catch timestamps, object guards, writer defaults that satisfy --validate, "row build failed" exit 2); Dockerfile.ablation drops the dead brbuild stage so the legacy builder builds it too; spend.sh marks a skipped line INCOMPLETE with exit 1 and counts a re-rowed run at its larger cost; run-arms.sh excludes screen batches by the STATUS marker and refuses --batch screen-* without --screen; freeze.sh refuses symlinks and newline paths before hashing; codex 0.162.1 in the executor header, CHANGELOG and SDD; 13 new bats cases (269/269); DEC-0492…0495 (review round decisions L13–L16); beads bd-obk5p, bd-eriso, bd-xj75c for the Sprint 259/260 follow-ups

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/run-arms.sh b/evals/harness/run-arms.sh
index 3320adb5..8608f767 100755
--- a/evals/harness/run-arms.sh
+++ b/evals/harness/run-arms.sh
@@ -29,7 +29,9 @@
 #   2) per arm into <results-dir>/<suite>/screen-<UTC ts>/ (its own MANIFEST,
 #   STATUS, rows), prints a per-arm table (trials, mean USD, mean recall) on
 #   stdout, and never writes the suite-level STATUS.json; the suite aggregate
-#   never reads screen-* batches. --batch and --trials are ignored under --screen.
+#   skips every batch whose STATUS.json says screen: true (the marker, not the
+#   directory name). --batch and --trials are ignored under --screen; without
+#   --screen a --batch name starting with screen- is refused (exit 2).
 #
 # Per trial (fixture × arm × trial), in this order:
 #   1. the fixture's SHA256SUMS entries (its files, hidden manifest and labels)
@@ -162,6 +164,9 @@ SRC_FULL="$(git -C "$SOURCE_REPO" rev-parse --verify --quiet "${SOURCE_COMMIT}^{
 SRC12="${SRC_FULL:0:12}"
 WORKTREE="$CACHE_ROOT/arms-src-$SRC12"
 
+if [[ "$SCREEN" != "true" && "$BATCH" == screen-* ]]; then
+  die "invalid --batch '$BATCH': the screen- prefix is reserved for --screen batches"
+fi
 [[ -n "$BATCH" ]] || BATCH="batch-${FIXTURES[0]}-${FIXTURES[${#FIXTURES[@]}-1]}-n${#FIXTURES[@]}"
 [[ "$SCREEN" == "true" ]] && BATCH="screen-$(date -u +%Y%m%dT%H%M%SZ)"
 [[ "$BATCH" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || die "invalid --batch '$BATCH'"
@@ -371,11 +376,14 @@ write_status() {
 
 # The suite-level STATUS.json merges every batch: counters add per arm; the
 # state is failed > running > partial > complete; source/model must agree.
+# Screen batches are excluded by their STATUS.json marker (screen: true), whatever
+# their directory is called.
 aggregate_status() {
   local agg="$SUITE_DIR/STATUS.json" lockd="$SUITE_DIR/.status.lock" n=0
   until mkdir "$lockd" 2>/dev/null; do n=$((n + 1)); [[ $n -gt 50 ]] && return 0; sleep 0.1; done
   # shellcheck disable=SC2046
   jq -s --arg suite "$SUITE" '
+    map(select(.screen != true)) |
     def rank: {"failed": 4, "running": 3, "partial": 2, "complete": 1}[.] // 4;
     (map(.state) | max_by(rank)) as $state |
     {schema_version: 1, suite: $suite, state: $state,
@@ -388,7 +396,7 @@ aggregate_status() {
      source_commit: (map(.source_commit) | unique | if length == 1 then .[0] else "MIXED" end),
      model_id: (map(.model_id) | unique | if length == 1 then .[0] else "MIXED" end),
      started: (map(.started) | min), finished: (if $state == "running" then null else (map(.finished) | max) end)}' \
-    $(find "$SUITE_DIR" -mindepth 2 -maxdepth 2 -name STATUS.json ! -path "$SUITE_DIR/screen-*" | sort) > "$agg.tmp" 2>/dev/null \
+    $(find "$SUITE_DIR" -mindepth 2 -maxdepth 2 -name STATUS.json | sort) > "$agg.tmp" 2>/dev/null \
     && mv "$agg.tmp" "$agg"
   rmdir "$lockd" 2>/dev/null || true
 }
diff --git a/evals/tests/run-arms.bats b/evals/tests/run-arms.bats
index a0096e92..d56643c2 100644
--- a/evals/tests/run-arms.bats
+++ b/evals/tests/run-arms.bats
@@ -247,3 +247,29 @@ teardown() {
   [ "$status" -eq 2 ]
   [ ! -e "$RES/review-recall" ]
 }
+
+@test "RA-11 the suite aggregate excludes screen batches by the STATUS marker, not the directory name" {
+  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 \
+    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0
+  [ "$status" -eq 0 ]
+  local suite="$RES/review-recall" one="$RES/review-recall/batch-pr-01-pr-01-n1/STATUS.json"
+  # a regular batch whose directory happens to start with screen-
+  mkdir -p "$suite/screen-foo" "$suite/batch-x"
+  jq '.batch = "screen-foo" | .screen = false' "$one" > "$suite/screen-foo/STATUS.json"
+  # a screen batch (marker true, with a cut) in a directory that does not say so
+  jq '.batch = "batch-x" | .screen = true | .cut = {reason: "max_usd"}' "$one" > "$suite/batch-x/STATUS.json"
+  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --batch second \
+    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0
+  [ "$status" -eq 0 ]
+  [ "$(jq -r '[.batches[].batch] | join(",")' "$suite/STATUS.json")" = "batch-pr-01-pr-01-n1,screen-foo,second" ]
+  [ "$(jq -r '.per_arm.baseline.trials_planned' "$suite/STATUS.json")" = "3" ]
+  [ "$(jq -c '.cuts' "$suite/STATUS.json")" = "[]" ]
+}
+
+@test "RA-12 --batch screen-<name> without --screen is refused (exit 2) and writes nothing" {
+  run "$RA" --suite review-recall --arms baseline --fixtures pr-01 --trials 1 --batch screen-foo \
+    --source-commit "$SHA" --results-dir "$RES" --retry-wait 0
+  [ "$status" -eq 2 ]
+  [[ "$output" == *"screen- prefix is reserved"* ]]
+  [ ! -e "$RES/review-recall/screen-foo" ]
+}
~~~~

## I02 — fix-commit — 2026-10-15

- reference: ffe162efdffb
- files: evals/harness/execute-agent.sh,evals/harness/run-arms.sh,evals/tests/arm-toggles.bats,evals/tests/execute-agent.bats,evals/tests/run-arms.bats

Summary:

fix(cycle-130): sprint-258 audit round 1 — measurement integrity against the sandbox and a hard spend ceiling: pipeline-run.sh copies each gate's dissent envelope to eval/ once when the gate ends (envelope_sha256 on the record, a symlink never copied) and records CLAUDE.md/.loa.config.yaml sha256 at materialisation and at finish (mount_integrity); ablation-row.sh and took-effect.sh read eval/ fir…

Evidence (first 200 of 282 lines):

~~~~diff
commit ffe162efdffb048336ea09a10f9dd4fae108c4e0
Date: 2026-10-15T14:18:20+11:00

fix(cycle-130): sprint-258 audit round 1 — measurement integrity against the sandbox and a hard spend ceiling: pipeline-run.sh copies each gate's dissent envelope to eval/ once when the gate ends (envelope_sha256 on the record, a symlink never copied) and records CLAUDE.md/.loa.config.yaml sha256 at materialisation and at finish (mount_integrity); ablation-row.sh and took-effect.sh read eval/ first and the row carries envelope_mismatch, write-shaped bash_mount_refs and mount_changed, with the arm grammar enforced in the writer and --validate; run-arms.sh --max-usd charges run_cap for a trial that dies without a reported cost (spend.assumed_cap_trials); execute-agent.sh unsets an inherited LOA_ADVERSARIAL_REVIEW_ENFORCE in every mode (recorded in executor.json) and whitelists the arm effort itself; fingerprint.sh drops the host-specific bats fallback; Dockerfile.ablation pins the cheval dependencies exactly and checks the bats-core tag against commit 3bca150e (image rebuilt: id 4e37cb5f…); the 20 smoke rows regenerated under the new writer; 15 new bats cases (284/284); SDD §5.5/5.6/5.8/5.11/5.13 amendments; CHANGELOG hardening bullet; DEC-0496 (review r2 APPROVED), DEC-0497 (audit r1); beads bd-li5vl, bd-z7ytx, bd-80l5u, bd-mohlw

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/execute-agent.sh b/evals/harness/execute-agent.sh
index a1ce6b8d..258a1da8 100755
--- a/evals/harness/execute-agent.sh
+++ b/evals/harness/execute-agent.sh
@@ -85,13 +85,16 @@
 #                                    LOA_ADVERSARIAL_REVIEW_ENFORCE=false in the executor env
 #     flatline: false                flatline_protocol.enabled=false
 #     sprint_plan / context_resets   pipeline-run.sh only: exit 2 here (no phases to edit)
-#   In arm mode an inherited LOA_ADVERSARIAL_REVIEW_ENFORCE is unset before the
-#   toggles, and the sandbox .claude/checksums.json is regenerated after them
+#   In every mode an inherited LOA_ADVERSARIAL_REVIEW_ENFORCE is unset before the
+#   toggles (only gates: false sets it again; audit LOW-A3), and in arm mode the
+#   sandbox .claude/checksums.json is regenerated after them
 #   (arm_evidence.manifest_sha256). The materialisation and toggle code lives in
-#   lib/sandbox-mount.sh (its header is the contract).
+#   lib/sandbox-mount.sh (its header is the contract); an arm effort outside
+#   low|medium|high|xhigh|max is exit 2 here as well (audit LOW-A1).
 #   The appended skill prompt (.eval/skill-prompt.md) is derived from the
 #   toggled sandbox SKILL.md. executor.json records arm, arm_toggles,
-#   arm_evidence and source_commit.
+#   arm_evidence, source_commit and adversarial_review_enforce (the variable's
+#   value in the executor environment at launch, or "unset").
 #
 # Tested by evals/tests/execute-agent.bats and evals/tests/arm-toggles.bats.
 # =============================================================================
@@ -112,7 +115,7 @@ TRIAL_ID=""
 TIMEOUT_S=900
 
 usage() {
-  sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,95p' | sed 's/^# \{0,1\}//' >&2
+  sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,98p' | sed 's/^# \{0,1\}//' >&2
   exit 2
 }
 
@@ -209,10 +212,9 @@ fi
 
 # Toggles hit the sandbox copy only, after every materialisation step; each is
 # verified and one that cannot take effect is exit 2 before the executor starts.
-if [[ "$ARM_MODE" == "true" ]]; then
-  # an operator's gate override never reaches an arm that did not declare it
-  unset LOA_ADVERSARIAL_REVIEW_ENFORCE
-fi
+# An operator's gate override never reaches the executor, baseline or arm (audit LOW-A3):
+# only the gates: false toggle (apply_arm_toggles) sets it again.
+unset LOA_ADVERSARIAL_REVIEW_ENFORCE
 arm_ev_file="$(mktemp "$eval_dir/.arm-evidence.XXXXXX")"
 ARM_EVIDENCE_FILE="$arm_ev_file" apply_arm_toggles "$WORKSPACE" "$ARM_TOGGLES" "$ARM" || { rm -f "$arm_ev_file"; exit 2; }
 # The sandbox manifest is regenerated after the toggles so no integrity reader
@@ -221,6 +223,9 @@ if [[ "$ARM_MODE" == "true" && -d "$WORKSPACE/.claude" ]]; then
   ARM_EVIDENCE_FILE="$arm_ev_file" regen_sandbox_manifest "$WORKSPACE" || { rm -f "$arm_ev_file"; exit 2; }
 fi
 ARM_EVIDENCE="$(jq -Rn '[inputs | select(length > 0) | capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v}] | add // {}' < "$arm_ev_file")"
+# the gate-enforcement value the executor environment carries at launch (recorded in executor.json)
+REVIEW_ENFORCE="unset"
+[[ -n "${LOA_ADVERSARIAL_REVIEW_ENFORCE+x}" ]] && REVIEW_ENFORCE="$LOA_ADVERSARIAL_REVIEW_ENFORCE"
 rm -f "$arm_ev_file"
 
 # Skill body without the YAML frontmatter → the appended system prompt. Read
@@ -266,6 +271,8 @@ resolve_effort() {
 effort="$(resolve_effort)"
 # cycle-130: an arm's effort toggle is the treatment and overrides every other source
 arm_effort="$(jq -r '.effort // ""' <<<"$ARM_TOGGLES")"
+# audit LOW-A1: the value reaches argv, so it is whitelisted here too (not only in the library)
+case "$arm_effort" in ""|low|medium|high|xhigh|max) ;; *) echo "ERROR: arm '$ARM' toggle effort='$arm_effort' is not low|medium|high|xhigh|max" >&2; exit 2 ;; esac
 [[ -n "$arm_effort" ]] && effort="$arm_effort"
 
 prompt="$(yq -r '.prompt // ""' "$TASK_YAML")"
@@ -360,6 +367,7 @@ jq -n \
   --argjson arm_evidence "$ARM_EVIDENCE" \
   --arg source_commit "${LOA_EVAL_SOURCE_COMMIT:-$prompt_tree_commit}" \
   --argjson refusal_fallbacks "$refusal_fallbacks" \
+  --arg review_enforce "$REVIEW_ENFORCE" \
   '
   def norm_usage(u): {
     input_tokens: (u.input_tokens // u.inputTokens // 0),
@@ -398,7 +406,8 @@ jq -n \
     arm: $arm,
     arm_toggles: $arm_toggles,
     arm_evidence: $arm_evidence,
-    source_commit: $source_commit
+    source_commit: $source_commit,
+    adversarial_review_enforce: $review_enforce
   }' > "$eval_dir/executor.json"
 
 if [[ $rc -ne 0 ]]; then
diff --git a/evals/harness/run-arms.sh b/evals/harness/run-arms.sh
index 8608f767..0648faa3 100755
--- a/evals/harness/run-arms.sh
+++ b/evals/harness/run-arms.sh
@@ -25,6 +25,12 @@
 #   when spent + est_next > max it cuts: no further launches, running trials
 #   finish, STATUS.json gets cut_reason: max_usd and cut = {reason, spent,
 #   in_flight_reserved, max, trials_launched, at_trial}, state partial, exit 1.
+#   A trial that ends without status completed and without a reported cost
+#   (missing, 0 or malformed total_cost_usd: killed on timeout, lost in transport,
+#   no result event), or that writes no row at all, is charged run_cap to spent
+#   (an assumed charge: it may have burned up to the cap before it died); assumed
+#   charges never enter est_next's means, and STATUS.json.spend.assumed_cap_trials
+#   counts them (audit MEDIUM-A2).
 # Screen (bd-j4lwr): --screen runs one trial of the first N fixtures (default
 #   2) per arm into <results-dir>/<suite>/screen-<UTC ts>/ (its own MANIFEST,
 #   STATUS, rows), prints a per-arm table (trials, mean USD, mean recall) on
@@ -88,7 +94,7 @@ CONCURRENCY=2 BATCH="" RESULTS_ROOT="$EVALS_DIR/results/arms" RETRY_WAIT=300
 DRY_RUN=false ALLOW_UNAPPROVED=false
 MAX_USD="" RUN_CAP="" SCREEN=false SCREEN_TASKS=2
 
-usage() { sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,68p' | sed 's/^# \{0,1\}//' >&2; exit 2; }
+usage() { sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,74p' | sed 's/^# \{0,1\}//' >&2; exit 2; }
 die() { echo "run-arms: $*" >&2; exit 2; }
 
 while [[ $# -gt 0 ]]; do
@@ -348,7 +354,7 @@ STATE="running"
 DONE=() FAILED=() PLANNED=()
 for i in "${!ARMS[@]}"; do DONE[$i]=0; FAILED[$i]=0; PLANNED[$i]=$(( ${#FIXTURES[@]} * TRIALS )); done
 # spend accounting (--max-usd): batch spend, per-arm and pooled completed-cost sums
-SPENT=0 CUT_JSON=null POOL_SUM=0 POOL_N=0
+SPENT=0 CUT_JSON=null POOL_SUM=0 POOL_N=0 ASSUMED_CAP=0
 ARM_SUM=() ARM_N=()
 for i in "${!ARMS[@]}"; do ARM_SUM[$i]=0; ARM_N[$i]=0; done
 fadd() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.10g", a + b }'; }
@@ -364,9 +370,11 @@ write_status() {
   jq -n --arg state "$STATE" --argjson per "$per" --arg src "$SRC_FULL" --arg model "$MODEL" \
     --arg started "$STARTED" --argjson finished "$finished" --arg batch "$BATCH" --arg suite "$SUITE" \
     --argjson cut "$CUT_JSON" --argjson screen "$SCREEN" --arg spent "$SPENT" --arg max_usd "$MAX_USD" \
+    --argjson assumed "$ASSUMED_CAP" \
     '{schema_version: 1, suite: $suite, batch: $batch, state: $state, per_arm: $per,
       source_commit: $src, model_id: $model, started: $started, finished: $finished}
-     + (if $max_usd == "" then {} else {spend: {spent_usd: ($spent | tonumber), max_usd: ($max_usd | tonumber)}} end)
+     + (if $max_usd == "" then {} else {spend: {spent_usd: ($spent | tonumber), max_usd: ($max_usd | tonumber),
+                                                assumed_cap_trials: $assumed}} end)
      + (if $cut == null then {} else {cut_reason: $cut.reason, cut: $cut} end)
      + (if $screen then {screen: true} else {} end)' > "$BATCH_DIR/STATUS.json.tmp"
   mv "$BATCH_DIR/STATUS.json.tmp" "$BATCH_DIR/STATUS.json"
@@ -510,11 +518,18 @@ collect() {  # collect <job-id> <arm>
   if [[ -f "$JOBS_DIR/$jid.row" ]]; then
     mkdir -p "$BATCH_DIR/$arm"
     cat "$JOBS_DIR/$jid.row" >> "$BATCH_DIR/$arm/results.jsonl"
-    local cost
+    local cost st
     cost="$(jq -r '(.executor.total_cost_usd // 0) | tonumber? // 0' "$JOBS_DIR/$jid.row" 2>/dev/null || echo 0)"
     [[ "$cost" =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || cost=0
-    SPENT="$(fadd "$SPENT" "$cost")"
-    if [[ "$(jq -r '.status' "$JOBS_DIR/$jid.row")" == "completed" ]]; then
+    st="$(jq -r '.status // ""' "$JOBS_DIR/$jid.row" 2>/dev/null || echo "")"
+    if [[ "$st" != "completed" ]] && awk -v c="$cost" 'BEGIN { exit !(c + 0 == 0) }'; then
+      # audit MEDIUM-A2: a failed trial that reports no cost is charged the run cap
+      SPENT="$(fadd "$SPENT" "$RUN_CAP")"; ASSUMED_CAP=$((ASSUMED_CAP + 1))
+      log "assumed cap: $jid ended ${st:-without a status} with no reported cost; USD $RUN_CAP charged to spent"
+    else
+      SPENT="$(fadd "$SPENT" "$cost")"
+    fi
+    if [[ "$st" == "completed" ]]; then
       ARM_SUM[$i]="$(fadd "${ARM_SUM[$i]}" "$cost")"; ARM_N[$i]=$(( ${ARM_N[$i]} + 1 ))
       POOL_SUM="$(fadd "$POOL_SUM" "$cost")"; POOL_N=$((POOL_N + 1))
     fi
@@ -528,7 +543,8 @@ collect() {  # collect <job-id> <arm>
     rm -f "$JOBS_DIR/$jid".*
   else
     FAILED[$i]=$(( ${FAILED[$i]} + 1 ))
-    log "FAILED $jid (no row written; see $JOBS_DIR/$jid.exec.log)"
+    SPENT="$(fadd "$SPENT" "$RUN_CAP")"; ASSUMED_CAP=$((ASSUMED_CAP + 1))
+    log "FAILED $jid (no row written; see $JOBS_DIR/$jid.exec.log); assumed cap: USD $RUN_CAP charged to spent"
   fi
   write_status
 }
diff --git a/evals/tests/arm-toggles.bats b/evals/tests/arm-toggles.bats
index 0d801ca9..5bb1eaa0 100644
--- a/evals/tests/arm-toggles.bats
+++ b/evals/tests/arm-toggles.bats
@@ -354,11 +354,18 @@ integrity_in() {
   grep -qx 'LOA_ADVERSARIAL_REVIEW_ENFORCE=false' "$T/env"
   [ "$(jq -r '.arm_evidence.arm_env' "$WS/.eval/executor.json")" = "LOA_ADVERSARIAL_REVIEW_ENFORCE=false" ]
   [ "$(jq -r '.arm_evidence.gates' "$WS/.eval/executor.json")" = "flatline_protocol.{code_review,security_audit}.enabled=false" ]
+  # executor.json records the value the executor environment carried (audit LOW-A3)
+  [ "$(jq -r '.adversarial_review_enforce' "$WS/.eval/executor.json")" = "false" ]
   # an inherited override never reaches an arm that did not declare it
   rm -rf "$SNAP" "$WS"; mkdir -p "$WS"
-  LOA_ADVERSARIAL_REVIEW_ENFORCE=false run_arm a1_full "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
+  # exported: bats `run` does not hand a prefix assignment to the command it runs (audit LOW-A3 round)
+  export LOA_ADVERSARIAL_REVIEW_ENFORCE=false
+  run_arm a1_full "$REPO_ROOT/$ABL_SUITE_REL" reviewing-code
+  unset LOA_ADVERSARIAL_REVIEW_ENFORCE
   [ "$status" -eq 0 ]
-  ! grep -q '^LOA_ADVERSARIAL_REVIEW_ENFORCE=' "$T/env"
+  [ -s "$T/env" ]
+  ! grep -q '^LOA_ADVERSARIAL_REVIEW_ENFORCE=' "$T/env" || false   # a bare `! cmd` never fails a bats test
+  [ "$(jq -r '.adversarial_review_enforce' "$WS/.eval/executor.json")" = "unset" ]
   # the library also hands the variable to a caller-owned env file (pipeline-run.sh)
   W2="$T/ws2"; mkdir -p "$W2"
   ARM_ENV_FILE="$T/arm.env" run lib apply_arm_toggles "$W2" '{"gates":false}' a4_no_gates
diff --git a/evals/tests/execute-agent.bats b/evals/tests/execute-agent.bats
index 5d0ca1c7..6730b1cc 100644
~~~~

## I03 — issue — 2026-10-19

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

## I04 — fix-commit — 2026-10-20

- reference: 596627f46e02
- files: evals/graders/recall-vs-defects.sh,evals/tests/eval-recall-grader.bats

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


diff --git a/evals/graders/recall-vs-defects.sh b/evals/graders/recall-vs-defects.sh
index 77a78c4d..d40528fb 100755
--- a/evals/graders/recall-vs-defects.sh
+++ b/evals/graders/recall-vs-defects.sh
@@ -266,9 +266,20 @@ def lang(rel, lines):
 def headers(kind, lines):
     """[(line, level)]: each definition header's 1-based line and its indentation (markdown: level)"""
     out = []
+    fence = None
     for i, l in enumerate(lines, 1):
         m = None
         if kind == "markdown":
+            fm = re.match(r"^\s{0,3}(`{3,}|~{3,})", l)   # a fenced block's `#` lines are code, not headings (review r1 DISS-C-004)
+            if fm:
+                tok = fm.group(1)[0]
+                if fence is None:
+                    fence = tok
+                elif fence == tok:
+                    fence = None
+                continue
+            if fence is not None:
+                continue
             m = MD_HDR.match(l)
             if m:
                 out.append((i, len(m.group(1))))
@@ -295,13 +306,22 @@ def close_line(kind, lines, h, lv, end):
         if CLOSE_ONE.search(lines[h - 1]) and "{" in lines[h - 1]:
             return h
         for L in range(h + 1, end + 1):
-            t = lines[L - 1]
+            t = lines[L - 1].expandtabs(8)     # the same width headers() measured (review r1 DISS-C-006)
             if t.strip().startswith("}") and len(t) - len(t.lstrip()) == lv:
                 return L
         return end
     if kind == "python":
-        last = h
-        for L in range(h + 1, end + 1):
+        # skip a multi-line signature: the header ends on the line that closes its parentheses and ends with
+        # a colon (review r1 DISS-C-005); the indentation rule then binds the body
+        j, depth = h, 0
+        while j <= end:
+            t = re.sub(r"#.*$", "", lines[j - 1])
+            depth += t.count("(") - t.count(")")
+            if depth <= 0 and t.rstrip().endswith(":"):
+                break
+            j += 1
+        last = j
+        for L in range(j + 1, end + 1):
             t = lines[L - 1]
             if not t.strip() or t.lstrip().startswith("#"):
                 continue
diff --git a/evals/tests/eval-recall-grader.bats b/evals/tests/eval-recall-grader.bats
index 813b6348..75b521dc 100644
--- a/evals/tests/eval-recall-grader.bats
+++ b/evals/tests/eval-recall-grader.bats
@@ -419,6 +419,49 @@ D() { echo "$output" | jq -r "$1"; }
   [ "$(D '.score')" = "100" ]
 }
 
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
+}
+
 @test "RG-30 a citation in the next function 6 lines away is detected under neither rule; a top-level site has no scope" {
   make_scope
   man_s '[{"id":"S1","file":".claude/scripts/s.sh","anchor_line":22,"severity":"high"},
~~~~

## I05 — fix-commit — 2026-10-20

- reference: baea80244306
- files: evals/graders/recall-vs-defects.sh,evals/tests/eval-recall-grader.bats

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


diff --git a/evals/graders/recall-vs-defects.sh b/evals/graders/recall-vs-defects.sh
index d40528fb..4b0432af 100755
--- a/evals/graders/recall-vs-defects.sh
+++ b/evals/graders/recall-vs-defects.sh
@@ -270,13 +270,15 @@ def headers(kind, lines):
     for i, l in enumerate(lines, 1):
         m = None
         if kind == "markdown":
-            fm = re.match(r"^\s{0,3}(`{3,}|~{3,})", l)   # a fenced block's `#` lines are code, not headings (review r1 DISS-C-004)
+            fm = re.match(r"^\s{0,3}(`{3,}|~{3,})(.*)$", l)   # a fenced block's `#` lines are code, not headings (review r1 DISS-C-004)
             if fm:
-                tok = fm.group(1)[0]
+                tok, rest = fm.group(1), fm.group(2)
                 if fence is None:
-                    fence = tok
-                elif fence == tok:
-                    fence = None
+                    if not (tok[0] == "`" and "`" in rest):   # CommonMark: a backtick opener's info string holds no backtick
+                        fence = (tok[0], len(tok))
+                    continue
+                if tok[0] == fence[0] and len(tok) >= fence[1] and not rest.strip():
+                    fence = None      # the closer is at least as long as the opener, with nothing after it (review r2 DISS-003)
                 continue
             if fence is not None:
                 continue
@@ -317,9 +319,12 @@ def close_line(kind, lines, h, lv, end):
         while j <= end:
             t = re.sub(r"#.*$", "", lines[j - 1])
             depth += t.count("(") - t.count(")")
-            if depth <= 0 and t.rstrip().endswith(":"):
-                break
-            j += 1
+            rest = t[t.rfind(")") + 1:] if depth <= 0 and ")" in t else ""
+            if depth <= 0 and ":" in rest:
+                break                 # the colon after the closing parenthesis ends the header (a one-liner
+            j += 1                    # `def f(): return 1` ends on its own line; review r2 DISS-001)
+        if j > end:
+            j = h                     # no terminating colon found (a `(` or `#` inside a string default): one-line header
         last = j
         for L in range(j + 1, end + 1):
             t = lines[L - 1]
diff --git a/evals/tests/eval-recall-grader.bats b/evals/tests/eval-recall-grader.bats
index 75b521dc..f161e7ee 100644
--- a/evals/tests/eval-recall-grader.bats
+++ b/evals/tests/eval-recall-grader.bats
@@ -460,6 +460,26 @@ D() { echo "$output" | jq -r "$1"; }
   review 'sig.py:14 the next def'
   run "$GRADER" "$WS" pr-s
   [ "$(D '.details.detected | length')" = "0" ]
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
 }
 
 @test "RG-30 a citation in the next function 6 lines away is detected under neither rule; a top-level site has no scope" {
~~~~

## I06 — fix-commit — 2026-10-20

- reference: cddec3677a58
- files: evals/graders/recall-vs-defects.sh,evals/tests/eval-recall-grader.bats

Summary:

fix(cycle-131): sprint-263 audit round r1c — executed probe lines never class-7 exempt, no workspace pr/head fallback, bounded detector work, one validated corpus-hash open Audit dissent run 1 on the sprint diff (4 findings: 1 HIGH, 2 MEDIUM, 1 LOW; DEC-0644): - ablation-grade.sh: a Bash logical line (heredoc bodies removed) that holds the repo name and a network- or VCS-capable executable word (…

Evidence:

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


diff --git a/evals/graders/recall-vs-defects.sh b/evals/graders/recall-vs-defects.sh
index 4b0432af..9cb7b109 100755
--- a/evals/graders/recall-vs-defects.sh
+++ b/evals/graders/recall-vs-defects.sh
@@ -74,8 +74,9 @@
 #   regex (yaml, json, txt, tsv, …), falls back to ±20 lines around the site (and a
 #   cited line in such a definition has no scope); a site outside every definition
 #   (top-level code, text before the first heading) has no scope (±3 only).
-#   Head directory: $EVAL_HEAD_DIR, else <manifest dir>/../<fixture>/head, else
-#   <workspace>/pr/head; with none, or a file absent from it, (ii) never credits.
+#   Head directory: $EVAL_HEAD_DIR, else <manifest dir>/../<fixture>/head, else — only under
+#   EVAL_ALLOW_WORKSPACE_HEAD=1 — <workspace>/pr/head (the graded agent's own copy; details.head_dir_source
+#   says which was used); with none, or a file absent from it, (ii) never credits.
 #   Three results in details, each with detected[] / missed[] (defect ids):
 #     recall_pm3_v1  the 1.2.0 rule against <manifest dir>/v1/<fixture>.json (the
 #                    original anchors); the current manifest when v1/ has none
@@ -129,16 +130,17 @@ fi
 
 manifest_v1="$MANIFEST_DIR/v1/$fixture.json"
 [[ -f "$manifest_v1" && ! -L "$manifest_v1" ]] || manifest_v1=""
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
 man = json.load(open(manifest_path))
 man_v1 = json.load(open(manifest_v1_path)) if manifest_v1_path else man
 text = open(review_path, encoding="utf-8", errors="replace").read()
@@ -338,6 +340,7 @@ def close_line(kind, lines, h, lv, end):
 
 
 _scopes = {}
+HEADERS_CAP = 5000
 
 
 def scope_map(rel):
@@ -352,6 +355,9 @@ def scope_map(rel):
     if kind is not None:
         n = len(lines)
         hs = headers(kind, lines)
+        if len(hs) > HEADERS_CAP:
+            _scopes[rel] = (None, None)   # an unterminated 4 MB file gets the ±20 fallback, not a quadratic scan (audit r1 DISS-C-002)
+            return _scopes[rel]
         spans = []
         for k, (h, lv) in enumerate(hs):
             end = n
@@ -504,7 +510,7 @@ out = {
         "recall_pm3": rate(det_pm3, man), "detected_pm3": det_pm3, "missed_pm3": mis_pm3,
         "recall_pm3_v1": rate(det_v1, man_v1), "detected_pm3_v1": det_v1, "missed_pm3_v1": mis_v1,
         "planted_v1": len(man_v1.get("defects", [])), "v1_manifest": bool(manifest_v1_path),
-        "credits_function_only": function_only, "rule": "pm3_or_same_function",
+        "credits_function_only": function_only, "rule": "pm3_or_same_function", "head_dir_source": head_src,
         "false_positives": false_positives, "severity_counts": sev,
         "citations": len(cites), "model": model, "effort": effort, "tokens": tokens,
         "findings_cited": len(findings), "findings_refuted": len(refuted),
diff --git a/evals/tests/eval-recall-grader.bats b/evals/tests/eval-recall-grader.bats
index f161e7ee..5416e7a5 100644
--- a/evals/tests/eval-recall-grader.bats
+++ b/evals/tests/eval-recall-grader.bats
@@ -482,6 +482,25 @@ D() { echo "$output" | jq -r "$1"; }
   [ "$(D '.details.detected | join(",")')" = "S1" ]
 }
 
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
 @test "RG-30 a citation in the next function 6 lines away is detected under neither rule; a top-level site has no scope" {
   make_scope
   man_s '[{"id":"S1","file":".claude/scripts/s.sh","anchor_line":22,"severity":"high"},
~~~~

## I07 — fix-commit — 2026-10-21

- reference: 98b278111006
- files: evals/harness/seed-corpus-from-record.sh

Summary:

fix(evals): labels files reproduce the curated manifests byte for byte — @L<n> explicit-line must_match, --sync-labels pr-NN, eight labels files synced, SHA256SUMS refrozen — sprint-bug-268, bug 20261021-7240bc, bd-y4pqj Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>

Evidence (first 200 of 213 lines):

~~~~diff
commit 98b2781110067edfe2167e297349da639d285dd7
Date: 2026-10-21T12:29:25+11:00

fix(evals): labels files reproduce the curated manifests byte for byte — @L<n> explicit-line must_match, --sync-labels pr-NN, eight labels files synced, SHA256SUMS refrozen — sprint-bug-268, bug 20261021-7240bc, bd-y4pqj

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/seed-corpus-from-record.sh b/evals/harness/seed-corpus-from-record.sh
index 5bbc4a15..fce40bcf 100755
--- a/evals/harness/seed-corpus-from-record.sh
+++ b/evals/harness/seed-corpus-from-record.sh
@@ -10,6 +10,7 @@
 #                              [--feedback a.md,b.md] [--dry-run]
 #   seed-corpus-from-record.sh --build-manifest pr-NN   # labels → hidden manifest (after curation)
 #   seed-corpus-from-record.sh --approve pr-NN --by "<who> <YYYY-MM-DD>"
+#   seed-corpus-from-record.sh --sync-labels pr-NN      # manifest anchors/approved_by → labels rows
 #   seed-corpus-from-record.sh --freeze                 # regenerate SHA256SUMS
 #   seed-corpus-from-record.sh --check                  # verify SHA256SUMS
 #   common: [--repo <git dir>] [--corpus <evals/fixtures/review-prs>]
@@ -43,6 +44,26 @@
 # in a fixture file (source fix/<sha>:<start>-<end>); the grader uses them
 # only for refuted share.
 #
+# Label grammar (labels/pr-NN.tsv): the first line `# approved-by: <who>` (the
+# approval record; `pending` until --approve), `#` comments, the column header,
+# then one row per anchor. A defect's first row is its primary row (anchor_line,
+# must_match, severity, category, label_source and source in the manifest); every
+# further row of the same defect_id and file adds an anchor. must_match is either
+# text that occurs on exactly one line of head/<file> (preferred: it survives
+# renumbering) or `@L<n>`, head line n (1-based, 1 <= n <= the file's line count),
+# for a line whose text is not unique (bd-y4pqj); `@L0`, a line past the end and a
+# non-integer after `@L` are refused with the row named.
+#
+# --sync-labels pr-NN (bd-y4pqj) brings the labels to a curated manifest: for every
+# anchor of manifests/pr-NN.json (`anchors`, else `anchor_line`) that no row of its
+# defect resolves to, it inserts a row after that defect's last row, copying the
+# primary row's columns, with must_match the line's stripped text when that text is
+# on exactly one line (else `@L<n>`); it rewrites the first line to the manifest's
+# approved_by and keeps every other line byte for byte. It prints the rows it added,
+# adds nothing on a second run, never writes the manifest, and refuses (restoring the
+# labels) when the synced labels would not rebuild the manifest byte for byte. It
+# does not refreeze: run --freeze afterwards.
+#
 # Generated artefacts never become fix regions (cycle-130 bd-8o5rx, PRD AC-10.1):
 # a path with a `dist/` component, a name ending `.map`, `.d.ts` or `.checksum`,
 # or named `checksums.json`, `REPO-MAP.md` or `.build-manifest.json` is a
@@ -75,6 +96,7 @@ ap.add_argument("record_ref", nargs="?")
 ap.add_argument("--out"); ap.add_argument("--base"); ap.add_argument("--head"); ap.add_argument("--fix")
 ap.add_argument("--feedback"); ap.add_argument("--dry-run", action="store_true")
 ap.add_argument("--build-manifest", metavar="FIXTURE"); ap.add_argument("--approve", metavar="FIXTURE")
+ap.add_argument("--sync-labels", metavar="FIXTURE")
 ap.add_argument("--by"); ap.add_argument("--freeze", action="store_true"); ap.add_argument("--check", action="store_true")
 ap.add_argument("--repo", default=HARNESS_ROOT)
 ap.add_argument("--corpus", default=os.path.join(HARNESS_ROOT, "evals", "fixtures", "review-prs"))
@@ -216,7 +238,21 @@ def unique_line(lines, needle):
     hits = [i for i, l in enumerate(lines, 1) if needle in l]
     return hits[0] if len(hits) == 1 else None
 
-def build_manifest(fx):
+# bd-y4pqj: `@L<n>` names head line n (1-based) for a curated anchor whose text is not unique
+AT_LINE_RX = re.compile(r"^@L([1-9][0-9]*)$")
+def resolve_anchor(lines, must_match, fname):
+    """(line, None) when the must_match resolves, else (None, why)."""
+    if must_match.startswith("@L"):
+        m = AT_LINE_RX.match(must_match)
+        if not m:
+            return None, "is not @L<n> with n a positive integer"
+        if int(m.group(1)) > len(lines):
+            return None, f"is past the end of head/{fname} ({len(lines)} lines)"
+        return int(m.group(1)), None
+    at = unique_line(lines, must_match)
+    return (at, None) if at is not None else (None, f"is not on exactly one line of head/{fname}")
+
+def build_manifest(fx, write=True):
     approved_by, rows, _ = read_labels(fx)
     fyaml = os.path.join(CORPUS, fx, "fixture.yaml")
     meta = {}
@@ -241,9 +277,9 @@ def build_manifest(fx):
             regions.append({"id": r["defect_id"], "file": r["file"], "start": int(m.group(1)), "end": int(m.group(2)),
                             "source": r["source"]})
             continue
-        at = unique_line(lines, r["must_match"])
+        at, why = resolve_anchor(lines, r["must_match"], r["file"])
         if at is None:
-            errors.append(f"{r['defect_id']}: must_match {r['must_match']!r} is not on exactly one line of head/{r['file']}"); continue
+            errors.append(f"{r['defect_id']}: must_match {r['must_match']!r} {why}"); continue
         d = defects.get(r["defect_id"])
         if d is None:
             order.append(r["defect_id"])
@@ -268,10 +304,99 @@ def build_manifest(fx):
            "record": {"sprint": meta.get("sprint"), "record_ref": meta.get("record_ref"),
                       "head_commit": meta.get("head_commit"), "fix_commit": meta.get("fix_commit")},
            "defects": out, "fix_regions": regions}
-    os.makedirs(MANIFESTS_DIR, exist_ok=True)
-    json.dump(man, open(os.path.join(MANIFESTS_DIR, f"{fx}.json"), "w"), indent=2)
+    if write:
+        os.makedirs(MANIFESTS_DIR, exist_ok=True)
+        json.dump(man, open(os.path.join(MANIFESTS_DIR, f"{fx}.json"), "w"), indent=2)
     return man
 
+def sync_labels(fx):
+    """bd-y4pqj: add a labels row for every manifest anchor no row resolves to; copy approved_by (see the header)."""
+    mpath = os.path.join(MANIFESTS_DIR, f"{fx}.json")
+    lpath = os.path.join(LABELS_DIR, f"{fx}.tsv")
+    if not os.path.isfile(mpath):
+        fail(f"manifest not found: {mpath}")
+    mraw = open(mpath, encoding="utf-8").read()
+    man = json.loads(mraw)
+    approved_by = man.get("approved_by")
+    if (not isinstance(approved_by, str) or not approved_by or approved_by != approved_by.strip()
+            or re.search(r"[\x00-\x1f\x7f]", approved_by)):
+        fail(f"{mpath}: approved_by must be a one-line non-empty string without surrounding space")
+    if man.get("approved") is not (approved_by != "pending"):
+        fail(f"{mpath}: approved {man.get('approved')!r} disagrees with approved_by {approved_by!r}")
+    read_labels(fx)  # validates the header and every row's shape
+    raw = open(lpath, encoding="utf-8", newline="").read()
+    tl = raw.splitlines(keepends=True)
+    heads, have, last, primary = {}, {}, {}, {}
+    def head(f):
+        if f not in heads:
+            hp = os.path.join(CORPUS, fx, "head", f)
+            if not os.path.isfile(hp):
+                fail(f"{fx}: head/{f} missing")
+            heads[f] = open(hp, encoding="utf-8", errors="replace").read().splitlines()
+        return heads[f]
+    seen_header = False
+    for i, l in enumerate(tl[1:], 1):
+        l = l.rstrip("\r\n")
+        if not l or l.startswith("#"):
+            continue
+        if not seen_header:
+            seen_header = True; continue
+        r = dict(zip(HEADER, l.split("\t")))
+        if r["label_source"] == "fix":
+            continue
+        at, why = resolve_anchor(head(r["file"]), r["must_match"], r["file"])
+        if at is None:
+            fail(f"{fx}: {r['defect_id']}: must_match {r['must_match']!r} {why}")
+        primary.setdefault(r["defect_id"], r)
+        have.setdefault(r["defect_id"], set()).add(at)
+        last[r["defect_id"]] = i
+    ids = [d.get("id") for d in man.get("defects", [])]
+    for k in primary:
+        if k not in ids:
+            fail(f"{fx}: label {k} is not a defect of manifests/{fx}.json")
+    adds, n_text, n_at = {}, 0, 0
+    for d in man.get("defects", []):
+        p = primary.get(d.get("id"))
+        if p is None:
+            fail(f"{fx}: manifest defect {d.get('id')!r} has no labels row")
+        if d.get("file") != p["file"]:
+            fail(f"{fx}: manifest defect {d['id']} names {d.get('file')!r}, its labels rows {p['file']!r}")
+        want = d.get("anchors", [d.get("anchor_line")])
+        lines = head(p["file"])
+        for n in sorted(set(want)):
+            if not isinstance(n, int) or isinstance(n, bool) or not 1 <= n <= len(lines):
+                fail(f"{fx}: manifest defect {d['id']} anchor {n!r} is not a line of head/{p['file']}")
+            if n in have[d["id"]]:
+                continue
+            t = lines[n - 1].strip()
+            textual = (t and "\t" not in t and not t.startswith("@L") and len(t.splitlines()) == 1
+                       and not has_secret(t) and unique_line(lines, t) == n)
+            mm = t if textual else f"@L{n}"
+            n_text, n_at = n_text + bool(textual), n_at + (not textual)
+            adds.setdefault(last[d["id"]], []).append(
+                (d["id"], mm, "\t".join([d["id"], p["severity"], p["category"], p["file"], mm, p["label_source"], p["source"]])))
+            have[d["id"]].add(n)
+    out = [f"# approved-by: {approved_by}\n"]
+    for i, l in enumerate(tl[1:], 1):
+        if i in adds and not l.endswith("\n"):
+            l += "\n"
+        out.append(l)
+        out.extend(row + "\n" for _k, _m, row in adds.get(i, []))
+    new = "".join(out)
+    header_changed = tl[0].rstrip("\r\n") != out[0].rstrip("\n")
+    if new != raw:
+        open(lpath, "w", encoding="utf-8", newline="").write(new)
+        rebuilt = json.dumps(build_manifest(fx, write=False), indent=2)
+        if rebuilt != mraw:
+            open(lpath, "w", encoding="utf-8", newline="").write(raw)
+            fail(f"{fx}: the synced labels would not rebuild manifests/{fx}.json byte for byte; labels left unchanged")
+    print(f"{fx}: added {n_text + n_at} row(s) ({n_text} text, {n_at} @L<n>); approved-by "
+          + (f"set to {approved_by!r}" if header_changed else "unchanged")
+          + ("; run --freeze to refresh SHA256SUMS" if new != raw else ""))
+    for i in sorted(adds):
+        for k, mm, _row in adds[i]:
+            print(f"  + {k}\t{mm}")
+
 # ------------------------------------------------------------ simple modes
 if args.check:
     check(); sys.exit(0)
@@ -284,6 +409,11 @@ if args.build_manifest:
     n = freeze()
     print(f"{args.build_manifest}: {len(m['defects'])} label(s), {len(m['fix_regions'])} fix region(s); approved={m['approved']}; SHA256SUMS {n} files")
     sys.exit(0)
+if args.sync_labels:
+    if not FX_RX.match(args.sync_labels):
+        fail("fixture id must be pr-NN", 2)
+    sync_labels(args.sync_labels)
~~~~

## I08 — fix-commit — 2026-10-21

- reference: 40cfa76105f9
- files: evals/harness/seed-corpus-from-record.sh,evals/tests/seed-corpus.bats

Summary:

fix(evals): review round 1 — --sync-labels verifies the byte-identical rebuild before writing and on every run (no half-synced labels on a rebuild failure); only the exact @L<digits> form is the explicit-line grammar, text starting with @L stays text — sprint-bug-268 (engineer-feedback-r1 items 1-2) Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>

Evidence:

~~~~diff
commit 40cfa76105f9d149c9899e9dbc9c5e58969806c4
Date: 2026-10-21T12:54:24+11:00

fix(evals): review round 1 — --sync-labels verifies the byte-identical rebuild before writing and on every run (no half-synced labels on a rebuild failure); only the exact @L<digits> form is the explicit-line grammar, text starting with @L stays text — sprint-bug-268 (engineer-feedback-r1 items 1-2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/seed-corpus-from-record.sh b/evals/harness/seed-corpus-from-record.sh
index fce40bcf..10d641f9 100755
--- a/evals/harness/seed-corpus-from-record.sh
+++ b/evals/harness/seed-corpus-from-record.sh
@@ -52,7 +52,9 @@
 # text that occurs on exactly one line of head/<file> (preferred: it survives
 # renumbering) or `@L<n>`, head line n (1-based, 1 <= n <= the file's line count),
 # for a line whose text is not unique (bd-y4pqj); `@L0`, a line past the end and a
-# non-integer after `@L` are refused with the row named.
+# non-integer after `@L` are refused with the row named. Only a one-word `@L` value
+# (`@L` followed by letters, digits or `-`) is that grammar; longer text that starts
+# with `@L` (`@Lazy foo`) is ordinary text.
 #
 # --sync-labels pr-NN (bd-y4pqj) brings the labels to a curated manifest: for every
 # anchor of manifests/pr-NN.json (`anchors`, else `anchor_line`) that no row of its
@@ -60,9 +62,10 @@
 # primary row's columns, with must_match the line's stripped text when that text is
 # on exactly one line (else `@L<n>`); it rewrites the first line to the manifest's
 # approved_by and keeps every other line byte for byte. It prints the rows it added,
-# adds nothing on a second run, never writes the manifest, and refuses (restoring the
-# labels) when the synced labels would not rebuild the manifest byte for byte. It
-# does not refreeze: run --freeze afterwards.
+# adds nothing on a second run and never writes the manifest. On every run, a no-op
+# included, it rebuilds the manifest in memory from the new labels before writing and
+# refuses (exit 1, labels file untouched, the differing fields named) when the rebuild
+# fails or is not byte-identical to the manifest. It does not refreeze: run --freeze.
 #
 # Generated artefacts never become fix regions (cycle-130 bd-8o5rx, PRD AC-10.1):
 # a path with a `dist/` component, a name ending `.map`, `.d.ts` or `.checksum`,
@@ -202,11 +205,12 @@ def check():
     print(f"corpus OK: {n} files match SHA256SUMS")
 
 # ---------------------------------------------------------------- labels I/O
-def read_labels(fx):
+def read_labels(fx, content=None):
+    """content: labels text to parse instead of the file (--sync-labels verifies before it writes)."""
     path = os.path.join(LABELS_DIR, f"{fx}.tsv")
-    if not os.path.isfile(path):
+    if content is None and not os.path.isfile(path):
         fail(f"labels not found: {path}")
-    text = open(path, encoding="utf-8").read().splitlines()
+    text = (open(path, encoding="utf-8").read() if content is None else content).splitlines()
     if not text or not re.match(r"^# approved-by: \S", text[0]):
         fail(f"{path}: the first line must be '# approved-by: <who> <date>' (or 'pending')")
     approved_by = text[0][len("# approved-by: "):].strip()
@@ -239,10 +243,13 @@ def unique_line(lines, needle):
     return hits[0] if len(hits) == 1 else None
 
 # bd-y4pqj: `@L<n>` names head line n (1-based) for a curated anchor whose text is not unique
+# only an `@L`-shaped value (one word of letters, digits, `-`) is the line grammar: `@L12`
+# resolves, `@L0`/`@Lx`/`@L4x`/`@L-1` are refused; longer text such as `@Lazy foo` stays text
 AT_LINE_RX = re.compile(r"^@L([1-9][0-9]*)$")
+AT_SHAPE_RX = re.compile(r"^@L[0-9A-Za-z-]*$")
 def resolve_anchor(lines, must_match, fname):
     """(line, None) when the must_match resolves, else (None, why)."""
-    if must_match.startswith("@L"):
+    if AT_SHAPE_RX.match(must_match):
         m = AT_LINE_RX.match(must_match)
         if not m:
             return None, "is not @L<n> with n a positive integer"
@@ -252,8 +259,8 @@ def resolve_anchor(lines, must_match, fname):
     at = unique_line(lines, must_match)
     return (at, None) if at is not None else (None, f"is not on exactly one line of head/{fname}")
 
-def build_manifest(fx, write=True):
-    approved_by, rows, _ = read_labels(fx)
+def build_manifest(fx, write=True, labels_content=None):
+    approved_by, rows, _ = read_labels(fx, labels_content)
     fyaml = os.path.join(CORPUS, fx, "fixture.yaml")
     meta = {}
     for l in open(fyaml, encoding="utf-8"):
@@ -309,6 +316,18 @@ def build_manifest(fx, write=True):
         json.dump(man, open(os.path.join(MANIFESTS_DIR, f"{fx}.json"), "w"), indent=2)
     return man
 
+def manifest_diff(got, want):
+    """Where a rebuilt manifest differs from the tracked one (for the --sync-labels refusal)."""
+    out = [k for k in sorted(set(got) | set(want)) if k != "defects" and got.get(k) != want.get(k)]
+    gd = {d.get("id"): d for d in got.get("defects", [])}
+    if [d.get("id") for d in got.get("defects", [])] != [d.get("id") for d in want.get("defects", [])]:
+        out.append("defect ids or order")
+    for d in want.get("defects", []):
+        g = gd.get(d.get("id"))
+        if g is not None and g != d:
+            out.append(f"defect {d['id']}: " + ", ".join(sorted(k for k in set(g) | set(d) if g.get(k) != d.get(k)) or ["key order"]))
+    return "; ".join(out[:8]) or "formatting or key order"
+
 def sync_labels(fx):
     """bd-y4pqj: add a labels row for every manifest anchor no row resolves to; copy approved_by (see the header)."""
     mpath = os.path.join(MANIFESTS_DIR, f"{fx}.json")
@@ -369,7 +388,7 @@ def sync_labels(fx):
             if n in have[d["id"]]:
                 continue
             t = lines[n - 1].strip()
-            textual = (t and "\t" not in t and not t.startswith("@L") and len(t.splitlines()) == 1
+            textual = (t and "\t" not in t and not AT_SHAPE_RX.match(t) and len(t.splitlines()) == 1
                        and not has_secret(t) and unique_line(lines, t) == n)
             mm = t if textual else f"@L{n}"
             n_text, n_at = n_text + bool(textual), n_at + (not textual)
@@ -384,12 +403,19 @@ def sync_labels(fx):
         out.extend(row + "\n" for _k, _m, row in adds.get(i, []))
     new = "".join(out)
     header_changed = tl[0].rstrip("\r\n") != out[0].rstrip("\n")
+    # verify before writing, on every run (a no-op sync proves the labels too): any refusal or
+    # error while rebuilding from the new content leaves the labels file untouched
+    try:
+        rebuilt = build_manifest(fx, write=False, labels_content=new)
+    except SystemExit:
+        fail(f"{fx}: the synced labels do not build (see above); labels left unchanged")
+    except Exception as e:
+        fail(f"{fx}: rebuilding from the synced labels failed ({type(e).__name__}: {e}); labels left unchanged")
+    if json.dumps(rebuilt, indent=2) != mraw:
+        fail(f"{fx}: the synced labels would not rebuild manifests/{fx}.json byte for byte "
+             f"({manifest_diff(rebuilt, man)}); labels left unchanged")
     if new != raw:
         open(lpath, "w", encoding="utf-8", newline="").write(new)
-        rebuilt = json.dumps(build_manifest(fx, write=False), indent=2)
-        if rebuilt != mraw:
-            open(lpath, "w", encoding="utf-8", newline="").write(raw)
-            fail(f"{fx}: the synced labels would not rebuild manifests/{fx}.json byte for byte; labels left unchanged")
     print(f"{fx}: added {n_text + n_at} row(s) ({n_text} text, {n_at} @L<n>); approved-by "
           + (f"set to {approved_by!r}" if header_changed else "unchanged")
           + ("; run --freeze to refresh SHA256SUMS" if new != raw else ""))
diff --git a/evals/tests/seed-corpus.bats b/evals/tests/seed-corpus.bats
index c280a132..b121eeef 100644
--- a/evals/tests/seed-corpus.bats
+++ b/evals/tests/seed-corpus.bats
@@ -357,3 +357,58 @@ json.dump(m, open(sys.argv[1], "w"), indent=2)' "$@"
   run "$SEED" --check
   [ "$status" -eq 0 ]
 }
+
+# --- review round 1 (DISS-001 / DISS-C-001 / DISS-C-002 / DISS-C-003) ---
+
+@test "SC-13 a --sync-labels whose rebuild fails (missing fixture.yaml, an invalid fix row) exits 1 and leaves the labels byte-identical" {
+  synthetic_at_fixture
+  run "$SEED" --build-manifest pr-93 --corpus "$C"
+  [ "$status" -eq 0 ]
+  curate_manifest "$C/manifests/pr-93.json" "lead 2026-10-19 (curated)" 0 '[1, 4, 5]'
+  L="$C/labels/pr-93.tsv"
+  cp "$L" "$T/before.tsv"
+  mv "$C/pr-93/fixture.yaml" "$T/fixture.yaml"
+  run "$SEED" --sync-labels pr-93 --corpus "$C"
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"labels left unchanged"* ]]
+  cmp -s "$L" "$T/before.tsv"
+  mv "$T/fixture.yaml" "$C/pr-93/fixture.yaml"
+  sed -i "s|fix/${FIX:0:12}:4-5|fix/not-a-region|" "$L"
+  cp "$L" "$T/before.tsv"
+  run "$SEED" --sync-labels pr-93 --corpus "$C"
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"labels left unchanged"* ]]
+  cmp -s "$L" "$T/before.tsv"
+}
+
+@test "SC-14 a no-op --sync-labels still proves the rebuild: a changed severity on a synced row exits 1 naming the mismatch, labels unchanged" {
+  synthetic_at_fixture
+  run "$SEED" --build-manifest pr-93 --corpus "$C"
+  [ "$status" -eq 0 ]
+  run "$SEED" --sync-labels pr-93 --corpus "$C"
+  [ "$status" -eq 0 ]
+  [[ "$output" == *"pr-93: added 0 row(s)"* ]]
+  L="$C/labels/pr-93.tsv"
+  sed -i 's/^L02-second\tlow\t/L02-second\tcritical\t/' "$L"
+  grep -q "^L02-second	critical	" "$L"
+  cp "$L" "$T/before.tsv"
+  run "$SEED" --sync-labels pr-93 --corpus "$C"
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"L02-second"*"severity"* ]]
+  cmp -s "$L" "$T/before.tsv"
+}
+
+@test "SC-15 a head line starting with @L but not @L<digits> (\`@Lazy foo\`) is anchored by text, and --sync-labels writes it as text" {
+  synthetic_at_fixture
+  printf 'class A {\n  @Lazy foo\n  @Lob bar\n}\n' > "$C/pr-93/head/src/A.kt"
+  printf 'L03-kotlin\tmedium\tlogic\tsrc/A.kt\t@Lazy foo\treview\treview:engineer-feedback.md\n' >> "$C/labels/pr-93.tsv"
+  run "$SEED" --build-manifest pr-93 --corpus "$C"
+  [ "$status" -eq 0 ]
+  M="$C/manifests/pr-93.json"
+  [ "$(jq -r '.defects[2].anchor_line' "$M")" = "2" ]
+  [ "$(jq -r '.defects[2].must_match' "$M")" = "@Lazy foo" ]
+  curate_manifest "$M" - 2 '[2, 3]'
+  run "$SEED" --sync-labels pr-93 --corpus "$C"
+  [ "$status" -eq 0 ]
+  [ "$(awk -F'\t' '$1 == "L03-kotlin" {print $5}' "$C/labels/pr-93.tsv" | tr '\n' ,)" = "@Lazy foo,@Lob bar," ]
+}
~~~~

## I09 — fix-commit — 2026-10-21

- reference: 8ba76633de01
- files: evals/harness/seed-corpus-from-record.sh,evals/tests/seed-corpus.bats

Summary:

fix(evals): audit round — head_path containment for the labels file column (absolute, .., backslash, NUL refused; realpath under head/), atomic temp+replace labels write, approved_by guard rejects Unicode line separators — sprint-bug-268 (auditor-sprint-feedback-r1 MEDIUM-1, LOW-1..2) Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>

Evidence:

~~~~diff
commit 8ba76633de01f88a2980562a289edf685a1f470d
Date: 2026-10-21T13:10:35+11:00

fix(evals): audit round — head_path containment for the labels file column (absolute, .., backslash, NUL refused; realpath under head/), atomic temp+replace labels write, approved_by guard rejects Unicode line separators — sprint-bug-268 (auditor-sprint-feedback-r1 MEDIUM-1, LOW-1..2)

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>


diff --git a/evals/harness/seed-corpus-from-record.sh b/evals/harness/seed-corpus-from-record.sh
index 10d641f9..4ef7ff52 100755
--- a/evals/harness/seed-corpus-from-record.sh
+++ b/evals/harness/seed-corpus-from-record.sh
@@ -51,7 +51,9 @@
 # further row of the same defect_id and file adds an anchor. must_match is either
 # text that occurs on exactly one line of head/<file> (preferred: it survives
 # renumbering) or `@L<n>`, head line n (1-based, 1 <= n <= the file's line count),
-# for a line whose text is not unique (bd-y4pqj); `@L0`, a line past the end and a
+# for a line whose text is not unique (bd-y4pqj); `file` must be a relative path
+# inside pr-NN/head/ (no absolute path, `..`, backslash or NUL; symlinks may not
+# lead out), else the row is refused; `@L0`, a line past the end and a
 # non-integer after `@L` are refused with the row named. Only a one-word `@L` value
 # (`@L` followed by letters, digits or `-`) is that grammar; longer text that starts
 # with `@L` (`@Lazy foo`) is ordinary text.
@@ -61,8 +63,9 @@
 # defect resolves to, it inserts a row after that defect's last row, copying the
 # primary row's columns, with must_match the line's stripped text when that text is
 # on exactly one line (else `@L<n>`); it rewrites the first line to the manifest's
-# approved_by and keeps every other line byte for byte. It prints the rows it added,
-# adds nothing on a second run and never writes the manifest. On every run, a no-op
+# approved_by (one line: no control, C1 or U+2028/U+2029 characters) and keeps every
+# other line byte for byte; the file is replaced atomically (temp file + rename).
+# It prints the rows it added, adds nothing on a second run and never writes the manifest. On every run, a no-op
 # included, it rebuilds the manifest in memory from the new labels before writing and
 # refuses (exit 1, labels file untouched, the differing fields named) when the rebuild
 # fails or is not byte-identical to the manifest. It does not refreeze: run --freeze.
@@ -242,6 +245,17 @@ def unique_line(lines, needle):
     hits = [i for i, l in enumerate(lines, 1) if needle in l]
     return hits[0] if len(hits) == 1 else None
 
+def head_path(fx, f):
+    """(path, None) for a labels `file` inside <corpus>/<fx>/head, else (None, why): no absolute
+    path, `..` component, backslash or NUL, and the resolved path (symlinks followed) stays under head/."""
+    if not f or os.path.isabs(f) or "\\" in f or "\x00" in f or ".." in f.split("/"):
+        return None, "an absolute path, a `..` component, a backslash or a NUL"
+    base = os.path.realpath(os.path.join(CORPUS, fx, "head"))
+    hp = os.path.join(base, f)
+    if not os.path.realpath(hp).startswith(base + os.sep):
+        return None, "it resolves outside head/"
+    return hp, None
+
 # bd-y4pqj: `@L<n>` names head line n (1-based) for a curated anchor whose text is not unique
 # only an `@L`-shaped value (one word of letters, digits, `-`) is the line grammar: `@L12`
 # resolves, `@L0`/`@Lx`/`@L4x`/`@L-1` are refused; longer text such as `@Lazy foo` stays text
@@ -271,7 +285,9 @@ def build_manifest(fx, write=True, labels_content=None):
     for r in rows:
         if r["label_source"] not in ("review", "audit", "bridgebuilder", "fix"):
             errors.append(f"{r['defect_id']}: label_source {r['label_source']!r}"); continue
-        hp = os.path.join(CORPUS, fx, "head", r["file"])
+        hp, why = head_path(fx, r["file"])
+        if hp is None:
+            errors.append(f"{r['defect_id']}: file {r['file']!r} is not a path inside head/ ({why})"); continue
         if not os.path.isfile(hp):
             errors.append(f"{r['defect_id']}: head/{r['file']} missing"); continue
         lines = open(hp, encoding="utf-8", errors="replace").read().splitlines()
@@ -338,7 +354,7 @@ def sync_labels(fx):
     man = json.loads(mraw)
     approved_by = man.get("approved_by")
     if (not isinstance(approved_by, str) or not approved_by or approved_by != approved_by.strip()
-            or re.search(r"[\x00-\x1f\x7f]", approved_by)):
+            or len(approved_by.splitlines()) != 1 or re.search(r"[\x00-\x1f\x7f-\x9f\u2028\u2029]", approved_by)):
         fail(f"{mpath}: approved_by must be a one-line non-empty string without surrounding space")
     if man.get("approved") is not (approved_by != "pending"):
         fail(f"{mpath}: approved {man.get('approved')!r} disagrees with approved_by {approved_by!r}")
@@ -346,9 +362,11 @@ def sync_labels(fx):
     raw = open(lpath, encoding="utf-8", newline="").read()
     tl = raw.splitlines(keepends=True)
     heads, have, last, primary = {}, {}, {}, {}
-    def head(f):
+    def head(f, who):
         if f not in heads:
-            hp = os.path.join(CORPUS, fx, "head", f)
+            hp, why = head_path(fx, f)
+            if hp is None:
+                fail(f"{fx}: {who}: file {f!r} is not a path inside head/ ({why})")
             if not os.path.isfile(hp):
                 fail(f"{fx}: head/{f} missing")
             heads[f] = open(hp, encoding="utf-8", errors="replace").read().splitlines()
@@ -363,7 +381,7 @@ def sync_labels(fx):
         r = dict(zip(HEADER, l.split("\t")))
         if r["label_source"] == "fix":
             continue
-        at, why = resolve_anchor(head(r["file"]), r["must_match"], r["file"])
+        at, why = resolve_anchor(head(r["file"], r["defect_id"]), r["must_match"], r["file"])
         if at is None:
             fail(f"{fx}: {r['defect_id']}: must_match {r['must_match']!r} {why}")
         primary.setdefault(r["defect_id"], r)
@@ -381,7 +399,7 @@ def sync_labels(fx):
         if d.get("file") != p["file"]:
             fail(f"{fx}: manifest defect {d['id']} names {d.get('file')!r}, its labels rows {p['file']!r}")
         want = d.get("anchors", [d.get("anchor_line")])
-        lines = head(p["file"])
+        lines = head(p["file"], d["id"])
         for n in sorted(set(want)):
             if not isinstance(n, int) or isinstance(n, bool) or not 1 <= n <= len(lines):
                 fail(f"{fx}: manifest defect {d['id']} anchor {n!r} is not a line of head/{p['file']}")
@@ -415,7 +433,17 @@ def sync_labels(fx):
         fail(f"{fx}: the synced labels would not rebuild manifests/{fx}.json byte for byte "
              f"({manifest_diff(rebuilt, man)}); labels left unchanged")
     if new != raw:
-        open(lpath, "w", encoding="utf-8", newline="").write(new)
+        # atomic: a temp file beside the target, then os.replace (never an in-place truncation)
+        fd, tmp = tempfile.mkstemp(dir=LABELS_DIR, prefix=f".{fx}.tsv.", suffix=".tmp")
+        try:
+            with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
+                fh.write(new); fh.flush(); os.fsync(fh.fileno())
+            os.chmod(tmp, os.stat(lpath).st_mode & 0o7777)
+            os.replace(tmp, lpath)
+        except BaseException:
+            if os.path.exists(tmp):
+                os.remove(tmp)
+            raise
     print(f"{fx}: added {n_text + n_at} row(s) ({n_text} text, {n_at} @L<n>); approved-by "
           + (f"set to {approved_by!r}" if header_changed else "unchanged")
           + ("; run --freeze to refresh SHA256SUMS" if new != raw else ""))
diff --git a/evals/tests/seed-corpus.bats b/evals/tests/seed-corpus.bats
index b121eeef..6260451f 100644
--- a/evals/tests/seed-corpus.bats
+++ b/evals/tests/seed-corpus.bats
@@ -412,3 +412,56 @@ json.dump(m, open(sys.argv[1], "w"), indent=2)' "$@"
   [ "$status" -eq 0 ]
   [ "$(awk -F'\t' '$1 == "L03-kotlin" {print $5}' "$C/labels/pr-93.tsv" | tr '\n' ,)" = "@Lazy foo,@Lob bar," ]
 }
+
+# --- audit round (MEDIUM-1 / LOW-1 / LOW-2) ---
+
+@test "SC-16 a labels file column outside head/ (../.., absolute, a symlink out) is refused by --build-manifest and --sync-labels, nothing written" {
+  synthetic_at_fixture
+  run "$SEED" --build-manifest pr-93 --corpus "$C"
+  [ "$status" -eq 0 ]
+  M="$C/manifests/pr-93.json"; L="$C/labels/pr-93.tsv"
+  mkdir -p "$C/etc"; printf 'outside dotdot line\n' > "$C/etc/hostname"
+  printf 'outside absolute line\n' > "$T/outside.txt"
+  ln -s "$T/outside.txt" "$C/pr-93/head/src/link.txt"
+  cp "$L" "$T/ok.tsv"; cp "$M" "$T/ok.json"
+  local f mm
+  for f in '../../etc/hostname' "$T/outside.txt" 'src/link.txt'; do
+    case "$f" in ../*) mm='outside dotdot line' ;; *) mm='outside absolute line' ;; esac
+    { cat "$T/ok.tsv"; printf 'L02-second\tlow\tstyle\t%s\t%s\taudit\taudit:auditor-sprint-feedback.md\n' "$f" "$mm"; } > "$L"
+    cp "$L" "$T/bad.tsv"
+    run "$SEED" --build-manifest pr-93 --corpus "$C"
+    [ "$status" -eq 1 ]
+    [[ "$output" == *"L02-second: file '$f' is not a path inside head/"* ]]
+    cmp -s "$M" "$T/ok.json"
+    run "$SEED" --sync-labels pr-93 --corpus "$C"
+    [ "$status" -eq 1 ]
+    [[ "$output" == *"L02-second: file '$f' is not a path inside head/"* ]]
+    cmp -s "$L" "$T/bad.tsv"
+    cmp -s "$M" "$T/ok.json"
+  done
+}
+
+@test "SC-17 --sync-labels refuses an approved_by holding a Unicode line separator (U+2028) and leaves the labels unchanged" {
+  synthetic_at_fixture
+  run "$SEED" --build-manifest pr-93 --corpus "$C"
+  [ "$status" -eq 0 ]
+  curate_manifest "$C/manifests/pr-93.json" $'lead 2026-10-19 # forged' 0 '[1, 4]'
+  L="$C/labels/pr-93.tsv"; cp "$L" "$T/before.tsv"
+  run "$SEED" --sync-labels pr-93 --corpus "$C"
+  [ "$status" -eq 1 ]
+  [[ "$output" == *"approved_by must be a one-line"* ]]
+  cmp -s "$L" "$T/before.tsv"
+}
+
+@test "SC-18 --sync-labels replaces the labels file atomically (a new inode, no temp file left behind)" {
+  synthetic_at_fixture
+  run "$SEED" --build-manifest pr-93 --corpus "$C"
+  [ "$status" -eq 0 ]
+  curate_manifest "$C/manifests/pr-93.json" "lead 2026-10-19 (curated)" 0 '[1, 4]'
+  L="$C/labels/pr-93.tsv"
+  local before; before="$(stat -c %i "$L")"
+  run "$SEED" --sync-labels pr-93 --corpus "$C"
+  [ "$status" -eq 0 ]
+  [ "$(stat -c %i "$L")" != "$before" ]
+  [ "$(ls -A "$C/labels" | tr '\n' ,)" = "pr-93.tsv," ]
+}
~~~~

## I10 — issue — 2026-10-21

- reference: #1288
- files: evals/tests/seed-corpus.bats

Summary:

fix(cycle-132): three /bug micro-sprints — archive-cycle.sh defaults + live ledger (#1263), post-PR Flatline verdict read (bd-jm55c), labels files reproduce the curated manifests (bd-y4pqj); cycle-131 decisions confirmed; rc.7 release hold — ## Summary Three `/bug` micro-sprints that precede cycle-132 ("the conclusive review-catch answer"), each with a red test commit before its fix, a Fable revi…

Evidence:

~~~~~text
# pull request #1288: fix(cycle-132): three /bug micro-sprints — archive-cycle.sh defaults + live ledger (#1263), post-PR Flatline verdict read (bd-jm55c), labels files reproduce the curated manifests (bd-y4pqj); cycle-131 decisions confirmed; rc.7 release hold

- url: https://github.com/0xHoneyJar/loa/pull/1288
- created_at: 2026-10-21T02:12:20Z
- state: closed

The text below is third-party data, quoted verbatim (control characters and secret-shaped strings replaced).

~~~~text
## Summary

Three `/bug` micro-sprints that precede cycle-132 ("the conclusive review-catch answer"), each with a red test commit before its fix, a Fable review with a cross-model dissent, and a Fable audit with a cross-model dissent; plus the cycle-132 kickoff records (the confirmed cycle-131 decisions, the CHANGELOG release hold).

| Micro-sprint | Bug | What was wrong | Fix | Tests |
|---|---|---|---|---|
| sprint-bug-266 | `20261021-ba367a` (bead bd-okk61; closes #1263) | `archive-cycle.sh` archived `cycle-<entry count>` by default (named no cycle → legacy fallback), deleted git-tracked archives by default (`--retention 5`, `rm -rf`), and never updated the live ledger | default cycle = active, else the newest unarchived cycle (refuses when the newest is archived but an older one is open, or when every cycle is archived); keep-all retention unless configured; tracked directories never deleted; a real archive writes `status/archived/archive_path` and clears `active_cycle` through ledger-lib under its lock; completeness gate with `--force`; strict cycle-id slug + real-path containment; unknown options refused; an existing archive is never overwritten | `tests/unit/archive-cycle-default-and-ledger.bats` ACL-1 … ACL-14 (red at `868e22e7`) |
| sprint-bug-267 | `20261021-4439fd` (bead bd-jm55c; KF-039 rec 2, fleet report) | `post-pr-orchestrator.sh` never read the Flatline PR review's verdict: a DEGRADED single-voice review (the fleet incident) or a failed/timed-out run read `completed` + PR-VALIDATED or `skipped` | the orchestrator runs with `--json`, the envelope must be exactly one JSON object, green needs APPROVED with no blockers and no degraded flag; every other outcome is `failed` with `.run/post-pr-degraded-summary.json` and the marker `FLATLINE-PR-DEGRADED`; the flow continues to READY_FOR_HITL and the hand-off names it; the Flatline summary survives a degraded Bridgebuilder for the same PR only. The transport half of the report (argv E2BIG) is not on main — stdin since rc.3 (`398859ad`); the reporting mount was rc.2 | `tests/unit/post-pr-flatline-degraded.bats` PFD-1 … PFD-15 (red at `06bc53ce`) |
| sprint-bug-268 | `20261021-7240bc` (bead bd-y4pqj) | the labels files had drifted from the curated multi-site manifests, so `seed-corpus-from-record.sh --build-manifest` regressed them; 11 of 221 anchor lines were inexpressible as unique text | `must_match` gains the exact explicit-line form `@L<n>`; `--sync-labels pr-NN` regenerates the missing rows and the approval line from the manifest, verifying the byte-identical rebuild before writing and on every run; path containment on the `file` column; atomic write; the eight labels files synced (112 rows), `SHA256SUMS` refrozen | `evals/tests/seed-corpus.bats` SC-9 … SC-15 (red at `c1477420`) |

## Gates

- `red-test-check.sh` VERIFIED for all three at their final commits.
- Reviews: APPROVED after one round each (`grimoires/loa/a2a/bug-*/engineer-feedback.md`; dissent envelopes beside them).
- Audits: APPROVED after one audit round each (`auditor-sprint-feedback.md`).
- Local suites: archive/ledger 91 ok, post-pr 106 ok, seed-corpus + full `evals/tests/` green (counts in the a2a reports). CI runs the full BATS and eval-harness steps.

## Release

`[Unreleased]` carries a release hold: v2.0.0-rc.7 waits for the cycle-132 measurement reads (DEC-0670). No tag is cut by this PR.

## Records

Kickoff: cycle-131 decisions DEC-0610 … DEC-0655 confirmed on the operator's instruction (`decided_by: operator`); DEC-0656 … DEC-0660 (bug-phase judgment calls); KF-039 attempt row; the a2a records travel on the cycle's record branch.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
~~~~
~~~~~
