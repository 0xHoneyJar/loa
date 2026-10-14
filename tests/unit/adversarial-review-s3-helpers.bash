# shellcheck shell=bash
# =============================================================================
# tests/unit/adversarial-review-s3-helpers.bash — the whole-run harness shared by the cycle-129 Sprint 3 suites
# (adversarial-review-advisory.bats, -budget.bats, -locality.bats).
#
# main() is sourced and run with `invoke_dissenter` replaced by a stub keyed on the model (canned adapter envelopes + a
# valid single-voice verdict_quality sidecar, the shape the companion suite uses), a temp .loa.config.yaml, a temp
# catalog when a case needs one, no credentials (a keyless host) and the test's own ledgers. No model is ever called.
# =============================================================================

s3_setup() {  # <sprint prefix>
    umask 022
    S3_PREFIX="$1"
    SPRINT="${S3_PREFIX}-$$-${BATS_TEST_NUMBER:-0}"
    : "${BATS_TEST_TMPDIR:?BATS_TEST_TMPDIR not set — needs bats-core >= 1.4}"
    T="$BATS_TEST_TMPDIR"
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    export PROJECT_ROOT
    OUT_DIR="$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT"
    [[ ! -e "$OUT_DIR" && ! -L "$OUT_DIR" ]] || { echo "setup: $OUT_DIR already stands" >&2; SPRINT=""; return 1; }
    export LOA_MODELINV_LOG_PATH="$T/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$T/cost-ledger.jsonl"
    export XDG_RUNTIME_DIR="$T" XDG_CACHE_HOME="$T/xdg-cache"
    export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
    unset LOA_ADVERSARIAL_KEEP_WORKDIR LOA_ADVERSARIAL_RUN_TAG LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE \
          LOA_ADVERSARIAL_REPAIR_MODEL LOA_ADVERSARIAL_REAP_GRACE_SECONDS LOA_MODEL_CONFIG LOA_ADVERSARIAL_CLI_HOP_TIMEOUT \
          LOA_ADVERSARIAL_NO_FM_DERIVATION LOA_ADVERSARIAL_RUN_LOCK_GRACE_SECONDS LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS \
          LOA_ADVERSARIAL_DISABLE_FALLBACK LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS _ADV_PGREP_BIN _ADV_FLOCK_BIN _ADV_REDACTOR_BIN
    local saved_root="$PROJECT_ROOT" _src
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    _src="$(sed 's/^\( *\)main "\$@"$/\1: main disabled for testing/' "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh")"
    grep -q ': main disabled for testing' <<<"$_src" || { echo "setup: the main trailer sed matched nothing" >&2; return 1; }
    eval "$_src"
    PROJECT_ROOT="$saved_root"; export PROJECT_ROOT
    local p v; local -a row
    for p in anthropic openai google; do read -ra row <<<"$(_adv_cred_aliases "$p")"; for v in "${row[@]}"; do unset "$v"; done; done
    export LOA_ADVERSARIAL_ENV_DIR="$T/env"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    if _adv_cred_present anthropic || _adv_cred_present openai; then echo "setup: a credential alias is still present" >&2; return 1; fi
    export LOA_ADVERSARIAL_CLI_PROBE=both
    CONFIG_FILE="$T/loa.config.yaml"
    printf 'diff --git a/x.sh b/x.sh\n--- a/x.sh\n+++ b/x.sh\n@@ -1 +1 @@\n-a\n+b\n' > "$T/diff.patch"
    CALLS="$T/calls.log"; : > "$CALLS"
    declare -gA BEHAVIOUR=()
    # the repair round-trip is not under test here: every repair is unavailable (the payload stays rejected)
    _repair_finding_via_model() { return 1; }
    invoke_dissenter() {  # <sys> <user> <model> <timeout> <vq_sidecar> <type> [schema]
        local model="$3" sidecar="$5" b sev="ADVISORY"
        [[ "${6:-review}" == "audit" ]] && sev="MEDIUM"   # each gate's own vocabulary — no reject detour
        echo "$model" >> "$CALLS"
        b="${BEHAVIOUR[$model]:-ok}"
        case "$b" in
            ok)
                [[ -n "$sidecar" ]] && _s3_vq "$model" ok > "$sidecar"
                jq -nc --arg m "$model" --arg s "$sev" \
                  '{content: ({findings: [{id: "DISS-001", severity: $s, category: "error-handling", anchor: "x.sh:10",
                     description: ("from " + $m + "."), failure_mode: "fm"}]} | tojson),
                    tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                return 0 ;;
            two)   # one finding that matches the counted one (same file, overlapping lines, same category), one on another line,
                   # one on the same line in another category
                [[ -n "$sidecar" ]] && _s3_vq "$model" ok > "$sidecar"
                jq -nc --arg m "$model" --arg s "$sev" '{content: ({findings: [
                    {id: "DISS-001", severity: $s, category: "error-handling", anchor: "x.sh:9-12", description: ("dup from " + $m + "."), failure_mode: "fm"},
                    {id: "DISS-002", severity: $s, category: "error-handling", anchor: "x.sh:40", description: ("new from " + $m + "."), failure_mode: "fm"},
                    {id: "DISS-003", severity: $s, category: "performance", anchor: "x.sh:10", description: ("other category from " + $m + "."), failure_mode: "fm"}]} | tojson),
                    tokens_input: 100, tokens_output: 20, cost_usd: 0.002, latency_ms: 5, schema_enforced: false}'
                return 0 ;;
            reject)   # a payload the normaliser cannot save (no severity)
                [[ -n "$sidecar" ]] && _s3_vq "$model" ok > "$sidecar"
                jq -nc '{content: "{\"findings\":[{\"title\":\"no severity\",\"category\":\"other\",\"description\":\"Something fails.\"}]}", tokens_input: 5, tokens_output: 5, cost_usd: 0.001, latency_ms: 1, schema_enforced: false}'
                return 0 ;;
            fail)  [[ -n "$sidecar" ]] && _s3_vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1 ;;
            malformed) [[ -n "$sidecar" ]] && _s3_vq "$model" ok > "$sidecar"; jq -nc '{content: "not json", tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: false}'; return 0 ;;
            slow)  bash -c 'exec -a "$0" sleep 300' "loa-s3adv-slow-$$"; return 0 ;;
            *) echo "stub: no arm for '$b'" >&2; return 99 ;;
        esac
    }
    _s3_vq() {  # <voice> <ok|fail> [reason] [exit]
        if [[ "$2" == ok ]]; then
            jq -nc --arg v "$1" '{status:"APPROVED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:1,voices_succeeded_ids:[$v],voices_dropped:[],chain_health:"ok",confidence_floor:"low",rationale:"stub",single_voice_call:true}'
        else
            jq -nc --arg v "$1" --arg r "$3" --argjson e "$4" '{status:"FAILED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:0,voices_succeeded_ids:[],voices_dropped:[{voice:$v,reason:$r,exit_code:$e,blocker_risk:"unknown"}],chain_health:"exhausted",confidence_floor:"low",rationale:"stub",single_voice_call:true}'
        fi
    }
    export PYTHONPATH="$PROJECT_ROOT/.claude/adapters"
}

s3_teardown() {
    pkill -KILL -f "loa-s3adv-slow-$$"'( |$)' 2>/dev/null || true
    [[ -n "${SPRINT:-}" && "$SPRINT" == "${S3_PREFIX:-x}"-* && -n "${PROJECT_ROOT:-}" ]] || return 0
    local d="$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT"
    if [[ -d "$d" && ! -L "$d" ]]; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi
    return 0
}

s3_config() {  # <yaml body> → the test's .loa.config.yaml (owner-only)
    printf '%s\n' "$1" > "$CONFIG_FILE"
}

s3_run() {  # <review|audit> → main's stdout (main runs in a subshell: it exits); stderr to $T/stderr.log; the status in $T/rc
    local rc=0
    ( main --type "${1:-review}" --sprint-id "$SPRINT" --diff-file "$T/diff.patch" --json ) 2> "$T/stderr.log" || rc=$?
    printf '%s' "$rc" > "$T/rc"
}

s3_norm() {  # <envelope file> → the envelope without advisory_voices, keys sorted, and only the clock-dependent fields removed
    # (the normalised compare: a timestamp and the repairs' measured wall seconds differ between any two runs, advisory or not)
    jq -S 'del(.advisory_voices) | walk(if type == "object" then del(.timestamp, .ts_utc, .repair_wall_seconds) else . end)' "$1"
}
