#!/usr/bin/env bash
# =============================================================================
# exec-census.sh — external-process-spawn census per hook invocation
# =============================================================================
# strace is unusable on this host (kernel.yama.ptrace_scope=2 blocks even
# PTRACE_TRACEME for unprivileged processes), so this uses a PATH-shim
# interceptor instead: a shim directory is prepended to PATH containing a
# logging wrapper for every external binary the hooks use. Each wrapper
# appends its name to a spawn log (bash-builtin echo — no extra spawn) and
# exec's the real binary, so hook behavior is unchanged and each PATH-resolved
# external spawn produces exactly one log line.
#
# Coverage notes (documented limitation):
#   - Spawns by ABSOLUTE path are not intercepted at that call site (only the
#     log-redactor.sh helper is invoked this way, by block-destructive-bash's
#     block path; its own internal sed/awk children ARE intercepted).
#   - The hook's own interpreter (env+bash) is NOT counted — the census counts
#     CHILD spawns per invocation. Add ~2 execve (env, bash) for the true
#     kernel-level total; Claude Code adds 1 more (sh -c wrapper).
#   - Pure subshell forks (command substitution running only builtins) are
#     invisible here; they cost a fork (~0.5ms) but no exec.
#
# Output: census.tsv (label / child_spawns / breakdown) + human table.
# =============================================================================

set -euo pipefail
export LC_ALL=C

PERF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CENSUS="${BENCH_CENSUS:-$PERF_DIR/census.tsv}"

M="$("$PERF_DIR/bench-env.sh")"
H="$M/.claude/hooks"
TRACE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loa-census.XXXXXX")"
trap 'rm -rf "$TRACE_DIR"' EXIT
SHIM_DIR="$TRACE_DIR/shims"
SPAWN_LOG="$TRACE_DIR/spawns.log"
mkdir -p "$SHIM_DIR"

# Binaries the hook set uses (from reading every hook source). Deliberately
# excludes bash/sh/env so the hook's own interpreter chain isn't counted.
BINS=(grep jq yq date mkdir realpath git cat head tail tr wc awk sed stat
      sort uniq find cp mv rm dirname basename timeout touch ln install)

for b in "${BINS[@]}"; do
  real="$(command -v "$b" 2>/dev/null)" || continue
  case "$real" in "$SHIM_DIR"/*) continue ;; esac
  printf '#!/bin/bash\necho %s >> %q\nexec %q "$@"\n' "$b" "$SPAWN_LOG" "$real" > "$SHIM_DIR/$b"
  chmod +x "$SHIM_DIR/$b"
done

printf 'label\tchild_spawns\tbreakdown\n' > "$CENSUS"

census() {  # census <label> <payload|-> [ENV=VAL...] -- cmd...
  local lbl="$1" pl="$2"; shift 2
  local envs=( "PATH=$SHIM_DIR:$PATH" )
  while [[ "$1" != "--" ]]; do envs+=( "$1" ); shift; done
  shift
  : > "$SPAWN_LOG"
  ( cd "$M"
    if [[ "$pl" == "-" ]]; then
      env "${envs[@]}" "$@" > /dev/null 2>&1 < /dev/null || true
    else
      env "${envs[@]}" "$@" < "$M/payloads/$pl" > /dev/null 2>&1 || true
    fi
  )
  local n breakdown
  n=$(wc -l < "$SPAWN_LOG" | tr -d ' ')
  breakdown=$(sort "$SPAWN_LOG" | uniq -c | sort -rn | awk '{printf "%s%s x%s", (NR>1?", ":""), $2, $1}')
  printf '%s\t%s\t%s\n' "$lbl" "$n" "$breakdown" >> "$CENSUS"
  printf '%-44s spawns=%-4s %s\n' "$lbl" "$n" "$breakdown"
}

census "block-destructive/bash-benign"      bash-benign.json      -- "$H/safety/block-destructive-bash.sh"
census "block-destructive/bash-mutating"    bash-mutating.json    -- "$H/safety/block-destructive-bash.sh"
census "block-destructive/bash-destructive" bash-destructive.json -- "$H/safety/block-destructive-bash.sh"
census "block-destructive/bash-blocked"     bash-blocked.json     -- "$H/safety/block-destructive-bash.sh"
census "team-role-guard/bash-benign"        bash-benign.json      -- "$H/safety/team-role-guard.sh"
census "team-role-guard/bash-mutating+TEAM" bash-mutating.json    LOA_TEAM_MEMBER=bench-mate -- "$H/safety/team-role-guard.sh"
census "mutation-logger/bash-benign"        bash-benign.json      -- "$H/audit/mutation-logger.sh"
census "mutation-logger/bash-mutating"      bash-mutating.json    -- "$H/audit/mutation-logger.sh"
census "team-role-guard-write/write-grim"   write-grimoires.json  -- "$H/safety/team-role-guard-write.sh"
census "spiral-dispatch-guard/write-grim"   write-grimoires.json  -- "$H/safety/spiral-dispatch-guard.sh"
census "zone-write-guard/write-grim"        write-grimoires.json  -- "$H/safety/zone-write-guard.sh"
census "zone-write-guard/write-claude"      write-claude.json     -- "$H/safety/zone-write-guard.sh"
census "adversarial-gate/write-grim"        write-grimoires.json  -- "$H/safety/adversarial-review-gate.sh"
census "adversarial-gate/write-completed"   write-completed.json  -- "$H/safety/adversarial-review-gate.sh"
census "write-mutation-logger/write-grim"   write-grimoires.json  -- "$H/audit/write-mutation-logger.sh"
cp "$M/fixtures/karpathy-seed.jsonl" "$M/.run/karpathy-task-state.jsonl"
census "karpathy-diff/write-grim-warn"      write-grimoires.json  -- "$H/quality/karpathy-surgical-diff-check.sh"
census "team-skill-guard/skill-implement"   skill-implement.json  -- "$H/safety/team-skill-guard.sh"
census "spiral-skill-sentinel/skill-impl"   skill-implement.json  -- "$H/safety/spiral-skill-sentinel.sh"
census "run-mode-stop-guard/stop-idle"      stop-idle.json        -- "$H/safety/run-mode-stop-guard.sh"
census "settings-cleanup/small"             stop-idle.json        -- "$H/hygiene/settings-cleanup.sh"
cp "$M/fixtures/settings.local.large.json" "$M/.claude/settings.local.json"
census "settings-cleanup/large"             stop-idle.json        -- "$H/hygiene/settings-cleanup.sh"
census "post-compact-reminder/no-marker"    prompt-submit.json    "HOME=$M" "PROJECT_ROOT=$M" -- "$H/post-compact-reminder.sh"
cp "$M/fixtures/compact-pending" "$M/.run/compact-pending"
census "post-compact-reminder/marker"       prompt-submit.json    "HOME=$M" "PROJECT_ROOT=$M" -- "$H/post-compact-reminder.sh"

echo ""
echo "census written to $CENSUS"
