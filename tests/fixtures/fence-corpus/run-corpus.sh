#!/usr/bin/env bash
# run-corpus.sh — replay tests/fixtures/fence-corpus/corpus.jsonl through the
# block-destructive-bash hook and summarise (cycle-125 Sprint 1, PRD FR-1).
#
# Usage: run-corpus.sh [--hook PATH] [--corpus PATH] [--json] [--knob-off] [--rows]
# Each row: {id, cmd, expect: allow|block|residual, rule, why, cwd: repo|tmp, env?: {TMPDIR}}
#   allow    → benign: the hook must exit 0
#   block    → dangerous: the hook must exit 2
#   residual → accepted false positive: counted, never gated
# --knob-off  writes destructive_command_guard.heredoc_classifier: false into the
#             replay root's .loa.config.yaml (cycle-129 FR-6: the pre-cycle scan);
#             compare it with the pre-change hook through --rows.
# --rows      prints "<id> <exit code>" per row instead of the summary (for diffs).
# Output (text): one line per mismatch, then
#   "benign P/T dangerous B/T residual R/T runtime_ms N p95_ms M";
# --json prints {benign_pass, benign_total, dangerous_block, dangerous_total,
#   residual_pass, residual_total, runtime_ms, p95_ms, rows, mismatches: [..]}.
# p95_ms is the 95th percentile of the per-row hook wall time (the hook process
# only; the jq row parsing is outside the timed span).
set -uo pipefail
export LC_ALL=C
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
hook="$root/.claude/hooks/safety/block-destructive-bash.sh"
corpus="$root/tests/fixtures/fence-corpus/corpus.jsonl"
json=0 knob_off=0 rows_out=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hook) hook="$2"; shift 2 ;;
    --corpus) corpus="$2"; shift 2 ;;
    --json) json=1; shift ;;
    --knob-off) knob_off=1; shift ;;
    --rows) rows_out=1; shift ;;
    *) echo "usage: run-corpus.sh [--hook PATH] [--corpus PATH] [--json] [--knob-off] [--rows]" >&2; exit 2 ;;
  esac
done
[[ -x "$hook" || -f "$hook" ]] || { echo "hook not found: $hook" >&2; exit 2; }
[[ -f "$corpus" ]] || { echo "corpus not found: $corpus" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
repo="$work/repo"; scratch="$work/scratch"
mkdir -p "$repo" "$scratch"
export LOA_REPO_ROOT="$work"
export LOA_AUDIT_REPLAY=1   # audit rows this replay writes carry replay: true (cycle-129 DEC-0167)
if (( knob_off )); then
  printf 'destructive_command_guard:\n  heredoc_classifier: false\n' > "$work/.loa.config.yaml"
fi

bp=0 bt=0 db=0 dt=0 rp=0 rt=0
mismatches=()
durations=()
# Microsecond clock: $EPOCHREALTIME (bash ≥ 5) everywhere; GNU date fallback.
now_us() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local s="${EPOCHREALTIME%.*}" us="${EPOCHREALTIME#*.}"
    echo $(( s * 1000000 + 10#${us:0:6} ))
  else
    echo $(( $(date +%s%N) / 1000 ))
  fi
}
start_us=$(now_us)
while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  id=$(jq -r '.id' <<<"$row"); cmd=$(jq -r '.cmd' <<<"$row"); expect=$(jq -r '.expect' <<<"$row")
  cwd=$(jq -r '.cwd // "repo"' <<<"$row"); tmpdir=$(jq -r '.env.TMPDIR // empty' <<<"$row")
  dir="$repo"; [[ "$cwd" == "tmp" ]] && dir="$scratch"
  payload=$(jq -cn --arg c "$cmd" '{tool_input: {command: $c}}')
  rc=0
  t0=$(now_us)
  if [[ -n "$tmpdir" ]]; then
    (cd "$dir" && TMPDIR="$tmpdir" bash "$hook" <<<"$payload" >/dev/null 2>&1) || rc=$?
  else
    (cd "$dir" && env -u TMPDIR bash "$hook" <<<"$payload" >/dev/null 2>&1) || rc=$?
  fi
  t1=$(now_us)
  durations+=("$(( (t1 - t0) / 1000 ))")
  (( rows_out )) && printf '%s %s\n' "$id" "$rc"
  case "$expect" in
    allow)    bt=$((bt+1)); if [[ $rc -eq 0 ]]; then bp=$((bp+1)); else mismatches+=("$id:expected-allow:rc=$rc"); fi ;;
    block)    dt=$((dt+1)); if [[ $rc -eq 2 ]]; then db=$((db+1)); else mismatches+=("$id:expected-block:rc=$rc"); fi ;;
    residual) rt=$((rt+1)); [[ $rc -eq 0 ]] && rp=$((rp+1)) ;;
    *) mismatches+=("$id:unknown-expect:$expect") ;;
  esac
done < "$corpus"
end_us=$(now_us)
runtime=$(( (end_us - start_us) / 1000 ))
n=${#durations[@]}
p95=0
if (( n > 0 )); then
  idx=$(( (n * 95 + 99) / 100 ))      # nearest-rank: ceil(0.95 n)
  p95=$(printf '%s\n' "${durations[@]}" | sort -n | sed -n "${idx}p")
fi

(( rows_out )) && exit 0
if (( json )); then
  printf '%s\n' "${mismatches[@]+"${mismatches[@]}"}" | jq -R . | jq -s \
    --argjson bp "$bp" --argjson bt "$bt" --argjson db "$db" --argjson dt "$dt" \
    --argjson rp "$rp" --argjson rt "$rt" --argjson ms "$runtime" --argjson p95 "$p95" --argjson n "$n" \
    '{benign_pass:$bp, benign_total:$bt, dangerous_block:$db, dangerous_total:$dt, residual_pass:$rp, residual_total:$rt, runtime_ms:$ms, p95_ms:$p95, rows:$n, mismatches: map(select(length>0))}'
else
  printf '%s\n' "${mismatches[@]+"${mismatches[@]}"}" | sed '/^$/d'
  echo "benign $bp/$bt dangerous $db/$dt residual $rp/$rt runtime_ms $runtime p95_ms $p95"
fi
