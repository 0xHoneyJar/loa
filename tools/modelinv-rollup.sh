#!/usr/bin/env bash
# =============================================================================
# tools/modelinv-rollup.sh — cycle-108 sprint-2 T2.F + T2.G + T2.H + T2.K
# =============================================================================
# PRD §5 FR-5, SDD §6 / §6.2 / §20.4 / §20.10.
#
# Reads .run/model-invoke.jsonl (READ-ONLY — never mutates the audit log) and
# emits a grouped cost rollup as JSON + Markdown. Performs hash-chain integrity
# verification BEFORE any aggregation (T2.G fail-closed) and strip-attack
# detection on the MODELINV v1.2 cutoff (T2.H).
#
# Reads pricing FROM envelopes (payload.pricing_snapshot) — NOT from current
# model-config.yaml — so historical pricing changes don't retroactively
# rewrite cost reports (T2.J / SDD §20.9 ATK-A20).
#
# Default behavior EXCLUDES envelopes marked payload.replay_marker:true
# (T2.K / SDD §20.10 ATK-A15). Opt in with --include-replays.
#
# Usage:
#   modelinv-rollup.sh [--per-cycle] [--per-skill] [--per-role] [--per-tier]
#                      [--per-model] [--per-stratum] [--last-90-days]
#                      [--last-N-days N] [--include-replays]
#                      [--input PATH] [--output-json PATH] [--output-md PATH]
#                      [--no-chain-verify] [--no-strip-detect]
#                      [--require-signed]
#
# Exit codes:
#   0 — success
#   1 — chain validation failed / strip-attack detected
#   2 — missing input / argument error
#   78 — strip-attack detected (when --strict-strip)
# =============================================================================

set -uo pipefail

_USAGE() {
    sed -n '/^# tools\/modelinv-rollup.sh/,/^# ====/p' "$0" | sed 's/^# \{0,1\}//; /^=====/d'
}

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$REPO_ROOT/.claude/scripts"

# Defaults.
INPUT_PATH="$REPO_ROOT/.run/model-invoke.jsonl"
OUTPUT_JSON=""
OUTPUT_MD=""
GROUP_FIELDS=()
DAYS_WINDOW=0          # 0 = no window
INCLUDE_REPLAYS=0
CHAIN_VERIFY=1
STRIP_DETECT=1
STRICT_STRIP=0
REQUIRE_SIGNED=0

PER_SKILL_DAILY_QUOTA=0  # T4.D sprint-4: emit alert when any skill exceeds this on a day

while [ "$#" -gt 0 ]; do
    case "$1" in
        --per-cycle)     GROUP_FIELDS+=("cycle_id");      shift ;;
        --per-skill)     GROUP_FIELDS+=("skill");         shift ;;
        --per-role)      GROUP_FIELDS+=("role");          shift ;;
        --per-tier)      GROUP_FIELDS+=("tier");          shift ;;
        --per-model)     GROUP_FIELDS+=("final_model_id");shift ;;
        --per-stratum)   GROUP_FIELDS+=("sprint_kind");   shift ;;
        --last-90-days)  DAYS_WINDOW=90; shift ;;
        --last-N-days)   DAYS_WINDOW="$2"; shift 2 ;;
        --include-replays) INCLUDE_REPLAYS=1; shift ;;
        --input)         INPUT_PATH="$2"; shift 2 ;;
        --output-json)   OUTPUT_JSON="$2"; shift 2 ;;
        --output-md)     OUTPUT_MD="$2"; shift 2 ;;
        --no-chain-verify) CHAIN_VERIFY=0; shift ;;
        --no-strip-detect) STRIP_DETECT=0; shift ;;
        --strict-strip)  STRICT_STRIP=1; shift ;;
        --require-signed) REQUIRE_SIGNED=1; shift ;;
        --per-skill-daily-quota) PER_SKILL_DAILY_QUOTA="$2"; shift 2 ;;
        --help|-h)       _USAGE; exit 0 ;;
        *)               echo "error: unknown flag $1" >&2; _USAGE >&2; exit 2 ;;
    esac
done

# Default group-by if no flags supplied: per-model (closest analog to legacy
# cost-report.sh).
if [ "${#GROUP_FIELDS[@]}" -eq 0 ]; then
    GROUP_FIELDS+=("final_model_id")
fi

if [ ! -f "$INPUT_PATH" ]; then
    echo "error: input log not found: $INPUT_PATH" >&2
    exit 2
fi

# -----------------------------------------------------------------------------
# T2.G — Hash-chain fail-closed integrity check.
# -----------------------------------------------------------------------------
if [ "$CHAIN_VERIFY" -eq 1 ]; then
    if [ -f "$SCRIPT_DIR/audit-envelope.sh" ]; then
        # Source in a "non-strict" inner subshell so audit-envelope.sh's
        # internal Python heredocs and BASH_SOURCE handling don't trip
        # `set -u` in this script. We run the verification in a child bash
        # process so any internal `set -e` doesn't propagate, and emit a
        # marker line to stderr that the parent grep-parses.
        # BB iter-6 F002 closure: capture audit_verify_chain's stderr to a
        # separate file inside the subshell + replay on FAIL. The prior
        # `( source ...; audit_verify_chain ... >&2 ) || marker=FAIL` pattern
        # let the underlying error message reach stderr but operators couldn't
        # tell post-hoc whether the failure was "envelope N hash mismatch"
        # vs "audit-envelope.sh failed to source". Stderr is now teed into
        # an operator-readable diagnostic file, replayed on FAIL.
        verify_marker_file="$(mktemp)"
        verify_diag_file="$(mktemp)"
        (
            set +u
            # shellcheck source=/dev/null
            if ! source "$SCRIPT_DIR/audit-envelope.sh" 2> "$verify_diag_file"; then
                printf 'SOURCE-FAILED\n' > "$verify_marker_file"
                exit 0
            fi
            if ! audit_verify_chain "$INPUT_PATH" 2>> "$verify_diag_file"; then
                printf 'FAIL\n' > "$verify_marker_file"
            else
                printf 'OK\n' > "$verify_marker_file"
            fi
        )
        verify_status="$(cat "$verify_marker_file" 2>/dev/null)"
        rm -f "$verify_marker_file"
        if [ "$verify_status" != "OK" ]; then
            echo "[CHAIN-VERIFY-FAILED] $INPUT_PATH (status=$verify_status)" >&2
            if [ -s "$verify_diag_file" ]; then
                echo "[CHAIN-VERIFY-DIAGNOSTIC] underlying error:" >&2
                cat "$verify_diag_file" >&2
            fi
            echo "Recovery: see grimoires/loa/runbooks/advisor-strategy-rollback.md (audit_recover_chain)." >&2
            rm -f "$verify_diag_file"
            exit 1
        fi
        rm -f "$verify_diag_file"
    else
        echo "warning: audit-envelope.sh not found at $SCRIPT_DIR; chain verification SKIPPED" >&2
    fi
fi

# -----------------------------------------------------------------------------
# Pre-pass: T2.H strip-attack detection.
#
# Records the cutoff timestamp = ts_utc of the first envelope with
# payload.writer_version=="1.2". Entries AFTER cutoff lacking writer_version
# (or with a value != "1.2") trigger [STRIP-ATTACK-DETECTED].
# -----------------------------------------------------------------------------
if [ "$STRIP_DETECT" -eq 1 ]; then
    cutoff_ts="$(jq -r 'select(.payload.writer_version == "1.2") | .ts_utc' "$INPUT_PATH" \
        2>/dev/null | head -1)"
    if [ -n "$cutoff_ts" ]; then
        # cycle-109 Sprint 5 T5.3 (#870): single-pass jq replaces the prior
        # awk+while+per-line-jq pipeline that spawned 2N subprocesses for
        # N envelopes. The awk prefix attaches NR (line number) with a TAB
        # separator before each non-skipped line; jq -R -r processes each
        # line once, parses the JSON, and emits violation strings. Tabs
        # never appear literally in serialized JSON (they're escaped to
        # \t), so split("\t") is safe. Measured ~11s → <200ms on 1001
        # envelopes (per tests/unit/cycle-109-t5-3-modelinv-rollup-perf.bats).
        strip_violations="$(awk '
            /^\[/ { next }
            NF == 0 { next }
            { printf "%d\t%s\n", NR, $0 }
        ' "$INPUT_PATH" | jq -R -r --arg cutoff "$cutoff_ts" '
            (split("\t") | {n: .[0] | tonumber, rest: .[1:] | join("\t")}) as $r |
            ($r.rest | fromjson? // null) as $env |
            select($env != null and ($env.ts_utc // "") != "") |
            select(($env.ts_utc >= $cutoff) and (($env.payload.writer_version // "") != "1.2")) |
            "line \($r.n): ts=\($env.ts_utc) writer_version=\($env.payload.writer_version // "MISSING")"
        ' 2>/dev/null)"
        if [ -n "$strip_violations" ]; then
            echo "[STRIP-ATTACK-DETECTED] cutoff=$cutoff_ts; post-cutoff entries lack writer_version=1.2:" >&2
            printf '%s\n' "$strip_violations" >&2
            if [ "$STRICT_STRIP" -eq 1 ]; then
                exit 78
            else
                exit 1
            fi
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Aggregation pass.
# -----------------------------------------------------------------------------
# Build a jq filter that:
#   1. Excludes seal markers (already filtered by jq —r on JSON parse)
#   2. Skips replay-marker envelopes unless --include-replays
#   3. Applies --last-N-days window via ts_utc
#   4. Extracts grouping fields + pricing_snapshot + cost_micro_usd
#   5. Aggregates by composite group key
#
# Pricing FROM envelope; if absent, count tokens but emit
# warning that envelope predates T2.J pricing capture.
# -----------------------------------------------------------------------------

# Build "select" predicate for replay exclusion.
if [ "$INCLUDE_REPLAYS" -eq 1 ]; then
    replay_pred='true'
else
    replay_pred='(.payload.replay_marker // false) != true'
fi

# Compute cutoff_ts_window for --last-N-days (if requested).
if [ "$DAYS_WINDOW" -gt 0 ]; then
    if command -v gdate >/dev/null 2>&1; then
        window_cutoff="$(gdate -u -d "$DAYS_WINDOW days ago" +%FT%TZ)"
    else
        window_cutoff="$(date -u -d "$DAYS_WINDOW days ago" +%FT%TZ 2>/dev/null || \
            date -u -v "-${DAYS_WINDOW}d" +%FT%TZ)"
    fi
else
    window_cutoff="1970-01-01T00:00:00Z"
fi

# Build a jq expression that produces the group-key array for one envelope.
# `_gk` is the array of grouping-field values (each null-coerced to "unknown").
group_keys_jq=""
for field in "${GROUP_FIELDS[@]}"; do
    case "$field" in
        cycle_id)        group_keys_jq+=' (.payload.cycle_id // "unknown"),' ;;
        skill)           group_keys_jq+=' (.payload.calling_primitive // "unknown"),' ;;
        role)            group_keys_jq+=' (.payload.role // "unknown"),' ;;
        tier)            group_keys_jq+=' (.payload.tier // "unknown"),' ;;
        final_model_id)  group_keys_jq+=' (.payload.final_model_id // "unknown"),' ;;
        sprint_kind)     group_keys_jq+=' (.payload.sprint_kind // "unknown"),' ;;
    esac
done
# Trim trailing comma.
group_keys_jq="${group_keys_jq%,}"

# Aggregation jq. We tag each envelope with `_gk` (group-key array) BEFORE
# group_by, so the per-group `map(...)` block can reference `.[0]._gk` to
# emit dimension labels without re-deriving them from `.payload.*`.
agg="$(jq -c -s \
    --arg window "$window_cutoff" \
    --arg group_fields "${GROUP_FIELDS[*]}" \
    "
    [.[] | select(type == \"object\") | select($replay_pred) | select(.ts_utc >= \$window)
       | . + { _gk: [ $group_keys_jq ] }
    ] as \$entries |
    \$entries
    | group_by(._gk)
    | map({
        group_key: (.[0]._gk | map(tostring) | join(\"|\")),
        group_dims: .[0]._gk,
        count: length,
        total_cost_micro_usd: (map(.payload.cost_micro_usd // 0) | add),
        envelopes_with_pricing: (map(select(.payload.pricing_snapshot)) | length),
        envelopes_with_writer_v12: (map(select(.payload.writer_version == \"1.2\")) | length),
        replay_count: (map(select(.payload.replay_marker == true)) | length),
        first_ts: (map(.ts_utc) | min),
        last_ts: (map(.ts_utc) | max)
    })
    | {
        generated_at: (now | strftime(\"%Y-%m-%dT%H:%M:%SZ\")),
        window: \$window,
        group_fields: (\$group_fields | split(\" \")),
        include_replays: ($INCLUDE_REPLAYS == 1),
        total_envelopes: (\$entries | length),
        groups: .
    }
    " "$INPUT_PATH")"

if [ -z "$agg" ]; then
    echo "error: jq aggregation failed" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# T4.D — Per-skill daily token quota alert.
# -----------------------------------------------------------------------------
if [ "$PER_SKILL_DAILY_QUOTA" -gt 0 ]; then
    quota_breaches="$(jq -c -s \
        --arg quota "$PER_SKILL_DAILY_QUOTA" \
        --argjson include_replays "$INCLUDE_REPLAYS" \
        '
        [.[] | select(type == "object")
            | select(($include_replays == 1) or ((.payload.replay_marker // false) != true))
            | {
                day: ((.ts_utc // "")[0:10]),
                skill: ((.payload.invocation_chain // []) | first // (.payload.calling_primitive // "unknown")),
                tokens: (
                    if (.payload.pricing_snapshot.input_per_mtok // 0) > 0
                       and (.payload.cost_micro_usd // 0) > 0
                    then ((.payload.cost_micro_usd * 1000000) / .payload.pricing_snapshot.input_per_mtok) | floor
                    else 0
                    end
                )
            }
            | select(.day != "" and .skill != "")
        ] | group_by([.day, .skill])
          | map({day: .[0].day, skill: .[0].skill, tokens_total: (map(.tokens // 0) | add)})
          | map(select(.tokens_total > ($quota | tonumber)))
        ' "$INPUT_PATH" 2>/dev/null)"
    if [ -n "$quota_breaches" ] && [ "$quota_breaches" != "[]" ]; then
        echo "[modelinv-rollup] QUOTA-ALERT: per-skill daily token quota exceeded ($PER_SKILL_DAILY_QUOTA):" >&2
        echo "$quota_breaches" | jq -r '.[] | "  - \(.day) \(.skill): \(.tokens_total) tokens"' >&2
    fi
fi

# Emit JSON (default to stdout if no --output-* flags).
if [ -n "$OUTPUT_JSON" ]; then
    mkdir -p "$(dirname "$OUTPUT_JSON")"
    printf '%s\n' "$agg" | jq . > "$OUTPUT_JSON"
elif [ -z "$OUTPUT_MD" ]; then
    printf '%s\n' "$agg" | jq .
fi

# Emit Markdown report.
if [ -n "$OUTPUT_MD" ]; then
    mkdir -p "$(dirname "$OUTPUT_MD")"
    {
        echo "# MODELINV cost rollup"
        echo
        echo "**Generated**: $(printf '%s' "$agg" | jq -r '.generated_at')"
        echo "**Window**: $(printf '%s' "$agg" | jq -r '.window') → present"
        echo "**Group fields**: $(printf '%s' "$agg" | jq -r '.group_fields | join(", ")')"
        echo "**Total envelopes**: $(printf '%s' "$agg" | jq -r '.total_envelopes')"
        echo "**Replays included**: $(printf '%s' "$agg" | jq -r '.include_replays')"
        echo
        echo "| Group | Count | Total cost (micro-USD) | First | Last | Pricing-pinned | v1.2-marked |"
        echo "| --- | --- | --- | --- | --- | --- | --- |"
        printf '%s' "$agg" | jq -r '.groups[] | "| \(.group_key) | \(.count) | \(.total_cost_micro_usd // 0) | \(.first_ts // "—") | \(.last_ts // "—") | \(.envelopes_with_pricing) | \(.envelopes_with_writer_v12) |"'
    } > "$OUTPUT_MD"
fi

exit 0
