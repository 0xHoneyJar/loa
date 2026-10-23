# Hunks — pr-16

The later fix changed 18 region(s) in 9 of the change's 39 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — .claude/scripts/grimoire-index.sh — head lines 186–189

Head context (head/.claude/scripts/grimoire-index.sh, lines 174–201):

~~~~text
   174 | # status, summary (title slot), path <ledger>#<id>, refs = source, two empty slots,
   175 | # voice ninth (decided_by // proposed_by). yq is optional here: without Mike Farah
   176 | # yq v4, or on an unparsable ledger, the family is skipped with a stderr note.
   177 | emit_decisions(){
   178 |   local f="${G}/decisions.yaml" j v=""; [[ -f "$f" ]] || return 0
   179 |   command -v yq >/dev/null 2>&1 && v="$(yq --version 2>&1 || true)"
   180 |   if [[ "$v" != *mikefarah*"version v4."* ]]; then
   181 |     echo "grimoire-index: NOTE: decisions family skipped (needs Mike Farah yq v4)" >&2; return 0
   182 |   fi
   183 |   if ! j="$(yq -o=json -I0 '.decisions // []' "$f" 2>/dev/null)" || ! printf '%s' "$j" | jq -e 'type == "array"' >/dev/null 2>&1; then
   184 |     echo "grimoire-index: NOTE: decisions family skipped (grimoires/loa/decisions.yaml does not parse)" >&2; return 0
   185 |   fi
>  186 |   # Sanitised in jq (control characters, C1, U+2028/9 flattened; capped at 160 code points) so an
>  187 |   # empty cell never shifts the TAB columns.
>  188 |   printf '%s' "$j" | jq -r '
>  189 |     def s: tostring | gsub("[[:cntrl:]\u2028\u2029]"; " ") | gsub("  +"; " ") | sub("^ "; "") | sub(" $"; "") | .[0:160];
   190 |     .[] | objects | select(((.id // "") | s) != "")
   191 |     | ["decisions", (.id | s), ((.status // "") | s), ((.summary // "") | s), ("grimoires/loa/decisions.yaml#" + (.id | s)),
   192 |        ((.source // "") | s), "", "", ((.decided_by // .proposed_by // "") | s)] | join("\t")'
   193 | }
   194 | 
   195 | # emit_obs removed cycle-121 (observation store deleted)
   196 | 
   197 | collect(){ { emit_kf; emit_vision; emit_lore; emit_handoff; emit_notes; emit_decisions; } | LC_ALL=C sort -t$'\t' -k1,1 -k2,2; }
   198 | 
   199 | to_json(){
   200 |   collect | jq -R -s '
   201 |     [ split("\n")[] | select(length>0) | split("\t")
~~~~

The change from head to the fix:

~~~~diff
@@ -186,4 +186,6 @@
-  # Sanitised in jq (control characters, C1, U+2028/9 flattened; capped at 160 code points) so an
-  # empty cell never shifts the TAB columns.
+  # Rows are agent-authored and UNTRUSTED (as in loa-decisions-surface.sh): every field is cleaned in jq.
+  # C0/C1 controls (tab and newline included, so no cell shifts the TAB columns) and U+2028/9 become
+  # spaces, < and > become single guillemets, and each field is capped at 160 code points.
   printf '%s' "$j" | jq -r '
-    def s: tostring | gsub("[[:cntrl:]\u2028\u2029]"; " ") | gsub("  +"; " ") | sub("^ "; "") | sub(" $"; "") | .[0:160];
+    def s: tostring | gsub("[[:cntrl:]\u0080-\u009f\u2028\u2029]"; " ") | gsub("<"; "\u2039") | gsub(">"; "\u203a")
+           | gsub("  +"; " ") | sub("^ "; "") | sub(" $"; "") | .[0:160];
~~~~

## H02 — .claude/scripts/lib/dec-write-lib.sh — head lines 249–252

Head context (head/.claude/scripts/lib/dec-write-lib.sh, lines 237–264):

~~~~text
   237 |   n="$(san1 "$(o sprint)")"
   238 |   if [[ -z "$n" ]]; then
   239 |     for st in "${PROJECT_ROOT}/.run/sprint-plan-state.json" ${MAIN_ROOT:+"${MAIN_ROOT}/.run/sprint-plan-state.json"}; do
   240 |       [[ -f "$st" ]] || continue
   241 |       n="$(jq -r '(.sprints.current // "") as $c | ([.sprints.list[]? | select(.id == $c) | .global_id] | first) // $c // empty' "$st" 2>/dev/null || true)"
   242 |       [[ -n "$n" ]] && break
   243 |     done
   244 |   fi
   245 |   n="${n#sprint-}"
   246 |   if [[ ! "$n" =~ ^[A-Za-z0-9_.-]+$ ]]; then warn "no sprint number (pass --sprint N); writing the pending file under sprint-unknown"; n="unknown"; fi
   247 |   printf '%s' "${G}/a2a/sprint-${n}/decisions-pending.yaml"
   248 | }
>  249 | resolve_target(){ # mode: write|read
>  250 |   if has file; then
>  251 |     TARGET="$(o file)"; TARGET_KIND="fixture"
>  252 |     [[ -f "$TARGET" ]] || die "target not found: ${TARGET}"
   253 |     return 0
   254 |   fi
   255 |   if [[ "$1" == "write" ]] && { has pending || [[ $IS_WORKTREE -eq 1 ]]; }; then
   256 |     TARGET="$(pending_path)"; TARGET_KIND="pending"
   257 |   else
   258 |     TARGET="$LIVE"; TARGET_KIND="live"
   259 |   fi
   260 |   if [[ "$1" == "write" ]]; then
   261 |     local why; if why="$(ci_blocked)"; then die "refused: ${why} is set; the ledger is never written from CI or a hook (use --file <fixture> in tests)"; fi
   262 |     if [[ "$TARGET_KIND" == "pending" && ! -f "$TARGET" ]]; then
   263 |       mkdir -p "$(dirname "$TARGET")"
   264 |       cat > "$TARGET" <<'EOF_PEND'
~~~~

The change from head to the fix:

~~~~diff
@@ -249,4 +249,28 @@
+# Canonical path of a file whose directory exists (pwd -P of the directory + basename); empty otherwise.
+canon(){ local d; d="$(abs_dir "$(dirname "$1")")" || return 0; [[ -n "$d" ]] && printf '%s/%s' "$d" "$(basename "$1")"; return 0; }
+# Kind of an explicit --file target, by its resolved path: live (this checkout's or the main checkout's
+# ledger), pending (grimoires/loa/a2a/<dir>/decisions-pending.yaml under either root) or fixture.
+# The CI/hook exemption belongs to fixtures only, so naming the live ledger by path never bypasses it.
+file_kind(){
+  local c root r; c="$(canon "$1")"
+  [[ -n "$c" ]] || { echo fixture; return 0; }
+  for root in "$PROJECT_ROOT" ${MAIN_ROOT:+"$MAIN_ROOT"}; do
+    r="$(abs_dir "$root")"; [[ -n "$r" ]] || continue
+    if [[ "$c" == "$(canon "${r}/grimoires/loa/decisions.yaml")" ]]; then echo live; return 0; fi
+    case "$c" in "${r}/grimoires/loa/a2a/"*/decisions-pending.yaml)
+      local mid="${c#"${r}/grimoires/loa/a2a/"}"; mid="${mid%/decisions-pending.yaml}"
+      if [[ "$mid" != */* ]]; then echo pending; return 0; fi ;;
+    esac
+  done
+  echo fixture
+}
 resolve_target(){ # mode: write|read
   if has file; then
-    TARGET="$(o file)"; TARGET_KIND="fixture"
+    TARGET="$(o file)"; TARGET_KIND="$(file_kind "$TARGET")"
     [[ -f "$TARGET" ]] || die "target not found: ${TARGET}"
+    if [[ "$1" == "write" && "$TARGET_KIND" != "fixture" ]]; then
+      local why; if why="$(ci_blocked)"; then die "refused: ${why} is set; --file ${TARGET} is the ${TARGET_KIND} ledger, which is never written from CI or a hook"; fi
+      if [[ "$TARGET_KIND" == "live" && $IS_WORKTREE -eq 1 ]]; then
+        die "refused: --file ${TARGET} is a live ledger and this is a linked worktree; worktrees write the pending file (drop --file), the lead imports it"
+      fi
+    fi
~~~~

## H03 — .claude/scripts/lib/dec-write-lib.sh — insertion after head line 626

Head context (head/.claude/scripts/lib/dec-write-lib.sh, lines 615–638):

~~~~text
   615 |   echo "$nid"
   616 | }
   617 | 
   618 | op_import(){
   619 |   preflight
   620 |   local from; from="$(o from)"; [[ -n "$from" ]] || usage "import --from <pending file> required"
   621 |   [[ -f "$from" ]] || die "import: pending file not found: $from"
   622 |   if has file; then resolve_target write; else
   623 |     [[ $IS_WORKTREE -eq 0 ]] || die "import runs in the main checkout (this is a linked worktree)"
   624 |     local why; if why="$(ci_blocked)"; then die "refused: ${why} is set"; fi
   625 |     TARGET="$LIVE"; TARGET_KIND="live"; [[ -f "$TARGET" ]] || die "ledger not found: $TARGET"
   626 |   fi
   627 |   local pv; pv="$(PROJECT_ROOT="$PROJECT_ROOT" bash "$VALIDATOR" --type decisions --file "$from" 2>&1)" || die "import: the pending file fails validation:"$'\n'"$pv"
   628 |   acquire_lock "$TARGET"
   629 |   local old pend n; old="$(read_ledger "$TARGET")"; pend="$(read_ledger "$from")"
   630 |   n="$(printf '%s' "$pend" | jq '.decisions | length')"
   631 |   [[ "$n" -gt 0 ]] || die "import: no rows in $from"
   632 |   # Allocate ids in file order, then rewrite every PEND reference inside the imported rows.
   633 |   local map="{}" pid i next cur="$old"
   634 |   for (( i = 0; i < n; i++ )); do
   635 |     pid="$(printf '%s' "$pend" | jq -r --argjson i "$i" '.decisions[$i].id')"
   636 |     [[ "$pid" =~ ^PEND-[0-9a-f]{8}$ ]] || die "import: row $i has id $pid, not PEND-<8 hex>"
   637 |     next="$(next_dec_id "$cur")"
   638 |     map="$(jq -cn --argjson m "$map" --arg p "$pid" --arg d "$next" '$m + {($p): $d}')"
~~~~

The change from head to the fix:

~~~~diff
@@ -626,0 +651,9 @@
+  # --rewrite targets are checked before anything is written: an existing regular file (not a symlink)
+  # whose canonical path lies under PROJECT_ROOT, named without '..'.
+  local rw rwc proot; proot="$(abs_dir "$PROJECT_ROOT")"
+  while IFS= read -r -d '' rw; do
+    [[ "$rw" != *".."* ]] || die "import: --rewrite path may not contain '..': $rw"
+    [[ -f "$rw" && ! -L "$rw" ]] || die "import: --rewrite target is not an existing regular file: $rw"
+    rwc="$(canon "$rw")"
+    case "$rwc" in "${proot}/"*) ;; *) die "import: --rewrite target is outside the project (${proot}): $rw" ;; esac
+  done < <(om rewrite)
~~~~

## H04 — .claude/skills/discovering-requirements/resources/REFERENCE.md — head line 60

Head context (head/.claude/skills/discovering-requirements/resources/REFERENCE.md, lines 48–72):

~~~~text
    48 | 
    49 | ## Interview Modes
    50 | 
    51 | The skill resolves `interview_mode` (`interview.mode`, overridden per skill by `interview.per_skill.<skill>`), `pacing` and the input styles in its Config Reading block. These tables say what each value does.
    52 | 
    53 | ### Mode Behavior Table
    54 | 
    55 | | Mode | Questions/Phase | Default pacing | Phase Gates | Gap Skipping |
    56 | |---|---|---|---|---|
    57 | | `thorough` | 3-6 (scales down with context) | `rounds` | All ON | Always ask `min_confirm` |
    58 | | `minimal` | 1-2 | `batch` | `before_generation` only | Skip covered phases |
    59 | 
>   60 | An explicit `interview.pacing` wins over the mode default, so a config that sets `sequential` keeps it.
    61 | 
    62 | ### Input Style Resolution
    63 | 
    64 | | Interaction Type | `structured` | `plain` |
    65 | |---|---|---|
    66 | | Routing gates | AskUserQuestion with options | "Continue, go back, or skip ahead?" |
    67 | | Discovery questions | AskUserQuestion with suggested answers | Markdown question, user responds freely |
    68 | | Confirmations | AskUserQuestion (Yes/Correct/Adjust) | "Is this accurate? [yes/corrections]" |
    69 | 
    70 | In `rounds` pacing, a round is one message even when `discovery_questions` is `structured`: present the numbered round as markdown and take the reply as text, because a round can hold more questions than one AskUserQuestion call allows.
    71 | 
    72 | ## Question Pacing
~~~~

The change from head to the fix:

~~~~diff
@@ -60 +60 @@
-An explicit `interview.pacing` wins over the mode default, so a config that sets `sequential` keeps it.
+`interview.pacing` is unset by default (the shipped `.loa.config.yaml.example` leaves it commented), so the mode default above applies. An explicit value wins over the mode default for every mode, so a config that sets `sequential` keeps it.
~~~~

## H05 — .loa.config.yaml.example — head line 100

Head context (head/.loa.config.yaml.example, lines 88–112):

~~~~text
    88 | # -----------------------------------------------------------------------------
    89 | plan_and_analyze:
    90 |   codebase_grounding:
    91 |     enabled: true
    92 |     reality_staleness_days: 7
    93 |     ride_timeout_minutes: 20
    94 |     skip_on_ride_error: false
    95 | 
    96 | # -----------------------------------------------------------------------------
    97 | # Interview Depth Configuration (v1.41.0)
    98 | # -----------------------------------------------------------------------------
    99 | # Controls question depth, input style, and pacing across planning skills.
>  100 | # Default: thorough mode with rounds of plain-text discovery questions.
   101 | #
   102 | # Construct override: Schema supports future construct manifest interview
   103 | # overrides gated by trust tier (RFC #379). Not wired yet.
   104 | interview:
   105 |   # Mode: thorough | minimal
   106 |   #   thorough: 3-6 questions/phase, mandatory phase gates, no inference
   107 |   #   minimal: 1-2 questions/phase, skip covered phases, faster throughput
   108 |   mode: thorough
   109 | 
   110 |   # Per-skill overrides (optional — mode applies to all if omitted)
   111 |   # per_skill:
   112 |   #   discovering-requirements: thorough
~~~~

The change from head to the fix:

~~~~diff
@@ -100 +100 @@
-# Default: thorough mode with rounds of plain-text discovery questions.
+# Default: thorough mode; pacing unset, so rounds of plain-text discovery questions.
~~~~

## H06 — .loa.config.yaml.example — head line 127

Head context (head/.loa.config.yaml.example, lines 115–139):

~~~~text
   115 | 
   116 |   # Input style — per interaction type
   117 |   input_style:
   118 |     # routing_gates: AskUserQuestion for phase transitions (Continue/Adjust/Stop)
   119 |     routing_gates: structured    # structured | plain
   120 |     # discovery_questions: plain text for domain exploration
   121 |     discovery_questions: plain   # structured | plain
   122 |     # confirmation: AskUserQuestion for understanding checks
   123 |     confirmation: structured     # structured | plain
   124 | 
   125 |   # Question pacing. One key for the discovery interview, /architect Phase 2,
   126 |   # /sprint-plan Phase 2 and /chart; per_skill above still picks the mode.
>  127 |   # Unset: rounds for thorough, batch for minimal. An explicit value always wins.
   128 |   #   rounds: each turn asks the whole frontier, every open question whose
   129 |   #     prerequisites are settled; a question that depends on another one still
   130 |   #     open waits for a later round. Questions are numbered across the session
   131 |   #     (Q1, Q2, ...), each with a recommended answer. "yes" accepts every
   132 |   #     recommendation in the round; a numbered answer overrides that question;
   133 |   #     unanswered numbers are restated and take the recommendation only after
   134 |   #     you confirm. The frontier is recomputed after each round. Each round ends
   135 |   #     with a <!-- round: N; questions: [...] --> block that
   136 |   #     tools/check-round-independence.sh checks.
   137 |   #   sequential: one question per turn, wait for the answer (the supported
   138 |   #     opt-out if you prefer one question at a time)
   139 |   #   batch: 3-6 numbered questions per turn, user responds freely
~~~~

The change from head to the fix:

~~~~diff
@@ -127 +127,2 @@
-  # Unset: rounds for thorough, batch for minimal. An explicit value always wins.
+  # Left unset (the shipped default), it is rounds for thorough and batch for
+  # minimal; uncomment and set a value to pin it for every mode.
~~~~

## H07 — .loa.config.yaml.example — head line 140

Head context (head/.loa.config.yaml.example, lines 128–152):

~~~~text
   128 |   #   rounds: each turn asks the whole frontier, every open question whose
   129 |   #     prerequisites are settled; a question that depends on another one still
   130 |   #     open waits for a later round. Questions are numbered across the session
   131 |   #     (Q1, Q2, ...), each with a recommended answer. "yes" accepts every
   132 |   #     recommendation in the round; a numbered answer overrides that question;
   133 |   #     unanswered numbers are restated and take the recommendation only after
   134 |   #     you confirm. The frontier is recomputed after each round. Each round ends
   135 |   #     with a <!-- round: N; questions: [...] --> block that
   136 |   #     tools/check-round-independence.sh checks.
   137 |   #   sequential: one question per turn, wait for the answer (the supported
   138 |   #     opt-out if you prefer one question at a time)
   139 |   #   batch: 3-6 numbered questions per turn, user responds freely
>  140 |   pacing: rounds   # sequential | batch | rounds
   141 | 
   142 |   # Phase transition gates
   143 |   phase_gates:
   144 |     between_phases: true       # Require confirmation between discovery phases
   145 |     before_generation: true    # Require confirmation before generating output doc
   146 | 
   147 |   # Backpressure controls (anti-rushing for capable models)
   148 |   backpressure:
   149 |     no_infer: true             # Prohibit inferring answers to unasked questions
   150 |     show_work: true            # Cite known vs unknown before asking
   151 |     min_confirmation_questions: 1  # Min questions even for "covered" phases
   152 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -140 +141 @@
-  pacing: rounds   # sequential | batch | rounds
+  # pacing: rounds   # sequential | batch | rounds; unset = rounds for thorough, batch for minimal
~~~~

## H08 — tests/unit/check-round-independence.bats — insertion after head line 137

Head context (head/tests/unit/check-round-independence.bats, lines 126–149):

~~~~text
   126 |     [[ "$output" == *"round 1 does not follow round 2"* ]]
   127 | }
   128 | 
   129 | @test "RI-11 a malformed questions array is a violation, not a crash" {
   130 |     printf '%s\n' '<!-- round: 1; questions: [{"id":"Q1"},{"id":"Q2","depends_on":"Q1"}] -->' \
   131 |                   '<!-- round: 2; questions: [not json] -->' > "$T"
   132 |     run "$CHECK" "$T"
   133 |     [ "$status" -eq 1 ]
   134 |     [[ "$output" == *"round 1: malformed questions array"* ]]
   135 |     [[ "$output" == *"round 2: malformed questions array"* ]]
   136 | }
   137 | 
   138 | @test "RI-12 no round block exits 2; usage errors exit 2" {
   139 |     printf 'an interview with no round blocks\n' > "$T"
   140 |     run "$CHECK" "$T"
   141 |     [ "$status" -eq 2 ]
   142 |     [[ "$output" == *"no <!-- round: N; questions: [...] --> block"* ]]
   143 |     run "$CHECK"
   144 |     [ "$status" -eq 2 ]
   145 |     run "$CHECK" "$BATS_TEST_TMPDIR/missing.md"
   146 |     [ "$status" -eq 2 ]
   147 |     run "$CHECK" "$FIX/independent.md" --min-average two
   148 |     [ "$status" -eq 2 ]
   149 |     run "$CHECK" "$FIX/independent.md" --bogus
~~~~

The change from head to the fix:

~~~~diff
@@ -137,0 +138,58 @@
+@test "RI-11b two JSON values in one block are a malformed violation (exit 1), not a usage error" {
+    printf '%s\n' '<!-- round: 1; questions: [] [{"id":"Q1","depends_on":[]}] -->' \
+                  '<!-- round: 2; questions: [{"id":"Q2","depends_on":[]},{"id":"Q3","depends_on":[]}] -->' > "$T"
+    run "$CHECK" "$T"
+    [ "$status" -eq 1 ]
+    [[ "$output" == *"round 1: malformed questions array"* ]]
+}
+
+@test "RI-11c ids carrying escapes are malformed (exit 1) and no ESC byte reaches the output" {
+    run "$CHECK" "$FIX/escape-id.md"
+    [ "$status" -eq 1 ]
+    [[ "$output" == *"round 1: malformed questions array"* ]]
+    [[ "$output" == *"round 2: malformed questions array"* ]]
+    [[ "$output" != *$'\e'* ]]
+    run "$CHECK" "$FIX/escape-id.md" --json
+    [ "$status" -eq 1 ]
+    [[ "$output" != *$'\e'* ]]
+}
+
+@test "RI-11d an id outside [A-Za-z0-9_.-]{1,64} is malformed" {
+    transcript '[{"id":"Q 1","depends_on":[]},{"id":"Q2","depends_on":[]}]'
+    run "$CHECK" "$T"
+    [ "$status" -eq 1 ]
+    [[ "$output" == *"round 1: malformed questions array"* ]]
+    local long; long="$(printf 'Q%.0s' $(seq 1 65))"
+    transcript "[{\"id\":\"$long\",\"depends_on\":[]},{\"id\":\"Q2\",\"depends_on\":[]}]"
+    run "$CHECK" "$T"
+    [ "$status" -eq 1 ]
+    [[ "$output" == *"round 1: malformed questions array"* ]]
+}
+
+@test "RI-11e a 200 KiB block is a malformed violation with a clear message, not a jq crash" {
+    {
+        printf '<!-- round: 1; questions: [{"id":"Q1","depends_on":[]},{"id":"Q2","depends_on":[]}'
+        local i; for i in $(seq 1 2300); do printf ',{"id":"P%04d","depends_on":[],"note":"%080d"}' "$i" 0; done
+        printf '] -->\n'
+        printf '%s\n' '<!-- round: 2; questions: [{"id":"Q3","depends_on":[]},{"id":"Q4","depends_on":[]}] -->'
+    } > "$T"
+    [ "$(wc -c < "$T")" -gt 204800 ]
+    run "$CHECK" "$T"
+    [ "$status" -eq 1 ]
+    [[ "$output" == *"round 1: malformed questions array (block is "*"over the 65536-byte limit)"* ]]
+}
+
+@test "RI-11f a transcript whose rounds total more than 128 KiB is checked, not crashed" {
+    local i pad; pad="$(printf 'x%.0s' $(seq 1 60))"
+    : > "$T"
+    for i in $(seq 1 900); do
+        printf '<!-- round: %d; questions: [{"id":"A%s%04d","depends_on":[]},{"id":"B%s%04d","depends_on":[]}] -->\n' \
+            "$i" "${pad:0:58}" "$i" "${pad:0:58}" "$i" >> "$T"
+    done
+    [ "$(wc -c < "$T")" -gt 131072 ]
+    run "$CHECK" "$T" --json
+    [ "$status" -eq 0 ]
+    [ "$(jq -r '.rounds' <<< "$output")" -eq 900 ]
+    [ "$(jq -r '.questions' <<< "$output")" -eq 1800 ]
+}
+
~~~~

## H09 — tests/unit/dec-write-lib.bats — insertion after head line 381

Head context (head/tests/unit/dec-write-lib.bats, lines 370–393):

~~~~text
   370 | @test "dec-write: CI, GITHUB_ACTIONS and LOA_HOOK_CONTEXT=1 make a live-ledger write exit 1; --file fixtures still run" {
   371 |   cp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
   372 |   local v
   373 |   for v in CI=1 GITHUB_ACTIONS=true LOA_HOOK_CONTEXT=1; do
   374 |     run env "$v" bash "$D" new --summary s --phase discovery --category scope --recorded-by x --source s
   375 |     [ "$status" -eq 1 ]; [[ "$output" == *"never written from CI or a hook"* ]]
   376 |   done
   377 |   cmp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
   378 |   run env CI=1 bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s --quiet
   379 |   [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
   380 | }
   381 | 
   382 | @test "dec-write: the live ledger in the main checkout gets DEC ids; --pending writes the sprint pending file" {
   383 |   run bash "$D" new --summary s --phase discovery --category scope --recorded-by x --source s --quiet
   384 |   [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
   385 |   run bash "$D" new --pending --sprint 252 --summary s --phase discovery --category scope --recorded-by x --source s --quiet
   386 |   [ "$status" -eq 0 ]; [[ "$output" =~ ^PEND-[0-9a-f]{8}$ ]]
   387 |   [ "$(yq '.decisions[0].id' "$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml")" = "$output" ]
   388 |   [ "$(yq '.decisions | length' "$L")" -eq 1 ]
   389 | }
   390 | 
   391 | @test "dec-write: a linked worktree writes PEND rows to the pending file; import in the main checkout allocates ids, rewrites refs and deletes the file" {
   392 |   git -C "$T" add -A
   393 |   git -C "$T" -c core.hooksPath=/dev/null -c user.email=t@t -c user.name=t commit -qm fixture
~~~~

The change from head to the fix:

~~~~diff
@@ -381,0 +382,40 @@
+@test "dec-write: under CI, GITHUB_ACTIONS or LOA_HOOK_CONTEXT, --file naming the live ledger or a pending file (relative or absolute) is refused; a temp fixture is allowed" {
+  mkdir -p "$T/grimoires/loa/a2a/sprint-252"
+  empty_ledger "$REPO/grimoires/loa/decisions.yaml" "$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml"
+  cp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
+  local v tgt
+  for v in CI=1 GITHUB_ACTIONS=1 LOA_HOOK_CONTEXT=1; do
+    for tgt in "$L" "grimoires/loa/decisions.yaml" "./grimoires/loa/../loa/decisions.yaml" "$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml" "grimoires/loa/a2a/sprint-252/decisions-pending.yaml"; do
+      run bash -c 'cd "$1" && shift && env "$@"' _ "$T" "$v" bash "$D" new --file "$tgt" --summary s --phase discovery --category scope --recorded-by x --source s
+      [ "$status" -eq 1 ] || { echo "$v --file $tgt: status $status: $output"; return 1; }
+      [[ "$output" == *"never written from CI or a hook"* ]]
+    done
+    run env "$v" bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s --quiet
+    [ "$status" -eq 0 ]
+  done
+  cmp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
+  [ "$(yq '.decisions | length' "$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml")" -eq 0 ]
+  # import into the live ledger by --file is refused under CI too, and leaves the pending file in place
+  run env -u CI bash "$D" new --pending --sprint 252 --summary p --phase discovery --category scope --recorded-by x --source s --quiet
+  [ "$status" -eq 0 ]
+  local P="$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml"
+  run env CI=1 bash "$D" import --from "$P" --file "$L"
+  [ "$status" -eq 1 ]; [[ "$output" == *"never written from CI or a hook"* ]]
+  [ -f "$P" ]; cmp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
+  # without CI, --file naming the live ledger is the live kind (DEC ids, normal verify)
+  run bash -c 'cd "$1" && bash "$2" new --file grimoires/loa/decisions.yaml --summary s --phase discovery --category scope --recorded-by x --source s --quiet' _ "$T" "$D"
+  [ "$status" -eq 0 ]; [ "$output" = "DEC-0001" ]
+}
+
+@test "dec-write: in a linked worktree, --file naming a live ledger is refused (worktrees write the pending file)" {
+  git -C "$T" add -A
+  git -C "$T" -c core.hooksPath=/dev/null -c user.email=t@t -c user.name=t commit -qm fixture
+  git -C "$T" worktree add -q "$T/wt" -b wt-file
+  local WD="$T/wt/.claude/scripts/lib/dec-write-lib.sh"
+  run bash "$WD" new --file "$T/wt/grimoires/loa/decisions.yaml" --summary s --phase discovery --category scope --recorded-by x --source s
+  [ "$status" -eq 1 ]; [[ "$output" == *"linked worktree"* ]]
+  run bash "$WD" new --file "$T/grimoires/loa/decisions.yaml" --summary s --phase discovery --category scope --recorded-by x --source s
+  [ "$status" -eq 1 ]; [[ "$output" == *"linked worktree"* ]]
+  [ "$(yq '.decisions | length' "$L")" -eq 0 ]
+}
+
~~~~

## H10 — tests/unit/dec-write-lib.bats — insertion after head line 417

Head context (head/tests/unit/dec-write-lib.bats, lines 406–429):

~~~~text
   406 |   printf 'NOTES: see %s and %s\n' "$p1" "$p2" > "$T/notes.md"
   407 |   run bash "$D" import --from "$P" --rewrite "$T/notes.md"
   408 |   [ "$status" -eq 0 ]
   409 |   [[ "$output" == *"$p1 DEC-0002"* && "$output" == *"$p2 DEC-0003"* ]]
   410 |   [ ! -f "$P" ]
   411 |   [ "$(ids "$L")" = "DEC-0001,DEC-0002,DEC-0003" ]
   412 |   [ "$(field "$L" DEC-0003 .summary)" = "refers to DEC-0002" ]
   413 |   [ "$(cat "$T/notes.md")" = "NOTES: see DEC-0002 and DEC-0003" ]
   414 |   run bash "$T/.claude/scripts/validate-artifact.sh" --type decisions --file "$L"
   415 |   [ "$status" -eq 0 ]
   416 | }
   417 | 
   418 | # ---- lock --------------------------------------------------------------------------
   419 | 
   420 | @test "dec-write: a held flock makes a second writer exit 1 and leaves the file intact" {
   421 |   command -v flock >/dev/null 2>&1 || skip "flock not installed"
   422 |   mkdir -p "$T/.run"; local lp; lp="$(lockpath "$F")"
   423 |   ( exec 9>"$lp"; flock 9; sleep 6 ) &
   424 |   local holder=$!
   425 |   sleep 0.5
   426 |   cp "$F" "$BATS_TEST_TMPDIR/before.yaml"
   427 |   run env LOA_DEC_LOCK_WAIT=1 bash "$D" new --file "$F" --summary s --phase discovery --category scope --recorded-by x --source s
   428 |   kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
   429 |   [ "$status" -eq 1 ]; [[ "$output" == *"lock busy"* ]]
~~~~

The change from head to the fix:

~~~~diff
@@ -417,0 +458,21 @@
+@test "dec-write import: --rewrite targets outside the project, with '..', symlinks or missing files are refused before any write" {
+  run bash "$D" new --pending --sprint 252 --summary p --phase discovery --category scope --recorded-by x --source s --quiet
+  [ "$status" -eq 0 ]; local pid="$output"
+  local P="$T/grimoires/loa/a2a/sprint-252/decisions-pending.yaml"
+  printf 'see %s\n' "$pid" > "$BATS_TEST_TMPDIR/outside.md"
+  printf 'see %s\n' "$pid" > "$T/inside.md"
+  ln -s "$BATS_TEST_TMPDIR/outside.md" "$T/link.md"
+  cp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"
+  local bad
+  for bad in "$BATS_TEST_TMPDIR/outside.md" "$T/grimoires/../inside.md" "$T/link.md" "$T/missing.md"; do
+    run bash "$D" import --from "$P" --rewrite "$bad"
+    [ "$status" -eq 1 ] || { echo "--rewrite $bad: status $status: $output"; return 1; }
+    [[ "$output" == *"--rewrite"* ]]
+  done
+  cmp "$L" "$BATS_TEST_TMPDIR/live-before.yaml"; [ -f "$P" ]
+  [ "$(cat "$BATS_TEST_TMPDIR/outside.md")" = "see $pid" ]
+  run bash "$D" import --from "$P" --rewrite "$T/inside.md"
+  [ "$status" -eq 0 ]
+  [ "$(cat "$T/inside.md")" = "see DEC-0001" ]
+}
+
~~~~

## H11 — tests/unit/grimoire-index.bats — insertion after head line 140

Head context (head/tests/unit/grimoire-index.bats, lines 129–140):

~~~~text
   129 | @test "decision ledger readers: loa-learnings-index.sh and path-lib.sh get_decisions_path resolve the tracked ledger (two-row fixture)" {
   130 |   _need_yq4
   131 |   local dir="$BATS_TEST_TMPDIR/dproj"; _decisions_project "$dir"
   132 |   cp "$PROJECT_ROOT/.claude/scripts/loa-learnings-index.sh" "$PROJECT_ROOT/.claude/scripts/path-lib.sh" "$PROJECT_ROOT/.claude/scripts/bash-version-guard.sh" "$dir/.claude/scripts/"
   133 |   run env LOA_INDEX_DIR="$dir/idx" bash "$dir/.claude/scripts/loa-learnings-index.sh" index --skip-integrity
   134 |   [ "$status" -eq 0 ]
   135 |   jq -e 'length == 2 and (map(.id) == ["DEC-0001","DEC-0002"]) and all(.[]; .type == "decision" and .source_file == "grimoires/loa/decisions.yaml")' "$dir/idx/decisions.idx" >/dev/null
   136 |   run bash -c 'cd "$1" && PROJECT_ROOT="$1" && source .claude/scripts/path-lib.sh && get_decisions_path' _ "$dir"
   137 |   [ "$status" -eq 0 ]
   138 |   [ "$output" = "$dir/grimoires/loa/decisions.yaml" ]
   139 |   [ -f "$output" ]
   140 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -140,0 +141,28 @@
+
+@test "grimoire-index decisions: untrusted row text is cleaned in TSV, JSON and md (tab, newline, ESC, C1, <script>)" {
+  _need_yq4
+  local dir="$BATS_TEST_TMPDIR/dproj"; _decisions_project "$dir"
+  # a hand-edited row (the index reads whatever the file holds) with a real TAB, LF, ESC and C1 NEL
+  SUM="$(printf 'a\tb\nc\033[31md\302\205e <script>alert(1)</script>')" SRC="$(printf 's\t<x>\ny')" \
+    yq -i '.decisions[0].summary = strenv(SUM) | .decisions[0].source = strenv(SRC)' "$dir/grimoires/loa/decisions.yaml"
+  # the fixture really holds the hostile bytes
+  yq -o=json '.decisions[0].summary' "$dir/grimoires/loa/decisions.yaml" | jq -e 'test("\t") and test("\n") and test("\u001b") and test("\u0085") and test("<script>")' >/dev/null
+  local tsv json md row out lq rq
+  lq="$(printf '\342\200\271')"; rq="$(printf '\342\200\272')"   # the single guillemets < and > become
+  tsv="$(bash "$dir/.claude/scripts/grimoire-index.sh" --tsv | grep '^decisions' | head -1)"
+  [ "$(printf '%s' "$tsv" | awk -F'\t' '{print NF}')" -eq 9 ]
+  [ "$(printf '%s' "$tsv" | cut -f4)" = "a b c [31md e ${lq}script${rq}alert(1)${lq}/script${rq}" ]
+  [ "$(printf '%s' "$tsv" | cut -f6)" = "s ${lq}x${rq} y" ]
+  json="$(bash "$dir/.claude/scripts/grimoire-index.sh" --json)"
+  [ "$(echo "$json" | jq -r '.families.decisions[0].title')" = "a b c [31md e ${lq}script${rq}alert(1)${lq}/script${rq}" ]
+  bash "$dir/.claude/scripts/grimoire-index.sh" --quiet
+  md="$(cat "$dir/grimoires/loa/INDEX.md")"
+  row="$(printf '%s\n' "$md" | grep '^| DEC-0001 ')"
+  [ "$row" = "| DEC-0001 | open | agent | a b c [31md e ${lq}script${rq}alert(1)${lq}/script${rq} | s ${lq}x${rq} y |" ]
+  for out in "$tsv" "$json" "$md"; do
+    [[ "$out" != *"<script>"* && "$out" != *"<x>"* ]]
+    run bash -c 'printf "%s" "$1" | tr -d "\t\n" | LC_ALL=C grep -c "[[:cntrl:]]"' _ "$out"
+    [ "$output" = "0" ]
+    [[ "$out" != *$'\xc2\x85'* ]]
+  done
+}
~~~~

## H12 — tests/unit/user-invoked-commands.bats — head lines 61–69

Head context (head/tests/unit/user-invoked-commands.bats, lines 49–81):

~~~~text
    49 | # check_flagged_listed <root>: prints each flagged command file not in the list
    50 | check_flagged_listed() {
    51 |     local root="$1" f name names
    52 |     names="$(list_names "$root")"
    53 |     for f in "$root"/.claude/commands/*.md; do
    54 |         [[ -f "$f" ]] || continue
    55 |         has_flag "$f" || continue
    56 |         name="$(basename "$f" .md)"
    57 |         grep -qxF "$name" <<<"$names" || echo "unlisted: $name"
    58 |     done
    59 | }
    60 | 
>   61 | # check_operative <root>: prints file:line for each operative reference to a
>   62 | # listed name in a body other than that command's own file
>   63 | check_operative() {
>   64 |     local root="$1" name re exempt
>   65 |     exempt='(^|[^[:alpha:]])(user|operator|human|manually|suggest|recommend|tell|ask)'
>   66 |     while IFS= read -r name; do
>   67 |         # SDD D-8.3 pattern, widened: verbs match in any case and may take
>   68 |         # "the" ("execute /x", "Invoke the /x skill").
>   69 |         re="([Ee][Xx][Ee][Cc][Uu][Tt][Ee]|[Ii][Nn][Vv][Oo][Kk][Ee]|[Rr][Uu][Nn]|[Cc][Aa][Ll][Ll])[[:space:]]+(the[[:space:]]+)?\`?/${name}([^[:alnum:]_-]|\$)|Skill\\(.*${name}"
    70 |         { find "$root/.claude/commands" -name '*.md' -type f 2>/dev/null
    71 |           find "$root/.claude/skills" -name '*.md' -type f 2>/dev/null; } |
    72 |         while IFS= read -r f; do
    73 |             [[ "$f" == "$root/.claude/commands/$name.md" ]] && continue
    74 |             grep -nE "$re" "$f" 2>/dev/null | grep -viE "$exempt" |
    75 |                 sed "s|^|${f#"$root"/}:|" || true
    76 |         done
    77 |     done < <(list_names "$root")
    78 | }
    79 | 
    80 | # check_operator_ops <root>: prints SKILL.md files whose allowed-tools grant
    81 | # an operator-only dec-write-lib.sh operation
~~~~

The change from head to the fix:

~~~~diff
@@ -61,9 +61,13 @@
-# check_operative <root>: prints file:line for each operative reference to a
-# listed name in a body other than that command's own file
+# check_operative <root>: prints file:line:text for each operative reference
+# to a listed name in a body other than that command's own file.
+# Two steps per line: find every verb + /name match (SDD D-8.3 pattern,
+# widened to any-case verbs and an optional "the"), then judge the text
+# BEFORE that match. A match is advice, and exempt, only when that prefix
+# holds an exempt word ("tell the user to run /x") within the same clause
+# (after the last ". ", ";" or " then "), or an odd number of backticks (the
+# verb sits inside an inline quote). An exempt word after the command
+# ("Run /x on the operator's behalf") or in an earlier clause does not
+# exempt. A line is reported when any match on it is operative.
 check_operative() {
-    local root="$1" name re exempt
-    exempt='(^|[^[:alpha:]])(user|operator|human|manually|suggest|recommend|tell|ask)'
+    local root="$1" name
     while IFS= read -r name; do
-        # SDD D-8.3 pattern, widened: verbs match in any case and may take
-        # "the" ("execute /x", "Invoke the /x skill").
-        re="([Ee][Xx][Ee][Cc][Uu][Tt][Ee]|[Ii][Nn][Vv][Oo][Kk][Ee]|[Rr][Uu][Nn]|[Cc][Aa][Ll][Ll])[[:space:]]+(the[[:space:]]+)?\`?/${name}([^[:alnum:]_-]|\$)|Skill\\(.*${name}"
~~~~

## H13 — tests/unit/user-invoked-commands.bats — head lines 74–75

Head context (head/tests/unit/user-invoked-commands.bats, lines 62–87):

~~~~text
    62 | # listed name in a body other than that command's own file
    63 | check_operative() {
    64 |     local root="$1" name re exempt
    65 |     exempt='(^|[^[:alpha:]])(user|operator|human|manually|suggest|recommend|tell|ask)'
    66 |     while IFS= read -r name; do
    67 |         # SDD D-8.3 pattern, widened: verbs match in any case and may take
    68 |         # "the" ("execute /x", "Invoke the /x skill").
    69 |         re="([Ee][Xx][Ee][Cc][Uu][Tt][Ee]|[Ii][Nn][Vv][Oo][Kk][Ee]|[Rr][Uu][Nn]|[Cc][Aa][Ll][Ll])[[:space:]]+(the[[:space:]]+)?\`?/${name}([^[:alnum:]_-]|\$)|Skill\\(.*${name}"
    70 |         { find "$root/.claude/commands" -name '*.md' -type f 2>/dev/null
    71 |           find "$root/.claude/skills" -name '*.md' -type f 2>/dev/null; } |
    72 |         while IFS= read -r f; do
    73 |             [[ "$f" == "$root/.claude/commands/$name.md" ]] && continue
>   74 |             grep -nE "$re" "$f" 2>/dev/null | grep -viE "$exempt" |
>   75 |                 sed "s|^|${f#"$root"/}:|" || true
    76 |         done
    77 |     done < <(list_names "$root")
    78 | }
    79 | 
    80 | # check_operator_ops <root>: prints SKILL.md files whose allowed-tools grant
    81 | # an operator-only dec-write-lib.sh operation
    82 | check_operator_ops() {
    83 |     local root="$1" f
    84 |     while IFS= read -r f; do
    85 |         frontmatter "$f" | awk '/^allowed-tools:/{on=1; print; next} on && /^[[:space:]]+-|^[[:space:]]+[^[:space:]]/{print; next} {on=0}' |
    86 |             grep -Eq 'dec-write-lib\.sh[^,)]*(confirm|supersede|context[[:space:]]+--clear)' && echo "${f#"$root"/}"
    87 |     done < <(find "$root/.claude/skills" -name SKILL.md -type f 2>/dev/null)
~~~~

The change from head to the fix:

~~~~diff
@@ -74,2 +78,21 @@
-            grep -nE "$re" "$f" 2>/dev/null | grep -viE "$exempt" |
-                sed "s|^|${f#"$root"/}:|" || true
+            awk -v name="$name" -v rel="${f#"$root"/}" '
+                BEGIN {
+                    re = "(execute|invoke|run|call)[[:space:]]+(the[[:space:]]+)?`?/" name "[^[:alnum:]_-]|skill[(].*" name
+                    ex = "(^|[^[:alpha:]])(user|operator|human|manually|suggest|recommend|tell|ask)"
+                    br = "[.!?;][[:space:]]|[[:space:]]then[[:space:]]"
+                }
+                {
+                    s = tolower($0) " "; off = 0; hit = 0
+                    while (match(substr(s, off + 1), re)) {
+                        at = off + RSTART
+                        pre = substr(s, 1, at - 1)
+                        tmp = pre; ticks = gsub(/`/, "", tmp)
+                        # judge only the current clause: cut at the last
+                        # sentence end, semicolon or " then "
+                        cl = pre
+                        while (match(cl, br)) cl = substr(cl, RSTART + RLENGTH)
+                        if (cl !~ ex && ticks % 2 == 0) { hit = 1; break }
+                        off = at
+                    }
+                    if (hit) print rel ":" NR ":" $0
+                }' "$f"
~~~~

## H14 — tests/unit/user-invoked-commands.bats — insertion after head line 209

Head context (head/tests/unit/user-invoked-commands.bats, lines 198–221):

~~~~text
   198 |     [[ "$output" == *"SKILL.md:5:Invoke /beta"* ]]
   199 |     [[ "$output" == *"SKILL.md:6:Then call Skill(alpha)"* ]]
   200 |     [[ "$output" != *":7:"* ]]
   201 |     [[ "$output" != *":8:"* ]]
   202 |     [[ "$output" != *"alphabet"* ]]
   203 |     [[ "$output" != *"alpha-two"* ]]
   204 |     [[ "$output" == *"SKILL.md:11:then execute /alpha"* ]]
   205 |     [[ "$output" == *"SKILL.md:12:Invoke the"* ]]
   206 |     # beta.md mentions Run `/alpha`: another body, so it is caught too
   207 |     [[ "$output" == *"commands/beta.md:5:"* ]]
   208 | }
   209 | 
   210 | @test "fixture: a skill granting dec-write-lib.sh confirm is reported" {
   211 |     local r; r="$(make_fixture)"
   212 |     printf -- '---\nname: demo\nallowed-tools: Read, Bash(.claude/scripts/lib/dec-write-lib.sh confirm *)\n---\n' > "$r/.claude/skills/demo/SKILL.md"
   213 |     run check_operator_ops "$r"
   214 |     [ "$output" = ".claude/skills/demo/SKILL.md" ]
   215 |     printf -- '---\nname: demo\nallowed-tools:\n  - Read\n  - Bash(.claude/scripts/lib/dec-write-lib.sh context --clear)\n---\n' > "$r/.claude/skills/demo/SKILL.md"
   216 |     run check_operator_ops "$r"
   217 |     [ "$output" = ".claude/skills/demo/SKILL.md" ]
   218 |     printf -- '---\nname: demo\nallowed-tools: Read, Bash(.claude/scripts/lib/dec-write-lib.sh new *)\n---\n' > "$r/.claude/skills/demo/SKILL.md"
   219 |     run check_operator_ops "$r"
   220 |     [ -z "$output" ]
   221 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -209,0 +233,25 @@
+@test "fixture: an exempt word only exempts when it precedes the verb" {
+    local r; r="$(make_fixture)"
+    printf -- '---\nname: beta\ndisable-model-invocation: true\n---\nplain body\n' > "$r/.claude/commands/beta.md"
+    cat > "$r/.claude/skills/demo/SKILL.md" <<'EOF'
+---
+name: demo
+---
+Run `/alpha confirm` on the operator's behalf.
+Invoke /beta for the user.
+Tell the user to run /alpha.
+Ask the operator to type `/alpha`.
+Example reply: `Run /alpha first.`
+Tell the user to run /alpha, then Run /beta yourself.
+Recommend the operator Run `/beta --force` after review.
+EOF
+    run check_operative "$r"
+    [[ "$output" == *'SKILL.md:4:Run `/alpha confirm` on the operator'* ]]
+    [[ "$output" == *"SKILL.md:5:Invoke /beta for the user"* ]]
+    [[ "$output" != *"SKILL.md:6:"* ]]
+    [[ "$output" != *"SKILL.md:7:"* ]]
+    [[ "$output" != *"SKILL.md:8:"* ]]
+    [[ "$output" == *"SKILL.md:9:Tell the user"* ]]
+    [[ "$output" != *"SKILL.md:10:"* ]]
+}
+
~~~~

## H15 — tools/check-round-independence.sh — head line 65

Head context (head/tools/check-round-independence.sh, lines 53–77):

~~~~text
    53 | command -v jq >/dev/null 2>&1 || { echo "check-round-independence.sh: jq is required" >&2; exit 2; }
    54 | 
    55 | BLOCK_RE='<!--[[:space:]]*round:[[:space:]]*[0-9]+[[:space:]]*;[[:space:]]*questions:[[:space:]]*\[.*\][[:space:]]*-->'
    56 | 
    57 | # One JSON object per block: {round, questions} or {round, malformed}. grep exits
    58 | # 1 on no match, which is the "no block" case below, not an error.
    59 | blocks="$(grep -oE "$BLOCK_RE" "$TRANSCRIPT" || true)"
    60 | if [[ -z "$blocks" ]]; then
    61 |   echo "check-round-independence.sh: no <!-- round: N; questions: [...] --> block in $TRANSCRIPT" >&2
    62 |   exit 2
    63 | fi
    64 | 
>   65 | rounds_json="[]"
    66 | while IFS= read -r block; do
    67 |   [[ -n "$block" ]] || continue
    68 |   n="$(printf '%s\n' "$block" | sed -E 's/^<!--[[:space:]]*round:[[:space:]]*([0-9]+).*/\1/')"
    69 |   [[ ${#n} -le 9 ]] || { echo "check-round-independence.sh: round number $n is too long" >&2; exit 1; }
    70 |   n=$((10#$n))   # "02" is not valid JSON; the round number is decimal
    71 |   arr="$(printf '%s\n' "$block" | sed -E 's/^<!--[[:space:]]*round:[[:space:]]*[0-9]+[[:space:]]*;[[:space:]]*questions:[[:space:]]*//; s/[[:space:]]*-->$//')"
    72 |   if printf '%s' "$arr" | jq -e 'type == "array" and all(.[];
    73 |         type == "object" and (.id | type == "string" and length > 0)
    74 |         and (.depends_on | type == "array" and all(.[]; type == "string")))' >/dev/null 2>&1; then
    75 |     entry="$(jq -cn --argjson r "$n" --argjson q "$arr" '{round: $r, questions: $q}')"
    76 |   else
    77 |     entry="$(jq -cn --argjson r "$n" --arg raw "$arr" '{round: $r, malformed: $raw}')"
~~~~

The change from head to the fix:

~~~~diff
@@ -65 +65,8 @@
-rounds_json="[]"
+# Transcript content never travels as a jq argv string (Linux caps one argument
+# at 128 KiB): each block and the accumulated rounds go through temp files.
+WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-round-independence.XXXXXX")"
+trap 'rm -rf "$WORK"' EXIT
+MAX_BLOCK_BYTES=65536
+ID_RE='^[A-Za-z0-9_.-]{1,64}$'
+: > "$WORK/rounds.jsonl"
+
~~~~

## H16 — tools/check-round-independence.sh — head lines 71–83

Head context (head/tools/check-round-independence.sh, lines 59–95):

~~~~text
    59 | blocks="$(grep -oE "$BLOCK_RE" "$TRANSCRIPT" || true)"
    60 | if [[ -z "$blocks" ]]; then
    61 |   echo "check-round-independence.sh: no <!-- round: N; questions: [...] --> block in $TRANSCRIPT" >&2
    62 |   exit 2
    63 | fi
    64 | 
    65 | rounds_json="[]"
    66 | while IFS= read -r block; do
    67 |   [[ -n "$block" ]] || continue
    68 |   n="$(printf '%s\n' "$block" | sed -E 's/^<!--[[:space:]]*round:[[:space:]]*([0-9]+).*/\1/')"
    69 |   [[ ${#n} -le 9 ]] || { echo "check-round-independence.sh: round number $n is too long" >&2; exit 1; }
    70 |   n=$((10#$n))   # "02" is not valid JSON; the round number is decimal
>   71 |   arr="$(printf '%s\n' "$block" | sed -E 's/^<!--[[:space:]]*round:[[:space:]]*[0-9]+[[:space:]]*;[[:space:]]*questions:[[:space:]]*//; s/[[:space:]]*-->$//')"
>   72 |   if printf '%s' "$arr" | jq -e 'type == "array" and all(.[];
>   73 |         type == "object" and (.id | type == "string" and length > 0)
>   74 |         and (.depends_on | type == "array" and all(.[]; type == "string")))' >/dev/null 2>&1; then
>   75 |     entry="$(jq -cn --argjson r "$n" --argjson q "$arr" '{round: $r, questions: $q}')"
>   76 |   else
>   77 |     entry="$(jq -cn --argjson r "$n" --arg raw "$arr" '{round: $r, malformed: $raw}')"
>   78 |   fi
>   79 |   rounds_json="$(jq -cn --argjson a "$rounds_json" --argjson e "$entry" '$a + [$e]')"
>   80 | done <<< "$blocks"
>   81 | 
>   82 | report="$(jq -n --argjson rounds "$rounds_json" --argjson min "$MIN_AVG" '
>   83 |   reduce range(0; $rounds | length) as $i (
    84 |     {asked: [], violations: [], per_round: [], prev: null};
    85 |     $rounds[$i] as $r
    86 |     | (if .prev != null and $r.round <= .prev
    87 |          then .violations += ["round \($r.round) does not follow round \(.prev)"] else . end)
    88 |     | .prev = $r.round
    89 |     | if $r.malformed != null then
    90 |         .violations += ["round \($r.round): malformed questions array (each entry needs a string id and a depends_on array of strings)"]
    91 |         | .per_round += [{round: $r.round, new: 0, reasked: 0, ids: []}]
    92 |       else
    93 |         ($r.questions | map(.id)) as $here
    94 |         | .asked as $before
    95 |         | reduce $r.questions[] as $q (.;
~~~~

The change from head to the fix:

~~~~diff
@@ -71,13 +78,25 @@
-  arr="$(printf '%s\n' "$block" | sed -E 's/^<!--[[:space:]]*round:[[:space:]]*[0-9]+[[:space:]]*;[[:space:]]*questions:[[:space:]]*//; s/[[:space:]]*-->$//')"
-  if printf '%s' "$arr" | jq -e 'type == "array" and all(.[];
-        type == "object" and (.id | type == "string" and length > 0)
-        and (.depends_on | type == "array" and all(.[]; type == "string")))' >/dev/null 2>&1; then
-    entry="$(jq -cn --argjson r "$n" --argjson q "$arr" '{round: $r, questions: $q}')"
+  printf '%s\n' "$block" | sed -E 's/^<!--[[:space:]]*round:[[:space:]]*[0-9]+[[:space:]]*;[[:space:]]*questions:[[:space:]]*//; s/[[:space:]]*-->$//' > "$WORK/arr.json"
+  bytes="$(wc -c < "$WORK/arr.json" | tr -d '[:space:]')"
+  if [[ "$bytes" -gt "$MAX_BLOCK_BYTES" ]]; then
+    jq -cn --argjson r "$n" --arg why "block is $bytes bytes, over the $MAX_BLOCK_BYTES-byte limit" \
+      '{round: $r, malformed: $why}' >> "$WORK/rounds.jsonl"
+  # -s slurps the capture: exactly one JSON value, a well-formed array whose
+  # ids and depends_on names match ID_RE. Without -s, `[] [{...}]` (two values)
+  # would pass on the last one. Ids are untrusted model output, so the pattern
+  # also keeps escapes and control characters out of every printed line.
+  elif jq -se --arg re "$ID_RE" 'length == 1 and (.[0] | type == "array" and all(.[];
+        type == "object" and (.id | type == "string" and test($re))
+        and (.depends_on | type == "array" and all(.[]; type == "string" and test($re)))))' \
+        "$WORK/arr.json" >/dev/null 2>&1; then
+    jq -c --argjson r "$n" '{round: $r, questions: .}' "$WORK/arr.json" >> "$WORK/rounds.jsonl"
   else
-    entry="$(jq -cn --argjson r "$n" --arg raw "$arr" '{round: $r, malformed: $raw}')"
+    jq -cn --argjson r "$n" \
+      '{round: $r, malformed: "each entry needs an id and depends_on names matching [A-Za-z0-9_.-]{1,64}"}' \
+      >> "$WORK/rounds.jsonl"
   fi
-  rounds_json="$(jq -cn --argjson a "$rounds_json" --argjson e "$entry" '$a + [$e]')"
 done <<< "$blocks"
+jq -s '.' "$WORK/rounds.jsonl" > "$WORK/rounds.json"
 
-report="$(jq -n --argjson rounds "$rounds_json" --argjson min "$MIN_AVG" '
-  reduce range(0; $rounds | length) as $i (
+report="$(jq -n --slurpfile rs "$WORK/rounds.json" --argjson min "$MIN_AVG" '
+  $rs[0] as $rounds
+  | reduce range(0; $rounds | length) as $i (
~~~~

## H17 — tools/check-round-independence.sh — head line 90

Head context (head/tools/check-round-independence.sh, lines 78–102):

~~~~text
    78 |   fi
    79 |   rounds_json="$(jq -cn --argjson a "$rounds_json" --argjson e "$entry" '$a + [$e]')"
    80 | done <<< "$blocks"
    81 | 
    82 | report="$(jq -n --argjson rounds "$rounds_json" --argjson min "$MIN_AVG" '
    83 |   reduce range(0; $rounds | length) as $i (
    84 |     {asked: [], violations: [], per_round: [], prev: null};
    85 |     $rounds[$i] as $r
    86 |     | (if .prev != null and $r.round <= .prev
    87 |          then .violations += ["round \($r.round) does not follow round \(.prev)"] else . end)
    88 |     | .prev = $r.round
    89 |     | if $r.malformed != null then
>   90 |         .violations += ["round \($r.round): malformed questions array (each entry needs a string id and a depends_on array of strings)"]
    91 |         | .per_round += [{round: $r.round, new: 0, reasked: 0, ids: []}]
    92 |       else
    93 |         ($r.questions | map(.id)) as $here
    94 |         | .asked as $before
    95 |         | reduce $r.questions[] as $q (.;
    96 |             ($q.reasked == true) as $re
    97 |             | (if $re then
    98 |                  (if ($before | index([$q.id])) == null
    99 |                     then .violations += ["round \($r.round): \($q.id) is marked reasked but was not asked in an earlier round"] else . end)
   100 |                else
   101 |                  (if (.asked | index([$q.id])) != null
   102 |                     then .violations += ["round \($r.round): \($q.id) is asked again without \"reasked\": true"] else . end)
~~~~

The change from head to the fix:

~~~~diff
@@ -90 +109 @@
-        .violations += ["round \($r.round): malformed questions array (each entry needs a string id and a depends_on array of strings)"]
+        .violations += ["round \($r.round): malformed questions array (\($r.malformed))"]
~~~~

## H18 — tools/check-round-independence.sh — head lines 139–143

Head context (head/tools/check-round-independence.sh, lines 127–147):

~~~~text
   127 |       reasked: (.per_round | map(.reasked) | add),
   128 |       average: (.average * 100 | round / 100),
   129 |       min_average: $min,
   130 |       final_round_exempt: ((.per_round | length) >= 2),
   131 |       per_round: .per_round,
   132 |       violations: .violations,
   133 |       verdict: (if (.violations | length) == 0 then "PASS" else "FAIL" end)
   134 |     }')"
   135 | 
   136 | if [[ "$JSON" -eq 1 ]]; then
   137 |   printf '%s\n' "$report"
   138 | else
>  139 |   printf '%s\n' "$report" | jq -r '
>  140 |     (.per_round[] | "round \(.round): \(.new) new question(s)\(if .reasked > 0 then ", \(.reasked) re-asked" else "" end) [\(.ids | join(" "))]"),
>  141 |     "rounds: \(.rounds); questions: \(.questions); average: \(.average) per round\(if .final_round_exempt then " (final round exempt)" else "" end); min-average: \(.min_average)",
>  142 |     (.violations[] | "VIOLATION: \(.)"),
>  143 |     .verdict'
   144 | fi
   145 | 
   146 | verdict="$(printf '%s\n' "$report" | jq -r '.verdict')"
   147 | [[ "$verdict" == "PASS" ]]
~~~~

The change from head to the fix:

~~~~diff
@@ -139,5 +158,8 @@
+  # Strip control characters from every printed line: ids are validated above,
+  # this keeps any future field from putting a raw ESC on the terminal.
   printf '%s\n' "$report" | jq -r '
-    (.per_round[] | "round \(.round): \(.new) new question(s)\(if .reasked > 0 then ", \(.reasked) re-asked" else "" end) [\(.ids | join(" "))]"),
+    def clean: gsub("[[:cntrl:]]"; "?");
+    ((.per_round[] | "round \(.round): \(.new) new question(s)\(if .reasked > 0 then ", \(.reasked) re-asked" else "" end) [\(.ids | join(" "))]"),
     "rounds: \(.rounds); questions: \(.questions); average: \(.average) per round\(if .final_round_exempt then " (final round exempt)" else "" end); min-average: \(.min_average)",
     (.violations[] | "VIOLATION: \(.)"),
-    .verdict'
+    .verdict) | clean'
~~~~
