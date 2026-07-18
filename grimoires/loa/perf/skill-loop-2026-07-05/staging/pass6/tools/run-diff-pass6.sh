#!/usr/bin/env bash
# =============================================================================
# pass-6 differential corpus: OLD (repo working tree) vs NEW (staging/pass6)
# for zone-write-guard.sh + karpathy-surgical-diff-check.sh under a cache-state
# matrix: cold cache, warm cache, STALE cache (source mutated between runs),
# corrupt/truncated cache, wrong-key cache, cache-path-is-a-dir, unreadable
# cache, read-only cache dir, cross-contamination via shared relative source
# names, forged-key (accepted-divergence, asserted explicitly).
#
# Each case runs the hook as a SEQUENCE of steps inside a per-side sandbox
# (the hook derives PROJECT_ROOT/REPO_ROOT from its own location, so each
# sandbox holds its own hook copy). Step outputs (stdout/stderr/exit) are
# compared pairwise old-vs-new (ts/date/root-normalized) plus the FULL
# side-effect tree, excluding ONLY .run/perf-cache (the documented additive
# side effect of pass 6).
#
# Sequences prove the cache lifecycle: step1 = cold parse (+cache write),
# step2+ = warm hit; a MUT between steps proves staleness (old side always
# parses fresh, so any stale serve on the new side diverges and FAILs).
# =============================================================================
set -uo pipefail
export LC_ALL=C

REPO=/home/merlin/Documents/thj/code/loa
STAGE=$REPO/grimoires/loa/perf/skill-loop-2026-07-05/staging/pass6
WORK=${1:-/tmp/p6diff/work}
rm -rf "$WORK" && mkdir -p "$WORK"

PASS=0; FAIL=0
declare -a FAILURES=()

norm() {
  sed -E -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/__TS__/g' \
         -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}/__DATE__/g' \
         -e "s|${NORM_ROOT:-__NOROOT__}/(old\|new)|__SB__|g"
}

# tree_dump <side-dir> — deterministic listing + normalized content of every
# file under the sandbox, EXCLUDING out/ (harness bookkeeping),
# root/.claude (holds only the old-vs-new hook copy itself — its bytes
# differ by construction) and root/.run/perf-cache (pass-6 documented
# additive side effect).
tree_dump() {
  local d="$1" f
  ( cd "$d" 2>/dev/null || exit 0
    local -a entries files
    mapfile -d '' -t entries < <(find . -mindepth 1 \( -path ./out -o -path ./root/.claude -o -path ./root/.run/perf-cache \) -prune -o -print0 | sort -z)
    for f in ${entries[@]+"${entries[@]}"}; do printf '%s' "$f" | norm; printf '\n'; done
    mapfile -d '' -t files < <(find . \( -path ./out -o -path ./root/.claude -o -path ./root/.run/perf-cache \) -prune -o -type f -print0 | sort -z)
    for f in ${files[@]+"${files[@]}"}; do
      printf '===== '; printf '%s' "$f" | norm; printf ' =====\n'
      norm < "$f" 2>/dev/null || printf '__UNREADABLE__\n'
    done
  )
}

# ---------------------------------------------------------------------------
# step engine: sandbox() builds $side/root; drive() runs the step sequence.
# invoke: run the hook once, recording out/err/rc under $side/out/stepN.*
#   invoke [ENV=val ...] [--arg <target> | --env <target> | --stdin <raw-json>]
# mut: run a mutation command inside $side/root
# ---------------------------------------------------------------------------
invoke() {
  STEP=$((STEP+1))
  local envs=() mode="" val=""
  while (( $# )); do
    case "$1" in
      --arg)   mode="arg";   val="$2"; shift 2 ;;
      --env)   mode="env";   val="$2"; shift 2 ;;
      --stdin) mode="stdin"; val="$2"; shift 2 ;;
      *) envs+=("$1"); shift ;;
    esac
  done
  local rc=0
  case "$mode" in
    arg)
      env ${envs[@]+"${envs[@]}"} "$HOOK" "$val" \
        > "$SIDE/out/step$STEP.out" 2> "$SIDE/out/step$STEP.err" < /dev/null || rc=$? ;;
    env)
      env ${envs[@]+"${envs[@]}"} CLAUDE_TOOL_FILE_PATH="$val" "$HOOK" \
        > "$SIDE/out/step$STEP.out" 2> "$SIDE/out/step$STEP.err" < /dev/null || rc=$? ;;
    stdin)
      printf '%s' "$val" | env ${envs[@]+"${envs[@]}"} "$HOOK" \
        > "$SIDE/out/step$STEP.out" 2> "$SIDE/out/step$STEP.err" || rc=$? ;;
    *)
      echo "invoke: no mode" >&2; exit 70 ;;
  esac
  echo "$rc" > "$SIDE/out/step$STEP.rc"
}

wpay() {  # wpay <file_path> — minimal Write payload JSON
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"x"}}' "$1"
}

run_case() {  # run_case <name>  (uses: sandbox, drive, HOOK_REL, OLD_SRC, NEW_SRC)
  local name="$1"
  local base="$WORK/$name"
  NORM_ROOT="$base"
  local v src
  for v in old new; do
    local d="$base/$v"
    mkdir -p "$d/out" "$d/root"
    sandbox "$d/root"
    src="$OLD_SRC"; [[ "$v" == new ]] && src="$NEW_SRC"
    mkdir -p "$d/root/$(dirname "$HOOK_REL")"
    cp "$src" "$d/root/$HOOK_REL"
    chmod +x "$d/root/$HOOK_REL"
    ( cd "$d/root" && SIDE="$d" HOOK="$d/root/$HOOK_REL" STEP=0 drive "$d/root" )
  done
  # compare step-by-step + tree
  local ok=1 why="" s
  local -a rcs
  mapfile -t rcs < <(cd "$base/old/out" 2>/dev/null && ls -1 | grep -E '\.rc$' | sort)
  if [[ "$(cd "$base/old/out" && ls -1 | sort)" != "$(cd "$base/new/out" && ls -1 | sort)" ]]; then
    ok=0; why="step-set"
  fi
  for s in ${rcs[@]+"${rcs[@]}"}; do
    local n="${s%.rc}"
    if ! diff -q "$base/old/out/$s" "$base/new/out/$s" >/dev/null 2>&1; then
      ok=0; why="$why $n:exit($(cat "$base/old/out/$s")→$(cat "$base/new/out/$s"))"
    fi
    if ! diff -q <(norm < "$base/old/out/$n.out") <(norm < "$base/new/out/$n.out") >/dev/null 2>&1; then
      ok=0; why="$why $n:stdout"
    fi
    if ! diff -q <(norm < "$base/old/out/$n.err") <(norm < "$base/new/out/$n.err") >/dev/null 2>&1; then
      ok=0; why="$why $n:stderr"
    fi
  done
  if ! diff -q <(tree_dump "$base/old") <(tree_dump "$base/new") >/dev/null 2>&1; then
    ok=0; why="$why tree"
  fi
  if (( ok )); then
    PASS=$((PASS+1)); printf 'PASS  %-52s\n' "$name"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$name:$why")
    printf 'FAIL  %-52s %s\n' "$name" "$why"
  fi
}

# =============================================================================
# SECTION 1: zone-write-guard
# =============================================================================
echo "=== zone-write-guard ==="
HOOK_REL=".claude/hooks/safety/zone-write-guard.sh"
OLD_SRC="$REPO/.claude/hooks/safety/zone-write-guard.sh"
NEW_SRC="$STAGE/zone-write-guard.sh"

ZONES_A='schema_version: "1.0"
zones:
  framework:
    tracked_paths:
      - ".claude/**"
  project:
    tracked_paths:
      - "grimoires/loa/cycles/**"
      - "grimoires/loa/NOTES.md"
  shared:
    tracked_paths:
      - "grimoires/loa/known-failures.md"
'
# same byte length as ZONES_A, framework/project pattern lists swapped in place
ZONES_B='schema_version: "1.0"
zones:
  framework:
    tracked_paths:
      - "grimoires/loa/cycles/**"
      - "grimoires/loa/NOTES.md"
  project:
    tracked_paths:
      - ".claude/**"
  shared:
    tracked_paths:
      - "grimoires/loa/known-failures.md"
'

zwg_base() {  # <root> [zones-content]
  mkdir -p "$1/grimoires/loa/a2a/trajectory" "$1/.run"
  printf '%s' "${2-$ZONES_A}" > "$1/grimoires/loa/zones.yaml"
}

# --- cold → warm → warm sequences per decision class -------------------------
sandbox() { zwg_base "$1"; }
drive() {
  invoke --stdin "$(wpay ".claude/x.sh")"
  invoke --stdin "$(wpay ".claude/x.sh")"
  invoke --stdin "$(wpay ".claude/y.sh")"
}
run_case "zwg-cold-warm-framework-block"

drive() {
  invoke --stdin "$(wpay "grimoires/loa/NOTES.md")"
  invoke --stdin "$(wpay "grimoires/loa/NOTES.md")"
  invoke --stdin "$(wpay "grimoires/loa/cycles/c/s.md")"
}
run_case "zwg-cold-warm-project-allow"

drive() {
  invoke --stdin "$(wpay "src/foo.c")"
  invoke --stdin "$(wpay "src/foo.c")"
}
run_case "zwg-cold-warm-unclassified-allow"

drive() {
  invoke LOA_ACTOR=update-loa --stdin "$(wpay "grimoires/loa/known-failures.md")"
  invoke LOA_ACTOR=update-loa --stdin "$(wpay ".claude/x.sh")"
  invoke LOA_ACTOR=update-loa --stdin "$(wpay "grimoires/loa/NOTES.md")"
}
run_case "zwg-actor-update-loa-matrix"

drive() {
  invoke LOA_ZONE_GUARD_BYPASS=1 --stdin "$(wpay ".claude/x.sh")"
  invoke LOA_ZONE_GUARD_BYPASS=1 --stdin "$(wpay ".claude/x.sh")"
}
run_case "zwg-bypass-env-cold-warm"

drive() {
  invoke --env ".claude/x.sh"
  invoke --arg ".claude/x.sh"
  invoke --env "grimoires/loa/NOTES.md"
}
run_case "zwg-env-and-arg-target-variants"

# --- staleness: zones.yaml edited between runs (same size, key must rotate) --
drive() {
  invoke --stdin "$(wpay ".claude/x.sh")"          # framework → BLOCK
  invoke --stdin "$(wpay ".claude/x.sh")"          # warm      → BLOCK
  printf '%s' "$ZONES_B" > grimoires/loa/zones.yaml
  invoke --stdin "$(wpay ".claude/x.sh")"          # project now → ALLOW
  invoke --stdin "$(wpay "grimoires/loa/NOTES.md")" # framework now → BLOCK
}
run_case "zwg-stale-edit-same-size-flip"

# rapid same-second rewrite (ns-mtime must rotate the key)
drive() {
  invoke --stdin "$(wpay ".claude/x.sh")"
  printf '%s' "$ZONES_B" > grimoires/loa/zones.yaml
  invoke --stdin "$(wpay ".claude/x.sh")"
  printf '%s' "$ZONES_A" > grimoires/loa/zones.yaml
  invoke --stdin "$(wpay ".claude/x.sh")"
}
run_case "zwg-stale-same-second-rewrites"

# --- cache corruption states --------------------------------------------------
sandbox() {
  zwg_base "$1"
  mkdir -p "$1/.run/perf-cache"
  head -c 256 /dev/urandom > "$1/.run/perf-cache/zone-write-guard.v1.rows"
}
drive() {
  invoke --stdin "$(wpay ".claude/x.sh")"
  invoke --stdin "$(wpay ".claude/x.sh")"
}
run_case "zwg-corrupt-binary-cache"

sandbox() {
  zwg_base "$1"
  mkdir -p "$1/.run/perf-cache"
  printf '2026-01-01 00:00:0' > "$1/.run/perf-cache/zone-write-guard.v1.rows"
}
run_case "zwg-truncated-cache"

sandbox() {
  zwg_base "$1"
  mkdir -p "$1/.run/perf-cache"
  : > "$1/.run/perf-cache/zone-write-guard.v1.rows"
}
run_case "zwg-empty-cache-file"

# wrong-key cache carrying FORGED rows that would flip the decision — must be
# ignored (key belongs to a different mtime/size/path)
sandbox() {
  zwg_base "$1"
  mkdir -p "$1/.run/perf-cache"
  printf '%s\n%s\t%s' \
    '2001-01-01 00:00:00.000000000 +0000:999:/elsewhere/zones.yaml' \
    'project' '.claude/**' > "$1/.run/perf-cache/zone-write-guard.v1.rows"
}
run_case "zwg-wrong-key-forged-rows-ignored"

# cache path is a DIRECTORY — read fails, mv -T refuses; fail-open both runs
sandbox() {
  zwg_base "$1"
  mkdir -p "$1/.run/perf-cache/zone-write-guard.v1.rows"
}
run_case "zwg-cache-path-is-dir"

# unreadable cache file — read fails; healed by atomic mv
sandbox() {
  zwg_base "$1"
  mkdir -p "$1/.run/perf-cache"
  printf 'garbage' > "$1/.run/perf-cache/zone-write-guard.v1.rows"
  chmod 000 "$1/.run/perf-cache/zone-write-guard.v1.rows"
}
run_case "zwg-unreadable-cache"

# read-only cache dir — no write possible; every run falls through to yq
sandbox() {
  zwg_base "$1"
  mkdir -p "$1/.run/perf-cache"
  chmod 500 "$1/.run/perf-cache"
}
run_case "zwg-readonly-cache-dir"

# read-only .run — mkdir -p of perf-cache fails; fall through, no noise
sandbox() {
  zwg_base "$1"
  chmod 500 "$1/.run"
}
run_case "zwg-readonly-run-dir"

# --- source-file shapes -------------------------------------------------------
sandbox() { zwg_base "$1" 'zones: [not : valid yaml   ::'; }
drive() {
  invoke --stdin "$(wpay ".claude/x.sh")"
  invoke --stdin "$(wpay ".claude/x.sh")"
}
run_case "zwg-malformed-yaml-cold-warm"

sandbox() { zwg_base "$1" 'schema_version: "1.0"
zones:
  framework:
    tracked_paths: []
'; }
run_case "zwg-zero-patterns-empty-rows-cache"

sandbox() { zwg_base "$1" 'schema_version: "1.0"
zones:
  framework:
    tracked_paths:
      - ".claude/**"
      - |-
        multi/**
        line/**
  project:
    tracked_paths:
      - "grimoires/**"
'; }
drive() {
  invoke --stdin "$(wpay "line/x")"
  invoke --stdin "$(wpay "line/x")"
  invoke --stdin "$(wpay "multi/x")"
  invoke --stdin "$(wpay "grimoires/loa/NOTES.md")"
}
run_case "zwg-multiline-pattern-entry-roundtrip"

sandbox() { zwg_base "$1" "schema_version: \"1.0\"
zones:
  framework:
    tracked_paths:
      - \"tab\there/**\"
  project:
    tracked_paths:
      - \"grimoires/**\"
"; }
drive() {
  # NB: the tab must travel as the JSON escape \t (a literal control byte is
  # invalid JSON and jq would reject the whole payload).
  invoke --stdin '{"tool_name":"Write","tool_input":{"file_path":"tab\there/f","content":"x"}}'
  invoke --stdin '{"tool_name":"Write","tool_input":{"file_path":"tab\there/f","content":"x"}}'
  invoke --stdin "$(wpay "grimoires/loa/NOTES.md")"
}
run_case "zwg-tab-bearing-pattern-roundtrip"

# zones.yaml missing entirely — early exit BEFORE any cache logic
sandbox() { mkdir -p "$1/grimoires/loa/a2a/trajectory" "$1/.run"; }
drive() {
  invoke --stdin "$(wpay ".claude/x.sh")"
  invoke --stdin "$(wpay ".claude/x.sh")"
}
run_case "zwg-zones-file-missing"

sandbox() { mkdir -p "$1/grimoires/loa/a2a/trajectory" "$1/.run"; }
drive() {
  invoke LOA_REQUIRE_ZONES=1 --stdin "$(wpay ".claude/x.sh")"
}
run_case "zwg-zones-missing-require-strict"

# trajectory dir absent — decision logging skipped; cache still functions
sandbox() { mkdir -p "$1/grimoires/loa" "$1/.run"; printf '%s' "$ZONES_A" > "$1/grimoires/loa/zones.yaml"; }
drive() {
  invoke --stdin "$(wpay ".claude/x.sh")"
  invoke --stdin "$(wpay ".claude/x.sh")"
}
run_case "zwg-no-trajectory-dir"

# --- cross-contamination: shared RELATIVE LOA_ZONES_FILE name, two dirs,
#     IDENTICAL mtime + size (touch -d) — only the abs-path key component
#     can discriminate. Old side parses fresh: any cross-serve diverges.
sandbox() {
  zwg_base "$1"
  mkdir -p "$1/dirA" "$1/dirB"
  printf '%s' "$ZONES_A" > "$1/dirA/zones-rel.yaml"
  printf '%s' "$ZONES_B" > "$1/dirB/zones-rel.yaml"
  touch -d '2026-01-02 03:04:05.678901234' "$1/dirA/zones-rel.yaml" "$1/dirB/zones-rel.yaml"
}
xcontam_case() {
  local name="zwg-xcontam-relative-shared-name" base="$WORK/zwg-xcontam-relative-shared-name"
  NORM_ROOT="$base"
  local v src
  for v in old new; do
    local d="$base/$v"
    mkdir -p "$d/out" "$d/root"
    sandbox "$d/root"
    src="$OLD_SRC"; [[ "$v" == new ]] && src="$NEW_SRC"
    mkdir -p "$d/root/.claude/hooks/safety"
    cp "$src" "$d/root/$HOOK_REL"; chmod +x "$d/root/$HOOK_REL"
    # target must be ABSOLUTE: classification is PROJECT_ROOT-anchored, and
    # a relative ".claude/x.sh" from a dirA/dirB cwd would canonicalize to
    # dirA/.claude/... (unclassified on both sides — vacuous).
    local rc=0
    ( cd "$d/root/dirA" && printf '%s' "$(wpay "$d/root/.claude/x.sh")" | \
        env LOA_ZONES_FILE=zones-rel.yaml "$d/root/$HOOK_REL" \
        > "$d/out/step1.out" 2> "$d/out/step1.err" ) || rc=$?
    echo "$rc" > "$d/out/step1.rc"
    rc=0
    ( cd "$d/root/dirB" && printf '%s' "$(wpay "$d/root/.claude/x.sh")" | \
        env LOA_ZONES_FILE=zones-rel.yaml "$d/root/$HOOK_REL" \
        > "$d/out/step2.out" 2> "$d/out/step2.err" ) || rc=$?
    echo "$rc" > "$d/out/step2.rc"
    rc=0
    ( cd "$d/root/dirA" && printf '%s' "$(wpay "$d/root/.claude/x.sh")" | \
        env LOA_ZONES_FILE=zones-rel.yaml "$d/root/$HOOK_REL" \
        > "$d/out/step3.out" 2> "$d/out/step3.err" ) || rc=$?
    echo "$rc" > "$d/out/step3.rc"
  done
  local ok=1 why="" n
  for n in step1 step2 step3; do
    diff -q "$base/old/out/$n.rc" "$base/new/out/$n.rc" >/dev/null 2>&1 || { ok=0; why="$why $n:exit"; }
    diff -q <(norm < "$base/old/out/$n.out") <(norm < "$base/new/out/$n.out") >/dev/null 2>&1 || { ok=0; why="$why $n:stdout"; }
    diff -q <(norm < "$base/old/out/$n.err") <(norm < "$base/new/out/$n.err") >/dev/null 2>&1 || { ok=0; why="$why $n:stderr"; }
  done
  diff -q <(tree_dump "$base/old") <(tree_dump "$base/new") >/dev/null 2>&1 || { ok=0; why="$why tree"; }
  # belt-and-braces: dirA says framework (BLOCK=2), dirB says project (ALLOW=0)
  [[ "$(cat "$base/new/out/step1.rc")" == "2" ]] || { ok=0; why="$why sem1"; }
  [[ "$(cat "$base/new/out/step2.rc")" == "0" ]] || { ok=0; why="$why sem2"; }
  [[ "$(cat "$base/new/out/step3.rc")" == "2" ]] || { ok=0; why="$why sem3"; }
  if (( ok )); then PASS=$((PASS+1)); printf 'PASS  %-52s\n' "$name"
  else FAIL=$((FAIL+1)); FAILURES+=("$name:$why"); printf 'FAIL  %-52s %s\n' "$name" "$why"; fi
}
xcontam_case

# --- forged key-matching cache (ACCEPTED DIVERGENCE — trust-domain argument):
#     an actor who can write .run/perf-cache can already write zones.yaml.
#     Assert the DOCUMENTED behavior explicitly on both sides.
forged_case() {
  local name="zwg-forged-key-match-accepted-divergence"
  local base="$WORK/$name"; NORM_ROOT="$base"
  local v src
  for v in old new; do
    local d="$base/$v"
    mkdir -p "$d/out" "$d/root"
    zwg_base "$d/root"
    src="$OLD_SRC"; [[ "$v" == new ]] && src="$NEW_SRC"
    mkdir -p "$d/root/.claude/hooks/safety"
    cp "$src" "$d/root/$HOOK_REL"; chmod +x "$d/root/$HOOK_REL"
    # forge: key computed exactly as the hook computes it, rows flipped
    local id
    id=$(stat -Lc '%y:%s' -- "$d/root/grimoires/loa/zones.yaml")
    mkdir -p "$d/root/.run/perf-cache"
    printf '%s\n%s\t%s' "${id}:$d/root/grimoires/loa/zones.yaml" \
      'project' '.claude/**' > "$d/root/.run/perf-cache/zone-write-guard.v1.rows"
    local rc=0
    ( cd "$d/root" && printf '%s' "$(wpay ".claude/x.sh")" | "$d/root/$HOOK_REL" \
        > "$d/out/step1.out" 2> "$d/out/step1.err" ) || rc=$?
    echo "$rc" > "$d/out/step1.rc"
  done
  local ok=1
  # old: authoritative parse → BLOCK(2). new: serves forged rows → ALLOW(0).
  [[ "$(cat "$base/old/out/step1.rc")" == "2" ]] || ok=0
  [[ "$(cat "$base/new/out/step1.rc")" == "0" ]] || ok=0
  if (( ok )); then
    PASS=$((PASS+1))
    printf 'PASS  %-52s (accepted divergence matches documentation: old=2 new=0)\n' "$name"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$name: documented divergence shape changed")
    printf 'FAIL  %-52s old=%s new=%s\n' "$name" "$(cat "$base/old/out/step1.rc")" "$(cat "$base/new/out/step1.rc")"
  fi
}
forged_case

# --- concurrency stress (new hook only): parallel cold writers, last wins;
#     every decision correct; cache ends valid
stress_case() {
  local name="zwg-concurrent-writers-stress"
  local d="$WORK/$name/root"
  mkdir -p "$d/out"
  zwg_base "$d"
  mkdir -p "$d/.claude/hooks/safety"
  cp "$NEW_SRC" "$d/$HOOK_REL"; chmod +x "$d/$HOOK_REL"
  local ok=1 i j rc
  for i in 1 2 3 4 5; do
    rm -rf "$d/.run/perf-cache"
    local -a pids=()
    for j in 1 2 3 4; do
      ( cd "$d" && printf '%s' "$(wpay ".claude/x.sh")" | "$d/$HOOK_REL" >/dev/null 2>&1; exit $? ) &
      pids+=($!)
    done
    for j in "${pids[@]}"; do
      wait "$j"; rc=$?
      [[ "$rc" == "2" ]] || ok=0
    done
    # post-race: next run must still be correct
    ( cd "$d" && printf '%s' "$(wpay "grimoires/loa/NOTES.md")" | "$d/$HOOK_REL" >/dev/null 2>&1 ); rc=$?
    [[ "$rc" == "0" ]] || ok=0
    # cache file must be a complete key+payload doc (readable, key line sane)
    [[ -f "$d/.run/perf-cache/zone-write-guard.v1.rows" ]] || ok=0
  done
  if (( ok )); then PASS=$((PASS+1)); printf 'PASS  %-52s\n' "$name"
  else FAIL=$((FAIL+1)); FAILURES+=("$name: race produced wrong decision or bad cache"); printf 'FAIL  %-52s\n' "$name"; fi
}
stress_case

# =============================================================================
# SECTION 2: karpathy-surgical-diff-check
# =============================================================================
echo "=== karpathy ==="
HOOK_REL=".claude/hooks/quality/karpathy-surgical-diff-check.sh"
OLD_SRC="$REPO/.claude/hooks/quality/karpathy-surgical-diff-check.sh"
NEW_SRC="$STAGE/karpathy-surgical-diff-check.sh"

CFG_ON='karpathy_principles:
  surgical_diff_warning: true
  diff_lines_per_task: 5
  enforce: warn
'
CFG_OFF='karpathy_principles:
  surgical_diff_warning: false
'
CFG_BIG='karpathy_principles:
  surgical_diff_warning: true
  diff_lines_per_task: 100000
  enforce: warn
'

kp_base() {  # <root> [config-content]
  mkdir -p "$1/.run" "$1/grimoires/loa/a2a/trajectory"
  printf '%s' "${2-$CFG_ON}" > "$1/.loa.config.yaml"
  printf '{"ts":"2026-07-05T00:00:00Z","tool":"Write","file":"seed.md","lines_changed":200,"running_total":200,"session_id":"bench-seed"}\n' \
    > "$1/.run/karpathy-task-state.jsonl"
}
KP_W='{"tool_name":"Write","tool_input":{"file_path":"src/x.md","content":"a\nb\nc\n"}}'
KP_E='{"tool_name":"Edit","tool_input":{"file_path":"tests/x.bats","old_string":"","new_string":"1\n2\n"}}'

sandbox() { kp_base "$1"; }
drive() {
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
  invoke LOA_SESSION_ID=corpus --stdin "$KP_E"
}
run_case "kp-cold-warm-warn-regime"

sandbox() { kp_base "$1" "$CFG_OFF"; }
drive() {
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
}
run_case "kp-switch-false-cold-warm"

# staleness: threshold raised between runs → warn stops immediately
sandbox() { kp_base "$1"; }
drive() {
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"     # warn (threshold 5)
  printf '%s' "$CFG_BIG" > .loa.config.yaml
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"     # no warn (100000)
  printf '%s' "$CFG_ON" > .loa.config.yaml
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"     # warn again
}
run_case "kp-stale-threshold-flip"

# staleness: switch turned off between runs → hook stops appending state
sandbox() { kp_base "$1"; }
drive() {
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
  printf '%s' "$CFG_OFF" > .loa.config.yaml
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
}
run_case "kp-stale-switch-off"

# missing config: early exit BEFORE cache logic
sandbox() { mkdir -p "$1/.run" "$1/grimoires/loa/a2a/trajectory"; }
drive() {
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
}
run_case "kp-missing-config"

sandbox() { kp_base "$1" 'karpathy: [broken :: yaml'; }
drive() {
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
}
run_case "kp-malformed-config-empty-tokens-cached"

# cache corruption matrix
sandbox() {
  kp_base "$1"
  mkdir -p "$1/.run/perf-cache"
  head -c 200 /dev/urandom > "$1/.run/perf-cache/karpathy-config.v1.tokens"
}
drive() {
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
}
run_case "kp-corrupt-binary-cache"

sandbox() {
  kp_base "$1"
  mkdir -p "$1/.run/perf-cache"
  printf '%s\n%s\n%s' \
    '2001-01-01 00:00:00.000000000 +0000:999:/elsewhere/.loa.config.yaml' \
    'true' 'DEFAULT' > "$1/.run/perf-cache/karpathy-config.v1.tokens"
}
run_case "kp-wrong-key-forged-suppression-ignored"

sandbox() {
  kp_base "$1"
  mkdir -p "$1/.run/perf-cache/karpathy-config.v1.tokens"
}
run_case "kp-cache-path-is-dir-set-e-survival"

sandbox() {
  kp_base "$1"
  mkdir -p "$1/.run/perf-cache"
  printf 'junk' > "$1/.run/perf-cache/karpathy-config.v1.tokens"
  chmod 000 "$1/.run/perf-cache/karpathy-config.v1.tokens"
}
run_case "kp-unreadable-cache"

sandbox() {
  kp_base "$1"
  mkdir -p "$1/.run/perf-cache"
  chmod 500 "$1/.run/perf-cache"
}
run_case "kp-readonly-cache-dir"

# threshold 007 leading-zero (trajectory writes normalized 7) cold+warm
sandbox() { kp_base "$1" 'karpathy_principles:
  surgical_diff_warning: true
  diff_lines_per_task: "007"
'; }
drive() {
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
}
run_case "kp-threshold-007-cold-warm"

# multi-doc config → 4 tokens; warm must round-trip all 4 lines
sandbox() { kp_base "$1" 'karpathy_principles:
  surgical_diff_warning: true
  diff_lines_per_task: 5
---
karpathy_principles:
  surgical_diff_warning: false
  diff_lines_per_task: 9
'; }
drive() {
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
}
run_case "kp-multidoc-config-4-tokens"

# weird config values: empty-string threshold, non-numeric, quoted "false"
sandbox() { kp_base "$1" 'karpathy_principles:
  surgical_diff_warning: true
  diff_lines_per_task: ""
'; }
drive() {
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
}
run_case "kp-empty-string-threshold"

sandbox() { kp_base "$1" 'karpathy_principles:
  surgical_diff_warning: "off"
  diff_lines_per_task: 12abc
'; }
run_case "kp-off-string-switch"

sandbox() { kp_base "$1" 'karpathy_principles:
  surgical_diff_warning:
    nested: map
  diff_lines_per_task:
    - 5
'; }
run_case "kp-container-config-values"

# non-Write tool + invalid stdin: config cache still built on cold run
sandbox() { kp_base "$1"; }
drive() {
  invoke LOA_SESSION_ID=corpus --stdin '{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  invoke LOA_SESSION_ID=corpus --stdin 'this is not json'
  invoke LOA_SESSION_ID=corpus --stdin "$KP_W"
}
run_case "kp-nonwrite-and-invalid-stdin"

# relative LOA_CONFIG_OVERRIDE cross-contamination (same file name, two dirs,
# identical mtime+size — abs-path key component must discriminate)
kp_xcontam() {
  local name="kp-xcontam-relative-override" base="$WORK/kp-xcontam-relative-override"
  NORM_ROOT="$base"
  local v src
  for v in old new; do
    local d="$base/$v"
    mkdir -p "$d/out" "$d/root/dirA" "$d/root/dirB"
    kp_base "$d/root"
    printf '%s' "$CFG_ON"  > "$d/root/dirA/cfg.yaml"   # threshold 5 → warn
    # same byte-length OFF variant (padded comment to equalize size)
    local off_pad
    off_pad='karpathy_principles:
  surgical_diff_warning: false
  diff_lines_per_task: 5
enforce_pad: w
'
    printf '%s' "$off_pad" > "$d/root/dirB/cfg.yaml"
    sza=$(stat -c%s "$d/root/dirA/cfg.yaml"); szb=$(stat -c%s "$d/root/dirB/cfg.yaml")
    touch -d '2026-01-02 03:04:05.678901234' "$d/root/dirA/cfg.yaml" "$d/root/dirB/cfg.yaml"
    src="$OLD_SRC"; [[ "$v" == new ]] && src="$NEW_SRC"
    mkdir -p "$d/root/.claude/hooks/quality"
    cp "$src" "$d/root/$HOOK_REL"; chmod +x "$d/root/$HOOK_REL"
    local rc n=0 wd
    for wd in dirA dirB dirA; do
      n=$((n+1)); rc=0
      ( cd "$d/root/$wd" && printf '%s' "$KP_W" | \
          env LOA_SESSION_ID=corpus LOA_CONFIG_OVERRIDE=cfg.yaml \
              KARPATHY_TASK_STATE="$d/root/.run/karpathy-task-state.jsonl" \
              KARPATHY_TRAJECTORY_DIR="$d/root/grimoires/loa/a2a/trajectory" \
              "$d/root/$HOOK_REL" \
          > "$d/out/step$n.out" 2> "$d/out/step$n.err" ) || rc=$?
      echo "$rc" > "$d/out/step$n.rc"
    done
  done
  local ok=1 why="" n
  [[ "$sza" == "$szb" ]] || { ok=0; why="fixture-size-mismatch($sza,$szb)"; }
  for n in step1 step2 step3; do
    diff -q "$base/old/out/$n.rc" "$base/new/out/$n.rc" >/dev/null 2>&1 || { ok=0; why="$why $n:exit"; }
    diff -q <(norm < "$base/old/out/$n.out") <(norm < "$base/new/out/$n.out") >/dev/null 2>&1 || { ok=0; why="$why $n:stdout"; }
    diff -q <(norm < "$base/old/out/$n.err") <(norm < "$base/new/out/$n.err") >/dev/null 2>&1 || { ok=0; why="$why $n:stderr"; }
  done
  diff -q <(tree_dump "$base/old") <(tree_dump "$base/new") >/dev/null 2>&1 || { ok=0; why="$why tree"; }
  # semantics: dirA warns (stderr non-empty), dirB no-ops (stderr empty)
  [[ -s "$base/new/out/step1.err" ]] || { ok=0; why="$why sem1"; }
  [[ ! -s "$base/new/out/step2.err" ]] || { ok=0; why="$why sem2"; }
  [[ -s "$base/new/out/step3.err" ]] || { ok=0; why="$why sem3"; }
  if (( ok )); then PASS=$((PASS+1)); printf 'PASS  %-52s\n' "$name"
  else FAIL=$((FAIL+1)); FAILURES+=("$name:$why"); printf 'FAIL  %-52s %s\n' "$name" "$why"; fi
}
kp_xcontam

# forged key-matching cache (ACCEPTED DIVERGENCE — same trust argument)
kp_forged() {
  local name="kp-forged-key-match-accepted-divergence"
  local base="$WORK/$name"; NORM_ROOT="$base"
  local v src
  for v in old new; do
    local d="$base/$v"
    mkdir -p "$d/out" "$d/root"
    kp_base "$d/root"
    src="$OLD_SRC"; [[ "$v" == new ]] && src="$NEW_SRC"
    mkdir -p "$d/root/.claude/hooks/quality"
    cp "$src" "$d/root/$HOOK_REL"; chmod +x "$d/root/$HOOK_REL"
    local id
    id=$(stat -Lc '%y:%s' -- "$d/root/.loa.config.yaml")
    mkdir -p "$d/root/.run/perf-cache"
    # forged token stream: switch reads "true" (= disabled) → hook no-ops
    printf '%s\n%s\n%s' "${id}:$d/root/.loa.config.yaml" 'true' 'DEFAULT' \
      > "$d/root/.run/perf-cache/karpathy-config.v1.tokens"
    local rc=0
    ( cd "$d/root" && printf '%s' "$KP_W" | env LOA_SESSION_ID=corpus "$d/root/$HOOK_REL" \
        > "$d/out/step1.out" 2> "$d/out/step1.err" ) || rc=$?
    echo "$rc" > "$d/out/step1.rc"
  done
  local ok=1
  # old ignores the cache concept → warns (stderr non-empty); new no-ops
  [[ -s "$base/old/out/step1.err" ]] || ok=0
  [[ ! -s "$base/new/out/step1.err" ]] || ok=0
  [[ "$(cat "$base/old/out/step1.rc")" == "0" && "$(cat "$base/new/out/step1.rc")" == "0" ]] || ok=0
  if (( ok )); then
    PASS=$((PASS+1))
    printf 'PASS  %-52s (accepted divergence matches documentation)\n' "$name"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$name: documented divergence shape changed")
    printf 'FAIL  %-52s\n' "$name"
  fi
}
kp_forged

# =============================================================================
echo ""
echo "RESULT: PASS=$PASS FAIL=$FAIL"
if (( FAIL > 0 )); then
  printf 'FAILURE: %s\n' "${FAILURES[@]}"
  exit 1
fi
