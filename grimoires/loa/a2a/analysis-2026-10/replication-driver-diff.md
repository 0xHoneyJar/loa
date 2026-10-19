# Replication driver deviation — diff of the patched out-of-repo copy against the tracked runner

```diff
--- evals/harness/run-ablation.sh	2026-10-19 01:10:38.713876980 +1100
+++ /home/merlin/.cache/loa/cycle-130/harness-partial/run-ablation-partial.sh	2026-10-19 13:52:21.341277261 +1100
@@ -302,7 +302,11 @@
 set -euo pipefail
 export LC_ALL=C
 
-SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
+# PATCHED COPY (cycle-130 deep analysis, 2026-10-19): the replication suite root holds two review-catch tasks, and the
+# runner's freeze --check and grader calls have no --allow-partial passthrough; this copy (outside the repo) adds the flag
+# to those two calls and pins SCRIPT_DIR to the repo harness so every collaborator is the unmodified tracked script.
+SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
+SCRIPT_DIR="<repo>/evals/harness"
 REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
 # eval.yml trust boundary: a literal in-tree path, no variable on the source line
 pushd "$SCRIPT_DIR" >/dev/null
@@ -492,9 +496,9 @@
   for a in "${SELF_ARGS[@]}"; do [[ "$a" == --detach ]] || child+=("$a"); done
   child+=(--batch "$BATCH")
   if command -v setsid >/dev/null 2>&1; then
-    setsid nohup "$SCRIPT_DIR/run-ablation.sh" "${child[@]}" > "$BATCH_DIR/driver.log" 2>&1 < /dev/null &
+    setsid nohup "$SELF_PATH" "${child[@]}" > "$BATCH_DIR/driver.log" 2>&1 < /dev/null &
   else
-    nohup "$SCRIPT_DIR/run-ablation.sh" "${child[@]}" > "$BATCH_DIR/driver.log" 2>&1 < /dev/null &
+    nohup "$SELF_PATH" "${child[@]}" > "$BATCH_DIR/driver.log" 2>&1 < /dev/null &
   fi
   echo "detached: batch $BATCH_DIR pid $! (log $BATCH_DIR/driver.log)"
   exit 0
@@ -693,7 +697,7 @@
 PY
 )"
 fi
-FREEZE_ARGS=(--check --root "$SUITE_ROOT" --suite-file "$SUITE_FILE")
+FREEZE_ARGS=(--check --root "$SUITE_ROOT" --suite-file "$SUITE_FILE" --allow-partial)   # PATCHED: partial suite root
 if [[ "$SMOKE" == true ]] || grep -q '  smoke/' "$SUITE_ROOT/MANIFEST.sha256" 2>/dev/null; then FREEZE_ARGS+=(--smoke); fi
 frc=0; fout="$("$FREEZE_BIN" "${FREEZE_ARGS[@]}" 2>&1)" || frc=$?
 [[ $frc -eq 0 ]] || refuse "freeze.sh ${FREEZE_ARGS[*]} failed (exit $frc): $(printf '%s' "$fout" | tail -5 | tr '\n' ' ')"
@@ -1239,7 +1243,7 @@
         done < <(jq -r 'to_entries[] | [.key, (.value.phases | join(",")), (.value.output_tokens | tostring)] | @tsv' <<<"$PR_EXTRA")
         if [[ "$PR_DRIFT" != null ]]; then PR_OVERRIDE=infrastructure_error; printf 'run-ablation: drift %s\n' "$PR_DRIFT" >> "$plog"; fi
         if [[ -z "$PR_OVERRIDE" ]]; then
-          local -a g=("$GRADE_BIN" "$rd" "$task" --suite-root "$SUITE_ROOT" --executor "$EXECUTOR" --image "$IMAGE" --docker-bin "$DOCKER_BIN")
+          local -a g=("$GRADE_BIN" "$rd" "$task" --suite-root "$SUITE_ROOT" --executor "$EXECUTOR" --image "$IMAGE" --docker-bin "$DOCKER_BIN" --allow-partial)   # PATCHED
           [[ "$SMOKE" == true ]] && g+=(--tasks-dir smoke)
           PR_GRC=0; ${GRADE_TMO[@]+"${GRADE_TMO[@]}"} "${g[@]}" >> "$plog" 2>&1 || PR_GRC=$?
           if [[ ${#GRADE_TMO[@]} -gt 0 && ( $PR_GRC -eq 124 || $PR_GRC -eq 137 ) ]]; then
```
