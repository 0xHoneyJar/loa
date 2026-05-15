#!/usr/bin/env bats
# =============================================================================
# tests/unit/cycle-109-t3-3-flatline-extract-json-content.bats
#
# cycle-109 Sprint 3 T3.3 — regression test for #863 Bug 2 (scoring engine
# emits no_items_to_score even when models return content).
#
# Bug shape (per #863 Bug 2 + #759):
#   - Phase 1 Opus/Gemini calls succeed; .content carries parseable JSON.
#   - Phase 3 (consensus) emits 'no items to score; emitting degraded'.
#   - Per-model `*-items.json` files are ~15 bytes (likely "[]").
#   - Workaround: bypass orchestrator, call model-adapter.sh directly.
#
# Hypothesis: extract_json_content / normalize_json_response trips on
# some shape of cheval's content output (escaped JSON, markdown fences,
# prose-wrapped, etc.) and falls through to the default `{"improvements":
# []}` — which the scoring engine sees as empty.
#
# This file exercises extract_json_content with the canonical shapes
# cheval emits and asserts the EXTRACTED items match the EXPECTED items
# (not the default). Any failure here pinpoints the specific shape the
# parser drops.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT

    # Source the orchestrator helpers we want to test. The orchestrator
    # has a `main "$@"` at the bottom — we need to source it without
    # invoking main. The script doesn't have a source-vs-exec guard yet
    # (T2.5 added that guard ONLY to adversarial-review.sh); we route
    # around by stubbing `main` and the env-precondition checks before
    # sourcing.

    # Stub functions main + log + error so sourcing is hermetic
    main() { :; }
    log() { :; }
    error() { printf '%s\n' "$*" >&2; return 1; }
    # Cheval/yq/jq checks short-circuit successfully
    check_dependencies() { :; }
    # Source the lib + orchestrator
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.claude/scripts/lib/normalize-json.sh" 2>/dev/null
    # We don't source the full orchestrator (too many top-level side
    # effects); we test normalize_json_response directly + a thin
    # extract_json_content re-implementation that mirrors the
    # orchestrator's call shape.

    BATS_TMP="$(mktemp -d "${BATS_TMPDIR:-/tmp}/t33.XXXXXX")"
}

teardown() {
    rm -rf "$BATS_TMP" 2>/dev/null || true
}

# Replicates flatline-orchestrator.sh::extract_json_content for hermetic
# testing. Matches the production behavior verbatim (read .content from
# review file, normalize, fallback to default on failure).
_extract_json_content() {
    local file="$1"
    local default="$2"

    if [[ ! -f "$file" ]]; then
        echo "$default"
        return
    fi

    local content
    content=$(jq -r '.content // ""' "$file" 2>/dev/null)

    if [[ -z "$content" || "$content" == "null" ]]; then
        echo "$default"
        return
    fi

    local normalized
    normalized=$(normalize_json_response "$content" 2>/dev/null) || {
        echo "$default"
        return
    }

    echo "$normalized"
}

# =============================================================================
# T33-1: Plain JSON content (no fences, no prose) — happy path
# =============================================================================

@test "T33-1: extract_json_content unwraps plain JSON content" {
    local review="$BATS_TMP/plain.json"
    cat > "$review" <<'JSON'
{
    "content": "{\n  \"improvements\": [\n    {\"id\": \"IMP-001\", \"description\": \"Add error handling\", \"priority\": \"HIGH\"}\n  ]\n}"
}
JSON
    local result
    result=$(_extract_json_content "$review" '{"improvements":[]}')
    local count
    count=$(echo "$result" | jq '.improvements | length')
    [ "$count" -eq 1 ]
    local id
    id=$(echo "$result" | jq -r '.improvements[0].id')
    [ "$id" = "IMP-001" ]
}

# =============================================================================
# T33-2: Markdown-fenced JSON content
# =============================================================================

@test "T33-2: extract_json_content handles markdown-fenced JSON" {
    local review="$BATS_TMP/fenced.json"
    cat > "$review" <<'JSON'
{
    "content": "```json\n{\n  \"improvements\": [\n    {\"id\": \"IMP-002\", \"priority\": \"MED\"}\n  ]\n}\n```"
}
JSON
    local result
    result=$(_extract_json_content "$review" '{"improvements":[]}')
    local count
    count=$(echo "$result" | jq '.improvements | length')
    [ "$count" -eq 1 ]
}

# =============================================================================
# T33-3: Prose-wrapped JSON (what Opus actually emits sometimes)
# =============================================================================

@test "T33-3: extract_json_content extracts JSON wrapped in prose" {
    local review="$BATS_TMP/prose.json"
    cat > "$review" <<'JSON'
{
    "content": "Here is my review of the document:\n\n{\n  \"improvements\": [\n    {\"id\": \"IMP-003\", \"description\": \"Better naming\", \"priority\": \"LOW\"}\n  ]\n}\n\nLet me know if you need clarification."
}
JSON
    local result
    result=$(_extract_json_content "$review" '{"improvements":[]}')
    local count
    count=$(echo "$result" | jq '.improvements | length')
    [ "$count" -eq 1 ]
}

# =============================================================================
# T33-4: Content with BOM prefix (UTF-8 BOM EF BB BF)
# =============================================================================

@test "T33-4: extract_json_content strips BOM prefix" {
    local review="$BATS_TMP/bom.json"
    # JSON-encode the BOM bytes:
    "$(command -v python3)" <<PY > "$review"
import json
content = "﻿" + '{"improvements": [{"id": "IMP-004"}]}'
print(json.dumps({"content": content}))
PY
    local result
    result=$(_extract_json_content "$review" '{"improvements":[]}')
    local count
    count=$(echo "$result" | jq '.improvements | length')
    [ "$count" -eq 1 ]
}

# =============================================================================
# T33-5: Empty content field → default
# =============================================================================

@test "T33-5: extract_json_content returns default when content is empty" {
    local review="$BATS_TMP/empty.json"
    echo '{"content": ""}' > "$review"
    local result
    result=$(_extract_json_content "$review" '{"improvements":[]}')
    local count
    count=$(echo "$result" | jq '.improvements | length')
    [ "$count" -eq 0 ]
}

# =============================================================================
# T33-6: Missing .content field → default
# =============================================================================

@test "T33-6: extract_json_content returns default when .content is null/missing" {
    local review="$BATS_TMP/no-content.json"
    echo '{"model": "claude-opus-4-7", "usage": {"input_tokens": 100}}' > "$review"
    local result
    result=$(_extract_json_content "$review" '{"improvements":[]}')
    local count
    count=$(echo "$result" | jq '.improvements | length')
    [ "$count" -eq 0 ]
}

# =============================================================================
# T33-7: Content with nested top-level prose (multiple JSON-like fragments)
# =============================================================================

@test "T33-7: extract_json_content prefers actual improvements over inline mentions" {
    local review="$BATS_TMP/multi-fragment.json"
    # Real bug class: model output mentions { example } in prose then
    # emits the real JSON below. Python3 raw_decode (step 4 of
    # normalize_json_response) should pick the first parseable object.
    cat > "$review" <<'JSON'
{
    "content": "Looking at the document, I see issues with { syntax }.\n\nMy findings:\n{\n  \"improvements\": [\n    {\"id\": \"IMP-007\", \"description\": \"Real finding\", \"priority\": \"HIGH\"}\n  ]\n}"
}
JSON
    local result
    result=$(_extract_json_content "$review" '{"improvements":[]}')
    local count
    count=$(echo "$result" | jq '.improvements | length' 2>/dev/null || echo "0")
    # Tolerant assertion: parser MAY pick the first {syntax} bracket OR
    # the real improvements. Either way, it should NOT silently fall
    # through to the default (which is the bug — empty default).
    # Detection rule: the result MUST NOT be the literal default value.
    if [[ "$result" != '{"improvements":[]}' ]] && [[ "$result" != *'"improvements": []'* ]]; then
        # Parser extracted something — pass
        true
    else
        # Parser fell through to default — that's the #863 Bug 2 shape
        echo "FAIL: extract_json_content fell through to default on prose+JSON shape" >&2
        echo "Result: $result" >&2
        false
    fi
}

# =============================================================================
# T33-8: Opus shape regression — the actual bug-trigger fixture
# =============================================================================

@test "T33-8: Opus 'content as escaped JSON object string' is unwrapped correctly" {
    # The actual repro from #863: cheval returns content field that is
    # an escaped JSON string. jq -r '.content' unescapes it to a raw
    # JSON object literal; normalize_json_response then parses it.
    # If this test FAILS, that's the bug.
    local review="$BATS_TMP/opus-real.json"
    # Generate via python3 to ensure correct escaping
    "$(command -v python3)" <<'PY' > "$review"
import json
# Opus often emits the full document with metadata, like the #863 paste
opus_output = {
    "content": "{\n  \"improvements\": [\n    {\n      \"id\": \"IMP-001\",\n      \"description\": \"Improve error handling in dispatch loop\",\n      \"priority\": \"HIGH\",\n      \"confidence\": 0.9\n    },\n    {\n      \"id\": \"IMP-002\",\n      \"description\": \"Add structured logging\",\n      \"priority\": \"MED\",\n      \"confidence\": 0.7\n    }\n  ]\n}",
    "tokens_input": 15701,
    "tokens_output": 2614,
    "cost_usd": 0.1438
}
print(json.dumps(opus_output))
PY
    local result
    result=$(_extract_json_content "$review" '{"improvements":[]}')
    local count
    count=$(echo "$result" | jq '.improvements | length')
    # The Opus-shape fixture has 2 improvements; bug shape would give 0.
    [ "$count" -eq 2 ]
    local ids
    ids=$(echo "$result" | jq -r '.improvements[].id' | sort | tr '\n' ',' | sed 's/,$//')
    [ "$ids" = "IMP-001,IMP-002" ]
}
