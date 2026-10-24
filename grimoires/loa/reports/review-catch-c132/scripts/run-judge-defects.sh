#!/usr/bin/env bash
# run-judge-defects.sh — Sprint 271 exploratory defect-level judge read (DEC-0800/0810): split c132-judge-defects/packets into chunks of <= 64 and run one blind Opus 5.5 judge session per chunk,
# at most 3 at a time; idempotent (a chunk whose session dir holds labels.json for this sample is skipped; a failed one is moved aside and rerun once).
# Usage: run-judge-defects.sh [--cache DIR] [--prompt F]
#   --cache DIR  chunks and logs (default ~/.cache/loa/cycle-132); --prompt F the judge prompt (default the tracked
#                copy prompts/judge.md beside this script)
# Sample binding (cycle-133 bd-xr3uq, bd-o3a5h): the key's sample_id (judge_defects.py) must head every packet
# ("Sample: `<id>`", line 3) or the run is refused; the chunk directory is <cache>/judge-defects/chunks-<first 16 hex
# of the key's sha256> with KEY_SHA256 inside (a directory holding another key's sha is refused); every session's
# labels.json is stamped with the sample_id after the session, and a session whose labels.json names another sample is
# moved aside (<chunk>.failed-stale-<time>) and rerun. The repository root comes from this script's path (any cwd).
# Exit: 0 every pass ran (the log names the labelled count); 2 usage or a refused key, packet or chunk directory.
set -uo pipefail
export LC_ALL=C
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd "$HERE/../../../../.." && pwd -P)"; cd "$ROOT" || exit 2
die() { echo "run-judge-defects.sh: $*" >&2; exit 2; }
CACHE="$HOME/.cache/loa/cycle-132"; PROMPT="$HERE/prompts/judge.md"
while [ $# -gt 0 ]; do case "$1" in
  --cache) CACHE="${2:-}"; shift 2;; --prompt) PROMPT="${2:-}"; shift 2;; *) die "unknown argument: $1";; esac; done
[ -n "$CACHE" ] || die "--cache needs a directory"
[ -f "$PROMPT" ] || die "judge prompt not found: $PROMPT"
J=grimoires/loa/reports/ablation-2.0/c132-judge-defects; S=$J/sessions; LOG=$CACHE/logs
[ -f "$J/key.json" ] || die "no key at $J/key.json (judge_defects.py sample first)"
KSHA="$(python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$J/key.json")" || die "cannot hash $J/key.json"
SID="$(jq -er '.sample_id' "$J/key.json")" || die "$J/key.json carries no sample_id (sampled before cycle-133?); re-sample"
[[ "$SID" =~ ^[0-9a-f]{12}$ ]] || die "$J/key.json sample_id is not 12 hex: ${SID:0:40}"
n=0
for f in "$J"/packets/D*.md; do
  [ -f "$f" ] || die "no packets under $J/packets"
  [ "$(sed -n 3p "$f")" = "Sample: \`$SID\`" ] || die "$(basename "$f") does not carry the key's sample_id $SID"
  n=$((n+1))
done
C=$CACHE/judge-defects/chunks-${KSHA:0:16}
mkdir -p "$CACHE/judge-defects" "$S" "$LOG" || die "cannot create $CACHE or $S"
if [ -d "$C" ]; then
  [ "$(cat "$C/KEY_SHA256" 2>/dev/null)" = "$KSHA" ] || die "$C/KEY_SHA256 does not name this key ($KSHA); remove the directory or use another --cache"
else
  T="$(mktemp -d "$CACHE/judge-defects/.chunks-XXXXXX")" || die "cannot create a temporary chunk directory"
  i=0; k=0
  for f in "$J"/packets/D*.md; do
    if (( k % 64 == 0 )); then i=$((i+1)); d=$(printf '%s/c%02d' "$T" "$i"); mkdir -p "$d"; fi
    cp "$f" "$d/"; k=$((k+1))
  done
  echo "$KSHA" > "$T/KEY_SHA256"
  mv "$T" "$C" || die "cannot place $C"
fi
run_one() {
  local c="$1" o="$S/$1" got
  if [[ -f "$o/labels.json" ]]; then
    if got="$(jq -er '.sample_id' "$o/labels.json")" && [ "$got" = "$SID" ]; then return 0; fi
    mv "$o" "$o.failed-stale-$(date -u +%H%M%S)"
  elif [[ -d "$o" ]]; then
    mv "$o" "$o.failed-$(date -u +%H%M%S)"
  fi
  bash evals/harness/blind-session.sh --packets "$C/$c" --prompt "$PROMPT" --model global.anthropic.claude-opus-5-5 \
    --out "$o" --max-usd 6 --max-turns 200 --timeout-min 60 --spend-row evals/results/ablation-2.0/c132-phase0/rows.jsonl > "$LOG/judge-defects-$c.log" 2>&1
  local rc=$?
  if [[ -f "$o/labels.json" ]]; then
    # bind the session's labels to the sample its packets carried; a labels.json that is not an object is left as is
    # (aggregate refuses it: no sample_id)
    if jq -e --arg s "$SID" 'if type == "object" then . + {sample_id: $s} else error("not an object") end' "$o/labels.json" > "$o/labels.json.tmp"; then
      mv "$o/labels.json.tmp" "$o/labels.json"
    else
      rm -f "$o/labels.json.tmp"
    fi
  fi
  echo "$(date -u +%H:%M:%SZ) $c rc=$rc $(tail -1 "$LOG/judge-defects-$c.log" | cut -c1-120)" >> "$LOG/run-judge-defects.log"
}
for pass in 1 2; do
  for c in $(cd "$C" && ls -d c[0-9]* | sort); do
    while (( $(jobs -rp | wc -l) >= 3 )); do sleep 5; done
    run_one "$c" &
  done
  wait
done
echo "$(date -u +%H:%M:%SZ) done ($n packets, sample $SID): $(ls "$S"/*/labels.json 2>/dev/null | wc -l) of $(cd "$C" && ls -d c[0-9]* | wc -l) chunks labelled" >> "$LOG/run-judge-defects.log"
