#!/usr/bin/env bats
# =============================================================================
# adversarial-review-repair-loop.bats — cycle-119 C14 (KF-004 repair loop)
# =============================================================================
# cycle-124 FR-7: no flag — the loop always runs on the UNENFORCED branch and never on a schema-enforced payload.
#
# Covers the 4 non-negotiable safety constraints from the adversarial
# design panel:
#   1. normalization pre-pass BEFORE validate_finding: case-fold
#      severity/category + whitespace trim ONLY, no synonym mapping.
#   2. on residual validation failure: ONE bounded same-model repair
#      round-trip sending only the offending finding JSON + the violated
#      clause.
#   3. the repaired finding re-enters the FULL pipeline (validate_finding
#      + validate_anchor), never just the failed clause.
#   4. byte-diff immutability guard: every field except the violated
#      one(s) must be byte-identical to the rejected original.
#
# Also covers: sidecar repair_attempted/repair_succeeded booleans,
# rejected+repaired counts in metadata (flag-gated), and flag-off
# byte-identical legacy behavior.
#
# Uses the same source-based testing pattern as adversarial-review.bats:
# eval-sources the whole script (main() disabled) so process_findings and
# its helpers run for real, and mocks `_repair_finding_via_model` (the
# ONE function that talks to a model) by simple bash function shadowing —
# bash resolves function calls at call time, so a redefinition after
# sourcing wins over the real implementation.
# =============================================================================

_scrub_cred_aliases() {  # unset every credential alias the probe recognises, from the script's own table; a missing or empty table fails setup rather than scrubbing nothing (twenty-fifth run, c2e DISS-C-002)
    local p v
    local -a names=() row
    declare -F _adv_cred_aliases >/dev/null || { echo "setup: _adv_cred_aliases is not loaded — the credential scrub would be a no-op" >&2; return 1; }
    for p in anthropic openai google; do
        read -ra row <<<"$(_adv_cred_aliases "$p")"
        [ "${#row[@]}" -gt 0 ] || { echo "setup: _adv_cred_aliases printed no alias for $p — the credential scrub would miss it" >&2; return 1; }
        names+=("${row[@]}")
    done
    for v in "${names[@]}"; do unset "$v"; done
}

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    TEST_DIR="${BATS_TEST_TMPDIR:?BATS_TEST_TMPDIR not set — must run under bats}"   # no mktemp fallback no teardown removes (thirty-second run, c2a DISS-C-002)

    local saved_root="$PROJECT_ROOT"

    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"

    # Source the script functions (but don't run main)
    # the trailer is an indented `main "$@"` in the BASH_SOURCE guard: `^main` matched nothing; `:` keeps the `then` non-empty (twentieth run, c2b C-001)
    # …and the substitution is CHECKED before the text is eval'd (twenty-first run, c2e C-001): a trailer change that makes the
    # sed a no-op again fails setup loudly instead of leaning on the BASH_SOURCE guard
    local _src; _src="$(sed 's/^\( *\)main "\$@"$/\1: main disabled for testing/' "$ADVERSARIAL_REVIEW")"
    grep -q ': main disabled for testing' <<<"$_src" || { echo "setup: the main trailer sed matched nothing" >&2; return 1; }
    ! grep -Eq '^[[:space:]]*main "\$@"' <<<"$_src" || { echo "setup: a main \"\$@\" call survived the sed" >&2; return 1; }
    eval "$_src"
    REPAIR_LOOP_MAIN_NEUTRALISED=1

    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT

    # Defaults load_adversarial_config would set.
    CONF_ENABLED="true"
    CONF_MODEL="gpt-5.3-codex"
    CONF_TIMEOUT=60
    CONF_BUDGET_CENTS=150
    CONF_ESCALATION_ENABLED="true"
    CONF_SECONDARY_BUDGET=12000
    CONF_MAX_FILE_LINES=500
    CONF_MAX_FILE_BYTES=51200
    CONF_SECRET_SCANNING="true"
    CONF_SECRET_ALLOWLIST=()
    LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=""

    # hermetic like the normalise and companion suites (twenty-first run, c2e C-002): no credential alias, an empty dotenv
    # seam, no CLI binary "installed" and a private lock directory — the repair chain is the answering voice alone on any
    # host, so no case charges or queues behind a real hop (the KF-037 contention class)
    _scrub_cred_aliases || return 1
    unset LOA_ADVERSARIAL_REPAIR_MODEL LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS _ADV_REPAIR_DEAD_HOPS LOA_ADVERSARIAL_RUN_TAG _ADV_SIDECAR_TAG
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-default"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    export LOA_ADVERSARIAL_CLI_PROBE=none
    export XDG_RUNTIME_DIR="$TEST_DIR"
}

teardown() {
    if [[ -n "${_REPAIR_TEST_SPRINT:-}" ]]; then
        rm -rf "$PROJECT_ROOT/grimoires/loa/a2a/${_REPAIR_TEST_SPRINT}" 2>/dev/null || true
    fi
}

# Builds a raw model-adapter envelope wrapping a {findings:[...]} content
# payload, matching process_findings' expected shape.
_raw_envelope() {
    local content_json="$1"
    jq -n --arg c "$content_json" \
        '{content: $c, tokens_input: 100, tokens_output: 50, cost_usd: 0.01, latency_ms: 500}'
}

_sidecar_path() {
    local sprint_id="$1" type="$2"
    echo "$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}/adversarial-rejected-${type}.jsonl"
}

# =============================================================================
# Constraint 1 — normalization pre-pass (case-fold + trim ONLY)
# =============================================================================

@test "C14: normalization allows a whitespace/case-mismatched finding to validate directly (no repair needed)" {
    _REPAIR_TEST_SPRINT="sprint-c14-norm-$$"
    # anchor + matching diff_files so validate_anchor doesn't demote the
    # BLOCKING severity we're asserting on below — that's an orthogonal,
    # pre-existing anchor-validation concern, not what this test covers.
    local content='{"findings":[{"id":"DISS-001","severity":"  blocking ","category":" Injection ","anchor":"src/foo.ts:x","anchor_type":"function","scope":"diff","description":"d","failure_mode":"fm"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "src/foo.ts")
    local count repaired
    count=$(echo "$result" | jq '.findings | length')
    repaired=$(echo "$result" | jq -r '.metadata.repaired_count')
    [[ "$count" == "1" ]]
    # Normalization alone fixed it — no repair round-trip was needed.
    [[ "$repaired" == "0" ]]
    local sev cat
    sev=$(echo "$result" | jq -r '.findings[0].severity')
    cat=$(echo "$result" | jq -r '.findings[0].category')
    [[ "$sev" == "BLOCKING" ]]
    [[ "$cat" == "injection" ]]
}

@test "C14: normalization does NOT synonym-map (a made-up severity is still rejected)" {
    # Force repair to be unavailable so we isolate the normalization step.
    _repair_finding_via_model() { return 1; }
    _REPAIR_TEST_SPRINT="sprint-c14-nosyn-$$"
    local content='{"findings":[{"id":"DISS-001","severity":"warning","category":"injection","description":"d","failure_mode":"fm"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")
    local count
    count=$(echo "$result" | jq '.findings | length')
    [[ "$count" == "0" ]]
}

@test "_normalize_finding_for_validation: leaves absent keys absent (no null keys introduced)" {
    local out
    out=$(_normalize_finding_for_validation '{"id":"x"}')
    [[ "$(echo "$out" | jq 'has("severity")')" == "false" ]]
    [[ "$(echo "$out" | jq 'has("category")')" == "false" ]]
}

# =============================================================================
# Constraint 4 — byte-diff immutability guard (pure function)
# =============================================================================

@test "_repair_diff_ok: accepts a repair that only touches the allowed field" {
    local orig='{"id":"x","severity":"blocking","category":"injection","description":"d","failure_mode":"fm"}'
    local rep='{"id":"x","severity":"BLOCKING","category":"injection","description":"d","failure_mode":"fm"}'
    run _repair_diff_ok "$orig" "$rep" "severity"
    [[ "$status" -eq 0 ]]
}

@test "_repair_diff_ok: rejects a repair that also mutates a non-violated field" {
    local orig='{"id":"x","severity":"blocking","category":"injection","description":"d","failure_mode":"fm"}'
    local rep='{"id":"x","severity":"BLOCKING","category":"injection","description":"CHANGED","failure_mode":"fm"}'
    run _repair_diff_ok "$orig" "$rep" "severity"
    [[ "$status" -ne 0 ]]
}

@test "_repair_diff_ok: rejects a repair that adds a new field" {
    local orig='{"id":"x","severity":"blocking","description":"d","failure_mode":"fm"}'
    local rep='{"id":"x","severity":"BLOCKING","description":"d","failure_mode":"fm","extra":"nope"}'
    run _repair_diff_ok "$orig" "$rep" "severity"
    [[ "$status" -ne 0 ]]
}

@test "_repair_violated_field: maps known reject reasons to their field" {
    [[ "$(_repair_violated_field "missing-severity")" == "severity" ]]
    [[ "$(_repair_violated_field "severity-not-in-enum (got: warning)")" == "severity" ]]
    [[ "$(_repair_violated_field "missing-category")" == "category" ]]
    [[ "$(_repair_violated_field "category-not-in-enum (got: bogus)")" == "category" ]]
    [[ "$(_repair_violated_field "missing-or-empty-description")" == "description" ]]
    [[ "$(_repair_violated_field "missing-or-empty-failure_mode")" == "failure_mode" ]]
    [[ "$(_repair_violated_field "missing-or-non-string-id")" == "id" ]]
    [[ "$(_repair_violated_field "something-unmapped")" == "" ]]
}

# =============================================================================
# Constraints 2+3 — repair succeeds, re-enters full pipeline
# =============================================================================

@test "C14: repair succeeds — mock model fixes only the violated field, finding is accepted" {
    # cycle-126 Sprint 2 (FR-2.2): the tolerant normaliser derives an empty failure_mode before validation;
    # the bats-gated seam skips only that step (production id derivation stays) so the repair round-trip runs
    export LOA_ADVERSARIAL_NO_FM_DERIVATION=1
    _REPAIR_TEST_SPRINT="sprint-c14-repair-ok-$$"

    # Mock: given the offending finding + violated clause, return the
    # same finding with ONLY failure_mode filled in.
    _repair_finding_via_model() {
        local finding_json="$1"
        echo "$finding_json" | jq '.failure_mode = "npe on line 42"'
    }

    local content='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"null-safety","anchor":"src/auth.ts:validateToken","description":"d","failure_mode":""}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "src/auth.ts")

    local count repaired rejected
    count=$(echo "$result" | jq '.findings | length')
    repaired=$(echo "$result" | jq -r '.metadata.repaired_count')
    rejected=$(echo "$result" | jq -r '.metadata.rejected_count')
    [[ "$count" == "1" ]]
    [[ "$repaired" == "1" ]]
    [[ "$rejected" == "0" ]]

    # Constraint 3: repaired finding passed through validate_anchor too
    # (anchor is in-diff so it should validate cleanly, not be demoted).
    local anchor_status
    anchor_status=$(echo "$result" | jq -r '.findings[0].anchor_status')
    [[ "$anchor_status" == "valid" ]]

    # No sidecar entry for a successfully-repaired finding.
    local sidecar
    sidecar=$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")
    if [[ -f "$sidecar" ]]; then
        [[ ! -s "$sidecar" ]]
    fi
}

@test "C14: repair mutates a non-violated field — rejected with repair-mutated-nonviolated-field" {
    # cycle-126 Sprint 2 (FR-2.2): the tolerant normaliser derives an empty failure_mode before validation;
    # the bats-gated seam skips only that step (production id derivation stays) so the repair round-trip runs
    export LOA_ADVERSARIAL_NO_FM_DERIVATION=1
    _REPAIR_TEST_SPRINT="sprint-c14-repair-mutate-$$"

    # Mock: "fixes" failure_mode but ALSO rewrites description — violates
    # the byte-diff immutability guard.
    _repair_finding_via_model() {
        local finding_json="$1"
        echo "$finding_json" | jq '.failure_mode = "npe" | .description = "totally different description"'
    }

    local content='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"null-safety","description":"original","failure_mode":""}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")

    local count repaired rejected
    count=$(echo "$result" | jq '.findings | length')
    repaired=$(echo "$result" | jq -r '.metadata.repaired_count')
    rejected=$(echo "$result" | jq -r '.metadata.rejected_count')
    [[ "$count" == "0" ]]
    [[ "$repaired" == "0" ]]
    [[ "$rejected" == "1" ]]

    local sidecar
    sidecar=$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")
    [[ -f "$sidecar" ]]
    local reason attempted succeeded
    reason=$(jq -r '.reject_reason' "$sidecar")
    attempted=$(jq -r '.repair_attempted' "$sidecar")
    succeeded=$(jq -r '.repair_succeeded' "$sidecar")
    [[ "$reason" == "repair-mutated-nonviolated-field" ]]
    [[ "$attempted" == "true" ]]
    [[ "$succeeded" == "false" ]]
}

@test "C14: repair unavailable (model call fails) — rejected, original reject_reason preserved, sidecar unchanged semantics" {
    # cycle-126 Sprint 2 (FR-2.2): the tolerant normaliser derives an empty failure_mode before validation;
    # the bats-gated seam skips only that step (production id derivation stays) so the repair round-trip runs
    export LOA_ADVERSARIAL_NO_FM_DERIVATION=1
    _REPAIR_TEST_SPRINT="sprint-c14-repair-fail-$$"

    # Mock: repair round-trip fails outright (e.g. timeout / API error twice).
    _repair_finding_via_model() { return 1; }

    local content='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"injection","description":"d"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")

    local count rejected
    count=$(echo "$result" | jq '.findings | length')
    rejected=$(echo "$result" | jq -r '.metadata.rejected_count')
    [[ "$count" == "0" ]]
    [[ "$rejected" == "1" ]]

    local sidecar
    sidecar=$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")
    [[ -f "$sidecar" ]]
    local reason attempted succeeded
    reason=$(jq -r '.reject_reason' "$sidecar")
    attempted=$(jq -r '.repair_attempted' "$sidecar")
    succeeded=$(jq -r '.repair_succeeded' "$sidecar")
    # Original reason (missing-or-empty-failure_mode), NOT overwritten.
    [[ "$reason" == "missing-or-empty-failure_mode" ]]
    [[ "$attempted" == "true" ]]
    [[ "$succeeded" == "false" ]]
}

@test "C14: repaired finding that is STILL invalid after repair — rejected with the repaired candidate's reason" {
    _REPAIR_TEST_SPRINT="sprint-c14-repair-stillbad-$$"

    # Mock: "fixes" the field it was told about but leaves it invalid.
    _repair_finding_via_model() {
        local finding_json="$1"
        echo "$finding_json" | jq '.severity = "SUPER_CRITICAL"'
    }

    local content='{"findings":[{"id":"DISS-001","severity":"warning","category":"injection","description":"d","failure_mode":"fm"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")

    local count rejected
    count=$(echo "$result" | jq '.findings | length')
    rejected=$(echo "$result" | jq -r '.metadata.rejected_count')
    [[ "$count" == "0" ]]
    [[ "$rejected" == "1" ]]

    local sidecar reason
    sidecar=$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")
    reason=$(jq -r '.reject_reason' "$sidecar")
    [[ "$reason" == severity-not-in-enum* ]]
}

@test "C14: production derivation — a missing severity is repaired alone; the derived failure_mode and id and their markers survive" {
    # twentieth run, c2e C-003: the repair round-trip on the PRODUCTION normaliser (no seam) — the model sees the
    # derived candidate, may touch only severity, and its reply drops the markers as a real model's would
    unset LOA_ADVERSARIAL_NO_FM_DERIVATION
    _REPAIR_TEST_SPRINT="sprint-c14-repair-derived-$$"
    _REPAIR_SEEN="$BATS_TEST_TMPDIR/repair-seen.json"
    _repair_finding_via_model() {
        local finding_json="$1"
        printf '%s' "$finding_json" > "$_REPAIR_SEEN"
        echo "$finding_json" | jq 'del(.id_derived, .failure_mode_derived) | .severity = "BLOCKING"'
    }

    local content='{"findings":[{"category":"null-safety","anchor":"src/auth.ts:validateToken","description":"The token is never checked before use. It is then dereferenced."}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "src/auth.ts")

    # the model was asked about the derived candidate, whose only defect is the severity
    [[ "$(jq -r '.failure_mode' "$_REPAIR_SEEN")" == "The token is never checked before use." ]]
    [[ "$(jq -r '.id' "$_REPAIR_SEEN")" == "DISS-001" ]]
    [[ "$(jq -r 'has("severity")' "$_REPAIR_SEEN")" == "false" ]]

    [[ "$(echo "$result" | jq '.findings | length')" == "1" ]]
    [[ "$(echo "$result" | jq -r '.metadata.repaired_count')" == "1" ]]
    [[ "$(echo "$result" | jq -r '.metadata.rejected_count')" == "0" ]]
    local f
    f=$(echo "$result" | jq -c '.findings[0]')
    [[ "$(jq -r '.severity' <<<"$f")" == "BLOCKING" ]]
    [[ "$(jq -r '.category' <<<"$f")" == "null-safety" ]]
    [[ "$(jq -r '.description' <<<"$f")" == "The token is never checked before use. It is then dereferenced." ]]
    [[ "$(jq -r '.failure_mode' <<<"$f")" == "The token is never checked before use." ]]
    [[ "$(jq -r '.id' <<<"$f")" == "DISS-001" ]]
    [[ "$(jq -r '.failure_mode_derived' <<<"$f")" == "true" ]]
    [[ "$(jq -r '.id_derived' <<<"$f")" == "true" ]]
    [[ "$(jq -r '.anchor_status' <<<"$f")" == "valid" ]]
}

@test "C14: production derivation — a repair that rewrites the DERIVED failure_mode keeps the finding with the derived value; the model's is discarded (twenty-seventh run, c2e DISS-C-003)" {
    # the derived failure_mode is the normaliser's text, not the dissenter's — a model that rewrites it alongside the
    # violated field mutated nothing the dissenter wrote; the finding is kept, the derived value (and its marker) restored
    unset LOA_ADVERSARIAL_NO_FM_DERIVATION
    _REPAIR_TEST_SPRINT="sprint-c14-repair-derived-mutate-$$"
    _repair_finding_via_model() {
        echo "$1" | jq '.severity = "BLOCKING" | .failure_mode = "something the model made up" | del(.failure_mode_derived)'
    }
    local content='{"findings":[{"category":"null-safety","description":"The token is never checked before use."}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")
    [[ "$(echo "$result" | jq '.findings | length')" == "1" ]]
    [[ "$(echo "$result" | jq -r '.metadata.rejected_count')" == "0" ]]
    [[ "$(echo "$result" | jq -r '.metadata.repaired_count')" == "1" ]]
    [[ "$(echo "$result" | jq -r '.findings[0].failure_mode')" == "The token is never checked before use." ]]
    [[ "$(echo "$result" | jq -r '.findings[0].failure_mode_derived')" == "true" ]]
    [[ "$(echo "$result" | jq -r '.findings[0].description')" == "The token is never checked before use." ]]
}

@test "C14: a repair that rewrites a dissenter-STATED failure_mode is still a non-violated-field mutation — only derived fields are free (twenty-seventh run, c2e DISS-C-003)" {
    unset LOA_ADVERSARIAL_NO_FM_DERIVATION
    _REPAIR_TEST_SPRINT="sprint-c14-repair-stated-mutate-$$"
    _repair_finding_via_model() {
        echo "$1" | jq '.severity = "BLOCKING" | .failure_mode = "something the model made up"'
    }
    local content='{"findings":[{"category":"null-safety","description":"The token is never checked before use.","failure_mode":"a crash on the first request"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")
    [[ "$(echo "$result" | jq '.findings | length')" == "0" ]]
    [[ "$(echo "$result" | jq -r '.metadata.rejected_count')" == "1" ]]
    [[ "$(jq -r '.reject_reason' "$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")")" == "repair-mutated-nonviolated-field" ]]
}

@test "C14: a repair that rewrites the DERIVED id keeps the finding under the normaliser's id (twenty-seventh run, c2e DISS-C-003)" {
    unset LOA_ADVERSARIAL_NO_FM_DERIVATION
    _REPAIR_TEST_SPRINT="sprint-c14-repair-derived-id-$$"
    _repair_finding_via_model() {
        echo "$1" | jq '.severity = "BLOCKING" | .id = "MODEL-9"'
    }
    local content='{"findings":[{"category":"null-safety","description":"The token is never checked before use.","failure_mode":"a crash"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")
    [[ "$(echo "$result" | jq '.findings | length')" == "1" ]]
    [[ "$(echo "$result" | jq -r '.findings[0].id')" == "DISS-001" ]]
    [[ "$(echo "$result" | jq -r '.findings[0].failure_mode')" == "a crash" ]]
}

@test "C14: production derivation — a whitespace-only description derives nothing; the repaired description supplies the failure_mode" {
    unset LOA_ADVERSARIAL_NO_FM_DERIVATION
    _REPAIR_TEST_SPRINT="sprint-c14-repair-ws-desc-$$"
    _REPAIR_SEEN="$BATS_TEST_TMPDIR/repair-seen.json"
    _repair_finding_via_model() {
        printf '%s' "$1" > "$_REPAIR_SEEN"
        printf '%s\n' "$3" > "$_REPAIR_SEEN.reason"
        echo "$1" | jq 'del(.id_derived, .failure_mode_derived) | .description = "The lock is released twice on the error path. Callers crash."'
    }
    local content='{"findings":[{"id":"DISS-007","severity":"ADVISORY","category":"concurrency","description":" \t "}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")

    # nothing was derived from the blank description, so the model was told about the description, not the failure_mode
    [[ "$(cat "$_REPAIR_SEEN.reason")" == "missing-or-empty-description" ]]
    [[ "$(jq -r 'has("failure_mode")' "$_REPAIR_SEEN")" == "false" ]]

    [[ "$(echo "$result" | jq '.findings | length')" == "1" ]]
    [[ "$(echo "$result" | jq -r '.metadata.repaired_count')" == "1" ]]
    local f
    f=$(echo "$result" | jq -c '.findings[0]')
    [[ "$(jq -r '.id' <<<"$f")" == "DISS-007" ]]
    [[ "$(jq -r '.id_derived // "absent"' <<<"$f")" == "absent" ]]
    [[ "$(jq -r '.severity' <<<"$f")" == "ADVISORY" ]]
    [[ "$(jq -r '.failure_mode' <<<"$f")" == "The lock is released twice on the error path." ]]
    [[ "$(jq -r '.failure_mode_derived' <<<"$f")" == "true" ]]
}

# =============================================================================
# Enforced branch — normalization and repair never run (cycle-124 FR-7)
# =============================================================================

@test "FR-7: schema_enforced payload — normalization never runs, repair never attempted, sidecar records the parse path" {
    # If repair were somehow invoked, fail loudly.
    _repair_finding_via_model() { echo "SHOULD NOT BE CALLED" >&2; return 1; }
    _REPAIR_TEST_SPRINT="sprint-c14-enforced-$$"

    local content='{"findings":[{"id":"DISS-001","severity":"  blocking ","category":"injection","description":"d","failure_mode":"fm"}]}'
    local raw
    raw=$(jq -n --arg c "$content" '{content: $c, tokens_input: 100, tokens_output: 50, cost_usd: 0.01, latency_ms: 500, schema_enforced: true}')
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")

    # Not normalized -> still rejected (case-mismatched severity is a drift signal on the enforced branch).
    [[ "$(echo "$result" | jq '.findings | length')" == "0" ]]
    [[ "$(echo "$result" | jq -r '.metadata.parse_path')" == "schema_enforced" ]]
    [[ "$(echo "$result" | jq -r '.metadata.schema_enforced')" == "true" ]]
    [[ "$(echo "$result" | jq -r '.metadata.repaired_count')" == "0" ]]
    [[ "$(echo "$result" | jq -r '.metadata.rejected_count')" == "1" ]]

    local sidecar
    sidecar=$(_sidecar_path "$_REPAIR_TEST_SPRINT" "review")
    [[ -f "$sidecar" ]]
    [[ "$(jq -r '.repair_attempted' "$sidecar")" == "false" ]]
    [[ "$(jq -r '.schema_enforced' "$sidecar")" == "true" ]]
    [[ "$(jq -r '.parse_path' "$sidecar")" == "schema_enforced" ]]
}

@test "FR-7: unenforced payload (no flag anywhere) — normalization runs and a clean finding passes; repaired_count is reported" {
    _REPAIR_TEST_SPRINT="sprint-c14-unenforced-$$"
    local content='{"findings":[{"id":"DISS-001","severity":"BLOCKING","category":"injection","description":"d","failure_mode":"fm"}]}'
    local raw
    raw=$(_raw_envelope "$content")
    result=$(process_findings "$raw" "review" "gpt-5.3-codex" "$_REPAIR_TEST_SPRINT" "0" "")
    [[ "$(echo "$result" | jq '.findings | length')" == "1" ]]
    [[ "$(echo "$result" | jq -r '.metadata.parse_path')" == "normalized" ]]
    [[ "$(echo "$result" | jq -r '.metadata.schema_enforced')" == "false" ]]
    [[ "$(echo "$result" | jq -r '.metadata.repaired_count')" == "0" ]]
}

@test "_write_rejected_sidecar: legacy 7-arg call omits repair_attempted/repair_succeeded" {
    local sidecar="$TEST_DIR/sidecar-legacy.jsonl"
    : > "$sidecar"
    _write_rejected_sidecar "$sidecar" '{"id":"x"}' "missing-severity" "0" "sprint-x" "review" "gpt-5.3-codex"
    [[ "$(jq 'has("repair_attempted")' "$sidecar")" == "false" ]]
    [[ "$(jq 'has("repair_succeeded")' "$sidecar")" == "false" ]]
}

@test "_write_rejected_sidecar: 9-arg call adds repair_attempted/repair_succeeded booleans" {
    local sidecar="$TEST_DIR/sidecar-repair.jsonl"
    : > "$sidecar"
    _write_rejected_sidecar "$sidecar" '{"id":"x"}' "missing-severity" "0" "sprint-x" "review" "gpt-5.3-codex" "true" "false"
    [[ "$(jq -r '.repair_attempted' "$sidecar")" == "true" ]]
    [[ "$(jq -r '.repair_succeeded' "$sidecar")" == "false" ]]
}

# =============================================================================
# Degraded-verdict trajectory wiring (#1177-D)
# =============================================================================

@test "C14: write_output emits a repair-loop DEGRADED trajectory record when rejected_count>0 (always, cycle-124)" {
    local sprint_id="sprint-c14-traj-$$"
    _REPAIR_TEST_SPRINT="$sprint_id"
    local traj_dir="$TEST_DIR/trajectory-$sprint_id"
    local pushlog="$TEST_DIR/pushlog-$sprint_id.txt"

    local runner="$TEST_DIR/runner-$sprint_id.sh"
    local result_json
    result_json=$(jq -nc --arg sid "$sprint_id" '{
        findings: [],
        metadata: {type: "review", model: "gpt-5.3-codex", sprint_id: $sid,
                   timestamp: "2026-07-07T00:00:00Z", status: "reviewed",
                   degraded: false, rejected_count: 2, repaired_count: 1}
    }')
    cat > "$runner" <<EOF
#!/usr/bin/env bash
set -euo pipefail
log() { :; }
error() { printf '%s\n' "\$*" >&2; return 1; }
main() { :; }
source "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
push_notify() { echo "PUSH|\$1|\$2|\$3|\$4" >> "$pushlog"; return 0; }
export LOA_DEGRADED_VERDICT_DIR="$traj_dir"
write_output '$result_json' "$sprint_id" "review" "0"
EOF
    run bash "$runner"
    [[ "$status" -eq 0 ]]

    local traj
    traj="$traj_dir/degraded-verdict-"*.jsonl
    # bash glob expansion: [[ ]] does NOT expand unquoted globs, [ ] does
    # (via ordinary word-splitting) — use single-bracket here, matching
    # the existing pattern in adversarial-review-verdict-quality.bats.
    [ -f $traj ]
    local gate band
    gate=$(jq -r '.gate' $traj)
    band=$(jq -r '.verdict_band' $traj)
    [[ "$gate" == "adversarial-review:review:repair-loop" ]]
    [[ "$band" == "DEGRADED" ]]

    rm -rf "$PROJECT_ROOT/grimoires/loa/a2a/${sprint_id}" 2>/dev/null || true
}

@test "C16: invoke_dissenter passes --skill adversarial-<type> through to model-adapter.sh" {
    local fake_dir="$TEST_DIR/fake-adapter-review"
    mkdir -p "$fake_dir"
    cat > "$fake_dir/model-adapter.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/captured-args.txt"
echo '{"content":"{}","tokens_input":1,"tokens_output":1,"cost_usd":0,"latency_ms":1}'
EOF
    chmod +x "$fake_dir/model-adapter.sh"

    local sysfile="$fake_dir/sys.txt" userfile="$fake_dir/user.txt"
    echo "sys" > "$sysfile"
    echo "user" > "$userfile"

    SCRIPT_DIR="$fake_dir"
    invoke_dissenter "$sysfile" "$userfile" "gpt-5.3-codex" "60" "" "review" >/dev/null

    grep -qx -- "adversarial-review" "$fake_dir/captured-args.txt"
}

@test "C16: invoke_dissenter uses adversarial-audit for type=audit" {
    local fake_dir="$TEST_DIR/fake-adapter-audit"
    mkdir -p "$fake_dir"
    cat > "$fake_dir/model-adapter.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$(dirname "$0")/captured-args.txt"
echo '{"content":"{}","tokens_input":1,"tokens_output":1,"cost_usd":0,"latency_ms":1}'
EOF
    chmod +x "$fake_dir/model-adapter.sh"

    local sysfile="$fake_dir/sys.txt" userfile="$fake_dir/user.txt"
    echo "sys" > "$sysfile"
    echo "user" > "$userfile"

    SCRIPT_DIR="$fake_dir"
    invoke_dissenter "$sysfile" "$userfile" "gpt-5.3-codex" "60" "" "audit" >/dev/null

    grep -qx -- "adversarial-audit" "$fake_dir/captured-args.txt"
}

@test "setup is hermetic: the main trailer was neutralised, and the repair chain is the answering voice alone — no host key, dotenv or CLI binary decides the hop (twenty-first run, c2e C-001 / C-002)" {
    [[ "$(type -t main)" == "function" ]]
    [ "$REPAIR_LOOP_MAIN_NEUTRALISED" = "1" ]
    [ "$(_repair_model_chain "gpt-5.3-codex")" = "gpt-5.3-codex" ]
    [ "$XDG_RUNTIME_DIR" = "$TEST_DIR" ]
    # the RESOLVED lock directory, not just the input: a resolver cached at source time would leave the export inert
    # (twenty-second run, c2e DISS-C-001)
    [ "$(_adv_cli_lock_dir)" = "$TEST_DIR/loa-headless-locks-$(id -u)" ]
    # no family's credential survives the scrub, and the scrub's provider list is the table's own (twenty-seventh run, c2e DISS-C-001)
    local p
    for p in anthropic openai google; do ! _adv_cred_present "$p" || { echo "a $p credential survived the scrub"; return 1; }; done
    [ "$(declare -f _adv_cred_aliases | grep -oE '^ +[a-z]+\)' | tr -d ' )' | LC_ALL=C sort | tr '\n' ' ')" = "anthropic google openai " ]
}
