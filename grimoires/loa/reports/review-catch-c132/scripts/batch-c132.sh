#!/usr/bin/env bash
# batch-c132.sh <smoke|g{1,2,3}-{a1,a2,a3,b}> <pin> [--dry-run|--resume …] — Sprint 270 batches under the registration
#   smoke : a1_full + a0_bare × 14 tasks × 1 trial (closed mount; oracle_closed must hold; cost ratio recorded)
#   smoke3: a1_full × the five adapter PRs (r11, r14, r15, r21, r22) × 1 — the KF-050 re-run under addendum 5
#   gN-a1 : a1_full × group N × 2 trials            ┐ the primary pairs and the positive control run first, one arm per batch
#   gN-a2 : a0_bare_matched × group N × 2 trials    │ (the codex token horizon pre-flight, KF-048, refuses one batch holding all
#   gN-a3 : a1_full_openmount × group N × 2 trials  ┘  three arms: its summed watchdog outruns the token's 7 days)
#   gN-b  : a0_bare_fable_matched, a1_review_only × group N × 2 trials  (secondary arms after the primary pairs)
# --max-usd is derived from the registration (cap − meter); one batch at a time; no dissent run while a batch runs.
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa
which="$1"; pin="$2"; shift 2
ROOT=grimoires/loa/evals/ablation-2.0-c132; REG=$ROOT/REGISTRATION-14.json; LOG=grimoires/loa/reports/ablation-2.0/self-check-c132.txt
ALL=review-r27,review-r28,review-r23,review-r14,review-r15,review-r25,review-r16,review-r26,review-r21,review-r19,review-r24,review-r20,review-r22,review-r11
G1=review-r27,review-r28,review-r23,review-r14,review-r15,review-r25; G2=review-r16,review-r26,review-r21,review-r19; G3=review-r24,review-r20,review-r22,review-r11
SECONDARY=a0_bare_fable_matched,a1_review_only
case "$which" in
  smoke) arms=a1_full,a0_bare; tasks=$ALL; trials=1; batch=c132-smoke2 ;;   # c132-smoke = the superseded first attempt (addenda 1 and 2)
  smoke3) arms=a1_full; tasks=review-r11,review-r14,review-r15,review-r21,review-r22,review-r20; trials=1; batch=c132-smoke3 ;;   # the five adapter PRs refused in smoke2 (KF-050, addendum 5)
  smoke4) arms=a1_full; tasks=review-r14; trials=1; batch=c132-smoke4 ;;   # pr-14 (model-catalog PR) under the whole-.claude pin (addendum 9)
  g[123]-a1) arms=a1_full ;; g[123]-a2) arms=a0_bare_matched ;; g[123]-a3) arms=a1_full_openmount ;; g[123]-b) arms=$SECONDARY ;;
  *) echo "which must be smoke|smoke3|smoke4|g{1,2,3}-{a1,a2,a3,b}" >&2; exit 2 ;;
esac
if [[ "$which" != smoke && "$which" != smoke3 && "$which" != smoke4 ]]; then
  case "${which%%-*}" in g1) tasks=$G1 ;; g2) tasks=$G2 ;; g3) tasks=$G3 ;; esac
  trials=2; batch="c132-$which"
fi
bash evals/harness/run-ablation.sh --source-commit "$pin" --registration "$REG" --arms "$arms" --tasks "$tasks" --trials-review "$trials" \
  --concurrency 3 --run-cap 45 --batch "$batch" --results-root evals/results/ablation-2.0 --suite-root "$ROOT" --allow-partial \
  --self-check-log "$LOG" --pre-registration-ref "NOTES 2026-10-21T06:35:41Z REGISTRATION-14 sha256 380f7a3656d3c9dfbd93ce73ab8732ec6a777ccf89f8e49e892ed27c5b595090 pin fbd36a0c" --batch-context "$batch" "$@"
