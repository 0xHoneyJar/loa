# Hunks — pr-14

The later fix changed 95 region(s) in 36 of the change's 88 file(s). Line numbers are head-side (the code under review). Each entry shows up to 12 head lines before and after the region; `>` marks a head line the fix changed.

## H01 — .claude/adapters/tests/test_trust_scopes.py — head lines 349–351

Head context (head/.claude/adapters/tests/test_trust_scopes.py, lines 337–363):

~~~~text
   337 |                     f"Model '{model_id}' missing execution_mode",
   338 |                 )
   339 | 
   340 |     def test_all_entries_have_capabilities(self):
   341 |         for model_id, entry in self.models.items():
   342 |             with self.subTest(model=model_id):
   343 |                 self.assertIn(
   344 |                     "capabilities",
   345 |                     entry,
   346 |                     f"Model '{model_id}' missing capabilities",
   347 |                 )
   348 | 
>  349 |     def test_every_anthropic_catalog_entry_has_a_row(self):
>  350 |         """cycle-126 D-4.2: every Anthropic entry the catalog serves (direct and
>  351 |         Bedrock-routed) has a registry row, so no current model is unscoped."""
   352 |         catalog_path = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
   353 |         with open(catalog_path, "r") as f:
   354 |             providers = yaml.safe_load(f)["providers"]
   355 |         served = [f"anthropic:{m}" for m in providers["anthropic"]["models"]]
   356 |         served += [f"bedrock:{m}" for m in providers.get("bedrock", {}).get("models", {})
   357 |                    if "anthropic." in m]
   358 |         self.assertGreaterEqual(len(served), 12)
   359 |         missing = [key for key in served if key not in self.models]
   360 |         self.assertEqual(missing, [], f"catalog entries without a model-permissions row: {missing}")
   361 | 
   362 |     def test_current_generation_rows_mirror_the_4_7_scopes(self):
   363 |         reference = self.models["anthropic:claude-opus-4-7"]
~~~~

The change from head to the fix:

~~~~diff
@@ -349,3 +349,3 @@
-    def test_every_anthropic_catalog_entry_has_a_row(self):
-        """cycle-126 D-4.2: every Anthropic entry the catalog serves (direct and
-        Bedrock-routed) has a registry row, so no current model is unscoped."""
+    @staticmethod
+    def _served_anthropic_keys():
+        """Every Anthropic entry the catalog serves, direct and Bedrock-routed."""
~~~~

## H02 — .claude/adapters/tests/test_trust_scopes.py — insertion after head line 357

Head context (head/.claude/adapters/tests/test_trust_scopes.py, lines 346–369):

~~~~text
   346 |                     f"Model '{model_id}' missing capabilities",
   347 |                 )
   348 | 
   349 |     def test_every_anthropic_catalog_entry_has_a_row(self):
   350 |         """cycle-126 D-4.2: every Anthropic entry the catalog serves (direct and
   351 |         Bedrock-routed) has a registry row, so no current model is unscoped."""
   352 |         catalog_path = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
   353 |         with open(catalog_path, "r") as f:
   354 |             providers = yaml.safe_load(f)["providers"]
   355 |         served = [f"anthropic:{m}" for m in providers["anthropic"]["models"]]
   356 |         served += [f"bedrock:{m}" for m in providers.get("bedrock", {}).get("models", {})
   357 |                    if "anthropic." in m]
   358 |         self.assertGreaterEqual(len(served), 12)
   359 |         missing = [key for key in served if key not in self.models]
   360 |         self.assertEqual(missing, [], f"catalog entries without a model-permissions row: {missing}")
   361 | 
   362 |     def test_current_generation_rows_mirror_the_4_7_scopes(self):
   363 |         reference = self.models["anthropic:claude-opus-4-7"]
   364 |         for key in ("anthropic:claude-opus-5-5", "anthropic:claude-opus-5", "anthropic:claude-sonnet-5",
   365 |                     "anthropic:claude-fable-5-1", "anthropic:claude-opus-4-8",
   366 |                     "bedrock:us.anthropic.claude-opus-4-8"):
   367 |             with self.subTest(model=key):
   368 |                 entry = self.models.get(key, {})
   369 |                 self.assertEqual(entry.get("trust_scopes"), reference["trust_scopes"])
~~~~

The change from head to the fix:

~~~~diff
@@ -357,0 +358,6 @@
+        return served
+
+    def test_every_anthropic_catalog_entry_has_a_row(self):
+        """cycle-126 D-4.2: every Anthropic entry the catalog serves (direct and
+        Bedrock-routed) has a registry row, so no current model is unscoped."""
+        served = self._served_anthropic_keys()
~~~~

## H03 — .claude/adapters/tests/test_trust_scopes.py — head lines 363–366

Head context (head/.claude/adapters/tests/test_trust_scopes.py, lines 351–376):

~~~~text
   351 |         Bedrock-routed) has a registry row, so no current model is unscoped."""
   352 |         catalog_path = REPO_ROOT / ".claude" / "defaults" / "model-config.yaml"
   353 |         with open(catalog_path, "r") as f:
   354 |             providers = yaml.safe_load(f)["providers"]
   355 |         served = [f"anthropic:{m}" for m in providers["anthropic"]["models"]]
   356 |         served += [f"bedrock:{m}" for m in providers.get("bedrock", {}).get("models", {})
   357 |                    if "anthropic." in m]
   358 |         self.assertGreaterEqual(len(served), 12)
   359 |         missing = [key for key in served if key not in self.models]
   360 |         self.assertEqual(missing, [], f"catalog entries without a model-permissions row: {missing}")
   361 | 
   362 |     def test_current_generation_rows_mirror_the_4_7_scopes(self):
>  363 |         reference = self.models["anthropic:claude-opus-4-7"]
>  364 |         for key in ("anthropic:claude-opus-5-5", "anthropic:claude-opus-5", "anthropic:claude-sonnet-5",
>  365 |                     "anthropic:claude-fable-5-1", "anthropic:claude-opus-4-8",
>  366 |                     "bedrock:us.anthropic.claude-opus-4-8"):
   367 |             with self.subTest(model=key):
   368 |                 entry = self.models.get(key, {})
   369 |                 self.assertEqual(entry.get("trust_scopes"), reference["trust_scopes"])
   370 |                 self.assertEqual(entry.get("trust_level"), reference["trust_level"])
   371 |                 self.assertEqual(entry.get("execution_mode"), "remote_model")
   372 |                 self.assertEqual(entry.get("capabilities"), reference["capabilities"])
   373 | 
   374 | 
   375 | if __name__ == "__main__":
   376 |     unittest.main()
~~~~

The change from head to the fix:

~~~~diff
@@ -363,4 +369,7 @@
+        # sprint-250 review run 1, n13: the key list is the catalog's served
+        # Anthropic/Bedrock entries (it pinned 6 of 16), so a widened scope on
+        # any served row fails here. No row is meant to differ from 4.7 today.
         reference = self.models["anthropic:claude-opus-4-7"]
-        for key in ("anthropic:claude-opus-5-5", "anthropic:claude-opus-5", "anthropic:claude-sonnet-5",
-                    "anthropic:claude-fable-5-1", "anthropic:claude-opus-4-8",
-                    "bedrock:us.anthropic.claude-opus-4-8"):
+        served = self._served_anthropic_keys()
+        self.assertGreaterEqual(len(served), 16)
+        for key in served:
~~~~

## H04 — .claude/adapters/tests/test_trust_scopes.py — insertion after head line 373

Head context (head/.claude/adapters/tests/test_trust_scopes.py, lines 362–376):

~~~~text
   362 |     def test_current_generation_rows_mirror_the_4_7_scopes(self):
   363 |         reference = self.models["anthropic:claude-opus-4-7"]
   364 |         for key in ("anthropic:claude-opus-5-5", "anthropic:claude-opus-5", "anthropic:claude-sonnet-5",
   365 |                     "anthropic:claude-fable-5-1", "anthropic:claude-opus-4-8",
   366 |                     "bedrock:us.anthropic.claude-opus-4-8"):
   367 |             with self.subTest(model=key):
   368 |                 entry = self.models.get(key, {})
   369 |                 self.assertEqual(entry.get("trust_scopes"), reference["trust_scopes"])
   370 |                 self.assertEqual(entry.get("trust_level"), reference["trust_level"])
   371 |                 self.assertEqual(entry.get("execution_mode"), "remote_model")
   372 |                 self.assertEqual(entry.get("capabilities"), reference["capabilities"])
   373 | 
   374 | 
   375 | if __name__ == "__main__":
   376 |     unittest.main()
~~~~

The change from head to the fix:

~~~~diff
@@ -373,0 +383,13 @@
+    def test_mirror_reference_row_is_literally_pinned(self):
+        # audit dissent run 1, n7: the mirror above compares every served row to
+        # the live 4.7 row, so a correlated widening (the reference row and the
+        # rest together) would pass it. Pin the reference row's capabilities and
+        # context_access.security literally; the six operational dimensions are
+        # pinned "none" by test_anthropic_opus_4_7_all_none.
+        reference = self.models["anthropic:claude-opus-4-7"]
+        self.assertEqual(
+            reference.get("capabilities"),
+            {"file_read": False, "file_write": False, "command_execution": False, "network_access": False},
+        )
+        self.assertEqual(reference["trust_scopes"]["context_access"]["security"], "redacted")
+
~~~~

## H05 — .claude/defaults/model-config.yaml — insertion after head line 478

Head context (head/.claude/defaults/model-config.yaml, lines 467–490):

~~~~text
   467 |             input_multiplier: 2.0
   468 |             output_multiplier: 1.5
   469 |             verified: false
   470 |       claude-opus-5-5:
   471 |         # cycle-126 sprint-250 (bead bd-2fti): Opus 5.5 — the `opus` alias
   472 |         # target (retargeted 5 → 5.5). Vendor reference, read 2026-10-05:
   473 |         # https://platform.claude.com/docs/en/about-claude/models/overview
   474 |         # (1M context, 128K output, adaptive thinking always on) and
   475 |         # https://platform.claude.com/docs/en/about-claude/pricing ($4/$20 per
   476 |         # MTok; cache hit 0.05× = $0.20; "Claude 4.6 and later models … include
   477 |         # the full 1M token context window at standard pricing", so no
   478 |         # long_context tier). structured_json per the structured-outputs page.
   479 |         auth_type: http_api
   480 |         dispatch_group: anthropic-claude
   481 |         capabilities: [chat, tools, function_calling, thinking_traces, structured_json]
   482 |         context_window: 1000000
   483 |         token_param: max_tokens
   484 |         # Within-company chain: 5.5 → 5 → Sonnet 5 → headless.
   485 |         fallback_chain:
   486 |           - anthropic:claude-opus-5
   487 |           - anthropic:claude-sonnet-5
   488 |           - anthropic:claude-headless
   489 |         max_output_tokens: 128000
   490 |         effective_input_ceiling: 180000   # cycle-124 FR-3 (SDD §2.1): see claude-fable-5-1
~~~~

The change from head to the fix:

~~~~diff
@@ -478,0 +479,4 @@
+        # The other 5-family entries (claude-fable-5-1, claude-fable-5,
+        # claude-opus-5, claude-sonnet-5) keep their unverified 2.0×/1.5×
+        # long_context tier above 200K until an invoice confirms which reading
+        # holds (sprint-250 review run 1, n3).
~~~~

## H06 — .claude/defaults/model-config.yaml.checksum — head line 1

Head context (head/.claude/defaults/model-config.yaml.checksum, lines 1–1):

~~~~text
>    1 | 759dfd3fd030411acb5f6f95f4ed5ba8c9e4cc5311f2d1bd20dffe57ab61b7cd
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-759dfd3fd030411acb5f6f95f4ed5ba8c9e4cc5311f2d1bd20dffe57ab61b7cd
+ede256301784d889d25e31f6b10444634637a22aaa6b406113d23a3b7b2eb1b1
~~~~

## H07 — .claude/hooks/compliance/implement-gate.sh — insertion after head line 13

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 2–25):

~~~~text
     2 | # =============================================================================
     3 | # implement-gate.sh — Dual-mode compliance hook for App Zone writes (FR-7)
     4 | # =============================================================================
     5 | # Checks whether Write/Edit to App Zone files occurs within an active
     6 | # /implement or /bug skill invocation.
     7 | #
     8 | # Two detection modes:
     9 | #   1. HEURISTIC (ADVISORY, the default): reads .run/ state files for RUNNING state
    10 | #   2. AUTHORITATIVE: reads tool_input.active_skill from hook stdin, only when
    11 | #      .loa.config.yaml sets implement_gate.mode: authoritative. The PreToolUse
    12 | #      payload carries no harness-set skill field (cycle-126 D-4.4) and tool_input
    13 | #      is model-authored, so nothing in .run/ selects this mode.
    14 | #
    15 | # Evidence recorder (cycle-126 D-4.4): a lead-session payload carrying
    16 | # tool_input.active_skill records active_skill_seen_at once in
    17 | # .run/platform-features.json. It is evidence only and never changes the mode.
    18 | #
    19 | # Failure mode: FAIL-ASK for App Zone writes (not fail-open).
    20 | # Non-App-Zone writes always allowed.
    21 | #
    22 | # IMPORTANT: No set -euo pipefail — hook must never crash-block.
    23 | # Parse/read errors on App Zone writes → ask (not allow).
    24 | #
    25 | # Part of cycle-049/050: Upstream Platform Alignment (FR-7)
~~~~

The change from head to the fix:

~~~~diff
@@ -13,0 +14,7 @@
+#      TIGHTEN-ONLY (sprint-250 audit n17/n18): the model-authored claim can only
+#      add an ask, never grant an allow. A claimed implementation skill falls
+#      through to the heuristic exactly like an absent field; a claimed
+#      non-implementation skill asks and logs compliance.mode.model_signal to
+#      .run/audit.jsonl (plain hook log, not the signed audit_emit chain). Every
+#      claim leaves one row per invocation: decision "ask" for a non-implementation
+#      claim, decision "heuristic" for an implementation claim (run-2 finding 6).
~~~~

## H08 — .claude/hooks/compliance/implement-gate.sh — head lines 19–20

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 7–32):

~~~~text
     7 | #
     8 | # Two detection modes:
     9 | #   1. HEURISTIC (ADVISORY, the default): reads .run/ state files for RUNNING state
    10 | #   2. AUTHORITATIVE: reads tool_input.active_skill from hook stdin, only when
    11 | #      .loa.config.yaml sets implement_gate.mode: authoritative. The PreToolUse
    12 | #      payload carries no harness-set skill field (cycle-126 D-4.4) and tool_input
    13 | #      is model-authored, so nothing in .run/ selects this mode.
    14 | #
    15 | # Evidence recorder (cycle-126 D-4.4): a lead-session payload carrying
    16 | # tool_input.active_skill records active_skill_seen_at once in
    17 | # .run/platform-features.json. It is evidence only and never changes the mode.
    18 | #
>   19 | # Failure mode: FAIL-ASK for App Zone writes (not fail-open).
>   20 | # Non-App-Zone writes always allowed.
    21 | #
    22 | # IMPORTANT: No set -euo pipefail — hook must never crash-block.
    23 | # Parse/read errors on App Zone writes → ask (not allow).
    24 | #
    25 | # Part of cycle-049/050: Upstream Platform Alignment (FR-7)
    26 | # Red Team findings addressed: ATK-005 (state tampering), ATK-006 (fail-open),
    27 | #   ATK-007 (prompt injection via file path)
    28 | # Sprint-108 T4.4: Dual-mode (authoritative + heuristic)
    29 | # Sprint-108 T4.5: Path normalization
    30 | # =============================================================================
    31 | 
    32 | # Read tool input from stdin
~~~~

The change from head to the fix:

~~~~diff
@@ -19,2 +26,24 @@
-# Failure mode: FAIL-ASK for App Zone writes (not fail-open).
-# Non-App-Zone writes always allowed.
+# Failure mode: FAIL-ASK for App Zone writes (not fail-open). A payload jq cannot
+# parse (or no jq), or a file_path that cannot be canonicalised, asks too (run-2
+# findings 1/5). The path is tool_input.file_path, or tool_input.notebook_path for
+# NotebookEdit; a relative path resolves from the payload's cwd, else PROJECT_ROOT
+# (run-3 finding 6). The zone test ORs a physical form (symlinks followed) and a
+# logical form (symlinks kept) and matches a lowercased copy (run-3 findings 1/2).
+# Root: PROJECT_ROOT, else CLAUDE_PROJECT_DIR, else this script's location
+# (<root>/.claude/hooks/compliance/), never the process cwd, which follows
+# Claude's `cd` (audit MED-001); RUN_DIR defaults to <root>/.run.
+# Trust inputs: a write to .run/state.json, .run/sprint-plan-state.json,
+# .run/simstim-state.json, .run/platform-features.json, .run/audit.jsonl or
+# .loa.config.yaml asks and logs compliance.state_write (run-3 finding 3).
+# Other non-App-Zone writes always allowed.
+#
+# Output (Claude Code PreToolUse contract, sprint-250 audit n20): allow = silent
+# exit 0 with empty stdout; ask = exit 0 with
+#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"…"}}
+# A top-level "decision" accepts approve|block only, so "ask" never goes there.
+# file_path and active_skill reach stderr only through strip_controls (n21;
+# run-2 findings 3/12; run-3 finding 5): cut to 256 bytes without splitting a
+# character, then C0 and DEL, UTF-8 C1 controls and the Unicode format/bidi/tag
+# code points are removed to a fixed point. Audit rows record the RAW values cut
+# the same way and written with jq -a, so every non-ASCII code point is \uXXXX:
+# faithful (implement+U+200B logs as implement\u200b) and terminal-safe (run-3 finding 4).
~~~~

## H09 — .claude/hooks/compliance/implement-gate.sh — head line 35

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 23–47):

~~~~text
    23 | # Parse/read errors on App Zone writes → ask (not allow).
    24 | #
    25 | # Part of cycle-049/050: Upstream Platform Alignment (FR-7)
    26 | # Red Team findings addressed: ATK-005 (state tampering), ATK-006 (fail-open),
    27 | #   ATK-007 (prompt injection via file path)
    28 | # Sprint-108 T4.4: Dual-mode (authoritative + heuristic)
    29 | # Sprint-108 T4.5: Path normalization
    30 | # =============================================================================
    31 | 
    32 | # Read tool input from stdin
    33 | input=$(cat 2>/dev/null) || input=""
    34 | 
>   35 | PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
    36 | RUN_DIR="${RUN_DIR:-$PROJECT_ROOT/.run}"
    37 | FEATURES_FILE="$RUN_DIR/platform-features.json"
    38 | 
    39 | # Evidence recorder: lead session only (no teammate role, no subagent agent_id), once, atomic.
    40 | if [[ -z "${LOA_TEAM_MEMBER:-}" && -d "$RUN_DIR" ]] \
    41 |     && jq -e '(.tool_input.active_skill // "") != "" and (.agent_id // "") == ""' <<<"$input" >/dev/null 2>&1 \
    42 |     && ! jq -e '.active_skill_seen_at' "$FEATURES_FILE" >/dev/null 2>&1; then
    43 |     _ig_base=$(jq -c 'select(type == "object")' "$FEATURES_FILE" 2>/dev/null | tail -n 1)
    44 |     _ig_tmp=$(mktemp "$RUN_DIR/.platform-features.XXXXXX" 2>/dev/null) && {
    45 |         jq -nc --argjson b "${_ig_base:-{\}}" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    46 |             '$b + {active_skill_available: false, active_skill_seen_at: $ts, active_skill_source: "tool_input"}' > "$_ig_tmp" 2>/dev/null \
    47 |             && mv -f "$_ig_tmp" "$FEATURES_FILE" 2>/dev/null
~~~~

The change from head to the fix:

~~~~diff
@@ -35 +64,76 @@
-PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
+# The ask reply; jq builds it so any reason is a well-formed JSON string (run-3 finding 7); the printf literal is only
+# for the jq-missing branch, whose reason is a fixed string
+emit_ask() {
+    if command -v jq &>/dev/null; then
+        jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'
+    else
+        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$1"
+    fi
+}
+
+# Byte sequences strip_controls removes: UTF-8 C1 controls (C2 80..C2 9F) and the format/bidi code points
+# U+200B-U+200F, U+2028-U+202E, U+2060-U+2064, U+2066-U+206F, U+FEFF, U+00AD, U+061C, U+180E, U+FE00-U+FE0F,
+# U+FFF9-U+FFFB and the tag characters U+E0001, U+E0020-U+E007F (run-3 finding 5); each sequence starts with a lead
+# byte, so a byte-wise match never lands inside another character; printf -v keeps this portable (no GNU-sed \x)
+_IG_STRIP_SEQS=()
+for (( _ig_i = 128; _ig_i < 160; _ig_i++ )); do
+    printf -v _ig_hex '%02x' "$_ig_i"; printf -v _ig_seq "\\xc2\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
+done
+for _ig_hex in 8b 8c 8d 8e 8f a8 a9 aa ab ac ad ae; do
+    printf -v _ig_seq "\\xe2\\x80\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
+done
+for _ig_hex in a0 a1 a2 a3 a4 a6 a7 a8 a9 aa ab ac ad ae af; do
+    printf -v _ig_seq "\\xe2\\x81\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
+done
+for _ig_seq in '\xef\xbb\xbf' '\xc2\xad' '\xd8\x9c' '\xe1\xa0\x8e' '\xef\xbf\xb9' '\xef\xbf\xba' '\xef\xbf\xbb' '\xf3\xa0\x80\x81'; do
+    printf -v _ig_seq "$_ig_seq"; _IG_STRIP_SEQS+=("$_ig_seq")
+done
+for (( _ig_i = 128; _ig_i < 144; _ig_i++ )); do   # U+FE00-U+FE0F = EF B8 80..EF B8 8F
+    printf -v _ig_hex '%02x' "$_ig_i"; printf -v _ig_seq "\\xef\\xb8\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
+done
+for (( _ig_i = 160; _ig_i < 192; _ig_i++ )); do   # U+E0020-U+E003F = F3 A0 80 A0..F3 A0 80 BF
+    printf -v _ig_hex '%02x' "$_ig_i"; printf -v _ig_seq "\\xf3\\xa0\\x80\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
+done
+for (( _ig_i = 128; _ig_i < 192; _ig_i++ )); do   # U+E0040-U+E007F = F3 A0 81 80..F3 A0 81 BF
+    printf -v _ig_hex '%02x' "$_ig_i"; printf -v _ig_seq "\\xf3\\xa0\\x81\\x${_ig_hex}"; _IG_STRIP_SEQS+=("$_ig_seq")
+done
+
+# Sets the variable named $1 to at most 256 bytes of $2, never ending inside a UTF-8 character: a trailing lead byte
+# whose sequence the cut left short, or stray continuation bytes, are dropped (run-3 finding 5; jq would read a split
+# character as U+FFFD). printf -v, not $(...), so a trailing newline in a raw value survives into the audit row
+cut_utf8_256() {
+    local LC_ALL=C
+    local _c_s=${2:0:256} _c_n _c_i _c_b _c_need
+    _c_n=${#_c_s}
+    for (( _c_i = _c_n - 1; _c_i >= 0 && _c_i >= _c_n - 4; _c_i-- )); do
+        printf -v _c_b '%d' "'${_c_s:_c_i:1}"
+        (( _c_b >= 128 && _c_b < 192 )) && continue   # continuation byte: keep walking back to its lead
+        if (( _c_b < 128 )); then _c_need=1; elif (( _c_b < 224 )); then _c_need=2; elif (( _c_b < 240 )); then _c_need=3; else _c_need=4; fi
+        if (( _c_n - _c_i < _c_need )); then _c_s=${_c_s:0:_c_i}          # the cut left this character short
+        elif (( _c_n - _c_i > _c_need )); then _c_s=${_c_s:0:_c_i+_c_need}   # continuation bytes after a complete character are stray
+        fi
+        printf -v "$1" '%s' "$_c_s"
+        return 0
+    done
+    printf -v "$1" '%s' "${_c_s:0:_c_i+1}"   # only continuation bytes at the end: drop them
+}
+
+# Display copy of a model-authored string: cut to 256 bytes first (the fixed point below then costs at most a few
+# passes over a short string), then C0 and DEL, then the sequences above byte-wise until nothing changes (deleting
+# one sequence can join its neighbours into another: C2 C2 9B 9B)
+strip_controls() {
+    local LC_ALL=C s prev seq
+    cut_utf8_256 s "$1"
+    s=$(printf '%s' "$s" | tr -d '\000-\037\177')
+    while :; do
+        prev=$s
+        for seq in "${_IG_STRIP_SEQS[@]}"; do s=${s//"$seq"/}; done
+        [[ "$s" == "$prev" ]] && break
+    done
+    printf '%s' "$s"
+}
+
+# The root never follows the process cwd, which follows Claude's `cd` (sprint-250 audit MED-001): PROJECT_ROOT, then
+# the harness's CLAUDE_PROJECT_DIR (it stays at the session's project root), then this script's own location
+# (<root>/.claude/hooks/compliance/)
+PROJECT_ROOT="${PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)}}"
~~~~

## H10 — .claude/hooks/compliance/implement-gate.sh — head lines 52–55

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 40–67):

~~~~text
    40 | if [[ -z "${LOA_TEAM_MEMBER:-}" && -d "$RUN_DIR" ]] \
    41 |     && jq -e '(.tool_input.active_skill // "") != "" and (.agent_id // "") == ""' <<<"$input" >/dev/null 2>&1 \
    42 |     && ! jq -e '.active_skill_seen_at' "$FEATURES_FILE" >/dev/null 2>&1; then
    43 |     _ig_base=$(jq -c 'select(type == "object")' "$FEATURES_FILE" 2>/dev/null | tail -n 1)
    44 |     _ig_tmp=$(mktemp "$RUN_DIR/.platform-features.XXXXXX" 2>/dev/null) && {
    45 |         jq -nc --argjson b "${_ig_base:-{\}}" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    46 |             '$b + {active_skill_available: false, active_skill_seen_at: $ts, active_skill_source: "tool_input"}' > "$_ig_tmp" 2>/dev/null \
    47 |             && mv -f "$_ig_tmp" "$FEATURES_FILE" 2>/dev/null
    48 |         rm -f "$_ig_tmp" 2>/dev/null
    49 |     }
    50 | fi
    51 | 
>   52 | # Extract file path from tool input (Write or Edit)
>   53 | file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || file_path=""
>   54 | 
>   55 | # If we can't determine the file path, allow (can't evaluate)
    56 | if [[ -z "$file_path" ]]; then
    57 |     exit 0
    58 | fi
    59 | 
    60 | # ---------------------------------------------------------------------------
    61 | # Source compat-lib.sh for _date_to_epoch()
    62 | # ---------------------------------------------------------------------------
    63 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || SCRIPT_DIR=""
    64 | COMPAT_LIB="${SCRIPT_DIR}/../../scripts/compat-lib.sh"
    65 | # shellcheck source=../../scripts/compat-lib.sh
    66 | source "$COMPAT_LIB" 2>/dev/null || true
    67 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -52,4 +156,17 @@
-# Extract file path from tool input (Write or Edit)
-file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || file_path=""
+# No jq, or a payload jq cannot parse: the write cannot be evaluated, so ask (run-2 finding 5)
+if ! command -v jq &>/dev/null || ! jq -e . <<<"$input" >/dev/null 2>&1; then
+    echo "[GATE] could not evaluate tool_input (jq missing or payload unparsable)." >&2
+    emit_ask "[GATE] could not evaluate tool_input. Verify this write is intentional."
+    exit 0
+fi
 
-# If we can't determine the file path, allow (can't evaluate)
+# Extract the path: Write/Edit/MultiEdit carry file_path, NotebookEdit carries notebook_path. jq -j plus a sentinel
+# byte keeps a trailing newline, which $(...) would otherwise strip from the raw value (run-3 finding 4)
+if ! file_path=$(jq -j '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input" 2>/dev/null && printf x); then
+    echo "[GATE] could not evaluate tool_input (path not readable)." >&2
+    emit_ask "[GATE] could not evaluate tool_input. Verify this write is intentional."
+    exit 0
+fi
+file_path=${file_path%x}
+
+# A parsed payload without a path is not a file write the gate can classify: allow
~~~~

## H11 — .claude/hooks/compliance/implement-gate.sh — head lines 69–103

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 57–115):

~~~~text
    57 |     exit 0
    58 | fi
    59 | 
    60 | # ---------------------------------------------------------------------------
    61 | # Source compat-lib.sh for _date_to_epoch()
    62 | # ---------------------------------------------------------------------------
    63 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null)" || SCRIPT_DIR=""
    64 | COMPAT_LIB="${SCRIPT_DIR}/../../scripts/compat-lib.sh"
    65 | # shellcheck source=../../scripts/compat-lib.sh
    66 | source "$COMPAT_LIB" 2>/dev/null || true
    67 | 
    68 | # ---------------------------------------------------------------------------
>   69 | # T4.5: Path normalization — resolve file_path relative to PROJECT_ROOT
>   70 | # Prevents false positives from parent directory names
>   71 | # (e.g., /home/user/src-projects/loa/grimoires/file.md should NOT match src/*)
>   72 | # ---------------------------------------------------------------------------
>   73 | normalized_path="$file_path"
>   74 | 
>   75 | # If file_path starts with PROJECT_ROOT, strip the prefix to get relative path
>   76 | if [[ "$file_path" == "$PROJECT_ROOT/"* ]]; then
>   77 |     normalized_path="${file_path#"$PROJECT_ROOT"/}"
>   78 | elif [[ "$file_path" == /* ]]; then
>   79 |     # Absolute path that doesn't start with PROJECT_ROOT — use as-is
>   80 |     # but don't match against App Zone patterns (could be false positive)
>   81 |     normalized_path="$file_path"
>   82 | fi
>   83 | 
>   84 | # ---------------------------------------------------------------------------
>   85 | # Zone check: Is this an App Zone write?
>   86 | # App Zone: src/, lib/, app/ (relative paths only after normalization)
>   87 | # ---------------------------------------------------------------------------
>   88 | is_app_zone=false
>   89 | case "$normalized_path" in
>   90 |     src/*|lib/*|app/*)
>   91 |         is_app_zone=true
>   92 |         ;;
>   93 | esac
>   94 | 
>   95 | # Only match */src/* etc. if path is relative (no leading /)
>   96 | # This prevents /home/user/src-projects/loa/grimoires from matching
>   97 | if [[ "$is_app_zone" == "false" && "$normalized_path" != /* ]]; then
>   98 |     case "$normalized_path" in
>   99 |         */src/*|*/lib/*|*/app/*)
>  100 |             is_app_zone=true
>  101 |             ;;
>  102 |     esac
>  103 | fi
   104 | 
   105 | # Non-App-Zone writes always allowed
   106 | if [[ "$is_app_zone" == "false" ]]; then
   107 |     exit 0
   108 | fi
   109 | 
   110 | # ---------------------------------------------------------------------------
   111 | # Mode: heuristic unless the operator opts in through .loa.config.yaml (cycle-126 D-4.4)
   112 | # ---------------------------------------------------------------------------
   113 | compliance_mode="heuristic"
   114 | if command -v yq &>/dev/null && [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
   115 |     configured_mode=$(yq '.implement_gate.mode // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null) || configured_mode=""
~~~~

The change from head to the fix:

~~~~diff
@@ -69,35 +186,104 @@
-# T4.5: Path normalization — resolve file_path relative to PROJECT_ROOT
-# Prevents false positives from parent directory names
-# (e.g., /home/user/src-projects/loa/grimoires/file.md should NOT match src/*)
+# T4.5: Path normalization — canonicalise both sides, then take file_path
+# relative to the project root (run-2 finding 1). A textual prefix test let
+# /proc/self/cwd/src/x, //ROOT/src/x, ROOT/../<name>/src/x or a symlinked root
+# reach an App-Zone file unseen. Two forms are tested and either one matching
+# counts (run-3 finding 1): the PHYSICAL form follows symlinks (realpath -m,
+# else readlink -f) against pwd -P of the root; the LOGICAL form keeps them
+# (realpath -m -s, else a pure-bash ./../// normaliser) against pwd -L, so a
+# src/ that is itself a symlink out of the root still asks. A relative path
+# resolves from the payload's cwd when it carries one (the harness resolves it
+# there and cwd follows `cd` in the Bash tool), else from PROJECT_ROOT (run-3
+# finding 6). Only the part under the root is matched, so parent directory
+# names never count (e.g., /home/user/src-projects/loa/grimoires/file.md is not src/*).
 # ---------------------------------------------------------------------------
-normalized_path="$file_path"
+# Lexical normaliser for an absolute path: drops empty and . components, resolves .. textually, follows no symlink
+_ig_lexical_norm() {
+    local rest=$1 part
+    local -a out=()
+    while [[ -n "$rest" ]]; do
+        part=${rest%%/*}
+        if [[ "$rest" == */* ]]; then rest=${rest#*/}; else rest=""; fi
+        case "$part" in
+            ''|.) ;;
+            ..) (( ${#out[@]} )) && unset 'out[${#out[@]}-1]' ;;
+            *) out+=("$part") ;;
+        esac
+    done
+    local IFS=/
+    printf '/%s' "${out[*]}"
+}
 
-# If file_path starts with PROJECT_ROOT, strip the prefix to get relative path
-if [[ "$file_path" == "$PROJECT_ROOT/"* ]]; then
-    normalized_path="${file_path#"$PROJECT_ROOT"/}"
-elif [[ "$file_path" == /* ]]; then
-    # Absolute path that doesn't start with PROJECT_ROOT — use as-is
-    # but don't match against App Zone patterns (could be false positive)
-    normalized_path="$file_path"
+# $1 relative to the root $2, or failure when $1 is not under $2
+_ig_under_root() {
+    [[ "$1" == "${2%/}/"* ]] || return 1
+    printf '%s' "${1#"${2%/}"/}"
+}
+
+canonical_root=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P) || canonical_root=""
+logical_root=$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -L) || logical_root=""
+payload_cwd=$(jq -r '.cwd // empty | strings' <<<"$input" 2>/dev/null) || payload_cwd=""
+if [[ "$file_path" == /* ]]; then
+    abs_path=$file_path
+else
+    base_dir=${payload_cwd:-$logical_root}
+    [[ "$base_dir" == /* ]] || base_dir="$logical_root/$base_dir"
+    abs_path="${base_dir%/}/$file_path"
 fi
+canonical_path=""
+logical_path=""
+if [[ -n "$canonical_root" && -n "$logical_root" ]]; then
+    # GNU realpath -m first (no component needs to exist), then readlink -f
+    canonical_path=$(cd "$PROJECT_ROOT" 2>/dev/null \
+        && { realpath -m -- "$abs_path" 2>/dev/null || readlink -f -- "$abs_path" 2>/dev/null; }) || canonical_path=""
+    logical_path=$(realpath -m -s -- "$abs_path" 2>/dev/null) || logical_path=""
+    [[ "$logical_path" == /* ]] || logical_path=$(_ig_lexical_norm "$abs_path")
+fi
+if [[ -z "$canonical_root" || -z "$canonical_path" ]]; then
+    echo "[GATE] could not canonicalise tool_input.file_path; asking." >&2
+    emit_ask "[GATE] could not canonicalise tool_input.file_path. Verify this write is intentional."
+    exit 0
+fi
+
+# The root-relative forms, lowercased: on a case-insensitive filesystem (macOS default, ext4 casefold) Src/ is src/,
+# and on a case-sensitive one this only adds asks for a directory literally named Src/ — tighten-only (run-3 finding 2)
+rel_forms=()
+if rel=$(_ig_under_root "$canonical_path" "$canonical_root"); then rel_forms+=("${rel,,}"); fi
+if rel=$(_ig_under_root "$logical_path" "$logical_root"); then rel_forms+=("${rel,,}"); fi
+
+# Audit-row copy of a model-authored value: raw, cut to 256 bytes on a character boundary; jq -a escapes the rest
+cut_utf8_256 audit_file_path "$file_path"
+
+# ---------------------------------------------------------------------------
+# Trust inputs (run-3 finding 3): the files this gate and the run state read are
+# writable through the same tool, so a write to one asks and leaves one
+# compliance.state_write row — evaluated before the App-Zone test, since they
+# are not App Zone. Everything else under .run/ and grimoires/ stays allow.
+# ---------------------------------------------------------------------------
+for rel in "${rel_forms[@]}"; do
+    case "$rel" in
+        .run/state.json|.run/sprint-plan-state.json|.run/simstim-state.json|.run/platform-features.json|.run/audit.jsonl|.loa.config.yaml)
+            echo "[GATE] write to an implement-gate trust input '$(strip_controls "$file_path")'." >&2
+            jq -nca \
+                --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
+                --arg path "$audit_file_path" \
+                '{timestamp: $ts, event: "compliance.state_write", file_path: $path}' \
+                >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
+            emit_ask "[GATE] write to an implement-gate trust input. Verify this write is intentional."
+            exit 0
+            ;;
+    esac
+done
 
 # ---------------------------------------------------------------------------
 # Zone check: Is this an App Zone write?
-# App Zone: src/, lib/, app/ (relative paths only after normalization)
+# App Zone: src/, lib/, app/ in either root-relative form; a path whose two
+# forms both fall outside the root is not App Zone
 # ---------------------------------------------------------------------------
 is_app_zone=false
-case "$normalized_path" in
-    src/*|lib/*|app/*)
-        is_app_zone=true
-        ;;
-esac
-
-# Only match */src/* etc. if path is relative (no leading /)
-# This prevents /home/user/src-projects/loa/grimoires from matching
-if [[ "$is_app_zone" == "false" && "$normalized_path" != /* ]]; then
+for normalized_path in "${rel_forms[@]}"; do
     case "$normalized_path" in
-        */src/*|*/lib/*|*/app/*)
+        src/*|lib/*|app/*|*/src/*|*/lib/*|*/app/*)
             is_app_zone=true
             ;;
     esac
-fi
+done
~~~~

## H12 — .claude/hooks/compliance/implement-gate.sh — insertion after head line 109

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 98–121):

~~~~text
    98 |     case "$normalized_path" in
    99 |         */src/*|*/lib/*|*/app/*)
   100 |             is_app_zone=true
   101 |             ;;
   102 |     esac
   103 | fi
   104 | 
   105 | # Non-App-Zone writes always allowed
   106 | if [[ "$is_app_zone" == "false" ]]; then
   107 |     exit 0
   108 | fi
   109 | 
   110 | # ---------------------------------------------------------------------------
   111 | # Mode: heuristic unless the operator opts in through .loa.config.yaml (cycle-126 D-4.4)
   112 | # ---------------------------------------------------------------------------
   113 | compliance_mode="heuristic"
   114 | if command -v yq &>/dev/null && [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
   115 |     configured_mode=$(yq '.implement_gate.mode // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null) || configured_mode=""
   116 |     [[ "${configured_mode//\"/}" == "authoritative" ]] && compliance_mode="authoritative"
   117 | fi
   118 | 
   119 | # ---------------------------------------------------------------------------
   120 | # Authoritative mode: read active_skill from hook input
   121 | # ---------------------------------------------------------------------------
~~~~

The change from head to the fix:

~~~~diff
@@ -109,0 +296,3 @@
+# Display copy only: control and format characters never reach stderr (n21, run-2 finding 3)
+safe_file_path=$(strip_controls "$file_path")
+
~~~~

## H13 — .claude/hooks/compliance/implement-gate.sh — head lines 123–152

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 111–164):

~~~~text
   111 | # Mode: heuristic unless the operator opts in through .loa.config.yaml (cycle-126 D-4.4)
   112 | # ---------------------------------------------------------------------------
   113 | compliance_mode="heuristic"
   114 | if command -v yq &>/dev/null && [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
   115 |     configured_mode=$(yq '.implement_gate.mode // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null) || configured_mode=""
   116 |     [[ "${configured_mode//\"/}" == "authoritative" ]] && compliance_mode="authoritative"
   117 | fi
   118 | 
   119 | # ---------------------------------------------------------------------------
   120 | # Authoritative mode: read active_skill from hook input
   121 | # ---------------------------------------------------------------------------
   122 | if [[ "$compliance_mode" == "authoritative" ]]; then
>  123 |     active_skill=$(echo "$input" | jq -r '.tool_input.active_skill // empty' 2>/dev/null) || active_skill=""
>  124 | 
>  125 |     if [[ -n "$active_skill" ]]; then
>  126 |         # Allow implementation skills
>  127 |         case "$active_skill" in
>  128 |             implement|/implement|bug|/bug|run|/run|simstim|/simstim)
>  129 |                 exit 0
>  130 |                 ;;
>  131 |         esac
>  132 | 
>  133 |         # Non-implementation skill — ask
>  134 |         echo "[AUTHORITATIVE] App Zone write to '$file_path' detected during /$active_skill (not an implementation skill)." >&2
>  135 |         echo '{"decision":"ask","reason":"[AUTHORITATIVE] App Zone write outside implementation skill. Verify this is intentional."}'
>  136 |         exit 0
>  137 |     fi
>  138 | 
>  139 |     # active_skill field absent despite authoritative mode — fall back to heuristic
>  140 |     # Log the downgrade
>  141 |     log_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || log_ts="unknown"
>  142 |     if command -v jq &>/dev/null; then
>  143 |         jq -nc \
>  144 |             --arg ts "$log_ts" \
>  145 |             --arg from "authoritative" \
>  146 |             --arg to "heuristic" \
>  147 |             --arg reason "active_skill field absent in hook input" \
>  148 |             '{timestamp: $ts, event: "compliance.mode.fallback", from_mode: $from, to_mode: $to, reason: $reason}' \
>  149 |             >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
>  150 |     else
>  151 |         echo "{\"timestamp\":\"$log_ts\",\"event\":\"compliance.mode.fallback\",\"from_mode\":\"authoritative\",\"to_mode\":\"heuristic\",\"reason\":\"active_skill field absent in hook input\"}" \
>  152 |             >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
   153 |     fi
   154 |     # Fall through to heuristic check below
   155 | fi
   156 | 
   157 | # ---------------------------------------------------------------------------
   158 | # Heuristic mode: Is an /implement or /bug skill currently active?
   159 | # Check .run/sprint-plan-state.json, .run/simstim-state.json, .run/state.json
   160 | # ---------------------------------------------------------------------------
   161 | check_implementation_active() {
   162 |     # Check sprint-plan state
   163 |     if [[ -f "$RUN_DIR/sprint-plan-state.json" ]]; then
   164 |         local state plan_id last_activity
~~~~

The change from head to the fix:

~~~~diff
@@ -123,30 +312,47 @@
-    active_skill=$(echo "$input" | jq -r '.tool_input.active_skill // empty' 2>/dev/null) || active_skill=""
+    active_skill=$(jq -j '.tool_input.active_skill // empty' <<<"$input" 2>/dev/null && printf x) || active_skill="x"
+    active_skill=${active_skill%x}
 
     if [[ -n "$active_skill" ]]; then
-        # Allow implementation skills
+        safe_skill=$(strip_controls "$active_skill")
+        cut_utf8_256 audit_skill "$active_skill"
+        # One model_signal row per invocation that carries a claim; the harness never sets the field,
+        # so a row means a model wrote it (run-2 finding 6). The row holds the raw claim, ASCII-escaped (run-3 finding 4)
+        log_model_signal() {
+            jq -nca \
+                --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" \
+                --arg skill "$audit_skill" \
+                --arg path "$audit_file_path" \
+                --arg decision "$1" \
+                '{timestamp: $ts, event: "compliance.mode.model_signal", mode: "authoritative", active_skill: $skill, file_path: $path, decision: $decision}' \
+                >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
+        }
         case "$active_skill" in
             implement|/implement|bug|/bug|run|/run|simstim|/simstim)
+                # Tighten-only (n17/n18): a model-authored implementation claim never
+                # allows by itself — log it, then fall through to the heuristic check below
+                log_model_signal heuristic
+                ;;
+            *)
+                # Non-implementation skill — log the model signal and ask
+                echo "[AUTHORITATIVE] App Zone write to '$safe_file_path' detected during /$safe_skill (not an implementation skill)." >&2
+                log_model_signal ask
+                emit_ask "[AUTHORITATIVE] App Zone write outside implementation skill. Verify this is intentional."
                 exit 0
                 ;;
         esac
-
-        # Non-implementation skill — ask
-        echo "[AUTHORITATIVE] App Zone write to '$file_path' detected during /$active_skill (not an implementation skill)." >&2
-        echo '{"decision":"ask","reason":"[AUTHORITATIVE] App Zone write outside implementation skill. Verify this is intentional."}'
-        exit 0
-    fi
-
-    # active_skill field absent despite authoritative mode — fall back to heuristic
-    # Log the downgrade
-    log_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || log_ts="unknown"
-    if command -v jq &>/dev/null; then
-        jq -nc \
-            --arg ts "$log_ts" \
-            --arg from "authoritative" \
-            --arg to "heuristic" \
-            --arg reason "active_skill field absent in hook input" \
-            '{timestamp: $ts, event: "compliance.mode.fallback", from_mode: $from, to_mode: $to, reason: $reason}' \
-            >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
     else
-        echo "{\"timestamp\":\"$log_ts\",\"event\":\"compliance.mode.fallback\",\"from_mode\":\"authoritative\",\"to_mode\":\"heuristic\",\"reason\":\"active_skill field absent in hook input\"}" \
-            >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
+        # active_skill field absent despite authoritative mode — fall back to heuristic
+        # Log the downgrade
+        log_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || log_ts="unknown"
+        if command -v jq &>/dev/null; then
+            jq -nc \
+                --arg ts "$log_ts" \
+                --arg from "authoritative" \
+                --arg to "heuristic" \
+                --arg reason "active_skill field absent in hook input" \
+                '{timestamp: $ts, event: "compliance.mode.fallback", from_mode: $from, to_mode: $to, reason: $reason}' \
+                >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
+        else
+            echo "{\"timestamp\":\"$log_ts\",\"event\":\"compliance.mode.fallback\",\"from_mode\":\"authoritative\",\"to_mode\":\"heuristic\",\"reason\":\"active_skill field absent in hook input\"}" \
+                >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
+        fi
~~~~

## H14 — .claude/hooks/compliance/implement-gate.sh — insertion after head line 160

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 149–172):

~~~~text
   149 |             >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
   150 |     else
   151 |         echo "{\"timestamp\":\"$log_ts\",\"event\":\"compliance.mode.fallback\",\"from_mode\":\"authoritative\",\"to_mode\":\"heuristic\",\"reason\":\"active_skill field absent in hook input\"}" \
   152 |             >> "$RUN_DIR/audit.jsonl" 2>/dev/null || true
   153 |     fi
   154 |     # Fall through to heuristic check below
   155 | fi
   156 | 
   157 | # ---------------------------------------------------------------------------
   158 | # Heuristic mode: Is an /implement or /bug skill currently active?
   159 | # Check .run/sprint-plan-state.json, .run/simstim-state.json, .run/state.json
   160 | # ---------------------------------------------------------------------------
   161 | check_implementation_active() {
   162 |     # Check sprint-plan state
   163 |     if [[ -f "$RUN_DIR/sprint-plan-state.json" ]]; then
   164 |         local state plan_id last_activity
   165 |         state=$(jq -r '.state // empty' "$RUN_DIR/sprint-plan-state.json" 2>/dev/null) || return 1
   166 |         plan_id=$(jq -r '.plan_id // empty' "$RUN_DIR/sprint-plan-state.json" 2>/dev/null) || true
   167 | 
   168 |         # Integrity: must have plan_id
   169 |         if [[ -z "$plan_id" ]]; then
   170 |             return 1
   171 |         fi
   172 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -160,0 +367,15 @@
+# True when the ISO-8601 timestamp $1 parses and is at most 24 h (86400 s) old; empty or unparsable is stale
+# (sprint-250 audit LOW-004: tighten-only)
+_ig_fresh() {
+    [[ -n "$1" ]] || return 1
+    local now last_epoch
+    now=$(date +%s 2>/dev/null) || return 1
+    if type _date_to_epoch &>/dev/null; then
+        last_epoch=$(_date_to_epoch "$1" 2>/dev/null) || last_epoch=""
+    else
+        last_epoch=$(date -d "$1" +%s 2>/dev/null || date -jf '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null) || last_epoch=""
+    fi
+    [[ "$last_epoch" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] || return 1
+    (( last_epoch > 0 && now - last_epoch <= 86400 ))
+}
+
~~~~

## H15 — .claude/hooks/compliance/implement-gate.sh — head lines 199–203

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 187–215):

~~~~text
   187 |                 local age=$((now - last_epoch))
   188 |                 if [[ $age -gt 86400 ]]; then
   189 |                     return 1  # Stale state (>24h)
   190 |                 fi
   191 |             fi
   192 |         fi
   193 | 
   194 |         if [[ "$state" == "RUNNING" ]]; then
   195 |             return 0
   196 |         fi
   197 |     fi
   198 | 
>  199 |     # Check simstim state
>  200 |     if [[ -f "$RUN_DIR/simstim-state.json" ]]; then
>  201 |         local phase
>  202 |         phase=$(jq -r '.phase // empty' "$RUN_DIR/simstim-state.json" 2>/dev/null) || return 1
>  203 |         if [[ "$phase" == "implementation" ]]; then
   204 |             return 0
   205 |         fi
   206 |     fi
   207 | 
   208 |     # Check run state
   209 |     if [[ -f "$RUN_DIR/state.json" ]]; then
   210 |         local run_state
   211 |         run_state=$(jq -r '.state // empty' "$RUN_DIR/state.json" 2>/dev/null) || return 1
   212 |         if [[ "$run_state" == "RUNNING" ]]; then
   213 |             return 0
   214 |         fi
   215 |     fi
~~~~

The change from head to the fix:

~~~~diff
@@ -199,5 +420,7 @@
-    # Check simstim state
+    # Check simstim state; its writers (simstim-state.sh, simstim-orchestrator.sh) stamp .timestamps.last_activity,
+    # and a stale or unstamped file falls through (LOW-004)
     if [[ -f "$RUN_DIR/simstim-state.json" ]]; then
-        local phase
+        local phase simstim_activity
         phase=$(jq -r '.phase // empty' "$RUN_DIR/simstim-state.json" 2>/dev/null) || return 1
-        if [[ "$phase" == "implementation" ]]; then
+        simstim_activity=$(jq -r '.timestamps.last_activity // empty | strings' "$RUN_DIR/simstim-state.json" 2>/dev/null) || simstim_activity=""
+        if [[ "$phase" == "implementation" ]] && _ig_fresh "$simstim_activity"; then
~~~~

## H16 — .claude/hooks/compliance/implement-gate.sh — head lines 208–212

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 196–224):

~~~~text
   196 |         fi
   197 |     fi
   198 | 
   199 |     # Check simstim state
   200 |     if [[ -f "$RUN_DIR/simstim-state.json" ]]; then
   201 |         local phase
   202 |         phase=$(jq -r '.phase // empty' "$RUN_DIR/simstim-state.json" 2>/dev/null) || return 1
   203 |         if [[ "$phase" == "implementation" ]]; then
   204 |             return 0
   205 |         fi
   206 |     fi
   207 | 
>  208 |     # Check run state
>  209 |     if [[ -f "$RUN_DIR/state.json" ]]; then
>  210 |         local run_state
>  211 |         run_state=$(jq -r '.state // empty' "$RUN_DIR/state.json" 2>/dev/null) || return 1
>  212 |         if [[ "$run_state" == "RUNNING" ]]; then
   213 |             return 0
   214 |         fi
   215 |     fi
   216 | 
   217 |     return 1
   218 | }
   219 | 
   220 | # ---------------------------------------------------------------------------
   221 | # Decision: allow or ask
   222 | # ---------------------------------------------------------------------------
   223 | if check_implementation_active; then
   224 |     # Implementation is active — allow the write
~~~~

The change from head to the fix:

~~~~diff
@@ -208,5 +431,7 @@
-    # Check run state
+    # Check run state; run-mode stamps .timestamps.last_activity (state-schemas.md), .updated_at is the fallback
+    # run-preflight.sh reads too; a stale or unstamped file falls through (LOW-004)
     if [[ -f "$RUN_DIR/state.json" ]]; then
-        local run_state
+        local run_state run_activity
         run_state=$(jq -r '.state // empty' "$RUN_DIR/state.json" 2>/dev/null) || return 1
-        if [[ "$run_state" == "RUNNING" ]]; then
+        run_activity=$(jq -r '.timestamps.last_activity // .updated_at // empty | strings' "$RUN_DIR/state.json" 2>/dev/null) || run_activity=""
+        if [[ "$run_state" == "RUNNING" ]] && _ig_fresh "$run_activity"; then
~~~~

## H17 — .claude/hooks/compliance/implement-gate.sh — head lines 228–230

Head context (head/.claude/hooks/compliance/implement-gate.sh, lines 216–232):

~~~~text
   216 | 
   217 |     return 1
   218 | }
   219 | 
   220 | # ---------------------------------------------------------------------------
   221 | # Decision: allow or ask
   222 | # ---------------------------------------------------------------------------
   223 | if check_implementation_active; then
   224 |     # Implementation is active — allow the write
   225 |     exit 0
   226 | else
   227 |     # No active implementation detected — ADVISORY ask
>  228 |     echo "[ADVISORY] App Zone write to '$file_path' detected outside active /implement or /bug." >&2
>  229 |     echo "No RUNNING state found in .run/ state files. This may bypass review gates." >&2
>  230 |     echo '{"decision":"ask","reason":"[ADVISORY] App Zone write outside active implementation. Verify this is intentional."}'
   231 |     exit 0
   232 | fi
~~~~

The change from head to the fix:

~~~~diff
@@ -228,3 +453,3 @@
-    echo "[ADVISORY] App Zone write to '$file_path' detected outside active /implement or /bug." >&2
+    echo "[ADVISORY] App Zone write to '$safe_file_path' detected outside active /implement or /bug." >&2
     echo "No RUNNING state found in .run/ state files. This may bypass review gates." >&2
-    echo '{"decision":"ask","reason":"[ADVISORY] App Zone write outside active implementation. Verify this is intentional."}'
+    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"[ADVISORY] App Zone write outside active implementation. Verify this is intentional."}}'
~~~~

## H18 — .claude/rules/skill-invariants.md — head line 29

Head context (head/.claude/rules/skill-invariants.md, lines 17–41):

~~~~text
    17 | | `Explore` | ✗ excluded | Read-only codebase analysis |
    18 | | `loa-scout`, `prompt-auditor`, `prompt-auditor-io` | ✗ excluded | Read-only project agents (`.claude/agents/`) |
    19 | | (unset) | inherited from caller | Default; safe for write-capable skills |
    20 | 
    21 | Source: Claude Code agent-type definitions in the system prompt, and `.claude/agents/*.md`.
    22 | 
    23 | ## Enforcement
    24 | 
    25 | `.claude/scripts/validate-skill-capabilities.sh` checks this invariant on every SKILL.md. A violation exits with code 1 and message:
    26 | 
    27 | > agent type '<name>' excludes Write/Edit tools but skill declares write capability …
    28 | 
>   29 | The allowlist is maintained in `.claude/data/agent-types.yaml` (one `write_capable` flag per agent type); the script loads the `true` entries into `WRITE_CAPABLE_AGENTS` and falls back to `general-purpose` alone when the file is missing or unparsable. Adding a new write-capable agent type is intentionally a one-line edit with reviewer visibility.
    30 | 
    31 | ## Mechanical C-PROC-001 enforcement via `disallowed-tools` (cycle-114 FR-4)
    32 | 
    33 | `disallowed-tools` frontmatter (Claude Code ≥2.1.152) removes tools from the
    34 | model while a skill is active — a harness-level barrier that instructions
    35 | cannot override. Cycle-114 uses it to make C-PROC-001 ("NEVER write application
    36 | code outside `/implement`") mechanical for review skills rather than prose-only.
    37 | 
    38 | | Skill class | `disallowed-tools` | Why |
    39 | |-------------|--------------------|-----|
    40 | | Pure-review (`write_files: false`, no report artifacts) | `Write`, `Edit`, `NotebookEdit` | Never writes anything — remove the write tools outright |
    41 | | Sprint review/audit (`reviewing-code`, `auditing-security`; `write_files: true`) | `NotebookEdit` | Write STATE-zone feedback/checkmarks/COMPLETED markers, run the allowed verdict check and run `adversarial-review.sh` (forks the provider CLIs, appends the `.run` cost and MODELINV ledgers, moves the previous round's a2a envelope aside as `.prev`, writes the new one; review also runs `qmd-context-query.sh`); System remains `none` and App remains `read` |
~~~~

The change from head to the fix:

~~~~diff
@@ -29 +29 @@
-The allowlist is maintained in `.claude/data/agent-types.yaml` (one `write_capable` flag per agent type); the script loads the `true` entries into `WRITE_CAPABLE_AGENTS` and falls back to `general-purpose` alone when the file is missing or unparsable. Adding a new write-capable agent type is intentionally a one-line edit with reviewer visibility.
+The allowlist is maintained in `.claude/data/agent-types.yaml` (one `write_capable` flag per agent type); the script loads the `true` entries into `WRITE_CAPABLE_AGENTS` and falls back to `general-purpose` alone when the file is missing, unparsable, or lists no `write_capable: true` entry. Adding a new write-capable agent type is intentionally a one-line edit with reviewer visibility.
~~~~

## H19 — .claude/scripts/check-permissions.sh — head line 26

Head context (head/.claude/scripts/check-permissions.sh, lines 14–38):

~~~~text
    14 | #   whatever the allow lists say. Rules are read as JSON arrays (permissions.allow /
    15 | #   permissions.deny) — never as file text. A malformed file is skipped with a WARN
    16 | #   (it allows nothing and denies nothing). Managed/enterprise policy files are out of
    17 | #   scope (not readable by design).
    18 | #   Grammar (cycle-126 SDD D-4.5): a rule Bash(<body>) normalises to the key <body>
    19 | #   with surrounding whitespace trimmed and one trailing ":*" or " *" removed (a
    20 | #   wildcard rule); a body without one is an exact rule. Nothing else is rewritten
    21 | #   (no glob expansion, no quoting or inner-whitespace changes). A wildcard rule
    22 | #   covers a required rule when its key equals the requirement's key or the
    23 | #   requirement's first word, so Bash(git push *) and Bash(git:*) both cover
    24 | #   Bash(git push:*). The same test applies to allow and to deny: a narrower deny
    25 | #   such as Bash(rm -rf /:*) or an exact Bash(git push) does not deny the generic
>   26 | #   requirement.
    27 | #
    28 | # Usage:
    29 | #   check-permissions.sh                 Check all permissions (text report)
    30 | #   check-permissions.sh --json          Output as JSON (adds denied[] and settings_files[])
    31 | #   check-permissions.sh --quiet         Suppress output, exit code only
    32 | #   check-permissions.sh --root <dir>    Project root whose .claude/settings*.json to read
    33 | #                                        (default: the repository this script lives in)
    34 | #
    35 | # Exit codes:
    36 | #   0 - Every required permission is effective (allowed in some layer, denied in none)
    37 | #   1 - A required permission is missing or denied
    38 | #   2 - No settings file found in any layer (or usage error)
~~~~

The change from head to the fix:

~~~~diff
@@ -26 +26,4 @@
-#   requirement.
+#   requirement. A universal rule (bare Bash, Bash(*) after trimming, or the empty
+#   prefix Bash(:*)) covers every Bash requirement: a universal allow satisfies each
+#   one, a universal deny denies each one (sprint-250 review run 1, n29; Bash(:*)
+#   named here in sprint-250 review run 3).
~~~~

## H20 — .claude/scripts/check-permissions.sh — head line 159

Head context (head/.claude/scripts/check-permissions.sh, lines 147–171):

~~~~text
   147 |   fi
   148 | }
   149 | 
   150 | # warn — diagnostics that --quiet must also silence (Bridgebuilder PR #1270
   151 | # FIND-003: --quiet is "exit code only"); JSON mode keeps them on stderr.
   152 | warn() {
   153 |   if [[ "$QUIET" != "true" ]]; then
   154 |     echo "WARN: $*" >&2
   155 |   fi
   156 | }
   157 | 
   158 | # rule_key <rule> — sets RULE_KEY to "*<body>" for a wildcard rule, "=<body>" for
>  159 | # an exact one; returns 1 for anything that is not Bash(...). Pure parameter
   160 | # expansion: the checker runs on every preflight against hundreds of rules.
   161 | RULE_KEY=""
   162 | rule_key() {
   163 |   local b="$1"
   164 |   [[ "$b" == "Bash("*")" ]] || return 1
   165 |   b="${b#Bash(}"; b="${b%)}"
   166 |   b="${b#"${b%%[![:space:]]*}"}"; b="${b%"${b##*[![:space:]]}"}"
   167 |   if [[ "$b" == *":*" || "$b" == *" *" ]]; then
   168 |     b="${b%??}"; b="${b%"${b##*[![:space:]]}"}"
   169 |     RULE_KEY="*$b"
   170 |   else
   171 |     RULE_KEY="=$b"
~~~~

The change from head to the fix:

~~~~diff
@@ -159 +162,3 @@
-# an exact one; returns 1 for anything that is not Bash(...). Pure parameter
+# an exact one, "ALL" for a universal one (bare Bash, Bash(*), or the empty
+# prefix Bash(:*), which matches every command — sprint-250 review run 2, #9); returns 1 for
+# anything that is not Bash or Bash(...). Pure parameter
~~~~

## H21 — .claude/scripts/check-permissions.sh — head lines 164–169

Head context (head/.claude/scripts/check-permissions.sh, lines 152–181):

~~~~text
   152 | warn() {
   153 |   if [[ "$QUIET" != "true" ]]; then
   154 |     echo "WARN: $*" >&2
   155 |   fi
   156 | }
   157 | 
   158 | # rule_key <rule> — sets RULE_KEY to "*<body>" for a wildcard rule, "=<body>" for
   159 | # an exact one; returns 1 for anything that is not Bash(...). Pure parameter
   160 | # expansion: the checker runs on every preflight against hundreds of rules.
   161 | RULE_KEY=""
   162 | rule_key() {
   163 |   local b="$1"
>  164 |   [[ "$b" == "Bash("*")" ]] || return 1
>  165 |   b="${b#Bash(}"; b="${b%)}"
>  166 |   b="${b#"${b%%[![:space:]]*}"}"; b="${b%"${b##*[![:space:]]}"}"
>  167 |   if [[ "$b" == *":*" || "$b" == *" *" ]]; then
>  168 |     b="${b%??}"; b="${b%"${b##*[![:space:]]}"}"
>  169 |     RULE_KEY="*$b"
   170 |   else
   171 |     RULE_KEY="=$b"
   172 |   fi
   173 | }
   174 | 
   175 | # ============================================================================
   176 | # MAIN LOGIC
   177 | # ============================================================================
   178 | 
   179 | main() {
   180 |   local -a layers=() consulted=()
   181 |   layers=("${HOME:-/nonexistent}/.claude/settings.json" "$ROOT/.claude/settings.json" "$ROOT/.claude/settings.local.json")
~~~~

The change from head to the fix:

~~~~diff
@@ -164,6 +169,9 @@
+  if [[ "$b" == "Bash" ]]; then RULE_KEY="ALL"; return 0; fi
   [[ "$b" == "Bash("*")" ]] || return 1
   b="${b#Bash(}"; b="${b%)}"
   b="${b#"${b%%[![:space:]]*}"}"; b="${b%"${b##*[![:space:]]}"}"
-  if [[ "$b" == *":*" || "$b" == *" *" ]]; then
+  if [[ "$b" == "*" ]]; then
+    RULE_KEY="ALL"
+  elif [[ "$b" == *":*" || "$b" == *" *" ]]; then
     b="${b%??}"; b="${b%"${b##*[![:space:]]}"}"
-    RULE_KEY="*$b"
+    if [[ -z "$b" ]]; then RULE_KEY="ALL"; else RULE_KEY="*$b"; fi
~~~~

## H22 — .claude/scripts/check-permissions.sh — head lines 238–239

Head context (head/.claude/scripts/check-permissions.sh, lines 226–251):

~~~~text
   226 |     "${REQUIRED_GIT_PERMISSIONS[@]}"
   227 |     "${REQUIRED_GH_PERMISSIONS[@]}"
   228 |     "${REQUIRED_FILE_PERMISSIONS[@]}"
   229 |     "${REQUIRED_SHELL_PERMISSIONS[@]}"
   230 |   )
   231 | 
   232 |   local -a found_permissions=() missing_permissions=() denied_lines=()
   233 |   local perm key base file line
   234 |   for perm in "${all_required[@]}"; do
   235 |     rule_key "$perm"
   236 |     key="$RULE_KEY"
   237 |     base="*${key#\*}"; base="${base%% *}"
>  238 |     # deny wins: the requirement's own key or its base wildcard, in any layer
>  239 |     if [[ -n "${deny_by[$key]+x}" ]]; then
   240 |       denied_lines+=("$perm"$'\t'"${deny_raw[$key]}"$'\t'"${deny_by[$key]}")
   241 |       continue
   242 |     elif [[ -n "${deny_by[$base]+x}" ]]; then
   243 |       denied_lines+=("$perm"$'\t'"${deny_raw[$base]}"$'\t'"${deny_by[$base]}")
   244 |       continue
   245 |     fi
   246 |     if [[ -n "${allow_by[$key]+x}" || -n "${allow_by[$base]+x}" ]]; then
   247 |       found_permissions+=("$perm")
   248 |     else
   249 |       missing_permissions+=("$perm")
   250 |     fi
   251 |   done
~~~~

The change from head to the fix:

~~~~diff
@@ -238,2 +246,5 @@
-    # deny wins: the requirement's own key or its base wildcard, in any layer
-    if [[ -n "${deny_by[$key]+x}" ]]; then
+    # deny wins: a universal deny, the requirement's own key or its base wildcard, in any layer
+    if [[ -n "${deny_by[ALL]+x}" ]]; then
+      denied_lines+=("$perm"$'\t'"${deny_raw[ALL]}"$'\t'"${deny_by[ALL]}")
+      continue
+    elif [[ -n "${deny_by[$key]+x}" ]]; then
~~~~

## H23 — .claude/scripts/check-permissions.sh — head line 246

Head context (head/.claude/scripts/check-permissions.sh, lines 234–258):

~~~~text
   234 |   for perm in "${all_required[@]}"; do
   235 |     rule_key "$perm"
   236 |     key="$RULE_KEY"
   237 |     base="*${key#\*}"; base="${base%% *}"
   238 |     # deny wins: the requirement's own key or its base wildcard, in any layer
   239 |     if [[ -n "${deny_by[$key]+x}" ]]; then
   240 |       denied_lines+=("$perm"$'\t'"${deny_raw[$key]}"$'\t'"${deny_by[$key]}")
   241 |       continue
   242 |     elif [[ -n "${deny_by[$base]+x}" ]]; then
   243 |       denied_lines+=("$perm"$'\t'"${deny_raw[$base]}"$'\t'"${deny_by[$base]}")
   244 |       continue
   245 |     fi
>  246 |     if [[ -n "${allow_by[$key]+x}" || -n "${allow_by[$base]+x}" ]]; then
   247 |       found_permissions+=("$perm")
   248 |     else
   249 |       missing_permissions+=("$perm")
   250 |     fi
   251 |   done
   252 | 
   253 |   local total_required=${#all_required[@]}
   254 |   local total_found=${#found_permissions[@]}
   255 |   local total_missing=${#missing_permissions[@]}
   256 |   local total_denied=${#denied_lines[@]}
   257 | 
   258 |   if [[ "$OUTPUT_MODE" == "json" ]]; then
~~~~

The change from head to the fix:

~~~~diff
@@ -246 +257 @@
-    if [[ -n "${allow_by[$key]+x}" || -n "${allow_by[$base]+x}" ]]; then
+    if [[ -n "${allow_by[ALL]+x}" || -n "${allow_by[$key]+x}" || -n "${allow_by[$base]+x}" ]]; then
~~~~

## H24 — .claude/scripts/detect-platform-features.sh — insertion after head line 12

Head context (head/.claude/scripts/detect-platform-features.sh, lines 1–24):

~~~~text
     1 | #!/usr/bin/env bash
     2 | # =============================================================================
     3 | # detect-platform-features.sh — Report Claude Code platform capabilities
     4 | # =============================================================================
     5 | # Reports whether a harness-set skill signal exists for the implement gate.
     6 | #
     7 | # cycle-126 D-4.4: the PreToolUse payload has no harness-set skill field
     8 | # (https://code.claude.com/docs/en/hooks), and tool_input is model-authored,
     9 | # so this script never reports `active_skill_available: true` on its own. It
    10 | # carries forward the evidence implement-gate.sh records (active_skill_seen_at,
    11 | # active_skill_source) and states that it is not a harness signal.
    12 | #
    13 | # Outputs: .run/platform-features.json
    14 | #   { "active_skill_available": false, "harness_signal": false,
    15 | #     "active_skill_seen_at": "ISO8601"|null, "active_skill_source": str|null,
    16 | #     "detected_at": "ISO8601", "schema_version": 2 }
    17 | #
    18 | # Usage: detect-platform-features.sh          refresh the file (cached for 1 hour)
    19 | #        detect-platform-features.sh --line   print the /loa evidence line; writes nothing
    20 | #
    21 | # IMPORTANT: No set -euo pipefail — must never crash-block.
    22 | # Part of cycle-050: Upstream Platform Alignment (sprint-108, T4.3)
    23 | # =============================================================================
    24 | 
~~~~

The change from head to the fix:

~~~~diff
@@ -12,0 +13,6 @@
+# The refresh carries active_skill_seen_at forward only as an ISO-8601 UTC
+# timestamp and active_skill_source only as a value the recorder writes
+# ("tool_input"); anything else is dropped (sprint-250 audit n24). --line applies
+# the same two checks: a malformed seen_at is no evidence, any other source
+# prints "unknown" (sprint-250 audit run 2, finding 4).
+#
~~~~

## H25 — .claude/scripts/detect-platform-features.sh — head lines 35–36

Head context (head/.claude/scripts/detect-platform-features.sh, lines 23–48):

~~~~text
    23 | # =============================================================================
    24 | 
    25 | PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
    26 | RUN_DIR="${RUN_DIR:-$PROJECT_ROOT/.run}"
    27 | FEATURES_FILE="$RUN_DIR/platform-features.json"
    28 | 
    29 | if [[ "${1:-}" == "--line" ]]; then
    30 |     label="heuristic ("
    31 |     if command -v yq &>/dev/null && [[ -f "$PROJECT_ROOT/.loa.config.yaml" ]]; then
    32 |         configured=$(yq '.implement_gate.mode // ""' "$PROJECT_ROOT/.loa.config.yaml" 2>/dev/null) || configured=""
    33 |         [[ "${configured//\"/}" == "authoritative" ]] && label="authoritative (opt-in; "
    34 |     fi
>   35 |     evidence=$(jq -r 'if (.active_skill_seen_at // "") != "" then "seen \(.active_skill_seen_at) via \(.active_skill_source // "unknown")" else empty end' \
>   36 |         "$FEATURES_FILE" 2>/dev/null | tr -d '[:cntrl:]' | cut -c1-120)
    37 |     echo "Implement gate: ${label}active_skill evidence: ${evidence:-none}; no harness skill signal)"
    38 |     exit 0
    39 | fi
    40 | 
    41 | mkdir -p "$RUN_DIR" 2>/dev/null || true
    42 | 
    43 | # Cache check: reuse an existing file if less than 1 hour old
    44 | if [[ -f "$FEATURES_FILE" ]]; then
    45 |     local_mtime=""
    46 |     if stat -c %Y "$FEATURES_FILE" &>/dev/null 2>&1; then
    47 |         local_mtime=$(stat -c %Y "$FEATURES_FILE" 2>/dev/null) || local_mtime=""
    48 |     elif stat -f %m "$FEATURES_FILE" &>/dev/null 2>&1; then
~~~~

The change from head to the fix:

~~~~diff
@@ -35,2 +41,4 @@
-    evidence=$(jq -r 'if (.active_skill_seen_at // "") != "" then "seen \(.active_skill_seen_at) via \(.active_skill_source // "unknown")" else empty end' \
-        "$FEATURES_FILE" 2>/dev/null | tr -d '[:cntrl:]' | cut -c1-120)
+    # the refresh's shape checks (run-2 finding 4): an ISO-8601 UTC seen_at or no evidence, a recorder-written source or "unknown"
+    evidence=$(jq -r 'if (.active_skill_seen_at | type == "string" and test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z"))
+                      then "seen \(.active_skill_seen_at) via \(if .active_skill_source == "tool_input" then "tool_input" else "unknown" end)" else empty end' \
+        "$FEATURES_FILE" 2>/dev/null | LC_ALL=C tr -cd '[:print:]' | cut -c1-120)   # printable ASCII only: drops U+202E/U+200B too (sprint-250 audit n24)
~~~~

## H26 — .claude/scripts/detect-platform-features.sh — head line 66

Head context (head/.claude/scripts/detect-platform-features.sh, lines 54–71):

~~~~text
    54 |             exit 0
    55 |         fi
    56 |     fi
    57 | fi
    58 | 
    59 | command -v jq &>/dev/null || exit 0
    60 | 
    61 | detected_at=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || detected_at="unknown"
    62 | base=$(jq -c 'select(type == "object") | {active_skill_seen_at, active_skill_source}' "$FEATURES_FILE" 2>/dev/null | tail -n 1)
    63 | tmp=$(mktemp "$RUN_DIR/.platform-features.XXXXXX" 2>/dev/null) || exit 0
    64 | jq -n --argjson b "${base:-{\}}" --arg detected "$detected_at" \
    65 |     '{active_skill_available: false, harness_signal: false,
>   66 |       active_skill_seen_at: ($b.active_skill_seen_at // null), active_skill_source: ($b.active_skill_source // null),
    67 |       detected_at: $detected, schema_version: 2}' > "$tmp" 2>/dev/null \
    68 |     && mv -f "$tmp" "$FEATURES_FILE" 2>/dev/null
    69 | rm -f "$tmp" 2>/dev/null
    70 | 
    71 | exit 0
~~~~

The change from head to the fix:

~~~~diff
@@ -66 +74,2 @@
-      active_skill_seen_at: ($b.active_skill_seen_at // null), active_skill_source: ($b.active_skill_source // null),
+      active_skill_seen_at: ($b.active_skill_seen_at | if type == "string" and test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z") then . else null end),
+      active_skill_source: ($b.active_skill_source | if . == "tool_input" then . else null end),
~~~~

## H27 — .claude/scripts/flatline-orchestrator.sh — head lines 581–583

Head context (head/.claude/scripts/flatline-orchestrator.sh, lines 569–595):

~~~~text
   569 |     '^gemini-[0-9]+\.[0-9]+(-flash|-pro)?(-preview)?$'  # google: gemini-2.5-pro, gemini-3.1-pro-preview (cycle-109 T3.4 #793: -preview suffix)
   570 |     '^(opus|sonnet|haiku|fable)$'            # short anthropic aliases (DISS-002: anchored alternation)
   571 |     # cycle-109 Sprint 3 T3.4 (#793): cheval-headless pin form.
   572 |     # PR #727 (cycle-098) introduced subscription-auth headless adapters;
   573 |     # the orchestrator's pre-validator must admit the canonical pin shape
   574 |     # so operators following the cycle-098/099 setup don't fall back to
   575 |     # API providers (which defeats the cost-via-subscription benefit).
   576 |     '^(claude|codex|gemini)-headless:.+$'    # cheval-headless pin form
   577 | )
   578 | 
   579 | # Read declarations only: validation must not dispatch or resolve credentials.
   580 | # Reuse the loader's merge and the routing resolver's alias semantics.
>  581 | configured_flatline_model() {
>  582 |     PYTHONPATH="$SCRIPT_DIR/../adapters" python3 - "$PROJECT_ROOT" "$1" <<'PY' 2>/dev/null
>  583 | import sys
   584 | from loa_cheval.config.loader import load_system_defaults, load_project_config, _deep_merge
   585 | from loa_cheval.routing.resolver import resolve_alias
   586 | 
   587 | try:
   588 |     config = _deep_merge(load_system_defaults(sys.argv[1]), load_project_config(sys.argv[1]))
   589 |     providers = config.get("providers", {})
   590 |     aliases = {**config.get("backward_compat_aliases", {}), **config.get("aliases", {})}
   591 |     model = sys.argv[2]
   592 |     if ":" not in model and model not in aliases:
   593 |         matches = [name for name, provider in providers.items() if model in provider.get("models", {})]
   594 |         if not matches:
   595 |             sys.exit(1)
~~~~

The change from head to the fix:

~~~~diff
@@ -581,3 +581,6 @@
+# python3 -I (sprint-250 audit LOW-003): no cwd entry on sys.path, so a json.py or yaml.py in the cwd is never
+# imported; -I also discards PYTHONPATH, so the adapters directory arrives as argv[1] and is inserted below
 configured_flatline_model() {
-    PYTHONPATH="$SCRIPT_DIR/../adapters" python3 - "$PROJECT_ROOT" "$1" <<'PY' 2>/dev/null
+    python3 -I - "$SCRIPT_DIR/../adapters" "$PROJECT_ROOT" "$1" <<'PY' 2>/dev/null
 import sys
+sys.path.insert(0, sys.argv[1])
~~~~

## H28 — .claude/scripts/flatline-orchestrator.sh — head lines 588–591

Head context (head/.claude/scripts/flatline-orchestrator.sh, lines 576–603):

~~~~text
   576 |     '^(claude|codex|gemini)-headless:.+$'    # cheval-headless pin form
   577 | )
   578 | 
   579 | # Read declarations only: validation must not dispatch or resolve credentials.
   580 | # Reuse the loader's merge and the routing resolver's alias semantics.
   581 | configured_flatline_model() {
   582 |     PYTHONPATH="$SCRIPT_DIR/../adapters" python3 - "$PROJECT_ROOT" "$1" <<'PY' 2>/dev/null
   583 | import sys
   584 | from loa_cheval.config.loader import load_system_defaults, load_project_config, _deep_merge
   585 | from loa_cheval.routing.resolver import resolve_alias
   586 | 
   587 | try:
>  588 |     config = _deep_merge(load_system_defaults(sys.argv[1]), load_project_config(sys.argv[1]))
>  589 |     providers = config.get("providers", {})
>  590 |     aliases = {**config.get("backward_compat_aliases", {}), **config.get("aliases", {})}
>  591 |     model = sys.argv[2]
   592 |     if ":" not in model and model not in aliases:
   593 |         matches = [name for name, provider in providers.items() if model in provider.get("models", {})]
   594 |         if not matches:
   595 |             sys.exit(1)
   596 |         if len(matches) != 1:
   597 |             sys.exit(2)
   598 |         print(f"{matches[0]}:{model}")
   599 |     else:
   600 |         resolved = resolve_alias(model, aliases)
   601 |         if resolved.provider not in providers:
   602 |             sys.exit(2 if model in aliases else 1)
   603 |         if resolved.model_id not in providers[resolved.provider].get("models", {}):
~~~~

The change from head to the fix:

~~~~diff
@@ -588,4 +591,4 @@
-    config = _deep_merge(load_system_defaults(sys.argv[1]), load_project_config(sys.argv[1]))
+    config = _deep_merge(load_system_defaults(sys.argv[2]), load_project_config(sys.argv[2]))
     providers = config.get("providers", {})
     aliases = {**config.get("backward_compat_aliases", {}), **config.get("aliases", {})}
-    model = sys.argv[2]
+    model = sys.argv[3]
~~~~

## H29 — .claude/scripts/lib-content.sh — insertion after head line 169

Head context (head/.claude/scripts/lib-content.sh, lines 158–181):

~~~~text
   158 | # If content fits budget, passes through unchanged.
   159 | # If over budget, parses diff into per-file sections, sorts by priority,
   160 | # includes highest-priority files first, appends summary of skipped files.
   161 | _lc_chunk_tok() {  # <temp dir> <chunk index> <outvar> → the chunk's estimate, counted once per prepare_content call: the memo is the
   162 |                   # caller's local `_lc_tok` array (twenty-sixth run, b1 DISS-C-001 — the candidate scan, the reservation scan and the
   163 |                   # include loop each re-read and re-counted every chunk); printf -v, so the memo survives (a `$(...)` would drop it)
   164 |   # a subscript is arithmetic — `$(…)` in it runs: only a number is an index (audit run 1, b1 DISS-C-001), and only a canonical
   165 |   # decimal one — `08` is invalid octal there (bd-pw7e LOW-002)
   166 |   [[ "$2" =~ ^(0|[1-9][0-9]*)$ ]] || return 1
   167 |   [[ -n "${_lc_tok[$2]:-}" ]] || _lc_tok[$2]=$(estimate_tokens "$(cat "$1/chunk_$2")")
   168 |   printf -v "$3" '%s' "${_lc_tok[$2]}"
   169 | }
   170 | prepare_content() {
   171 |   local raw_content="$1"
   172 |   local max_tokens="${2:-30000}"
   173 | 
   174 |   local token_count
   175 |   token_count=$(estimate_tokens "$raw_content")
   176 | 
   177 |   # If content fits, return as-is
   178 |   if [[ $token_count -le $max_tokens ]]; then
   179 |     printf '%s' "$raw_content"
   180 |     return 0
   181 |   fi
~~~~

The change from head to the fix:

~~~~diff
@@ -169,0 +170,52 @@
+# The operator-facing stderr copy of a diff header path (bd-pw7e LOW-003; audit run 1 n30; run 2 finding 8; run 3
+# findings 8/10/11) → sets the variable named $1. Byte-wise under LC_ALL=C:
+#   1. cut to 256 bytes first, then drop an incomplete trailing UTF-8 sequence — the fixed point below then costs at
+#      most a few passes over a short string (C2^k 9B^k used to cost k passes over the whole path);
+#   2. C0 controls and DEL go;
+#   3. to a fixed point (deleting one sequence can join its neighbours into another: C2 C2 9B 9B -> C2 9B): UTF-8 C1
+#      controls C2 80..C2 9F and the Unicode format/bidi/tag code points U+00AD, U+061C, U+180E, U+200B-U+200F,
+#      U+2028-U+202E, U+2060-U+2064, U+2066-U+206F, U+FE00-U+FE0F, U+FEFF, U+FFF9-U+FFFB, U+E0001, U+E0020-U+E007F
+#      (Trojan-Source reordering of the file name). Every sequence starts with a lead byte, so legitimate UTF-8
+#      (src/café.sh) is untouched; printf -v keeps this portable (no GNU-sed \x);
+#   4. a copy that is still not valid UTF-8 (a bare 9B, or the 9B a C2 9B 9B leaves) has every non-printable byte,
+#      i.e. every byte >= 0x80, replaced with '?'; without iconv the replacement applies when a byte 80..9F remains.
+_LC_LOG_SEQS=()
+_lc_log_seqs_init() {
+  local i hex seq
+  for (( i = 128; i < 160; i++ )); do printf -v hex '%02x' "$i"; printf -v seq "\\xc2\\x${hex}"; _LC_LOG_SEQS+=("$seq"); done
+  for hex in 8b 8c 8d 8e 8f a8 a9 aa ab ac ad ae; do printf -v seq "\\xe2\\x80\\x${hex}"; _LC_LOG_SEQS+=("$seq"); done
+  for hex in a0 a1 a2 a3 a4 a6 a7 a8 a9 aa ab ac ad ae af; do printf -v seq "\\xe2\\x81\\x${hex}"; _LC_LOG_SEQS+=("$seq"); done
+  for seq in '\xef\xbb\xbf' '\xc2\xad' '\xd8\x9c' '\xe1\xa0\x8e' '\xef\xbf\xb9' '\xef\xbf\xba' '\xef\xbf\xbb' '\xf3\xa0\x80\x81'; do
+    printf -v seq "$seq"; _LC_LOG_SEQS+=("$seq")
+  done
+  for (( i = 128; i < 144; i++ )); do printf -v hex '%02x' "$i"; printf -v seq "\\xef\\xb8\\x${hex}"; _LC_LOG_SEQS+=("$seq"); done
+  for (( i = 160; i < 192; i++ )); do printf -v hex '%02x' "$i"; printf -v seq "\\xf3\\xa0\\x80\\x${hex}"; _LC_LOG_SEQS+=("$seq"); done
+  for (( i = 128; i < 192; i++ )); do printf -v hex '%02x' "$i"; printf -v seq "\\xf3\\xa0\\x81\\x${hex}"; _LC_LOG_SEQS+=("$seq"); done
+}
+_lc_safe_log_path() {  # <outvar> <path>
+  local LC_ALL=C
+  local _p=${2:0:256} _n _i _b _need _prev _seq
+  (( ${#_LC_LOG_SEQS[@]} )) || _lc_log_seqs_init
+  _n=${#_p}
+  for (( _i = _n - 1; _i >= 0 && _i >= _n - 4; _i-- )); do
+    printf -v _b '%d' "'${_p:_i:1}"
+    (( _b >= 128 && _b < 192 )) && continue   # continuation byte: keep walking back to its lead
+    if (( _b < 128 )); then _need=1; elif (( _b < 224 )); then _need=2; elif (( _b < 240 )); then _need=3; else _need=4; fi
+    (( _n - _i < _need )) && _p=${_p:0:_i}     # the cut left this character short
+    break
+  done
+  (( _i < 0 || _i < _n - 4 )) && _p=${_p:0:_i+1}   # only continuation bytes at the end
+  _p=$(printf '%s' "$_p" | tr -d '\000-\037\177')
+  while :; do
+    _prev=$_p
+    for _seq in "${_LC_LOG_SEQS[@]}"; do _p=${_p//"$_seq"/}; done
+    [[ "$_p" == "$_prev" ]] && break
+  done
+  if command -v iconv >/dev/null 2>&1; then
+    printf '%s' "$_p" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 || _p=$(printf '%s' "$_p" | tr -c '[:print:]' '?')
+  elif printf '%s' "$_p" | grep -q $'[\x80-\x9f]'; then
+    _p=$(printf '%s' "$_p" | tr -c '[:print:]' '?')
+  fi
+  printf -v "$1" '%s' "$_p"
+}
+
~~~~

## H30 — .claude/scripts/lib-content.sh — head line 295

Head context (head/.claude/scripts/lib-content.sh, lines 283–307):

~~~~text
   283 |   # reservation below is computed against the rows at or above the candidate's own priority
   284 |   # — and not only a row larger than the WHOLE budget (twenty-first run, b1 DISS-C-002: a P0 file that fits the budget alone but
   285 |   # not beside the P0 rows ahead of it was dropped whole while a P1 file behind it was shown); the running sum below is the main
   286 |   # loop's own include rule up to its first omission
   287 |   local top_pri="" top_path="" top_idx="" top_partial_done=0 top_no_room=0 c_pri c_path c_idx c_tok c_run=0
   288 |   local -a _lc_tok=()
   289 |   while IFS=$'\t' read -r c_pri c_idx c_path; do
   290 |     [[ -n "$c_idx" && -f "$temp_dir/chunk_${c_idx}" ]] || continue
   291 |     _lc_chunk_tok "$temp_dir" "$c_idx" c_tok || continue
   292 |     if (( c_run + c_tok > max_tokens )); then top_pri="$c_pri"; top_path="$c_path"; top_idx="$c_idx"; break; fi
   293 |     c_run=$(( c_run + c_tok ))
   294 |   done <<< "$sorted_manifest"
>  295 |   local top_path_log; top_path_log=$(printf '%s' "$top_path" | LC_ALL=C tr -d '\000-\037\177')   # stderr never gets a header's raw controls (bd-pw7e LOW-003)
   296 |   if [[ -n "$top_idx" ]]; then
   297 |     # the reservation is what the other files AT THE TOP PRIORITY that fit leave over, clamped to a quarter … three quarters
   298 |     # of the budget — a same-priority sibling that used to be reviewed whole is not displaced by a partial view of one large
   299 |     # file (fifteenth run, b1 C-002), and a lower-priority row never shrinks the view of the file the review is about
   300 |     # (sixteenth run, b1 C-001)
   301 |     local others=0 o_pri o_path o_idx o_tok reserve partial kept total how
   302 |     while IFS=$'\t' read -r o_pri o_idx o_path; do
   303 |       [[ -n "$o_idx" && "$o_idx" != "$top_idx" && -f "$temp_dir/chunk_${o_idx}" ]] || continue
   304 |       [[ "$o_pri" -le "$top_pri" ]] || continue
   305 |       _lc_chunk_tok "$temp_dir" "$o_idx" o_tok || continue
   306 |       # what those rows take TOGETHER, by the main loop's greedy rule — two siblings that each fit but not side by side are not
   307 |       # reserved twice (twenty-second run, b1 DISS-C-001)
~~~~

The change from head to the fix:

~~~~diff
@@ -295 +347 @@
-  local top_path_log; top_path_log=$(printf '%s' "$top_path" | LC_ALL=C tr -d '\000-\037\177')   # stderr never gets a header's raw controls (bd-pw7e LOW-003)
+  local top_path_log; _lc_safe_log_path top_path_log "$top_path"   # stderr never gets a header's raw controls, C1 or bidi code points
~~~~

## H31 — .claude/scripts/model-adapter.sh — insertion after head line 147

Head context (head/.claude/scripts/model-adapter.sh, lines 136–159):

~~~~text
   136 | # =============================================================================
   137 | # Logging
   138 | # =============================================================================
   139 | 
   140 | log() {
   141 |     echo "[model-adapter:shim] $*" >&2
   142 | }
   143 | 
   144 | error() {
   145 |     echo "ERROR: $*" >&2
   146 | }
   147 | 
   148 | # =============================================================================
   149 | # Probe-cache integration (Sprint 3B Task 3B.7 — SDD §5.1 row 4-5, §6.2)
   150 | # =============================================================================
   151 | 
   152 | PROBE_CACHE_PATH="${LOA_CACHE_DIR:-.run}/model-health-cache.json"
   153 | PROBE_SCRIPT="${LOA_PROBE_SCRIPT:-$(dirname "${BASH_SOURCE[0]}")/model-health-probe.sh}"
   154 | 
   155 | # Honor LOA_PROBE_BYPASS in the adapter as well — the probe script handles the
   156 | # audit + TTL on bypass set; the adapter only reads the env var to decide
   157 | # whether to consult the cache at all. The probe-side `_check_bypass` already
   158 | # refused-with-audit when no reason is given.
   159 | _adapter_bypass_active() {
~~~~

The change from head to the fix:

~~~~diff
@@ -147,0 +148,7 @@
+# _trap_body "<trap -p output>" — the handler text of a `trap -- '<body>' SIG`
+# line (trap -p quotes it for re-input), so a new handler can chain it.
+_trap_body() {
+    eval "set -- $1"
+    printf '%s' "${3:-}"
+}
+
~~~~

## H32 — .claude/scripts/model-adapter.sh — head lines 655–659

Head context (head/.claude/scripts/model-adapter.sh, lines 643–670):

~~~~text
   643 |     fi
   644 | 
   645 |     # Dry run
   646 |     if [[ "$dry_run" == "true" ]]; then
   647 |         log "Dry run — validating through model-invoke"
   648 |         "$MODEL_INVOKE" --agent "$agent" --model "$model_override" --dry-run
   649 |         exit $?
   650 |     fi
   651 | 
   652 |     # Call model-invoke and translate output
   653 |     # cheval's stderr stays out of the caller's view except the agy argv-exposure
   654 |     # WARN, which is the operator-facing half of that mitigation (bd-pw7e LOW-001).
>  655 |     local result exit_code=0 err_file
>  656 |     err_file="$(mktemp "${TMPDIR:-/tmp}/model-adapter-stderr.XXXXXX")"
>  657 |     result=$("$MODEL_INVOKE" "${invoke_args[@]}" 2>"$err_file") || exit_code=$?
>  658 |     grep -F -- 'gemini-headless dispatches agy' "$err_file" | cut -c1-600 >&2 || :
>  659 |     rm -f -- "$err_file"
   660 | 
   661 |     if [[ $exit_code -ne 0 ]]; then
   662 |         error "model-invoke failed with exit code $exit_code"
   663 |         exit $exit_code
   664 |     fi
   665 | 
   666 |     # Translate output format for backward compatibility
   667 |     echo "$result" | translate_output "$model" "$mode" "$phase"
   668 | }
   669 | 
   670 | main "$@"
~~~~

The change from head to the fix:

~~~~diff
@@ -655,5 +662,19 @@
-    local result exit_code=0 err_file
-    err_file="$(mktemp "${TMPDIR:-/tmp}/model-adapter-stderr.XXXXXX")"
-    result=$("$MODEL_INVOKE" "${invoke_args[@]}" 2>"$err_file") || exit_code=$?
-    grep -F -- 'gemini-headless dispatches agy' "$err_file" | cut -c1-600 >&2 || :
-    rm -f -- "$err_file"
+    # An unusable TMPDIR must not abort the call: without a temp file stderr is
+    # discarded as before; the EXIT trap removes the file on a caller's TERM too
+    # (sprint-250 review run 1, n15). It chains any EXIT trap already set and
+    # restores it afterwards, never clearing it (sprint-250 review run 2, #6);
+    # the fallback says so on stderr (run 2, #7).
+    local result exit_code=0 err_file="" prev_exit_trap="" prev_exit_body=""
+    err_file="$(mktemp "${TMPDIR:-/tmp}/model-adapter-stderr.XXXXXX" 2>/dev/null)" || err_file=""
+    if [[ -n "$err_file" ]]; then
+        prev_exit_trap="$(trap -p EXIT)"
+        [[ -n "$prev_exit_trap" ]] && prev_exit_body="$(_trap_body "$prev_exit_trap")"
+        trap 'rm -f -- "$err_file"'"${prev_exit_body:+; $prev_exit_body}" EXIT
+        result=$("$MODEL_INVOKE" "${invoke_args[@]}" 2>"$err_file") || exit_code=$?
+        grep -F -- 'gemini-headless dispatches agy' "$err_file" | cut -c1-600 >&2 || :
+        rm -f -- "$err_file"
+        if [[ -n "$prev_exit_trap" ]]; then eval "$prev_exit_trap"; else trap - EXIT; fi
+    else
+        echo "WARN: model-adapter: stderr capture disabled (mktemp failed under ${TMPDIR:-/tmp}); the agy argv-exposure WARN will not be relayed" >&2
+        result=$("$MODEL_INVOKE" "${invoke_args[@]}" 2>/dev/null) || exit_code=$?
+    fi
~~~~

## H33 — .claude/scripts/validate-skill-capabilities.sh — insertion after head line 33

Head context (head/.claude/scripts/validate-skill-capabilities.sh, lines 22–45):

~~~~text
    22 | 
    23 | # Source safe yq
    24 | # shellcheck source=yq-safe.sh
    25 | source "$SCRIPT_DIR/yq-safe.sh"
    26 | 
    27 | # shellcheck source=lib/dx-utils.sh
    28 | source "$SCRIPT_DIR/lib/dx-utils.sh"
    29 | 
    30 | # --- CLI flags ---
    31 | STRICT=false
    32 | JSON_OUTPUT=false
    33 | SINGLE_SKILL=""
    34 | 
    35 | while [[ $# -gt 0 ]]; do
    36 |     case "$1" in
    37 |         --strict) STRICT=true; shift ;;
    38 |         --json) JSON_OUTPUT=true; shift ;;
    39 |         --skill)
    40 |             # R-010 (bd-m1o6): '--skill' as the last arg used to leak a raw
    41 |             # bash '$2: unbound variable' error under set -u.
    42 |             if [[ -z "${2:-}" ]]; then
    43 |                 echo "Error: --skill requires a skill name (e.g. --skill reviewing-code)" >&2
    44 |                 echo "Usage: validate-skill-capabilities.sh [--strict] [--json] [--skill NAME]" >&2
    45 |                 exit 2
~~~~

The change from head to the fix:

~~~~diff
@@ -33,0 +34,3 @@
+AGENT_TYPES_FILE_ARG=""
+# The ambient AGENT_TYPES_FILE variable is ignored (audit run 3, finding 13): only --agent-types-file redirects
+unset AGENT_TYPES_FILE
~~~~

## H34 — .claude/scripts/validate-skill-capabilities.sh — head lines 48–57

Head context (head/.claude/scripts/validate-skill-capabilities.sh, lines 36–69):

~~~~text
    36 |     case "$1" in
    37 |         --strict) STRICT=true; shift ;;
    38 |         --json) JSON_OUTPUT=true; shift ;;
    39 |         --skill)
    40 |             # R-010 (bd-m1o6): '--skill' as the last arg used to leak a raw
    41 |             # bash '$2: unbound variable' error under set -u.
    42 |             if [[ -z "${2:-}" ]]; then
    43 |                 echo "Error: --skill requires a skill name (e.g. --skill reviewing-code)" >&2
    44 |                 echo "Usage: validate-skill-capabilities.sh [--strict] [--json] [--skill NAME]" >&2
    45 |                 exit 2
    46 |             fi
    47 |             SINGLE_SKILL="$2"; shift 2 ;;
>   48 |         -h|--help)
>   49 |             echo "Usage: validate-skill-capabilities.sh [--strict] [--json] [--skill NAME]"
>   50 |             echo "  --strict   Promote warnings to errors"
>   51 |             echo "  --json     Output as JSON"
>   52 |             echo "  --skill    Validate single skill"
>   53 |             exit 0
>   54 |             ;;
>   55 |         *)
>   56 |             dx_unknown_flag "$1" "Usage: validate-skill-capabilities.sh [--strict] [--json] [--skill NAME]" \
>   57 |                 --strict --json --skill --help
    58 |             exit 2
    59 |             ;;
    60 |     esac
    61 | done
    62 | 
    63 | # --- Internal sub-skills to skip ---
    64 | SKIP_SKILLS=("flatline-reviewer" "flatline-scorer" "flatline-skeptic" "gpt-reviewer")
    65 | 
    66 | # --- Cycle-108 T1.D: role/primary_role validation constants ---
    67 | # Valid role enum (PRD §5 FR-3, SDD §4.1)
    68 | VALID_ROLES=("planning" "review" "implementation")
    69 | # cycle-114 FR-3: valid values for the optional `effort:` frontmatter key
~~~~

The change from head to the fix:

~~~~diff
@@ -48,10 +51,20 @@
+        --agent-types-file)
+            if [[ -z "${2:-}" ]]; then
+                echo "Error: --agent-types-file requires a path" >&2
+                echo "Usage: validate-skill-capabilities.sh [--strict] [--json] [--skill NAME] [--agent-types-file PATH]" >&2
+                exit 2
+            fi
+            AGENT_TYPES_FILE_ARG="$2"; shift 2 ;;
         -h|--help)
-            echo "Usage: validate-skill-capabilities.sh [--strict] [--json] [--skill NAME]"
+            echo "Usage: validate-skill-capabilities.sh [--strict] [--json] [--skill NAME] [--agent-types-file PATH]"
             echo "  --strict   Promote warnings to errors"
             echo "  --json     Output as JSON"
             echo "  --skill    Validate single skill"
+            echo "  --agent-types-file PATH"
+            echo "             Test seam: read the write-capable agent types from PATH instead of"
+            echo "             .claude/data/agent-types.yaml (the AGENT_TYPES_FILE variable is ignored)"
             exit 0
             ;;
         *)
-            dx_unknown_flag "$1" "Usage: validate-skill-capabilities.sh [--strict] [--json] [--skill NAME]" \
-                --strict --json --skill --help
+            dx_unknown_flag "$1" "Usage: validate-skill-capabilities.sh [--strict] [--json] [--skill NAME] [--agent-types-file PATH]" \
+                --strict --json --skill --agent-types-file --help
~~~~

## H35 — .claude/scripts/validate-skill-capabilities.sh — head lines 108–110

Head context (head/.claude/scripts/validate-skill-capabilities.sh, lines 96–122):

~~~~text
    96 | should_skip() {
    97 |     local name="$1"
    98 |     for skip in "${SKIP_SKILLS[@]}"; do
    99 |         [[ "$name" == "$skip" ]] && return 0
   100 |     done
   101 |     return 1
   102 | }
   103 | 
   104 | # --- Agent types that include Write/Edit in their tool allowlist (Issue #553) ---
   105 | # When a skill declares write capability (capabilities.write_files: true OR
   106 | # allowed-tools lists Write/Edit), its agent: frontmatter key MUST be unset
   107 | # or set to one of these. Read from .claude/data/agent-types.yaml (cycle-126
>  108 | # D-4.4); a missing or unparsable file leaves general-purpose only.
>  109 | # See .claude/rules/skill-invariants.md.
>  110 | AGENT_TYPES_FILE="${AGENT_TYPES_FILE:-$PROJECT_ROOT/.claude/data/agent-types.yaml}"
   111 | WRITE_CAPABLE_AGENTS=()
   112 | if [[ -f "$AGENT_TYPES_FILE" ]]; then
   113 |     while IFS= read -r _agent; do
   114 |         [[ "$_agent" =~ ^[A-Za-z0-9_-]+$ ]] && WRITE_CAPABLE_AGENTS+=("$_agent")
   115 |     done < <(yq eval '.agent_types | to_entries | .[] | select(.value.write_capable == true) | .key' "$AGENT_TYPES_FILE" 2>/dev/null || true)
   116 | fi
   117 | [[ ${#WRITE_CAPABLE_AGENTS[@]} -gt 0 ]] || WRITE_CAPABLE_AGENTS=("general-purpose")
   118 | 
   119 | is_write_capable_agent() {
   120 |     local agent="$1"
   121 |     for a in "${WRITE_CAPABLE_AGENTS[@]}"; do
   122 |         [[ "$agent" == "$a" ]] && return 0
~~~~

The change from head to the fix:

~~~~diff
@@ -108,3 +121,8 @@
-# D-4.4); a missing or unparsable file leaves general-purpose only.
+# D-4.4); a missing or unparsable file, or one with no `write_capable: true`
+# entry, leaves general-purpose only.
+# The ambient environment can no longer redirect the allowlist (audit run 3,
+# finding 13): the AGENT_TYPES_FILE variable is ignored. The explicit
+# --agent-types-file argument can, by design — it is the test seam, visible on
+# the command line of whoever invokes the validator.
 # See .claude/rules/skill-invariants.md.
-AGENT_TYPES_FILE="${AGENT_TYPES_FILE:-$PROJECT_ROOT/.claude/data/agent-types.yaml}"
+AGENT_TYPES_FILE="${AGENT_TYPES_FILE_ARG:-$PROJECT_ROOT/.claude/data/agent-types.yaml}"
~~~~

## H36 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head lines 3–4

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 1–16):

~~~~text
     1 | {
     2 |   "version": "1.0",
>    3 |   "generated_at": "2026-10-05T11:21:48Z",
>    4 |   "source_hash": "13d61e7ce3c7cbb4a4291b2edc6892622afa12f50ac2874e99fd747da7b0174c",
     5 |   "file_count": 42,
     6 |   "files": [
     7 |     {
     8 |       "path": ".claude/skills/bridgebuilder-review/resources/adapters/adapter-factory.ts",
     9 |       "sha256": "e40e075c96c8c73244d6344a6a18e6f128ccf86bb35b56325fb3d88fd3efda18"
    10 |     },
    11 |     {
    12 |       "path": ".claude/skills/bridgebuilder-review/resources/adapters/cheval-delegate.ts",
    13 |       "sha256": "bafda4073a3bfd6bd3506a124640135fbd02397f5157bfef7009390861818470"
    14 |     },
    15 |     {
    16 |       "path": ".claude/skills/bridgebuilder-review/resources/adapters/console-logger.ts",
~~~~

The change from head to the fix:

~~~~diff
@@ -3,2 +3,2 @@
-  "generated_at": "2026-10-05T11:21:48Z",
-  "source_hash": "13d61e7ce3c7cbb4a4291b2edc6892622afa12f50ac2874e99fd747da7b0174c",
+  "generated_at": "2026-10-06T09:01:29Z",
+  "source_hash": "f06747ce10232aaf7bcd455f0ffc242402b78d9cf61245614bc958a653bf0793",
~~~~

## H37 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head line 105

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 93–117):

~~~~text
    93 |       "sha256": "c36a76a459ad2b2365c021d9f581a63685bc61ae4170c9c0593f97b8345afeac"
    94 |     },
    95 |     {
    96 |       "path": ".claude/skills/bridgebuilder-review/resources/core/rating.ts",
    97 |       "sha256": "322cb2bfe26b7c132d6e998520bfbf852b8cf5d6190a847d80c01073795a7dee"
    98 |     },
    99 |     {
   100 |       "path": ".claude/skills/bridgebuilder-review/resources/core/review-verdict.ts",
   101 |       "sha256": "be87841aa516aae732397ab2f1c469e3ca78c206bf4d04206641078bc92475ea"
   102 |     },
   103 |     {
   104 |       "path": ".claude/skills/bridgebuilder-review/resources/core/reviewer.ts",
>  105 |       "sha256": "5c873ecb91c3924abb1a3e20fd10a719b7a74a73561365d7723b1984668caa22"
   106 |     },
   107 |     {
   108 |       "path": ".claude/skills/bridgebuilder-review/resources/core/schemas.ts",
   109 |       "sha256": "ad1503e6fc1031e2b137b5e2866cf6b13fc27dd6045cc64422cf3b1f8a3ae048"
   110 |     },
   111 |     {
   112 |       "path": ".claude/skills/bridgebuilder-review/resources/core/scoring.ts",
   113 |       "sha256": "69942be01495aa8f12fe1f9266594bd3bbf42bb87456e4cbd33410a25750d9e0"
   114 |     },
   115 |     {
   116 |       "path": ".claude/skills/bridgebuilder-review/resources/core/template.ts",
   117 |       "sha256": "9b0163d3aca18196e5701fe27575e5d27249763b42f59ea09680719e978b215f"
~~~~

The change from head to the fix:

~~~~diff
@@ -105 +105 @@
-      "sha256": "5c873ecb91c3924abb1a3e20fd10a719b7a74a73561365d7723b1984668caa22"
+      "sha256": "89b94a402f6591836537b0b23c807c0400ff74177bc56ff54435238644d2e01f"
~~~~

## H38 — .claude/skills/bridgebuilder-review/dist/.build-manifest.json — head lines 121–125

Head context (head/.claude/skills/bridgebuilder-review/dist/.build-manifest.json, lines 109–137):

~~~~text
   109 |       "sha256": "ad1503e6fc1031e2b137b5e2866cf6b13fc27dd6045cc64422cf3b1f8a3ae048"
   110 |     },
   111 |     {
   112 |       "path": ".claude/skills/bridgebuilder-review/resources/core/scoring.ts",
   113 |       "sha256": "69942be01495aa8f12fe1f9266594bd3bbf42bb87456e4cbd33410a25750d9e0"
   114 |     },
   115 |     {
   116 |       "path": ".claude/skills/bridgebuilder-review/resources/core/template.ts",
   117 |       "sha256": "9b0163d3aca18196e5701fe27575e5d27249763b42f59ea09680719e978b215f"
   118 |     },
   119 |     {
   120 |       "path": ".claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts",
>  121 |       "sha256": "cc0ef5d11ff15d6f83f247e1e3edaf201c62f2e08f02f0641d50eed9b549324c"
>  122 |     },
>  123 |     {
>  124 |       "path": ".claude/skills/bridgebuilder-review/resources/core/truncation.ts",
>  125 |       "sha256": "ecf61b3ae7a20bf2444743589b83d2c092d92ffb6b9d9e6b096479c8fed65d8d"
   126 |     },
   127 |     {
   128 |       "path": ".claude/skills/bridgebuilder-review/resources/core/types.ts",
   129 |       "sha256": "b2550acecccd39fe9c14583742f19870db0835e543995f1208543f82283318fe"
   130 |     },
   131 |     {
   132 |       "path": ".claude/skills/bridgebuilder-review/resources/lib/endpoint-validator.generated.ts",
   133 |       "sha256": "d77e64398c184401f8fb1b22ac6868f50c301cc50c38c3d658887738acbee25e"
   134 |     },
   135 |     {
   136 |       "path": ".claude/skills/bridgebuilder-review/resources/lib/model-resolver.generated.ts",
   137 |       "sha256": "5f32f6e734a27195962bb69de704d6d0b7eb9c24415f4a008800346f4711bb45"
~~~~

The change from head to the fix:

~~~~diff
@@ -121,5 +121,5 @@
-      "sha256": "cc0ef5d11ff15d6f83f247e1e3edaf201c62f2e08f02f0641d50eed9b549324c"
+      "sha256": "92e4a13f145cd55777a296d2c8ccb5952c59a44e73024d4ed755c22dbde429c5"
     },
     {
       "path": ".claude/skills/bridgebuilder-review/resources/core/truncation.ts",
-      "sha256": "ecf61b3ae7a20bf2444743589b83d2c092d92ffb6b9d9e6b096479c8fed65d8d"
+      "sha256": "5ed9bd99a13564cc0a65e2a8117e258e557d002b05f31887398fbec22112b249"
~~~~

## H39 — .claude/skills/bridgebuilder-review/dist/core/truncation.generated.d.ts.map — head line 1

Head context (head/.claude/skills/bridgebuilder-review/dist/core/truncation.generated.d.ts.map, lines 1–1):

~~~~text
>    1 | {"version":3,"file":"truncation.generated.d.ts","sourceRoot":"","sources":["../../resources/core/truncation.generated.ts"],"names":[],"mappings":"AAgBA,OAAO,KAAK,EAAE,WAAW,EAAE,MAAM,YAAY,CAAC;AAE9C,eAAO,MAAM,uBAAuB,EAAE,MAAM,CAAC,MAAM,EAAE,WAAW,CAkC/D,CAAC"}
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-{"version":3,"file":"truncation.generated.d.ts","sourceRoot":"","sources":["../../resources/core/truncation.generated.ts"],"names":[],"mappings":"AAgBA,OAAO,KAAK,EAAE,WAAW,EAAE,MAAM,YAAY,CAAC;AAE9C,eAAO,MAAM,uBAAuB,EAAE,MAAM,CAAC,MAAM,EAAE,WAAW,CAkC/D,CAAC"}
\ No newline at end of file
+{"version":3,"file":"truncation.generated.d.ts","sourceRoot":"","sources":["../../resources/core/truncation.generated.ts"],"names":[],"mappings":"AAsBA,OAAO,KAAK,EAAE,WAAW,EAAE,MAAM,YAAY,CAAC;AAE9C,eAAO,MAAM,uBAAuB,EAAE,MAAM,CAAC,MAAM,EAAE,WAAW,CAkC/D,CAAC;AAEF,eAAO,MAAM,uBAAuB,EAAE,MAAM,CAAC,MAAM,EAAE,MAAM,CAmB1D,CAAC"}
\ No newline at end of file
~~~~

## H40 — .claude/skills/bridgebuilder-review/dist/core/truncation.generated.js — insertion after head line 14

Head context (head/.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js, lines 3–26):

~~~~text
     3 | // Source: .claude/defaults/model-config.yaml
     4 | //
     5 | // Per-provider defaults applied at codegen time (yaml tracks API context_window
     6 | // only; maxOutput + coefficient are BB-skill truncation heuristics):
     7 | //   anthropic / bedrock / google: maxOutput=8192, coefficient=0.25
     8 | //   openai:                       maxOutput=4096, coefficient=0.23
     9 | //   default fallback:             maxInput=100000, maxOutput=4096, coefficient=0.25
    10 | //
    11 | // maxInput = effective_input_ceiling − 20000 when the yaml entry carries the
    12 | // v3 ceiling (cycle-124 FR-3 / SDD §2.1: BB truncates below cheval's pre-flight
    13 | // gate instead of dispatching what exit 7 would reject), else context_window.
    14 | //
    15 | // cycle-099 sprint-1 (T1.1). See SDD §1.4.3 + §5.3.
    16 | export const GENERATED_TOKEN_BUDGETS = {
    17 |     "claude-fable-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    18 |     "claude-fable-5-1": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    19 |     "claude-haiku-4-5-20251001": { maxInput: 160000, maxOutput: 8192, coefficient: 0.25 },
    20 |     "claude-headless": { maxInput: 1000000, maxOutput: 8192, coefficient: 0.25 },
    21 |     "claude-opus-4-6": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    22 |     "claude-opus-4-7": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    23 |     "claude-opus-4-8": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    24 |     "claude-opus-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    25 |     "claude-opus-5-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    26 |     "claude-sonnet-4-5-20250929": { maxInput: 160000, maxOutput: 8192, coefficient: 0.25 },
~~~~

The change from head to the fix:

~~~~diff
@@ -14,0 +15,6 @@
+// GENERATED_MODEL_ALIASES maps the catalog's `aliases:` block to bare model
+// ids (provider-qualified targets only; self-maps dropped) so an alias such as
+// `opus` gets its target's budget. An operator alias overlay in
+// .loa.config.yaml is NOT reflected — pin a concrete model or set
+// max_input_tokens (cycle-126 sprint-250).
+//
~~~~

## H41 — .claude/skills/bridgebuilder-review/dist/core/truncation.generated.js — insertion after head line 50

Head context (head/.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js, lines 39–51):

~~~~text
    39 |     "gemini-3-flash-preview": { maxInput: 1048576, maxOutput: 8192, coefficient: 0.25 },
    40 |     "gemini-3.1-pro-preview": { maxInput: 1048576, maxOutput: 32000, coefficient: 0.25 },
    41 |     "gemini-headless": { maxInput: 1048576, maxOutput: 8192, coefficient: 0.25 },
    42 |     "codex-headless": { maxInput: 400000, maxOutput: 4096, coefficient: 0.23 },
    43 |     "gpt-5.2": { maxInput: 128000, maxOutput: 16000, coefficient: 0.23 },
    44 |     "gpt-5.3-codex": { maxInput: 400000, maxOutput: 32000, coefficient: 0.23 },
    45 |     "gpt-5.5": { maxInput: 400000, maxOutput: 32000, coefficient: 0.23 },
    46 |     "gpt-5.5-pro": { maxInput: 400000, maxOutput: 32000, coefficient: 0.23 },
    47 |     "grok-build": { maxInput: 256000, maxOutput: 4096, coefficient: 0.25 },
    48 |     "grok-composer-2.5-fast": { maxInput: 256000, maxOutput: 4096, coefficient: 0.25 },
    49 |     "default": { maxInput: 100000, maxOutput: 4096, coefficient: 0.25 },
    50 | };
    51 | //# sourceMappingURL=truncation.generated.js.map
~~~~

The change from head to the fix:

~~~~diff
@@ -50,0 +57,20 @@
+export const GENERATED_MODEL_ALIASES = {
+    "cheap": "claude-sonnet-5",
+    "cursor-composer": "composer-2.5",
+    "cursor-fast": "composer-2.5-fast",
+    "cursor-headless": "composer-2.5",
+    "deep-thinker": "gemini-3.1-pro-preview",
+    "fable": "claude-fable-5-1",
+    "gemini-2.0": "gemini-2.0-flash",
+    "gemini-3-flash": "gemini-3-flash-preview",
+    "gemini-3.1-pro": "gemini-3.1-pro-preview",
+    "gemini-api": "gemini-2.5-pro",
+    "grok-composer": "grok-composer-2.5-fast",
+    "grok-fast": "grok-composer-2.5-fast",
+    "grok-headless": "grok-build",
+    "opus": "claude-opus-5-5",
+    "reasoning": "gpt-5.5",
+    "researcher": "deep-research-pro",
+    "reviewer": "gpt-5.5",
+    "tiny": "claude-haiku-4-5-20251001",
+};
~~~~

## H42 — .claude/skills/bridgebuilder-review/dist/core/truncation.generated.js.map — head line 1

Head context (head/.claude/skills/bridgebuilder-review/dist/core/truncation.generated.js.map, lines 1–1):

~~~~text
>    1 | {"version":3,"file":"truncation.generated.js","sourceRoot":"","sources":["../../resources/core/truncation.generated.ts"],"names":[],"mappings":"AAAA,mFAAmF;AACnF,yFAAyF;AACzF,6CAA6C;AAC7C,EAAE;AACF,gFAAgF;AAChF,qEAAqE;AACrE,mEAAmE;AACnE,mEAAmE;AACnE,oFAAoF;AACpF,EAAE;AACF,6EAA6E;AAC7E,gFAAgF;AAChF,8EAA8E;AAC9E,EAAE;AACF,oDAAoD;AAIpD,MAAM,CAAC,MAAM,uBAAuB,GAAgC;IAClE,gBAAgB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC3E,kBAAkB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,2BAA2B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACrF,iBAAiB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,eAAe,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,4BAA4B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACtF,mBAAmB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC9E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,6CAA6C,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACvG,8BAA8B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACxF,8BAA8B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACxF,gCAAgC,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1F,cAAc,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACxE,mBAAmB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,mBAAmB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC9E,kBAAkB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,kBAAkB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,gBAAgB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,wBAAwB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACnF,wBAAwB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACpF,iBAAiB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,gBAAgB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1E,SAAS,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACpE,eAAe,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1E,SAAS,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACpE,aAAa,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACxE,YAAY,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACtE,wBAAwB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAClF,SAAS,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;CACpE,CAAC"}
~~~~

The change from head to the fix:

~~~~diff
@@ -1 +1 @@
-{"version":3,"file":"truncation.generated.js","sourceRoot":"","sources":["../../resources/core/truncation.generated.ts"],"names":[],"mappings":"AAAA,mFAAmF;AACnF,yFAAyF;AACzF,6CAA6C;AAC7C,EAAE;AACF,gFAAgF;AAChF,qEAAqE;AACrE,mEAAmE;AACnE,mEAAmE;AACnE,oFAAoF;AACpF,EAAE;AACF,6EAA6E;AAC7E,gFAAgF;AAChF,8EAA8E;AAC9E,EAAE;AACF,oDAAoD;AAIpD,MAAM,CAAC,MAAM,uBAAuB,GAAgC;IAClE,gBAAgB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC3E,kBAAkB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,2BAA2B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACrF,iBAAiB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,eAAe,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,4BAA4B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACtF,mBAAmB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC9E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,6CAA6C,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACvG,8BAA8B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACxF,8BAA8B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACxF,gCAAgC,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1F,cAAc,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACxE,mBAAmB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,mBAAmB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC9E,kBAAkB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,kBAAkB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,gBAAgB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,wBAAwB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACnF,wBAAwB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACpF,iBAAiB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,gBAAgB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1E,SAAS,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACpE,eAAe,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1E,SAAS,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACpE,aAAa,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACxE,YAAY,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACtE,wBAAwB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAClF,SAAS,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;CACpE,CAAC"}
\ No newline at end of file
+{"version":3,"file":"truncation.generated.js","sourceRoot":"","sources":["../../resources/core/truncation.generated.ts"],"names":[],"mappings":"AAAA,mFAAmF;AACnF,yFAAyF;AACzF,6CAA6C;AAC7C,EAAE;AACF,gFAAgF;AAChF,qEAAqE;AACrE,mEAAmE;AACnE,mEAAmE;AACnE,oFAAoF;AACpF,EAAE;AACF,6EAA6E;AAC7E,gFAAgF;AAChF,8EAA8E;AAC9E,EAAE;AACF,4EAA4E;AAC5E,+EAA+E;AAC/E,gEAAgE;AAChE,kEAAkE;AAClE,2CAA2C;AAC3C,EAAE;AACF,oDAAoD;AAIpD,MAAM,CAAC,MAAM,uBAAuB,GAAgC;IAClE,gBAAgB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC3E,kBAAkB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,2BAA2B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACrF,iBAAiB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,eAAe,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,4BAA4B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACtF,mBAAmB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC9E,iBAAiB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,6CAA6C,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACvG,8BAA8B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACxF,8BAA8B,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACxF,gCAAgC,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1F,cAAc,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACxE,mBAAmB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,mBAAmB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC9E,kBAAkB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,kBAAkB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC7E,gBAAgB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,wBAAwB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACnF,wBAAwB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACpF,iBAAiB,EAAE,EAAE,QAAQ,EAAE,OAAO,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC5E,gBAAgB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1E,SAAS,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACpE,eAAe,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IAC1E,SAAS,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACpE,aAAa,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,KAAK,EAAE,WAAW,EAAE,IAAI,EAAE;IACxE,YAAY,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IACtE,wBAAwB,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;IAClF,SAAS,EAAE,EAAE,QAAQ,EAAE,MAAM,EAAE,SAAS,EAAE,IAAI,EAAE,WAAW,EAAE,IAAI,EAAE;CACpE,CAAC;AAEF,MAAM,CAAC,MAAM,uBAAuB,GAA2B;IAC7D,OAAO,EAAE,iBAAiB;IAC1B,iBAAiB,EAAE,cAAc;IACjC,aAAa,EAAE,mBAAmB;IAClC,iBAAiB,EAAE,cAAc;IACjC,cAAc,EAAE,wBAAwB;IACxC,OAAO,EAAE,kBAAkB;IAC3B,YAAY,EAAE,kBAAkB;IAChC,gBAAgB,EAAE,wBAAwB;IAC1C,gBAAgB,EAAE,wBAAwB;IAC1C,YAAY,EAAE,gBAAgB;IAC9B,eAAe,EAAE,wBAAwB;IACzC,WAAW,EAAE,wBAAwB;IACrC,eAAe,EAAE,YAAY;IAC7B,MAAM,EAAE,iBAAiB;IACzB,WAAW,EAAE,SAAS;IACtB,YAAY,EAAE,mBAAmB;IACjC,UAAU,EAAE,SAAS;IACrB,MAAM,EAAE,2BAA2B;CACpC,CAAC"}
\ No newline at end of file
~~~~

## H43 — .claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts — insertion after head line 14

Head context (head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts, lines 3–26):

~~~~text
     3 | // Source: .claude/defaults/model-config.yaml
     4 | //
     5 | // Per-provider defaults applied at codegen time (yaml tracks API context_window
     6 | // only; maxOutput + coefficient are BB-skill truncation heuristics):
     7 | //   anthropic / bedrock / google: maxOutput=8192, coefficient=0.25
     8 | //   openai:                       maxOutput=4096, coefficient=0.23
     9 | //   default fallback:             maxInput=100000, maxOutput=4096, coefficient=0.25
    10 | //
    11 | // maxInput = effective_input_ceiling − 20000 when the yaml entry carries the
    12 | // v3 ceiling (cycle-124 FR-3 / SDD §2.1: BB truncates below cheval's pre-flight
    13 | // gate instead of dispatching what exit 7 would reject), else context_window.
    14 | //
    15 | // cycle-099 sprint-1 (T1.1). See SDD §1.4.3 + §5.3.
    16 | 
    17 | import type { TokenBudget } from "./types.js";
    18 | 
    19 | export const GENERATED_TOKEN_BUDGETS: Record<string, TokenBudget> = {
    20 |   "claude-fable-5": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    21 |   "claude-fable-5-1": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    22 |   "claude-haiku-4-5-20251001": { maxInput: 160000, maxOutput: 8192, coefficient: 0.25 },
    23 |   "claude-headless": { maxInput: 1000000, maxOutput: 8192, coefficient: 0.25 },
    24 |   "claude-opus-4-6": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    25 |   "claude-opus-4-7": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
    26 |   "claude-opus-4-8": { maxInput: 160000, maxOutput: 32000, coefficient: 0.25 },
~~~~

The change from head to the fix:

~~~~diff
@@ -14,0 +15,6 @@
+// GENERATED_MODEL_ALIASES maps the catalog's `aliases:` block to bare model
+// ids (provider-qualified targets only; self-maps dropped) so an alias such as
+// `opus` gets its target's budget. An operator alias overlay in
+// .loa.config.yaml is NOT reflected — pin a concrete model or set
+// max_input_tokens (cycle-126 sprint-250).
+//
~~~~

## H44 — .claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts — insertion after head line 53

Head context (head/.claude/skills/bridgebuilder-review/resources/core/truncation.generated.ts, lines 42–53):

~~~~text
    42 |   "gemini-3-flash-preview": { maxInput: 1048576, maxOutput: 8192, coefficient: 0.25 },
    43 |   "gemini-3.1-pro-preview": { maxInput: 1048576, maxOutput: 32000, coefficient: 0.25 },
    44 |   "gemini-headless": { maxInput: 1048576, maxOutput: 8192, coefficient: 0.25 },
    45 |   "codex-headless": { maxInput: 400000, maxOutput: 4096, coefficient: 0.23 },
    46 |   "gpt-5.2": { maxInput: 128000, maxOutput: 16000, coefficient: 0.23 },
    47 |   "gpt-5.3-codex": { maxInput: 400000, maxOutput: 32000, coefficient: 0.23 },
    48 |   "gpt-5.5": { maxInput: 400000, maxOutput: 32000, coefficient: 0.23 },
    49 |   "gpt-5.5-pro": { maxInput: 400000, maxOutput: 32000, coefficient: 0.23 },
    50 |   "grok-build": { maxInput: 256000, maxOutput: 4096, coefficient: 0.25 },
    51 |   "grok-composer-2.5-fast": { maxInput: 256000, maxOutput: 4096, coefficient: 0.25 },
    52 |   "default": { maxInput: 100000, maxOutput: 4096, coefficient: 0.25 },
    53 | };
~~~~

The change from head to the fix:

~~~~diff
@@ -53,0 +60,21 @@
+
+export const GENERATED_MODEL_ALIASES: Record<string, string> = {
+  "cheap": "claude-sonnet-5",
+  "cursor-composer": "composer-2.5",
+  "cursor-fast": "composer-2.5-fast",
+  "cursor-headless": "composer-2.5",
+  "deep-thinker": "gemini-3.1-pro-preview",
+  "fable": "claude-fable-5-1",
+  "gemini-2.0": "gemini-2.0-flash",
+  "gemini-3-flash": "gemini-3-flash-preview",
+  "gemini-3.1-pro": "gemini-3.1-pro-preview",
+  "gemini-api": "gemini-2.5-pro",
+  "grok-composer": "grok-composer-2.5-fast",
+  "grok-fast": "grok-composer-2.5-fast",
+  "grok-headless": "grok-build",
+  "opus": "claude-opus-5-5",
+  "reasoning": "gpt-5.5",
+  "researcher": "deep-research-pro",
+  "reviewer": "gpt-5.5",
+  "tiny": "claude-haiku-4-5-20251001",
+};
~~~~

## H45 — docs/migration/v2.0-model-generation-floor.md — head line 230

Head context (head/docs/migration/v2.0-model-generation-floor.md, lines 218–242):

~~~~text
   218 |   line byte-for-byte, holds the writer's own lock while it rewrites the file
   219 |   in place (a `cheval` call that lands during the pass simply appends after
   220 |   it), first copies the previous bytes to `<ledger>.pre-reprice-<UTC>` (your
   221 |   recovery point) and writes `.run/cost-ledger-reprice-<UTC>.json`. Nothing
   222 |   is re-priced unless you ask.
   223 | 
   224 | ### Cycle-126 addendum — full size, two voices, context class, current generation (unreleased)
   225 | 
   226 | | Old way | New way | Switch back |
   227 | |---|---|---|
   228 | | One literal input ceiling, preempted above it | the bound comes from the resolved catalog entry: `probed_ceiling` (180,000) until `ceiling_calibration.calibrated_at` is set; the output budget shrinks to a 4,096 floor before a refusal | `LOA_CHEVAL_LEGACY_CEILING=1`; `LOA_CHEVAL_MAX_INPUT_TOKENS` lowers any bound |
   229 | | `temperature: 0.7` on every request | unset, so absent from the wire unless you set it | set `temperature`, or `LOA_CHEVAL_LEGACY_WIRE=1` (0.7 again) |
>  230 | | Bridgebuilder default model `claude-opus-4-7` | `DEFAULTS.model` is the `opus` alias, 200,000 in / 32,000 out | `BRIDGEBUILDER_MODEL=<id>` or the skill config |
   231 | | One dissent voice | a companion voice from the other provider family runs beside the primary | `flatline_protocol.{code_review,security_audit}.companion_voice: false` |
   232 | | One set of context-clearing thresholds | `long` (default) or `standard` (a ≤ 200K-window session model), written to `.run/context-class` at session start | `LOA_CONTEXT_CLASS=long` |
   233 | | `opus` → `claude-opus-5`, `cheap` → `claude-sonnet-4-6` | `opus` → `claude-opus-5-5`, `cheap` → `claude-sonnet-5` | pin the explicit id (`claude-opus-5`, `claude-sonnet-4-6`) |
   234 | 
   235 | - **Calibrate the input ceiling once per model.** A request above the probed
   236 |   bound with a `high`-uncertainty estimate is refused with the command to run:
   237 |   `python3 tools/ceiling-probe-live.py --model <id> --write-catalog`. It writes
   238 |   the measured ceiling and `calibrated_at` into the catalog entry and leaves
   239 |   every other line alone. `LOA_CHEVAL_UNCALIBRATED_CEILING=derived` uses the
   240 |   catalog-derived bound (`context_window − max_tokens`) before calibration.
   241 | - **A host with one provider family.** The companion voice has no route there
   242 |   and is recorded as `planned: false` (`reason: no_route`). On
~~~~

The change from head to the fix:

~~~~diff
@@ -230 +230 @@
-| Bridgebuilder default model `claude-opus-4-7` | `DEFAULTS.model` is the `opus` alias, 200,000 in / 32,000 out | `BRIDGEBUILDER_MODEL=<id>` or the skill config |
+| Bridgebuilder default model `claude-opus-4-7` | `DEFAULTS.model` is the `opus` alias; 200,000 is Bridgebuilder's own `maxInputTokens` default (`config.ts`), with 32,000 out. cheval still applies its own input bound (`probed_ceiling` 180,000 until calibration) and refuses a larger payload with the calibrate-first message, so set `max_input_tokens` ≤ 180,000 to stay under it | `BRIDGEBUILDER_MODEL=<id>` or the skill config |
~~~~

## H46 — docs/migration/v2.0-model-generation-floor.md — head lines 247–248

Head context (head/docs/migration/v2.0-model-generation-floor.md, lines 235–260):

~~~~text
   235 | - **Calibrate the input ceiling once per model.** A request above the probed
   236 |   bound with a `high`-uncertainty estimate is refused with the command to run:
   237 |   `python3 tools/ceiling-probe-live.py --model <id> --write-catalog`. It writes
   238 |   the measured ceiling and `calibrated_at` into the catalog entry and leaves
   239 |   every other line alone. `LOA_CHEVAL_UNCALIBRATED_CEILING=derived` uses the
   240 |   catalog-derived bound (`context_window − max_tokens`) before calibration.
   241 | - **A host with one provider family.** The companion voice has no route there
   242 |   and is recorded as `planned: false` (`reason: no_route`). On
   243 |   `security_audit` that marks every audit `DEGRADED_SECURITY_REVIEW`, so set
   244 |   `companion_voice: false` on that block when one voice is the host's shape.
   245 | - **Opus 5.5 is the `opus` alias.** `claude-opus-5-5` has a 1M-token window
   246 |   at standard pricing ($4 / $20 per MTok, $0.20 cache read) and no
>  247 |   long-context tier. Until it is calibrated, its input bound is the probed
>  248 |   180,000. Every Anthropic entry in the catalog, direct or through Bedrock,
   249 |   now has a `model-permissions.yaml` row with the same trust scopes as
   250 |   `claude-opus-4-7`. The rows have no runtime effect unless
   251 |   `hounfour.feature_flags.context_filtering` is on.
   252 | - **Implement-gate evidence on `/loa`.** `/loa` prints an `Implement gate:`
   253 |   line. The Claude Code PreToolUse payload carries no harness-set skill
   254 |   field (https://code.claude.com/docs/en/hooks), and `tool_input` is written
   255 |   by the model. The gate therefore stays heuristic: it reads the run state in
   256 |   `.run/`. A `tool_input.active_skill` field is recorded once, as evidence
   257 |   only, and never changes the gate's decision.
   258 | - **Run preflight reads permission rules the way Claude Code does.**
   259 |   `Bash(git push:*)` and `Bash(git push *)` are the same wildcard rule, and a
   260 |   broader one (`Bash(git:*)`) covers both. Whitespace around the body is
~~~~

The change from head to the fix:

~~~~diff
@@ -247,2 +247,4 @@
-  long-context tier. Until it is calibrated, its input bound is the probed
-  180,000. Every Anthropic entry in the catalog, direct or through Bedrock,
+  long-context tier. The other 5-family entries (Fable 5.1, Fable 5, Opus 5,
+  Sonnet 5) keep an unverified 2×/1.5× tier above 200K pending invoice
+  confirmation. Until `claude-opus-5-5` is calibrated, its input bound is the
+  probed 180,000. Every Anthropic entry in the catalog, direct or through Bedrock,
~~~~

## H47 — docs/migration/v2.0-model-generation-floor.md — head lines 262–263

Head context (head/docs/migration/v2.0-model-generation-floor.md, lines 250–269):

~~~~text
   250 |   `claude-opus-4-7`. The rows have no runtime effect unless
   251 |   `hounfour.feature_flags.context_filtering` is on.
   252 | - **Implement-gate evidence on `/loa`.** `/loa` prints an `Implement gate:`
   253 |   line. The Claude Code PreToolUse payload carries no harness-set skill
   254 |   field (https://code.claude.com/docs/en/hooks), and `tool_input` is written
   255 |   by the model. The gate therefore stays heuristic: it reads the run state in
   256 |   `.run/`. A `tool_input.active_skill` field is recorded once, as evidence
   257 |   only, and never changes the gate's decision.
   258 | - **Run preflight reads permission rules the way Claude Code does.**
   259 |   `Bash(git push:*)` and `Bash(git push *)` are the same wildcard rule, and a
   260 |   broader one (`Bash(git:*)`) covers both. Whitespace around the body is
   261 |   trimmed. A rule with no trailing wildcard (`Bash(git push)`) is exact: it
>  262 |   allows or denies only that command, never the generic requirement. Deny
>  263 |   still wins over allow, in any settings layer.
   264 | 
   265 | ## Non-goals / explicitly unchanged
   266 | 
   267 | - No change to the audit-envelope chain semantics, the zone model, or the
   268 |   hook wiring contract (the upstream hook hardening is fail-loud tightening, not a new surface).
   269 | - The per-sprint a2a record of the cycle is on the branch `record/cycle-124-a2a`, not on `main`.
~~~~

The change from head to the fix:

~~~~diff
@@ -262,2 +264,10 @@
-  allows or denies only that command, never the generic requirement. Deny
-  still wins over allow, in any settings layer.
+  allows or denies only that command, never the generic requirement. A
+  universal rule (bare `Bash`, `Bash(*)`, or the empty prefix `Bash(:*)`)
+  covers every requirement: as an allow it satisfies each one, as a deny it
+  denies each one. Deny still wins over allow, in any settings layer.
+- **`opus` callers that pass no effort get the model-side default.** cheval
+  sends `output_config.effort` only when the caller passes `--effort` (or
+  the request metadata carries one). After the `opus` retarget to
+  `claude-opus-5-5`, a caller that omits it runs at Opus 5.5's own default,
+  which need not match Opus 5's. Pass `--effort high` wherever the previous
+  behaviour is required.
~~~~

## H48 — evals/graders/recall-vs-defects.sh — insertion after head line 22

Head context (head/evals/graders/recall-vs-defects.sh, lines 11–34):

~~~~text
    11 | # when the review contains a `path:line` (or `path:line-line`) citation whose
    12 | # path ends with the defect's file (repo-relative, `head/`-prefixed, or the
    13 | # bare basename) and whose line, or line range, falls within ±3 of the
    14 | # manifest anchor — `anchor_line`, or any line in `anchors[]` for a defect
    15 | # with more than one site.
    16 | #
    17 | # Parser (1.1.0, bd-ewrc): a leading `(` is not part of the path; comma
    18 | # continuations (`path:776,807`, `path:10, 118-121`) and a later bare `:N` or
    19 | # `head:N` / `base:N` bind to the most recent cited path. A `:N` glued to a
    20 | # word or a number (`note:40`, `10:40`), or with no cited path before it,
    21 | # credits nothing.
    22 | #
    23 | # Clean fixtures (0 planted defects) measure FALSE POSITIVES: the LOA-VERDICT
    24 | # trailer's critical+high counts; without a trailer, every file:line citation
    25 | # counts as one.
    26 | #
    27 | # Output: {"pass", "score", "details":{recall, planted, detected[], missed[],
    28 | #          false_positives, severity_counts, model, effort, tokens}, "grader_version"}
    29 | #   pass  = every planted defect detected (defect fixture) / zero false
    30 | #           positives (clean fixture); score = recall*100 or 100/0.
    31 | # Exit: 0 pass, 1 fail, 2 error (missing manifest / bad args)
    32 | #
    33 | # Tested by evals/tests/eval-recall-grader.bats.
    34 | # =============================================================================
~~~~

The change from head to the fix:

~~~~diff
@@ -22,0 +23,19 @@
+# Parser 1.1.1 (sprint-250 review run 1, n40-n42): the LOA-VERDICT trailer is
+# removed before citations are parsed, and a bare `:N` after a quote, bracket,
+# brace or `*` (JSON such as `"high":3`) credits nothing; a backtick- or
+# bold-wrapped path (`` `b.sh`:40 ``, `**b.sh**:40`) binds its own line; a comma
+# continuation or range stays on its line, and a continuation must end at a
+# number boundary (no dates);
+# a path containing `//` (a URL) is not a citation.
+# Run 2 (#11/#13-#15): a match inside any URL token (`scheme://...`) is not a
+# citation; a range dash is unspaced and every number (first, continuation,
+# bare) ends at a boundary (no further `-N` / `–N`: no dates); the
+# quote/bracket guard applies only to the fully bare `:N` (plus a closing
+# backtick), so `"head:40"` binds as in 1.1.0; one trailer pattern strips and
+# reads the LOA-VERDICT comment and never crosses another comment's bounds.
+# Parser 1.1.2 (the run 2 changes above, plus sprint-250 review run 3): the
+# URL look-back takes the text after the last whitespace — one linear split —
+# so a citation that opens a line never inherits the previous line's URL.
+# The parser runs as `python3 -I -` (audit dissent run 1, n32): a module planted
+# in the invoker's cwd (a forging json.py) is never imported (RG-27).
+#
~~~~

## H49 — evals/graders/recall-vs-defects.sh — head line 44

Head context (head/evals/graders/recall-vs-defects.sh, lines 32–56):

~~~~text
    32 | #
    33 | # Tested by evals/tests/eval-recall-grader.bats.
    34 | # =============================================================================
    35 | set -euo pipefail
    36 | 
    37 | workspace="${1:-}"
    38 | fixture="${2:-}"
    39 | review_name="${3:-review.md}"
    40 | 
    41 | SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    42 | MANIFEST_DIR="${EVAL_MANIFEST_DIR:-$SCRIPT_DIR/../fixtures/review-prs/manifests}"
    43 | 
>   44 | err() { printf '{"pass":false,"score":0,"details":{"error":%s},"grader_version":"1.1.0"}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 2; }
    45 | 
    46 | [[ -n "$workspace" && -d "$workspace" ]] || err "invalid workspace"
    47 | [[ -n "$fixture" && "$fixture" =~ ^[A-Za-z0-9._-]+$ ]] || err "invalid fixture id"
    48 | manifest="$MANIFEST_DIR/$fixture.json"
    49 | [[ -f "$manifest" ]] || err "manifest not found: $manifest"
    50 | case "$review_name" in */*|..*) err "review file must be a bare name" ;; esac
    51 | 
    52 | review="$workspace/$review_name"
    53 | executor="$workspace/.eval/executor.json"
    54 | 
    55 | if [[ ! -f "$review" ]]; then
    56 |   printf '{"pass":false,"score":0,"details":{"error":"review file not found: %s","planted":%s,"detected":[],"recall":0},"grader_version":"1.1.0"}\n' \
~~~~

The change from head to the fix:

~~~~diff
@@ -44 +63 @@
-err() { printf '{"pass":false,"score":0,"details":{"error":%s},"grader_version":"1.1.0"}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 2; }
+err() { printf '{"pass":false,"score":0,"details":{"error":%s},"grader_version":"1.1.2"}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 2; }
~~~~

## H50 — evals/graders/recall-vs-defects.sh — head line 56

Head context (head/evals/graders/recall-vs-defects.sh, lines 44–68):

~~~~text
    44 | err() { printf '{"pass":false,"score":0,"details":{"error":%s},"grader_version":"1.1.0"}\n' "$(jq -Rn --arg m "$1" '$m')"; exit 2; }
    45 | 
    46 | [[ -n "$workspace" && -d "$workspace" ]] || err "invalid workspace"
    47 | [[ -n "$fixture" && "$fixture" =~ ^[A-Za-z0-9._-]+$ ]] || err "invalid fixture id"
    48 | manifest="$MANIFEST_DIR/$fixture.json"
    49 | [[ -f "$manifest" ]] || err "manifest not found: $manifest"
    50 | case "$review_name" in */*|..*) err "review file must be a bare name" ;; esac
    51 | 
    52 | review="$workspace/$review_name"
    53 | executor="$workspace/.eval/executor.json"
    54 | 
    55 | if [[ ! -f "$review" ]]; then
>   56 |   printf '{"pass":false,"score":0,"details":{"error":"review file not found: %s","planted":%s,"detected":[],"recall":0},"grader_version":"1.1.0"}\n' \
    57 |     "$review_name" "$(jq '.defects | length' "$manifest")"
    58 |   exit 1
    59 | fi
    60 | 
    61 | python3 - "$manifest" "$review" "$executor" <<'PY'
    62 | import json, re, sys
    63 | manifest_path, review_path, executor_path = sys.argv[1:4]
    64 | man = json.load(open(manifest_path))
    65 | text = open(review_path, encoding="utf-8", errors="replace").read()
    66 | 
    67 | # path:line[-line] citations. Path = something with a file extension; the
    68 | # optional trailing range keeps `file.py:10-14` in one token, and the comma
~~~~

The change from head to the fix:

~~~~diff
@@ -56 +75 @@
-  printf '{"pass":false,"score":0,"details":{"error":"review file not found: %s","planted":%s,"detected":[],"recall":0},"grader_version":"1.1.0"}\n' \
+  printf '{"pass":false,"score":0,"details":{"error":"review file not found: %s","planted":%s,"detected":[],"recall":0},"grader_version":"1.1.2"}\n' \
~~~~

## H51 — evals/graders/recall-vs-defects.sh — head line 61

Head context (head/evals/graders/recall-vs-defects.sh, lines 49–73):

~~~~text
    49 | [[ -f "$manifest" ]] || err "manifest not found: $manifest"
    50 | case "$review_name" in */*|..*) err "review file must be a bare name" ;; esac
    51 | 
    52 | review="$workspace/$review_name"
    53 | executor="$workspace/.eval/executor.json"
    54 | 
    55 | if [[ ! -f "$review" ]]; then
    56 |   printf '{"pass":false,"score":0,"details":{"error":"review file not found: %s","planted":%s,"detected":[],"recall":0},"grader_version":"1.1.0"}\n' \
    57 |     "$review_name" "$(jq '.defects | length' "$manifest")"
    58 |   exit 1
    59 | fi
    60 | 
>   61 | python3 - "$manifest" "$review" "$executor" <<'PY'
    62 | import json, re, sys
    63 | manifest_path, review_path, executor_path = sys.argv[1:4]
    64 | man = json.load(open(manifest_path))
    65 | text = open(review_path, encoding="utf-8", errors="replace").read()
    66 | 
    67 | # path:line[-line] citations. Path = something with a file extension; the
    68 | # optional trailing range keeps `file.py:10-14` in one token, and the comma
    69 | # list after it (`:776,807`) belongs to the same path. A bare `:N` (or
    70 | # `head:N` / `base:N`) not glued to a word binds to the most recent path.
    71 | RNG = r'(\d{1,6})(?:\s*[-–]\s*(\d{1,6}))?'
    72 | CITE = re.compile(
    73 |     r'(?P<path>[A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6}):(?P<first>' + RNG + r'(?:\s*,\s*' + RNG + r')*)'
~~~~

The change from head to the fix:

~~~~diff
@@ -61 +80 @@
-python3 - "$manifest" "$review" "$executor" <<'PY'
+python3 -I - "$manifest" "$review" "$executor" <<'PY'
~~~~

## H52 — evals/graders/recall-vs-defects.sh — head lines 71–79

Head context (head/evals/graders/recall-vs-defects.sh, lines 59–91):

~~~~text
    59 | fi
    60 | 
    61 | python3 - "$manifest" "$review" "$executor" <<'PY'
    62 | import json, re, sys
    63 | manifest_path, review_path, executor_path = sys.argv[1:4]
    64 | man = json.load(open(manifest_path))
    65 | text = open(review_path, encoding="utf-8", errors="replace").read()
    66 | 
    67 | # path:line[-line] citations. Path = something with a file extension; the
    68 | # optional trailing range keeps `file.py:10-14` in one token, and the comma
    69 | # list after it (`:776,807`) belongs to the same path. A bare `:N` (or
    70 | # `head:N` / `base:N`) not glued to a word binds to the most recent path.
>   71 | RNG = r'(\d{1,6})(?:\s*[-–]\s*(\d{1,6}))?'
>   72 | CITE = re.compile(
>   73 |     r'(?P<path>[A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6}):(?P<first>' + RNG + r'(?:\s*,\s*' + RNG + r')*)'
>   74 |     r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])')
>   75 | ONE = re.compile(RNG)
>   76 | cites = []
>   77 | last = None
>   78 | for m in CITE.finditer(text):
>   79 |     if m.group("path") is not None:
    80 |         p = m.group("path").lstrip("(")
    81 |         if p.startswith("./"):
    82 |             p = p[2:]
    83 |         last, spans = p, m.group("first")
    84 |     elif last is not None:
    85 |         p, spans = last, m.group("bare")
    86 |     else:
    87 |         continue
    88 |     for r in ONE.finditer(spans):
    89 |         a = int(r.group(1)); b = int(r.group(2)) if r.group(2) else a
    90 |         if b < a:
    91 |             a, b = b, a
~~~~

The change from head to the fix:

~~~~diff
@@ -71,9 +90,35 @@
-RNG = r'(\d{1,6})(?:\s*[-–]\s*(\d{1,6}))?'
+# a range dash is unspaced (`a.sh:12 - 40 rows` is prose, not a range) and
+# every number ends at a boundary: no letter or digit, and no hyphen / en dash
+# before another digit, after it (dates such as 2026-10-05 / 2026–10–05 never
+# parse; an open `:369-...` still cites 369) — sprint-250 review run 2, #13
+RNG = r'(\d{1,6})(?:[-–](\d{1,6}))?(?![A-Za-z0-9]|[-–]\d)'
 CITE = re.compile(
-    r'(?P<path>[A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6}):(?P<first>' + RNG + r'(?:\s*,\s*' + RNG + r')*)'
-    r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:])):(?P<bare>' + RNG + r')(?![A-Za-z0-9])')
+    r'(?P<path>[A-Za-z0-9_./+()-]+\.[A-Za-z0-9]{1,6})[`*)]{0,3}:(?P<first>' + RNG
+    + r'(?:[ \t]*,[ \t]*' + RNG + r')*)'
+    # head:N / base:N keep the 1.1.0 boundary set ("head:40" binds); the JSON
+    # punctuation set, plus a CLOSING backtick (one after a token character:
+    # `rows`:40, `"high"`:3), guards only the fully bare :N — an opening
+    # backtick (`:7`, (`:212`)) still binds (RG-13) — run 2, #14
+    r'|(?:(?<![A-Za-z0-9_./:])(?:head|base)|(?<![A-Za-z0-9_./:"\'{}\[\]*])(?<![A-Za-z0-9_"\'}\]]`)):(?P<bare>' + RNG + r')')
 ONE = re.compile(RNG)
 cites = []
 last = None
-for m in CITE.finditer(text):
+# the trailer is machine output (its counts are read below), never a citation.
+# One pattern strips and reads it (tolerant whitespace, line breaks); the body
+# may not contain another comment's `<!--` or `-->`, so an unterminated
+# `<!-- LOA-VERDICT` strips nothing — sprint-250 review run 2, #15
+TRAILER = re.compile(r'<!--\s*LOA-VERDICT\s*(\{(?:(?!<!--|-->).)*\})\s*-->', re.S)
+body = TRAILER.sub('', text)
+URL = re.compile(r'[A-Za-z][A-Za-z0-9+.-]*://|^//')
+for m in CITE.finditer(body):
     if m.group("path") is not None:
+        # a URL (https://h/x.js:8080, //host.com:8080) is not a path, nor is a
+        # partial match that starts later inside the URL token
+        # (https://u@h.com/x.js:8080 matches `h.com/x.js`) — run 2, #11
+        # the token so far is the window's text after its last whitespace —
+        # one linear split ("" when the window ends in whitespace); `\S*$`
+        # also matched before a final newline, so a line-leading citation
+        # inherited the previous line's URL, and was O(k^2) — run 3
+        tok = re.split(r'\s', body[max(0, m.start() - 4096):m.start()])[-1] + m.group("path")
+        if "//" in m.group("path") or URL.search(tok):
+            continue
~~~~

## H53 — evals/graders/recall-vs-defects.sh — head line 113

Head context (head/evals/graders/recall-vs-defects.sh, lines 101–125):

~~~~text
   101 | detected, missed = [], []
   102 | for d in man.get("defects", []):
   103 |     sites = d.get("anchors") or [d["anchor_line"]]
   104 |     hit = any(path_matches(p, d["file"]) and not (b < s - 3 or a > s + 3)
   105 |               for p, a, b in cites for s in sites)
   106 |     (detected if hit else missed).append(d["id"])
   107 | 
   108 | planted = len(man.get("defects", []))
   109 | recall = round(len(detected) / planted, 4) if planted else None
   110 | 
   111 | # trailer → severity counts (false positives on clean fixtures)
   112 | sev = None
>  113 | tm = re.search(r'<!-- LOA-VERDICT (\{.*\}) -->', text)
   114 | if tm:
   115 |     try:
   116 |         sev = json.loads(tm.group(1)).get("counts")
   117 |     except Exception:
   118 |         sev = None
   119 | if isinstance(sev, dict):
   120 |     fp = int(sev.get("critical", 0) or 0) + int(sev.get("high", 0) or 0)
   121 | else:
   122 |     fp = len({(p, a, b) for p, a, b in cites})
   123 | false_positives = fp if planted == 0 else 0
   124 | 
   125 | model = effort = None
~~~~

The change from head to the fix:

~~~~diff
@@ -113 +158 @@
-tm = re.search(r'<!-- LOA-VERDICT (\{.*\}) -->', text)
+tm = TRAILER.search(text)
~~~~

## H54 — evals/graders/recall-vs-defects.sh — head line 155

Head context (head/evals/graders/recall-vs-defects.sh, lines 143–159):

~~~~text
   143 | else:
   144 |     ok = false_positives == 0
   145 |     score = 100 if ok else 0
   146 | 
   147 | out = {
   148 |     "pass": ok,
   149 |     "score": score,
   150 |     "details": {
   151 |         "recall": recall, "planted": planted, "detected": detected, "missed": missed,
   152 |         "false_positives": false_positives, "severity_counts": sev,
   153 |         "citations": len(cites), "model": model, "effort": effort, "tokens": tokens,
   154 |     },
>  155 |     "grader_version": "1.1.0",
   156 | }
   157 | print(json.dumps(out))
   158 | sys.exit(0 if ok else 1)
   159 | PY
~~~~

The change from head to the fix:

~~~~diff
@@ -155 +200 @@
-    "grader_version": "1.1.0",
+    "grader_version": "1.1.2",
~~~~

## H55 — evals/tests/eval-recall-grader.bats — head lines 180–185

Head context (head/evals/tests/eval-recall-grader.bats, lines 168–185):

~~~~text
   168 | @test "RG-16 the two real multi-site manifests carry anchors[] (pr-05 D13 776/807, pr-02 D06 57/83), each a real site" {
   169 |   local M="$REPO_ROOT/evals/fixtures/review-prs/manifests" F="$REPO_ROOT/evals/fixtures/review-prs"
   170 |   [ "$(jq -c '.defects[] | select(.id=="D13-find-exec-multi-root") | .anchors' "$M/pr-05.json")" = "[776,807]" ]
   171 |   [ "$(jq -c '.defects[] | select(.id=="D06-prerelease-tags-rejected") | .anchors' "$M/pr-02.json")" = "[57,83]" ]
   172 |   sed -n 776p "$F/pr-05/head/.claude/hooks/safety/block-destructive-bash.sh" | grep -q '_re_find_exec_prefix='
   173 |   sed -n 57p "$F/pr-02/head/.claude/scripts/semver-bump.sh" | grep -q "tag -l 'v\[0-9\]\*"
   174 |   # every anchors[] list contains its anchor_line, so the field only ever widens detection
   175 |   for f in "$M"/*.json; do
   176 |     jq -e '[.defects[] | select(has("anchors")) | . as $d | .anchors | index($d.anchor_line) != null] | all' "$f" >/dev/null
   177 |   done
   178 | }
   179 | 
>  180 | @test "RG-17 grader_version is 1.1.0 (the bd-ewrc parser); the manifest corpus checksum list matches the manifests" {
>  181 |   review 'a.sh:40'
>  182 |   run "$GRADER" "$WS" pr-x
>  183 |   [ "$(echo "$output" | jq -r '.grader_version')" = "1.1.0" ]
>  184 |   ( cd "$REPO_ROOT/evals/fixtures/review-prs" && grep ' manifests/' SHA256SUMS | sha256sum -c --quiet - )
>  185 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -180,6 +180,163 @@
-@test "RG-17 grader_version is 1.1.0 (the bd-ewrc parser); the manifest corpus checksum list matches the manifests" {
+@test "RG-17 grader_version is 1.1.2 (the bd-ewrc parser, sprint-250 hardening through review run 3); the manifest corpus checksum list matches the manifests" {
   review 'a.sh:40'
   run "$GRADER" "$WS" pr-x
-  [ "$(echo "$output" | jq -r '.grader_version')" = "1.1.0" ]
+  [ "$(echo "$output" | jq -r '.grader_version')" = "1.1.2" ]
   ( cd "$REPO_ROOT/evals/fixtures/review-prs" && grep ' manifests/' SHA256SUMS | sha256sum -c --quiet - )
 }
+
+# --- sprint-250 review run 1 (n40/n41/n42): grader 1.1.1 parser hardening ---
+@test "RG-18 the LOA-VERDICT trailer and JSON numbers are not citations: \"high\":3 never binds to the last cited path" {
+  cat > "$T/manifests/pr-z.json" <<'JSON'
+{"fixture":"pr-z","defects":[
+ {"id":"Z1","file":".claude/scripts/a.sh","anchor_line":3,"severity":"high","category":"logic","source_commit":"deadbeef","synthetic":false}
+]}
+JSON
+  printf 'a.sh:12 has a nit\n\n<!-- LOA-VERDICT {"gate":"review","verdict":"CHANGES_REQUIRED","counts":{"critical":0,"high":3,"medium":0,"low":0},"sprint_id":"sprint-0","ts":"2026-01-01T00:00:00Z"} -->\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-z
+  [ "$(echo "$output" | jq -r '.details.missed | join(",")')" = "Z1" ]
+  [ "$(echo "$output" | jq -r '.details.citations')" = "1" ]
+  [ "$(echo "$output" | jq -r '.details.severity_counts.high')" = "3" ]   # the trailer still feeds the counts
+  # the same numbers in a JSON block in the body
+  printf 'a.sh:12 has a nit\n\n```json\n{"critical":0,"high":3, "rows": [3]}\n```\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-z
+  [ "$(echo "$output" | jq -r '.details.missed | join(",")')" = "Z1" ]
+  [ "$(echo "$output" | jq -r '.details.citations')" = "1" ]
+}
+
+@test "RG-19 a comma continuation stays on its line and is a line number: a.sh:12, 2026-10-05 and a.sh:12,<newline>40 rows credit nothing" {
+  review 'a.sh:12, 2026-10-05 is when it landed'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  printf 'a.sh:12,\n40 rows were dropped\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  printf 'a.sh:12\n- 40 rows were dropped\n' > "$WS/review.md"   # nor does a range
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  review 'a.sh:12, 40 on one line still binds'   # RG-12 behaviour kept
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D1" ]
+}
+
+@test "RG-20 a backtick- or bold-wrapped path binds its own line (\`c.sh\`:7, **c.sh**:7); a URL is not a path citation" {
+  review 'a.sh:1 is fine; `c.sh`:7 returns early'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+  review 'a.sh:1 is fine; **c.sh**:7 returns early'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+  printf 'see https://example.com/x.js:8080 and http://example.com:8080/y\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-clean
+  [ "$(echo "$output" | jq -r '.details.citations')" = "0" ]
+  [ "$(echo "$output" | jq -r '.details.false_positives')" = "0" ]
+}
+
+@test "RG-21 a path inside a URL is not a citation, even where the match starts after the scheme (sprint-250 review run 2, #11)" {
+  # `@`/`~`/`%` split the path class, so a later partial match carries no `//`
+  printf 'see https://user@example.com/x.js:8080 and https://example.com/~u/c.sh:7 and https://h.io/%%7Ec.sh:7\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-clean
+  [ "$(echo "$output" | jq -r '.details.citations')" = "0" ]
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  review 'see https://example.com/x.js:8080, then c.sh:7 returns early'   # a real path after a URL still binds
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+}
+
+@test "RG-22 a range is unspaced and ends at a number boundary (ASCII hyphen or en dash): a.sh:12 - 40 rows and dates credit nothing (sprint-250 review run 2, #13)" {
+  review 'a.sh:12 - 40 rows were dropped'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  review 'a.sh:12-2026-10-05 is when it landed'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  review 'a.sh:12, 2026–10–05 is when it landed'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  review 'a.sh:12–2026–10–05 is when it landed'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  review 'c.sh:100 is odd, and :1-2026-10-05 too'   # the bare branch as well
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  review 'a.sh:40-... is open-ended'   # a dash before a non-digit still cites 40
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D1" ]
+  review 'a.sh:12-40 and a.sh:12–40 are ranges'   # RG-3 behaviour kept
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D1" ]
+}
+
+@test "RG-23 a quoted or bracketed head:N binds as in 1.1.0; a bare :N after a closing backtick credits nothing (sprint-250 review run 2, #14)" {
+  review 'c.sh:100 is odd, and "head:7" too'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+  review 'c.sh:100 is odd, and [head:7] too'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+  review 'c.sh:100 is odd; `rows`:7 is a field'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  review 'c.sh:100 is odd; `"high"`:7 is JSON'
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+  review 'c.sh:100 is odd, then `:7` returns early'   # RG-13: an opening backtick still binds
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+  review 'c.sh:100 is odd, then the guard (`:7`) returns early'   # after ( or [ too
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+}
+
+@test "RG-24 one trailer pattern strips and reads: tolerant whitespace and line breaks; an unterminated trailer swallows nothing (sprint-250 review run 2, #15)" {
+  printf 'b.py:1 is a nit\n\n<!--LOA-VERDICT  {"gate":"review","verdict":"APPROVED",\n "counts":{"critical":0,"high":0,"medium":0,"low":0}}\n-->\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-clean
+  [ "$(echo "$output" | jq -r '.details.severity_counts.high')" = "0" ]
+  [ "$(echo "$output" | jq -r '.details.false_positives')" = "0" ]
+  [ "$(echo "$output" | jq -r '.details.citations')" = "1" ]
+  # an unterminated trailer must not eat the citations after it up to a later comment's -->
+  printf '<!-- LOA-VERDICT {broken\nc.sh:7 returns early\n<!-- note -->\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+  # the strip stops at the trailer's own -->
+  printf '<!-- LOA-VERDICT {"counts":{"critical":0,"high":0}} --> c.sh:7 returns early -->\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+}
+
+# --- sprint-250 review run 3: the URL-token look-back is one linear split ---
+@test "RG-25 a line-leading citation after a line ending in a URL binds (LF, CRLF, tab); the URL token never crosses whitespace (sprint-250 review run 3, #1)" {
+  printf 'see https://example.com/pr/1\nc.sh:7 returns early\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+  printf 'see https://example.com/pr/1\r\nc.sh:7 returns early\r\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+  printf 'see https://example.com/pr/1\tc.sh:7 returns early\n' > "$WS/review.md"
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | join(",")')" = "D3" ]
+  printf 'see\nhttps://example.com/~u/c.sh:7\n' > "$WS/review.md"   # a line-leading URL is still a URL
+  run "$GRADER" "$WS" pr-x
+  [ "$(echo "$output" | jq -r '.details.detected | length')" = "0" ]
+}
+
+@test "RG-26 the look-back is linear: a 4,000-char unbroken token before 400 citations grades in under 3 s (sprint-250 review run 3, #1)" {
+  python3 -c "import sys; sys.stdout.write('x' * 4000 + ' ' + ' '.join('c.sh:%d' % i for i in range(1, 401)) + '\n')" > "$WS/review.md"
+  run timeout 3 "$GRADER" "$WS" pr-clean
+  [ "$status" -ne 124 ]
+  [ "$(echo "$output" | jq -r '.details.citations')" = "400" ]
+}
+
+@test "RG-27 a json.py planted in the invoker's cwd is never imported: the grader runs python3 -I (audit dissent run 1, n32)" {
+  review 'nothing cited here'
+  cat > "$WS/json.py" <<'PY'
+import sys
+sys.stdout.write('{"pass":true,"score":100,"forged":true}\n')
+sys.exit(0)
+PY
+  run bash -c 'cd "$1" && "$2" "$1" pr-x' _ "$WS" "$GRADER"
+  [ "$status" -eq 1 ]
+  [ "$(echo "$output" | jq -r '.pass')" = "false" ]
+  [ "$(echo "$output" | jq -r 'has("forged")')" = "false" ]
+  [ "$(echo "$output" | jq -r '.grader_version')" = "1.1.2" ]
+}
~~~~

## H56 — tests/fixtures/ensure_license_fixtures.sh — insertion after head line 38

Head context (head/tests/fixtures/ensure_license_fixtures.sh, lines 27–50):

~~~~text
    27 | _ELF_PUBKEY="$_ELF_DIR/mock_public_key.pem"
    28 | _ELF_GEN="$_ELF_DIR/generate_test_licenses.py"
    29 | 
    30 | # Fast path: ALL fixtures already present. The license JSONs and pubkey are
    31 | # paired (signed by the same keypair) so we re-run the generator if any are
    32 | # missing. Just checking the pubkey was insufficient: if a user deletes a
    33 | # license JSON (or after `git clean` since they're gitignored), the pubkey
    34 | # may still exist but the licenses won't, leaving downstream tests broken.
    35 | _ELF_ALL_PRESENT=true
    36 | for _lic in valid_license.json grace_period_license.json expired_license.json \
    37 |             invalid_signature_license.json team_license.json enterprise_license.json; do
    38 |     [[ -s "$_ELF_DIR/$_lic" ]] || { _ELF_ALL_PRESENT=false; break; }
    39 | done
    40 | if [[ -s "$_ELF_PUBKEY" && "$_ELF_ALL_PRESENT" == "true" ]]; then
    41 |     # Freshness guard: the generator computes expiry relative to now, but a
    42 |     # presence-only cache let stale fixtures survive across days. Every
    43 |     # time-relative window must still be open: valid_license.json's
    44 |     # expires_at (30 days) and grace_period_license.json's
    45 |     # offline_valid_until (12 hours — the tightest, so it goes stale first).
    46 |     # Any closed or unparseable window regenerates the whole set.
    47 |     _elf_future() {  # <file> <field> — exit 0 iff the ISO-8601 Z timestamp is in the future
    48 |         local ts epoch
    49 |         ts="$(grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z\"" "$1" 2>/dev/null \
    50 |               | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' | head -1)"
~~~~

The change from head to the fix:

~~~~diff
@@ -38,0 +39,3 @@
+    # A generator newer than a fixture regenerates the set, so a generator fix
+    # reaches checkouts that already hold fixtures (sprint-250: the naive-UTC exp).
+    [[ "$_ELF_GEN" -nt "$_ELF_DIR/$_lic" ]] && { _ELF_ALL_PRESENT=false; break; }
~~~~

## H57 — tests/fixtures/ensure_license_fixtures.sh — head lines 46–47

Head context (head/tests/fixtures/ensure_license_fixtures.sh, lines 34–59):

~~~~text
    34 | # may still exist but the licenses won't, leaving downstream tests broken.
    35 | _ELF_ALL_PRESENT=true
    36 | for _lic in valid_license.json grace_period_license.json expired_license.json \
    37 |             invalid_signature_license.json team_license.json enterprise_license.json; do
    38 |     [[ -s "$_ELF_DIR/$_lic" ]] || { _ELF_ALL_PRESENT=false; break; }
    39 | done
    40 | if [[ -s "$_ELF_PUBKEY" && "$_ELF_ALL_PRESENT" == "true" ]]; then
    41 |     # Freshness guard: the generator computes expiry relative to now, but a
    42 |     # presence-only cache let stale fixtures survive across days. Every
    43 |     # time-relative window must still be open: valid_license.json's
    44 |     # expires_at (30 days) and grace_period_license.json's
    45 |     # offline_valid_until (12 hours — the tightest, so it goes stale first).
>   46 |     # Any closed or unparseable window regenerates the whole set.
>   47 |     _elf_future() {  # <file> <field> — exit 0 iff the ISO-8601 Z timestamp is in the future
    48 |         local ts epoch
    49 |         ts="$(grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z\"" "$1" 2>/dev/null \
    50 |               | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' | head -1)"
    51 |         [[ -n "$ts" ]] || return 1
    52 |         epoch="$(date -u -d "$ts" +%s 2>/dev/null \
    53 |                  || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null || echo 0)"
    54 |         [[ "${epoch:-0}" -gt "$(date -u +%s)" ]]
    55 |     }
    56 |     if _elf_future "$_ELF_DIR/valid_license.json" expires_at \
    57 |        && _elf_future "$_ELF_DIR/grace_period_license.json" offline_valid_until; then
    58 |         unset -f _elf_future
    59 |         return 0 2>/dev/null || exit 0
~~~~

The change from head to the fix:

~~~~diff
@@ -46,2 +49,5 @@
-    # Any closed or unparseable window regenerates the whole set.
-    _elf_future() {  # <file> <field> — exit 0 iff the ISO-8601 Z timestamp is in the future
+    # Any closed or unparseable window regenerates the whole set, and so does
+    # one closing within 3600 s: a window that closes mid-suite is as stale
+    # (sprint-250 review run 1, n39; run 2, #8 — the full unit run takes
+    # ~38 min, and the 12 h window makes the extra regenerations negligible).
+    _elf_future() {  # <file> <field> — exit 0 iff the ISO-8601 Z timestamp is > now + 3600 s
~~~~

## H58 — tests/fixtures/ensure_license_fixtures.sh — head line 54

Head context (head/tests/fixtures/ensure_license_fixtures.sh, lines 42–66):

~~~~text
    42 |     # presence-only cache let stale fixtures survive across days. Every
    43 |     # time-relative window must still be open: valid_license.json's
    44 |     # expires_at (30 days) and grace_period_license.json's
    45 |     # offline_valid_until (12 hours — the tightest, so it goes stale first).
    46 |     # Any closed or unparseable window regenerates the whole set.
    47 |     _elf_future() {  # <file> <field> — exit 0 iff the ISO-8601 Z timestamp is in the future
    48 |         local ts epoch
    49 |         ts="$(grep -oE "\"$2\"[[:space:]]*:[[:space:]]*\"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z\"" "$1" 2>/dev/null \
    50 |               | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+Z' | head -1)"
    51 |         [[ -n "$ts" ]] || return 1
    52 |         epoch="$(date -u -d "$ts" +%s 2>/dev/null \
    53 |                  || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null || echo 0)"
>   54 |         [[ "${epoch:-0}" -gt "$(date -u +%s)" ]]
    55 |     }
    56 |     if _elf_future "$_ELF_DIR/valid_license.json" expires_at \
    57 |        && _elf_future "$_ELF_DIR/grace_period_license.json" offline_valid_until; then
    58 |         unset -f _elf_future
    59 |         return 0 2>/dev/null || exit 0
    60 |     fi
    61 |     unset -f _elf_future
    62 |     # else: stale (expired or unparseable) → fall through to regenerate
    63 | fi
    64 | 
    65 | # Generate. Requires python3.
    66 | if ! command -v python3 >/dev/null 2>&1; then
~~~~

The change from head to the fix:

~~~~diff
@@ -54 +60 @@
-        [[ "${epoch:-0}" -gt "$(date -u +%s)" ]]
+        [[ "${epoch:-0}" -gt $(( $(date -u +%s) + 3600 )) ]]
~~~~

## H59 — tests/fixtures/pretooluse-payloads/expected.tsv — head lines 5–13

Head context (head/tests/fixtures/pretooluse-payloads/expected.tsv, lines 1–13):

~~~~text
     1 | # PreToolUse stdin shapes per https://code.claude.com/docs/en/hooks (read 2026-10-05): the common fields,
     2 | # plus agent_id/agent_type inside a subagent. The harness sets no active_skill field; where a fixture carries
     3 | # tool_input.active_skill it is what a model-authored tool_input can contain. __ROOT__ is the test project root.
     4 | # fixture	heuristic	authoritative	records_evidence
>    5 | # Decisions with no RUNNING state in .run/: "ask" = the gate emits {"decision":"ask"}, "allow" = silent exit 0.
>    6 | # records_evidence: the lead-session recorder writes active_skill_seen_at (yes) or nothing (no).
>    7 | write-src-plain.json	ask	ask	no
>    8 | write-src-active-implement.json	ask	allow	yes
>    9 | edit-lib-active-bug.json	ask	allow	yes
>   10 | write-app-active-review.json	ask	ask	yes
>   11 | write-src-subagent-run.json	ask	allow	no
>   12 | edit-src-subagent-plain.json	ask	ask	no
>   13 | write-state-active-review.json	allow	allow	yes
~~~~

The change from head to the fix:

~~~~diff
@@ -5,9 +5,14 @@
-# Decisions with no RUNNING state in .run/: "ask" = the gate emits {"decision":"ask"}, "allow" = silent exit 0.
+# Decisions with no RUNNING state in .run/: "ask" = the gate prints
+# {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"…"}} on stdout,
+# "allow" = silent exit 0 with empty stdout. Authoritative is tighten-only: a claimed implementation skill
+# falls through to the heuristic, so it asks here; a claimed non-implementation skill always asks.
 # records_evidence: the lead-session recorder writes active_skill_seen_at (yes) or nothing (no).
 write-src-plain.json	ask	ask	no
-write-src-active-implement.json	ask	allow	yes
-edit-lib-active-bug.json	ask	allow	yes
+write-src-active-implement.json	ask	ask	yes
+edit-lib-active-bug.json	ask	ask	yes
 write-app-active-review.json	ask	ask	yes
-write-src-subagent-run.json	ask	allow	no
+write-src-subagent-run.json	ask	ask	no
 edit-src-subagent-plain.json	ask	ask	no
 write-state-active-review.json	allow	allow	yes
+notebook-src-plain.json	ask	ask	no
+write-Src-plain.json	ask	ask	no
~~~~

## H60 — tests/unit/adversarial-review-companion.bats — head line 628

Head context (head/tests/unit/adversarial-review-companion.bats, lines 616–640):

~~~~text
   616 |     reason=$(jq -r '.metadata.rejected_summary[0].reason' <<<"$result")
   617 |     [ -n "$reason" ]
   618 |     [ "$reason" != "null" ]
   619 |     [ "$(jq -r '.reject_reason' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "$reason" ]
   620 |     [ "$(jq -r '.model' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "claude-headless" ]
   621 |     [ ! -s "$OUT_DIR/adversarial-rejected-review.jsonl" ]
   622 |     # c C-005: the repair round-trip went through the stubbed dissenter (dissent + repair), never a live CLI
   623 |     [ "$(grep -cx claude-headless "$CALLS")" = "2" ]
   624 | }
   625 | 
   626 | @test "CMP-13 an operator companion_chain on the block is used as given, before presence or defaults (C-011)" {
   627 |     export ANTHROPIC_API_KEY="REDACTED-TEST-SECRET"
>  628 |     python3 - "$CONFIG_FILE" <<'PY'
   629 | import sys; p=sys.argv[1]; s=open(p, encoding="utf-8").read()
   630 | s=s.replace("  code_review:\n    enabled: true\n", "  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: [claude-headless]\n      openai: [codex-headless]\n", 1); open(p, "w", encoding="utf-8").write(s)
   631 | PY
   632 |     result=$(_run_main review)
   633 |     [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "claude-headless" ]
   634 |     [ "$(grep -cx "opus" "$CALLS")" = "0" ]
   635 |     [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
   636 | }
   637 | 
   638 | @test "CMP-14 the wait cap reaps a hung companion: failure_class timeout, the review completes, no orphan (C-001)" {
   639 |     # positive control first (twentieth run, c1a DISS-C-002): the probe below counts a live stub, then nothing once it is gone
   640 |     _cmp14_probe() { local a; a=$(ps -eo args=) || { echo "ps -eo args= is unsupported here" >&2; return 1; }; grep -Ec "loa-cmp14-hun[g]-$$"'( |$)' <<<"$a" || true; }
~~~~

The change from head to the fix:

~~~~diff
@@ -628 +628 @@
-    python3 - "$CONFIG_FILE" <<'PY'
+    python3 -I - "$CONFIG_FILE" <<'PY'
~~~~

## H61 — tests/unit/adversarial-review-companion.bats — head line 1178

Head context (head/tests/unit/adversarial-review-companion.bats, lines 1166–1190):

~~~~text
  1166 |     rc=0; ( _ADV_CLI_HOP_TIMEOUT=1; _ADV_LOCK_WAIT=1; _ADV_LOCK_WAIT_CLI=1; _adv_invoke_hop opus-plain a b opus-plain 30 "" review >/dev/null 2>"$T/lock-err4" ) || rc=$?
  1167 |     flock -u 9; exec 9>&-; flock -u 8; exec 8>&-
  1168 |     after=$(ls -A "$T/loa-headless-locks-$(id -u)" 2>/dev/null)
  1169 |     [ "$rc" = "0" ]
  1170 |     ! grep -q "not acquired" "$T/lock-err4" || { echo "the HTTP hop queued for a lock" >&2; return 1; }
  1171 |     [ -n "$before" ]
  1172 |     [ "$before" = "$after" ]   # a model with no CLI in its chain touched no lock (snapshot, not a filename guess)
  1173 |     [ "$(grep -c ran "$T/lock-trace")" = "2" ]
  1174 | }
  1175 | 
  1176 | @test "CMP-32 the INV-5 exclusion is symmetric: a companion attempt that dropped a voice the primary answered with is excluded, verdict quality still aggregates, and an aggregator failure would be named on the envelope (eighth run, a2 C-004)" {
  1177 |     # an operator chain whose first hop is the primary's own CLI: the companion's codex-headless attempt fails, then claude-headless answers
> 1178 |     python3 - "$CONFIG_FILE" <<'PY'
  1179 | import sys; p=sys.argv[1]; s=open(p, encoding="utf-8").read()
  1180 | s=s.replace("  code_review:\n    enabled: true\n", "  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: [codex-headless, claude-headless]\n", 1); open(p, "w", encoding="utf-8").write(s)
  1181 | PY
  1182 |     BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
  1183 |     BEHAVIOUR[codex-headless]=unavailable-companion-only
  1184 |     result=$(_run_main review)
  1185 |     [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
  1186 |     [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]
  1187 |     [ "$(jq '.metadata.companion_voice.companion_attempts_excluded' <<<"$result")" = "1" ]
  1188 |     [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
  1189 |     [ "$(jq -r '.verdict_quality.voices_succeeded_ids | sort | join(",")' <<<"$result")" = "claude-headless,codex-headless" ]
  1190 |     [ "$(jq -r '.metadata | has("verdict_quality_error")' <<<"$result")" = "false" ]
~~~~

The change from head to the fix:

~~~~diff
@@ -1178 +1178 @@
-    python3 - "$CONFIG_FILE" <<'PY'
+    python3 -I - "$CONFIG_FILE" <<'PY'
~~~~

## H62 — tests/unit/adversarial-review-companion.bats — head line 2696

Head context (head/tests/unit/adversarial-review-companion.bats, lines 2684–2708):

~~~~text
  2684 |     sleep 60 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID"); _ADV_COMPANION_START=$(_adv_proc_start "$_ADV_COMPANION_PID")
  2685 |     mkdir -p "$T/vw"; : > "$T/vw/companion.current"; printf 'post' > "$T/vw/companion.phase"
  2686 |     # an empty current (a truncating write caught mid-way) with no answering id: wait, then the walker publishes its next hop
  2687 |     t0=$(_now_ms)
  2688 |     ( sleep 2; printf 'opus' > "$T/vw/companion.current" ) 3>&- & writer=$!
  2689 |     [ "$(_adv_shared_hop_verdict claude-headless "$T/vw" "$(( $(date +%s) - 20 ))" 10 60 | cut -f1,2)" = "$(printf 'run\tcompanion_on_other_hop')" ]   # (inside the post deadline)
  2690 |     (( $(_now_ms) - t0 >= 1900 ))   # it waited for a readable name
  2691 |     wait "$writer" 2>/dev/null || true
  2692 |     kill "$_ADV_COMPANION_PID" 2>/dev/null; wait "$_ADV_COMPANION_PID" 2>/dev/null || true; _ADV_COMPANION_PID=""
  2693 |     # the walker's hop/phase writes are atomic (a temp file renamed over the target), never a truncate-then-write
  2694 |     # (thirty-ninth run, c1b DISS-C-005: any redirect onto a hop/phase file in the whole script, however its path is spelled —
  2695 |     # "$x/…", "${x}/…", unquoted, >> — and the walker's own writes are the atomic helper's)
> 2696 |     local hits; hits=$(python3 - "$ADVERSARIAL_REVIEW" <<'PY'
  2697 | import re, sys
  2698 | pat = re.compile(r'''(?<![0-9&])>>?\s*["']?\$\{?[A-Za-z_][A-Za-z_0-9]*\}?["']?/companion\.(current|phase)\b|(?<![0-9&])>>?\s*["']?\$\{?_ADV_PHASE_FILE\b''')
  2699 | for n, line in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
  2700 |     if pat.search(line.split(" # ")[0]): print(n, line.rstrip()[:160])
  2701 | PY
  2702 | ) || { echo "the lint did not run"; return 1; }
  2703 |     [ -z "$hits" ] || { echo "a truncating hop/phase write: $hits"; return 1; }
  2704 |     body=$(declare -f _walk_companion_chain)
  2705 |     grep -qF '_adv_put_state "$workdir/companion.current"' <<<"$body" && grep -qF '_adv_put_state "$workdir/companion.phase"' <<<"$body" || { echo "the walker does not publish through _adv_put_state"; return 1; }
  2706 |     declare -f _adv_hop_begins | grep -qF '_adv_put_state "$_ADV_PHASE_FILE"' || { echo "the hop phase is not published through _adv_put_state"; return 1; }
  2707 |     _adv_put_state "$T/vw/companion.phase" queue; [ "$(cat "$T/vw/companion.phase")" = "queue" ]
  2708 |     [ -z "$(find "$T/vw" -name '*.tmp*')" ]
~~~~

The change from head to the fix:

~~~~diff
@@ -2696 +2696 @@
-    local hits; hits=$(python3 - "$ADVERSARIAL_REVIEW" <<'PY'
+    local hits; hits=$(python3 -I - "$ADVERSARIAL_REVIEW" <<'PY'
~~~~

## H63 — tests/unit/adversarial-review-companion.bats — head line 4248

Head context (head/tests/unit/adversarial-review-companion.bats, lines 4236–4260):

~~~~text
  4236 |     unset -f mv
  4237 |     [ "$rc" = 2 ] || { echo "rc $rc: $result"; return 1; }
  4238 |     [ "$(jq -r '.metadata.status + " " + .metadata.path' <<<"$result")" = "workdir_unavailable grimoires/loa/a2a/$SPRINT/adversarial-rejected-review.jsonl" ]
  4239 |     # the lock is released — no lock directory stands (a later run would take over a dead holder's lock, so a review alone
  4240 |     # proves nothing; thirty-seventh run, c1c DISS-C-001) — and the next run reviews
  4241 |     ! compgen -G "$(_adv_cli_lock_dir)/run-*.lock.d" >/dev/null || { echo "the refusal left its run lock: $(compgen -G "$(_adv_cli_lock_dir)/run-*.lock.d")"; return 1; }
  4242 |     command rm -f -- "$OUT_DIR/adversarial-rejected-review.jsonl"
  4243 |     result=$(_run_main review)
  4244 |     [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ] || { jq -c .metadata <<<"$result"; return 1; }
  4245 | }
  4246 | 
  4247 | @test "CMP-188 every shell step either review skill or its beads resource prescribes is granted under deny_raw_shell, byte for byte — allowed-tools and capabilities alike — or is a native-tool step (thirtieth run, b2 DISS-C-002 / DISS-C-003)" {
> 4248 |     run python3 - "$PROJECT_ROOT" <<'PY'
  4249 | import fnmatch, re, sys, yaml
  4250 | root = sys.argv[1]
  4251 | WORDS = r'(?:find|ls|wc|yq|jq|mkdir|source|cat|grep|git|br|xargs|tail|head|sed|awk|cp|mv|rm|touch|chmod|python3|bash|echo|test)'
  4252 | SPAN = re.compile(r'`((?:\.claude/scripts/|' + WORDS + r' )[^`]*)`')
  4253 | bad = []
  4254 | for s in ('reviewing-code', 'auditing-security'):
  4255 |     text = open(f'{root}/.claude/skills/{s}/SKILL.md', encoding='utf-8').read()
  4256 |     _, fm, body = text.split('---\n', 2)
  4257 |     meta = yaml.safe_load(fm)
  4258 |     grants = [g.strip()[5:-1] for g in meta['allowed-tools'].split(', ') if g.strip().startswith('Bash(')]
  4259 |     caps = meta['capabilities']['execute_commands']
  4260 |     assert caps['deny_raw_shell'] is True
~~~~

The change from head to the fix:

~~~~diff
@@ -4248 +4248 @@
-    run python3 - "$PROJECT_ROOT" <<'PY'
+    run python3 -I - "$PROJECT_ROOT" <<'PY'
~~~~

## H64 — tests/unit/adversarial-review-companion.bats — head line 4440

Head context (head/tests/unit/adversarial-review-companion.bats, lines 4428–4452):

~~~~text
  4428 |     local real; real=$(command -v git)
  4429 |     mkdir -p "$T/oldgit" "$T/home197"
  4430 |     printf '#!/usr/bin/env bash\nunset GIT_CONFIG_GLOBAL\nexec %q "$@"\n' "$real" > "$T/oldgit/git"; chmod +x "$T/oldgit/git"
  4431 |     printf '[loatest]\n\tleak = yes\n' > "$T/home197/.gitconfig"
  4432 |     local got
  4433 |     got=$(HOME="$T/home197" PATH="$T/oldgit:$PATH" _cmp_git config --get loatest.leak 2>/dev/null) || true
  4434 |     [ -z "$got" ] || { echo "the operator's ~/.gitconfig reached the scratch repo: loatest.leak=$got"; return 1; }
  4435 |     # (the model is faithful: the same git reads it when the helper's isolation is bypassed)
  4436 |     [ "$(HOME="$T/home197" PATH="$T/oldgit:$PATH" GIT_CONFIG_GLOBAL=/dev/null git config --get loatest.leak)" = "yes" ]
  4437 | }
  4438 | 
  4439 | @test "CMP-198 a prescribed beads step is never read as two unconditional commands: each br label add in the review resource sits under its own condition comment; the CHANGELOG's FR-2 bullet never says the fallback record applies 'only' when no envelope stands (thirty-second run, e2b DISS-C-005 / e2a DISS-C-001)" {
> 4440 |     run python3 - "$PROJECT_ROOT/.claude/skills/reviewing-code/resources/BEADS-WORKFLOW.md" <<'PY'
  4441 | import re, sys
  4442 | bad = []
  4443 | for block in re.findall(r'```bash\n(.*?)```', open(sys.argv[1], encoding='utf-8').read(), re.S):
  4444 |     lines = block.splitlines()
  4445 |     for i, l in enumerate(lines):
  4446 |         if l.startswith('br label add '):
  4447 |             prev = lines[i - 1] if i else ''
  4448 |             if not re.match(r'#\s*If\b', prev):
  4449 |                 bad.append(f'`{l}` has no condition comment directly above it (got: {prev!r})')
  4450 | print('\n'.join(bad)); sys.exit(1 if bad else 0)
  4451 | PY
  4452 |     [ "$status" -eq 0 ] || { echo "$output"; return 1; }
~~~~

The change from head to the fix:

~~~~diff
@@ -4440 +4440 @@
-    run python3 - "$PROJECT_ROOT/.claude/skills/reviewing-code/resources/BEADS-WORKFLOW.md" <<'PY'
+    run python3 -I - "$PROJECT_ROOT/.claude/skills/reviewing-code/resources/BEADS-WORKFLOW.md" <<'PY'
~~~~

## H65 — tests/unit/adversarial-review-companion.bats — head line 4824

Head context (head/tests/unit/adversarial-review-companion.bats, lines 4812–4836):

~~~~text
  4812 | }
  4813 | 
  4814 | @test "CMP-221 the audit's discovered-vulnerability bead names its criterion only: the flushed .beads JSONL is committed, so a title naming the file tells every reader of a public repo where an unpatched weakness lives before the fix lands — the location stays in the feedback file (thirty-fourth run, e2b DISS-C-003)" {
  4815 |     local r="$PROJECT_ROOT/.claude/skills/auditing-security/resources/BEADS-WORKFLOW.md" t
  4816 |     t=$(grep -o 'log-discovered-issue.sh "<sprint-epic-id>" "[^"]*"' "$r") || { echo "no discovered-issue step"; return 1; }
  4817 |     [[ "$t" == *'"Security: <criterion>'* && "$t" == *auditor-sprint-feedback.md* ]] || { echo "$t"; return 1; }
  4818 |     [[ "$t" != *'<file>'* && "$t" != *'<anchor>'* && "$t" != *'<location>'* ]] || { echo "the title names where: $t"; return 1; }
  4819 | }
  4820 | 
  4821 | @test "CMP-244 the audit resource labels a result as the review twin does: security always, then exactly one of security-approved / security-blocked, each its own command under its own condition — 'labelled security, security-approved or security-blocked' read as one label of three (thirty-seventh run, e2b DISS-C-004)" {
  4822 |     local r="$PROJECT_ROOT/.claude/skills/auditing-security/resources/BEADS-WORKFLOW.md"
  4823 |     ! grep -q 'labelled `security`, `security-approved` or `security-blocked`' "$r" || { echo "the one-of-three wording is back"; return 1; }
> 4824 |     run python3 - "$r" <<'PY'
  4825 | import re, sys
  4826 | text = open(sys.argv[1], encoding='utf-8').read()
  4827 | bad = []
  4828 | blocks = re.findall(r'```bash\n(.*?)```', text, re.S)
  4829 | lines = [l for b in blocks for l in b.splitlines()]
  4830 | labels = [(i, l) for i, l in enumerate(lines) if l.startswith('br label add <task-id> ')]
  4831 | got = [l.split()[-1] for _, l in labels]
  4832 | if got != ['security', 'security-approved', 'security-blocked']:
  4833 |     bad.append(f'labels {got}')
  4834 | for i, l in labels[1:]:
  4835 |     if not re.match(r'#\s*If\b', lines[i - 1]):
  4836 |         bad.append(f'`{l}` has no condition comment directly above it')
~~~~

The change from head to the fix:

~~~~diff
@@ -4824 +4824 @@
-    run python3 - "$r" <<'PY'
+    run python3 -I - "$r" <<'PY'
~~~~

## H66 — tests/unit/adversarial-review-companion.bats — head line 5669

Head context (head/tests/unit/adversarial-review-companion.bats, lines 5657–5681):

~~~~text
  5657 |         [[ "$1" == "$_SW_D269" ]] && return 0
  5658 |         kill -0 "$1" 2>/dev/null
  5659 |     }
  5660 |     _sweep_stale_suite_dirs "$a" sprint-comp
  5661 |     unset -f _sweep_alive
  5662 |     [ -e "$a/sprint-comp-$d/keep" ] || { echo "the live run's directory was swept: $(ls -A "$a")"; return 1; }
  5663 |     [ -e "$m" ] || { echo "the live run's marker was removed"; return 1; }
  5664 |     find "$a" -mindepth 1 -delete
  5665 | }
  5666 | 
  5667 | @test "CMP-270 the suite holds to its portability floor: no GNU-only touch -d, date -d, stat -c or sed -i outside a comment — files are aged by _touch_at (POSIX touch -t) and modes read by ls (thirty-ninth run, c1c DISS-C-002)" {
  5668 |     local T_LINT="$T"
> 5669 |     local hits; hits=$(python3 - "$BATS_TEST_FILENAME" <<'PY'
  5670 | import re, sys
  5671 | pat = re.compile(r'(^|[^A-Za-z0-9_-])(touch[ \t]+-d|date[ \t]+(-[A-Za-z]*[ \t]+)*-d|stat[ \t]+-c|sed[ \t]+-i)\b')
  5672 | for n, line in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
  5673 |     code = line.split(" # ")[0].split("   # ")[0]
  5674 |     if code.lstrip().startswith(("#", "@test")) or "pat = re.compile" in code: continue
  5675 |     if pat.search(code): print(n, line.rstrip()[:160])
  5676 | PY
  5677 | ) || { echo "the lint did not run"; return 1; }
  5678 |     [ -z "$hits" ] || { echo "a GNU-only primitive: $hits"; return 1; }
  5679 |     # the helper ages a file to the second it names, on BSD touch too
  5680 |     : > "$T_LINT/aged"; _touch_at "$(( $(date +%s) - 700 ))" "$T_LINT/aged"
  5681 |     local age; age=$(( $(date +%s) - $(python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$T_LINT/aged") ))
~~~~

The change from head to the fix:

~~~~diff
@@ -5669 +5669 @@
-    local hits; hits=$(python3 - "$BATS_TEST_FILENAME" <<'PY'
+    local hits; hits=$(python3 -I - "$BATS_TEST_FILENAME" <<'PY'
~~~~

## H67 — tests/unit/adversarial-review-companion.bats — insertion after head line 5816

Head context (head/tests/unit/adversarial-review-companion.bats, lines 5805–5828):

~~~~text
  5805 | d="diff --git a/$name b/$name
  5806 | @@ -1 +1,400 @@
  5807 | $big"
  5808 | prepare_content "$d" 300 >/dev/null
  5809 | EOF
  5810 |     rc=0; bash "$T/lc-ctl.sh" "$lib" 2>"$T/lc-ctl.err" || rc=$?
  5811 |     [ "$rc" = "0" ] || { cat "$T/lc-ctl.err"; return 1; }
  5812 |     grep -q 'Top-priority file src/a\[2Jb\.sh exceeds the token budget' "$T/lc-ctl.err"
  5813 |     [ -z "$(LC_ALL=C tr -d '\n\t -~\200-\377' < "$T/lc-ctl.err")" ]
  5814 |     grep -q 'File ${top_path_log} exceeds what the rows that fit leave over' "$lib"
  5815 | }
  5816 | 
  5817 | @test "CMP-275 main refuses a --sprint-id that is not a plain name — a path in it never reaches mktemp, the run lock, the move-aside or the envelope's directory: a usage error (exit 2) and nothing written (audit run 1, a5 DISS-C-002)" {
  5818 |     local esc="cmp275esc-$$" sid
  5819 |     mkdir -p "$T/tmp/adversarial-x"   # the pre-made directory that lets mktemp -d walk out of TMPDIR
  5820 |     for sid in "../$esc" "x/../../$esc" "x/../../../$esc" ".hidden" "a..b"; do
  5821 |         rc=0; result=$( export TMPDIR="$T/tmp"; main --type review --sprint-id "$sid" --diff-file "$T/diff.patch" --json 2> "$T/stderr.log" ) || rc=$?
  5822 |         [ "$rc" = "2" ] || { echo "sprint id $sid: rc=$rc"; cat "$T/stderr.log"; return 1; }
  5823 |         grep -q 'invalid --sprint-id' "$T/stderr.log"
  5824 |         [ -z "$result" ]
  5825 |     done
  5826 |     [ -z "$(find "$T" "$PROJECT_ROOT/grimoires" -maxdepth 4 -name "$esc*" -print -quit)" ]
  5827 |     [ -z "$(find "$T/tmp" -mindepth 1 -name 'adversarial-*' ! -name adversarial-x -print -quit)" ]
  5828 |     # and the record-fallback path keeps its own check behind it (a usage error before it, the same exit code)
~~~~

The change from head to the fix:

~~~~diff
@@ -5816,0 +5817,117 @@
+@test "CMP-279 a diff --git header path's UTF-8 C1 controls (C2 80..C2 9F, e.g. U+009B CSI) never reach stderr either, while legitimate UTF-8 such as café passes verbatim (audit dissent run 1, n30)" {
+    local lib="$PROJECT_ROOT/.claude/scripts/lib-content.sh"
+    cat > "$T/lc-c1.sh" <<'EOF'
+set -euo pipefail
+source "$1"
+big=$(printf '+line %s\n' $(seq 1 400))
+name="$2"
+d="diff --git a/$name b/$name
+@@ -1 +1,400 @@
+$big"
+prepare_content "$d" 300 >/dev/null
+EOF
+    rc=0; bash "$T/lc-c1.sh" "$lib" 'src/a'$'\xc2\x9b''2J'$'\xc2\x9d''b'$'\xc2\x80\xc2\x9f''.sh' 2>"$T/lc-c1.err" || rc=$?
+    [ "$rc" = "0" ] || { cat "$T/lc-c1.err"; return 1; }
+    grep -q 'Top-priority file src/a2Jb\.sh exceeds the token budget' "$T/lc-c1.err"
+    local pair
+    for pair in $'\xc2\x80' $'\xc2\x9b' $'\xc2\x9d' $'\xc2\x9f'; do
+        ! LC_ALL=C grep -qF "$pair" "$T/lc-c1.err" || { echo "C1 pair reached stderr"; od -c "$T/lc-c1.err" | head; return 1; }
+    done
+    rc=0; bash "$T/lc-c1.sh" "$lib" 'src/café.sh' 2>"$T/lc-cafe.err" || rc=$?
+    [ "$rc" = "0" ] || { cat "$T/lc-cafe.err"; return 1; }
+    grep -qF 'Top-priority file src/café.sh exceeds the token budget' "$T/lc-cafe.err"
+}
+
+@test "CMP-280 the C1 strip is a fixed point: a doubled C2 C2 9B 9B (one pass leaves a live C2 9B CSI) never reaches stderr, while café still passes (audit run 2, finding 8)" {
+    local lib="$PROJECT_ROOT/.claude/scripts/lib-content.sh"
+    cat > "$T/lc-c1x.sh" <<'EOF'
+set -euo pipefail
+source "$1"
+big=$(printf '+line %s\n' $(seq 1 400))
+name="$2"
+d="diff --git a/$name b/$name
+@@ -1 +1,400 @@
+$big"
+prepare_content "$d" 300 >/dev/null
+EOF
+    # LC_ALL=C: under a UTF-8 locale the header regex's `.` does not match the invalid C2 C2 lead, so the path never reaches
+    # the strip; a C/POSIX-locale run (CI) parses it byte-wise, which is where a single pass left a live C2 9B
+    rc=0; LC_ALL=C bash "$T/lc-c1x.sh" "$lib" 'src/a'$'\xc2\xc2\x9b\x9b''2J'$'\xc2\xc2\x9d\x9d''52;c;QUJD'$'\xc2\xc2\x9c\x9c''b.sh' 2>"$T/lc-c1x.err" || rc=$?
+    [ "$rc" = "0" ] || { cat "$T/lc-c1x.err"; return 1; }
+    grep -q 'Top-priority file src/a2J52;c;QUJDb\.sh exceeds the token budget' "$T/lc-c1x.err"
+    local pair
+    for pair in $'\xc2\x9b' $'\xc2\x9d' $'\xc2\x9c'; do
+        ! LC_ALL=C grep -qF "$pair" "$T/lc-c1x.err" || { echo "C1 pair reached stderr"; od -c "$T/lc-c1x.err" | head; return 1; }
+    done
+    rc=0; LC_ALL=C bash "$T/lc-c1x.sh" "$lib" 'src/café.sh' 2>"$T/lc-cafe2.err" || rc=$?
+    [ "$rc" = "0" ] || { cat "$T/lc-cafe2.err"; return 1; }
+    grep -qF 'Top-priority file src/café.sh exceeds the token budget' "$T/lc-cafe2.err"
+}
+
+@test "CMP-281 the stderr path copy is cut to 256 bytes before the C1 fixed point: a 20,000-byte C2^k 9B^k path finishes fast and leaves no C2 9B pair (audit run 3, finding 8)" {
+    local lib="$PROJECT_ROOT/.claude/scripts/lib-content.sh"
+    cat > "$T/lc-c1k.sh" <<'EOF'
+set -euo pipefail
+source "$1"
+big=$(printf '+line %s\n' $(seq 1 400))
+name="src/$(printf '\xc2%.0s' $(seq 1 10000))$(printf '\x9b%.0s' $(seq 1 10000))"
+d="diff --git a/$name b/$name
+@@ -1 +1,400 @@
+$big"
+prepare_content "$d" 300 >/dev/null
+EOF
+    rc=0; LC_ALL=C timeout 5 bash "$T/lc-c1k.sh" "$lib" 2>"$T/lc-c1k.err" || rc=$?
+    [ "$rc" = "0" ] || { echo "rc=$rc"; head -c 300 "$T/lc-c1k.err"; return 1; }
+    grep -q 'Top-priority file src/' "$T/lc-c1k.err"
+    ! LC_ALL=C grep -qF $'\xc2\x9b' "$T/lc-c1k.err" || { echo "C1 pair reached stderr"; return 1; }
+    [ "$(LC_ALL=C grep 'Top-priority file' "$T/lc-c1k.err" | LC_ALL=C wc -c)" -lt 400 ]
+}
+
+@test "CMP-282 the stderr path copy drops the Unicode bidi/format code points (U+202E, U+2066, U+200B, U+FEFF — Trojan-Source reordering of the file name) while café passes (audit run 3, finding 10)" {
+    local lib="$PROJECT_ROOT/.claude/scripts/lib-content.sh"
+    cat > "$T/lc-bidi.sh" <<'EOF'
+set -euo pipefail
+source "$1"
+big=$(printf '+line %s\n' $(seq 1 400))
+name="$2"
+d="diff --git a/$name b/$name
+@@ -1 +1,400 @@
+$big"
+prepare_content "$d" 300 >/dev/null
+EOF
+    rc=0; LC_ALL=C.UTF-8 bash "$T/lc-bidi.sh" "$lib" 'src/caf'$'\xc3\xa9''a'$'\xe2\x80\xae''hs.b'$'\xe2\x81\xa6''x'$'\xe2\x80\x8b\xef\xbb\xbf''.sh' 2>"$T/lc-bidi.err" || rc=$?
+    [ "$rc" = "0" ] || { cat "$T/lc-bidi.err"; return 1; }
+    grep -qF 'Top-priority file src/caféahs.bx.sh exceeds the token budget' "$T/lc-bidi.err"
+    local seq
+    for seq in $'\xe2\x80\xae' $'\xe2\x81\xa6' $'\xe2\x80\x8b' $'\xef\xbb\xbf'; do
+        ! LC_ALL=C grep -qF "$seq" "$T/lc-bidi.err" || { echo "format code point reached stderr"; od -c "$T/lc-bidi.err" | head; return 1; }
+    done
+}
+
+@test "CMP-283 raw 8-bit C1 bytes without a C2 lead (a bare 9B, or the 9B a C2 9B 9B leaves) never reach stderr: an invalid-UTF-8 copy has its high bytes replaced, while café passes (audit run 3, finding 11)" {
+    local lib="$PROJECT_ROOT/.claude/scripts/lib-content.sh"
+    cat > "$T/lc-raw.sh" <<'EOF'
+set -euo pipefail
+source "$1"
+big=$(printf '+line %s\n' $(seq 1 400))
+name="$2"
+d="diff --git a/$name b/$name
+@@ -1 +1,400 @@
+$big"
+prepare_content "$d" 300 >/dev/null
+EOF
+    local name
+    for name in 'src/a'$'\x9b''2Jb.sh' 'src/a'$'\xc2\x9b\x9b''2Jb.sh'; do
+        rc=0; LC_ALL=C bash "$T/lc-raw.sh" "$lib" "$name" 2>"$T/lc-raw.err" || rc=$?
+        [ "$rc" = "0" ] || { cat "$T/lc-raw.err"; return 1; }
+        grep -q 'Top-priority file src/a?2Jb\.sh exceeds the token budget' "$T/lc-raw.err" || { od -c "$T/lc-raw.err" | head; return 1; }
+        ! LC_ALL=C grep -qF $'\x9b' "$T/lc-raw.err" || { echo "raw 9B reached stderr"; return 1; }
+    done
+    rc=0; LC_ALL=C.UTF-8 bash "$T/lc-raw.sh" "$lib" 'src/café.sh' 2>"$T/lc-raw-cafe.err" || rc=$?
+    [ "$rc" = "0" ] || { cat "$T/lc-raw-cafe.err"; return 1; }
+    grep -qF 'Top-priority file src/café.sh exceeds the token budget' "$T/lc-raw-cafe.err"
+    rc=0; LC_ALL=C bash "$T/lc-raw.sh" "$lib" 'src/café.sh' 2>"$T/lc-raw-cafe2.err" || rc=$?
+    [ "$rc" = "0" ] || { cat "$T/lc-raw-cafe2.err"; return 1; }
+    grep -qF 'Top-priority file src/café.sh exceeds the token budget' "$T/lc-raw-cafe2.err"
+}
+
~~~~

## H68 — tests/unit/check-permissions.bats — insertion after head line 227

Head context (head/tests/unit/check-permissions.bats, lines 216–227):

~~~~text
   216 |   # every generic deny covers each subcommand, in either form
   217 |   for d in 'Bash(git:*)' 'Bash(git *)' 'Bash( git:* )' 'Bash(git :*)'; do
   218 |     cp13_case "generic-deny $d" "$REQ" "$(jq -nc --arg d "$d" '[$d]')" 1 '.total_denied == 9'
   219 |   done
   220 |   for d in 'Bash(rm:*)' 'Bash(rm *)' 'Bash(git push:*)' 'Bash(git push *)'; do
   221 |     cp13_case "subcommand-deny $d" "$REQ" "$(jq -nc --arg d "$d" '[$d]')" 1 '.total_denied == 1 and .total_found == 15'
   222 |   done
   223 |   cp13_case "gh-deny" "$REQ" '["Bash(gh *)"]' 1 '.total_denied == 2'
   224 |   # a deny in one form wins over an allow of the other form in another layer
   225 |   settings "$USERF" '[]' '["Bash(gh pr *)"]'
   226 |   cp13_case "cross-form-deny" "$REQ" '[]' 1 '.total_denied == 1 and .denied[0].rule == "Bash(gh pr:*)" and .denied[0].by == "Bash(gh pr *)"'
   227 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -227,0 +228,20 @@
+
+@test "CP-14 table: a universal rule, bare Bash, Bash(*) or Bash(:*), covers every Bash requirement, for allow and for deny" {
+  # sprint-250 review run 1, n29: rule_key skipped bare Bash and keyed Bash(*) as the
+  # exact body "*", so a universal deny passed the preflight and the run stalled later
+  local u
+  # run 2, #9: an empty prefix (Bash(:*)) matches every command in Claude Code's prefix grammar
+  for u in 'Bash' 'Bash(*)' 'Bash( * )' 'Bash(:*)' 'Bash( :* )'; do
+    cp13_case "universal-allow $u" "$(jq -nc --arg u "$u" '[$u]')" '[]' 0 '.total_found == 16 and .total_denied == 0'
+    cp13_case "universal-deny $u" "$REQ" "$(jq -nc --arg u "$u" '[$u]')" 1 \
+      ".total_denied == 16 and .total_found == 0 and ([.denied[].by] | unique == [\"$u\"])"
+  done
+  # a narrower deny still subtracts from a universal allow
+  cp13_case "universal-allow-narrow-deny" '["Bash"]' '["Bash(rm:*)"]' 1 '.total_found == 15 and .total_denied == 1 and .denied[0].rule == "Bash(rm:*)"'
+  # a universal deny in the user file wins over the full allow list in the project file
+  settings "$USERF" '[]' '["Bash"]'
+  cp13_case "universal-deny-user-layer" "$REQ" '[]' 1 '.total_denied == 16'
+  settings "$USERF" '[]' '[]'
+  # near-misses are not universal: another tool, a lowercase name, a literal ** body
+  cp13_case "not-universal" '["Read","bash","Bash(**)","Bashx"]' '[]' 1 '.total_found == 0 and .total_missing == 16'
+}
~~~~

## H69 — tests/unit/compliance-hook.bats — head lines 45–57

Head context (head/tests/unit/compliance-hook.bats, lines 33–69):

~~~~text
    33 | }
    34 | EOF
    35 | }
    36 | 
    37 | # Helper: write platform-features.json
    38 | write_platform_features() {
    39 |     local available="${1:-false}"
    40 |     cat > "$PROJECT_ROOT/.run/platform-features.json" << EOF
    41 | {"active_skill_available":${available},"detected_at":"2026-03-20T00:00:00Z","schema_version":1}
    42 | EOF
    43 | }
    44 | 
>   45 | # Helper: write simstim-state.json
>   46 | write_simstim_state() {
>   47 |     local phase="$1"
>   48 |     cat > "$PROJECT_ROOT/.run/simstim-state.json" << EOF
>   49 | {"phase":"${phase}"}
>   50 | EOF
>   51 | }
>   52 | 
>   53 | # Helper: write state.json (run state)
>   54 | write_run_state() {
>   55 |     local state="$1"
>   56 |     cat > "$PROJECT_ROOT/.run/state.json" << EOF
>   57 | {"state":"${state}"}
    58 | EOF
    59 | }
    60 | 
    61 | # =========================================================================
    62 | # T1: State file absent → ask (fail-ask for App Zone)
    63 | # =========================================================================
    64 | 
    65 | @test "App Zone write with no state files returns ask decision" {
    66 |     # No state files exist
    67 |     run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    68 |     [ "$status" -eq 0 ]
    69 |     echo "$output" | grep -q "ADVISORY"
~~~~

The change from head to the fix:

~~~~diff
@@ -45,13 +45,15 @@
-# Helper: write simstim-state.json
+# Helper: write simstim-state.json; the gate allows only while .timestamps.last_activity is under 24 h (LOW-004)
 write_simstim_state() {
     local phase="$1"
+    local last_activity="${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
     cat > "$PROJECT_ROOT/.run/simstim-state.json" << EOF
-{"phase":"${phase}"}
+{"phase":"${phase}","timestamps":{"last_activity":"${last_activity}"}}
 EOF
 }
 
-# Helper: write state.json (run state)
+# Helper: write state.json (run state); same freshness rule as simstim-state.json (LOW-004)
 write_run_state() {
     local state="$1"
+    local last_activity="${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
     cat > "$PROJECT_ROOT/.run/state.json" << EOF
-{"state":"${state}"}
+{"state":"${state}","timestamps":{"last_activity":"${last_activity}"}}
~~~~

## H70 — tests/unit/compliance-hook.bats — insertion after head line 69

Head context (head/tests/unit/compliance-hook.bats, lines 58–81):

~~~~text
    58 | EOF
    59 | }
    60 | 
    61 | # =========================================================================
    62 | # T1: State file absent → ask (fail-ask for App Zone)
    63 | # =========================================================================
    64 | 
    65 | @test "App Zone write with no state files returns ask decision" {
    66 |     # No state files exist
    67 |     run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    68 |     [ "$status" -eq 0 ]
    69 |     echo "$output" | grep -q "ADVISORY"
    70 | }
    71 | 
    72 | # =========================================================================
    73 | # T2: RUNNING + valid state → allow
    74 | # =========================================================================
    75 | 
    76 | @test "App Zone write with RUNNING state returns allow" {
    77 |     write_sprint_state "RUNNING"
    78 |     run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
    79 |     [ "$status" -eq 0 ]
    80 |     # Should NOT contain ADVISORY (silent allow)
    81 |     ! echo "$output" | grep -q "ADVISORY"
~~~~

The change from head to the fix:

~~~~diff
@@ -69,0 +72,3 @@
+    # Claude Code PreToolUse contract: "ask" lives in hookSpecificOutput.permissionDecision (sprint-250 audit n20)
+    [[ "$output" == *'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"'* ]]
+    [[ "$output" != *'"decision":"ask"'* ]]
~~~~

## H71 — tests/unit/compliance-hook.bats — head lines 147–151

Head context (head/tests/unit/compliance-hook.bats, lines 135–163):

~~~~text
   135 | # =========================================================================
   136 | # T7: Non-App-Zone write → always allow (no check)
   137 | # =========================================================================
   138 | 
   139 | @test "Non-App-Zone write always allowed regardless of state" {
   140 |     # No state files, writing to grimoires (State Zone)
   141 |     run bash -c 'echo "{\"tool_input\":{\"file_path\":\"grimoires/loa/notes.md\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
   142 |     [ "$status" -eq 0 ]
   143 |     ! echo "$output" | grep -q "ADVISORY"
   144 | }
   145 | 
   146 | # =========================================================================
>  147 | # CH-T8: Authoritative mode (operator opt-in) — active_skill "implement" allows
>  148 | # cycle-126 D-4.4: only implement_gate.mode in .loa.config.yaml selects it.
>  149 | # =========================================================================
>  150 | 
>  151 | @test "CH-T8: Authoritative mode (implement_gate.mode opt-in) allows App Zone write for implement skill" {
   152 |     command -v yq >/dev/null || skip "yq not installed"
   153 |     printf 'implement_gate:\n  mode: authoritative\n' > "$PROJECT_ROOT/.loa.config.yaml"
   154 |     run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\",\"active_skill\":\"implement\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
   155 |     [ "$status" -eq 0 ]
   156 |     [[ "$output" != *"ADVISORY"* ]]
   157 |     [[ "$output" != *"AUTHORITATIVE"* ]]
   158 |     [[ "$output" != *'"decision"'* ]]
   159 | }
   160 | 
   161 | # =========================================================================
   162 | # CH-T9: Authoritative mode — no active_skill field falls back to heuristic
   163 | # =========================================================================
~~~~

The change from head to the fix:

~~~~diff
@@ -147,5 +152,7 @@
-# CH-T8: Authoritative mode (operator opt-in) — active_skill "implement" allows
+# CH-T8: Authoritative mode (operator opt-in) — a claimed "implement" never
+# allows by itself (tighten-only, sprint-250 audit n17/n18): it falls through
+# to the heuristic, so it asks without RUNNING state and allows with it.
 # cycle-126 D-4.4: only implement_gate.mode in .loa.config.yaml selects it.
 # =========================================================================
 
-@test "CH-T8: Authoritative mode (implement_gate.mode opt-in) allows App Zone write for implement skill" {
+@test "CH-T8: Authoritative mode (implement_gate.mode opt-in) defers an implement claim to the heuristic" {
~~~~

## H72 — tests/unit/compliance-hook.bats — insertion after head line 155

Head context (head/tests/unit/compliance-hook.bats, lines 144–167):

~~~~text
   144 | }
   145 | 
   146 | # =========================================================================
   147 | # CH-T8: Authoritative mode (operator opt-in) — active_skill "implement" allows
   148 | # cycle-126 D-4.4: only implement_gate.mode in .loa.config.yaml selects it.
   149 | # =========================================================================
   150 | 
   151 | @test "CH-T8: Authoritative mode (implement_gate.mode opt-in) allows App Zone write for implement skill" {
   152 |     command -v yq >/dev/null || skip "yq not installed"
   153 |     printf 'implement_gate:\n  mode: authoritative\n' > "$PROJECT_ROOT/.loa.config.yaml"
   154 |     run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\",\"active_skill\":\"implement\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
   155 |     [ "$status" -eq 0 ]
   156 |     [[ "$output" != *"ADVISORY"* ]]
   157 |     [[ "$output" != *"AUTHORITATIVE"* ]]
   158 |     [[ "$output" != *'"decision"'* ]]
   159 | }
   160 | 
   161 | # =========================================================================
   162 | # CH-T9: Authoritative mode — no active_skill field falls back to heuristic
   163 | # =========================================================================
   164 | 
   165 | @test "CH-T9: Authoritative mode falls back to heuristic when no active_skill" {
   166 |     command -v yq >/dev/null || skip "yq not installed"
   167 |     printf 'implement_gate:\n  mode: authoritative\n' > "$PROJECT_ROOT/.loa.config.yaml"
~~~~

The change from head to the fix:

~~~~diff
@@ -155,0 +163,7 @@
+    [[ "$output" == *"ADVISORY"* ]]
+    # Claude Code PreToolUse contract: "ask" lives in hookSpecificOutput.permissionDecision (sprint-250 audit n20)
+    [[ "$output" == *'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"'* ]]
+    [[ "$output" != *'"decision":"ask"'* ]]
+    write_sprint_state "RUNNING"
+    run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\",\"active_skill\":\"implement\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
+    [ "$status" -eq 0 ]
~~~~

## H73 — tests/unit/compliance-hook.bats — head line 185

Head context (head/tests/unit/compliance-hook.bats, lines 173–197):

~~~~text
   173 | # =========================================================================
   174 | # CH-T10: .run/ never selects the mode — a pinned .compliance-mode or
   175 | # platform-features.json claiming active_skill_available is ignored
   176 | # =========================================================================
   177 | 
   178 | @test "CH-T10: .compliance-mode and platform-features.json do not select authoritative mode" {
   179 |     echo "authoritative" > "$PROJECT_ROOT/.run/.compliance-mode"
   180 |     write_platform_features true
   181 |     run bash -c 'echo "{\"tool_input\":{\"file_path\":\"src/index.ts\",\"active_skill\":\"implement\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
   182 |     [ "$status" -eq 0 ]
   183 |     # Heuristic mode ignores active_skill; no RUNNING state → ask
   184 |     [[ "$output" == *"ADVISORY"* ]]
>  185 |     [[ "$output" == *'"decision":"ask"'* ]]
   186 | }
   187 | 
   188 | # =========================================================================
   189 | # CH-T11: Path normalization — absolute path correctly classified
   190 | # =========================================================================
   191 | 
   192 | @test "CH-T11: Path normalization strips PROJECT_ROOT prefix for zone check" {
   193 |     write_sprint_state "RUNNING"
   194 |     # Use absolute path with PROJECT_ROOT prefix — should still detect App Zone correctly
   195 |     run bash -c 'echo "{\"tool_input\":{\"file_path\":\"'"$PROJECT_ROOT"'/src/file.ts\"}}" | PROJECT_ROOT="$1" RUN_DIR="$1/.run" "$2"' _ "$PROJECT_ROOT" "$HOOKS_DIR/implement-gate.sh"
   196 |     [ "$status" -eq 0 ]
   197 |     # RUNNING state + App Zone → allow (no ADVISORY)
~~~~

The change from head to the fix:

~~~~diff
@@ -185 +199,3 @@
-    [[ "$output" == *'"decision":"ask"'* ]]
+    # Claude Code PreToolUse contract: "ask" lives in hookSpecificOutput.permissionDecision (sprint-250 audit n20)
+    [[ "$output" == *'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"'* ]]
+    [[ "$output" != *'"decision":"ask"'* ]]
~~~~

## H74 — tests/unit/flatline-max-tokens.bats — insertion after head line 10

Head context (head/tests/unit/flatline-max-tokens.bats, lines 1–22):

~~~~text
     1 | #!/usr/bin/env bats
     2 | # =============================================================================
     3 | # tests/unit/flatline-max-tokens.bats — cycle-126 Sprint 1 (PRD FR-1.6, SDD D-1.6)
     4 | # flatline-orchestrator.sh call_model sizes --max-tokens from the resolved
     5 | # catalog entry: min(64000, max_output_tokens). A 128K entry → 64000; a smaller
     6 | # entry → its own value; an entry without a declared budget → no flag (cheval's
     7 | # per-model default); --per-call-max-tokens still overrides. No 16000 literal.
     8 | # =============================================================================
     9 | 
    10 | setup() {
    11 |   PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; export PROJECT_ROOT
    12 |   ORCHESTRATOR="$PROJECT_ROOT/.claude/scripts/flatline-orchestrator.sh"
    13 |   ARGV="$BATS_TEST_TMPDIR/argv.txt"
    14 |   SHIM="$BATS_TEST_TMPDIR/model-invoke-shim.sh"
    15 |   cat > "$SHIM" <<SHIM
    16 | printf '%s\n' "\$@" > "$ARGV"
    17 | cat <<'JSON'
    18 | {"content": "{\\"findings\\": []}", "model": "stub", "provider": "stub", "usage": {"input_tokens": 1, "output_tokens": 1}, "latency_ms": 1}
    19 | JSON
    20 | SHIM
    21 |   chmod +x "$SHIM"
    22 |   export MODEL_INVOKE="$SHIM"
~~~~

The change from head to the fix:

~~~~diff
@@ -10,0 +11 @@
+  bats_require_minimum_version 1.5.0   # `run -1 grep`: a bare `! grep` cannot fail, and only "no match" (exit 1) passes — a missing file (exit 2) fails (sprint-250 review run 1, n20; run 2, #10)
~~~~

## H75 — tests/unit/flatline-max-tokens.bats — head line 80

Head context (head/tests/unit/flatline-max-tokens.bats, lines 68–82):

~~~~text
    68 | @test "FMT-4 an entry without a declared budget passes no --max-tokens (cheval's per-model default applies)" {
    69 |   _call_model anthropic:claude-headless review >/dev/null
    70 |   [ -s "$ARGV" ]
    71 |   ! grep -qx -- '--max-tokens' "$ARGV"
    72 | }
    73 | 
    74 | @test "FMT-5 --per-call-max-tokens still overrides the catalog-bounded value" {
    75 |   _call_model anthropic:claude-opus-5 review 4096 >/dev/null
    76 |   [ "$(_argv_value --max-tokens)" = "4096" ]
    77 | }
    78 | 
    79 | @test "FMT-6 no per-call-kind literal remains in the orchestrator" {
>   80 |   ! grep -qE '^FLATLINE_(REVIEW|SCORE)_MAX_TOKENS=' "$ORCHESTRATOR"
    81 |   grep -qE '^FLATLINE_VOICE_MAX_TOKENS_CAP=64000' "$ORCHESTRATOR"
    82 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -80 +81 @@
-  ! grep -qE '^FLATLINE_(REVIEW|SCORE)_MAX_TOKENS=' "$ORCHESTRATOR"
+  run -1 grep -qE '^FLATLINE_(REVIEW|SCORE)_MAX_TOKENS=' "$ORCHESTRATOR"
~~~~

## H76 — tests/unit/gen-bb-registry-codegen.bats — insertion after head line 527

Head context (head/tests/unit/gen-bb-registry-codegen.bats, lines 516–527):

~~~~text
   516 |     cat > "$bad_yaml" <<'EOF'
   517 | providers:
   518 |   testprovider:
   519 |     models:
   520 |       bogus-float:
   521 |         context_window: 1.5
   522 | EOF
   523 | 
   524 |     run "$TSX" "$GEN_SCRIPT" --source-yaml "$bad_yaml" --output-dir "$OUTPUT_DIR"
   525 |     [ "$status" -eq 78 ]
   526 |     [[ "$output" == *"invalid context_window"* ]]
   527 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -527,0 +528,78 @@
+
+# ---------------------------------------------------------------------------
+# T13: catalog aliases resolve to their target's budget (cycle-126 sprint-250
+# round 2). BB's DEFAULTS.model is the alias `opus`; without an alias row the
+# budget lookup fell to the 100K default row and effectiveInputBudget kept the
+# operator's 200K — above cheval's 180K probed ceiling for claude-opus-5-5.
+# ---------------------------------------------------------------------------
+
+# The alias block the generator must emit, derived independently from the
+# catalog: every `aliases:` entry whose `provider:model` target is a catalog
+# model with a context_window, minus self-maps, as `"alias": "model"` lines.
+_expected_alias_lines() {
+    local alias target provider model
+    # space-separated: yq v4 does not expand "\t" in string literals, and
+    # alias names / provider:model targets carry no whitespace
+    while read -r alias target; do
+        [[ "$target" == *:* ]] || continue
+        provider="${target%%:*}"; model="${target#*:}"
+        [ "$alias" = "$model" ] && continue
+        local cw
+        cw="$(yq -r ".providers.\"$provider\".models.\"$model\".context_window // \"\"" "$DEFAULTS_YAML")"
+        [[ "$cw" =~ ^[0-9]+$ ]] || continue
+        printf '  "%s": "%s",\n' "$alias" "$model"
+    done < <(yq -r '.aliases | to_entries | .[] | .key + " " + .value' "$DEFAULTS_YAML") | LC_ALL=C sort
+}
+
+_generated_alias_lines() {
+    awk '/^export const GENERATED_MODEL_ALIASES/ {f=1; next} f && /^};/ {exit} f' "$TRUNC_OUT"
+}
+
+@test "T13: truncation.generated.ts exports GENERATED_MODEL_ALIASES matching the catalog aliases block" {
+    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
+    grep -E '^export const GENERATED_MODEL_ALIASES: Record<string, string> = \{' "$TRUNC_OUT"
+    local expected generated
+    expected="$(_expected_alias_lines)"
+    generated="$(_generated_alias_lines)"
+    [ -n "$expected" ]
+    if [ "$expected" != "$generated" ]; then
+        diff <(echo "$expected") <(echo "$generated") || true
+        return 1
+    fi
+}
+
+@test "T13: the opus alias maps to the catalog's opus target (bare id)" {
+    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
+    local target; target="$(yq -r '.aliases.opus' "$DEFAULTS_YAML")"
+    [[ "$target" == anthropic:* ]]
+    grep -E "^  \"opus\": \"${target#anthropic:}\",\$" "$TRUNC_OUT"
+}
+
+@test "T13: aliases whose target is not a catalog model (native → claude-code:session) are not emitted" {
+    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
+    [ "$(yq -r '.aliases.native' "$DEFAULTS_YAML")" = "claude-code:session" ]
+    # the block must exist, or the zero-hit count below is vacuous
+    grep -E '^export const GENERATED_MODEL_ALIASES' "$TRUNC_OUT"
+    local hits; hits="$(_generated_alias_lines | grep -c '"native":' || true)"
+    [ "$hits" -eq 0 ]
+}
+
+@test "T13: fixture yaml — provider-qualified targets resolve; mismatched provider, bare, and self-map targets are dropped" {
+    local y="$BATS_TEST_TMPDIR/alias-fixture.yaml"
+    cat > "$y" <<'YAML'
+providers:
+  p1:
+    models:
+      m1:
+        context_window: 1000
+aliases:
+  fast: "p1:m1"
+  wrongprov: "p2:m1"
+  bare: "m1"
+  m1: "p1:m1"
+YAML
+    run "$TSX" "$GEN_SCRIPT" --source-yaml "$y" --output-dir "$OUTPUT_DIR"
+    [ "$status" -eq 0 ]
+    local generated; generated="$(_generated_alias_lines)"
+    [ "$generated" = '  "fast": "m1",' ]
+}
~~~~

## H77 — tests/unit/hook-guard.bats — insertion after head line 11

Head context (head/tests/unit/hook-guard.bats, lines 1–23):

~~~~text
     1 | #!/usr/bin/env bats
     2 | # =============================================================================
     3 | # hook-guard.bats — #1180 (bd-c1180-hook-brick-trlm)
     4 | # =============================================================================
     5 | # .claude/hooks/hook-guard.sh wraps each PreToolUse safety hook so a hook that
     6 | # fails to PARSE (e.g. unresolved git conflict markers) fails OPEN loudly
     7 | # instead of bricking every Bash/Edit call. When the wrapped hook parses
     8 | # clean, the guard is byte-for-byte transparent on BOTH the allow and block
     9 | # paths (exit code, stdout, stderr, stdin passthrough).
    10 | 
    11 | setup() {
    12 |     PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    13 |     GUARD="$PROJECT_ROOT/.claude/hooks/hook-guard.sh"
    14 |     BLOCK_HOOK="$PROJECT_ROOT/.claude/hooks/safety/block-destructive-bash.sh"
    15 | 
    16 |     # Conflict-marker fixture, built at runtime (never typed as a 7-char run):
    17 |     # a valid shebang followed by unresolved git conflict markers, which is a
    18 |     # bash parse error.
    19 |     LT="$(printf '<%.0s' 1 2 3 4 5 6 7)"
    20 |     EQ="$(printf '=%.0s' 1 2 3 4 5 6 7)"
    21 |     GT="$(printf '>%.0s' 1 2 3 4 5 6 7)"
    22 |     BROKEN="$BATS_TEST_TMPDIR/broken-hook.sh"
    23 |     {
~~~~

The change from head to the fix:

~~~~diff
@@ -11,0 +12 @@
+    bats_require_minimum_version 1.5.0   # `run -1 grep`: a bare `! grep` cannot fail, and only "no match" (exit 1) passes — a missing file (exit 2) fails (sprint-250 review run 1, n38; run 2, #10)
~~~~

## H78 — tests/unit/hook-guard.bats — head line 152

Head context (head/tests/unit/hook-guard.bats, lines 140–155):

~~~~text
   140 |     } > "$echoer"
   141 |     chmod +x "$echoer"
   142 | 
   143 |     run "$GUARD" "$echoer" alpha beta
   144 |     [ "$status" -eq 0 ]
   145 |     [ "$output" = "alpha|beta" ]
   146 | }
   147 | 
   148 | # --- (d) the WARN names no event: the guard also wraps SessionStart hooks ----
   149 | @test "parse-failure WARN does not call every wrapped hook a PreToolUse hook (it also wraps loa-context-class.sh)" {
   150 |     local err="$BATS_TEST_TMPDIR/d.err"
   151 |     "$GUARD" "$BROKEN" </dev/null >/dev/null 2>"$err"
>  152 |     ! grep -q "PreToolUse hook" "$err"
   153 |     grep -q "did not run" "$err"
   154 |     grep -q "failing OPEN" "$err"
   155 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -152 +153 @@
-    ! grep -q "PreToolUse hook" "$err"
+    run -1 grep -q "PreToolUse hook" "$err"
~~~~

## H79 — tests/unit/implement-gate.bats — head line 17

Head context (head/tests/unit/implement-gate.bats, lines 5–29):

~~~~text
     5 | # The PreToolUse stdin carries no harness-set skill signal
     6 | # (https://code.claude.com/docs/en/hooks lists session_id, transcript_path,
     7 | # cwd, permission_mode, hook_event_name, tool_name, tool_input, tool_use_id,
     8 | # and agent_id/agent_type inside a subagent). tool_input is model-authored,
     9 | # so `tool_input.active_skill` is evidence at most:
    10 | #   - the recorder writes active_skill_seen_at once, from the lead session only
    11 | #   - nothing in .run/ flips the gate; only `implement_gate.mode: authoritative`
    12 | #     in .loa.config.yaml does, and the key stays undocumented
    13 | #   - detect-platform-features.sh never reports the flag true on its own
    14 | # =============================================================================
    15 | 
    16 | setup() {
>   17 |     bats_require_minimum_version 1.5.0
    18 |     REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    19 |     GATE="$REPO/.claude/hooks/compliance/implement-gate.sh"
    20 |     DETECT="$REPO/.claude/scripts/detect-platform-features.sh"
    21 |     FIX="$REPO/tests/fixtures/pretooluse-payloads"
    22 |     ROOT="$BATS_TEST_TMPDIR/proj"
    23 |     mkdir -p "$ROOT/.run"
    24 |     unset LOA_TEAM_MEMBER CLAUDE_ACTIVE_SKILL_AVAILABLE
    25 | }
    26 | 
    27 | payload() { sed "s#__ROOT__#$ROOT#g" "$FIX/$1"; }
    28 | 
    29 | gate_with() {
~~~~

The change from head to the fix:

~~~~diff
@@ -17 +17 @@
-    bats_require_minimum_version 1.5.0
+    bats_require_minimum_version 1.5.0   # `run -1 grep`: a bare `! grep` cannot fail, and only "no match" (exit 1) passes — a missing file (exit 2) fails (sprint-250 review run 2, #10)
~~~~

## H80 — tests/unit/implement-gate.bats — head line 35

Head context (head/tests/unit/implement-gate.bats, lines 23–47):

~~~~text
    23 |     mkdir -p "$ROOT/.run"
    24 |     unset LOA_TEAM_MEMBER CLAUDE_ACTIVE_SKILL_AVAILABLE
    25 | }
    26 | 
    27 | payload() { sed "s#__ROOT__#$ROOT#g" "$FIX/$1"; }
    28 | 
    29 | gate_with() {
    30 |     local fixture="$1"
    31 |     payload "$fixture" > "$BATS_TEST_TMPDIR/stdin.json"
    32 |     run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
    33 | }
    34 | 
>   35 | decision() { [[ "$output" == *'"decision":"ask"'* ]] && echo ask || echo allow; }
    36 | 
    37 | opt_in() { printf 'implement_gate:\n  mode: authoritative\n' > "$ROOT/.loa.config.yaml"; }
    38 | 
    39 | @test "IG-1 a lead-session payload carrying tool_input.active_skill records active_skill_seen_at and its source" {
    40 |     gate_with write-src-active-implement.json
    41 |     [ "$status" -eq 0 ]
    42 |     run jq -r '[.active_skill_seen_at, .active_skill_source, .active_skill_available] | map(tostring) | @tsv' "$ROOT/.run/platform-features.json"
    43 |     [[ "$output" =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$'\t'tool_input$'\t'false$ ]]
    44 |     printf '{"active_skill_available":true}\n' > "$ROOT/.run/platform-features.json"
    45 |     gate_with write-src-active-implement.json
    46 |     [ "$(jq -r '.active_skill_available' "$ROOT/.run/platform-features.json")" = false ]
    47 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -35 +35,9 @@
-decision() { [[ "$output" == *'"decision":"ask"'* ]] && echo ask || echo allow; }
+# Claude Code PreToolUse contract: "ask" is only valid as hookSpecificOutput.permissionDecision; a top-level
+# "decision" takes approve|block only (sprint-250 audit n20). Allow = silent exit 0 with empty stdout.
+decision() {
+    if [[ -z "$output" ]]; then echo allow
+    elif jq -e '(has("decision") | not) and .hookSpecificOutput.hookEventName == "PreToolUse"
+                and .hookSpecificOutput.permissionDecision == "ask"
+                and (.hookSpecificOutput.permissionDecisionReason | type == "string" and length > 0)' <<<"$output" >/dev/null 2>&1; then echo ask
+    else echo "invalid:$output"; fi
+}
~~~~

## H81 — tests/unit/implement-gate.bats — head lines 151–153

Head context (head/tests/unit/implement-gate.bats, lines 139–154):

~~~~text
   139 |     printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z","active_skill_source":"tool_input"}\n' > "$ROOT/.run/platform-features.json"
   140 |     run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
   141 |     [ "$output" = "Implement gate: heuristic (active_skill evidence: seen 2026-01-01T00:00:00Z via tool_input; no harness skill signal)" ]
   142 |     if command -v yq >/dev/null; then
   143 |         opt_in
   144 |         run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
   145 |         [[ "$output" == "Implement gate: authoritative (opt-in; active_skill evidence: seen "* ]]
   146 |     fi
   147 |     grep -q 'display_gate_line' "$REPO/.claude/scripts/loa-status.sh"
   148 |     grep -A1 '^      display_context_line$' "$REPO/.claude/scripts/loa-status.sh" | grep -q 'display_gate_line'
   149 | }
   150 | 
>  151 | @test "IG-11 the opt-in key stays undocumented while the payload carries no harness signal" {
>  152 |     ! grep -q 'implement_gate' "$REPO/.loa.config.yaml.example"
>  153 |     ! grep -rq 'implement_gate' "$REPO/docs" "$REPO/README.md"
   154 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -151,3 +159,280 @@
-@test "IG-11 the opt-in key stays undocumented while the payload carries no harness signal" {
-    ! grep -q 'implement_gate' "$REPO/.loa.config.yaml.example"
-    ! grep -rq 'implement_gate' "$REPO/docs" "$REPO/README.md"
+@test "IG-12 authoritative is strictly tighter than heuristic: with RUNNING state a non-implementation claim asks and logs one ask row, each implementation claim one heuristic row" {
+    command -v yq >/dev/null || skip "yq not installed"
+    printf '{"plan_id":"p","state":"RUNNING","timestamps":{"last_activity":"%s"}}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$ROOT/.run/sprint-plan-state.json"
+    gate_with write-app-active-review.json
+    [ "$(decision)" = allow ]
+    [ ! -e "$ROOT/.run/audit.jsonl" ]
+    opt_in
+    gate_with write-app-active-review.json
+    [ "$(decision)" = ask ]
+    [[ "$stderr" == *"[AUTHORITATIVE]"* ]]
+    run jq -sc '[.[] | select(.event == "compliance.mode.model_signal")] | map([.mode, .active_skill, .file_path, .decision, (.timestamp | test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\\z"))])' "$ROOT/.run/audit.jsonl"
+    [ "$output" = "[[\"authoritative\",\"review-sprint\",\"$ROOT/app/main.py\",\"ask\",true]]" ]
+    # a claimed implementation skill never allows by itself: with RUNNING it allows (heuristic), without it asks
+    gate_with write-src-active-implement.json
+    [ "$(decision)" = allow ]
+    rm "$ROOT/.run/sprint-plan-state.json"
+    gate_with write-src-active-implement.json
+    [ "$(decision)" = ask ]
+    [[ "$stderr" == *"[ADVISORY]"* ]]
+    # every forged claim leaves a trace (run-2 finding 6): one ask row for the review claim, one heuristic row per implementation claim
+    run jq -sc '[.[] | select(.event == "compliance.mode.model_signal") | .decision] | sort' "$ROOT/.run/audit.jsonl"
+    [ "$output" = '["ask","heuristic","heuristic"]' ]
+    run jq -sc '[.[] | select(.event == "compliance.mode.model_signal" and .decision == "heuristic") | [.mode, .active_skill, .file_path]] | unique' "$ROOT/.run/audit.jsonl"
+    [ "$output" = "[[\"authoritative\",\"implement\",\"$ROOT/src/index.ts\"]]" ]
+}
+
+@test "IG-13 control characters in a claimed skill or path are stripped from stderr and the audit row (n21)" {
+    command -v yq >/dev/null || skip "yq not installed"
+    opt_in
+    printf '{"tool_input":{"file_path":"%s/src/a\\u001b[31mb\\u007f.py","active_skill":"rev\\u0007iew\\r\\n"}}\n' "$ROOT" > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$(decision)" = ask ]
+    [[ "$stderr" == *"'$ROOT/src/a[31mb.py' detected during /review (not an implementation skill)."* ]]
+    run -1 env LC_ALL=C grep -q $'[\x01-\x09\x0b-\x1f\x7f]' <<<"$stderr"
+    # run-3 finding 4: the row records the raw claim faithfully, every control and non-ASCII code point \u-escaped (jq -a)
+    run jq -r 'select(.event == "compliance.mode.model_signal") | (.active_skill + " " + .file_path) | @json' "$ROOT/.run/audit.jsonl"
+    [ "$output" = "\"rev\\u0007iew\\r\\n $ROOT/src/a\\u001b[31mb\\u007f.py\"" ]
+    run -1 env LC_ALL=C grep -q $'[\x01-\x09\x0b-\x1f\x7f-\xff]' "$ROOT/.run/audit.jsonl"
+    # run-2 findings 3/12: UTF-8 C1 controls, bidi/format code points and a doubled C2 C2 9B 9B (one pass would leave a live
+    # C2 9B) never reach stderr or the row; the logged skill is at most 256 bytes; legitimate UTF-8 (café) passes verbatim
+    local bad=$'\xc2\x9b'$'\xe2\x80\xae'$'\xe2\x80\x8b'$'\xc2\xc2\x9b\x9b' long
+    long=$(printf 'k%.0s' {1..400})
+    rm -f "$ROOT/.run/audit.jsonl"
+    printf '{"tool_input":{"file_path":"%s/src/caf\xc3\xa9%sx.py","active_skill":"rev%siew%s"}}\n' "$ROOT" "$bad" "$bad" "$long" > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$(decision)" = ask ]
+    [[ "$stderr" == *"'$ROOT/src/café"* ]]
+    [[ "$stderr" == *"detected during /rev"* ]]   # jq reads the invalid doubled bytes as U+FFFD U+009B U+FFFD; only the U+009B goes
+    local seq
+    for seq in $'\xc2\x9b' $'\xe2\x80\xae' $'\xe2\x80\x8b'; do
+        run -1 env LC_ALL=C grep -qF "$seq" <<<"$stderr"
+        run -1 env LC_ALL=C grep -qF "$seq" "$ROOT/.run/audit.jsonl"
+    done
+    run -1 env LC_ALL=C grep -q $'\xc2[\x80-\x9f]' "$ROOT/.run/audit.jsonl"
+    run jq -r 'select(.event == "compliance.mode.model_signal") | .file_path' "$ROOT/.run/audit.jsonl"
+    [[ "$output" == "$ROOT/src/café"*x.py ]]
+    run jq -j 'select(.event == "compliance.mode.model_signal") | .active_skill' "$ROOT/.run/audit.jsonl"
+    [[ "$output" == rev* ]]
+    [ "$(printf '%s' "$output" | LC_ALL=C wc -c)" -le 256 ]
+    # run-3 finding 4: implement + U+200B is not an implementation claim — it asks, and the row shows the claim as written
+    # (implement\u200b), never the stripped "implement" beside decision "ask"
+    rm -f "$ROOT/.run/audit.jsonl"
+    printf '{"tool_input":{"file_path":"%s/src/i.py","active_skill":"implement\\u200b"}}\n' "$ROOT" > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$(decision)" = ask ]
+    grep -qF '"active_skill":"implement\u200b"' "$ROOT/.run/audit.jsonl"
+    grep -qF '"decision":"ask"' "$ROOT/.run/audit.jsonl"
+    # run-3 finding 5: U+00AD, U+061C, U+206A, U+180E, U+FFF9, U+FE0F and the tag characters U+E0001/U+E0041 never reach stderr
+    rm -f "$ROOT/.run/audit.jsonl"
+    printf '{"tool_input":{"file_path":"%s/src/x\\u00ad\\u061c\\u206a\\u180e\\ufff9\\ufe0f\\udb40\\udc01\\udb40\\udc41y.py","active_skill":"rev\\u206fiew"}}\n' "$ROOT" > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$(decision)" = ask ]
+    [[ "$stderr" == *"'$ROOT/src/xy.py' detected during /review (not an implementation skill)."* ]]
+    for seq in $'\xc2\xad' $'\xd8\x9c' $'\xe2\x81\xaa' $'\xe2\x81\xaf' $'\xe1\xa0\x8e' $'\xef\xbf\xb9' $'\xef\xb8\x8f' $'\xf3\xa0\x80\x81' $'\xf3\xa0\x81\x81'; do
+        run -1 env LC_ALL=C grep -qF "$seq" <<<"$stderr"
+    done
+    # run-3 finding 5: a 256-byte cut that would split a 2-byte character drops it whole — no U+FFFD in the row or on stderr
+    rm -f "$ROOT/.run/audit.jsonl"
+    local pre="$ROOT/src/" pad
+    pad=$(printf 'p%.0s' $(seq 1 $(( 255 - ${#pre} ))))
+    printf '{"tool_input":{"file_path":"%s%s\xc3\xa9tail.py","active_skill":"review"}}\n' "$pre" "$pad" > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$(decision)" = ask ]
+    run -1 grep -qiF '\ufffd' "$ROOT/.run/audit.jsonl"
+    run -1 env LC_ALL=C grep -qF $'\xef\xbf\xbd' <<<"$stderr"
+    run jq -j 'select(.event == "compliance.mode.model_signal") | .file_path' "$ROOT/.run/audit.jsonl"
+    [ "$output" = "$pre$pad" ]
+}
+
+@test "IG-14 the /loa evidence line and the refresh never carry Unicode format characters (U+202E, U+200B) and share one shape check" {
+    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z\\u202e","active_skill_source":"tool\\u200b_input"}\n' > "$ROOT/.run/platform-features.json"
+    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
+    [ "$output" = "Implement gate: heuristic (active_skill evidence: none; no harness skill signal)" ]
+    run -1 env LC_ALL=C grep -q '[^[:print:]]' <<<"$output"
+    # run-2 finding 4: --line applies the refresh's shape checks — a malformed seen_at is no evidence, an unknown source is "unknown"
+    printf '{"active_skill_seen_at":"yesterday","active_skill_source":"tool_input"}\n' > "$ROOT/.run/platform-features.json"
+    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
+    [ "$output" = "Implement gate: heuristic (active_skill evidence: none; no harness skill signal)" ]
+    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z","active_skill_source":"forged"}\n' > "$ROOT/.run/platform-features.json"
+    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" --line' _ "$ROOT" "$DETECT"
+    [ "$output" = "Implement gate: heuristic (active_skill evidence: seen 2026-01-01T00:00:00Z via unknown; no harness skill signal)" ]
+    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z\\u202e","active_skill_source":"tool\\u200b_input"}\n' > "$ROOT/.run/platform-features.json"
+    touch -d '2 hours ago' "$ROOT/.run/platform-features.json"
+    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2"' _ "$ROOT" "$DETECT"
+    run jq -r '[.active_skill_seen_at, .active_skill_source] | map(tostring) | join(" ")' "$ROOT/.run/platform-features.json"
+    [ "$output" = "null null" ]
+    # a well-shaped seen_at with an unknown source keeps the seen_at only
+    printf '{"active_skill_seen_at":"2026-01-01T00:00:00Z","active_skill_source":"forged"}\n' > "$ROOT/.run/platform-features.json"
+    touch -d '2 hours ago' "$ROOT/.run/platform-features.json"
+    run bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2"' _ "$ROOT" "$DETECT"
+    run jq -r '[.active_skill_seen_at, .active_skill_source] | map(tostring) | join(" ")' "$ROOT/.run/platform-features.json"
+    [ "$output" = "2026-01-01T00:00:00Z null" ]
+}
+
+gate_path() {
+    jq -nc --arg p "$1" '{tool_name: "Write", tool_input: {file_path: $p, content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+}
+
+@test "IG-15 the App-Zone check compares canonical paths: a non-canonical spelling of a src/ file asks, a canonically-outside path allows (run-2 finding 1)" {
+    local p
+    for p in "/proc/self/cwd/src/x.ts" "/$ROOT/src/x.ts" "$ROOT/../$(basename "$ROOT")/src/x.ts" "$ROOT/grimoires/../src/x.ts"; do
+        gate_path "$p"
+        [ "$(decision)" = ask ] || { echo "$p: expected ask, got $(decision)" >&2; return 1; }
+    done
+    ln -s "$ROOT" "$BATS_TEST_TMPDIR/link"
+    gate_path "$BATS_TEST_TMPDIR/link/src/x.ts"
+    [ "$(decision)" = ask ]
+    mkdir -p "$BATS_TEST_TMPDIR/elsewhere/src"
+    gate_path "$BATS_TEST_TMPDIR/elsewhere/src/x.ts"
+    [ "$(decision)" = allow ]
+    gate_path "$ROOT/grimoires/loa/NOTES.md"
+    [ "$(decision)" = allow ]
+    # run-3 finding 2: on a case-insensitive filesystem LIB/ is lib/ — the patterns match a lowercased copy
+    gate_path "$ROOT/LIB/x.js"
+    [ "$(decision)" = ask ]
+}
+
+@test "IG-16 an unparsable payload and a NotebookEdit payload under src/ ask; a parsed payload without a path allows (run-2 finding 5)" {
+    printf 'not json\n' > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$status" -eq 0 ]
+    [ "$(decision)" = ask ]
+    [[ "$output" == *"[GATE] could not evaluate tool_input"* ]]
+    printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"%s/src/nb.ipynb","new_source":"x"}}\n' "$ROOT" > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$(decision)" = ask ]
+    printf '{"tool_input":{"content":"x"}}\n' > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$status" -eq 0 ]
+    [ "$(decision)" = allow ]
+}
+
+@test "IG-17 an inside-out symlink (src/ itself, or a lib/ file, pointing out of the root) still asks: the logical and the physical form are both tested (run-3 finding 1)" {
+    mkdir -p "$BATS_TEST_TMPDIR/outside"
+    ln -s "$BATS_TEST_TMPDIR/outside" "$ROOT/src"
+    mkdir -p "$ROOT/lib"
+    ln -s ../outside/real.ts "$ROOT/lib/cfg.ts"
+    gate_path "$ROOT/src/x.ts"
+    [ "$(decision)" = ask ]
+    gate_path "$ROOT/lib/cfg.ts"
+    [ "$(decision)" = ask ]
+    # the pure-bash normaliser (no realpath -s): a realpath that refuses -s forces the fallback
+    mkdir -p "$BATS_TEST_TMPDIR/shim"
+    printf '#!/usr/bin/env bash\nfor a in "$@"; do [[ "$a" == -s || "$a" == --no-symlinks ]] && exit 1; done\nexec %q "$@"\n' "$(command -v realpath)" > "$BATS_TEST_TMPDIR/shim/realpath"
+    chmod +x "$BATS_TEST_TMPDIR/shim/realpath"
+    local p
+    for p in "$ROOT/src/x.ts" "$ROOT/lib/cfg.ts" "$ROOT/grimoires/./../src//y.ts"; do
+        jq -nc --arg p "$p" '{tool_name: "Write", tool_input: {file_path: $p, content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
+        run --separate-stderr bash -c 'cd "$1" && PATH="$4:$PATH" PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json" "$BATS_TEST_TMPDIR/shim"
+        [ "$(decision)" = ask ] || { echo "fallback $p: expected ask, got $(decision)" >&2; return 1; }
+    done
+    jq -nc --arg p "$ROOT/grimoires/loa/../loa/NOTES.md" '{tool_name: "Write", tool_input: {file_path: $p, content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PATH="$4:$PATH" PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json" "$BATS_TEST_TMPDIR/shim"
+    [ "$(decision)" = allow ]
+}
+
+@test "IG-18 a write to one of the gate's own trust inputs asks and leaves one compliance.state_write row; other .run/ and grimoires/ files allow silently (run-3 finding 3)" {
+    local rel n=0
+    for rel in .run/state.json .run/sprint-plan-state.json .run/simstim-state.json .run/platform-features.json .run/audit.jsonl .loa.config.yaml; do
+        gate_path "$ROOT/$rel"
+        [ "$(decision)" = ask ] || { echo "$rel: expected ask, got $(decision)" >&2; return 1; }
+        [[ "$stderr" == *"[GATE] write to an implement-gate trust input"* ]]
+        n=$(( n + 1 ))
+        run jq -sc --arg p "$ROOT/$rel" '[.[] | select(.event == "compliance.state_write" and .file_path == $p and (.timestamp | test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\\z")))] | length' "$ROOT/.run/audit.jsonl"
+        [ "$output" = 1 ] || { echo "$rel: expected one row, got $output" >&2; return 1; }
+    done
+    [ "$(jq -sc 'length' "$ROOT/.run/audit.jsonl")" = "$n" ]
+    # a relative spelling of a trust input asks too
+    gate_path ".run/../.run/state.json"
+    [ "$(decision)" = ask ]
+    rm -f "$ROOT/.run/audit.jsonl"
+    gate_path "$ROOT/.run/other.json"
+    [ "$(decision)" = allow ]
+    gate_path "$ROOT/grimoires/loa/NOTES.md"
+    [ "$(decision)" = allow ]
+    [ ! -e "$ROOT/.run/audit.jsonl" ]
+}
+
+@test "IG-19 a relative file_path resolves from the payload's cwd when it carries one, else from PROJECT_ROOT (run-3 finding 6)" {
+    mkdir -p "$ROOT/src" "$ROOT/grimoires"
+    jq -nc --arg c "$ROOT/src" '{cwd: $c, tool_input: {file_path: "index.ts", content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$(decision)" = ask ]
+    jq -nc --arg c "$ROOT/grimoires" '{cwd: $c, tool_input: {file_path: "x.md", content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$(decision)" = allow ]
+    jq -nc '{tool_input: {file_path: "src/index.ts", content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$(decision)" = ask ]
+}
+
+@test "IG-20 the ask reply is built by jq: the reason is a JSON string whatever it contains (run-3 finding 7)" {
+    grep -q 'jq -nc --arg r "\$1"' "$GATE"
+    printf 'not json\n' > "$BATS_TEST_TMPDIR/stdin.json"
+    run --separate-stderr bash -c 'cd "$1" && PROJECT_ROOT="$1" RUN_DIR="$1/.run" bash "$2" < "$3"' _ "$ROOT" "$GATE" "$BATS_TEST_TMPDIR/stdin.json"
+    [ "$(decision)" = ask ]
+}
+
+# The hook as wired in production: no PROJECT_ROOT or RUN_DIR in its environment, its process cwd wherever Claude cd'd
+# (MED-001). $1 = hook path, $2 = process cwd, $3 = CLAUDE_PROJECT_DIR (empty = unset), $4 = file_path; payload cwd = $2
+gate_unrooted() {
+    jq -nc --arg c "$2" --arg p "$4" '{cwd: $c, tool_name: "Write", tool_input: {file_path: $p, content: "x"}}' > "$BATS_TEST_TMPDIR/stdin.json"
+    if [[ -n "$3" ]]; then
+        run --separate-stderr env -u PROJECT_ROOT -u RUN_DIR CLAUDE_PROJECT_DIR="$3" bash -c 'cd "$1" && bash "$2" < "$3"' _ "$2" "$1" "$BATS_TEST_TMPDIR/stdin.json"
+    else
+        run --separate-stderr env -u PROJECT_ROOT -u RUN_DIR -u CLAUDE_PROJECT_DIR bash -c 'cd "$1" && bash "$2" < "$3"' _ "$2" "$1" "$BATS_TEST_TMPDIR/stdin.json"
+    fi
+}
+
+@test "IG-21 the root is CLAUDE_PROJECT_DIR, else the hook's own location, never the process cwd: from a subdirectory an App-Zone and a trust-input write still ask (MED-001)" {
+    mkdir -p "$ROOT/src" "$ROOT/.claude/hooks/compliance"
+    cp "$GATE" "$ROOT/.claude/hooks/compliance/implement-gate.sh"
+    local leg hook cwd cpd
+    # leg = hook|cwd|CLAUDE_PROJECT_DIR: the harness's project dir from a subdirectory, then the script-location rung
+    # (the copy under $ROOT/.claude/hooks/compliance/ resolves to $ROOT) from the subdirectory and from the root
+    for leg in "$GATE|$ROOT/src|$ROOT" "$ROOT/.claude/hooks/compliance/implement-gate.sh|$ROOT/src|" "$ROOT/.claude/hooks/compliance/implement-gate.sh|$ROOT|"; do
+        IFS='|' read -r hook cwd cpd <<<"$leg"
+        rm -f "$ROOT/.run/audit.jsonl"
+        gate_unrooted "$hook" "$cwd" "$cpd" "$ROOT/src/x.ts"
+        [ "$(decision)" = ask ] || { echo "$leg src/x.ts: expected ask, got $(decision)" >&2; return 1; }
+        gate_unrooted "$hook" "$cwd" "$cpd" "$ROOT/.loa.config.yaml"
+        [ "$(decision)" = ask ] || { echo "$leg .loa.config.yaml: expected ask, got $(decision)" >&2; return 1; }
+        run jq -sc --arg p "$ROOT/.loa.config.yaml" '[.[] | select(.event == "compliance.state_write" and .file_path == $p)] | length' "$ROOT/.run/audit.jsonl"
+        [ "$output" = 1 ] || { echo "$leg: expected one state_write row in \$ROOT/.run/audit.jsonl, got $output" >&2; return 1; }
+    done
+    [ ! -e "$ROOT/src/.run/audit.jsonl" ]
+}
+
+# A state file under .run/ named $1, aged $2 hours (0 = now), the jq object $3 plus .timestamps.last_activity
+state_aged() {
+    jq -nc --argjson h "$2" "$3"' + {timestamps: {last_activity: (now - $h * 3600 | floor | todate)}}' > "$ROOT/.run/$1"   # jq todate: portable, no GNU date -d
+}
+
+@test "IG-22 state.json RUNNING and simstim-state.json implementation allow only while fresh: older than 24 h, or with no timestamp, asks (LOW-004)" {
+    local f body
+    for f in state.json simstim-state.json; do
+        case "$f" in state.json) body='{state: "RUNNING"}' ;; *) body='{state: "RUNNING", phase: "implementation"}' ;; esac
+        rm -f "$ROOT/.run/state.json" "$ROOT/.run/simstim-state.json"
+        state_aged "$f" 25 "$body"
+        gate_path "$ROOT/src/x.ts"
+        [ "$(decision)" = ask ] || { echo "$f 25 h: expected ask, got $(decision)" >&2; return 1; }
+        state_aged "$f" 0 "$body"
+        gate_path "$ROOT/src/x.ts"
+        [ "$(decision)" = allow ] || { echo "$f fresh: expected allow, got $(decision)" >&2; return 1; }
+        jq -nc "$body" > "$ROOT/.run/$f"
+        gate_path "$ROOT/src/x.ts"
+        [ "$(decision)" = ask ] || { echo "$f no timestamp: expected ask, got $(decision)" >&2; return 1; }
+    done
+    # state.json's .updated_at (the run-preflight fallback) counts as its timestamp
+    rm -f "$ROOT/.run/simstim-state.json"
+    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{state: "RUNNING", updated_at: $ts}' > "$ROOT/.run/state.json"
+    gate_path "$ROOT/src/x.ts"
+    [ "$(decision)" = allow ]
+}
+
+@test "IG-11 the opt-in key stays undocumented while the payload carries no harness signal" {
+    # sprint-250 review run 1, n20: a bare mid-test `! grep` cannot fail
+    run -1 grep -q 'implement_gate' "$REPO/.loa.config.yaml.example"
+    run -1 grep -rq 'implement_gate' "$REPO/docs" "$REPO/README.md"
~~~~

## H82 — tests/unit/instruction-diet-revert.bats — head line 38

Head context (head/tests/unit/instruction-diet-revert.bats, lines 26–50):

~~~~text
    26 | }
    27 | 
    28 | @test "IDR-2 CLAUDE.loa.md carries the truenames table and the NOTES clause" {
    29 |     grep -qxF '| Phase | Command | Output |' "$LOA"
    30 |     for row in '| 1 | `/plan-and-analyze` | PRD |' '| 4 | `/implement sprint-N` | Code |' \
    31 |                '| 5.5 | `/audit-sprint sprint-N` | Approval |' '| 6 | `/deploy-production` | Infrastructure |'; do
    32 |         grep -qxF "$row" "$LOA"
    33 |     done
    34 |     grep -qF 'memory lives in `grimoires/loa/NOTES.md`' "$LOA"
    35 | }
    36 | 
    37 | @test "IDR-3 the twelve constraint rationales carry their pre-diet text" {
>   38 |     run python3 - "$R/.claude/data/constraints.json" "$R/tests/fixtures/constraint-rationales-pre-diet.json" <<'PY'
    39 | import json, sys
    40 | found = {}
    41 | def walk(x):
    42 |     if isinstance(x, dict):
    43 |         if "id" in x and "why" in x:
    44 |             found[x["id"]] = x["why"]
    45 |         for v in x.values():
    46 |             walk(v)
    47 |     elif isinstance(x, list):
    48 |         for v in x:
    49 |             walk(v)
    50 | walk(json.load(open(sys.argv[1])))
~~~~

The change from head to the fix:

~~~~diff
@@ -38 +38 @@
-    run python3 - "$R/.claude/data/constraints.json" "$R/tests/fixtures/constraint-rationales-pre-diet.json" <<'PY'
+    run python3 -I - "$R/.claude/data/constraints.json" "$R/tests/fixtures/constraint-rationales-pre-diet.json" <<'PY'
~~~~

## H83 — tests/unit/license-fixture-freshness.bats — head line 35

Head context (head/tests/unit/license-fixture-freshness.bats, lines 23–47):

~~~~text
    23 | }
    24 | 
    25 | _offline_until() {
    26 |     python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["offline_valid_until"])' "$1"
    27 | }
    28 | 
    29 | _is_future() {
    30 |     python3 -c 'import sys,datetime as d; t=d.datetime.strptime(sys.argv[1],"%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=d.timezone.utc); sys.exit(0 if t > d.datetime.now(d.timezone.utc) else 1)' "$1"
    31 | }
    32 | 
    33 | @test "LFF-1: a grace fixture past its offline window is regenerated even when valid_license.json is fresh" {
    34 |     # Age only the grace fixture: its window closed yesterday.
>   35 |     python3 - "$WORK/grace_period_license.json" <<'PY'
    36 | import json, sys
    37 | p = sys.argv[1]
    38 | d = json.load(open(p))
    39 | d["expires_at"] = "2026-01-01T00:00:00Z"
    40 | d["offline_valid_until"] = "2026-01-02T00:00:00Z"
    41 | json.dump(d, open(p, "w"))
    42 | PY
    43 |     source "$WORK/ensure_license_fixtures.sh"
    44 |     _is_future "$(_offline_until "$WORK/grace_period_license.json")"
    45 | }
    46 | 
    47 | @test "LFF-2: fresh fixtures are left alone (no regeneration on every call)" {
~~~~

The change from head to the fix:

~~~~diff
@@ -35 +35 @@
-    python3 - "$WORK/grace_period_license.json" <<'PY'
+    python3 -I - "$WORK/grace_period_license.json" <<'PY'
~~~~

## H84 — tests/unit/license-fixture-freshness.bats — insertion after head line 51

Head context (head/tests/unit/license-fixture-freshness.bats, lines 40–51):

~~~~text
    40 | d["offline_valid_until"] = "2026-01-02T00:00:00Z"
    41 | json.dump(d, open(p, "w"))
    42 | PY
    43 |     source "$WORK/ensure_license_fixtures.sh"
    44 |     _is_future "$(_offline_until "$WORK/grace_period_license.json")"
    45 | }
    46 | 
    47 | @test "LFF-2: fresh fixtures are left alone (no regeneration on every call)" {
    48 |     local before; before="$(cksum < "$WORK/grace_period_license.json")"
    49 |     source "$WORK/ensure_license_fixtures.sh"
    50 |     [ "$(cksum < "$WORK/grace_period_license.json")" = "$before" ]
    51 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -51,0 +52,45 @@
+
+@test "LFF-3: a grace fixture that expires within the margin (now + 30 min) is regenerated, not trusted to outlive the suite" {
+    # sprint-250 review run 1, n39: a zero-margin check passed a window closing
+    # seconds later, and the fixture then expired mid-suite. Run 2, #8: the
+    # margin is 3600 s (the full unit run takes ~38 min), so a window closing
+    # in 30 minutes — past the old 300 s margin — is regenerated too.
+    python3 -I - "$WORK/grace_period_license.json" <<'PY'
+import json, sys, datetime as dt
+p = sys.argv[1]
+d = json.load(open(p))
+d["offline_valid_until"] = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M:%SZ")
+json.dump(d, open(p, "w"))
+PY
+    local soon; soon="$(_offline_until "$WORK/grace_period_license.json")"
+    source "$WORK/ensure_license_fixtures.sh"
+    [ "$(_offline_until "$WORK/grace_period_license.json")" != "$soon" ]
+    python3 -c 'import sys,datetime as d; t=d.datetime.strptime(sys.argv[1],"%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=d.timezone.utc); sys.exit(0 if t > d.datetime.now(d.timezone.utc) + d.timedelta(hours=1) else 1)' "$(_offline_until "$WORK/grace_period_license.json")"
+}
+
+@test "LFF-4: on a host east of UTC the JWT exp agrees with expires_at (the generator never reads a naive UTC time as local)" {
+    # sprint-250 review round 1: datetime.utcnow() is naive and .timestamp()
+    # reads it as local time, so on AEDT (UTC+11) every JWT exp landed 11 hours
+    # early and the pro tier's 24h grace closed 1 hour after generation.
+    ( cd "$WORK" && TZ=Australia/Sydney python3 generate_test_licenses.py >/dev/null )
+    python3 -I - "$WORK/grace_period_license.json" "$WORK/valid_license.json" <<'PY'
+import base64, json, sys, datetime as dt
+for p in sys.argv[1:]:
+    d = json.load(open(p))
+    seg = d["token"].split(".")[1]
+    exp = json.loads(base64.urlsafe_b64decode(seg + "=" * (-len(seg) % 4)))["exp"]
+    want = int(dt.datetime.strptime(d["expires_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc).timestamp())
+    assert abs(exp - want) <= 1, f"{p}: jwt exp {exp} vs expires_at {want} (delta {exp - want} s)"
+    issued = dt.datetime.strptime(d["issued_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)
+    assert abs((issued - dt.datetime.now(dt.timezone.utc)).total_seconds()) < 300, f"{p}: issued_at {d['issued_at']} is not UTC now"
+PY
+}
+
+@test "LFF-5: fixtures older than the generator are regenerated (a generator fix reaches an existing checkout)" {
+    local before; before="$(cksum < "$WORK/grace_period_license.json")"
+    touch -d '2026-01-01T00:00:00Z' "$WORK"/*.json
+    touch "$WORK/generate_test_licenses.py"
+    sleep 1
+    source "$WORK/ensure_license_fixtures.sh"
+    [ "$(cksum < "$WORK/grace_period_license.json")" != "$before" ]
+}
~~~~

## H85 — tests/unit/model-adapter.bats — insertion after head line 94

Head context (head/tests/unit/model-adapter.bats, lines 83–94):

~~~~text
    83 | 
    84 | @test "MA-6 (bd-pw7e LOW-001) the WARN is forwarded on a failed hop too, and the exit code is kept" {
    85 |     cat > "$TMP_DIR/mi" <<'SHIM'
    86 | #!/usr/bin/env bash
    87 | echo "[cheval] WARNING: gemini-headless dispatches agy, which takes the whole prompt on argv" >&2
    88 | exit 7
    89 | SHIM
    90 |     chmod +x "$TMP_DIR/mi"
    91 |     MODEL_INVOKE="$TMP_DIR/mi" run --separate-stderr bash "$ADAPTER" --model opus --mode review --input "$TMP_DIR/input.txt"
    92 |     [ "$status" -eq 7 ]
    93 |     [[ "$stderr" == *"gemini-headless dispatches agy"* ]]
    94 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -94,0 +95,84 @@
+
+@test "MA-7 (sprint-250 review run 1, n15) an unusable TMPDIR does not abort the call: the shim still runs and the result comes back" {
+    cat > "$TMP_DIR/mi" <<SHIM
+#!/usr/bin/env bash
+printf '%s\n' "\$@" > "$TMP_DIR/argv"
+echo "[cheval] WARNING: gemini-headless dispatches agy, which takes the whole prompt on argv" >&2
+printf '%s\n' '{"content": "ok", "model": "stub", "provider": "stub", "usage": {"input_tokens": 1, "output_tokens": 1}, "latency_ms": 1}'
+SHIM
+    chmod +x "$TMP_DIR/mi"
+    TMPDIR=/nonexistent/r250 MODEL_INVOKE="$TMP_DIR/mi" run --separate-stderr bash "$ADAPTER" --model opus --mode review --input "$TMP_DIR/input.txt"
+    [ "$status" -eq 0 ]
+    [ -s "$TMP_DIR/argv" ]
+    [[ "$output" == *"ok"* ]]
+    [ -c /dev/null ]   # the fallback never removes /dev/null
+    # the degraded mode is visible: one WARN line names the lost relay (sprint-250 review run 2, #7)
+    [[ "$stderr" == *"WARN: model-adapter: stderr capture disabled"*"agy argv-exposure WARN will not be relayed"* ]]
+    [ "$(grep -c 'stderr capture disabled' <<<"$stderr")" -eq 1 ]
+}
+
+@test "MA-8 (sprint-250 review run 1, n15) a caller's TERM mid-call leaves no model-adapter-stderr file behind" {
+    local priv="$TMP_DIR/priv-tmp" pid
+    mkdir -p "$priv"
+    cat > "$TMP_DIR/mi" <<SHIM
+#!/usr/bin/env bash
+echo "\$\$" > "$TMP_DIR/started"
+exec sleep 20
+SHIM
+    chmod +x "$TMP_DIR/mi"
+    TMPDIR="$priv" MODEL_INVOKE="$TMP_DIR/mi" bash "$ADAPTER" --model opus --mode review --input "$TMP_DIR/input.txt" >/dev/null 2>&1 &
+    pid=$!
+    for _ in $(seq 1 100); do [ -e "$TMP_DIR/started" ] && break; sleep 0.1; done
+    [ -e "$TMP_DIR/started" ]
+    compgen -G "$priv/model-adapter-stderr.*" >/dev/null   # the file exists while the hop runs
+    kill -TERM "$pid"
+    wait "$pid" || true
+    kill "$(cat "$TMP_DIR/started")" 2>/dev/null || true   # the orphaned shim sleep
+    run compgen -G "$priv/model-adapter-stderr.*"
+    [ "$status" -ne 0 ] || { echo "left behind: $output" >&2; return 1; }
+}
+
+@test "MA-9 (sprint-250 review run 2, #6) the stderr-file EXIT trap never clobbers or removes an EXIT trap already set" {
+    cat > "$TMP_DIR/mi" <<SHIM
+#!/usr/bin/env bash
+printf '%s\n' '{"content": "ok", "model": "stub", "provider": "stub", "usage": {"input_tokens": 1, "output_tokens": 1}, "latency_ms": 1}'
+exit "\${MI_EXIT:-0}"
+SHIM
+    chmod +x "$TMP_DIR/mi"
+    local priv="$TMP_DIR/priv-tmp"; mkdir -p "$priv"
+    # sourced, so a prior EXIT trap exists when main() runs; success path
+    TMPDIR="$priv" MODEL_INVOKE="$TMP_DIR/mi" run --separate-stderr bash -c 'trap "echo PRIOR-EXIT-RAN >&2" EXIT; source "$1" --model opus --mode review --input "$2"' _ "$ADAPTER" "$TMP_DIR/input.txt"
+    [ "$status" -eq 0 ]
+    [[ "$output" == *"ok"* ]]
+    [[ "$stderr" == *"PRIOR-EXIT-RAN"* ]]
+    # failure path: main() exits while the stderr file is live — both handlers run
+    MI_EXIT=3 TMPDIR="$priv" MODEL_INVOKE="$TMP_DIR/mi" run --separate-stderr bash -c 'trap "echo PRIOR-EXIT-RAN >&2" EXIT; source "$1" --model opus --mode review --input "$2"' _ "$ADAPTER" "$TMP_DIR/input.txt"
+    [ "$status" -eq 3 ]
+    [[ "$stderr" == *"PRIOR-EXIT-RAN"* ]]
+    run compgen -G "$priv/model-adapter-stderr.*"
+    [ "$status" -ne 0 ] || { echo "left behind: $output" >&2; return 1; }
+}
+
+@test "MA-10 (sprint-250 review run 3, #4) a TERM while the chained EXIT trap is installed runs both halves: the stderr file goes and the prior handler runs" {
+    # MA-9's failure path exits after the prior trap is restored, so only this
+    # case exercises the chained handler itself
+    local priv="$TMP_DIR/priv-tmp" marker="$TMP_DIR/prior-ran" pid
+    mkdir -p "$priv"
+    cat > "$TMP_DIR/mi" <<SHIM
+#!/usr/bin/env bash
+echo "\$\$" > "$TMP_DIR/started"
+exec sleep 20
+SHIM
+    chmod +x "$TMP_DIR/mi"
+    TMPDIR="$priv" MODEL_INVOKE="$TMP_DIR/mi" bash -c 'trap "echo PRIOR-EXIT-RAN > \"$3\"" EXIT; source "$1" --model opus --mode review --input "$2"' _ "$ADAPTER" "$TMP_DIR/input.txt" "$marker" >/dev/null 2>&1 &
+    pid=$!
+    for _ in $(seq 1 100); do [ -e "$TMP_DIR/started" ] && break; sleep 0.1; done
+    [ -e "$TMP_DIR/started" ]
+    compgen -G "$priv/model-adapter-stderr.*" >/dev/null   # the chained trap is live
+    kill -TERM "$pid"
+    wait "$pid" || true
+    kill "$(cat "$TMP_DIR/started")" 2>/dev/null || true   # the orphaned shim sleep
+    run compgen -G "$priv/model-adapter-stderr.*"
+    [ "$status" -ne 0 ] || { echo "left behind: $output" >&2; return 1; }
+    [ "$(cat "$marker")" = "PRIOR-EXIT-RAN" ]
+}
~~~~

## H86 — tests/unit/model-config-v3-schema.bats — head line 487

Head context (head/tests/unit/model-config-v3-schema.bats, lines 475–499):

~~~~text
   475 | @test "V3-add (c126): params.beta_headers is a list of dated beta flags (the adapter's allowlist)" {
   476 |     run validate_v3 "$(_c126_model '{"context_window": 1000000, "params": {"beta_headers": []}}')"
   477 |     [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
   478 |     run validate_v3 "$(_c126_model '{"context_window": 1000000, "params": {"beta_headers": ["context-1m-2025-08-07", "interleaved-thinking-2025-05-14"]}}')"
   479 |     [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
   480 |     for bad in '"context-1m-2025-08-07"' '["Context-1M-2025-08-07"]' '["context-1m"]' '["context-1m-2025-8-7"]' \
   481 |                '[1]' '["context-1m-2025-08-07,x-2025-01-01"]' '["context--1m-2025-08-07"]' null; do
   482 |         run validate_v3 "$(_c126_model "{\"context_window\": 1000000, \"params\": {\"beta_headers\": $bad}}")"
   483 |         [ "$status" -ne 0 ] || { echo "accepted beta_headers: $bad" >&2; return 1; }
   484 |     done
   485 | }
   486 | 
>  487 | @test "V3 (c126): every beta-header value the schema accepts, the adapter accepts (never looser)" {
   488 |     cd "$PROJECT_ROOT/.claude/adapters"
   489 |     run "$PYTHON_BIN" - "$SCHEMA_V3" <<'PYEOF'
   490 | import json, re, sys
   491 | from loa_cheval.providers import anthropic_adapter as a
   492 | schema = json.load(open(sys.argv[1]))
   493 | pat = schema["$defs"]["modelEntry"]["properties"]["params"]["properties"]["beta_headers"]["items"]["pattern"]
   494 | cases = ["context-1m-2025-08-07", "a-2025-01-01", "x1-y2-2030-12-31", "Context-1m-2025-08-07", "context-1m",
   495 |          "context-1m-2025-8-7", "-a-2025-01-01", "a--b-2025-01-01", "a-2025-01-01-", "a b-2025-01-01",
   496 |          "a-٢٠٢٥-01-01"]
   497 | accepted = [c for c in cases if re.search(pat, c)]
   498 | assert "context-1m-2025-08-07" in accepted, accepted
   499 | bad = [c for c in accepted if not a._BETA_HEADER_RE.match(c)]
~~~~

The change from head to the fix:

~~~~diff
@@ -487 +487 @@
-@test "V3 (c126): every beta-header value the schema accepts, the adapter accepts (never looser)" {
+@test "V3 (c126): every beta-header value the schema accepts, the adapter accepts, and every value it rejects, the adapter rejects" {
~~~~

## H87 — tests/unit/model-config-v3-schema.bats — insertion after head line 499

Head context (head/tests/unit/model-config-v3-schema.bats, lines 488–511):

~~~~text
   488 |     cd "$PROJECT_ROOT/.claude/adapters"
   489 |     run "$PYTHON_BIN" - "$SCHEMA_V3" <<'PYEOF'
   490 | import json, re, sys
   491 | from loa_cheval.providers import anthropic_adapter as a
   492 | schema = json.load(open(sys.argv[1]))
   493 | pat = schema["$defs"]["modelEntry"]["properties"]["params"]["properties"]["beta_headers"]["items"]["pattern"]
   494 | cases = ["context-1m-2025-08-07", "a-2025-01-01", "x1-y2-2030-12-31", "Context-1m-2025-08-07", "context-1m",
   495 |          "context-1m-2025-8-7", "-a-2025-01-01", "a--b-2025-01-01", "a-2025-01-01-", "a b-2025-01-01",
   496 |          "a-٢٠٢٥-01-01"]
   497 | accepted = [c for c in cases if re.search(pat, c)]
   498 | assert "context-1m-2025-08-07" in accepted, accepted
   499 | bad = [c for c in accepted if not a._BETA_HEADER_RE.match(c)]
   500 | print("MISMATCH %r" % bad if bad else "OK")
   501 | PYEOF
   502 |     [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
   503 |     [[ "$output" == *"OK"* ]] || { echo "$output" >&2; return 1; }
   504 | }
   505 | 
   506 | @test "Live (c124): production model-config.yaml migrated with --to-v3 validates against v3 and keeps the catalog's own ceiling" {
   507 |     MIGRATE="$PROJECT_ROOT/.claude/scripts/loa-migrate-model-config.py"
   508 |     "$PYTHON_BIN" -c "import ruamel.yaml" 2>/dev/null || skip "ruamel.yaml not available in $PYTHON_BIN"
   509 |     run "$PYTHON_BIN" "$MIGRATE" "$PROJECT_ROOT/.claude/defaults/model-config.yaml" \
   510 |         -o "$WORK_DIR/live-v3.yaml" --to-v3 \
   511 |         --model-permissions "$PROJECT_ROOT/.claude/data/model-permissions.yaml" \
~~~~

The change from head to the fix:

~~~~diff
@@ -499,0 +500,20 @@
+# Converse (audit dissent run 1, n1/n4): every value the schema REJECTS, the adapter's
+# own check (_beta_header_value) rejects. The schema is read with JSON Schema's ECMA-262
+# semantics: non-multiline `$` is end of input (Python's `$` also matches before a final
+# newline, so it is rewritten to \Z) and `[0-9]` is ASCII only.
+assert pat.endswith("$") and "\\d" not in pat, pat
+assert a._BETA_HEADER_RE.pattern == pat, (a._BETA_HEADER_RE.pattern, pat)
+ecma = re.compile(pat[:-1] + r"\Z", re.ASCII)
+rejected = cases + ["context-1m-2025-08-07\n", "context-1m-2025-08-07\r\n", "context-1m-\u0662\u0660\u0662\u0665-08-07",
+                    "context-1m-2025-08-0\u0667", "context-1m-2025-08-07 ", "\ncontext-1m-2025-08-07"]
+rejected = [c for c in rejected if not ecma.search(c)]
+assert "context-1m-2025-08-07\n" in rejected and "context-1m-\u0662\u0660\u0662\u0665-08-07" in rejected, rejected
+loose = []
+for c in rejected:
+    try:
+        a._beta_header_value({"beta_headers": [c]}, "m")
+        loose.append(c)
+    except Exception as e:
+        if type(e).__name__ != "ConfigError":
+            raise
+bad += ["adapter-accepted %r" % c for c in loose]
~~~~

## H88 — tests/unit/model-residue.bats — insertion after head line 10

Head context (head/tests/unit/model-residue.bats, lines 1–22):

~~~~text
     1 | #!/usr/bin/env bats
     2 | # =============================================================================
     3 | # tests/unit/model-residue.bats — cycle-126 sprint-250 Tasks 4.2/4.3 (SDD D-4.1,
     4 | # D-4.3; bead bd-2fti). No routing alias, bash map, default or example pin names
     5 | # the previous generation as current: the bash maps agree with the catalog's
     6 | # `opus`, the script defaults are catalog aliases, `cheap` is Sonnet 5, the
     7 | # Gemini agents name served ids, and the acceptance grep returns nothing.
     8 | # =============================================================================
     9 | 
    10 | setup() {
    11 |     R="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    12 |     CAT="${RES_CAT:-$R/.claude/defaults/model-config.yaml}"   # RES_CAT: red-first replay against a base catalog
    13 | }
    14 | 
    15 | yq_cat() { python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1]))
    16 | for k in sys.argv[2].split("."): d=d[k]
    17 | print(d)' "$CAT" "$1"; }
    18 | 
    19 | # map_value <script> <array> <key>
    20 | map_value() {
    21 |     local src
    22 |     src=$(awk -v a="$2" '$0 ~ "^declare -A "a"=\\(" {f=1} f{print} f && /^\)/{exit}' "$1")
~~~~

The change from head to the fix:

~~~~diff
@@ -10,0 +11 @@
+    bats_require_minimum_version 1.5.0   # `run -1 grep`: a bare `! grep` cannot fail, and only "no match" (exit 1) passes — a missing file (exit 2) fails (sprint-250 review run 1, n20; run 2, #10)
~~~~

## H89 — tests/unit/model-residue.bats — head lines 60–63

Head context (head/tests/unit/model-residue.bats, lines 48–75):

~~~~text
    48 | @test "RES-3 script defaults are catalog aliases: flatline-proposal-review / validate-learning / learning-extractor / red-team-pipeline" {
    49 |     local s
    50 |     for s in flatline-proposal-review.sh flatline-validate-learning.sh; do
    51 |         grep -qF 'GPT_MODEL="${LOA_GPT_MODEL:-reviewer}"' "$R/.claude/scripts/$s" || { echo "$s GPT" >&2; return 1; }
    52 |         grep -qF 'OPUS_MODEL="${LOA_OPUS_MODEL:-opus}"' "$R/.claude/scripts/$s" || { echo "$s OPUS" >&2; return 1; }
    53 |     done
    54 |     grep -qF 'call_flatline_chat "cheap"' "$R/.claude/scripts/flatline-learning-extractor.sh"
    55 |     grep -qF '.red_team.models.evaluator_primary // "opus"' "$R/.claude/scripts/red-team-pipeline.sh"
    56 |     [ "$(yq_cat aliases.reviewer)" != "" ]
    57 | }
    58 | 
    59 | @test "RES-4 example pins: hitl-jury-panel uses opus, alternative-model names the Bedrock Opus 4.8 id the catalog serves" {
>   60 |     ! grep -q 'claude-opus-4-7' "$R/.claude/skills/hitl-jury-panel/SKILL.md"
>   61 |     [ "$(grep -c '      model: opus$' "$R/.claude/skills/hitl-jury-panel/SKILL.md")" -ge 2 ]
>   62 |     grep -qF 'bedrock:us.anthropic.claude-opus-4-8' "$R/.claude/data/personas/alternative-model.md"
>   63 |     ! grep -q 'claude-3-5-sonnet' "$R/.claude/data/personas/alternative-model.md"
    64 |     python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); assert "us.anthropic.claude-opus-4-8" in d["providers"]["bedrock"]["models"]' "$CAT"
    65 | }
    66 | 
    67 | @test "RES-5 Gemini agents name served ids: deep-thinker → gemini-3.1-pro (thinking_traces), fast-thinker stays gemini-3-flash (no 3.1 flash served)" {
    68 |     [ "$(yq_cat agents.deep-thinker.model)" = "gemini-3.1-pro" ]
    69 |     python3 - "$CAT" <<'PY'
    70 | import sys, yaml
    71 | d = yaml.safe_load(open(sys.argv[1]))
    72 | target = d["aliases"]["gemini-3.1-pro"].split(":", 1)[1]
    73 | assert "thinking_traces" in d["providers"]["google"]["models"][target]["capabilities"], target
    74 | assert d["agents"]["fast-thinker"]["model"] == "gemini-3-flash"
    75 | assert not any(k.startswith("gemini-3.1-flash") for k in d["providers"]["google"]["models"])
~~~~

The change from head to the fix:

~~~~diff
@@ -60,4 +61,4 @@
-    ! grep -q 'claude-opus-4-7' "$R/.claude/skills/hitl-jury-panel/SKILL.md"
+    run -1 grep -q 'claude-opus-4-7' "$R/.claude/skills/hitl-jury-panel/SKILL.md"
     [ "$(grep -c '      model: opus$' "$R/.claude/skills/hitl-jury-panel/SKILL.md")" -ge 2 ]
     grep -qF 'bedrock:us.anthropic.claude-opus-4-8' "$R/.claude/data/personas/alternative-model.md"
-    ! grep -q 'claude-3-5-sonnet' "$R/.claude/data/personas/alternative-model.md"
+    run -1 grep -q 'claude-3-5-sonnet' "$R/.claude/data/personas/alternative-model.md"
~~~~

## H90 — tests/unit/model-residue.bats — head line 69

Head context (head/tests/unit/model-residue.bats, lines 57–81):

~~~~text
    57 | }
    58 | 
    59 | @test "RES-4 example pins: hitl-jury-panel uses opus, alternative-model names the Bedrock Opus 4.8 id the catalog serves" {
    60 |     ! grep -q 'claude-opus-4-7' "$R/.claude/skills/hitl-jury-panel/SKILL.md"
    61 |     [ "$(grep -c '      model: opus$' "$R/.claude/skills/hitl-jury-panel/SKILL.md")" -ge 2 ]
    62 |     grep -qF 'bedrock:us.anthropic.claude-opus-4-8' "$R/.claude/data/personas/alternative-model.md"
    63 |     ! grep -q 'claude-3-5-sonnet' "$R/.claude/data/personas/alternative-model.md"
    64 |     python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); assert "us.anthropic.claude-opus-4-8" in d["providers"]["bedrock"]["models"]' "$CAT"
    65 | }
    66 | 
    67 | @test "RES-5 Gemini agents name served ids: deep-thinker → gemini-3.1-pro (thinking_traces), fast-thinker stays gemini-3-flash (no 3.1 flash served)" {
    68 |     [ "$(yq_cat agents.deep-thinker.model)" = "gemini-3.1-pro" ]
>   69 |     python3 - "$CAT" <<'PY'
    70 | import sys, yaml
    71 | d = yaml.safe_load(open(sys.argv[1]))
    72 | target = d["aliases"]["gemini-3.1-pro"].split(":", 1)[1]
    73 | assert "thinking_traces" in d["providers"]["google"]["models"][target]["capabilities"], target
    74 | assert d["agents"]["fast-thinker"]["model"] == "gemini-3-flash"
    75 | assert not any(k.startswith("gemini-3.1-flash") for k in d["providers"]["google"]["models"])
    76 | PY
    77 | }
    78 | 
    79 | @test "RES-6 the acceptance grep: no previous-generation model is a default or described as current in live scripts, skills and data" {
    80 |     run grep -rnE -- ':-gpt-4o|:-claude-3|"gpt-4o-mini"|// "claude-opus-4-|\["opus"\]="anthropic:claude-opus-4-|Claude Opus 4\.7 \(current|model: claude-opus-4-7$|claude-3-5-sonnet' \
    81 |         "$R/.claude/scripts" "$R/.claude/data" "$R/.claude/hooks" \
~~~~

The change from head to the fix:

~~~~diff
@@ -69 +70 @@
-    python3 - "$CAT" <<'PY'
+    python3 -I - "$CAT" <<'PY'
~~~~

## H91 — tests/unit/protocol-refs-resolve.bats — insertion after head line 12

Head context (head/tests/unit/protocol-refs-resolve.bats, lines 1–24):

~~~~text
     1 | #!/usr/bin/env bats
     2 | # =============================================================================
     3 | # tests/unit/protocol-refs-resolve.bats — cycle-124 FR-8 / AC-8.3
     4 | #
     5 | # Every `protocols/<name>.md` (and `protocols/reference/<name>.md`) string in .claude/, PROCESS.md, CONTRIBUTING.md,
     6 | # tests/ and .github/workflows/ resolves to a file under .claude/protocols/,
     7 | # so an archived protocol cannot leave a dangling pointer behind. Synthetic
     8 | # strings (test fixtures) are listed in tools/protocol-refs.allowlist with a
     9 | # reason, and a stale allowlist row is itself a failure.
    10 | # =============================================================================
    11 | 
    12 | setup() {
    13 |     SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    14 |     PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    15 |     ALLOW="$PROJECT_ROOT/tools/protocol-refs.allowlist"
    16 | }
    17 | 
    18 | # file:name.md pairs for every reference in scope (tracked files only — the
    19 | # working tree also holds ignored local docs under .claude/config/)
    20 | refs() {
    21 |     ( cd "$PROJECT_ROOT" && git ls-files -z -- .claude PROCESS.md CONTRIBUTING.md tests .github/workflows 2>/dev/null \
    22 |         | xargs -0 grep -noE 'protocols/(reference/)?[A-Za-z0-9_-]+\.md' 2>/dev/null \
    23 |         | awk -F: '{ sub(/^protocols\//, "", $3); print $1 "\t" $3 }' | sort -u )
    24 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -12,0 +13 @@
+    bats_require_minimum_version 1.5.0   # `run -1 grep`: a bare `! grep` cannot fail, and only "no match" (exit 1) passes — a missing file (exit 2) fails (sprint-250 review run 1, n20; run 2, #10)
~~~~

## H92 — tests/unit/protocol-refs-resolve.bats — head line 58

Head context (head/tests/unit/protocol-refs-resolve.bats, lines 46–64):

~~~~text
    46 | @test "PR-2 no stale allowlist row (every row still matches an unresolved reference)" {
    47 |     local stale=0 a_sub a_name
    48 |     while IFS=$'\t' read -r a_sub a_name _; do
    49 |         refs | awk -F'\t' -v s="$a_sub" -v n="$a_name" 'index($1, s) && $2 == n { found = 1 } END { exit found ? 0 : 1 }' \
    50 |             || { echo "STALE allowlist row: $a_sub $a_name"; stale=$((stale + 1)); }
    51 |     done < <(grep -v -E '^\s*(#|$)' "$ALLOW")
    52 |     [ "$stale" -eq 0 ]
    53 | }
    54 | 
    55 | @test "PR-3 the three archived protocols are gone from .claude/protocols and their summary rows with them" {
    56 |     for p in risk-analysis upgrade-process sprint-completion; do
    57 |         [ ! -e "$PROJECT_ROOT/.claude/protocols/$p.md" ]
>   58 |         ! grep -q "protocols/$p.md" "$PROJECT_ROOT/.claude/loa/reference/protocols-summary.md"
    59 |     done
    60 | }
    61 | 
    62 | @test "PR-4 the scan covers protocols/reference/ pointers (the cycle-126 moves), so a dangling one is caught by PR-1" {
    63 |     refs | awk -F'\t' '$2 ~ /^reference\// { n++ } END { exit n > 0 ? 0 : 1 }'
    64 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -58 +59 @@
-        ! grep -q "protocols/$p.md" "$PROJECT_ROOT/.claude/loa/reference/protocols-summary.md"
+        run -1 grep -q "protocols/$p.md" "$PROJECT_ROOT/.claude/loa/reference/protocols-summary.md"
~~~~

## H93 — tests/unit/skill-capabilities.bats — head lines 876–879

Head context (head/tests/unit/skill-capabilities.bats, lines 864–891):

~~~~text
   864 |     [ "$status" -eq 0 ]
   865 |     SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-scout
   866 |     [ "$status" -eq 1 ]
   867 |     [[ "$output" == *"agent type 'loa-scout'"*"(general-purpose claude fork)"* ]]
   868 |     SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-io
   869 |     [ "$status" -eq 1 ]
   870 | }
   871 | 
   872 | @test "SC-T-AGENT-8: the validator reads the list from the data file, not a hard-coded array" {
   873 |     printf 'agent_types:\n  Plan:\n    write_capable: true\n  general-purpose:\n    write_capable: false\n' > "$BATS_TEST_TMPDIR/agent-types.yaml"
   874 |     agent_skill w-plan Plan
   875 |     agent_skill w-gp general-purpose
>  876 |     AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/agent-types.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-plan
>  877 |     [ "$status" -eq 0 ]
>  878 |     AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/agent-types.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-gp
>  879 |     [ "$status" -eq 1 ]
   880 | }
   881 | 
   882 | @test "SC-T-AGENT-9: a missing or unreadable agent-types file falls back to general-purpose only" {
   883 |     agent_skill w-claude claude
   884 |     agent_skill w-gp general-purpose
   885 |     AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/absent.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-claude
   886 |     [ "$status" -eq 1 ]
   887 |     printf 'agent_types: [\n' > "$BATS_TEST_TMPDIR/broken.yaml"
   888 |     AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/broken.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-gp
   889 |     [ "$status" -eq 0 ]
   890 |     AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/broken.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-claude
   891 |     [ "$status" -eq 1 ]
~~~~

The change from head to the fix:

~~~~diff
@@ -876,4 +876,6 @@
-    AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/agent-types.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-plan
+    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --agent-types-file "$BATS_TEST_TMPDIR/agent-types.yaml" --skill w-plan
     [ "$status" -eq 0 ]
-    AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/agent-types.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-gp
+    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-gp --agent-types-file "$BATS_TEST_TMPDIR/agent-types.yaml"
     [ "$status" -eq 1 ]
+    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-gp --agent-types-file
+    [ "$status" -eq 2 ]
~~~~

## H94 — tests/unit/skill-capabilities.bats — head lines 885–892

Head context (head/tests/unit/skill-capabilities.bats, lines 873–892):

~~~~text
   873 |     printf 'agent_types:\n  Plan:\n    write_capable: true\n  general-purpose:\n    write_capable: false\n' > "$BATS_TEST_TMPDIR/agent-types.yaml"
   874 |     agent_skill w-plan Plan
   875 |     agent_skill w-gp general-purpose
   876 |     AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/agent-types.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-plan
   877 |     [ "$status" -eq 0 ]
   878 |     AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/agent-types.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-gp
   879 |     [ "$status" -eq 1 ]
   880 | }
   881 | 
   882 | @test "SC-T-AGENT-9: a missing or unreadable agent-types file falls back to general-purpose only" {
   883 |     agent_skill w-claude claude
   884 |     agent_skill w-gp general-purpose
>  885 |     AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/absent.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-claude
>  886 |     [ "$status" -eq 1 ]
>  887 |     printf 'agent_types: [\n' > "$BATS_TEST_TMPDIR/broken.yaml"
>  888 |     AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/broken.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-gp
>  889 |     [ "$status" -eq 0 ]
>  890 |     AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/broken.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-claude
>  891 |     [ "$status" -eq 1 ]
>  892 | }
~~~~

The change from head to the fix:

~~~~diff
@@ -885,8 +887,22 @@
-    AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/absent.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-claude
+    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --agent-types-file "$BATS_TEST_TMPDIR/absent.yaml" --skill w-claude
     [ "$status" -eq 1 ]
     printf 'agent_types: [\n' > "$BATS_TEST_TMPDIR/broken.yaml"
-    AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/broken.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-gp
+    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --agent-types-file "$BATS_TEST_TMPDIR/broken.yaml" --skill w-gp
     [ "$status" -eq 0 ]
-    AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/broken.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-claude
+    SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --agent-types-file "$BATS_TEST_TMPDIR/broken.yaml" --skill w-claude
     [ "$status" -eq 1 ]
 }
+
+@test "SC-T-AGENT-10: the ambient AGENT_TYPES_FILE variable never redirects the allowlist, bats markers or not; only the explicit --agent-types-file argument does (audit run 3, finding 13)" {
+    printf 'agent_types:\n  Plan:\n    write_capable: true\n' > "$BATS_TEST_TMPDIR/agent-types.yaml"
+    agent_skill w-plan Plan
+    run env -u BATS_TEST_FILENAME -u BATS_VERSION -u BATS_TEST_DIRNAME -u BATS_TEST_TMPDIR \
+        AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/agent-types.yaml" SKILLS_DIR="$FIXTURE_DIR" "$VALIDATOR" --skill w-plan
+    [ "$status" -eq 1 ]
+    [[ "$output" == *"agent type 'Plan'"* ]]
+    AGENT_TYPES_FILE="$BATS_TEST_TMPDIR/agent-types.yaml" SKILLS_DIR="$FIXTURE_DIR" run "$VALIDATOR" --skill w-plan
+    [ "$status" -eq 1 ]
+    [[ "$output" == *"agent type 'Plan'"* ]]
+    run "$VALIDATOR" --help
+    [[ "$output" == *"--agent-types-file"* ]]
+}
~~~~

## H95 — tools/check-prompt-budget.sh — head line 50

Head context (head/tools/check-prompt-budget.sh, lines 38–62):

~~~~text
    38 | QUIET=0
    39 | while [[ $# -gt 0 ]]; do
    40 |   case "$1" in
    41 |     --root) [[ $# -ge 2 ]] || { echo "check-prompt-budget.sh: --root needs a directory" >&2; exit 2; }; ROOT="$2"; shift 2 ;;
    42 |     --json) JSON=1; shift ;;
    43 |     --quiet|-q) QUIET=1; shift ;;
    44 |     --help|-h) sed -n '/^# Usage:/,/^# Exit codes/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    45 |     *) echo "check-prompt-budget.sh: unknown arg $1" >&2; exit 2 ;;
    46 |   esac
    47 | done
    48 | [[ -d "$ROOT/.claude" ]] || { echo "check-prompt-budget.sh: no .claude/ under $ROOT" >&2; exit 2; }
    49 | 
>   50 | python3 - "$ROOT" "$JSON" "$QUIET" <<'PY'
    51 | import glob, json, os, re, sys
    52 | root, as_json, quiet = sys.argv[1], sys.argv[2] == "1", sys.argv[3] == "1"
    53 | SKILL_LIMIT, LOA_LIMIT, PROTO_FAIL, PROTO_WARN = 16384, 10240, 160000, 114688
    54 | IMPERATIVE = re.compile(r"\b(read|load|source|include)\b", re.I)
    55 | GUARD = re.compile(r"\b(if|when|only|optional|as needed|on demand|unless|may|see)\b", re.I)
    56 | HISTORY = re.compile(r"cycle-[0-9]{3}|#[0-9]{3,4}|KF-[0-9]{3}")
    57 | RES = re.compile(r"resources/([A-Za-z0-9_.-]+\.md)")
    58 | 
    59 | def size(p):
    60 |     return os.path.getsize(p)
    61 | 
    62 | violations, skills = [], []
~~~~

The change from head to the fix:

~~~~diff
@@ -50 +50 @@
-python3 - "$ROOT" "$JSON" "$QUIET" <<'PY'
+python3 -I - "$ROOT" "$JSON" "$QUIET" <<'PY'
~~~~
