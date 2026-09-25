#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-companion.bats — cycle-126 Sprint 2 (PRD FR-2.1,
# SDD D-2.1). The companion voice: a dissent plans TWO chains from different
# provider families, walks them, aggregates both envelopes (voices_planned 2),
# records the companion's completion-based status and failure class, and can
# be switched off per block (`companion_voice: false`).
#
# Whole-run harness: main() is sourced and run with `invoke_dissenter` replaced
# by a stub keyed on the model (canned adapter envelopes + a valid single-voice
# verdict_quality sidecar), a temp .loa.config.yaml, and no credentials present
# (a keyless host: the Anthropic companion chain is `claude-headless` only).
# =============================================================================

setup() {
    export LOA_MODELINV_LOG_PATH="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/cost-ledger.jsonl"
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    T="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL_REVIEW")"
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT
    SPRINT="sprint-comp-$$"
    OUT_DIR="$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT"
    # keyless host: no env keys, an empty dotenv dir (bats-gated seam)
    unset ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY GEMINI_API_KEY
    export LOA_ADVERSARIAL_ENV_DIR="$T/env"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    export LOA_ADVERSARIAL_CLI_PROBE=both   # both CLI hops "installed" unless a case says otherwise (C-007 seam)
    unset LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS
    # temp config: review enabled, primary gpt-5.5-pro with the OpenAI chain
    CONFIG_FILE="$T/loa.config.yaml"
    cat > "$CONFIG_FILE" <<'YAML'
flatline_protocol:
  code_review:
    enabled: true
    model: gpt-5.5-pro
    budget_cents: 200
    timeout_seconds: 30
    fallback_chain:
      - gpt-5.5
      - codex-headless
  security_audit:
    enabled: true
    model: gpt-5.5-pro
    budget_cents: 200
    timeout_seconds: 30
    fallback_chain:
      - codex-headless
YAML
    printf 'diff --git a/x.sh b/x.sh\n--- a/x.sh\n+++ b/x.sh\n@@ -1 +1 @@\n-a\n+b\n' > "$T/diff.patch"
    CALLS="$T/calls.log"; : > "$CALLS"
    # behaviour table: model → outcome (ok | walked:<hop> | auth | quota | timeout | malformed | unavailable).
    # `walked:<hop>` models cheval's INNER fallback chain (one invocation, one sidecar whose
    # succeeded id is the hop it landed on, the HTTP voice recorded as dropped) — the shape a
    # keyless host produces (sprint-247: final_model gpt-5.5-pro, voices_succeeded_ids [codex-headless]).
    declare -gA BEHAVIOUR=()
    _vq() {  # <voice> <ok|fail|walked> <reason|hop> <exit> → single-voice verdict_quality envelope JSON
        if [[ "$2" == "ok" ]]; then
            jq -nc --arg v "$1" '{status:"APPROVED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:1,voices_succeeded_ids:[$v],voices_dropped:[],chain_health:"ok",confidence_floor:"low",rationale:"stub",single_voice_call:true}'
        elif [[ "$2" == "walked" ]]; then
            # one voice that walked internally: INV-6 (dropped == planned − succeeded) keeps voices_dropped
            # empty; the walk shows as chain_health degraded, the succeeded id is the hop it landed on
            jq -nc --arg v "$1" --arg hop "$3" '{status:"DEGRADED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:1,voices_succeeded_ids:[$hop],voices_dropped:[],chain_health:"degraded",confidence_floor:"low",rationale:("stub inner walk from " + $v),single_voice_call:true}'
        else
            jq -nc --arg v "$1" --arg r "$3" --argjson e "$4" '{status:"FAILED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:0,voices_succeeded_ids:[],voices_dropped:[{voice:$v,reason:$r,exit_code:$e,blocker_risk:"unknown"}],chain_health:"exhausted",confidence_floor:"low",rationale:"stub",single_voice_call:true}'
        fi
    }
    invoke_dissenter() {  # <sys> <user> <model> <timeout> <vq_sidecar> <type> [schema]
        local model="$3" sidecar="$5" sev="ADVISORY"
        [[ "${6:-review}" == "audit" ]] && sev="MEDIUM"   # each gate's own vocabulary — no reject/repair detour
        echo "$model" >> "$CALLS"
        local b="${BEHAVIOUR[$model]:-ok}"
        case "$b" in
            ok)
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                jq -nc --arg m "$model" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                return 0 ;;
            walked:*)
                local hop="${b#walked:}"
                echo "$hop" >> "$CALLS"
                [[ -n "$sidecar" ]] && _vq "$model" walked "$hop" > "$sidecar"
                jq -nc --arg m "$hop" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                return 0 ;;
            malformed)
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                jq -nc '{content: "not json at all", tokens_input: 1, tokens_output: 1, cost_usd: 0.001, latency_ms: 1, schema_enforced: false}'
                return 0 ;;
            reject)   # a payload the normaliser cannot save (no severity) → the companion's own sidecar
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                jq -nc '{content: "{\"findings\":[{\"title\":\"no severity\",\"category\":\"other\",\"description\":\"Something fails.\"}]}", tokens_input: 5, tokens_output: 5, cost_usd: 0.001, latency_ms: 1, schema_enforced: false}'
                return 0 ;;
            slow)     sleep 4; [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"; jq -nc '{content: "{\"findings\":[]}", tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: false}'; return 0 ;;
            errlog)   echo "boom: provider said no (token sk-ant-api03-SECRETSECRETSECRETSECRET1234)" >&2; return 1 ;;
            auth)        [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 4 > "$sidecar"; return 4 ;;
            quota)       [[ -n "$sidecar" ]] && _vq "$model" fail RateLimited 6 > "$sidecar"; return 6 ;;
            timeout)     [[ -n "$sidecar" ]] && _vq "$model" fail Other 3 > "$sidecar"; return 3 ;;
            unavailable) [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1 ;;
        esac
    }
    export PYTHONPATH="$PROJECT_ROOT/.claude/adapters"
}
teardown() {
    local d
    for d in "$OUT_DIR" "$OUT_DIR"-*; do
        if [[ -d "$d" ]]; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi
    done
}
# portable in-place literal substitution (first occurrence) — no GNU-only `sed -i`
_cfg_edit() { python3 -c 'import sys; p,a,b=sys.argv[1:4]; s=open(p).read(); assert a in s, a; open(p,"w").write(s.replace(a,b,1))' "$CONFIG_FILE" "$1" "$2"; }

_run_main() { main --type "${1:-review}" --sprint-id "$SPRINT" --diff-file "$T/diff.patch" --json 2> "$T/stderr.log"; }

@test "CMP-1 keyless host: the primary's inner chain lands on codex-headless, the Anthropic companion is claude-headless; voices_planned 2, both ids succeeded, companion status succeeded with its cost" {
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.final_model' <<<"$result")" = "gpt-5.5-pro" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | sort | join(",")' <<<"$result")" = "claude-headless,codex-headless" ]
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.family' <<<"$result")" = "anthropic" ]
    [ "$(jq '.metadata.companion_voice.cost_cents' <<<"$result")" != "null" ]
    # keyless: the HTTP Anthropic voice (opus) was never tried
    ! grep -qx "opus" "$CALLS"
    grep -qx "claude-headless" "$CALLS"
    # both voices' findings are present, the companion's re-numbered and tagged
    [ "$(jq '.findings | length' <<<"$result")" = "2" ]
    [ "$(jq -r '[.findings[].voice] | sort | join(",")' <<<"$result")" = "claude-headless,gpt-5.5-pro" ]
    [ "$(jq -r '[.findings[].id] | sort | join(",")' <<<"$result")" = "DISS-001,DISS-C-001" ]
    [ -f "$OUT_DIR/adversarial-review.json" ]
}

@test "CMP-2 the companion chain failing (auth / quota / timeout) names the class, records the dropped voice, and the review still completes" {
    for cls in auth quota timeout; do
        : > "$CALLS"
        BEHAVIOUR[claude-headless]=$cls
        result=$(_run_main review)
        [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
        [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
        [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "$cls" ]
        [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
        [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "gpt-5.5-pro" ]
        [ "$(jq '[.verdict_quality.voices_dropped[].voice] | index("claude-headless") != null' <<<"$result")" = "true" ]
        [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "FAILED" ]
        [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    done
}

@test "CMP-3 a malformed companion is failure_class malformed; the primary's verdict is untouched" {
    BEHAVIOUR[claude-headless]=malformed
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "malformed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
}

@test "CMP-4 an Anthropic-family primary gets the OpenAI companion (keyless → codex-headless only)" {
    _cfg_edit 'model: gpt-5.5-pro' 'model: opus'
    _cfg_edit $'      - gpt-5.5\n      - codex-headless\n' $'      - claude-headless\n'   # an Anthropic chain: C-005 keeps codex-headless free for the companion
    BEHAVIOUR[opus]=walked:claude-headless   # no key: cheval's inner chain lands on the CLI hop
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.family' <<<"$result")" = "openai" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "codex-headless" ]
    ! grep -qx "gpt-5.5-pro" "$CALLS"
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
}

@test "CMP-5 companion_voice: false on the block disables the second chain (voices_planned 1, planned false)" {
    _cfg_edit $'enabled: true\n' $'enabled: true\n    companion_voice: false\n'
    result=$(_run_main review)
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "false" ]
    ! grep -qx "claude-headless" "$CALLS"
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
}

@test "CMP-6 with a credential present the companion chain starts at the HTTP voice (opus) before the hop" {
    export ANTHROPIC_API_KEY="sk-ant-presence-only-never-printed"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "opus" ]
    grep -qx "opus" "$CALLS"
    [[ "$(cat "$T/stderr.log")" != *"sk-ant-presence-only-never-printed"* ]]
    [[ "$result" != *"sk-ant-presence-only-never-printed"* ]]
}

@test "CMP-7 the audit gate plans a companion too and keeps its degraded rules for a failed one" {
    BEHAVIOUR[claude-headless]=timeout
    result=$(_run_main audit)
    [ "$(jq -r '.metadata.type' <<<"$result")" = "audit" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    [ -f "$OUT_DIR/adversarial-audit.json" ]
    # the audit gate's own vocabulary: nothing rejected, nothing repaired, the primary's finding stands
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.findings[0].severity' <<<"$result")" = "MEDIUM" ]
}

# --- review round 1 (companion voice DISS-C-001 … C-011) --------------------------------------

@test "CMP-8 the envelope's spend is both voices (C-004); independence is recorded (C-005); no reject → no companion sidecar (C-010)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq '.metadata.cost_usd' <<<"$result")" = "0.0246" ]
    [ "$(jq '.metadata.tokens_input' <<<"$result")" = "200" ]
    [ "$(jq '.metadata.companion_voice.cost_cents' <<<"$result")" = "1.23" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.rejected_sidecar' <<<"$result")" = "null" ]
}

@test "CMP-9 a companion hop the primary chain already holds is dropped; nothing left → planned false, reason no_disjoint_route (C-005)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'
    result=$(_run_main review)
    [ "$(jq -c '.metadata.companion_voice' <<<"$result")" = '{"planned":false,"reason":"no_disjoint_route","family":"anthropic"}' ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    ! grep -qx "claude-headless" "$CALLS"
}

@test "CMP-10 a primary chain that exhausts does not bury the companion: reviewed + degraded, primary_voice failed, the companion's findings stand (C-006)" {
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.degraded' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.primary_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.findings[0].voice' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
}

@test "CMP-11 no credential and no CLI for the other family → planned false, reason no_route; the CLI alone is a route (C-007)" {
    export LOA_ADVERSARIAL_CLI_PROBE=none
    result=$(_run_main review)
    [ "$(jq -c '.metadata.companion_voice' <<<"$result")" = '{"planned":false,"reason":"no_route","family":"anthropic"}' ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    export LOA_ADVERSARIAL_CLI_PROBE=claude
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "claude-headless" ]
}

@test "CMP-12 a companion payload that still fails lands in the companion's own sidecar, named on the envelope, and in rejected_summary with its voice (C-010)" {
    BEHAVIOUR[claude-headless]=reject
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.rejected_sidecar' <<<"$result")" = "grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-companion.jsonl" ]
    [ "$(wc -l < "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "1" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.rejected_summary[0].voice' <<<"$result")" = "claude-headless" ]
    # the terminal reason after the repair round-trip (the stub's repair answer mutates a
    # non-violated field): the summary and the sidecar row name the same reason
    reason=$(jq -r '.metadata.rejected_summary[0].reason' <<<"$result")
    [ -n "$reason" ] && [ "$reason" != "null" ]
    [ "$(jq -r '.reject_reason' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "$reason" ]
    [ "$(jq -r '.model' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "claude-headless" ]
    [ ! -s "$OUT_DIR/adversarial-rejected-review.jsonl" ]
}

@test "CMP-13 an operator companion_chain on the block is used as given, before presence or defaults (C-011)" {
    export ANTHROPIC_API_KEY="sk-ant-presence-only-never-printed"
    python3 - "$CONFIG_FILE" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("  code_review:\n    enabled: true\n", "  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: [claude-headless]\n      openai: [codex-headless]\n", 1); open(p,"w").write(s)
PY
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "claude-headless" ]
    ! grep -qx "opus" "$CALLS"
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
}

@test "CMP-14 the wait cap reaps a hung companion: failure_class timeout, the review completes, no orphan (C-001)" {
    BEHAVIOUR[claude-headless]=slow
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=1
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    ! pgrep -f "sleep 4" >/dev/null
}

@test "CMP-15 a fold that fails keeps the primary envelope (companion_voice.status fold_failed) instead of blanking it (C-002)" {
    _fold_companion() { echo "not json at all"; }
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "fold_failed" ]
}

@test "CMP-16 a failed companion carries its last diagnostic line, redacted (C-003)" {
    BEHAVIOUR[claude-headless]=errlog
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "model_unavailable" ]
    le=$(jq -r '.metadata.companion_voice.last_error' <<<"$result")
    [[ "$le" == *"provider said no"* ]]
    [[ "$le" != *"SECRETSECRETSECRETSECRET1234"* ]]
    [[ "$result" != *"SECRETSECRETSECRETSECRET1234"* ]]
}

@test "CMP-17 the failure class follows cheval's EXIT_CODES (4 MISSING_API_KEY auth, 6 BUDGET_EXCEEDED quota, 3/124 timeout, 5 INVALID_RESPONSE malformed, 1/other model_unavailable) and the wait-cap / malformed statuses" {
    [ "$(_companion_failure_class api_failure 4)" = "auth" ]
    [ "$(_companion_failure_class api_failure 6)" = "quota" ]
    [ "$(_companion_failure_class api_failure 3)" = "timeout" ]
    [ "$(_companion_failure_class api_failure 124)" = "timeout" ]
    [ "$(_companion_failure_class api_failure 5)" = "malformed" ]
    [ "$(_companion_failure_class api_failure 1)" = "model_unavailable" ]
    [ "$(_companion_failure_class api_failure 2)" = "model_unavailable" ]
    [ "$(_companion_failure_class malformed_response 0)" = "malformed" ]
    [ "$(_companion_failure_class wait_timeout 124)" = "timeout" ]
    # each class maps onto a verdict-quality drop reason
    [ "$(_companion_drop_reason quota)" = "RateLimited" ]
    [ "$(_companion_drop_reason auth)" = "ProviderUnavailable" ]
    [ "$(_companion_drop_reason model_unavailable)" = "ProviderUnavailable" ]
    [ "$(_companion_drop_reason malformed)" = "EmptyContent" ]
    [ "$(_companion_drop_reason timeout)" = "Other" ]
}

@test "CMP-18 independence follows the voice that answered: a primary whose inner chain lands on the companion's family is independent: false, with the succeeded id recorded and a warning (chunk c C-003)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:claude-headless   # cheval's inner chain crossed families
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "false" ]
    [ "$(jq -r '.metadata.companion_voice.primary_succeeded_model' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.final_model' <<<"$result")" = "gpt-5.5-pro" ]
    grep -q "NOT independent" "$T/stderr.log"
    # and the honest case: the primary answered from its own family
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.primary_succeeded_model' <<<"$result")" = "codex-headless" ]
}
