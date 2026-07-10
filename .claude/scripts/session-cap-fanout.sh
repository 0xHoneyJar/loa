#!/usr/bin/env bash
# =============================================================================
# session-cap-fanout.sh — translate session_cap config into L3 schedules +
# a marker-delimited crontab block.
#
# cycle-117 Wave-2 item B (bd-c117-b-fanout-5ggb). Takes each configured
# `session_cap.reset_windows` x `session_cap.post_reset_fanout.phases` pair
# and materializes:
#   (a) an L3 ScheduleConfig YAML at .run/schedules/session-cap-fanout-w<idx>-
#       <phase>.yaml, validated via `scheduled-cycle-lib.sh register` before
#       anything is installed (install aborts on any registration failure);
#   (b) a real, idempotent crontab entry with deterministic per-repo minute
#       jitter that never lands on :00 or :30.
#
# SCOPE NOTE (bd-fanout-real-dispatch-9jv6, Tranche 1): the `bridgebuilder`
# phase now dispatches a REAL review — its dispatch_contract points at the
# session-cap-bb reader/decider/dispatcher/awaiter/logger scripts under
# .claude/skills/scheduled-cycle-template/contracts/session-cap-bb/. The
# earlier claim that bridgebuilder-review "has no standalone CLI entrypoint"
# was FALSE: resources/entry.sh -> dist/main.js is a real headless entrypoint
# that spiral-harness.sh already fires unattended, and BB with no --pr
# self-discovers open PRs + dedups. The session-cap-bb decider is FAIL-CLOSED
# (dispatch only when the captured snapshot shows sprint_plan/bridge RUNNING or
# HALTED), so a reset window where nothing was in flight is still a no-op.
# The `flatline` and `red_team` phases REMAIN shipped no-op example-*.sh
# placeholders (Tranche 2, deferred): unlike BB, both hard-require an explicit
# --doc <path> and cannot auto-resolve a target from the session-limit snapshot
# — wiring them needs an operator decision on current-state vs resume-exact
# doc-targeting semantics.
#
# Modeled on .claude/scripts/budget/budget-reconcile-install.sh and
# .claude/scripts/audit/audit-snapshot-install.sh (same subcommand shape,
# same marker-comment convention, same yq/python3-fallback config read).
#
# Subcommands:
#   install [--dry-run]   Generate YAMLs, register() each via the L3 lib,
#                          then install the crontab block. Refuses (exit 0)
#                          unless session_cap.post_reset_fanout.enabled is
#                          literally true. --dry-run generates into a scratch
#                          dir and prints the YAMLs + would-be crontab block
#                          with ZERO writes to .run/schedules/ or crontab.
#   uninstall | --off     Remove exactly the loa-cycle117-session-cap-fanout
#                          marker block from crontab. Runs regardless of the
#                          enabled flag so flipping to false can be cleaned up.
#   status                Print whether the crontab block is installed.
#   show                  Print the YAMLs + crontab block that WOULD install
#                          (side-effect free; ignores the enabled flag).
#
# Config (.loa.config.yaml — see .loa.config.yaml.example for full docs):
#   session_cap:
#     reset_windows: ["HH:MM <IANA-TZ>", ...]
#     post_reset_fanout:
#       enabled: false
#       phases: [flatline, bridgebuilder, red_team]
#       cron_jitter_min: 7                    # integer 1..59; else default 7
#
# Env overrides:
#   LOA_SESSION_CAP_CONFIG_FILE      override .loa.config.yaml path
#   LOA_SESSION_CAP_SCHEDULES_DIR    override .run/schedules output dir
#                                      (testability — production installs
#                                      write .run/schedules/ of the repo the
#                                      script lives in)
#
# Marker convention: `# loa-cycle117-session-cap-fanout BEGIN` / `... END`
# =============================================================================

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_REPO_ROOT="$(cd "${_SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${_SCRIPT_DIR}/compat-lib.sh"

_LIB="${_REPO_ROOT}/.claude/scripts/lib/scheduled-cycle-lib.sh"
_CONTRACTS_REL=".claude/skills/scheduled-cycle-template/contracts"
# Real bridgebuilder dispatch contract (bd-fanout-real-dispatch-9jv6 T1).
_CONTRACTS_BB_REL="${_CONTRACTS_REL}/session-cap-bb"
# Per-phase stagger (minutes) so multiple phases in ONE reset window fire at
# DISTINCT minutes rather than simultaneously. 7 is coprime to 60, so phase_idx
# * 7 (mod 60) is distinct for every realistic phase count, and the >1-minute
# spacing survives _final_minute's off-:00/:30 nudge without collisions.
_PHASE_STAGGER_MIN=7
# Real multi-model BB budget for the bridgebuilder schedule. Bounded by the L3
# projected-cycle guard (timeout_seconds x 5 phases must be <= max_cycle_seconds,
# default 14400), so 1800s (30m) is the generous-but-safe ceiling — raise both
# together if a real BB run needs longer.
_BB_TIMEOUT_SECONDS=1800
_LOG_PATH="${_REPO_ROOT}/.run/session-cap-fanout-cron.log"
MARKER_BEGIN="# loa-cycle117-session-cap-fanout BEGIN"
MARKER_END="# loa-cycle117-session-cap-fanout END"
PLACEHOLDER_BODY="with placeholder phases -- real dispatch: bd-fanout-real-dispatch-9jv6"
PLACEHOLDER_NOTE="ARMED ${PLACEHOLDER_BODY}"

_schedules_dir() {
    echo "${LOA_SESSION_CAP_SCHEDULES_DIR:-${_REPO_ROOT}/.run/schedules}"
}

usage() {
    sed -n '2,52p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
    exit 0
}

_config_path() {
    echo "${LOA_SESSION_CAP_CONFIG_FILE:-${_REPO_ROOT}/.loa.config.yaml}"
}

# -----------------------------------------------------------------------------
# Config readers — yq preferred, python3+PyYAML fallback (house convention;
# see budget-reconcile-install.sh / audit-snapshot-install.sh).
# -----------------------------------------------------------------------------

read_reset_windows() {
    local config
    config="$(_config_path)"
    [[ -f "$config" ]] || return 0
    if command -v yq >/dev/null 2>&1; then
        yq -r '.session_cap.reset_windows[]' "$config" 2>/dev/null || true
        return 0
    fi
    python3 - "$config" <<'PY' 2>/dev/null || true
import sys
try:
    import yaml
except ImportError:
    sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    sys.exit(0)
for w in ((doc.get('session_cap') or {}).get('reset_windows') or []):
    print(w)
PY
}

read_fanout_enabled() {
    local config
    config="$(_config_path)"
    if [[ ! -f "$config" ]]; then echo "false"; return 0; fi
    if command -v yq >/dev/null 2>&1; then
        local v
        v="$(yq -r '.session_cap.post_reset_fanout.enabled // false' "$config" 2>/dev/null || echo false)"
        [[ -z "$v" || "$v" == "null" ]] && v="false"
        echo "$v"
        return 0
    fi
    python3 - "$config" <<'PY' 2>/dev/null || echo false
import sys
try:
    import yaml
except ImportError:
    print("false"); sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print("false"); sys.exit(0)
v = ((doc.get('session_cap') or {}).get('post_reset_fanout') or {}).get('enabled', False)
print("true" if v else "false")
PY
}

read_fanout_phases() {
    local config default_phases
    config="$(_config_path)"
    default_phases="flatline
bridgebuilder
red_team"
    if [[ ! -f "$config" ]]; then printf '%s\n' "$default_phases"; return 0; fi
    if command -v yq >/dev/null 2>&1; then
        local out
        out="$(yq -r '.session_cap.post_reset_fanout.phases[]' "$config" 2>/dev/null || true)"
        if [[ -z "$out" ]]; then printf '%s\n' "$default_phases"; else printf '%s\n' "$out"; fi
        return 0
    fi
    python3 - "$config" <<'PY' 2>/dev/null || printf '%s\n' "$default_phases"
import sys
try:
    import yaml
except ImportError:
    sys.exit(1)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    sys.exit(1)
phases = ((doc.get('session_cap') or {}).get('post_reset_fanout') or {}).get('phases')
if not phases:
    phases = ["flatline", "bridgebuilder", "red_team"]
for p in phases:
    print(p)
PY
}

# read_cron_jitter_min — default 7; validated integer in [1,59], else 7
# (division-by-zero guard for the jitter modulo below).
read_cron_jitter_min() {
    local config v
    config="$(_config_path)"
    v="7"
    if [[ -f "$config" ]]; then
        if command -v yq >/dev/null 2>&1; then
            v="$(yq -r '.session_cap.post_reset_fanout.cron_jitter_min // 7' "$config" 2>/dev/null || echo 7)"
        else
            v="$(python3 - "$config" <<'PY' 2>/dev/null || echo 7
import sys
try:
    import yaml
except ImportError:
    print(7); sys.exit(0)
try:
    with open(sys.argv[1]) as f:
        doc = yaml.safe_load(f) or {}
except Exception:
    print(7); sys.exit(0)
v = ((doc.get('session_cap') or {}).get('post_reset_fanout') or {}).get('cron_jitter_min', 7)
print(v if v is not None else 7)
PY
)"
        fi
    fi
    [[ -z "$v" || "$v" == "null" ]] && v=7
    if ! [[ "$v" =~ ^[0-9]+$ ]] || (( v < 1 || v > 59 )); then
        v=7
    fi
    echo "$v"
}

# -----------------------------------------------------------------------------
# Jitter — deterministic per-repo minute offset via sha256_portable (NEVER
# raw sha256sum; tools/check-no-raw-sha256sum.sh hard-fails CI on that).
# Offset is always in [1, jitter_min] (never 0), so the fire time is always
# strictly AFTER the configured reset. Final minute is nudged off :00/:30.
# -----------------------------------------------------------------------------

_jitter_offset() {
    local jitter_min="$1"
    local h dec
    h="$(printf '%s' "$_REPO_ROOT" | sha256_portable | awk '{print $1}' | cut -c1-8)"
    dec=$((16#$h))
    echo $(( (dec % jitter_min) + 1 ))
}

# _final_minute <base_minute> <offset> — apply offset mod 60, nudge off :00/:30.
_final_minute() {
    local base_minute="$1" offset="$2" m
    m=$(( (base_minute + offset) % 60 ))
    while (( m == 0 || m == 30 )); do
        m=$(( (m + 1) % 60 ))
    done
    echo "$m"
}

_system_tz() {
    timedatectl show -p Timezone --value 2>/dev/null \
        || cat /etc/timezone 2>/dev/null \
        || echo UTC
}

# -----------------------------------------------------------------------------
# YAML generation
# -----------------------------------------------------------------------------

_generate_yaml() {
    local schedule_id="$1" cron_minute="$2" cron_hour="$3" window_tz="$4" phase="$5"
    if [[ "$phase" == "bridgebuilder" ]]; then
        cat <<YAML
# GENERATED by session-cap-fanout.sh -- regenerated on every install, do not
# hand-edit. REAL bridgebuilder dispatch (bd-fanout-real-dispatch-9jv6 T1):
# dispatch_contract points at the session-cap-bb phase scripts. The decider is
# FAIL-CLOSED -- it only fires bridgebuilder-review's headless entrypoint
# (resources/entry.sh, the same one spiral-harness.sh already runs unattended)
# when the captured session-limit snapshot shows sprint_plan/bridge RUNNING or
# HALTED; otherwise it is a no-op. Arming this posts LIVE PR review comments
# unattended on cron.
# window_tz: ${window_tz} (informational; the crontab TZ= line carries the
# actual timezone this schedule's hour/minute are LOCAL to)
schedule_id: ${schedule_id}
schedule: "${cron_minute} ${cron_hour} * * *"
dispatch_contract:
  reader:     "${_CONTRACTS_BB_REL}/reader.sh"
  decider:    "${_CONTRACTS_BB_REL}/decider.sh"
  dispatcher: "${_CONTRACTS_BB_REL}/dispatcher.sh"
  awaiter:    "${_CONTRACTS_BB_REL}/awaiter.sh"
  logger:     "${_CONTRACTS_BB_REL}/logger.sh"
  budget_estimate_usd: 0
  timeout_seconds: ${_BB_TIMEOUT_SECONDS}
YAML
    else
        cat <<YAML
# GENERATED by session-cap-fanout.sh -- regenerated on every install, do not
# hand-edit. PLACEHOLDER (Tranche 2, deferred): dispatch_contract points at the
# shipped no-op example-*.sh phase scripts. Real "${phase}" dispatch needs an
# operator decision on current-state vs resume-exact doc-targeting semantics
# (bd-fanout-real-dispatch-9jv6 Tranche 2) -- flatline/red_team hard-require an
# explicit --doc <path> that the session-limit snapshot does not carry.
# window_tz: ${window_tz} (informational; the crontab TZ= line carries the
# actual timezone this schedule's hour/minute are LOCAL to)
schedule_id: ${schedule_id}
schedule: "${cron_minute} ${cron_hour} * * *"
dispatch_contract:
  reader:     "${_CONTRACTS_REL}/example-reader.sh"
  decider:    "${_CONTRACTS_REL}/example-decider.sh"
  dispatcher: "${_CONTRACTS_REL}/example-dispatcher.sh"
  awaiter:    "${_CONTRACTS_REL}/example-awaiter.sh"
  logger:     "${_CONTRACTS_REL}/example-logger.sh"
  budget_estimate_usd: 0
  timeout_seconds: 300
YAML
    fi
}

# -----------------------------------------------------------------------------
# _plan <target_dir>
#
# Reads config, generates one YAML per (window x phase) into <target_dir>,
# registers each via the L3 lib (abort-on-first-failure), and populates the
# global CRON_LINES array ("tz|<cron line text>"). Returns 1 (target_dir left
# as-is for caller cleanup) if reset_windows is empty or any register fails.
# -----------------------------------------------------------------------------
CRON_LINES=()

_plan() {
    local target_dir="$1"
    CRON_LINES=()

    local windows=()
    while IFS= read -r _w; do
        [[ -n "$_w" ]] && windows+=("$_w")
    done < <(read_reset_windows)
    if [[ ${#windows[@]} -eq 0 ]]; then
        echo "session_cap.reset_windows is empty; nothing to plan." >&2
        return 2
    fi

    local phases=()
    while IFS= read -r _p; do
        [[ -n "$_p" ]] && phases+=("$_p")
    done < <(read_fanout_phases)

    local jitter_min offset
    jitter_min="$(read_cron_jitter_min)"
    offset="$(_jitter_offset "$jitter_min")"

    local schedules_dir
    schedules_dir="$(_schedules_dir)"

    local idx=0 window
    for window in "${windows[@]}"; do
        local time_part tz_part hour minute
        time_part="${window%% *}"
        tz_part="${window#* }"
        hour="${time_part%%:*}"
        minute="${time_part##*:}"
        hour=$((10#$hour))
        minute=$((10#$minute))

        local phase phase_idx=0 final_minute
        for phase in "${phases[@]}"; do
            # Per-phase deterministic stagger: each phase in this window fires at
            # a DISTINCT minute (base per-repo jitter + phase_idx * stagger),
            # still nudged off :00/:30 by _final_minute. Without this, every
            # phase in one reset window fired at the identical minute
            # (bd-fanout-real-dispatch-9jv6 T1).
            final_minute="$(_final_minute "$minute" "$((offset + phase_idx * _PHASE_STAGGER_MIN))")"
            local schedule_id="session-cap-fanout-w${idx}-${phase}"
            local yaml_path="${target_dir}/${schedule_id}.yaml"
            _generate_yaml "$schedule_id" "$final_minute" "$hour" "$tz_part" "$phase" > "$yaml_path"

            if ! "$_LIB" register "$yaml_path" >/dev/null; then
                echo "ERROR: register failed for ${yaml_path}; aborting" >&2
                return 1
            fi

            local final_yaml_path="${schedules_dir}/${schedule_id}.yaml"
            local invoke_cmd="cd ${_REPO_ROOT} && ${_LIB} invoke ${final_yaml_path} >> ${_LOG_PATH} 2>&1"
            CRON_LINES+=("${tz_part}|${final_minute} ${hour} * * * ${invoke_cmd}  # loa-cycle117-session-cap-fanout w${idx}:${phase}")
            phase_idx=$((phase_idx + 1))
        done
        idx=$((idx + 1))
    done
    return 0
}

# -----------------------------------------------------------------------------
# Crontab block assembly (grouped by TZ, LC_ALL=C sort for determinism; final
# line resets TZ to the system default so entries added later via `crontab
# -e` are not silently reinterpreted under a leaked TZ= setting).
# -----------------------------------------------------------------------------

_build_crontab_block() {
    local -a tzs=()
    local seen="|" line tz
    for line in "${CRON_LINES[@]}"; do
        tz="${line%%|*}"
        case "$seen" in
            *"|${tz}|"*) ;;
            *) seen="${seen}${tz}|"; tzs+=("$tz") ;;
        esac
    done
    local sorted_tzs
    sorted_tzs="$(printf '%s\n' "${tzs[@]}" | LC_ALL=C sort)"

    echo "$MARKER_BEGIN"
    echo "# ${PLACEHOLDER_NOTE}"
    echo "# NOTE: crontab TZ= env-lines persist to end-of-file (POSIX cron"
    echo "# semantics, no 'unset' syntax) -- this block always ends with an"
    echo "# explicit system-TZ reset line so entries added below it via"
    echo "# 'crontab -e' are not silently reinterpreted under our TZ setting."
    local t
    while IFS= read -r t; do
        [[ -z "$t" ]] && continue
        echo "TZ=${t}"
        for line in "${CRON_LINES[@]}"; do
            [[ "${line%%|*}" == "$t" ]] && echo "${line#*|}"
        done
    done <<<"$sorted_tzs"
    echo "TZ=$(_system_tz)"
    echo "$MARKER_END"
}

_strip_managed_block() {
    local existing="$1"
    awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '
        $0==b {skip=1; next}
        $0==e {skip=0; next}
        skip!=1 {print}
    ' <<<"$existing"
}

# -----------------------------------------------------------------------------
# Subcommands
# -----------------------------------------------------------------------------

cmd_install() {
    local dry_run=0
    while (( $# )); do
        case "$1" in
            --dry-run) dry_run=1; shift ;;
            *) echo "unknown install arg: $1" >&2; return 2 ;;
        esac
    done

    local enabled
    enabled="$(read_fanout_enabled)"
    if [[ "$enabled" != "true" ]]; then
        echo "session_cap.post_reset_fanout.enabled is not true; nothing to install."
        return 0
    fi

    local target_dir rc=0
    if (( dry_run )); then
        target_dir="$(mktemp -d)"
    else
        target_dir="$(_schedules_dir)"
        mkdir -p "$target_dir"
    fi

    if _plan "$target_dir"; then
        rc=0
    else
        rc=$?
    fi
    if (( rc != 0 )); then
        (( dry_run )) && rm -rf "$target_dir"
        if (( rc == 2 )); then
            echo "Nothing to install."
            return 0
        fi
        return 1
    fi

    if (( dry_run )); then
        echo "WOULD ARM ${PLACEHOLDER_BODY} (dry-run: no writes to $(_schedules_dir), no crontab changes)"
        echo "--- Generated YAMLs (would be written to $(_schedules_dir)/) ---"
        local f
        for f in "$target_dir"/*.yaml; do
            echo "== $(_schedules_dir)/$(basename "$f") =="
            cat "$f"
        done
        echo "--- Would-be crontab block ---"
        _build_crontab_block
        rm -rf "$target_dir"
        return 0
    fi

    echo "$PLACEHOLDER_NOTE"
    if ! command -v crontab >/dev/null 2>&1; then
        echo "crontab not available on this system" >&2
        return 1
    fi
    local existing new_block
    existing="$(crontab -l 2>/dev/null || true)"
    new_block="$(_build_crontab_block)"
    printf '%s\n%s\n' "$(_strip_managed_block "$existing")" "$new_block" | crontab -
    echo "Installed ${#CRON_LINES[@]} session-cap-fanout crontab entries."
}

cmd_uninstall() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "crontab not available on this system" >&2
        return 1
    fi
    local existing
    existing="$(crontab -l 2>/dev/null || true)"
    if ! printf '%s\n' "$existing" | grep -qF "$MARKER_BEGIN"; then
        echo "Not installed; nothing to remove."
        return 0
    fi
    printf '%s\n' "$(_strip_managed_block "$existing")" | crontab -
    echo "Uninstalled session-cap-fanout crontab block."
}

cmd_status() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "crontab not available on this system"
        return 1
    fi
    local existing
    existing="$(crontab -l 2>/dev/null || true)"
    if printf '%s\n' "$existing" | grep -qF "$MARKER_BEGIN"; then
        echo "INSTALLED"
        awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" '$0==b{f=1} f{print} $0==e{f=0}' <<<"$existing"
        return 0
    fi
    echo "NOT-INSTALLED"
    return 0
}

cmd_show() {
    local target_dir rc
    target_dir="$(mktemp -d)"
    if _plan "$target_dir"; then
        rc=0
    else
        rc=$?
    fi
    if (( rc != 0 )); then
        rm -rf "$target_dir"
        if (( rc == 2 )); then
            echo "Nothing to show."
            return 0
        fi
        return 1
    fi
    echo "--- Generated YAMLs (would be written to $(_schedules_dir)/) ---"
    local f
    for f in "$target_dir"/*.yaml; do
        echo "== $(_schedules_dir)/$(basename "$f") =="
        cat "$f"
    done
    echo "--- Would-be crontab block ---"
    _build_crontab_block
    rm -rf "$target_dir"
}

# -----------------------------------------------------------------------------
# CLI dispatcher — guarded so tests can `source` this file to reach internal
# functions (jitter math, YAML generation) without triggering a subcommand.
# -----------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "$cmd" in
        install)         cmd_install "$@" ;;
        uninstall|--off)  cmd_uninstall ;;
        status)           cmd_status ;;
        show)             cmd_show ;;
        --help|-h|"")     usage ;;
        *) echo "unknown subcommand: $cmd" >&2; exit 2 ;;
    esac
fi
