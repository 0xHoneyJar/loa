#!/usr/bin/env bash
# =============================================================================
# ab-pass5.sh — per-run ALTERNATING old-vs-new benchmark for pass-5 targets
# =============================================================================
# Per-run alternation (old,new,old,new,…) neutralizes the powersave-governor
# drift that pass 3 documented. Requires bash >= 5 ($EPOCHREALTIME).
# Output: TSV rows  label<TAB>side<TAB>runs<TAB>min_ms<TAB>mean_ms<TAB>p95_ms
# =============================================================================
set -u
export LC_ALL=C

REPO=/home/merlin/Documents/thj/code/loa
MIR=/tmp/loa-pass5/mirror
FX=/tmp/loa-pass5/fx
TSV="${1:-$REPO/grimoires/loa/perf/skill-loop-2026-07-05/ab-pass5.tsv}"
RUNS="${AB_RUNS:-20}"

declare -A SAMPLES_old SAMPLES_new

_now_us() { local t=${EPOCHREALTIME/./}; printf '%s' "$t"; }

# time one invocation; append to SAMPLES_<side>[label]
_time_one() { # <side> <label> <cmd...>
  local side="$1" label="$2"; shift 2
  local t0 t1
  t0=$(_now_us)
  "$@" >/dev/null 2>&1
  t1=$(_now_us)
  local d=$((t1 - t0))
  if [[ "$side" == old ]]; then
    SAMPLES_old[$label]="${SAMPLES_old[$label]:-} $d"
  else
    SAMPLES_new[$label]="${SAMPLES_new[$label]:-} $d"
  fi
}

report() { # <label>
  local label="$1" side
  for side in old new; do
    local raw
    if [[ "$side" == old ]]; then raw="${SAMPLES_old[$label]}"; else raw="${SAMPLES_new[$label]}"; fi
    # shellcheck disable=SC2086
    printf '%s\n' $raw | sort -n | awk -v L="$label" -v S="$side" -v T="$TSV" '
      { v[NR]=$1; sum+=$1 }
      END {
        p95i = int((NR*95 + 99) / 100); if (p95i < 1) p95i = 1; if (p95i > NR) p95i = NR
        printf "%-26s %-4s runs=%d min=%7.2f mean=%7.2f p95=%7.2f (ms)\n", L, S, NR, v[1]/1000, sum/NR/1000, v[p95i]/1000
        printf "%s\t%s\t%d\t%.2f\t%.2f\t%.2f\n", L, S, NR, v[1]/1000, sum/NR/1000, v[p95i]/1000 >> T
      }'
  done
}

ab() { # <label> <warmups> -- <old-cmd...> ++ <new-cmd...>
  local label="$1" warm="$2"; shift 2
  [[ "$1" == "--" ]] && shift
  local old_cmd=() new_cmd=() in_new=0 a
  for a in "$@"; do
    if [[ "$a" == "++" ]]; then in_new=1; continue; fi
    if (( in_new )); then new_cmd+=("$a"); else old_cmd+=("$a"); fi
  done
  local i
  for ((i=0;i<warm;i++)); do "${old_cmd[@]}" >/dev/null 2>&1; "${new_cmd[@]}" >/dev/null 2>&1; done
  for ((i=0;i<RUNS;i++)); do
    _time_one old "$label" "${old_cmd[@]}"
    _time_one new "$label" "${new_cmd[@]}"
  done
  report "$label"
}

: > /dev/null
mkdir -p "$(dirname "$TSV")"

# --- fixtures for check-updates bench (fresh cache, update available) ---
CU_CACHE_DIR=$FX/ab-cu-cache
mkdir -p "$CU_CACHE_DIR"
printf '%s\n' '{"last_check":"2026-07-05T03:00:50Z","local_version":"v1.180.0","remote_version":"v1.182.0","remote_url":"https://github.com/0xHoneyJar/loa/releases/tag/v1.182.0","update_available":true,"is_major_update":false,"ttl_hours":24}' > "$CU_CACHE_DIR/update-check.json"

cd "$REPO"

ab bh-quick-json 3 -- \
  env PROJECT_ROOT="$REPO" bash "$MIR/old/.claude/scripts/beads/beads-health.sh" --quick --json ++ \
  env PROJECT_ROOT="$REPO" bash "$MIR/new/.claude/scripts/beads/beads-health.sh" --quick --json

ab bh-full-json 2 -- \
  env PROJECT_ROOT="$REPO" bash "$MIR/old/.claude/scripts/beads/beads-health.sh" --json ++ \
  env PROJECT_ROOT="$REPO" bash "$MIR/new/.claude/scripts/beads/beads-health.sh" --json

# check-updates derives PROJECT_ROOT from its own location — give both mirror
# roots the REAL repo's config + version file so the bench exercises the true
# fresh-cache hot path (yq config read + jq version read + cache read).
for _side in old new; do
  cp "$REPO/.loa.config.yaml" "$MIR/$_side/.loa.config.yaml"
  cp "$REPO/.loa-version.json" "$MIR/$_side/.loa-version.json"
done

ab cu-notify-freshcache 3 -- \
  env LOA_CACHE_DIR="$CU_CACHE_DIR" bash "$MIR/old/.claude/scripts/check-updates.sh" --notify ++ \
  env LOA_CACHE_DIR="$CU_CACHE_DIR" bash "$MIR/new/.claude/scripts/check-updates.sh" --notify

ab gp-source 3 -- \
  env PROJECT_ROOT="$REPO" bash -c "source '$MIR/old/.claude/scripts/golden-path.sh'" ++ \
  env PROJECT_ROOT="$REPO" bash -c "source '$MIR/new/.claude/scripts/golden-path.sh'"

echo "TSV appended to $TSV"
