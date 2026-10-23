#!/usr/bin/env bash
# run-judge-defects.sh — Sprint 271 exploratory defect-level judge read (DEC-0800/0810): split c132-judge-defects/packets into chunks of <= 64 and run one blind Opus 5.5 judge session per chunk,
# at most 3 at a time; idempotent (a chunk whose session dir holds labels.json is skipped; a failed one is moved aside and rerun once).
set -uo pipefail
cd /home/merlin/Documents/thj/code/loa
J=grimoires/loa/reports/ablation-2.0/c132-judge-defects; C=~/.cache/loa/cycle-132/judge-defects/chunks; S=$J/sessions; LOG=~/.cache/loa/cycle-132/logs
mkdir -p "$C" "$S"
if [[ -z "$(ls -A "$C" 2>/dev/null)" ]]; then
  i=0; n=0
  for f in $(ls "$J/packets" | sort); do
    if (( n % 64 == 0 )); then i=$((i+1)); d=$(printf '%s/c%02d' "$C" "$i"); mkdir -p "$d"; fi
    cp "$J/packets/$f" "$d/"; n=$((n+1))
  done
fi
run_one() {
  local c="$1" o="$S/$1"
  [[ -f "$o/labels.json" ]] && return 0
  [[ -d "$o" ]] && mv "$o" "$o.failed-$(date -u +%H%M%S)"
  bash evals/harness/blind-session.sh --packets "$C/$c" --prompt ~/.cache/loa/cycle-132/prompts/judge.md --model global.anthropic.claude-opus-5-5 \
    --out "$o" --max-usd 6 --max-turns 200 --timeout-min 60 --spend-row evals/results/ablation-2.0/c132-phase0/rows.jsonl > "$LOG/judge-defects-$c.log" 2>&1
  echo "$(date -u +%H:%M:%SZ) $c rc=$? $(tail -1 "$LOG/judge-defects-$c.log" | cut -c1-120)" >> "$LOG/run-judge-defects.log"
}
for pass in 1 2; do
  for c in $(ls "$C" | sort); do
    while (( $(jobs -rp | wc -l) >= 3 )); do sleep 5; done
    run_one "$c" &
  done
  wait
done
echo "$(date -u +%H:%M:%SZ) done: $(ls "$S"/*/labels.json 2>/dev/null | wc -l) of $(ls "$C" | wc -l) chunks labelled" >> "$LOG/run-judge-defects.log"
