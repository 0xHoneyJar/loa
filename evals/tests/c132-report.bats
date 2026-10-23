#!/usr/bin/env bats
# c132-report.bats — cycle-132 Sprint 271 (PRD FR-9 AC 2): every table row in the report carries no hand-typed number.
# Each markdown table row of grimoires/loa/reports/review-catch-c132/report.md that contains a digit must appear verbatim
# (same bytes, whitespace-trimmed) in one of the generated artefacts the report is assembled from: the reads
# (reads.md = reads-c132.py --final), the two placebos, the judge result, the spend meter, the contamination hand-reads,
# the ground-truth annotation result, the power simulation, or the batches record. A row that appears nowhere fails
# with its text. Header and separator rows ("| --- |", "| arm | …") are exempt only when they carry no digit; the
# "## Files" index (artefact names) is exempt as a section.

REPORT="grimoires/loa/reports/review-catch-c132/report.md"
SOURCES=(
  grimoires/loa/reports/review-catch-c132/reads.md
  grimoires/loa/reports/review-catch-c132/placebo-phase1.md
  grimoires/loa/reports/ablation-2.0/placebo-existing/placebo-existing.md
  grimoires/loa/reports/review-catch-c132/judge/result.md
  grimoires/loa/reports/review-catch-c132/spend.md
  grimoires/loa/reports/review-catch-c132/batch-scans.md
  grimoires/loa/reports/review-catch-c132/ground-truth.md
  grimoires/loa/reports/review-catch-c132/power.md
  grimoires/loa/reports/review-catch-c132/batches.md
  grimoires/loa/reports/review-catch-c132/judge-defects/result.md
  grimoires/loa/reports/review-catch-c132/reproduction/report.md
)

setup() {
  cd "${BATS_TEST_DIRNAME}/../.." || return 1
  [ -f "$REPORT" ] || skip "report not written yet: $REPORT"
}

@test "c132 report: every numeric table row is copied verbatim from a generated artefact" {
  local missing=0 line trimmed found src section=""
  while IFS= read -r line; do
    trimmed="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ "$trimmed" == "## "* ]] && section="$trimmed"
    # the file index names artefacts (digits in file names, not figures); every other table is a measurement
    [[ "$section" == "## Files" ]] && continue
    [[ "$trimmed" == \|* ]] || continue
    [[ "$trimmed" =~ [0-9] ]] || continue
    found=0
    for src in "${SOURCES[@]}"; do
      [ -f "$src" ] || continue
      if grep -qxF -- "$trimmed" "$src"; then found=1; break; fi
    done
    if (( ! found )); then echo "NOT FOUND in any artefact: $trimmed" >&2; missing=$((missing+1)); fi
  done < "$REPORT"
  [ "$missing" -eq 0 ]
}

@test "c132 report: reads.md beside the report is byte-identical to the final read it was copied from" {
  [ -f grimoires/loa/reports/ablation-2.0/c132-final/final.md ] || skip "no final read in the working tree"
  cmp grimoires/loa/reports/review-catch-c132/reads.md grimoires/loa/reports/ablation-2.0/c132-final/final.md
  cmp grimoires/loa/reports/review-catch-c132/reads.json grimoires/loa/reports/ablation-2.0/c132-final/final.json
}

@test "c132 report: the ELI5 section is at most 300 words" {
  local words
  words="$(awk '/^## ELI5/{f=1; next} /^## /{if(f) exit} f' "$REPORT" | wc -w)"
  echo "ELI5 words: $words" >&2
  [ "$words" -gt 0 ] && [ "$words" -le 300 ]
}
