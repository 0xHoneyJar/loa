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
    # the sprint id and its directory come FIRST: teardown runs on any setup failure, and a delete
    # target derived from an unset id would be the a2a root (fourth run, chunk c C-001)
    SPRINT="sprint-comp-$$"
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    OUT_DIR="$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT"
    export LOA_MODELINV_LOG_PATH="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/cost-ledger.jsonl"
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    T="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL_REVIEW")"
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT
    # keyless host: no env keys, an empty dotenv dir (bats-gated seam)
    unset ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY GEMINI_API_KEY
    export LOA_ADVERSARIAL_ENV_DIR="$T/env"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    export LOA_ADVERSARIAL_CLI_PROBE=both   # both CLI hops "installed" unless a case says otherwise (C-007 seam)
    unset LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS
    # seventh run (chunk c1 C-002 / C-005): every test gets its own lock directory and none of the operator's
    # knobs — the suite runs in the same session that drives live dissents
    export XDG_RUNTIME_DIR="$T"
    unset LOA_ADVERSARIAL_KEEP_WORKDIR LOA_ADVERSARIAL_RUN_TAG LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE \
          LOA_ADVERSARIAL_REPAIR_MODEL LOA_ADVERSARIAL_REAP_GRACE_SECONDS LOA_MODEL_CONFIG LOA_ADVERSARIAL_CLI_HOP_TIMEOUT \
          LOA_ADVERSARIAL_NO_FM_DERIVATION
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
            stubborn) # a hop that ignores TERM (a CLI stuck under a usage limit): only KILL ends it
                bash -c 'trap "" TERM; exec -a "$0" sleep 300' "loa-cmp30-stubborn-$$"; return 0 ;;
            slow2)    sleep 2; [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"; jq -nc '{content: "{\"findings\":[]}", tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: false}'; return 0 ;;
            slow)     # a hung hop with a PID-scoped process name, so the orphan probe cannot match anything else on the host (c C-001)
                bash -c 'exec -a "$0" sleep 300' "loa-cmp14-hung-$$"   # only the reaper can end it (eighth run, c1 C-002)
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"; jq -nc '{content: "{\"findings\":[]}", tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: false}'; return 0 ;;
            errlog)   echo "boom: provider said no (token sk-ant-api03-SECRETSECRETSECRETSECRET1234)" >&2; return 1 ;;
            errquiet) # the shim's shape when cheval fails: banners only, the provider's line went to the MODELINV ledger
                echo "[model-adapter:shim] Model: $model → anthropic:$model, Phase: review" >&2
                echo "ERROR: model-invoke failed with exit code 1" >&2; return 1 ;;
            clitimeout)  # cheval's CLI-hop timeout as the live run reported it, followed by the shim's generic wrapper
                echo "[cheval] RETRIES_EXHAUSTED: Failed after 1 attempts: [cheval] PROVIDER_UNAVAILABLE: Provider 'anthropic' unavailable: claude -p timed out after 610s" >&2
                echo "ERROR: model-invoke failed with exit code 1" >&2; return 1 ;;
            auth)        [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 4 > "$sidecar"; return 4 ;;
            quota)       [[ -n "$sidecar" ]] && _vq "$model" fail RateLimited 6 > "$sidecar"; return 6 ;;
            timeout)     [[ -n "$sidecar" ]] && _vq "$model" fail Other 3 > "$sidecar"; return 3 ;;
            unavailable) [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1 ;;
            unavailable-companion-only)  # the COMPANION's call to this model fails; the primary's answers
                if [[ "$sidecar" == *vq-companion-* ]]; then [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1; fi
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                jq -nc --arg m "$model" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                return 0 ;;
            unavailable-primary-only)  # the PRIMARY's call to this model fails; the companion's (vq-companion sidecar) answers
                if [[ "$sidecar" == *vq-companion-* ]]; then
                    [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                    jq -nc --arg m "$model" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                    return 0
                fi
                [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1 ;;
        esac
    }
    export PYTHONPATH="$PROJECT_ROOT/.claude/adapters"
}
teardown() {
    local d
    # a PID-scoped stub the reaper under test failed to end never outlives the test (seventh run, c1 C-007)
    pkill -KILL -f "loa-cmp(14|30)-[a-z]+-$$" 2>/dev/null || true
    [[ -n "${SPRINT:-}" && -n "${OUT_DIR:-}" && "$OUT_DIR" == */grimoires/loa/a2a/sprint-comp-* ]] || return 0
    for d in "$OUT_DIR" "$OUT_DIR"-*; do
        [[ "$d" == */a2a/sprint-comp-* ]] || continue
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
    [ "$(grep -cx "opus" "$CALLS")" = "0" ]
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
    [ "$(grep -cx "gpt-5.5-pro" "$CALLS")" = "0" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    # with an OpenAI credential the default companion chain starts at gpt-5.5 — never gpt-5.5-pro (KF-002; third run C-007)
    export OPENAI_API_KEY="sk-presence-only-never-printed"
    : > "$CALLS"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "gpt-5.5,codex-headless" ]
    [ "$(grep -cx "gpt-5.5-pro" "$CALLS")" = "0" ]
    [[ "$result" != *"sk-presence-only-never-printed"* ]]
}

@test "CMP-5 companion_voice: false on the block disables the second chain (voices_planned 1, planned false)" {
    _cfg_edit $'enabled: true\n' $'enabled: true\n    companion_voice: false\n'
    result=$(_run_main review)
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "false" ]
    [ "$(grep -cx "claude-headless" "$CALLS")" = "0" ]
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

@test "CMP-9 a companion hop the primary chain also holds stays planned (shared_hops); the primary answering from its own family keeps the companion independent (C-005, live re-run)" {
    _cfg_edit $'      - codex-headless
  security_audit:' $'      - codex-headless
      - claude-headless
  security_audit:'
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.shared_hops | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "independent_voice" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq '.verdict_quality.voices_succeeded' <<<"$result")" = "2" ]
    grep -qx "claude-headless" "$CALLS"
    # no overlap at all: shared_hops is empty
    _cfg_edit $'      - codex-headless
      - claude-headless
  security_audit:' $'      - codex-headless
  security_audit:'
    result=$(_run_main review)
    [ "$(jq -c '.metadata.companion_voice.shared_hops' <<<"$result")" = "[]" ]
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
    # c C-002 (third run): the promotion is visible in verdict quality too — never a clean consensus
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "APPROVED" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq '[.verdict_quality.voices_dropped[].voice] | index("gpt-5.5-pro") != null' <<<"$result")" = "true" ]
    [ "$(jq '.verdict_quality.voices_succeeded' <<<"$result")" = "1" ]
    [ -n "$(jq -r '.metadata.primary_voice.error // empty' <<<"$result")" ]
    [ "$(jq -r '.metadata.status_note' <<<"$result")" != "null" ]
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
    [ "$(grep -c '' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "1" ]   # not wc -l: BSD wc pads
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.rejected_summary[0].voice' <<<"$result")" = "claude-headless" ]
    # the terminal reason after the repair round-trip (the stub's repair answer mutates a
    # non-violated field): the summary and the sidecar row name the same reason
    reason=$(jq -r '.metadata.rejected_summary[0].reason' <<<"$result")
    [ -n "$reason" ] && [ "$reason" != "null" ]
    [ "$(jq -r '.reject_reason' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "$reason" ]
    [ "$(jq -r '.model' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "claude-headless" ]
    [ ! -s "$OUT_DIR/adversarial-rejected-review.jsonl" ]
    # c C-005: the repair round-trip went through the stubbed dissenter (dissent + repair), never a live CLI
    [ "$(grep -cx claude-headless "$CALLS")" = "2" ]
}

@test "CMP-13 an operator companion_chain on the block is used as given, before presence or defaults (C-011)" {
    export ANTHROPIC_API_KEY="sk-ant-presence-only-never-printed"
    python3 - "$CONFIG_FILE" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("  code_review:\n    enabled: true\n", "  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: [claude-headless]\n      openai: [codex-headless]\n", 1); open(p,"w").write(s)
PY
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(grep -cx "opus" "$CALLS")" = "0" ]
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
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]   # the hop in flight, not a guess (sixth run C-001)
    command -v pgrep >/dev/null || skip "pgrep not installed: the orphan probe cannot run here"
    [ -z "$(pgrep -f "loa-cmp14-hung-$$")" ]   # the reaper ended a 300 s hop
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
    # the envelope carries only an allowlisted summary (nothing here qualifies → no last_error at all);
    # the redacted raw line is operator-facing on stderr (fourth run, chunk c C-004)
    [ "$(jq -r '.metadata.companion_voice.last_error // "none"' <<<"$result")" = "none" ]
    grep -q "Companion voice diagnostic (claude-headless): boom: provider said no" "$T/stderr.log"
    [ "$(grep -c "SECRETSECRETSECRETSECRET1234" "$T/stderr.log")" = "0" ]
    [[ "$result" != *"SECRETSECRETSECRETSECRET1234"* ]]
    # c C-004: the raw line lives only in the /tmp workdir, which the EXIT trap removed — never in the a2a directory
    [ -d "$OUT_DIR" ]   # a missing directory would make the recursive grep pass vacuously
    [ -z "$(grep -rl "SECRETSECRETSECRETSECRET1234" "$OUT_DIR")" ]
    [ -z "$(ls -d "${TMPDIR:-/tmp}"/adversarial-"$SPRINT"-* 2>/dev/null)" ]   # the script's workdir honours TMPDIR
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
    # a diagnostic decides when the exit code does not: rate limits are quota (fifth run)
    [ "$(_companion_failure_class api_failure 1 "[cheval] RETRIES_EXHAUSTED: Failed after 4 attempts: [cheval] RATE_LIMITED: Rate limited by anthropic")" = "quota" ]
    [ "$(_companion_failure_class api_failure 1 "claude -p timed out after 910s")" = "timeout" ]   # the live bound, not a literal 610 (d C-003)
}

@test "CMP-18 a primary whose inner chain lands on the companion's family: independent false, the companion's findings kept and tagged, no second voice in verdict quality (chunk c C-003)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:claude-headless   # cheval's inner chain crossed families
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "false" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "duplicate_voice" ]
    [ "$(jq -r '.metadata.companion_voice.primary_succeeded_model' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.final_model' <<<"$result")" = "gpt-5.5-pro" ]
    grep -q "NOT independent" "$T/stderr.log"
    # findings: both kept, tagged — voice is the outer hop, answered_by the model that actually answered (c C-003)
    [ "$(jq '.findings | length' <<<"$result")" = "2" ]
    [ "$(jq -r '[.findings[].voice] | sort | join(",")' <<<"$result")" = "claude-headless,gpt-5.5-pro" ]
    [ "$(jq -r '[.findings[].answered_by] | unique | join(",")' <<<"$result")" = "claude-headless" ]
    # verdict quality counts distinct voices: the duplicate contributes no envelope (the aggregator's
    # INV-5 forbids one id both succeeded and dropped) — one voice, nothing dropped, still aggregated
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    [ "$(jq '.verdict_quality.voices_succeeded' <<<"$result")" = "1" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq '.verdict_quality.voices_dropped | length' <<<"$result")" = "0" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    # and the honest case: the primary answered from its own family
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "independent_voice" ]
    [ "$(jq -r '.metadata.companion_voice.primary_succeeded_model' <<<"$result")" = "codex-headless" ]
    [ "$(jq '.verdict_quality.voices_succeeded' <<<"$result")" = "2" ]
}

@test "CMP-19 cheval's CLI-hop timeout (PROVIDER_UNAVAILABLE / exit 1, 'timed out') classes as timeout, and last_error carries the provider's line, not the shim wrapper (live re-run)" {
    BEHAVIOUR[claude-headless]=clitimeout
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    le=$(jq -r '.metadata.companion_voice.last_error' <<<"$result")
    [ "$le" = "RETRIES_EXHAUSTED PROVIDER_UNAVAILABLE timed out after 610s" ]   # the allowlisted summary, nothing else
    [ "$(jq -r '.verdict_quality.voices_dropped[0].reason' <<<"$result")" = "Other" ]
    # the classifier alone: the diagnostic decides only when the exit code does not
    [ "$(_companion_failure_class api_failure 1 "claude -p timed out after 610s")" = "timeout" ]
    [ "$(_companion_failure_class api_failure 1 "connection refused")" = "model_unavailable" ]
    [ "$(_companion_failure_class api_failure 4 "timed out")" = "auth" ]
}

@test "CMP-20 a FAILED companion whose id is one of the primary's succeeded voices feeds no dropped-voice envelope (INV-5): verdict quality still aggregates, counted_as duplicate_voice (third run C-001 BLOCKING)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:claude-headless     # the primary fell through to claude-headless (this host's last resort)
    BEHAVIOUR[claude-headless]=timeout                # …and the claude-headless companion timed out
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "duplicate_voice" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq '.verdict_quality.voices_dropped | length' <<<"$result")" = "0" ]
    grep -q "no dropped-voice envelope" "$T/stderr.log"
    # the ordinary failed companion (a different id) is still a dropped voice
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq -r '.verdict_quality.voices_dropped[0].voice' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "null" ]
}

@test "CMP-21 the companion's answered_by and independence follow ITS succeeded id, not its outer hop (third run C-002)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    BEHAVIOUR[claude-headless]=walked:codex-headless   # cheval's inner chain under the companion hop landed on the primary's family
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.answered_by' <<<"$result")" = "codex-headless" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "false" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "duplicate_voice" ]
    [ "$(jq -r '[.findings[] | select(.voice == "claude-headless") | .answered_by] | unique | join(",")' <<<"$result")" = "codex-headless" ]
    # and when the companion answers from its own family it is independent
    BEHAVIOUR[claude-headless]=ok
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.answered_by' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "true" ]
}

@test "CMP-22 the wait cap is sized per hop — a *-headless hop by the CLI adapter's bound (connect 10 s + max(600 s, the catalog's headless_timeout_seconds)), an HTTP hop by timeout_seconds — plus 30 s slack (third + fourth run)" {
    # claude-headless carries headless_timeout_seconds: 900 in the catalog → 910; codex-headless does not → 610
    [ "$(_adv_cli_hop_bound claude-headless)" = "910" ]
    [ "$(_adv_cli_hop_bound codex-headless)" = "610" ]
    [ "$(_companion_wait_cap 30 claude-headless)" = "940" ]
    [ "$(_companion_wait_cap 30 opus claude-headless)" = "970" ]
    [ "$(_companion_wait_cap 900 codex-headless)" = "930" ]
    [ "$(_companion_wait_cap 60 gpt-5.5)" = "90" ]
    [ "$(_companion_wait_cap 600 gpt-5.5 codex-headless)" = "1240" ]
    [ "$( _ADV_CLI_HOP_TIMEOUT=100; _companion_wait_cap 30 foo-headless )" = "130" ]   # a hop the catalog does not size
    [ "$( LOA_MODEL_CONFIG=/nonexistent.yaml _adv_cli_hop_bound claude-headless )" = "610" ]
    # the live line names the cap
    result=$(_run_main review)
    grep -q "wait cap 940s" "$T/stderr.log"
}

@test "CMP-23 each writer truncates its own rejected sidecar at run start — a second run into the same sprint directory does not accumulate rows (third run, chunk c C-001)" {
    BEHAVIOUR[claude-headless]=reject
    result=$(_run_main review)
    [ "$(grep -c '' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "1" ]
    result=$(_run_main review)
    [ "$(grep -c '' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "1" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    # the envelope names the sidecars this run produced; verdict-derive counts JSON rows, not bytes —
    # one triage bullet clears the contract, and a trailing blank line changes nothing (c C-007)
    [ "$(jq -c '.metadata.rejected_sidecars' <<<"$result")" = "[\"grimoires/loa/a2a/$SPRINT/adversarial-rejected-review.jsonl\",\"grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-companion.jsonl\"]" ]
    printf '\n' >> "$OUT_DIR/adversarial-rejected-review-companion.jsonl"
    {
        echo "All good"; echo; echo "Sprint 9 has been reviewed and approved."; echo
        echo "## Rejected dissent payloads"; echo; echo "- no severity — repair-mutated-nonviolated-field: not a defect."; echo
        echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'
    } > "$OUT_DIR/engineer-feedback.md"
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.consistent == true' >/dev/null
    # a stale sidecar from a writer that did not run this time is not this run's (chunk b C-003 / c C-002) —
    # older than the envelope it is a warning; newer, a stale-envelope violation (eighth run b C-001)
    printf '{"reject_reason":"stale"}\n%.0s' 1 2 3 4 5 > "$OUT_DIR/adversarial-rejected-review-a-old-chunk.jsonl"
    touch -d '2020-01-01 00:00:00' "$OUT_DIR/adversarial-rejected-review-a-old-chunk.jsonl"
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 0 ]
}

@test "CMP-24 when the shim swallowed cheval's stderr, the failed companion's class and last_error come from the MODELINV ledger row for that call (fourth run)" {
    BEHAVIOUR[claude-headless]=errquiet
    # the row cheval would have written for this call (the harness points LOA_MODELINV_LOG_PATH at a temp file)
    jq -nc '{schema_version:"1.1.0", primitive_id:"MODELINV", event_type:"model.invoke.complete", ts_utc:"2099-01-01T00:00:00Z",
             payload:{models_requested:["anthropic:claude-headless"], models_succeeded:[], calling_primitive:"adversarial-review",
                      models_failed:[{model:"anthropic:claude-headless", provider:"anthropic", error_class:"FALLBACK_EXHAUSTED",
                                      message_redacted:"[cheval] RETRIES_EXHAUSTED: Failed after 1 attempts: [cheval] PROVIDER_UNAVAILABLE: Provider \u0027anthropic\u0027 unavailable: claude -p timed out after 910s"}]}}' >> "$LOA_MODELINV_LOG_PATH"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    le=$(jq -r '.metadata.companion_voice.last_error' <<<"$result")
    [ "$le" = "MODELINV RETRIES_EXHAUSTED PROVIDER_UNAVAILABLE timed out after 910s" ] || [ "$le" = "RETRIES_EXHAUSTED PROVIDER_UNAVAILABLE timed out after 910s" ]
    [[ "$le" != *"shim"* ]]
    # a row older than the companion's start is not this call's
    : > "$LOA_MODELINV_LOG_PATH"
    # the same full shape as above, differing only in ts_utc — so only the timestamp filter rejects it (c1 C-004)
    jq -nc '{schema_version:"1.1.0", primitive_id:"MODELINV", event_type:"model.invoke.complete", ts_utc:"2000-01-01T00:00:00Z",
             payload:{models_requested:["anthropic:claude-headless"], models_succeeded:[], calling_primitive:"adversarial-review",
                      models_failed:[{model:"anthropic:claude-headless", provider:"anthropic", error_class:"FALLBACK_EXHAUSTED", message_redacted:"stale: claude -p timed out after 1s"}]}}' >> "$LOA_MODELINV_LOG_PATH"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "model_unavailable" ]
    [[ "$(jq -r '.metadata.companion_voice.last_error' <<<"$result")" != *"stale"* ]]
}

@test "CMP-25 *-headless hops are serialised per CLI binary across the two walks (phase-tagged trace, time-bounded); a lock not acquired within the hop's bound fails the hop as a timeout; the repair round-trip takes the same lock (fourth–seventh run)" {
    # phase-tagged trace: serialised hops read start,end,start,end by timestamp; overlapping ones start,start,… (c1 C-001)
    invoke_dissenter() { echo "$(date +%s%N) start $BASHPID" >> "$T/lock-trace"; sleep 1; echo "$(date +%s%N) end $BASHPID" >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    t0=$(date +%s%N)
    _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null &
    _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null &
    wait
    t1=$(date +%s%N)
    [ "$(sort -n "$T/lock-trace" | awk '{printf "%s,", $2}')" = "start,end,start,end," ]
    (( (t1 - t0) / 1000000 >= 2000 ))   # two one-second hops, one after the other
    [ -f "$T/loa-headless-locks-$(id -u)/claude.lock" ]
    # a held lock: the hop is not run, rc 124 (a timeout), the chain can walk on
    : > "$T/lock-trace"
    exec 8>>"$T/loa-headless-locks-$(id -u)/foo.lock"; flock 8
    rc=0; ( _ADV_CLI_HOP_TIMEOUT=1; _adv_invoke_hop foo-headless a b foo-headless 30 "" review 2>"$T/lock-err" ) || rc=$?
    flock -u 8; exec 8>&-
    [ "$rc" = "124" ]
    [ ! -s "$T/lock-trace" ]
    grep -q "not acquired within 1s" "$T/lock-err"
    # an HTTP hop takes no lock
    : > "$T/lock-trace"; _adv_invoke_hop gpt-5.5 a b gpt-5.5 30 "" review >/dev/null
    [ ! -f "$T/loa-headless-locks-$(id -u)/gpt-5.5.lock" ]
    # the repair round-trip goes through the same lock
    _repair_finding_via_model() { echo "$(date +%s%N) repair $BASHPID" >> "$T/lock-trace"; echo '{}'; }
    : > "$T/lock-trace"
    _adv_with_cli_lock claude-headless _repair_finding_via_model x y z claude-headless 60 >/dev/null
    [ "$(grep -c repair "$T/lock-trace")" = "1" ]
}

@test "CMP-26 the companion's post-hop work has its own budget: a model that answered is not reaped mid-process_findings when the hop cap has passed (fifth run C-001)" {
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=1          # the hop phase's cap
    eval "$(declare -f process_findings | sed '1s/^process_findings/_orig_process_findings/')"
    process_findings() { if [[ "$3" == "claude-headless" ]]; then : > "$T/slow-post-hop"; sleep 3; fi; _orig_process_findings "$@"; }   # slow post-hop work for the companion only
    t0=$(date +%s)
    result=$(_run_main review)
    [ -f "$T/slow-post-hop" ]                       # the slow branch ran (c1 C-003)
    (( $(date +%s) - t0 >= 3 ))
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(_companion_post_budget gpt-5.5-pro 30)" = "4760" ]      # keyless: claude-headless (910) + the answering voice (30), × 5 + 60
    [ "$( export ANTHROPIC_API_KEY=k; _companion_post_budget gpt-5.5-pro 30 )" = "4910" ]   # tiny (30) + claude-headless (910) + gpt-5.5-pro (30), × 5 + 60
}

@test "CMP-27 a primary that never answered leaves the companion as the sole voice: counted_as sole_voice, independent null, and the primary attempt that dropped the companion's own hop is excluded from verdict quality (fifth run C-003)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'   # this host's shape: the primary chain ends on claude-headless
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[claude-headless]=unavailable-primary-only
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.degraded' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.primary_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "sole_voice" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "null" ]
    [ "$(jq '.metadata.companion_voice.primary_attempts_excluded' <<<"$result")" = "1" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "4" ]
    [ "$(jq '.verdict_quality.voices_dropped | length' <<<"$result")" = "3" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
}

@test "CMP-28 LOA_ADVERSARIAL_RUN_TAG scopes the sidecar names to the run: only this run's files are removed at start and listed on the envelope (fifth run C-004)" {
    mkdir -p "$OUT_DIR"; printf '{"reject_reason":"earlier"}\n' > "$OUT_DIR/adversarial-rejected-review-companion.jsonl"   # another run's file
    export LOA_ADVERSARIAL_RUN_TAG="chunk-x"
    BEHAVIOUR[claude-headless]=reject
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.rejected_sidecar' <<<"$result")" = "grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-companion-chunk-x.jsonl" ]
    [ "$(jq -c '.metadata.rejected_sidecars' <<<"$result")" = "[\"grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-chunk-x.jsonl\",\"grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-companion-chunk-x.jsonl\"]" ]
    [ "$(grep -c '' "$OUT_DIR/adversarial-rejected-review-companion-chunk-x.jsonl")" = "1" ]
    [ -f "$OUT_DIR/adversarial-rejected-review-companion.jsonl" ]   # untouched: not this run's name
    # sixth run, C-004: with the sidecar disabled nothing of ours is listed (another run's files stay out)
    unset LOA_ADVERSARIAL_RUN_TAG; export LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=1
    result=$(_run_main review)
    [ "$(jq -c '.metadata.rejected_sidecars' <<<"$result")" = "[]" ]
    unset LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE
}

@test "CMP-29 lock-wait time is not charged to the hop's cap: a companion that queued behind another claude -p still gets its full cap once it holds the lock (sixth run C-002); the lock directory must be ours (C-003)" {
    export XDG_RUNTIME_DIR="$T"
    # hold the claude lock for 2 s from outside; the companion's hop needs 2 s of its own; the hop cap is 3 s
    mkdir -m 700 "$T/loa-headless-locks-$(id -u)"
    ( exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8; sleep 5 ) &   # held longer than the 3 s cap: queueing alone would reap (eighth run, c1 C-002)
    # wait until the lock is observably held (c1 C-006)
    for _ in $(seq 1 40); do flock -n "$T/loa-headless-locks-$(id -u)/claude.lock" true 2>/dev/null || break; sleep 0.05; done
    if flock -n "$T/loa-headless-locks-$(id -u)/claude.lock" true 2>/dev/null; then echo "lock not held" >&2; false; fi
    BEHAVIOUR[claude-headless]=slow2
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=3
    t0=$(date +%s%N)
    result=$(_run_main review)
    t1=$(date +%s%N)
    wait
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    (( (t1 - t0) / 1000000 >= 5000 ))   # queued ~5 s behind the holder, then its own 2 s hop: far past the 3 s hop cap, not reaped
    # a foreign or symlinked lock directory is never used — the hop runs unserialised instead
    rm -f "$T/loa-headless-locks-$(id -u)"/*.lock; rmdir "$T/loa-headless-locks-$(id -u)"   # (the primary's alias chain took codex.lock too)
    ln -s "$T" "$T/loa-headless-locks-$(id -u)"
    invoke_dissenter() { echo ran >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null
    [ "$(grep -c ran "$T/lock-trace")" = "1" ]
    [ ! -e "$T/claude.lock" ]
}

@test "CMP-30 a companion whose CLI ignores TERM is killed after the grace period and the review completes (sixth run: an 8 h hang under the account's usage limit)" {
    BEHAVIOUR[claude-headless]=stubborn
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=1 LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1
    start=$(date +%s)
    result=$(_run_main review)
    (( $(date +%s) - start < 30 ))
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    grep -q "after TERM — KILL" "$T/stderr.log"
    command -v pgrep >/dev/null || skip "pgrep not installed"
    [ -z "$(pgrep -f "loa-cmp30-stubborn-$$")" ]
}

@test "CMP-31 the per-binary lock follows the alias's resolved chain: an HTTP alias whose catalog fallback_chain falls through to a CLI hop takes that binary's lock (eighth run, a2 C-002)" {
    cat > "$T/catalog.yaml" <<'YAML'
providers:
  openai:
    models:
      gpt-5.5:
        context_window: 400000
        fallback_chain: ["openai:gpt-5.3-codex", "openai:codex-headless"]
      gpt-5.3-codex:
        context_window: 400000
      codex-headless:
        context_window: 400000
  anthropic:
    models:
      opus-plain:
        context_window: 1000000
aliases:
  fast: "openai:gpt-5.5"
YAML
    export LOA_MODEL_CONFIG="$T/catalog.yaml"
    [ "$(_adv_cli_bin_for gpt-5.5)" = "codex" ]
    [ "$(_adv_cli_bin_for fast)" = "codex" ]
    [ "$(_adv_cli_bin_for claude-headless)" = "claude" ]
    [ "$(_adv_cli_bin_for opus-plain)" = "" ]
    invoke_dissenter() { echo ran >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    _adv_invoke_hop gpt-5.5 a b gpt-5.5 30 "" review >/dev/null
    [ -f "$T/loa-headless-locks-$(id -u)/codex.lock" ]
    _adv_invoke_hop opus-plain a b opus-plain 30 "" review >/dev/null
    [ ! -f "$T/loa-headless-locks-$(id -u)/opus-plain.lock" ]
    [ "$(grep -c ran "$T/lock-trace")" = "2" ]
}

@test "CMP-32 the INV-5 exclusion is symmetric: a companion attempt that dropped a voice the primary answered with is excluded, verdict quality still aggregates, and an aggregator failure would be named on the envelope (eighth run, a2 C-004)" {
    # an operator chain whose first hop is the primary's own CLI: the companion's codex-headless attempt fails, then claude-headless answers
    python3 - "$CONFIG_FILE" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
s=s.replace("  code_review:\n    enabled: true\n", "  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: [codex-headless, claude-headless]\n", 1); open(p,"w").write(s)
PY
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    BEHAVIOUR[codex-headless]=unavailable-companion-only
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]
    [ "$(jq '.metadata.companion_voice.companion_attempts_excluded' <<<"$result")" = "1" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | sort | join(",")' <<<"$result")" = "claude-headless,codex-headless" ]
    [ "$(jq -r '.metadata | has("verdict_quality_error")' <<<"$result")" = "false" ]
    # an aggregator failure is named, not discarded
    _adv_aggregate_envelopes() { echo "[verdict-aggregate] invariant violation: INV-5: stub" >&2; return 2; }
    result=$(_run_main review)
    [ "$(jq -r '.metadata.verdict_quality_error' <<<"$result")" = "[verdict-aggregate] invariant violation: INV-5: stub" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
}
