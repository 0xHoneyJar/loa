#!/usr/bin/env bash
# =============================================================================
# lib/batch-supervisor.sh — the ablation batch supervisor (cycle-133 SDD C-9 as amended by D-2.5; PRD FR-9;
# bd-yvjew, KF-052). run-ablation.sh --supervised [--max-retries N] execs `launch`; nothing else sources it.
#
# Usage:
#   batch-supervisor.sh launch  <batch-dir> --runner R [--max-retries N] [--mode auto|systemd|setsid] -- <runner args…>
#   batch-supervisor.sh restore <batch-dir> [--max-retries N] [--mode auto|systemd|setsid]
#   batch-supervisor.sh stop    <batch-dir>
#   batch-supervisor.sh status  <batch-dir>
#   batch-supervisor.sh run     <batch-dir> --attempt-id ID [--lock-inherited] [--unit U]   (internal: the loop)
#   batch-supervisor.sh record-job <jobs-dir> <name> <pgid> [fields…]   (the .jobs/ record writer; run-ablation.sh)
#
# launch   Precondition (exit 2, nothing written): `loginctl show-user <user> --property=Linger --value` is yes, or
#          this process runs in a system-level scope (/proc/self/cgroup under system.slice); the repair named is
#          `loginctl enable-linger <user>`. Takes flock <batch>/supervisor.lock (held: exit 2 naming the owner; a
#          systemd handover younger than 120 s on this boot is also refused), writes <batch>/supervisor/args.json
#          {schema_version, runner, args, max_retries, batch} (run-ablation.sh copies it into MANIFEST.json
#          supervisor, so a reboot restores the batch from the MANIFEST), starts a new supervision episode (an earlier
#          episode's record moves to history[]) and daemonises the loop: with systemd-run (mode auto: systemd-run on
#          PATH and `systemctl --user show-environment` answering) as `systemd-run --user --unit loa-batch-<name>
#          --collect` (PATH, HOME and the LOA_*/EVAL_* variables whose names do not look secret are passed), else
#          `setsid`, the lock's descriptor inherited so the lock is held across daemonisation. Prints
#          `supervised: batch <dir> mode setsid pid <pid> …` | `… mode systemd unit loa-batch-<name> …`; exit 0.
# restore  After a reboot or a lost supervisor: the args from supervisor/args.json (the latest launch; else the
#          MANIFEST.json supervisor copy of the first, for a batch directory restored without its ignored files),
#          the retries of the episode kept (the cap counts across the reboot); a record whose state is not running
#          is refused (exit 2: launch with --resume instead), as is a reached cap. The batch resumes as a retry of
#          class reboot (boot id changed), supervisor_lost (the recorded runner still alive: its group is terminated)
#          or driver_lost.
# stop     The intentional stop (cancellation): writes supervisor/stop and signals a live owner; the loop terminates
#          the runner's process group and every pipeline group under <batch>/.jobs/, removes the batch's
#          containers, records the uncertain provider requests in `stopped` and never retries. Exit 2 when the batch
#          has no supervisor record.
# status   Prints supervisor/state.json.
# record-job  Writes the .jobs/ record of a pipeline group (cycle-134 C-6, D-2.3; bd-ruo5b): first
#          <jobs-dir>/<name>.ident, one line `<start_ticks>:<sha256 hex of /proc/<pgid>/cmdline>` of the group leader
#          (pgid = leader pid; start_ticks is field 22 of /proc/<pgid>/stat), then <jobs-dir>/<name>.pgid, one line
#          `<pgid> [fields…]` (run-ablation.sh: `<pgid> <epoch> <watchdog s>`), each through a temporary file and a
#          rename. The identity is taken once the leader has finished exec'ing (its cmdline differs from the caller's,
#          argv[0] is not setsid or env, two reads 50 ms apart agree; at most 5 s). A leader that exited (silent) or
#          never settles (a warning on stderr) gets no .ident (an earlier .ident of the name is removed) and its .pgid
#          is still written, so the record is stale for reclaim. Exit 0 written; 1 the .pgid write failed; 2 usage.
#
# The loop: runs the runner in its own session (its process group is owned), polls every $LOA_SUPERVISOR_POLL_S
# (default 15) and declares the runner dead when it exits, or hung when it lives and no file under the batch
# (depth ≤ 4, the supervisor's own files excluded) changed for $LOA_SUPERVISOR_HANG_S (default 1800) while STATUS.json
# is absent or `running` (the hung runner's group gets TERM, KILL after $LOA_SUPERVISOR_GRACE_S, default 30).
# Classes (last_exit.reason_class): exit 0 complete; exit 2 refusal; exit 3 failed; then from STATUS.json and the
# run dirs: budget (cuts[]), outage, metering_incomplete (a meta/pipeline.json reason), paused_arm — none retried;
# retried: driver_lost (killed or signalled from outside, STATUS.json not final), hang, infrastructure_error (rows
# of the batch with that status or interrupted: the resume adds --rerun-status for each), incomplete (exit 1 with
# trials left and no named cause). Before every resume: the runner's group and the .jobs/ groups are terminated
# (on the same boot only — after a reboot a recorded pid may be another process: the stale .lock/ and .jobs/ are
# removed unsignalled; on the same boot a .jobs/ group is signalled only when its identity matches, see Job records
# below), containers named loa-abl-<batch>-* are removed (docker rm -f; the run ids are
# <batch>-…, so this is every loa-abl-<run_id>-* of the batch), and the uncertain provider requests are reconciled:
# the run dirs whose meta/pipeline.json was missing or running when the runner died, their cost-ledger.jsonl
# request ids and ledger micro-USD go into the retry entry (the runner's resume charges such a trial its cap).
# The resume argv: --resume --batch <name> plus the launch's --results-root, --smoke, --max-usd, --concurrency,
# --self-check-log and collaborator --*-bin flags (the MANIFEST supplies the rest). After --max-retries retries
# (default 3) the state is gave_up.
#
# State: <batch>/supervisor/state.json, mirrored into STATUS.json supervisor under flock <batch>/STATUS.json.lock
# (run-ablation.sh write_status takes the same lock and keeps the key): {schema_version, state: launching | running
# | complete | halted | gave_up | stopped, owner_pid, boot_id, start_time, start_ticks (the owner's
# /proc/<pid>/stat start time: a pid is the owner only on the same boot with the same start time), unit, mode,
# attempt_id, runner_pid, runner_start_ticks, cap, retries: [{at, reason_class, retry_id (<attempt_id>-r<n>),
# provider_request_ids, uncertain_runs, ledger_micro_usd, containers_stopped, groups_terminated, resume_args}],
# history, last_exit {rc, reason_class, at}, stopped}. Logs: supervisor/supervisor.log, supervisor/runner.log.
# Exit (run): 0 complete; 1 halted, gave_up or stopped; 2 refused (lock, superseded).
# Env: LOA_SUPERVISOR_POLL_S, LOA_SUPERVISOR_HANG_S, LOA_SUPERVISOR_GRACE_S, LOA_SUPERVISOR_MODE (the --mode
#   default), LOA_SUPERVISOR_LOGINCTL (default loginctl), LOA_SUPERVISOR_BOOT_ID_FILE (default
#   /proc/sys/kernel/random/boot_id; tests), EVAL_DOCKER_BIN (when the runner args name no --docker-bin).
# Job records (cycle-134 C-6, D-2.3; FR-7, bd-ruo5b): <batch>/.jobs/<name>.pgid `<pgid> …` and <name>.ident
#   `<start_ticks>:<sha256 of the leader's cmdline>` (record-job; the .ident is published before the .pgid, so a
#   .pgid without .ident is legacy — written before cycle-134 — or partial). reclaim on the same boot, per .pgid:
#   no .ident → stale: never signalled, both files removed, one warning listing `<name> <pgid>` of every such record;
#   the leader /proc/<pgid> gone (or a zombie) while the group has members → leaderless: never signalled (its
#   identity cannot be verified), the member pids logged for the operator, the record removed; the leader's identity
#   differs from the record (a reused pid) → stale: logged, never signalled, removed; it matches → kill_group with the
#   identity re-read immediately before TERM (changed: nothing sent) and again before KILL (the leader alive with
#   another identity: the KILL is not sent; the leader gone or a zombie while members remain: the KILL is sent — a pid
#   is not reused while any process still has it as its process group id). A group with no process left is skipped.
#   Residual window: numeric pgids cannot be checked and signalled atomically (no pidfd for a process group), so a
#   pgid that exits and is reused between the identity read and kill(2) — microseconds — would be signalled; the two
#   re-reads keep that window to the span of one read and one syscall.
# Tested by evals/tests/batch-supervisor.bats (stub runners, loginctl, docker and systemd-run; no model call).
# =============================================================================
set -euo pipefail
export LC_ALL=C

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
POLL_S="${LOA_SUPERVISOR_POLL_S:-15}"
HANG_S="${LOA_SUPERVISOR_HANG_S:-1800}"
GRACE_S="${LOA_SUPERVISOR_GRACE_S:-30}"
LOGINCTL="${LOA_SUPERVISOR_LOGINCTL:-loginctl}"
BOOT_ID_FILE="${LOA_SUPERVISOR_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"
HANDOVER_S=120

die() { echo "batch-supervisor: $*" >&2; exit 2; }
refuse() { echo "batch-supervisor: refused: $*" >&2; exit 2; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
[[ "$POLL_S" =~ ^[0-9]{1,4}(\.[0-9]{1,3})?$ ]] || die "LOA_SUPERVISOR_POLL_S must be seconds"
[[ "$HANG_S" =~ ^[1-9][0-9]{0,6}$ ]] || die "LOA_SUPERVISOR_HANG_S must be positive whole seconds"
[[ "$GRACE_S" =~ ^[0-9]{1,4}$ ]] || die "LOA_SUPERVISOR_GRACE_S must be whole seconds"
for tool in jq flock setsid find; do command -v "$tool" >/dev/null 2>&1 || die "missing tool: $tool"; done

boot_id() { tr -d ' \n' < "$BOOT_ID_FILE"; }
ticks_of() { [[ -r "/proc/$1/stat" ]] || return 1; awk '{ sub(/^.*\) /, ""); print $20 }' "/proc/$1/stat"; }
# ident_alive <pid> <start ticks> <boot id> → 0 when that pid is the recorded process (same boot, same start time)
ident_alive() {
  local p="$1" t="$2" b="$3" now
  [[ "$p" =~ ^[0-9]+$ && -n "$t" && "$t" != null ]] || return 1
  [[ "$b" == "$(boot_id)" ]] || return 1
  now="$(ticks_of "$p")" || return 1
  [[ "$now" == "$t" ]]
}
# leader_live <pid> → 0 when /proc/<pid> is a live process (not gone, not a zombie)
leader_live() {
  local st
  [[ -r "/proc/$1/stat" ]] || return 1
  st="$(awk '{ sub(/^.*\) /, ""); print $1 }' "/proc/$1/stat" 2>/dev/null)" || return 1
  [[ -n "$st" && "$st" != Z && "$st" != X ]]
}
# job_ident <pgid> → `<start_ticks>:<sha256 hex of /proc/<pgid>/cmdline>` of the live group leader (1 when unreadable)
job_ident() {
  local p="$1" t h
  [[ "$p" =~ ^[1-9][0-9]*$ ]] && leader_live "$p" || return 1
  t="$(ticks_of "$p")" || return 1
  [[ "$t" =~ ^[0-9]+$ ]] || return 1
  h="$(sha256sum < "/proc/$p/cmdline" 2>/dev/null)" || return 1
  h="${h%% *}"
  [[ "$h" =~ ^[0-9a-f]{64}$ ]] || return 1
  [[ "$(ticks_of "$p" 2>/dev/null)" == "$t" ]] || return 1   # the pid did not change hands between the two reads
  printf '%s:%s' "$t" "$h"
}
# job_ident_settled <pgid> <caller pid> → job_ident once the leader has finished exec'ing (bounded: 100 × 50 ms)
job_ident_settled() {
  local p="$1" caller="$2" i=0 a b own arg0
  own="$(sha256sum < "/proc/$caller/cmdline" 2>/dev/null)" || own=""
  own="${own%% *}"
  while (( i < 100 )); do
    [[ -e "/proc/$p" ]] || return 1
    a="$(job_ident "$p")" || return 1
    arg0="$(tr '\0' '\n' < "/proc/$p/cmdline" 2>/dev/null | head -n 1)" || arg0=""
    arg0="${arg0##*/}"
    if [[ "${a#*:}" != "$own" && "$arg0" != setsid && "$arg0" != env && -n "$arg0" ]]; then
      sleep 0.05
      b="$(job_ident "$p")" || return 1
      [[ "$a" == "$b" ]] && { printf '%s' "$a"; return 0; }
    else
      sleep 0.05
    fi
    i=$((i + 1))
  done
  return 1
}
# group_members <pgid> → newline list of the pids whose process group is <pgid>
group_members() {
  if command -v pgrep >/dev/null 2>&1; then pgrep -g "$1" 2>/dev/null || true; return 0; fi
  local s l
  local -a f
  for s in /proc/[0-9]*/stat; do
    read -r l 2>/dev/null < "$s" || continue
    l="${l##*) }"; read -r -a f <<<"$l"
    [[ "${f[2]:-}" == "$1" ]] && { s="${s#/proc/}"; printf '%s\n' "${s%/stat}"; }
  done
  return 0
}

# --- the record ------------------------------------------------------------------------------------------------------
B="" SUPD="" STATE_F="" ARGS_F="" LOGF=""
paths() {
  B="$1"; [[ "$B" == /* ]] || B="$PWD/$B"
  SUPD="$B/supervisor" STATE_F="$B/supervisor/state.json" ARGS_F="$B/supervisor/args.json" LOGF="$B/supervisor/supervisor.log"
}
log() { printf '%s %s\n' "$(now_iso)" "$*" >> "$LOGF"; }
sget() { jq -r "$1" "$STATE_F"; }
# sset <jq filter> [jq args…] — rewrite state.json, then mirror it into STATUS.json supervisor under the status lock
sset() {
  local f="$1"; shift
  jq "$@" "$f" "$STATE_F" > "$STATE_F.tmp" || die "state update failed ($f)"
  mv "$STATE_F.tmp" "$STATE_F"
  mirror
}
mirror() {
  [[ -f "$B/STATUS.json" ]] || return 0
  {
    flock -x 8
    if jq --slurpfile s "$STATE_F" '.supervisor = $s[0]' "$B/STATUS.json" > "$B/STATUS.json.sup.tmp"; then
      mv "$B/STATUS.json.sup.tmp" "$B/STATUS.json"
    else
      rm -f "$B/STATUS.json.sup.tmp"; log "WARN STATUS.json unreadable; the supervisor entry is in $STATE_F only"
    fi
  } 8>>"$B/STATUS.json.lock"
}

# --- the precondition and the lock ------------------------------------------------------------------------------------
linger_ok() {
  local v user
  user="$(id -un)"
  # a system.slice scope (a service unit) lingers by construction; the file is a knob for the bats (LOA_SUPERVISOR_CGROUP_FILE,
  # like LOA_SUPERVISOR_BOOT_ID_FILE) because a CI runner itself runs under system.slice
  if grep -q '/system\.slice/' "${LOA_SUPERVISOR_CGROUP_FILE:-/proc/self/cgroup}" 2>/dev/null; then return 0; fi
  if command -v "$LOGINCTL" >/dev/null 2>&1; then
    v="$("$LOGINCTL" show-user "$user" --property=Linger --value 2>/dev/null)" || v="unknown"
  else
    v="unavailable (no $LOGINCTL)"
  fi
  [[ "$v" == yes ]] && return 0
  refuse "--supervised needs a lingering user so a logout or a closed terminal cannot end the batch (Linger is ${v:-empty} for $user); run \`loginctl enable-linger $user\` and launch again"
}
# take_lock — fd 9 on supervisor.lock, non-blocking; refuses naming the owner
take_lock() {
  exec 9>>"$B/supervisor.lock"
  if ! flock -n 9; then
    local who="unknown"
    [[ -f "$STATE_F" ]] && who="$(sget '.owner_pid // "unknown"')"
    refuse "$B is supervised by pid $who (flock $B/supervisor.lock is held); stop it first (batch-supervisor.sh stop $B)"
  fi
  if [[ -f "$STATE_F" && "$(sget .state)" == launching && "$(sget '.boot_id')" == "$(boot_id)" ]] \
     && (( $(date +%s) - $(sget '.launched_epoch // 0') < HANDOVER_S )); then
    refuse "$B is being handed to its systemd unit $(sget '.unit') (attempt $(sget .attempt_id)); retry in $HANDOVER_S s"
  fi
}

new_attempt_id() { printf 'sv-%s-%s' "$(date -u +%Y%m%dT%H%M%SZ)" "$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"; }

pick_mode() {
  case "$1" in
    setsid|systemd) printf '%s' "$1" ;;
    auto) if command -v systemd-run >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then printf systemd; else printf setsid; fi ;;
    *) die "--mode must be auto, systemd or setsid" ;;
  esac
}
safe_name() { printf '%s' "$(basename "$B")" | tr -c 'A-Za-z0-9_.-' '-'; }   # printf: no newline turned into a dash
unit_of() { printf 'loa-batch-%s' "$(safe_name)"; }

# daemonise <mode> <attempt id> — start the loop and print the launch line
daemonise() {
  local mode="$1" aid="$2" unit pid
  if [[ "$mode" == systemd ]]; then
    unit="$(unit_of)"
    local -a envs=(--setenv="PATH=$PATH" --setenv="HOME=$HOME")
    local n
    while IFS= read -r n; do
      case "$n" in *KEY*|*TOKEN*|*SECRET*|*PASSWORD*|*CREDENTIAL*) continue ;; esac
      envs+=(--setenv="$n=${!n}")
    done < <(compgen -e | grep -E '^(LOA_|EVAL_)' | LC_ALL=C sort)
    sset '.unit = $u | .mode = "systemd"' --arg u "$unit"
    systemd-run --user --unit "$unit" --collect --quiet --working-directory "$PWD" "${envs[@]}" \
      -- "$SELF" run "$B" --attempt-id "$aid" --unit "$unit" </dev/null >>"$LOGF" 2>&1 3>&- 9>&- \
      || { sset '.state = "halted" | .last_exit = {rc: null, reason_class: "launch_failed", at: $at}' --arg at "$(now_iso)"; refuse "systemd-run --user --unit $unit failed (a unit of that name may still be active: systemctl --user status $unit)"; }
    echo "supervised: batch $B mode systemd unit $unit (log $LOGF)"
  else
    sset '.unit = null | .mode = "setsid"'
    setsid "$SELF" run "$B" --attempt-id "$aid" --lock-inherited </dev/null >>"$LOGF" 2>&1 3>&- &
    pid=$!
    echo "supervised: batch $B mode setsid pid $pid (log $LOGF)"
  fi
}

# --- reconciliation ---------------------------------------------------------------------------------------------------
# uncertain_runs — the run dirs (relative to the batch) whose meta/pipeline.json is missing or running
uncertain_runs() {
  local d rel st
  for d in "$B"/*/*/ "$B"/*/*/sessions/*/; do
    d="${d%/}"; [[ -d "$d" ]] || continue
    rel="${d#"$B"/}"
    case "$rel" in supervisor/*|.*) continue ;; esac
    [[ -d "$d/sessions" ]] && continue   # a matched cell: its sessions are the run dirs
    st=missing
    if [[ -f "$d/meta/pipeline.json" ]]; then st="$(jq -r '.status // "missing"' "$d/meta/pipeline.json" 2>/dev/null)" || st=unreadable; fi
    case "$st" in missing|running|unreadable) printf '%s\n' "$rel" ;; esac
  done | LC_ALL=C sort -u
}
# ledger_of <relative run dirs (newline list)> → JSON {ids: [...], micro: N} from their cost-ledger.jsonl files
ledger_of() {
  local rel f
  { while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      while IFS= read -r f; do cat "$f"; echo; done < <(find "$B/$rel" -maxdepth 3 -name cost-ledger.jsonl -type f 2>/dev/null)
    done <<<"$1"
  } | jq -R -s -c '[split("\n")[] | select(length > 0) | fromjson? | select(type == "object")]
      | {ids: ([.[] | .request_id // empty | tostring] | unique), micro: ([.[] | .cost_micro_usd // 0 | tonumber? // 0] | add // 0)}'
}
docker_bin() {
  local d="${EVAL_DOCKER_BIN:-docker}" i
  for ((i = 0; i < ${#RARGS[@]}; i++)); do [[ "${RARGS[$i]}" == --docker-bin ]] && d="${RARGS[$((i + 1))]:-$d}"; done
  printf '%s' "$d"
}
# stop_containers → newline list of the removed names (loa-abl-<batch>-*)
stop_containers() {
  local d prefix n
  d="$(docker_bin)"; prefix="loa-abl-$(safe_name)-"
  command -v "$d" >/dev/null 2>&1 || { log "no docker CLI ($d): no container to stop"; return 0; }
  "$d" ps -a --filter "name=^${prefix//./\\.}" --format '{{.Names}}' 2>>"$LOGF" | while IFS= read -r n; do
    [[ "$n" == "$prefix"* ]] || continue
    if "$d" rm -f "$n" >>"$LOGF" 2>&1; then printf '%s\n' "$n"; else log "WARN docker rm -f $n failed"; fi
  done
}
# kill_group <pgid> [identity] → 0 when the group was alive and has been terminated (TERM, KILL after the grace).
# With an identity (a .jobs/ record): re-read before TERM (changed: nothing sent, 1) and before KILL (the leader alive
# with another identity: no KILL, 1); see Job records in the header for the residual window
kill_group() {
  local g="$1" want="${2:-}" i=0 now
  kill -0 -- "-$g" 2>/dev/null || return 1
  if [[ -n "$want" ]]; then
    now="$(job_ident "$g")" || now=""
    [[ "$now" == "$want" ]] || { log "WARN kill_group: process group $g changed identity before TERM (${now:-leader gone}): not signalled"; return 1; }
  fi
  kill -TERM -- "-$g" 2>/dev/null || true
  while (( i < GRACE_S * 10 )) && kill -0 -- "-$g" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
  if [[ -n "$want" ]] && kill -0 -- "-$g" 2>/dev/null && leader_live "$g"; then
    now="$(job_ident "$g")" || now=""
    [[ "$now" == "$want" ]] || { log "WARN kill_group: process group $g changed identity before KILL (${now:-unreadable}): KILL not sent"; return 1; }
  fi
  kill -KILL -- "-$g" 2>/dev/null || true
  return 0
}
# reclaim <recorded boot id> <runner pid> <runner ticks> → newline list of the terminated groups. Same boot: the
# recorded runner (identity-checked) and every .jobs/ group still alive whose identity matches its record are
# terminated (stale, legacy and leaderless records: see Job records in the header); another boot: nothing is
# signalled (a recorded pid may now be any process) and the stale .lock/ and .jobs/ are removed
reclaim() {
  local rb="$1" rp="$2" rt="$3" f g _ n id now members legacy="" nleg=0
  if [[ "$rb" != "$(boot_id)" ]]; then
    log "reclaim: recorded boot $rb is not this boot: stale .lock/ and .jobs/ removed, nothing signalled"
    rm -rf "$B/.lock" "$B/.jobs"
    return 0
  fi
  if ident_alive "$rp" "$rt" "$rb"; then kill_group "$rp" && printf '%s\n' "$rp"; fi
  for f in "$B"/.jobs/*.pgid; do
    [[ -f "$f" ]] || continue
    read -r g _ < "$f" || continue
    [[ "$g" =~ ^[0-9]+$ ]] || continue
    n="$(basename "$f" .pgid)"
    if [[ ! -f "$B/.jobs/$n.ident" ]]; then   # legacy (before cycle-134) or partial: never signalled
      legacy="$legacy${legacy:+, }$n $g"; nleg=$((nleg + 1)); rm -f "$f"; continue
    fi
    id=""; read -r id < "$B/.jobs/$n.ident" || true
    if ! leader_live "$g"; then
      members="$(group_members "$g")"
      [[ -n "$members" ]] || continue   # nothing of the group is left
      log "WARN reclaim: .jobs/$n: process group $g is leaderless (its leader exited; the identity cannot be verified): not signalled, record removed; live members for the operator: ${members//$'\n'/ } (check them, then kill -TERM -- -$g)"
      rm -f "$f" "$B/.jobs/$n.ident"; continue
    fi
    now="$(job_ident "$g")" || now=""
    if [[ -z "$id" || "$now" != "$id" ]]; then
      log "WARN reclaim: .jobs/$n: process group $g is not the recorded job (identity ${id:-empty} recorded, ${now:-unreadable} now): stale, not signalled, record removed"
      rm -f "$f" "$B/.jobs/$n.ident"; continue
    fi
    kill_group "$g" "$id" && printf '%s\n' "$g"
  done
  [[ $nleg -eq 0 ]] || log "WARN reclaim: $nleg .jobs record(s) carry no identity (.ident: written before cycle-134, or partial) and are stale: not signalled, removed: $legacy"
  return 0
}
# reconcile <reason class> <uncertain runs> <groups list> → the JSON retry/stop fields
reconcile() {
  local cls="$1" unc="$2" groups="$3" led cont
  led="$(ledger_of "$unc")"
  cont="$(stop_containers)"
  jq -n -c --arg cls "$cls" --argjson led "$led" --arg unc "$unc" --arg cont "$cont" --arg groups "$groups" --arg at "$(now_iso)" \
    '{at: $at, reason_class: $cls, provider_request_ids: $led.ids, uncertain_runs: ($unc | split("\n") | map(select(length > 0))),
      ledger_micro_usd: $led.micro, containers_stopped: ($cont | split("\n") | map(select(length > 0))),
      groups_terminated: ($groups | split("\n") | map(select(length > 0) | tonumber))}'
}

# --- the runner's argv -------------------------------------------------------------------------------------------------
RARGS=() RUNNER=""
load_args() {  # load_args — RUNNER and RARGS from supervisor/args.json (the latest launch), else MANIFEST.json supervisor
  local src=""
  if [[ -f "$ARGS_F" ]]; then
    src="$(jq -c '.' "$ARGS_F")" || refuse "unreadable $ARGS_F"
  elif [[ -f "$B/MANIFEST.json" ]] && jq -e '.supervisor.args | type == "array"' "$B/MANIFEST.json" >/dev/null 2>&1; then
    src="$(jq -c '.supervisor' "$B/MANIFEST.json")"
  else
    refuse "$B has no persisted run arguments (MANIFEST.json supervisor or supervisor/args.json)"
  fi
  RUNNER="$(jq -r '.runner // ""' <<<"$src")"
  RARGS=()
  while IFS= read -r -d '' a; do RARGS+=("$a"); done < <(jq -j '.args[] | (tostring + "\u0000")' <<<"$src")
  [[ -n "$RUNNER" && -x "$RUNNER" ]] || refuse "the persisted runner '$RUNNER' is not executable"
}
batch_name() {
  local i n; n="$(basename "$B")"
  for ((i = 0; i < ${#RARGS[@]}; i++)); do [[ "${RARGS[$i]}" == --batch ]] && n="${RARGS[$((i + 1))]:-$n}"; done
  printf '%s' "$n"
}
# resume_argv [extra…] → RESUME_ARGV
resume_argv() {
  RESUME_ARGV=(--resume --batch "$(batch_name)")
  local i a
  for ((i = 0; i < ${#RARGS[@]}; i++)); do
    a="${RARGS[$i]}"
    case "$a" in
      --results-root|--max-usd|--concurrency|--self-check-log|--pipeline-bin|--grade-bin|--row-bin|--took-effect-bin|--docker-bin|--spend-bin)
        RESUME_ARGV+=("$a" "${RARGS[$((i + 1))]:-}"); i=$((i + 1)) ;;
      --smoke) RESUME_ARGV+=("$a") ;;
    esac
  done
  RESUME_ARGV+=("$@")
}

# --- classification -----------------------------------------------------------------------------------------------------
rows_file() {
  local i r=""
  [[ -f "$B/MANIFEST.json" ]] && r="$(jq -r '.rows_file // ""' "$B/MANIFEST.json" 2>/dev/null)" || true
  if [[ -z "$r" ]]; then for ((i = 0; i < ${#RARGS[@]}; i++)); do [[ "${RARGS[$i]}" == --rows ]] && r="${RARGS[$((i + 1))]:-}"; done; fi
  printf '%s' "$r"
}
batch_rows_with() {  # batch_rows_with <status> → 0 when a row of this batch has that status
  local r; r="$(rows_file)"
  [[ -n "$r" && -f "$r" ]] || return 1
  jq -R -e --arg p "$(batch_name)-" --arg s "$1" 'fromjson? | select(type == "object" and ((.run_id // "") | startswith($p)) and .status == $s)' "$r" >/dev/null 2>&1
}
metering_incomplete() {
  local f
  while IFS= read -r f; do
    jq -e '(.reason // "") | tostring | startswith("metering_incomplete")' "$f" >/dev/null 2>&1 && return 0
  done < <(find "$B" -maxdepth 6 -path '*/meta/pipeline.json' -type f 2>/dev/null)
  return 1
}
CLASS="" RETRYABLE=false EXTRA=()
classify() {  # classify <rc> → CLASS, RETRYABLE, EXTRA (the resume's --rerun-status flags)
  local rc="$1" st="{}"
  CLASS="" RETRYABLE=false EXTRA=()
  [[ -f "$B/STATUS.json" ]] && { st="$(jq -c '.' "$B/STATUS.json" 2>/dev/null)" || st="{}"; }
  case "$rc" in
    0) CLASS=complete; return 0 ;;
    2) CLASS=refusal; return 0 ;;
    3) CLASS=failed; return 0 ;;
  esac
  if [[ "$(jq -r '(.cuts // []) | length' <<<"$st")" -gt 0 ]]; then CLASS=budget
  elif [[ "$(jq -r '.outage != null' <<<"$st")" == true ]]; then CLASS=outage
  elif metering_incomplete; then CLASS=metering_incomplete
  elif [[ "$(jq -r '(.paused_arms // {}) | length' <<<"$st")" -gt 0 ]]; then CLASS=paused_arm
  elif [[ "$rc" != 1 || "$(jq -r '.state // "running"' <<<"$st")" == running || "$(jq -r '.signalled // false' <<<"$st")" == true ]]; then
    CLASS=driver_lost RETRYABLE=true
  else
    batch_rows_with infrastructure_error && EXTRA+=(--rerun-status infrastructure_error)
    batch_rows_with interrupted && EXTRA+=(--rerun-status interrupted)
    if [[ ${#EXTRA[@]} -gt 0 ]]; then CLASS=infrastructure_error; else CLASS=incomplete; fi
    RETRYABLE=true
  fi
}

# --- the loop -------------------------------------------------------------------------------------------------------------
STOP_REQ=0 RPID=""
progress_since() {  # progress_since <epoch> → 0 when a batch file (not the supervisor's) changed after it
  local ref="$SUPD/.hang-ref"
  touch -d "@$1" "$ref"
  [[ -n "$(find "$B" -maxdepth 4 -newer "$ref" ! -path "$SUPD" ! -path "$SUPD/*" ! -name supervisor.lock ! -name STATUS.json.lock -print -quit 2>/dev/null)" ]]
}
start_runner() {  # start_runner <argv…>
  printf '%s %s\n' "$(now_iso)" "$*" >> "$SUPD/runner.log"
  setsid "$RUNNER" "$@" </dev/null >>"$SUPD/runner.log" 2>&1 9>&- &
  RPID=$!
  local t; t="$(ticks_of "$RPID")" || t=""
  sset '.runner_pid = $p | .runner_start_ticks = (if $t == "" then null else $t end)' --argjson p "$RPID" --arg t "$t"
  log "runner pid $RPID: $*"
}
# watch → WATCH (exited | hang | stop) and WRC (the runner's exit code, or null)
watch() {
  WATCH="" WRC=null
  local last; last="$(date +%s)"
  while kill -0 "$RPID" 2>/dev/null; do
    if [[ "$STOP_REQ" == 1 || -e "$SUPD/stop" ]]; then WATCH=stop; return 0; fi
    sleep "$POLL_S"
    if progress_since "$last"; then last="$(date +%s)"; continue; fi
    local stj=running
    [[ -f "$B/STATUS.json" ]] && { stj="$(jq -r '.state // "running"' "$B/STATUS.json" 2>/dev/null)" || stj=running; }
    if [[ "$stj" == running ]] && (( $(date +%s) - last >= HANG_S )); then WATCH=hang; return 0; fi
  done
  local rc=0; wait "$RPID" || rc=$?
  WATCH=exited WRC="$rc"
  if [[ "$STOP_REQ" == 1 || -e "$SUPD/stop" ]]; then WATCH=stop; fi
}
finish() {  # finish <state> <rc> <reason class> <exit> [stopped JSON]
  sset '.state = $s | .last_exit = {rc: $rc, reason_class: $c, at: $at} | .stopped = $st | .runner_pid = null'  \
    --arg s "$1" --argjson rc "$2" --arg c "$3" --arg at "$(now_iso)" --argjson st "${5:-null}"
  log "supervisor $1 ($3); exit $4"
  exit "$4"
}

cmd_run() {
  local aid="" inherited=false unit=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --attempt-id) aid="${2:-}"; shift 2 ;;
      --lock-inherited) inherited=true; shift ;;
      --unit) unit="${2:-}"; shift 2 ;;
      *) die "run: unknown option $1" ;;
    esac
  done
  [[ -n "$aid" ]] || die "run needs --attempt-id"
  if [[ "$inherited" == true ]]; then flock -n 9 || refuse "the inherited supervisor.lock is not held"
  else exec 9>>"$B/supervisor.lock"; flock -w "$HANDOVER_S" 9 || refuse "supervisor.lock not acquired within $HANDOVER_S s"; fi
  [[ "$(sget .attempt_id)" == "$aid" && "$(sget .state)" == launching ]] || refuse "attempt $aid was superseded ($(sget .attempt_id), $(sget .state))"
  trap 'STOP_REQ=1' TERM INT HUP
  rm -f "$SUPD/stop"
  sset '.state = "running" | .owner_pid = $p | .start_time = $t | .start_ticks = $k | .boot_id = $b'  \
    --argjson p "$$" --arg t "$(now_iso)" --arg k "$(ticks_of $$)" --arg b "$(boot_id)"
  load_args
  log "supervisor attempt $aid pid $$ owns $B (cap $(sget .cap); unit ${unit:-none})"
  local -a argv=()
  local pend; pend="$(sget '.pending_resume // null')"
  if [[ "$pend" != null ]]; then
    while IFS= read -r -d '' a; do argv+=("$a"); done < <(jq -j '.[] | (tostring + "\u0000")' <<<"$pend")
    sset '.pending_resume = null'
  else
    argv=(${RARGS[@]+"${RARGS[@]}"})
  fi
  local unc groups entry n cap
  while true; do
    start_runner "${argv[@]}"
    watch
    unc="$(uncertain_runs)"
    if [[ "$WATCH" != exited ]]; then
      groups="$(kill_group "$RPID" && printf '%s\n' "$RPID")" || groups=""
      wait "$RPID" 2>/dev/null || true
    else groups=""; fi
    if [[ "$WATCH" == stop ]]; then
      groups="$groups"$'\n'"$(reclaim "$(boot_id)" "" "")"
      entry="$(reconcile intentional_stop "$unc" "$groups")"
      finish stopped "$WRC" intentional_stop 1 "$entry"
    fi
    if [[ "$WATCH" == hang ]]; then CLASS=hang RETRYABLE=true EXTRA=(); log "runner $RPID hung: no batch file changed for $HANG_S s"
    else classify "$WRC"; log "runner $RPID exited $WRC: $CLASS"; fi
    sset '.last_exit = {rc: $rc, reason_class: $c, at: $at}' --argjson rc "$WRC" --arg c "$CLASS" --arg at "$(now_iso)"
    [[ "$CLASS" != complete ]] || finish complete 0 complete 0
    [[ "$RETRYABLE" == true ]] || finish halted "$WRC" "$CLASS" 1
    n="$(sget '.retries | length')" cap="$(sget .cap)"
    if (( n >= cap )); then log "retry cap $cap reached ($CLASS)"; finish gave_up "$WRC" "$CLASS" 1; fi
    groups="$groups"$'\n'"$(reclaim "$(boot_id)" "" "")"
    entry="$(reconcile "$CLASS" "$unc" "$groups")"
    if [[ -f "$B/MANIFEST.json" && -f "$B/STATUS.json" ]]; then resume_argv ${EXTRA[@]+"${EXTRA[@]}"}; argv=("${RESUME_ARGV[@]}")
    else argv=(${RARGS[@]+"${RARGS[@]}"}); fi   # the runner died before its MANIFEST: the launch again
    sset '.retries += [$e + {retry_id: ($aid + "-r" + ((.retries | length) + 1 | tostring)), resume_args: $a}]' \
      --argjson e "$entry" --arg aid "$aid" --argjson a "$(printf '%s\0' "${argv[@]}" | jq -R -s -c 'split("\u0000")[:-1]')"
    log "retry $((n + 1)) of $cap ($CLASS): ${argv[*]}"
  done
}

# --- launch / restore / stop / status ---------------------------------------------------------------------------------------
init_state() {  # init_state <attempt id> <cap> <keep retries: true|false>
  local prior=null
  [[ -f "$STATE_F" ]] && prior="$(jq -c '.' "$STATE_F")"
  jq -n --argjson prior "$prior" --arg aid "$1" --argjson cap "$2" --argjson keep "$3" --arg b "$(boot_id)" \
    --arg at "$(now_iso)" --argjson ep "$(date +%s)" '
    {schema_version: 1, state: "launching", owner_pid: null, boot_id: $b, start_time: null, start_ticks: null,
     unit: null, mode: null, attempt_id: $aid, runner_pid: null, runner_start_ticks: null, cap: $cap,
     retries: (if $keep then ($prior.retries // []) else [] end),
     history: (($prior.history // []) + (if $keep or $prior == null then [] else [$prior | del(.history)] end)),
     last_exit: null, stopped: null, pending_resume: null, launched_at: $at, launched_epoch: $ep}' > "$STATE_F.tmp"
  mv "$STATE_F.tmp" "$STATE_F"
}
opts() {  # opts <args…> → MAXR, MODE, RUNNER_OPT, REST
  MAXR=3 MODE="${LOA_SUPERVISOR_MODE:-auto}" RUNNER_OPT="" REST=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-retries) MAXR="${2:-}"; shift 2 ;;
      --mode) MODE="${2:-}"; shift 2 ;;
      --runner) RUNNER_OPT="${2:-}"; shift 2 ;;
      --) shift; REST=("$@"); break ;;
      *) die "unknown option $1" ;;
    esac
  done
  [[ "$MAXR" =~ ^[0-9]$ ]] || die "--max-retries must be 0-9"
  MODE="$(pick_mode "$MODE")"
}

cmd_launch() {
  opts "$@"
  [[ -n "$RUNNER_OPT" && -x "$RUNNER_OPT" ]] || die "launch needs --runner <executable>"
  [[ -d "$(dirname "$B")" ]] || die "no directory $(dirname "$B")"
  linger_ok
  mkdir -p "$SUPD"
  take_lock
  local aid; aid="$(new_attempt_id)"
  RARGS=(${REST[@]+"${REST[@]}"})
  jq -n --arg r "$RUNNER_OPT" --argjson m "$MAXR" --arg b "$(basename "$B")" \
    --argjson a "$(printf '%s\0' ${REST[@]+"${REST[@]}"} | jq -R -s -c 'split("\u0000")[:-1]')" \
    '{schema_version: 1, runner: $r, args: $a, max_retries: $m, batch: $b}' > "$ARGS_F.tmp"
  mv "$ARGS_F.tmp" "$ARGS_F"
  local prior_state=none rb="" rp="" rt=""
  if [[ -f "$STATE_F" ]]; then prior_state="$(sget .state)" rb="$(sget '.boot_id // ""')" rp="$(sget '.runner_pid // ""')" rt="$(sget '.runner_start_ticks // ""')"; fi
  init_state "$aid" "$MAXR" false
  if [[ "$prior_state" == running ]]; then   # an earlier episode died uncleanly: reclaim before the runner refuses
    local g; g="$(reclaim "$rb" "$rp" "$rt")"; stop_containers >/dev/null
    log "launch: took over from an unfinished episode (groups terminated: ${g//$'\n'/ })"
  fi
  daemonise "$MODE" "$aid"
}

cmd_restore() {
  opts "$@"
  [[ -f "$STATE_F" ]] || refuse "$B has no supervisor record to restore"
  linger_ok
  take_lock
  local st rb rp rt cls cap n aid unc groups entry
  st="$(sget .state)"
  [[ "$st" == running || "$st" == launching ]] || refuse "the supervisor record of $B is $st, not running; launch with --resume instead"
  load_args
  cap="$(sget .cap)"; [[ "${MAXR_GIVEN:-}" == "" ]] || cap="$MAXR"
  n="$(sget '.retries | length')"
  (( n < cap )) || refuse "the retry cap $cap is reached ($n retries); restore --max-retries N with a larger N"
  rb="$(sget '.boot_id // ""')" rp="$(sget '.runner_pid // ""')" rt="$(sget '.runner_start_ticks // ""')"
  if [[ "$rb" != "$(boot_id)" ]]; then cls=reboot
  elif ident_alive "$rp" "$rt" "$rb"; then cls=supervisor_lost
  else cls=driver_lost; fi
  if [[ "$rb" == "$(boot_id)" && -f "$B/.lock/pid" ]]; then
    local lp; lp="$(cat "$B/.lock/pid")"
    if [[ "$lp" =~ ^[0-9]+$ && "$lp" != "$rp" ]] && kill -0 "$lp" 2>/dev/null && tr '\0' ' ' < "/proc/$lp/cmdline" 2>/dev/null | grep -q 'run-ablation.sh'; then
      refuse "batch $B is driven by an unsupervised run-ablation.sh (pid $lp); stop it or let it finish"
    fi
  fi
  unc="$(uncertain_runs)"
  groups="$(reclaim "$rb" "$rp" "$rt")"
  entry="$(reconcile "$cls" "$unc" "$groups")"
  aid="$(new_attempt_id)"
  init_state "$aid" "$cap" true
  resume_argv
  sset '.retries += [$e + {retry_id: ($aid + "-r" + ((.retries | length) + 1 | tostring)), resume_args: $a}] | .pending_resume = $a' \
    --argjson e "$entry" --arg aid "$aid" --argjson a "$(printf '%s\0' "${RESUME_ARGV[@]}" | jq -R -s -c 'split("\u0000")[:-1]')"
  log "restore ($cls): ${RESUME_ARGV[*]}"
  daemonise "$MODE" "$aid"
}

cmd_stop() {
  [[ -f "$STATE_F" ]] || refuse "$B has no supervisor record"
  printf '%s\n' "$(now_iso)" > "$SUPD/stop"
  local p t b; p="$(sget '.owner_pid // ""')" t="$(sget '.start_ticks // ""')" b="$(sget '.boot_id // ""')"
  if ident_alive "$p" "$t" "$b"; then kill -TERM "$p" 2>/dev/null || true; echo "stop requested: supervisor pid $p"
  else echo "stop requested: no live supervisor of $B (the record is $(sget .state))"; fi
}

cmd_record_job() {  # record-job <jobs-dir> <name> <pgid> [fields…] (header: record-job)
  [[ $# -ge 3 ]] || die "usage: batch-supervisor.sh record-job <jobs-dir> <name> <pgid> [fields…]"
  local d="$1" n="$2" p="$3" id
  shift 3
  [[ -d "$d" ]] || die "record-job: no directory $d"
  [[ "$n" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || die "record-job: the name must be [A-Za-z0-9_.-] ($n)"
  [[ "$p" =~ ^[1-9][0-9]*$ ]] || die "record-job: the pgid must be a positive integer ($p)"
  if id="$(job_ident_settled "$p" "$PPID")" && printf '%s\n' "$id" > "$d/$n.ident.tmp" 2>/dev/null && mv -f "$d/$n.ident.tmp" "$d/$n.ident"; then :
  else
    rm -f "$d/$n.ident.tmp" "$d/$n.ident" 2>/dev/null || true
    # a leader that already exited needs no identity (nothing to reclaim): silent; a live one is named
    leader_live "$p" && echo "batch-supervisor: WARN record-job: no identity for the live process group $p (not settled within 5 s, or $d/$n.ident unwritable): $d/$n.pgid is written without .ident, so reclaim treats it as stale and never signals it" >&2
  fi
  if { printf '%s' "$p"; [[ $# -eq 0 ]] || printf ' %s' "$@"; printf '\n'; } > "$d/$n.pgid.tmp" 2>/dev/null && mv -f "$d/$n.pgid.tmp" "$d/$n.pgid"; then
    return 0
  fi
  rm -f "$d/$n.pgid.tmp" 2>/dev/null || true
  echo "batch-supervisor: record-job: writing $d/$n.pgid failed" >&2
  exit 1
}

if [[ "${1:-}" == record-job ]]; then shift; cmd_record_job "$@"; exit 0; fi
cmd="${1:-}"; [[ $# -ge 2 ]] || die "usage: batch-supervisor.sh launch|restore|stop|status|run <batch-dir> [options] (see the header)"
paths "$2"; shift 2
MAXR_GIVEN=""; for a in "$@"; do [[ "$a" == --max-retries ]] && MAXR_GIVEN=1; [[ "$a" == -- ]] && break; done
case "$cmd" in
  launch) cmd_launch "$@" ;;
  restore) cmd_restore "$@" ;;
  run) cmd_run "$@" ;;
  stop) cmd_stop ;;
  status) [[ -f "$STATE_F" ]] || refuse "$B has no supervisor record"; jq '.' "$STATE_F" ;;
  *) die "unknown command '$cmd' (launch | restore | stop | status | run | record-job)" ;;
esac
