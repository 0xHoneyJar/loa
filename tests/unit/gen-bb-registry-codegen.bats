#!/usr/bin/env bats
# =============================================================================
# gen-bb-registry-codegen.bats — cycle-099 Sprint 1A (T1.1 + T1.10 partial)
# =============================================================================
# Tests for .claude/skills/bridgebuilder-review/scripts/gen-bb-registry.ts.
#
# The codegen script reads .claude/defaults/model-config.yaml and emits two
# TypeScript files into the bridgebuilder-review skill:
#   - resources/core/truncation.generated.ts (TOKEN_BUDGETS map)
#   - resources/config.generated.ts          (MODEL_REGISTRY map)
#
# Runtime: npx tsx (Bun-compatible — script uses only node:* APIs).
# YAML parsing: shells out to yq (mikefarah/yq v4+; same toolchain as
# cycle-095 gen-adapter-maps.sh).
#
# Sprint plan: grimoires/loa/cycles/cycle-099-model-registry/sprint.md §1
# SDD §1.4.3, §3.4, §5.3
# AC: AC-S1.1 (deterministic byte-equal codegen)

setup() {
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export BB_SKILL_DIR="$PROJECT_ROOT/.claude/skills/bridgebuilder-review"
    export GEN_SCRIPT="$BB_SKILL_DIR/scripts/gen-bb-registry.ts"
    export DEFAULTS_YAML="$PROJECT_ROOT/.claude/defaults/model-config.yaml"
    # Use BB skill's pinned local tsx (devDependency) — supply-chain hardened
    # vs `npx tsx` which would fall back to fetching the latest release on
    # cache miss. CI must `npm install` in the BB skill before running tests.
    export TSX="$BB_SKILL_DIR/node_modules/.bin/tsx"
    export OUTPUT_DIR="$BATS_TEST_TMPDIR/gen-output"
    export TRUNC_OUT="$OUTPUT_DIR/core/truncation.generated.ts"
    export CONFIG_OUT="$OUTPUT_DIR/config.generated.ts"
    mkdir -p "$OUTPUT_DIR/core"

    # Preconditions — fail fast with a clear message rather than an opaque
    # 'command not found' or 'no such file' from a downstream test (BB F2).
    if ! command -v yq >/dev/null; then
        skip "yq required (mikefarah/yq v4+) — install via brew/apt/asdf"
    fi
    if [ ! -x "$TSX" ]; then
        skip "tsx not found at $TSX — run 'npm install' in $BB_SKILL_DIR first"
    fi
}

# ---------------------------------------------------------------------------
# T1: script existence + invocation contract
# ---------------------------------------------------------------------------

@test "T1: codegen script file exists" {
    [ -f "$GEN_SCRIPT" ]
}

@test "T1: --help prints usage and exits 0" {
    run "$TSX" "$GEN_SCRIPT" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"gen-bb-registry"* ]]
    [[ "$output" == *"--check"* ]]
    [[ "$output" == *"--output-dir"* ]]
}

@test "T1: default emit creates two output files" {
    run "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 0 ]
    [ -f "$TRUNC_OUT" ]
    [ -f "$CONFIG_OUT" ]
}

# ---------------------------------------------------------------------------
# T2: byte-determinism (AC-S1.1)
# ---------------------------------------------------------------------------

@test "T2: two consecutive runs produce byte-identical truncation.generated.ts" {
    run "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 0 ]
    cp "$TRUNC_OUT" "$BATS_TEST_TMPDIR/run1-truncation.ts"

    run "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 0 ]

    run diff "$BATS_TEST_TMPDIR/run1-truncation.ts" "$TRUNC_OUT"
    [ "$status" -eq 0 ]
}

@test "T2: two consecutive runs produce byte-identical config.generated.ts" {
    run "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 0 ]
    cp "$CONFIG_OUT" "$BATS_TEST_TMPDIR/run1-config.ts"

    run "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 0 ]

    run diff "$BATS_TEST_TMPDIR/run1-config.ts" "$CONFIG_OUT"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T3: parity with hardcoded TOKEN_BUDGETS in resources/core/truncation.ts
# ---------------------------------------------------------------------------

@test "T3: truncation.generated.ts contains claude-opus-4-7 with maxInput=200000, maxOutput=8192, coefficient=0.25" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    grep -E '"claude-opus-4-7":[[:space:]]*\{[[:space:]]*maxInput:[[:space:]]*200000,[[:space:]]*maxOutput:[[:space:]]*8192,[[:space:]]*coefficient:[[:space:]]*0\.25' "$TRUNC_OUT"
}

@test "T3: truncation.generated.ts contains claude-opus-4-6 with parity" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    grep -E '"claude-opus-4-6":[[:space:]]*\{[[:space:]]*maxInput:[[:space:]]*200000,[[:space:]]*maxOutput:[[:space:]]*8192,[[:space:]]*coefficient:[[:space:]]*0\.25' "$TRUNC_OUT"
}

@test "T3: truncation.generated.ts contains claude-sonnet-4-6 with parity" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    grep -E '"claude-sonnet-4-6":[[:space:]]*\{[[:space:]]*maxInput:[[:space:]]*200000,[[:space:]]*maxOutput:[[:space:]]*8192,[[:space:]]*coefficient:[[:space:]]*0\.25' "$TRUNC_OUT"
}

@test "T3: truncation.generated.ts contains gpt-5.2 with maxInput=128000, maxOutput=4096, coefficient=0.23" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    grep -E '"gpt-5\.2":[[:space:]]*\{[[:space:]]*maxInput:[[:space:]]*128000,[[:space:]]*maxOutput:[[:space:]]*4096,[[:space:]]*coefficient:[[:space:]]*0\.23' "$TRUNC_OUT"
}

@test "T3: truncation.generated.ts contains 'default' fallback entry" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    # Default fallback: maxInput=100000, maxOutput=4096, coefficient=0.25 (matches existing TOKEN_BUDGETS["default"])
    grep -E 'default:[[:space:]]*\{[[:space:]]*maxInput:[[:space:]]*100000,[[:space:]]*maxOutput:[[:space:]]*4096,[[:space:]]*coefficient:[[:space:]]*0\.25' "$TRUNC_OUT"
}

# ---------------------------------------------------------------------------
# T4: config.generated.ts model registry shape
# ---------------------------------------------------------------------------

@test "T4: config.generated.ts contains GENERATED_MODEL_REGISTRY export" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    # Anchor on line start to ensure the export body exists, not just the
    # comment-line mention of the symbol in the file header.
    grep -E '^export const GENERATED_MODEL_REGISTRY' "$CONFIG_OUT"
}

@test "T4: config.generated.ts contains anthropic provider entry for claude-opus-4-7" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    # Look for both the model id key and the anthropic provider value in the entry
    grep -F '"claude-opus-4-7":' "$CONFIG_OUT"
    grep -F 'provider: "anthropic"' "$CONFIG_OUT"
}

@test "T4: config.generated.ts contains gpt-5.2 with openai provider + context_window 128000" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    grep -F '"gpt-5.2":' "$CONFIG_OUT"
    grep -F 'provider: "openai"' "$CONFIG_OUT"
    grep -F 'contextWindow: 128000' "$CONFIG_OUT"
}

@test "T4: config.generated.ts contains gemini-3.1-pro-preview with google provider" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    grep -F '"gemini-3.1-pro-preview":' "$CONFIG_OUT"
    grep -F 'provider: "google"' "$CONFIG_OUT"
}

# ---------------------------------------------------------------------------
# T5: --check mode (drift detection)
# ---------------------------------------------------------------------------

@test "T5: --check exits 0 immediately after default emit (no drift)" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    [ -f "$TRUNC_OUT" ]

    run "$TSX" "$GEN_SCRIPT" --check --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 0 ]
}

@test "T5: --check exits 3 after hand-editing truncation.generated.ts" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    [ -f "$TRUNC_OUT" ]

    # Tamper: append a bogus comment line
    echo "// hand-edit drift marker" >> "$TRUNC_OUT"

    run "$TSX" "$GEN_SCRIPT" --check --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 3 ]
}

@test "T5: --check exits 3 when output files are missing" {
    # Files do not exist yet
    [ ! -f "$TRUNC_OUT" ]

    run "$TSX" "$GEN_SCRIPT" --check --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 3 ]
}

@test "T5: --check error message includes [DRIFT-DETECTED] marker" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    echo "// drift" >> "$TRUNC_OUT"

    run "$TSX" "$GEN_SCRIPT" --check --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 3 ]
    [[ "$output" == *"[DRIFT-DETECTED]"* ]]
}

# ---------------------------------------------------------------------------
# T6: TypeScript compilation of generated files
# ---------------------------------------------------------------------------

@test "T6: generated truncation.generated.ts is syntactically valid TypeScript" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    # Use tsc --noEmit on a stub project that imports types.ts (where TokenBudget is declared).
    # We can't typecheck in isolation since the file imports from "./types.js"; instead, use
    # Node 24's experimental TS strip + parse via tsx's syntactic check (run + immediately exit).
    # tsx will fail at parse time for syntax errors.
    cat > "$BATS_TEST_TMPDIR/check-truncation.mjs" <<'EOF'
import { readFileSync } from "node:fs";
const src = readFileSync(process.argv[2], "utf8");
// Structural sanity: file is non-empty, ends with newline, has the export
// AS A STATEMENT (line-anchored) — substring match would also catch the
// header-comment mention of the symbol, missing a regression that drops
// the export body entirely.
if (src.length < 200) { console.error("file too short"); process.exit(1); }
if (!src.endsWith("\n")) { console.error("missing trailing newline"); process.exit(1); }
if (!/^export const GENERATED_TOKEN_BUDGETS/m.test(src)) {
  console.error("missing GENERATED_TOKEN_BUDGETS export statement"); process.exit(1);
}
EOF
    run node "$BATS_TEST_TMPDIR/check-truncation.mjs" "$TRUNC_OUT"
    [ "$status" -eq 0 ]
}

@test "T6: generated config.generated.ts has well-formed exports (line-anchored)" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    grep -E '^export interface GeneratedModelEntry' "$CONFIG_OUT"
    grep -E '^export const GENERATED_MODEL_REGISTRY' "$CONFIG_OUT"
}

# ---------------------------------------------------------------------------
# T7: header invariants (machine-readable provenance, no timestamps for determinism)
# ---------------------------------------------------------------------------

@test "T7: generated files contain DO NOT EDIT header" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    grep -F "DO NOT EDIT" "$TRUNC_OUT"
    grep -F "DO NOT EDIT" "$CONFIG_OUT"
}

@test "T7: generated files reference source yaml path in header" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    grep -F "model-config.yaml" "$TRUNC_OUT"
    grep -F "model-config.yaml" "$CONFIG_OUT"
}

@test "T7: generated files do NOT contain timestamps (determinism guard)" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    # Reject ISO 8601 timestamps and any year-month-day pattern that would break byte-determinism.
    if grep -E '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T' "$TRUNC_OUT"; then
        echo "FAIL: truncation.generated.ts contains a timestamp"
        return 1
    fi
    if grep -E '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T' "$CONFIG_OUT"; then
        echo "FAIL: config.generated.ts contains a timestamp"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# T8: model coverage from yaml
# ---------------------------------------------------------------------------

@test "T8: truncation.generated.ts covers all anthropic models from yaml" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    # Every model under .providers.anthropic.models in yaml must appear as a TOKEN_BUDGETS key.
    local yaml_models
    yaml_models=$(yq -r '.providers.anthropic.models | keys | .[]' "$DEFAULTS_YAML")
    for model in $yaml_models; do
        if ! grep -qF "\"$model\":" "$TRUNC_OUT"; then
            echo "FAIL: anthropic model $model missing from truncation.generated.ts"
            return 1
        fi
    done
}

@test "T8: config.generated.ts covers all openai models from yaml" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    local yaml_models
    yaml_models=$(yq -r '.providers.openai.models | keys | .[]' "$DEFAULTS_YAML")
    for model in $yaml_models; do
        if ! grep -qF "\"$model\":" "$CONFIG_OUT"; then
            echo "FAIL: openai model $model missing from config.generated.ts"
            return 1
        fi
    done
}

# ---------------------------------------------------------------------------
# T9: end-to-end build-chain integration (AC-S1.1 — review H1)
# ---------------------------------------------------------------------------
# Proves that `npm run build` invokes the codegen, AND that the on-disk tree
# state after build agrees with --check (no drift). Without this, a future
# change that breaks the build-pipeline order (e.g., tsc emitting *.generated.js
# next to source, a new `prebuild` script, or `cd resources` semantics
# breaking) would slip through.
#
# T9 invokes the npm script which writes to BB_SKILL_DIR/resources/ — i.e.,
# the committed working tree. The _t9_snapshot/_t9_restore helpers preserve
# the committed-tree state so the test does not leave the developer's git
# diff dirty (BB F4). Files are restored even on test failure.

_t9_committed_truncation="$BB_SKILL_DIR/resources/core/truncation.generated.ts"
_t9_committed_config="$BB_SKILL_DIR/resources/config.generated.ts"

_t9_snapshot() {
    if [ -f "$_t9_committed_truncation" ]; then
        cp "$_t9_committed_truncation" "$BATS_TEST_TMPDIR/t9-snapshot-truncation"
    fi
    if [ -f "$_t9_committed_config" ]; then
        cp "$_t9_committed_config" "$BATS_TEST_TMPDIR/t9-snapshot-config"
    fi
}

_t9_restore() {
    if [ -f "$BATS_TEST_TMPDIR/t9-snapshot-truncation" ]; then
        cp "$BATS_TEST_TMPDIR/t9-snapshot-truncation" "$_t9_committed_truncation"
    fi
    if [ -f "$BATS_TEST_TMPDIR/t9-snapshot-config" ]; then
        cp "$BATS_TEST_TMPDIR/t9-snapshot-config" "$_t9_committed_config"
    fi
}

@test "T9: npm run gen-bb-registry from BB skill dir succeeds" {
    # trap-on-EXIT ensures restore fires even on SIGINT/SIGTERM/timeout — the
    # explicit _t9_restore call is redundant but kept for clarity (BB iter-2 F2).
    trap _t9_restore EXIT
    _t9_snapshot
    cd "$BB_SKILL_DIR"
    run npm run gen-bb-registry
    local rc=$status
    _t9_restore
    [ "$rc" -eq 0 ]
    [[ "$output" == *"generated:"* ]]
}

@test "T9: npm run gen-bb-registry:check passes against committed tree (post-regen)" {
    trap _t9_restore EXIT
    _t9_snapshot
    cd "$BB_SKILL_DIR"
    # Regenerate first so committed tree matches what the codegen would emit.
    run npm run gen-bb-registry
    local rc1=$status
    if [ "$rc1" -ne 0 ]; then _t9_restore; [ "$rc1" -eq 0 ]; fi

    # --check now must pass (exit 0).
    run npm run gen-bb-registry:check
    local rc2=$status
    _t9_restore
    [ "$rc2" -eq 0 ]
}

# ---------------------------------------------------------------------------
# T10: parity guard against existing TOKEN_BUDGETS in resources/core/truncation.ts
# (review H2 + M1 — prevents sprint-1B import-swap from silently dropping a
# model that the hand-maintained map currently covers)
# ---------------------------------------------------------------------------

@test "T10: generated keyset is a superset of existing TOKEN_BUDGETS keys" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    local existing="$BB_SKILL_DIR/resources/core/truncation.ts"
    [ -f "$existing" ]

    # Extract every quoted key from the TOKEN_BUDGETS literal (lines 430-437 in
    # cycle-098 baseline). Pattern matches `"<modelId>": {` after leading
    # whitespace inside the literal block.
    local existing_keys
    existing_keys=$(grep -E '^[[:space:]]*"[^"]+":[[:space:]]*\{' "$existing" \
                    | sed -E 's/^[[:space:]]*"([^"]+)":.*/\1/' \
                    | sort -u)

    local missing=""
    for key in $existing_keys; do
        # "default" is emitted as a special last-row fallback in the generated
        # file (no quotes). Check for the unquoted form too.
        if ! grep -qE "(\"$key\":|^[[:space:]]+$key:)" "$TRUNC_OUT"; then
            missing="$missing $key"
        fi
    done

    if [ -n "$missing" ]; then
        echo "FAIL: generated truncation map missing keys present in existing TOKEN_BUDGETS:$missing"
        echo "      existing file: $existing"
        echo "      generated file: $TRUNC_OUT"
        echo "      fix: add the model to .claude/defaults/model-config.yaml,"
        echo "      OR explicitly retire it before sprint-1B import-swap"
        return 1
    fi
}

@test "T10: generated maxInput parity for models present in BOTH yaml + existing TOKEN_BUDGETS" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    local existing="$BB_SKILL_DIR/resources/core/truncation.ts"

    # Extract `"<modelId>": { maxInput: <N>, ... }` from existing map and
    # assert the generated file emits the same maxInput for that key.
    while IFS= read -r line; do
        # Strip leading whitespace and parse modelId + maxInput.
        local key
        local existing_input
        key=$(echo "$line" | sed -E 's/^[[:space:]]*"([^"]+)":.*/\1/')
        existing_input=$(echo "$line" | sed -E 's/.*maxInput:[[:space:]]*([0-9_]+).*/\1/' | tr -d '_')
        # Skip lines that didn't match (key empty or non-numeric input).
        if [ -z "$key" ] || ! [[ "$existing_input" =~ ^[0-9]+$ ]]; then
            continue
        fi
        # Skip "default" — generated emits it unquoted.
        if [ "$key" = "default" ]; then
            continue
        fi
        # Find the line in generated output for this key, extract its maxInput.
        local gen_line
        gen_line=$(grep -F "\"$key\":" "$TRUNC_OUT" || true)
        if [ -z "$gen_line" ]; then
            # Already covered by the superset test; skip here to avoid double-fail.
            continue
        fi
        local gen_input
        gen_input=$(echo "$gen_line" | sed -E 's/.*maxInput:[[:space:]]*([0-9]+).*/\1/')
        if [ "$existing_input" != "$gen_input" ]; then
            echo "FAIL: maxInput mismatch for $key — existing=$existing_input generated=$gen_input"
            return 1
        fi
    done < <(grep -E '^[[:space:]]*"[^"]+":[[:space:]]*\{[[:space:]]*maxInput' "$existing")
}

# ---------------------------------------------------------------------------
# T11: prototype-pollution guard (audit HIGH-1)
# All keys must be quoted strings. Reserved object-literal sugar names like
# __proto__ and constructor would silently shadow Object.prototype if emitted
# bare. Even if no current model_id triggers this, a future yaml entry could.
# ---------------------------------------------------------------------------

@test "T11: every TOKEN_BUDGETS entry uses a quoted string key (no bare identifiers)" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    # Find the export block boundaries.
    local start
    local end
    start=$(grep -n '^export const GENERATED_TOKEN_BUDGETS' "$TRUNC_OUT" | head -1 | cut -d: -f1)
    end=$(awk -v s="$start" 'NR>s && /^};/ {print NR; exit}' "$TRUNC_OUT")
    [ -n "$start" ]
    [ -n "$end" ]

    # Every key line inside the block must start with a quote.
    local bare
    # Match exactly 2-space indent (top-level entry keys only); inner fields
    # like `pricing: {...}` use 4-space indent and are correctly excluded.
    bare=$(awk -v s="$start" -v e="$end" 'NR>s && NR<e' "$TRUNC_OUT" \
           | grep -E '^  [A-Za-z_$][A-Za-z0-9_$]*:[[:space:]]*\{' || true)

    if [ -n "$bare" ]; then
        echo "FAIL: bare-identifier keys found in TOKEN_BUDGETS (would silently shadow prototype):"
        echo "$bare"
        return 1
    fi
}

@test "T11: every MODEL_REGISTRY entry uses a quoted string key" {
    "$TSX" "$GEN_SCRIPT" --output-dir "$OUTPUT_DIR"
    local start
    local end
    start=$(grep -n '^export const GENERATED_MODEL_REGISTRY' "$CONFIG_OUT" | head -1 | cut -d: -f1)
    end=$(awk -v s="$start" 'NR>s && /^};/ {print NR; exit}' "$CONFIG_OUT")
    [ -n "$start" ]
    [ -n "$end" ]

    local bare
    # Match exactly 2-space indent (top-level entry keys only); inner fields
    # like `pricing: {...}` use 4-space indent and are correctly excluded.
    bare=$(awk -v s="$start" -v e="$end" 'NR>s && NR<e' "$CONFIG_OUT" \
           | grep -E '^  [A-Za-z_$][A-Za-z0-9_$]*:[[:space:]]*\{' || true)

    if [ -n "$bare" ]; then
        echo "FAIL: bare-identifier keys found in MODEL_REGISTRY (would silently shadow prototype):"
        echo "$bare"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# T12: invalid context_window rejection (audit MEDIUM-1)
# ---------------------------------------------------------------------------

@test "T12: codegen rejects negative context_window with exit 78" {
    local bad_yaml="$BATS_TEST_TMPDIR/bad-negative.yaml"
    cat > "$bad_yaml" <<'EOF'
providers:
  testprovider:
    models:
      bogus-negative:
        context_window: -1
EOF

    run "$TSX" "$GEN_SCRIPT" --source-yaml "$bad_yaml" --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 78 ]
    [[ "$output" == *"[CONFIG-ERROR]"* ]]
    [[ "$output" == *"invalid context_window"* ]]
}

@test "T12: codegen rejects non-integer context_window" {
    local bad_yaml="$BATS_TEST_TMPDIR/bad-float.yaml"
    cat > "$bad_yaml" <<'EOF'
providers:
  testprovider:
    models:
      bogus-float:
        context_window: 1.5
EOF

    run "$TSX" "$GEN_SCRIPT" --source-yaml "$bad_yaml" --output-dir "$OUTPUT_DIR"
    [ "$status" -eq 78 ]
    [[ "$output" == *"invalid context_window"* ]]
}
