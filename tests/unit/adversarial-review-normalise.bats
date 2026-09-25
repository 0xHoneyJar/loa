#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-normalise.bats — cycle-126 Sprint 2 (PRD FR-2.2 /
# FR-2.4, SDD D-2.2 / D-2.4). The tolerant schema: a finding missing only
# `failure_mode` is normalised (first sentence of `description`, ≤ 200 chars,
# `failure_mode_derived: true`) and reaches the reviewer without a repair
# round-trip; a payload that still fails goes to the sidecar AND is summarised
# in `metadata.rejected_summary[]`; the repair loop's model is `tiny` with an
# Anthropic key present, `claude-headless` without.
# Source-based harness (the pattern of adversarial-review-schema-enforced.bats).
# =============================================================================

setup() {
    export LOA_MODELINV_LOG_PATH="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/cost-ledger.jsonl"
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    FIXTURES="$PROJECT_ROOT/tests/fixtures/dissent-rejected"
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL_REVIEW")"
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT
    CONF_ENABLED="true"; CONF_MODEL="gpt-5.5-pro"; CONF_TIMEOUT=60; CONF_BUDGET_CENTS=150
    CONF_ESCALATION_ENABLED="true"; CONF_SECONDARY_BUDGET=12000; CONF_MAX_FILE_LINES=500
    CONF_MAX_FILE_BYTES=51200; CONF_SECRET_SCANNING="true"; CONF_SECRET_ALLOWLIST=()
    LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=""
    SPRINT="sprint-norm-$$"
    REPAIR_CANARY="$TEST_DIR/repair-called-$$"
    # the normaliser must make the repair unnecessary: a stub that records the call and fails
    _repair_finding_via_model() { : > "$REPAIR_CANARY"; return 1; }
    unset ANTHROPIC_API_KEY OPENAI_API_KEY LOA_ADVERSARIAL_REPAIR_MODEL
}
teardown() {
    local d
    for d in "$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}" "$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}"-*; do
        if [[ -d "$d" ]]; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi
    done
}
_env() {  # <content json string> → adapter envelope (unenforced)
    jq -n --arg c "$1" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}'
}
_fixture_content() {  # all three fixtures as one findings document
    jq -c -s '{findings: [.[] | .payload]}' "$FIXTURES"/0*.json
}

@test "NRM-1 the three real rejected payloads become findings with failure_mode_derived: true, no sidecar row, no repair call, empty rejected_summary" {
    result=$(process_findings "$(_env "$(_fixture_content)")" "audit" "gpt-5.5-pro" "$SPRINT" "0" "")
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq '[.findings[] | select(.failure_mode_derived == true)] | length' <<<"$result")" = "3" ]
    [ "$(jq -r '.findings[0].failure_mode' <<<"$result")" = "The autonomous skill explicitly continues execution when the guardrails orchestrator is missing, exits non-zero, or returns unparseable output." ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.rejected_summary | length' <<<"$result")" = "0" ]
    [ ! -e "$REPAIR_CANARY" ]
    sidecar="$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}/adversarial-rejected-audit.jsonl"
    [ ! -s "$sidecar" ]
}

@test "NRM-2 a derived failure_mode is the first sentence, capped at 200 characters, and never raises the severity" {
    long=$(python3 -c 'print("A" * 350 + ". Second sentence.")')
    doc=$(jq -nc --arg d "$long" '{findings: [{"severity":"LOW","category":"other","description":$d}]}')
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    fm=$(jq -r '.findings[0].failure_mode' <<<"$result")
    [ "${#fm}" -le 200 ]
    [ "$(jq -r '.findings[0].severity' <<<"$result")" = "LOW" ]
    [ "$(jq -r '.findings[0].failure_mode_derived' <<<"$result")" = "true" ]
}

@test "NRM-3 a finding that carries its own failure_mode is untouched (no failure_mode_derived key)" {
    doc='{"findings":[{"id":"DISS-001","severity":"HIGH","category":"config","description":"d. e.","failure_mode":"stated"}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.findings[0].failure_mode' <<<"$result")" = "stated" ]
    [ "$(jq 'has("failure_mode_derived")' <<<"$(jq '.findings[0]' <<<"$result")")" = "false" ]
}

@test "NRM-4 a payload without a severity still goes to the sidecar AND appears in rejected_summary with its reason and anchor" {
    doc='{"findings":[{"title":"No severity here","category":"config","location":"x.sh:12","description":"Something fails when the file is missing. More."}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.rejected_summary | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.rejected_summary[0].reason' <<<"$result")" = "missing-severity" ]
    [ "$(jq -r '.metadata.rejected_summary[0].title' <<<"$result")" = "No severity here" ]
    [ "$(jq -r '.metadata.rejected_summary[0].anchor' <<<"$result")" = "x.sh:12" ]
    [ "$(jq -r '.metadata.rejected_summary[0].severity' <<<"$result")" = "null" ]
    [[ "$(jq -r '.metadata.rejected_summary[0].description_head' <<<"$result")" == "Something fails when the file is missing."* ]]
    sidecar="$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}/adversarial-rejected-audit.jsonl"
    [ "$(grep -c '' "$sidecar")" = "1" ]   # not wc -l: BSD wc pads its count
    [ "$(jq -r '.reject_reason' "$sidecar")" = "missing-severity" ]
}

@test "NRM-5 the schema-enforced branch never derives (an enforced payload missing failure_mode is rejected, not repaired)" {
    doc='{"findings":[{"id":"DISS-001","severity":"HIGH","category":"config","description":"d."}]}'
    env=$(jq -n --arg c "$doc" '{content: $c, tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: true}')
    result=$(process_findings "$env" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.rejected_summary[0].reason' <<<"$result")" = "missing-or-empty-failure_mode" ]
    [ ! -e "$REPAIR_CANARY" ]
}

@test "NRM-6 the repair loop's model is tiny with an Anthropic key present and claude-headless without (presence only, value never read)" {
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    [ "$(_repair_model "gpt-5.5-pro")" = "claude-headless" ]
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
    [ "$(_repair_model "gpt-5.5-pro")" = "tiny" ]
    unset ANTHROPIC_API_KEY
    printf 'ANTHROPIC_API_KEY="from-dotenv"\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    [ "$(_repair_model "gpt-5.5-pro")" = "tiny" ]
    export LOA_ADVERSARIAL_REPAIR_MODEL="codex-headless"
    [ "$(_repair_model "gpt-5.5-pro")" = "codex-headless" ]
}

@test "NRM-7 with the normaliser bypassed, the repair loop still recovers the fixtures through a stubbed model and records repaired_count" {
    # bypass the failure_mode derivation (keep the positional id) so the repair path is exercised
    _derive_failure_mode() { local idx="${1:-0}"; jq --arg idx "$idx" '.id //= ("DISS-" + (($idx | tonumber) + 1 | tostring))'; }
    _repair_finding_via_model() {  # <finding> <type> <clause> <model> [timeout] → fixed finding (stubbed model)
        printf '%s' "$1" | jq -c '. + {failure_mode: "stubbed repair"}'
    }
    result=$(process_findings "$(_env "$(_fixture_content)")" "audit" "gpt-5.5-pro" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq '.metadata.repaired_count' <<<"$result")" = "3" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ]
}

@test "NRM-8 credential presence never materialises the value: an xtrace'd check echoes no secret (review C-008)" {
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-x"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    printf 'ANTHROPIC_API_KEY="dotenv-secret-value-xyz-987"\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    run bash -xc "$(declare -f _adv_cred_present); PROJECT_ROOT='$PROJECT_ROOT'; LOA_ADVERSARIAL_ENV_DIR='$LOA_ADVERSARIAL_ENV_DIR'; BATS_TEST_FILENAME=x; _adv_cred_present anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" != *"dotenv-secret-value-xyz-987"* ]]
}
