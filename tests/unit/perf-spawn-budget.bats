#!/usr/bin/env bats
# =============================================================================
# perf-spawn-budget.bats — deterministic regression guard for the hot-path
# process-spawn counts (extreme-software-optimization loop, 2026-10-27/28).
#
# WHY: the 2026-07 optimisation loop's gains partly regressed because nothing
# guarded process counts, and wall-clock tests are flaky in CI. This guards the
# SPAWN PROXY instead: each target runs under `bash -x` against a FIXED fixture
# and the trace lines are counted. The trace goes to a dedicated descriptor
# (BASH_XTRACEFD, inherited by the target) with SHELLOPTS=xtrace exported, so it
# ALSO sees commands inside functions and sourced libs whose stderr is redirected
# (`source lib 2>/dev/null`, `v="$(loa_knob … 2>/dev/null)"`) and inside child
# bash shells (`$(bash "$CHECKPOINT" read --json 2>/dev/null | jq …)`) — a plain
# `bash -x 2>trace` lost all of those (sprint-281 review, DISS-C-003; test (g)
# pins it). Not seen: the internals of non-bash children (python, jq). For a
# fixed code path and fixture the count is deterministic (verified: three runs
# per target gave identical counts before any budget below was set). Two numbers
# per target:
#   * total trace lines  <= measured + 10% headroom (at least +3)
#   * trace lines that invoke an external tool (jq yq awk/gawk/mawk/nawk/busybox
#     sed/gsed tr cut grep realpath stat date and their g-prefixed GNU names)
#     <= measured + 2
#
# If a budget trips, the failure message prints both counts. If the change is
# intended, update the budget in the same commit and say why.
#
# Fixtures are built in each test from heredocs under BATS_TEST_TMPDIR. The live
# grimoire and .run are never read; configs are fixture copies or absent
# (implement-gate honours PROJECT_ROOT and reads "$PROJECT_ROOT/.loa.config.yaml"
# — absent in the fixture, so defaults apply; notes-size-guard reads no config;
# run-mode-stop-guard reads LOA_PUSH_CONFIG). _trace asserts the live config path
# never appears in the trace. Measured on bash 5.2 / mawk 1.3.4 / jq 1.7 /
# mikefarah yq 4.44 (CI pins its own; the +10 % and +2 headroom absorb a
# different toolchain's small differences, a larger one is a budget review).
# =============================================================================

setup() {
  BATS_TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  PROJECT_ROOT="$(cd "$BATS_TEST_DIR/../.." && pwd)"
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  command -v yq >/dev/null 2>&1 || skip "yq not installed"
  command -v awk >/dev/null 2>&1 || skip "awk not installed"
  W="$BATS_TEST_TMPDIR/w"
  mkdir -p "$W/home"
}

# External tools whose trace lines count as process spawns (a leading VAR=value
# assignment list and an absolute path prefix are tolerated; GNU g-prefixed names
# and the awk variants count too, so a Homebrew/BSD host cannot make EXT vacuous).
EXT_RE='^\++ ?([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*(/[^ ]*/)?(jq|yq|g?awk|mawk|nawk|busybox|g?sed|tr|cut|grep|g?realpath|g?readlink|g?stat|g?date)( |$)'

# _trace <stdin-file> <cwd> [VAR=value ...] -- <args to bash -x ...>
# Runs the target under bash -x with PS4='+' from <cwd> with the given extra
# environment ONLY: `env -i` drops the developer's or CI runner's ambient
# environment (an ambient LOA_* override could point a hook at live state and any
# value a hook expands would land in the trace file), then PATH, a fixture HOME
# and TMPDIR, LANG=C and the explicit VAR=value list are set (case (h) pins it).
# The trace is written to an inherited descriptor (BASH_XTRACEFD), not stderr,
# and SHELLOPTS=xtrace makes child bash shells trace into it too; the target's
# own stderr goes to TRACE_FILE.stderr. Sets TRACE_FILE, TOTAL (trace lines) and
# EXT (external-tool lines), and fails the test if the live repository's config,
# .run or grimoires path shows up in the trace (the fixtures must stand alone).
_trace() {
  local in="$1" cwd="$2"; shift 2
  local envs=()
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  TRACE_FILE="$W/trace.$$.$RANDOM"
  local xfd
  exec {xfd}>"$TRACE_FILE"
  ( cd "$cwd" && env -i PATH="$PATH" HOME="$W/home" TMPDIR="$W" LANG=C ${envs[@]+"${envs[@]}"} \
      PS4='+' BASH_XTRACEFD="$xfd" SHELLOPTS=xtrace \
      bash -x "$@" <"$in" >/dev/null 2>"$TRACE_FILE.stderr" ) || true
  exec {xfd}>&-
  TOTAL="$(grep -c '^+' "$TRACE_FILE" || true)"
  EXT="$(grep -cE "$EXT_RE" "$TRACE_FILE" || true)"
  # A live path may appear in a plain assignment (a hook computing its default
  # before the test seam overrides it: `+KF_FILE=<live>`); it may NOT appear as a
  # command argument, which is a read or write of live state.
  local live hits
  for live in "$PROJECT_ROOT/.loa.config.yaml" "$PROJECT_ROOT/.run/" "$PROJECT_ROOT/grimoires/"; do
    hits="$(grep -nF -- "$live" "$TRACE_FILE" | grep -vE '^[0-9]+:\++[A-Za-z_][A-Za-z0-9_]*=' || true)"
    if [[ -n "$hits" ]]; then
      echo "the trace touches live repository state ($live) outside a plain assignment; point the target at a fixture copy:" >&2
      printf '%s\n' "$hits" | head -5 >&2
      return 1
    fi
  done
}

# _check_budget <label> <measured-total> <measured-ext>
# Budget: total <= measured + 10%, ext <= measured + 2.
# PERF_SPAWN_BUDGET_PRINT=1 prints the live counts (used to set the budgets).
_check_budget() {
  local label="$1" mt="$2" me="$3"
  local hr=$(( mt / 10 )); (( hr < 3 )) && hr=3   # +10 %, never less than +3 lines on a small budget
  local tb=$(( mt + hr )) eb=$(( me + 2 ))
  [[ -z "${PERF_SPAWN_BUDGET_PRINT:-}" ]] || echo "SPAWNCOUNT ${label} total=${TOTAL} ext=${EXT}" >&3
  if (( TOTAL > tb || EXT > eb )); then
    {
      echo "SPAWN BUDGET EXCEEDED for ${label}:"
      echo "  trace lines          : ${TOTAL} (measured ${mt}, budget ${tb} = +10%, min +3)"
      echo "  external-tool lines  : ${EXT} (measured ${me}, budget ${eb} = +2)"
      echo "  trace file           : ${TRACE_FILE}"
      echo "  If this is an intended change, update the budget in the same commit and say why."
    } >&2
    return 1
  fi
  # Floor: a trace far below the measure means the fixture no longer reaches
  # the target code path and the guard would pass vacuously.
  if (( TOTAL < mt / 2 )); then
    echo "SPAWN BUDGET FIXTURE DRIFT for ${label}: ${TOTAL} trace lines is under half of the measured ${mt}; the fixture no longer exercises the target." >&2
    return 1
  fi
}

# --- (a) loa-kf-surface.sh: 5-entry known-failures fixture, SessionStart payload.
# Measured by ESO pass 22 (after pass 6 single awk and pass 8 lazy compat probes).
@test "spawn budget: loa-kf-surface.sh on a 5-entry fixture" {
  local kf="$W/known-failures.md" i
  {
    printf '# Known Failures\n\n## Index\n\n| ID | Status |\n|----|--------|\n\n'
    for i in 1 2 3 4 5; do
      printf '## KF-%03d: fixture entry %d\n\n**Status**: OPEN\n**Symptom**: compact symptom line for entry %d\n**Recurrence count**: %d\n\n' "$i" "$i" "$i" "$i"
    done
  } >"$kf"
  printf '%s\n' '{"hook_event_name":"SessionStart","source":"startup","session_id":"perf-spawn-budget"}' >"$W/in.json"
  _trace "$W/in.json" "$W" LOA_KF_SURFACE_TEST_MODE=1 BATS_VERSION=1 LOA_KF_SURFACE_TEST_CONFIG=true \
    LOA_KNOWN_FAILURES_FILE="$kf" -- "$PROJECT_ROOT/.claude/hooks/loa-kf-surface.sh"
  # sanity: the fixture really reaches the table (all five rows surface)
  [[ "$(LOA_KF_SURFACE_TEST_MODE=1 BATS_VERSION=1 LOA_KF_SURFACE_TEST_CONFIG=true LOA_KNOWN_FAILURES_FILE="$kf" bash "$PROJECT_ROOT/.claude/hooks/loa-kf-surface.sh" <"$W/in.json")" == *"KF-005 (rec 5)"* ]]
  _check_budget "loa-kf-surface" 36 2   # measured: 36 trace lines, 2 external-tool lines (was 34/2; the explicit env -i environment adds two bash-internal lines — no new tool spawn; sprint-281 audit DISS-C-001)
}

# --- (b) grimoire-index.sh --tsv on a scratch PROJECT_ROOT mirror.
# Measured by ESO pass 22 (after passes 4, 5 and 8).
@test "spawn budget: grimoire-index.sh --tsv on a fixture grimoire" {
  [[ "$(yq --version 2>&1)" == *mikefarah*"version v4."* ]] || skip "Mike Farah yq v4 not installed"
  local root="$W/root" g="$W/root/grimoires/loa" i
  mkdir -p "$root/x/y" "$g/lore" "$g/handoffs" "$g/visions/entries" "$root/.run"
  cp "$PROJECT_ROOT/.claude/scripts/grimoire-index.sh" "$PROJECT_ROOT/.claude/scripts/compat-lib.sh" "$root/x/y/"
  {
    printf '# Known Failures\n\n'
    for i in 1 2 3; do
      printf '## KF-%03d: fixture entry %d\n\n**Status**: OPEN\n**Symptom**: symptom %d\n**Recurrence count**: %d\n\n' "$i" "$i" "$i" "$i"
    done
  } >"$g/known-failures.md"
  printf 'version: 2\ncategories:\n  - id: patterns\n    entries:\n      - id: alpha\n        status: Active\n      - id: beta\n        status: Active\n' >"$g/lore/index.yaml"
  printf '# Notes\n\n## First heading\ntext\n## Second heading\ntext\n' >"$g/NOTES.md"
  {
    printf '# Handoff Index\n\n| handoff_id | file | from | to | topic | ts_utc | read_by |\n|---|---|---|---|---|---|---|\n'
    printf '| sha256:%064d | h1.md | a | b | topic-one | 2026-01-01T00:00:00Z |  |\n' 1
  } >"$g/handoffs/INDEX.md"
  printf '# Vision: Fixture\n\n**ID**: vision-001\n**Status**: Captured\n' >"$g/visions/entries/vision-001.md"
  {
    printf 'schema_version: 1\ndecisions:\n'
    for i in 1 2 3; do
      printf '  - id: "DEC-%04d"\n    status: open\n    summary: "fixture decision %d"\n    source: "prd.md#fr-%d"\n    proposed_by: agent\n' "$i" "$i" "$i"
    done
  } >"$g/decisions.yaml"
  : >"$W/empty"
  _trace "$W/empty" "$W" -- "$root/x/y/grimoire-index.sh" --tsv
  # sanity: all six families reach the index, so the trace covers every emitter
  local tsv; tsv="$(bash "$root/x/y/grimoire-index.sh" --tsv)"
  [[ "$tsv" == *$'decisions\tDEC-0003'* && "$tsv" == *$'vision\tvision-001'* && "$tsv" == *$'lore\tbeta'* && "$tsv" == *$'notes\tL5'* ]]
  _check_budget "grimoire-index --tsv" 167 15   # measured: 167 trace lines (umask 002: the fixture .run is 775 and the trust check tightens it with one chmod — D-5.3; 165 under umask 022), 15 external-tool lines (was 96/11): the traced run is a decisions-cache MISS (cycle-137 FR-5: snapshot, sha256, jq --version, trust-boundary stat checks, the writer awk); a warm run skips the yq parse
}

# --- (c) implement-gate.sh: Write to a grimoires/ path, no live .run.
# Measured by ESO pass 22 (after passes 8 and 9).
@test "spawn budget: implement-gate.sh on a Write payload" {
  local proj="$W/proj"
  mkdir -p "$proj/.run" "$proj/grimoires/loa"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/grimoires/loa/notes-x.md","content":"x"},"cwd":"%s"}\n' "$proj" "$proj" >"$W/in.json"
  _trace "$W/in.json" "$proj" PROJECT_ROOT="$proj" RUN_DIR="$proj/.run" LOA_RUN_DIR="$proj/.run" \
    -- "$PROJECT_ROOT/.claude/hooks/compliance/implement-gate.sh"
  # Sanity: the fixture must reach the path-classification stage (not an early exit).
  grep -q '^+canonical_root=' "$TRACE_FILE"
  _check_budget "implement-gate" 127 5   # measured: 127 trace lines, 5 external-tool lines (was 113/5 under the stderr-only tracer; the dedicated descriptor now sees 14 bash-internal lines inside stderr-redirected blocks — no new tool spawn; sprint-281 review DISS-C-003)
}

# --- (d) notes-size-guard.sh: a non-NOTES Write payload.
# Measured by ESO pass 22 (after pass 10: one jq parse).
@test "spawn budget: notes-size-guard.sh on a non-NOTES Write payload" {
  local gd="$W/g"; mkdir -p "$gd"
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s/other.md","content":"x"}}\n' "$W" >"$W/in.json"
  _trace "$W/in.json" "$W" LOA_GRIMOIRE_DIR="$gd" -- "$PROJECT_ROOT/.claude/hooks/safety/notes-size-guard.sh"
  # Sanity: the fixture must get past the parse gate to the NOTES.md comparison.
  grep -q '^+notes=' "$TRACE_FILE"
  _check_budget "notes-size-guard" 26 3   # measured: 26 trace lines, 3 external-tool lines
}

# --- (e) compat-lib.sh: sourcing must not fork a capability probe (lazy-probe
# guarantee from ESO pass 8). The absence assertion is the real invariant.
# Measured by ESO pass 22.
@test "spawn budget: sourcing compat-lib.sh forks no capability probe" {
  : >"$W/empty"
  _trace "$W/empty" "$W" -- -c 'source "$1"' _ "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
  local probes='(^|[^[:alnum:]_-])(uname|sort -V|readlink -f|stat -c)([^[:alnum:]_-]|$)|sed --version|find .*-printf'
  if grep -nE "$probes" "$TRACE_FILE" >&2; then
    echo "compat-lib.sh forked a capability probe at source time (lines above). Keep probes lazy (_compat_need_*)." >&2
    return 1
  fi
  _check_budget "compat-lib source" 15 0   # measured: 15 trace lines, 0 external-tool lines
}

# --- (f) run-mode-stop-guard.sh: HALTED sprint-plan state, push disabled.
# Measured by ESO pass 22 (after pass 18: one yq for the push config).
@test "spawn budget: run-mode-stop-guard.sh on a HALTED state with push disabled" {
  local proj="$W/proj"
  mkdir -p "$proj/.run"
  printf '{"state":"HALTED","sprints":{"current":"sprint-1"},"timestamps":{"last_activity":"2026-01-01T00:00:00Z"}}\n' >"$proj/.run/sprint-plan-state.json"
  printf 'notifications:\n  push_command:\n    enabled: false\n' >"$W/push.yaml"
  printf '%s\n' '{"hook_event_name":"Stop","session_id":"perf-spawn-budget"}' >"$W/in.json"
  _trace "$W/in.json" "$proj" LOA_RUN_DIR="$proj/.run" LOA_PUSH_CONFIG="$W/push.yaml" \
    -- "$PROJECT_ROOT/.claude/hooks/safety/run-mode-stop-guard.sh"
  grep -q 'push_notify_active\|_push_load_config' "$TRACE_FILE"
  _check_budget "run-mode-stop-guard" 78 2   # measured: 78 trace lines, 2 external-tool lines
}

# --- (g) the tracer itself: xtrace must count spawns that run inside a function or
# a sourced file whose stderr is redirected, and inside a child bash — the shapes
# the guarded hooks use for their jq/yq calls (`source lib 2>/dev/null`,
# `v="$(loa_knob … 2>/dev/null)"`, `$(bash "$CHECKPOINT" read --json 2>/dev/null | jq …)`).
# A plain `bash -x 2>trace` loses all three (xtrace rides stderr), so the budgets
# above would pass while the real spawn count regressed (sprint-281 review, DISS-C-003).
@test "spawn budget tracer: counts spawns hidden by stderr redirects, sourced libs and child shells" {
  cat >"$W/lib.sh" <<'EOF'
lib_call() { jq -n '1' >/dev/null; }
EOF
  cat >"$W/target.sh" <<'EOF'
#!/usr/bin/env bash
f() { jq -n '2' >/dev/null; }
f 2>/dev/null                                               # function with stderr redirected
source "${LIB_UNDER_TEST}" 2>/dev/null && lib_call 2>/dev/null   # sourced lib, redirected
v="$(printf 'x' | jq -R . 2>/dev/null)"                     # command substitution + pipeline, redirected
bash -c 'yq --version >/dev/null 2>&1' >/dev/null           # child bash
printf '%s\n' "$v" >/dev/null
EOF
  : >"$W/empty"
  _trace "$W/empty" "$W" LIB_UNDER_TEST="$W/lib.sh" -- "$W/target.sh"
  # four external-tool spawns: jq (function), jq (sourced lib), jq (pipeline), yq (child bash)
  echo "EXT=${EXT} TOTAL=${TOTAL}" >&2
  [[ "$EXT" -eq 4 ]]
}

# --- (h) the tracer's environment: the traced target must run under an explicit,
# allowlisted environment, not the developer's or CI runner's ambient one — an
# ambient LOA_* override could point a hook at live state (making a budget
# nondeterministic) and any ambient value a hook expands lands in the trace file,
# whose path is printed on failure (sprint-281 audit, DISS-C-001).
@test "spawn budget tracer: the ambient environment does not reach the traced target or its trace" {
  cat >"$W/canary.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${LOA_SPAWN_BUDGET_CANARY:-unset}" >/dev/null
EOF
  : >"$W/empty"
  export LOA_SPAWN_BUDGET_CANARY="canary-$$-$RANDOM"
  _trace "$W/empty" "$W" -- "$W/canary.sh"
  unset LOA_SPAWN_BUDGET_CANARY
  # (a bare `! grep` never fails a bats test — errexit ignores negated commands — so test the status explicitly)
  if grep -q 'canary-' "$TRACE_FILE"; then
    echo "the ambient LOA_SPAWN_BUDGET_CANARY reached the traced target and its trace:" >&2; cat "$TRACE_FILE" >&2
    return 1
  fi
  grep -qF "printf '%s\\n' unset" "$TRACE_FILE"
}
