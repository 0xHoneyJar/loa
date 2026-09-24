#!/usr/bin/env bash
# =============================================================================
# run-preflight.sh — can this run finish? One checklist before `/run`,
# `/run sprint-plan`, `run-bridge` and `/run-resume` (cycle-125 FR-3, SDD D-3.1)
#
#   run-preflight.sh [--unattended] [--resume] [--json] [--root DIR]
#
# Predicates (each PASS / WARN / FAIL with a one-line fix):
#   P1 permissions.defaultMode — effective value across
#      .claude/settings.local.json > .claude/settings.json > ~/.claude/settings.json.
#      bypassPermissions passes; acceptEdits/default pass when P2 confirms the
#      run's allow rules (an unattended run cannot answer prompts — the fences
#      are the guard); plan fails; auto fails ("prompts unavailable → auto-denied").
#      Interactive mode downgrades P1 failures to WARN.
#   P2 tool allow rules — check-permissions.sh --quiet (pass-through; it reads
#      ~/.claude/settings.json, .claude/settings.json and .claude/settings.local.json
#      and lets a deny rule in any layer win — sprint-bug-246).
#   P3 voices — for flatline_protocol.{code_review,security_audit}: model +
#      fallback_chain → provider (catalog alias in .claude/defaults/model-config.yaml,
#      else by name) → a credential is PRESENT in the environment / .env.local /
#      .env (never printed) or the CLI hop binary is on PATH (claude, codex, agy).
#      A stage with NO usable voice fails; each missing voice warns.
#   P4 breakers — .run/circuit-breaker-<provider>-<auth>.json: OPEN for a
#      stage's only usable provider fails; any other OPEN warns with its age.
#   P5 NOTES size — notes-guard.sh check: exit 3 fails (rotate hint), WARN warns.
#   P6 run state — .run/state.json, sprint-plan-state.json, simstim-state.json:
#      RUNNING fresh = "already in progress" (fail); RUNNING/INTERRUPTED older
#      than 12 h or HALTED = fail with the resume command; JACKED_OUT/absent pass.
#      --resume inverts P6: a resumable state passes, nothing to resume fails.
#   P7 beads — beads-health.sh --quick --json: HEALTHY pass, DEGRADED warn,
#      else fail unless beads.autonomous.requires_beads=false or
#      LOA_BEADS_AUTONOMOUS_OVERRIDE=true (then warn).
#   P8 branch — run-mode-ice.sh validate (pass-through).
#
# Output: `[PASS|WARN|FAIL] Pn <name>: <detail> → fix: <fix>` per predicate, then
# `run-preflight (<mode>): N pass, N warn, N fail`. --json: one object
# {mode, ok, pass, warn, fail, checks:[{id,name,status,detail,fix}], ts}.
# Exit: 0 no FAIL · 1 any FAIL · 2 usage. Reads settings, env and state only;
# writes nothing; no network; never prints a credential value.
# Test seam (bats-gated): LOA_PREFLIGHT_HELPERS_DIR overrides the directory of
# the composed helper scripts so fixtures can drive P2/P7/P8.
# =============================================================================
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="interactive"; RESUME=0; JSON=0; ROOT=""
usage() { sed -n '3,/^# Output:/p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --unattended) MODE="unattended"; shift ;;
    --resume) RESUME=1; shift ;;
    --json) JSON=1; shift ;;
    --root) [[ $# -ge 2 && -d "${2:-}" ]] || usage; ROOT="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done
[[ -n "$ROOT" ]] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[[ -d "$ROOT" ]] || usage
STALE_SECS=$(( 12 * 3600 ))

helper() {  # $1 = relative helper path; bats-gated stub dir first
  if [[ -n "${BATS_TEST_FILENAME:-}${BATS_VERSION:-}" && -n "${LOA_PREFLIGHT_HELPERS_DIR:-}" && -x "${LOA_PREFLIGHT_HELPERS_DIR}/$1" ]]; then
    echo "${LOA_PREFLIGHT_HELPERS_DIR}/$1"
  else
    echo "${SCRIPT_DIR}/$1"
  fi
}
# yq comes in two flavours (KF-027): Mike Farah's Go yq (`yq eval <expr> file`)
# and the Python jq-wrapper (`yq -r <expr> file`). Detect once; both read the
# same expressions used here (plain paths and `[]` iteration).
YQ_FLAVOUR=""
if command -v yq >/dev/null 2>&1; then
  if yq --version 2>&1 | grep -qi 'mikefarah\|version v4\|version 4'; then YQ_FLAVOUR="go"
  elif yq eval '.x' <<<'x: 1' >/dev/null 2>&1; then YQ_FLAVOUR="go"
  else YQ_FLAVOUR="py"; fi
fi
have_yq() { [[ -n "$YQ_FLAVOUR" ]]; }
yq_read() {  # $1 expr  $2 file → values, one per line ("" for null)
  if [[ "$YQ_FLAVOUR" == "go" ]]; then yq eval "$1" "$2" 2>/dev/null
  else yq -r "$1" "$2" 2>/dev/null; fi | sed 's/^null$//'
}
cfg() { have_yq && [[ -f "$ROOT/.loa.config.yaml" ]] && yq_read "$1" "$ROOT/.loa.config.yaml"; }
age_h() {  # $1 = ISO-8601 or epoch → "Nh" / "Nm" / "?"
  local t="$1" e now
  [[ -n "$t" && "$t" != "null" ]] || { echo "?"; return; }
  if [[ "$t" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then e="${t%.*}"; else e=$(date -u -d "$t" +%s 2>/dev/null || echo ""); fi
  [[ -n "$e" ]] || { echo "?"; return; }
  now=$(date +%s); local d=$(( now - e ))
  (( d < 0 )) && d=0
  if (( d >= 3600 )); then echo "$(( d / 3600 ))h"; else echo "$(( d / 60 ))m"; fi
}
age_s() { local t="$1" e; [[ "$t" =~ ^[0-9]+(\.[0-9]+)?$ ]] && e="${t%.*}" || e=$(date -u -d "$t" +%s 2>/dev/null || echo ""); [[ -n "$e" ]] && echo $(( $(date +%s) - e )) || echo -1; }

# --- results ------------------------------------------------------------------
IDS=(); NAMES=(); STATUSES=(); DETAILS=(); FIXES=()
record() { IDS+=("$1"); NAMES+=("$2"); STATUSES+=("$3"); DETAILS+=("$4"); FIXES+=("${5:-}"); }
status_of() { local i; for i in "${!IDS[@]}"; do [[ "${IDS[$i]}" == "$1" ]] && { echo "${STATUSES[$i]}"; return; }; done; echo ""; }

# --- P2 allow rules (evaluated first: P1 depends on it) ------------------------
p2_status="FAIL"; p2_detail=""
cp="$(helper check-permissions.sh)"
if [[ -x "$cp" ]]; then
  if "$cp" --quiet >/dev/null 2>&1; then p2_status="PASS"; p2_detail="run-mode allow rules effective across ~/.claude/settings.json, .claude/settings.json, .claude/settings.local.json (deny wins) ($(basename "$(dirname "$cp")" 2>/dev/null | grep -q helpers && echo stub || echo check-permissions.sh))"
  else p2_detail="run-mode allow rules missing"; fi
else
  p2_detail="check-permissions.sh not found"
fi

# --- P1 defaultMode --------------------------------------------------------------
p1_val=""; p1_src=""
for f in "$ROOT/.claude/settings.local.json" "$ROOT/.claude/settings.json" "$HOME/.claude/settings.json"; do
  [[ -f "$f" ]] || continue
  v=$(jq -r '.permissions.defaultMode // empty' "$f" 2>/dev/null || true)
  if [[ -n "$v" ]]; then p1_val="$v"; case "$f" in "$HOME"/*) p1_src="home ~/.claude/settings.json" ;; *) p1_src="${f#$ROOT/}" ;; esac; break; fi
done
p1_fix="set permissions.defaultMode to bypassPermissions in .claude/settings.local.json for unattended runs, or keep acceptEdits/default and add the run-mode allow rules (P2)"
case "$p1_val" in
  bypassPermissions) record P1 permissions PASS "defaultMode = bypassPermissions ($p1_src)" "" ;;
  plan) if [[ $MODE == unattended ]]; then record P1 permissions FAIL "defaultMode = plan ($p1_src): every write is refused" "$p1_fix"; else record P1 permissions WARN "defaultMode = plan ($p1_src): writes refused until changed" "$p1_fix"; fi ;;
  auto) if [[ $MODE == unattended ]]; then record P1 permissions FAIL "defaultMode = auto ($p1_src): prompts unavailable → auto-denied in an unattended session" "$p1_fix"; else record P1 permissions WARN "defaultMode = auto ($p1_src): unattended sessions get auto-denied prompts" "$p1_fix"; fi ;;
  acceptEdits|default|"")
    label="${p1_val:-unset}"; src="${p1_src:-no settings file defines it}"
    if [[ $p2_status == PASS ]]; then record P1 permissions PASS "defaultMode = $label ($src); allow rules cover the run (P2)" ""
    elif [[ $MODE == unattended ]]; then record P1 permissions FAIL "defaultMode = $label ($src) and the allow rules are missing: prompts cannot be answered unattended" "$p1_fix"
    else record P1 permissions WARN "defaultMode = $label ($src); allow rules missing (P2)" "$p1_fix"; fi ;;
  *) record P1 permissions WARN "defaultMode = $p1_val ($p1_src): unknown value" "$p1_fix" ;;
esac
record P2 allow-rules "$p2_status" "$p2_detail" "run .claude/scripts/check-permissions.sh; add the listed Bash(...) allow rules to .claude/settings.local.json (machine-local) or .claude/settings.json (shared), and remove any deny rule that covers them (~/.claude/settings.json, .claude/settings*.json — deny wins)"

# --- P3 voices ------------------------------------------------------------------
cred_present() {  # $1 = provider → 0 if a credential is present (env / .env.local / .env) — value never read out
  local -a vars
  case "$1" in
    openai) vars=(OPENAI_API_KEY) ;;
    anthropic) vars=(ANTHROPIC_API_KEY) ;;
    google) vars=(GOOGLE_API_KEY GEMINI_API_KEY) ;;
    *) return 1 ;;
  esac
  local v f val
  for v in "${vars[@]}"; do [[ -n "${!v:-}" ]] && return 0; done
  for f in "$ROOT/.env.local" "$ROOT/.env"; do
    [[ -f "$f" ]] || continue
    for v in "${vars[@]}"; do
      # presence = a non-empty value after stripping one layer of quotes; the value itself never leaves this function
      val=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${v}=" "$f" 2>/dev/null | tail -1 | sed -e 's/^[^=]*=//' -e "s/^[\"']//" -e "s/[\"'][[:space:]]*$//" -e 's/[[:space:]]*#.*$//')
      [[ -n "$val" ]] && return 0
    done
  done
  return 1
}
cli_for() { case "$1" in claude-headless) echo claude ;; codex-headless) echo codex ;; gemini-headless) echo agy ;; *) echo "" ;; esac; }
provider_of() {  # $1 = model id → openai|anthropic|google|""
  local id="$1" alias="" cat=""
  # Only catalog-shaped ids reach the yq expression (config text is operator-owned but is still input).
  [[ "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._:/-]*$ ]] || { echo ""; return; }
  if [[ -f "$ROOT/.claude/defaults/model-config.yaml" ]]; then cat="$ROOT/.claude/defaults/model-config.yaml"
  elif [[ -f "$SCRIPT_DIR/../defaults/model-config.yaml" ]]; then cat="$SCRIPT_DIR/../defaults/model-config.yaml"; fi
  if have_yq && [[ -n "$cat" ]]; then alias=$(yq_read ".aliases.\"$id\"" "$cat" | head -1); fi
  [[ "$alias" == *:* ]] && { echo "${alias%%:*}"; return; }
  case "$id" in
    openai:*|anthropic:*|google:*) echo "${id%%:*}" ;;
    gpt*|o[0-9]*|codex*) echo openai ;;
    claude*) echo anthropic ;;
    gemini*) echo google ;;
    *) echo "" ;;
  esac
}
declare -A USABLE_PROVIDERS=()   # providers that have a usable voice in any stage
declare -A STAGE_ONLY=()         # stage → the single usable provider (for P4)
p3_status="PASS"; p3_detail=""; p3_fail_stages=""; p3_warn=""; p3_usable=""
if ! have_yq || [[ ! -f "$ROOT/.loa.config.yaml" ]]; then
  p3_status="WARN"; p3_detail="yq or .loa.config.yaml missing: voices unchecked"
else
  for stage in code_review security_audit; do
    en=$(cfg ".flatline_protocol.$stage.enabled"); [[ "$en" == "true" ]] || continue
    models=$(cfg ".flatline_protocol.$stage.model"); chain=$(cfg ".flatline_protocol.$stage.fallback_chain[]" | tr '\n' ' ')
    usable=0; missing=""; provs=""; usable_names=""
    for m in $models $chain; do
      prov=$(provider_of "$m"); cli=$(cli_for "$m"); ok=0
      if [[ -n "$cli" ]] && command -v "$cli" >/dev/null 2>&1; then ok=1
      elif [[ -z "$cli" && -n "$prov" ]] && cred_present "$prov"; then ok=1; fi
      if (( ok )); then usable=$((usable + 1)); USABLE_PROVIDERS["${prov:-$m}"]=1; provs+="${prov:-$m} "; usable_names+="$m${cli:+(cli $cli)} "
      else missing+="$m${cli:+(cli $cli)} "; fi
    done
    provs_u=$(printf '%s\n' $provs | sort -u | tr '\n' ' ')
    if (( usable == 0 )); then p3_fail_stages+="$stage "
    else
      [[ $(printf '%s\n' $provs | sort -u | wc -l) -eq 1 ]] && STAGE_ONLY["$stage"]="${provs_u% }"
      p3_usable+="$stage usable: ${usable_names% }; "
      [[ -n "$missing" ]] && p3_warn+="$stage missing: ${missing% }; "
    fi
  done
  if [[ -n "$p3_fail_stages" ]]; then p3_status="FAIL"; p3_detail="no usable voice for ${p3_fail_stages% }: no credential present and no CLI hop on PATH"
  elif [[ -n "$p3_warn" ]]; then p3_status="WARN"; p3_detail="${p3_usable}${p3_warn%; }"
  else p3_detail="every configured voice has a credential or CLI hop (${p3_usable%; })"; fi
fi
record P3 voices "$p3_status" "$p3_detail" "export OPENAI_API_KEY / ANTHROPIC_API_KEY / GOOGLE_API_KEY (or put them in .env.local), or install a CLI hop (claude, codex, agy) named in the stage's fallback_chain"

# --- P4 breakers ----------------------------------------------------------------
p4_status="PASS"; p4_detail="no OPEN provider breaker"; p4_open=""; p4_fail=""
for f in "$ROOT"/.run/circuit-breaker-*.json; do
  [[ -f "$f" && ! -L "$f" ]] || continue
  b=$(basename "$f" .json); b="${b#circuit-breaker-}"; prov="${b%%-*}"; auth="${b#*-}"; [[ "$auth" == "$b" ]] && auth="legacy"
  st=$(jq -r '.state // empty' "$f" 2>/dev/null || echo "unparseable"); [[ -n "$st" ]] || st="unknown"
  [[ "$st" == "OPEN" ]] || continue
  opened=$(jq -r '.opened_at // empty' "$f" 2>/dev/null || true)
  p4_open+="$prov/$auth OPEN $(age_h "$opened"); "
  for s in "${!STAGE_ONLY[@]}"; do [[ "${STAGE_ONLY[$s]}" == "$prov" ]] && p4_fail+="$prov (only usable voice of $s) "; done
done
if [[ -n "$p4_fail" ]]; then p4_status="FAIL"; p4_detail="breaker OPEN for ${p4_fail% }: ${p4_open%; }"
elif [[ -n "$p4_open" ]]; then p4_status="WARN"; p4_detail="OPEN breaker(s) will route around: ${p4_open%; }"; fi
record P4 breakers "$p4_status" "$p4_detail" "wait for reset_timeout_seconds, or cheval --reset-breaker <provider> after fixing the provider error"

# --- P5 NOTES size --------------------------------------------------------------
ng="$SCRIPT_DIR/notes-guard.sh"; notes="$ROOT/grimoires/loa/NOTES.md"
if [[ -f "$notes" && -f "$ng" ]]; then
  out=$(bash "$ng" check --file "$notes" 2>&1 >/dev/null); rc=$?
  sz=$(stat -c%s "$notes" 2>/dev/null || echo 0)
  if [[ $rc -eq 3 ]]; then record P5 notes-size FAIL "NOTES.md is $sz bytes (block line 204800): appends are refused" "bash .claude/scripts/notes-guard.sh rotate --file grimoires/loa/NOTES.md"
  elif [[ "$out" == *NOTES-WARN* ]]; then record P5 notes-size WARN "NOTES.md is $sz bytes (warn line 102400)" "run /compound or notes-guard.sh rotate before it reaches 204800"
  else record P5 notes-size PASS "NOTES.md is $sz bytes" ""; fi
else
  record P5 notes-size PASS "no NOTES.md yet" ""
fi

# --- P6 run state --------------------------------------------------------------
p6_items=""; p6_resumable=""; p6_inprogress=""; p6_bad=""
p6_read() {  # $1 file  $2 label  $3 jq for state  $4 jq for last activity
  local f="$1" label="$2" st ts
  [[ -f "$f" ]] || return 0
  if ! jq -e . "$f" >/dev/null 2>&1; then p6_bad+="$label unparseable; "; return 0; fi
  st=$(jq -r "$3 // empty" "$f" 2>/dev/null); ts=$(jq -r "$4 // empty" "$f" 2>/dev/null)
  [[ -n "$st" ]] || return 0
  local a; a=$(age_h "$ts"); local s; s=$(age_s "$ts")
  case "$st" in
    HALTED|INTERRUPTED) p6_resumable+="$label $st ($a ago); " ;;
    RUNNING)
      if [[ -n "$ts" && "$s" -ge 0 && "$s" -ge $STALE_SECS ]]; then p6_resumable+="$label RUNNING stale (last activity ${a} ago); "
      else p6_inprogress+="$label RUNNING (${a} ago); "; fi ;;
    *) p6_items+="$label $st; " ;;
  esac
}
p6_read "$ROOT/.run/sprint-plan-state.json" "sprint-plan-state.json" '.state' '.timestamps.last_activity'
p6_read "$ROOT/.run/state.json" "state.json" '.state' '.timestamps.last_activity // .updated_at'
p6_read "$ROOT/.run/simstim-state.json" "simstim-state.json" '.status // .state' '.updated_at // .timestamps.last_activity'
if (( RESUME )); then
  if [[ -n "$p6_bad" ]]; then record P6 run-state FAIL "${p6_bad%; }" "inspect the file under .run/ and remove or repair it"
  elif [[ -n "$p6_resumable$p6_inprogress" ]]; then record P6 run-state PASS "resumable: ${p6_resumable}${p6_inprogress}" ""
  else record P6 run-state FAIL "nothing to resume (no HALTED/INTERRUPTED/RUNNING state under .run/)" "start a new run: /run sprint-plan"; fi
else
  if [[ -n "$p6_bad" ]]; then record P6 run-state FAIL "${p6_bad%; }" "inspect the file under .run/ and remove or repair it"
  elif [[ -n "$p6_inprogress" ]]; then record P6 run-state FAIL "run already in progress: ${p6_inprogress%; }" "/run-status to inspect; /run-halt to stop it; /run-resume continues it"
  elif [[ -n "$p6_resumable" ]]; then record P6 run-state FAIL "${p6_resumable%; }" "/run-resume (or /run-halt --force then rm -rf .run/ to abandon)"
  else record P6 run-state PASS "no active run${p6_items:+ (${p6_items%; })}" ""; fi
fi

# --- P7 beads --------------------------------------------------------------------
bh="$(helper beads/beads-health.sh)"
bstatus="MISSING"
if [[ -x "$bh" ]]; then
  # Health scripts exit non-zero BY DESIGN for DEGRADED (4) and worse: capture
  # the JSON first, then read it — never `cmd | jq || echo fallback` under
  # pipefail (the live smoke test produced "DEGRADED\nUNKNOWN" that way).
  bh_out=$(cd "$ROOT" && "$bh" --quick --json 2>/dev/null) || true
  bstatus=$(printf '%s' "$bh_out" | jq -r '.status // "UNKNOWN"' 2>/dev/null | head -1)
  [[ -n "$bstatus" ]] || bstatus="UNKNOWN"
fi
req=$(cfg '.beads.autonomous.requires_beads'); [[ -n "$req" ]] || req="true"
case "$bstatus" in
  HEALTHY) record P7 beads PASS "beads HEALTHY" "" ;;
  DEGRADED) record P7 beads WARN "beads DEGRADED (br sync --status)" "br sync --flush-only / see beads-health.sh --json" ;;
  *) if [[ "$req" == "false" || "${LOA_BEADS_AUTONOMOUS_OVERRIDE:-}" == "true" ]]; then record P7 beads WARN "beads $bstatus but requires_beads is off / override set" "cargo install beads_rust && br init"
     else record P7 beads FAIL "beads $bstatus: autonomous mode requires beads" "cargo install beads_rust && br init (override: beads.autonomous.requires_beads: false or LOA_BEADS_AUTONOMOUS_OVERRIDE=true)"; fi ;;
esac

# --- P8 branch --------------------------------------------------------------------
ice="$(helper run-mode-ice.sh)"
if [[ -x "$ice" ]]; then
  msg=$(cd "$ROOT" && "$ice" validate 2>&1); rc=$?
  msg=$(printf '%s' "$msg" | tr '\n' ' ' | cut -c1-160)
  if [[ $rc -eq 0 ]]; then record P8 branch PASS "${msg:-branch ok}" ""; else record P8 branch FAIL "${msg:-protected branch}" "checkout a feature branch (git checkout -b feature/<name>)"; fi
else
  record P8 branch FAIL "run-mode-ice.sh not found" "restore .claude/scripts/run-mode-ice.sh"
fi

# --- output ----------------------------------------------------------------------
npass=0; nwarn=0; nfail=0
for s in "${STATUSES[@]}"; do case "$s" in PASS) npass=$((npass+1));; WARN) nwarn=$((nwarn+1));; FAIL) nfail=$((nfail+1));; esac; done
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if (( JSON )); then
  {
    for i in "${!IDS[@]}"; do
      jq -cn --arg id "${IDS[$i]}" --arg name "${NAMES[$i]}" --arg st "${STATUSES[$i]}" --arg d "${DETAILS[$i]}" --arg fx "${FIXES[$i]}" \
        '{id:$id, name:$name, status:$st, detail:$d, fix:$fx}'
    done
  } | jq -s --arg mode "$MODE" --argjson p "$npass" --argjson w "$nwarn" --argjson f "$nfail" --arg ts "$ts" \
      '{mode:$mode, ok:($f==0), pass:$p, warn:$w, fail:$f, checks:., ts:$ts}'
else
  for i in "${!IDS[@]}"; do
    line="[${STATUSES[$i]}] ${IDS[$i]} ${NAMES[$i]}: ${DETAILS[$i]}"
    [[ "${STATUSES[$i]}" != "PASS" && -n "${FIXES[$i]}" ]] && line+=" → fix: ${FIXES[$i]}"
    echo "$line"
  done
  echo "run-preflight ($MODE): $npass pass, $nwarn warn, $nfail fail"
fi
(( nfail == 0 )) && exit 0 || exit 1
