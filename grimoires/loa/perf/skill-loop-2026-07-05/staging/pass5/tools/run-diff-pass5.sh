#!/usr/bin/env bash
# =============================================================================
# run-diff-pass5.sh — old-vs-new differential proof harness for pass 5
# =============================================================================
# Targets: beads-health.sh, check-updates.sh, golden-path.sh (+ path-lib.sh,
# bootstrap.sh which golden-path exercises through its source chain).
#
# Method: two mirror trees under /tmp/loa-pass5/mirror/{old,new} — `old` gets
# live .claude/scripts copies, `new` gets the staged pass-5 files overlaid.
# Each case runs both sides with identical fixtures/env, captures
# stdout+stderr+exit (+ cache-file bytes for check-updates), normalizes
# timestamps and mirror-root paths, and diffs. Zero real network: curl is a
# PATH shim and the endpoint-validator python is a repo-local .venv stub in
# BOTH mirrors.
#
# Usage: run-diff-pass5.sh [bh|cu|gp|all]
# =============================================================================
set -euo pipefail
export LC_ALL=C

REPO=/home/merlin/Documents/thj/code/loa
STAGE="$REPO/grimoires/loa/perf/skill-loop-2026-07-05/staging/pass5"
WORK=/tmp/loa-pass5
MIR="$WORK/mirror"
FX="$WORK/fx"
OUT="$WORK/out"

# ---------------------------------------------------------------- mirrors
build_mirrors() {
  rm -rf "$MIR" "$OUT"
  mkdir -p "$OUT"
  local side src
  for side in old new; do
    local root="$MIR/$side"
    mkdir -p "$root/.claude/scripts/beads" "$root/.claude/scripts/lib/allowlists" "$root/.venv/bin"
    cp "$REPO/.claude/scripts/bash-version-guard.sh" "$root/.claude/scripts/"
    cp "$REPO/.claude/scripts/compat-lib.sh" "$root/.claude/scripts/"
    cp "$REPO/.claude/scripts/lib/endpoint-validator.sh" "$root/.claude/scripts/lib/"
    cp "$REPO/.claude/scripts/lib/endpoint-validator.py" "$root/.claude/scripts/lib/"
    cp "$REPO/.claude/scripts/lib/allowlists/loa-github.json" "$root/.claude/scripts/lib/allowlists/"
    if [[ "$side" == old ]]; then src="$REPO/.claude/scripts"; else src="$STAGE"; fi
    cp "$([[ $side == old ]] && echo "$REPO/.claude/scripts/beads/beads-health.sh" || echo "$STAGE/beads-health.sh")" "$root/.claude/scripts/beads/beads-health.sh"
    cp "$([[ $side == old ]] && echo "$REPO/.claude/scripts/check-updates.sh" || echo "$STAGE/check-updates.sh")" "$root/.claude/scripts/check-updates.sh"
    cp "$([[ $side == old ]] && echo "$REPO/.claude/scripts/golden-path.sh" || echo "$STAGE/golden-path.sh")" "$root/.claude/scripts/golden-path.sh"
    cp "$([[ $side == old ]] && echo "$REPO/.claude/scripts/bootstrap.sh" || echo "$STAGE/bootstrap.sh")" "$root/.claude/scripts/bootstrap.sh"
    cp "$([[ $side == old ]] && echo "$REPO/.claude/scripts/path-lib.sh" || echo "$STAGE/path-lib.sh")" "$root/.claude/scripts/path-lib.sh"
    # .venv python stub: accepts every endpoint-validator check (rc 0).
    printf '#!/usr/bin/env bash\nexit 0\n' > "$root/.venv/bin/python"
    chmod +x "$root/.venv/bin/python"
  done
  # curl PATH shim dir (shared; behavior selected via LOA_P5_CURL_MODE)
  mkdir -p "$WORK/shims"
  cat > "$WORK/shims/curl" <<'CURLSTUB'
#!/usr/bin/env bash
case "${LOA_P5_CURL_MODE:-ok}" in
  ok)
    printf '{"tag_name":"v9.9.9","html_url":"https://github.com/0xHoneyJar/loa/releases/tag/v9.9.9","prerelease":false}\n'
    exit 0 ;;
  prerelease)
    printf '{"tag_name":"v10.0.0-rc.1","html_url":"https://github.com/0xHoneyJar/loa/releases/tag/v10.0.0-rc.1","prerelease":true}\n'
    exit 0 ;;
  apierror)
    printf '{"message":"API rate limit exceeded"}\n'
    exit 0 ;;
  neterr)
    exit 6 ;;
esac
CURLSTUB
  chmod +x "$WORK/shims/curl"
  # br-less PATH dir for the NOT_INSTALLED case: symlink common bins, omit br.
  mkdir -p "$WORK/nobr"
  local b p
  for b in bash sh env sqlite3 jq yq stat date head tail awk grep sed cat printf cp mv rm mkdir dirname basename touch realpath; do
    p="$(command -v "$b" 2>/dev/null)" || continue
    ln -sf "$p" "$WORK/nobr/$b"
  done
  echo "mirrors built"
}

# ---------------------------------------------------------------- helpers
normalize() {
  sed -E \
    -e 's/"timestamp": "[0-9TZ:.+-]+"/"timestamp": "TS"/' \
    -e 's/"last_check": "[0-9TZ:.+-]+"/"last_check": "TS"/' \
    -e "s|$MIR/old|MROOT|g" \
    -e "s|$MIR/new|MROOT|g" \
    -e 's/(bh-[a-z]+)-(old|new)/\1-SIDE/g' \
    -e 's/(beads-health\.sh: line) [0-9]+:/\1 N:/' \
    -e 's/(path-lib\.sh: line) [0-9]+:/\1 N:/'
}

FAIL=0
compare_case() { # <name>  — expects $OUT/{old,new}/<name>.txt written
  local name="$1"
  if diff -u <(normalize < "$OUT/old/$name.txt") <(normalize < "$OUT/new/$name.txt") > "$OUT/diff-$name.txt" 2>&1; then
    echo "  OK   $name"
    rm -f "$OUT/diff-$name.txt"
  else
    echo "  DIFF $name  (see $OUT/diff-$name.txt)"
    FAIL=1
  fi
}

# =========================================================== beads-health
bh_fixture() { # <name> <schema-mode> <jsonl-mode>
  local d="$FX/bh-$1"
  rm -rf "$d"; mkdir -p "$d/.beads"
  local db="$d/.beads/beads.db"
  case "$2" in
    healthy)
      sqlite3 "$db" "CREATE TABLE issues (id TEXT PRIMARY KEY, owner TEXT); INSERT INTO issues VALUES ('t','me'); CREATE TABLE dirty_issues (id INTEGER PRIMARY KEY, marked_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);" ;;
    noowner)
      sqlite3 "$db" "CREATE TABLE issues (id TEXT PRIMARY KEY, title TEXT);" ;;
    dirtybug)
      sqlite3 "$db" "CREATE TABLE issues (id TEXT PRIMARY KEY, owner TEXT); CREATE TABLE dirty_issues (id INTEGER PRIMARY KEY, marked_at TEXT NOT NULL);" ;;
    dirtynullable)
      sqlite3 "$db" "CREATE TABLE issues (id TEXT PRIMARY KEY, owner TEXT); CREATE TABLE dirty_issues (id INTEGER PRIMARY KEY, marked_at TEXT);" ;;
    nodirty)
      sqlite3 "$db" "CREATE TABLE issues (id TEXT PRIMARY KEY, owner TEXT);" ;;
    nodb) : ;;
    corrupt)
      printf 'this is not a sqlite database at all — 16 bytes+\n' > "$db" ;;
    nobeads) rm -rf "$d/.beads" ;;
  esac
  case "$3" in
    fresh)   printf '{"id":"t"}\n' > "$d/.beads/issues.jsonl" ;;
    stale)   printf '{"id":"t"}\n' > "$d/.beads/issues.jsonl"; touch -d '26 hours ago' "$d/.beads/issues.jsonl" ;;
    aged90m) printf '{"id":"t"}\n' > "$d/.beads/issues.jsonl"; touch -d '90 minutes ago' "$d/.beads/issues.jsonl" ;;
    missing) : ;;
    none)    : ;;
  esac
}

bh_run() { # <case> <fixture-dir-or-REAL> <extra-env...> -- <args...>
  local name="$1" fixroot="$2"; shift 2
  local envs=()
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  local side
  for side in old new; do
    local script="$MIR/$side/.claude/scripts/beads/beads-health.sh"
    local pr="$fixroot"
    [[ "$fixroot" == REAL ]] && pr="$REPO"
    local rc=0 cwd="$pr"
    { env "PROJECT_ROOT=$pr" ${envs[@]+"${envs[@]}"} bash -c 'cd "$1"; shift; exec bash "$@"' _ "$cwd" "$script" "$@" \
        > "$OUT/$side/$name.stdout" 2> "$OUT/$side/$name.stderr"; rc=$?; } || rc=$?
    { echo "EXIT=$rc"; echo "--- STDOUT ---"; cat "$OUT/$side/$name.stdout"; echo "--- STDERR ---"; cat "$OUT/$side/$name.stderr"; } > "$OUT/$side/$name.txt"
  done
  compare_case "$name"
}

bh_run_sided() { # <case> <fixture-stem> -- <args...>  (fixture bh-<stem>-<side>)
  local name="$1" stem="$2"; shift 2
  shift  # consume --
  local side
  for side in old new; do
    local script="$MIR/$side/.claude/scripts/beads/beads-health.sh"
    local pr="$FX/bh-$stem-$side"
    local rc=0
    { env "PROJECT_ROOT=$pr" bash -c 'cd "$1"; shift; exec bash "$@"' _ "$pr" "$script" "$@" \
        > "$OUT/$side/$name.stdout" 2> "$OUT/$side/$name.stderr"; rc=$?; } || rc=$?
    { echo "EXIT=$rc"; echo "--- STDOUT ---"; cat "$OUT/$side/$name.stdout"; echo "--- STDERR ---"; cat "$OUT/$side/$name.stderr"; } > "$OUT/$side/$name.txt"
  done
  compare_case "$name"
}

run_bh() {
  echo "== beads-health differentials =="
  mkdir -p "$OUT/old" "$OUT/new"
  bh_fixture healthy healthy aged90m
  bh_fixture noowner noowner fresh
  bh_fixture dirtybug dirtybug fresh
  bh_fixture dirtynullable dirtynullable fresh
  bh_fixture nodirty nodirty fresh
  bh_fixture nodb nodb missing
  bh_fixture corrupt corrupt fresh
  bh_fixture nobeads nobeads none
  bh_fixture stale healthy stale
  bh_fixture missingjsonl healthy missing

  bh_run bh-healthy-quick-json   "$FX/bh-healthy" -- --quick --json
  bh_run bh-healthy-quick-text   "$FX/bh-healthy" -- --quick
  bh_run bh-healthy-quick-verb   "$FX/bh-healthy" -- --quick --verbose
  # full mode runs `br doctor`, which may mutate its fixture (auto-flush) —
  # give each side its own identical fixture instead of sharing one.
  bh_fixture fullj-old healthy aged90m
  bh_fixture fullj-new healthy aged90m
  bh_run_sided bh-full-json fullj -- --json
  bh_run bh-noowner-quick-json   "$FX/bh-noowner" -- --quick --json
  bh_run bh-dirtybug-quick-json  "$FX/bh-dirtybug" -- --quick --json
  bh_run bh-dirtybug-quick-text  "$FX/bh-dirtybug" -- --quick
  bh_run bh-dirtynull-quick-json "$FX/bh-dirtynullable" -- --quick --json
  bh_run bh-nodirty-quick-json   "$FX/bh-nodirty" -- --quick --json
  bh_run bh-nodb-quick-json      "$FX/bh-nodb" -- --quick --json
  bh_run bh-corrupt-quick-json   "$FX/bh-corrupt" -- --quick --json
  bh_run bh-nobeads-quick-json   "$FX/bh-nobeads" -- --quick --json
  bh_run bh-nobeads-text         "$FX/bh-nobeads" -- --quick
  bh_run bh-stale-quick-json     "$FX/bh-stale" -- --quick --json
  bh_run bh-missingjsonl-qj      "$FX/bh-missingjsonl" -- --quick --json
  bh_run bh-badflag              "$FX/bh-healthy" -- --nonsense
  bh_run bh-beadsdir-override    "$FX/bh-nobeads" "LOA_BEADS_DIR=$FX/bh-healthy/.beads" -- --quick --json
  # br absent → NOT_INSTALLED (PATH without br)
  bh_run bh-nobr-json "$FX/bh-healthy" "PATH=$WORK/nobr" -- --quick --json
  bh_run bh-nobr-text "$FX/bh-healthy" "PATH=$WORK/nobr" -- --quick
  # real repo, read-only quick (doctor skipped)
  bh_run bh-real-quick-json REAL -- --quick --json
}

# =========================================================== check-updates
cu_write_version() { # <side-root> <json-or-ABSENT>
  local root="$1" v="$2"
  rm -f "$root/.loa-version.json"
  [[ "$v" == ABSENT ]] || printf '%s\n' "$v" > "$root/.loa-version.json"
}
cu_write_config() { # <side-root> <content-or-ABSENT>
  local root="$1" c="$2"
  rm -f "$root/.loa.config.yaml"
  [[ "$c" == ABSENT ]] || printf '%s\n' "$c" > "$root/.loa.config.yaml"
}
cu_write_cache() { # <cache-dir> <content-or-ABSENT-or-EMPTY> <age>
  rm -rf "$1"; mkdir -p "$1"
  case "$2" in
    ABSENT) return 0 ;;
    EMPTY)  : > "$1/update-check.json" ;;
    *)      printf '%s\n' "$2" > "$1/update-check.json" ;;
  esac
  [[ "$3" == now ]] || touch -d "$3" "$1/update-check.json"
}

CU_VER_OK='{"framework_version":"1.180.0","schema_version":2}'
CU_CACHE_UPD='{"last_check":"2026-07-04T03:00:50Z","local_version":"v1.180.0","remote_version":"v1.182.0","remote_url":"https://github.com/0xHoneyJar/loa/releases/tag/v1.182.0","update_available":true,"is_major_update":false,"ttl_hours":24}'
CU_CACHE_NOUPD='{"last_check":"2026-07-04T03:00:50Z","local_version":"v1.180.0","remote_version":"v1.180.0","remote_url":"https://github.com/0xHoneyJar/loa/releases/tag/v1.180.0","update_available":false,"is_major_update":false,"ttl_hours":24}'
CU_CACHE_MAJOR='{"last_check":"2026-07-04T03:00:50Z","local_version":"v1.180.0","remote_version":"v2.0.0","remote_url":"https://github.com/0xHoneyJar/loa/releases/tag/v2.0.0","update_available":true,"is_major_update":true,"ttl_hours":24}'

cu_run() { # <case> <version> <config> <cache-content> <cache-age> <curlmode> <extra-env...> -- <args...>
  local name="$1" ver="$2" cfg="$3" cache="$4" age="$5" curlmode="$6"; shift 6
  local envs=()
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  local side
  for side in old new; do
    local root="$MIR/$side"
    cu_write_version "$root" "$ver"
    cu_write_config  "$root" "$cfg"
    local cdir="$FX/cu-$name/cache-$side"
    cu_write_cache "$cdir" "$cache" "$age"
    local rc=0
    { env "PATH=$WORK/shims:$PATH" "LOA_CACHE_DIR=$cdir" "LOA_P5_CURL_MODE=$curlmode" \
          ${envs[@]+"${envs[@]}"} bash "$root/.claude/scripts/check-updates.sh" "$@" \
          > "$OUT/$side/$name.stdout" 2> "$OUT/$side/$name.stderr"; rc=$?; } || rc=$?
    { echo "EXIT=$rc"; echo "--- STDOUT ---"; cat "$OUT/$side/$name.stdout"; echo "--- STDERR ---"; cat "$OUT/$side/$name.stderr"
      echo "--- CACHE-AFTER ---"
      if [[ -f "$cdir/update-check.json" ]]; then cat "$cdir/update-check.json"; else echo "(no cache file)"; fi
      echo "--- CACHE-DIR-EXISTS=$([[ -d $cdir ]] && echo yes || echo no) ---"
    } > "$OUT/$side/$name.txt"
  done
  compare_case "$name"
}

run_cu() {
  echo "== check-updates differentials =="
  mkdir -p "$OUT/old" "$OUT/new"
  # cache-hit paths (hot)
  cu_run cu-fresh-upd-notify   "$CU_VER_OK" ABSENT "$CU_CACHE_UPD"   now ok -- --notify
  cu_run cu-fresh-noupd-notify "$CU_VER_OK" ABSENT "$CU_CACHE_NOUPD" now ok -- --notify
  cu_run cu-fresh-major-notify "$CU_VER_OK" ABSENT "$CU_CACHE_MAJOR" now ok -- --notify
  cu_run cu-fresh-upd-json     "$CU_VER_OK" ABSENT "$CU_CACHE_UPD"   now ok -- --notify --json
  cu_run cu-fresh-noupd-json   "$CU_VER_OK" ABSENT "$CU_CACHE_NOUPD" now ok -- --notify --json
  cu_run cu-fresh-upd-quiet    "$CU_VER_OK" ABSENT "$CU_CACHE_UPD"   now ok -- --notify --quiet
  cu_run cu-empty-cache        "$CU_VER_OK" ABSENT EMPTY             now ok -- --notify --json
  cu_run cu-malformed-cache    "$CU_VER_OK" ABSENT '{"remote_version": BROKEN' now ok -- --notify --json
  cu_run cu-weird-cache        "$CU_VER_OK" ABSENT '{"remote_version":123,"remote_url":null,"update_available":"true","is_major_update":"x"}' now ok -- --notify --json
  # notification styles via env (cache-hit)
  cu_run cu-style-line   "$CU_VER_OK" ABSENT "$CU_CACHE_UPD" now ok "LOA_UPDATE_NOTIFICATION=line"   -- --notify
  cu_run cu-style-silent "$CU_VER_OK" ABSENT "$CU_CACHE_UPD" now ok "LOA_UPDATE_NOTIFICATION=silent" -- --notify
  # fetch paths (stubbed, no network)
  cu_run cu-fetch-ok        "$CU_VER_OK" ABSENT ABSENT now ok         -- --notify
  cu_run cu-fetch-ok-json   "$CU_VER_OK" ABSENT ABSENT now ok         -- --notify --json
  cu_run cu-fetch-prerel    "$CU_VER_OK" ABSENT ABSENT now prerelease -- --notify --json
  cu_run cu-fetch-apierror  "$CU_VER_OK" ABSENT ABSENT now apierror   -- --notify --json
  cu_run cu-fetch-neterr    "$CU_VER_OK" ABSENT ABSENT now neterr     -- --notify --json
  cu_run cu-fetch-stale     "$CU_VER_OK" ABSENT "$CU_CACHE_UPD" '30 hours ago' neterr -- --notify
  cu_run cu-fetch-stale-ok  "$CU_VER_OK" ABSENT "$CU_CACHE_NOUPD" '30 hours ago' ok -- --notify
  cu_run cu-force-check     "$CU_VER_OK" ABSENT "$CU_CACHE_NOUPD" now ok -- --notify --check
  # config-driven branches
  cu_run cu-cfg-fastpath    "$CU_VER_OK" 'advisor_strategy: {}' "$CU_CACHE_UPD" now ok -- --notify
  cu_run cu-cfg-keys        "$CU_VER_OK" $'update_check:\n  cache_ttl_hours: 1000\n  notification_style: line\n  enabled: true\n  include_prereleases: true' "$CU_CACHE_UPD" '30 hours ago' ok -- --notify
  cu_run cu-cfg-disabled    "$CU_VER_OK" $'update_check:\n  enabled: false' "$CU_CACHE_UPD" now ok -- --notify --json
  cu_run cu-cfg-scalar      "$CU_VER_OK" 'update_check: yes' "$CU_CACHE_UPD" now ok -- --notify
  cu_run cu-cfg-emptymap    "$CU_VER_OK" 'update_check: {}' "$CU_CACHE_UPD" now ok -- --notify
  cu_run cu-cfg-malformed   "$CU_VER_OK" $'update_check: [unclosed\nbad: {{' "$CU_CACHE_UPD" now ok -- --notify
  cu_run cu-ttl-env-zero    "$CU_VER_OK" ABSENT "$CU_CACHE_NOUPD" now ok "LOA_UPDATE_CHECK_TTL=0" -- --notify --json
  # skip / error paths
  cu_run cu-disabled-env "$CU_VER_OK" ABSENT "$CU_CACHE_UPD" now ok "LOA_DISABLE_UPDATE_CHECK=1" -- --notify --json
  cu_run cu-ci-env       "$CU_VER_OK" ABSENT "$CU_CACHE_UPD" now ok "GITHUB_ACTIONS=true" -- --notify --json
  cu_run cu-no-version   ABSENT       ABSENT "$CU_CACHE_UPD" now ok -- --notify --json
  cu_run cu-no-notify-nontty "$CU_VER_OK" ABSENT "$CU_CACHE_UPD" now ok -- --json
  cu_run cu-help         "$CU_VER_OK" ABSENT ABSENT now ok -- --help
  cu_run cu-badflag      "$CU_VER_OK" ABSENT ABSENT now ok -- --bogus
}

# =========================================================== golden-path
GP_BATTERY='
set +e
export PROJECT_ROOT="${GP_ROOT}"
cd "${GP_ROOT}"
source "${GP_ROOT}/.claude/scripts/golden-path.sh"
echo "SOURCE_RC=$?"
set +e; set +u
for fn in golden_detect_plan_phase golden_detect_sprint golden_detect_review_target \
          golden_detect_workflow_state golden_suggest_command golden_format_journey \
          golden_detect_bridge_state golden_bridge_progress golden_detect_install_mode; do
  out=$($fn 2>&1); rc=$?
  printf "%s rc=%d [%s]\n" "$fn" "$rc" "$out"
done
out=$(golden_check_ship_ready 2>&1); printf "golden_check_ship_ready rc=%d [%s]\n" $? "$out"
out=$(golden_menu_options 2>&1); printf "golden_menu_options rc=%d [%s]\n" $? "$out"
out=$(golden_menu_options --json 2>&1); printf "golden_menu_options_json rc=%d [%s]\n" $? "$out"
out=$(golden_boundary_report 2>&1); printf "golden_boundary_report rc=%d [%s]\n" $? "$out"
out=$(golden_detect_active_bug 2>&1); printf "golden_detect_active_bug rc=%d [%s]\n" $? "$out"
for cmd in plan build review ship; do
  out=$(golden_resolve_truename "$cmd" 2>&1); printf "resolve_%s rc=%d [%s]\n" "$cmd" $? "$out"
done
out=$(golden_resolve_truename build sprint-2 2>&1); printf "resolve_build_override rc=%d [%s]\n" $? "$out"
out=$(golden_resolve_truename build "bad;id" 2>&1); printf "resolve_build_badid rc=%d [%s]\n" $? "$out"
out=$(golden_trajectory 2>&1); printf "golden_trajectory rc=%d [%s]\n" $? "$out"
for t in "TRIAGE IMPLEMENTING" "IMPLEMENTING REVIEWING" "REVIEWING AUDITING" "AUDITING COMPLETED" "COMPLETED IMPLEMENTING" "IMPLEMENTING HALTED" "TRIAGE COMPLETED"; do
  set -- $t
  golden_validate_bug_transition "$1" "$2"; printf "transition_%s_%s rc=%d\n" "$1" "$2" $?
done
out=$(golden_bug_check_deps 2>&1); printf "golden_bug_check_deps rc=%d [%s]\n" $? "$out"
echo "GRIM=${LOA_GRIMOIRE_DIR:-UNSET}"
echo "BEADS=${LOA_BEADS_DIR:-UNSET}"
echo "STATE=${LOA_STATE_DIR:-UNSET}"
'

gp_state() { # <side-root> <state-name>
  local root="$1" st="$2"
  rm -rf "$root/grimoires" "$root/.run" "$root/custom"
  rm -f "$root/.loa-version.json" "$root/.loa.config.yaml"
  mkdir -p "$root/grimoires/loa"
  case "$st" in
    discovery) : ;;
    prd)
      echo "# PRD" > "$root/grimoires/loa/prd.md" ;;
    sdd)
      echo "# PRD" > "$root/grimoires/loa/prd.md"
      echo "# SDD" > "$root/grimoires/loa/sdd.md" ;;
    midsprint)
      echo "# PRD" > "$root/grimoires/loa/prd.md"
      echo "# SDD" > "$root/grimoires/loa/sdd.md"
      printf '## Sprint 1\n## Sprint 2\n## Sprint 3\n' > "$root/grimoires/loa/sprint.md"
      mkdir -p "$root/grimoires/loa/a2a/sprint-1" "$root/grimoires/loa/a2a/sprint-2"
      touch "$root/grimoires/loa/a2a/sprint-1/COMPLETED"
      printf '# Review\nAll good.\n' > "$root/grimoires/loa/a2a/sprint-2/engineer-feedback.md" ;;
    findings)
      echo "# PRD" > "$root/grimoires/loa/prd.md"
      echo "# SDD" > "$root/grimoires/loa/sdd.md"
      printf '## Sprint 1\n## Sprint 2\n' > "$root/grimoires/loa/sprint.md"
      mkdir -p "$root/grimoires/loa/a2a/sprint-1"
      printf '# Review\n## Changes Required\n- fix X\n' > "$root/grimoires/loa/a2a/sprint-1/engineer-feedback.md" ;;
    shipready)
      echo "# PRD" > "$root/grimoires/loa/prd.md"
      echo "# SDD" > "$root/grimoires/loa/sdd.md"
      printf '## Sprint 1\n## Sprint 2\n' > "$root/grimoires/loa/sprint.md"
      mkdir -p "$root/grimoires/loa/a2a/sprint-1" "$root/grimoires/loa/a2a/sprint-2"
      touch "$root/grimoires/loa/a2a/sprint-1/COMPLETED" "$root/grimoires/loa/a2a/sprint-2/COMPLETED" ;;
    allplanned)
      echo "# PRD" > "$root/grimoires/loa/prd.md"
      echo "# SDD" > "$root/grimoires/loa/sdd.md"
      printf '## Sprint 1\n' > "$root/grimoires/loa/sprint.md" ;;
    bug)
      echo "# PRD" > "$root/grimoires/loa/prd.md"
      echo "# SDD" > "$root/grimoires/loa/sdd.md"
      printf '## Sprint 1\n' > "$root/grimoires/loa/sprint.md"
      mkdir -p "$root/.run/bugs/bug-042"
      printf '{"state":"IMPLEMENTING","bug_id":"bug-042","bug_title":"A very long bug title that should get truncated at forty chars for menu","sprint_id":"sprint-bug-042"}\n' > "$root/.run/bugs/bug-042/state.json"
      touch -d '10 minutes ago' "$root/.run/bugs/bug-042/state.json" ;;
    bridge)
      echo "# PRD" > "$root/grimoires/loa/prd.md"
      mkdir -p "$root/.run"
      printf '{"state":"ITERATING","bridge_id":"bridge-x","config":{"depth":3},"iterations":[{"iteration":1}],"flatline":{"last_score":4.0,"initial_score":15.5}}\n' > "$root/.run/bridge-state.json" ;;
    versionfile)
      echo "# PRD" > "$root/grimoires/loa/prd.md"
      printf '{"framework_version":"1.180.0","installation_mode":"submodule","submodule":{"commit":"abcdef1234567890","path":".loa"}}\n' > "$root/.loa-version.json" ;;
  esac
}

gp_run() { # <case> <state> <config-content-or-ABSENT> <extra-env...>
  local name="$1" st="$2" cfg="$3"; shift 3
  local envs=("$@")
  local side
  for side in old new; do
    local root="$MIR/$side"
    gp_state "$root" "$st"
    [[ "$cfg" == ABSENT ]] || printf '%s\n' "$cfg" > "$root/.loa.config.yaml"
    local rc=0
    { env GP_ROOT="$root" ${envs[@]+"${envs[@]}"} bash -c "$GP_BATTERY" \
        > "$OUT/$side/$name.stdout" 2> "$OUT/$side/$name.stderr"; rc=$?; } || rc=$?
    { echo "EXIT=$rc"; echo "--- STDOUT ---"; cat "$OUT/$side/$name.stdout"; echo "--- STDERR ---"; cat "$OUT/$side/$name.stderr"; } > "$OUT/$side/$name.txt"
  done
  compare_case "$name"
}

gp_run_sourceonly() { # <case> <state> <config> <extra-env...>  — plain source, capture rc
  local name="$1" st="$2" cfg="$3"; shift 3
  local envs=("$@")
  local side
  for side in old new; do
    local root="$MIR/$side"
    gp_state "$root" "$st"
    [[ "$cfg" == ABSENT ]] || printf '%s\n' "$cfg" > "$root/.loa.config.yaml"
    local rc=0
    { env ${envs[@]+"${envs[@]}"} PROJECT_ROOT="$root" bash -c "cd '$root' && source '$root/.claude/scripts/golden-path.sh'; echo POST_SOURCE_RC=\$?" \
        > "$OUT/$side/$name.stdout" 2> "$OUT/$side/$name.stderr"; rc=$?; } || rc=$?
    { echo "EXIT=$rc"; echo "--- STDOUT ---"; cat "$OUT/$side/$name.stdout"; echo "--- STDERR ---"; cat "$OUT/$side/$name.stderr"; } > "$OUT/$side/$name.txt"
  done
  compare_case "$name"
}

run_gp() {
  echo "== golden-path differentials =="
  mkdir -p "$OUT/old" "$OUT/new"
  gp_run gp-discovery   discovery   ABSENT
  gp_run gp-prd         prd         ABSENT
  gp_run gp-sdd         sdd         ABSENT
  gp_run gp-midsprint   midsprint   ABSENT
  gp_run gp-findings    findings    ABSENT
  gp_run gp-shipready   shipready   ABSENT
  gp_run gp-allplanned  allplanned  ABSENT
  gp_run gp-bug         bug         ABSENT
  gp_run gp-bridge      bridge      ABSENT
  gp_run gp-versionfile versionfile ABSENT
  # config variants (path-lib branches)
  gp_run gp-cfg-custom    midsprint $'paths:\n  grimoire: custom/grim'
  gp_run gp-cfg-emptymap  midsprint 'paths: {}'
  gp_run gp-cfg-scalar    midsprint 'paths: hello'
  gp_run gp-cfg-emptystr  midsprint 'paths: ""'
  gp_run gp-cfg-null      midsprint 'paths: null'
  gp_run gp-cfg-abs       midsprint $'paths:\n  grimoire: /etc/evil'
  gp_run gp-cfg-escape    midsprint $'paths:\n  grimoire: ../outside'
  gp_run gp-cfg-statedir  midsprint $'paths:\n  state_dir: mystate'
  gp_run gp-cfg-soul      midsprint $'paths:\n  soul:\n    source: grimoires/loa/A.md\n    output: grimoires/loa/A.md'
  gp_run_sourceonly gp-cfg-malformed midsprint $'paths: [unclosed\nbad: {{'
  # env-driven branches
  gp_run gp-env-grimdir  midsprint ABSENT "LOA_GRIMOIRE_DIR=$MIR/PLACEHOLDER/grimoires/loa"
  gp_run gp-legacy       midsprint ABSENT "LOA_USE_LEGACY_PATHS=1"
  gp_run gp-staterel     midsprint ABSENT "LOA_STATE_DIR=relstate"
  gp_run_sourceonly gp-stateabs midsprint ABSENT "LOA_STATE_DIR=/tmp/loa-pass5-absstate"
  echo "note: gp-env-grimdir uses per-side path via PLACEHOLDER substitution — see gp_run_envgrim"
}

# env-grimdir needs a per-side value; handle specially
gp_run_envgrim() {
  local name=gp-env-grimdir side
  for side in old new; do
    local root="$MIR/$side"
    gp_state "$root" midsprint
    local rc=0
    { env GP_ROOT="$root" "LOA_GRIMOIRE_DIR=$root/grimoires/loa" bash -c "$GP_BATTERY" \
        > "$OUT/$side/$name.stdout" 2> "$OUT/$side/$name.stderr"; rc=$?; } || rc=$?
    { echo "EXIT=$rc"; echo "--- STDOUT ---"; cat "$OUT/$side/$name.stdout"; echo "--- STDERR ---"; cat "$OUT/$side/$name.stderr"; } > "$OUT/$side/$name.txt"
  done
  compare_case "$name"
}

# ---------------------------------------------------------------- main
main() {
  local what="${1:-all}"
  build_mirrors
  case "$what" in
    bh)  run_bh ;;
    cu)  run_cu ;;
    gp)  run_gp; gp_run_envgrim ;;
    all) run_bh; run_cu; run_gp; gp_run_envgrim ;;
  esac
  if [[ $FAIL -eq 0 ]]; then
    echo "ALL CASES IDENTICAL"
  else
    echo "DIVERGENCES FOUND — inspect $OUT/diff-*.txt"
    exit 1
  fi
}
main "$@"
