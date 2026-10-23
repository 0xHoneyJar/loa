#!/usr/bin/env bash
# register.sh — build REGISTRATION.json for cycle-132 at the current HEAD (the PIN commit must already hold
# PREREGISTRATION.md, the suite root, the corpus and the analysis tree; REGISTRATION.json is committed next).
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa
ROOT=grimoires/loa/evals/ablation-2.0-c132
PIN="$(git rev-parse HEAD)"
[[ -z "$(git status --short -- evals grimoires/loa/evals grimoires/loa/reports)" ]] || { echo "working tree not clean under evals/ or the suite root; commit the pin first" >&2; exit 1; }
IMG="$(docker image inspect loa-ablation:258 --format '{{.Id}}')"
G1='["review-r27","review-r28","review-r23","review-r14","review-r15","review-r25"]'
G2='["review-r16","review-r26","review-r21","review-r19"]'
G3='["review-r24","review-r20","review-r22","review-r11"]'
python3 -I evals/analysis/c132/registration.py build \
  --prereg "$ROOT/PREREGISTRATION.md" --corpus-sums evals/fixtures/review-prs/SHA256SUMS --suite-root "$ROOT" \
  --analysis-tree "$PIN:evals/analysis/c132" --pin "$PIN" --suite-file evals/suites/ablation-2.0.yaml \
  --arms a1_full,a0_bare_matched,a0_bare_fable_matched,a1_review_only,a1_full_openmount \
  --groups "[$G1,$G2,$G3]" --looks '[6,10,14]' --boundary-constant 1.0 --cap-usd 4200 --seed 20261021 \
  --kickoff 2026-10-21T00:23:00Z --image-digest "$IMG" --cycle cycle-132-conclusive-review-catch --label-set v2 \
  --out "$ROOT/REGISTRATION.json" | tee "$ROOT/REGISTRATION.sha256.txt"
python3 -I evals/analysis/c132/registration.py verify "$ROOT/REGISTRATION.json"
echo "pin $PIN"; sha256sum "$ROOT/REGISTRATION.json"
