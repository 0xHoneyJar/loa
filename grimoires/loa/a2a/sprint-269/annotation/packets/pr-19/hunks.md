# Hunks — pr-19

The later fix changed 20 region(s) in 8 of the change's 81 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — .claude/scripts/guard-yield.sh — head lines 220–229

Head context (head/.claude/scripts/guard-yield.sh, lines 208–241):

~~~~text
   208 |   | join("\u001f")
   209 | ' "$SETTINGS" > "$HOOK_LINES" || die 3 "settings hooks could not be enumerated: $SETTINGS"
   210 | 
   211 | HOOK_ROWS="$TMPWORK/hooks.jsonl"
   212 | : > "$HOOK_ROWS"
   213 | while IFS="$US" read -r tag ev mt rel wrapped; do
   214 |     [[ -n "$tag" ]] || continue
   215 |     if [[ "$tag" != "ok" ]]; then
   216 |         echo "hook command outside the canonical schema \"\$(git rev-parse --show-toplevel)\"/.claude/<path> [args] (or wrapped in hook-guard.sh): $ev" >> "$ERRORS"
   217 |         continue
   218 |     fi
   219 |     abs="$ROOT/.claude/$rel"
>  220 |     if [[ -L "$abs" ]]; then
>  221 |         tgt="$(readlink "$abs")"
>  222 |         case "$tgt" in /*) ;; *) tgt="$(dirname "$abs")/$tgt" ;; esac
>  223 |         tdir="$(cd "$(dirname "$tgt")" 2>/dev/null && pwd -P)" || tdir=""
>  224 |         canon="$tdir/$(basename "$tgt")"
>  225 |         case "$canon" in
>  226 |             "$ROOT/.claude/"*) rel="${canon#"$ROOT/.claude/"}"; abs="$canon" ;;
>  227 |             *) echo "hook script .claude/$rel is a symlink that leaves .claude/ (registered for $ev)" >> "$ERRORS"; continue ;;
>  228 |         esac
>  229 |     fi
   230 |     if [[ ! -f "$abs" ]]; then
   231 |         echo "hook script .claude/$rel registered for $ev does not exist" >> "$ERRORS"
   232 |         continue
   233 |     fi
   234 |     case "$rel" in hooks/*) id="hook:${rel#hooks/}" ;; *) id="hook:$rel" ;; esac
   235 |     if [[ -n "$mt" ]]; then reg="$ev:$mt"; else reg="$ev"; fi
   236 |     jq -cn --arg id "$id" --arg rel "$rel" --arg ev "$ev" --arg mt "$mt" --arg reg "$reg" --arg w "$wrapped" \
   237 |         '{id: $id, rel: $rel, event: $ev, matcher: $mt, registration: $reg, wrapped: ($w == "1")}' >> "$HOOK_ROWS"
   238 | done < "$HOOK_LINES"
   239 | HOOKS_JSON="$(jq -cs '.' "$HOOK_ROWS")"
   240 | 
   241 | # ----------------------------------------------------------------------------- fence markers
~~~~

The change from head to the fix:

~~~~diff
@@ -220,10 +220,19 @@
-    if [[ -L "$abs" ]]; then
-        tgt="$(readlink "$abs")"
-        case "$tgt" in /*) ;; *) tgt="$(dirname "$abs")/$tgt" ;; esac
+    if [[ ! -e "$abs" ]]; then
+        echo "hook script .claude/$rel registered for $ev does not exist" >> "$ERRORS"
+        continue
+    fi
+    # Containment on the physical path: every component resolved (pwd -P on the
+    # parent, readlink on the leaf), so an intermediate symlinked directory under
+    # .claude/ cannot point the register at a file outside it (review r1 DISS-C-002).
+    tdir="$(cd "$(dirname "$abs")" 2>/dev/null && pwd -P)" || tdir=""
+    canon="$tdir/$(basename "$abs")"
+    if [[ -L "$canon" ]]; then
+        tgt="$(readlink "$canon")"
+        case "$tgt" in /*) ;; *) tgt="$tdir/$tgt" ;; esac
         tdir="$(cd "$(dirname "$tgt")" 2>/dev/null && pwd -P)" || tdir=""
         canon="$tdir/$(basename "$tgt")"
-        case "$canon" in
-            "$ROOT/.claude/"*) rel="${canon#"$ROOT/.claude/"}"; abs="$canon" ;;
-            *) echo "hook script .claude/$rel is a symlink that leaves .claude/ (registered for $ev)" >> "$ERRORS"; continue ;;
-        esac
     fi
+    case "$canon" in
+        "$ROOT/.claude/"*) rel="${canon#"$ROOT/.claude/"}"; abs="$canon" ;;
+        *) echo "hook script .claude/$rel resolves outside .claude/ (registered for $ev): $canon" >> "$ERRORS"; continue ;;
+    esac
~~~~

## H02 — .claude/scripts/guard-yield.sh — insertion after head line 334

Head context (head/.claude/scripts/guard-yield.sh, lines 323–346):

~~~~text
   323 |     ((($floor.floor_guards // []) | if type != "array" then ["(floor_guards is not a list)"] else . end) as $fg
   324 |       | ($fg[] | select($by[.] == null) | "floor guard \(.) has no row in \($map)"),
   325 |         ($g[] | select(.floor == true) | select(.id | IN($fg[]) | not) | "row \(.id) has floor: true but is not in floor.yaml floor_guards"),
   326 |         ($g[] | select(.floor != true) | select(.id | IN($fg[])) | "row \(.id) is in floor.yaml floor_guards but has floor: false"))
   327 | ' <<<"$MAP_JSON" >> "$ERRORS"
   328 | 
   329 | while IFS= read -r spath; do
   330 |     [[ -n "$spath" ]] || continue
   331 |     case "$spath" in /*|*..*) echo "gate or policy script '$spath' must be a repository-relative path" >> "$ERRORS"; continue ;; esac
   332 |     [[ -f "$ROOT/$spath" ]] || echo "gate or policy script $spath does not exist" >> "$ERRORS"
   333 | done < <(jq -r '.guards[] | select(.kind == "gate" or .kind == "policy") | .script' <<<"$MAP_JSON")
   334 | 
   335 | if [[ -s "$ERRORS" ]]; then
   336 |     sed "s/^/$SCRIPT_NAME: /" "$ERRORS" >&2
   337 |     exit 5
   338 | fi
   339 | 
   340 | # ----------------------------------------------------------------------------- renderers
   341 | # Shared cell sanitiser: control characters removed, pipes escaped for GFM tables.
   342 | JQ_DEFS='
   343 |   def cell: tostring | explode | map(select(. >= 32 and . != 127)) | implode | gsub("\\|"; "\\|");
   344 |   def kinds: ["hook", "fence", "validator", "gate", "policy"];
   345 |   def regs: if (.registrations // []) | length == 0 then "-" else (.registrations | map("`" + cell + "`") | join(", ")) end;
   346 |   def origin_txt: .origin as $o | if ($o.ref | tostring | startswith($o.kind | tostring)) then ($o.ref | tostring) else "\($o.kind) \($o.ref)" end;
~~~~

The change from head to the fix:

~~~~diff
@@ -334,0 +344,12 @@
+# A floor gate implemented as a hook must be REGISTERED, not merely present on disk:
+# a row whose script lives under .claude/hooks/ needs a command in settings.json that
+# runs it (review r1 DISS-C-003 — unregistering adversarial-review-gate.sh and dropping
+# its hook row would otherwise leave --check green while the COMPLETED gate never runs).
+jq -r --argjson e "$ENUM_JSON" '
+  ($e.hooks | map(.id)) as $hooks
+  | .guards[] | select(.floor == true and .kind == "gate" and ((.script // "") | startswith(".claude/hooks/")))
+  | . as $g | ("hook:" + ($g.script | ltrimstr(".claude/hooks/"))) as $hid
+  | select($hooks | index($hid) | not)
+  | "floor gate \($g.id) names \($g.script) but no command in .claude/settings.json runs it (the gate is not registered)"
+' <<<"$MAP_JSON" >> "$ERRORS"
+
~~~~

## H03 — .claude/scripts/guard-yield.sh — insertion after head line 393

Head context (head/.claude/scripts/guard-yield.sh, lines 382–405):

~~~~text
   382 |         "<!-- guard-register:end -->"
   383 |     ' <<<"$MAP_JSON"
   384 | }
   385 | 
   386 | # Rewrites the marker block of $HOOKS_REF into $2 (exit 3 when the markers are absent or repeated).
   387 | render_hooks_ref() {
   388 |     local block="$1" dest="$2" nb ne
   389 |     [[ -f "$HOOKS_REF" && -r "$HOOKS_REF" ]] || die 3 "hooks reference not readable: $HOOKS_REF"
   390 |     nb="$(grep -c '^<!-- guard-register:begin -->$' "$HOOKS_REF" || true)"
   391 |     ne="$(grep -c '^<!-- guard-register:end -->$' "$HOOKS_REF" || true)"
   392 |     [[ "$nb" == "1" && "$ne" == "1" ]] \
   393 |         || die 3 "$HOOKS_REF needs exactly one <!-- guard-register:begin --> and one <!-- guard-register:end --> line (found $nb and $ne)"
   394 |     awk -v blockfile="$block" '
   395 |       /^<!-- guard-register:begin -->$/ { while ((getline l < blockfile) > 0) print l; skip = 1; next }
   396 |       /^<!-- guard-register:end -->$/ { skip = 0; next }
   397 |       !skip { print }
   398 |     ' "$HOOKS_REF" > "$dest"
   399 | }
   400 | 
   401 | # Atomic replace: temp beside the destination, then rename.
   402 | install_file() {
   403 |     local src="$1" dest="$2" tmp
   404 |     mkdir -p "$(dirname "$dest")"
   405 |     tmp="$(mktemp "$(dirname "$dest")/.$(basename "$dest").XXXXXX")"
~~~~

The change from head to the fix:

~~~~diff
@@ -393,0 +415,7 @@
+    # The end marker must follow the begin marker, else the awk pass below would drop
+    # everything after a misplaced end line (review r1 DISS-C-006).
+    local lb le
+    lb="$(grep -n '^<!-- guard-register:begin -->$' "$HOOKS_REF" | cut -d: -f1)"
+    le="$(grep -n '^<!-- guard-register:end -->$' "$HOOKS_REF" | cut -d: -f1)"
+    [[ "$lb" -lt "$le" ]] \
+        || die 3 "$HOOKS_REF has its <!-- guard-register:end --> marker (line $le) before the begin marker (line $lb); restore the order"
~~~~

## H04 — .github/workflows/bats-tests.yml — insertion after head line 91

Head context (head/.github/workflows/bats-tests.yml, lines 80–103):

~~~~text
    80 | env:
    81 |   REQUIRE_TESTS: 'true'
    82 |   PYTHONDONTWRITEBYTECODE: '1'
    83 | 
    84 | jobs:
    85 |   bats:
    86 |     name: Shell Tests
    87 |     runs-on: ubuntu-latest
    88 |     steps:
    89 |       # PINNING: SHA verified against actions/checkout v4.3.1 tag
    90 |       - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1
    91 | 
    92 |       - name: Configure git identity for tests
    93 |         run: |
    94 |           git config --global user.name "CI Bot"
    95 |           git config --global user.email "ci@example.com"
    96 | 
    97 |       # Real Aleph installer fixtures require Node 22 or later.
    98 |       - uses: actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020 # v4.4.0
    99 |         with:
   100 |           node-version: '22.22.0'
   101 | 
   102 |       # PINNING: SHA matches the actions/setup-python v5.3.0 pin used by
   103 |       # cycle099-sprint-1e-tests.yml and jcs-conformance.yml. Rotate together.
~~~~

The change from head to the fix:

~~~~diff
@@ -91,0 +92,6 @@
+      # cycle-129 FR-1: tests/unit/floor-snapshot.bats compares the floor files and
+      # corpus rows with origin/main; the depth-1 checkout has no origin/main, so
+      # fetch that one ref (no tags) or the floor proof would skip in CI.
+      - name: Fetch origin/main for the floor snapshot
+        run: git fetch --no-tags --depth=1 origin +refs/heads/main:refs/remotes/origin/main
+
~~~~

## H05 — evals/harness/execute-agent.sh — head lines 163–165

Head context (head/evals/harness/execute-agent.sh, lines 151–177):

~~~~text
   151 | 
   152 | # --- 2b. control arm (cycle-129 FR-2) -----------------------------------------
   153 | ARM_MODE=false
   154 | [[ -n "${LOA_EVAL_ARM+x}" ]] && ARM_MODE=true
   155 | ARM="${LOA_EVAL_ARM:-baseline}"
   156 | [[ "$ARM" =~ ^[a-z][a-z0-9_]{0,63}$ ]] || { echo "ERROR: invalid LOA_EVAL_ARM '$ARM'" >&2; exit 2; }
   157 | if [[ "$ARM_MODE" == "true" && -f "$PROMPT_TREE/.loa.config.yaml" ]]; then
   158 |   cp "$PROMPT_TREE/.loa.config.yaml" "$WORKSPACE/.loa.config.yaml"
   159 | fi
   160 | 
   161 | # The arm's toggles: explicit JSON, else the suite's ab.arms[] entry.
   162 | resolve_toggles() {
>  163 |   if [[ -n "${LOA_EVAL_ARM_TOGGLES:-}" ]]; then
>  164 |     jq -ce 'if type == "object" then . else error("not an object") end' <<<"$LOA_EVAL_ARM_TOGGLES" 2>/dev/null \
>  165 |       || { echo "ERROR: LOA_EVAL_ARM_TOGGLES is not a JSON object" >&2; return 2; }
   166 |     return 0
   167 |   fi
   168 |   local suite_file="${LOA_EVAL_SUITE_FILE:-}"
   169 |   if [[ -z "$suite_file" ]]; then
   170 |     local tdir; tdir="$(basename "$(dirname "$TASK_YAML")")"
   171 |     [[ -f "$REPO_ROOT/evals/suites/$tdir.yaml" ]] && suite_file="$REPO_ROOT/evals/suites/$tdir.yaml"
   172 |   fi
   173 |   local t="" found=0
   174 |   if [[ -n "$suite_file" && -f "$suite_file" ]]; then
   175 |     found="$(ARM="$ARM" yq '[.ab.arms[]? | select(.id == strenv(ARM))] | length' "$suite_file" 2>/dev/null || echo 0)"
   176 |     [[ "$found" =~ ^[0-9]+$ ]] || found=0
   177 |     if [[ "$found" -gt 0 ]]; then
~~~~

The change from head to the fix:

~~~~diff
@@ -163,3 +163,13 @@
+  # audit r1 DISS-C-001: toggles exist only in arm mode (LOA_EVAL_ARM set); a stale
+  # LOA_EVAL_ARM_TOGGLES in a non-arm environment is ignored, and the baseline arm
+  # never carries toggles.
+  if [[ "$ARM_MODE" != "true" ]]; then
+    [[ -z "${LOA_EVAL_ARM_TOGGLES:-}" ]] || echo "WARN: LOA_EVAL_ARM_TOGGLES is set but LOA_EVAL_ARM is not: ignored (not an arm run)" >&2
+    printf '{}'; return 0
+  fi
   if [[ -n "${LOA_EVAL_ARM_TOGGLES:-}" ]]; then
     jq -ce 'if type == "object" then . else error("not an object") end' <<<"$LOA_EVAL_ARM_TOGGLES" 2>/dev/null \
       || { echo "ERROR: LOA_EVAL_ARM_TOGGLES is not a JSON object" >&2; return 2; }
+    if [[ "$ARM" == "baseline" && "$(jq -c 'length' <<<"$LOA_EVAL_ARM_TOGGLES")" != "0" ]]; then
+      echo "ERROR: the baseline arm takes no toggles (LOA_EVAL_ARM_TOGGLES=$LOA_EVAL_ARM_TOGGLES)" >&2; return 2
+    fi
~~~~

## H06 — evals/harness/execute-agent.sh — head lines 254–258

Head context (head/evals/harness/execute-agent.sh, lines 242–270):

~~~~text
   242 |           || { echo "ERROR: companion_voice toggle: yq failed on the sandbox config" >&2; return 2; }
   243 |         [[ "$(yq -r '.flatline_protocol.code_review.companion_voice' "$cfg")" == "false" ]] \
   244 |           || { echo "ERROR: companion_voice toggle did not take effect" >&2; return 2; }
   245 |         _evidence companion_voice "flatline_protocol.{code_review,security_audit}.companion_voice=false"
   246 |         ;;
   247 |       karpathy_block)
   248 |         local k="$WORKSPACE/.claude/loa/CLAUDE.loa.md" n
   249 |         [[ -f "$k" ]] || { echo "ERROR: karpathy_block toggle: no sandbox CLAUDE.loa.md" >&2; return 2; }
   250 |         n="$(_drop_md_section "$k" '## Karpathy Principles')"
   251 |         if [[ "${n:-0}" -eq 0 ]] || grep -q '^## Karpathy Principles' "$k"; then
   252 |           echo "ERROR: karpathy_block toggle: no '## Karpathy Principles' section removed" >&2; return 2
   253 |         fi
>  254 |         local cj="$WORKSPACE/.claude/data/constraints.json"
>  255 |         if [[ -f "$cj" ]]; then
>  256 |           jq '(.constraints // []) |= map(select((tostring | test("karpathy"; "i")) | not))' "$cj" > "$cj.tmp" && mv "$cj.tmp" "$cj"
>  257 |         fi
>  258 |         _evidence karpathy_block "removed ${n} lines from CLAUDE.loa.md"
   259 |         ;;
   260 |       rule_files)
   261 |         local r gone=""
   262 |         for r in stash-safety.md skill-invariants.md; do
   263 |           if [[ -e "$WORKSPACE/.claude/rules/$r" ]]; then rm -f "$WORKSPACE/.claude/rules/$r"; gone="$gone $r"; fi
   264 |           [[ ! -e "$WORKSPACE/.claude/rules/$r" ]] || { echo "ERROR: rule_files toggle: $r still present" >&2; return 2; }
   265 |         done
   266 |         _evidence rule_files "removed:${gone:- none present}"
   267 |         ;;
   268 |       audit_delta_instruction)
   269 |         local s="$WORKSPACE/.claude/skills/auditing-security/SKILL.md"
   270 |         [[ -f "$s" ]] || { echo "ERROR: audit_delta_instruction toggle: no sandbox auditing-security/SKILL.md" >&2; return 2; }
~~~~

The change from head to the fix:

~~~~diff
@@ -254,5 +264,10 @@
-        local cj="$WORKSPACE/.claude/data/constraints.json"
+        local cj="$WORKSPACE/.claude/data/constraints.json" cjn="none"
         if [[ -f "$cj" ]]; then
-          jq '(.constraints // []) |= map(select((tostring | test("karpathy"; "i")) | not))' "$cj" > "$cj.tmp" && mv "$cj.tmp" "$cj"
+          # audit r1 DISS-C-008: a failed rewrite is exit 2, not a silent pass; verify afterwards
+          jq '(.constraints // []) |= map(select((tostring | test("karpathy"; "i")) | not))' "$cj" > "$cj.tmp" \
+            || { rm -f "$cj.tmp"; echo "ERROR: karpathy_block toggle: constraints.json could not be rewritten" >&2; return 2; }
+          mv "$cj.tmp" "$cj"
+          cjn="$(jq '[(.constraints // [])[] | select(tostring | test("karpathy"; "i"))] | length' "$cj" 2>/dev/null || echo "?")"
+          [[ "$cjn" == "0" ]] || { echo "ERROR: karpathy_block toggle: constraints.json still carries Karpathy rows ($cjn)" >&2; return 2; }
         fi
-        _evidence karpathy_block "removed ${n} lines from CLAUDE.loa.md"
+        _evidence karpathy_block "removed ${n} lines from CLAUDE.loa.md; constraints.json karpathy rows after: ${cjn}"
~~~~

## H07 — evals/harness/execute-agent.sh — insertion after head line 289

Head context (head/evals/harness/execute-agent.sh, lines 278–301):

~~~~text
   278 |   return 0
   279 | }
   280 | apply_toggles || exit 2
   281 | 
   282 | # Skill body without the YAML frontmatter → the appended system prompt. Read
   283 | # from the (toggled) sandbox copy so an arm reaches the system prompt too.
   284 | awk 'BEGIN{fm=0} NR==1 && $0=="---"{fm=1; next} fm==1 && $0=="---"{fm=2; next} fm!=1{print}' \
   285 |   "$skill_dst/SKILL.md" > "$eval_dir/skill-prompt.md"
   286 | 
   287 | # Prompt-tree identity (what the A/B is actually varying).
   288 | prompt_tree_sha="$(git -C "$PROMPT_TREE" rev-parse HEAD:.claude 2>/dev/null || echo unknown)"
   289 | prompt_tree_commit="$(git -C "$PROMPT_TREE" rev-parse HEAD 2>/dev/null || echo unknown)"
   290 | prompt_tree_dirty=false
   291 | if [[ -n "$(git -C "$PROMPT_TREE" status --porcelain -- .claude 2>/dev/null)" ]]; then
   292 |   prompt_tree_dirty=true
   293 | fi
   294 | 
   295 | # Effort: env > task > skill frontmatter > none; invalid → none.
   296 | resolve_effort() {
   297 |   local cand="${EVAL_EFFORT:-}"
   298 |   if [[ -z "$cand" ]]; then
   299 |     cand="$(yq -r '.agent.effort // ""' "$TASK_YAML")"
   300 |   fi
   301 |   if [[ -z "$cand" || "$cand" == "null" ]]; then
~~~~

The change from head to the fix:

~~~~diff
@@ -289,0 +305,10 @@
+# audit r1 DISS-C-009: a declared source commit is a hex id and, when the prompt tree's
+# HEAD is known, the same commit — otherwise two trials from different trees could
+# present one source_commit and pass compare.sh's skew check.
+if [[ -n "${LOA_EVAL_SOURCE_COMMIT:-}" ]]; then
+  [[ "$LOA_EVAL_SOURCE_COMMIT" =~ ^[0-9a-f]{7,40}$ ]] \
+    || { echo "ERROR: LOA_EVAL_SOURCE_COMMIT is not a hex commit id" >&2; exit 2; }
+  if [[ "$prompt_tree_commit" != "unknown" && "$prompt_tree_commit" != "$LOA_EVAL_SOURCE_COMMIT"* ]]; then
+    echo "ERROR: LOA_EVAL_SOURCE_COMMIT ($LOA_EVAL_SOURCE_COMMIT) is not the prompt tree's HEAD ($prompt_tree_commit)" >&2; exit 2
+  fi
+fi
~~~~

## H08 — evals/harness/run-arms.sh — head lines 45–46

Head context (head/evals/harness/run-arms.sh, lines 33–58):

~~~~text
    33 | #
    34 | # Layout: <results-dir>/<suite>/<batch>/{MANIFEST.json,STATUS.json,run.log,
    35 | #   <arm>/results.jsonl,<arm>/artifacts/…}; <results-dir>/<suite>/STATUS.json
    36 | #   aggregates every batch of the suite (the Sprint 2 gate and report.sh
    37 | #   --arms read it). STATUS.json: {state: running|complete|partial|failed,
    38 | #   per_arm: {<arm>: {trials_done, trials_failed, trials_planned}},
    39 | #   source_commit, model_id, started, finished}.
    40 | #
    41 | # Exit: 0 complete, 1 partial (some trial failed twice; results kept),
    42 | #       2 usage / refused before starting, 3 failed (no trial completed, or
    43 | #       the corpus drifted mid-run)
    44 | #
>   45 | # Executor: Fable 5.1 (D33, DEC-0164); the default --model is the id the
>   46 | # local claude CLI accepted on the cycle-129 probe (claude-fable-5-1).
    47 | # Tested by evals/tests/run-arms.bats (stubbed CLI; no model call).
    48 | # =============================================================================
    49 | set -euo pipefail
    50 | export LC_ALL=C
    51 | 
    52 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    53 | REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    54 | EVALS_DIR="$REPO_ROOT/evals"
    55 | CORPUS_DIR="$EVALS_DIR/fixtures/review-prs"
    56 | DEFAULT_MODEL="claude-fable-5-1"
    57 | CACHE_ROOT="${LOA_ARMS_CACHE:-$HOME/.cache/loa/cycle-129}"
    58 | # the repository the pinned source worktree is cut from (tests point it at a
~~~~

The change from head to the fix:

~~~~diff
@@ -45,2 +45,6 @@
-# Executor: Fable 5.1 (D33, DEC-0164); the default --model is the id the
-# local claude CLI accepted on the cycle-129 probe (claude-fable-5-1).
+# Executor: Opus 5.5 (DEC-0172, amending D33/DEC-0164): the cycle-129 proof
+# trial on claude-fable-5-1 was refused by a safeguard and the CLI fell back to
+# Opus mid-session, so a Fable run is not homogeneous; the default --model is
+# the homogeneous id. The arms therefore carry a model-transfer assumption
+# (measured on Opus 5.5, the production gates run on Fable 5.1), stated in the
+# report header and next to every change the arms clear.
~~~~

## H09 — evals/harness/run-arms.sh — head line 56

Head context (head/evals/harness/run-arms.sh, lines 44–68):

~~~~text
    44 | #
    45 | # Executor: Fable 5.1 (D33, DEC-0164); the default --model is the id the
    46 | # local claude CLI accepted on the cycle-129 probe (claude-fable-5-1).
    47 | # Tested by evals/tests/run-arms.bats (stubbed CLI; no model call).
    48 | # =============================================================================
    49 | set -euo pipefail
    50 | export LC_ALL=C
    51 | 
    52 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    53 | REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    54 | EVALS_DIR="$REPO_ROOT/evals"
    55 | CORPUS_DIR="$EVALS_DIR/fixtures/review-prs"
>   56 | DEFAULT_MODEL="claude-fable-5-1"
    57 | CACHE_ROOT="${LOA_ARMS_CACHE:-$HOME/.cache/loa/cycle-129}"
    58 | # the repository the pinned source worktree is cut from (tests point it at a
    59 | # throwaway repo so they never register a worktree in the real one)
    60 | SOURCE_REPO="${LOA_ARMS_SOURCE_REPO:-$REPO_ROOT}"
    61 | 
    62 | SUITE="" ARMS_CSV="" FIXTURES_CSV="" TRIALS="" SOURCE_COMMIT="" MODEL="$DEFAULT_MODEL"
    63 | CONCURRENCY=2 BATCH="" RESULTS_ROOT="$EVALS_DIR/results/arms" RETRY_WAIT=300
    64 | DRY_RUN=false ALLOW_UNAPPROVED=false
    65 | 
    66 | usage() { sed -n '2,/^# =====.*$/p' "$0" | sed -n '2,46p' | sed 's/^# \{0,1\}//' >&2; exit 2; }
    67 | die() { echo "run-arms: $*" >&2; exit 2; }
    68 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -56 +60 @@
-DEFAULT_MODEL="claude-fable-5-1"
+DEFAULT_MODEL="global.anthropic.claude-opus-5-5"
~~~~

## H10 — evals/harness/run-arms.sh — insertion after head line 127

Head context (head/evals/harness/run-arms.sh, lines 116–139):

~~~~text
   116 |         && "$ALLOW_UNAPPROVED" != "true" ]]; then
   117 |     die "$f: labels.tsv is not approved yet (seed-corpus-from-record.sh --approve $f --by '<who> <date>'), or pass --allow-unapproved"
   118 |   fi
   119 | done
   120 | 
   121 | SRC_FULL="$(git -C "$SOURCE_REPO" rev-parse --verify --quiet "${SOURCE_COMMIT}^{commit}" 2>/dev/null)" \
   122 |   || die "source commit $SOURCE_COMMIT is not in this repository"
   123 | SRC12="${SRC_FULL:0:12}"
   124 | WORKTREE="$CACHE_ROOT/arms-src-$SRC12"
   125 | 
   126 | [[ -n "$BATCH" ]] || BATCH="batch-${FIXTURES[0]}-${FIXTURES[${#FIXTURES[@]}-1]}-n${#FIXTURES[@]}"
   127 | [[ "$BATCH" =~ ^[A-Za-z0-9._-]{1,80}$ ]] || die "invalid --batch '$BATCH'"
   128 | SUITE_DIR="$RESULTS_ROOT/$SUITE"
   129 | BATCH_DIR="$SUITE_DIR/$BATCH"
   130 | 
   131 | # --- corpus freeze ------------------------------------------------------------
   132 | # verify_corpus [<fixture>] — every SHA256SUMS entry (or one fixture's entries
   133 | # and its manifest) hashes as recorded. Prints the SHA256SUMS digest.
   134 | verify_corpus() {
   135 |   python3 -I - "$CORPUS_DIR" "${1:-}" <<'PY'
   136 | import hashlib, os, sys
   137 | corpus, only = sys.argv[1], sys.argv[2]
   138 | sums = os.path.join(corpus, "SHA256SUMS")
   139 | raw = open(sums, "rb").read()
~~~~

The change from head to the fix:

~~~~diff
@@ -127,0 +132 @@
+case "$BATCH" in .|..) die "invalid --batch '$BATCH' (a batch is one child directory)" ;; esac   # audit r1 DISS-C-004
~~~~

## H11 — evals/harness/run-arms.sh — insertion after head line 150

Head context (head/evals/harness/run-arms.sh, lines 139–162):

~~~~text
   139 | raw = open(sums, "rb").read()
   140 | bad = []
   141 | for line in raw.decode("utf-8").splitlines():
   142 |     if not line.strip():
   143 |         continue
   144 |     digest, rel = line.split("  ", 1)
   145 |     if only and not (rel.startswith(only + "/") or rel == f"manifests/{only}.json" or rel == "corpus.tsv"
   146 |                      or rel.startswith(f"labels/{only}.")):
   147 |         continue
   148 |     p = os.path.join(corpus, rel)
   149 |     if not os.path.isfile(p) or hashlib.sha256(open(p, "rb").read()).hexdigest() != digest:
   150 |         bad.append(rel)
   151 | if bad:
   152 |     print("corpus drift: " + ", ".join(bad[:10]), file=sys.stderr)
   153 |     sys.exit(1)
   154 | print(hashlib.sha256(raw).hexdigest())
   155 | PY
   156 | }
   157 | CORPUS_DIGEST="$(verify_corpus)" || die "fixture corpus does not match SHA256SUMS (run build/seed with --check first)"
   158 | 
   159 | # --- the planned trials (interleaved: trial-major, then fixture, then arm) ----
   160 | PLAN=()
   161 | for t in $(seq 1 "$TRIALS"); do
   162 |   for f in "${FIXTURES[@]}"; do
~~~~

The change from head to the fix:

~~~~diff
@@ -150,0 +156,23 @@
+# audit r1 DISS-C-002: a file present on disk but absent from SHA256SUMS is drift too
+# (the seed's --check already says so; the runner must agree), else an added file
+# would reach the sandbox under an unchanged corpus digest.
+listed = {l.split("  ", 1)[1] for l in raw.decode("utf-8").splitlines() if l.strip()}
+walk_root = os.path.join(corpus, only) if only else corpus
+for root, _d, files in os.walk(walk_root):
+    for f in files:
+        rel = os.path.relpath(os.path.join(root, f), corpus)
+        if rel == "SHA256SUMS" or rel in listed:
+            continue
+        if only and not (rel.startswith(only + "/")):
+            continue
+        bad.append(rel + " (not listed)")
+if only:
+    for extra in (f"manifests/{only}.json", "corpus.tsv"):
+        if os.path.isfile(os.path.join(corpus, extra)) and extra not in listed:
+            bad.append(extra + " (not listed)")
+    ldir = os.path.join(corpus, "labels")
+    if os.path.isdir(ldir):
+        for f in os.listdir(ldir):
+            rel = f"labels/{f}"
+            if f.startswith(only + ".") and rel not in listed:
+                bad.append(rel + " (not listed)")
~~~~

## H12 — evals/harness/run-arms.sh — head lines 231–232

Head context (head/evals/harness/run-arms.sh, lines 219–244):

~~~~text
   219 |   echo "manifest: $mpath"
   220 |   exit 0
   221 | fi
   222 | 
   223 | CLAUDE_BIN="${EVAL_CLAUDE_BIN:-claude}"
   224 | command -v "$CLAUDE_BIN" >/dev/null 2>&1 || [[ -x "$CLAUDE_BIN" ]] || die "executor CLI not found: $CLAUDE_BIN"
   225 | 
   226 | # --- the pinned source worktree -------------------------------------------------
   227 | mkdir -p "$CACHE_ROOT"
   228 | if [[ -e "$WORKTREE" ]]; then
   229 |   [[ "$(git -C "$WORKTREE" rev-parse HEAD 2>/dev/null)" == "$SRC_FULL" ]] \
   230 |     || die "$WORKTREE exists but is not at $SRC_FULL; remove it with git worktree remove"
>  231 |   [[ -z "$(git -C "$WORKTREE" status --porcelain 2>/dev/null)" ]] \
>  232 |     || die "$WORKTREE has local changes; the pinned source must be pristine"
   233 | else
   234 |   git -C "$SOURCE_REPO" worktree add --detach "$WORKTREE" "$SRC_FULL" >/dev/null 2>&1 \
   235 |     || die "could not create the source worktree at $WORKTREE"
   236 | fi
   237 | 
   238 | # --- batch directory and lock --------------------------------------------------
   239 | mkdir -p "$BATCH_DIR"
   240 | LOCK="$BATCH_DIR/.lock"
   241 | mkdir "$LOCK" 2>/dev/null || die "batch $BATCH is locked ($LOCK): another run-arms is using it"
   242 | JOBS_DIR="$BATCH_DIR/.jobs"
   243 | mkdir -p "$JOBS_DIR"
   244 | cleanup() {
~~~~

The change from head to the fix:

~~~~diff
@@ -231,2 +259,4 @@
-  [[ -z "$(git -C "$WORKTREE" status --porcelain 2>/dev/null)" ]] \
-    || die "$WORKTREE has local changes; the pinned source must be pristine"
+  # audit r1 DISS-C-006: ignored files count too — an earlier run's .loa.config.yaml or
+  # .run/ in the worktree would be copied into every sandbox under one recorded commit
+  [[ -z "$(git -C "$WORKTREE" status --porcelain --ignored 2>/dev/null)" ]] \
+    || die "$WORKTREE has local or ignored files; the pinned source must be pristine (git -C $WORKTREE status --ignored)"
~~~~

## H13 — evals/harness/run-arms.sh — head lines 314–315

Head context (head/evals/harness/run-arms.sh, lines 302–327):

~~~~text
   302 |     && mv "$agg.tmp" "$agg"
   303 |   rmdir "$lockd" 2>/dev/null || true
   304 | }
   305 | set_state() { STATE="$1"; write_status; }
   306 | 
   307 | # --- one trial (runs in a background job; writes its row to $JOBS_DIR/<id>.row)
   308 | is_transport_failure() {  # is_transport_failure <sandbox-ws>
   309 |   local ws="$1" out="$1/.eval/agent-output.json" err="$1/.eval/agent-stderr.log" rc
   310 |   rc="$(jq -r '.exit_code // 0' "$ws/.eval/executor.json" 2>/dev/null || echo 0)"
   311 |   case "$rc" in 124|137|143) return 0 ;; esac
   312 |   [[ "$(jq -r '.subtype // ""' "$out" 2>/dev/null)" == "missing" ]] && return 0
   313 |   [[ -n "$(jq -r '.api_error_status // empty' "$out" 2>/dev/null)" ]] && return 0
>  314 |   grep -qiE 'rate.?limit|overloaded|session limit|usage limit|out of extra usage|ECONNRESET|ETIMEDOUT|network|socket hang up|5[0-9][0-9] ' \
>  315 |     "$err" "$out" 2>/dev/null && return 0
   316 |   return 1
   317 | }
   318 | 
   319 | run_trial() {  # run_trial <job-id> <arm> <fixture> <trial>
   320 |   local jid="$1" arm="$2" fx="$3" trial="$4"
   321 |   local task="$EVALS_DIR/tasks/$SUITE/$TASK_PREFIX-$fx.yaml" task_id="$TASK_PREFIX-$fx"
   322 |   local run_id="arms-$SUITE-$BATCH" attempt=0 ws="" trial_id status="error" err_json='null'
   323 |   local graders='[]' composite='{"strategy":"all_must_pass","pass":false,"score":0}' executor='null'
   324 |   local start_ms end_ms per_trial ex_rc
   325 |   per_trial="$(yq -r '.timeout.per_trial // 1500' "$task")"
   326 |   start_ms="$(date +%s%N | cut -c1-13)"
   327 |   if ! verify_corpus "$fx" >"$JOBS_DIR/$jid.digest" 2>"$JOBS_DIR/$jid.drift"; then
~~~~

The change from head to the fix:

~~~~diff
@@ -314,2 +344,5 @@
-  grep -qiE 'rate.?limit|overloaded|session limit|usage limit|out of extra usage|ECONNRESET|ETIMEDOUT|network|socket hang up|5[0-9][0-9] ' \
-    "$err" "$out" 2>/dev/null && return 0
+  # audit r1 DISS-C-005: classify on the CLI's stderr only, never on the agent's own
+  # output, so the agent under test cannot earn itself a retry by mentioning a network
+  # error; the patterns are the CLI's transport messages, not free text.
+  grep -qiE 'rate.?limit|overloaded|session limit|usage limit|out of extra usage|ECONNRESET|ETIMEDOUT|socket hang up|^(fetch|request) failed|HTTP 5[0-9][0-9]' \
+    "$err" 2>/dev/null && return 0
~~~~

## H14 — evals/harness/run-arms.sh — head line 336

Head context (head/evals/harness/run-arms.sh, lines 324–348):

~~~~text
   324 |   local start_ms end_ms per_trial ex_rc
   325 |   per_trial="$(yq -r '.timeout.per_trial // 1500' "$task")"
   326 |   start_ms="$(date +%s%N | cut -c1-13)"
   327 |   if ! verify_corpus "$fx" >"$JOBS_DIR/$jid.digest" 2>"$JOBS_DIR/$jid.drift"; then
   328 |     printf 'DRIFT\n' > "$JOBS_DIR/$jid.flag"; return 0
   329 |   fi
   330 |   while [[ $attempt -lt 2 ]]; do
   331 |     attempt=$((attempt + 1))
   332 |     trial_id="$run_id-$arm-$fx-t$trial-a$attempt-$jid"
   333 |     ws="$("$SCRIPT_DIR/sandbox.sh" create --fixture "review-prs/$fx" --run-id "$run_id" --trial-id "$trial_id" 2>/dev/null)" \
   334 |       || { err_json='{"type":"infrastructure_error","message":"sandbox creation failed"}'; break; }
   335 |     ex_rc=0
>  336 |     EVAL_PROMPT_TREE="$WORKTREE" EVAL_MODEL="$MODEL" LOA_EVAL_ARM="$arm" LOA_EVAL_SUITE_FILE="$SUITE_FILE" \
   337 |       LOA_EVAL_SOURCE_COMMIT="$SRC_FULL" LOA_AUDIT_REPLAY=1 \
   338 |       "$SCRIPT_DIR/execute-agent.sh" --task-yaml "$task" --workspace "$ws" \
   339 |         --run-id "$run_id" --trial-id "$trial_id" --timeout "$per_trial" \
   340 |         >/dev/null 2>"$JOBS_DIR/$jid.exec.log" || ex_rc=$?
   341 |     [[ -f "$ws/.eval/executor.json" ]] && executor="$(cat "$ws/.eval/executor.json")"
   342 |     if [[ $ex_rc -eq 0 ]]; then
   343 |       local gout gexit=0
   344 |       gout="$("$SCRIPT_DIR/grade.sh" --task-yaml "$task" --workspace "$ws" \
   345 |         --timeout "$(yq -r '.timeout.per_grader // 60' "$task")" 2>/dev/null)" || gexit=$?
   346 |       if jq -e . >/dev/null 2>&1 <<<"$gout"; then
   347 |         graders="$(jq -c '.graders' <<<"$gout")"; composite="$(jq -c '.composite' <<<"$gout")"
   348 |       fi
~~~~

The change from head to the fix:

~~~~diff
@@ -336 +369,4 @@
-    EVAL_PROMPT_TREE="$WORKTREE" EVAL_MODEL="$MODEL" LOA_EVAL_ARM="$arm" LOA_EVAL_SUITE_FILE="$SUITE_FILE" \
+    # audit r1 DISS-C-001: the arm's toggles come from the suite declaration only; a
+    # LOA_EVAL_ARM_TOGGLES inherited from the parent environment never reaches a trial
+    env -u LOA_EVAL_ARM_TOGGLES \
+      EVAL_PROMPT_TREE="$WORKTREE" EVAL_MODEL="$MODEL" LOA_EVAL_ARM="$arm" LOA_EVAL_SUITE_FILE="$SUITE_FILE" \
~~~~

## H15 — evals/harness/seed-corpus-from-record.sh — head lines 111–114

Head context (head/evals/harness/seed-corpus-from-record.sh, lines 99–126):

~~~~text
    99 |     return p.stdout.strip()
   100 | 
   101 | def show(r, path):
   102 |     p = subprocess.run(["git", "-C", REPO, "show", f"{r}:{path}"], capture_output=True)
   103 |     return p.stdout if p.returncode == 0 else None
   104 | 
   105 | CTRL = re.compile(r"[\x00-\x1f\x7f-\x9f
   106 | 
   107 | ]")
   108 | def clean(s, cap=160):
   109 |     s = CTRL.sub(" ", s)
   110 |     s = re.sub(r"\s+", " ", s).strip()
>  111 |     return s if len(s) <= cap else s[: cap - 1].rstrip() + "…"
>  112 | 
>  113 | SECRET_RX = [re.compile(p) for p in (
>  114 |     r"AKIA[0-9A-Z]{16}", r"sk-[a-zA-Z0-9]{20,}", r"ghp_[a-zA-Z0-9]{36}", r"gho_[a-zA-Z0-9]{36}",
   115 |     r"glpat-[a-zA-Z0-9\-]{20,}", r"xox[bpors]-[a-zA-Z0-9\-]+", r"sk-ant-[a-zA-Z0-9\-]{20,}",
   116 |     r"password\s*[:=]\s*[\"'][^\"']{8,}", r"secret\s*[:=]\s*[\"'][^\"']{8,}")]
   117 | def has_secret(s):
   118 |     return any(r.search(s) for r in SECRET_RX)
   119 | 
   120 | REDACTED = [0]
   121 | def redact(b, count=True):
   122 |     """Secret-shaped strings in verbatim copies of tracked files (fake test keys)
   123 |     become a fixed marker, identically in base/, head/ and head.diff; line
   124 |     numbers never move. Counted in the dropped report."""
   125 |     if b is None:
   126 |         return None
~~~~

The change from head to the fix:

~~~~diff
@@ -111,4 +111,12 @@
+# audit r1 DISS-C-007: shapes beyond the original nine (PEM blocks, JWTs, GitHub
+# fine-grained/app/user tokens, Google and Stripe keys, generic key/token assignments);
+# the generic patterns stay on ONE line so a redaction never joins lines.
 SECRET_RX = [re.compile(p) for p in (
     r"AKIA[0-9A-Z]{16}", r"sk-[a-zA-Z0-9]{20,}", r"ghp_[a-zA-Z0-9]{36}", r"gho_[a-zA-Z0-9]{36}",
+    r"github_pat_[A-Za-z0-9_]{20,}", r"gh[su]_[a-zA-Z0-9]{36}",
     r"glpat-[a-zA-Z0-9\-]{20,}", r"xox[bpors]-[a-zA-Z0-9\-]+", r"sk-ant-[a-zA-Z0-9\-]{20,}",
-    r"password\s*[:=]\s*[\"'][^\"']{8,}", r"secret\s*[:=]\s*[\"'][^\"']{8,}")]
+    r"AIza[0-9A-Za-z\-_]{35}", r"(?:sk|rk)_(?:live|test)_[0-9a-zA-Z]{20,}",
+    r"-----BEGIN [A-Z ]*PRIVATE KEY-----[^-]*-----END [A-Z ]*PRIVATE KEY-----",
+    r"eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}",
+    r"password[ \t]*[:=][ \t]*[\"'][^\"'\n]{8,}", r"secret[ \t]*[:=][ \t]*[\"'][^\"'\n]{8,}",
+    r"(?:api[_-]?key|access[_-]?token|auth[_-]?token)[ \t]*[:=][ \t]*[\"'][^\"'\n]{16,}")]
~~~~

## H16 — evals/harness/seed-corpus-from-record.sh — head line 307

Head context (head/evals/harness/seed-corpus-from-record.sh, lines 295–319):

~~~~text
   295 | fdir = os.path.join(CORPUS, fx)
   296 | fy = os.path.join(fdir, "fixture.yaml")
   297 | if os.path.isfile(fy) and "\nsprint:" not in "\n" + open(fy, encoding="utf-8").read():
   298 |     fail(f"{fx} exists and is not a record fixture; refusing to overwrite it")
   299 | for f in feedback:
   300 |     if "/" in f or f.startswith(".") or not f.endswith(".md"):
   301 |         fail(f"feedback file must be a bare .md name: {f}", 2)
   302 | base, head, fixc = rev(base_r), rev(head_r), rev(fix_r)
   303 | record_ref = args.record_ref
   304 | if subprocess.run(["git", "-C", REPO, "rev-parse", "--verify", "--quiet", record_ref], capture_output=True).returncode != 0:
   305 |     fail(f"record ref not found: {record_ref} (git fetch origin 'refs/heads/record/*:refs/remotes/origin/record/*')")
   306 | record_name = record_ref.split("origin/", 1)[-1]
>  307 | 
   308 | # --- scope -------------------------------------------------------------------
   309 | EXCL = re.compile(r"^(grimoires/|\.beads/|\.run/|evals/results/|CHANGELOG\.md$|\.claude/checksums\.json$|(.*/)?REPO-MAP\.md$|.*\.lock$|(.*/)?package-lock\.json$)")
   310 | binary = set()
   311 | for l in git("diff", "--numstat", "-M", base, head).splitlines():
   312 |     a, d, p = l.split("\t", 2)
   313 |     if a == "-" and d == "-":
   314 |         binary.add(p.split(" => ")[-1].strip("{}"))
   315 | changes = []  # (status, old, new)
   316 | for l in git("diff", "--name-status", "-M", base, head).splitlines():
   317 |     parts = l.split("\t")
   318 |     st = parts[0][0]
   319 |     if st in "RC":
~~~~

The change from head to the fix:

~~~~diff
@@ -307 +315,4 @@
-EXCL = re.compile(r"^(grimoires/|\.beads/|\.run/|evals/results/|CHANGELOG\.md$|\.claude/checksums\.json$|(.*/)?REPO-MAP\.md$|.*\.lock$|(.*/)?package-lock\.json$)")
+# audit r1 DISS-C-003 (defensive): a root CLAUDE.md copy inside a fixture would be an
+# instruction file Claude Code may load for the agent under test; the sandbox's own
+# CLAUDE.md points at the pinned prompt tree and is the only one allowed.
+EXCL = re.compile(r"^(grimoires/|\.beads/|\.run/|evals/results/|CLAUDE\.md$|CHANGELOG\.md$|\.claude/checksums\.json$|(.*/)?REPO-MAP\.md$|.*\.lock$|(.*/)?package-lock\.json$)")
~~~~

## H17 — evals/tests/arm-toggles.bats — head line 194

Head context (head/evals/tests/arm-toggles.bats, lines 182–200):

~~~~text
   182 |   run_arm no_such_arm "$REVIEW_SUITE" reviewing-code
   183 |   [ "$status" -eq 2 ]
   184 |   LOA_EVAL_ARM=x LOA_EVAL_ARM_TOGGLES='{"warp_drive":false}' run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
   185 |   [ "$status" -eq 2 ]
   186 |   LOA_EVAL_ARM=x LOA_EVAL_ARM_TOGGLES='[1]' run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
   187 |   [ "$status" -eq 2 ]
   188 |   LOA_EVAL_ARM='../x' run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
   189 |   [ "$status" -eq 2 ]
   190 |   [ ! -e "$SNAP" ]
   191 | }
   192 | 
   193 | @test "AT-11 explicit LOA_EVAL_ARM_TOGGLES and LOA_EVAL_SOURCE_COMMIT are honoured and recorded" {
>  194 |   LOA_EVAL_ARM=custom LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' LOA_EVAL_SOURCE_COMMIT=864069f2 \
   195 |     run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
   196 |   [ "$status" -eq 0 ]
   197 |   [ ! -e "$SNAP/.claude/rules/stash-safety.md" ]
   198 |   [ "$(jq -r '.arm' "$WS/.eval/executor.json")" = "custom" ]
   199 |   [ "$(jq -r '.source_commit' "$WS/.eval/executor.json")" = "864069f2" ]
   200 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -194 +194,2 @@
-  LOA_EVAL_ARM=custom LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' LOA_EVAL_SOURCE_COMMIT=864069f2 \
+  head_sha="$(git -C "$PT" rev-parse HEAD)"
+  LOA_EVAL_ARM=custom LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' LOA_EVAL_SOURCE_COMMIT="$head_sha" \
~~~~

## H18 — evals/tests/arm-toggles.bats — head line 199

Head context (head/evals/tests/arm-toggles.bats, lines 187–200):

~~~~text
   187 |   [ "$status" -eq 2 ]
   188 |   LOA_EVAL_ARM='../x' run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
   189 |   [ "$status" -eq 2 ]
   190 |   [ ! -e "$SNAP" ]
   191 | }
   192 | 
   193 | @test "AT-11 explicit LOA_EVAL_ARM_TOGGLES and LOA_EVAL_SOURCE_COMMIT are honoured and recorded" {
   194 |   LOA_EVAL_ARM=custom LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' LOA_EVAL_SOURCE_COMMIT=864069f2 \
   195 |     run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
   196 |   [ "$status" -eq 0 ]
   197 |   [ ! -e "$SNAP/.claude/rules/stash-safety.md" ]
   198 |   [ "$(jq -r '.arm' "$WS/.eval/executor.json")" = "custom" ]
>  199 |   [ "$(jq -r '.source_commit' "$WS/.eval/executor.json")" = "864069f2" ]
   200 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -199 +200,22 @@
-  [ "$(jq -r '.source_commit' "$WS/.eval/executor.json")" = "864069f2" ]
+  [ "$(jq -r '.source_commit' "$WS/.eval/executor.json")" = "$head_sha" ]
+}
+
+@test "AT-12 a source commit that is not the prompt tree's HEAD, a non-hex one, toggles outside arm mode and baseline toggles are refused or ignored (audit r1 DISS-C-001, DISS-C-009)" {
+  LOA_EVAL_ARM=custom LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' LOA_EVAL_SOURCE_COMMIT=864069f2 \
+    run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
+  [ "$status" -eq 2 ]
+  grep -q "not the prompt tree's HEAD" <<<"$output"
+  LOA_EVAL_ARM=custom LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' LOA_EVAL_SOURCE_COMMIT='not-a-sha' \
+    run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
+  [ "$status" -eq 2 ]
+  # baseline never carries toggles
+  LOA_EVAL_ARM=baseline LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' \
+    run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
+  [ "$status" -eq 2 ]
+  grep -q "baseline arm takes no toggles" <<<"$output"
+  # outside arm mode a stale LOA_EVAL_ARM_TOGGLES is ignored: the rule file stays
+  rm -rf "$WS"; mkdir -p "$WS"
+  LOA_EVAL_ARM_TOGGLES='{"rule_files":false}' run "$EXEC" --task-yaml "$T/task-reviewing-code.yaml" --workspace "$WS"
+  [ "$status" -eq 0 ]
+  grep -q "LOA_EVAL_ARM_TOGGLES is set but LOA_EVAL_ARM is not" <<<"$output"
+  [ -e "$SNAP/.claude/rules/stash-safety.md" ]
~~~~

## H19 — evals/tests/run-arms.bats — head line 52

Head context (head/evals/tests/run-arms.bats, lines 40–64):

~~~~text
    40 | @test "RA-1 --dry-run lists the interleaved plan and writes MANIFEST.json without a worktree or a CLI call" {
    41 |   export STUB_ARGV_FILE="$T/argv"
    42 |   run "$RA" --suite review-recall --arms baseline,no_rule_files --fixtures pr-01,pr-02 --trials 2 \
    43 |     --source-commit "$SHA" --results-dir "$RES" --dry-run
    44 |   [ "$status" -eq 0 ]
    45 |   grep -q 'planned trials: 8' <<<"$output"
    46 |   # trial-major, then fixture, then arm: arms alternate on consecutive lines
    47 |   [ "$(grep -E '^ +[0-9]+ ' <<<"$output" | awk '{print $2}' | head -4 | tr '\n' ,)" = "baseline,no_rule_files,baseline,no_rule_files," ]
    48 |   [ "$(grep -E '^ +[0-9]+ ' <<<"$output" | awk '{print $3}' | head -4 | tr '\n' ,)" = "pr-01,pr-01,pr-02,pr-02," ]
    49 |   M="$RES/review-recall/batch-pr-01-pr-02-n2/MANIFEST.json"
    50 |   [ -f "$M" ]
    51 |   [ "$(jq -r '.source_commit' "$M")" = "$SHA" ]
>   52 |   [ "$(jq -r '.model_id' "$M")" = "claude-fable-5-1" ]
    53 |   [ "$(jq -r '.dry_run' "$M")" = "true" ]
    54 |   [ "$(jq -r '.trials_planned' "$M")" = "8" ]
    55 |   [ "$(jq -r '.corpus.sha256 | length' "$M")" = "64" ]
    56 |   jq -e '.harness_commit and .executor.cli_version and .environment.os and .environment.yq' "$M" >/dev/null
    57 |   [ ! -e "$T/cache/arms-src-${SHA:0:12}" ]
    58 |   [ ! -e "$T/argv" ]
    59 | }
    60 | 
    61 | @test "RA-2 a stubbed batch completes: rows carry arm, trial, source_commit, model_id and seed; STATUS is complete; artifacts are kept" {
    62 |   run "$RA" --suite review-recall --arms baseline,no_rule_files --fixtures pr-01 --trials 1 \
    63 |     --source-commit "$SHA" --results-dir "$RES" --concurrency 2 --retry-wait 0
    64 |   [ "$status" -eq 0 ]
~~~~

The change from head to the fix:

~~~~diff
@@ -52 +52 @@
-  [ "$(jq -r '.model_id' "$M")" = "claude-fable-5-1" ]
+  [ "$(jq -r '.model_id' "$M")" = "global.anthropic.claude-opus-5-5" ]   # the DEC-0172 default
~~~~

## H20 — tests/unit/floor-snapshot.bats — head lines 44–50

Head context (head/tests/unit/floor-snapshot.bats, lines 32–51):

~~~~text
    32 |   done < <(yq -r '.floor_files[]' "$FLOOR")
    33 |   [ "$n" -ge 4 ]
    34 | }
    35 | 
    36 | @test "FS-2 the fence-corpus rows named in floor_corpus (FR-1.2b, FR-SZ*) are identical to origin/main" {
    37 |   corpus="$(yq -r '.floor_corpus.file' "$FLOOR")"
    38 |   rules="$(yq -o=json -I0 '.floor_corpus.rules' "$FLOOR")"
    39 |   sel='def m($r): $r | any(.[]; . as $p | if ($p | endswith("*")) then ($in.rule // "" | startswith($p | rtrimstr("*"))) else ($in.rule // "") == $p end);
    40 |        . as $in | select(m($rules))'
    41 |   diff <(base_show "$corpus" | jq -c --argjson rules "$rules" "$sel") <(jq -c --argjson rules "$rules" "$sel" "$ROOT/$corpus")
    42 | }
    43 | 
>   44 | @test "FS-3 the register disables nothing: settings.json hook registrations are identical to origin/main" {
>   45 |   diff <(base_show .claude/settings.json | jq -c '.hooks') <(jq -c '.hooks' "$ROOT/.claude/settings.json")
>   46 | }
>   47 | 
>   48 | @test "FS-4 the fence's pattern-id call-site list (in order) is identical to origin/main" {
>   49 |   ids() { grep -oE 'emit_block "[A-Za-z0-9._-]+"|pattern_id(: |=)"[A-Za-z0-9._-]+"'; }
>   50 |   diff <(base_show .claude/hooks/safety/block-destructive-bash.sh | ids) <(ids < "$ROOT/.claude/hooks/safety/block-destructive-bash.sh")
    51 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -44,7 +44,33 @@
-@test "FS-3 the register disables nothing: settings.json hook registrations are identical to origin/main" {
-  diff <(base_show .claude/settings.json | jq -c '.hooks') <(jq -c '.hooks' "$ROOT/.claude/settings.json")
+@test "FS-3 the register disables nothing: the registrations of the hooks that run floor guards are identical to origin/main" {
+  # audit r1: pin the FLOOR hooks' registrations (the fence host and the dissent artefact gate),
+  # not every registration — a later task may add a non-floor hook without touching the floor.
+  floor_regs() { jq -c '[.hooks | to_entries[] | .key as $e | .value[] | .matcher as $m | .hooks[] | select(.command | test("safety/(block-destructive-bash|adversarial-review-gate)\\.sh")) | {event: $e, matcher: $m, command}] | sort_by(.command, .event, .matcher)'; }
+  diff <(base_show .claude/settings.json | floor_regs) <(floor_regs < "$ROOT/.claude/settings.json")
+  [ "$(floor_regs < "$ROOT/.claude/settings.json" | jq 'length')" -ge 2 ]
 }
 
-@test "FS-4 the fence's pattern-id call-site list (in order) is identical to origin/main" {
-  ids() { grep -oE 'emit_block "[A-Za-z0-9._-]+"|pattern_id(: |=)"[A-Za-z0-9._-]+"'; }
-  diff <(base_show .claude/hooks/safety/block-destructive-bash.sh | ids) <(ids < "$ROOT/.claude/hooks/safety/block-destructive-bash.sh")
+@test "FS-4 every floor fence id (FR-1.2b, FR-SZ*, FR-SZ2*) keeps at least the call sites it has on origin/main" {
+  # audit r1: count the floor ids' sites rather than diffing the whole ordered list, so a
+  # non-floor fence change (FR-6 in Sprint 2) does not fail the floor proof.
+  ids() { grep -oE 'emit_block "[A-Za-z0-9._-]+"|pattern_id(: |=)"[A-Za-z0-9._-]+"' | grep -oE '"[A-Za-z0-9._-]+"' | tr -d '"'; }
+  while IFS= read -r id; do
+    [[ -n "$id" ]] || continue
+    case "$id" in fence:*) id="${id#fence:}" ;; *) continue ;; esac
+    before="$(base_show .claude/hooks/safety/block-destructive-bash.sh | ids | grep -cx -- "$id" || true)"
+    now="$(ids < "$ROOT/.claude/hooks/safety/block-destructive-bash.sh" | grep -cx -- "$id" || true)"
+    [ "$now" -ge "$before" ] || { echo "floor fence id $id has $now call site(s), origin/main has $before" >&2; return 1; }
+    [ "$before" -ge 1 ] || { echo "floor fence id $id has no call site on origin/main (floor.yaml names a non-existent guard)" >&2; return 1; }
+  done < <(yq -r '.floor_guards[]' "$FLOOR")
+}
+
+@test "FS-5 the live permission deny list (policy:permission-deny-list) is identical to origin/main" {
+  # review r1 DISS-C-003: floor_files pins the deny template, not the live rules
+  diff <(base_show .claude/settings.json | jq -c '.permissions.deny') <(jq -c '.permissions.deny' "$ROOT/.claude/settings.json")
+}
+
+@test "FS-6 every floor gate implemented as a hook is registered in settings.json" {
+  # review r1 DISS-C-003: a gate present on disk but unregistered never runs
+  while IFS= read -r s; do
+    [[ -n "$s" ]] || continue
+    grep -qF -- "$s" "$ROOT/.claude/settings.json" || { echo "floor gate script $s is not registered in settings.json" >&2; return 1; }
+  done < <(yq -r '.guards[] | select(.floor == true and .kind == "gate") | .script' "$ROOT/.claude/data/guard-origins.yaml" | grep '^\.claude/hooks/' | sed 's#^\.claude/##')
~~~~
