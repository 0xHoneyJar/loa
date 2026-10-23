#!/usr/bin/env bash
# run-annotation.sh <pr-NN> [--skip-sessions|--finish] — cycle-132 Sprint 269 Task 1.6, one fixture:
#   1. packets (annotation-packets.sh) → a2a/sprint-269/annotation/packets/pr-NN + pr-NN.hunks.meta.json
#      (no --deny-dir: the candidates have no run directories of their own; the corpus-wide list collides on generic code lines)
#   2. blind sessions A and B in parallel (blind-session.sh, Opus 5.5, container) → a2a/sprint-269/annotation/pr-NN/{A,B}/
#      MAXUSD / TIMEOUT_MIN env override the per-role cap (default 8 USD / 45 min); SPEND_ROWS names the meter rows file once
#      blind-session.sh has --spend-row (implementer B round 2)
#   3. kappa phase (annotation_merge.py --kappa) → a2a/sprint-269/annotation/pr-NN/merge/{kappa.json,adjudication.md}
# The lead then writes adjudication.json and runs `run-annotation.sh pr-NN --finish`:
#   4. merge with --adjudication → labels.rows.tsv; copy to labels/pr-NN.tsv; --build-manifest; --validate; (freeze later, once for all)
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa
fx="$1"; mode="${2:-}"; rerun_role="${3:-}"   # modes: (none) | --skip-sessions | --finish | --rerun A|B
A2A=grimoires/loa/a2a/sprint-269/annotation
P="$A2A/packets"; O="$A2A/$fx"; CORPUS=evals/fixtures/review-prs
MODEL=global.anthropic.claude-opus-5-5
PROMPT=~/.cache/loa/cycle-132/prompts/annotator.md
mkdir -p "$O"
if [[ "$mode" == "--finish" ]]; then
  [[ -f "$O/adjudication.json" ]] || { echo "write $O/adjudication.json first" >&2; exit 2; }
  # the seeded review-derived set (labels/pr-NN.tsv + manifests/pr-NN.json, "approved-by: pending") is preserved under review/ before the v2 rows replace it
  mkdir -p "$CORPUS/labels/review" "$CORPUS/manifests/review"
  [[ -f "$CORPUS/labels/review/$fx.tsv" ]] || cp "$CORPUS/labels/$fx.tsv" "$CORPUS/labels/review/$fx.tsv"
  [[ -f "$CORPUS/manifests/review/$fx.json" || ! -f "$CORPUS/manifests/$fx.json" ]] || cp "$CORPUS/manifests/$fx.json" "$CORPUS/manifests/review/$fx.json"
  key=""; for k in "$CORPUS/manifests/c131/$fx.json" "$CORPUS/manifests/review/$fx.json"; do [[ -f "$k" ]] && { key="$k"; break; }; done
  python3 -I evals/analysis/c132/annotation_merge.py --fixture "$fx" --a "$O/A/labels.json" --b "$O/B/labels.json" \
    --adjudication "$O/adjudication.json" --hunks-meta "$P/$fx.hunks.meta.json" --head-dir "$CORPUS/$fx/head" \
    --fix-rows "$CORPUS/labels/review/$fx.tsv" ${key:+--manifest-c131 "$key"} \
    --schema evals/harness/schemas/annotation.schema.json --out "$O/merge"
  cp "$O/merge/labels.rows.tsv" "$CORPUS/labels/$fx.tsv"
  bash evals/harness/seed-corpus-from-record.sh --build-manifest "$fx" | tail -1
  python3 -I evals/analysis/c132/annotation_merge.py --validate evals/harness/schemas/review-manifest.schema.json "$CORPUS/manifests/$fx.json" | tail -1
  echo "finished $fx (run --freeze once all fixtures are done)"
  exit 0
fi
roles=(A B)
if [[ "$mode" == "--rerun" ]]; then
  [[ "$rerun_role" == A || "$rerun_role" == B ]] || { echo "--rerun needs A or B" >&2; exit 2; }
  roles=("$rerun_role"); n=1; while [[ -e "$O/$rerun_role-invalid-$n" ]]; do n=$((n+1)); done
  [[ -d "$O/$rerun_role" ]] && mv "$O/$rerun_role" "$O/$rerun_role-invalid-$n" && mv "$O/$rerun_role.log" "$O/$rerun_role-invalid-$n.log"
  echo "rerun $rerun_role (previous output kept as $rerun_role-invalid-$n)"
fi
if [[ "$mode" != "--skip-sessions" ]]; then
  bash evals/harness/annotation-packets.sh "$fx" --out "$P" | tail -1
  spend=(); [[ -n "${SPEND_ROWS:-}" ]] && spend=(--spend-row "$SPEND_ROWS")
  for role in "${roles[@]}"; do
    [[ -d "$O/$role" ]] && find "$O/$role" -mindepth 1 -delete && rmdir "$O/$role"
    ( bash evals/harness/blind-session.sh --packets "$P/$fx" --prompt "$PROMPT" --model "$MODEL" --out "$O/$role" \
        --max-usd "${MAXUSD:-8}" --timeout-min "${TIMEOUT_MIN:-45}" ${spend[@]+"${spend[@]}"} > "$O/$role.log" 2>&1
      echo "role $role exit $?" >> "$O/$role.log" ) &
  done
  wait
  for role in "${roles[@]}"; do
    printf '%s: %s %s\n' "$role" "$(tail -1 "$O/$role.log")" "$(jq -c '{tainted, cost: .cost_usd}' "$O/$role/taint.json" "$O/$role/cost.json" 2>/dev/null | tr '\n' ' ')"
  done
fi
rc=0
python3 -I evals/analysis/c132/annotation_merge.py --fixture "$fx" --a "$O/A/labels.json" --b "$O/B/labels.json" --kappa \
  --hunks-meta "$P/$fx.hunks.meta.json" --head-dir "$CORPUS/$fx/head" --schema evals/harness/schemas/annotation.schema.json --out "$O/merge" || rc=$?
echo "kappa phase exit $rc (3 = disagreements to adjudicate in $O/merge/adjudication.md)"
jq -c '.' "$O/merge/kappa.json" 2>/dev/null | cut -c1-400
