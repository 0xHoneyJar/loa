#!/usr/bin/env bash
# =============================================================================
# tools/advisor-benchmark.sh — cycle-108 sprint-2 T2.A + T2.C + T2.D + T2.E
# =============================================================================
# Worktree-hermetic benchmark harness for the cycle-108 advisor-strategy
# replay study. SDD §5.1 / §5.2 / §5.6 / §5.7 / §5.8.
#
# Lifecycle per replay:
#   1. git worktree add /tmp/loa-advisor-replay-<id> <pre_sha>
#   2. harness_symlink_scan + harness_fs_snapshot_pre (T1.E)
#   3. Optional cost-cap pre-estimate (T2.D)
#   4. LOA_REPLAY_CONTEXT=1 + LOA_NETWORK_RESTRICTED=1 + sourced
#      cheval-network-guard.sh in replay subshell
#   5. Execute the replay command (caller-supplied)
#   6. harness_fs_snapshot_post + harness_symlink_scan (re-verify)
#   7. classify_replay_outcome (T2.E)
#   8. Emit per-replay manifest JSON
#   9. git worktree remove (or schedule cleanup; daily cleaner lives at
#      tools/cron.d/cleanup-advisor-replays.sh — operator installs via crontab).
#
# Usage:
#   advisor-benchmark.sh --sprints <comma-list> [options]
#   advisor-benchmark.sh --selection-manifest <path> [options]
#   advisor-benchmark.sh --dry-run [...]
#
# Options:
#   --mode fresh-run|recorded-replay  (T2.C; default fresh-run)
#   --cost-cap-usd N                  (T2.D; default 50)
#   --no-cost-cap                     (skip pre-estimate)
#   --replays-per-tier N              (default 3 per stratum × tier)
#   --output-dir <path>               (default replay-manifests/)
#   --cleanup-strategy keep|defer|now (default defer)
#
# Exit codes:
#   0 — all replays completed (regardless of pass/fail outcome)
#   2 — invalid arguments
#   3 — git diff failed / pre-sha resolution failed
#   78 — cost-cap exceeded
# =============================================================================

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/.claude/scripts"
LIB_DIR="$REPO_ROOT/.claude/scripts/lib"

# -----------------------------------------------------------------------------
# Defaults.
# -----------------------------------------------------------------------------
MODE="fresh-run"
COST_CAP_USD=50
COST_CAP_ENABLED=1
REPLAYS_PER_TIER=3
OUTPUT_DIR="$REPO_ROOT/replay-manifests"
CLEANUP_STRATEGY="defer"
SPRINTS_LIST=""
SELECTION_MANIFEST=""
DRY_RUN=0
REPLAY_CMD=""

# -----------------------------------------------------------------------------
# CLI.
# -----------------------------------------------------------------------------
while [ "$#" -gt 0 ]; do
    case "$1" in
        --sprints)            SPRINTS_LIST="$2"; shift 2 ;;
        --selection-manifest) SELECTION_MANIFEST="$2"; shift 2 ;;
        --mode)               MODE="$2"; shift 2 ;;
        --cost-cap-usd)       COST_CAP_USD="$2"; shift 2 ;;
        --no-cost-cap)        COST_CAP_ENABLED=0; shift ;;
        --replays-per-tier)   REPLAYS_PER_TIER="$2"; shift 2 ;;
        --output-dir)         OUTPUT_DIR="$2"; shift 2 ;;
        --cleanup-strategy)   CLEANUP_STRATEGY="$2"; shift 2 ;;
        --dry-run)            DRY_RUN=1; shift ;;
        --replay-cmd)         REPLAY_CMD="$2"; shift 2 ;;
        --help|-h)
            sed -n '/^# tools\/advisor-benchmark.sh/,/^# ====/p' "$0" | sed 's/^# \{0,1\}//; /^=====/d'
            exit 0
            ;;
        *) echo "error: unknown flag $1" >&2; exit 2 ;;
    esac
done

case "$MODE" in
    fresh-run|recorded-replay) ;;
    *) echo "error: --mode must be fresh-run|recorded-replay (got: $MODE)" >&2; exit 2 ;;
esac
case "$CLEANUP_STRATEGY" in
    keep|defer|now) ;;
    *) echo "error: --cleanup-strategy must be keep|defer|now" >&2; exit 2 ;;
esac

if [ -z "$SPRINTS_LIST" ] && [ -z "$SELECTION_MANIFEST" ]; then
    echo "error: --sprints or --selection-manifest required" >&2
    exit 2
fi

mkdir -p "$OUTPUT_DIR"


# -----------------------------------------------------------------------------
# T2.E — classify_replay_outcome <manifest_jsonl>
#
# Classifies a per-replay outcome based on MODELINV envelopes emitted during
# that replay. Returns one of: OK / OK-with-fallback / INCONCLUSIVE / EXCLUDED.
#
# Rules (per FR-4 IMP-013):
#   OK              — at least one envelope with models_succeeded non-empty
#                     AND no models_failed entries
#   OK-with-fallback— models_succeeded non-empty BUT len(models_failed)>0
#                     (within-company chain walked)
#   INCONCLUSIVE    — all chain entries returned errors (chain exhausted);
#                     replay is dropped from aggregate
#   EXCLUDED        — operator interrupt (signal trap fired)
# -----------------------------------------------------------------------------
classify_replay_outcome() {
    local manifest="$1"
    local excluded_flag="${2:-0}"
    if [ "$excluded_flag" -eq 1 ]; then
        echo "EXCLUDED"
        return 0
    fi
    if [ ! -f "$manifest" ]; then
        echo "INCONCLUSIVE"
        return 0
    fi
    # Tally envelope outcomes.
    local succ failed
    succ="$(jq -s '[.[] | select(.payload.models_succeeded | length > 0)] | length' "$manifest" 2>/dev/null || echo 0)"
    failed="$(jq -s '[.[] | select((.payload.models_failed // []) | length > 0)] | length' "$manifest" 2>/dev/null || echo 0)"
    if [ "$succ" -eq 0 ]; then
        echo "INCONCLUSIVE"
        return 0
    fi
    if [ "$failed" -gt 0 ]; then
        echo "OK-with-fallback"
        return 0
    fi
    echo "OK"
}


# -----------------------------------------------------------------------------
# T2.D — cost-cap pre-estimate (SDD §20.10 ATK-A6, NFR-P3).
#
# Reads .run/historical-medians.json (computed by T2.F rollup tool) and
# computes sum(median_tokens × pricing_per_mtok) over planned replays.
# Aborts BEFORE any replay if estimate exceeds --cost-cap-usd.
# -----------------------------------------------------------------------------
estimate_cost_usd() {
    local replay_count="$1"
    local medians_file="$REPO_ROOT/.run/historical-medians.json"
    if [ ! -f "$medians_file" ]; then
        # No medians yet (Sprint 2 pre-data) — skip estimate with WARN.
        echo "0" # micro-USD
        return 0
    fi
    # Conservative default: use median input+output tokens × median pricing.
    # The medians file's exact schema is set by T2.F; we read defensively.
    local median_input median_output median_input_price median_output_price
    median_input="$(jq -r '.median_input_tokens // 5000' "$medians_file" 2>/dev/null)"
    median_output="$(jq -r '.median_output_tokens // 2000' "$medians_file" 2>/dev/null)"
    median_input_price="$(jq -r '.median_input_per_mtok // 10000000' "$medians_file" 2>/dev/null)"
    median_output_price="$(jq -r '.median_output_per_mtok // 30000000' "$medians_file" 2>/dev/null)"
    # cost_micro = replays × (input × in_price + output × out_price) / 1_000_000
    python3 -c "
import sys
n = int('$replay_count')
inp = int('$median_input'); out = int('$median_output')
ip = int('$median_input_price'); op = int('$median_output_price')
micro = n * (inp * ip + out * op) // 1_000_000
print(micro)
"
}


pre_estimate_or_abort() {
    local replay_count="$1"
    if [ "$COST_CAP_ENABLED" -eq 0 ]; then
        echo "[advisor-benchmark] cost-cap pre-estimate disabled (--no-cost-cap)" >&2
        return 0
    fi
    local cost_micro
    cost_micro="$(estimate_cost_usd "$replay_count")"
    local cost_usd
    cost_usd="$(python3 -c "print(f'{int(\"$cost_micro\")/1_000_000:.2f}')")"
    local cap_micro
    cap_micro="$(python3 -c "print(int(${COST_CAP_USD} * 1_000_000))")"
    echo "[advisor-benchmark] pre-estimate: ${cost_usd} USD for $replay_count replays (cap: ${COST_CAP_USD} USD)" >&2
    # shellcheck disable=SC2086
    if [ "$cost_micro" -gt $cap_micro ]; then
        echo "[advisor-benchmark] ABORT: estimate $cost_usd USD exceeds cap ${COST_CAP_USD} USD." >&2
        echo "[advisor-benchmark] Raise --cost-cap-usd or reduce --replays-per-tier." >&2
        exit 78
    fi
}


# -----------------------------------------------------------------------------
# Per-replay setup + teardown.
# -----------------------------------------------------------------------------
setup_worktree() {
    local sprint_sha="$1"
    local tier="$2"
    local idx="$3"
    local id="${sprint_sha:0:8}-${tier}-${idx}"
    local wt="/tmp/loa-advisor-replay-${id}"
    if [ -e "$wt" ]; then
        echo "[advisor-benchmark] removing stale worktree: $wt" >&2
        git worktree remove --force "$wt" 2>/dev/null || true
    fi
    git -C "$REPO_ROOT" worktree add "$wt" "$sprint_sha" >/dev/null 2>&1 || {
        echo "[advisor-benchmark] ERROR: failed to create worktree at $wt (sprint_sha=$sprint_sha)" >&2
        return 3
    }
    printf '%s' "$wt"
}


cleanup_worktree() {
    local wt="$1"
    case "$CLEANUP_STRATEGY" in
        keep)
            echo "[advisor-benchmark] keep: worktree retained at $wt" >&2
            ;;
        defer)
            # The daily cron at .run/cron.d/cleanup-advisor-replays.sh removes
            # stale /tmp/loa-advisor-replay-* dirs older than 24h. Mark with
            # timestamp file so cron can identify.
            date -u +%s > "$wt/.cleanup-marker" 2>/dev/null || true
            ;;
        now)
            git -C "$REPO_ROOT" worktree remove --force "$wt" 2>/dev/null || true
            ;;
    esac
}


# -----------------------------------------------------------------------------
# Replay execution (single sprint × tier × idx).
# -----------------------------------------------------------------------------
run_one_replay() {
    local sprint_sha="$1"
    local tier="$2"
    local idx="$3"
    local replay_log_dir="$OUTPUT_DIR/${sprint_sha:0:8}-${tier}-${idx}"
    local replay_log="$replay_log_dir/model-invoke.jsonl"
    local manifest="$replay_log_dir/manifest.json"
    mkdir -p "$replay_log_dir"

    local wt
    wt="$(setup_worktree "$sprint_sha" "$tier" "$idx")"
    if [ -z "$wt" ] || [ ! -d "$wt" ]; then
        # Manifest records the failure but does not stop the batch.
        jq -n \
            --arg sprint "$sprint_sha" --arg tier "$tier" --arg idx "$idx" \
            --arg outcome "INCONCLUSIVE" --arg reason "worktree_setup_failed" \
            '{sprint_sha: $sprint, tier: $tier, idx: $idx, outcome: $outcome, reason: $reason}' \
            > "$manifest"
        return 1
    fi

    # Trap to ensure cleanup even on SIGINT.
    local excluded=0
    trap 'excluded=1' INT TERM
    trap "cleanup_worktree '$wt'" EXIT

    # FS-guard pre. The default protected paths include /tmp + /var/tmp, but
    # the harness ITSELF writes worktrees there. Switch FS-guard to EXCLUSIVE
    # mode and watch only the repo root + ~ (replay should never mutate either).
    local snapshot_pre
    snapshot_pre="$(mktemp)"
    if [ -f "$LIB_DIR/harness-fs-guard.sh" ]; then
        # shellcheck source=/dev/null
        set +u
        source "$LIB_DIR/harness-fs-guard.sh" 2>/dev/null || true
        set -u
        export LOA_HARNESS_FS_GUARD_EXCLUSIVE=1
        export LOA_HARNESS_FS_GUARD_EXTRA_PATHS="$REPO_ROOT/.claude:$REPO_ROOT/tools:$REPO_ROOT/grimoires"
        if declare -F harness_symlink_scan > /dev/null; then
            harness_symlink_scan "$wt" >&2 || true
        fi
        if declare -F harness_fs_snapshot_pre > /dev/null; then
            harness_fs_snapshot_pre "$snapshot_pre" >/dev/null 2>&1 || true
        fi
    fi

    # Network restriction + replay context env.
    export LOA_REPLAY_CONTEXT=1
    export LOA_NETWORK_RESTRICTED=1
    export LOA_MODELINV_LOG_PATH="$replay_log"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[advisor-benchmark] DRY-RUN: would execute replay (sprint=$sprint_sha tier=$tier idx=$idx, mode=$MODE, worktree=$wt)" >&2
    else
        if [ -z "$REPLAY_CMD" ]; then
            echo "[advisor-benchmark] WARN: --replay-cmd not supplied; recording an empty replay shell for substrate test." >&2
        else
            # Run the replay command inside the worktree with the guard sourced.
            (
                cd "$wt"
                set +u
                source "$LIB_DIR/cheval-network-guard.sh" 2>/dev/null || true
                set -u
                bash -c "$REPLAY_CMD"
            ) 2>&1 | tee "$replay_log_dir/stdout.log" >/dev/null
        fi
    fi

    # FS-guard post.
    if declare -F harness_fs_snapshot_post > /dev/null; then
        harness_fs_snapshot_post "$snapshot_pre" >&2 || true
    fi
    rm -f "$snapshot_pre"

    # Outcome classification.
    local outcome
    outcome="$(classify_replay_outcome "$replay_log" "$excluded")"

    # Emit per-replay manifest.
    jq -n \
        --arg sprint "$sprint_sha" --arg tier "$tier" --arg idx "$idx" \
        --arg outcome "$outcome" --arg mode "$MODE" \
        --arg worktree "$wt" --arg log "$replay_log" \
        --arg started_at "$(date -u +%FT%TZ)" \
        --argjson replay_marker true \
        '{
            sprint_sha: $sprint,
            tier: $tier,
            idx: $idx,
            outcome: $outcome,
            mode: $mode,
            worktree: $worktree,
            modelinv_log: $log,
            started_at: $started_at,
            replay_marker: $replay_marker
        }' > "$manifest"

    # Reset traps before returning so they don't fire in the caller.
    trap - INT TERM EXIT
    cleanup_worktree "$wt"

    echo "$outcome"
}


# -----------------------------------------------------------------------------
# Top-level orchestration.
# -----------------------------------------------------------------------------
expand_sprints() {
    if [ -n "$SELECTION_MANIFEST" ]; then
        # Read SHAs out of a selection manifest from T2.J's
        # tools/select-benchmark-sprints.py
        if [ ! -f "$SELECTION_MANIFEST" ]; then
            echo "error: --selection-manifest not found: $SELECTION_MANIFEST" >&2
            exit 2
        fi
        jq -r '[.selected[][].sha] | join(",")' "$SELECTION_MANIFEST"
    else
        printf '%s' "$SPRINTS_LIST"
    fi
}


main() {
    local sprints
    sprints="$(expand_sprints)"
    if [ -z "$sprints" ]; then
        echo "error: no sprints to replay" >&2
        exit 2
    fi
    # Convert comma-list to count.
    local count=0
    IFS=',' read -ra _arr <<< "$sprints"
    count="${#_arr[@]}"
    # Each sprint × 2 tiers (advisor / executor) × REPLAYS_PER_TIER.
    local total=$((count * 2 * REPLAYS_PER_TIER))

    echo "[advisor-benchmark] planning: $count sprints × 2 tiers × $REPLAYS_PER_TIER replays = $total replays" >&2

    pre_estimate_or_abort "$total"

    local outcomes_log="$OUTPUT_DIR/outcomes.jsonl"
    : > "$outcomes_log"

    for sprint in "${_arr[@]}"; do
        for tier in advisor executor; do
            for idx in $(seq 1 "$REPLAYS_PER_TIER"); do
                outcome="$(run_one_replay "$sprint" "$tier" "$idx" || true)"
                jq -n \
                    --arg sprint "$sprint" --arg tier "$tier" --arg idx "$idx" \
                    --arg outcome "$outcome" \
                    '{sprint_sha: $sprint, tier: $tier, idx: ($idx|tonumber), outcome: $outcome}' \
                    >> "$outcomes_log"
            done
        done
    done

    echo "[advisor-benchmark] done; outcomes recorded at $outcomes_log" >&2
}


main
