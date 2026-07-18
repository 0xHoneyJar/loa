#!/usr/bin/env bash
# =============================================================================
# run-matrix.sh — run the full hook x payload benchmark matrix
# =============================================================================
# Rebuilds the isolated mirror (bench-env.sh), then times every registered
# per-tool-call hook against representative payloads plus the workflow-
# boundary scripts. Emits:
#   results.tsv   label / runs / min / mean / p95 / max / exit  (ms)
#   stdout        human-readable rows + per-tool-call chain totals
#
# Re-run this in later optimization passes to get comparable numbers —
# the mirror is rebuilt from the LIVE working tree on every invocation.
#
# Workflow-boundary scripts (beads-health, check-updates, golden-path) run
# read-only against the REAL repo (that is their production shape).
# =============================================================================

set -euo pipefail
export LC_ALL=C

PERF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${PERF_DIR}/../../../.." && pwd)"
BENCH="$PERF_DIR/bench.sh"
RESULTS="${BENCH_RESULTS:-$PERF_DIR/results.tsv}"

M="$("$PERF_DIR/bench-env.sh")"
echo "mirror: $M"
echo "results: $RESULTS"

printf 'label\truns\tmin_ms\tmean_ms\tp95_ms\tmax_ms\texit\n' > "$RESULTS"

b() {  # b <label> <payload|-> [extra bench args...] -- cmd...
  local lbl="$1" pl="$2"; shift 2
  local pargs=()
  [[ "$pl" == "-" ]] || pargs=( --payload "$M/payloads/$pl" )
  bash "$BENCH" --label "$lbl" "${pargs[@]}" --cwd "$M" --tsv "$RESULTS" "$@"
}

H="$M/.claude/hooks"

echo ""
echo "== floors (process-spawn cost anatomy) =="
b "floor/fork-exec-true"   -                 -- /usr/bin/true
b "floor/sh-noop"          -                 -- sh -c 'exit 0'
b "floor/bash-noop"        -                 -- bash -c 'exit 0'
b "floor/bash-norc-noop"   -                 -- bash --norc --noprofile -c 'exit 0'
b "floor/jq-startup"       bash-benign.json  -- jq -r '.tool_name'
b "floor/yq-startup"       -                 -- yq --null-input '.x'
b "floor/git-rev-parse"    -                 -- git rev-parse --show-toplevel

echo ""
echo "== PreToolUse:Bash chain =="
b "block-destructive/bash-benign"      bash-benign.json      -- "$H/safety/block-destructive-bash.sh"
b "block-destructive/bash-mutating"    bash-mutating.json    -- "$H/safety/block-destructive-bash.sh"
b "block-destructive/bash-destructive" bash-destructive.json -- "$H/safety/block-destructive-bash.sh"
b "block-destructive/bash-blocked"     bash-blocked.json     -- "$H/safety/block-destructive-bash.sh"
b "block-destructive/bash-benign-utf8" bash-benign.json      --env LC_ALL=en_US.UTF-8 -- "$H/safety/block-destructive-bash.sh"
b "team-role-guard/bash-benign"        bash-benign.json      -- "$H/safety/team-role-guard.sh"
b "team-role-guard/bash-mutating+TEAM" bash-mutating.json    --env LOA_TEAM_MEMBER=bench-mate -- "$H/safety/team-role-guard.sh"

echo ""
echo "== PostToolUse:Bash chain =="
b "mutation-logger/bash-benign"        bash-benign.json      -- "$H/audit/mutation-logger.sh"
b "mutation-logger/bash-mutating"      bash-mutating.json    -- "$H/audit/mutation-logger.sh"

echo ""
echo "== PreToolUse:Write/Edit chain =="
b "team-role-guard-write/write-grim"   write-grimoires.json  -- "$H/safety/team-role-guard-write.sh"
b "team-role-guard-write/write-grim+TEAM" write-grimoires.json --env LOA_TEAM_MEMBER=bench-mate -- "$H/safety/team-role-guard-write.sh"
b "team-role-guard-write/write-claude+TEAM" write-claude.json --env LOA_TEAM_MEMBER=bench-mate -- "$H/safety/team-role-guard-write.sh"
b "spiral-dispatch-guard/write-grim"   write-grimoires.json  -- "$H/safety/spiral-dispatch-guard.sh"
b "zone-write-guard/write-grim"        write-grimoires.json  -- "$H/safety/zone-write-guard.sh"
b "zone-write-guard/write-claude"      write-claude.json     -- "$H/safety/zone-write-guard.sh"
b "zone-write-guard/edit-tests"        edit-tests.json       -- "$H/safety/zone-write-guard.sh"
b "adversarial-gate/write-grim"        write-grimoires.json  -- "$H/safety/adversarial-review-gate.sh"
b "adversarial-gate/write-completed"   write-completed.json  -- "$H/safety/adversarial-review-gate.sh"

echo ""
echo "== PostToolUse:Write/Edit chain =="
b "write-mutation-logger/write-grim"   write-grimoires.json  -- "$H/audit/write-mutation-logger.sh"
b "write-mutation-logger/edit-tests"   edit-tests.json       -- "$H/audit/write-mutation-logger.sh"
b "karpathy-diff/write-grim-fresh"     write-grimoires.json  --prep ": > '$M/.run/karpathy-task-state.jsonl'" -- "$H/quality/karpathy-surgical-diff-check.sh"
b "karpathy-diff/write-grim-warn"      write-grimoires.json  --prep "cp '$M/fixtures/karpathy-seed.jsonl' '$M/.run/karpathy-task-state.jsonl'" -- "$H/quality/karpathy-surgical-diff-check.sh"
b "karpathy-diff/edit-tests-warn"      edit-tests.json       --prep "cp '$M/fixtures/karpathy-seed.jsonl' '$M/.run/karpathy-task-state.jsonl'" -- "$H/quality/karpathy-surgical-diff-check.sh"

echo ""
echo "== PreToolUse:Skill chain =="
b "team-skill-guard/skill-implement"   skill-implement.json  -- "$H/safety/team-skill-guard.sh"
b "team-skill-guard/skill-implement+TEAM" skill-implement.json --env LOA_TEAM_MEMBER=bench-mate -- "$H/safety/team-skill-guard.sh"
b "spiral-skill-sentinel/skill-implement" skill-implement.json -- "$H/safety/spiral-skill-sentinel.sh"

echo ""
echo "== Stop chain =="
b "run-mode-stop-guard/stop-idle"      stop-idle.json        -- "$H/safety/run-mode-stop-guard.sh"
b "settings-cleanup/small"             stop-idle.json        -- "$H/hygiene/settings-cleanup.sh"
b "settings-cleanup/large"             stop-idle.json        --prep "cp '$M/fixtures/settings.local.large.json' '$M/.claude/settings.local.json'" -- "$H/hygiene/settings-cleanup.sh"

echo ""
echo "== UserPromptSubmit =="
b "post-compact-reminder/no-marker"    prompt-submit.json    --env "HOME=$M" --env "PROJECT_ROOT=$M" -- "$H/post-compact-reminder.sh"
b "post-compact-reminder/marker"       prompt-submit.json    --env "HOME=$M" --env "PROJECT_ROOT=$M" --prep "cp '$M/fixtures/compact-pending' '$M/.run/compact-pending'" -- "$H/post-compact-reminder.sh"

echo ""
echo "== PreToolUse:Skill(plan-and-analyze) — cleanup-context =="
b "cleanup-context/no-context-dir"     skill-implement.json  --env "LOA_CONTEXT_DIR=$M/absent-context" -- "$M/.claude/scripts/cleanup-context.sh" --prompt
b "cleanup-context/full-archive"       skill-implement.json  \
  --env "LOA_CONTEXT_DIR=$M/grimoires/loa/context" \
  --env "LOA_LEDGER=$M/grimoires/loa/ledger.json" \
  --env "LOA_ARCHIVE_BASE=$M/grimoires/loa/archive" \
  --prep "rm -rf '$M/grimoires/loa/context' '$M/grimoires/loa/archive'; mkdir -p '$M/grimoires/loa/context' '$M/grimoires/loa/archive'; cp -r '$M/fixtures/context/.' '$M/grimoires/loa/context/'" \
  -- setsid "$M/.claude/scripts/cleanup-context.sh" --prompt
# ^ setsid: detach from any controlling tty so the script's `read < /dev/tty`
#   fails fast (auto-"Y") instead of blocking the harness.

echo ""
echo "== workflow-boundary scripts (real repo, read-only) =="
bash "$BENCH" --label "beads-health/--json"       --cwd "$REPO_ROOT" --tsv "$RESULTS" --timeout 60 -- "$REPO_ROOT/.claude/scripts/beads/beads-health.sh" --json
bash "$BENCH" --label "beads-health/--quick-json" --cwd "$REPO_ROOT" --tsv "$RESULTS" --timeout 60 -- "$REPO_ROOT/.claude/scripts/beads/beads-health.sh" --quick --json
bash "$BENCH" --label "check-updates/--notify"    --cwd "$REPO_ROOT" --tsv "$RESULTS" --timeout 30 -- "$REPO_ROOT/.claude/scripts/check-updates.sh" --notify
bash "$BENCH" --label "golden-path/source-only"   --cwd "$REPO_ROOT" --tsv "$RESULTS" -- bash -c 'source .claude/scripts/golden-path.sh'

# =============================================================================
# Per-tool-call chain totals
# =============================================================================
echo ""
echo "== per-tool-call chain totals (sum of registered hook chain, ms) =="
total() {  # total <name> <label>...
  local name="$1"; shift
  awk -F'\t' -v labels="$*" -v name="$name" '
    BEGIN { n = split(labels, want, " ") }
    { for (i = 1; i <= n; i++) if ($1 == want[i]) { mean += $4; p95 += $5; hits++ } }
    END { printf "%-38s mean=%8.3fms  p95(sum)=%8.3fms  (%d hooks)\n", name, mean, p95, hits }
  ' "$RESULTS"
}
total "TOTAL per Bash tool call"  "block-destructive/bash-benign" "team-role-guard/bash-benign" "mutation-logger/bash-benign"
total "TOTAL per Write tool call" "team-role-guard-write/write-grim" "spiral-dispatch-guard/write-grim" "zone-write-guard/write-grim" "adversarial-gate/write-grim" "write-mutation-logger/write-grim" "karpathy-diff/write-grim-warn"
total "TOTAL per Edit tool call"  "team-role-guard-write/write-grim" "spiral-dispatch-guard/write-grim" "zone-write-guard/edit-tests" "adversarial-gate/write-grim" "write-mutation-logger/edit-tests" "karpathy-diff/edit-tests-warn"
total "TOTAL per Skill call"      "team-skill-guard/skill-implement" "spiral-skill-sentinel/skill-implement"
total "TOTAL per Stop event"      "run-mode-stop-guard/stop-idle" "settings-cleanup/small"
