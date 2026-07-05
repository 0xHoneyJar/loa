#!/usr/bin/env bash
# =============================================================================
# bench-env.sh — build/refresh the isolated hook-benchmark mirror
# =============================================================================
# Hooks have side effects (append .run/audit.jsonl, append trajectory JSONL,
# append karpathy task state, delete compact markers, archive+delete the
# context dir). To benchmark and golden-capture them WITHOUT touching real
# repo state, we run the LIVE hook files inside a disposable mirror of the
# repo layout. Several hooks derive PROJECT_ROOT from their own physical
# location (BASH_SOURCE), so the hook FILES are copied into the mirror —
# they are re-copied from the repo on every build, so later optimization
# passes automatically measure the current working-tree versions.
#
# Usage:
#   bench-env.sh [mirror_dir]        # default: /tmp/loa-hookbench-$(id -u)
#   eval "$(bench-env.sh --print-root)"   # emit BENCH_ROOT=... only
#
# The mirror contains:
#   .claude/hooks/**                  live copies of all hook scripts
#   .claude/scripts/lib/log-redactor.sh   dependency of block-destructive
#   .claude/scripts/cleanup-context.sh    PreToolUse Skill(plan-and-analyze)
#   .claude/settings.local.json      SMALL fixture (< 64KB -> early-exit path)
#   .claude/settings.local.large.json LARGE fixture (> 64KB -> full path)
#   .loa.config.yaml                 live copy (flatline flags, karpathy cfg)
#   grimoires/loa/zones.yaml         live copy (zone-write-guard patterns)
#   grimoires/loa/ledger.json        synthetic fixture
#   grimoires/loa/a2a/trajectory/    exists -> decision logging is exercised
#   grimoires/loa/context/           synthetic fixture (restored per-run)
#   .run/*.json                      synthetic idle-state fixtures
#   payloads/*.json                  payload templates with __ROOT__ rendered
#   fixtures/                        pristine copies used by --prep restores
# =============================================================================

set -euo pipefail
export LC_ALL=C

PERF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${PERF_DIR}/../../../.." && pwd)"
BENCH_ROOT="${1:-${LOA_BENCH_ROOT:-/tmp/loa-hookbench-$(id -u)}}"

if [[ "${1:-}" == "--print-root" ]]; then
  echo "BENCH_ROOT=${LOA_BENCH_ROOT:-/tmp/loa-hookbench-$(id -u)}"
  exit 0
fi

# Refuse to operate on a path that doesn't look like ours (rm -rf guard).
case "$BENCH_ROOT" in
  *loa-hookbench*) ;;
  *) echo "bench-env.sh: refusing mirror path without 'loa-hookbench' marker: $BENCH_ROOT" >&2; exit 64 ;;
esac

rm -rf "$BENCH_ROOT"
mkdir -p \
  "$BENCH_ROOT/.claude/scripts/lib" \
  "$BENCH_ROOT/.run" \
  "$BENCH_ROOT/payloads" \
  "$BENCH_ROOT/fixtures/context" \
  "$BENCH_ROOT/grimoires/loa/a2a/trajectory" \
  "$BENCH_ROOT/grimoires/loa/context" \
  "$BENCH_ROOT/grimoires/loa/cycles/cycle-bench/sprints/sprint-1" \
  "$BENCH_ROOT/grimoires/loa/archive" \
  "$BENCH_ROOT/tests/unit" \
  "$BENCH_ROOT/.local/state/loa-compact"

# --- live framework files (re-copied every build) ----------------------------
cp -r "$REPO_ROOT/.claude/hooks" "$BENCH_ROOT/.claude/hooks"
cp "$REPO_ROOT/.claude/scripts/lib/log-redactor.sh" "$BENCH_ROOT/.claude/scripts/lib/"
cp "$REPO_ROOT/.claude/scripts/cleanup-context.sh"  "$BENCH_ROOT/.claude/scripts/"
cp "$REPO_ROOT/.loa.config.yaml"                    "$BENCH_ROOT/.loa.config.yaml"
cp "$REPO_ROOT/grimoires/loa/zones.yaml"            "$BENCH_ROOT/grimoires/loa/zones.yaml"

# team-role-guard-write runs `git rev-parse --show-toplevel`; make the mirror
# a real git repo so that code path matches production.
git -C "$BENCH_ROOT" init -q 2>/dev/null || true

# --- synthetic fixtures (deterministic content) ------------------------------
# Idle-state .run fixtures — the production steady state on this repo
# (all autonomous modes jacked out; stop guard walks all three files).
cat > "$BENCH_ROOT/fixtures/sprint-plan-state.json" <<'EOF'
{"state": "JACKED_OUT", "sprints": {"current": null, "completed": ["sprint-1"]}, "timestamps": {"last_activity": "2026-07-05T00:00:00Z"}}
EOF
cat > "$BENCH_ROOT/fixtures/bridge-state.json" <<'EOF'
{"state": "JACKED_OUT", "current_iteration": 3, "timestamps": {"last_activity": "2026-07-05T00:00:00Z"}}
EOF
cat > "$BENCH_ROOT/fixtures/simstim-state.json" <<'EOF'
{"state": "COMPLETED", "phase": "implementation", "timestamps": {"last_activity": "2026-07-05T00:00:00Z"}}
EOF
cp "$BENCH_ROOT/fixtures/sprint-plan-state.json" "$BENCH_ROOT/.run/sprint-plan-state.json"
cp "$BENCH_ROOT/fixtures/bridge-state.json"      "$BENCH_ROOT/.run/bridge-state.json"
cp "$BENCH_ROOT/fixtures/simstim-state.json"     "$BENCH_ROOT/.run/simstim-state.json"

# settings.local.json fixtures for settings-cleanup.sh.
# Small (< 64KB threshold): early-exit path — matches this repo today (55KB).
jq -n '{permissions: {allow: [range(0; 40) | "Bash(echo bench-\(.):*)"]}}' \
  > "$BENCH_ROOT/fixtures/settings.local.small.json"
# Large (> 64KB): full jq-filter path, incl. one >200-char entry that gets
# removed (so the rewrite branch executes).
jq -n '{permissions: {allow: ([range(0; 900) | "Bash(echo bench-entry-number-\(.) --with-some-longer-arguments:*)"] + ["Bash(" + ("x" * 300) + ":*)"])}}' \
  > "$BENCH_ROOT/fixtures/settings.local.large.json"
cp "$BENCH_ROOT/fixtures/settings.local.small.json" "$BENCH_ROOT/.claude/settings.local.json"

# Ledger fixture (cleanup-context archive-path resolution: 2 jq reads).
cat > "$BENCH_ROOT/grimoires/loa/ledger.json" <<'EOF'
{
  "active_cycle": "cycle-bench",
  "cycles": [
    {"id": "cycle-old", "status": "archived", "archived_at": "2026-06-01T00:00:00Z", "archive_path": "grimoires/loa/archive/2026-06-01-cycle-old"},
    {"id": "cycle-bench", "status": "active", "archive_path": "grimoires/loa/archive/2026-07-05-cycle-bench"}
  ]
}
EOF

# Context fixture: 5 files + 1 subdir (2 files) — restored by --prep before
# each cleanup-context full run (the script consumes its input).
for i in 1 2 3 4 5; do
  printf '# context doc %s\n\nbench fixture content line.\n' "$i" \
    > "$BENCH_ROOT/fixtures/context/doc-$i.md"
done
mkdir -p "$BENCH_ROOT/fixtures/context/research"
printf 'nested fixture A\n' > "$BENCH_ROOT/fixtures/context/research/a.md"
printf 'nested fixture B\n' > "$BENCH_ROOT/fixtures/context/research/b.md"
printf '# Context README\n' > "$BENCH_ROOT/fixtures/context/README.md"
cp -r "$BENCH_ROOT/fixtures/context/." "$BENCH_ROOT/grimoires/loa/context/"

# Compact-pending marker fixture (post-compact-reminder deletes it per run).
cat > "$BENCH_ROOT/fixtures/compact-pending" <<'EOF'
{"run_mode": {"active": true, "state": "RUNNING"}, "simstim": {"active": false, "phase": "unknown"}, "timestamp": "2026-07-05T00:00:00Z"}
EOF

# Karpathy over-threshold seed: one prior entry with lines_changed=200
# (> default threshold 100) — puts every measured run in the WARN regime,
# which is this repo's production steady state (.run/karpathy-task-state.jsonl
# already holds 500+ entries).
cat > "$BENCH_ROOT/fixtures/karpathy-seed.jsonl" <<'EOF'
{"ts":"2026-07-05T00:00:00Z","tool":"Write","file":"seed.md","lines_changed":200,"running_total":200,"session_id":"bench-seed"}
EOF

# Sprint COMPLETED fixture dir already created; leave artefacts ABSENT so
# adversarial-review-gate exercises its full BLOCK path (config walk + yq x2
# + 2 artefact validations).

# Bats file referenced by edit-tests payload (realpath resolution target).
cat > "$BENCH_ROOT/tests/unit/bench-example.bats" <<'EOF'
@test "placeholder" {
  run true
  [ "$status" -eq 0 ]
}
EOF

# Empty audit log + karpathy state (prep seeds/clears per combo).
: > "$BENCH_ROOT/.run/audit.jsonl"
: > "$BENCH_ROOT/.run/karpathy-task-state.jsonl"

# --- render payloads ----------------------------------------------------------
for tpl in "$PERF_DIR"/payloads/*.json; do
  sed "s|__ROOT__|$BENCH_ROOT|g" "$tpl" > "$BENCH_ROOT/payloads/$(basename "$tpl")"
done

echo "$BENCH_ROOT"
