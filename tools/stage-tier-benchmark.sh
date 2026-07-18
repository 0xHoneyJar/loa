#!/usr/bin/env bash
# =============================================================================
# tools/stage-tier-benchmark.sh — cycle-116 D3 (bd-c116-d3-tiering)
# =============================================================================
# Single-call A/B sibling of tools/advisor-benchmark.sh. Where advisor-benchmark
# is a git-worktree-hermetic FULL-SPRINT replay harness (2-way advisor/executor
# tier loop over historical sprint SHAs, gated by a cycle-108-scoped signed
# baseline), this harness is shaped for the OTHER A/B shape that cycle-108 never
# produced mechanically (PR #885 executor-vs-advisor was a manual swap): a
# single repeated model call against one fixed prompt, per tier, per trial.
#
# It deliberately does NOT source advisor-benchmark.sh — that script runs `main`
# at file scope and its verify_baselines_gate() is hard-scoped to
# cycle-108-advisor-strategy/baselines.json + a specific signed git tag. Reusing
# it for a new cycle would either spoof that gate or fail closed. The only piece
# worth sharing — classify_replay_outcome (~15 lines, pure jq over a MODELINV
# manifest) — is duplicated below verbatim-in-spirit so the emitted outcomes.jsonl
# is byte-for-byte the shape tools/advisor-benchmark-stats.py already consumes.
#
# Emitted outcomes.jsonl record (per advisor-benchmark-stats.py:22-26):
#   {sprint_sha, tier, idx, score, outcome, stratum}
# `sprint_sha` is repurposed as a trial-batch id (this harness has no sprints).
#
# Usage:
#   stage-tier-benchmark.sh --agent NAME --prompt-file PATH [options]
#   stage-tier-benchmark.sh --dry-run --agent NAME [options]
#
# Options:
#   --agent NAME           (required) cheval agent to invoke (e.g. flatline-scorer)
#   --skill NAME           skill name for per_skill_overrides lookup (default: --agent)
#   --prompt-file PATH     (required unless --dry-run) input prompt file
#   --tiers a,b            comma tiers to A/B (default: advisor,executor)
#   --provider NAME        provider for tier_alias resolution (default: anthropic)
#   --trials-per-tier N    trials per tier (default: 3)
#   --cost-cap-usd N       pre-run cost cap in USD (default: 3.00)
#   --no-cost-cap          skip the cost pre-estimate
#   --score-cmd 'CMD'      optional scorer: invoked as `CMD <model-output-file>`,
#                          MUST print a single numeric quality score to stdout.
#                          Omitted => score field is null (dispatch-only run).
#   --batch-id ID          value for the repurposed sprint_sha field (default: ts)
#   --stratum LABEL        stratum label for the record (default: single-call)
#   --output-dir PATH      output dir (default: stage-tier-manifests/)
#   --timeout SECONDS      per-call cheval timeout (default: 120)
#   --dry-run              plan + emit synthetic outcomes, no API calls
#   --help
#
# Exit codes (mirror advisor-benchmark.sh):
#   0  — all trials completed (regardless of pass/fail outcome)
#   2  — invalid arguments
#   78 — cost-cap exceeded
# =============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG_FILE="$REPO_ROOT/.loa.config.yaml"
CHEVAL="$REPO_ROOT/.claude/adapters/cheval.py"

# --- Defaults ----------------------------------------------------------------
AGENT=""
SKILL=""
PROMPT_FILE=""
TIERS="advisor,executor"
PROVIDER="anthropic"
TRIALS_PER_TIER=3
COST_CAP_USD="3.00"
COST_CAP_ENABLED=1
SCORE_CMD=""
BATCH_ID=""
STRATUM="single-call"
OUTPUT_DIR="$REPO_ROOT/stage-tier-manifests"
TIMEOUT=120
DRY_RUN=0

usage() {
    sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'
}

die() { echo "[stage-tier-benchmark] ERROR: $*" >&2; exit 2; }

# --- Arg parse ---------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --agent)          AGENT="${2:-}"; shift 2 ;;
        --skill)          SKILL="${2:-}"; shift 2 ;;
        --prompt-file)    PROMPT_FILE="${2:-}"; shift 2 ;;
        --tiers)          TIERS="${2:-}"; shift 2 ;;
        --provider)       PROVIDER="${2:-}"; shift 2 ;;
        --trials-per-tier) TRIALS_PER_TIER="${2:-}"; shift 2 ;;
        --cost-cap-usd)   COST_CAP_USD="${2:-}"; shift 2 ;;
        --no-cost-cap)    COST_CAP_ENABLED=0; shift ;;
        --score-cmd)      SCORE_CMD="${2:-}"; shift 2 ;;
        --batch-id)       BATCH_ID="${2:-}"; shift 2 ;;
        --stratum)        STRATUM="${2:-}"; shift 2 ;;
        --output-dir)     OUTPUT_DIR="${2:-}"; shift 2 ;;
        --timeout)        TIMEOUT="${2:-}"; shift 2 ;;
        --dry-run)        DRY_RUN=1; shift ;;
        --help|-h)        usage; exit 0 ;;
        *)                die "unknown argument: $1" ;;
    esac
done

# --- Validation --------------------------------------------------------------
[ -n "$AGENT" ] || die "--agent is required"
[ -n "$SKILL" ] || SKILL="$AGENT"
[ -n "$BATCH_ID" ] || BATCH_ID="batch-$(date -u +%Y%m%dT%H%M%SZ)"

case "$TRIALS_PER_TIER" in
    ''|*[!0-9]*) die "--trials-per-tier must be a positive integer (got '$TRIALS_PER_TIER')" ;;
esac
[ "$TRIALS_PER_TIER" -ge 1 ] || die "--trials-per-tier must be >= 1"

if [ "$DRY_RUN" -eq 0 ]; then
    [ -n "$PROMPT_FILE" ] || die "--prompt-file is required (unless --dry-run)"
    [ -f "$PROMPT_FILE" ] || die "--prompt-file not found: $PROMPT_FILE"
    [ -f "$CHEVAL" ] || die "cheval.py not found at $CHEVAL"
fi

IFS=',' read -ra TIER_ARR <<< "$TIERS"
[ "${#TIER_ARR[@]}" -ge 1 ] || die "--tiers must list at least one tier"
for t in "${TIER_ARR[@]}"; do
    case "$t" in
        advisor|executor) ;;
        *) die "--tiers entries must be advisor|executor (got '$t')" ;;
    esac
done

mkdir -p "$OUTPUT_DIR"

# -----------------------------------------------------------------------------
# classify_replay_outcome — duplicated (in spirit) from advisor-benchmark.sh
# T2.E. Pure jq over a MODELINV manifest jsonl. Not sourced: the parent script
# is signature-gated + runs main at file scope (see header).
#   OK              — >=1 envelope with a non-empty models_succeeded
#   OK-with-fallback— succeeded AND >=1 models_failed (chain walked)
#   INCONCLUSIVE    — no successes / manifest absent
#   EXCLUDED        — operator interrupt (excluded_flag=1)
# -----------------------------------------------------------------------------
classify_replay_outcome() {
    local manifest="$1"
    local excluded_flag="${2:-0}"
    if [ "$excluded_flag" -eq 1 ]; then
        echo "EXCLUDED"; return 0
    fi
    if [ ! -f "$manifest" ]; then
        echo "INCONCLUSIVE"; return 0
    fi
    local succ failed
    succ="$(jq -s '[.[] | (.payload // .) | select((.models_succeeded // []) | length > 0)] | length' "$manifest" 2>/dev/null || echo 0)"
    failed="$(jq -s '[.[] | (.payload // .) | select((.models_failed // []) | length > 0)] | length' "$manifest" 2>/dev/null || echo 0)"
    if [ "$succ" -eq 0 ]; then
        echo "INCONCLUSIVE"; return 0
    fi
    if [ "$failed" -gt 0 ]; then
        echo "OK-with-fallback"; return 0
    fi
    echo "OK"
}

# -----------------------------------------------------------------------------
# resolve_tier_model — read advisor_strategy.tier_aliases.<tier>.<provider>.
# -----------------------------------------------------------------------------
resolve_tier_model() {
    local tier="$1"
    local model
    model="$(yq -r ".advisor_strategy.tier_aliases.${tier}.${PROVIDER} // \"\"" "$CONFIG_FILE" 2>/dev/null)"
    if [ -z "$model" ] || [ "$model" = "null" ]; then
        die "no tier_alias for advisor_strategy.tier_aliases.${tier}.${PROVIDER} in $CONFIG_FILE"
    fi
    # Emit provider:model-id form. tier_aliases store bare model-ids, but
    # cheval --model wants an alias OR provider:model-id; not every tier value
    # is a registered alias (e.g. claude-sonnet-4-6's alias is 'cheap'), so the
    # qualified form is the portable choice.
    echo "${PROVIDER}:${model}"
}

# -----------------------------------------------------------------------------
# cost pre-estimate — lighter reuse of advisor-benchmark.sh's shape. Reads
# .run/historical-medians.json (CODEOWNERS-gated) if present; defensive
# defaults otherwise. NFR-P3 / ATK-A6 honesty: DISCLOSE when no medians exist.
# -----------------------------------------------------------------------------
estimate_cost_micro() {
    local trial_count="$1"
    local medians_file="${LOA_HISTORICAL_MEDIANS_PATH:-$REPO_ROOT/.run/historical-medians.json}"
    if [ ! -f "$medians_file" ]; then
        echo "0"; return 0
    fi
    local mi mo ip op
    mi="$(jq -r '.median_input_tokens // 5000' "$medians_file" 2>/dev/null)"
    mo="$(jq -r '.median_output_tokens // 2000' "$medians_file" 2>/dev/null)"
    ip="$(jq -r '.median_input_per_mtok // 10000000' "$medians_file" 2>/dev/null)"
    op="$(jq -r '.median_output_per_mtok // 30000000' "$medians_file" 2>/dev/null)"
    LOA_N="$trial_count" LOA_IN="$mi" LOA_OUT="$mo" LOA_IP="$ip" LOA_OP="$op" \
    python3 - <<'PY'
import os
n=int(os.environ["LOA_N"]); inp=int(os.environ["LOA_IN"]); out=int(os.environ["LOA_OUT"])
ip=int(os.environ["LOA_IP"]); op=int(os.environ["LOA_OP"])
print(n * (inp*ip + out*op) // 1_000_000)
PY
}

pre_estimate_or_abort() {
    local trial_count="$1"
    if [ "$COST_CAP_ENABLED" -eq 0 ]; then
        echo "[stage-tier-benchmark] cost-cap pre-estimate disabled (--no-cost-cap)" >&2
        return 0
    fi
    local micro
    micro="$(estimate_cost_micro "$trial_count")"
    if [ "$micro" -eq 0 ]; then
        echo "[stage-tier-benchmark] WARN: no .run/historical-medians.json — cost pre-estimate unavailable (coverage 0%); proceeding under --cost-cap-usd ${COST_CAP_USD} without a numeric estimate." >&2
        return 0
    fi
    local usd cap_micro
    usd="$(awk "BEGIN{printf \"%.2f\", $micro/1000000}")"
    cap_micro="$(LOA_C="$COST_CAP_USD" python3 -c 'import os; print(int(float(os.environ["LOA_C"])*1_000_000))')"
    echo "[stage-tier-benchmark] pre-estimate: ${usd} USD for ${trial_count} calls (cap: ${COST_CAP_USD} USD)" >&2
    if [ "$micro" -gt "$cap_micro" ]; then
        echo "[stage-tier-benchmark] ABORT: estimate ${usd} USD exceeds cap ${COST_CAP_USD} USD. Raise --cost-cap-usd or lower --trials-per-tier." >&2
        exit 78
    fi
}

# -----------------------------------------------------------------------------
# run_one_trial — invoke cheval once for (tier, idx). Returns outcome via stdout;
# writes the score (or "null") to the file named by $2.
# -----------------------------------------------------------------------------
run_one_trial() {
    local model="$1"
    local score_out="$2"
    local manifest out_file exit_code=0
    manifest="$(mktemp)"
    out_file="$(mktemp)"
    LOA_MODELINV_LOG_PATH="$manifest" \
        python3 "$CHEVAL" \
            --agent "$AGENT" \
            --skill "$SKILL" \
            --model "$model" \
            --input "$PROMPT_FILE" \
            --output-format json \
            --json-errors \
            --timeout "$TIMEOUT" \
            > "$out_file" 2>/dev/null || exit_code=$?

    local outcome
    outcome="$(classify_replay_outcome "$manifest" 0)"
    if [ "$exit_code" -ne 0 ] && [ "$outcome" = "OK" ]; then
        outcome="OK-with-fallback"
    fi

    local score="null"
    if [ -n "$SCORE_CMD" ] && [ "$outcome" != "INCONCLUSIVE" ]; then
        local s
        s="$(eval "$SCORE_CMD \"$out_file\"" 2>/dev/null || echo "")"
        case "$s" in
            ''|*[!0-9.]*) score="null" ;;
            *) score="$s" ;;
        esac
    fi
    printf '%s' "$score" > "$score_out"
    rm -f "$manifest" "$out_file"
    echo "$outcome"
}

# --- Main --------------------------------------------------------------------
total=$(( ${#TIER_ARR[@]} * TRIALS_PER_TIER ))
echo "[stage-tier-benchmark] planning: ${#TIER_ARR[@]} tiers × $TRIALS_PER_TIER trials = $total calls (agent=$AGENT skill=$SKILL)" >&2

pre_estimate_or_abort "$total"

outcomes_log="$OUTPUT_DIR/outcomes.jsonl"
: > "$outcomes_log"

for tier in "${TIER_ARR[@]}"; do
    model=""
    [ "$DRY_RUN" -eq 0 ] && model="$(resolve_tier_model "$tier")"
    for idx in $(seq 1 "$TRIALS_PER_TIER"); do
        if [ "$DRY_RUN" -eq 1 ]; then
            outcome="OK"
            score="null"
        else
            score_file="$(mktemp)"
            outcome="$(run_one_trial "$model" "$score_file")"
            score="$(cat "$score_file")"
            rm -f "$score_file"
        fi
        if [ "$score" = "null" ] || [ -z "$score" ]; then
            jq -cn --arg b "$BATCH_ID" --arg tier "$tier" --arg idx "$idx" \
                  --arg outcome "$outcome" --arg stratum "$STRATUM" \
                  '{sprint_sha:$b, tier:$tier, idx:($idx|tonumber), score:null, outcome:$outcome, stratum:$stratum}' \
                  >> "$outcomes_log"
        else
            jq -cn --arg b "$BATCH_ID" --arg tier "$tier" --arg idx "$idx" \
                  --argjson score "$score" \
                  --arg outcome "$outcome" --arg stratum "$STRATUM" \
                  '{sprint_sha:$b, tier:$tier, idx:($idx|tonumber), score:$score, outcome:$outcome, stratum:$stratum}' \
                  >> "$outcomes_log"
        fi
    done
done

echo "[stage-tier-benchmark] done; outcomes recorded at $outcomes_log" >&2
