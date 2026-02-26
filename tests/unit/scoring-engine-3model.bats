#!/usr/bin/env bats
# Unit tests for scoring-engine.sh 3-model consensus (bug-flatline-3model)
# Tests: 2-model backward compat, 3-model with tertiary items, degraded mode

setup() {
    BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
    SCORING_ENGINE="$PROJECT_ROOT/.claude/scripts/scoring-engine.sh"
    FIXTURES="$BATS_TEST_DIR/../fixtures/scoring-engine"
    mkdir -p "$FIXTURES"

    # Create 2-model score fixtures
    cat > "$FIXTURES/gpt-scores-2model.json" <<'FIXTURE'
{"scores":[
  {"id":"IMP-001","score":850,"evaluation":"Strong improvement","would_integrate":true},
  {"id":"IMP-002","score":400,"evaluation":"Minor improvement","would_integrate":false},
  {"id":"IMP-003","score":750,"evaluation":"Good improvement","would_integrate":true}
]}
FIXTURE

    cat > "$FIXTURES/opus-scores-2model.json" <<'FIXTURE'
{"scores":[
  {"id":"IMP-001","score":800,"evaluation":"Agreed, strong","would_integrate":true},
  {"id":"IMP-002","score":350,"evaluation":"Not worth it","would_integrate":false},
  {"id":"IMP-003","score":300,"evaluation":"Disagree, not useful","would_integrate":false}
]}
FIXTURE

    # Create 3-model tertiary cross-scoring fixtures
    # Tertiary scores of Opus items
    cat > "$FIXTURES/tertiary-scores-opus.json" <<'FIXTURE'
{"scores":[
  {"id":"IMP-001","score":780,"evaluation":"Tertiary agrees on opus item"},
  {"id":"IMP-002","score":420,"evaluation":"Tertiary neutral on opus item"}
]}
FIXTURE

    # Tertiary scores of GPT items
    cat > "$FIXTURES/tertiary-scores-gpt.json" <<'FIXTURE'
{"scores":[
  {"id":"IMP-001","score":810,"evaluation":"Tertiary agrees on gpt item"},
  {"id":"IMP-003","score":650,"evaluation":"Tertiary moderate on gpt item"}
]}
FIXTURE

    # GPT scores of Tertiary items
    cat > "$FIXTURES/gpt-scores-tertiary.json" <<'FIXTURE'
{"scores":[
  {"id":"TIMP-001","score":900,"evaluation":"GPT loves tertiary item","would_integrate":true},
  {"id":"TIMP-002","score":350,"evaluation":"GPT dislikes tertiary item","would_integrate":false}
]}
FIXTURE

    # Opus scores of Tertiary items
    cat > "$FIXTURES/opus-scores-tertiary.json" <<'FIXTURE'
{"scores":[
  {"id":"TIMP-001","score":850,"evaluation":"Opus agrees on tertiary item","would_integrate":true},
  {"id":"TIMP-002","score":300,"evaluation":"Opus also dislikes","would_integrate":false}
]}
FIXTURE

    # Skeptic fixtures
    cat > "$FIXTURES/skeptic-gpt.json" <<'FIXTURE'
{"concerns":[
  {"concern":"Missing error handling","severity_score":750,"category":"robustness"}
]}
FIXTURE

    cat > "$FIXTURES/skeptic-opus.json" <<'FIXTURE'
{"concerns":[
  {"concern":"Race condition risk","severity_score":800,"category":"concurrency"}
]}
FIXTURE

    cat > "$FIXTURES/skeptic-tertiary.json" <<'FIXTURE'
{"concerns":[
  {"concern":"Missing error handling","severity_score":720,"category":"robustness"},
  {"concern":"No input validation","severity_score":600,"category":"security"}
]}
FIXTURE

    # Empty fixtures for degraded tests
    echo '{"scores":[]}' > "$FIXTURES/empty-scores.json"
}

# =============================================================================
# 2-Model Backward Compatibility
# =============================================================================

@test "2-model mode: accepts standard args without error" {
    run "$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --json
    [ "$status" -eq 0 ]
}

@test "2-model mode: classifies HIGH_CONSENSUS correctly" {
    result=$("$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --json 2>/dev/null)
    high_count=$(echo "$result" | jq '.consensus_summary.high_consensus_count')
    [ "$high_count" -ge 1 ]
}

@test "2-model mode: reports 2 models in summary" {
    result=$("$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --json 2>/dev/null)
    models=$(echo "$result" | jq '.consensus_summary.models')
    [ "$models" -eq 2 ]
}

@test "2-model mode: no tertiary items in output" {
    result=$("$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --json 2>/dev/null)
    tertiary_items=$(echo "$result" | jq '.consensus_summary.tertiary_items')
    [ "$tertiary_items" -eq 0 ]
}

# =============================================================================
# 3-Model Tertiary Cross-Scoring
# =============================================================================

@test "3-model mode: accepts all tertiary args without error" {
    run "$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --tertiary-scores-opus "$FIXTURES/tertiary-scores-opus.json" \
        --tertiary-scores-gpt "$FIXTURES/tertiary-scores-gpt.json" \
        --gpt-scores-tertiary "$FIXTURES/gpt-scores-tertiary.json" \
        --opus-scores-tertiary "$FIXTURES/opus-scores-tertiary.json" \
        --json
    [ "$status" -eq 0 ]
}

@test "3-model mode: reports 3 models in summary" {
    result=$("$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --tertiary-scores-opus "$FIXTURES/tertiary-scores-opus.json" \
        --tertiary-scores-gpt "$FIXTURES/tertiary-scores-gpt.json" \
        --gpt-scores-tertiary "$FIXTURES/gpt-scores-tertiary.json" \
        --opus-scores-tertiary "$FIXTURES/opus-scores-tertiary.json" \
        --json 2>/dev/null)
    models=$(echo "$result" | jq '.consensus_summary.models')
    [ "$models" -eq 3 ]
}

@test "3-model mode: includes tertiary-authored items" {
    result=$("$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --tertiary-scores-opus "$FIXTURES/tertiary-scores-opus.json" \
        --tertiary-scores-gpt "$FIXTURES/tertiary-scores-gpt.json" \
        --gpt-scores-tertiary "$FIXTURES/gpt-scores-tertiary.json" \
        --opus-scores-tertiary "$FIXTURES/opus-scores-tertiary.json" \
        --json 2>/dev/null)
    tertiary_items=$(echo "$result" | jq '.consensus_summary.tertiary_items')
    [ "$tertiary_items" -ge 1 ]
}

@test "3-model mode: TIMP-001 classified as HIGH_CONSENSUS (both >700)" {
    result=$("$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --gpt-scores-tertiary "$FIXTURES/gpt-scores-tertiary.json" \
        --opus-scores-tertiary "$FIXTURES/opus-scores-tertiary.json" \
        --json 2>/dev/null)
    timp001=$(echo "$result" | jq '[.high_consensus[] | select(.id == "TIMP-001")] | length')
    [ "$timp001" -eq 1 ]
}

@test "3-model mode: TIMP-002 classified as LOW_VALUE (both <400)" {
    result=$("$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --gpt-scores-tertiary "$FIXTURES/gpt-scores-tertiary.json" \
        --opus-scores-tertiary "$FIXTURES/opus-scores-tertiary.json" \
        --json 2>/dev/null)
    timp002=$(echo "$result" | jq '[.low_value[] | select(.id == "TIMP-002")] | length')
    [ "$timp002" -eq 1 ]
}

@test "3-model mode: tertiary_score field present for confirmed items" {
    result=$("$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --tertiary-scores-opus "$FIXTURES/tertiary-scores-opus.json" \
        --tertiary-scores-gpt "$FIXTURES/tertiary-scores-gpt.json" \
        --gpt-scores-tertiary "$FIXTURES/gpt-scores-tertiary.json" \
        --opus-scores-tertiary "$FIXTURES/opus-scores-tertiary.json" \
        --json 2>/dev/null)
    # IMP-001 has tertiary scores from both t_opus and t_gpt maps
    has_tertiary=$(echo "$result" | jq '[.high_consensus[] | select(.id == "IMP-001" and .tertiary_score != null)] | length')
    [ "$has_tertiary" -ge 1 ]
}

# =============================================================================
# Skeptic Concerns with Tertiary (3 sources)
# =============================================================================

@test "3-model mode: skeptic concerns from 3 sources deduplicated" {
    result=$("$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --include-blockers \
        --skeptic-gpt "$FIXTURES/skeptic-gpt.json" \
        --skeptic-opus "$FIXTURES/skeptic-opus.json" \
        --skeptic-tertiary "$FIXTURES/skeptic-tertiary.json" \
        --json 2>/dev/null)
    # "Missing error handling" appears in both gpt and tertiary skeptic but should be deduped
    blocker_count=$(echo "$result" | jq '.consensus_summary.blocker_count')
    # At least 2 blockers: "Missing error handling" (750) and "Race condition risk" (800)
    # "No input validation" (600) is below 700 threshold
    [ "$blocker_count" -eq 2 ]
}

# =============================================================================
# Degraded Mode — Missing Tertiary Scores
# =============================================================================

@test "3-model degraded: works with empty tertiary score files" {
    run "$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --tertiary-scores-opus "$FIXTURES/empty-scores.json" \
        --tertiary-scores-gpt "$FIXTURES/empty-scores.json" \
        --gpt-scores-tertiary "$FIXTURES/empty-scores.json" \
        --opus-scores-tertiary "$FIXTURES/empty-scores.json" \
        --json
    [ "$status" -eq 0 ]
}

@test "3-model degraded: partial tertiary (only gpt-scores-tertiary)" {
    run "$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --gpt-scores-tertiary "$FIXTURES/gpt-scores-tertiary.json" \
        --json
    [ "$status" -eq 0 ]
}

@test "3-model degraded: nonexistent tertiary files gracefully ignored" {
    run "$SCORING_ENGINE" \
        --gpt-scores "$FIXTURES/gpt-scores-2model.json" \
        --opus-scores "$FIXTURES/opus-scores-2model.json" \
        --tertiary-scores-opus "/nonexistent/file.json" \
        --gpt-scores-tertiary "/nonexistent/file.json" \
        --json
    [ "$status" -eq 0 ]
}

# =============================================================================
# Help Text
# =============================================================================

@test "help text includes tertiary scoring options" {
    run "$SCORING_ENGINE" --help
    [[ "$output" == *"--tertiary-scores-opus"* ]]
    [[ "$output" == *"--tertiary-scores-gpt"* ]]
    [[ "$output" == *"--gpt-scores-tertiary"* ]]
    [[ "$output" == *"--opus-scores-tertiary"* ]]
}
