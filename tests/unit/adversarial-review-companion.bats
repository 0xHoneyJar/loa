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
    # …and the premise is ASSERTED, not assumed (twelfth run, c1 C-003): a host that exports another alias the probe
    # knows fails here with a message, not in CMP-1 / CMP-11 with a planner-shaped red
    if _adv_cred_present anthropic || _adv_cred_present openai; then
        echo "this host exports a credential alias for anthropic or openai — the keyless-host suite cannot run here (unset it for the run)" >&2
        return 1
    fi
    HOLDER_PIDS=()   # out-of-band lock holders a test spawns; teardown kills them (c1 C-002)
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
        elif [[ "$2" == "mixed" ]]; then
            # cheval's inner walk dropped one voice AND answered with another — one envelope with both (a3 C-007)
            jq -nc --arg d "$3" --arg hop "$4" '{status:"DEGRADED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:2,voices_succeeded:1,voices_succeeded_ids:[$hop],voices_dropped:[{voice:$d,reason:"ProviderUnavailable",exit_code:1,blocker_risk:"unknown"}],chain_health:"degraded",confidence_floor:"low",rationale:"stub mixed inner walk",single_voice_call:false}'
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
            walkedmixed:*)   # <dropped>:<hop> — the inner walk dropped one voice and answered with another (a3 C-007)
                local _mx="${BEHAVIOUR[$model]#walkedmixed:}" _mxd _mxh; _mxd="${_mx%%:*}"; _mxh="${_mx#*:}"
                [[ -n "$sidecar" ]] && _vq "$model" mixed "$_mxd" "$_mxh" > "$sidecar"
                jq -nc --arg m "$_mxh" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
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
            unavailable-after-companion)   # a failure the primary sees only once the companion is GONE (bounded barrier: CMP-27)
                local _i=0; while [[ -n "${_ADV_COMPANION_PID:-}" ]] && kill -0 "$_ADV_COMPANION_PID" 2>/dev/null && (( _i++ < 300 )); do sleep 0.1; done
                [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1 ;;
            unavailable-marker)            # a failure that leaves a marker the companion's stub waits for (CMP-33)
                : > "$T/marker-$model-failed"
                [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1 ;;
            await-primary-marker)          # answers only once the primary has failed its codex hop AND logged the skip of the shared
                                           # hop (bounded barriers on a marker and on the live stderr — never a sleep: CMP-33; twelfth run, c1 C-001)
                local _j=0; while [[ ! -e "$T/marker-codex-headless-failed" ]] && (( _j++ < 300 )); do sleep 0.1; done
                _j=0; while ! grep -q "skipped on the primary chain" "$T/stderr.log" 2>/dev/null && (( _j++ < 300 )); do sleep 0.1; done
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"; jq -nc '{content: "{\"findings\":[]}", tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: false}'; return 0 ;;
            slow)     # a hung hop with a PID-scoped process name, so the orphan probe cannot match anything else on the host (c C-001)
                bash -c 'exec -a "$0" sleep 300' "loa-cmp14-hung-$$"   # only the reaper can end it (eighth run, c1 C-002)
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"; jq -nc '{content: "{\"findings\":[]}", tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: false}'; return 0 ;;
            errlog)   echo "boom: provider said no (token sk-ant-api03-SECRETSECRETSECRETSECRET1234)" >&2; return 1 ;;
            errquiet) # the shim's shape when cheval fails: banners only, the provider's line went to the MODELINV ledger —
                      # the row is written NOW (inside the companion's window), as cheval would (tenth run, c1 C-005)
                if [[ -n "${ERRQUIET_LEDGER_MESSAGE:-}" ]]; then
                    jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg msg "$ERRQUIET_LEDGER_MESSAGE" '{schema_version:"1.1.0", primitive_id:"MODELINV", event_type:"model.invoke.complete", ts_utc:$ts,
                        payload:{models_requested:["anthropic:claude-headless"], models_succeeded:[], calling_primitive:"adversarial-review",
                                 models_failed:[{model:"anthropic:claude-headless", provider:"anthropic", error_class:"FALLBACK_EXHAUSTED", message_redacted:$msg}]}}' >> "$LOA_MODELINV_LOG_PATH"
                fi
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
    # an out-of-band lock holder a failed assertion left behind (twelfth run, c1 C-002)
    local p; for p in ${HOLDER_PIDS[@]+"${HOLDER_PIDS[@]}"}; do kill "$p" 2>/dev/null || true; done
    [[ -n "${SPRINT:-}" && -n "${OUT_DIR:-}" && "$OUT_DIR" == */grimoires/loa/a2a/sprint-comp-* ]] || return 0
    for d in "$OUT_DIR" "$OUT_DIR"-*; do
        [[ "$d" == */a2a/sprint-comp-* ]] || continue
        if [[ -d "$d" ]]; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi
    done
    # a workdir a failing CMP-16 kept (LOA_ADVERSARIAL_KEEP_WORKDIR=1) holds the raw diagnostic line — it never
    # outlives the test (eleventh run, c1 C-003)
    for d in "${TMPDIR:-/tmp}"/adversarial-"$SPRINT"-*; do
        [[ "$d" == */adversarial-sprint-comp-* && -d "$d" ]] || continue
        find "$d" -mindepth 1 -delete; rmdir "$d"
    done
}
_now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }   # (macOS date has no %N)
_need_flock() { command -v flock >/dev/null 2>&1 || skip "flock not installed (macOS): the lock cases cannot run here"; }
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

@test "CMP-5 companion_voice: false on the block disables the second chain (voices_planned 1, planned false); the YAML boolean spellings match in any case and a non-boolean is said and ignored (eleventh run, a1 C-001)" {
    _cfg_edit $'enabled: true\n' $'enabled: true\n    companion_voice: false\n'
    result=$(_run_main review)
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "false" ]
    [ "$(grep -cx "claude-headless" "$CALLS")" = "0" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    prev=false
    for spelling in False NO Off; do
        _cfg_edit "companion_voice: $prev" "companion_voice: $spelling"; prev=$spelling
        result=$(_run_main review)
        [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "false" ]
    done
    _cfg_edit "companion_voice: $prev" "companion_voice: nope"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    grep -q "companion_voice='nope' is not a boolean" "$T/stderr.log"
    _cfg_edit "companion_voice: nope" "companion_voice: TRUE"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    [ "$(grep -c "is not a boolean" "$T/stderr.log")" = "0" ]
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
    # the common production case (tenth run, c1 C-002): every listed sidecar exists, and a feedback file with no
    # rejected-payload section is CONSISTENT against this clean two-voice envelope
    [ "$(jq '.metadata.rejected_sidecars | length' <<<"$result")" = "1" ]   # the primary's (empty) file; a companion that rejected nothing writes none — the loop below is not a no-op
    for f in $(jq -r '.metadata.rejected_sidecars[]' <<<"$result"); do [ -f "$PROJECT_ROOT/$f" ]; done
    { echo "All good"; echo; echo "Sprint 9 has been reviewed and approved."; echo
      echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'; } > "$OUT_DIR/engineer-feedback.md"
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.consistent == true and (.warnings | length) == 0' >/dev/null
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
    [ -n "$reason" ]
    [ "$reason" != "null" ]
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

@test "CMP-15 a fold that fails keeps the primary envelope (companion_voice.status fold_failed) instead of blanking it (C-002), and the companion's sidecar stays listed so its rows are still counted (tenth run, c2 C-002)" {
    _fold_companion() { echo "not json at all"; }
    BEHAVIOUR[claude-headless]=reject
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "fold_failed" ]
    # the rows the companion rejected do not go with the fold: the file exists, the envelope lists it (the list
    # is the run's files, not the fold's output), and verdict-derive holds an approval to those rows
    [ "$(grep -c '' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "1" ]
    jq -e --arg p "grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-companion.jsonl" '.metadata.rejected_sidecars | index($p) != null' <<<"$result" >/dev/null
    { echo "All good"; echo; echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'; } > "$OUT_DIR/engineer-feedback.md"
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.consistent == false and (.violations | map(select(test("schema-rejected payload"))) | length) == 1' >/dev/null
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
    # …and that glob is the real workdir, not a vacuous pattern (tenth run, c1 C-003): kept once, it is exactly one
    # directory holding the companion's log with the raw line; then removed
    LOA_ADVERSARIAL_KEEP_WORKDIR=1 _run_main review >/dev/null
    kept=$(ls -d "${TMPDIR:-/tmp}"/adversarial-"$SPRINT"-* 2>/dev/null)
    [ "$(printf '%s\n' "$kept" | grep -c .)" = "1" ]
    [ -s "$kept/companion/companion.log" ]
    grep -q "provider said no" "$kept/companion/companion.log"
    find "$kept" -mindepth 1 -delete; rmdir "$kept"
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
    # a stale sidecar from a writer that did not run this time is not this run's (chunk b C-003 / c C-002) — and
    # whatever its age it is a violation, never exempt for being older than the envelope (tenth run b C-001):
    # its rows were never folded, so they are triaged or the file removed before the gate passes
    printf '{"reject_reason":"stale"}\n%.0s' 1 2 3 4 5 > "$OUT_DIR/adversarial-rejected-review-a-old-chunk.jsonl"
    touch -t 202001010000 "$OUT_DIR/adversarial-rejected-review-a-old-chunk.jsonl"   # (BSD touch has no -d 'Y-m-d H:M:S')
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 1 ]   # its five rows count (eleventh run, b DISS-C-001): 6 rows against 1 bullet, the warning names the file
    echo "$output" | jq -e '.consistent == false and (.violations | length) == 1 and (.violations[0] | test("holds 1 top-level triage line.*6 rejected payload")) and (.warnings | map(select(test("a-old-chunk.jsonl.*not listed.*never folded"))) | length) == 1' >/dev/null
    rm -f "$OUT_DIR/adversarial-rejected-review-a-old-chunk.jsonl"
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 0 ]
}

@test "CMP-24 when the shim swallowed cheval's stderr, the failed companion's class and last_error come from the MODELINV ledger row for that call (fourth run)" {
    BEHAVIOUR[claude-headless]=errquiet
    # the row cheval writes for this call lands inside the companion's window (the stub writes it at call time;
    # the harness points LOA_MODELINV_LOG_PATH at a temp file)
    export ERRQUIET_LEDGER_MESSAGE="[cheval] RETRIES_EXHAUSTED: Failed after 1 attempts: [cheval] PROVIDER_UNAVAILABLE: Provider 'anthropic' unavailable: claude -p timed out after 910s"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    le=$(jq -r '.metadata.companion_voice.last_error' <<<"$result")
    [ "$le" = "MODELINV RETRIES_EXHAUSTED PROVIDER_UNAVAILABLE timed out after 910s" ] || [ "$le" = "RETRIES_EXHAUSTED PROVIDER_UNAVAILABLE timed out after 910s" ]
    [[ "$le" != *"shim"* ]]
    # a row older than the companion's start is not this call's — nor one after its end (tenth run, c1 C-005)
    unset ERRQUIET_LEDGER_MESSAGE
    : > "$LOA_MODELINV_LOG_PATH"
    jq -nc '{schema_version:"1.1.0", primitive_id:"MODELINV", event_type:"model.invoke.complete", ts_utc:"2099-01-01T00:00:00Z",
             payload:{models_requested:["anthropic:claude-headless"], models_succeeded:[], calling_primitive:"adversarial-review",
                      models_failed:[{model:"anthropic:claude-headless", provider:"anthropic", error_class:"FALLBACK_EXHAUSTED", message_redacted:"later: claude -p timed out after 1s"}]}}' >> "$LOA_MODELINV_LOG_PATH"
    # the same full shape as above, differing only in ts_utc — so only the timestamp filter rejects it (c1 C-004)
    jq -nc '{schema_version:"1.1.0", primitive_id:"MODELINV", event_type:"model.invoke.complete", ts_utc:"2000-01-01T00:00:00Z",
             payload:{models_requested:["anthropic:claude-headless"], models_succeeded:[], calling_primitive:"adversarial-review",
                      models_failed:[{model:"anthropic:claude-headless", provider:"anthropic", error_class:"FALLBACK_EXHAUSTED", message_redacted:"stale: claude -p timed out after 1s"}]}}' >> "$LOA_MODELINV_LOG_PATH"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "model_unavailable" ]
    [[ "$(jq -r '.metadata.companion_voice.last_error // ""' <<<"$result")" != *"stale"* ]]
    [[ "$(jq -r '.metadata.companion_voice.last_error // ""' <<<"$result")" != *"later"* ]]
}

@test "CMP-25 *-headless hops are serialised per CLI binary across the two walks (phase-tagged trace, time-bounded); a lock not acquired within the hop's bound fails the hop as a timeout; the repair round-trip takes the same lock (fourth–seventh run)" {
    _need_flock
    # phase-tagged trace: serialised hops read start,end,start,end by timestamp; overlapping ones start,start,… (c1 C-001)
    invoke_dissenter() { echo "$(_now_ms) start $BASHPID" >> "$T/lock-trace"; sleep 1; echo "$(_now_ms) end $BASHPID" >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    t0=$(_now_ms)
    _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null &
    _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null &
    wait
    t1=$(_now_ms)
    [ "$(sort -n "$T/lock-trace" | awk '{printf "%s,", $2}')" = "start,end,start,end," ]
    (( t1 - t0 >= 2000 ))   # two one-second hops, one after the other
    [ -f "$T/loa-headless-locks-$(id -u)/claude.lock" ]
    # a held lock: the hop is not run, rc 124 (a timeout), the chain can walk on
    : > "$T/lock-trace"
    exec 8>>"$T/loa-headless-locks-$(id -u)/foo.lock"; flock 8
    rc=0; ( _ADV_CLI_HOP_TIMEOUT=1; _adv_invoke_hop foo-headless a b foo-headless 30 "" review 2>"$T/lock-err" ) || rc=$?
    flock -u 8; exec 8>&-
    [ "$rc" = "124" ]
    [ ! -s "$T/lock-trace" ]
    grep -q "not acquired within 1s" "$T/lock-err"
    # an HTTP hop whose chain holds no CLI hop takes no lock: the lock directory is byte-identical around the call
    # (lock files are named after the BINARY, so "no gpt-5.5.lock" proves nothing — c1 C-001 of the tenth run)
    printf 'providers:\n  openai:\n    models:\n      gpt-5.5-plain:\n        context_window: 400000\n' > "$T/plain-catalog.yaml"
    before=$(ls -A "$T/loa-headless-locks-$(id -u)" 2>/dev/null)
    : > "$T/lock-trace"; LOA_MODEL_CONFIG="$T/plain-catalog.yaml" _adv_invoke_hop gpt-5.5-plain a b gpt-5.5-plain 30 "" review >/dev/null
    after=$(ls -A "$T/loa-headless-locks-$(id -u)" 2>/dev/null)
    [ -n "$before" ]
    [ "$before" = "$after" ]
    [ "$(grep -c . "$T/lock-trace")" = "2" ]
    # the repair round-trip goes through the same lock
    _repair_finding_via_model() { echo "$(_now_ms) repair $BASHPID" >> "$T/lock-trace"; echo '{}'; }
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
    # the primary's first hop fails only once the companion is GONE (a bounded barrier on its pid, not a sleep —
    # eleventh run, c1 C-001), so the primary reaches the shared hop after the companion finished, tries it itself
    # and fails — the skip rule (CMP-33) applies only while the companion is alive
    BEHAVIOUR[gpt-5.5-pro]=unavailable-after-companion; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[claude-headless]=unavailable-primary-only
    result=$(_run_main review)
    [ "$(jq -r '.metadata.model_attempts | join(",")' <<<"$result")" = "gpt-5.5-pro:api_failure,gpt-5.5:api_failure,codex-headless:api_failure,claude-headless:api_failure" ]
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
    _need_flock
    export XDG_RUNTIME_DIR="$T"
    # hold the claude lock for 2 s from outside; the companion's hop needs 2 s of its own; the hop cap is 3 s
    mkdir -m 700 "$T/loa-headless-locks-$(id -u)"
    ( exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8; sleep 5 ) 3>&- &   # held longer than the 3 s cap: queueing alone would reap (eighth run, c1 C-002)
    HOLDER_PIDS+=("$!")
    # wait until the lock is observably held (c1 C-006)
    for _ in $(seq 1 40); do flock -n "$T/loa-headless-locks-$(id -u)/claude.lock" true 2>/dev/null || break; sleep 0.05; done
    if flock -n "$T/loa-headless-locks-$(id -u)/claude.lock" true 2>/dev/null; then echo "lock not held" >&2; false; fi
    BEHAVIOUR[claude-headless]=slow2
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=3
    t0=$(_now_ms)
    result=$(_run_main review)
    t1=$(_now_ms)
    wait
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    (( t1 - t0 >= 5000 ))   # queued ~5 s behind the holder, then its own 2 s hop: far past the 3 s hop cap, not reaped
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
    _need_flock
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
    # the prefix and an alias are resolved before the *-headless test (twelfth run, a2 C-001): one lock per binary
    [ "$(_adv_cli_bin_for anthropic:claude-headless)" = "claude" ]
    [ "$(_adv_cli_bin_for openai:gpt-5.5)" = "codex" ]
    printf 'aliases:\n  fastclaude: "anthropic:claude-headless"\n' >> "$T/catalog.yaml"
    [ "$(_adv_cli_bin_for fastclaude)" = "claude" ]
    invoke_dissenter() { echo ran >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    _adv_invoke_hop anthropic:claude-headless a b anthropic:claude-headless 30 "" review >/dev/null
    [ -f "$T/loa-headless-locks-$(id -u)/claude.lock" ]
    [ ! -e "$T/loa-headless-locks-$(id -u)/anthropic_claude.lock" ]
    : > "$T/lock-trace"
    invoke_dissenter() { echo ran >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    _adv_invoke_hop gpt-5.5 a b gpt-5.5 30 "" review >/dev/null
    [ -f "$T/loa-headless-locks-$(id -u)/codex.lock" ]
    before=$(ls -A "$T/loa-headless-locks-$(id -u)" 2>/dev/null)
    _adv_invoke_hop opus-plain a b opus-plain 30 "" review >/dev/null
    after=$(ls -A "$T/loa-headless-locks-$(id -u)" 2>/dev/null)
    [ -n "$before" ]
    [ "$before" = "$after" ]   # a model with no CLI in its chain touched no lock (snapshot, not a filename guess)
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

@test "CMP-33 the primary skips a hop the live companion shares instead of queueing behind its claude -p: model_attempts records it, the companion is the sole voice (tenth run, a2 C-003)" {
    _need_flock
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'   # the primary chain ends on the companion's hop
    # the companion answers only after the primary has failed its codex hop (a bounded barrier on a marker, not a
    # sleep — eleventh run, c1 C-001): it is alive when the primary reaches the shared hop
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable-marker
    BEHAVIOUR[claude-headless]=await-primary-marker
    result=$(_run_main review)
    [ "$(jq -r '.metadata.model_attempts | join(",")' <<<"$result")" = "gpt-5.5-pro:api_failure,gpt-5.5:api_failure,codex-headless:api_failure,claude-headless:skipped_shared_with_companion" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "sole_voice" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    grep -q "the companion is running it — skipped on the primary chain" "$T/stderr.log"
    # the repair's HTTP hop waits for the lock only as long as its own timeout (a2 C-001) — and so does a repair's
    # CLI hop under _ADV_LOCK_WAIT_CLI (twelfth run, a1 C-002), never a dissent hop's 910 s bound
    export ANTHROPIC_API_KEY="sk-presence-only-never-printed" XDG_RUNTIME_DIR="$T"
    mkdir -p "$T/loa-headless-locks-$(id -u)"; exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8
    _repair_finding_via_model() { echo '{}'; }
    t0=$(date +%s); rc=0; ( _ADV_LOCK_WAIT=1; _adv_with_cli_lock tiny _repair_finding_via_model x y z tiny 1 >/dev/null 2>&1 ) || rc=$?
    (( $(date +%s) - t0 < 10 ))
    [ "$rc" = "124" ]
    t0=$(date +%s); rc=0; ( _ADV_LOCK_WAIT_CLI=1; _adv_with_cli_lock claude-headless _repair_finding_via_model x y z claude-headless 1 >/dev/null 2>&1 ) || rc=$?
    flock -u 8; exec 8>&-
    (( $(date +%s) - t0 < 10 ))
    [ "$rc" = "124" ]
}

@test "CMP-34 the envelope and sidecars are single-writer per (sprint, gate): a second live run is refused before it removes anything — a distinct tag too (the envelope path is shared); a dead run's lock, a reused pid and an abandoned empty lock are taken over; a lock seconds old with no pid yet is a holder in flight (eleventh run a2 DISS-001; twelfth run a2 C-002 / C-003)" {
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"; [ -d "$lockd" ]
    [ "$(sed -n 1p "$lockd/pid")" = "$$" ]; [ -n "$(sed -n 2p "$lockd/pid")" ]   # pid + start time
    sleep 30 3>&- & holder=$!; HOLDER_PIDS+=("$holder"); printf '%s\n%s\n' "$holder" "$(_adv_proc_start "$holder")" > "$lockd/pid"; _ADV_RUN_LOCK_DIR=""   # held by another live process
    BEHAVIOUR[claude-headless]=reject
    rc=0; result=$(_run_main review) || rc=$?
    [ "$rc" = "2" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "refused_concurrent_run" ]   # a --json caller fails closed (twelfth run, a3 C-004)
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    grep -q "another adversarial-review run for $SPRINT/review is in progress (pid $holder)" "$T/stderr.log"
    [ ! -e "$OUT_DIR/adversarial-review.json" ]
    # a distinct tag is NOT a parallel path — the envelope adversarial-review.json is shared (twelfth run, a2 C-003)
    rc=0; result=$( export LOA_ADVERSARIAL_RUN_TAG=other; _run_main review ) || rc=$?
    [ "$rc" = "2" ]; [ ! -e "$OUT_DIR/adversarial-rejected-review-companion-other.jsonl" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "refused_concurrent_run" ]
    [ "$(ls -d "$(_adv_cli_lock_dir)"/run-*.lock.d | grep -c .)" = "1" ]
    # a reused pid: the token's start time is not the live process's — the holder is gone, the lock is taken over
    printf '%s\n%s\n' "$holder" "Thu Jan  1 00:00:00 1970" > "$lockd/pid"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ ! -d "$lockd" ]
    # the holder died without releasing: taken over, run, released
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"; printf '%s\n%s\n' "$holder" "$(_adv_proc_start "$holder")" > "$lockd/pid"; _ADV_RUN_LOCK_DIR=""
    kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null || true
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ ! -d "$lockd" ]
    # a lock directory seconds old with no pid yet is a holder in flight (twelfth run, a2 C-002) …
    mkdir "$lockd"
    rc=0; result=$(_run_main review) || rc=$?
    [ "$rc" = "2" ]; grep -q "is starting (its lock is seconds old)" "$T/stderr.log"
    [ "$(jq -r '.metadata.status' <<<"$result")" = "refused_concurrent_run" ]
    # … and an abandoned one (older than five seconds, still no pid) is taken over
    touch -t 202001010000 "$lockd"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ ! -d "$lockd" ]
}

@test "CMP-35 the repair chain, like the main walk, omits a hop the LIVE companion shares and takes it back once the companion is gone; the answering voice is never omitted (twelfth run, a1 C-002)" {
    export ANTHROPIC_API_KEY="sk-presence-only-never-printed"
    companion_shared_hops="claude-headless"
    sleep 30 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID")
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny gpt-5.5-pro" ]
    [ "$(_repair_model_chain "claude-headless")" = "tiny claude-headless" ]   # the voice that answered stays terminal
    kill "$_ADV_COMPANION_PID" 2>/dev/null; wait "$_ADV_COMPANION_PID" 2>/dev/null || true
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]
    _ADV_COMPANION_PID=""; companion_shared_hops=""
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]
    unset ANTHROPIC_API_KEY
}

@test "CMP-36 without flock the per-binary serialisation is off and said once, never silently (twelfth run, a2 C-006)" {
    invoke_dissenter() { echo ran >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    ( _ADV_FLOCK_BIN=/nonexistent/flock
      _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null
      _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null ) 2>"$T/noflock-err"
    [ "$(grep -c ran "$T/lock-trace")" = "2" ]
    [ "$(grep -c "flock is not installed" "$T/noflock-err")" = "1" ]
    [ ! -e "$T/loa-headless-locks-$(id -u)/claude.lock" ]
}

@test "CMP-37 a shared hop is skipped only while the companion is ON it: with the companion busy on its HTTP hop the primary waits for it to settle and then runs the hop itself; a companion that moved to the shared hop is not doubled (twelfth run, a3 C-001)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'   # the primary chain ends on the companion's CLI hop
    export ANTHROPIC_API_KEY="sk-presence-only-never-printed"   # a credentialed host: the companion chain is opus → claude-headless
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[opus]=slow2   # the companion is on opus (an HTTP hop) when the primary reaches claude-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "opus,claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "opus" ]
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:reviewed" ]   # not skipped: the companion never ran it
    grep -q "the companion finished without it — the primary runs it" "$T/stderr.log"
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "false" ]   # both Anthropic: not a second voice, but the primary did answer
    # the companion's HTTP hop fails and it moves to claude-headless: the primary does not double the binary
    BEHAVIOUR[opus]=unavailable; BEHAVIOUR[claude-headless]=slow2
    result=$(_run_main review)
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:skipped_shared_with_companion" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "sole_voice" ]
    unset ANTHROPIC_API_KEY
}

@test "CMP-38 a failed prompt copy never launches the companion against an empty workdir: planned false, reason prompt_copy_failed, one voice (twelfth run, a3 C-006)" {
    cp() { return 1; }
    result=$(_run_main review)
    [ "$(jq -c '.metadata.companion_voice' <<<"$result")" = '{"planned":false,"reason":"prompt_copy_failed","family":"anthropic"}' ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    [ "$(grep -cx "claude-headless" "$CALLS")" = "0" ]
    grep -q "Companion voice not planned (anthropic family): prompt_copy_failed" "$T/stderr.log"
    unset -f cp
}

@test "CMP-39 a MIXED primary attempt envelope (the inner walk dropped the companion's voice and answered with another) keeps its own voice: aggregated without the conflicting dropped entry, two voices, INV-6 intact (twelfth run, a3 C-007)" {
    BEHAVIOUR[gpt-5.5-pro]=walkedmixed:claude-headless:codex-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq '.metadata.companion_voice.primary_attempts_rewritten' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.companion_voice.primary_attempts_excluded' <<<"$result")" = "null" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | sort | join(",")' <<<"$result")" = "claude-headless,codex-headless" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq '.verdict_quality.voices_dropped | length' <<<"$result")" = "0" ]
    grep -q "rewritten without that entry (INV-5; the primary's own voice kept)" "$T/stderr.log"
}

@test "CMP-40 an operator wait knob that is not a number never aborts the review or reaps a healthy companion: the computed cap applies (twelfth run, a3 C-003)" {
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS="ten minutes"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    grep -qE "Companion voice \(anthropic family\): claude-headless \(wait cap [0-9]+s\)" "$T/stderr.log"
    unset LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS
}
