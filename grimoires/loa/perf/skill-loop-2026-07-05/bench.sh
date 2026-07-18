#!/usr/bin/env bash
# =============================================================================
# bench.sh — reusable wall-time harness for Loa hook/script benchmarking
# =============================================================================
# Part of the extreme-software-optimization skill loop (pass 1 baseline,
# 2026-07-05). hyperfine is not installed on this host; this is a bash-loop
# timer using $EPOCHREALTIME (microsecond resolution, bash >= 5).
#
# Usage:
#   bench.sh [options] -- <command> [args...]
#
# Options:
#   --label NAME       Row label in output (default: command basename)
#   --payload FILE     File fed to the target's stdin on EVERY run (fresh fd
#                      per run — mirrors Claude Code hook stdin JSON payload).
#                      Default: /dev/null.
#   --cwd DIR          Working directory for the target (default: caller cwd)
#   --warmup N         Warmup runs, untimed (default 3, min 3)
#   --runs N           Measured runs (default 20, min 20 unless --allow-short)
#   --allow-short      Permit --runs < 20 (for slow / networked targets)
#   --env K=V          Export K=V for the target (repeatable)
#   --prep CMD         Shell command eval'd (untimed) before EVERY run,
#                      warmup and measured — use to reset consumed state
#                      (e.g. restore a fixture the target deletes/appends).
#   --timeout SECS     Per-run timeout via coreutils timeout (default: none)
#   --tsv FILE         Also append a machine-readable TSV row to FILE:
#                      label<TAB>runs<TAB>min_ms<TAB>mean_ms<TAB>p95_ms<TAB>max_ms<TAB>exit
#
# Measurement notes:
#   - LC_ALL=C is pinned (exported) for the harness AND the target, so
#     grep/sort/awk locale costs are deterministic across passes.
#   - Target stdout/stderr go to /dev/null (I/O to a terminal would dominate).
#   - Exit code reported is the mode across measured runs; "mixed" if unstable.
#   - p95 = value at ceil(0.95 * runs) in the sorted sample list.
# =============================================================================

set -euo pipefail
export LC_ALL=C

label="" payload="/dev/null" run_cwd="" warmup=3 runs=20 prep="" timeout_s="" tsv_file="" allow_short=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label)   label="$2"; shift 2 ;;
    --payload) payload="$2"; shift 2 ;;
    --cwd)     run_cwd="$2"; shift 2 ;;
    --warmup)  warmup="$2"; shift 2 ;;
    --runs)    runs="$2"; shift 2 ;;
    --allow-short) allow_short=1; shift ;;
    --env)     export "${2?}"; shift 2 ;;
    --prep)    prep="$2"; shift 2 ;;
    --timeout) timeout_s="$2"; shift 2 ;;
    --tsv)     tsv_file="$2"; shift 2 ;;
    --)        shift; break ;;
    *) echo "bench.sh: unknown option '$1'" >&2; exit 64 ;;
  esac
done

[[ $# -gt 0 ]] || { echo "bench.sh: no command given (use -- cmd args)" >&2; exit 64; }
cmd=( "$@" )
[[ -n "$label" ]] || label="$(basename "$1")"
[[ -r "$payload" ]] || { echo "bench.sh: payload '$payload' not readable" >&2; exit 66; }
if (( warmup < 3 )); then warmup=3; fi
if (( runs < 20 )) && (( allow_short == 0 )); then
  echo "bench.sh: --runs must be >= 20 (use --allow-short for slow targets)" >&2
  exit 64
fi
[[ -z "$run_cwd" ]] || cd "$run_cwd"

runner=( "${cmd[@]}" )
[[ -z "$timeout_s" ]] || runner=( timeout "$timeout_s" "${cmd[@]}" )

one_run() {  # -> sets global _rc; output discarded
  _rc=0
  "${runner[@]}" < "$payload" > /dev/null 2>&1 || _rc=$?
}

# --- warmup (untimed) --------------------------------------------------------
for (( i = 0; i < warmup; i++ )); do
  [[ -z "$prep" ]] || eval "$prep" > /dev/null 2>&1
  one_run
done

# --- measured runs -----------------------------------------------------------
samples=()
exits=()
for (( i = 0; i < runs; i++ )); do
  [[ -z "$prep" ]] || eval "$prep" > /dev/null 2>&1
  t0=$EPOCHREALTIME
  one_run
  t1=$EPOCHREALTIME
  exits+=( "$_rc" )
  samples+=( "$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", (b - a) * 1000 }')" )
done

# --- stats -------------------------------------------------------------------
sorted=$(printf '%s\n' "${samples[@]}" | sort -g)
read -r min_ms mean_ms p95_ms max_ms < <(printf '%s\n' "$sorted" | awk -v n="$runs" '
  { v[NR] = $1; sum += $1 }
  END {
    p95i = int(0.95 * n + 0.999999); if (p95i < 1) p95i = 1; if (p95i > n) p95i = n
    printf "%.3f %.3f %.3f %.3f\n", v[1], sum / n, v[p95i], v[n]
  }')

# Exit-code mode (hooks legitimately exit 2 on block — not a harness failure).
exit_mode=$(printf '%s\n' "${exits[@]}" | sort | uniq -c | sort -rn | awk 'NR==1{print $2}')
distinct_exits=$(printf '%s\n' "${exits[@]}" | sort -u | wc -l)
(( distinct_exits == 1 )) || exit_mode="mixed(${exit_mode})"

printf '%-42s runs=%-3d min=%8.3fms mean=%8.3fms p95=%8.3fms max=%8.3fms exit=%s\n' \
  "$label" "$runs" "$min_ms" "$mean_ms" "$p95_ms" "$max_ms" "$exit_mode"

if [[ -n "$tsv_file" ]]; then
  printf '%s\t%d\t%s\t%s\t%s\t%s\t%s\n' \
    "$label" "$runs" "$min_ms" "$mean_ms" "$p95_ms" "$max_ms" "$exit_mode" >> "$tsv_file"
fi
