#!/usr/bin/env bash
# run-corpus.sh — replay tests/fixtures/fence-corpus/corpus.jsonl through the
# block-destructive-bash hook and summarise (cycle-125 Sprint 1, PRD FR-1).
#
# Usage: run-corpus.sh [--hook PATH] [--corpus PATH] [--json] [--knob-off] [--rows]
# Each row: {id, cmd, expect: allow|block|residual|miss, rule, why, cwd: repo|tmp, env?: {TMPDIR}}
#   allow/block are gated (a mismatch fails the run); residual is an accepted
#   false positive (counted, reported as R/T where R = rows that now allow);
#   miss is a documented false negative (M id; counted, reported as M/T where
#   M = rows the hook still lets through, never a mismatch in either direction,
#   so a fix never reads as a regression — r256-3).
#   allow    → benign: the hook must exit 0
#   block    → dangerous: the hook must exit 2
#   residual → accepted false positive: counted, never gated
# --knob-off  writes destructive_command_guard.heredoc_classifier: false into the
#             replay root's .loa.config.yaml (cycle-129 FR-6: the pre-cycle scan);
#             compare it with the pre-change hook through --rows. The hook reads
#             that file through LOA_REPO_ROOT, which this runner exports as the
#             replay root; the self-check below proves the knob reached the hook.
# --no-self-check  skip the --knob-off self-check (for a probe corpus without D122).
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
json=0 knob_off=0 rows_out=0 no_self_check=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --hook) hook="$2"; shift 2 ;;
    --corpus) corpus="$2"; shift 2 ;;
    --json) json=1; shift ;;
    --knob-off) knob_off=1; shift ;;
    --no-self-check) no_self_check=1; shift ;;
    --rows) rows_out=1; shift ;;
    *) echo "usage: run-corpus.sh [--hook PATH] [--corpus PATH] [--json] [--knob-off] [--no-self-check] [--rows]" >&2; exit 2 ;;
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

bp=0 bt=0 db=0 dt=0 rp=0 rt=0 mp=0 mt=0
# The miss class is gated by count (audit r256-4 HIGH-A1): a new documented miss is a
# mismatch until this pin is raised deliberately in the same change that documents it.
EXPECTED_MISS_ROWS=0
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
  [[ "$id" == D122 ]] && rc_d122=$rc   # knob-off self-check (r256-1 LOW-2): classifier-only block
  [[ "$id" == D01 ]] && rc_d01=$rc     # knob-off positive control (r256-3): a plain FR-2 block the knob must not touch
  (( rows_out )) && printf '%s %s\n' "$id" "$rc"
  case "$expect" in
    allow)    bt=$((bt+1)); if [[ $rc -eq 0 ]]; then bp=$((bp+1)); else mismatches+=("$id:expected-allow:rc=$rc"); fi ;;
    block)    dt=$((dt+1)); if [[ $rc -eq 2 ]]; then db=$((db+1)); else mismatches+=("$id:expected-block:rc=$rc"); fi ;;
    residual) rt=$((rt+1)); [[ $rc -eq 0 ]] && rp=$((rp+1)) ;;
    miss)     mt=$((mt+1)); [[ $rc -eq 0 ]] && mp=$((mp+1)) ;;
    *) mismatches+=("$id:unknown-expect:$expect") ;;
  esac
done < "$corpus"
(( mt == EXPECTED_MISS_ROWS )) || mismatches+=("miss-rows:$mt (pinned $EXPECTED_MISS_ROWS; raise EXPECTED_MISS_ROWS in the change that documents a new miss)")
end_us=$(now_us)
runtime=$(( (end_us - start_us) / 1000 ))
n=${#durations[@]}
p95=0
if (( n > 0 )); then
  idx=$(( (n * 95 + 99) / 100 ))      # nearest-rank: ceil(0.95 n)
  p95=$(printf '%s\n' "${durations[@]}" | sort -n | sed -n "${idx}p")
fi

# --knob-off self-check (r256-1 LOW-2): D122 (a .sh-target quoted heredoc) is blocked only
# by the classifier; the pre-cycle scan lets it through. If it still blocks, the knob did not
# reach the hook and the comparison would compare the hook with itself.
if (( knob_off )) && (( ! ${no_self_check:-0} )); then
  if [[ -z "${rc_d122:-}" ]]; then
    echo "run-corpus: --knob-off self-check impossible: the corpus has no D122 row (pass --no-self-check for a probe corpus)" >&2
    exit 3
  fi
  if [[ "$rc_d122" != 0 ]]; then
    echo "run-corpus: --knob-off did not take effect (D122 exited $rc_d122, expected 0): the hook did not read $work/.loa.config.yaml via LOA_REPO_ROOT" >&2
    exit 3
  fi
  # Positive control: a classifier-independent dangerous row must still block, or the
  # written config disabled (or broke) the whole fence rather than the classifier.
  if [[ -z "${rc_d01:-}" || "$rc_d01" != 2 ]]; then
    echo "run-corpus: --knob-off positive control failed (D01 exited ${rc_d01:-unseen}, expected 2): the config file disabled the fence, not only the classifier" >&2
    exit 3
  fi
fi
(( rows_out )) && exit 0
if (( json )); then
  printf '%s\n' "${mismatches[@]+"${mismatches[@]}"}" | jq -R . | jq -s \
    --argjson bp "$bp" --argjson bt "$bt" --argjson db "$db" --argjson dt "$dt" \
    --argjson rp "$rp" --argjson rt "$rt" --argjson ms "$runtime" --argjson p95 "$p95" --argjson n "$n" \
    --argjson mp "$mp" --argjson mt "$mt" \
    '{benign_pass:$bp, benign_total:$bt, dangerous_block:$db, dangerous_total:$dt, residual_pass:$rp, residual_total:$rt, miss_open:$mp, miss_total:$mt, runtime_ms:$ms, p95_ms:$p95, rows:$n, mismatches: map(select(length>0))}'
else
  printf '%s\n' "${mismatches[@]+"${mismatches[@]}"}" | sed '/^$/d'
  echo "benign $bp/$bt dangerous $db/$dt residual $rp/$rt miss $mp/$mt runtime_ms $runtime p95_ms $p95"
fi
