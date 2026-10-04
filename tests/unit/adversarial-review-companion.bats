#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-companion.bats — cycle-126 Sprint 2 (PRD FR-2.1,
# SDD D-2.1). The companion voice: a dissent plans TWO chains from different
# provider families, walks them, aggregates both envelopes (voices_planned 2),
# records the companion's completion-based status and failure class, and can
# be switched off per block (`companion_voice: false`).
#
# Whole-run harness: main() is sourced and run with `invoke_dissenter` replaced
# by a stub keyed on the model (canned adapter envelopes + a valid single-voice
# verdict_quality sidecar), a temp .loa.config.yaml, and no credentials present
# (a keyless host: the Anthropic companion chain is `claude-headless` only).
# =============================================================================

_scrub_cred_aliases() {  # unset every credential alias the probe recognises, from the script's own table; a missing or empty table fails setup rather than scrubbing nothing (twenty-fifth run, c2e DISS-C-002)
    local p v
    local -a names=() row
    declare -F _adv_cred_aliases >/dev/null || { echo "setup: _adv_cred_aliases is not loaded — the credential scrub would be a no-op" >&2; return 1; }
    for p in anthropic openai google; do
        read -ra row <<<"$(_adv_cred_aliases "$p")"
        [ "${#row[@]}" -gt 0 ] || { echo "setup: _adv_cred_aliases printed no alias for $p — the credential scrub would miss it" >&2; return 1; }
        names+=("${row[@]}")
    done
    for v in "${names[@]}"; do unset "$v"; done
}

_claim_sprint_dir() {  # <dir> → 0 when nothing stands there or a leftover this suite MARKED was emptied and removed; 1 (named,
    # SPRINT cleared so teardown touches nothing) when an unmarked node stands there — thirty-fourth run, c1a DISS-C-001: a crashed
    # run on a reused pid left this very path, setup's marker claimed it, and the stale sweep, seeing a live owner, never cleared it
    local d="$1"
    [[ -e "$d" || -L "$d" ]] || return 0
    # (thirty-fifth run, c1a DISS-C-001: a marker written on another host or pid namespace is never ours — as the sweep judges it;
    # DISS-C-002: a leftover that cannot be cleared is a named failure, never a claimed, still-populated directory)
    if [[ -d "$d" && ! -L "$d" && -f "${d%/*}/.$SPRINT.owner" ]] && ! _sweep_foreign "${d%/*}/.$SPRINT.owner"; then
        find "$d" -mindepth 1 -delete && rmdir "$d" && return 0
        echo "setup: could not clear $d"; SPRINT=""; return 1
    fi
    echo "setup: $d stands and is not this suite's"; SPRINT=""; return 1
}
setup() {
    # the sprint id and its directory come FIRST: teardown runs on any setup failure, and a delete
    # target derived from an unset id would be the a2a root (fourth run, chunk c C-001)
    SPRINT="sprint-comp-$$"
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    OUT_DIR="$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT"
    _claim_sprint_dir "$OUT_DIR" || return 1
    mkdir -p "${OUT_DIR%/*}" && _sweep_where > "${OUT_DIR%/*}/.$SPRINT.owner"   # this suite's own: the stale sweep deletes only marked dirs
    T="${BATS_TEST_TMPDIR:-}"; CMP_OWN_TMP=""
    if [[ -z "$T" ]]; then T="$(mktemp -d)"; CMP_OWN_TMP="$T"; fi   # bats < 1.4: our own directory, removed in teardown (sixteenth run, c2a C-003)
    # the two ledgers the script appends to are the TEST's, by construction (sixteenth run, c1b C-002: KF-033 is this suite
    # family polluting .run/model-invoke.jsonl — the append-only signed chain is never a test's scratch file)
    export LOA_MODELINV_LOG_PATH="$T/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$T/cost-ledger.jsonl"
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    # seventh run (chunk c1 C-002 / C-005): every test gets its own lock directory and none of the operator's
    # knobs — the suite runs in the same session that drives live dissents; cleared BEFORE the script is sourced, which reads
    # some at load (twenty-third run, c2a DISS-C-001: LOA_ADVERSARIAL_CLI_HOP_TIMEOUT → _ADV_CLI_HOP_TIMEOUT)
    export XDG_RUNTIME_DIR="$T"
    unset LOA_ADVERSARIAL_KEEP_WORKDIR LOA_ADVERSARIAL_RUN_TAG LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE \
          LOA_ADVERSARIAL_REPAIR_MODEL LOA_ADVERSARIAL_REAP_GRACE_SECONDS LOA_MODEL_CONFIG LOA_ADVERSARIAL_CLI_HOP_TIMEOUT \
          LOA_ADVERSARIAL_NO_FM_DERIVATION LOA_ADVERSARIAL_RUN_LOCK_GRACE_SECONDS LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS \
          _ADV_PGREP_BIN _ADV_FLOCK_BIN _ADV_REDACTOR_BIN   # (twenty-first run, c1a DISS-C-003: the knobs and seams added since the list was written)
    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    local _src; _src="$(sed 's/^\( *\)main "\$@"$/\1: main disabled for testing/' "$ADVERSARIAL_REVIEW")"   # (twenty-eighth run, c2a DISS-C-001: the substitution is asserted)
    grep -q ': main disabled for testing' <<<"$_src" || { echo "setup: the main trailer sed matched nothing" >&2; return 1; }
    ! grep -Eq '^[[:space:]]*main "\$@"' <<<"$_src" || { echo "setup: a main \"\$@\" call survived the sed" >&2; return 1; }
    eval "$_src"
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT
    # keyless host: no env keys, an empty dotenv dir (bats-gated seam) — the unset list IS the probe's alias table, so the two
    # cannot drift (sixteenth run, c1a C-002)
    _scrub_cred_aliases || return 1
    export LOA_ADVERSARIAL_ENV_DIR="$T/env"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    # …and the premise is ASSERTED, not assumed (twelfth run, c1 C-003): a host that exports another alias the probe
    # knows fails here with a message, not in CMP-1 / CMP-11 with a planner-shaped red
    if _adv_cred_present anthropic || _adv_cred_present openai; then
        echo "this host exports a credential alias for anthropic or openai — the keyless-host suite cannot run here (unset it for the run; a hard failure, on purpose: a silently skipped suite would hide a planner regression)" >&2
        return 1
    fi
    HOLDER_PIDS=()   # out-of-band lock holders a test spawns; teardown kills them (c1 C-002)
    export LOA_ADVERSARIAL_CLI_PROBE=both   # both CLI hops "installed" unless a case says otherwise (C-007 seam)
    unset LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS
    # temp config: review enabled, primary gpt-5.5-pro with the OpenAI chain
    CONFIG_FILE="$T/loa.config.yaml"
    cat > "$CONFIG_FILE" <<'YAML'
flatline_protocol:
  code_review:
    enabled: true
    model: gpt-5.5-pro
    budget_cents: 200
    timeout_seconds: 30
    fallback_chain:
      - gpt-5.5
      - codex-headless
  security_audit:
    enabled: true
    model: gpt-5.5-pro
    budget_cents: 200
    timeout_seconds: 30
    fallback_chain:
      - codex-headless
YAML
    printf 'diff --git a/x.sh b/x.sh\n--- a/x.sh\n+++ b/x.sh\n@@ -1 +1 @@\n-a\n+b\n' > "$T/diff.patch"
    CALLS="$T/calls.log"; : > "$CALLS"
    # behaviour table: model → outcome (ok | walked:<hop> | auth | quota | timeout | malformed | unavailable).
    # `walked:<hop>` models cheval's INNER fallback chain (one invocation, one sidecar whose
    # succeeded id is the hop it landed on, the HTTP voice recorded as dropped) — the shape a
    # keyless host produces (sprint-247: final_model gpt-5.5-pro, voices_succeeded_ids [codex-headless]).
    declare -gA BEHAVIOUR=()
    _vq() {  # <voice> <ok|fail|walked> <reason|hop> <exit> → single-voice verdict_quality envelope JSON
        if [[ "$2" == "ok" ]]; then
            jq -nc --arg v "$1" '{status:"APPROVED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:1,voices_succeeded_ids:[$v],voices_dropped:[],chain_health:"ok",confidence_floor:"low",rationale:"stub",single_voice_call:true}'
        elif [[ "$2" == "mixed" ]]; then
            # cheval's inner walk dropped one voice AND answered with another — one envelope with both (a3 C-007)
            jq -nc --arg d "$3" --arg hop "$4" '{status:"DEGRADED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:2,voices_succeeded:1,voices_succeeded_ids:[$hop],voices_dropped:[{voice:$d,reason:"ProviderUnavailable",exit_code:1,blocker_risk:"unknown"}],chain_health:"degraded",confidence_floor:"low",rationale:"stub mixed inner walk",single_voice_call:false}'
        elif [[ "$2" == "walked" ]]; then
            # one voice that walked internally: INV-6 (dropped == planned − succeeded) keeps voices_dropped
            # empty; the walk shows as chain_health degraded, the succeeded id is the hop it landed on
            jq -nc --arg v "$1" --arg hop "$3" '{status:"DEGRADED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:1,voices_succeeded_ids:[$hop],voices_dropped:[],chain_health:"degraded",confidence_floor:"low",rationale:("stub inner walk from " + $v),single_voice_call:true}'
        else
            jq -nc --arg v "$1" --arg r "$3" --argjson e "$4" '{status:"FAILED",consensus_outcome:"consensus",truncation_waiver_applied:false,voices_planned:1,voices_succeeded:0,voices_succeeded_ids:[],voices_dropped:[{voice:$v,reason:$r,exit_code:$e,blocker_risk:"unknown"}],chain_health:"exhausted",confidence_floor:"low",rationale:"stub",single_voice_call:true}'
        fi
    }
    invoke_dissenter() {  # <sys> <user> <model> <timeout> <vq_sidecar> <type> [schema]
        local model="$3" sidecar="$5" sev="ADVISORY"
        [[ "${6:-review}" == "audit" ]] && sev="MEDIUM"   # each gate's own vocabulary — no reject/repair detour
        echo "$model" >> "$CALLS"
        local b="${BEHAVIOUR[$model]:-ok}"
        case "$b" in
            ok)
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                jq -nc --arg m "$model" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                return 0 ;;
            walked:*)
                local hop="${b#walked:}"
                echo "$hop" >> "$CALLS"
                [[ -n "$sidecar" ]] && _vq "$model" walked "$hop" > "$sidecar"
                jq -nc --arg m "$hop" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                return 0 ;;
            walkedmixed:*)   # <dropped>:<hop> — the inner walk dropped one voice and answered with another (a3 C-007)
                local _mx="${BEHAVIOUR[$model]#walkedmixed:}" _mxd _mxh; _mxd="${_mx%%:*}"; _mxh="${_mx#*:}"
                [[ -n "$sidecar" ]] && _vq "$model" mixed "$_mxd" "$_mxh" > "$sidecar"
                jq -nc --arg m "$_mxh" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                return 0 ;;
            malformed)
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                jq -nc '{content: "not json at all", tokens_input: 1, tokens_output: 1, cost_usd: 0.001, latency_ms: 1, schema_enforced: false}'
                return 0 ;;
            reject)   # a payload the normaliser cannot save (no severity) → the companion's own sidecar
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                jq -nc '{content: "{\"findings\":[{\"title\":\"no severity\",\"category\":\"other\",\"description\":\"Something fails.\"}]}", tokens_input: 5, tokens_output: 5, cost_usd: 0.001, latency_ms: 1, schema_enforced: false}'
                return 0 ;;
            stubborn) # a hop that ignores TERM (a CLI stuck under a usage limit): only KILL ends it
                bash -c 'trap "" TERM; exec -a "$0" sleep 300' "loa-cmp30-stubborn-$$"; return 0 ;;
            sleeper)  sleep 20 & echo "$!" > "$T/sleeper.pid"; wait "$!"; return 0 ;;   # a hop in flight for longer than any test waits (CMP-114)
            slow2)    sleep 2; [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"; jq -nc '{content: "{\"findings\":[]}", tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: false}'; return 0 ;;
            abort-shell)                   # the shell running main is ended at once (a session limit, an operator INT): the EXIT trap is all that runs (CMP-64)
                kill -TERM "${_ADV_RUN_LOCK_OWNER:-$BASHPID}" 2>/dev/null; sleep 5; exit 70 ;;
            unavailable-after-companion)   # a failure the primary sees only once the companion is GONE (bounded barrier: CMP-27) —
                                           # attributable: the seam must exist, and the barrier must have been met (sixteenth run, c1a C-001)
                [[ -n "${_ADV_COMPANION_PID:-}" ]] || { echo "stub: the companion pid seam is missing" >&2; : > "$T/marker-barrier-expired"; return 99; }
                local _i=0; while kill -0 "$_ADV_COMPANION_PID" 2>/dev/null && (( _i++ < 300 )); do sleep 0.1; done
                kill -0 "$_ADV_COMPANION_PID" 2>/dev/null && { echo "stub: the companion did not finish within the barrier" >&2; : > "$T/marker-barrier-expired"; return 99; }
                [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1 ;;
            unavailable-marker)            # a failure that leaves a marker the companion's stub waits for (CMP-33)
                : > "$T/marker-$model-failed"
                [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1 ;;
            await-primary-marker)          # answers only once the primary has failed its codex hop AND logged the skip of the shared
                                           # hop (bounded barriers on a marker and on the live stderr — never a sleep: CMP-33; twelfth run, c1 C-001)
                local _j=0; while [[ ! -e "$T/marker-codex-headless-failed" ]] && (( _j++ < 300 )); do sleep 0.1; done
                [[ -e "$T/marker-codex-headless-failed" ]] || { echo "stub: the primary never failed its codex hop within the barrier" >&2; : > "$T/marker-barrier-expired"; return 99; }
                _j=0; while ! grep -q "the primary waits for the companion to settle" "$T/stderr.log" 2>/dev/null && (( _j++ < 300 )); do sleep 0.1; done
                grep -q "the primary waits for the companion to settle" "$T/stderr.log" 2>/dev/null || { echo "stub: the primary never waited on the shared hop within the barrier" >&2; : > "$T/marker-barrier-expired"; return 99; }
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"; jq -nc '{content: "{\"findings\":[]}", tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: false}'; return 0 ;;
            slow)     # a hung hop with a PID-scoped process name, so the orphan probe cannot match anything else on the host (c C-001)
                # (twenty-fourth run, c1a DISS-C-002: CMP-14 tells a cap that fired first from a reaper regression — thirty-sixth run, c1a
                # DISS-C-001: the marker is written by the pid that becomes the hung sleep, so it proves that process existed)
                bash -c ': > "$1"; exec -a "$0" sleep 300' "loa-cmp14-hung-$$" "$T/marker-slow-spawned"   # only the reaper can end it (eighth run, c1 C-002)
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"; jq -nc '{content: "{\"findings\":[]}", tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: false}'; return 0 ;;
            errlog)   echo "boom: provider said no (token sk-ant-api03-SECRETSECRETSECRETSECRET1234)" >&2; return 1 ;;
            errquiet) # the shim's shape when cheval fails: banners only, the provider's line went to the MODELINV ledger —
                      # the row is written NOW (inside the companion's window), as cheval would (tenth run, c1 C-005)
                if [[ -n "${ERRQUIET_LEDGER_MESSAGE:-}" ]]; then
                    # the guard travels with the writer (twenty-second run, c1a DISS-C-002): a fabricated row lands only in this test's
                    # own ledger, never in the repository's signed chain (KF-033)
                    [[ -n "${LOA_MODELINV_LOG_PATH:-}" && "$LOA_MODELINV_LOG_PATH" == "$T"/* ]] || { echo "stub: LOA_MODELINV_LOG_PATH is not test-scoped — no row written" >&2; return 98; }
                    # (at cheval's own precision — microseconds; the companion's window opens at a sub-second lock stamp, so a
                    # whole-second row in the hop's first second sorts before it: round 1ab's regression, CMP-24)
                    local _rts; _rts=$(date -u +%Y-%m-%dT%H:%M:%S.%6NZ); [[ "$_rts" == *N* ]] && _rts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                    jq -nc --arg ts "$_rts" --arg msg "$ERRQUIET_LEDGER_MESSAGE" '{schema_version:"1.1.0", primitive_id:"MODELINV", event_type:"model.invoke.complete", ts_utc:$ts,
                        payload:{models_requested:["anthropic:claude-headless"], models_succeeded:[], calling_primitive:"adversarial-review",
                                 models_failed:[{model:"anthropic:claude-headless", provider:"anthropic", error_class:"FALLBACK_EXHAUSTED", message_redacted:$msg}]}}' >> "$LOA_MODELINV_LOG_PATH"
                fi
                echo "[model-adapter:shim] Model: $model → anthropic:$model, Phase: review" >&2
                echo "ERROR: model-invoke failed with exit code 1" >&2; return 1 ;;
            clitimeout)  # cheval's CLI-hop timeout as the live run reported it, followed by the shim's generic wrapper
                echo "[cheval] RETRIES_EXHAUSTED: Failed after 1 attempts: [cheval] PROVIDER_UNAVAILABLE: Provider 'anthropic' unavailable: claude -p timed out after 610s" >&2
                echo "ERROR: model-invoke failed with exit code 1" >&2; return 1 ;;
            auth)        [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 4 > "$sidecar"; return 4 ;;
            quota)       [[ -n "$sidecar" ]] && _vq "$model" fail RateLimited 6 > "$sidecar"; return 6 ;;
            timeout)     [[ -n "$sidecar" ]] && _vq "$model" fail Other 3 > "$sidecar"; return 3 ;;
            unavailable) [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1 ;;
            unavailable-companion-slow)  # the COMPANION's call to this model HANGS (a PID-scoped sleep the reaper ends); the primary's answers
                if [[ "$sidecar" == *vq-companion-* ]]; then bash -c 'exec -a "$0" sleep 300' "loa-cmp14-hung-$$"; [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1; fi
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                jq -nc --arg m "$model" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                return 0 ;;
            unavailable-companion-only)  # the COMPANION's call to this model fails; the primary's answers
                if [[ "$sidecar" == *vq-companion-* ]]; then [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1; fi
                [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                jq -nc --arg m "$model" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                return 0 ;;
            unavailable-primary-only)  # the PRIMARY's call to this model fails; the companion's (vq-companion sidecar) answers
                if [[ "$sidecar" == *vq-companion-* ]]; then
                    [[ -n "$sidecar" ]] && _vq "$model" ok > "$sidecar"
                    jq -nc --arg m "$model" --arg s "$sev" '{content: ("{\"findings\":[{\"id\":\"DISS-001\",\"severity\":\"" + $s + "\",\"category\":\"other\",\"description\":\"from " + $m + ".\",\"failure_mode\":\"fm\"}]}"), tokens_input: 100, tokens_output: 20, cost_usd: 0.0123, latency_ms: 5, schema_enforced: false}'
                    return 0
                fi
                [[ -n "$sidecar" ]] && _vq "$model" fail ProviderUnavailable 1 > "$sidecar"; return 1 ;;
            *)   # a value with no arm (a typo, a behaviour added before its arm) fails the test in teardown — it fell out of the
                 # case as an empty answer the script read as malformed (thirty-third run, c1a DISS-C-001)
                printf '%s\n' "$b" >> "$T/marker-unknown-behaviour"; echo "stub: no arm for BEHAVIOUR '$b'" >&2; return 99 ;;
        esac
    }
    export PYTHONPATH="$PROJECT_ROOT/.claude/adapters"
}

# A directory an earlier, killed run of this suite left behind never accumulates (twenty-second run, c2a C-002) — and only a
# directory this suite MARKED as its own is ever deleted: setup writes `<a2a>/.<prefix>-<pid>.owner`, so a real sprint that
# happens to be named <prefix>-<n> is never touched (twenty-fifth run, c1a DISS-C-001). An owner is dead only when no probe
# sees it — `kill -0` also fails with EPERM for a LIVE process of another uid (twenty-fourth run, c1a DISS-C-001). The
# rename claims a directory, so concurrent teardowns never race one delete (twenty-fourth run, c2a DISS-C-001); a `.reap-<q>`
# a dead sweeper left is finished here, and the marker goes with its owner's directory. A marker names ONE directory: a sibling
# <prefix>-<pid>-x is never this suite's (it makes none) and is never deleted (twenty-ninth run, c1a DISS-001).
_sweep_alive() {
    local e; e=$(LC_ALL=C; kill -0 "$1" 2>&1) && return 0   # (EPERM's text in the C locale — thirty-fifth run, c1a DISS-C-003)
    [[ "$e" == *"not permitted"* ]] || ps -p "$1" >/dev/null 2>&1 || [[ -d "/proc/$1" ]]
}
# (thirty-fourth run, c2a DISS-C-001: a pid means nothing on another host or in another pid namespace — two runs over one
# checkout from a devcontainer and its host — so a marker records where it was written, and only a marker written HERE is
# judged; and kill -0's EPERM is a live process of another uid even when hidepid keeps ps and /proc from seeing it)
_sweep_where() { printf 'where %s %s\n' "$(uname -n 2>/dev/null)" "$(readlink /proc/self/ns/pid 2>/dev/null)"; }
_sweep_foreign() {  # <marker> → 0 when it records a where line that is not this one
    local w; w=$(grep -m1 '^where ' -- "$1" 2>/dev/null) || return 1
    [[ "$w" != "$(_sweep_where)" ]]
}
_sweep_stale_suite_dirs() {  # <a2a dir> <prefix>
    local a2a="$1" pre="$2" m p d q left
    for m in "$a2a"/."$pre"-[0-9]*.owner; do
        [[ -f "$m" && ! -L "$m" ]] || continue
        p=${m##*/."$pre"-}; p=${p%.owner}
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        _sweep_foreign "$m" && continue
        _sweep_alive "$p" && continue
        left=0
        for d in "$a2a/$pre-$p" "$a2a/$pre-$p".reap-*; do
            [[ -e "$d" || -L "$d" ]] || continue
            [[ -d "$d" && ! -L "$d" ]] || { left=1; continue; }
            if [[ "$d" == *.reap-* ]]; then
                q=${d##*.reap-}
                if [[ ! "$q" =~ ^[0-9]+$ ]] || { [[ "$q" != "$$" ]] && _sweep_alive "$q"; }; then left=1; continue; fi
            else
                mv -- "$d" "$d.reap-$$" 2>/dev/null || { left=1; continue; }
                d="$d.reap-$$"
            fi
            find "$d" -mindepth 1 -delete 2>/dev/null || true
            rmdir "$d" 2>/dev/null || left=1
        done
        (( left )) || rm -f -- "$m"
    done
    return 0
}
teardown() {
    local d
    # (thirty-sixth run, c1b DISS-C-001: a test's stand-in for a command outlives its body — bats runs teardown in the same shell — so
    # none reaches the sweep below; CMP-236 lints that every command a test defines is named here)
    unset -f cat cp date git kill mkdir mv ps sha256sum shasum sort yq 2>/dev/null || true
    # a PID-scoped stub the reaper under test failed to end never outlives the test (seventh run, c1 C-007)
    pkill -KILL -f "loa-cmp(14|30)-[a-z]+-$$"'( |$)' 2>/dev/null || true   # (anchored: pid 1234 never matches a sibling's 12345 — twentieth run, c1a DISS-C-001)
    # an out-of-band lock holder a failed assertion left behind (twelfth run, c1 C-002)
    _end_holders
    local _unk=""; [[ -s "$T/marker-unknown-behaviour" ]] && _unk=$(sort -u "$T/marker-unknown-behaviour" | tr '\n' ' ')
    if [[ -n "${CMP_OWN_TMP:-}" && -d "$CMP_OWN_TMP" && "$(basename "$CMP_OWN_TMP")" == tmp.* ]]; then find "$CMP_OWN_TMP" -mindepth 1 -delete; rmdir "$CMP_OWN_TMP"; fi
    [[ -n "${SPRINT:-}" && -n "${OUT_DIR:-}" && "$OUT_DIR" == */grimoires/loa/a2a/sprint-comp-* ]] || { _unknown_behaviour_said "$_unk"; return; }
    _sweep_stale_suite_dirs "${OUT_DIR%/*}" sprint-comp
    # this test's directory only — never a sibling it did not make (twenty-ninth run, c1a DISS-001)
    if [[ -d "$OUT_DIR" && ! -L "$OUT_DIR" ]]; then find "$OUT_DIR" -mindepth 1 -delete; rmdir "$OUT_DIR"; fi   # (never a link: the sweep's rule — twenty-seventh run, c2a DISS-C-002)
    rm -f -- "${OUT_DIR%/*}/.$SPRINT.owner"
    # a workdir a failing CMP-16 kept (LOA_ADVERSARIAL_KEEP_WORKDIR=1) holds the raw diagnostic line — it never
    # outlives the test (eleventh run, c1 C-003)
    for d in "${TMPDIR:-/tmp}"/adversarial-"$SPRINT"-*; do
        [[ "$d" == */adversarial-sprint-comp-* && -d "$d" && ! -L "$d" ]] || continue   # (never a link — twenty-eighth run, c1a DISS-C-001)
        find "$d" -mindepth 1 -delete; rmdir "$d"
    done
    _unknown_behaviour_said "$_unk"
}
_unknown_behaviour_said() {  # <values> — the teardown verdict on a BEHAVIOUR the stub has no arm for (CMP-206)
    [[ -z "$1" ]] || { echo "the stub has no arm for BEHAVIOUR value(s): $1" >&2; return 1; }
}
# a holder a failed assertion left behind ends — a stopped one too: a TERM to a SIGSTOPped process stays pending until a CONT
# (twenty-fifth run, c1b DISS-C-003)
_end_holders() {
    local p; for p in ${HOLDER_PIDS[@]+"${HOLDER_PIDS[@]}"}; do kill "$p" 2>/dev/null || true; kill -CONT "$p" 2>/dev/null || true; done
}
# <seconds> <cmd…>: run a probe as a job and end it at the bound — a hang is a fast red (rc 199, named), never a stalled suite
# (twenty-fifth run, c1b DISS-C-001)
_cmp_bounded() {
    local s="$1" pid i rc=0; shift
    "$@" 3>&- & pid=$!
    for (( i = 0; i < s * 10; i++ )); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$pid" 2>/dev/null; then
        # the whole tree, collected before any signal (twenty-sixth run, c1a DISS-C-002: pkill -P reached children only)
        local -a tree=(); mapfile -t tree < <(_adv_tree_pids "$pid")
        kill -KILL ${tree[@]+"${tree[@]}"} "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true   # (an empty tree is set -u safe below bash 4.4 — twenty-ninth run, c1a DISS-C-002)
        echo "still running after ${s} s: $*" >&2; return 199
    fi
    wait "$pid" || rc=$?
    return "$rc"
}
_now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }   # (macOS date has no %N)
# a --diff-range base this checkout resolves: `main` when the local branch exists, else HEAD — a PR checkout (a detached merge
# ref, depth 1) or a fork whose default branch is not main has no refs/heads/main (twenty-ninth run, c1c DISS-C-004)
# a scratch repository the suite builds is the suite's own: no global or system config reaches its init, add or commit —
# commit.gpgsign, core.hooksPath, init.templateDir, commit.template (thirtieth run, c1c DISS-C-003)
# (thirty-second run, c1a DISS-C-002: a git < 2.32 ignores GIT_CONFIG_GLOBAL — HOME and XDG_CONFIG_HOME point at no config too)
_cmp_git() { HOME=/nonexistent/loa-cmp-home XDG_CONFIG_HOME=/nonexistent/loa-cmp-home GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 command git -c user.email=t@t -c user.name=t -c protocol.file.allow=always "$@"; }
# sha256 hex of stdin — sha256sum, else shasum -a 256 (BSD / macOS), as the script falls back (thirtieth run, c1c DISS-C-002)
_cmp_sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; elif command -v shasum >/dev/null 2>&1; then shasum -a 256; else return 1; fi; }
_cmp_base_ref() { if command git -C "$PROJECT_ROOT" rev-parse -q --verify refs/heads/main >/dev/null 2>&1; then echo main; else echo HEAD; fi; }
_need_flock() { command -v flock >/dev/null 2>&1 || skip "flock not installed (macOS): the lock cases cannot run here"; }
# portable in-place literal substitution (first occurrence) — no GNU-only `sed -i`
# (thirty-second run, c1a DISS-C-001: an explicit exit, never an assert — PYTHONOPTIMIZE strips asserts, and an unmatched edit passed)
_cfg_edit() { python3 -c 'import sys; p,a,b=sys.argv[1:4]; s=open(p, encoding="utf-8").read(); a in s or sys.exit("_cfg_edit: no match for " + repr(a)); open(p, "w", encoding="utf-8").write(s.replace(a,b,1))' "$CONFIG_FILE" "$1" "$2"; }

_run_main() { main --type "${1:-review}" --sprint-id "$SPRINT" --diff-file "$T/diff.patch" --json 2> "$T/stderr.log"; }


# bounded readiness polls, never a fixed sleep (twenty-third run, c1c DISS-C-001: a 300 ms gap is not exotic on a host a live
# claude -p saturates): the stubborn child has exec'd its renamed sleep only after `trap "" TERM` ran, and a tree is ready when
# it has as many pids as it forks
_await_stubborn() { local _i; for _i in $(seq 1 100); do [[ "$(ps -o args= -p "$1" 2>/dev/null)" == "loa-cmp30-stubborn-"* ]] && return 0; sleep 0.05; done; echo "pid $1 never installed its TERM-ignore" >&2; return 1; }
_await_tree() { local _i; for _i in $(seq 1 100); do [ "$(_adv_tree_pids "$1" | wc -w)" -ge "$2" ] && return 0; sleep 0.05; done; echo "the tree of $1 never reached $2 pids" >&2; return 1; }
@test "CMP-1 keyless host: the primary's inner chain lands on codex-headless, the Anthropic companion is claude-headless; voices_planned 2, both ids succeeded, companion status succeeded with its cost" {
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.final_model' <<<"$result")" = "gpt-5.5-pro" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | sort | join(",")' <<<"$result")" = "claude-headless,codex-headless" ]
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.family' <<<"$result")" = "anthropic" ]
    [ "$(jq '.metadata.companion_voice.cost_cents' <<<"$result")" != "null" ]
    # keyless: the HTTP Anthropic voice (opus) was never tried
    [ "$(grep -cx "opus" "$CALLS")" = "0" ]
    grep -qx "claude-headless" "$CALLS"
    # both voices' findings are present, the companion's re-numbered and tagged
    [ "$(jq '.findings | length' <<<"$result")" = "2" ]
    [ "$(jq -r '[.findings[].voice] | sort | join(",")' <<<"$result")" = "claude-headless,gpt-5.5-pro" ]
    [ "$(jq -r '[.findings[].id] | sort | join(",")' <<<"$result")" = "DISS-001,DISS-C-001" ]
    [ -f "$OUT_DIR/adversarial-review.json" ]
}

@test "CMP-2 the companion chain failing (auth / quota / timeout) names the class, records the dropped voice, and the review still completes" {
    for cls in auth quota timeout; do
        : > "$CALLS"
        BEHAVIOUR[claude-headless]=$cls
        result=$(_run_main review)
        [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
        [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
        [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "$cls" ]
        [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
        [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "gpt-5.5-pro" ]
        [ "$(jq '[.verdict_quality.voices_dropped[].voice] | index("claude-headless") != null' <<<"$result")" = "true" ]
        [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "FAILED" ]
        [ "$(jq '.findings | length' <<<"$result")" = "1" ]
        [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "null" ]   # (nineteenth run, a3 C-006: nothing to judge)
    done
}

@test "CMP-3 a malformed companion is failure_class malformed; the primary's verdict is untouched" {
    BEHAVIOUR[claude-headless]=malformed
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "malformed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    # (twenty-fifth run, c1a DISS-C-002: the stub's malformed branch leaves a CLEAN sidecar beside unparseable content —
    # the KF-023 shape — so the envelope's verdict_quality must not count that voice)
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "gpt-5.5-pro" ]
    [ "$(jq -c '[.verdict_quality.voices_dropped[] | {voice, reason}]' <<<"$result")" = '[{"voice":"claude-headless","reason":"EmptyContent"}]' ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "APPROVED" ]
}

@test "CMP-4 an Anthropic-family primary gets the OpenAI companion (keyless → codex-headless only)" {
    _cfg_edit 'model: gpt-5.5-pro' 'model: opus'
    _cfg_edit $'      - gpt-5.5\n      - codex-headless\n' $'      - claude-headless\n'   # an Anthropic chain: C-005 keeps codex-headless free for the companion
    BEHAVIOUR[opus]=walked:claude-headless   # no key: cheval's inner chain lands on the CLI hop
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.family' <<<"$result")" = "openai" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "codex-headless" ]
    [ "$(grep -cx "gpt-5.5-pro" "$CALLS")" = "0" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    # with an OpenAI credential the default companion chain starts at gpt-5.5 — never gpt-5.5-pro (KF-002; third run C-007)
    export OPENAI_API_KEY="presence-canary-openai-never-printed"   # no sk- prefix: the diagnostic mask would hide a leak of an sk- canary (thirtieth run, c1a DISS-C-002)
    : > "$CALLS"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "gpt-5.5,codex-headless" ]
    [ "$(grep -cx "gpt-5.5-pro" "$CALLS")" = "0" ]
    [[ "$result" != *"presence-canary-openai-never-printed"* ]]
    [[ "$(cat "$T/stderr.log")" != *"presence-canary-openai-never-printed"* ]]   # (sixteenth run, c1a C-003: stderr too, as CMP-6 checks for the Anthropic key)
}

@test "CMP-5 companion_voice: false on the block disables the second chain (voices_planned 1, planned false); the YAML boolean spellings match in any case and a non-boolean is said and ignored (eleventh run, a1 C-001)" {
    _cfg_edit $'enabled: true\n' $'enabled: true\n    companion_voice: false\n'
    result=$(_run_main review)
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "false" ]
    [ "$(grep -cx "claude-headless" "$CALLS")" = "0" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    prev=false
    for spelling in False NO Off; do
        _cfg_edit "companion_voice: $prev" "companion_voice: $spelling"; prev=$spelling
        result=$(_run_main review)
        [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "false" ]
    done
    _cfg_edit "companion_voice: $prev" "companion_voice: nope"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    grep -q "companion_voice='nope' is not a boolean" "$T/stderr.log"
    _cfg_edit "companion_voice: nope" "companion_voice: TRUE"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    [ "$(grep -c "is not a boolean" "$T/stderr.log")" = "0" ]
}

@test "CMP-6 with a credential present the companion chain starts at the HTTP voice (opus) before the hop" {
    local canary="presence-canary-anthropic-never-printed"
    # the canary has teeth: neither the shared redactor nor the script's provider-key mask rewrites it, so a leak through
    # either redacted path still shows (an sk-ant- canary was masked whole — thirtieth run, c1a DISS-C-002)
    local mask; mask=$(grep -o "s/(^|\[^A-Za-z0-9\])(sk|xai|gsk)[^']*" "$ADVERSARIAL_REVIEW" | head -1)
    [ -n "$mask" ]
    [ "$(printf '%s\n' "x sk-ant-presence-only-never-printed" | sed -E "$mask")" = "x [REDACTED-KEY]" ]   # (the mask is live)
    [ "$(printf '%s\n' "x $canary" | bash "$PROJECT_ROOT/.claude/scripts/lib/log-redactor.sh" | sed -E "$mask")" = "x $canary" ]
    export ANTHROPIC_API_KEY="$canary"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "opus" ]
    grep -qx "opus" "$CALLS"
    [[ "$(cat "$T/stderr.log")" != *"$canary"* ]]
    [[ "$result" != *"$canary"* ]]
}

@test "CMP-7 the audit gate plans a companion too and keeps its degraded rules for a failed one" {
    BEHAVIOUR[claude-headless]=timeout
    result=$(_run_main audit)
    [ "$(jq -r '.metadata.type' <<<"$result")" = "audit" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    [ -f "$OUT_DIR/adversarial-audit.json" ]
    # the audit gate's own vocabulary: nothing rejected, nothing repaired, the primary's finding stands
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.findings[0].severity' <<<"$result")" = "MEDIUM" ]
}

# --- review round 1 (companion voice DISS-C-001 … C-011) --------------------------------------

@test "CMP-8 the envelope's spend is both voices (C-004); independence is recorded (C-005); no reject → no companion sidecar (C-010)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq '.metadata.cost_usd' <<<"$result")" = "0.0246" ]
    [ "$(jq '.metadata.tokens_input' <<<"$result")" = "200" ]
    [ "$(jq '.metadata.companion_voice.cost_cents' <<<"$result")" = "1.23" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.rejected_sidecar' <<<"$result")" = "null" ]
    # the common production case (tenth run, c1 C-002): every listed sidecar exists, and a feedback file with no
    # rejected-payload section is CONSISTENT against this clean two-voice envelope
    [ "$(jq '.metadata.rejected_sidecars | length' <<<"$result")" = "1" ]   # the primary's (empty) file; a companion that rejected nothing writes none — the loop below is not a no-op
    for f in $(jq -r '.metadata.rejected_sidecars[]' <<<"$result"); do [ -f "$PROJECT_ROOT/$f" ]; done
    { echo "All good"; echo; echo "Sprint 9 has been reviewed and approved."; echo
      echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'; } > "$OUT_DIR/engineer-feedback.md"
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.consistent == true and (.warnings | length) == 0' >/dev/null
}

@test "CMP-9 a companion hop the primary chain also holds stays planned (shared_hops); the primary answering from its own family keeps the companion independent (C-005, live re-run)" {
    _cfg_edit $'      - codex-headless
  security_audit:' $'      - codex-headless
      - claude-headless
  security_audit:'
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.shared_hops | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "independent_voice" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq '.verdict_quality.voices_succeeded' <<<"$result")" = "2" ]
    grep -qx "claude-headless" "$CALLS"
    # no overlap at all: shared_hops is empty
    _cfg_edit $'      - codex-headless
      - claude-headless
  security_audit:' $'      - codex-headless
  security_audit:'
    result=$(_run_main review)
    [ "$(jq -c '.metadata.companion_voice.shared_hops' <<<"$result")" = "[]" ]
}

@test "CMP-10 a primary chain that exhausts does not bury the companion: reviewed + degraded, primary_voice failed, the companion's findings stand (C-006)" {
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.degraded' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.primary_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.findings[0].voice' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    # c C-002 (third run): the promotion is visible in verdict quality too — never a clean consensus
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "APPROVED" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq '[.verdict_quality.voices_dropped[].voice] | index("gpt-5.5-pro") != null' <<<"$result")" = "true" ]
    [ "$(jq '.verdict_quality.voices_succeeded' <<<"$result")" = "1" ]
    [ -n "$(jq -r '.metadata.primary_voice.error // empty' <<<"$result")" ]
    [ "$(jq -r '.metadata.status_note' <<<"$result")" != "null" ]
}

@test "CMP-11 no credential and no CLI for the other family → planned false, reason no_route; the CLI alone is a route (C-007)" {
    export LOA_ADVERSARIAL_CLI_PROBE=none
    result=$(_run_main review)
    # (field by field, as every other case — an additive field is not a defect; twenty-second run, c1a DISS-C-003)
    [ "$(jq -r '.metadata.companion_voice | [.planned, .reason, .family] | map(tostring) | join(",")' <<<"$result")" = "false,no_route,anthropic" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    export LOA_ADVERSARIAL_CLI_PROBE=claude
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "claude-headless" ]
}

@test "CMP-12 a companion payload that still fails lands in the companion's own sidecar, named on the envelope, and in rejected_summary with its voice (C-010)" {
    BEHAVIOUR[claude-headless]=reject
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.rejected_sidecar' <<<"$result")" = "grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-companion.jsonl" ]
    [ "$(grep -c '' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "1" ]   # not wc -l: BSD wc pads
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.rejected_summary[0].voice' <<<"$result")" = "claude-headless" ]
    # the terminal reason after the repair round-trip (the stub's repair answer mutates a
    # non-violated field): the summary and the sidecar row name the same reason
    reason=$(jq -r '.metadata.rejected_summary[0].reason' <<<"$result")
    [ -n "$reason" ]
    [ "$reason" != "null" ]
    [ "$(jq -r '.reject_reason' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "$reason" ]
    [ "$(jq -r '.model' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "claude-headless" ]
    [ ! -s "$OUT_DIR/adversarial-rejected-review.jsonl" ]
    # c C-005: the repair round-trip went through the stubbed dissenter (dissent + repair), never a live CLI
    [ "$(grep -cx claude-headless "$CALLS")" = "2" ]
}

@test "CMP-13 an operator companion_chain on the block is used as given, before presence or defaults (C-011)" {
    export ANTHROPIC_API_KEY="sk-ant-presence-only-never-printed"
    python3 - "$CONFIG_FILE" <<'PY'
import sys; p=sys.argv[1]; s=open(p, encoding="utf-8").read()
s=s.replace("  code_review:\n    enabled: true\n", "  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: [claude-headless]\n      openai: [codex-headless]\n", 1); open(p, "w", encoding="utf-8").write(s)
PY
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(grep -cx "opus" "$CALLS")" = "0" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
}

@test "CMP-14 the wait cap reaps a hung companion: failure_class timeout, the review completes, no orphan (C-001)" {
    # positive control first (twentieth run, c1a DISS-C-002): the probe below counts a live stub, then nothing once it is gone
    _cmp14_probe() { local a; a=$(ps -eo args=) || { echo "ps -eo args= is unsupported here" >&2; return 1; }; grep -Ec "loa-cmp14-hun[g]-$$"'( |$)' <<<"$a" || true; }
    bash -c 'exec -a "$0" sleep 300' "loa-cmp14-hung-$$" 3>&- & s=$!; HOLDER_PIDS+=("$s")
    # (the stub leaves HOLDER_PIDS once it is reaped below: teardown never signals a freed pid — twenty-first run, c1a DISS-C-002)
    for _ in $(seq 1 50); do [ "$(_cmp14_probe)" = "1" ] && break; sleep 0.1; done
    [ "$(_cmp14_probe)" = "1" ]
    kill -KILL "$s"; wait "$s" 2>/dev/null || true; unset "HOLDER_PIDS[$(( ${#HOLDER_PIDS[@]} - 1 ))]"   # (dense; no negative subscript below bash 4.3 — twenty-ninth run, c1a DISS-C-001)
    [ "$(_cmp14_probe)" = "0" ]
    BEHAVIOUR[claude-headless]=slow
    # (twenty-second run, c1a DISS-C-001: the hop must have been IN FLIGHT — a 1 s cap that fires before the stub spawned anything
    # reaps nothing — and the run is bounded, so a reaper that failed is not hidden by a 300 s sleep that ends on its own)
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=5
    local t0; t0=$(_now_ms)
    result=$(_run_main review)
    (( $(_now_ms) - t0 < 120000 )) || { echo "the run took $(( ($(_now_ms) - t0) / 1000 )) s: the hung hop was not reaped"; return 1; }
    [ -e "$T/marker-slow-spawned" ] || { echo "the cap fired before the hop was in flight (a startup race, not a reaper regression)"; return 1; }
    grep -qx claude-headless "$CALLS"
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]   # the hop in flight, not a guess (sixth run C-001)
    # the orphan probe needs no pgrep (sixteenth run, c1b C-004): ps args, the pattern bracketed so the grep never matches itself,
    # anchored after the pid (twentieth run, c1a DISS-C-001), and a ps that cannot answer is a red, never a vacuous 0 (c1a DISS-C-002)
    _cmp14_orphans() { local a; a=$(ps -eo args=) || { echo "ps -eo args= is unsupported here" >&2; return 1; }; grep -Ec "loa-cmp14-hun[g]-$$"'( |$)' <<<"$a" || true; }
    [ "$(_cmp14_orphans)" = "0" ]   # the reaper ended a 300 s hop
    # …and the same reap through the pgrep-FREE walker (round 1p's fallback — the path most likely to be wrong is the one
    # asserted too): pgrep hidden from the script, a fresh hung hop, no orphan afterwards
    : > "$CALLS"
    t0=$(_now_ms)
    result=$( export _ADV_PGREP_BIN=/nonexistent/pgrep; _run_main review )   # exported: a prefix is undone before the EXIT-trap reaper runs (run 23 c1a C-001)
    (( $(_now_ms) - t0 < 120000 )) || { echo "the pgrep-free run took $(( ($(_now_ms) - t0) / 1000 )) s: the hung hop was not reaped"; return 1; }
    grep -qx claude-headless "$CALLS"
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    [ "$(_cmp14_orphans)" = "0" ]
}

@test "CMP-15 a fold that fails keeps the primary envelope (companion_voice.status fold_failed) instead of blanking it (C-002), and the companion's sidecar stays listed so its rows are still counted (tenth run, c2 C-002)" {
    _fold_companion() { echo "not json at all"; }
    BEHAVIOUR[claude-headless]=reject
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "fold_failed" ]
    # the rows the companion rejected do not go with the fold: the file exists, the envelope lists it (the list
    # is the run's files, not the fold's output), and verdict-derive holds an approval to those rows
    [ "$(grep -c '' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "1" ]
    jq -e --arg p "grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-companion.jsonl" '.metadata.rejected_sidecars | index($p) != null' <<<"$result" >/dev/null
    { echo "All good"; echo; echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'; } > "$OUT_DIR/engineer-feedback.md"
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 1 ]
    echo "$output" | jq -e '.consistent == false and (.violations | map(select(test("schema-rejected payload"))) | length) == 1' >/dev/null
    # verdict quality says the companion's voice was LOST to the fold — never a healthy second voice whose findings are
    # absent (thirteenth run, a3 C-002)
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "gpt-5.5-pro" ]
    [ "$(jq -c '[.verdict_quality.voices_dropped[] | {voice, reason}]' <<<"$result")" = '[{"voice":"claude-headless","reason":"Other"}]' ]   # (the schema's reason enum; the rationale names the fold)
}

@test "CMP-16 a failed companion carries its last diagnostic line, redacted (C-003)" {
    BEHAVIOUR[claude-headless]=errlog
    export TMPDIR="$T"   # the workdir glob and the delete below are test-scoped, whatever an interrupted run left in /tmp (sixteenth run, c1b C-003)
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "model_unavailable" ]
    # the envelope carries only an allowlisted summary (nothing here qualifies → no last_error at all);
    # the redacted raw line is operator-facing on stderr (fourth run, chunk c C-004)
    [ "$(jq -r '.metadata.companion_voice.last_error // "none"' <<<"$result")" = "none" ]
    grep -q "Companion voice diagnostic (claude-headless): boom: provider said no" "$T/stderr.log"
    [ "$(grep -c "SECRETSECRETSECRETSECRET1234" "$T/stderr.log")" = "0" ]
    [[ "$result" != *"SECRETSECRETSECRETSECRET1234"* ]]
    # c C-004: the raw line lives only in the /tmp workdir, which the EXIT trap removed — never in the a2a directory
    [ -d "$OUT_DIR" ]   # a missing directory would make the recursive grep pass vacuously
    [ -z "$(grep -rl "SECRETSECRETSECRETSECRET1234" "$OUT_DIR")" ]
    [ -z "$(ls -d "$TMPDIR"/adversarial-"$SPRINT"-* 2>/dev/null)" ]   # the script's workdir honours TMPDIR
    # …and that glob is the real workdir, not a vacuous pattern (tenth run, c1 C-003): kept once, it is exactly one
    # directory holding the companion's log with the raw line; then removed
    # main's traps, exits and globals stay in a subshell, and the knob is exported there as a process env would be — a
    # prefix on the call would end before the subshell's EXIT trap reads it (twenty-first run, c1a DISS-C-001)
    ( export LOA_ADVERSARIAL_KEEP_WORKDIR=1; _run_main review >/dev/null )
    kept=$(ls -d "$TMPDIR"/adversarial-"$SPRINT"-* 2>/dev/null)
    [ "$(printf '%s\n' "$kept" | grep -c .)" = "1" ]
    [ -s "$kept/companion/companion.log" ]
    grep -q "provider said no" "$kept/companion/companion.log"
    [[ "$kept" == "$T"/* ]]   # never a delete outside the test's directory
    find "$kept" -mindepth 1 -delete; rmdir "$kept"
}

@test "CMP-17 the failure class follows cheval's EXIT_CODES (4 MISSING_API_KEY auth, 6 BUDGET_EXCEEDED quota, 3/124 timeout, 5 INVALID_RESPONSE malformed, 1/other model_unavailable) and the wait-cap / malformed statuses" {
    [ "$(_companion_failure_class api_failure 4)" = "auth" ]
    [ "$(_companion_failure_class api_failure 6)" = "quota" ]
    [ "$(_companion_failure_class api_failure 3)" = "timeout" ]
    [ "$(_companion_failure_class api_failure 124)" = "timeout" ]
    [ "$(_companion_failure_class api_failure 5)" = "malformed" ]
    [ "$(_companion_failure_class api_failure 1)" = "model_unavailable" ]
    [ "$(_companion_failure_class api_failure 2)" = "model_unavailable" ]
    [ "$(_companion_failure_class malformed_response 0)" = "malformed" ]
    [ "$(_companion_failure_class wait_timeout 124)" = "timeout" ]
    # each class maps onto a verdict-quality drop reason
    [ "$(_companion_drop_reason quota)" = "RateLimited" ]
    [ "$(_companion_drop_reason auth)" = "ProviderUnavailable" ]
    [ "$(_companion_drop_reason model_unavailable)" = "ProviderUnavailable" ]
    [ "$(_companion_drop_reason malformed)" = "EmptyContent" ]
    [ "$(_companion_drop_reason timeout)" = "Other" ]
    # a diagnostic decides when the exit code does not: rate limits are quota (fifth run)
    [ "$(_companion_failure_class api_failure 1 "[cheval] RETRIES_EXHAUSTED: Failed after 4 attempts: [cheval] RATE_LIMITED: Rate limited by anthropic")" = "quota" ]
    [ "$(_companion_failure_class api_failure 1 "claude -p timed out after 910s")" = "timeout" ]   # the live bound, not a literal 610 (d C-003)
    # a rate limit is `quota` however it arrives: cheval's exit 6, or a RATE_LIMITED / 429 diagnostic under exit 1 (the resource
    # documents exactly this — sixteenth run, b2 C-001)
    [ "$(_companion_failure_class "" 1 "[cheval] RETRIES_EXHAUSTED: Failed after 4 attempts: [cheval] RATE_LIMITED: Rate limited by anthropic")" = "quota" ]
    [ "$(_companion_failure_class "" 1 "HTTP 429 Too Many Requests")" = "quota" ]
    [ "$(_companion_failure_class "" 1 "Provider 'anthropic' unavailable: connection refused")" = "model_unavailable" ]
}

@test "CMP-18 a primary whose inner chain lands on the companion's family: independent false, the companion's findings kept and tagged, no second voice in verdict quality (chunk c C-003)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:claude-headless   # cheval's inner chain crossed families
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "false" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "duplicate_voice" ]
    [ "$(jq -r '.metadata.companion_voice.primary_succeeded_model' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.final_model' <<<"$result")" = "gpt-5.5-pro" ]
    grep -q "NOT independent" "$T/stderr.log"
    # findings: both kept, tagged — voice is the outer hop, answered_by the model that actually answered (c C-003)
    [ "$(jq '.findings | length' <<<"$result")" = "2" ]
    [ "$(jq -r '[.findings[].voice] | sort | join(",")' <<<"$result")" = "claude-headless,gpt-5.5-pro" ]
    [ "$(jq -r '[.findings[].answered_by] | unique | join(",")' <<<"$result")" = "claude-headless" ]
    # verdict quality counts distinct voices: the duplicate contributes no envelope (the aggregator's
    # INV-5 forbids one id both succeeded and dropped) — one voice, nothing dropped, still aggregated
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    [ "$(jq '.verdict_quality.voices_succeeded' <<<"$result")" = "1" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq '.verdict_quality.voices_dropped | length' <<<"$result")" = "0" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    # and the honest case: the primary answered from its own family
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "true" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "independent_voice" ]
    [ "$(jq -r '.metadata.companion_voice.primary_succeeded_model' <<<"$result")" = "codex-headless" ]
    [ "$(jq '.verdict_quality.voices_succeeded' <<<"$result")" = "2" ]
}

@test "CMP-19 cheval's CLI-hop timeout (PROVIDER_UNAVAILABLE / exit 1, 'timed out') classes as timeout, and last_error carries the provider's line, not the shim wrapper (live re-run)" {
    BEHAVIOUR[claude-headless]=clitimeout
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    le=$(jq -r '.metadata.companion_voice.last_error' <<<"$result")
    [ "$le" = "RETRIES_EXHAUSTED PROVIDER_UNAVAILABLE timed out after 610s" ]   # the allowlisted summary, nothing else
    [ "$(jq -r '.verdict_quality.voices_dropped[0].reason' <<<"$result")" = "Other" ]
    # the classifier alone: the diagnostic decides only when the exit code does not
    [ "$(_companion_failure_class api_failure 1 "claude -p timed out after 610s")" = "timeout" ]
    [ "$(_companion_failure_class api_failure 1 "connection refused")" = "model_unavailable" ]
    [ "$(_companion_failure_class api_failure 4 "timed out")" = "auth" ]
}

@test "CMP-20 a FAILED companion whose id is one of the primary's succeeded voices feeds no dropped-voice envelope (INV-5): verdict quality still aggregates, counted_as duplicate_voice (third run C-001 BLOCKING)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:claude-headless     # the primary fell through to claude-headless (this host's last resort)
    BEHAVIOUR[claude-headless]=timeout                # …and the claude-headless companion timed out
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "duplicate_voice" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq '.verdict_quality.voices_dropped | length' <<<"$result")" = "0" ]
    grep -q "no dropped-voice envelope" "$T/stderr.log"
    # the ordinary failed companion (a different id) is still a dropped voice
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq -r '.verdict_quality.voices_dropped[0].voice' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "null" ]
}

@test "CMP-21 the companion's answered_by and independence follow ITS succeeded id, not its outer hop (third run C-002)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    BEHAVIOUR[claude-headless]=walked:codex-headless   # cheval's inner chain under the companion hop landed on the primary's family
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.answered_by' <<<"$result")" = "codex-headless" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "false" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "duplicate_voice" ]
    [ "$(jq -r '[.findings[] | select(.voice == "claude-headless") | .answered_by] | unique | join(",")' <<<"$result")" = "codex-headless" ]
    # and when the companion answers from its own family it is independent
    BEHAVIOUR[claude-headless]=ok
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.answered_by' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "true" ]
}

@test "CMP-22 the wait cap is sized per hop — a *-headless hop by the CLI adapter's bound (connect 10 s + max(600 s, the catalog's headless_timeout_seconds)), an HTTP hop by timeout_seconds — plus 30 s slack (third + fourth run)" {
    # claude-headless carries headless_timeout_seconds: 900 in the catalog → 910; codex-headless does not → 610. These legs pin the
    # SHIPPED catalog on purpose (the System-Zone defaults no operator edits; a framework change to a bound or a chain is reviewed
    # here) — the formula over arbitrary catalogs is NRM-44's (thirtieth run, c1a DISS-C-001, refuted)
    [ "$(_adv_cli_hop_bound claude-headless)" = "910" ]
    [ "$(_adv_cli_hop_bound codex-headless)" = "610" ]
    [ "$(_companion_wait_cap 30 claude-headless)" = "940" ]
    # an HTTP hop whose catalog chain falls through to a CLI hop takes that binary's lock first and can run that CLI inside one
    # cheval call: its lock wait, its own timeout, then the CLI bound (eighteenth run, a2 C-002; nineteenth run, a2 C-001) —
    # in the shipped catalog opus and tiny reach claude, gpt-5.5 reaches codex
    [ "$(_companion_wait_cap 30 opus claude-headless)" = "1910" ]
    [ "$(_companion_wait_cap 900 codex-headless)" = "930" ]
    [ "$(_companion_wait_cap 60 gpt-5.5)" = "760" ]
    [ "$(_companion_wait_cap 600 gpt-5.5 codex-headless)" = "2450" ]
    [ "$(_adv_cli_inner_bound opus)" = "910" ]; [ "$(_adv_cli_inner_bound gpt-5.5)" = "610" ]; [ "$(_adv_cli_inner_bound claude-headless)" = "910" ]
    [ "$( _ADV_CLI_HOP_TIMEOUT=100; _companion_wait_cap 30 foo-headless )" = "130" ]   # a hop the catalog does not size
    [ "$( LOA_MODEL_CONFIG=/nonexistent.yaml _adv_cli_hop_bound claude-headless )" = "610" ]
    # the fallback knob is validated like every other numeric knob, and never above the ceiling (eighteenth run, a2 C-003)
    [ "$( LOA_ADVERSARIAL_CLI_HOP_TIMEOUT=abc _adv_cli_hop_timeout_load 2>"$T/knob-err"; echo "$_ADV_CLI_HOP_TIMEOUT" )" = "610" ]
    grep -q "LOA_ADVERSARIAL_CLI_HOP_TIMEOUT='abc' is not a whole number of at least 1 — 610 applies" "$T/knob-err"
    [ "$( LOA_ADVERSARIAL_CLI_HOP_TIMEOUT=0 _adv_cli_hop_timeout_load 2>/dev/null; echo "$_ADV_CLI_HOP_TIMEOUT" )" = "610" ]
    [ "$( LOA_ADVERSARIAL_CLI_HOP_TIMEOUT=99999 _adv_cli_hop_timeout_load 2>"$T/knob-err"; echo "$_ADV_CLI_HOP_TIMEOUT" )" = "3600" ]
    grep -q "exceeds the CLI hop ceiling — 3600 applies" "$T/knob-err"
    [ "$( LOA_ADVERSARIAL_CLI_HOP_TIMEOUT=100 _adv_cli_hop_timeout_load 2>/dev/null; echo "$_ADV_CLI_HOP_TIMEOUT" )" = "100" ]
    _adv_cli_hop_timeout_load 2>/dev/null   # (back to the suite's default)
    # the live line names the cap
    result=$(_run_main review)
    grep -q "wait cap 940s" "$T/stderr.log"
}

@test "CMP-23 each writer truncates its own rejected sidecar at run start — a second run into the same sprint directory does not accumulate rows (third run, chunk c C-001)" {
    BEHAVIOUR[claude-headless]=reject
    result=$(_run_main review)
    [ "$(grep -c '' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "1" ]
    result=$(_run_main review)
    [ "$(grep -c '' "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = "1" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    # the envelope names the sidecars this run produced; verdict-derive counts JSON rows, not bytes —
    # one triage bullet clears the contract, and a trailing blank line changes nothing (c C-007)
    [ "$(jq -c '.metadata.rejected_sidecars' <<<"$result")" = "[\"grimoires/loa/a2a/$SPRINT/adversarial-rejected-review.jsonl\",\"grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-companion.jsonl\"]" ]
    printf '\n' >> "$OUT_DIR/adversarial-rejected-review-companion.jsonl"
    {
        echo "All good"; echo; echo "Sprint 9 has been reviewed and approved."; echo
        echo "## Rejected dissent payloads"; echo; echo "- no severity — repair-mutated-nonviolated-field: not a defect."; echo
        echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"sprint-9","ts":"2026-09-25T00:00:00Z"} -->'
    } > "$OUT_DIR/engineer-feedback.md"
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.consistent == true' >/dev/null
    # a stale sidecar from a writer that did not run this time is not this run's (chunk b C-003 / c C-002) — and
    # whatever its age it is a violation, never exempt for being older than the envelope (tenth run b C-001):
    # its rows were never folded, so they are triaged or the file removed before the gate passes
    printf '{"reject_reason":"stale"}\n%.0s' 1 2 3 4 5 > "$OUT_DIR/adversarial-rejected-review-a-old-chunk.jsonl"
    touch -t 202001010000 "$OUT_DIR/adversarial-rejected-review-a-old-chunk.jsonl"   # (BSD touch has no -d 'Y-m-d H:M:S')
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 1 ]   # its five rows count (eleventh run, b DISS-C-001): 6 rows against 1 bullet, the warning names the file
    echo "$output" | jq -e '.consistent == false and (.violations | length) == 1 and (.violations[0] | test("holds 1 top-level triage line.*6 rejected payload")) and (.warnings | map(select(test("a-old-chunk.jsonl.*not listed.*never folded"))) | length) == 1' >/dev/null
    rm -f "$OUT_DIR/adversarial-rejected-review-a-old-chunk.jsonl"
    run bash -c "bash '$PROJECT_ROOT/.claude/scripts/verdict-derive.sh' --file '$OUT_DIR/engineer-feedback.md' --gate review --json 2>/dev/null"
    [ "$status" -eq 0 ]
}

@test "CMP-24 when the shim swallowed cheval's stderr, the failed companion's class and last_error come from the MODELINV ledger row for that call (fourth run)" {
    # test-scoped, asserted before ANY write to it — never the repository's append-only chain (sixteenth run, c1b C-002; twentieth run, c1b DISS-C-001)
    [[ "${LOA_MODELINV_LOG_PATH:-}" == "$T"/* ]]
    BEHAVIOUR[claude-headless]=errquiet
    # the row cheval writes for this call lands inside the companion's window (the stub writes it at call time;
    # the harness points LOA_MODELINV_LOG_PATH at a temp file)
    export ERRQUIET_LEDGER_MESSAGE="[cheval] RETRIES_EXHAUSTED: Failed after 1 attempts: [cheval] PROVIDER_UNAVAILABLE: Provider 'anthropic' unavailable: claude -p timed out after 910s"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    le=$(jq -r '.metadata.companion_voice.last_error' <<<"$result")
    [ "$le" = "MODELINV RETRIES_EXHAUSTED PROVIDER_UNAVAILABLE timed out after 910s" ] || [ "$le" = "RETRIES_EXHAUSTED PROVIDER_UNAVAILABLE timed out after 910s" ]
    [[ "$le" != *"shim"* ]]
    # the adapter's note on a catalog bound not applied as written survives the summary, and the class stays timeout
    # (nineteenth run, d C-002)
    export ERRQUIET_LEDGER_MESSAGE="[cheval] RETRIES_EXHAUSTED: Failed after 1 attempts: [cheval] PROVIDER_UNAVAILABLE: Provider 'anthropic' unavailable: claude -p timed out after 610s (catalog headless_timeout_seconds '15m' ignored: not a positive finite number of seconds)"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    le=$(jq -r '.metadata.companion_voice.last_error' <<<"$result")
    [[ "$le" == *"timed out after 610s"* ]]
    [[ "$le" == *"catalog headless_timeout_seconds '15m' ignored: not a positive finite number of seconds"* ]]
    # a row written by ANOTHER invocation of the same model during the companion's post phase (a primary repair) is not
    # this voice's either: the window is the companion's last hop (sixteenth run, a3 C-004) — pinned on the lookup itself
    # (twentieth run, c1b DISS-C-002: a companion that succeeds carries no last_error, so an envelope assertion is inert)
    _row() { jq -nc --arg ts "$1" --arg msg "$2" '{schema_version:"1.1.0", primitive_id:"MODELINV", event_type:"model.invoke.complete", ts_utc:$ts,
                payload:{models_requested:["anthropic:claude-headless"], models_succeeded:[], calling_primitive:"adversarial-review",
                         models_failed:[{model:"anthropic:claude-headless", provider:"anthropic", error_class:"FALLBACK_EXHAUSTED", message_redacted:$msg}]}}'; }
    { _row 2026-10-01T10:00:03Z before; _row 2026-10-01T10:00:06Z hop; _row 2026-10-01T10:00:12Z "repair: rate limit hit"; } > "$LOA_MODELINV_LOG_PATH"
    [ "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05Z 2026-10-01T10:00:09Z)" = "hop" ]   # the post-phase row (after the hop's end) is not this voice's
    _row 2026-10-01T10:00:12Z "repair: rate limit hit" > "$LOA_MODELINV_LOG_PATH"
    [ -z "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05Z 2026-10-01T10:00:09Z)" ]
    [ "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05Z 2026-10-01T10:00:13Z)" = "repair: rate limit hit" ]   # positive control: inside a wider window it is read
    BEHAVIOUR[claude-headless]=errquiet
    # a row older than the companion's start is not this call's — nor one after its end (tenth run, c1 C-005)
    unset ERRQUIET_LEDGER_MESSAGE
    [[ "${LOA_MODELINV_LOG_PATH:-}" == "$T"/* ]]   # test-scoped, asserted — never the repository's append-only chain (sixteenth run, c1b C-002)
    : > "$LOA_MODELINV_LOG_PATH"
    jq -nc '{schema_version:"1.1.0", primitive_id:"MODELINV", event_type:"model.invoke.complete", ts_utc:"2099-01-01T00:00:00Z",
             payload:{models_requested:["anthropic:claude-headless"], models_succeeded:[], calling_primitive:"adversarial-review",
                      models_failed:[{model:"anthropic:claude-headless", provider:"anthropic", error_class:"FALLBACK_EXHAUSTED", message_redacted:"later: claude -p timed out after 1s"}]}}' >> "$LOA_MODELINV_LOG_PATH"
    # the same full shape as above, differing only in ts_utc — so only the timestamp filter rejects it (c1 C-004)
    jq -nc '{schema_version:"1.1.0", primitive_id:"MODELINV", event_type:"model.invoke.complete", ts_utc:"2000-01-01T00:00:00Z",
             payload:{models_requested:["anthropic:claude-headless"], models_succeeded:[], calling_primitive:"adversarial-review",
                      models_failed:[{model:"anthropic:claude-headless", provider:"anthropic", error_class:"FALLBACK_EXHAUSTED", message_redacted:"stale: claude -p timed out after 1s"}]}}' >> "$LOA_MODELINV_LOG_PATH"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "model_unavailable" ]
    [[ "$(jq -r '.metadata.companion_voice.last_error // ""' <<<"$result")" != *"stale"* ]]
    [[ "$(jq -r '.metadata.companion_voice.last_error // ""' <<<"$result")" != *"later"* ]]
}

@test "CMP-25 *-headless hops are serialised per CLI binary across the two walks (phase-tagged trace, time-bounded); a lock not acquired within the hop's bound fails the hop as a timeout; the repair round-trip takes the same lock (fourth–seventh run)" {
    _need_flock
    # phase-tagged trace: serialised hops read start,end,start,end by timestamp; overlapping ones start,start,… (c1 C-001)
    invoke_dissenter() { echo "$(_now_ms) start $BASHPID" >> "$T/lock-trace"; sleep 1; echo "$(_now_ms) end $BASHPID" >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    # (twenty-second run, c1b DISS-C-003: a short lock bound, so a lock-release regression is a prompt red, never a 910 s stall,
    # and each hop's own status is checked — a bare `wait` is 0 whatever its children returned)
    t0=$(_now_ms)
    ( _ADV_LOCK_WAIT_CLI=20; _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null ) & h1=$!
    ( _ADV_LOCK_WAIT_CLI=20; _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null ) & h2=$!
    wait "$h1"; wait "$h2"
    t1=$(_now_ms)
    (( t1 - t0 < 20000 ))
    [ "$(sort -n "$T/lock-trace" | awk '{printf "%s,", $2}')" = "start,end,start,end," ]
    (( t1 - t0 >= 2000 ))   # two one-second hops, one after the other
    [ -f "$T/loa-headless-locks-$(id -u)/claude.lock" ]
    # a held lock: the hop is not run, rc 124 (a timeout), the chain can walk on
    : > "$T/lock-trace"
    exec 8>>"$T/loa-headless-locks-$(id -u)/foo.lock"; flock 8
    rc=0; ( _ADV_CLI_HOP_TIMEOUT=1; _adv_invoke_hop foo-headless a b foo-headless 30 "" review 2>"$T/lock-err" ) || rc=$?
    flock -u 8; exec 8>&-
    [ "$rc" = "124" ]
    [ ! -s "$T/lock-trace" ]
    grep -q "not acquired within 1s" "$T/lock-err"
    # an HTTP hop whose chain holds no CLI hop takes no lock: the lock directory is byte-identical around the call
    # (lock files are named after the BINARY, so "no gpt-5.5.lock" proves nothing — c1 C-001 of the tenth run)
    # …and proven the held-lock way too (twentieth run, c1b DISS-C-004): with claude.lock and codex.lock held, a wrong
    # resolution onto either would wait out its 1 s bound and fail rc 124; the hop runs at once instead
    printf 'providers:\n  openai:\n    models:\n      gpt-5.5-plain:\n        context_window: 400000\n' > "$T/plain-catalog.yaml"
    exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8; exec 9>>"$T/loa-headless-locks-$(id -u)/codex.lock"; flock 9
    before=$(ls -A "$T/loa-headless-locks-$(id -u)" 2>/dev/null)
    : > "$T/lock-trace"; rc=0
    ( _ADV_CLI_HOP_TIMEOUT=1; _ADV_LOCK_WAIT=1; _ADV_LOCK_WAIT_CLI=1; LOA_MODEL_CONFIG="$T/plain-catalog.yaml" _adv_invoke_hop gpt-5.5-plain a b gpt-5.5-plain 30 "" review >/dev/null 2>"$T/lock-err3" ) || rc=$?
    flock -u 9; exec 9>&-; flock -u 8; exec 8>&-
    after=$(ls -A "$T/loa-headless-locks-$(id -u)" 2>/dev/null)
    [ "$rc" = "0" ]
    ! grep -q "not acquired" "$T/lock-err3" || { echo "the HTTP hop queued for a lock" >&2; return 1; }
    [ -n "$before" ]
    [ "$before" = "$after" ]
    [ "$(grep -c . "$T/lock-trace")" = "2" ]
    # the repair round-trip goes through the SAME lock — proven the held-lock way (sixteenth run, c1b C-001): with claude.lock
    # held the repair is not run (rc 124 within its own wait, an empty trace, the line on stderr); released, it runs exactly once
    _repair_finding_via_model() { echo "$(_now_ms) repair $BASHPID" >> "$T/lock-trace"; echo '{}'; }
    : > "$T/lock-trace"
    exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8
    rc=0; ( _ADV_LOCK_WAIT_CLI=1; _adv_with_cli_lock claude-headless _repair_finding_via_model x y z claude-headless 60 2>"$T/lock-err2" >/dev/null ) || rc=$?
    flock -u 8; exec 8>&-
    [ "$rc" = "124" ]
    [ ! -s "$T/lock-trace" ]
    grep -q "not acquired within 1s" "$T/lock-err2"
    _adv_with_cli_lock claude-headless _repair_finding_via_model x y z claude-headless 60 >/dev/null
    [ "$(grep -c repair "$T/lock-trace")" = "1" ]
}

@test "CMP-26 the companion's post-hop work has its own budget: a model that answered is not reaped mid-process_findings when the hop cap has passed (fifth run C-001)" {
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=3          # the hop phase's cap (twenty-first run, c1b DISS-C-003: room for the hop itself on a loaded host)
    eval "$(declare -f process_findings | sed '1s/^process_findings/_orig_process_findings/')"
    process_findings() { if [[ "$3" == "claude-headless" ]]; then : > "$T/slow-post-hop"; sleep 5; fi; _orig_process_findings "$@"; }   # slow post-hop work for the companion only, past the hop cap
    t0=$(_now_ms)
    result=$(_run_main review)
    [ -f "$T/slow-post-hop" ]                       # the slow branch ran (c1 C-003)
    (( $(_now_ms) - t0 >= 5000 ))
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    # the budget is read from a FIXTURE catalog whose bounds differ from the shipped ones (twenty-third run, c1b DISS-C-002: a
    # catalog retune must never read as a budget regression): claude-headless 1200 → bound 1210, codex-headless 800 → 810
    printf 'providers:\n  anthropic:\n    models:\n      haiku-fixture:\n        context_window: 1000\n        fallback_chain: ["anthropic:claude-headless"]\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 1200\n  openai:\n    models:\n      gpt-5.5-pro:\n        context_window: 1000\n        fallback_chain: ["openai:codex-headless"]\n      codex-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 800\naliases:\n  tiny: "anthropic:haiku-fixture"\n' > "$T/budget-catalog.yaml"
    [ "$( export LOA_MODEL_CONFIG="$T/budget-catalog.yaml"; _companion_post_budget gpt-5.5-pro 30 )" = "3810" ]      # keyless: hops claude-headless (its lock wait 30 + its bound 1210 — twenty-third run, a2 DISS-C-001) and the answering voice (its lock wait 30 + timeout 30 + its inner codex bound 810 — eighteenth run a2 C-002, nineteenth run a2 C-001); the repair wall budget 1240 × 2 + 30 plus the heaviest hop 1240, + 60 (twenty-ninth run, a3 DISS-C-001)
    [ "$( export LOA_MODEL_CONFIG="$T/budget-catalog.yaml" ANTHROPIC_API_KEY=k; _companion_post_budget gpt-5.5-pro 30 )" = "3900" ]   # tiny (30 + 30 + its inner claude bound 1210) the heaviest: 1270 × 2 + 30 + 1270 + 60
}

@test "CMP-27 a primary that never answered leaves the companion as the sole voice: counted_as sole_voice, independent null; a companion that already answered with the shared hop is honoured, so the primary cedes it instead of failing it (fifth run C-003; thirteenth run a3 C-004)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'   # this host's shape: the primary chain ends on claude-headless
    # the primary's first hop fails only once the companion is GONE (a bounded barrier on its pid, not a sleep —
    # eleventh run, c1 C-001); on reaching the shared hop the primary finds the companion already ANSWERED with it and
    # cedes (`skipped_shared_with_companion`, `primary_voice.status ceded`, not degraded — thirteenth run). The
    # `unavailable-primary-only` stub is the tripwire: it fails this test if the primary ever runs that hop itself
    # (sixteenth run, c1b C-005: the comment says what the assertions pin)
    BEHAVIOUR[gpt-5.5-pro]=unavailable-after-companion; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[claude-headless]=unavailable-primary-only
    result=$(_run_main review)
    [ "$(jq -r '.metadata.model_attempts | join(",")' <<<"$result")" = "gpt-5.5-pro:api_failure,gpt-5.5:api_failure,codex-headless:api_failure,claude-headless:skipped_shared_with_companion" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.degraded' <<<"$result")" = "false" ]   # ceded, not exhausted (thirteenth run, a2 C-004)
    [ "$(jq -r '.metadata.primary_voice.status' <<<"$result")" = "ceded" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "sole_voice" ]
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "null" ]
    [ "$(jq '.metadata.companion_voice.primary_attempts_excluded' <<<"$result")" = "null" ]   # no primary attempt ever dropped the companion's hop
    [ "$(grep -cx "claude-headless" "$CALLS")" = "1" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "4" ]
    [ "$(jq '.verdict_quality.voices_dropped | length' <<<"$result")" = "3" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ ! -e "$T/marker-barrier-expired" ]   # the ordering barrier was met, never expired (sixteenth run, c1a C-001)
}

@test "CMP-28 LOA_ADVERSARIAL_RUN_TAG scopes the sidecar names to the run: only this run's files are removed at start and listed on the envelope (fifth run C-004)" {
    mkdir -p "$OUT_DIR"; printf '{"reject_reason":"earlier"}\n' > "$OUT_DIR/adversarial-rejected-review-companion.jsonl"   # another run's file
    # …and a stale file under THIS run's tag, from a previous attempt: removed at start, never appended to (twenty-second run, c1b DISS-C-002)
    printf '{"reject_reason":"stale-1"}\n{"reject_reason":"stale-2"}\n' > "$OUT_DIR/adversarial-rejected-review-companion-chunk-x.jsonl"
    export LOA_ADVERSARIAL_RUN_TAG="chunk-x"
    BEHAVIOUR[claude-headless]=reject
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.rejected_sidecar' <<<"$result")" = "grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-companion-chunk-x.jsonl" ]
    [ "$(jq -c '.metadata.rejected_sidecars' <<<"$result")" = "[\"grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-chunk-x.jsonl\",\"grimoires/loa/a2a/$SPRINT/adversarial-rejected-review-companion-chunk-x.jsonl\"]" ]
    [ "$(grep -c '' "$OUT_DIR/adversarial-rejected-review-companion-chunk-x.jsonl")" = "1" ]
    # listed implies present (twenty-sixth run, c1b DISS-C-003): the primary rejected nothing, and its tagged sidecar is still an
    # empty regular file beside the envelope — verdict-derive reads a listed, missing one as a violation
    [ -f "$OUT_DIR/adversarial-rejected-review-chunk-x.jsonl" ]
    [ ! -L "$OUT_DIR/adversarial-rejected-review-chunk-x.jsonl" ]
    [ ! -s "$OUT_DIR/adversarial-rejected-review-chunk-x.jsonl" ]
    if grep -q 'stale-' "$OUT_DIR/adversarial-rejected-review-companion-chunk-x.jsonl"; then echo "this run's stale rows survived its start"; return 1; fi
    [ "$(cat "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = '{"reject_reason":"earlier"}' ]   # untouched — its CONTENT, not its presence (sixteenth run, c1c C-004)
    # sixth run, C-004: with the sidecar disabled nothing of ours is listed (another run's files stay out)
    unset LOA_ADVERSARIAL_RUN_TAG; export LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=1
    result=$(_run_main review)
    [ "$(jq -c '.metadata.rejected_sidecars' <<<"$result")" = "[]" ]
    [ "$(cat "$OUT_DIR/adversarial-rejected-review-companion.jsonl")" = '{"reject_reason":"earlier"}' ]   # the disabled run shares its canonical name and still left it alone
    unset LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE
}

@test "CMP-29 lock-wait time is not charged to the hop's cap: a companion that queued behind another claude -p still gets its full cap once it holds the lock (sixth run C-002); the lock directory must be ours (C-003)" {
    _need_flock
    export XDG_RUNTIME_DIR="$T"
    # hold the claude lock for 8 s from outside; the companion's hop needs 2 s of its own; the hop cap is 6 s (twenty-first run,
    # c1b DISS-C-003: 4 s of slack beside the hop, not 1)
    mkdir -m 700 "$T/loa-headless-locks-$(id -u)"
    ( exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8; sleep 8 ) 3>&- &   # held longer than the 6 s cap: queueing alone would reap (eighth run, c1 C-002)
    HOLDER_PIDS+=("$!")
    # wait until the lock is observably held (c1 C-006)
    for _ in $(seq 1 40); do flock -n "$T/loa-headless-locks-$(id -u)/claude.lock" true 2>/dev/null || break; sleep 0.05; done
    if flock -n "$T/loa-headless-locks-$(id -u)/claude.lock" true 2>/dev/null; then echo "lock not held" >&2; false; fi
    BEHAVIOUR[claude-headless]=slow2
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=6
    t0=$(_now_ms)
    result=$(_run_main review)
    t1=$(_now_ms)
    wait
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    (( t1 - t0 >= 8000 ))   # queued ~8 s behind the holder, then its own 2 s hop: far past the 6 s hop cap, not reaped
    # a foreign or symlinked lock directory is never used — the hop runs unserialised instead
    find "$T/loa-headless-locks-$(id -u)" -mindepth 1 -delete; rmdir "$T/loa-headless-locks-$(id -u)"   # whatever locks the two chains took — never coupled to the shipped catalog's chains (sixteenth run, c1c C-005)
    ln -s "$T" "$T/loa-headless-locks-$(id -u)"
    invoke_dissenter() { echo ran >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null
    [ "$(grep -c ran "$T/lock-trace")" = "1" ]
    [ ! -e "$T/claude.lock" ]
}

@test "CMP-30 a companion whose CLI ignores TERM is killed after the grace period and the review completes (sixth run: an 8 h hang under the account's usage limit)" {
    BEHAVIOUR[claude-headless]=stubborn
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=1 LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1
    start=$(date +%s)
    result=$(_run_main review)
    (( $(date +%s) - start < 30 ))
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    grep -q "after TERM — KILL" "$T/stderr.log"
    command -v pgrep >/dev/null || skip "pgrep not installed"
    [ -z "$(pgrep -f "loa-cmp30-stubborn-$$"'( |$)')" ]
}

@test "CMP-31 the per-binary lock follows the alias's resolved chain: an HTTP alias whose catalog fallback_chain falls through to a CLI hop takes that binary's lock (eighth run, a2 C-002)" {
    _need_flock
    cat > "$T/catalog.yaml" <<'YAML'
providers:
  openai:
    models:
      gpt-5.5:
        context_window: 400000
        fallback_chain: ["openai:gpt-5.3-codex", "openai:codex-headless"]
      gpt-5.3-codex:
        context_window: 400000
      codex-headless:
        context_window: 400000
  anthropic:
    models:
      opus-plain:
        context_window: 1000000
aliases:
  fast: "openai:gpt-5.5"
  fastclaude: "anthropic:claude-headless"
YAML
    export LOA_MODEL_CONFIG="$T/catalog.yaml"
    [ "$(_adv_cli_bin_for gpt-5.5)" = "codex" ]
    [ "$(_adv_cli_bin_for fast)" = "codex" ]
    [ "$(_adv_cli_bin_for claude-headless)" = "claude" ]
    [ "$(_adv_cli_bin_for opus-plain)" = "" ]
    # the prefix and an alias are resolved before the *-headless test (twelfth run, a2 C-001): one lock per binary
    [ "$(_adv_cli_bin_for anthropic:claude-headless)" = "claude" ]
    [ "$(_adv_cli_bin_for openai:gpt-5.5)" = "codex" ]
    [ "$(_adv_cli_bin_for fastclaude)" = "claude" ]   # (declared in the one `aliases:` block above — a second top-level key is a parser's coin toss; sixteenth run, c1c C-002)
    # …and every reader of a hop's CLI bound sees the canonical id (thirteenth run, a2 C-001): a prefixed or aliased CLI hop
    # gets the catalog's bound and counts as a CLI hop in the wait cap, never the 610 s fallback
    printf 'providers:\n  anthropic:\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 900\naliases:\n  fastclaude: "anthropic:claude-headless"\n' > "$T/catalog2.yaml"
    export LOA_MODEL_CONFIG="$T/catalog2.yaml"
    [ "$(_adv_cli_hop_bound claude-headless)" = "910" ]
    [ "$(_adv_cli_hop_bound anthropic:claude-headless)" = "910" ]
    [ "$(_adv_cli_hop_bound fastclaude)" = "910" ]
    [ "$(_companion_wait_cap 30 anthropic:claude-headless)" = "$(_companion_wait_cap 30 claude-headless)" ]
    [ "$(_companion_wait_cap 30 fastclaude)" = "940" ]
    export LOA_MODEL_CONFIG="$T/catalog.yaml"
    # an HTTP hop whose fixture chain falls through to codex-headless is charged its timeout plus that bound; one without a CLI
    # in its chain only its timeout (eighteenth run, a2 C-002)
    [ "$(_companion_wait_cap 30 gpt-5.5)" = "700" ]   # lock wait 30 + timeout 30 + codex 610 + 30
    [ "$(_companion_wait_cap 30 opus-plain)" = "60" ]
    invoke_dissenter() { echo ran >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    _adv_invoke_hop anthropic:claude-headless a b anthropic:claude-headless 30 "" review >/dev/null
    [ -f "$T/loa-headless-locks-$(id -u)/claude.lock" ]
    [ ! -e "$T/loa-headless-locks-$(id -u)/anthropic_claude.lock" ]
    : > "$T/lock-trace"
    invoke_dissenter() { echo ran >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    _adv_invoke_hop gpt-5.5 a b gpt-5.5 30 "" review >/dev/null
    [ -f "$T/loa-headless-locks-$(id -u)/codex.lock" ]
    before=$(ls -A "$T/loa-headless-locks-$(id -u)" 2>/dev/null)
    # held-lock proof (twentieth run, c1b DISS-C-004): both binaries' locks held, a wrong resolution would fail rc 124 within 1 s
    exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8; exec 9>>"$T/loa-headless-locks-$(id -u)/codex.lock"; flock 9
    rc=0; ( _ADV_CLI_HOP_TIMEOUT=1; _ADV_LOCK_WAIT=1; _ADV_LOCK_WAIT_CLI=1; _adv_invoke_hop opus-plain a b opus-plain 30 "" review >/dev/null 2>"$T/lock-err4" ) || rc=$?
    flock -u 9; exec 9>&-; flock -u 8; exec 8>&-
    after=$(ls -A "$T/loa-headless-locks-$(id -u)" 2>/dev/null)
    [ "$rc" = "0" ]
    ! grep -q "not acquired" "$T/lock-err4" || { echo "the HTTP hop queued for a lock" >&2; return 1; }
    [ -n "$before" ]
    [ "$before" = "$after" ]   # a model with no CLI in its chain touched no lock (snapshot, not a filename guess)
    [ "$(grep -c ran "$T/lock-trace")" = "2" ]
}

@test "CMP-32 the INV-5 exclusion is symmetric: a companion attempt that dropped a voice the primary answered with is excluded, verdict quality still aggregates, and an aggregator failure would be named on the envelope (eighth run, a2 C-004)" {
    # an operator chain whose first hop is the primary's own CLI: the companion's codex-headless attempt fails, then claude-headless answers
    python3 - "$CONFIG_FILE" <<'PY'
import sys; p=sys.argv[1]; s=open(p, encoding="utf-8").read()
s=s.replace("  code_review:\n    enabled: true\n", "  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: [codex-headless, claude-headless]\n", 1); open(p, "w", encoding="utf-8").write(s)
PY
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    BEHAVIOUR[codex-headless]=unavailable-companion-only
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]
    [ "$(jq '.metadata.companion_voice.companion_attempts_excluded' <<<"$result")" = "1" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | sort | join(",")' <<<"$result")" = "claude-headless,codex-headless" ]
    [ "$(jq -r '.metadata | has("verdict_quality_error")' <<<"$result")" = "false" ]
    # an aggregator failure is named, not discarded
    _adv_aggregate_envelopes() { echo "[verdict-aggregate] invariant violation: INV-5: stub" >&2; return 2; }
    result=$(_run_main review)
    [ "$(jq -r '.metadata.verdict_quality_error' <<<"$result")" = "[verdict-aggregate] invariant violation: INV-5: stub" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
}

@test "CMP-33 the primary skips a hop the live companion shares instead of queueing behind its claude -p: model_attempts records it, the companion is the sole voice (tenth run, a2 C-003)" {
    _need_flock
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'   # the primary chain ends on the companion's hop
    # the companion answers only after the primary has failed its codex hop (a bounded barrier on a marker, not a
    # sleep — eleventh run, c1 C-001): it is alive when the primary reaches the shared hop
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable-marker
    BEHAVIOUR[claude-headless]=await-primary-marker
    result=$(_run_main review)
    [ "$(jq -r '.metadata.model_attempts | join(",")' <<<"$result")" = "gpt-5.5-pro:api_failure,gpt-5.5:api_failure,codex-headless:api_failure,claude-headless:skipped_shared_with_companion" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "sole_voice" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    grep -q "the companion answered with it — skipped on the primary chain" "$T/stderr.log"
    # the primary CEDED the hop to a companion that answered with it: one voice, not a degraded "chain exhausted" (thirteenth run, a2 C-004)
    [ "$(jq -r '.metadata.degraded' <<<"$result")" = "false" ]
    [ "$(jq -r '.metadata.primary_voice.status' <<<"$result")" = "ceded" ]
    [ "$(jq -r '.metadata.primary_voice.hop' <<<"$result")" = "claude-headless" ]
    # the repair's HTTP hop waits for the lock only as long as its own timeout (a2 C-001) — and so does a repair's
    # CLI hop under _ADV_LOCK_WAIT_CLI (twelfth run, a1 C-002), never a dissent hop's 910 s bound
    export ANTHROPIC_API_KEY="sk-presence-only-never-printed" XDG_RUNTIME_DIR="$T"
    # the HTTP alias's fall-through to the claude binary is the FIXTURE's, never the shipped catalog's (sixteenth run, c1c C-005)
    printf 'providers:\n  anthropic:\n    models:\n      haiku-fixture:\n        context_window: 1000\n        fallback_chain: ["anthropic:claude-headless"]\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 900\naliases:\n  tiny: "anthropic:haiku-fixture"\n' > "$T/repair-catalog.yaml"
    export LOA_MODEL_CONFIG="$T/repair-catalog.yaml"
    [ "$(_adv_cli_bin_for tiny)" = "claude" ]
    mkdir -p "$T/loa-headless-locks-$(id -u)"; exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8
    _repair_finding_via_model() { echo '{}'; }
    # the DEFAULT rule, never the override knob (twenty-third run, c1b DISS-C-001): both knobs unset, the hop's own CONF_TIMEOUT
    # of 1 s against a fixture bound of 910 s — a rule that charged this hop the CLI bound runs past the 10 s ceiling below
    # (each probe is bounded: a regressed rule fails at the bound, never a ~15-minute stall under the held lock — twenty-fifth
    # run, c1b DISS-C-001)
    _probe_default() { unset _ADV_LOCK_WAIT _ADV_LOCK_WAIT_CLI; CONF_TIMEOUT=1; _adv_with_cli_lock tiny _repair_finding_via_model x y z tiny 1 >/dev/null 2>&1; }
    _probe_knob() { _ADV_LOCK_WAIT_CLI=1; _adv_with_cli_lock claude-headless _repair_finding_via_model x y z claude-headless 1 >/dev/null 2>&1; }
    t0=$(date +%s); rc=0; _cmp_bounded 10 _probe_default || rc=$?
    (( $(date +%s) - t0 < 10 ))
    [ "$rc" = "124" ]
    t0=$(date +%s); rc=0; _cmp_bounded 10 _probe_knob || rc=$?
    flock -u 8; exec 8>&-
    (( $(date +%s) - t0 < 10 ))
    [ "$rc" = "124" ]
    [ ! -e "$T/marker-barrier-expired" ]   # the ordering barrier was met, never expired (sixteenth run, c1a C-001)
}

@test "CMP-34 the envelope and sidecars are single-writer per (sprint, gate): a second live run is refused before it removes anything — a distinct tag too (the envelope path is shared); a dead run's lock, a reused pid and an abandoned empty lock are taken over; a lock seconds old with no pid yet is a holder in flight (eleventh run a2 DISS-001; twelfth run a2 C-002 / C-003)" {
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"; [ -d "$lockd" ]
    [ "$(sed -n 1p "$lockd/pid")" = "$BASHPID" ]; [ -n "$(sed -n 2p "$lockd/pid")" ]   # pid + start time
    me=$BASHPID   # captured in THIS shell — inside `$(…)` BASHPID is the substitution's pid, the defect a2 C-001 fixed
    [ "$(sed -n 2p "$lockd/pid")" = "$(_adv_proc_start "$me")" ]   # the ACQUIRING process's token, not a substitution subshell's (sixteenth run, a2 C-001)
    # a subshell of the run (it inherits $$ and the variables) can never release the parent's lock (fifteenth run, a2 C-002)
    ( _adv_release_run_lock ); [ -d "$lockd" ]
    _adv_release_run_lock; [ ! -d "$lockd" ]
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"; [ -d "$lockd" ]
    sleep 30 3>&- & holder=$!; HOLDER_PIDS+=("$holder"); printf '%s\n%s\n' "$holder" "$(_adv_proc_start "$holder")" > "$lockd/pid"; _ADV_RUN_LOCK_DIR=""   # held by another live process
    # the live run's envelope and sidecars are on disk: the refused run must leave them exactly as they are (twentieth run, c1b DISS-C-003)
    mkdir -p "$OUT_DIR"
    printf '{"findings":[],"metadata":{"status":"reviewed","marker":"live-run"}}\n' > "$OUT_DIR/adversarial-review.json"
    printf '{"reject_reason":"live-primary"}\n' > "$OUT_DIR/adversarial-rejected-review.jsonl"
    printf '{"reject_reason":"live-companion"}\n' > "$OUT_DIR/adversarial-rejected-review-companion.jsonl"
    # the whole directory, not three names (twenty-sixth run, c1b DISS-C-002): a file the refused run created, removed or rewrote
    # under any name — a tagged sidecar, a marker — fails the leg
    # POSIX find types and cksum (no -printf, no sha256sum), pipefail, and a non-empty seed: a snapshot that failed cannot
    # match itself vacuously (twenty-seventh run, c1b DISS-C-001)
    _cmp34_snap() { (set -o pipefail; cd "$OUT_DIR" && for _t in f d l; do find . -type "$_t" | LC_ALL=C sort | sed "s/\$/ $_t/" || exit 1; done && find . -type f -exec cksum {} + | LC_ALL=C sort); }
    seeded=$(_cmp34_snap) && [ -n "$seeded" ] || { echo "the CMP-34 snapshot failed or is empty" >&2; return 1; }
    [[ "$seeded" == *"adversarial-review.json f"* ]]
    _cmp34_untouched() {
        [ "$(_cmp34_snap)" = "$seeded" ] || { echo "the refused run changed the live run's directory: $(diff <(printf '%s\n' "$seeded") <(_cmp34_snap))" >&2; return 1; }
        [ -z "$(ls -A "$OUT_DIR" | grep -E '\.prev$|moved-aside')" ] || { echo "the refused run moved files aside: $(ls -A "$OUT_DIR")" >&2; return 1; }
    }
    BEHAVIOUR[claude-headless]=reject
    rc=0; result=$(_run_main review) || rc=$?
    [ "$rc" = "2" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "refused_concurrent_run" ]   # a --json caller fails closed (twelfth run, a3 C-004)
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    grep -q "another adversarial-review run for $SPRINT/review is in progress (pid $holder)" "$T/stderr.log"
    _cmp34_untouched
    # a distinct tag is NOT a parallel path — the envelope adversarial-review.json is shared (twelfth run, a2 C-003)
    rc=0; result=$( export LOA_ADVERSARIAL_RUN_TAG=other; _run_main review ) || rc=$?
    [ "$rc" = "2" ]; [ ! -e "$OUT_DIR/adversarial-rejected-review-companion-other.jsonl" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "refused_concurrent_run" ]
    _cmp34_untouched
    [ "$(ls -d "$(_adv_cli_lock_dir)"/run-*.lock.d | grep -c .)" = "1" ]
    # a reused pid: the token's start time is not the live process's — the holder is gone, the lock is taken over
    printf '%s\n%s\n' "$holder" "Thu Jan  1 00:00:00 1970" > "$lockd/pid"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ ! -d "$lockd" ]
    # the holder died without releasing: taken over, run, released
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"; printf '%s\n%s\n' "$holder" "$(_adv_proc_start "$holder")" > "$lockd/pid"; _ADV_RUN_LOCK_DIR=""
    kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null || true
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ ! -d "$lockd" ]
    # a lock directory seconds old with no pid yet is a holder in flight (twelfth run, a2 C-002) …
    # (the grace is set wide so a loaded host's startup never outlasts it — twentieth run, c1b DISS-C-005)
    mkdir "$lockd"
    rc=0; result=$(LOA_ADVERSARIAL_RUN_LOCK_GRACE_SECONDS=120 _run_main review) || rc=$?
    [ "$rc" = "2" ]; grep -q "is starting (its lock is seconds old)" "$T/stderr.log"
    [ "$(jq -r '.metadata.status' <<<"$result")" = "refused_concurrent_run" ]
    # … and an abandoned one (older than five seconds, still no pid) is taken over
    touch -t 202001010000 "$lockd"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ ! -d "$lockd" ]
}

@test "CMP-35 the repair chain, like the main walk, omits a shared hop only while the companion is ON it (queue / hop), keeps it when the companion is on another hop or past its own, and always keeps the answering voice (twelfth run a1 C-002; thirteenth run a1 C-002)" {
    export ANTHROPIC_API_KEY="sk-presence-only-never-printed"
    companion_shared_hops="claude-headless"; companion_workdir="$T/cw"; mkdir -p "$companion_workdir"
    sleep 30 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID")
    printf 'claude-headless' > "$companion_workdir/companion.current"; printf 'queue' > "$companion_workdir/companion.phase"
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny gpt-5.5-pro" ]
    [ "$(_repair_model_chain "claude-headless")" = "tiny claude-headless" ]   # the voice that answered stays terminal
    printf 'hop' > "$companion_workdir/companion.phase"
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny gpt-5.5-pro" ]
    printf 'opus' > "$companion_workdir/companion.current"                    # busy elsewhere: the hop stays
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]
    printf 'claude-headless' > "$companion_workdir/companion.current"; printf 'post' > "$companion_workdir/companion.phase"   # past its hop: stays
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]
    kill "$_ADV_COMPANION_PID" 2>/dev/null; wait "$_ADV_COMPANION_PID" 2>/dev/null || true
    printf 'hop' > "$companion_workdir/companion.phase"
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]   # a dead companion holds nothing
    _ADV_COMPANION_PID=""; companion_shared_hops=""; companion_workdir=""
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]
    unset ANTHROPIC_API_KEY
}

@test "CMP-36 without flock the per-binary serialisation is off and said once per run — across capture subshells — and the hop's phase still starts (twelfth run a2 C-006; fifteenth run a3 C-001 / C-002)" {
    invoke_dissenter() { echo ran >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    mkdir -p "$T/wd"; _ADVERSARIAL_WORKDIR="$T/wd"   # the run's workdir holds the said-once marker (nineteenth run, a2 C-004: never a fixed name in a shared tmp)
    ( _ADV_FLOCK_BIN=/nonexistent/flock
      _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null
      x=$(_ADV_PHASE_FILE="$T/phase" _adv_invoke_hop claude-headless a b claude-headless 30 "" review)   # a capture subshell, as the walker calls it
      _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null ) 2>"$T/noflock-err"
    [ "$(grep -c ran "$T/lock-trace")" = "3" ]
    [ "$(grep -c "flock is not installed" "$T/noflock-err")" = "1" ]
    [ "$(cat "$T/phase")" = "hop" ]   # an unlocked hop is charged as a hop, never left in `queue`
    [ ! -e "$T/loa-headless-locks-$(id -u)/claude.lock" ]
    # a lock directory that is not ours is another unlocked path, said once too
    rm -f "$T/wd/.adv-unlocked-warned"; : > "$T/lock-trace"
    ( XDG_RUNTIME_DIR="/proc"; _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null; _adv_invoke_hop claude-headless a b claude-headless 30 "" review >/dev/null ) 2>"$T/notours-err"
    [ "$(grep -c ran "$T/lock-trace")" = "2" ]
    [ "$(grep -c "is not ours" "$T/notours-err")" = "1" ]
}

@test "CMP-37 a shared hop is skipped only while the companion is ON it: with the companion busy on its HTTP hop the primary waits for it to settle and then runs the hop itself; a companion that moved to the shared hop is not doubled (twelfth run, a3 C-001)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'   # the primary chain ends on the companion's CLI hop
    export ANTHROPIC_API_KEY="sk-presence-only-never-printed"   # a credentialed host: the companion chain is opus → claude-headless
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[opus]=slow2   # the companion is on opus (an HTTP hop) when the primary reaches claude-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "opus,claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "opus" ]
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:reviewed" ]   # not skipped: the companion never ran it
    grep -q "the companion finished without it — the primary runs it" "$T/stderr.log"
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "false" ]   # both Anthropic: not a second voice, but the primary did answer
    # the companion's HTTP hop fails and it moves to claude-headless: the primary does not double the binary
    BEHAVIOUR[opus]=unavailable; BEHAVIOUR[claude-headless]=slow2
    result=$(_run_main review)
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:skipped_shared_with_companion" ]
    [ "$(jq -r '.metadata.companion_voice.model' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "sole_voice" ]
    unset ANTHROPIC_API_KEY
}

@test "CMP-38 a failed prompt copy never launches the companion against an empty workdir: planned false, reason prompt_copy_failed, one voice (twelfth run, a3 C-006)" {
    cp() { return 1; }
    result=$(_run_main review)
    [ "$(jq -c '.metadata.companion_voice' <<<"$result")" = '{"planned":false,"reason":"prompt_copy_failed","family":"anthropic"}' ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "1" ]
    [ "$(grep -cx "claude-headless" "$CALLS")" = "0" ]
    grep -q "Companion voice not planned (anthropic family): prompt_copy_failed" "$T/stderr.log"
    [ "$(grep -c "hop the companion shares" "$T/stderr.log")" = "0" ]   # nothing is shared with a companion that never started (a3 C-004)
    unset -f cp
}

@test "CMP-39 a MIXED primary attempt envelope (the inner walk dropped the companion's voice and answered with another) keeps its own voice: aggregated without the conflicting dropped entry, two voices, INV-6 intact (twelfth run, a3 C-007)" {
    BEHAVIOUR[gpt-5.5-pro]=walkedmixed:claude-headless:codex-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq '.metadata.companion_voice.primary_attempts_rewritten' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.companion_voice.primary_attempts_excluded' <<<"$result")" = "null" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | sort | join(",")' <<<"$result")" = "claude-headless,codex-headless" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq '.verdict_quality.voices_dropped | length' <<<"$result")" = "0" ]
    grep -q "rewritten without that entry (INV-5; the primary's own voice kept)" "$T/stderr.log"
}

@test "CMP-40 an operator wait knob that is not a number never aborts the review or reaps a healthy companion: the computed cap applies (twelfth run, a3 C-003)" {
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS="ten minutes"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    grep -qE "Companion voice \(anthropic family\): claude-headless \(wait cap [0-9]+s\)" "$T/stderr.log"
    unset LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS
}

@test "CMP-41 a shared hop the companion is ON is not ceded on sight: the primary waits for the companion to settle, and when the companion FAILS that hop the primary runs it as its last resort — one voice, nothing dropped (thirteenth run, a2 C-003)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'   # the primary chain ends on the companion's hop
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[claude-headless]=unavailable-companion-only   # the companion's call fails; the primary's answers
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:reviewed" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.final_model' <<<"$result")" = "claude-headless" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "claude-headless" ]
    grep -q "the companion failed it — the primary runs it" "$T/stderr.log"
}

@test "CMP-42 a companion that already answered with the shared hop before the primary reached it is honoured: the binary runs once, the primary cedes (thirteenth run, a3 C-004)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'
    BEHAVIOUR[gpt-5.5-pro]=unavailable-after-companion; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable   # the companion (instant) is gone first
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:skipped_shared_with_companion" ]
    [ "$(grep -cx "claude-headless" "$CALLS")" = "1" ]   # one CLI invocation for the run, the companion's
    [ "$(jq -r '.metadata.primary_voice.status' <<<"$result")" = "ceded" ]
    [ "$(jq -r '.metadata.degraded' <<<"$result")" = "false" ]
    grep -q "the companion answered with it — skipped on the primary chain" "$T/stderr.log"
    [ "$(grep -c "the primary waits for the companion to settle" "$T/stderr.log")" = "0" ]   # nothing to wait for
    [ ! -e "$T/marker-barrier-expired" ]   # the ordering barrier was met, never expired (sixteenth run, c1a C-001)
}

@test "CMP-43 a workdir that cannot be created refuses with a JSON envelope under --json (status workdir_unavailable), like a refused concurrent run (thirteenth run, a3 C-005)" {
    rc=0; result=$( export TMPDIR="$T/no/such/dir"; _run_main review ) || rc=$?
    [ "$rc" = "2" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "workdir_unavailable" ]
    [ "$(jq -r '.metadata.tmpdir' <<<"$result")" = "$T/no/such/dir" ]
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    grep -q "cannot create a workdir under $T/no/such/dir" "$T/stderr.log"
}

@test "CMP-44 a diff whose single file exceeds the whole token budget is shown partially, cut at a hunk boundary, with a PARTIAL note — never an empty diff (thirteenth run, c1 C-001)" {
    mk_hunk() { printf '@@ -%d,3 +%d,4 @@ fn%d\n context\n-old line %d\n+new line %d %s\n+another line %d\n' "$1" "$1" "$1" "$1" "$1" "$(printf 'x%.0s' $(seq 1 200))" "$1"; }
    big="diff --git a/big.sh b/big.sh
--- a/big.sh
+++ b/big.sh
$(mk_hunk 10)
$(mk_hunk 40)
$(mk_hunk 70)
$(mk_hunk 100)"
    # 180 tokens ≈ 540 bytes: no whole file fits, one whole hunk and the marker do (twenty-fourth run, b1 DISS-C-001: with no lower rows the
    # marker comes out of the view's own share — at 150 the old three-quarter cap showed a hunk whose marker overran the budget)
    out=$(prepare_content "$big" 180 2>"$T/prep-err")
    [ "$(estimate_tokens "$out")" -le 180 ]
    [[ "$out" == "diff --git a/big.sh b/big.sh"* ]]
    [ "$(printf '%s\n' "$out" | grep -c '^@@ ')" -ge 1 ]
    [ "$(printf '%s\n' "$out" | grep -c '^@@ ')" -lt 4 ]
    [[ "$out" == *"--- PARTIAL: big.sh shown up to the token budget ("*" of 4 hunks; token budget: 180)"* ]]
    [[ "$out" != *"--- TRUNCATED:"* ]]
    grep -q "Top-priority file big.sh exceeds the token budget: shown partially" "$T/prep-err"
    # a cut inside the FIRST hunk ends on a line boundary and the marker says so (fifteenth run, b1 C-001)
    one="diff --git a/one.sh b/one.sh
--- a/one.sh
+++ b/one.sh
$(mk_hunk 5)"
    out=$(prepare_content "$one" 80 2>/dev/null)   # 80 tokens: the marker's ~50 and a cut inside the only hunk (at 40 the marker alone overran)
    [ "$(estimate_tokens "$out")" -le 80 ]
    [[ "$out" == *"--- PARTIAL: one.sh shown up to the token budget (1 of 1 hunks, the last one cut mid-way; token budget: 80)"* ]]
    [ "$(printf '%s\n' "$out" | awk '/^--- PARTIAL/{exit} {n++} END{print n}')" -ge 5 ]   # header + hunk header + at least one whole line, then the blank line before the marker
    # a budget that lands before the first newline shows nothing, never a mid-line fragment (eighteenth run, b1 DISS-002)
    printf 'diff --git a/one.sh b/one.sh\n' > "$T/first-line"
    [ "$(_lc_cut_partial "$T/first-line" 12 "$T/first-out")" = "mid" ]; [ ! -s "$T/first-out" ]
    out=$(prepare_content "$one" 4 2>/dev/null)   # 4 tokens ≈ 12 bytes: inside the header line
    [[ "$out" != *"diff --git"* ]]   # (twenty-first run, c1b DISS-C-001: the needle a 12-byte fragment could actually hold)
    [[ "$out" == *"--- PARTIAL: one.sh: no hunk fit within the token budget (0 of 1 hunks shown; token budget: 4)"* ]]   # (twentieth run, b1 DISS-C-003: a view that kept no hunk says so)
    # same-priority siblings that fit are not displaced by the partial view of one large file (fifteenth run, b1 C-002)
    sib1=$'diff --git a/s1.sh b/s1.sh\n--- a/s1.sh\n+++ b/s1.sh\n@@ -1 +1 @@\n-a\n+'"$(printf 'y%.0s' $(seq 1 120))"
    sib2=$'diff --git a/s2.sh b/s2.sh\n--- a/s2.sh\n+++ b/s2.sh\n@@ -1 +1 @@\n-a\n+'"$(printf 'z%.0s' $(seq 1 120))"
    out=$(prepare_content "$big
$sib1
$sib2" 300 2>/dev/null)   # 300 tokens: the two 60-token siblings fit; the big file gets what is left, not three quarters
    [[ "$out" == *"diff --git a/s1.sh b/s1.sh"* ]]
    [[ "$out" == *"diff --git a/s2.sh b/s2.sh"* ]]
    [[ "$out" == *"--- PARTIAL: big.sh"* ]]
    [[ "$out" != *"--- TRUNCATED:"* ]]
    # lower-priority rows never shrink the top file's view (sixteenth run, b1 C-001): with docs worth most of the budget the
    # script still gets three quarters and the docs are the ones truncated
    docs=""; for i in 1 2 3; do docs="$docs
diff --git a/d$i.md b/d$i.md
--- a/d$i.md
+++ b/d$i.md
@@ -1 +1 @@
-a
+$(printf 'w%.0s' $(seq 1 240))"; done
    out=$(prepare_content "$big$docs" 300 2>/dev/null)   # three ~100-token docs exceed the 300 budget: without the priority filter the script would get a quarter
    [[ "$out" == "diff --git a/big.sh b/big.sh"* ]]
    [ "$(printf '%s\n' "$out" | grep -c '^@@ ')" -ge 2 ]   # three quarters of 300 tokens = 225 ≈ 675 bytes: two of the four ~275-byte hunks (a quarter, 75 tokens, holds none)
    [[ "$out" == *"(2 of 4 hunks; token budget: 300)"* ]]
    [[ "$out" == *"--- TRUNCATED:"* ]]
    # the partial candidate is the first TOP-PRIORITY file that does not fit, not the first row (sixteenth run, b1 C-002)
    out=$(prepare_content "$sib1
$big" 300 2>/dev/null)
    [[ "$out" == *"diff --git a/s1.sh b/s1.sh"* ]]
    [[ "$out" == *"--- PARTIAL: big.sh shown up to the token budget"* ]]
    [[ "$out" != *"--- TRUNCATED:"* ]]
    # …and when the top tier fits whole, the candidate is the first over-budget file of the NEXT tier (nineteenth run, b1 C-002):
    # a small P0 script ahead of a large P1 source file — the large file is shown partially, never dropped whole
    bigpy=$(printf '%s' "$big" | sed 's/big\.sh/big.py/g')
    out=$(prepare_content "$sib1
$bigpy" 300 2>/dev/null)
    [[ "$out" == *"diff --git a/s1.sh b/s1.sh"* ]]
    [[ "$out" == *"--- PARTIAL: big.py shown up to the token budget"* ]]
    [[ "$out" != *"--- TRUNCATED:"* ]]
    # every file excluded by the review scope: an empty payload and a log line, never an abort (sixteenth run, b1 DISS-001)
    printf 'big.sh\n' > "$T/reviewignore"
    out=$(REVIEWIGNORE_FILE="$T/reviewignore" prepare_content "$big" 150 2>"$T/prep-err2")
    [ -z "$out" ]
    grep -q "Review scope excluded every file of the diff" "$T/prep-err2"
    # the mixed case (fourteenth run, b C-002): a top-priority script that does not fit whole plus a small doc that does —
    # the script is shown FIRST, partially, and the doc follows; the doc never displaces the script
    doc=$'diff --git a/notes.md b/notes.md\n--- a/notes.md\n+++ b/notes.md\n@@ -1 +1 @@\n-a\n+b'
    out=$(prepare_content "$doc
$big" 200 2>/dev/null)   # (twentieth run, b1 DISS-001: 200, not 150 — the PARTIAL marker is charged now, and 150 holds the partial and its marker but not the doc too)
    [[ "$out" == "diff --git a/big.sh b/big.sh"* ]]
    [[ "$out" == *"--- PARTIAL: big.sh shown up to the token budget"* ]]
    [[ "$out" == *"diff --git a/notes.md b/notes.md"* ]]
    [[ "$out" != *"--- TRUNCATED:"* ]]
    # the marker is ONE line even when the chunk has no hunk header at all (fourteenth run, b C-001: grep -c prints 0
    # and exits 1 — a `|| echo 0` would have emitted a second 0)
    bin="diff --git a/blob.bin b/blob.bin
GIT binary patch
literal 900
$(printf 'zcmV0123456789abcdef0123456789%.0s\n' $(seq 1 60))"
    out=$(prepare_content "$bin" 100 2>/dev/null)
    [ "$(printf '%s\n' "$out" | grep -c "^--- PARTIAL: blob.bin shown up to the token budget (0 of 0 hunks; token budget: 100)")" = "1" ]
    [ "$(printf '%s\n' "$out" | grep -cx '0')" = "0" ]
}

@test "CMP-45 a numeric knob that is not a whole number without a leading zero and at least its floor is said and its default applies — timeout_seconds, budget_cents, the context-escalation knobs and the --timeout / --budget overrides alike (fourteenth run a1 C-003; fifteenth run a1 C-001)" {
    _cfg_edit "timeout_seconds: 30" "timeout_seconds: 30s"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    grep -q "timeout_seconds='30s' is not a whole number of at least 1 — 60 applies" "$T/stderr.log"
    [ "$(grep -c "is not a whole number of at least" "$T/stderr.log")" = "1" ]
    # zero (GNU timeout 0 = no limit, and a zero repair budget) and a leading zero (octal to bash, rejected by --argjson)
    for bad in 0 060; do
        _cfg_edit "timeout_seconds: 30s" "timeout_seconds: $bad"
        result=$(_run_main review)
        [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
        grep -q "timeout_seconds='$bad' is not a whole number of at least 1 — 60 applies" "$T/stderr.log"
        _cfg_edit "timeout_seconds: $bad" "timeout_seconds: 30s"
    done
    # the sibling knobs get the same guard
    _cfg_edit "budget_cents: 200" "budget_cents: 150c"
    rc=0; result=$(_run_main review) || rc=$?
    [ "$rc" = "4" ]   # budget_exceeded is the pre-check's exit 4 — the run refuses to spend (round-1q dry run)
    grep -q "budget_cents='150c' is not a whole number of at least 0 — 0 applies" "$T/stderr.log"   # (a malformed spend cap fails CLOSED — sixteenth run, a1 C-004)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "budget_exceeded" ]
    _cfg_edit "budget_cents: 150c" "budget_cents: 200"
    # …and so do the command-line overrides
    rc=0; result=$(main --type review --sprint-id "$SPRINT" --diff-file "$T/diff.patch" --timeout 0x --budget -5 --json 2> "$T/stderr.log") || rc=$?
    [ "$rc" = "4" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "budget_exceeded" ]   # (a malformed --budget is 0 cents: fail closed)
    grep -q -- "--timeout='0x' is not a whole number of at least 1 — 60 applies" "$T/stderr.log"
    grep -q -- "--budget='-5' is not a whole number of at least 0 — 0 applies" "$T/stderr.log"
    result=$(main --type review --sprint-id "$SPRINT" --diff-file "$T/diff.patch" --timeout 0x --json 2> "$T/stderr.log")
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
}

@test "CMP-46 an aggregator that fails without a word never aborts the review: the envelope is emitted with verdict_quality_error (fourteenth run, a3 C-001)" {
    _adv_aggregate_envelopes() { return 1; }
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "2" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.verdict_quality // "absent"' <<<"$result")" = "absent" ]
    [ "$(jq -r '.metadata.verdict_quality_error' <<<"$result")" != "null" ]
    grep -q "aggregator unavailable or returned no output" "$T/stderr.log"
}

@test "CMP-48 a companion still running when the wait cap expires while the primary waits on the shared hop is reaped there, and the primary runs the hop itself — one voice, not none (fourteenth run, a3 C-002)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=3
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[claude-headless]=unavailable-companion-slow   # the companion hangs on it; the primary's own call answers
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.companion_voice.failure_class' <<<"$result")" = "timeout" ]
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:reviewed" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    grep -q "reaping the second voice; the primary runs the hop" "$T/stderr.log"
    grep -q "the companion was reaped at the wait cap — the primary runs it" "$T/stderr.log"
    # the helper's own decision field says so too (sixteenth run, a2 DISS-001 / C-002): a companion still on the hop past the
    # cap is `run` — the caller reaps, then runs
    sleep 30 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID"); _ADV_COMPANION_START=$(_adv_proc_start "$_ADV_COMPANION_PID")
    mkdir -p "$T/vw"; printf 'claude-headless' > "$T/vw/companion.current"; printf 'hop' > "$T/vw/companion.phase"
    [ "$(_adv_shared_hop_verdict claude-headless "$T/vw" "$(( $(date +%s) - 100 ))" 10 | cut -f1,2)" = "$(printf 'run\tpast_wait_cap')" ]
    kill "$_ADV_COMPANION_PID" 2>/dev/null; wait "$_ADV_COMPANION_PID" 2>/dev/null || true; _ADV_COMPANION_PID=""
    unset LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS
}

@test "CMP-49 a shared hop is recognised under a provider prefix: a primary chain ending on anthropic:claude-headless cedes it to the companion's claude-headless (fourteenth run, a3 C-003)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - anthropic:claude-headless\n  security_audit:'
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.shared_hops | join(",")' <<<"$result")" = "claude-headless" ]
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "anthropic:claude-headless:skipped_shared_with_companion" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.primary_voice.status' <<<"$result")" = "ceded" ]
    [ "$(grep -c "claude-headless" "$CALLS")" = "1" ]   # one CLI invocation — the companion's
}

@test "CMP-50 the reaper signals the companion's pid only while its start token matches the one recorded at the fork — a recycled pid is left alone (fifteenth run, a3 C-003)" {
    sleep 30 3>&- & p=$!; HOLDER_PIDS+=("$p")
    _ADV_COMPANION_PID=$p; _ADV_COMPANION_START="t1"   # not this process's token
    _adv_reap_companion 2>"$T/reap-err"
    kill -0 "$p"   # untouched
    grep -q "now belongs to another process" "$T/reap-err"
    _ADV_COMPANION_PID=$p; _ADV_COMPANION_START=$(_adv_proc_start "$p")
    LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1 _adv_reap_companion 2>/dev/null
    sleep 0.3; if kill -0 "$p" 2>/dev/null; then echo "pid $p still alive after reap" >&2; return 1; fi   # (twentieth run, c1c DISS-C-001: errexit-evaluable)
}

@test "CMP-51 the process tree is enumerated without pgrep too (fifteenth run, a3 C-004)" {
    bash -c 'sleep 30 & sleep 30 & wait' 3>&- & root=$!
    # a bounded poll until both children are forked, never a fixed wait (twenty-second run, c1b DISS-C-001): the baseline below is the whole tree
    local _i; for _i in $(seq 1 100); do [ "$(_adv_tree_pids "$root" | wc -w)" -ge 3 ] && break; sleep 0.1; done
    HOLDER_PIDS+=("$root")
    with=$(_adv_tree_pids "$root" | sort -n | tr '\n' ' ')
    # the WHOLE tree is a teardown holder (sixteenth run, c1c C-001: a TERM to the root alone frees its children first) — registered
    # before the assertion below can fail (twenty-eighth run, c1b DISS-C-004), but only a pid ps itself names as the root's own
    # child: the walker is what this test checks, and a walker that over-matched must be a red, never a teardown that signals
    # another process (thirty-first run, c1b DISS-C-001)
    for p in $with; do
        [[ "$p" == "$root" ]] && continue
        [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "$root" ] && HOLDER_PIDS+=("$p")
    done
    [ "$(printf '%s' "$with" | wc -w)" -eq 3 ]
    # the seam is observable (c1c C-003): a shadow pgrep first in PATH answers nothing, so an enumeration that ignored the
    # seam would return the root alone — asserted — while the ps walker returns the whole tree
    mkdir -p "$T/shadowbin"; printf '#!/bin/sh\nexit 1\n' > "$T/shadowbin/pgrep"; chmod +x "$T/shadowbin/pgrep"
    shadow=$( PATH="$T/shadowbin:$PATH"; hash -r; _adv_tree_pids "$root" | sort -n | tr '\n' ' ' )
    [ "$(printf '%s' "$shadow" | wc -w)" -eq 1 ]   # (-eq: BSD wc pads its count — twenty-eighth run, c1b DISS-C-001)
    without=$( PATH="$T/shadowbin:$PATH"; hash -r; _ADV_PGREP_BIN=/nonexistent/pgrep _adv_tree_pids "$root" | sort -n | tr '\n' ' ' )
    [ "$with" = "$without" ]
    # (thirty-second run, c1b DISS-C-001: every pid the walker returned is the root or one of its own children — an over-match is a
    # red here, and the closing signal goes only to that verified set, never to a stranger the walker named)
    local verified="$root"
    for p in $with; do
        [[ "$p" == "$root" ]] && continue
        [ "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" = "$root" ] || { echo "the walker named pid $p, not a child of $root" >&2; kill "$root" 2>/dev/null; return 1; }
        verified+=" $p"
    done
    # signalled as a whole, children with the parent — never the root first
    # shellcheck disable=SC2086
    kill $verified 2>/dev/null || true
}

@test "CMP-54 past the wait cap a companion that already ANSWERED and is finishing (phase post) is not reaped by the primary's shared-hop branch: the primary cedes, the post budget governs, one CLI run (fifteenth run, a4 C-002)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=2
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[claude-headless]=reject   # the companion answers at once, then repairs — in `post` — for longer than the wait cap
    _repair_finding_via_model() { [[ "${_ADV_SIDECAR_TAG:-}" == "companion" ]] && sleep 5; return 1; }
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:skipped_shared_with_companion" ]
    [ "$(jq -r '.metadata.primary_voice.status' <<<"$result")" = "ceded" ]
    [ "$(grep -cx "claude-headless" "$CALLS")" = "1" ]
    [ "$(grep -c "reaping the second voice" "$T/stderr.log")" = "0" ]
    grep -q "the companion answered with it — skipped on the primary chain" "$T/stderr.log"   # (eighteenth run, a3: the primary waited for the settled record, never ceded on sight)
    unset LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS
}

@test "CMP-55 a reaper that returns non-zero never aborts the review: the envelope is still emitted (fifteenth run, a4 C-001)" {
    eval "__real_kill_tree() $(declare -f _adv_kill_tree | sed '1d')"
    _adv_kill_tree() { __real_kill_tree "$@"; return 1; }
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'
    export LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS=3
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[claude-headless]=unavailable-companion-slow
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:reviewed" ]
    unset LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS
}

@test "CMP-52 a companion chain spelled through a catalog alias cedes like the canonical name: the fold's ceded comparison is canonical (fifteenth run, a3 C-005)" {
    printf 'providers:\n  anthropic:\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 900\naliases:\n  fastclaude: "anthropic:claude-headless"\n' > "$T/alias.yaml"
    export LOA_MODEL_CONFIG="$T/alias.yaml" ANTHROPIC_API_KEY="sk-presence-only-never-printed"
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - anthropic:claude-headless\n    companion_chain:\n      anthropic: [fastclaude]\n  security_audit:'
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.chain | join(",")' <<<"$result")" = "fastclaude" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "anthropic:claude-headless:skipped_shared_with_companion" ]
    [ "$(jq -r '.metadata.primary_voice.status' <<<"$result")" = "ceded" ]
    [ "$(jq -r '.metadata.degraded' <<<"$result")" = "false" ]
    unset ANTHROPIC_API_KEY LOA_MODEL_CONFIG
}

@test "CMP-53 the fold merges envelopes larger than an argv string can carry: both travel as files (fifteenth run, a3 C-006)" {
    wd="$T/fold-wd"; mkdir -p "$wd"
    python3 -c 'print("x" * 200000, end="")' > "$wd/desc.txt"   # (built through a file: a 200 KB argv string is the very limit under test)
    big=$(jq -nc --rawfile d "$wd/desc.txt" '{findings:[{id:"DISS-001",severity:"LOW",category:"other",description:$d,failure_mode:"fm"}],metadata:{type:"review",status:"reviewed",model:"gpt-5.5-pro",cost_usd:0.01,tokens_input:1,tokens_output:1,rejected_summary:[],rejected_count:0}}')
    [ "${#big}" -gt 150000 ]
    jq -nc '{findings:[{id:"DISS-001",severity:"LOW",category:"other",description:"from the companion.",failure_mode:"fm"}],metadata:{type:"review",status:"reviewed",model:"claude-headless",cost_usd:0.02,tokens_input:1,tokens_output:1,rejected_summary:[],rejected_count:0}}' > "$wd/companion.result.json"
    printf 'claude-headless' > "$wd/companion.final"; printf 'claude-headless:reviewed\n' > "$wd/companion.attempts"; printf 'reviewed' > "$wd/companion.status"; printf '0' > "$wd/companion.rc"
    _vq claude-headless ok > "$wd/vq-companion-1.json"; printf '%s\n' "$wd/vq-companion-1.json" > "$wd/companion.vq"
    out=$(_fold_companion "$big" "$wd" anthropic claude-headless gpt-5.5-pro gpt-5.5-pro "" "gpt-5.5-pro" "" 2>"$T/fold-err")
    [ -n "$out" ]
    [ "$(jq '.findings | length' <<<"$out")" = "2" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$out")" = "succeeded" ]
    [ "$(jq '.metadata.cost_usd' <<<"$out")" = "0.03" ]
    [ ! -s "$T/fold-err" ]
}

@test "CMP-56 a second run against a REAL holder is refused: the holder's lock token is its own, so it never looks recycled (sixteenth run, a2 C-001)" {
    ( _adv_take_run_lock "$OUT_DIR" review; printf '%s' "$_ADV_RUN_LOCK_DIR" > "$T/holder.dir"; exec sleep 30 ) 3>&- & holder=$!; HOLDER_PIDS+=("$holder")   # (exec: the holder IS the sleep, so one kill ends the tree — twenty-first run, c1c DISS-C-007)
    for _ in $(seq 1 50); do [ -s "$T/holder.dir" ] && break; sleep 0.1; done   # bounded poll, not a fixed sleep (twentieth run, c1c DISS-C-003)
    lockd=$(cat "$T/holder.dir"); [ -d "$lockd" ]
    [ "$(sed -n 1p "$lockd/pid")" = "$holder" ]
    [ "$(sed -n 2p "$lockd/pid")" = "$(_adv_proc_start "$holder")" ]   # the token seen from outside is the holder's
    rc=0; result=$(_run_main review) || rc=$?
    [ "$rc" = "2" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "refused_concurrent_run" ]
    grep -q "is in progress (pid $holder)" "$T/stderr.log"
    [ -d "$lockd" ]; [ "$(sed -n 1p "$lockd/pid")" = "$holder" ]   # untouched
    kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null || true
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
}

@test "CMP-57 the timed-out reaper records a wait timeout only for a tree it signalled: a walker that exited on its own at the cap boundary keeps its own status and exit code (sixteenth run, a3 C-001)" {
    wd="$T/cw57"; mkdir -p "$wd"
    printf 'api_failure' > "$wd/companion.status"; printf '4' > "$wd/companion.rc"; printf 'done' > "$wd/companion.phase"; printf 'claude-headless' > "$wd/companion.final"
    _ADV_COMPANION_PID=""   # nothing alive to reap
    _adv_reap_companion_timed_out "$wd" "claude-headless"
    [ "$(cat "$wd/companion.status")" = "api_failure" ]; [ "$(cat "$wd/companion.rc")" = "4" ]
    # a live tree IS reaped and recorded as a wait timeout
    sleep 30 3>&- & p=$!; HOLDER_PIDS+=("$p"); _ADV_COMPANION_PID=$p; _ADV_COMPANION_START=$(_adv_proc_start "$p")
    printf 'hop' > "$wd/companion.phase"
    LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1 _adv_reap_companion_timed_out "$wd" "claude-headless" 2>/dev/null
    [ "$(cat "$wd/companion.status")" = "wait_timeout" ]; [ "$(cat "$wd/companion.rc")" = "124" ]
    sleep 0.3; if kill -0 "$p" 2>/dev/null; then echo "pid $p still alive after reap" >&2; return 1; fi   # (twentieth run, c1c DISS-C-001: errexit-evaluable)
}

@test "CMP-58 a reap grace knob that is not a whole number is said and the default applies (sixteenth run, a3 C-002)" {
    sleep 30 3>&- & p=$!; HOLDER_PIDS+=("$p"); _ADV_COMPANION_PID=$p; _ADV_COMPANION_START=$(_adv_proc_start "$p")
    LOA_ADVERSARIAL_REAP_GRACE_SECONDS=5s _adv_reap_companion 2>"$T/grace-err"
    grep -q "LOA_ADVERSARIAL_REAP_GRACE_SECONDS='5s' is not a whole number of at least 0 — 5 applies" "$T/grace-err"
    sleep 0.3; if kill -0 "$p" 2>/dev/null; then echo "pid $p still alive after reap" >&2; return 1; fi   # (twentieth run, c1c DISS-C-001: errexit-evaluable)
}

@test "CMP-59 the INV-5 duplicate guard compares canonical names: a companion that fails on an alias of a hop the primary answered with is a duplicate, never a dropped voice (sixteenth run, a3 C-005)" {
    printf 'providers:\n  anthropic:\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 900\naliases:\n  fastclaude: "anthropic:claude-headless"\n' > "$T/alias.yaml"
    export LOA_MODEL_CONFIG="$T/alias.yaml" ANTHROPIC_API_KEY="sk-presence-only-never-printed"
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n    companion_chain:\n      anthropic: [fastclaude]\n  security_audit:'
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[fastclaude]=unavailable   # the companion fails its aliased hop; the primary then runs claude-headless itself (its call answers)
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "failed" ]
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "duplicate_voice" ]
    [ "$(jq -r '.verdict_quality.status' <<<"$result")" != "null" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "claude-headless" ]
    unset ANTHROPIC_API_KEY LOA_MODEL_CONFIG
}

@test "CMP-60 the kill tree is collected again after the freeze and before KILL (sixteenth run, a3 C-006)" {
    : > "$T/collect-count"
    eval "__real_tree_pids() $(declare -f _adv_tree_pids | sed '1d')"
    _adv_tree_pids() { echo x >> "$T/collect-count"; __real_tree_pids "$@"; }
    bash -c 'trap "" TERM; exec -a "$0" sleep 300' "loa-cmp30-stubborn-$$" 3>&- & p=$!; HOLDER_PIDS+=("$p"); _await_stubborn "$p"
    _ADV_COMPANION_PID=$p; _ADV_COMPANION_START=$(_adv_proc_start "$p")
    LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1 _adv_reap_companion 2>/dev/null
    [ "$(grep -c x "$T/collect-count")" -ge 3 ]   # before STOP, after STOP, before KILL
    sleep 0.3; if kill -0 "$p" 2>/dev/null; then echo "pid $p still alive after reap" >&2; return 1; fi   # (twentieth run, c1c DISS-C-001: errexit-evaluable)
}

@test "CMP-63 a dead run's lock is taken over by ONE of two concurrent takers at a time — the takeover is an atomic rename, never rm + rmdir; a second holder is legitimate only once the first released (eighteenth run, a2 C-001)" {
    _need_flock   # the takeover runs under the per-key flock section: without flock it is refused and the run is unguarded (twenty-third run, c1c DISS-C-002)
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"; [ -d "$lockd" ]
    # a dead holder: a pid above pid_max is never live (thirty-third run, c1b DISS-C-002: 999999 is a legal, often live, pid
    # under the 4194304 pid_max systemd sets — the takeover then ran the recycled-token branch, not the dead-holder one)
    local dead; dead=$(( $(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304) + 1 ))
    if kill -0 "$dead" 2>/dev/null; then echo "pid $dead is live — not a dead holder"; return 1; fi
    printf '%s\n%s\n' "$dead" "Thu Jan  1 00:00:00 1970" > "$lockd/pid"; _ADV_RUN_LOCK_DIR=""
    # (the takers stamp with _now_ms, never GNU-only `date +%s%N` — twentieth run, c1c DISS-C-002)
    for round in 1 2 3; do
        : > "$T/takers"; : > "$T/takers-err"
        ( rc=0; _adv_take_run_lock "$OUT_DIR" review 2>>"$T/takers-err" || rc=$?; echo "rc $BASHPID $rc" >> "$T/takers"; (( rc == 0 )) && { echo "held $BASHPID $(_now_ms)" >> "$T/takers"; sleep 1; echo "released $BASHPID $(_now_ms)" >> "$T/takers"; _adv_release_run_lock; } ) 3>&- &
        p1=$!
        ( rc=0; _adv_take_run_lock "$OUT_DIR" review 2>>"$T/takers-err" || rc=$?; echo "rc $BASHPID $rc" >> "$T/takers"; (( rc == 0 )) && { echo "held $BASHPID $(_now_ms)" >> "$T/takers"; sleep 1; echo "released $BASHPID $(_now_ms)" >> "$T/takers"; _adv_release_run_lock; } ) 3>&- &
        p2=$!
        wait "$p1" "$p2" 2>/dev/null || true
        [ "$(grep -c '^held' "$T/takers")" -ge 1 ]   # the dead lock was taken over
        # the loser is inspected too (twenty-first run, c1c DISS-C-002): both takers ended; one that never held was REFUSED
        # (rc 1, with the in-progress message), never an unguarded run or another failure
        [ "$(grep -c '^rc ' "$T/takers")" = "2" ]
        while read -r _ pid rc; do
            if grep -q "^held $pid " "$T/takers"; then [ "$rc" = "0" ]; else [ "$rc" = "1" ]; fi
        done < <(grep '^rc ' "$T/takers")
        if grep -q '^rc [0-9]* 1$' "$T/takers"; then grep -q 'is in progress (pid [0-9]*)' "$T/takers-err"; fi
        if grep -q 'run lock is not taken' "$T/takers-err"; then cat "$T/takers-err" >&2; false; fi
        # never two holders at once: with two holders, one released before the other acquired
        if [ "$(grep -c '^held' "$T/takers")" = "2" ]; then
            h1=$(awk '$1=="held"{print $3}' "$T/takers" | sort -n | sed -n 2p); r1=$(awk '$1=="released"{print $3}' "$T/takers" | sort -n | sed -n 1p)
            [ "$r1" -le "$h1" ]
        fi
        [ -z "$(ls -d "$lockd".stale.* 2>/dev/null)" ]   # the renamed carcass is gone
        mkdir -p "$lockd"; printf '%s\n%s\n' "$dead" "Thu Jan  1 00:00:00 1970" > "$lockd/pid"   # dead again for the next round
    done
    command rm -f -- "$lockd/pid"; rmdir "$lockd" 2>/dev/null || true
}

@test "CMP-61 past the wait cap a companion in post is never ceded to: on the shared hop the primary waits for the settled record (bounded by the post cap), on another hop it runs its own at once; a result on disk is an answer only when valid and final; a dotted hop matches its own attempts line (eighteenth run, a3 DISS-001 / C-001 / C-002 / C-005)" {
    sleep 60 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID"); _ADV_COMPANION_START=$(_adv_proc_start "$_ADV_COMPANION_PID")
    mkdir -p "$T/vw"; printf 'claude-headless' > "$T/vw/companion.current"; printf 'post' > "$T/vw/companion.phase"; printf '{"findings":[]}' > "$T/vw/companion.result.json"
    # post on OUR hop: the primary waits; the walker then settles (done, final = the hop) → answered with it
    t0=$(_now_ms)   # (sampled before the writer starts, in ms: the wait is bounded from below — twenty-first run, c1c DISS-C-004)
    ( sleep 2; printf 'claude-headless' > "$T/vw/companion.final"; printf 'done' > "$T/vw/companion.phase" ) 3>&- & writer=$!
    [ "$(_adv_shared_hop_verdict claude-headless "$T/vw" "$(( $(date +%s) - 20 ))" 10 60 | cut -f1,2)" = "$(printf 'skip\tanswered_with_it')" ]   # (20 s from the fork: past the wait cap, inside the ceiling)
    (( $(_now_ms) - t0 >= 1900 ))
    wait "$writer" 2>/dev/null || true
    # post on our hop past the POST cap too: run — the caller reaps, then runs
    # (a fresh phase file never makes this leg wait its 5 s post budget out: the global ceiling from the fork — 100 s ago, cap 10
    # + post 5 — has passed, so the verdict is at once: twenty-ninth run, c1b DISS-C-002, refuted and pinned by the bound below)
    printf 'post' > "$T/vw/companion.phase"; rm -f "$T/vw/companion.final"
    t0=$(_now_ms)
    [ "$(_adv_shared_hop_verdict claude-headless "$T/vw" "$(( $(date +%s) - 100 ))" 10 5 | cut -f1,2)" = "$(printf 'run\tpost_budget_expired')" ]
    (( $(_now_ms) - t0 < 3000 )) || { echo "the expired post leg waited $(( $(_now_ms) - t0 )) ms"; return 1; }
    # post on ANOTHER hop: the shared hop is free — run at once, and the token is not a reap
    printf 'opus' > "$T/vw/companion.current"
    [ "$(_adv_shared_hop_verdict claude-headless "$T/vw" "$(( $(date +%s) - 100 ))" 10 60 | cut -f1,2)" = "$(printf 'run\tcompanion_on_other_hop')" ]
    kill "$_ADV_COMPANION_PID" 2>/dev/null; wait "$_ADV_COMPANION_PID" 2>/dev/null || true; _ADV_COMPANION_PID=""
    # settled: a result that is not valid JSON is not an answer — the hop was failed
    printf 'claude-headless' > "$T/vw/companion.final"; printf 'done' > "$T/vw/companion.phase"; printf 'not json' > "$T/vw/companion.result.json"
    printf 'claude-headless:malformed_response\n' > "$T/vw/companion.attempts"
    [ "$(_adv_shared_hop_verdict claude-headless "$T/vw" 0 10 | cut -f1,2)" = "$(printf 'run\tfailed_it')" ]
    # cheval's inner chain answered from the shared hop under another outer hop (nineteenth run, a3 C-004): final says opus, the
    # last vq sidecar says claude-headless — answered with it
    printf 'opus' > "$T/vw/companion.final"; printf '{"findings":[]}' > "$T/vw/companion.result.json"
    printf '{"voices_succeeded_ids":["opus","claude-headless"]}' > "$T/vw/vq-1.json"; printf '%s\n' "$T/vw/vq-1.json" > "$T/vw/companion.vq"
    [ "$(_adv_shared_hop_verdict claude-headless "$T/vw" 0 10 | cut -f1,2)" = "$(printf 'skip\tanswered_with_it')" ]
    rm -f "$T/vw/companion.vq" "$T/vw/vq-1.json" "$T/vw/companion.result.json"
    # a dotted hop, prefixed in the attempts file, is matched as a literal (C-005); a near-miss is not
    printf 'openai:gpt-5.5:api_failure\n' > "$T/vw/companion.attempts"; rm -f "$T/vw/companion.result.json"
    [ "$(_adv_shared_hop_verdict gpt-5.5 "$T/vw" 0 10 | cut -f1,2)" = "$(printf 'run\tfailed_it')" ]
    printf 'gpt-5x5:api_failure\n' > "$T/vw/companion.attempts"
    [ "$(_adv_shared_hop_verdict gpt-5.5 "$T/vw" 0 10 | cut -f1,2)" = "$(printf 'run\tfinished_without_it')" ]
}

@test "CMP-62 the reaper keeps a walker's own record once it reached done even when a tree was signalled, survives a failing helper, and a trap re-entry finishes the kill of the tree already collected (eighteenth run, a3 C-003 / C-004)" {
    mkdir -p "$T/rw"; printf 'quota_exhausted' > "$T/rw/companion.status"; printf 'done' > "$T/rw/companion.phase"; printf '6' > "$T/rw/companion.rc"
    printf 'claude-headless' > "$T/rw/companion.final"; printf '{"findings":[]}' > "$T/rw/companion.result.json"
    sleep 30 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID"); _ADV_COMPANION_START=$(_adv_proc_start "$_ADV_COMPANION_PID")
    local p0=$_ADV_COMPANION_PID
    _adv_reap_companion_timed_out "$T/rw" "claude-headless"
    [ "$(cat "$T/rw/companion.status")" = "quota_exhausted" ]; [ "$(cat "$T/rw/companion.rc")" = "6" ]; [ -s "$T/rw/companion.result.json" ]
    [ -z "${_ADV_COMPANION_PID:-}" ]
    # the pid is cleared, so the EXIT cleanup has nothing left to reap: the tree must really be gone (twenty-seventh run, c1b DISS-C-002)
    sleep 0.3; if kill -0 "$p0" 2>/dev/null; then echo "pid $p0 still alive after the done-walker reap" >&2; return 1; fi
    # a helper that fails mid-reap (the /proc entry vanished) never aborts it under errexit: the tree still goes
    sleep 30 3>&- & p=$!; HOLDER_PIDS+=("$p"); _ADV_COMPANION_PID=$p; _ADV_COMPANION_START=$(_adv_proc_start "$p")
    _orig_proc_start=$(declare -f _adv_proc_start); _adv_proc_start() { return 1; }
    ( set -e; _adv_reap_companion )
    eval "$_orig_proc_start"
    sleep 0.3; if kill -0 "$p" 2>/dev/null; then echo "pid $p still alive after reap" >&2; return 1; fi   # (twentieth run, c1c DISS-C-001: a mid-body `! cmd` is inert under bats)
    _ADV_COMPANION_PID=""
    # a re-entry while a reap is under way (the EXIT trap firing inside the reaper) finishes the kill of the collected tree —
    # even one already frozen by the interrupted reap (nineteenth run, a3 C-002: the tree is published before the freeze)
    # (twenty-eighth run, c1b DISS-C-002: a TERM-ignoring survivor — a re-entry that only TERMed, or a CONT that delivered a pending
    # TERM, would leave it alive; only the reap's KILL ends it)
    bash -c 'trap "" TERM; exec -a "$0" sleep 300' "loa-cmp30-stubborn-$$" 3>&- & q=$!; HOLDER_PIDS+=("$q"); _await_stubborn "$q"; kill -STOP "$q"
    _ADV_COMPANION_PID=$q; _ADV_REAP_IN_PROGRESS="true"; _ADV_REAP_TREE_PIDS="$q"
    _ADV_REAP_TREE_TOKENS="$q=$(_adv_tok_word "$(_adv_proc_start "$q")") "   # (the token the interrupted reap collected: twenty-fifth run, c1b DISS-C-002)
    _adv_reap_companion
    # (twenty-eighth run, c1b DISS-C-002: read BEFORE any CONT of the test's own — a TERM pending on the stopped survivor would be
    # delivered by it, and a TERM-only re-entry would pass; only the reap's KILL ends a process that is still stopped)
    sleep 0.3; if kill -0 "$q" 2>/dev/null; then kill -CONT "$q" 2>/dev/null || true; kill -KILL "$q" 2>/dev/null || true; echo "pid $q still alive after the re-entered reap" >&2; return 1; fi   # (a stopped survivor is resumed and KILLed so the TERM teardown cannot leave it)
    [ -z "${_ADV_COMPANION_PID:-}" ]; [ "$_ADV_REAP_IN_PROGRESS" = "false" ]
    # the re-entered reap KILLs only a pid still the process collected: a pid whose recorded token no longer matches (reused)
    # survives (twenty-fifth run, c1b DISS-C-002)
    sleep 30 3>&- & r=$!; HOLDER_PIDS+=("$r")
    _ADV_COMPANION_PID=$r; _ADV_REAP_IN_PROGRESS="true"; _ADV_REAP_TREE_PIDS="$r"; _ADV_REAP_TREE_TOKENS="$r=not_the_collected_process "
    _adv_reap_companion
    sleep 0.3; kill -0 "$r" 2>/dev/null || { echo "pid $r (a stale token) was killed by the re-entered reap" >&2; return 1; }
    kill -KILL "$r" 2>/dev/null || true
}

@test "CMP-64 a run that aborts before writing its envelope leaves NO envelope at the path — the previous round's envelope and sidecars sit beside it as .prev, never restored — so the skill's fallback rule is a fact it can read; a run that completes drops them (eighteenth run a4 C-001; nineteenth run b2 C-001)" {
    # a previous round: an envelope listing its primary sidecar, which holds one row
    mkdir -p "$OUT_DIR"; printf '{"reject_reason":"earlier","payload":{"title":"x"}}\n' > "$OUT_DIR/adversarial-rejected-review.jsonl"
    jq -n '{findings: [], metadata: {type: "review", model: "m", status: "reviewed", rejected_summary: [{"index":0,"title":"x"}], rejected_sidecars: ["grimoires/loa/a2a/'"$SPRINT"'/adversarial-rejected-review.jsonl"]}}' > "$OUT_DIR/adversarial-review.json"
    prev_env=$(cat "$OUT_DIR/adversarial-review.json")
    # this run aborts after the lock (the shell running main is ended — a session limit, an operator INT)
    BEHAVIOUR[gpt-5.5-pro]=abort-shell
    rc=0; result=$(_run_main review) || rc=$?
    [ "$rc" != "0" ]; [ -z "$result" ]
    [ ! -e "$OUT_DIR/adversarial-review.json" ]                                   # no envelope at the path: "the script left none" is readable
    [ "$(cat "$OUT_DIR/adversarial-review.json.prev")" = "$prev_env" ]           # the previous round's envelope, beside it
    [ "$(cat "$OUT_DIR/adversarial-rejected-review.jsonl.prev")" = '{"reject_reason":"earlier","payload":{"title":"x"}}' ]
    [ ! -e "$OUT_DIR/adversarial-rejected-review.jsonl" ]                         # and no canonical sidecar (this run wrote no rows)
    # the skill's fallback envelope, as the resources say to write it: consistent, and the .prev files count nothing
    jq -n '{findings: [], metadata: {status: "failed", reason: "aborted", rejected_summary: [], rejected_sidecars: []}}' > "$OUT_DIR/adversarial-review.json"
    printf 'All good\n' > "$T/fb.md"
    # (the exit code and the keys are asserted — a usage error or a parse failure carries no violations array either: twenty-second
    # run, c1c DISS-C-003)
    vrc=0; vd=$(bash "$PROJECT_ROOT/.claude/scripts/verdict-derive.sh" --file "$T/fb.md" --gate review --envelope "$OUT_DIR/adversarial-review.json" --json 2>"$T/vd.err") || vrc=$?
    # (2 is a trailer-less file — success without --require-trailer; 1 a violation, and a usage error says so in the object)
    [[ "$vrc" == 0 || "$vrc" == 2 ]] || { echo "verdict-derive exited $vrc: $(cat "$T/vd.err")"; return 1; }
    jq -e '(.usage_error // false) == false and (.violations | type) == "array" and (.violations | length) == 0 and (.warnings | type) == "array" and (.warnings | length) == 0' <<<"$vd" >/dev/null
    # a run that completes drops the previous round's files: only its own are present
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ ! -e "$OUT_DIR/adversarial-review.json.prev" ]; [ ! -e "$OUT_DIR/adversarial-rejected-review.jsonl.prev" ]
    [ "$(jq -r '.metadata.rejected_sidecars | length' <<<"$result")" -le 2 ]
}

@test "CMP-65 one deadline model for the primary's shared-hop wait and main's post-walk wait: a companion queued behind another claude holder keeps its lock bound past the wait cap from the fork, a hop the wait cap, post work the post budget, all under the global ceiling (eighteenth run, a4 C-002)" {
    sleep 60 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID"); _ADV_COMPANION_START=$(_adv_proc_start "$_ADV_COMPANION_PID")
    mkdir -p "$T/dw"; printf 'claude-headless' > "$T/dw/companion.current"
    _adv_cli_hop_bound() { echo 910; }   # (twenty-fourth run, c1c DISS-C-002: the hop bound is a fixture here, never the shipped catalog's timeout)
    now=$(date +%s)
    # queue: the phase clock and the lock's bound (910 + 30 for claude-headless), not the wait cap from the fork
    printf 'queue' > "$T/dw/companion.phase"
    [ -z "$(_companion_deadline_why "$T/dw" $(( now - 100 )) 10 60 940)" ]   # 100 s from the fork, cap 10: still queued within its bound and the ceiling (10 + 940 + 60)
    [[ "$(_companion_deadline_why "$T/dw" $(( now - 2000 )) 10 60 940)" == "global ceiling: 1010s from the fork" ]]
    # hop: the wait cap from the phase start
    _age30() { touch -t "$(printf '%(%Y%m%d%H%M.%S)T' "$(( $(date +%s) - 30 ))")" "$1"; }   # (POSIX touch -t, never GNU `touch -d` — twentieth run, c1c DISS-C-002 — and no python3: twenty-fourth run, c1c DISS-C-001)
    printf 'hop' > "$T/dw/companion.phase"; _age30 "$T/dw/companion.phase"
    [[ "$(_companion_deadline_why "$T/dw" $(( now - 100 )) 10 60 940)" == "phase 'hop' deadline: 10s from the phase start" ]]
    touch "$T/dw/companion.phase"; [ -z "$(_companion_deadline_why "$T/dw" $(( now - 100 )) 60 60 940)" ]
    # post: the post budget from the phase start
    printf 'post' > "$T/dw/companion.phase"; _age30 "$T/dw/companion.phase"
    [[ "$(_companion_deadline_why "$T/dw" $(( now - 100 )) 10 20 940)" == "phase 'post' deadline: 20s from the phase start" ]]
    [ -z "$(_companion_deadline_why "$T/dw" $(( now - 100 )) 10 60 940)" ]
    # in the caller's shell (printf -v) the queue-bound cache holds — one yq per hop (nineteenth run, a3 C-001)
    printf 'queue' > "$T/dw/companion.phase"; _ADV_QB_HOP=""; whyv="x"
    _companion_deadline_why "$T/dw" $(( now - 100 )) 10 60 940 whyv
    [ -z "$whyv" ]; [ "$_ADV_QB_HOP" = "claude-headless" ]; [ "$_ADV_QB_VAL" = "940" ]
    # …and the primary's verdict is that same model: queued past the wait cap from the fork is NOT past_wait_cap
    printf 'queue' > "$T/dw/companion.phase"
    printf 'claude-headless:api_failure\n' > "$T/dw/companion.attempts"
    t0=$(_now_ms)   # (before the ender starts, in ms — twenty-first run, c1c DISS-C-004)
    ( sleep 2; kill "$_ADV_COMPANION_PID" 2>/dev/null ) 3>&- & ender=$!
    [ "$(_adv_shared_hop_verdict claude-headless "$T/dw" $(( $(date +%s) - 100 )) 10 60 940 | cut -f1,2)" = "$(printf 'run\tfailed_it')" ]   # it waited for the companion to end, then read the record
    (( $(_now_ms) - t0 >= 1900 ))
    wait "$ender" 2>/dev/null || true; wait "$_ADV_COMPANION_PID" 2>/dev/null || true; _ADV_COMPANION_PID=""
}

@test "CMP-66 an HTTP hop whose catalog chain reaches a CLI binary queues for that binary's lock before its request: phase queue while it waits, hop once held (nineteenth run, a2 C-001)" {
    _need_flock
    mkdir -m 700 "$T/loa-headless-locks-$(id -u)"
    exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8   # another claude -p holds the binary
    invoke_dissenter() { echo ran >> "$T/lock-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    mkdir -p "$T/ww"; printf 'system' > "$T/ww/system-prompt.txt"; printf 'user' > "$T/ww/user-prompt.txt"
    ( _ADV_LOCK_WAIT=3; _walk_companion_chain "$T/ww" "$T/ww" review "$SPRINT" 30 "" opus >/dev/null 2>&1 ) 3>&- & w=$!
    for _ in $(seq 1 50); do [ "$(cat "$T/ww/companion.phase" 2>/dev/null)" = "queue" ] && break; sleep 0.1; done   # bounded poll (twentieth run, c1c DISS-C-003)
    [ "$(cat "$T/ww/companion.phase")" = "queue" ]   # opus reaches claude in the shipped catalog: it is queueing, not on the hop
    flock -u 8; exec 8>&-
    wait "$w" 2>/dev/null || true
    [ "$(grep -c ran "$T/lock-trace")" = "1" ]   # the lock freed within the wait: the hop ran
    [ "$(cat "$T/ww/companion.phase")" = "done" ]
}

@test "CMP-67 a run-lock holder that is a zombie is dead, as the reaper knows: its lock is taken over (nineteenth run, a2 C-002)" {
    _need_flock   # the takeover runs under the per-key flock section, as CMP-63 says (thirty-third run, c1b DISS-C-001)
    bash -c 'sleep 0.05 & echo $! > "$1/zpid"; exec sleep 30' _ "$T" 3>&- & HOLDER_PIDS+=("$!")
    # a bounded poll, never a fixed wait before a skip: a loaded host must not drop the only zombie-holder check (thirty-fourth run,
    # c1b DISS-C-004)
    local _i; for _i in $(seq 1 50); do [[ -s "$T/zpid" && "$(ps -o stat= -p "$(cat "$T/zpid")" 2>/dev/null)" == Z* ]] && break; sleep 0.1; done
    z=$(cat "$T/zpid")
    [[ "$(ps -o stat= -p "$z" 2>/dev/null)" == Z* ]] || skip "no zombie could be staged on this host"
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"
    printf '%s\n%s\n' "$z" "$(_adv_proc_start "$z")" > "$lockd/pid"; _ADV_RUN_LOCK_DIR=""   # the zombie "holds" it, token and all
    _adv_take_run_lock "$OUT_DIR" review   # taken over, never refused
    [ "$(sed -n 1p "$lockd/pid")" = "$BASHPID" ]
    _adv_release_run_lock
}

@test "CMP-68 the moved-aside file list is one path per line: a directory with a space drops whole paths, and only the .prev copies (nineteenth run, a2 C-003)" {
    d="$T/a dir with spaces"; mkdir -p "$d"
    printf 'r1\n' > "$d/adversarial-rejected-review.jsonl.prev"; printf 'r2\n' > "$d/adversarial-review.json.prev"; printf 'live\n' > "$d/adversarial-rejected-review.jsonl"
    _ADV_PREV_FILES="$d/adversarial-rejected-review.jsonl"$'\n'"$d/adversarial-review.json"
    _adv_prev_files_drop
    [ ! -e "$d/adversarial-rejected-review.jsonl.prev" ]; [ ! -e "$d/adversarial-review.json.prev" ]
    [ "$(cat "$d/adversarial-rejected-review.jsonl")" = "live" ]   # the live file is never touched
    _ADV_PREV_FILES=""
}

@test "CMP-69 the exit cleanup reaps, removes the workdir and releases the run lock LAST — and restores nothing (nineteenth run, a3 C-005 / b2 C-001)" {
    _adv_release_run_lock() { echo release >> "$T/order"; }
    _adv_prev_files_drop() { echo drop >> "$T/order"; }
    _adv_reap_companion() { echo reap >> "$T/order"; }
    # a real workdir is removed, and a moved-aside envelope beside an absent one is left as it is — nothing is restored
    # (twenty-first run, c1c DISS-C-005: both halves of the title observed, not implied)
    # (the probe reads the path this test made — a cleanup that blanks the global before releasing would pass a probe of the
    # global vacuously: twenty-ninth run, c1b DISS-C-001)
    _adv_release_run_lock() { [ -d "$_cmp69_wd" ] && echo release-before-rm >> "$T/order" || echo release >> "$T/order"; }
    mkdir -p "$OUT_DIR"; printf 'prev' > "$OUT_DIR/adversarial-review.json.prev"; rm -f "$OUT_DIR/adversarial-review.json"
    _ADVERSARIAL_WORKDIR=$(mktemp -d "$T/wd.XXXXXX"); printf x > "$_ADVERSARIAL_WORKDIR/f"; _cmp69_wd=$_ADVERSARIAL_WORKDIR
    : > "$T/order"; _ADV_ENVELOPE_WRITTEN="false"
    ( _adv_cleanup_on_exit; echo returned >> "$T/order" )   # (twenty-fourth run, c1c DISS-C-003: an exit inside the handler ends the test green — bats passes an exit 0 — so it runs in a subshell whose sentinel proves it returned)
    [ "$(tr '\n' ' ' < "$T/order")" = "reap release returned " ]
    [ ! -d "$_cmp69_wd" ]
    [ "$(cat "$OUT_DIR/adversarial-review.json.prev")" = "prev" ]; [ ! -e "$OUT_DIR/adversarial-review.json" ]
    _ADVERSARIAL_WORKDIR=$(mktemp -d "$T/wd.XXXXXX"); printf x > "$_ADVERSARIAL_WORKDIR/f"; _cmp69_wd=$_ADVERSARIAL_WORKDIR
    : > "$T/order"; _ADV_ENVELOPE_WRITTEN="true"
    ( _adv_cleanup_on_exit; echo returned >> "$T/order" )
    [ "$(tr '\n' ' ' < "$T/order")" = "reap release returned " ]
    [ ! -d "$_cmp69_wd" ]
    [ "$(cat "$OUT_DIR/adversarial-review.json.prev")" = "prev" ]; [ ! -e "$OUT_DIR/adversarial-review.json" ]
}

@test "CMP-71 a start token that cannot be read at the fork never aborts main: the pid alone keeps the companion in view, its answer is folded, the review completes (nineteenth run, a4 C-001; title per the twenty-second run, c1c DISS-C-002)" {
    _orig_proc_start=$(declare -f _adv_proc_start); _adv_proc_start() { return 1; }
    result=$(_run_main review)
    eval "$_orig_proc_start"
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]   # never an abort: the walk and the envelope stand
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]   # the pid alone keeps the companion in view — its answer is folded
    [ "$(jq '.findings | length' <<<"$result")" = "2" ]
    [ "$(grep -c "unbound variable" "$T/stderr.log")" = "0" ]
}

@test "CMP-73 lib-content's log fallback never writes into prepare_content's payload: a caller without a log FUNCTION gets the message on stderr (nineteenth run, b1 C-004)" {
    printf 'big.sh\n' > "$T/reviewignore"
    # an over-budget diff (the scope filter and the early return live on the truncation path) whose only file is out of scope
    over=$'diff --git a/big.sh b/big.sh\n--- a/big.sh\n+++ b/big.sh\n@@ -1 +1,80 @@\n-a\n'"$(for i in $(seq 1 80); do printf '+line %d of a change large enough to exceed the token budget by a wide margin\n' "$i"; done)"
    out=$(REVIEWIGNORE_FILE="$T/reviewignore" bash -c 'source "$1/.claude/scripts/lib-content.sh"; prepare_content "$2" 150' _ "$PROJECT_ROOT" "$over" 2>"$T/lc-err")
    [ -z "$out" ]                                                     # the empty payload the early return promises — not a stray log line
    grep -q "Review scope excluded every file of the diff" "$T/lc-err"
    [ "$(grep -c '>&2' "$T/lc-err")" = "0" ]
}

@test "CMP-74 the fold decides 'ceded' from the companion's ANSWERING id, as the shared-hop verdict does: an outer hop whose inner chain answered from the ceded hop is a cede, not an exhausted primary (twentieth run, a3 DISS-C-001)" {
    wd="$T/fold-ans"; mkdir -p "$wd"
    p='{"findings":[],"metadata":{"type":"review","status":"api_failure","model":"gpt-5.5-pro","cost_usd":0,"tokens_input":0,"tokens_output":0,"rejected_summary":[],"rejected_count":0}}'
    jq -nc '{findings:[{id:"DISS-001",severity:"LOW",category:"other",description:"from the companion.",failure_mode:"fm"}],metadata:{type:"review",status:"reviewed",model:"claude-headless",cost_usd:0.02,tokens_input:1,tokens_output:1,rejected_summary:[],rejected_count:0}}' > "$wd/companion.result.json"
    printf 'opus' > "$wd/companion.final"; printf 'opus:reviewed\n' > "$wd/companion.attempts"; printf 'reviewed' > "$wd/companion.status"; printf '0' > "$wd/companion.rc"
    printf '{"voices_succeeded_ids":["claude-headless"]}' > "$wd/vq-companion-1.json"; printf '%s\n' "$wd/vq-companion-1.json" > "$wd/companion.vq"
    out=$(_fold_companion "$p" "$wd" anthropic "opus" codex-headless "" "claude-headless" "" "claude-headless" 2>"$T/fold-ans-err")
    [ "$(jq -r '.metadata.primary_voice.status' <<<"$out")" = "ceded" ]
    [ "$(jq -r '.metadata.degraded' <<<"$out")" = "false" ]
}

@test "CMP-75 a partial view never displaces a row of a higher or the same tier that fits whole, sits at its own tier's place, and its PARTIAL marker is charged to the budget (twentieth run, b1 DISS-001 / DISS-C-001)" {
    mk_hunk() { printf '@@ -%d,3 +%d,4 @@ fn%d\n context\n-old line %d\n+new line %d %s\n+another line %d\n' "$1" "$1" "$1" "$1" "$1" "$(printf 'x%.0s' $(seq 1 200))" "$1"; }
    mk_file() { printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@\n-a\n+%s\n' "$1" "$1" "$1" "$1" "$(printf 'q%.0s' $(seq 1 "$2"))"; }
    bigpy="diff --git a/big.py b/big.py
--- a/big.py
+++ b/big.py
$(mk_hunk 10)
$(mk_hunk 40)
$(mk_hunk 70)
$(mk_hunk 100)"
    bigsh=$(printf '%s' "$bigpy" | sed 's/big\.py/big.sh/g')
    # (a) a P0 script worth 0.73 of the budget ahead of a large P1 file: the script is reviewed whole, the P1 file after it
    a=$(mk_file a.sh 600)
    out=$(prepare_content "$a
$bigpy" 300 2>/dev/null)
    [[ "$out" == "diff --git a/a.sh b/a.sh"* ]]
    [[ "$out" != *"P0: a.sh"* ]]
    [[ "$out" == *"--- PARTIAL: big.py"* ]]
    # …worth 0.9 of it, no room is left for even the marker: the P1 file is listed as omitted (twenty-first run, b1 DISS-001 —
    # this case used to pin a marker-only block that ran the payload past the budget)
    a=$(mk_file a.sh 740)
    out=$(prepare_content "$a
$bigpy" 300 2>/dev/null)
    [[ "$out" == "diff --git a/a.sh b/a.sh"* ]]
    [[ "$out" != *"P0: a.sh"* ]]
    [[ "$out" != *"--- PARTIAL:"* ]]
    [[ "$out" == *"P1: big.py"* ]]
    # (b) the same tier: a P0 sibling worth 0.8 of the budget stays whole beside the partial view
    a=$(mk_file a.sh 650)
    out=$(prepare_content "$bigsh
$a" 300 2>/dev/null)
    [[ "$out" == *"diff --git a/a.sh b/a.sh"* ]]
    [[ "$out" != *"P0: a.sh"* ]]
    [[ "$out" == *"--- PARTIAL: big.sh"* ]]
    # (c) the marker is charged: the payload before the TRUNCATED list never exceeds the budget, whatever a doc's size
    local n payload
    for n in 30 60 90 120 150 180 210 240 270 300; do
        out=$(prepare_content "$bigsh
$(mk_file d.md "$n")" 300 2>/dev/null)
        payload=$(printf '%s' "$out" | sed '/^--- TRUNCATED:/,$d')
        [ "$(estimate_tokens "$payload")" -le 300 ] || { echo "doc of $n bytes: payload $(estimate_tokens "$payload") tokens > 300"; false; }
    done
}

@test "CMP-76 a hop is charged by what it can reach, one rule for the repair budget and the post budget: an HTTP hop whose chain falls through to a CLI pays its lock wait, its timeout and the CLI bound; a bound that is not a number never zeroes the charge (twentieth run, a1 DISS-C-001 / a3 DISS-C-003)" {
    _adv_cli_bin_for() { case "$1" in plain-x|claude-headless) echo claude ;; *) echo "" ;; esac; }
    _adv_cli_hop_bound() { echo 700; }
    [ "$(_adv_hop_charge plain-x 60)" = "820" ]
    [ "$(_adv_hop_charge plain-y 60)" = "60" ]
    [ "$(_adv_hop_charge claude-headless 60)" = "760" ]   # its lock wait too: the repair waits up to the timeout for the CLI lock (twenty-third run, a2 DISS-C-001)
    [ "$(LOA_ADVERSARIAL_REPAIR_MODEL=plain-x _companion_post_budget m 60)" = "$(( 820 * 2 + 60 + 820 + 60 ))" ]   # the wall budget plus the hop (twenty-ninth run, a3 DISS-C-001)
    # (twenty-first run, c1c DISS-C-003: digits that differ from the 610 fallback, so a stripped suffix cannot pass)
    _adv_cli_hop_bound() { echo 905s; }
    [ "$(_adv_hop_charge claude-headless 60)" = "670" ]
    [ "$(_adv_hop_charge plain-x 60)" = "730" ]
    _adv_cli_hop_bound() { echo 0x2bc; }
    [ "$(_adv_hop_charge claude-headless 60)" = "670" ]
    _adv_cli_hop_bound() { echo ""; }
    [ "$(LOA_ADVERSARIAL_REPAIR_MODEL=claude-headless _companion_post_budget m 60)" = "$(( 670 * 2 + 60 + 670 + 60 ))" ]
    # the repair loop: a hop that reaches the CLI is not started against a budget its CLI bound exceeds
    _adv_cli_hop_bound() { echo 700; }
    _repair_finding_via_model() { echo "$4" >> "$T/repair-calls"; return 1; }
    : > "$T/repair-calls"; CONF_TIMEOUT=60
    raw=$(jq -nc '{content: "{\"findings\":[{\"title\":\"t\",\"category\":\"other\",\"description\":\"No severity.\"}]}"}')
    result=$(LOA_ADVERSARIAL_REPAIR_MODEL=plain-x LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=200 process_findings "$raw" review m "$SPRINT" 0 "" 2>/dev/null)
    [ ! -s "$T/repair-calls" ]
    jq -e '.metadata.repair_hops_skipped | index("plain-x:over_budget") != null' <<<"$result" >/dev/null
    [ "$(jq '.metadata.repair_budget_exhausted' <<<"$result")" = "1" ]
}

@test "CMP-77 a pinned repair chain is filtered by this run's retired hops like the default chain, and a payload no hop was started for without a budget skip is repair_skipped_no_hop, never a budget exhaustion (twentieth run, a1 DISS-C-002)" {
    _ADV_REPAIR_DEAD_HOPS="plain-y"
    [ -z "$(LOA_ADVERSARIAL_REPAIR_MODEL=plain-y _repair_model_chain m)" ]
    [ "$(LOA_ADVERSARIAL_REPAIR_MODEL='plain-y plain-z' _repair_model_chain m)" = "plain-z" ]
    _repair_finding_via_model() { echo "$4" >> "$T/repair-calls"; return 1; }
    : > "$T/repair-calls"
    raw=$(jq -nc '{content: "{\"findings\":[{\"title\":\"t\",\"category\":\"other\",\"description\":\"No severity.\"}]}"}')
    result=$(LOA_ADVERSARIAL_REPAIR_MODEL=plain-y process_findings "$raw" review m "$SPRINT" 0 "" 2>/dev/null)
    [ ! -s "$T/repair-calls" ]
    [ "$(jq '.metadata.repair_budget_exhausted' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.repair_skipped_no_hop' <<<"$result")" = "1" ]
    # the shared-hop skip of a pinned hop is the same outcome
    _ADV_REPAIR_DEAD_HOPS=""
    _adv_repair_hop_shared_now() { [[ "$1" == plain-y ]]; }
    result=$(LOA_ADVERSARIAL_REPAIR_MODEL=plain-y process_findings "$raw" review m "$SPRINT" 0 "" 2>/dev/null)
    [ ! -s "$T/repair-calls" ]
    [ "$(jq '.metadata.repair_budget_exhausted' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.repair_skipped_no_hop' <<<"$result")" = "1" ]
}

@test "CMP-78 the companion walker survives a failing post-hop helper under errexit: the hop is malformed_response and the walk records done (twentieth run, a2 DISS-C-001)" {
    mkdir -p "$T/wk"; printf 's' > "$T/wk/system-prompt.txt"; printf 'u' > "$T/wk/user-prompt.txt"
    invoke_dissenter() { echo '{"content":"{\"findings\":[]}"}'; }
    process_findings() { return 5; }
    # a background job, as main launches the walker: errexit is live there (inside `( … ) || true` it would be ignored)
    ( set -e; _walk_companion_chain "$T/wk" "$T/wk" review "$SPRINT" 30 "" plain-x plain-y ) >/dev/null 2>&1 3>&- &
    wait "$!" || true
    [ "$(cat "$T/wk/companion.phase")" = "done" ]
    [ "$(cat "$T/wk/companion.status")" = "malformed_response" ]
    [ "$(tr '\n' ' ' < "$T/wk/companion.attempts")" = "plain-x:malformed_response plain-y:malformed_response " ]
}

@test "CMP-79 the MODELINV lookup skips a torn ledger line instead of stopping at it, and a fractional-second row in the hop's first second is inside the window (twentieth run, a2 DISS-C-002)" {
    row() { jq -nc --arg ts "$1" --arg msg "$2" '{event_type:"model.invoke.complete", ts_utc:$ts, payload:{models_requested:["anthropic:claude-headless"], calling_primitive:"adversarial-review", models_failed:[{model:"anthropic:claude-headless", message_redacted:$msg}]}}'; }
    # (twenty-first run, c1c DISS-C-001: the truncating writes below go to the test's own scratch ledger, asserted, not assumed)
    [[ -n "$T" && "$LOA_MODELINV_LOG_PATH" == "$T/"* ]]
    { row 2026-10-01T10:00:00Z older; printf '{"torn": \n'; row 2026-10-01T10:00:05.123Z mine; } > "$LOA_MODELINV_LOG_PATH"
    [ "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05Z 2026-10-01T10:00:09Z)" = "mine" ]
    { row 2026-10-01T10:00:09.500Z late-in-last-second; } > "$LOA_MODELINV_LOG_PATH"
    [ "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05Z 2026-10-01T10:00:09Z)" = "late-in-last-second" ]
}

@test "CMP-80 a companion hop whose CLI lock was never acquired is class lock_wait, not a model timeout: the request was never sent (twentieth run, a2 DISS-C-003)" {
    _need_flock
    mkdir -m 700 "$T/loa-headless-locks-$(id -u)"
    exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8   # another claude -p holds the binary for longer than the wait
    invoke_dissenter() { echo ran >> "$T/lw-trace"; echo '{"content":"{\"findings\":[]}"}'; }
    mkdir -p "$T/ww"; printf 's' > "$T/ww/system-prompt.txt"; printf 'u' > "$T/ww/user-prompt.txt"
    ( _ADV_LOCK_WAIT=1; _walk_companion_chain "$T/ww" "$T/ww" review "$SPRINT" 30 "" opus ) >/dev/null 2>&1 3>&- || true
    flock -u 8; exec 8>&-
    [ ! -e "$T/lw-trace" ]
    [ "$(cat "$T/ww/companion.status")" = "lock_wait" ]
    [ "$(cat "$T/ww/companion.rc")" = "124" ]
    [ "$(_companion_failure_class lock_wait 124 "")" = "lock_wait" ]
    [ "$(_companion_drop_reason lock_wait)" = "Other" ]
}

@test "CMP-81 in post the shared-hop verdict reads the answering id too: an outer hop whose inner chain answered from the shared hop is waited for, then skipped (twentieth run, a3 DISS-C-002)" {
    wd="$T/sh"; mkdir -p "$wd"
    sleep 30 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID"); _ADV_COMPANION_START=$(_adv_proc_start "$_ADV_COMPANION_PID")
    printf 'post' > "$wd/companion.phase"; printf 'opus' > "$wd/companion.current"
    printf '{"voices_succeeded_ids":["claude-headless"]}' > "$wd/vq1.json"; printf '%s\n' "$wd/vq1.json" > "$wd/companion.vq"
    ( sleep 1.5; printf '{"findings":[]}' > "$wd/companion.result.json"; printf 'opus' > "$wd/companion.final"; printf 'done' > "$wd/companion.phase" ) 3>&- &
    out=$(_adv_shared_hop_verdict claude-headless "$wd" "$(date +%s)" 600 600)
    [ "$(cut -f2 <<<"$out")" = "answered_with_it" ]
    kill "$_ADV_COMPANION_PID" 2>/dev/null || true; _ADV_COMPANION_PID=""
}

@test "CMP-82 the reaper KILLs a pid only while it is still the process it collected: a pid whose start token changed during the grace is left alone (twentieth run, a3 DISS-C-004)" {
    sleep 30 3>&- & p=$!; HOLDER_PIDS+=("$p"); tok=$(_adv_proc_start "$p")
    _adv_kill_same "$p" "$p=bogus"; sleep 0.2; _adv_pid_alive "$p"
    _adv_kill_same "$p" "$p=-"; sleep 0.2; _adv_pid_alive "$p"
    _adv_kill_same "$p" "$p=$tok"; sleep 0.3; if _adv_pid_alive "$p"; then false; fi
    sleep 30 3>&- & q=$!; HOLDER_PIDS+=("$q")
    _adv_kill_same "$q" ""; sleep 0.3; if _adv_pid_alive "$q"; then false; fi   # (no token recorded — unreadable at collection: the pid alone, as before)
    # the whole reap: the root's identity changes after the TERM (a reuse inside the grace window) — no KILL
    eval "__real_kill_tree() $(declare -f _adv_kill_tree | sed '1d')"
    _adv_kill_tree() { __real_kill_tree "$@"; : > "$T/reused"; }
    _adv_proc_start() { if [[ -e "$T/reused" ]]; then echo t2; else echo t1; fi; }
    bash -c 'trap "" TERM; exec -a "$0" sleep 300' "loa-cmp30-stubborn-$$" 3>&- & r=$!; HOLDER_PIDS+=("$r"); _await_stubborn "$r"
    _ADV_COMPANION_PID=$r; _ADV_COMPANION_START=t1
    LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1 _adv_reap_companion 2>/dev/null
    _adv_pid_alive "$r"
    kill -KILL "$r"
}

@test "CMP-83 the INV-5 rewrite compares canonical names: a dropped entry recorded with a provider prefix is removed for its bare id (twentieth run, a3 DISS-C-005)" {
    printf '%s' '{"voices_planned":3,"voices_succeeded":1,"voices_dropped":[{"voice":"anthropic:claude-headless","reason":"Other"},{"voice":"gpt-5.5","reason":"Other"}]}' > "$T/e.json"
    _adv_inv5_rewrite "$T/e.json" "claude-headless" "$T/o.json"
    [ "$(jq -c '[.voices_dropped[].voice]' "$T/o.json")" = '["gpt-5.5"]' ]
    [ "$(jq '.voices_planned' "$T/o.json")" = "2" ]
    _adv_inv5_rewrite "$T/e.json" "openai:gpt-5.5 claude-headless" "$T/o2.json"
    [ "$(jq -c '.voices_dropped' "$T/o2.json")" = '[]' ]
    [ "$(jq '.voices_planned' "$T/o2.json")" = "1" ]
}

@test "CMP-84 an empty prepared payload is never dispatched: status nothing_to_review, exit 1, before the run lock and the move-aside — the previous envelope stays where it is (twentieth run, b1 DISS-C-002)" {
    mkdir -p "$OUT_DIR"; printf '{"prev":true}' > "$OUT_DIR/adversarial-review.json"
    prepare_content() { :; }
    run _run_main review
    [ "$status" -eq 1 ]
    [ "$(jq -r '.metadata.status' <<<"$output")" = "nothing_to_review" ]
    [ ! -s "$CALLS" ]
    [ "$(cat "$OUT_DIR/adversarial-review.json")" = '{"prev":true}' ]
    [ ! -e "$OUT_DIR/adversarial-review.json.prev" ]
}

@test "CMP-85 a partial view that kept no hunk says so: no 'cut mid-way', no hunk claimed (twentieth run, b1 DISS-C-003)" {
    big="diff --git a/big.sh b/big.sh
--- a/big.sh
+++ b/big.sh
@@ -1,3 +1,4 @@ $(printf 'h%.0s' $(seq 1 2400))
 context
+new"
    out=$(prepare_content "$big" 300 2>/dev/null)
    [[ "$out" == *"--- PARTIAL: big.sh: no hunk fit within the token budget (0 of 1 hunks shown; token budget: 300) — split the diff for a full review ---"* ]]
    [[ "$out" != *"cut mid-way"* ]]
    [[ "$out" != *"hhhhhhhh"* ]]
}

@test "CMP-86 a timeout line that carries cheval's headless-timeout note still classifies as timeout (twentieth run, d DISS-C-001)" {
    [ "$(_companion_failure_class "" 1 "[cheval] PROVIDER_UNAVAILABLE: Provider 'anthropic' unavailable: claude -p timed out after 610s (catalog headless_timeout_seconds '15m' ignored: not a positive finite number of seconds)")" = "timeout" ]
    [ "$(_companion_failure_class "" 1 "claude -p timed out after 3600s (headless_timeout_seconds 4500 clamped to 3600s)")" = "timeout" ]
}

@test "CMP-87 a partial view with no room for even its marker beside the rows of its tier that fit is not made: the sibling that fits is shown whole, the large file is listed as omitted, the payload stays within the budget (twenty-first run, b1 DISS-001)" {
    mk_hunk() { printf '@@ -%d,3 +%d,4 @@ fn%d\n context\n-old line %d\n+new line %d %s\n+another line %d\n' "$1" "$1" "$1" "$1" "$1" "$(printf 'x%.0s' $(seq 1 200))" "$1"; }
    mk_file() { printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@\n-a\n+%s\n' "$1" "$1" "$1" "$1" "$(printf 'q%.0s' $(seq 1 "$2"))"; }
    bigsh="diff --git a/big.sh b/big.sh
--- a/big.sh
+++ b/big.sh
$(mk_hunk 10)
$(mk_hunk 40)
$(mk_hunk 70)
$(mk_hunk 100)"
    # a P0 sibling worth 0.92 of the budget: no room is left for the marker, so no PARTIAL block displaces it
    out=$(prepare_content "$bigsh
$(mk_file a.sh 780)" 300 2>/dev/null)
    [[ "$out" == *"diff --git a/a.sh b/a.sh"* ]]
    [[ "$out" != *"P0: a.sh"* ]]
    [[ "$out" != *"--- PARTIAL:"* ]]
    [[ "$out" == *"P0: big.sh"* ]]
    # whatever the sibling's size: a sibling that fits is never displaced, the large file is never silently lost, the budget holds
    local n a payload
    for n in 600 640 680 700 720 740 760 780 800 820 840 860; do
        a=$(mk_file a.sh "$n")
        out=$(prepare_content "$bigsh
$a" 300 2>/dev/null)
        if (( $(estimate_tokens "$a") <= 300 )); then
            [[ "$out" == *"diff --git a/a.sh b/a.sh"* && "$out" != *"P0: a.sh"* ]] || { echo "a.sh of $n bytes fits but was displaced"; false; }
        fi
        [[ "$out" == *"--- PARTIAL: big.sh"* || "$out" == *"P0: big.sh"* ]] || { echo "a.sh of $n bytes: big.sh neither partial nor listed"; false; }
        payload=$(printf '%s' "$out" | sed '/^--- TRUNCATED:/,$d')
        [ "$(estimate_tokens "$payload")" -le 300 ] || { echo "a.sh of $n bytes: payload $(estimate_tokens "$payload") tokens > 300"; false; }
    done
    # across tiers: a P0 row that fits ahead of a large P1 file — the marker-only block ran the payload to 313..340 tokens here
    local bigpy; bigpy=$(printf '%s' "$bigsh" | sed 's/big\.sh/big.py/g')
    for n in 700 740 780 820; do
        out=$(prepare_content "$(mk_file a.sh "$n")
$bigpy" 300 2>/dev/null)
        payload=$(printf '%s' "$out" | sed '/^--- TRUNCATED:/,$d')
        [ "$(estimate_tokens "$payload")" -le 300 ] || { echo "P0 a.sh of $n bytes + P1 big.py: payload $(estimate_tokens "$payload") tokens > 300"; false; }
        [[ "$out" == *"--- PARTIAL: big.py"* || "$out" == *"P1: big.py"* ]]
    done
}

@test "CMP-88 _lc_hunk_count returns status 0 with no hunk header, called as a plain statement under errexit and inside a substitution with inherit_errexit (twenty-first run, b1 DISS-C-001)" {
    run bash -c 'set -e; source "$1"; _lc_hunk_count "no header here"; echo; shopt -s inherit_errexit; c=$(_lc_hunk_count "plain"); echo "c=$c"' _ "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"c=0"* ]]
    [ "$(_lc_hunk_count $'@@ -1 +1 @@\n-a\n+b\n@@ -5 +5 @@\n x')" = "2" ]
}

@test "CMP-89 the partial-view candidate is the first row that does not fit what the rows before it leave, not only a row larger than the whole budget: a P0 file is never dropped whole while a P1 file is shown (twenty-first run, b1 DISS-C-002)" {
    mk_hunk() { printf '@@ -%d,3 +%d,4 @@ fn%d\n context\n-old line %d\n+new line %d %s\n+another line %d\n' "$1" "$1" "$1" "$1" "$1" "$(printf 'x%.0s' $(seq 1 200))" "$1"; }
    mk_file() { printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@\n-a\n+%s\n' "$1" "$1" "$1" "$1" "$(printf 'q%.0s' $(seq 1 "$2"))"; }
    # a.sh (P0, ~111 tokens) + big.sh (P0, ~294 tokens: fits the budget alone, not beside a.sh) + c.py (P1, ~61 tokens), budget 300
    bigsh="diff --git a/big.sh b/big.sh
--- a/big.sh
+++ b/big.sh
$(mk_hunk 10)
$(mk_hunk 40)
$(mk_hunk 70)"
    [ "$(estimate_tokens "$bigsh")" -le 300 ]
    out=$(prepare_content "$(mk_file a.sh 270)
$bigsh
$(mk_file c.py 120)" 300 2>/dev/null)
    [[ "$out" == "diff --git a/a.sh b/a.sh"* ]]
    [[ "$out" == *"--- PARTIAL: big.sh"* ]]
    [[ "$out" != *"P0: big.sh"* ]]
    payload=$(printf '%s' "$out" | sed '/^--- TRUNCATED:/,$d')
    [ "$(estimate_tokens "$payload")" -le 300 ]
}

@test "CMP-90 the repair's shared-hop check never pairs one hop's name with the next hop's phase: current is re-read after phase, and a pair that moved under the read is read again (twenty-first run, a1 DISS-C-001)" {
    companion_workdir="$T/cw"; mkdir -p "$companion_workdir"
    _adv_companion_alive() { return 0; }
    printf 'post' > "$companion_workdir/companion.phase"; printf 'hop-a' > "$companion_workdir/companion.current"
    # the walker moves from hop-a (post) to hop-b (queue) between the first read of current and the read of phase
    cat() {   # (the real one through command — a test-local path is unbound in teardown: thirty-sixth run, c1b DISS-C-001)
        if [[ "${1:-}" == "$companion_workdir/companion.current" && ! -e "$T/moved" ]]; then
            command cat "$@"; : > "$T/moved"; printf 'hop-b' > "$companion_workdir/companion.current"; printf 'queue' > "$companion_workdir/companion.phase"; return 0
        fi
        command cat "$@"
    }
    _ADV_REPAIR_SKIP_FILE="$T/skips"; : > "$_ADV_REPAIR_SKIP_FILE"
    if _adv_repair_hop_shared_now hop-a answering-x; then echo "hop-a was called shared from hop-b's phase"; return 1; fi
    [ ! -s "$_ADV_REPAIR_SKIP_FILE" ]
    _adv_repair_hop_shared_now hop-b answering-x
    grep -qxF 'hop-b:shared_with_companion' "$_ADV_REPAIR_SKIP_FILE"
}

@test "CMP-91 a pinned repair budget below a hop's charge is said once when it is read, and the hop's over-budget line once per hop, not once per payload (twenty-first run, a1 DISS-C-002)" {
    _adv_cli_bin_for() { case "$1" in plain-x|claude-headless) echo claude ;; *) echo "" ;; esac; }
    _adv_cli_hop_bound() { echo 700; }
    _repair_finding_via_model() { echo "$4" >> "$T/repair-calls"; return 1; }
    : > "$T/repair-calls"; CONF_TIMEOUT=60
    raw=$(jq -nc '{content: "{\"findings\":[{\"title\":\"a\",\"category\":\"other\",\"description\":\"No severity.\"},{\"title\":\"b\",\"category\":\"other\",\"description\":\"No severity.\"},{\"title\":\"c\",\"category\":\"other\",\"description\":\"No severity.\"}]}"}')
    result=$(LOA_ADVERSARIAL_REPAIR_MODEL=plain-x LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=200 process_findings "$raw" review m "$SPRINT" 0 "" 2>"$T/pin-err")
    [ "$(jq '.metadata.repair_budget_exhausted' <<<"$result")" = "3" ]
    [ "$(grep -c "LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=200 is below the charge of repair hop plain-x (820s)" "$T/pin-err")" = "1" ]
    [ "$(grep -c "Repair hop plain-x needs up to" "$T/pin-err")" = "1" ]
    # a pin that admits every hop says nothing
    result=$(LOA_ADVERSARIAL_REPAIR_MODEL=plain-y LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=200 process_findings "$raw" review m "$SPRINT" 0 "" 2>"$T/pin-err")
    if grep -q "is below the charge of repair hop" "$T/pin-err"; then echo "a pin that admits plain-y was flagged"; return 1; fi
}

@test "CMP-92 an explicit id the model supplies twice is renumbered on its second use: every finding in the envelope has its own id, the first keeps the model's (twenty-first run, a1 DISS-C-003)" {
    doc='{"findings":[{"id":"DISS-001","severity":"HIGH","category":"config","description":"First one.","failure_mode":"stated"},{"id":"DISS-001","severity":"LOW","category":"other","description":"Second one.","failure_mode":"stated"},{"id":"DISS-002","severity":"LOW","category":"other","description":"Third one.","failure_mode":"stated"}]}'
    raw=$(jq -nc --arg c "$doc" '{content: $c}')
    result=$(process_findings "$raw" audit m "$SPRINT" 0 "" 2>"$T/dup-err")
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq '[.findings[].id] | unique | length' <<<"$result")" = "3" ]
    [ "$(jq -r '.findings[] | select(.description == "First one.") | .id' <<<"$result")" = "DISS-001" ]
    [ "$(jq -r '.findings[] | select(.description == "Third one.") | .id' <<<"$result")" = "DISS-002" ]
    [ "$(jq -r '.findings[] | select(.description == "Second one.") | .id_derived' <<<"$result")" = "true" ]
    grep -q "duplicate explicit id DISS-001" "$T/dup-err"
}

@test "CMP-93 the run lock fails open on a lock directory that is not ours, and on no hash tool — never a refusal, and said once per run (twenty-first run, a2 DISS-C-001 / c1b DISS-C-004)" {
    local lockdir; lockdir=$(_adv_cli_lock_dir)
    # the symlink is planted and removed only under this test's directory — never at the per-user lock dir a live dissent
    # holds, should the suite's redirect ever regress (twenty-third run, c1c DISS-C-003)
    [[ -n "$T" && "$lockdir" == "$T/"* ]] || { echo "the CLI lock dir $lockdir is not under the test directory"; return 1; }
    mkdir -p "$T/elsewhere"; ln -s "$T/elsewhere" "$lockdir"
    _ADV_RUN_LOCK_DIR=""; unset _ADV_RUN_LOCK_WARNED
    _adv_take_run_lock "$OUT_DIR" review 2>"$T/rl-err"
    _adv_take_run_lock "$OUT_DIR" review 2>>"$T/rl-err"
    [ -z "$_ADV_RUN_LOCK_DIR" ]
    [ -z "$(ls -A "$T/elsewhere")" ]   # (nothing created through the symlink)
    [ "$(grep -c "run lock is not taken — the lock directory $lockdir is a symlink or not owned by this user" "$T/rl-err")" = "1" ]
    rm -f "$lockdir"
    # no hash tool to name the lock
    sha256sum() { return 1; }; shasum() { return 1; }
    unset _ADV_RUN_LOCK_WARNED
    _adv_take_run_lock "$OUT_DIR" review 2>"$T/rl-err"
    [ -z "$_ADV_RUN_LOCK_DIR" ]
    grep -q "run lock is not taken — no sha256sum or shasum to name the lock" "$T/rl-err"
    unset -f sha256sum shasum
    # a lock directory that IS ours: taken, nothing said
    unset _ADV_RUN_LOCK_WARNED
    _adv_take_run_lock "$OUT_DIR" review 2>"$T/rl-err"
    [ -n "$_ADV_RUN_LOCK_DIR" ]   # (two statements: a failed `[ ]` before `&&` never trips errexit — twenty-second run, c1c DISS-C-001)
    [ -d "$_ADV_RUN_LOCK_DIR" ]
    if grep -q "run lock is not taken" "$T/rl-err"; then echo "an owned lock directory was reported unguarded"; return 1; fi
    _adv_release_run_lock
}

@test "CMP-94 the MODELINV lookup tolerates a row of another shape — a non-string models_requested element, a non-object models_failed element — and returns 0 under errexit and pipefail (twenty-first run, a2 DISS-C-002)" {
    [[ -n "$T" && "$LOA_MODELINV_LOG_PATH" == "$T/"* ]]
    {
        jq -nc '{event_type:"model.invoke.complete", ts_utc:"2026-10-01T10:00:01Z", payload:{models_requested:[1, {"a":2}, "anthropic:claude-headless"], models_failed:["a string", 3, {message_redacted:"odd-row"}]}}'
        jq -nc '{event_type:"model.invoke.complete", ts_utc:"2026-10-01T10:00:02Z", payload:{models_requested:"claude-headless", models_failed:{message_redacted:"x"}}}'
        jq -nc '{event_type:"model.invoke.complete", ts_utc:"2026-10-01T10:00:03Z", payload:{models_requested:["anthropic:claude-headless"], calling_primitive:"adversarial-review", models_failed:[{message_redacted:"mine"}]}}'
        jq -nc '{event_type:"model.invoke.complete", ts_utc:"2026-10-01T10:00:04Z", payload:{models_requested:[null], models_failed:[[1]]}}'
    } > "$LOA_MODELINV_LOG_PATH"
    set -o pipefail
    local out rc=0
    out=$(_companion_ledger_message claude-headless 2026-10-01T10:00:00Z 2026-10-01T10:00:09Z) || rc=$?
    [ "$rc" = "0" ]
    [ "$out" = "mine" ]
}

@test "CMP-95 a companion hop starts with no end time: the previous hop's hop_ended_iso is cleared, so a hop reaped mid-flight is seen as such and its MODELINV window is never inverted (twenty-first run, a3 DISS-C-001)" {
    mkdir -p "$T/wk"; printf 's' > "$T/wk/system-prompt.txt"; printf 'u' > "$T/wk/user-prompt.txt"
    invoke_dissenter() { if [[ -e "$T/wk/companion.hop_ended_iso" ]]; then echo "stale" >> "$T/he-trace"; else echo "fresh" >> "$T/he-trace"; fi; echo '{"content":"{\"findings\":[]}"}'; }
    process_findings() { return 5; }
    ( _walk_companion_chain "$T/wk" "$T/wk" review "$SPRINT" 30 "" plain-x plain-y ) >/dev/null 2>&1 3>&- || true
    [ "$(tr '\n' ' ' < "$T/he-trace")" = "fresh fresh " ]
    [ -s "$T/wk/companion.hop_ended_iso" ]   # (the last hop that ended still records its end)
}

@test "CMP-96 a companion hop whose CLI lock was never acquired is recorded lock_wait in companion.attempts too — the attempts row and the failure class agree, on a non-final hop as well (twenty-first run, a3 DISS-C-005)" {
    _need_flock
    mkdir -m 700 "$T/loa-headless-locks-$(id -u)"
    exec 8>>"$T/loa-headless-locks-$(id -u)/claude.lock"; flock 8
    invoke_dissenter() { echo '{"content":"{\"findings\":[]}"}'; }
    process_findings() { return 5; }
    mkdir -p "$T/ww"; printf 's' > "$T/ww/system-prompt.txt"; printf 'u' > "$T/ww/user-prompt.txt"
    ( _ADV_LOCK_WAIT=1; _walk_companion_chain "$T/ww" "$T/ww" review "$SPRINT" 30 "" opus plain-y ) >/dev/null 2>&1 3>&- || true
    flock -u 8; exec 8>&-
    [ "$(sed -n 1p "$T/ww/companion.attempts")" = "opus:lock_wait" ]
    [ "$(sed -n 2p "$T/ww/companion.attempts")" = "plain-y:malformed_response" ]
}

@test "CMP-97 a start token from the ps lstart fallback carries no whitespace: a pid=token map entry stays one word, and the reaper's same-process check still KILLs the process it collected (twenty-first run, a3 DISS-C-002)" {
    ps() { if [[ "$*" == *lstart* ]]; then echo "  Wed Oct  1 10:00:00 2026  "; else command ps "$@"; fi; }
    tok=$(_adv_lstart_token 12345)
    [ "$tok" = "Wed_Oct_1_10:00:00_2026" ]
    unset -f ps
    # the reaper side holds even for a token that does carry whitespace: the map entry is one word, read back whole
    sleep 30 3>&- & s=$!; HOLDER_PIDS+=("$s")
    _adv_proc_start() { echo "Wed Oct  1 10:00:00 2026"; }
    [[ "$(_adv_pid_tokens "$s")" == "$s=Wed_Oct_1_10:00:00_2026 " ]]
    _adv_kill_same "$s" "$(_adv_pid_tokens "$s")"
    sleep 0.2
    if kill -0 "$s" 2>/dev/null; then echo "the collected process was not killed"; return 1; fi
    wait "$s" 2>/dev/null || true
}

@test "CMP-98 a companion that died and was not yet waited for (a zombie) is not alive: the shared-hop wait and the repair skip use the reaper's liveness rule (twenty-first run, a3 DISS-C-003)" {
    bash -c 'sleep 0.1 3>&- & echo $! > "$1"; exec sleep 30' _ "$T/zpid" 3>&- & parent=$!; HOLDER_PIDS+=("$parent")
    local i; for i in $(seq 1 50); do [[ -s "$T/zpid" ]] && [[ "$(ps -o stat= -p "$(cat "$T/zpid")" 2>/dev/null)" == Z* ]] && break; sleep 0.1; done
    z=$(cat "$T/zpid"); [[ "$(ps -o stat= -p "$z" 2>/dev/null)" == Z* ]]
    kill -0 "$z"   # (the premise: kill -0 answers for a zombie)
    _ADV_COMPANION_PID="$z"; _ADV_COMPANION_START=""
    if _adv_companion_alive; then echo "a zombie companion was judged alive"; return 1; fi
    # (twenty-eighth run, c1c DISS-C-001: and on the normal path — a fork-time token that is present and matches; a zombie keeps a
    # readable /proc/<pid>/stat, so this is the leg a token-path regression that trusts kill -0 would turn red)
    _ADV_COMPANION_START=$(_adv_proc_start "$z"); [ -n "$_ADV_COMPANION_START" ]
    if _adv_companion_alive; then echo "a zombie companion with a matching token was judged alive"; return 1; fi
    # a live companion still is
    _ADV_COMPANION_PID="$parent"; _ADV_COMPANION_START=$(_adv_proc_start "$parent")
    _adv_companion_alive
    _ADV_COMPANION_PID=""
    kill "$parent" 2>/dev/null || true; wait "$parent" 2>/dev/null || true
}

@test "CMP-99 the fold survives its redactor under errexit and pipefail: a redactor that fails withholds the diagnostic (never the raw line), one that writes many lines gives its first (twenty-first run, a3 DISS-C-004)" {
    wd="$T/rf"; mkdir -p "$wd"
    printf 'claude-headless' > "$wd/companion.final"; printf 'api_failure' > "$wd/companion.status"; printf '1' > "$wd/companion.rc"
    printf 'done' > "$wd/companion.phase"; : > "$wd/companion.attempts"; : > "$wd/companion.vq"
    printf 'boom: RAWLINE-%s\n' 7 > "$wd/companion.log"
    printf '#!/bin/sh\ncat\nexit 3\n' > "$T/redact-fail"; chmod +x "$T/redact-fail"
    printf '#!/bin/sh\nsed s/RAWLINE/CLEAN/\nyes extra | head -n 200000\n' > "$T/redact-many"; chmod +x "$T/redact-many"
    set -o pipefail
    local out rc=0
    out=$(_ADV_REDACTOR_BIN="$T/redact-fail" _fold_companion '{"findings":[],"metadata":{}}' "$wd" anthropic claude-headless gpt-5.5-pro gpt-5.5-pro 2>"$T/rf-err") || rc=$?
    [ "$rc" = "0" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$out")" = "failed" ]
    grep -q "Companion voice diagnostic (claude-headless): \[diagnostic withheld: the redactor failed\]" "$T/rf-err"
    if grep -q "RAWLINE" "$T/rf-err"; then echo "the unredacted line reached stderr"; return 1; fi
    out=$(_ADV_REDACTOR_BIN="$T/redact-many" _fold_companion '{"findings":[],"metadata":{}}' "$wd" anthropic claude-headless gpt-5.5-pro gpt-5.5-pro 2>"$T/rf-err") || rc=$?
    [ "$rc" = "0" ]
    grep -q "Companion voice diagnostic (claude-headless): boom: CLEAN-7" "$T/rf-err"
}

@test "CMP-100 a trap that re-enters the reaper before the tree was collected still KILLs the companion it forked — the bare pid and its fork-time token are published first — and never a pid whose token changed (twenty-first run, a3 DISS-C-006)" {
    sleep 30 3>&- & s=$!; HOLDER_PIDS+=("$s")
    # the re-entry lands at the very start of the inner reap, before any probe ran
    _adv_reap_companion_inner() { _adv_reap_companion; }
    _ADV_COMPANION_PID="$s"; _ADV_COMPANION_START=$(_adv_proc_start "$s"); _ADV_REAP_IN_PROGRESS="false"
    _adv_reap_companion
    sleep 0.2
    if kill -0 "$s" 2>/dev/null; then echo "the re-entered reaper signalled nothing"; return 1; fi
    wait "$s" 2>/dev/null || true
    [ -z "$_ADV_COMPANION_PID" ]
    # a fork-time token that no longer matches: the pid is another process, left alone
    sleep 30 3>&- & s=$!; HOLDER_PIDS+=("$s")
    _ADV_COMPANION_PID="$s"; _ADV_COMPANION_START="t1"; _ADV_REAP_IN_PROGRESS="false"
    _adv_reap_companion
    kill -0 "$s"
    kill "$s"; wait "$s" 2>/dev/null || true
}

@test "CMP-101 the global ceiling's queue allowance counts each *-headless hop's queue at the bound its queue phase uses; an HTTP hop whose chain reaches a CLI adds nothing — its lock wait is already the first timeout of its wait-cap share (twenty-first run, a4 DISS-C-001; re-pinned by the twenty-second run, a2 DISS-C-002)" {
    _adv_cli_bin_for() { case "$1" in plain-x|claude-headless) echo claude ;; *) echo "" ;; esac; }
    _adv_cli_hop_bound() { echo 700; }
    [ "$(_companion_queue_allowance claude-headless)" = "730" ]
    [ "$(_companion_queue_allowance plain-x claude-headless)" = "730" ]
    [ "$(_companion_queue_allowance plain-x)" = "0" ]
    [ "$(_companion_queue_allowance plain-y)" = "0" ]
    [ "$(_companion_queue_allowance anthropic:claude-headless)" = "730" ]   # (canonical: a prefixed CLI hop is the CLI hop)
    _adv_cli_hop_bound() { echo 10m; }   # (a bound that is not a number: the adapter's default, as the queue phase reads it)
    [ "$(_companion_queue_allowance claude-headless)" = "640" ]
}

@test "CMP-102 main's INT and TERM traps exit 130 / 143 even when the reaper fails under errexit (twenty-first run, a4 DISS-C-002)" {
    local sig code tr
    # (twenty-eighth run, c1c DISS-C-003: TERM first — it needs no default-signal reset — so a host that must skip the INT leg
    # still runs it; bats' skip ends the test)
    for sig in TERM:143 INT:130; do
        code="${sig#*:}"; sig="${sig%%:*}"
        tr=$(grep -E "^[[:space:]]*trap [\"'].*_adv_reap_companion.*[\"'] ${sig}\$" "$ADVERSARIAL_REVIEW" | sed -E "s/^[[:space:]]*trap [\"'](.*)[\"'] ${sig}\$/\\1/")   # (either quote: the twenty-fourth run's masking trap is double-quoted)
        [ -n "$tr" ]
        # a shell started as an async job inherits SIGINT ignored, and a non-interactive bash cannot trap a signal ignored at
        # entry (run 23: the detached regression read this as a red) — the probe shell gets the default disposition back
        local pre=(); env --default-signal=INT true 2>/dev/null && pre=(env --default-signal=INT)
        if [[ "$sig" == INT && ${#pre[@]} -eq 0 && -n "$(bash -c 'trap -p INT')" ]]; then skip "SIGINT is ignored here and env --default-signal is unavailable (the TERM leg ran)"; fi
        run "${pre[@]}" bash -c 'set -e; _adv_reap_primary() { return 1; }; _adv_reap_companion() { return 1; }; trap "$1" "$2"; kill -"$2" $$; sleep 2; exit 0' _ "$tr" "$sig"
        [ "$status" -eq "$code" ] || { echo "$sig trap '$tr' exited $status, not $code"; false; }
    done
}

@test "CMP-103 a companion that failed AND a fold that failed still leave verdict quality planning two voices with the companion dropped — the synthetic FAILED envelope the fold never wrote (twenty-first run, a4 DISS-C-003)" {
    _fold_companion() { echo "not json at all"; }
    BEHAVIOUR[claude-headless]=errlog
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "fold_failed" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    [ "$(jq -r '.verdict_quality.voices_succeeded_ids | join(",")' <<<"$result")" = "gpt-5.5-pro" ]
    [ "$(jq -c '[.verdict_quality.voices_dropped[] | {voice, reason}]' <<<"$result")" = '[{"voice":"claude-headless","reason":"Other"}]' ]
}

@test "CMP-104 the room a partial view leaves to the rows at or above its tier is what those rows can take TOGETHER — two siblings that each fit but not beside each other never reserve the budget twice (twenty-second run, b1 DISS-C-001)" {
    mk_hunk() { printf '@@ -%d,3 +%d,4 @@ fn%d\n context\n-old line %d\n+new line %d %s\n+another line %d\n' "$1" "$1" "$1" "$1" "$1" "$(printf 'x%.0s' $(seq 1 200))" "$1"; }
    mk_file() { printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@\n-a\n+%s\n' "$1" "$1" "$1" "$1" "$(printf 'q%.0s' $(seq 1 "$2"))"; }
    big="diff --git a/big.sh b/big.sh
--- a/big.sh
+++ b/big.sh
$(mk_hunk 10)
$(mk_hunk 40)
$(mk_hunk 70)
$(mk_hunk 100)"
    a=$(mk_file a.sh 380); s=$(mk_file s.sh 470)
    [ "$(estimate_tokens "$a")" -lt 160 ]   # each fits alone; a + s overflow 300 (two statements: errexit never sees a failed `[ ]` before `&&`)
    [ "$(estimate_tokens "$s")" -gt 150 ]
    out=$(prepare_content "$a
$big
$s" 300 2>/dev/null)
    [[ "$out" == "diff --git a/a.sh b/a.sh"* ]]
    [[ "$out" != *"P0: a.sh"* ]]
    [[ "$out" == *"--- PARTIAL: big.sh"* ]]
    payload=$(printf '%s' "$out" | sed '/^--- TRUNCATED:/,$d')
    [ "$(estimate_tokens "$payload")" -le 300 ]
}

@test "CMP-105 a companion_chain family written as a scalar or a map — or a companion_chain that is not a map — is SAID, never read silently as an empty chain (twenty-second run, a1 DISS-C-001)" {
    _cfg_edit $'  code_review:\n    enabled: true\n' $'  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: claude-headless\n      openai: {first: codex-headless}\n'
    result=$(_run_main review)
    grep -q 'WARN: flatline_protocol.code_review.companion_chain.anthropic is a !!str, not a list' "$T/stderr.log"
    grep -q 'WARN: flatline_protocol.code_review.companion_chain.openai is a !!map, not a list' "$T/stderr.log"
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]   # the default chain applies
    _cfg_edit $'    companion_chain:\n      anthropic: claude-headless\n      openai: {first: codex-headless}\n' $'    companion_chain: claude-headless\n'
    ( _run_main review ) >/dev/null || true
    grep -q 'WARN: flatline_protocol.code_review.companion_chain is a !!str, not a map of family lists' "$T/stderr.log"
    # a list is read silently, as before
    _cfg_edit $'    companion_chain: claude-headless\n' $'    companion_chain:\n      anthropic: [claude-headless]\n'
    ( _run_main review ) >/dev/null || true
    if grep 'companion_chain' "$T/stderr.log" | grep -q 'WARN'; then return 1; fi
}

@test "CMP-106 only a safe token is an explicit id: an id with whitespace, a newline or a control character is renumbered id_derived and never logged raw, and it never renumbers the safe id it would split into (twenty-second run, a1 DISS-C-003)" {
    doc=$(jq -nc '{findings: [
      {id: "x DISS-002", severity: "HIGH", category: "config", description: "Spaced.", failure_mode: "stated"},
      {id: "A\nB", severity: "LOW", category: "other", description: "Newlined.", failure_mode: "stated"},
      {id: "DISS-007\n", severity: "LOW", category: "other", description: "Trailing.", failure_mode: "stated"},
      {id: "ok\u0007", severity: "LOW", category: "other", description: "Bell.", failure_mode: "stated"},
      {id: "DISS-002", severity: "LOW", category: "other", description: "Safe.", failure_mode: "stated"}]}')
    raw=$(jq -nc --arg c "$doc" '{content: $c}')
    result=$(process_findings "$raw" audit m "$SPRINT" 0 "" 2>"$T/tok-err")
    [ "$(jq '.findings | length' <<<"$result")" = "5" ]
    [ "$(jq '[.findings[].id] | unique | length' <<<"$result")" = "5" ]
    [ "$(jq -r '.findings[] | select(.description == "Safe.") | .id' <<<"$result")" = "DISS-002" ]
    [ "$(jq '[.findings[] | select(.description != "Safe.") | .id_derived] | all' <<<"$result")" = "true" ]
    [ "$(jq '[.findings[].id | test("\\A[A-Za-z0-9._:-]{1,64}\\z")] | all' <<<"$result")" = "true" ]
    grep -q "not a safe token" "$T/tok-err"
    if grep -q 'x DISS-002' "$T/tok-err"; then return 1; fi
}

@test "CMP-107 a takeover whose per-key flock times out still judges the holder — a LIVE holder refuses the run — never takes a lock over without the flock, and a dead holder behind the busy section refuses too (twenty-second run, a2 DISS-C-001; twenty-third run, c1c DISS-C-004)" {
    printf '#!/bin/sh\nexit 1\n' > "$T/flock-busy"; chmod +x "$T/flock-busy"   # (flock -w 5 that times out: another taker holds the section)
    sleep 60 3>&- & holder=$!; HOLDER_PIDS+=("$holder")
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"; [ -d "$lockd" ]
    printf '%s\n%s\n' "$holder" "$(_adv_proc_start "$holder")" > "$lockd/pid"; _ADV_RUN_LOCK_DIR=""
    rc=0; ( _ADV_FLOCK_BIN="$T/flock-busy"; _adv_take_run_lock "$OUT_DIR" review ) 2>"$T/busy.err" || rc=$?
    [ "$rc" = "1" ]; grep -q "is in progress (pid $holder)" "$T/busy.err"
    [ "$(sed -n 1p "$lockd/pid")" = "$holder" ]
    # a dead holder behind a busy section: not taken over without the flock, and the run is REFUSED — a section another taker holds
    # is a live taker about to become the holder, never an absence to run unguarded beside (twenty-third run, c1c DISS-C-004)
    kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null || true
    rc=0; ( _ADV_FLOCK_BIN="$T/flock-busy"; _adv_take_run_lock "$OUT_DIR" review ) 2>"$T/busy.err" || rc=$?
    [ "$rc" = "1" ]; grep -q "another taker holds the takeover of a dead run's lock" "$T/busy.err"
    if grep -q "run lock is not taken" "$T/busy.err"; then echo "a busy takeover section ran unguarded"; return 1; fi
    [ "$(sed -n 1p "$lockd/pid")" = "$holder" ]
    command rm -f -- "$lockd/pid"; rmdir "$lockd"
}

@test "CMP-108 the companion's pid is published to the reaper before main forks anything else — a signal in the next command's fork window still reaps it (twenty-second run, a4 DISS-C-001)" {
    # the first `date` main runs once it holds the companion's pid is the next fork after the companion's: the reaper must already see it
    date() { if [[ -n "${companion_pid:-}" && ! -e "$T/pid-probe" ]]; then printf '%s|%s\n' "$companion_pid" "${_ADV_COMPANION_PID:-unset}" > "$T/pid-probe"; fi; command date "$@"; }
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ]
    [ -s "$T/pid-probe" ]
    IFS='|' read -r forked published < "$T/pid-probe"
    [ "$published" = "$forked" ]
}

@test "CMP-109 the reaper takes each pid's token while the tree is frozen — a descendant found by the second collection is never tokenised after TERM, when its pid may be free (twenty-second run, a4 DISS-C-002)" {
    # kill_tree's tokens mode: pid=token pairs of the frozen tree, the tree signalled as before
    bash -c 'sleep 30 & wait' 3>&- & s=$!; HOLDER_PIDS+=("$s")
    _await_tree "$s" 2
    want="$s=$(_adv_tok_word "$(_adv_proc_start "$s")")"
    out=$(_adv_kill_tree "$s" TERM tokens)
    grep -qx "$want" <<<"$out" || { echo "no frozen token for the root ($want): $out"; return 1; }
    [ "$(grep -c '=' <<<"$out")" -ge 2 ]
    sleep 0.3; if kill -0 "$s" 2>/dev/null; then echo "the tree was not signalled"; return 1; fi
    wait "$s" 2>/dev/null || true
    # the inner reap uses those pairs: a pid only the frozen collection saw carries the token taken while frozen
    sleep 30 3>&- & s=$!; HOLDER_PIDS+=("$s")
    _adv_kill_tree() { printf '%s=%s\n' "$1" "$(_adv_tok_word "$(_adv_proc_start "$1")")" 999999 tFROZEN; kill "$1"; }
    _ADV_COMPANION_PID="$s"; _ADV_COMPANION_START=$(_adv_proc_start "$s"); LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1
    _adv_reap_companion_inner "$s"
    [[ " $_ADV_REAP_TREE_TOKENS" == *" 999999=tFROZEN "* ]] || { echo "tokens: $_ADV_REAP_TREE_TOKENS"; return 1; }
    [[ " $_ADV_REAP_TREE_PIDS " == *" 999999 "* ]]
    [[ "$_ADV_REAP_TREE_TOKENS" != *"tFROZEN="* ]]
    wait "$s" 2>/dev/null || true
}

@test "CMP-110 a second INT or TERM that lands while the EXIT trap cleans up never exits from inside it — the workdir is removed and the run lock released (twenty-second run, a4 DISS-C-004)" {
    local sig
    for sig in TERM INT; do
        # a detached run inherits SIGINT ignored, which a non-interactive bash cannot trap: the INT leg would pass whatever the
        # cleanup masks — a visible skip, never a vacuous pass (twenty-seventh run, c1c DISS-C-003; the regression driver runs
        # bats under env --default-signal=INT, so it is exercised there)
        if [[ "$sig" == INT && -n "$(bash -c 'trap -p INT')" ]]; then skip "SIGINT is ignored here: the INT leg cannot be delivered (the TERM leg ran)"; fi
        command rm -f -- "$T/once"; mkdir -p "$T/wd-$sig"
        ( _ADVERSARIAL_WORKDIR="$T/wd-$sig"
          _adv_take_run_lock "$OUT_DIR" review
          printf '%s' "$_ADV_RUN_LOCK_DIR" > "$T/lockdir"
          trap '_adv_cleanup_on_exit' EXIT
          trap '_adv_reap_companion || true; exit 130' INT
          trap '_adv_reap_companion || true; exit 143' TERM
          _adv_reap_companion() { [[ -e "$T/once" ]] && return 0; : > "$T/once"; kill -"$sig" "$BASHPID"; sleep 0.3; return 0; }
          exit 0 ) 3>&- || true
        [ -e "$T/once" ]
        [ ! -d "$T/wd-$sig" ] || { echo "$sig: the workdir survived the cleanup"; return 1; }
        [ ! -d "$(cat "$T/lockdir")" ] || { echo "$sig: the run lock survived the cleanup"; return 1; }
    done
}

@test "CMP-111 a companion_chain family written as a map is ignored as the WARN says: its values never become hops — the default chain is walked (twenty-third run, a1 DISS-C-001)" {
    _cfg_edit $'  code_review:\n    enabled: true\n' $'  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: {first: bogus-hop-a}\n      openai: {first: bogus-hop-o}\n'
    result=$(_run_main review)
    grep -q 'companion_chain.anthropic is a !!map, not a list' "$T/stderr.log"
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    chain=$(jq -r '.metadata.companion_voice.chain | if type == "array" then join(",") else . end' <<<"$result")
    # (an absent chain prints `null` — non-empty, no bogus hop — so the walk is asserted, not implied: twenty-ninth run, c1c DISS-C-001)
    jq -e '.metadata.companion_voice.chain | type == "array" and length > 0' <<<"$result" >/dev/null || { echo "no chain recorded: $chain"; return 1; }
    [ -n "$chain" ]; [ "$chain" != null ]
    if [[ "$chain" == *bogus-hop* ]]; then return 1; fi
}


@test "CMP-112 an unreadable hop name in post is not 'another hop': the primary keeps waiting instead of running the shared hop the companion may be moving onto, and the walker publishes its hop and phase whole (twenty-third run, a3 DISS-C-001)" {
    sleep 60 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID"); _ADV_COMPANION_START=$(_adv_proc_start "$_ADV_COMPANION_PID")
    mkdir -p "$T/vw"; : > "$T/vw/companion.current"; printf 'post' > "$T/vw/companion.phase"
    # an empty current (a truncating write caught mid-way) with no answering id: wait, then the walker publishes its next hop
    t0=$(_now_ms)
    ( sleep 2; printf 'opus' > "$T/vw/companion.current" ) 3>&- & writer=$!
    [ "$(_adv_shared_hop_verdict claude-headless "$T/vw" "$(( $(date +%s) - 20 ))" 10 60 | cut -f1,2)" = "$(printf 'run\tcompanion_on_other_hop')" ]   # (inside the post deadline)
    (( $(_now_ms) - t0 >= 1900 ))   # it waited for a readable name
    wait "$writer" 2>/dev/null || true
    kill "$_ADV_COMPANION_PID" 2>/dev/null; wait "$_ADV_COMPANION_PID" 2>/dev/null || true; _ADV_COMPANION_PID=""
    # the walker's hop/phase writes are atomic (a temp file renamed over the target), never a truncate-then-write
    body=$(declare -f _walk_companion_chain)
    if grep -qE "> \"\\\$workdir/companion\.(current|phase)\"" <<<"$body"; then return 1; fi
    if declare -f _adv_invoke_hop | grep -qE "> \"\\\$_ADV_PHASE_FILE\""; then return 1; fi
    _adv_put_state "$T/vw/companion.phase" queue; [ "$(cat "$T/vw/companion.phase")" = "queue" ]
    [ -z "$(find "$T/vw" -name '*.tmp*')" ]
}

@test "CMP-113 an errno diagnostic survives the allowlisted summary: [Errno 7] Argument list too long and E2BIG reach last_error, and a long upper-case token with digits (an access-key shape) still does not (twenty-third run, a3 DISS-C-002)" {
    out=$(_adv_error_summary "[cheval] PROVIDER_UNAVAILABLE: Provider 'anthropic' unavailable: [Errno 7] Argument list too long: 'claude'")
    [[ "$out" == *"PROVIDER_UNAVAILABLE"* ]]
    [[ "$out" == *"[Errno 7] Argument list too long"* ]]
    out=$(_adv_error_summary "OSError: E2BIG from execve")
    [[ "$out" == *"E2BIG"* ]]
    out=$(_adv_error_summary "key AKIAIOSFODNN7EXAMPLE leaked E2BIG")
    [[ "$out" != *"AKIA"* ]]
    [[ "$out" == *"E2BIG"* ]]
}

@test "CMP-114 a TERM sent to the run while a primary hop is in flight ends it at once — exit 143, the hop's tree reaped — never only once the hop returns (twenty-third run, a4 DISS-C-001)" {
    BEHAVIOUR[gpt-5.5-pro]=sleeper
    local mp start rc=0 i=0
    ( _run_main review ) >/dev/null 3>&- &
    mp=$!; HOLDER_PIDS+=("$mp")   # (registered at once, and the reclaim bounded: twenty-seventh run, c1c DISS-C-004)
    while [[ ! -s "$T/sleeper.pid" ]] && (( i++ < 300 )); do sleep 0.05; done
    [ -s "$T/sleeper.pid" ]
    HOLDER_PIDS+=("$(cat "$T/sleeper.pid")")
    start=$SECONDS; kill -TERM "$mp"
    i=0; while kill -0 "$mp" 2>/dev/null && (( i++ < 300 )); do sleep 0.05; done
    if kill -0 "$mp" 2>/dev/null; then kill -KILL "$mp" 2>/dev/null || true; echo "the run outlived its TERM by 15 s (it waits for the hop)"; return 1; fi
    wait "$mp" || rc=$?
    [ "$rc" -eq 143 ]
    (( SECONDS - start < 12 )) || { echo "the run waited $(( SECONDS - start )) s for the hop"; return 1; }
    if kill -0 "$(cat "$T/sleeper.pid")" 2>/dev/null; then echo "the primary hop survived the run"; return 1; fi
}

@test "CMP-115 a reap re-entered while only the companion's root pid is published still KILLs its descendants — the root is verified, then its tree goes (twenty-third run, a4 DISS-C-002)" {
    bash -c 'sleep 60 & sleep 60 & wait' 3>&- & local root=$!; HOLDER_PIDS+=("$root")
    local i=0 kids
    while (( $(pgrep -P "$root" | wc -l) < 2 && i++ < 100 )); do sleep 0.05; done
    kids=$(pgrep -P "$root" | tr '\n' ' '); HOLDER_PIDS+=($kids)
    [ "$(wc -w <<<"$kids")" -eq 2 ]
    _ADV_COMPANION_PID="$root"; _ADV_COMPANION_START=$(_adv_proc_start "$root")
    _ADV_REAP_TREE_PIDS="$root"; _ADV_REAP_TREE_TOKENS="$root=$(_adv_tok_word "$_ADV_COMPANION_START") "; _ADV_REAP_IN_PROGRESS="true"
    _adv_reap_companion
    sleep 0.3
    local k; for k in $kids; do if _adv_pid_alive "$k"; then echo "descendant $k survived the re-entered reap"; return 1; fi; done
    # a root whose token no longer matches is not this run's companion: nothing is signalled (the re-entered branch reads the
    # frozen tree token only, never _ADV_COMPANION_START — dropping its check turns this leg red: twenty-ninth run, c1c DISS-C-002)
    bash -c 'sleep 60 & wait' 3>&- & root=$!; HOLDER_PIDS+=("$root")
    i=0; while (( $(pgrep -P "$root" | wc -l) < 1 && i++ < 100 )); do sleep 0.05; done
    kids=$(pgrep -P "$root" | tr '\n' ' '); HOLDER_PIDS+=($kids)
    _ADV_COMPANION_PID="$root"; _ADV_REAP_TREE_PIDS="$root"; _ADV_REAP_TREE_TOKENS="$root=not-this-process "; _ADV_REAP_IN_PROGRESS="true"
    _adv_reap_companion
    sleep 0.2
    _adv_pid_alive "$root"
    for k in $kids; do _adv_pid_alive "$k"; done
}

@test "CMP-116 the EXIT cleanup runs to its end under errexit when a reaper returns non-zero — the workdir is removed and the run lock released (twenty-third run, a4 DISS-C-003)" {
    mkdir -p "$T/wd"
    ( set -e
      _ADVERSARIAL_WORKDIR="$T/wd"
      _adv_take_run_lock "$OUT_DIR" review
      printf '%s' "$_ADV_RUN_LOCK_DIR" > "$T/lockdir"
      _adv_reap_companion() { return 1; }
      _adv_reap_primary() { return 1; }
      _adv_cleanup_on_exit ) 3>&- &   # (a job, not `( … ) || true`: the `||` would switch errexit off inside the subshell)
    wait "$!" || true
    [ -s "$T/lockdir" ]
    [ ! -d "$T/wd" ] || { echo "the workdir survived the cleanup"; return 1; }
    [ ! -d "$(cat "$T/lockdir")" ] || { echo "the run lock survived the cleanup"; return 1; }
}

@test "CMP-117 a byte cut that lands exactly on a hunk boundary keeps the hunk it completes — before or after that hunk's last newline; a cut inside the next header still drops only the incomplete hunk (twenty-third run, b1 DISS-C-001)" {
    printf 'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+b\n@@ -5 +5 @@\n-c\n+d\n@@ -9 +9 @@\n-e\n+f\n' > "$T/chunk"
    local one two how
    one=$(printf 'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+b\n' | wc -c)
    two=$(printf 'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+b\n@@ -5 +5 @@\n-c\n+d\n' | wc -c)
    local n
    for n in "$one" $(( one - 1 )); do
        how=$(_lc_cut_partial "$T/chunk" "$n" "$T/part")
        [ "$how" = hunk ] || { echo "cut at $n: $how"; return 1; }
        [ "$(_lc_hunk_count "$(cat "$T/part")")" -eq 1 ]
        [[ "$(cat "$T/part")" == *$'\n+b' ]]
    done
    for n in "$two" $(( two - 1 )); do
        how=$(_lc_cut_partial "$T/chunk" "$n" "$T/part")
        [ "$how" = hunk ]
        [ "$(_lc_hunk_count "$(cat "$T/part")")" -eq 2 ] || { echo "cut at $n kept $(_lc_hunk_count "$(cat "$T/part")")"; return 1; }
    done
    # a cut two bytes into hunk 3's header: hunk 3 is dropped, hunks 1 and 2 stay
    how=$(_lc_cut_partial "$T/chunk" $(( two + 2 )) "$T/part")
    [ "$how" = hunk ]
    [ "$(_lc_hunk_count "$(cat "$T/part")")" -eq 2 ]
    # a cut inside hunk 1's last line is still mid-way (the only hunk is incomplete)
    how=$(_lc_cut_partial "$T/chunk" $(( one - 2 )) "$T/part")
    [ "$how" = mid ]
}

@test "CMP-118 a top-priority file dropped for want of room for a partial view is named as such in the TRUNCATED footer — never counted among 'lower-priority' files; a plain truncation keeps its wording (twenty-third run, b1 DISS-C-002)" {
    mk_hunk() { printf '@@ -%d,3 +%d,4 @@ fn%d\n context\n-old line %d\n+new line %d %s\n+another line %d\n' "$1" "$1" "$1" "$1" "$1" "$(printf 'x%.0s' $(seq 1 200))" "$1"; }
    mk_file() { printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1 +1 @@\n-a\n+%s\n' "$1" "$1" "$1" "$1" "$(printf 'q%.0s' $(seq 1 "$2"))"; }
    bigsh="diff --git a/big.sh b/big.sh
--- a/big.sh
+++ b/big.sh
$(mk_hunk 10)
$(mk_hunk 40)
$(mk_hunk 70)
$(mk_hunk 100)"
    out=$(prepare_content "$bigsh
$(mk_file a.sh 780)" 300 2>/dev/null)
    [[ "$out" != *"--- PARTIAL:"* ]]
    [[ "$out" == *"P0: big.sh"* ]]
    local foot; foot=$(grep '^--- TRUNCATED:' <<<"$out")
    [[ "$foot" != *"lower-priority"* ]] || { echo "footer: $foot"; return 1; }
    [[ "$foot" == *"big.sh"*"no room for a partial view"* ]]
    # control: a P2 doc dropped behind a P0 file that fits keeps the lower-priority wording
    out=$(prepare_content "$(mk_file a.sh 780)
$(mk_file README.md 780)" 300 2>/dev/null)
    foot=$(grep '^--- TRUNCATED:' <<<"$out")
    [[ "$foot" == *"lower-priority file(s) omitted"* ]] || { echo "control footer: $foot"; return 1; }
}

@test "CMP-119 --record-fallback writes the skill's failed-run record under the run lock: a pre-lock refusal moves the previous envelope and sidecars aside, an aborted run's record never overwrites a standing envelope, a live run is refused (twenty-third run, b2 DISS-C-001)" {
    mkdir -p "$OUT_DIR"
    local env="$OUT_DIR/adversarial-review.json" sc="$OUT_DIR/adversarial-rejected-review.jsonl" rc
    printf '{"findings":[],"metadata":{"status":"reviewed","rejected_summary":[{"id":"x"}]}}\n' > "$env"
    printf '{"row":1}\n' > "$sc"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback nothing_to_review --reason "nothing to review: the diff prepared to no content" ) >"$T/out" 2>"$T/err" || rc=$?
    [ "$rc" -eq 0 ] || { cat "$T/err"; return 1; }
    [ "$(jq -r '.metadata.status' "$env")" = "nothing_to_review" ]
    [ "$(jq -r '.metadata.reason' "$env")" = "nothing to review: the diff prepared to no content" ]
    [ "$(jq -c '[.findings, .metadata.rejected_summary, .metadata.rejected_sidecars]' "$env")" = "[[],[],[]]" ]
    [ "$(jq -r '.metadata.status' "$env.prev")" = "reviewed" ]
    [ -f "$sc.prev" ]
    [ ! -e "$sc" ]
    # an aborted run (no envelope at the path): the record is written and this run's own sidecar stays where verdict-derive counts it
    command rm -f -- "$env"; printf '{"row":2}\n' > "$sc"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --reason "session limit mid-run" ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 0 ]
    [ "$(jq -r '.metadata.status' "$env")" = "failed" ]
    [ -f "$sc" ]
    # …but an envelope that stands is a run's own: never overwritten
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --reason "again" ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 2 ]
    [ "$(jq -r '.metadata.reason' "$env")" = "session limit mid-run" ]
    # a live run holding the lock: refused, nothing moved
    ( _adv_take_run_lock "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT" review; : > "$T/held"; sleep 30 ) 3>&- & HOLDER_PIDS+=("$!")
    local i=0; while [[ ! -e "$T/held" ]] && (( i++ < 100 )); do sleep 0.05; done
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback budget_exceeded --reason "over budget" ) >"$T/out" 2>"$T/err" || rc=$?
    [ "$rc" -eq 2 ]
    [ "$(jq -r '.metadata.status' "$T/out")" = "refused_concurrent_run" ]
    [ "$(jq -r '.metadata.status' "$env")" = "failed" ]
    # the statuses it does not record, and a missing reason — with the holder GONE, so the only refusal is the argument's own, and
    # each names its cause (twenty-sixth run, c1c DISS-C-001: under the live holder every leg exited 2 as a concurrent run)
    local h; for h in "${HOLDER_PIDS[@]}"; do pkill -P "$h" 2>/dev/null || true; kill "$h" 2>/dev/null || true; wait "$h" 2>/dev/null || true; done
    _adv_take_run_lock "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT" review; _adv_release_run_lock   # (the dead holder's lock is taken over and freed)
    local bad want
    for bad in refused_concurrent_run bogus; do
        rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback "$bad" --reason r ) >/dev/null 2>"$T/err" || rc=$?
        [ "$rc" -eq 2 ] || { echo "$bad: rc $rc"; return 1; }
        case "$bad" in refused_concurrent_run) want="refused_concurrent_run is not recorded" ;; *) want="unknown status 'bogus'" ;; esac
        grep -qF -- "$want" "$T/err" || { echo "$bad: $(cat "$T/err")"; return 1; }
        if grep -q 'in progress' "$T/err"; then echo "$bad: refused as a concurrent run"; return 1; fi
    done
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 2 ]
    grep -qF -- "needs --reason" "$T/err"
}

@test "CMP-120 the skills can carry out the failed-run procedure their resources prescribe: both allowlist adversarial-review.sh and the qmd step (the audit no git diff: --diff-range), the resources name --record-fallback and no hand-moved .prev files; the Locks bullet, the voices_planned rule, the degraded-audit rule and the config example match the envelope (twenty-third run, b2 DISS-C-001…005; twenty-fourth run, b2 DISS-001, DISS-C-001…004)" {
    local s r
    for s in reviewing-code auditing-security; do
        grep -q 'Bash(.claude/scripts/adversarial-review.sh \*)' "$PROJECT_ROOT/.claude/skills/$s/SKILL.md" || { echo "$s: adversarial-review.sh not allowlisted"; return 1; }
        grep -q 'command: ".claude/scripts/adversarial-review.sh"' "$PROJECT_ROOT/.claude/skills/$s/SKILL.md" || { echo "$s: capabilities miss adversarial-review.sh"; return 1; }
        r="$PROJECT_ROOT/.claude/skills/$s/resources/ADVERSARIAL-REVIEW.md"
        grep -q -- '--record-fallback' "$r" || { echo "$s: resource does not name --record-fallback"; return 1; }
        if grep -q 'move that envelope and its' "$r"; then echo "$s: resource still prescribes a hand move"; return 1; fi
        if grep -A1 'a lock not acquired within the hop' "$r" | grep -q '`timeout`'; then echo "$s: Locks bullet says timeout"; return 1; fi
        grep -q 'voices_planned` stays 1' "$r" || { echo "$s: voices_planned rule omits the INV-5 case"; return 1; }
    done
    # (twenty-fourth run, b2: the audit holds no git diff grant — --diff-range produces the diff; both skills may run the qmd
    # step they prescribe; the resources carry --since, displaced, the post-refusal triage and every family's chain)
    if grep -q 'git diff' "$PROJECT_ROOT/.claude/skills/auditing-security/SKILL.md"; then echo "audit: still names git diff"; return 1; fi
    grep -q -- '--diff-range main...HEAD' "$PROJECT_ROOT/.claude/skills/auditing-security/SKILL.md"
    # (twenty-fifth run, b2 DISS-C-003: only the review runs the qmd step — the audit prescribes none and holds no grant for it)
    grep -q 'Bash(.claude/scripts/qmd-context-query.sh \*)' "$PROJECT_ROOT/.claude/skills/reviewing-code/SKILL.md" || { echo "review: qmd step not allowlisted"; return 1; }
    grep -q 'command: ".claude/scripts/qmd-context-query.sh"' "$PROJECT_ROOT/.claude/skills/reviewing-code/SKILL.md" || { echo "review: capabilities miss qmd"; return 1; }
    if grep -qi 'qmd' "$PROJECT_ROOT/.claude/skills/auditing-security/SKILL.md"; then echo "audit: a qmd grant without a qmd step"; return 1; fi
    # (twenty-fifth run, b2 DISS-C-001: the review's invocation is the bare call its prefix grant covers, never an assignment)
    if grep -q 'findings=\$(' "$PROJECT_ROOT/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md"; then echo "review: the dissent call is wrapped in an assignment"; return 1; fi
    for s in reviewing-code auditing-security; do
        r="$PROJECT_ROOT/.claude/skills/$s/resources/ADVERSARIAL-REVIEW.md"
        grep -q -- '--since <the time on the run' "$r" || { echo "$s: --since missing"; return 1; }
        grep -q 'metadata.displaced' "$r" || { echo "$s: displaced missing"; return 1; }
        grep -q 'otherwise, or when none stands, run again' "$r" || { echo "$s: post-refusal triage missing"; return 1; }
        grep -q 'outside the Anthropic family' "$r" || { echo "$s: family rule missing"; return 1; }
        if grep -q 'run has exited and run again' "$r"; then echo "$s: still re-runs after a refusal"; return 1; fi
    done
    grep -q -- '--diff-range main...HEAD' "$PROJECT_ROOT/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md"
    grep -q 'Google, xAI' "$PROJECT_ROOT/.loa.config.yaml.example"
    r="$PROJECT_ROOT/.claude/skills/auditing-security/resources/ADVERSARIAL-REVIEW.md"
    grep -q 'A bare `planned: false`' "$r"
    if grep -q 'a `counted_as` other than `independent_voice`' "$r"; then echo "audit: the counted_as clause reads an opt-out as degraded"; return 1; fi
    grep -q 'no_route' "$PROJECT_ROOT/.loa.config.yaml.example"
}

@test "CMP-138 both skills' shared two-voices block is byte-identical, and the failed-run rule is stated once per status class, branched on the stdout status line (twenty-fifth run, b2 DISS-C-002 / DISS-C-004)" {
    local a b s r
    a=$(sed -n '/^## Two voices and the rejected-payload contract/,$p' "$PROJECT_ROOT/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md")
    b=$(sed -n '/^## Two voices and the rejected-payload contract/,$p' "$PROJECT_ROOT/.claude/skills/auditing-security/resources/ADVERSARIAL-REVIEW.md")
    [ -n "$a" ]
    [ "$a" = "$b" ] || { diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | head -20; return 1; }
    for s in reviewing-code auditing-security; do
        r="$PROJECT_ROOT/.claude/skills/$s/resources/ADVERSARIAL-REVIEW.md"
        grep -q 'Branch on the `status` line the script prints on stdout, never on exit 2 alone' "$r" || { echo "$s: no stdout-status rule"; return 1; }
        grep -q '^- \*\*`failed`\*\*' "$r" || { echo "$s: no failed class"; return 1; }
        grep -q '^- \*\*`refused_concurrent_run`\*\*' "$r" || { echo "$s: no refused class"; return 1; }
        grep -q '^- \*\*`workdir_unavailable`, `nothing_to_review`, `budget_exceeded`, `diff_range_failed`\*\*' "$r" || { echo "$s: no pre-lock class"; return 1; }
    done
}

@test "CMP-121 every suite that names adversarial-review.sh resolves the CLI lock under its own XDG_RUNTIME_DIR — never the per-user directory a live dissent holds (run 23: the e2e suite queued 910 s behind a live claude -p and failed)" {
    local f bad=""
    # (twenty-eighth run, c1c DISS-C-002: an export STATEMENT — at the line start or after `{` — whose own assignments include
    # XDG_RUNTIME_DIR; a commented-out redirect or a bare assignment after an unrelated `export …;` is no isolation)
    local re='(^[[:space:]]*|[{][[:space:]]*)export[[:space:]]+([A-Za-z_][A-Za-z_0-9]*=("[^"]*"|[^[:space:];#"]*)[[:space:]]+)*XDG_RUNTIME_DIR='
    local probe
    for probe in '    # export XDG_RUNTIME_DIR="$T"' '    export A=1; XDG_RUNTIME_DIR="$T"' '    XDG_RUNTIME_DIR="$T"  # export'; do
        if printf '%s\n' "$probe" | grep -qE "$re"; then echo "the rule accepts: $probe"; return 1; fi
    done
    for probe in '    export XDG_RUNTIME_DIR="$T"' '    export A="x y" XDG_RUNTIME_DIR="$T"' 'setup() { export XDG_RUNTIME_DIR="$d"; }'; do
        printf '%s\n' "$probe" | grep -qE "$re" || { echo "the rule rejects: $probe"; return 1; }
    done
    while IFS= read -r f; do
        grep -qE "$re" "$f" || bad+=" ${f#"$PROJECT_ROOT"/}"
    done < <(grep -lE 'adversarial-review\.sh' "$PROJECT_ROOT"/tests/unit/*.bats "$PROJECT_ROOT"/tests/integration/*.bats)
    [ -z "$bad" ] || { echo "no XDG_RUNTIME_DIR isolation in:$bad"; return 1; }
}

@test "CMP-122 the operator's knobs are cleared BEFORE the script is sourced — a value it reads at load (the CLI hop bound) never drives the suite (twenty-third run, c2a DISS-C-001)" {
    # (setup cannot run twice here — the script declares a readonly — so the order is read from setup itself)
    local body unset_at eval_at
    body=$(declare -f setup)
    unset_at=$(grep -n 'LOA_ADVERSARIAL_CLI_HOP_TIMEOUT' <<<"$body" | head -n 1 | cut -d: -f1)
    eval_at=$(grep -n 'eval "$_src"' <<<"$body" | head -n 1 | cut -d: -f1)
    [ -n "$unset_at" ] || { echo "setup never clears LOA_ADVERSARIAL_CLI_HOP_TIMEOUT"; return 1; }
    [ -n "$eval_at" ]
    (( unset_at < eval_at )) || { echo "the knobs are cleared at line $unset_at, after the script is sourced at $eval_at"; return 1; }
    [ "$_ADV_CLI_HOP_TIMEOUT" = "610" ]
}

@test "CMP-123 a companion_chain list element that is not a hop name (a map, a list, a null, a spaced string) is said and dropped — never split into hop tokens (twenty-fourth run, a1 DISS-C-001)" {
    _cfg_edit $'  code_review:\n    enabled: true\n' $'  code_review:\n    enabled: true\n    companion_chain:\n      anthropic: [{a: 1}, ~, [b, c], "x y", claude-headless]\n'
    result=$(_run_main review)
    [ "$(grep -c 'companion_chain.anthropic\[[0-9]\] is not a hop name' "$T/stderr.log")" = "4" ]
    for _i in 0 1 2 3; do grep -q "companion_chain.anthropic\[$_i\] is not a hop name" "$T/stderr.log"; done
    if grep -q 'x y' "$T/stderr.log"; then return 1; fi   # the dropped value is never echoed
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    chain=$(jq -r '.metadata.companion_voice.chain | if type == "array" then join(" ") else gsub(","; " ") end' <<<"$result")
    [ -n "$chain" ]
    for _h in $chain; do [[ "$_h" =~ ^[A-Za-z0-9._/:-]+$ ]] || return 1; [[ "$_h" != null && "$_h" != a: && "$_h" != x && "$_h" != y && "$_h" != b && "$_h" != c ]] || return 1; done
}

@test "CMP-132 a companion_chain family list that cannot be read in full — over 999 entries, or a length yq cannot report — is said, never silently taken as no operator chain (twenty-fifth run, a1 DISS-C-003)" {
    local hops; hops=$(printf 'claude-headless,%.0s' $(seq 1 1000)); hops="[${hops%,}]"
    _cfg_edit $'  code_review:\n    enabled: true\n' "  code_review:"$'\n'"    enabled: true"$'\n'"    companion_chain:"$'\n'"      anthropic: ${hops}"$'\n'
    run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; _adv_conf_chain_hops code_review anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" == *"companion_chain.anthropic has 1000 entries"* ]]
    # a length yq cannot report (an older yq, a read error) on a list the tag check saw
    _cfg_edit "      anthropic: ${hops}" '      anthropic: [claude-headless]'
    run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; yq() { case \"\$*\" in *length*) return 1 ;; *) command yq \"\$@\" ;; esac; }; _adv_conf_chain_hops code_review anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" == *"companion_chain.anthropic could not be read"* ]]
    # an explicitly empty list, or one whose every element was dropped, yields no hop: the default applies and that is said
    # once for the list (twenty-seventh run, a1 DISS-C-001 — `companion_voice: false` is the opt-out, not `[]`)
    local _l
    for _l in '[]' '[{a: 1}, "bad hop"]'; do
        _cfg_edit '      anthropic: [claude-headless]' "      anthropic: ${_l}"
        run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; _adv_conf_chain_hops code_review anthropic"
        [ "$status" -eq 0 ]
        [[ "$output" == *"companion_chain.anthropic is a list with no hop name — the default anthropic chain applies"* ]] || { echo "$_l: $output"; return 1; }
        [ "$(grep -c 'is a list with no hop name' <<<"$output")" -eq 1 ]
        _cfg_edit "      anthropic: ${_l}" '      anthropic: [claude-headless]'
    done
    # a list that keeps a hop says nothing for the list
    run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; _adv_conf_chain_hops code_review anthropic"
    [ "$output" = "claude-headless" ]
    # control: an absent family list is the default, said by nobody
    run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; _adv_conf_chain_hops code_review openai"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "CMP-124 a lone top file over the budget gets the whole budget for its partial view — the three-quarter cap leaves room only when a lower-ranked row is there to take it (twenty-fourth run, b1 DISS-C-001)" {
    mk_hunk() { printf '@@ -%d,3 +%d,4 @@ fn%d\n context\n-old line %d\n+new line %d %s\n' "$1" "$1" "$1" "$1" "$1" "$(printf 'x%.0s' $(seq 1 8))"; }
    big="diff --git a/big.sh b/big.sh
--- a/big.sh
+++ b/big.sh"
    for _n in $(seq 1 120); do big+=$'\n'"$(mk_hunk $(( _n * 10 )))"; done
    [ "$(estimate_tokens "$big")" -gt 600 ]
    out=$(prepare_content "$big" 300 2>/dev/null)
    [[ "$out" == *"--- PARTIAL: big.sh"* ]]
    payload=$(printf '%s' "$out" | sed '/^--- TRUNCATED:/,$d')
    [ "$(estimate_tokens "$payload")" -le 300 ]
    [ "$(estimate_tokens "$payload")" -gt 270 ]   # past the three-quarter cap (225) plus its marker (~35): 258 before the fix, whole hunks of ~10 tokens
    # control: a lower-ranked row present — the cap holds, and the quarter it keeps is that row's to take
    doc=$'diff --git a/notes.md b/notes.md\n--- a/notes.md\n+++ b/notes.md\n@@ -1 +1 @@\n-a\n+b'
    out=$(prepare_content "$big
$doc" 300 2>/dev/null)
    part=$(printf '%s' "$out" | sed '/^diff --git a\/notes.md/,$d; /^--- TRUNCATED:/,$d')
    [ "$(estimate_tokens "$part")" -le 262 ]   # the cap and the marker
    [[ "$out" == *"diff --git a/notes.md b/notes.md"* ]]
}

@test "CMP-125 the companion's state publisher is best-effort — a read-only workdir or a failed rename never ends the errexit walker, and no temp file is left behind (twenty-fourth run, a3 DISS-C-001)" {
    # (the write fails for ANY uid: the workdir is a regular file, ENOTDIR — a mode-555 directory does not bind root, the uid
    # of most CI containers: twenty-fifth run, c1c DISS-C-002)
    local ro="$T/notadir"; : > "$ro"
    run bash -c "set -e; $(declare -f _adv_put_state); _adv_put_state '$ro/companion.phase' hop; echo walked-on"
    [ "$status" -eq 0 ]
    [ "$output" = "walked-on" ]
    [ -f "$ro" ]
    [ ! -s "$ro" ]   # (two statements: a failing `[ ]` left of && fires nothing under bats — twenty-sixth run, c1c DISS-C-003)
    # the rename fails: the walker goes on and the temp is removed
    local rw="$T/rw"; mkdir -p "$rw"
    run bash -c "set -e; mv() { return 1; }; $(declare -f _adv_put_state); _adv_put_state '$rw/companion.phase' post; echo walked-on"
    [ "$status" -eq 0 ]
    [ "$output" = "walked-on" ]
    [ ! -e "$rw/companion.phase" ]   # nothing published by a rename that failed
    [ -z "$(find "$rw" -name '*.tmp*')" ]
    # the ordinary case still publishes the value whole
    _adv_put_state "$rw/companion.phase" done
    [ "$(cat "$rw/companion.phase")" = "done" ]
    [ ! -e "$rw/companion.phase.tmp" ]
}

@test "CMP-126 a second INT / TERM while a signal's trap is reaping never runs a nested handler, and the primary's pid stays published until its tree is signalled (twenty-fourth run, a4 DISS-C-001)" {
    # the run's own INT / TERM trap lines, evaluated around a reaper that is signalled again mid-reap: a nested handler would
    # run the reaper twice (bash enters a second signal's trap inside a running one)
    local traps
    traps=$(grep -E "^  trap [\"'].*exit 1[34][03][\"'] (INT|TERM)$" "$ADVERSARIAL_REVIEW")
    [ "$(grep -c '' <<<"$traps")" = "2" ]   # (not wc -l: BSD wc pads — twenty-ninth run, c1c DISS-C-003)
    # (a detached run inherits SIGINT ignored, which a non-interactive bash cannot trap — the probe gets the default back, as CMP-102)
    local pre=(); env --default-signal=INT true 2>/dev/null && pre=(env --default-signal=INT)
    if [[ ${#pre[@]} -eq 0 && -n "$(bash -c 'trap -p INT')" ]]; then skip "SIGINT is ignored here and env --default-signal is unavailable"; fi
    for sig in TERM INT; do
        run "${pre[@]}" bash -c "
            _adv_reap_primary() { echo reap; kill -$sig \$\$; kill -TERM \$\$; sleep 0.3; echo reaped; }
            _adv_reap_companion() { :; }
            $traps
            kill -$sig \$\$; sleep 2; echo never"
        [ "$(grep -c '^reap$' <<<"$output")" = "1" ] || { echo "$sig: $output"; return 1; }
        grep -q '^reaped$' <<<"$output"
        if grep -q '^never$' <<<"$output"; then return 1; fi
    done
    # the reaper: the tree is signalled while the pid is still published
    # (fd 3 closed and registered, and the reclaim bounded — a reaper that never signals it fails here, never stalls the harness
    # 30 s: twenty-fifth run, c1c DISS-C-003)
    sleep 30 3>&- & local p=$!; HOLDER_PIDS+=("$p")
    _adv_kill_tree() { echo "published=${_ADV_PRIMARY_PID:-}" >> "$T/kt.log"; kill -TERM "$1"; echo "$1=x"; }
    _ADV_PRIMARY_PID=$p; LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1 _adv_reap_primary
    sleep 0.3; if kill -0 "$p" 2>/dev/null; then echo "pid $p still alive after the primary reap" >&2; return 1; fi
    [ "$(cat "$T/kt.log")" = "published=$p" ]
    [ -z "${_ADV_PRIMARY_PID:-}" ]
}

@test "CMP-127 --record-fallback failed --since <run start>: a standing envelope older than the run (or with no timestamp) is the previous round's and goes aside; a newer one, a malformed --since, or no --since leaves the refusal standing and names --since (twenty-fourth run, a2 DISS-C-001)" {
    mkdir -p "$OUT_DIR"
    local env="$OUT_DIR/adversarial-review.json" sc="$OUT_DIR/adversarial-rejected-review.jsonl" rc
    # the previous round's envelope and sidecar; the run died before its lock, writing nothing
    printf '{"findings":[],"metadata":{"status":"reviewed","timestamp":"2026-10-01T10:00:00Z","rejected_summary":[]}}\n' > "$env"
    printf '{"row":1}\n' > "$sc"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --reason "died in prepare" ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 2 ]
    grep -q -- '--since' "$T/err"
    [ "$(jq -r '.metadata.status' "$env")" = "reviewed" ]
    # (twenty-sixth run, c1c DISS-C-004: the refusal names the malformed value — a lenient parser reading 2026-10-01 as midnight
    # would refuse on age instead, with the same exit)
    for bad in yesterday 2026-10-01 '2026-10-01T10:00:00Z;x'; do
        rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --since "$bad" --reason r ) >/dev/null 2>"$T/err" || rc=$?
        [ "$rc" -eq 2 ] || { echo "$bad: rc $rc"; return 1; }
        grep -qF -- "--since: expected YYYY-MM-DDTHH:MM:SSZ" "$T/err" || { echo "$bad: $(cat "$T/err")"; return 1; }
    done
    # an envelope written AFTER the run started is that run's own: refused
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --since 2026-10-01T09:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 2 ]
    [ "$(jq -r '.metadata.status' "$env")" = "reviewed" ]
    [ ! -e "$env.prev" ]
    # older than the run: moved aside with its sidecar, then recorded
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --since 2026-10-02T12:00:00Z --reason "died in prepare" ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 0 ] || { cat "$T/err"; return 1; }
    [ "$(jq -r '.metadata.status' "$env")" = "failed" ]
    [ "$(jq -r '.metadata.status' "$env.prev")" = "reviewed" ]
    [ -f "$sc.prev" ]
    [ ! -e "$sc" ]
    # an envelope with no timestamp predates any run start
    printf '{"findings":[],"metadata":{"status":"reviewed"}}\n' > "$env"; command rm -f -- "$env.prev"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 0 ]
    [ "$(jq -r '.metadata.status' "$env.prev")" = "reviewed" ]
    # (twenty-sixth run, b2 DISS-C-002: a pre-lock refusal's --since is the same age guard — CMP-146)
    # (an empty --diff-file is itself a nothing_to_review exit 2: the refusal must be the flag's own — twenty-seventh run, c1c DISS-C-001)
    rc=0; ( main --type review --sprint-id "$SPRINT" --since 2026-10-02T12:00:00Z --diff-file /dev/null ) >"$T/out" 2>"$T/err" || rc=$?
    [ "$rc" -eq 2 ]   # (--since belongs to --record-fallback)
    grep -qF -- '--since applies to --record-fallback only' "$T/err" || { echo "not the flag's refusal: $(cat "$T/out" "$T/err")"; return 1; }
    if grep -q nothing_to_review "$T/out"; then echo "--since passed the parser"; return 1; fi
}

@test "CMP-128 --diff-range <base>...<head> has the script produce the diff itself (no external diff driver, no textconv) — the audit needs no git diff grant, whose --output / --no-index write and read any path; a range that is not ref names, or one beside --diff-file, is refused before git runs (twenty-fourth run, b2 DISS-C-001)" {
    git() {
        if [[ "${1:-}" == "-C" && " $* " == *" diff "* ]]; then echo "$*" >> "$T/git.log"; cat "$T/diff.patch"; return 0; fi
        command git "$@"
    }
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    local _r; _r=$(_cmp_base_ref)
    result=$(main --type review --sprint-id "$SPRINT" --diff-range "$_r...HEAD" --json 2> "$T/stderr.log")
    [ "$(grep -c . "$T/git.log")" = "1" ]
    # (twenty-seventh run, a4 DISS-C-002: the diff is taken between the commits the range resolved to, and the scope names them)
    local _b _h; _b=$(command git -C "$PROJECT_ROOT" rev-parse "$_r"); _h=$(command git -C "$PROJECT_ROOT" rev-parse HEAD)
    # (a fixed string: the checkout path and the `...` between the oids are literal — thirty-third run, c1c DISS-C-002)
    grep -qxF -- "-C $PROJECT_ROOT -c diff.suppressBlankEmpty=false -c core.quotePath=true -c diff.relative=false -c diff.noprefix=false -c diff.mnemonicPrefix=false -c diff.renames=true -c diff.indentHeuristic=true -c core.attributesFile=/dev/null diff -U3 --inter-hunk-context=0 --diff-algorithm=myers -O/dev/null --no-color --no-ext-diff --no-textconv --submodule=short --ignore-submodules=none --src-prefix=a/ --dst-prefix=b/ ${_b}...${_h} --" "$T/git.log"
    [ "$(jq -c '.metadata.scope.diff_oids' <<<"$result")" = "{\"base\":\"$_b\",\"head\":\"$_h\"}" ]
    [ "$(jq -r '.metadata.scope.diff_range' <<<"$result")" = "$_r...HEAD" ]
    [ "$(jq '.verdict_quality.voices_planned' <<<"$result")" = "2" ]
    if ls "${TMPDIR:-/tmp}"/adversarial-range-* 2>/dev/null | grep -q .; then
        for f in "${TMPDIR:-/tmp}"/adversarial-range-*; do [[ "$(cat "$f" 2>/dev/null)" != "$(cat "$T/diff.patch")" ]] || { echo "range diff $f left behind"; return 1; }; done
    fi
    : > "$T/git.log"
    local bad rc
    # (twenty-sixth run, a4 DISS-C-003: exactly <base>...<head> — a two-dot range is a different diff, and no side holds `..`)
    for bad in --output=x -main...HEAD 'main...HEAD --output=x' 'main;id' 'main...' '' main..HEAD 'a...b..c' 'a..b...c' 'a....b'; do
        rc=0; ( main --type review --sprint-id "$SPRINT" --diff-range "$bad" --json ) >/dev/null 2>"$T/bad.err" || rc=$?
        [ "$rc" -eq 2 ] || { echo "'$bad': rc $rc"; return 1; }
        # (thirty-second run, c1c DISS-C-003: the refusal is the parser's — an empty value is no range at all — never a later
        # failure of rev-parse or the diff, which an rc of 2 alone cannot tell apart)
        if [[ -z "$bad" ]]; then grep -q 'Missing --diff-file' "$T/bad.err" || { echo "'': $(cat "$T/bad.err")"; return 1; }
        else grep -q -- '--diff-range: expected <base>...<head> (ref names only)' "$T/bad.err" || { echo "'$bad': $(cat "$T/bad.err")"; return 1; }; fi
        ! grep -qE 'git diff .* failed|diff_range_failed' "$T/bad.err" || { echo "'$bad' reached git: $(cat "$T/bad.err")"; return 1; }
    done
    rc=0; ( main --type review --sprint-id "$SPRINT" --diff-range main...HEAD --diff-file "$T/diff.patch" --json ) >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 2 ]
    [ ! -s "$T/git.log" ]
}

@test "CMP-129 a run says when it started, as the --since an aborted run's --record-fallback failed needs — the skills' allowlists hold no date (twenty-fourth run, a2 DISS-C-001)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    result=$(_run_main review)
    grep -qE 'run started [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$T/stderr.log"
    local ts; ts=$(grep -oE 'run started [0-9T:Z-]+' "$T/stderr.log" | head -n 1 | cut -d' ' -f3)
    local ets; ets=$(jq -er '.metadata.timestamp' <<<"$result")   # an absent timestamp is "null", which sorts after any date (thirtieth run, c1c DISS-C-004)
    [[ "$ets" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { echo "metadata.timestamp is not an ISO-8601 UTC stamp: $ets"; return 1; }
    [[ ! "$ets" < "$ts" ]]   # the envelope this run writes is never older than its start
}

@test "CMP-130 a fallback record that moves an envelope aside says what it displaced — its status, timestamp, findings and rejected counts — and verdict-derive warns when the displaced envelope held findings (twenty-fourth run, b2 DISS-C-002)" {
    mkdir -p "$OUT_DIR"
    local env="$OUT_DIR/adversarial-review.json" rc
    printf '{"findings":[{"id":"DISS-001"},{"id":"DISS-002"}],"metadata":{"status":"reviewed","timestamp":"2026-10-01T10:00:00Z","rejected_summary":[{"index":0}]}}\n' > "$env"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback nothing_to_review --reason "nothing to review" ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 0 ] || { cat "$T/err"; return 1; }
    [ "$(jq -c '.metadata.displaced' "$env")" = '{"status":"reviewed","timestamp":"2026-10-01T10:00:00Z","findings":2,"rejected":1}' ]
    {
        echo "All good"; echo
        echo '<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0},"excluded":0,"sprint_id":"s","ts":"2026-10-02T00:00:00Z"} -->'
    } > "$OUT_DIR/engineer-feedback.md"
    run bash -c "\"$PROJECT_ROOT/.claude/scripts/verdict-derive.sh\" --file \"$OUT_DIR/engineer-feedback.md\" --gate review --json 2>/dev/null"
    echo "$output" | jq -e '.warnings | any(test("displaced an envelope with 2 findings"))' >/dev/null
    # nothing displaced: null, and no warning
    command rm -f -- "$env" "$env.prev"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --reason "aborted" ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 0 ]
    [ "$(jq -c '.metadata.displaced' "$env")" = "null" ]
    run bash -c "\"$PROJECT_ROOT/.claude/scripts/verdict-derive.sh\" --file \"$OUT_DIR/engineer-feedback.md\" --gate review --json 2>/dev/null"
    echo "$output" | jq -e '.warnings | any(test("displaced")) | not' >/dev/null
    # (twenty-fifth run, b1 DISS-C-001: and the record is read — a null displaced never made the envelope "not parseable")
    if echo "$output" | jq -e '.violations | any(test("not parseable"))' >/dev/null; then echo "a fallback record with displaced null was read as unparseable"; return 1; fi
}

@test "CMP-137 prepare_content runs to its end as a plain statement under errexit — the first whole file admitted, and a partial view with no room for any byte (a BSD head refuses -c 0) (twenty-fifth run, b1 DISS-C-003 / DISS-C-004)" {
    local lib="$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    small=$'diff --git a/a.sh b/a.sh\n--- a/a.sh\n+++ b/a.sh\n@@ -1,1 +1,1 @@\n-a\n+b'
    pad="diff --git a/pad.txt b/pad.txt
--- a/pad.txt
+++ b/pad.txt
@@ -1,1 +1,1 @@
-$(printf 'p%.0s' $(seq 1 900))
+$(printf 'q%.0s' $(seq 1 900))"
    # (a plain statement — a command substitution turns errexit off — over budget, two files: the parse loop's counters and the
    # first whole file admitted all start at 0)
    run bash -c 'set -e; source "$1"; prepare_content "$2" 300 > "$3" 2>/dev/null; echo survived' _ "$lib" "$small"$'\n'"$pad" "$T/plain.out"
    [[ "$output" == *survived* ]] || { echo "prepare_content stopped under errexit: $output"; return 1; }
    grep -q '^+b$' "$T/plain.out"
    big="diff --git a/big.sh b/big.sh
--- a/big.sh
+++ b/big.sh
@@ -1,3 +1,4 @@ f
 context
-old $(printf 'x%.0s' $(seq 1 400))
+new $(printf 'y%.0s' $(seq 1 400))"
    run bash -c 'head() { if [[ "${1:-}" == "-c" && "${2:-}" == "0" ]]; then echo "head: illegal byte count -- 0" >&2; return 1; fi; command head "$@"; }
        set -e; source "$1"; prepare_content "$2" 10 2>/dev/null; echo; echo survived' _ "$lib" "$big"
    [[ "$output" == *survived* ]] || { echo "a zero-byte cut stopped prepare_content: $output"; return 1; }
    [[ "$output" == *"--- PARTIAL: big.sh: no hunk fit within the token budget"* ]]
}

@test "CMP-135 the shared-hop wait is an interruptible job, and the primary job's reaper signals only the process it forked — a reused pid is left alone, and a signal in the fork window still reaps the new job (twenty-fifth run, a4 DISS-C-001 / DISS-C-003)" {
    # (1) the call site runs the wait through _adv_run_interruptible, never in a command substitution main blocks on
    if grep -qE '\$\(_adv_shared_hop_verdict ' "$ADVERSARIAL_REVIEW"; then echo "the shared-hop wait still runs in \$(…)"; return 1; fi
    grep -qE '_adv_run_interruptible "[^"]*" _adv_shared_hop_verdict ' "$ADVERSARIAL_REVIEW"
    # (2) a token that no longer matches: the pid was reused, nothing is signalled
    sleep 30 3>&- & local p=$!; HOLDER_PIDS+=("$p")
    local _orig_kt; _orig_kt=$(declare -f _adv_kill_tree); [ -n "$_orig_kt" ]
    _adv_kill_tree() { echo "signalled $1" >> "$T/kt.log"; echo "$1=x"; }
    _ADV_PRIMARY_PID=$p; _ADV_PRIMARY_START="t1"; LOA_ADVERSARIAL_REAP_GRACE_SECONDS=0 _adv_reap_primary
    [ ! -s "$T/kt.log" ]; [ -z "${_ADV_PRIMARY_PID:-}" ]; [ -z "${_ADV_PRIMARY_START:-}" ]
    kill -0 "$p"
    # …the matching token is signalled
    _ADV_PRIMARY_PID=$p; _ADV_PRIMARY_START=$(_adv_proc_start "$p"); LOA_ADVERSARIAL_REAP_GRACE_SECONDS=0 _adv_reap_primary
    grep -qx "signalled $p" "$T/kt.log"; : > "$T/kt.log"
    # (3) the fork window: the job is forked and $! is new, the pid not yet published — the reaper takes $! (BANG is $! as it
    # stood BEFORE the fork — the previous job's, $p — so a new $! is the forked job: twenty-ninth run, c1c DISS-001, refuted)
    sleep 30 3>&- & local q=$!; HOLDER_PIDS+=("$q")
    _ADV_PRIMARY_PID=""; _ADV_PRIMARY_START=""; _ADV_PRIMARY_FORKING=1; _ADV_PRIMARY_BANG="$p"
    LOA_ADVERSARIAL_REAP_GRACE_SECONDS=0 _adv_reap_primary
    grep -qx "signalled $q" "$T/kt.log"; : > "$T/kt.log"
    # …before the fork ($! is still the previous job's — the companion's) nothing is signalled
    _ADV_PRIMARY_FORKING=1; _ADV_PRIMARY_BANG="$q"
    LOA_ADVERSARIAL_REAP_GRACE_SECONDS=0 _adv_reap_primary
    [ ! -s "$T/kt.log" ]
    _ADV_PRIMARY_FORKING=""; _ADV_PRIMARY_BANG=""
    # (4) _adv_run_interruptible publishes and clears the token with the pid — under the script's own _adv_kill_tree, restored,
    # never deleted (thirty-first run, c1c DISS-C-001: `unset -f` removed the sourced helper outright)
    eval "$_orig_kt"
    [ "$(declare -f _adv_kill_tree)" = "$_orig_kt" ]
    _adv_run_interruptible "$T/ri.out" true
    [ -z "${_ADV_PRIMARY_PID:-}" ]; [ -z "${_ADV_PRIMARY_START:-}" ]; [ -z "${_ADV_PRIMARY_FORKING:-}" ]
}

@test "CMP-136 --diff-range's diff ignores the operator's presentation config: no colour, a/ b/ prefixes under diff.noprefix / mnemonicPrefix (twenty-fifth run, a4 DISS-C-002)" {
    local r="$T/hostile"; _cmp_git init -q "$r"
    _cmp_git -C "$r" commit -q --allow-empty -m base
    printf 'one\n' > "$r/f.txt"; _cmp_git -C "$r" add f.txt
    _cmp_git -C "$r" commit -q -m head
    command git -C "$r" config color.ui always; command git -C "$r" config color.diff always
    command git -C "$r" config diff.noprefix true; command git -C "$r" config diff.mnemonicPrefix true
    out=$(_adv_range_diff "$r" HEAD~1...HEAD)
    if grep -q $'\033' <<<"$out"; then echo "colour escapes in the range diff"; return 1; fi
    grep -qx 'diff --git a/f.txt b/f.txt' <<<"$out"
    grep -qx '+++ b/f.txt' <<<"$out"
    grep -qx '+one' <<<"$out"
}

@test "CMP-134 any provider prefix is stripped from a hop before its CLI nature, bound and lock are read, and a bedrock id's version colon is kept; an empty companion.current is the fallback hop's queue bound, never a zero budget (twenty-fifth run, a3 C-001 / C-002)" {
    printf 'providers:\n  anthropic:\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 900\n' > "$T/catalog3.yaml"
    export LOA_MODEL_CONFIG="$T/catalog3.yaml"
    [ "$(_adv_hop_canon bedrock:claude-headless)" = "claude-headless" ]
    [ "$(_adv_hop_canon xai:foo-headless)" = "foo-headless" ]
    [ "$(_adv_cli_bin_for xai:foo-headless)" = "foo" ]
    [ "$(_adv_cli_hop_bound bedrock:claude-headless)" = "910" ]
    [ "$(_adv_hop_canon us.anthropic.claude-x-v1:0)" = "us.anthropic.claude-x-v1:0" ]
    [ "$(_adv_hop_canon bedrock:us.anthropic.claude-x-v1:0)" = "us.anthropic.claude-x-v1:0" ]
    # (2) queue phase, companion.current present but empty, the cache in its initial state
    sleep 60 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID"); _ADV_COMPANION_START=$(_adv_proc_start "$_ADV_COMPANION_PID")
    mkdir -p "$T/dq"; : > "$T/dq/companion.current"; printf 'queue' > "$T/dq/companion.phase"
    _adv_cli_hop_bound() { echo 910; }
    _ADV_QB_HOP=""; _ADV_QB_VAL=0; whyq="x"; now=$(date +%s)
    _companion_deadline_why "$T/dq" $(( now - 5 )) 10 60 940 whyq
    [ -z "$whyq" ]
    [ "$_ADV_QB_VAL" = "940" ]
}

@test "CMP-133 a takeover in the last round is followed by a mkdir that takes the key — a freed lock is never run unguarded as an unsettled race (twenty-fifth run, a2 C-001)" {
    lockdir=$(_adv_cli_lock_dir)
    [[ -n "$T" && "$lockdir" == "$T/"* ]] || { echo "the CLI lock dir $lockdir is not under the test directory"; return 1; }   # (thirty-first run, c1c DISS-C-002: before any mutation of it)
    mkdir -p -m 700 "$lockdir"
    sleep 0 3>&- & dead=$!; wait "$dead" 2>/dev/null || true
    # every one of the first three mkdirs of the run lock loses to a dead run's lock re-created in front of it: three takeovers
    mkdir() {
      local last="${!#}"
      if [[ "$last" == *.lock.d ]]; then
        local n=0; [[ -f "$T/mk.count" ]] && n=$(<"$T/mk.count"); n=$((n + 1)); echo "$n" > "$T/mk.count"
        if (( n <= 3 )); then
          command mkdir "$last" && printf '%s\n%s\n' "$dead" "0" > "$last/pid"
          echo "mkdir: cannot create directory '$last': File exists" >&2; return 1
        fi
      fi
      command mkdir "$@"
    }
    rc=0; ( _adv_take_run_lock "$OUT_DIR" review; echo "held=${_ADV_RUN_LOCK_DIR}" > "$T/held"; _adv_release_run_lock ) 2>"$T/race.err" || rc=$?
    unset -f mkdir
    [ "$rc" = "0" ]
    [ "$(cat "$T/mk.count")" = "4" ]
    if grep -q "did not settle" "$T/race.err"; then echo "a lock freed by the last round's takeover was run unguarded"; return 1; fi
    grep -q "held=.*\.lock\.d" "$T/held"
}

@test "CMP-131 a run lock that cannot be made for a reason other than contention runs unguarded at once with that reason, and a takeover section that cannot be opened runs unguarded with its reason — neither is a busy refusal nor an unsettled race (twenty-fourth run, a2 C-002)" {
    lockdir=$(_adv_cli_lock_dir)
    [[ -n "$T" && "$lockdir" == "$T/"* ]] || { echo "the CLI lock dir $lockdir is not under the test directory"; return 1; }   # (thirty-first run, c1c DISS-C-002: before any mutation of it)
    mkdir -p -m 700 "$lockdir"
    # (1) mkdir of the lock dir fails EACCES (a read-only lock directory): unguarded at once, naming mkdir's error — never three rounds
    # (mode bits do not bind uid 0, the uid of most CI containers: there the EACCES is mkdir's own, stubbed — twenty-seventh run,
    # c1c DISS-C-002)
    if [ "$(id -u)" -eq 0 ]; then
        rc=0; ( mkdir() { if [[ "${*: -1}" == *.lock.d ]]; then echo "mkdir: cannot create directory '${*: -1}': Permission denied" >&2; return 1; fi; command mkdir "$@"; }
                _adv_take_run_lock "$OUT_DIR" review ) 2>"$T/ro.err" || rc=$?
    else
        chmod 500 "$lockdir"
        rc=0; ( _adv_take_run_lock "$OUT_DIR" review ) 2>"$T/ro.err" || rc=$?
        chmod 700 "$lockdir"
    fi
    [ "$rc" = "0" ]
    grep -q "run lock is not taken — the run lock .* cannot be created: .*[Pp]ermission denied" "$T/ro.err"
    if grep -q "did not settle" "$T/ro.err"; then echo "a non-contention mkdir failure was retried as a race"; return 1; fi
    # (2) a dead holder behind a takeover section that cannot be opened (a directory where the lock file goes): unguarded, never busy
    sleep 60 3>&- & holder=$!; HOLDER_PIDS+=("$holder")
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"; [ -d "$lockd" ]
    printf '%s\n%s\n' "$holder" "$(_adv_proc_start "$holder")" > "$lockd/pid"; _ADV_RUN_LOCK_DIR=""
    kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null || true
    tl="${lockd%.lock.d}.takeover.lock"; mkdir "$tl"
    rc=0; ( _adv_take_run_lock "$OUT_DIR" review ) 2>"$T/tl.err" || rc=$?
    rmdir "$tl"
    [ "$rc" = "0" ]
    if grep -q "another taker holds the takeover" "$T/tl.err"; then echo "an unopenable section was reported busy"; return 1; fi
    grep -q "run lock is not taken — the takeover lock $tl cannot be opened" "$T/tl.err"
    command rm -f -- "$lockd/pid"; rmdir "$lockd" 2>/dev/null || true
}

@test "CMP-139 the stale-directory sweep deletes only what this suite marked as its own: an unmarked sprint-comp-<dead pid> stays, a marked one goes with an earlier sweep's .reap leftover, a sibling it does not name and a live owner's stay (twenty-fifth run, c1a DISS-C-001; twenty-ninth run, c1a DISS-001)" {
    local a="$T/a2a" d1 d2
    ( : ) & d1=$!; wait "$d1"
    ( : ) & d2=$!; wait "$d2"
    mkdir -p "$a/sprint-comp-$d1" "$a/sprint-comp-$d2/x" "$a/sprint-comp-$d2-companion" "$a/sprint-comp-$d2.reap-$d1/y" "$a/sprint-comp-$$-z" "$a/sprint-comp-$$/w"
    : > "$a/.sprint-comp-$d2.owner"; : > "$a/.sprint-comp-$$.owner"
    _sweep_stale_suite_dirs "$a" sprint-comp
    [ -d "$a/sprint-comp-$d1" ]                      # no marker: a real sprint of that name is never touched
    [ ! -e "$a/sprint-comp-$d2" ]
    [ -d "$a/sprint-comp-$d2-companion" ]             # a sibling the marker does not name stays (twenty-ninth run, c1a DISS-001)
    [ ! -e "$a/sprint-comp-$d2.reap-$d1" ]            # a dead sweeper's leftover is finished
    [ ! -e "$a/.sprint-comp-$d2.owner" ]              # the marker goes with its directory
    [ -d "$a/sprint-comp-$$-z" ]                       # a live owner's sibling stays
    [ -d "$a/sprint-comp-$$/w" ]                       # …and the directory its marker names (thirty-first run, c1c DISS-C-003: the sibling
                                                       # alone stays by the sibling rule, whatever the owner's liveness)
    [ -e "$a/.sprint-comp-$$.owner" ]
    # setup marks this suite's own sprint directory
    [ -f "$PROJECT_ROOT/grimoires/loa/a2a/.$SPRINT.owner" ]
}

@test "CMP-140 a holder left stopped by a failed assertion is ended by teardown, never left with a pending TERM (twenty-fifth run, c1b DISS-C-003)" {
    sleep 30 3>&- & q=$!; HOLDER_PIDS=("$q")
    # (thirty-third regression: STOPped before the fork had exec'd sleep, the TERM reached the child shell's inherited trap and
    # was lost across the exec — a 1-in-8 red no poll length cured; the holder is stopped only once it is sleep)
    local i; for i in $(seq 1 50); do [[ "$(ps -o comm= -p "$q" 2>/dev/null)" == sleep ]] && break; sleep 0.05; done
    kill -STOP "$q"
    _end_holders
    # (a bounded poll, never a fixed 0.5 s: a TERM'd process on a loaded host can take longer to exit — round 1ag's regression)
    for i in $(seq 1 50); do { kill -0 "$q" 2>/dev/null && [[ "$(ps -o stat= -p "$q" 2>/dev/null)" != Z* ]]; } || break; sleep 0.1; done
    if kill -0 "$q" 2>/dev/null && [[ "$(ps -o stat= -p "$q" 2>/dev/null)" != Z* ]]; then kill -CONT "$q"; kill -KILL "$q"; echo "a stopped holder outlived _end_holders by 5 s" >&2; return 1; fi
    HOLDER_PIDS=()
}

@test "CMP-141 a run that loses the race to create the per-user lock directory still takes its run lock — the directory is re-tested after a failed mkdir, as the CLI lock does, never declared unguarded (twenty-sixth run, a2 DISS-C-001)" {
    lockdir=$(_adv_cli_lock_dir)
    [[ -n "$T" && "$lockdir" == "$T/"* ]] || { echo "the CLI lock dir $lockdir is not under the test directory"; return 1; }   # (thirty-first run, c1c DISS-C-002: before any mutation of it)
    command rm -f -- "$lockdir"/run-*.lock.d/pid 2>/dev/null || true
    rmdir "$lockdir"/run-*.lock.d 2>/dev/null || true; rmdir "$lockdir" 2>/dev/null || true
    [ ! -e "$lockdir" ]
    # the losing racer: another run's mkdir lands first, so this run's `mkdir -m 700 <lockdir>` fails with EEXIST
    rc=0
    ( mkdir() { if [[ "$1" == "-m" ]]; then command mkdir "$@"; : > "$T/race.fired"; return 1; fi; command mkdir "$@"; }
      _adv_take_run_lock "$OUT_DIR" review; printf '%s' "$?" > "$T/race.rc"; printf '%s' "$_ADV_RUN_LOCK_DIR" > "$T/race.dir" ) 2>"$T/race.err" || rc=$?
    [ "$rc" = "0" ]
    # (thirty-sixth run, c1c DISS-C-001: the subshell's status is its last printf's — the lock call's own is recorded)
    [ "$(cat "$T/race.rc")" = "0" ] || { echo "the race loser's lock call returned $(cat "$T/race.rc")"; return 1; }
    # (thirty-second run, c1c DISS-C-002: the race was simulated — a lock-dir mkdir of another shape would pass untested)
    [ -e "$T/race.fired" ] || { echo "the losing-racer stub never fired: no mkdir -m ran"; return 1; }
    if grep -q "run lock is not taken" "$T/race.err"; then echo "the race loser ran unguarded: $(cat "$T/race.err")"; return 1; fi
    lockd=$(cat "$T/race.dir"); [ -n "$lockd" ]; [ -d "$lockd" ]   # two statements: a failed left operand of && never fails a test (thirtieth run, c1c DISS-C-001)
    command rm -f -- "$lockd/pid"; rmdir "$lockd" 2>/dev/null || true
}

@test "CMP-142 --diff-range's diff shows a submodule change as its short gitlink record under diff.submodule=diff — the submodule's own files never appear as top-level diff --git records (twenty-sixth run, a3 DISS-C-001)" {
    local s="$T/sub" r="$T/super"
    _cmp_git init -q "$s"; printf 'one\n' > "$s/inner.txt"; _cmp_git -C "$s" add inner.txt; _cmp_git -C "$s" commit -q -m s1
    _cmp_git init -q "$r"; _cmp_git -C "$r" submodule add -q "$s" mod >/dev/null 2>&1
    _cmp_git -C "$r" commit -q -m base
    printf 'two\n' >> "$r/mod/inner.txt"; _cmp_git -C "$r/mod" commit -qam s2
    _cmp_git -C "$r" add mod; _cmp_git -C "$r" commit -q -m head
    command git -C "$r" config diff.submodule diff
    out=$(_adv_range_diff "$r" HEAD~1...HEAD)
    if grep -q '^diff --git a/mod/inner.txt' <<<"$out"; then echo "a submodule's file surfaced as a top-level record"; return 1; fi
    grep -qx 'diff --git a/mod b/mod' <<<"$out"
    grep -q '^+Subproject commit ' <<<"$out"
}

@test "CMP-143 a --diff-range whose git diff fails, or whose temp file cannot be made, refuses with a JSON status under --json (diff_range_failed with the range / workdir_unavailable), and --record-fallback records diff_range_failed (twenty-sixth run, a4 DISS-C-001)" {
    git() {
        if [[ "${1:-}" == "-C" && " $* " == *" diff "* ]]; then echo "fatal: bad revision" >&2; return 128; fi
        command git "$@"
    }
    rc=0; result=$( main --type review --sprint-id "$SPRINT" --diff-range nosuch...HEAD --json 2>"$T/stderr.log" ) || rc=$?
    [ "$rc" = "2" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "diff_range_failed" ]
    [ "$(jq -r '.metadata.range' <<<"$result")" = "nosuch...HEAD" ]
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    grep -q "git diff nosuch...HEAD failed" "$T/stderr.log"
    unset -f git
    rc=0; result=$( export TMPDIR="$T/no/such/dir"; main --type review --sprint-id "$SPRINT" --diff-range "$(_cmp_base_ref)...HEAD" --json 2>/dev/null ) || rc=$?
    [ "$rc" = "2" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" = "workdir_unavailable" ]
    [ "$(jq -r '.metadata.tmpdir' <<<"$result")" = "$T/no/such/dir" ]
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback diff_range_failed --reason "git diff nosuch...HEAD failed" ) >"$T/out" 2>"$T/err" || rc=$?
    [ "$rc" = "0" ] || { cat "$T/err"; return 1; }
    [ "$(jq -r '.metadata.status' "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT/adversarial-review.json")" = "diff_range_failed" ]
    local r; for r in reviewing-code auditing-security; do   # (the skills are told what the status means and how to record it)
        grep -q '`diff_range_failed`' "$BATS_TEST_DIRNAME/../../.claude/skills/$r/resources/ADVERSARIAL-REVIEW.md" || { echo "$r resource lacks diff_range_failed"; return 1; }
    done
}

@test "CMP-144 a primary hop job that leaves no output file is an empty answer (the next hop, an envelope) — the read never aborts main past the run lock (twenty-sixth run, a4 DISS-C-002)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    eval "_orig_$(declare -f _adv_run_interruptible)"
    _adv_run_interruptible() {   # the first hop's job could not be forked (EAGAIN): no file, a failure status
        if [[ "$1" == */primary-hop.out && ! -e "$T/forked-once" ]]; then : > "$T/forked-once"; command rm -f -- "$1"; return 1; fi
        _orig__adv_run_interruptible "$@"
    }
    # (errexit as the script runs it: a substitution, or any subshell on the left of `||`, runs with it ignored)
    set +e; ( set -e; _run_main review > "$T/main.out" ); rc=$?; set -e; result=$(cat "$T/main.out")
    [ -e "$T/forked-once" ]
    jq -e '.metadata.status' <<<"$result" >/dev/null || { echo "no envelope (rc $rc): $(tail -5 "$T/stderr.log")"; return 1; }
}

@test "CMP-145 prepare_content estimates each chunk once — the candidate scan, the reservation scan and the include loop share one count, and the output is unchanged (twenty-sixth run, b1 DISS-C-001)" {
    mk_hunk() { printf '@@ -%d,3 +%d,4 @@ fn%d\n context\n-old line %d\n+new line %d %s\n+another line %d\n' "$1" "$1" "$1" "$1" "$1" "$(printf 'x%.0s' $(seq 1 200))" "$1"; }
    big="diff --git a/big.sh b/big.sh
--- a/big.sh
+++ b/big.sh
$(mk_hunk 10)
$(mk_hunk 40)
$(mk_hunk 70)
$(mk_hunk 100)"
    sib1=$'diff --git a/s1.sh b/s1.sh\n--- a/s1.sh\n+++ b/s1.sh\n@@ -1 +1 @@\n-a\n+'"$(printf 'y%.0s' $(seq 1 120))"
    sib2=$'diff --git a/s2.sh b/s2.sh\n--- a/s2.sh\n+++ b/s2.sh\n@@ -1 +1 @@\n-a\n+'"$(printf 'z%.0s' $(seq 1 120))"
    eval "_orig_$(declare -f estimate_tokens)"
    estimate_tokens() { printf '%s' "$1" | _cmp_sha256 | cut -c1-16 >> "$T/est.log"; _orig_estimate_tokens "$1"; }
    out=$(prepare_content "$sib1
$big
$sib2" 300 2>/dev/null)
    [[ "$out" == *"diff --git a/s1.sh b/s1.sh"* && "$out" == *"diff --git a/s2.sh b/s2.sh"* && "$out" == *"--- PARTIAL: big.sh"* ]]
    # (thirty-sixth run, c1c DISS-C-002: an estimate that no longer goes through the stub leaves no log — never a vacuous "no duplicate")
    [ -s "$T/est.log" ] && (( $(grep -c '' "$T/est.log") >= 3 )) || { echo "the estimate stub fired $(grep -c '' "$T/est.log" 2>/dev/null || echo 0) times"; return 1; }
    dup=$(sort "$T/est.log" | uniq -d)
    [ -z "$dup" ] || { echo "content estimated more than once ($(sort "$T/est.log" | uniq -c | sort -rn | head -3 | tr '\n' ' '))"; return 1; }
}

@test "CMP-146 a pre-lock refusal's --record-fallback --since <run start> never displaces an envelope written after that start — another run's, finished meanwhile — and moves an older one aside as before; without --since the previous envelope goes aside as before (twenty-sixth run, b2 DISS-C-002)" {
    mkdir -p "$OUT_DIR"
    local env="$OUT_DIR/adversarial-review.json" st rc
    for st in nothing_to_review workdir_unavailable budget_exceeded diff_range_failed; do
        command rm -f -- "$env" "$env.prev"
        printf '{"findings":[{"id":"DISS-001"}],"metadata":{"status":"reviewed","timestamp":"2026-10-02T12:30:00Z","rejected_summary":[]}}\n' > "$env"
        rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback "$st" --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
        [ "$rc" -eq 2 ] || { echo "$st: a newer envelope was displaced (rc $rc)"; return 1; }
        [ "$(jq -r '.metadata.status' "$env")" = "reviewed" ]; [ ! -e "$env.prev" ]
        grep -q "written after" "$T/err"
        rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback "$st" --since 2026-10-02T13:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
        [ "$rc" -eq 0 ] || { echo "$st: $(cat "$T/err")"; return 1; }
        [ "$(jq -r '.metadata.status' "$env")" = "$st" ]; [ "$(jq -r '.metadata.status' "$env.prev")" = "reviewed" ]
    done
    command rm -f -- "$env.prev"; printf '{"findings":[],"metadata":{"status":"reviewed","timestamp":"2026-10-02T12:30:00Z"}}\n' > "$env"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback nothing_to_review --reason r ) >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ]; [ "$(jq -r '.metadata.status' "$env.prev")" = "reviewed" ]
    local r; for r in reviewing-code auditing-security; do
        grep -q 'pre-lock.*--since\|--since.*never displaces' "$BATS_TEST_DIRNAME/../../.claude/skills/$r/resources/ADVERSARIAL-REVIEW.md" || { echo "$r: the pre-lock --since guard is not stated"; return 1; }
    done
}

@test "CMP-147 every envelope main writes says what it reviewed (metadata.scope: diff_range, the diff's sha256, run_tag — null when absent), and both resources adopt another run's envelope after refused_concurrent_run only when its scope matches (twenty-sixth run, b2 DISS-C-003)" {
    result=$(_run_main review) || { tail -5 "$T/stderr.log"; return 1; }
    local want; want=$(_cmp_sha256 < "$T/diff.patch" | cut -c1-64); [[ "$want" =~ ^[0-9a-f]{64}$ ]]
    [ "$(jq -r '.metadata.scope.diff_sha256' <<<"$result")" = "$want" ]
    [ "$(jq -r '.metadata.scope.diff_range' <<<"$result")" = "null" ]
    [ "$(jq -r '.metadata.scope.run_tag' <<<"$result")" = "null" ]
    [ "$(jq -r '.metadata.scope.diff_sha256' "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT/adversarial-review.json")" = "$want" ]
    result=$(export LOA_ADVERSARIAL_RUN_TAG=chunk-a1; _ADV_RUN_TAG_RAW_SEEN=""; _run_main review) || { tail -5 "$T/stderr.log"; return 1; }
    [ "$(jq -r '.metadata.scope.run_tag' <<<"$result")" = "chunk-a1" ]
    local r; for r in reviewing-code auditing-security; do
        grep -q 'refused_concurrent_run.*only when its `metadata.scope` is what you asked for' "$BATS_TEST_DIRNAME/../../.claude/skills/$r/resources/ADVERSARIAL-REVIEW.md" || { echo "$r resource adopts on timestamp alone"; return 1; }
    done
}

@test "CMP-148 the review skill's qmd context query carries changed file paths only — never the sprint goal or other prose a grimoire search would send off-box (twenty-sixth run, b2 DISS-C-001)" {
    local f="$BATS_TEST_DIRNAME/../../.claude/skills/reviewing-code/SKILL.md" line
    line=$(grep 'qmd-context-query.sh' "$f")
    [ -n "$line" ]
    grep -q -- '--query "<changed file paths>"' <<<"$line"
    if grep -qi 'sprint_goal\|sprint goal' <<<"$line"; then echo "the qmd query carries the sprint goal: $line"; return 1; fi
}

@test "CMP-149 _cmp_bounded ends an over-time probe's whole tree — a grandchild the probe's subshell forked never outlives the bound (twenty-sixth run, c1a DISS-C-002)" {
    _probe_deep() { ( exec -a loa-cmp149-grandchild sleep 30 & echo "$!" > "$T/gc.pid"; wait ); }
    rc=0; _cmp_bounded 1 _probe_deep 2>/dev/null || rc=$?
    [ "$rc" = "199" ]
    local gc; gc=$(cat "$T/gc.pid"); [ -n "$gc" ]
    local i; for i in $(seq 1 20); do kill -0 "$gc" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$gc" 2>/dev/null; then kill -KILL "$gc"; echo "grandchild $gc outlived the bound"; return 1; fi
}

@test "CMP-150 a hop name reaches the catalog's yq expressions as data (strenv), never spliced into the expression: a quote in a name is looked up, not a parse error, and cannot inject a yq operator (twenty-seventh run, a2 DISS-C-001)" {
    local cat="$T/quote-catalog.yaml"
    cat > "$cat" <<'YAML'
aliases:
  'we"ird': 'anthropic:claude-headless'
providers:
  anthropic:
    connect_timeout: 10
    read_timeout: 120
    models:
      'odd"hop':
        kind: cli
        headless_timeout_seconds: 777
        fallback_chain: ['claude-headless']
YAML
    [ "$(LOA_MODEL_CONFIG="$cat" _adv_hop_canon 'we"ird')" = "claude-headless" ]
    [ "$(LOA_MODEL_CONFIG="$cat" _adv_cli_hop_bound 'odd"hop')" = "787" ]
    [ "$(LOA_MODEL_CONFIG="$cat" _adv_cli_bin_for 'odd"hop')" = "claude" ]
    # an injected operator is a key that is not there, never evaluated
    printf 'secret-canary' > "$T/canary.txt"
    # (thirty-fourth run, c1c DISS-C-001: a payload that keeps the file's text — `| "` piped the canary into an empty string, so a
    # spliced lookup passed too; `//` carries it out, and the name must come back as itself: a key that is not there)
    local inj
    for inj in 'x" // load_str("'"$T"'/canary.txt") // "' 'x", load_str("'"$T"'/canary.txt"), "'; do
        [ "$(LOA_MODEL_CONFIG="$cat" _adv_hop_canon "$inj")" = "$inj" ] || { echo "injected: $(LOA_MODEL_CONFIG="$cat" _adv_hop_canon "$inj")"; return 1; }
    done
    # no yq expression in the script splices a shell variable but the fixed config tokens (thirty-sixth run, c1c DISS-C-007: every
    # yq call — `yq e`, `yq eval`, a bare `yq '…'` — and every quoting shape, single-quote concatenation and an unquoted key included)
    _cmp_yq_splices() {
        grep -nE '\byq( +(e|eval))?( +-[A-Za-z-]+)* +['"'"'".]' "$1" | grep -vE '^[0-9]+:[[:space:]]*#' \
            | sed -E 's/\$\(/(/g; s/="\$[^"]*"/=V/g; s/ "\$[A-Za-z_]+"/ FILE/g; s/\$\{(1|2|config_key|_ccf|type\/\/-\/_)\}//g; s/\$DEFAULT_[A-Z_]+//g; s/strenv\([A-Za-z_]+\)//g' \
            | grep -E '\$[A-Za-z_{]' || true
    }
    printf '%s\n' "  x=\$(yq e '.a[\"'\"\$n\"'\"]' \"\$f\")" "  y=\$(yq '.aliases.\$name' \"\$c\")" "  z=\$(yq eval \".aliases.\${hop}\" \"\$c\")" > "$T/yq150"
    [ "$(_cmp_yq_splices "$T/yq150" | grep -c '')" = "3" ] || { echo "the lint misses a splice shape: $(_cmp_yq_splices "$T/yq150")"; return 1; }
    local sp; sp=$(_cmp_yq_splices "$BATS_TEST_DIRNAME/../../.claude/scripts/adversarial-review.sh")
    [ -z "$sp" ] || { echo "a shell variable is spliced into a yq expression: $sp"; return 1; }
}

@test "CMP-151 --record-fallback failed --since over an envelope that is not JSON moves it aside as unreadable — the error's own instruction works — and never over a parseable newer one (twenty-seventh run, a2 DISS-C-002)" {
    mkdir -p "$OUT_DIR"
    local env="$OUT_DIR/adversarial-review.json" rc
    printf 'not json {\n' > "$env"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 0 ] || { echo "an unparseable envelope refused --since: $(cat "$T/err")"; return 1; }
    [ "$(jq -r '.metadata.status' "$env")" = "failed" ]
    [ "$(jq -r '.metadata.displaced.unreadable' "$env")" = "true" ]
    [ "$(cat "$env.prev")" = "not json {" ]
    # without --since it still refuses, and a parseable newer envelope still stands
    command rm -f -- "$env.prev"; printf 'not json {\n' > "$env"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --reason r ) >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 2 ]; [ "$(cat "$env")" = "not json {" ]
    printf '{"findings":[],"metadata":{"status":"reviewed","timestamp":"2026-10-02T12:30:00Z"}}\n' > "$env"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 2 ]; [ "$(jq -r '.metadata.status' "$env")" = "reviewed" ]
}

@test "CMP-152 the envelopes written outside process_findings carry metadata.scope too — the --record-fallback record and the --json refusal (diff_range / run_tag as given, diff_sha256 null: no diff was read) (twenty-seventh run, a2 DISS-C-003)" {
    mkdir -p "$OUT_DIR"
    local env="$OUT_DIR/adversarial-review.json" rc
    command rm -f -- "$env"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback nothing_to_review --reason r ) >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ "$(jq -c '.metadata.scope' "$env")" = '{"diff_range":null,"diff_oids":null,"diff_sha256":null,"run_tag":null}' ]
    command rm -f -- "$env" "$env.prev"
    rc=0; ( export LOA_ADVERSARIAL_RUN_TAG=chunk-a1; main --type review --sprint-id "$SPRINT" --diff-range main...HEAD --record-fallback diff_range_failed --reason r ) >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ]
    [ "$(jq -c '.metadata.scope' "$env")" = '{"diff_range":"main...HEAD","diff_oids":null,"diff_sha256":null,"run_tag":"chunk-a1"}' ]
    local out; out=$(type=review sprint_id="$SPRINT"; diff_range="main...HEAD"; _ADV_RUN_TAG=""; _adv_refuse_json refused_concurrent_run)
    [ "$(jq -c '.metadata.scope' <<<"$out")" = '{"diff_range":"main...HEAD","diff_oids":null,"diff_sha256":null,"run_tag":null}' ]
    [ "$(jq -r '.metadata.status' <<<"$out")" = "refused_concurrent_run" ]
}

@test "CMP-153 a companion hop's MODELINV window opens when its CLI lock is acquired (sub-second where date has it), so a row the primary wrote on the same shared hop before releasing that lock is never read as the companion's; and the audit gate's own rows are found (twenty-seventh run, a3 DISS-C-001)" {
    row() { jq -nc --arg ts "$1" --arg msg "$2" --arg p "${3:-adversarial-review}" '{event_type:"model.invoke.complete", ts_utc:$ts, payload:{models_requested:["anthropic:claude-headless"], calling_primitive:$p, models_failed:[{model:"anthropic:claude-headless", message_redacted:$msg}]}}'; }
    [[ -n "$T" && "$LOA_MODELINV_LOG_PATH" == "$T/"* ]]
    # the primary's row in the very second the companion took the lock is before a sub-second window start
    { row 2026-10-01T10:00:05.300000Z primary-row; } > "$LOA_MODELINV_LOG_PATH"
    [ -z "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05.400000000Z 2026-10-01T10:00:09Z)" ]
    { row 2026-10-01T10:00:05.300000Z primary-row; row 2026-10-01T10:00:05.500000Z companion-row; } > "$LOA_MODELINV_LOG_PATH"
    [ "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05.400000000Z 2026-10-01T10:00:09Z)" = "companion-row" ]
    # a whole-second start stays inclusive (the hop's first second), a whole-second end holds its last second
    [ "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05Z 2026-10-01T10:00:05Z)" = "companion-row" ]
    # the audit gate's rows carry calling_primitive adversarial-audit
    { row 2026-10-01T10:00:06Z audit-row adversarial-audit; } > "$LOA_MODELINV_LOG_PATH"
    [ "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05Z 2026-10-01T10:00:09Z adversarial-audit)" = "audit-row" ]
    [ -z "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05Z 2026-10-01T10:00:09Z adversarial-review)" ]
    # the window start is restamped at lock acquisition, on the locked and the unserialised path alike
    local f="$T/hop_started_iso" out
    echo 2000-01-01T00:00:00Z > "$f"
    # (the CLI lock is keyed on the binary, shared with a live run on the host's directory — thirty-fifth run, c1c DISS-C-002)
    [[ -n "$T" && "$(_adv_cli_lock_dir)" == "$T/"* ]] || { echo "the CLI lock dir $(_adv_cli_lock_dir) is not under the test directory"; return 1; }
    out=$(_ADV_HOP_START_FILE="$f" _adv_with_cli_lock claude-headless cat "$f")
    [[ "$out" =~ ^20[2-9][0-9]-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{9})?Z$ ]] || { echo "locked path: $out"; return 1; }
    echo 2000-01-01T00:00:00Z > "$f"
    out=$(_ADV_FLOCK_BIN=/nonexistent/flock _ADV_HOP_START_FILE="$f" _adv_with_cli_lock claude-headless cat "$f" 2>/dev/null)
    [[ "$out" =~ ^20[2-9][0-9]- ]] || { echo "unserialised path: $out"; return 1; }
    # an HTTP hop restamps it too — sub-second where date has %N — and turns its phase `hop` (thirtieth run, a2 DISS-001)
    local ph="$T/hop_phase"; echo 2000-01-01T00:00:00Z > "$f"; echo queue > "$ph"
    [ -z "$(_adv_cli_bin_for http-only-hop)" ]   # (no catalog chain reaches a CLI: the unlocked branch)
    out=$(_ADV_PHASE_FILE="$ph" _ADV_HOP_START_FILE="$f" _adv_with_cli_lock http-only-hop cat "$f")
    if [[ "$(date -u +%N)" =~ ^[0-9]{9}$ ]]; then
        [[ "$out" =~ ^20[2-9][0-9]-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{9}Z$ ]] || { echo "http path: $out"; return 1; }
    else
        [[ "$out" =~ ^20[2-9][0-9]- ]] || { echo "http path: $out"; return 1; }
    fi
    [ "$(cat "$ph")" = hop ]
    # the walker publishes the stamp file to the hop, and the fold passes the gate's primitive
    grep -q '_ADV_HOP_START_FILE="\$workdir/companion.hop_started_iso"' "$BATS_TEST_DIRNAME/../../.claude/scripts/adversarial-review.sh"
    grep -q '_companion_ledger_message "\$final" "\$_since" "\$_until" "adversarial-' "$BATS_TEST_DIRNAME/../../.claude/scripts/adversarial-review.sh"
}

@test "CMP-154 --diff-range's diff takes no shape from the operator's diff.relative, diff.suppressBlankEmpty or core.quotePath — byte-identical to the unconfigured diff, from the root or a subdirectory (twenty-seventh run, a3 DISS-C-002)" {
    local r="$T/shape" d
    _cmp_git init -q "$r"; mkdir -p "$r/sub"
    printf 'a\n\nb\n\nc\n' > "$r/top.txt"; printf 'x\n' > "$r/sub/in.txt"; printf 'n\n' > "$r/café.txt"
    _cmp_git -C "$r" add -A; _cmp_git -C "$r" commit -q -m base
    printf 'a\n\nB\n\nc\n' > "$r/top.txt"; printf 'y\n' > "$r/sub/in.txt"; printf 'm\n' > "$r/café.txt"
    _cmp_git -C "$r" commit -qam head
    local want_root want_sub; want_root=$(_adv_range_diff "$r" HEAD~1...HEAD); want_sub=$(_adv_range_diff "$r/sub" HEAD~1...HEAD)
    grep -q '^ $' <<<"$want_root"; grep -q '"a/caf\\303\\251.txt"' <<<"$want_root"; grep -q '^diff --git a/top.txt' <<<"$want_sub"
    command git -C "$r" config diff.relative true; command git -C "$r" config diff.suppressBlankEmpty true; command git -C "$r" config core.quotePath false
    [ "$(_adv_range_diff "$r" HEAD~1...HEAD)" = "$want_root" ] || { echo "the root diff took the operator's config"; return 1; }
    [ "$(_adv_range_diff "$r/sub" HEAD~1...HEAD)" = "$want_sub" ] || { echo "the subdirectory diff took diff.relative"; return 1; }
}

@test "CMP-155 a primary normalisation job that dies (a KILL, a failed redirect) is an unusable answer for that hop — the next hop, an envelope — never an abort past the run lock (twenty-seventh run, a4 DISS-C-001)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    eval "_orig_$(declare -f _adv_run_interruptible)"
    _adv_run_interruptible() {
        if [[ "$1" == */primary-findings.out && ! -e "$T/killed-once" ]]; then : > "$T/killed-once"; command rm -f -- "$1"; return 137; fi
        _orig__adv_run_interruptible "$@"
    }
    set +e; ( set -e; _run_main review > "$T/main.out" ); rc=$?; set -e; result=$(cat "$T/main.out")
    [ -e "$T/killed-once" ]
    jq -e '.metadata.status' <<<"$result" >/dev/null || { echo "no envelope (rc $rc): $(tail -5 "$T/stderr.log")"; return 1; }
}

@test "CMP-156 the exit cleanup removes the workdir even when the --diff-range temp file cannot be unlinked — the rm is not the errexit-live tail of an && list (twenty-seventh run, a4 DISS-C-003)" {
    local ro="$T/ro" wd="$T/wd-156"
    mkdir -p "$ro" "$wd"; : > "$ro/adversarial-range-x"; chmod 555 "$ro"
    if command rm -f -- "$ro/adversarial-range-x" 2>/dev/null; then chmod 755 "$ro"; skip "rm in a read-only dir succeeds here (root)"; fi
    set +e; ( set -e; _ADV_RANGE_DIFF="$ro/adversarial-range-x"; _ADVERSARIAL_WORKDIR="$wd"; _adv_cleanup_on_exit; echo returned > "$T/ret-156" ) 2>/dev/null; set -e
    chmod 755 "$ro"
    [ ! -d "$wd" ] || { echo "the workdir was left behind"; return 1; }
    [ -s "$T/ret-156" ]
}

@test "CMP-157 metadata.scope names the commits a --diff-range resolved to (diff_oids) on the refusal and the envelope alike, and both resources adopt another run's envelope only on a scope equal to the refusal's own (twenty-seventh run, a4 DISS-C-002)" {
    local b=1111111111111111111111111111111111111111 h=2222222222222222222222222222222222222222 out
    out=$(type=review sprint_id="$SPRINT"; diff_range="main...HEAD"; _ADV_RANGE_OIDS="$b $h"; _ADV_RUN_TAG=""; _adv_refuse_json refused_concurrent_run)
    [ "$(jq -c '.metadata.scope.diff_oids' <<<"$out")" = "{\"base\":\"$b\",\"head\":\"$h\"}" ]
    local r; for r in reviewing-code auditing-security; do
        grep -q 'refused_concurrent_run.*`diff_oids`' "$BATS_TEST_DIRNAME/../../.claude/skills/$r/resources/ADVERSARIAL-REVIEW.md" || { echo "$r adopts on the range string alone"; return 1; }
    done
}

@test "CMP-158 the COMPLETED gate opens on a run's envelope and never on a --record-fallback record (no metadata.model): a failed dissent is recorded, never passed off as one (twenty-seventh run, b2 DISS-C-006)" {
    local hook="$PROJECT_ROOT/.claude/hooks/safety/adversarial-review-gate.sh" cfg="$T/gate.yaml" rc
    printf 'flatline_protocol:\n  code_review:\n    enabled: true\n' > "$cfg"
    _gate() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s/COMPLETED"}}' "$OUT_DIR" \
        | env -u LOA_ADVERSARIAL_REVIEW_ENFORCE LOA_CONFIG_PATH_OVERRIDE="$cfg" bash "$hook" 2>/dev/null; }
    mkdir -p "$OUT_DIR"; command rm -f -- "$OUT_DIR/adversarial-review.json"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --reason r ) >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ]; [ "$(jq -r '.metadata.status' "$OUT_DIR/adversarial-review.json")" = "failed" ]
    rc=0; _gate || rc=$?
    [ "$rc" -eq 2 ] || { echo "a fallback record opened the gate (rc $rc)"; return 1; }
    command rm -f -- "$OUT_DIR"/adversarial-review.json*
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    _run_main review >/dev/null
    [ "$(jq -r '.metadata.model // empty' "$OUT_DIR/adversarial-review.json")" != "" ]
    rc=0; _gate || rc=$?
    [ "$rc" -eq 0 ] || { echo "a run's envelope did not open the gate (rc $rc)"; return 1; }
    # the audit resource states what the hook checks
    local res="$PROJECT_ROOT/.claude/skills/auditing-security/resources/ADVERSARIAL-REVIEW.md"
    ! grep -q 'checks that this file exists, not its contents' "$res" || { echo "the audit resource says the hook checks existence only"; return 1; }
    grep -q 'never opens the gate' "$res"
}

@test "CMP-159 the shipped docs say what the code does: an empty or failed dissent still triages its rejected payloads, an operator companion_chain is not PATH-filtered, the review/audit invariants row names the dissent's side effects, and no_route degrades every audit (twenty-seventh run, b2 DISS-C-001/003/004/005)" {
    local root="$PROJECT_ROOT" r
    for r in reviewing-code auditing-security; do
        ! grep -q 'invocation failed: log and continue' "$root/.claude/skills/$r/resources/ADVERSARIAL-REVIEW.md" || { echo "$r: a failed run skips its record"; return 1; }
    done
    grep -q '^   - If `findings` is empty.*`## Rejected dissent payloads`' "$root/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md"
    grep -q -- '--sprint-id <sprint_id>' "$root/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md"
    ! grep -q 'reviewer_concerns_file' "$root/.claude/skills/reviewing-code/resources/ADVERSARIAL-REVIEW.md" || { echo "the review resource names a removed flag"; return 1; }
    ! grep -q 'used as given; the CLI hop' "$root/.loa.config.yaml.example" || { echo "the config example says an operator chain is PATH-filtered"; return 1; }
    grep -q 'no PATH filter' "$root/.loa.config.yaml.example"
    grep -q '^| Sprint review/audit .*adversarial-review\.sh' "$root/.claude/rules/skill-invariants.md"
    ! grep -q 'so audits do not turn degraded by default' "$root/CHANGELOG.md" || { echo "the CHANGELOG says no_route keeps audits clean"; return 1; }
    grep -q 'no_route.*DEGRADED_SECURITY_REVIEW.*companion_voice: false' "$root/CHANGELOG.md"
    # an operator chain really is used as given: a CLI hop whose binary is absent stays planned
    _adv_cli_present() { return 1; }
    [ "$(CONF_COMPANION_CHAIN_ANTHROPIC="opus claude-headless"; _companion_chain anthropic)" = "opus claude-headless" ]
    [[ " $(CONF_COMPANION_CHAIN_ANTHROPIC=""; _companion_chain anthropic) " != *" claude-headless "* ]]
}

@test "CMP-160 a companion_chain family list is read in a fixed number of yq calls, not two per element, and classifies each element as before (twenty-eighth run, a1 DISS-C-002)" {
    local hops; hops=$(printf 'claude-headless,%.0s' $(seq 1 30)); hops="[${hops%,} , {a: 1}, ~, [b, c], \"x y\", 12, \"multi\\nline\"]"
    _cfg_edit $'  code_review:\n    enabled: true\n' "  code_review:"$'\n'"    enabled: true"$'\n'"    companion_chain:"$'\n'"      anthropic: ${hops}"$'\n'
    run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; yq() { echo x >> '$T/yq-calls'; command yq \"\$@\"; }; _adv_conf_chain_hops code_review anthropic"
    [ "$status" -eq 0 ]
    calls=$(grep -c '' "$T/yq-calls")
    (( calls <= 4 )) || { echo "$calls yq calls for a 36-element list"; return 1; }
    [ "$(grep -o 'claude-headless' <<<"$(tail -n 1 <<<"$output")" | grep -c '')" = "30" ]
    [ "$(grep -c 'is not a hop name' <<<"$output")" = "6" ]
    for _i in 30 31 32 33 34 35; do grep -q "companion_chain.anthropic\[$_i\] is not a hop name" <<<"$output"; done
    grep -q 'anthropic\[30\] is not a hop name (!!map)' <<<"$output"
    grep -q 'anthropic\[34\] is not a hop name (!!int)' <<<"$output"
    if grep -q 'x y\|multi' <<<"$output"; then return 1; fi   # a dropped value is never echoed
    # the element pass itself failing is said, and the default applies — never a partial chain
    run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; yq() { case \"\$*\" in *'[tag, .]'*) return 1 ;; *) command yq \"\$@\" ;; esac; }; _adv_conf_chain_hops code_review anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" == *"companion_chain.anthropic could not be read — the default anthropic chain applies"* ]]
    [[ "$(tail -n 1 <<<"$output")" != *claude-headless* ]]
}

@test "CMP-161 a run releases its lock inside the per-key takeover section: a taker judging the holder never sees the lock vanish and another run's appear under the same name mid-section; a section held past the wait still releases, and says so (twenty-eighth run, a2 DISS-C-001)" {
    _need_flock
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"; [ -d "$lockd" ]
    tl="${lockd%.lock.d}.takeover.lock"
    # a taker inside the section until the sampler has looked (bounded): the release waits for it — never a fixed 2 s the sampler
    # had to beat on a loaded host (thirty-fifth run, c1c DISS-C-005; the release's own wait is 5 s)
    ( exec 7>>"$tl"; "${_ADV_FLOCK_BIN:-flock}" 7; : > "$T/in-section"; for _ in $(seq 1 100); do [ -e "$T/go" ] && break; sleep 0.1; done ) 3>&- & HOLDER_PIDS+=("$!"); sec=$!
    for _ in $(seq 1 50); do [ -e "$T/in-section" ] && break; sleep 0.1; done; [ -e "$T/in-section" ]
    # (the release runs here — only the acquiring BASHPID releases — and a sampler watches the lock from outside)
    ( sleep 0.5; [ -d "$lockd" ] && : > "$T/still-held"; : > "$T/go" ) 3>&- & samp=$!; HOLDER_PIDS+=("$samp")
    _adv_release_run_lock
    wait "$samp" 2>/dev/null || true
    [ -e "$T/still-held" ] || { echo "the lock was released while a taker held the section"; return 1; }
    [ ! -d "$lockd" ]
    wait "$sec" 2>/dev/null || true
    # a section held past the release's wait: the lock is still released (a dead run's lock must never outlive it), and that is said
    _adv_take_run_lock "$OUT_DIR" review; lockd="$_ADV_RUN_LOCK_DIR"; [ -d "$lockd" ]
    # (thirty-sixth run, c1c DISS-C-003: the holder outlasts the bound by far, and the bound the 5 s wait — a loaded host's stall is
    # not a red, a release that waited for the holder still is)
    ( exec 7>>"$tl"; "${_ADV_FLOCK_BIN:-flock}" 7; : > "$T/in-section2"; exec sleep 40 ) 3>&- & HOLDER_PIDS+=("$!"); sec=$!
    for _ in $(seq 1 50); do [ -e "$T/in-section2" ] && break; sleep 0.1; done; [ -e "$T/in-section2" ]
    t0=$(date +%s)
    _adv_release_run_lock 2>"$T/rel-err"
    (( $(date +%s) - t0 <= 20 )) || { echo "the release took $(( $(date +%s) - t0 )) s: it waited for the holder"; return 1; }
    [ ! -d "$lockd" ]
    grep -q 'released unserialised' "$T/rel-err"
    kill "$sec" 2>/dev/null || true
    # (thirty-third run, c1c DISS-C-001: the holder that was ended is the one holding the section — a forked sleep kept fd 7,
    # and the flock with it, for the rest of its sleep after the test ended)
    wait "$sec" 2>/dev/null || true
    ( exec 7>>"$tl"; "${_ADV_FLOCK_BIN:-flock}" -n 7 ) 3>&- || { echo "the takeover section is still held after its holder was ended"; return 1; }
}

@test "CMP-162 a refusal envelope carries the documented metadata keys only — its scope once, as metadata.scope, never a stray copy of a jq binding (twenty-eighth run, a2 DISS-C-002)" {
    out=$(type=review sprint_id="$SPRINT" _adv_refuse_json nothing_to_review reason "no diff")
    [ "$(jq -c '.metadata | keys' <<<"$out")" = '["cost_usd","model","reason","scope","sprint_id","status","timestamp","type"]' ] || { jq -c '.metadata | keys' <<<"$out"; return 1; }
    [ "$(jq -r '.metadata.reason' <<<"$out")" = "no diff" ]
    [ "$(jq -r '.metadata.scope | type' <<<"$out")" = "object" ]
}

@test "CMP-163 a model's family is its vendor, never its host: a Bedrock-hosted Claude is anthropic — its companion is the OpenAI chain and a Claude companion beside it is the same family, never an independent voice (twenty-eighth run, a2 DISS-C-004)" {
    local m
    for m in us.anthropic.claude-opus-4-8 us.anthropic.claude-haiku-4-5-20251001-v1:0 bedrock:us.anthropic.claude-sonnet-4-6 anthropic:claude-headless claude-headless opus; do
        [ "$(_adv_family_of "$m")" = "anthropic" ] || { echo "$m → $(_adv_family_of "$m")"; return 1; }
    done
    [ "$(_companion_family "$(_adv_family_of us.anthropic.claude-opus-4-8)")" = "openai" ]
    # (the independence judgement compares the two answering ids' families)
    [ "$(_adv_family_of claude-headless)" = "$(_adv_family_of us.anthropic.claude-opus-4-8)" ]
    # vendors that are their own family stay so; a prefix names the host only when it is not a family
    [ "$(_adv_family_of gpt-5.5-pro)" = "openai" ]
    [ "$(_adv_family_of openai:gpt-5.5)" = "openai" ]
    [ "$(_adv_family_of gemini-3.1-pro)" = "google" ]
    [ "$(_adv_family_of grok-fast)" = "xai" ]
    [ "$(_adv_family_of xai:grok-fast)" = "xai" ]
    [ "$(_adv_family_of composer-2.5)" = "cursor" ]
    # a Bedrock model of another vendor is not passed off as anthropic
    [ "$(_adv_family_of bedrock:amazon.nova-pro-v1:0)" != "anthropic" ]
    # every generated provider value is a vendor or the one host the family reader sets aside — a new host
    # (vertex, azure) must be taught to _adv_family_of before it ships (thirtieth run, a2 C-001, refuted and pinned)
    # (thirty-fourth run, c1c DISS-C-002: the values are read on their own first — an unsourceable map or an empty / renamed array
    # is a red, never an empty `bad` behind the grep's `|| true`)
    local bad vals vrc=0
    vals=$(bash -c 'declare -A MODEL_IDS=() MODEL_PROVIDERS=(); source "$1" >/dev/null 2>&1 || exit 3; (( ${#MODEL_PROVIDERS[@]} > 0 )) || exit 4; printf "%s\n" "${MODEL_PROVIDERS[@]}"' _ "$BATS_TEST_DIRNAME/../../.claude/scripts/generated-model-maps.sh") || vrc=$?
    [ "$vrc" = 0 ] && [ -n "$vals" ] || { echo "the generated provider map could not be read (rc $vrc)"; return 1; }
    bad=$(printf '%s\n' "$vals" | sort -u | grep -vxE 'anthropic|openai|google|xai|cursor|bedrock') || true
    [ -z "$bad" ] || { echo "unhandled provider values: $bad"; return 1; }
}

@test "CMP-164 --diff-range's diff takes no shape from diff.context, interHunkContext, renames, algorithm, orderFile, noprefix, mnemonicPrefix or indentHeuristic — byte-identical to the unconfigured diff — and pins diff.relative by config, not the git ≥ 2.28 --no-relative flag (twenty-eighth run, a3 DISS-C-001 / DISS-C-004)" {
    local r="$T/shape2" i
    _cmp_git init -q "$r"
    for i in $(seq 1 30); do printf 'line %s\n' "$i"; done > "$r/b.txt"
    for i in $(seq 1 40); do printf 'src %s\n' "$i"; done > "$r/src.txt"
    printf 'z\n' > "$r/z.txt"
    _cmp_git -C "$r" add -A; _cmp_git -C "$r" commit -q -m base
    sed 's/^line 10$/LINE 10/; s/^line 20$/LINE 20/' "$r/b.txt" > "$r/b.new"; command mv -f -- "$r/b.new" "$r/b.txt"; printf 'z2\n' > "$r/z.txt"   # (no GNU-only sed -i)
    cp "$r/src.txt" "$r/copy.txt"; printf 'src 41\n' >> "$r/src.txt"
    _cmp_git -C "$r" add -A; _cmp_git -C "$r" commit -q -m head
    local want; want=$(_adv_range_diff "$r" HEAD~1...HEAD)
    grep -q '^diff --git a/b.txt b/b.txt' <<<"$want"; [ "$(grep -c '^@@' <<<"$(sed -n '/^diff --git a\/b.txt/,/^diff --git a\/[^b]/p' <<<"$want")")" = 2 ]
    printf 'z.txt\n' > "$T/order"
    for kv in diff.context=0 diff.interHunkContext=10 diff.renames=copies diff.algorithm=histogram "diff.orderFile=$T/order" \
              diff.noprefix=true diff.mnemonicPrefix=true diff.indentHeuristic=false; do command git -C "$r" config "${kv%%=*}" "${kv#*=}"; done
    [ "$(_adv_range_diff "$r" HEAD~1...HEAD)" = "$want" ] || { echo "the diff took the operator's config"; diff <(printf '%s\n' "$want") <(_adv_range_diff "$r" HEAD~1...HEAD) | head -20; return 1; }
    # the argv: diff.relative pinned as config (a git < 2.28 ignores an unknown key; it rejects an unknown flag)
    local body; body=$(declare -f _adv_range_diff)
    grep -q 'diff.relative=false' <<<"$body"; ! grep -q -- '--no-relative' <<<"$body"
}

@test "CMP-165 the fallback classifier reads 429 as a status code, never a digit run inside a duration or an id (twenty-eighth run, a3 DISS-C-002)" {
    [ "$(_companion_failure_class api_failure 1 'PROVIDER_UNAVAILABLE: upstream reset after 4290ms')" = "model_unavailable" ]
    [ "$(_companion_failure_class api_failure 1 'request id req_14291 failed')" = "model_unavailable" ]
    [ "$(_companion_failure_class api_failure 1 'HTTP 429 Too Many Requests')" = "quota" ]
    [ "$(_companion_failure_class api_failure 1 'status=429: slow down')" = "quota" ]
    [ "$(_companion_failure_class api_failure 1 '429')" = "quota" ]
    [ "$(_companion_failure_class api_failure 1 'Rate limit reached')" = "quota" ]
}

@test "CMP-166 a shared hop's failed_it reads any provider spelling of the hop in the attempts rows — the canonical prefix rule, not a lower-case one (twenty-eighth run, a3 DISS-C-003)" {
    mkdir -p "$T/vw166"; printf 'done' > "$T/vw166/companion.phase"; printf 'opus' > "$T/vw166/companion.final"
    local row
    for row in 'Bedrock:claude-headless:api_failure' 'openai-compat:claude-headless:api_failure' 'ANTHROPIC:claude-headless:lock_wait' 'claude-headless:api_failure'; do
        printf 'opus:api_failure\n%s\n' "$row" > "$T/vw166/companion.attempts"
        [ "$(_adv_shared_hop_verdict claude-headless "$T/vw166" 0 10 | cut -f1,2)" = "$(printf 'run\tfailed_it')" ] || { echo "row $row not read as the hop"; return 1; }
    done
    for row in 'claude-headless-x:api_failure' 'x:claude-headless-y:api_failure' 'claude-headless'; do
        printf '%s\n' "$row" > "$T/vw166/companion.attempts"
        [ "$(_adv_shared_hop_verdict claude-headless "$T/vw166" 0 10 | cut -f1,2)" = "$(printf 'run\tfinished_without_it')" ] || { echo "row $row read as the hop"; return 1; }
    done
}

@test "CMP-167 the exit cleanup releases the run lock even when the workdir cannot be fully removed — the rm -rf is guarded, its failure logged (twenty-eighth run, a4 DISS-C-001)" {
    local wd="$T/wd-167"
    mkdir -p "$wd/stuck"; : > "$wd/stuck/f"; chmod 555 "$wd/stuck"
    if command rm -f -- "$wd/stuck/f" 2>/dev/null; then chmod 755 "$wd/stuck"; skip "rm in a read-only dir succeeds here (root)"; fi
    set +e; ( set -e; _adv_release_run_lock() { echo released > "$T/rel-167"; }; _ADV_RANGE_DIFF=""; _ADVERSARIAL_WORKDIR="$wd"; _adv_cleanup_on_exit; echo returned > "$T/ret-167" ) 2>"$T/err-167"; set -e
    chmod 755 "$wd/stuck"
    [ -s "$T/rel-167" ] || { echo "the run lock was not released"; return 1; }
    [ -s "$T/ret-167" ]
    grep -q 'could not be removed' "$T/err-167"
}

@test "CMP-168 a findings job that dies on the LAST primary hop is that hop's malformed_response envelope — never an empty envelope written over the previous round's (twenty-eighth run, a4 DISS-C-002)" {
    eval "_orig_$(declare -f _adv_run_interruptible)"
    _adv_run_interruptible() {
        if [[ "$1" == */primary-findings.out ]]; then : > "$T/killed-168"; command rm -f -- "$1"; return 137; fi
        _orig__adv_run_interruptible "$@"
    }
    set +e; ( set -e; _run_main review > "$T/main.out" ); rc=$?; set -e; result=$(cat "$T/main.out")
    [ -e "$T/killed-168" ]
    # with the companion: the primary's failure is recorded and the envelope degraded — never a companion-only clean envelope
    jq -e '(.metadata.primary_voice.status == "failed") and (.metadata.primary_voice.error | test("findings pass ended without an answer"))
           and .metadata.degraded == true and (.metadata.model_attempts | length) == 3 and (.metadata.final_model | length) > 0' <<<"$result" >/dev/null \
        || { echo "rc $rc, metadata: $(jq -c '.metadata | del(.rejected_summary)' <<<"$result" 2>/dev/null | cut -c1-600)"; return 1; }
    # alone: that hop's malformed_response envelope
    _cfg_edit $'enabled: true\n' $'enabled: true\n    companion_voice: false\n'
    set +e; ( set -e; _run_main review > "$T/main2.out" ); rc=$?; set -e; result=$(cat "$T/main2.out")
    jq -e 'type == "object" and .metadata.status == "malformed_response" and .findings == [] and (.metadata.error | test("findings pass"))' <<<"$result" >/dev/null \
        || { echo "rc $rc, envelope: ${result:0:400}"; return 1; }
}

@test "CMP-169 no negative array subscript in the script — bash < 4.3 rejects \${a[-1]} (twenty-eighth run, a4 DISS-C-003)" {
    # (thirty-sixth run, c1c DISS-C-005: the subscript itself — ${#a[-1]}, ${!a[-1]}, ${a[ -1]}, ${a[-$n]}, a[-1]=x, (( a[-1] )) —
    # not only the ${name[- prefix)
    local re='[A-Za-z_][A-Za-z0-9_]*\[[[:space:]]*-[[:space:]]*[0-9$]'
    printf '%s\n' 'x=${#a[-1]}' 'x=${!a[-1]}' 'x=${a[ -1]}' 'x=${a[-$n]}' 'a[-1]=x' '(( a[-1] ))' > "$T/neg169"
    [ "$(grep -cE "$re" "$T/neg169")" = "6" ] || { echo "the lint misses a negative-subscript shape"; return 1; }
    run grep -nE "$re" "$ADVERSARIAL_REVIEW"
    [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "CMP-170 both resources say a --record-fallback record never opens the COMPLETED gate, with its remedy; both skills allowlist the br and log-discovered-issue steps they prescribe, narrowly (twenty-eighth run, b2 DISS-C-001 / DISS-C-002)" {
    local s r f sub
    for s in reviewing-code auditing-security; do
        r="$PROJECT_ROOT/.claude/skills/$s/resources/ADVERSARIAL-REVIEW.md"
        grep -q 'never opens the gate' "$r" || { echo "$s: the resource does not say a fallback record never opens the gate"; return 1; }
        grep -q 'LOA_ADVERSARIAL_REVIEW_ENFORCE=false' "$r" || { echo "$s: no remedy named"; return 1; }
    done
    # every br step the skill (or its beads resource) instructs is granted — by subcommand, never `br *`
    for s in reviewing-code auditing-security; do
        f="$PROJECT_ROOT/.claude/skills/$s/SKILL.md"
        for sub in 'comments add' 'label add'; do
            grep -q "Bash(br $sub \*)" "$f" || { echo "$s: br $sub not allowlisted"; return 1; }
            grep -qF "args: [$(sed 's/\([a-z]*\)/"\1"/g; s/ /, /g' <<<"$sub"), \"*\"]" "$f" || { echo "$s: capabilities miss br $sub"; return 1; }
        done
        if grep -q 'Bash(br \*)' "$f"; then echo "$s: a blanket br grant"; return 1; fi
        # sync as its two sanctioned forms, never `br sync *` — that admits --force, --merge, --rebuild (twenty-ninth run, b2 DISS-C-004)
        for sub in import-only flush-only; do
            grep -qF "Bash(br sync --$sub)" "$f" || { echo "$s: br sync --$sub not allowlisted"; return 1; }
            grep -qF "args: [\"sync\", \"--$sub\"]" "$f" || { echo "$s: capabilities miss br sync --$sub"; return 1; }
        done
        if grep -qF 'Bash(br sync *)' "$f" || grep -qF 'args: ["sync", "*"]' "$f"; then echo "$s: a wildcard br sync grant"; return 1; fi
    done
    f="$PROJECT_ROOT/.claude/skills/auditing-security/SKILL.md"
    grep -q 'Bash(.claude/scripts/beads/log-discovered-issue.sh \*)' "$f"
    grep -q 'command: ".claude/scripts/beads/log-discovered-issue.sh"' "$f"
}

@test "CMP-171 the kept-workdir sweep in TMPDIR never follows nor fails on a symlink at a workdir path — the suite's one link rule (twenty-eighth run, c1a DISS-C-001)" {
    local tgt="$T/link-171" lnk="${TMPDIR:-/tmp}/adversarial-${SPRINT}-lnk171" rc=0
    # (thirty-sixth run, c1c DISS-C-004: a link an interrupted run left at this pid-scoped name is replaced, never an EEXIST)
    mkdir -p "$tgt"; : > "$tgt/keep"; if [[ -L "$lnk" ]]; then command rm -f -- "$lnk"; fi; ln -s "$tgt" "$lnk"
    ( set -e; CMP_OWN_TMP=""; teardown ) 3>&- & wait $! || rc=$?
    command rm -f -- "$lnk"
    [ "$rc" -eq 0 ] || { echo "a symlinked workdir path failed the teardown (rc $rc)"; return 1; }
    [ -e "$tgt/keep" ]
}

@test "CMP-172 on a /proc host a start token is always the starttime form — a failed /proc read is unknown, never the lstart form a reader compares unlike, so a live holder's lock is never taken over as recycled (twenty-eighth regression, CMP-63 under load)" {
    [[ -r /proc/self/stat ]] || skip "no /proc: the lstart form is the only form"
    _need_flock
    sleep 300 3>&- & local p=$!; HOLDER_PIDS+=("$p")
    local tok; tok=$(awk() { return 1; }; _adv_proc_start "$p") || tok=""
    [ -z "$tok" ] || { echo "a failed /proc read gave the token '$tok' — another form than a reader's"; return 1; }
    # a live holder whose token was taken under that failure keeps its lock
    _adv_take_run_lock "$OUT_DIR" review; local lockd="$_ADV_RUN_LOCK_DIR"; _ADV_RUN_LOCK_DIR=""
    printf '%s\n%s\n' "$p" "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$p" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\{1,\}/_/g')" > "$lockd/pid"
    local rc=0; ( _adv_take_run_lock "$OUT_DIR" review ) 2>/dev/null || rc=$?
    [ "$(sed -n 1p "$lockd/pid" 2>/dev/null)" = "$p" ] || { echo "a live holder's lock (an lstart token) was taken over"; return 1; }
    [ "$rc" -eq 1 ]
    command rm -f -- "$lockd/pid"; rmdir "$lockd"
}

@test "CMP-173 a one-element companion_chain list whose element pass fails is said as unreadable — an empty read is no row, never the one row a list of one would have (twenty-ninth run, a1 DISS-C-001)" {
    _cfg_edit $'  code_review:\n    enabled: true\n' "  code_review:"$'\n'"    enabled: true"$'\n'"    companion_chain:"$'\n'"      anthropic: [claude-headless]"$'\n'
    run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; yq() { case \"\$*\" in *'[tag, .]'*) return 1 ;; *) command yq \"\$@\" ;; esac; }; _adv_conf_chain_hops code_review anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" == *"companion_chain.anthropic could not be read — the default anthropic chain applies"* ]] || { echo "$output"; return 1; }
    [[ "$output" != *"is a list with no hop name"* ]]
    # the healthy one-element list still reads its hop
    run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; _adv_conf_chain_hops code_review anthropic"
    [ "$status" -eq 0 ]
    [ "$(tail -n 1 <<<"$output")" = "claude-headless" ]
}

@test "CMP-174 a catalog alias is resolved before its family is judged: an alias of a Claude model is anthropic — its companion is the OpenAI chain and a Claude companion beside it is never independent (twenty-ninth run, a2 DISS-C-001)" {
    local cat="$T/cat-174.yaml"
    cp "$PROJECT_ROOT/.claude/defaults/model-config.yaml" "$cat"
    yq -i '.aliases["my-claude"] = "anthropic:claude-opus-4-8" | .aliases["my-host-claude"] = "bedrock:us.anthropic.claude-opus-4-8" | .aliases["my-gpt"] = "openai:gpt-5.5" | .aliases["my-loop"] = "my-loop"' "$cat"
    export LOA_MODEL_CONFIG="$cat"
    [ "$(_adv_family_of my-claude)" = "anthropic" ] || { echo "my-claude → $(_adv_family_of my-claude)"; return 1; }
    [ "$(_adv_family_of my-host-claude)" = "anthropic" ]
    [ "$(_adv_family_of my-gpt)" = "openai" ]
    [ "$(_companion_family "$(_adv_family_of my-claude)")" = "openai" ]
    # the shipped aliases name their target's family
    [ "$(_adv_family_of reviewer)" = "openai" ]
    [ "$(_adv_family_of deep-thinker)" = "google" ]
    # one level only: an alias naming itself ends, and an unaliased id is judged as before
    [ "$(_adv_family_of my-loop)" = "unknown" ]
    [ "$(_adv_family_of claude-headless)" = "anthropic" ]
    [ "$(_adv_family_of us.anthropic.claude-opus-4-8)" = "anthropic" ]
    # the canonical hop name still resolves through the same reader
    [ "$(_adv_hop_canon my-gpt)" = "gpt-5.5" ]
}

@test "CMP-175 a run lock made by another run between this run's third round and its last mkdir is a live holder: refused, never run unguarded beside it — while a dead run's lock that cannot be moved aside still runs unguarded, and says why (twenty-ninth run, a2 DISS-C-002)" {
    _need_flock
    _adv_take_run_lock "$OUT_DIR" review; local lockd="$_ADV_RUN_LOCK_DIR"; _ADV_RUN_LOCK_DIR=""
    command rm -f -- "$lockd/pid"; rmdir "$lockd"
    sleep 300 3>&- & local p=$!; HOLDER_PIDS+=("$p")
    ( exit 0 ) & local dead=$!; wait "$dead" 2>/dev/null || true
    : > "$T/mk"
    # every mkdir of the lock loses: rounds one to three to a dead run (taken over each time), the last to a live one
    mkdir() {
        if [[ "$*" == "$lockd" ]]; then
            echo x >> "$T/mk"; command mkdir "$lockd" 2>/dev/null || true
            if (( $(grep -c '' "$T/mk") < 4 )); then printf '%s\n\n' "$dead" > "$lockd/pid"
            else printf '%s\n%s\n' "$p" "$(_adv_proc_start "$p")" > "$lockd/pid"; fi
            echo "mkdir: cannot create directory '$lockd': File exists" >&2; return 1
        fi
        command mkdir "$@"
    }
    local rc=0; ( _adv_take_run_lock "$OUT_DIR" review ) 2>"$T/err" || rc=$?
    unset -f mkdir
    [ "$(grep -c '' "$T/mk")" = "4" ] || { echo "$(grep -c '' "$T/mk") lock mkdirs"; cat "$T/err"; return 1; }
    [ "$rc" -eq 1 ] || { echo "rc $rc: $(cat "$T/err")"; return 1; }
    [ "$(sed -n 1p "$lockd/pid")" = "$p" ]
    if grep -q 'NOT guarded' "$T/err"; then echo "ran unguarded beside a live holder"; return 1; fi
    command rm -f -- "$lockd/pid"; rmdir "$lockd"
    # a dead run's lock whose rename fails every round: not a holder — the run proceeds unguarded and names the cause
    command mkdir "$lockd"; printf '%s\n\n' "$dead" > "$lockd/pid"
    rc=0; ( mv() { return 1; }; _adv_take_run_lock "$OUT_DIR" review ) 2>"$T/err" || rc=$?
    [ "$rc" -eq 0 ] || { echo "rc $rc: $(cat "$T/err")"; return 1; }
    grep -q "could not be moved aside" "$T/err" || { cat "$T/err"; return 1; }
    command rm -f -- "$lockd/pid"; rmdir "$lockd"
}

@test "CMP-176 --record-fallback failed --since: a standing envelope whose timestamp cannot be dated (fractional seconds, no Z, not a string) goes aside as the other statuses move it, never a refusal naming the --since already passed (twenty-ninth run, a2 DISS-C-003)" {
    mkdir -p "$OUT_DIR"
    local env="$OUT_DIR/adversarial-review.json" ts rc
    for ts in '"2026-10-01T10:00:00.123Z"' '"2026-10-01T10:00:00"' '"2026-10-01 10:00:00Z"' 1759312800; do
        printf '{"findings":[],"metadata":{"status":"reviewed","timestamp":%s,"rejected_summary":[]}}\n' "$ts" > "$env"; command rm -f -- "$env.prev"
        rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
        [ "$rc" -eq 0 ] || { echo "$ts: rc $rc — $(cat "$T/err")"; return 1; }
        [ "$(jq -r '.metadata.status' "$env")" = "failed" ]
        [ "$(jq -r '.metadata.status' "$env.prev")" = "reviewed" ]
    done
    # a canonical timestamp after the run start is still that run's own: refused
    printf '{"findings":[],"metadata":{"status":"reviewed","timestamp":"2026-10-03T10:00:00Z","rejected_summary":[]}}\n' > "$env"; command rm -f -- "$env.prev"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 2 ]
    [ ! -e "$env.prev" ]
}

@test "CMP-177 a failed companion's diagnostic is read from its own gate's ledger rows: the fold sees main's --type through bash's dynamic scope, so an audit run queries adversarial-audit, never review (twenty-ninth run, a3 DISS-001 — refuted, pinned)" {
    local wd="$T/fold-177"; mkdir -p "$wd"
    printf 'claude-headless' > "$wd/companion.final"; printf 'failed' > "$wd/companion.status"; printf '1' > "$wd/companion.rc"
    _companion_ledger_message() { printf '%s\n' "$4" >> "$T/prim-177"; return 1; }
    _w177() { local type="$1"; _fold_companion '{"findings":[],"metadata":{"status":"reviewed"}}' "$wd" anthropic claude-headless codex-headless >/dev/null 2>&1; }
    : > "$T/prim-177"
    _w177 audit; _w177 review
    [ "$(tr '\n' ' ' < "$T/prim-177")" = "adversarial-audit adversarial-review " ] || { cat "$T/prim-177"; return 1; }
    # and the fold declares no `type` of its own that would shadow main's
    if declare -f _fold_companion | grep -qE '(local|declare)[^#]*[[:space:]]type([=[:space:]]|$)'; then echo "the fold shadows type"; return 1; fi
}

@test "CMP-178 the companion's post-hop budget is what its repairs are held to — the repair wall budget plus one hop that overran its estimate — never the chain × the per-run count, several times larger; a short chain keeps the smaller product; the run's own repair timeout sizes it (twenty-ninth run, a3 DISS-C-001)" {
    printf 'providers:\n  anthropic:\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 1200\n  openai:\n    models:\n      gpt-5.5-pro:\n        context_window: 1000\n        fallback_chain: ["openai:codex-headless"]\n      codex-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 800\n' > "$T/pb-catalog.yaml"
    export LOA_MODEL_CONFIG="$T/pb-catalog.yaml"
    # keyless: charges claude-headless 1240, gpt-5.5-pro 870 — the wall budget 1240 × 2 + 30, + the heaviest hop, + 60
    [ "$(_companion_post_budget gpt-5.5-pro 30)" = "3810" ] || { echo "post budget $(_companion_post_budget gpt-5.5-pro 30)"; return 1; }
    # an operator pin on the wall budget bounds it the same way (validated; a bad pin is the default, said by the repair loop only)
    [ "$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=100 _companion_post_budget gpt-5.5-pro 30)" = "$(( 100 + 1240 + 60 ))" ]
    [ "$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=x _companion_post_budget gpt-5.5-pro 30 2>"$T/pb-err")" = "3810" ]
    [ ! -s "$T/pb-err" ]
    # one HTTP hop: its five charges are below the wall budget — the product stands
    local _orig_cbf; _orig_cbf=$(declare -f _adv_cli_bin_for)
    _adv_cli_bin_for() { echo ""; }
    [ "$(LOA_ADVERSARIAL_REPAIR_MODEL=plain-y _companion_post_budget m 60)" = "$(( 60 * ADV_REPAIR_MAX_PER_RUN + 60 ))" ]
    eval "$_orig_cbf"   # (the script's own helper restored, never deleted — thirty-fifth run, c1c DISS-C-001)
    # the caller passes the timeout the repairs use (CONF_TIMEOUT), not the hop --timeout
    grep -q 'companion_post_budget=$(_adv_num_or "$(_companion_post_budget_chain "${CONF_TIMEOUT:-60}" $companion_chain_str)" 60)' "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    # and the repair loop reads the same wall budget
    [ "$(_adv_repair_wall_for 1240 30)" = "2510" ]
    [ "$(_adv_repair_wall_for 10 60)" = "$(( ADV_REPAIR_MAX_PER_RUN * 120 ))" ]
    grep -q '_repair_wall_budget=$(_adv_repair_wall_for "$_rmax" "${CONF_TIMEOUT:-60}")' "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
}

@test "CMP-179 the KILL escalation loses no pid collected at TERM: a sort that keeps any line of an equal-keyed run may drop one from the merge, and that pid's own turn of the loop collects it again (twenty-ninth run, a3 DISS-C-002 — refuted, pinned)" {
    bash -c 'trap "" TERM; exec -a "$0" sleep 300' "loa-cmp30-stubborn-$$" 3>&- & local p=$!; HOLDER_PIDS+=("$p"); _await_stubborn "$p"
    bash -c 'trap "" TERM; exec -a "$0" sleep 300' "loa-cmp30-stubborn-$$" 3>&- & local c=$!; HOLDER_PIDS+=("$c"); _await_stubborn "$c"
    # TERM reached both (a child since reparented: the root's tree no longer holds it)
    local _orig_kt; _orig_kt=$(declare -f _adv_kill_tree)
    _adv_kill_tree() { kill -TERM "$p" "$c" 2>/dev/null || true; _adv_pid_tokens "$p $c"; }
    # a sort that keeps the LAST line of an equal-keyed run (POSIX leaves it unspecified; the reversal in awk — tac is GNU-only,
    # thirty-fifth run, c1c DISS-C-004)
    sort() { awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }' | command sort -s "$@"; }
    _ADV_COMPANION_PID=$p; _ADV_COMPANION_START=$(_adv_proc_start "$p")
    LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1 _adv_reap_companion 2>/dev/null
    unset -f sort; eval "$_orig_kt"   # (thirty-fifth run, c1c DISS-C-001)
    sleep 0.3
    if kill -0 "$c" 2>/dev/null; then echo "pid $c (collected at TERM) survived the KILL"; return 1; fi
    if kill -0 "$p" 2>/dev/null; then echo "root $p survived the KILL"; return 1; fi
}

@test "CMP-180 --diff-range's diff shows a submodule's gitlink under diff.ignoreSubmodules=all, and its text hunks under a global attributes file marking them -diff — the operator's config never hides what the range changed (twenty-ninth run, a3 DISS-C-003)" {
    local s="$T/sub3" r="$T/super3"
    _cmp_git init -q "$s"; printf 'one\n' > "$s/inner.txt"; _cmp_git -C "$s" add inner.txt; _cmp_git -C "$s" commit -q -m s1
    _cmp_git init -q "$r"; _cmp_git -C "$r" submodule add -q "$s" mod >/dev/null 2>&1
    printf 'a\n' > "$r/t.txt"; _cmp_git -C "$r" add t.txt
    _cmp_git -C "$r" commit -q -m base
    printf 'two\n' >> "$r/mod/inner.txt"; _cmp_git -C "$r/mod" commit -qam s2
    printf 'b\n' >> "$r/t.txt"
    _cmp_git -C "$r" add mod t.txt; _cmp_git -C "$r" commit -q -m head
    command git -C "$r" config diff.ignoreSubmodules all
    printf '*.txt -diff\n' > "$T/attrs"; command git -C "$r" config core.attributesFile "$T/attrs"
    out=$(_adv_range_diff "$r" HEAD~1...HEAD)
    grep -qx 'diff --git a/mod b/mod' <<<"$out" || { echo "the gitlink was hidden"; echo "$out"; return 1; }
    grep -q '^+Subproject commit ' <<<"$out"
    if grep -q '^Binary files' <<<"$out"; then echo "a text hunk read as binary"; return 1; fi
    grep -qx '+b' <<<"$out"
    # …nor does the repository's own .gitattributes, since the thirty-fifth run (e2a DISS-C-002, CMP-231: attributes are read from
    # the empty tree on git >= 2.40); .git/info/attributes, the operator's own, still applies (CMP-186)
    # (thirty-sixth run, c1c DISS-C-006: an old git is a skip the run shows; a version that cannot be read is a red, never a pass)
    local gv; gv=$(_cmp_git version) || { echo "git version failed"; return 1; }
    [[ "$gv" =~ ^git\ version\ ([0-9]+)\.([0-9]+) ]] || { echo "unreadable git version: $gv"; return 1; }
    (( BASH_REMATCH[1] > 2 || (BASH_REMATCH[1] == 2 && BASH_REMATCH[2] >= 40) )) || skip "git < 2.40 reads no attributes from the empty tree"
    printf '*.txt -diff\n' > "$r/.gitattributes"
    grep -qx '+b' <<<"$(_adv_range_diff "$r" HEAD~1...HEAD)" || { echo "the tree's own .gitattributes hid the hunk"; return 1; }
}

@test "CMP-181 a findings pass killed on the last hop with the companion disabled writes an envelope verdict-derive reads CONSISTENT — an absent rejected_summary beside the FR-2 markers is the empty array, as on process_findings' own malformed_response envelopes (twenty-ninth run, a4 DISS-C-001 — refuted, pinned)" {
    eval "_orig_$(declare -f _adv_run_interruptible)"
    _adv_run_interruptible() {
        if [[ "$1" == */primary-findings.out ]]; then command rm -f -- "$1"; return 137; fi
        _orig__adv_run_interruptible "$@"
    }
    _cfg_edit $'enabled: true\n' $'enabled: true\n    companion_voice: false\n'
    set +e; ( set -e; _run_main review > "$T/main.out" ); set -e
    local env="$T/env-181.json"; cp "$T/main.out" "$env"
    jq -e '.metadata.status == "malformed_response" and (.metadata | has("rejected_sidecars") and has("companion_voice"))' "$env" >/dev/null
    printf 'All good\n\nNothing found.\n\n<!-- LOA-VERDICT {"gate":"review","verdict":"APPROVED","counts":{"critical":0,"high":0,"medium":0,"low":0}} -->\n' > "$T/fb-181.md"
    run bash "$PROJECT_ROOT/.claude/scripts/verdict-derive.sh" --file "$T/fb-181.md" --gate review --envelope "$env"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [[ "$output" == *"CONSISTENT: gate=review"* ]]
}

@test "CMP-182 the review skill's qmd step is a no-op when the script is missing; the audit's Phase 0 refuses a review envelope without metadata.model — the gate's COMPLETED check — and names its remedy; both beads resources say a teammate reports through the lead and a comment carries the verdict and the feedback path only (twenty-ninth run, b2 DISS-001 / DISS-C-003 / DISS-C-004)" {
    local f="$PROJECT_ROOT/.claude/skills/reviewing-code/SKILL.md" r s
    grep 'qmd-context-query.sh --query "<changed file paths>"' "$f" | grep -q 'missing' || { echo "the qmd step does not name a missing script as a no-op"; return 1; }
    f="$PROJECT_ROOT/.claude/skills/auditing-security/SKILL.md"
    r=$(awk '/^## Phase 0: Prerequisites Check/,/^## Phase 0.5/' "$f")
    grep -q 'metadata.model' <<<"$r" || { echo "Phase 0 does not check the review envelope's metadata.model"; return 1; }
    grep -q 'adversarial-review.json' <<<"$r"
    grep -q 'STOP' <<<"$r"
    # the gate it mirrors requires the same field
    grep -q 'metadata.model' "$PROJECT_ROOT/.claude/hooks/safety/adversarial-review-gate.sh"
    for s in reviewing-code auditing-security; do
        r="$PROJECT_ROOT/.claude/skills/$s/resources/BEADS-WORKFLOW.md"
        grep -q 'SendMessage' "$r" || { echo "$s: no Agent Teams note"; return 1; }
        grep -q "the verdict and the feedback file's path" "$r" || { echo "$s: the comment body is not bounded"; return 1; }
    done
}

@test "CMP-183 the suite's own helpers hold to its bash floor and its delete rule: teardown removes this test's sprint directory only, never a sibling sprint-comp-<pid>-x; no negative array subscript; the timeout branch's tree expansion is set -u safe when the tree came back empty (twenty-ninth run, c1a DISS-001 / DISS-C-001 / DISS-C-002)" {
    local f="$PROJECT_ROOT/tests/unit/adversarial-review-companion.bats" sib="$OUT_DIR-sib183" rc=0
    mkdir -p "$OUT_DIR" "$sib"; : > "$sib/keep"
    ( CMP_OWN_TMP=""; teardown ) 3>&- & wait $! || rc=$?
    [ -e "$sib/keep" ] || { echo "teardown deleted a sibling it never made"; return 1; }
    find "$sib" -mindepth 1 -delete; rmdir "$sib"
    [ "$rc" -eq 0 ]
    : > "${OUT_DIR%/*}/.$SPRINT.owner"
    # bash 4.2: no negative subscript anywhere in the suite (`unset 'a[-1]'`, `${a[-1]}`)
    if grep -nE "(\\\$\\{[A-Za-z_]+|unset '?[A-Za-z_]+)\\[-[0-9]+\\]" "$f" | grep -vE '^[0-9]+:[[:space:]]*(#|@test)'; then echo "a negative subscript"; return 1; fi
    # the kill of an empty tree is set -u safe below bash 4.4
    grep -qF 'kill -KILL ${tree[@]+"${tree[@]}"} "$pid"' "$f"
    _adv_tree_pids() { :; }
    rc=0; ( set -u; _cmp_bounded 1 sleep 5 ) 2>"$T/b-err" || rc=$?
    [ "$rc" -eq 199 ] || { echo "rc $rc: $(cat "$T/b-err")"; return 1; }
    grep -q 'still running after 1 s' "$T/b-err"
}

@test "CMP-184 a finding the pass cannot append fails that hop loudly — malformed_response and the chain falls through — never a reviewed envelope short of a finding (thirtieth run, a1 DISS-C-002, refuted and pinned)" {
    eval "_orig_$(declare -f validate_anchor)"
    validate_anchor() {   # the first call emits nothing — an anchor pass that failed on one finding
        if [[ ! -e "$T/va-184" ]]; then : > "$T/va-184"; return 0; fi
        _orig_validate_anchor "$@"
    }
    _cfg_edit $'enabled: true\n' $'enabled: true\n    companion_voice: false\n'
    set +e; ( set -e; _run_main review > "$T/main.out" 2>/dev/null ); rc=$?; set -e; result=$(cat "$T/main.out")
    [ -e "$T/va-184" ]
    jq -e '(.metadata.model_attempts[0] | test(":malformed_response$")) and (.metadata.model_attempts | length) >= 2
           and .metadata.status == "reviewed"' <<<"$result" >/dev/null \
        || { echo "rc $rc: $(jq -c '{s: .metadata.status, n: (.findings | length), ma: .metadata.model_attempts}' <<<"$result" 2>/dev/null)"; return 1; }
}

@test "CMP-185 the companion's post budget is sized from the hops the companion can answer on — its repairs walk the answering hop's chain — never from the primary's: a companion answering on a heavier CLI hop is not reaped mid-repair (thirtieth run, a3 DISS-C-001)" {
    printf 'providers:\n  anthropic:\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 300\n  openai:\n    models:\n      gpt-5.5-pro:\n        context_window: 1000\n      codex-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 2000\n' > "$T/pb185.yaml"
    export LOA_MODEL_CONFIG="$T/pb185.yaml"
    local prim comp chain
    prim=$(_companion_post_budget opus 30); comp=$(_companion_post_budget codex-headless 30)
    (( comp > prim )) || { echo "fixture: codex $comp vs primary $prim"; return 1; }
    chain=$(_companion_post_budget_chain 30 gpt-5.5-pro codex-headless)
    [ "$chain" = "$comp" ] || { echo "chain $chain, codex $comp, primary $prim"; return 1; }
    # the largest of the hops, whatever their order; an empty chain is the floor
    [ "$(_companion_post_budget_chain 30 codex-headless gpt-5.5-pro)" = "$comp" ]
    [ "$(_companion_post_budget_chain 30)" = "60" ]
}

@test "CMP-186 --diff-range's diff reads no system-wide gitattributes — GIT_ATTR_NOSYSTEM reaches git — while the repository's own .git/info/attributes still applies (thirtieth run, a3 DISS-C-002)" {
    git() { printf '%s\n' "${GIT_ATTR_NOSYSTEM:-unset}" > "$T/nosys"; }
    _adv_range_diff "$PROJECT_ROOT" HEAD~1...HEAD >/dev/null
    unset -f git
    [ "$(cat "$T/nosys")" = "1" ] || { echo "GIT_ATTR_NOSYSTEM: $(cat "$T/nosys")"; return 1; }
    # the variable is the git call's alone — never exported to the caller
    [ -z "${GIT_ATTR_NOSYSTEM:-}" ]
    local r="$T/infoattr"
    _cmp_git init -q "$r"; printf 'a\n' > "$r/t.txt"; _cmp_git -C "$r" add t.txt; _cmp_git -C "$r" commit -q -m base
    printf 'b\n' >> "$r/t.txt"; _cmp_git -C "$r" commit -qam head
    grep -qx '+b' <<<"$(_adv_range_diff "$r" HEAD~1...HEAD)"
    printf '*.txt -diff\n' > "$r/.git/info/attributes"
    grep -q '^Binary files' <<<"$(_adv_range_diff "$r" HEAD~1...HEAD)"
}

@test "CMP-189 --diff-range's diff carries three lines of context whatever GIT_DIFF_OPTS the operator exported — git lets it override -U — and the caller's own GIT_DIFF_OPTS is left as it was (thirty-first run, a4 DISS-C-001)" {
    local r="$T/diffopts"
    _cmp_git init -q "$r"; printf '1\n2\n3\n4\n5\n6\n7\n' > "$r/f"; _cmp_git -C "$r" add f; _cmp_git -C "$r" commit -q -m base
    printf '1\n2\n3\nX\n5\n6\n7\n' > "$r/f"; _cmp_git -C "$r" commit -qam head
    [ "$(_adv_range_diff "$r" HEAD~1...HEAD | grep -c '^ ')" = "6" ]   # the positive control
    local v
    for v in -u0 -u --unified=0 -u1; do
        [ "$(GIT_DIFF_OPTS="$v" _adv_range_diff "$r" HEAD~1...HEAD | grep -c '^ ')" = "6" ] || { echo "GIT_DIFF_OPTS=$v"; return 1; }
    done
    export GIT_DIFF_OPTS=-u0
    _adv_range_diff "$r" HEAD~1...HEAD >/dev/null
    [ "$GIT_DIFF_OPTS" = "-u0" ]; unset GIT_DIFF_OPTS
}

@test "CMP-187 a previous round's file that cannot be moved aside refuses the run before it reviews anything — never a stale envelope or sidecar read as this run's — and the refusal releases the run lock (thirtieth run, a4 DISS-C-001)" {
    mkdir -p "$OUT_DIR"
    jq -n '{findings: [], metadata: {type: "review", model: "m", status: "reviewed", timestamp: "2026-01-01T00:00:00Z"}}' > "$OUT_DIR/adversarial-review.json"
    prev_env=$(cat "$OUT_DIR/adversarial-review.json")
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    # an unwritable a2a directory: the envelope stands, nothing moved, the refusal says which file
    if [[ "$(id -u)" != 0 ]]; then
        chmod a-w "$OUT_DIR"
        rc=0; result=$(_run_main review) || rc=$?
        chmod u+w "$OUT_DIR"
        [ "$rc" = 2 ] || { echo "rc $rc: $result"; return 1; }
        [ "$(jq -r '.metadata.status + " " + .metadata.path' <<<"$result")" = "workdir_unavailable grimoires/loa/a2a/$SPRINT/adversarial-review.json" ]
        [ "$(cat "$OUT_DIR/adversarial-review.json")" = "$prev_env" ]; [ ! -e "$OUT_DIR/adversarial-review.json.prev" ]
        grep -q 'could not be moved aside' "$T/stderr.log"
    fi
    # a sidecar that cannot move (the envelope could): refused too — a canonical sidecar is counted as this run's
    printf '{"reject_reason":"earlier"}\n' > "$OUT_DIR/adversarial-rejected-review.jsonl"
    mv() { case "$*" in *adversarial-rejected-review.jsonl*) return 1 ;; esac; command mv "$@"; }
    rc=0; result=$(_run_main review) || rc=$?
    unset -f mv
    [ "$rc" = 2 ] || { echo "rc $rc: $result"; return 1; }
    [ "$(jq -r '.metadata.status + " " + .metadata.path' <<<"$result")" = "workdir_unavailable grimoires/loa/a2a/$SPRINT/adversarial-rejected-review.jsonl" ]
    # the lock is released: the next run reviews
    command rm -f -- "$OUT_DIR/adversarial-rejected-review.jsonl"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ] || { jq -c .metadata <<<"$result"; return 1; }
}

@test "CMP-188 every shell step either review skill or its beads resource prescribes is granted under deny_raw_shell, byte for byte — allowed-tools and capabilities alike — or is a native-tool step (thirtieth run, b2 DISS-C-002 / DISS-C-003)" {
    run python3 - "$PROJECT_ROOT" <<'PY'
import fnmatch, re, sys, yaml
root = sys.argv[1]
WORDS = r'(?:find|ls|wc|yq|jq|mkdir|source|cat|grep|git|br|xargs|tail|head|sed|awk|cp|mv|rm|touch|chmod|python3|bash|echo|test)'
SPAN = re.compile(r'`((?:\.claude/scripts/|' + WORDS + r' )[^`]*)`')
bad = []
for s in ('reviewing-code', 'auditing-security'):
    text = open(f'{root}/.claude/skills/{s}/SKILL.md', encoding='utf-8').read()
    _, fm, body = text.split('---\n', 2)
    meta = yaml.safe_load(fm)
    grants = [g.strip()[5:-1] for g in meta['allowed-tools'].split(', ') if g.strip().startswith('Bash(')]
    caps = meta['capabilities']['execute_commands']
    assert caps['deny_raw_shell'] is True
    cap_cmds = {c['command'] for c in caps['allowed']}
    spans = SPAN.findall(body)
    # the beads resource: its backticked commands and every command line of a bash block, as written
    res = open(f'{root}/.claude/skills/{s}/resources/BEADS-WORKFLOW.md', encoding='utf-8').read()
    spans += [x for x in SPAN.findall(res) if x.startswith(('br ', '.claude/scripts/'))]
    for block in re.findall(r'```bash\n(.*?)```', res, re.S):
        spans += [l for l in block.splitlines() if l.strip() and not l.lstrip().startswith('#')]
    for span in spans:
        if '{' in span.split()[0]:
            continue
        hit = [g for g in grants if fnmatch.fnmatchcase(span, g) or (g.endswith(' *') and span == g[:-2])]
        if not hit:
            bad.append(f'{s}: `{span}` is prescribed but no Bash grant admits it')
        elif not any(h.split()[0] in cap_cmds for h in hit):
            bad.append(f'{s}: `{span}` is granted in allowed-tools but not in capabilities.execute_commands')
print('\n'.join(bad))
sys.exit(1 if bad else 0)
PY
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    # the shared integrity step reads the config natively — never a yq call no review skill may run
    grep -q '`yq ' "$PROJECT_ROOT/.claude/data/skill-includes/integrity_precheck.md" && { echo "integrity_precheck still prescribes yq"; return 1; }
    true
}

@test "CMP-190 the CHANGELOG states the contracts that ship, not superseded ones: a pre-run-lock status is recorded with --record-fallback (no hand-made .prev recipe), the repair chain ends at the voice that answered, the rejected_summary row is the full key set, and a sidecar newer than a pre-FR-2 envelope counts (thirty-first run, e2a DISS-C-001/002)" {
    local cl="$PROJECT_ROOT/CHANGELOG.md"
    ! grep -q 'move the stale envelope and sidecars aside as `.prev` and write the fallback' "$cl" || { echo "the retired hand-written fallback recipe"; return 1; }
    ! grep -q 'goes to `tiny` with an Anthropic credential present, else `claude-headless`' "$cl" || { echo "a repair chain without its last hop"; return 1; }
    grep -q 'the voice that answered, so an OpenAI-only host without `claude` repairs through its own primary' "$cl"
    ! grep -q '(`{severity, title, anchor, reason, description_head}`)' "$cl" || { echo "a five-key rejected_summary row"; return 1; }
    grep -q '`{index, severity, title, title_derived, anchor, reason, description_head}`' "$cl"
    ! grep -q 'counts no sidecar rows, so historical sprints' "$cl" || { echo "an unconditional legacy pass"; return 1; }
    grep -q 'a sidecar newer than it (a run that died after writing rows) counts' "$cl"
    grep -q 'every envelope since #832 carries `rejected_count`' "$cl" || { echo "the pre-FR-2 marker set unstated"; return 1; }
    # the key set named is the one the script writes
    grep -q "index: \$idx, severity: null, title: null, title_derived: false, anchor: null, reason: \$r, description_head: null" "$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
}

@test "CMP-191 --record-fallback names the remedy that applies: failed --since over a newer envelope says it is another run's (never 'pass --since' again), and an envelope path that is not a regular file is refused with its own remedy on every status — never an unclearable --since loop, never a record moved into a directory (thirty-second run, a2 DISS-C-001)" {
    mkdir -p "$OUT_DIR"
    local env="$OUT_DIR/adversarial-review.json" rc st
    printf '{"findings":[],"metadata":{"status":"reviewed","timestamp":"2026-10-02T12:30:00Z"}}\n' > "$env"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 2 ]
    grep -q "another run's: triage it" "$T/err" || { cat "$T/err"; return 1; }
    ! grep -q 'pass --since' "$T/err" || { echo "the remedy already taken is prescribed again: $(cat "$T/err")"; return 1; }
    [ "$(jq -r '.metadata.status' "$env")" = "reviewed" ]
    # a symlink (dangling) and a directory at the envelope path: no run writes either — refused, named, left as found
    command rm -f -- "$env"; ln -s "$T/nowhere.json" "$env"
    for st in failed workdir_unavailable; do
        rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback "$st" --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
        [ "$rc" -eq 2 ] || { echo "$st over a symlink: rc $rc"; return 1; }
        grep -q "is not a regular file" "$T/err" || { echo "$st: $(cat "$T/err")"; return 1; }
        ! grep -q 'pass --since' "$T/err" || { echo "$st over a symlink names --since as the remedy"; return 1; }
        [ -L "$env" ] && [ ! -e "$T/nowhere.json" ]
    done
    command rm -f -- "$env"; mkdir "$env"
    for st in failed nothing_to_review; do
        rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback "$st" --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
        [ "$rc" -eq 2 ] || { echo "$st over a directory: rc $rc"; return 1; }
        grep -q "is not a regular file" "$T/err" || { echo "$st: $(cat "$T/err")"; return 1; }
        [ -z "$(ls -A "$env")" ] || { echo "$st wrote into the directory: $(ls -A "$env")"; return 1; }
    done
    rmdir -- "$env"
}

@test "CMP-192 a companion reaped while it still queued for the CLI lock never sent its request: it is lock_wait, as the walker classes the same event, never a provider timeout; one reaped on its hop stays wait_timeout (thirty-second run, a3 DISS-C-001)" {
    local ph
    for ph in queue hop; do
        mkdir -p "$T/q-$ph"; printf '%s' "$ph" > "$T/q-$ph/companion.phase"; printf 'claude-headless' > "$T/q-$ph/companion.current"
        sleep 30 3>&- & _ADV_COMPANION_PID=$!; HOLDER_PIDS+=("$_ADV_COMPANION_PID"); _ADV_COMPANION_START=$(_adv_proc_start "$_ADV_COMPANION_PID")
        _adv_reap_companion_timed_out "$T/q-$ph" "claude-headless" 2>/dev/null
        [ "$(cat "$T/q-$ph/companion.rc")" = "124" ]
        [ "$(cat "$T/q-$ph/companion.final")" = "claude-headless" ]
    done
    [ "$(cat "$T/q-queue/companion.status")" = "lock_wait" ]
    [ "$(_companion_failure_class "$(cat "$T/q-queue/companion.status")" 124)" = "lock_wait" ]
    [ "$(cat "$T/q-hop/companion.status")" = "wait_timeout" ]
    [ "$(_companion_failure_class "$(cat "$T/q-hop/companion.status")" 124)" = "timeout" ]
}

@test "CMP-193 a reviewer killed between _adv_kill_tree's STOP and CONT passes never leaves the tree stopped: a detached watchdog resumes it, so a frozen claude -p never holds the per-binary lock for good (thirty-second run, a3 DISS-C-003)" {
    sleep 30 3>&- & local victim=$!; HOLDER_PIDS+=("$victim")
    export _ADV_CONT_WATCHDOG_SECONDS=2   # (the default is longer: the watchdog is cancelled on the normal path — CMP-204)
    # the token pass runs while the tree is frozen; the stub KILLs the shell running _adv_kill_tree right there
    _adv_pid_tokens() { kill -KILL "$KT_SHELL"; sleep 5; }
    ( KT_SHELL=$BASHPID; _adv_kill_tree "$victim" TERM tokens ) >/dev/null 2>&1 3>&- || true
    [[ "$(ps -o stat= -p "$victim")" == T* ]] || { echo "the stub never ran inside the freeze: $(ps -o stat= -p "$victim")"; return 1; }
    local i; for i in $(seq 1 60); do [[ "$(ps -o stat= -p "$victim")" == T* ]] || break; sleep 0.1; done
    [[ "$(ps -o stat= -p "$victim")" != T* ]] || { echo "pid $victim is still stopped after 6 s"; kill -CONT "$victim"; return 1; }
    kill -0 "$victim"   # resumed, not killed: the signal pass never ran
    # the normal path is unchanged: the tree is signalled and resumed at once, and nothing waits on the watchdog
    sleep 30 3>&- & local v2=$!; HOLDER_PIDS+=("$v2")
    local t0=$SECONDS out; out=$(_adv_kill_tree "$v2" TERM)
    [ "$out" = "$v2" ]; [ $(( SECONDS - t0 )) -lt 2 ]
    sleep 0.3; ! kill -0 "$v2" 2>/dev/null
}

@test "CMP-194 a symlink, directory or other node at the envelope path refuses the run before it reviews anything, with its own remedy — never a two-voice run whose envelope is lost into a directory or written through a link (thirty-second run, a4 DISS-C-001)" {
    mkdir -p "$OUT_DIR"
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    local env="$OUT_DIR/adversarial-review.json" kind
    for kind in dangling link dir; do
        command rm -f -- "$env"; [[ -d "$env" ]] && rmdir -- "$env"
        case "$kind" in
            dangling) ln -s "$T/nowhere-194.json" "$env" ;;
            link) printf '{"findings":[]}' > "$T/elsewhere-194.json"; ln -s "$T/elsewhere-194.json" "$env" ;;
            dir) mkdir "$env" ;;
        esac
        : > "$T/stderr.log"
        rc=0; result=$(_run_main review) || rc=$?
        [ "$rc" = 2 ] || { echo "$kind: rc $rc: $result"; return 1; }
        [ "$(jq -r '.metadata.status + " " + .metadata.path' <<<"$result")" = "workdir_unavailable grimoires/loa/a2a/$SPRINT/adversarial-review.json" ] || { echo "$kind: $result"; return 1; }
        grep -q 'is not a regular file' "$T/stderr.log" || { echo "$kind: $(cat "$T/stderr.log")"; return 1; }
        [ ! -e "$env.prev" ] && [ ! -L "$env.prev" ]
        case "$kind" in
            dangling) [ -L "$env" ] && [ ! -e "$T/nowhere-194.json" ] ;;
            link) [ -L "$env" ] && [ "$(cat "$T/elsewhere-194.json")" = '{"findings":[]}' ] ;;
            dir) [ -d "$env" ] && [ -z "$(ls -A "$env")" ] ;;
        esac
    done
    rmdir -- "$env"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ] || { jq -c .metadata <<<"$result"; return 1; }
}

@test "CMP-195 a hop job whose output redirect never happened reads as an empty answer on every hop — never the previous hop's file (thirty-second run, a4 DISS-C-002)" {
    local f="$T/hop-195.out"
    printf 'previous hop answer' > "$f"
    chmod a-w "$f"   # the job's redirect cannot open it: the job never writes this hop's answer
    rc=0; _adv_run_interruptible "$f" printf 'this hop' 2>/dev/null || rc=$?
    local got; got=$(cat "$f" 2>/dev/null) || got=""
    [[ "$got" != "previous hop answer" ]] || { echo "the previous hop's file was read as this hop's answer"; return 1; }
    # the normal path: the job's stdout is the answer
    _adv_run_interruptible "$f" printf 'second hop'
    [ "$(cat "$f")" = "second hop" ]
}

@test "CMP-196 a partial view with lower-priority rows behind it and no sibling at its tier stays inside the budget with its marker: the three-quarter cap never leaves the marker uncharged (thirty-second run, b1 DISS-001)" {
    mk() { local p=$1 n=$2 h l; printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n' "$p" "$p" "$p" "$p"; for h in $(seq 1 "$n"); do printf '@@ -%d,3 +%d,3 @@\n' "$h" "$h"; for l in 1 2 3; do printf '+line %d of hunk %d with some padding text here\n' "$l" "$h"; done; done; }
    mk1() { local p=$1 l; printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1,300 +1,300 @@\n' "$p" "$p" "$p" "$p"; for l in $(seq 1 300); do printf '+line %d with some padding text here\n' "$l"; done; }
    local big mt out kind
    # (a budget the marker alone fills — under ~50 tokens — stays the pinned marker-only floor, CMP-44)
    for kind in hunks onehunk; do
    if [[ "$kind" == hunks ]]; then big="$(mk src/auth/login.ts 400)"; else big="$(mk1 src/auth/login.ts)"; fi
    big+=$'\n'"$(mk docs/readme.md 3)"
    for mt in 60 80 100 120 140 160 200 400 1000; do
        out=$(prepare_content "$big" "$mt" 2>/dev/null)
        out=${out%%$'\n'"--- TRUNCATED:"*}   # (the omitted-files footer is a notice after the budgeted content — not charged, as before)
        [ "$(estimate_tokens "$out")" -le "$mt" ] || { echo "$kind budget $mt: $(estimate_tokens "$out") tokens sent"; return 1; }
        [[ "$out" == *"--- PARTIAL: src/auth/login.ts"* ]] || { echo "$kind budget $mt: no partial marker"; return 1; }
    done
    done
    big="$(mk src/auth/login.ts 400)"$'\n'"$(mk docs/readme.md 3)"
    # the cap still keeps a quarter for the lower rows at a working budget: the view is no larger than three quarters plus its marker
    out=$(prepare_content "$big" 4000 2>/dev/null)
    [ "$(estimate_tokens "${out%%--- PARTIAL*}")" -le 3000 ]
}

@test "CMP-197 the suite's harness helpers keep their guarantees on any host: an unmatched _cfg_edit fails under PYTHONOPTIMIZE (an assert is stripped there), and _cmp_git never reads the operator's ~/.gitconfig on a git that ignores GIT_CONFIG_GLOBAL (< 2.32) (thirty-second run, c1a DISS-C-001 / DISS-C-002)" {
    printf 'a: 1\n' > "$CONFIG_FILE.197"
    local CONFIG_FILE="$CONFIG_FILE.197" rc
    rc=0; PYTHONOPTIMIZE=1 _cfg_edit 'no-such-text' 'x' 2>/dev/null || rc=$?
    [ "$rc" -ne 0 ] || { echo "an unmatched _cfg_edit passed under PYTHONOPTIMIZE"; return 1; }
    [ "$(cat "$CONFIG_FILE")" = "a: 1" ]
    PYTHONOPTIMIZE=1 _cfg_edit 'a: 1' 'a: 2'; [ "$(cat "$CONFIG_FILE")" = "a: 2" ]
    # a git older than 2.32 ignores GIT_CONFIG_GLOBAL: modelled by a git on PATH that drops it before the real one runs
    local real; real=$(command -v git)
    mkdir -p "$T/oldgit" "$T/home197"
    printf '#!/usr/bin/env bash\nunset GIT_CONFIG_GLOBAL\nexec %q "$@"\n' "$real" > "$T/oldgit/git"; chmod +x "$T/oldgit/git"
    printf '[loatest]\n\tleak = yes\n' > "$T/home197/.gitconfig"
    local got
    got=$(HOME="$T/home197" PATH="$T/oldgit:$PATH" _cmp_git config --get loatest.leak 2>/dev/null) || true
    [ -z "$got" ] || { echo "the operator's ~/.gitconfig reached the scratch repo: loatest.leak=$got"; return 1; }
    # (the model is faithful: the same git reads it when the helper's isolation is bypassed)
    [ "$(HOME="$T/home197" PATH="$T/oldgit:$PATH" GIT_CONFIG_GLOBAL=/dev/null git config --get loatest.leak)" = "yes" ]
}

@test "CMP-198 a prescribed beads step is never read as two unconditional commands: each br label add in the review resource sits under its own condition comment; the CHANGELOG's FR-2 bullet never says the fallback record applies 'only' when no envelope stands (thirty-second run, e2b DISS-C-005 / e2a DISS-C-001)" {
    run python3 - "$PROJECT_ROOT/.claude/skills/reviewing-code/resources/BEADS-WORKFLOW.md" <<'PY'
import re, sys
bad = []
for block in re.findall(r'```bash\n(.*?)```', open(sys.argv[1], encoding='utf-8').read(), re.S):
    lines = block.splitlines()
    for i, l in enumerate(lines):
        if l.startswith('br label add '):
            prev = lines[i - 1] if i else ''
            if not re.match(r'#\s*If\b', prev):
                bad.append(f'`{l}` has no condition comment directly above it (got: {prev!r})')
print('\n'.join(bad)); sys.exit(1 if bad else 0)
PY
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    [ "$(grep -c '^br label add ' "$PROJECT_ROOT/.claude/skills/reviewing-code/resources/BEADS-WORKFLOW.md")" -eq 2 ]
    ! grep -q "fallback record applies only then" "$PROJECT_ROOT/CHANGELOG.md" || { echo "the FR-2 bullet contradicts its own --since rule"; return 1; }
    grep -q 'the review skill.s fallback record applies then, and after a pre-run-lock status' "$PROJECT_ROOT/CHANGELOG.md"
}

@test "CMP-199 no assertion in the dissent suites is a bare mid-test negation: bats' errexit ignores a \`! cmd\`, so one that is not a test's last command never fails it — each is explicit (thirty-second run, e3 DISS-C-001: found by its mutation proof)" {
    cat > "$T/neg-lint.py" <<'PY'
import re, sys
bad = []
for f in sys.argv[1:]:
    L = open(f, encoding='utf-8').read().split('\n'); intest = False
    for i, l in enumerate(L):
        if l.startswith('@test'): intest = True; continue
        if intest and l.startswith('}'): intest = False; continue
        if not (intest and re.match(r'\s*! ', l)) or '||' in l or l.rstrip().endswith(('\\', '|', '&&')): continue
        j = i + 1
        while j < len(L) and (not L[j].strip() or L[j].strip().startswith('#')): j += 1
        if j < len(L) and not L[j].startswith('}'): bad.append(f'{f}:{i + 1}: {l.strip()}')
print('\n'.join(bad)); sys.exit(1 if bad else 0)
PY
    run python3 "$T/neg-lint.py" "$PROJECT_ROOT"/tests/unit/adversarial-review*.bats "$PROJECT_ROOT"/tests/unit/verdict-derive*.bats "$PROJECT_ROOT/tests/unit/kf-write-lib.bats"
    [ "$status" -eq 0 ] || { echo "$output"; return 1; }
    # the lint is not vacuous: a fixture with one mid-test negation is caught, a last-command one and an explicit one are not
    printf '@test "x" {\n    ! false\n    true\n}\n' > "$T/neg-a.bats"
    printf '@test "y" {\n    ! false || { echo no; return 1; }\n    true\n    ! false\n}\n' > "$T/neg-b.bats"
    run python3 "$T/neg-lint.py" "$T/neg-a.bats" "$T/neg-b.bats"
    [ "$status" -eq 1 ]; [[ "$output" == *"neg-a.bats:2:"* ]]; [[ "$output" != *"neg-b.bats"* ]]
}

@test "CMP-200 companion_voice reads the YAML 1.1 single-letter booleans: n opts out and y stays on, never 'not a boolean' (thirty-third run, a1 DISS-C-001)" {
    _cfg_edit $'enabled: true\n' $'enabled: true\n    companion_voice: n\n'
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "false" ] || { echo "$result"; return 1; }
    [ "$(grep -c "is not a boolean" "$T/stderr.log")" = "0" ] || { cat "$T/stderr.log"; return 1; }
    _cfg_edit "companion_voice: n" "companion_voice: Y"
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.planned' <<<"$result")" = "true" ]
    [ "$(grep -c "is not a boolean" "$T/stderr.log")" = "0" ] || { cat "$T/stderr.log"; return 1; }
}

@test "CMP-201 a companion_chain element ending in a newline (a block scalar) is dropped alone — never read as its trimmed name, nor an extra row that discards the whole list as unreadable (thirty-third run, a1 DISS-C-002)" {
    _cfg_edit $'  code_review:\n    enabled: true\n' "  code_review:"$'\n'"    enabled: true"$'\n'"    companion_chain:"$'\n'"      anthropic:"$'\n'"        - claude-headless"$'\n'"        - |"$'\n'"          tiny"$'\n'
    [ "$(yq eval '.flatline_protocol.code_review.companion_chain.anthropic[1]' -o=json "$CONFIG_FILE")" = '"tiny\n"' ]
    run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; _adv_conf_chain_hops code_review anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" != *"could not be read"* ]] || { echo "$output"; return 1; }
    [[ "$output" == *"companion_chain.anthropic[1] is not a hop name"* ]] || { echo "$output"; return 1; }
    [ "$(tail -n 1 <<<"$output")" = "claude-headless" ]
    # first in the list: before, its extra empty row made the count disagree and the whole list was discarded
    yq -i '.flatline_protocol.code_review.companion_chain.anthropic |= [.[1], .[0]]' "$CONFIG_FILE"
    run bash -c "$(declare -f _adv_conf_chain_hops log); CONFIG_FILE='$CONFIG_FILE'; _adv_conf_chain_hops code_review anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" != *"could not be read"* ]] || { echo "$output"; return 1; }
    [[ "$output" == *"companion_chain.anthropic[0] is not a hop name"* ]] || { echo "$output"; return 1; }
    [ "$(tail -n 1 <<<"$output")" = "claude-headless" ]
}

@test "CMP-202 an alias's target loses only a provider token: a bare Bedrock id keeps its -v1:0, so two such aliases never collapse onto the canonical hop 0 (thirty-third run, a2 DISS-C-002)" {
    local cat="$T/cat-202.yaml"
    cp "$PROJECT_ROOT/.claude/defaults/model-config.yaml" "$cat"
    yq -i '.aliases["my-bare"] = "anthropic.claude-sonnet-4-5-20250929-v1:0" | .aliases["my-bare-2"] = "anthropic.claude-haiku-4-5-20251001-v1:0" | .aliases["my-host"] = "bedrock:anthropic.claude-sonnet-4-5-20250929-v1:0" | .aliases["my-cli"] = "anthropic:claude-headless"' "$cat"
    export LOA_MODEL_CONFIG="$cat"
    [ "$(_adv_hop_canon my-bare)" = "anthropic.claude-sonnet-4-5-20250929-v1:0" ] || { echo "my-bare → $(_adv_hop_canon my-bare)"; return 1; }
    [ "$(_adv_hop_canon my-bare-2)" != "$(_adv_hop_canon my-bare)" ]
    [ "$(_adv_hop_canon my-host)" = "anthropic.claude-sonnet-4-5-20250929-v1:0" ]
    # a provider-prefixed target and a prefixed spelling of the hop canonicalise as before
    [ "$(_adv_hop_canon my-cli)" = "claude-headless" ]
    [ "$(_adv_hop_canon anthropic:claude-headless)" = "claude-headless" ]
    [ "$(_adv_hop_canon bedrock:us.anthropic.claude-opus-4-8)" = "us.anthropic.claude-opus-4-8" ]
}

@test "CMP-203 the primary reaper collects the tree again before KILL, as the companion's does: a child the job forked during the grace never outlives the reap (thirty-third run, a3 DISS-001)" {
    rm -f "$T/p203-child" "$T/p203-ready"
    bash -c 'trap "sleep 300 3>&- & echo \$! > \"\$1/p203-child\"" TERM; : > "$1/p203-ready"; while :; do sleep 0.1; done' _ "$T" 3>&- & local p=$!; HOLDER_PIDS+=("$p")
    for i in $(seq 1 50); do [ -e "$T/p203-ready" ] && break; sleep 0.1; done
    [ -e "$T/p203-ready" ]
    _ADV_PRIMARY_PID=$p; _ADV_PRIMARY_START=$(_adv_proc_start "$p"); LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1 _adv_reap_primary
    for i in $(seq 1 30); do [ -s "$T/p203-child" ] && break; sleep 0.1; done
    local c; c=$(cat "$T/p203-child" 2>/dev/null || true); [[ "$c" =~ ^[0-9]+$ ]] || { echo "the job never forked its child (got: $c)"; return 1; }
    HOLDER_PIDS+=("$c")
    sleep 0.3
    if kill -0 "$p" 2>/dev/null; then echo "job $p still alive after the primary reap"; return 1; fi
    if kill -0 "$c" 2>/dev/null; then echo "child $c forked during the grace outlived the primary reap"; return 1; fi
}

@test "CMP-204 the CONT watchdog is cancelled once the reaper's own CONT pass ran — a pid it resumed and someone then stopped is never resumed seconds later — and it runs in its own session, so a process-group KILL of the reviewer never takes it down (thirty-third run, a3 DISS-C-001)" {
    export _ADV_CONT_WATCHDOG_SECONDS=1
    bash -c 'trap "" TERM; exec -a "$0" sleep 300' "loa-cmp30-stubborn-204-$$" 3>&- & local v=$!; HOLDER_PIDS+=("$v"); _await_stubborn "$v"
    _adv_kill_tree "$v" TERM >/dev/null
    kill -0 "$v"
    kill -STOP "$v"   # stopped after the reap by someone else (or a recycled pid's owner)
    sleep 2
    [[ "$(ps -o stat= -p "$v")" == T* ]] || { echo "the watchdog resumed pid $v after the reaper had finished: $(ps -o stat= -p "$v")"; return 1; }
    kill -CONT "$v"
    if command -v setsid >/dev/null 2>&1; then
        # a reviewer killed by its process group mid-freeze: the watchdog is in no group of the reviewer's
        sleep 30 3>&- & local w=$!; HOLDER_PIDS+=("$w")
        _adv_pid_tokens() { kill -KILL -- -"$(ps -o pgid= -p "$BASHPID" | tr -d ' ')"; sleep 5; }
        setsid bash -c "$(declare -f _adv_kill_tree _adv_tree_pids _adv_cont_watchdog _adv_pid_tokens); _adv_kill_tree $w TERM tokens" >/dev/null 2>&1 3>&- </dev/null || true
        local i; for i in $(seq 1 30); do [[ "$(ps -o stat= -p "$w")" == T* ]] && break; sleep 0.1; done
        for i in $(seq 1 40); do [[ "$(ps -o stat= -p "$w")" == T* ]] || break; sleep 0.1; done
        [[ "$(ps -o stat= -p "$w")" != T* ]] || { echo "pid $w is still stopped after the reviewer's group was killed"; kill -CONT "$w"; return 1; }
    fi
}

@test "CMP-205 a primary that answered as an id no catalog entry or name rule places (family unknown) is never judged independent of the companion: independent false, duplicate_voice, the findings kept, and the log says why (thirty-third run, b2 DISS-C-002)" {
    BEHAVIOUR[gpt-5.5-pro]=walked:my-proxy-model
    [ "$(_adv_family_of my-proxy-model)" = "unknown" ]
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.status' <<<"$result")" = "succeeded" ] || { echo "$result"; return 1; }
    [ "$(jq -r '.metadata.companion_voice.primary_succeeded_model' <<<"$result")" = "my-proxy-model" ] || { echo "$result"; return 1; }
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "false" ] || { jq -c '.metadata.companion_voice' <<<"$result"; return 1; }
    [ "$(jq -r '.metadata.companion_voice.counted_as' <<<"$result")" = "duplicate_voice" ]
    [ "$(jq '.findings | length' <<<"$result")" = "2" ]
    grep -q "cannot be judged independent" "$T/stderr.log" || { cat "$T/stderr.log"; return 1; }
    # a known, different family stays independent
    BEHAVIOUR[gpt-5.5-pro]=ok
    result=$(_run_main review)
    [ "$(jq -r '.metadata.companion_voice.independent' <<<"$result")" = "true" ]
}

@test "CMP-206 a BEHAVIOUR value the stub has no arm for fails the test that set it — never a silent empty answer the script reads as malformed (thirty-third run, c1a DISS-C-001)" {
    BEHAVIOUR[gpt-5.5-pro]=malfromed
    result=$(_run_main review) || true   # (a subshell: main exits)
    [ -e "$T/marker-unknown-behaviour" ] || { echo "the stub answered an unknown BEHAVIOUR without a marker"; return 1; }
    grep -q "malfromed" "$T/marker-unknown-behaviour"
    command rm -f -- "$T/marker-unknown-behaviour"   # (this test meant it: the teardown check stays for every other test)
}

@test "CMP-207 the CHANGELOG FR-2 bullet states one shipped state: only the review skill grants the qmd step (the audit skill dropped it), and the headless cwd fails closed when no private base qualifies — gemini's prompt on stdin with claude's (thirty-third run, e2a DISS-C-002, e1b DISS-C-002)" {
    local cl="$PROJECT_ROOT/CHANGELOG.md" sk="$PROJECT_ROOT/.claude/skills"
    if grep -q 'both skills allowlist the `qmd-context-query.sh` step they prescribe' "$cl"; then echo "a qmd grant the audit skill no longer has"; return 1; fi
    grep -q 'the review skill allowlists the `qmd-context-query.sh` step it prescribes' "$cl" || { echo "the qmd grant is not stated as shipped"; return 1; }
    if grep -q 'and none fails the call closed' "$cl"; then echo "a cwd guarantee that reads as never failing closed"; return 1; fi
    grep -q 'when none qualifies, the hop fails closed as provider-unavailable' "$cl" || { echo "the fail-closed cwd is not stated"; return 1; }
    grep -q 'and `gemini-headless` adapters send every prompt on stdin' "$cl" || { echo "gemini's stdin transport is not stated"; return 1; }
    # (what the bullet says is what ships)
    grep -q 'Bash(.claude/scripts/qmd-context-query.sh \*)' "$sk/reviewing-code/SKILL.md" || { echo "the review skill lost its qmd grant"; return 1; }
    if grep -q 'qmd-context-query' "$sk/auditing-security/SKILL.md"; then echo "the audit skill grants qmd again"; return 1; fi
}

@test "CMP-208 the config states what the all-Fable move costs and how its claude-headless gate hops authenticate: the harness caps are named as sized for the sonnet/opus split, and the Flatline and BB primaries' auth follows CLAUDE_HEADLESS_BIN with the breaker shared with the dissent companion (thirty-third run, e2b DISS-C-001/003)" {
    local cfg="$PROJECT_ROOT/.loa.config.yaml"
    grep -q 'caps below were sized for the sonnet executor / opus advisor split' "$cfg" || { echo "the harness caps are not named as pre-Fable"; return 1; }
    grep -q 'Fable 5.1 is 5x sonnet-5 and 2x opus-5 per token' "$cfg" || { echo "the Fable cost multiple is not stated"; return 1; }
    [ "$(grep -c 'auth follows CLAUDE_HEADLESS_BIN' "$cfg")" -ge 2 ] || { echo "a claude-headless gate primary does not state its auth mode"; return 1; }
    grep -q 'shares the anthropic headless circuit breaker with the dissent companion' "$cfg" || { echo "the shared breaker is not stated"; return 1; }
    # (the caps themselves are the operator's spend decision — this round names them, never raises them)
    [ "$(yq '.spiral.harness.implement_budget_usd' "$cfg")" = "5" ] || { echo "the implement cap moved"; return 1; }
}

@test "CMP-209 kill_tree starts a second CONT watchdog only for a descendant the re-collection found, and for that pid alone — a tree that did not grow gets one watchdog (thirty-fourth run, a3 DISS-C-003)" {
    _adv_cont_watchdog() { [[ -n "$1" ]] || return 0; printf '%s|\n' "$(echo $1)" >> "$T/wd-calls"; }
    sleep 30 3>&- & local v=$!; HOLDER_PIDS+=("$v")
    _adv_kill_tree "$v" TERM >/dev/null
    [ "$(cat "$T/wd-calls")" = "$v|" ] || { echo "watchdogs: $(cat "$T/wd-calls")"; return 1; }
    # a descendant forked between the first collection and the freeze: the second watchdog carries it, not the whole tree again
    : > "$T/wd-calls"
    sleep 30 3>&- & local u=$!; HOLDER_PIDS+=("$u")
    sleep 30 3>&- & local w=$!; HOLDER_PIDS+=("$w")
    _adv_tree_pids() { echo "$1"; if [[ -e "$T/second-209" ]]; then echo "$w"; fi; : > "$T/second-209"; }
    _adv_kill_tree "$u" TERM >/dev/null
    [ "$(cat "$T/wd-calls")" = "$(printf '%s|\n%s|' "$u" "$w")" ] || { echo "watchdogs: $(cat "$T/wd-calls")"; return 1; }
}

@test "CMP-210 a queue-phase bound lookup that failed is never cached and never reaps: the strict hop bound prints nothing on a failed catalog read, the tick decides nothing, and the next tick's good read is cached (thirty-fourth run, a3 DISS-C-002)" {
    export LOA_MODEL_CONFIG="$T/cat-210.yaml"
    printf 'providers:\n  anthropic:\n    connect_timeout: 10\n    read_timeout: 900\n    models:\n      claude-headless: {}\n' > "$LOA_MODEL_CONFIG"
    [ "$(_adv_cli_hop_bound claude-headless strict)" = "910" ]
    [ "$(_adv_cli_hop_bound not-listed-headless strict)" = "$_ADV_CLI_HOP_TIMEOUT" ]   # (not listed is an answer: the fallback)
    yq() { return 1; }
    run _adv_cli_hop_bound claude-headless strict
    [ "$status" -ne 0 ] && [ -z "$output" ] || { echo "strict over a failed has(): status $status, '$output'"; return 1; }
    [ "$(_adv_cli_hop_bound claude-headless)" = "$_ADV_CLI_HOP_TIMEOUT" ]   # (the non-strict callers keep their fallback)
    yq() { case "$*" in *read_timeout*) return 1 ;; *) command yq "$@" ;; esac; }
    run _adv_cli_hop_bound claude-headless strict
    [ "$status" -ne 0 ] && [ -z "$output" ] || { echo "strict over a failed read_timeout read: status $status, '$output'"; return 1; }
    # the deadline: 700 s into the queue phase, under the 910 + 30 bound — a failed read must not reap at the 640 s fallback
    yq() { return 1; }
    local now; now=$(date +%s); mkdir -p "$T/dq210"
    echo queue > "$T/dq210/companion.phase"; touch -d "@$(( now - 700 ))" "$T/dq210/companion.phase"
    echo claude-headless > "$T/dq210/companion.current"
    _ADV_QB_HOP=""; _ADV_QB_VAL=0; local whyq=""
    _companion_deadline_why "$T/dq210" $(( now - 800 )) 10 60 2000 whyq
    [ -z "$whyq" ] || { echo "a failed bound lookup reaped: $whyq"; return 1; }
    [ -z "$_ADV_QB_HOP" ] || { echo "a failed bound lookup was cached for $_ADV_QB_HOP ($_ADV_QB_VAL)"; return 1; }
    unset -f yq
    _companion_deadline_why "$T/dq210" $(( now - 800 )) 10 60 2000 whyq
    [ -z "$whyq" ] && [ "$_ADV_QB_HOP" = "claude-headless" ] && [ "$_ADV_QB_VAL" = "940" ] \
      || { echo "good read: why '$whyq', cache $_ADV_QB_HOP=$_ADV_QB_VAL"; return 1; }
    touch -d "@$(( now - 945 ))" "$T/dq210/companion.phase"
    _companion_deadline_why "$T/dq210" $(( now - 1000 )) 10 60 2000 whyq
    [ "$whyq" = "phase 'queue' deadline: 940s from the phase start" ] || { echo "past the bound: '$whyq'"; return 1; }
}

@test "CMP-211 a companion gone before its fork token was read is recorded as exited — a later process on that pid is neither the live companion nor reaped — and the fork site records the token through that rule (thirty-fourth run, a3 DISS-C-001)" {
    ( exit 0 ) & local d=$!; wait "$d" || true
    [ "$(_adv_fork_token "$d")" = "exited" ]
    sleep 30 3>&- & local v=$!; HOLDER_PIDS+=("$v")
    [ -n "$(_adv_fork_token "$v")" ] && [ "$(_adv_fork_token "$v")" = "$(_adv_proc_start "$v")" ]
    # a host where no token can be read: a live child is "" (the pid alone decides) ...
    _adv_proc_start() { return 1; }
    [ -z "$(_adv_fork_token "$v")" ]
    # ... and the pid of a child recorded exited, now another process's (its token unreadable too), is neither alive nor reaped
    _ADV_COMPANION_PID="$v"; _ADV_COMPANION_START="exited"
    ! _adv_companion_alive || { echo "a recycled pid was the live companion"; return 1; }
    _adv_reap_companion_inner "$v"
    _ADV_COMPANION_PID="$v"; _ADV_COMPANION_START="exited"; _adv_reap_companion 2> "$T/reap-211.err"
    grep -q "exited before its start token was read" "$T/reap-211.err" || { cat "$T/reap-211.err"; return 1; }   # (the outer reaper's own check: nothing published for a trap to KILL)
    kill -0 "$v" && [[ "$(ps -o stat= -p "$v")" != T* ]] || { echo "the recycled pid $v was signalled"; return 1; }
    [ -z "$_ADV_COMPANION_PID" ]
    grep -qF '_ADV_COMPANION_START=$(_adv_fork_token "$companion_pid")' "$ADVERSARIAL_REVIEW"
}

@test "CMP-212 a .prev destination that is a directory or a symlink is refused (2) before anything moves — the envelope never lands inside a directory, never follows a link, and is never listed for a drop that cannot remove it; a regular .prev is replaced (thirty-fourth run, a4 DISS-C-002)" {
    local rel="grimoires/loa/a2a/$SPRINT/adversarial-review.json" rc
    mkdir -p "$OUT_DIR"; printf 'env' > "$PROJECT_ROOT/$rel"
    mkdir "$PROJECT_ROOT/$rel.prev"
    _ADV_PREV_FILES=""; rc=0; _adv_move_aside "$rel" || rc=$?
    [ "$rc" = 2 ] || { echo "rc $rc; .prev: $(ls -A "$PROJECT_ROOT/$rel.prev")"; return 1; }
    [ "$(cat "$PROJECT_ROOT/$rel")" = "env" ] && [ -z "$(ls -A "$PROJECT_ROOT/$rel.prev")" ] && [ -z "$_ADV_PREV_FILES" ]
    rmdir "$PROJECT_ROOT/$rel.prev"
    mkdir "$T/elsewhere-212"; ln -s "$T/elsewhere-212" "$PROJECT_ROOT/$rel.prev"
    rc=0; _adv_move_aside "$rel" || rc=$?
    [ "$rc" = 2 ] && [ -z "$(ls -A "$T/elsewhere-212")" ] && [ "$(cat "$PROJECT_ROOT/$rel")" = "env" ] || { echo "rc $rc through a link"; return 1; }
    command rm -f -- "$PROJECT_ROOT/$rel.prev"
    printf 'older' > "$PROJECT_ROOT/$rel.prev"
    rc=0; _adv_move_aside "$rel" || rc=$?
    [ "$rc" = 0 ] && [ "$(cat "$PROJECT_ROOT/$rel.prev")" = "env" ] && [ ! -e "$PROJECT_ROOT/$rel" ]
    # the refusal names both nodes
    grep -qF 'error "$_ma or $_ma.prev is not a regular file' "$ADVERSARIAL_REVIEW"
}

@test "CMP-213 --record-fallback never moves an envelope or sidecar into a .prev directory or through a .prev link: refused (2), named, the file left where it stands, on both move paths (thirty-fourth run, a4 DISS-C-002)" {
    mkdir -p "$OUT_DIR"
    local env="$OUT_DIR/adversarial-review.json" rc st
    for st in failed workdir_unavailable; do
        printf '{"findings":[],"metadata":{"status":"reviewed","timestamp":"2026-10-02T11:00:00Z"}}\n' > "$env"
        mkdir "$env.prev"
        rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback "$st" --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
        [ "$rc" -eq 2 ] || { echo "$st over a .prev directory: rc $rc"; cat "$T/err"; return 1; }
        grep -q "adversarial-review.json.prev is not a regular file" "$T/err" || { echo "$st: $(cat "$T/err")"; return 1; }
        [ -z "$(ls -A "$env.prev")" ] && [ "$(jq -r '.metadata.timestamp' "$env")" = "2026-10-02T11:00:00Z" ] || { echo "$st moved it: $(ls -A "$env.prev")"; return 1; }
        rmdir -- "$env.prev"
    done
    mkdir "$T/elsewhere-213"; ln -s "$T/elsewhere-213" "$env.prev"
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback failed --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
    [ "$rc" -eq 2 ] && [ -z "$(ls -A "$T/elsewhere-213")" ] || { echo "through a .prev link: rc $rc, $(ls -A "$T/elsewhere-213")"; return 1; }
    command rm -f -- "$env.prev" "$env"
}

@test "CMP-214 the three-quarter cap bounds the partial view itself — siblings at its tier first, whole; the view next; the lower rows get what both leave, nothing once the siblings take over a quarter — and the comment says so, not that a quarter is kept for the lower rows (thirty-fourth run, b1 DISS-C-001)" {
    mk() { local p=$1 n=$2 h l; printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n' "$p" "$p" "$p" "$p"; for h in $(seq 1 "$n"); do printf '@@ -%d,3 +%d,3 @@\n' "$h" "$h"; for l in 1 2 3; do printf '+line %d of hunk %d with some padding text here\n' "$l" "$h"; done; done; }
    local out sib
    sib="$(mk src/auth/a.ts 20)"
    [ "$(estimate_tokens "$sib")" -gt 1000 ]   # (over a quarter of the 4000-token budget)
    out=$(prepare_content "$sib"$'\n'"$(mk src/auth/login.ts 400)"$'\n'"$(mk docs/readme.md 3)" 4000 2>/dev/null)
    [[ "$out" == *"diff --git a/src/auth/a.ts"* && "$out" != *"--- PARTIAL: src/auth/a.ts"* ]]           # the sibling, whole
    [[ "$out" == *"--- PARTIAL: src/auth/login.ts"* ]]                                                  # the view, at its tier
    [[ "$out" != *"diff --git a/docs/readme.md"* && "$out" == *"--- TRUNCATED: 1 lower-priority file(s) omitted"* ]]
    # with no sibling the cap leaves the quarter the lower row fits in
    out=$(prepare_content "$(mk src/auth/login.ts 400)"$'\n'"$(mk docs/readme.md 3)" 4000 2>/dev/null)
    [[ "$out" == *"diff --git a/docs/readme.md"* ]]
    local lc="$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    ! grep -q 'the cap keeps a quarter for the rows ranked BELOW the top file' "$lc" || { echo "the old comment stands"; return 1; }
    grep -q 'the cap bounds the VIEW' "$lc"
}

@test "CMP-215 the config example states the shipped rules: a primary of unknown family gets a companion that is never counted as a second voice (duplicate_voice), a malformed budget_cents fails closed, and a repaired finding can take one call per repair-chain hop — never 'one finding each' read as one call (thirty-fourth run, b2 DISS-C-001 / DISS-C-003)" {
    local ex="$PROJECT_ROOT/.loa.config.yaml.example" blk
    blk=$(sed -n '/^  code_review:$/,/^  stable_anchors:$/p' "$ex")
    [ -n "$blk" ]
    grep -q 'unknown family' <<<"$blk" && grep -q 'duplicate_voice' <<<"$blk" || { echo "the unknown-family companion is not said to be a duplicate voice"; return 1; }
    ! grep -q 'xAI, unknown' <<<"$blk" || { echo "unknown is still listed among the second-voice primaries"; return 1; }
    [ "$(grep -c 'malformed value fails closed' <<<"$blk")" -ge 2 ] || { echo "both budget_cents comments must say a malformed value fails closed"; return 1; }
    ! grep -q 'one finding each' <<<"$blk" || { echo "the repair count still reads as one call per finding"; return 1; }
    grep -q 'one call per repair-chain hop' <<<"$blk"
    # the rules themselves: the 5-repair cap and the unknown-family judgement
    grep -q '^readonly ADV_REPAIR_MAX_PER_RUN=5$' "$ADVERSARIAL_REVIEW"
    [ "$(_adv_family_of my-proxy-model)" = "unknown" ]
}

@test "CMP-216 setup never inherits a directory already standing at this test's sprint path: a marked one (a crashed run on a reused pid) is emptied and removed before the marker is written; an unmarked one is refused, named, and left for teardown not to touch (thirty-fourth run, c1a DISS-C-001)" {
    local m="${OUT_DIR%/*}/.$SPRINT.owner"
    mkdir -p "$OUT_DIR"; printf 'stale' > "$OUT_DIR/adversarial-review.json.prev"
    _claim_sprint_dir "$OUT_DIR"
    [ ! -e "$OUT_DIR" ] || { echo "a marked leftover was inherited: $(ls -A "$OUT_DIR")"; return 1; }
    command rm -f -- "$m"; mkdir -p "$OUT_DIR"; printf 'theirs' > "$OUT_DIR/keep"
    run _claim_sprint_dir "$OUT_DIR"
    [ "$status" -ne 0 ] && [[ "$output" == *"setup: $OUT_DIR stands and is not this suite's"* ]] || { echo "unmarked: status $status, $output"; return 1; }
    [ "$(cat "$OUT_DIR/keep")" = "theirs" ] && [ ! -e "$m" ]
    # the normalise suite's setup carries the same guard
    grep -q "stands and is not this suite's" "$PROJECT_ROOT/tests/unit/adversarial-review-normalise.bats"
    # setup claims the directory through it, before the marker is written
    sed -n '/^setup() {/,/^}/p' "$BATS_TEST_FILENAME" | grep -A1 '_claim_sprint_dir "$OUT_DIR" || return 1' | grep -q 'SPRINT.owner"' || { echo "setup does not claim before the marker"; return 1; }
    : > "$m"   # (ours again: teardown removes it with the directory)
}

@test "CMP-217 a pgrep that fails for a reason of its own (exit 2 / 3: a bad option, an internal error) never reads as 'no children' — the ps walker answers then; exit 1 (no match) is still the answer (thirty-fourth run, c1b DISS-C-001)" {
    bash -c 'sleep 30 & sleep 30 & wait' 3>&- & local root=$! _i st got
    for _i in $(seq 1 100); do [ "$(_adv_tree_pids "$root" | wc -w)" -ge 3 ] && break; sleep 0.1; done
    HOLDER_PIDS+=("$root")
    local with; with=$(_adv_tree_pids "$root" | sort -n | tr '\n' ' ')
    for p in $with; do [[ "$p" != "$root" && "$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')" == "$root" ]] && HOLDER_PIDS+=("$p"); done
    [ "$(printf '%s' "$with" | wc -w)" -eq 3 ]
    mkdir -p "$T/failbin"
    for st in 2 3; do
        printf '#!/bin/sh\necho "pgrep: invalid option" >&2\nexit %s\n' "$st" > "$T/failbin/pgrep"; chmod +x "$T/failbin/pgrep"
        got=$(_ADV_PGREP_BIN="$T/failbin/pgrep" _adv_tree_pids "$root" | sort -n | tr '\n' ' ')
        [ "$got" = "$with" ] || { echo "pgrep exit $st: '$got', not the tree '$with'"; return 1; }
    done
    printf '#!/bin/sh\nexit 1\n' > "$T/failbin/pgrep"
    [ "$(_ADV_PGREP_BIN="$T/failbin/pgrep" _adv_tree_pids "$root" | wc -w)" -eq 1 ]   # (no match: the root alone)
}

@test "CMP-218 the companion suite's sweep never deletes a live run's directory it cannot see: an EPERM owner is alive, a marker from another host or pid namespace is left; one of ours, dead, is removed (thirty-fourth run, c2a DISS-C-001, as NRM-55)" {
    # (thirty-fifth run, c2b DISS-C-003: the sweep legs run in this test's own a2a — never fixtures in the real one, which no
    # teardown registers; setup's own marker is still checked where setup writes it)
    local a="$T/a2a" dead
    mkdir -p "$a"
    dead=$(( $(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304) + 1 ))
    if kill -0 "$dead" 2>/dev/null; then echo "pid $dead is live"; return 1; fi
    ( kill() { echo "bash: kill: ($2) - Operation not permitted" >&2; return 1; }; _sweep_alive "$dead" ) || { echo "an EPERM owner was judged dead"; return 1; }
    mkdir -p "$a/sprint-comp-$dead"; printf 'where other-host pid:[1]\n' > "$a/.sprint-comp-$dead.owner"
    _sweep_stale_suite_dirs "$a" sprint-comp
    [ -d "$a/sprint-comp-$dead" ] || { echo "another namespace's directory was deleted"; return 1; }
    _sweep_where > "$a/.sprint-comp-$dead.owner"
    _sweep_stale_suite_dirs "$a" sprint-comp
    [ ! -e "$a/sprint-comp-$dead" ] && [ ! -e "$a/.sprint-comp-$dead.owner" ] || { echo "our own dead run's directory was kept"; return 1; }
    [ "$(cat "${OUT_DIR%/*}/.$SPRINT.owner")" = "$(_sweep_where)" ]
}

@test "CMP-219 a teardown a test runs mid-test never removes that test's own tmp directory: every mid-test teardown in the dissent suites clears the bats < 1.4 own-tmp name first, so a later check on a file under it tests the teardown, not the harness (thirty-fourth run, c2b DISS-C-003)" {
    local f n=0 l
    for f in "$PROJECT_ROOT/tests/unit/adversarial-review-companion.bats" "$PROJECT_ROOT/tests/unit/adversarial-review-normalise.bats"; do
        while IFS= read -r l; do
            n=$(( n + 1 ))
            [[ "$l" == *'( set -e; '*'_OWN_TMP=""; '*'teardown )'* || "$l" == *'( '*'_OWN_TMP=""; '*'teardown )'* ]] || { echo "${f##*/}: $l"; return 1; }
        done < <(grep -E '\( .*teardown \)' "$f" | grep -vE '^\s*#')
    done
    [ "$n" -ge 8 ]
}

@test "CMP-220 every Python open() in the dissent suites names encoding='utf-8': under a C / POSIX locale with UTF-8 mode off (Python 3.6, the old-mawk platforms these lints name) open() decodes ASCII and a lint dies on the scripts' first em-dash, a traceback in place of its verdict (thirty-fourth run, c2d DISS-C-002)" {
    local f l n=0
    # the failure is real here: a C locale with UTF-8 mode and coercion off decodes ASCII
    run env LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 python3 -c 'import io, sys; io.open(sys.argv[1]).read()' "$ADVERSARIAL_REVIEW"
    [ "$status" -ne 0 ] && [[ "$output" == *UnicodeDecodeError* ]] || skip "this python3 decodes UTF-8 under LC_ALL=C"
    run env LC_ALL=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 python3 -c 'import sys; open(sys.argv[1], encoding="utf-8").read()' "$ADVERSARIAL_REVIEW"
    [ "$status" -eq 0 ]
    for f in "$PROJECT_ROOT"/tests/unit/adversarial-review-*.bats "$PROJECT_ROOT/tests/unit/verdict-derive.bats"; do
        while IFS= read -r l; do
            n=$(( n + 1 ))
            [[ "$l" == *"encoding="* ]] || { echo "${f##*/}: $l"; return 1; }
        done < <(grep -E '(^|[^.[:alnum:]_])open\(' "$f" | grep -vE '^[[:space:]]*#' | grep -vE 'os\.open|fdopen')
    done
    [ "$n" -ge 10 ]
}

@test "CMP-221 the audit's discovered-vulnerability bead names its criterion only: the flushed .beads JSONL is committed, so a title naming the file tells every reader of a public repo where an unpatched weakness lives before the fix lands — the location stays in the feedback file (thirty-fourth run, e2b DISS-C-003)" {
    local r="$PROJECT_ROOT/.claude/skills/auditing-security/resources/BEADS-WORKFLOW.md" t
    t=$(grep -o 'log-discovered-issue.sh "<sprint-epic-id>" "[^"]*"' "$r") || { echo "no discovered-issue step"; return 1; }
    [[ "$t" == *'"Security: <criterion>'* && "$t" == *auditor-sprint-feedback.md* ]] || { echo "$t"; return 1; }
    [[ "$t" != *'<file>'* && "$t" != *'<anchor>'* && "$t" != *'<location>'* ]] || { echo "the title names where: $t"; return 1; }
}

@test "CMP-222 a later file's .prev that is a directory refuses before ANYTHING moves — the envelope stays at its path, on --record-fallback (both statuses) and at a run's start; a refusal that says nothing was recorded or reviewed has moved nothing (thirty-fifth run, a2 DISS-C-002)" {
    mkdir -p "$OUT_DIR"
    local env="$OUT_DIR/adversarial-review.json" sc="$OUT_DIR/adversarial-rejected-review.jsonl" rc st result
    for st in failed workdir_unavailable; do
        printf '{"findings":[],"metadata":{"status":"reviewed","timestamp":"2026-10-02T11:00:00Z"}}\n' > "$env"
        printf '{"reject_reason":"earlier"}\n' > "$sc"; mkdir "$sc.prev"
        rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback "$st" --since 2026-10-02T12:00:00Z --reason r ) >/dev/null 2>"$T/err" || rc=$?
        [ "$rc" -eq 2 ] || { echo "$st: rc $rc"; cat "$T/err"; return 1; }
        grep -q "adversarial-rejected-review.jsonl.prev is not a regular file" "$T/err" || { echo "$st: $(cat "$T/err")"; return 1; }
        [ -f "$env" ] && [ ! -e "$env.prev" ] && [ "$(jq -r '.metadata.timestamp' "$env")" = "2026-10-02T11:00:00Z" ] \
            || { echo "$st moved the envelope before refusing: $(ls -A "$OUT_DIR")"; return 1; }
        [ -f "$sc" ] && [ -z "$(ls -A "$sc.prev")" ]
        rmdir -- "$sc.prev"
    done
    # a run's start: the same order — the sidecar's .prev is checked before the envelope moves
    jq -n '{findings: [], metadata: {type: "review", model: "m", status: "reviewed", timestamp: "2026-01-01T00:00:00Z"}}' > "$env"
    local prev_env; prev_env=$(cat "$env")
    mkdir "$sc.prev"
    BEHAVIOUR[gpt-5.5-pro]=walked:codex-headless
    rc=0; result=$(_run_main review) || rc=$?
    [ "$rc" = 2 ] || { echo "rc $rc: $result"; return 1; }
    [ "$(jq -r '.metadata.status + " " + .metadata.path' <<<"$result")" = "workdir_unavailable grimoires/loa/a2a/$SPRINT/adversarial-rejected-review.jsonl" ]
    [ "$(cat "$env")" = "$prev_env" ] && [ ! -e "$env.prev" ] || { echo "the run moved the envelope before refusing: $(ls -A "$OUT_DIR")"; return 1; }
    rmdir -- "$sc.prev"; command rm -f -- "$sc"
}

@test "CMP-223 the KILL re-collection splits the TERM-time pid line into words before it merges: a sort -u that keeps another line of an equal-key run (POSIX leaves which one unspecified) never drops a still-alive pid whose own re-collection came back empty (thirty-fifth run, a3 DISS-C-001)" {
    local a b
    bash -c 'trap "" TERM; sleep 30' 3>&- & a=$!; HOLDER_PIDS+=("$a")
    bash -c 'trap "" TERM; sleep 30' 3>&- & b=$!; HOLDER_PIDS+=("$b")
    _await_tree "$a" 1; _await_tree "$b" 1; sleep 0.2   # (bash execs the sleep, which keeps TERM ignored)
    : > "$T/killed"
    local _orig; _orig=$(declare -f _adv_kill_tree _adv_tree_pids _adv_kill_same)
    _adv_kill_tree() { printf '%s=%s\n' "$a" "$(_adv_tok_word "$(_adv_proc_start "$a")")" "$b" "$(_adv_tok_word "$(_adv_proc_start "$b")")"; }
    _adv_tree_pids() { [[ "$1" == "$a" ]] && echo "$a"; return 0; }   # (b's re-collection comes back empty)
    _adv_kill_same() { echo "$1" >> "$T/killed"; }
    sort() { awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }' | command sort "$@"; }   # (keeps the LAST line of an equal-key run)
    _ADV_COMPANION_PID="$a"; _ADV_COMPANION_START=$(_adv_proc_start "$a"); LOA_ADVERSARIAL_REAP_GRACE_SECONDS=1
    _adv_reap_companion_inner "$a"
    unset -f sort; eval "$_orig"
    grep -qx "$a" "$T/killed" && grep -qx "$b" "$T/killed" || { echo "killed: $(tr '\n' ' ' < "$T/killed")"; return 1; }
    kill -KILL "$a" "$b" 2>/dev/null || true; wait "$a" "$b" 2>/dev/null || true
}

@test "CMP-224 a shared-hop wait that wrote no verdict is said as such: the primary runs the hop (never a hop ceded without a positive skip) and the log never claims the companion finished without it (thirty-fifth run, a4 DISS-C-001)" {
    _cfg_edit $'      - codex-headless\n  security_audit:' $'      - codex-headless\n      - claude-headless\n  security_audit:'
    export ANTHROPIC_API_KEY="sk-presence-only-never-printed"
    BEHAVIOUR[gpt-5.5-pro]=unavailable; BEHAVIOUR[gpt-5.5]=unavailable; BEHAVIOUR[codex-headless]=unavailable
    BEHAVIOUR[opus]=slow2
    _adv_shared_hop_verdict() { return 1; }   # (the wait job dies before it writes)
    result=$(_run_main review)
    [ "$(jq -r '.metadata.model_attempts[-1]' <<<"$result")" = "claude-headless:reviewed" ]
    grep -qF "no verdict on it came back (the wait wrote none) — the primary runs it" "$T/stderr.log" || { grep -i 'shares' "$T/stderr.log"; return 1; }
    if grep -qF "finished without it" "$T/stderr.log"; then echo "the log claimed the companion finished without it"; return 1; fi
}

@test "CMP-225 --reason and --since without --record-fallback, and an empty --record-fallback, are usage errors (exit 2, naming the flag) — never a silently dropped value and a full review in place of the record (thirty-fifth run, a4 DISS-C-002)" {
    local rc a
    for a in "--reason|died" "--reason|" "--since|"; do
        rc=0; ( main --type review --sprint-id "$SPRINT" "${a%%|*}" "${a#*|}" --diff-file /dev/null ) >"$T/out" 2>"$T/err" || rc=$?
        [ "$rc" -eq 2 ] || { echo "$a: rc $rc"; return 1; }
        grep -qF -- "${a%%|*} applies to --record-fallback only" "$T/err" || { echo "$a: $(cat "$T/out" "$T/err")"; return 1; }
    done
    rc=0; ( main --type review --sprint-id "$SPRINT" --record-fallback "" --reason r --diff-file /dev/null ) >"$T/out" 2>"$T/err" || rc=$?
    [ "$rc" -eq 2 ] || { echo "empty --record-fallback: rc $rc"; return 1; }
    grep -qF -- "--record-fallback needs a status" "$T/err" || { echo "$(cat "$T/out" "$T/err")"; return 1; }
}

@test "CMP-226 the config example says what the pre-pass does (failure_mode and id derived, never only a case-fold and trim) and that an absent companion_voice key is on, in both gate blocks (thirty-fifth run, b2 DISS-C-001 / DISS-C-002)" {
    local ex="$PROJECT_ROOT/.loa.config.yaml.example"
    if grep -qF 'trim only, no synonym mapping' "$ex"; then echo "the pre-pass is still described as a case-fold and trim only"; return 1; fi
    grep -qF 'a missing failure_mode is derived from' "$ex"
    [ "$(grep -cF 'an absent key is true' "$ex")" -eq 2 ]
}

@test "CMP-227 setup's claim honours where a marker was written: a standing directory whose marker was written on another host or pid namespace (a coinciding pid there) is refused and left, never emptied (thirty-fifth run, c1a DISS-C-001)" {
    local m="${OUT_DIR%/*}/.$SPRINT.owner"
    mkdir -p "$OUT_DIR"; printf 'theirs' > "$OUT_DIR/keep"; printf 'where other-host pid:[1]\n' > "$m"
    run _claim_sprint_dir "$OUT_DIR"
    [ "$status" -ne 0 ] && [[ "$output" == *"is not this suite's"* ]] || { echo "foreign marker: status $status, $output"; return 1; }
    [ "$(cat "$OUT_DIR/keep")" = "theirs" ] || { echo "another namespace's directory was emptied"; return 1; }
    # the normalise suite's claim carries the same guard
    sed -n '/^_claim_sprint_dir() {/,/^}/p' "$PROJECT_ROOT/tests/unit/adversarial-review-normalise.bats" | grep -q '_sweep_foreign'
    command rm -f -- "$OUT_DIR/keep"; _sweep_where > "$m"   # (ours again: teardown removes both)
}

@test "CMP-228 setup's claim fails, named, when the leftover cannot be cleared: a find -delete or rmdir that fails is never a claimed, still-populated directory (thirty-fifth run, c1a DISS-C-002)" {
    [ "$(id -u)" -ne 0 ] || skip "root deletes through a read-only directory"
    mkdir -p "$OUT_DIR/ro"; printf 'stale' > "$OUT_DIR/ro/adversarial-review.json"; chmod 500 "$OUT_DIR/ro"
    run _claim_sprint_dir "$OUT_DIR"
    chmod 700 "$OUT_DIR/ro"
    [ "$status" -ne 0 ] && [[ "$output" == *"setup: could not clear $OUT_DIR"* ]] || { echo "status $status, $output"; return 1; }
    sed -n '/^_claim_sprint_dir() {/,/^}/p' "$PROJECT_ROOT/tests/unit/adversarial-review-normalise.bats" | grep -qF 'could not clear'
    SPRINT="sprint-comp-$$"   # (the refusal cleared it; teardown removes the directory and marker)
}

@test "CMP-229 the sweep reads kill -0's EPERM in the C locale: under a translated LC_MESSAGES the live owner of another uid is still alive; both suites' _sweep_alive are one text (thirty-fifth run, c1a DISS-C-003)" {
    local dead
    dead=$(( $(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304) + 1 ))
    ( export LC_MESSAGES=de_DE.UTF-8 LANG=de_DE.UTF-8; unset LC_ALL
      kill() { if [[ "${LC_ALL:-}" == C ]]; then echo "bash: kill: ($2) - Operation not permitted"; else echo "bash: kill: ($2) - Die Operation ist nicht erlaubt"; fi >&2; return 1; }
      _sweep_alive "$dead" ) || { echo "a translated EPERM owner was judged dead"; return 1; }
    [ "$(sed -n '/^_sweep_alive() {/,/^}/p' "$BATS_TEST_FILENAME")" = "$(sed -n '/^_sweep_alive() {/,/^}/p' "$PROJECT_ROOT/tests/unit/adversarial-review-normalise.bats")" ]
}

@test "CMP-230 no dissent-suite test deletes a sourced helper or leans on a GNU-only reverser: an unset -f names only a stub of an external command (the script's own function is restored from its saved text), and no stub pipes through tac (thirty-fifth run, c1c DISS-C-001 / DISS-C-004)" {
    local f n=0 name l
    for f in "$PROJECT_ROOT"/tests/unit/adversarial-review-companion.bats "$PROJECT_ROOT"/tests/unit/adversarial-review-normalise.bats; do
        while IFS= read -r l; do
            for name in ${l#*unset -f}; do
                n=$(( n + 1 ))
                # (thirty-sixth run, regression: teardown's `unset -f … 2>/dev/null || true` read `||` as a name, and `^||\(\)`
                # matched every line — the operand list ends at an operator or a redirection, and only a name is ever a pattern)
                [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { echo "${f##*/}: the lint read '$name' as a function name"; return 1; }
                if grep -qE "^${name}\(\) *\{" "$ADVERSARIAL_REVIEW"; then echo "${f##*/}: unset -f $name deletes the script's own function"; return 1; fi
            done
        done < <(grep -E '^[[:space:]]+unset -f ' "$f" | sed -E 's/[0-9]*[;#|&<>].*//')
        if grep -vE '^[[:space:]]*#' "$f" | grep -qE '(^|[^[:alnum:]_-])tac[[:space:]]*\|'; then echo "${f##*/}: tac is GNU-only"; return 1; fi
    done
    [ "$n" -ge 8 ]
}

@test "CMP-231 --diff-range's diff reads no attribute of the reviewed tree: a committed .gitattributes '-diff' line never turns a text hunk into \"Binary files differ\" for both voices — git's content check alone decides, a NUL file stays binary — an inherited GIT_ATTR_SOURCE is replaced and left as it was, and .git/info/attributes (the operator's own) still applies (thirty-fifth run, e2a DISS-C-002)" {
    _cmp_git version | awk '{split($3, v, "."); exit !(v[1] > 2 || (v[1] == 2 && v[2] >= 40))}' || skip "git < 2.40 reads no GIT_ATTR_SOURCE"
    local r="$T/attrsrc" out
    _cmp_git init -q "$r"; printf 'a\n' > "$r/t.txt"; printf 'P\0Q' > "$r/b.bin"; _cmp_git -C "$r" add .; _cmp_git -C "$r" commit -q -m base
    printf '*.txt -diff\n' > "$r/.gitattributes"; printf 'b\n' >> "$r/t.txt"; printf 'P\0R' > "$r/b.bin"
    _cmp_git -C "$r" add .; _cmp_git -C "$r" commit -q -m head
    out=$(_adv_range_diff "$r" HEAD~1...HEAD)
    grep -qx '+b' <<<"$out" || { echo "the tree's own -diff hid its hunk: $out"; return 1; }
    grep -q '^Binary files a/b.bin and b/b.bin differ' <<<"$out" || { echo "a NUL file read as text: $out"; return 1; }
    # an exported GIT_ATTR_SOURCE naming the head tree (whose .gitattributes says -diff) is not the caller's to choose
    out=$(export GIT_ATTR_SOURCE=HEAD; _adv_range_diff "$r" HEAD~1...HEAD; printf 'caller:%s\n' "$GIT_ATTR_SOURCE")
    grep -qx '+b' <<<"$out" || { echo "an inherited GIT_ATTR_SOURCE hid the hunk: $out"; return 1; }
    grep -qx 'caller:HEAD' <<<"$out" || { echo "the caller's GIT_ATTR_SOURCE changed: $out"; return 1; }
    printf '*.txt -diff\n' > "$r/.git/info/attributes"
    grep -q '^Binary files a/t.txt and b/t.txt differ' <<<"$(_adv_range_diff "$r" HEAD~1...HEAD)" || { echo ".git/info/attributes no longer applies"; return 1; }
}

@test "CMP-232 a failed companion's MODELINV lookup reads only its own gate's rows for its own hop: a row with no calling_primitive is another writer's; an aliased or provider-prefixed hop finds cheval's provider:canonical-id row; a near-miss id is not the hop (thirty-sixth run, a3 DISS-C-002 / DISS-C-003)" {
    [[ -n "$T" && "$LOA_MODELINV_LOG_PATH" == "$T/"* ]] || { echo "the ledger is not test-scoped"; return 1; }
    row() { jq -nc --arg ts "$1" --arg msg "$2" --arg m "$3" --arg p "${4-adversarial-review}" '{event_type:"model.invoke.complete", ts_utc:$ts, payload:({models_requested:[$m], models_failed:[{model:$m, message_redacted:$msg}]} + (if $p == "-" then {} else {calling_primitive:$p} end))}'; }
    # another writer's row — no calling_primitive — inside the window, for the same model, is not this voice's
    row 2026-10-01T10:00:06Z foreign anthropic:claude-headless - > "$LOA_MODELINV_LOG_PATH"
    [ -z "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05Z 2026-10-01T10:00:09Z)" ] || { echo "a row without calling_primitive was read as this voice's"; return 1; }
    row 2026-10-01T10:00:07Z ours anthropic:claude-headless >> "$LOA_MODELINV_LOG_PATH"
    [ "$(_companion_ledger_message claude-headless 2026-10-01T10:00:05Z 2026-10-01T10:00:09Z)" = "ours" ] || { echo "the gate's own row was not read"; return 1; }
    # cheval writes provider:canonical-id — an alias hop and a host-prefixed hop are that id too
    local cat="$T/cat232.yaml"
    printf '%s\n' 'aliases:' "  myopus: 'anthropic:claude-opus-5'" 'providers:' '  anthropic:' '    models:' '      claude-opus-5: {}' > "$cat"
    row 2026-10-01T10:00:06Z opus-row anthropic:claude-opus-5 > "$LOA_MODELINV_LOG_PATH"
    local m
    for m in myopus bedrock:claude-opus-5 anthropic:claude-opus-5 claude-opus-5; do
        [ "$(LOA_MODEL_CONFIG="$cat" _companion_ledger_message "$m" 2026-10-01T10:00:05Z 2026-10-01T10:00:09Z)" = "opus-row" ] || { echo "hop $m missed its canonical row"; return 1; }
    done
    for m in claude-opus opus-5 claude-opus-5-x; do
        [ -z "$(LOA_MODEL_CONFIG="$cat" _companion_ledger_message "$m" 2026-10-01T10:00:05Z 2026-10-01T10:00:09Z)" ] || { echo "near-miss $m read the row"; return 1; }
    done
}

@test "CMP-233 a shared hop is failed_it only on a failure row (api_failure, malformed_response, lock_wait): a success row for the hop whose answer is not the hop's — another inner model answered, or the result is gone — is finished_without_it, never a failure the companion did not have (thirty-sixth run, a3 DISS-C-004)" {
    _ADV_COMPANION_PID=""
    mkdir -p "$T/vw233"; printf 'done' > "$T/vw233/companion.phase"; printf 'gpt-5.5' > "$T/vw233/companion.final"
    rm -f "$T/vw233/companion.result.json" "$T/vw233/companion.vq"
    local row
    for row in 'gpt-5.5:reviewed' 'openai:gpt-5.5:clean' 'gpt-5.5:degraded'; do
        printf 'opus:api_failure\n%s\n' "$row" > "$T/vw233/companion.attempts"
        [ "$(_adv_shared_hop_verdict gpt-5.5 "$T/vw233" 0 10 | cut -f1,2)" = "$(printf 'run\tfinished_without_it')" ] || { echo "success row $row read as a failure"; return 1; }
    done
    for row in 'gpt-5.5:api_failure' 'gpt-5.5:malformed_response' 'openai:gpt-5.5:lock_wait'; do
        printf '%s\nopus:reviewed\n' "$row" > "$T/vw233/companion.attempts"
        [ "$(_adv_shared_hop_verdict gpt-5.5 "$T/vw233" 0 10 | cut -f1,2)" = "$(printf 'run\tfailed_it')" ] || { echo "failure row $row not read as failed_it"; return 1; }
    done
}

@test "CMP-234 a byte cut followed by a run of empty lines (suppressBlankEmpty context) and more of the hunk is not the chunk's end: the incomplete hunk is dropped, never counted whole; a chunk that ends in empty lines is still its end (thirty-sixth run, b1 DISS-C-001)" {
    printf 'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+b\n@@ -5,8 +5,8 @@\n-c\n+d\n\n\n\n\n\n x\n' > "$T/chunk234"
    local two how n full
    two=$(printf 'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+b\n@@ -5,8 +5,8 @@\n-c\n+d\n' | wc -c)
    for n in "$two" $(( two - 1 )) $(( two + 2 )); do
        how=$(_lc_cut_partial "$T/chunk234" "$n" "$T/part234")
        [ "$how" = hunk ] || { echo "cut at $n: $how"; return 1; }
        [ "$(_lc_hunk_count "$(cat "$T/part234")")" -eq 1 ] || { echo "cut at $n kept the incomplete hunk"; return 1; }
    done
    full=$(wc -c < "$T/chunk234")
    how=$(_lc_cut_partial "$T/chunk234" "$full" "$T/part234")
    [ "$how" = hunk ] && [ "$(_lc_hunk_count "$(cat "$T/part234")")" -eq 2 ] || { echo "the whole chunk lost a hunk"; return 1; }
    # a chunk whose last hunk ends in empty lines: the cut before them is its end
    printf 'diff --git a/f b/f\n--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+b\n@@ -5 +5 @@\n-c\n+d\n\n\n\n\n\n\n' > "$T/chunk234b"
    for n in "$two" $(( two - 1 )); do
        how=$(_lc_cut_partial "$T/chunk234b" "$n" "$T/part234")
        [ "$how" = hunk ] && [ "$(_lc_hunk_count "$(cat "$T/part234")")" -eq 2 ] || { echo "cut at $n before the trailing empty lines dropped a hunk"; return 1; }
    done
}

@test "CMP-235 both budget_cents comments name the knob that bounds the KF-004 repairs — LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS, the wall-clock budget the script reads — never only a count an operator cannot tune (thirty-sixth run, b2 DISS-C-001)" {
    local ex="$PROJECT_ROOT/.loa.config.yaml.example" blk
    blk=$(sed -n '/^  code_review:$/,/^  stable_anchors:$/p' "$ex")
    [ -n "$blk" ]
    [ "$(grep -c 'LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS' <<<"$blk")" -ge 2 ] || { echo "a budget_cents comment does not name the repair wall budget"; return 1; }
    grep -q 'two of the heaviest hop' <<<"$blk" || { echo "the default wall budget is not stated"; return 1; }
    # the knob is the script's
    grep -q 'LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS' "$ADVERSARIAL_REVIEW"
    [ "$(_adv_repair_wall_for 900 60)" = "$(( 900 * 2 + 60 ))" ]
    [ "$(_adv_repair_wall_for 10 60)" = "$(( ADV_REPAIR_MAX_PER_RUN * 60 * 2 ))" ]
}

@test "CMP-236 a test's stand-in for a command (cat, sort, kill, mkdir…) never reaches teardown: teardown's first statement unsets every command name a test defines, and CMP-90's cat calls the real one through command, never an unbound local (thirty-sixth run, c1b DISS-C-001)" {
    local f="$BATS_TEST_FILENAME" names n t first
    names=$(awk '/^[ \t]+[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { sub(/^[ \t]+/, ""); sub(/\(\).*/, ""); print }' "$f" | LC_ALL=C sort -u)
    [ -n "$names" ]
    first=$(awk '/^teardown\(\) *\{/ { go = 1; next } go && /^[ \t]+(local |#)/ { next } go { print; exit }' "$f")
    [[ "$first" == *"unset -f "* ]] || { echo "teardown does not start by unsetting the stand-ins: $first"; return 1; }
    local seen=0
    for n in $names; do
        t=$(env -i PATH="$PATH" bash --norc --noprofile -c "type -t $n" 2>/dev/null) || t=""
        [[ "$t" == file || "$t" == builtin ]] || continue
        seen=$(( seen + 1 ))
        [[ " $first " == *" $n "* ]] || { echo "teardown never unsets the test's stand-in for $n"; return 1; }
    done
    (( seen >= 10 )) || { echo "the lint found only $seen stand-ins"; return 1; }
    ! grep -qF "real_cat=\$(command -v" "$f" || { echo "CMP-90 still calls cat through a test-local path"; return 1; }
}

@test "CMP-237 --diff-range on a git older than 2.40 says the reviewed tree's .gitattributes still applies — GIT_ATTR_SOURCE is ignored there without a word, so a committed -diff line would hide its hunks from both voices silently; a git that reads it, and the diff itself, are unchanged (thirty-sixth run, e2a DISS-C-002)" {
    local r="$T/oldgit" sh="$T/oldgit-bin" out err real
    real=$(command -v git)
    _cmp_git init -q "$r"; printf 'a\n' > "$r/t.txt"; _cmp_git -C "$r" add .; _cmp_git -C "$r" commit -q -m base
    printf 'b\n' >> "$r/t.txt"; _cmp_git -C "$r" commit -q -am head
    mkdir -p "$sh"
    printf '#!/bin/sh\n[ "$1" = version ] && { echo "git version %s"; exit 0; }\nexec %q "$@"\n' '2.39.5 (Apple Git-154)' "$real" > "$sh/git"; chmod +x "$sh/git"
    err=$( { out=$(PATH="$sh:$PATH" _adv_range_diff "$r" HEAD~1...HEAD); } 2>&1 )
    grep -q 'WARN: git 2.39.5 reads no GIT_ATTR_SOURCE' <<<"$err" || { echo "no warning on an old git: $err"; return 1; }
    out=$(PATH="$sh:$PATH" _adv_range_diff "$r" HEAD~1...HEAD 2>/dev/null)
    grep -qx '+b' <<<"$out" || { echo "the diff changed: $out"; return 1; }
    grep -q WARN <<<"$out" && { echo "the warning reached the diff: $out"; return 1; }
    # an unreadable version is said too — never taken as new enough
    printf '#!/bin/sh\n[ "$1" = version ] && { echo "git version unknown"; exit 0; }\nexec %q "$@"\n' "$real" > "$sh/git"
    err=$(PATH="$sh:$PATH" _adv_range_diff "$r" HEAD~1...HEAD 2>&1 >/dev/null)
    grep -q 'WARN: git unknown reads no GIT_ATTR_SOURCE' <<<"$err" || { echo "an unparsed version passed silently: $err"; return 1; }
    for v in 2.40.0 2.47.1 3.0.0; do
        printf '#!/bin/sh\n[ "$1" = version ] && { echo "git version %s"; exit 0; }\nexec %q "$@"\n' "$v" "$real" > "$sh/git"
        err=$(PATH="$sh:$PATH" _adv_range_diff "$r" HEAD~1...HEAD 2>&1 >/dev/null)
        [ -z "$err" ] || { echo "git $v warned: $err"; return 1; }
    done
}

@test "CMP-238 the FR-2 CHANGELOG bullet states every headless adapter's prompt transport and what runs without flock (thirty-sixth run, e2a DISS-C-001 / DISS-C-003)" {
    local cl; cl=$(sed -n '/^- \*\*Two voices, nothing dropped\*\*/p' "$PROJECT_ROOT/CHANGELOG.md")
    [ -n "$cl" ] || { echo "no FR-2 bullet"; return 1; }
    grep -qF 'codex and cursor read the prompt on stdin, grok from a prompt file inside its private workspace' <<<"$cl" || { echo "codex/cursor/grok transport unstated"; return 1; }
    grep -qF 'without flock the run lock is still taken (mkdir)' <<<"$cl" || { echo "the no-flock lock unstated"; return 1; }
    grep -qF 'claude'"'"'s and gemini'"'"'s are each one stable directory' <<<"$cl" || { echo "gemini's stable cwd unstated"; return 1; }
    grep -qF 'a git older than 2.40 ignores it, which is said once as a WARN' <<<"$cl" || { echo "the old-git behaviour unstated"; return 1; }
}
