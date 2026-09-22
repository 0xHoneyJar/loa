#!/usr/bin/env bash
# =============================================================================
# tests/fixtures/notes/make-large-notes.sh OUT SIZE — NOTES.md fixture generator
# (cycle-124 Sprint 4, PRD FR-10 / AC-10.1: nothing large is committed; every
# size is produced at test time).
#
#   SIZE: under | 100k (102400) | 200k (204800) | 250k (256000) | 750k (768000)
#         | <bytes>   — the file ends up in [SIZE, SIZE+63] bytes ("under" = no
#                       padding, ~1.3 KB).
#
# Shape (fixed, so notes-guard.bats can pin the selection rules):
#   - two `## Blockers` blocks (B-1, B-2) — `read` concatenates both
#   - `## Session Continuity — 2026-09-01` (old) and `— 2026-09-10` (newest,
#     placed MID-FILE: recency is the heading date, not the position)
#   - `## Decision Log` blocks dated 09-02, 09-05, 09-01, 09-04, 09-03 in that
#     file order — the three newest are 09-05, 09-04, 09-03
#   - the 09-03 block is the LAST section and carries the padding, so a large
#     fixture has one oversized Decision Log block (the 750 KB headline case)
# =============================================================================
set -euo pipefail

out="${1:?usage: make-large-notes.sh OUT SIZE}"
size="${2:?usage: make-large-notes.sh OUT SIZE}"

case "$size" in
  under) target=0 ;;
  100k)  target=102400 ;;
  200k)  target=204800 ;;
  250k)  target=256000 ;;
  750k)  target=768000 ;;
  *)
    [[ "$size" =~ ^[0-9]+$ ]] || { echo "make-large-notes.sh: bad SIZE '$size'" >&2; exit 2; }
    target=$size ;;
esac

mkdir -p "$(dirname "$out")"
cat > "$out" <<'EOF'
# Project Memory — fixture (tests/fixtures/notes/make-large-notes.sh)

## Current Focus
- **Active Task**: fixture
- **Status**: generated

## Blockers
- [ ] B-1 first blockers block (fixture)

## Session Continuity — 2026-09-01
### Active Context
OLD-CONTINUITY-0901 — must not be selected

## Decision Log — 2026-09-02
- D-0902 older decision — must not be selected

## Decision Log — 2026-09-05
- D-0905 newest decision — selected first

## Blockers
- [ ] B-2 second blockers block (fixture, concatenated after B-1)

## Decision Log — 2026-09-01
- D-0901 oldest decision — must not be selected

## Session Continuity — 2026-09-10
### Active Context
NEWEST-CONTINUITY-0910 — selected (sits mid-file: position is not recency)

## Decision Log — 2026-09-04
- D-0904 second-newest decision — selected

## Learnings
- L-1 fixture learning

## Decision Log — 2026-09-03
- D-0903 third-newest decision — selected; the padding below makes this block oversized
EOF

if (( target > 0 )); then
  cur=$(stat -c%s "$out")
  if (( cur < target )); then
    # every pad line is exactly 64 bytes: "pad " (4) + 10 digits + " " (1) + 48 dots + "\n"
    n=$(( (target - cur + 63) / 64 ))
    awk -v n="$n" 'BEGIN { for (i = 1; i <= n; i++) printf "pad %010d %s\n", i, "................................................" }' >> "$out"
  fi
fi
