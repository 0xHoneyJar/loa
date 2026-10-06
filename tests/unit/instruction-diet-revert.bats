#!/usr/bin/env bats
# =============================================================================
# tests/unit/instruction-diet-revert.bats — cycle-126 sprint-250 Task 4.8
#
# The Sprint 3 replay A/B re-run (grimoires a2a sprint-250 replay-ab-rerun.md)
# failed its pre-registered gate on audit-pr-02 / audit-pr-05, and each of the
# two ablations (CLAUDE.loa.md trim reverted; constraint rationales reverted)
# restored before-level recall. Per the pre-registered rule both are reverted:
# CLAUDE.loa.md keeps its Reference Files and truenames tables and the NOTES
# clause, and the twelve rationales carry their pre-diet text.
# =============================================================================

setup() {
    R="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
    LOA="$R/.claude/loa/CLAUDE.loa.md"
}

@test "IDR-1 CLAUDE.loa.md carries the Reference Files table, one row per reference file" {
    grep -qxF '| Topic | Location |' "$LOA"
    for f in context-engineering protocols-summary scripts-reference beads-reference run-bridge-reference \
             flatline-reference guardrails-reference hooks-reference agent-teams-reference \
             agent-network-reference multi-model-reference; do
        grep -qE "^\| [^|]+ \| \`\.claude/loa/reference/$f\.md\` \|$" "$LOA"
    done
    grep -qxF '| Configuration | `.loa.config.yaml.example` |' "$LOA"
}

@test "IDR-2 CLAUDE.loa.md carries the truenames table and the NOTES clause" {
    grep -qxF '| Phase | Command | Output |' "$LOA"
    for row in '| 1 | `/plan-and-analyze` | PRD |' '| 4 | `/implement sprint-N` | Code |' \
               '| 5.5 | `/audit-sprint sprint-N` | Approval |' '| 6 | `/deploy-production` | Infrastructure |'; do
        grep -qxF "$row" "$LOA"
    done
    grep -qF 'memory lives in `grimoires/loa/NOTES.md`' "$LOA"
}

@test "IDR-3 the twelve constraint rationales carry their pre-diet text" {
    run python3 - "$R/.claude/data/constraints.json" "$R/tests/fixtures/constraint-rationales-pre-diet.json" <<'PY'
import json, sys
found = {}
def walk(x):
    if isinstance(x, dict):
        if "id" in x and "why" in x:
            found[x["id"]] = x["why"]
        for v in x.values():
            walk(v)
    elif isinstance(x, list):
        for v in x:
            walk(v)
walk(json.load(open(sys.argv[1])))
want = json.load(open(sys.argv[2]))
assert len(want) == 12, len(want)
bad = [k for k, v in want.items() if found.get(k) != v]
print("mismatch:", bad)
sys.exit(1 if bad else 0)
PY
    echo "$output"
    [ "$status" -eq 0 ]
}

@test "IDR-4 every rendered rationale in CLAUDE.loa.md matches constraints.json (seven C-PROC rows)" {
    for id in C-PROC-001 C-PROC-002 C-PROC-004 C-PROC-005 C-PROC-015 C-PROC-017 C-PROC-018; do
        why=$(jq -r --arg id "$id" '[.. | objects | select(.id? == $id) | .why][0]' "$R/.claude/data/constraints.json")
        grep -qF "| $why |" "$LOA"
    done
}
