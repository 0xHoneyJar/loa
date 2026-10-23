#!/usr/bin/env bash
# register-addendum-analysis.sh <N> <predecessor-sha256> <pipeline-pin> — build REGISTRATION-<N>.json for an ANALYSIS-ONLY addendum
# (PREREGISTRATION §12): the pipeline/harness pin stays <pipeline-pin> (every Phase 1 row keeps the same source_commit; make-inputs
# validates rows against it), while the analysis tree is taken from the current HEAD. PREREGISTRATION-addendum-<N>.md must be committed.
set -euo pipefail
cd /home/merlin/Documents/thj/code/loa
N="$1"; PRED="$2"; PIN="$3"
ROOT=grimoires/loa/evals/ablation-2.0-c132
[[ -f "$ROOT/PREREGISTRATION-addendum-$N.md" ]] || { echo "write $ROOT/PREREGISTRATION-addendum-$N.md first" >&2; exit 2; }
[[ -z "$(git status --short --untracked-files=no -- evals grimoires/loa/evals grimoires/loa/reports)" ]] || { echo "working tree not clean under evals/ or the suite root; commit first" >&2; exit 1; }
HEAD_SHA="$(git rev-parse HEAD)"
# the pipeline under test must be byte-identical at the two commits
# the judge sampler is analysis-side tooling no arm runs (addendum 12); every other pipeline file must be identical
if ! git diff --quiet "$PIN" "$HEAD_SHA" -- .claude evals/harness evals/suites evals/fixtures "$ROOT/tasks" "$ROOT/MANIFEST.sha256" \
     ":(exclude)evals/harness/judge-sample.sh" ":(exclude)evals/harness/defect-descriptions.py"; then
  echo "pipeline/harness/suite differ between pin $PIN and HEAD $HEAD_SHA — an analysis-only addendum cannot keep the pin" >&2; exit 1; fi
IMG="$(docker image inspect loa-ablation:258 --format '{{.Id}}')"
G1='["review-r27","review-r28","review-r23","review-r14","review-r15","review-r25"]'
G2='["review-r16","review-r26","review-r21","review-r19"]'
G3='["review-r24","review-r20","review-r22","review-r11"]'
python3 -I evals/analysis/c132/registration.py build \
  --prereg "$ROOT/PREREGISTRATION.md" --corpus-sums evals/fixtures/review-prs/SHA256SUMS --suite-root "$ROOT" \
  --analysis-tree "$HEAD_SHA:evals/analysis/c132" --pin "$PIN" --suite-file evals/suites/ablation-2.0.yaml \
  --arms a1_full,a0_bare_matched,a0_bare_fable_matched,a1_review_only,a1_full_openmount \
  --groups "[$G1,$G2,$G3]" --looks '[6,10,14]' --boundary-constant 1.0 --cap-usd 4200 --seed 20261021 \
  --kickoff 2026-10-21T00:23:00Z --image-digest "$IMG" --cycle cycle-132-conclusive-review-catch --label-set v2 \
  --supersedes "$PRED" --out "$ROOT/REGISTRATION-$N.json" | tee "$ROOT/REGISTRATION-$N.sha256.txt"
python3 -I evals/analysis/c132/registration.py verify "$ROOT/REGISTRATION-$N.json"
echo "pin $PIN (unchanged); analysis tree at $HEAD_SHA"; sha256sum "$ROOT/REGISTRATION-$N.json"
