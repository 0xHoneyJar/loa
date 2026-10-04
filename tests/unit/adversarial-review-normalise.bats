#!/usr/bin/env bats
# =============================================================================
# tests/unit/adversarial-review-normalise.bats — cycle-126 Sprint 2 (PRD FR-2.2 /
# FR-2.4, SDD D-2.2 / D-2.4). The tolerant schema: a finding missing only
# `failure_mode` is normalised (first sentence of `description`, ≤ 200 chars,
# `failure_mode_derived: true`) and reaches the reviewer without a repair
# round-trip; a payload that still fails goes to the sidecar AND is summarised
# in `metadata.rejected_summary[]`; the repair loop's model is `tiny` with an
# Anthropic key present, `claude-headless` without.
# Source-based harness (the pattern of adversarial-review-schema-enforced.bats).
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
    # the sprint id comes FIRST: teardown runs on any setup failure, and a delete target derived from
    # an unset id would be the a2a root (fourth run, chunk c C-001)
    SPRINT="sprint-norm-$$"
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    _claim_sprint_dir "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT" || return 1
    # this suite's own: the stale sweep deletes only marked dirs; the marker holds this process's start, so a recycled pid is not it
    mkdir -p "$PROJECT_ROOT/grimoires/loa/a2a" && printf '%s\n%s\n' "$(_sweep_start "$$")" "$(_sweep_where)" > "$PROJECT_ROOT/grimoires/loa/a2a/.$SPRINT.owner"
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    FIXTURES="$PROJECT_ROOT/tests/fixtures/dissent-rejected"
    TEST_DIR="${BATS_TEST_TMPDIR:-}"; NORM_OWN_TMP=""
    if [[ -z "$TEST_DIR" ]]; then TEST_DIR="$(mktemp -d)"; NORM_OWN_TMP="$TEST_DIR"; fi   # bats < 1.4: our own directory, removed in teardown (sixteenth run, c2a C-003)
    # the two ledgers the script appends to are the TEST's, by construction — never a shared /tmp file no suite truncates
    export LOA_MODELINV_LOG_PATH="$TEST_DIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$TEST_DIR/cost-ledger.jsonl"
    # every test gets its own CLI lock directory, as the companion suite does (round-1q dry run: a repair through the
    # claude-headless hop queued 60 s behind a LIVE dissent's claude.lock in the per-user directory and failed as a timeout —
    # the KF-037 contention class, in a unit test)
    export XDG_RUNTIME_DIR="$TEST_DIR"
    unset LOA_ADVERSARIAL_RUN_TAG _ADV_SIDECAR_TAG LOA_ADVERSARIAL_ENV_DIR LOA_ADVERSARIAL_NO_FM_DERIVATION   # (seventh run, c2 C-005)
    # …and every other knob the script reads (thirteenth run, c2 C-004): hermetic like the companion suite; the dotenv
    # seam points at an empty directory unless a case says otherwise
    unset LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS _ADV_REPAIR_DEAD_HOPS _ADV_REPAIR_RC_FILE LOA_MODEL_CONFIG LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS \
          LOA_ADVERSARIAL_CLI_HOP_TIMEOUT LOA_ADVERSARIAL_REPAIR_MODEL   # cleared BEFORE the script is sourced, which reads some at load (twenty-third run, c2a DISS-C-001)
    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    # the trailer is an indented `main "$@"` in the BASH_SOURCE guard: `^main` matched nothing; `:` keeps the `then` non-empty (twentieth run, c2b C-001)
    local _src; _src="$(sed 's/^\( *\)main "\$@"$/\1: main disabled for testing/' "$ADVERSARIAL_REVIEW")"   # (twenty-eighth run, c2a DISS-C-001: the substitution is asserted)
    grep -q ': main disabled for testing' <<<"$_src" || { echo "setup: the main trailer sed matched nothing" >&2; return 1; }
    ! grep -Eq '^[[:space:]]*main "\$@"' <<<"$_src" || { echo "setup: a main \"\$@\" call survived the sed" >&2; return 1; }
    eval "$_src"
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT
    CONF_ENABLED="true"; CONF_MODEL="gpt-5.5-pro"; CONF_TIMEOUT=60; CONF_BUDGET_CENTS=150
    CONF_ESCALATION_ENABLED="true"; CONF_SECONDARY_BUDGET=12000; CONF_MAX_FILE_LINES=500
    CONF_MAX_FILE_BYTES=51200; CONF_SECRET_SCANNING="true"; CONF_SECRET_ALLOWLIST=()
    LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=""
    REPAIR_CANARY="$TEST_DIR/repair-called-$$"
    NORM_HOLDER_PIDS=()   # stand-in processes a test spawns (NRM-23's companion timer); teardown ends them (sixteenth run, c2b C-003)
    # the normaliser must make the repair unnecessary: a stub that records the call and fails
    _repair_finding_via_model() { : > "$REPAIR_CANARY"; return 1; }
    # every credential alias the probe recognises, from the script's own table (twenty-first run, c2a C-001; as the companion suite)
    _scrub_cred_aliases || return 1
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-default"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    export LOA_ADVERSARIAL_CLI_PROBE=both   # both CLI binaries "installed" unless a case says otherwise (the repair chain gates on it)
}

# A directory an earlier, killed run of this suite left behind never accumulates (twenty-second run, c2a C-002) — and only a
# directory this suite MARKED as its own is ever deleted: setup writes `<a2a>/.<prefix>-<pid>.owner`, so a real sprint that
# happens to be named <prefix>-<n> is never touched (twenty-fifth run, c1a DISS-C-001). An owner is dead only when no probe
# sees it — `kill -0` also fails with EPERM for a LIVE process of another uid (twenty-fourth run, c1a DISS-C-001). The
# rename claims a directory, so concurrent teardowns never race one delete (twenty-fourth run, c2a DISS-C-001); a `.reap-<q>`
# a dead sweeper left is finished here, and the marker goes with its owner's last directory.
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
# (thirty-second run, c2a DISS-C-001: a pid alone outlives its owner — once a killed run's pid is reused, its directory was live
# for good. The marker holds the owner's start token; a live pid whose start differs is another process. An unknown token on
# either side — an older marker, a host with neither /proc nor ps — keeps the pid-only answer: never a live run's directory)
_sweep_start() {  # <pid> → /proc starttime, else a C/UTC lstart; "" when unknown
    local st
    if [[ -r "/proc/$1/stat" ]]; then
        st=$(awk '{ n = split($0, a, ")"); split(a[n], f, " "); print f[20] }' "/proc/$1/stat" 2>/dev/null) || st=""
        [[ "$st" =~ ^[0-9]+$ ]] && echo "t$st"
        return 0
    fi
    LC_ALL=C TZ=UTC0 ps -o lstart= -p "$1" 2>/dev/null | tr -s ' ' || true
}
_sweep_owner_alive() {  # <pid> <marker>
    local want now
    _sweep_alive "$1" || return 1
    want=$(head -n1 -- "$2" 2>/dev/null) || want=""
    [[ -n "$want" ]] || return 0
    now=$(_sweep_start "$1")
    [[ -z "$now" || "$now" == "$want" ]]
}
_sweep_stale_suite_dirs() {  # <a2a dir> <prefix>
    local a2a="$1" pre="$2" m p d q left
    for m in "$a2a"/."$pre"-[0-9]*.owner; do
        [[ -f "$m" && ! -L "$m" ]] || continue
        p=${m##*/."$pre"-}; p=${p%.owner}
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        _sweep_foreign "$m" && continue
        _sweep_owner_alive "$p" "$m" && continue
        left=0
        for d in "$a2a/$pre-$p" "$a2a/$pre-$p".reap-*; do   # (one directory per marker, never a sibling — twenty-ninth run, c2a)
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
    local d p
    for p in ${NORM_HOLDER_PIDS[@]+"${NORM_HOLDER_PIDS[@]}"}; do kill "$p" 2>/dev/null || true; done
    if [[ -n "${NORM_OWN_TMP:-}" && -d "$NORM_OWN_TMP" && "$(basename "$NORM_OWN_TMP")" == tmp.* ]]; then find "$NORM_OWN_TMP" -mindepth 1 -delete; rmdir "$NORM_OWN_TMP"; fi
    _sweep_stale_suite_dirs "$PROJECT_ROOT"/grimoires/loa/a2a sprint-norm
    [[ -n "${SPRINT:-}" && "$SPRINT" == sprint-norm-* ]] || return 0
    # this test's directory only — never a sibling it did not make (twenty-ninth run, c2a; as c1a DISS-001)
    d="$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}"
    if [[ -d "$d" && ! -L "$d" ]]; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi   # (never a link: the sweep's rule — twenty-seventh run, c2a DISS-C-002)
    rm -f -- "$PROJECT_ROOT/grimoires/loa/a2a/.$SPRINT.owner"
    # (thirty-third run, c2b DISS-C-004: the one link a test registered at its own path — removed, never followed)
    d="${NORM_OWN_LINK:-}"
    if [[ "$d" == "$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}" && -L "$d" ]]; then rm -f -- "$d"; fi
    # (thirty-second run, c2b DISS-C-003: the one sibling a test registered — that exact path, a real directory, this suite's shape)
    d="${NORM_SIB_DIR:-}"
    if [[ "$d" == "$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}-sib" && -d "$d" && ! -L "$d" ]]; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi
    return 0
}
_fake_repair_clock() {  # the repair budget reads _adv_repair_now: a file this test advances, never the wall clock (run 23, c2b DISS-C-001)
    echo 1000 > "$TEST_DIR/clock"
    _adv_repair_now() { cat "$TEST_DIR/clock"; }
}
_tick() { echo $(( $(cat "$TEST_DIR/clock") + $1 )) > "$TEST_DIR/clock"; }   # <seconds>

_env() {  # <content json string> → adapter envelope (unenforced)
    jq -n --arg c "$1" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}'
}
_fixture_content() {  # all three fixtures as one findings document
    jq -c -s '{findings: [.[] | .payload]}' "$FIXTURES"/0*.json
}

@test "NRM-1 the three real rejected payloads become findings with failure_mode_derived: true, no sidecar row, no repair call, empty rejected_summary" {
    result=$(process_findings "$(_env "$(_fixture_content)")" "audit" "gpt-5.5-pro" "$SPRINT" "0" "")
    [ "$(jq -r '.metadata.status' <<<"$result")" = "reviewed" ]
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq '[.findings[] | select(.failure_mode_derived == true)] | length' <<<"$result")" = "3" ]
    [ "$(jq -r '.findings[0].failure_mode' <<<"$result")" = "The autonomous skill explicitly continues execution when the guardrails orchestrator is missing, exits non-zero, or returns unparseable output." ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.rejected_summary | length' <<<"$result")" = "0" ]
    [ ! -e "$REPAIR_CANARY" ]
    sidecar="$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}/adversarial-rejected-audit.jsonl"
    [ ! -s "$sidecar" ]
}

@test "NRM-2 a derived failure_mode is the first sentence, capped at 200 characters, and never raises the severity" {
    long="$(printf 'A%.0s' $(seq 1 350)). Second sentence."   # (shell, as NRM-19 builds its strings — sixteenth run, c2a C-004)
    # a whitespace-only failure_mode is empty: derived over from the description (eighteenth run, a1 C-001)
    ws=$(jq -nc '{findings: [{"severity":"LOW","category":"other","description":"Real words here in the first sentence. Second sentence.","failure_mode":"  \t "}]}')
    r=$(process_findings "$(_env "$ws")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.findings[0].failure_mode' <<<"$r")" = "Real words here in the first sentence." ]
    [ "$(jq -r '.findings[0].failure_mode_derived' <<<"$r")" = "true" ]
    doc=$(jq -nc --arg d "$long" '{findings: [{"severity":"LOW","category":"other","description":$d}]}')
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    fm=$(jq -r '.findings[0].failure_mode' <<<"$result")
    [ "${#fm}" -le 200 ]
    [ "$(jq -r '.findings[0].severity' <<<"$result")" = "LOW" ]
    [ "$(jq -r '.findings[0].failure_mode_derived' <<<"$result")" = "true" ]
}

@test "NRM-3 a finding that carries its own failure_mode is untouched (no failure_mode_derived key)" {
    doc='{"findings":[{"id":"DISS-001","severity":"HIGH","category":"config","description":"d. e.","failure_mode":"stated"}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq -r '.findings[0].failure_mode' <<<"$result")" = "stated" ]
    [ "$(jq 'has("failure_mode_derived")' <<<"$(jq '.findings[0]' <<<"$result")")" = "false" ]
}

@test "NRM-4 a payload without a severity still goes to the sidecar AND appears in rejected_summary with its reason and anchor" {
    doc='{"findings":[{"title":"No severity here","category":"config","location":"x.sh:12","description":"Something fails when the file is missing. More."}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.rejected_summary | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.rejected_summary[0].reason' <<<"$result")" = "missing-severity" ]
    [ "$(jq -r '.metadata.rejected_summary[0].title' <<<"$result")" = "No severity here" ]
    [ "$(jq -r '.metadata.rejected_summary[0].anchor' <<<"$result")" = "x.sh:12" ]
    jq -e '.metadata.rejected_summary[0] | has("severity") and .severity == null' <<<"$result" >/dev/null   # (twenty-eighth run, c2a DISS-C-002: the key, not just a null read)
    jq -e '.metadata.rejected_summary[0] as $e | ["severity","title","anchor","reason","description_head"] | all(. as $k | $e | has($k))' <<<"$result" >/dev/null
    [[ "$(jq -r '.metadata.rejected_summary[0].description_head' <<<"$result")" == "Something fails when the file is missing."* ]]
    sidecar="$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}/adversarial-rejected-audit.jsonl"
    [ "$(grep -c '' "$sidecar")" = "1" ]   # not wc -l: BSD wc pads its count
    [ "$(jq -r '.reject_reason' "$sidecar")" = "missing-severity" ]
}

@test "NRM-5 the schema-enforced branch never derives (an enforced payload missing failure_mode is rejected, not repaired)" {
    doc='{"findings":[{"id":"DISS-001","severity":"HIGH","category":"config","description":"d."}]}'
    env=$(jq -n --arg c "$doc" '{content: $c, tokens_input: 1, tokens_output: 1, cost_usd: 0, latency_ms: 1, schema_enforced: true}')
    result=$(process_findings "$env" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.rejected_summary[0].reason' <<<"$result")" = "missing-or-empty-failure_mode" ]
    [ ! -e "$REPAIR_CANARY" ]
}

@test "NRM-6 the repair loop's model is tiny with an Anthropic key present and claude-headless without (presence only, value never read)" {
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    [ "$(_repair_model "gpt-5.5-pro")" = "claude-headless" ]
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
    [ "$(_repair_model "gpt-5.5-pro")" = "tiny" ]
    unset ANTHROPIC_API_KEY
    printf 'ANTHROPIC_API_KEY="from-dotenv"\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    [ "$(_repair_model "gpt-5.5-pro")" = "tiny" ]
    export LOA_ADVERSARIAL_REPAIR_MODEL="codex-headless"
    [ "$(_repair_model "gpt-5.5-pro")" = "codex-headless" ]
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "codex-headless" ]   # an operator pin is the whole chain
    unset LOA_ADVERSARIAL_REPAIR_MODEL
    # the negatives that decide routing in practice (fourth run, chunk c C-008): an empty value, a
    # quoted empty value, a commented line, an exported-but-empty variable → not present
    for line in 'ANTHROPIC_API_KEY=' 'ANTHROPIC_API_KEY=""' "ANTHROPIC_API_KEY=''" '# ANTHROPIC_API_KEY=abc' '  #ANTHROPIC_API_KEY=abc' 'ANTHROPIC_API_KEY=""  # was=sk-old' 'ANTHROPIC_API_KEY=  # key=rotated 2026-09'; do
        printf '%s\n' "$line" > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
        [ "$(_repair_model "gpt-5.5-pro")" = "claude-headless" ]
    done
    rm -f "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    ANTHROPIC_API_KEY="" bash -c 'true'; export ANTHROPIC_API_KEY=""
    [ "$(_repair_model "gpt-5.5-pro")" = "claude-headless" ]
    unset ANTHROPIC_API_KEY
    # the dotenv positives beyond the bare line (c2 C-007): the export form and .env alone (an empty .env.local
    # assignment does NOT fall through to .env — the override block below pins that; tenth run, c2 C-001)
    printf 'export ANTHROPIC_API_KEY="abc"\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    [ "$(_repair_model "gpt-5.5-pro")" = "tiny" ]
    rm -f "$LOA_ADVERSARIAL_ENV_DIR/.env.local"; printf 'ANTHROPIC_API_KEY=abc\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env"
    [ "$(_repair_model "gpt-5.5-pro")" = "tiny" ]
    # override precedence (eighth run, c2 C-002): an empty .env.local assignment DISABLES the key even when .env
    # carries a value; a non-empty .env.local wins over an empty .env; the last assignment in a file wins
    printf 'ANTHROPIC_API_KEY=\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    [ "$(_repair_model "gpt-5.5-pro")" = "claude-headless" ]
    printf 'ANTHROPIC_API_KEY=abc\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"; printf 'ANTHROPIC_API_KEY=\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env"
    [ "$(_repair_model "gpt-5.5-pro")" = "tiny" ]
    printf 'ANTHROPIC_API_KEY=abc\nANTHROPIC_API_KEY=\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    [ "$(_repair_model "gpt-5.5-pro")" = "claude-headless" ]
    rm -f "$LOA_ADVERSARIAL_ENV_DIR/.env" "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    # the repair chain (eighth run, a1 C-001): tiny only with a credential, claude-headless only with the
    # binary, and the voice that answered always last — never a chain that cannot run on this host
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]
    unset ANTHROPIC_API_KEY
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "claude-headless gpt-5.5-pro" ]
    export LOA_ADVERSARIAL_CLI_PROBE=none
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "gpt-5.5-pro" ]                 # an OpenAI-only host repairs through its primary
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny gpt-5.5-pro" ]
    [ "$(_repair_model_chain "claude-headless")" = "tiny claude-headless" ]   # the answering voice is not repeated
    unset ANTHROPIC_API_KEY; export LOA_ADVERSARIAL_CLI_PROBE=both
}

@test "NRM-7 with the normaliser bypassed, the repair loop still recovers the fixtures through a stubbed model and records repaired_count" {
    # bypass the failure_mode derivation (keep the positional id) so the repair path is exercised
    export LOA_ADVERSARIAL_NO_FM_DERIVATION=1   # bats-gated seam: production id derivation, no failure_mode derivation (c2 C-004)
    _repair_finding_via_model() {  # <finding> <type> <clause> <model> [timeout] → fixed finding (stubbed model)
        printf '%s' "$1" | jq -c '. + {failure_mode: "stubbed repair"}'
    }
    result=$(process_findings "$(_env "$(_fixture_content)")" "audit" "gpt-5.5-pro" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq '.metadata.repaired_count' <<<"$result")" = "3" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ]
}

@test "NRM-8 credential presence never materialises the value: an xtrace'd check echoes no secret (review C-008)" {
    # (thirty-fourth run, c2a DISS-C-002: every path here carries a quote — a checkout under "Merlin's Mac" is a path the probes
    # must pass as data, never a parse error that skips the very check)
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-x'q"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    printf 'ANTHROPIC_API_KEY="dotenv-secret-value-xyz-987"\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    run bash -xc "$(declare -f _adv_cred_aliases _adv_cred_present); PROJECT_ROOT=$(printf %q "$PROJECT_ROOT"); LOA_ADVERSARIAL_ENV_DIR=$(printf %q "$LOA_ADVERSARIAL_ENV_DIR"); BATS_TEST_FILENAME=x; _adv_cred_present anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" != *"dotenv-secret-value-xyz-987"* ]]
    # the exported-variable path too (seventh run, c2 C-003): the probe never expands the value
    # (the value enters through the environment, not the traced script — an `export` line would trace itself)
    # …hermetic like the first probe (twentieth run, c2a C-001): the dotenv seam points at an EMPTY directory, so only the
    # environment branch can answer — the inherited env-x above (or a host .env.local) would otherwise say "present" for it
    mkdir -p "$TEST_DIR/env-empty'q"
    ANTHROPIC_API_KEY=env-secret-value-123 run bash -xc "$(declare -f _adv_cred_aliases _adv_cred_present); PROJECT_ROOT=$(printf %q "$PROJECT_ROOT"); LOA_ADVERSARIAL_ENV_DIR=$(printf %q "$TEST_DIR/env-empty'q"); BATS_TEST_FILENAME=x; _adv_cred_present anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" != *"env-secret-value-123"* ]]
    # the inverse under the same prelude: no variable, no dotenv — absent, so the branch is proven both ways
    run env $(printf -- '-u %s ' $(_adv_cred_aliases anthropic)) bash -xc "$(declare -f _adv_cred_aliases _adv_cred_present); PROJECT_ROOT=$(printf %q "$PROJECT_ROOT"); LOA_ADVERSARIAL_ENV_DIR=$(printf %q "$TEST_DIR/env-empty'q"); BATS_TEST_FILENAME=x; _adv_cred_present anthropic"
    [ "$status" -eq 1 ]
}

@test "NRM-9 a derived id never collides with an id the model supplied — the collision takes max(explicit id) + 1 (fourth run, chunk c C-005)" {
    doc='{"findings":[{"id":"DISS-002","severity":"MEDIUM","category":"config","description":"Explicit id here.","failure_mode":"stated"},{"severity":"LOW","category":"other","description":"No id here."}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "2" ]
    [ "$(jq -r '[.findings[].id] | join(",")' <<<"$result")" = "DISS-002,DISS-003" ]
    [ "$(jq -r '.findings[1].id_derived' <<<"$result")" = "true" ]
    [ "$(jq -r '.findings[0] | has("id_derived")' <<<"$result")" = "false" ]
}

@test "NRM-10 the repair round-trip walks tiny then claude-headless when a credential is present: a failing tiny degrades to the CLI hop instead of rejecting (fourth run, chunk c C-008)" {
    export LOA_ADVERSARIAL_NO_FM_DERIVATION=1   # bats-gated seam: production id derivation, no failure_mode derivation (c2 C-004)
    export ANTHROPIC_API_KEY="presence-canary-nrm10-never-printed"   # no sk- prefix: a masked leak must still show (thirtieth run, c1a DISS-C-002)
    _repair_finding_via_model() {  # <finding> <type> <clause> <model> [timeout]
        echo "$4" >> "$TEST_DIR/repair-models"
        [[ "$4" == "tiny" ]] && return 1
        printf '%s' "$1" | jq -c '. + {failure_mode: "stubbed repair"}'
    }
    doc='{"findings":[{"id":"DISS-001","severity":"MEDIUM","category":"config","description":"Needs a repair."}]}'
    # the lock directory is resolved under this test's XDG_RUNTIME_DIR — deterministic, never a snapshot of the shared
    # per-user directories a live dissent writes to concurrently (twentieth run, c2a C-002; twenty-second run, c2a C-001)
    local uid; uid=$(id -u)
    [ "$(_adv_cli_lock_dir)" = "$TEST_DIR/loa-headless-locks-$uid" ]
    # one resolver in the CODE: counted over bash's own reprint of the script's functions (`declare -f` in a clean shell: no
    # comments, whatever quotes they hold — twenty-fifth run, c2a DISS-C-002; prose never reds a correct change, twenty-third
    # run, c2a DISS-C-003); a path assembled from pieces, or one at top level, is beyond a static count — the CLI hop's lock
    # below is the behavioural proof
    cat > "$TEST_DIR/df.sh" <<'DF'
source "$1/.claude/scripts/lib-content.sh"; source "$1/.claude/scripts/compat-lib.sh"
eval "$(sed 's/^\( *\)main "\$@"$/\1: main disabled/' "$2")"
declare -f
DF
    [ "$(PROJECT_ROOT="$PROJECT_ROOT" bash "$TEST_DIR/df.sh" "$PROJECT_ROOT" "$ADVERSARIAL_REVIEW" 2>/dev/null | grep -c 'loa-headless-locks')" = "1" ]
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.metadata.repaired_count' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ]
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-models")" = "tiny claude-headless " ]   # the answering voice (m) would be third; never reached
    # the CLI hop's lock was taken under this test's XDG_RUNTIME_DIR, never in the per-user directory a live dissent holds
    if command -v flock >/dev/null 2>&1; then
        [ -e "$TEST_DIR/loa-headless-locks-$uid/claude.lock" ]
    fi
    [[ "$result" != *"presence-canary-nrm10-never-printed"* ]]
}

@test "NRM-11 a non-object element in findings[] still lands in rejected_summary (raw value as description_head) and in the sidecar (fifth run C-006)" {
    doc='{"findings":["just a string",{"id":"DISS-002","severity":"MEDIUM","category":"config","description":"Fine.","failure_mode":"stated"}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.rejected_summary | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.rejected_summary[0].description_head' <<<"$result")" = '"just a string"' ]
    jq -e '.metadata.rejected_summary[0] | has("severity") and .severity == null and has("anchor") and has("title")' <<<"$result" >/dev/null   # (twenty-eighth run, c2a DISS-C-002)
}

@test "NRM-12 a finding with no description at all (or an empty one) cannot derive a failure_mode: it is rejected with a named reason, never crashes the run (seventh run, c2 C-006)" {
    # …and a whitespace-only description IS empty (round 1r: it derived a one-space failure_mode the validator accepted)
    doc='{"findings":[{"severity":"HIGH","category":"config"},{"severity":"HIGH","category":"config","description":""},{"severity":"HIGH","category":"config","description":null},{"severity":"HIGH","category":"config","description":"  \n\t "}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "4" ]
    # a whitespace-only description derives NO failure_mode (nineteenth run, a1 C-002: the same emptiness test as the validators),
    # and a repaired description supplies one — the repair is not spent on a payload that stays empty
    _repair_finding_via_model() { printf '%s' "$1" | jq -c '. + {description: "Repaired words in the first sentence. Second."}'; }
    ws=$(jq -nc '{findings: [{"severity":"HIGH","category":"config","description":"  \n "}]}')
    r=$(process_findings "$(_env "$ws")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(jq '.metadata.repaired_count' <<<"$r")" = "1" ]
    [ "$(jq -r '.findings[0].failure_mode' <<<"$r")" = "Repaired words in the first sentence." ]
    [ "$(jq -r '.findings[0].failure_mode_derived' <<<"$r")" = "true" ]
    _repair_finding_via_model() { : > "$REPAIR_CANARY"; return 1; }
    # …and with the derivation off (the bats seam) a whitespace-only failure_mode is rejected, never accepted blank (a1 C-001)
    ws=$(jq -nc '{findings: [{"severity":"HIGH","category":"config","description":"Words.","failure_mode":" "}]}')
    r=$(LOA_ADVERSARIAL_NO_FM_DERIVATION=1 process_findings "$(_env "$ws")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(jq -r '.metadata.rejected_summary[0].reason' <<<"$r")" = "missing-or-empty-failure_mode" ]
    [ "$(jq -r '[.metadata.rejected_summary[].reason] | unique | join(",")' <<<"$result")" = "missing-or-empty-description" ]
    [ "$(jq -r '.metadata.status' <<<"$result")" != "null" ]
}

@test "NRM-13 the derivation markers are not part of the repair's byte-diff: a model that omits id_derived / failure_mode_derived still repairs the violated field only (eighth run, a1 C-002)" {
    _repair_finding_via_model() {  # returns the candidate WITHOUT the markers, the violated field filled
        printf '%s' "$1" | jq -c 'del(.id_derived, .failure_mode_derived) + {category: "config"}'
    }
    doc='{"findings":[{"severity":"HIGH","description":"Needs a category. More words here."}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.repaired_count' <<<"$result")" = "1" ]
    [ "$(jq -r '.findings[0].id' <<<"$result")" = "DISS-001" ]
    [ "$(jq -r '.findings[0].category' <<<"$result")" = "config" ]
    # …and the provenance markers come back onto the accepted repair (ninth run, a1 C-003)
    [ "$(jq -r '.findings[0].id_derived' <<<"$result")" = "true" ]
    [ "$(jq -r '.findings[0].failure_mode_derived' <<<"$result")" = "true" ]
}

@test "NRM-14 a degenerate first sentence (an enumerator, an abbreviation) is not a failure_mode — below 20 characters the description's head is used (eighth run, a1 C-003)" {
    doc='{"findings":[{"severity":"HIGH","category":"config","description":"e.g. the sidecar is written before the lock is held, so rows interleave."},{"severity":"LOW","category":"other","description":"1. Missing null check on the cursor before the walk begins."},{"severity":"LOW","category":"other","description":"A real first sentence that is long enough. And a second one."}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq -r '.findings[0].failure_mode' <<<"$result")" = "e.g. the sidecar is written before the lock is held, so rows interleave." ]
    [ "$(jq -r '.findings[1].failure_mode' <<<"$result")" = "1. Missing null check on the cursor before the walk begins." ]
    [ "$(jq -r '.findings[2].failure_mode' <<<"$result")" = "A real first sentence that is long enough." ]
}

@test "NRM-15 the collision guard reads the highest explicit id, not the finding count: a derived id colliding with an explicit one takes max(explicit) + 1 (ninth run, a1 C-002 — the jq '?' that zeroed it)" {
    doc='{"findings":[{"id":"DISS-009","severity":"MEDIUM","category":"config","description":"Nine.","failure_mode":"s"},{"severity":"LOW","category":"other","description":"No id, positional DISS-002 collides."},{"id":"DISS-002","severity":"LOW","category":"other","description":"Two.","failure_mode":"s"}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq -r '[.findings[].id] | join(",")' <<<"$result")" = "DISS-009,DISS-010,DISS-002" ]
}

@test "NRM-16 credential presence resolves per alias with override precedence: an empty GOOGLE_API_KEY never hides a GEMINI_API_KEY assigned in the same or a lower source; every alias assigned empty at its deciding source disables (ninth run a1 C-005; tenth run c2 C-001)" {
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-g'q"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"   # (a quote in the path: thirty-fourth run, c2a DISS-C-002)
    _probe() {  # <env assignments…> — runs the probe in a shell with only the named Google variables (the operator's shell may export one)
        bash -c "unset GOOGLE_API_KEY GEMINI_API_KEY; $1; $(declare -f _adv_cred_aliases _adv_cred_present); PROJECT_ROOT=$(printf %q "$PROJECT_ROOT"); LOA_ADVERSARIAL_ENV_DIR=$(printf %q "$LOA_ADVERSARIAL_ENV_DIR"); BATS_TEST_FILENAME=x; _adv_cred_present google"
    }
    _probe 'export GOOGLE_API_KEY="" GEMINI_API_KEY="present-never-printed"'                       # env: one alias empty, the other set → present
    rc=0; _probe 'export GOOGLE_API_KEY="" GEMINI_API_KEY=""' || rc=$?; [ "$rc" = "1" ]              # env: both empty → disabled
    printf 'GOOGLE_API_KEY=\nGEMINI_API_KEY=abc\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    _probe ':'                                                                                    # .env.local: one empty, one set → present
    printf 'GOOGLE_API_KEY=\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"; printf 'GEMINI_API_KEY=abc\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env"
    _probe ':'                                                                                    # per alias: GEMINI is unassigned in .env.local and falls to .env → present (the per-source rule said absent)
    printf 'GOOGLE_API_KEY=\nGEMINI_API_KEY=\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    rc=0; _probe ':' || rc=$?; [ "$rc" = "1" ]                                                    # both aliases overridden empty in .env.local: .env's value is never reached
    rm -f "$LOA_ADVERSARIAL_ENV_DIR/.env"; printf 'GEMINI_API_KEY=abc\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    _probe 'export GOOGLE_API_KEY=""'                                                              # an empty env override of one alias, the other alias from .env.local → present
    rc=0; _probe 'export GOOGLE_API_KEY="" GEMINI_API_KEY=""' || rc=$?; [ "$rc" = "1" ]              # …unless the env overrides both
}

@test "NRM-17 a derived id steps past every taken id even when the explicit-id scan yielded nothing: [DISS-003, DISS-004, <no id>] never produces a duplicate (tenth run, a1 C-002)" {
    doc='{"findings":[{"id":"DISS-003","severity":"MEDIUM","category":"config","description":"Three.","failure_mode":"s"},{"id":"DISS-004","severity":"MEDIUM","category":"config","description":"Four.","failure_mode":"s"},{"severity":"LOW","category":"other","description":"No id; positional DISS-003 collides."}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq -r '[.findings[].id] | join(",")' <<<"$result")" = "DISS-003,DISS-004,DISS-005" ]
    [ "$(jq '[.findings[].id] | unique | length' <<<"$result")" = "3" ]
    # two colliding positional ids in one document never share a number: each derived id joins the taken set before
    # the next finding is numbered (twelfth run, c2 C-001)
    doc='{"findings":[{"id":"DISS-003","severity":"MEDIUM","category":"config","description":"Three.","failure_mode":"s"},{"id":"DISS-004","severity":"MEDIUM","category":"config","description":"Four.","failure_mode":"s"},{"severity":"LOW","category":"other","description":"No id A."},{"severity":"LOW","category":"other","description":"No id B."}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq -r '[.findings[].id] | join(",")' <<<"$result")" = "DISS-003,DISS-004,DISS-005,DISS-006" ]
    doc='{"findings":[{"id":"DISS-001","severity":"LOW","category":"other","description":"One.","failure_mode":"s"},{"severity":"LOW","category":"other","description":"No id A."},{"severity":"LOW","category":"other","description":"No id B."},{"id":"DISS-002","severity":"LOW","category":"other","description":"Two.","failure_mode":"s"},{"id":"DISS-003","severity":"LOW","category":"other","description":"Three.","failure_mode":"s"}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "5" ]
    [ "$(jq '[.findings[].id] | unique | length' <<<"$result")" = "5" ]
    # derived ids start past BOTH the explicit ids and the positional range (five findings → DISS-005 is a possible
    # positional id), so the two colliders take 006 and 007 — distinct from each other and from every explicit id
    [ "$(jq -r '[.findings[] | select(.id_derived == true) | .id] | join(",")' <<<"$result")" = "DISS-006,DISS-007" ]
}

@test "NRM-18 the shell's CLI-hop ceiling equals cheval's HEADLESS_TIMEOUT_CEILING_SECONDS, and an over-ceiling catalog value bounds the hop at connect + ceiling (tenth run, d C-001: one clamp, two readers)" {
    command -v yq >/dev/null 2>&1 || skip "yq not installed: the hop bound cannot read a catalog"
    py="$PROJECT_ROOT/.venv/bin/python"; [[ -x "$py" ]] || py=python3
    ceiling=$(cd "$PROJECT_ROOT/.claude/adapters" && "$py" -c 'from loa_cheval.types import HEADLESS_TIMEOUT_CEILING_SECONDS as c; print(int(c))' 2>/dev/null) || skip "loa_cheval is not importable with $py"
    [ "$ceiling" = "$_ADV_CLI_HOP_CEILING" ]
    printf 'providers:\n  anthropic:\n    connect_timeout: 10\n    read_timeout: 120\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 7200\n' > "$TEST_DIR/over.yaml"
    [ "$(LOA_MODEL_CONFIG="$TEST_DIR/over.yaml" _adv_cli_hop_bound claude-headless)" = "$(( 10 + ceiling ))" ]
    # a provider read_timeout already above the ceiling is NOT clamped — the shell mirrors cheval (the Python contract
    # pins 4000 → 4020 for connect 20): with or without the catalog key (thirteenth run, c2 C-001)
    printf 'providers:\n  anthropic:\n    connect_timeout: 10\n    read_timeout: 4000\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n' > "$TEST_DIR/rt.yaml"
    [ "$(LOA_MODEL_CONFIG="$TEST_DIR/rt.yaml" _adv_cli_hop_bound claude-headless)" = "4010" ]
    printf 'providers:\n  anthropic:\n    connect_timeout: 10\n    read_timeout: 4000\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 7200\n' > "$TEST_DIR/rt2.yaml"
    [ "$(LOA_MODEL_CONFIG="$TEST_DIR/rt2.yaml" _adv_cli_hop_bound claude-headless)" = "4010" ]
    # cheval's whole formula whenever the catalog was read: a connect_timeout above 10 s counts under the 600 s read floor
    # too (sixteenth run, a2 C-003); the flat 610 only without a catalog
    printf 'providers:\n  anthropic:\n    connect_timeout: 30\n    read_timeout: 120\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n' > "$TEST_DIR/ct.yaml"
    [ "$(LOA_MODEL_CONFIG="$TEST_DIR/ct.yaml" _adv_cli_hop_bound claude-headless)" = "630" ]
    # a hop no catalog lists keeps the operator fallback even though a catalog WAS read — yq's `//` fires on an empty
    # stream, so a defaulted connect / read must never count as catalog data (round-1q dry run, CMP-22 red on the copy);
    # a listed hop is bound by the formula whatever the fallback says
    [ "$(LOA_MODEL_CONFIG="$TEST_DIR/ct.yaml" _ADV_CLI_HOP_TIMEOUT=100 _adv_cli_hop_bound foo-headless)" = "100" ]
    [ "$(LOA_MODEL_CONFIG="$TEST_DIR/ct.yaml" _ADV_CLI_HOP_TIMEOUT=100 _adv_cli_hop_bound claude-headless)" = "630" ]
    [ "$(LOA_MODEL_CONFIG="$TEST_DIR/does-not-exist.yaml" _adv_cli_hop_bound claude-headless)" = "610" ]
}

@test "NRM-19 LOA_ADVERSARIAL_RUN_TAG is validated, not stripped: a tag outside [A-Za-z0-9_-]{1,64} becomes a short hash of its raw value, said once, so c.1 and c1 never share a sidecar (eleventh run, a1 C-002)" {
    [ "$(LOA_ADVERSARIAL_RUN_TAG="" _adv_run_tag)" = "" ]
    [ "$(LOA_ADVERSARIAL_RUN_TAG="c1-dissent_script" _adv_run_tag 2>/dev/null)" = "c1-dissent_script" ]
    a=$(LOA_ADVERSARIAL_RUN_TAG="c.1" _adv_run_tag 2>"$TEST_DIR/tag-err"); b=$(LOA_ADVERSARIAL_RUN_TAG="c1" _adv_run_tag 2>/dev/null)
    c=$(LOA_ADVERSARIAL_RUN_TAG="a/1" _adv_run_tag 2>/dev/null); d=$(LOA_ADVERSARIAL_RUN_TAG="x y" _adv_run_tag 2>/dev/null)
    [[ "$a" =~ ^h[0-9a-f]{12}$ ]]; [ "$b" = "c1" ]; [[ "$c" =~ ^h[0-9a-f]{12}$ ]]; [[ "$d" =~ ^h[0-9a-f]{12}$ ]]
    [ "$a" != "$c" ]; [ "$a" != "$d" ]; [ "$c" != "$d" ]
    grep -q "LOA_ADVERSARIAL_RUN_TAG is not \[A-Za-z0-9_-\]{1,64}" "$TEST_DIR/tag-err"
    [ "$(grep -cF "c.1" "$TEST_DIR/tag-err")" = "0" ]   # the raw value is not echoed, as a fixed string — `c.1` as a regex matches c01 too (sixteenth run, c2a C-001)
    grep -qF "the tag $a" "$TEST_DIR/tag-err"          # …and the hashed tag IS named, so the line is pinned positively
    long=$(printf 'a%.0s' $(seq 1 65)); [[ "$(LOA_ADVERSARIAL_RUN_TAG="$long" _adv_run_tag 2>/dev/null)" =~ ^h[0-9a-f]{12}$ ]]
    # no digest tool at all (twelfth run, c2 C-003): the raw tag is hex-encoded — distinct tags stay distinct, never a shared "invalid"
    sha256sum() { return 127; }; shasum() { return 127; }
    [ "$(LOA_ADVERSARIAL_RUN_TAG="c.1" _adv_run_tag 2>/dev/null)" = "h632e31" ]
    [ "$(LOA_ADVERSARIAL_RUN_TAG="a/1" _adv_run_tag 2>/dev/null)" = "h612f31" ]
    # …whole up to 100 bytes: two raw tags that differ only after byte 20 never share a name (eighteenth run, a2 C-004); beyond
    # 100 bytes the hex is cut and the byte length appended, so the name stays a filename
    long1="$(printf 'x%.0s' $(seq 1 30))/1"; long2="$(printf 'x%.0s' $(seq 1 30))/2"
    [ "$(LOA_ADVERSARIAL_RUN_TAG="$long1" _adv_run_tag 2>/dev/null)" != "$(LOA_ADVERSARIAL_RUN_TAG="$long2" _adv_run_tag 2>/dev/null)" ]
    huge="$(printf 'y%.0s' $(seq 1 150))/1"
    [[ "$(LOA_ADVERSARIAL_RUN_TAG="$huge" _adv_run_tag 2>/dev/null)" =~ ^h[0-9a-f]{200}-152$ ]]
    # …and that branch is reachable under errexit, as process_findings calls it (fifteenth run, a2 C-003): a failing
    # digest pipeline never aborts the resolver
    # (the script's own option line, -u included, and nothing pre-seeded: the resolver reads its flag with a default — c2a C-002)
    run bash -euo pipefail -c "sha256sum() { return 127; }; shasum() { return 127; }; export -f sha256sum shasum; $(declare -f _adv_resolve_run_tag log); LOA_ADVERSARIAL_RUN_TAG='c.1'; _adv_resolve_run_tag 2>/dev/null; printf '%s' \"\$_ADV_RUN_TAG\""
    [ "$status" -eq 0 ]
    [ "$output" = "h632e31" ]
    unset -f sha256sum shasum
    # the same warning once per process: the second call is silent
    ( LOA_ADVERSARIAL_RUN_TAG="c.1"; _adv_run_tag >/dev/null; _adv_run_tag >/dev/null ) 2>"$TEST_DIR/tag-err2"
    [ "$(grep -c "is not" "$TEST_DIR/tag-err2")" = "1" ]
    # end to end: the sidecar a rejecting run writes carries the hashed tag, never the stripped one
    # (hermetic on its own, twenty-first run c2b C-002: a failing repair stub and an empty dotenv seam — never setup's alone)
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; return 1; }
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"; : > "$TEST_DIR/repair-calls"
    doc='{"findings":[{"title":"no severity","category":"other","description":"Something fails."}]}'
    LOA_ADVERSARIAL_RUN_TAG="c.1" process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" >/dev/null 2>&1 || true
    [ -f "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT/adversarial-rejected-audit-$a.jsonl" ]
    [ ! -e "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT/adversarial-rejected-audit-c1.jsonl" ]
    [ -s "$TEST_DIR/repair-calls" ]   # the repair ran through this test's stub, not a real hop
}

@test "NRM-20 an explicit auth (4) or quota (6) exit code retires a repair hop for the run's remaining repairs; exit 1 (unavailable, or a CLI-hop timeout reported as such), a lock timeout, no exit code or an unusable reply retires nothing; the answering voice never is (eleventh run a1 C-003; twelfth run a1 C-001)" {
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]
    [ "$(_ADV_REPAIR_DEAD_HOPS="tiny" _repair_model_chain "gpt-5.5-pro")" = "claude-headless gpt-5.5-pro" ]
    [ "$(_ADV_REPAIR_DEAD_HOPS="tiny claude-headless" _repair_model_chain "gpt-5.5-pro")" = "gpt-5.5-pro" ]
    [ "$(_ADV_REPAIR_DEAD_HOPS="gpt-5.5-pro" _repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]   # the answering voice stays
    [ "$(_ADV_REPAIR_DEAD_HOPS="claude-headless" _repair_model_chain "claude-headless")" = "tiny claude-headless" ]
    [ "$(_repair_model_chain "anthropic:claude-headless")" = "tiny claude-headless" ]   # (sixteenth run, a1 C-002: a prefixed answering voice is not appended twice)
    [ "$(_ADV_REPAIR_DEAD_HOPS="claude-headless" _repair_model_chain "anthropic:claude-headless")" = "tiny claude-headless" ]   # (eighteenth run, a1 C-002: never retired, however spelled)
    _adv_repair_retire_hop tiny 4 2>/dev/null; _adv_repair_retire_hop tiny 4 2>/dev/null; _adv_repair_retire_hop foo 6 2>/dev/null
    [ "$_ADV_REPAIR_DEAD_HOPS" = "tiny foo" ]
    unset _ADV_REPAIR_DEAD_HOPS
    # through the loop: two payloads the normaliser cannot save. tiny answers the first with the exit code in TINY_RC,
    # claude-headless with an unusable reply (rc 1, no JSON): an explicit auth (4) or quota (6) code retires tiny for
    # the second payload; exit 1 — a CLI-hop timeout or a transient failure looks the same here — retires nothing
    # (twelfth run, a1 C-001)
    _repair_finding_via_model() {
        echo "$4" >> "$TEST_DIR/repair-calls"
        echo "${_ADV_REPAIR_RC_FILE:-}" >> "$TEST_DIR/rc-paths"   # (per repair, per voice: a fresh mktemp — thirteenth run, c2 C-003)
        case "$4" in
            tiny) [[ -n "${_ADV_REPAIR_RC_FILE:-}" ]] && printf '%s' "${TINY_RC:-4}" > "$_ADV_REPAIR_RC_FILE"; return 1 ;;
            claude-headless) [[ -n "${_ADV_REPAIR_RC_FILE:-}" ]] && printf 1 > "$_ADV_REPAIR_RC_FILE"; return 1 ;;
            *) return 1 ;;
        esac
    }
    doc='{"findings":[{"title":"no severity one","category":"other","description":"Something fails."},{"title":"no severity two","category":"other","description":"Something else fails."}]}'
    for rc_case in 4 6 1; do
        : > "$TEST_DIR/repair-calls"; unset _ADV_REPAIR_DEAD_HOPS
        result=$(TINY_RC="$rc_case" process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
        [ "$(jq '.metadata.rejected_count' <<<"$result")" = "2" ]
        if [[ "$rc_case" == "1" ]]; then
            [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny claude-headless m tiny claude-headless m " ]
            [ "$(grep -c "retired" "$TEST_DIR/repair-err")" = "0" ]
        else
            [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny claude-headless m claude-headless m " ]
            grep -q "Repair hop tiny failed (rc $rc_case) — retired" "$TEST_DIR/repair-err"
            [ "$(grep -c "retired" "$TEST_DIR/repair-err")" = "1" ]
        fi
    done
    unset _ADV_REPAIR_DEAD_HOPS
    # the rc file is a fresh mktemp under the workdir for every repair of every process_findings call — never a path
    # keyed on $$ that a concurrent voice could truncate or read (thirteenth run, c2 C-003)
    # exactly one file per repaired payload — three iterations × two payloads — and each shared by that payload's hops
    # (a per-hop mktemp would show 16 paths, a per-process path one; fourteenth run, c2 C-002)
    [ "$(sort -u "$TEST_DIR/rc-paths" | grep -c .)" = "6" ]
    [ "$(sort "$TEST_DIR/rc-paths" | uniq -c | awk '$1 < 2' | grep -c .)" = "0" ]
    [ "$(grep -vc 'adv-repair-rc\.' "$TEST_DIR/rc-paths")" = "0" ]
    # a hop that writes NO exit code (the answering voice's arm, a round-trip that died before the capture) and one
    # that returns 124 without running (the lock timed out) retire nothing — after tiny's rc 4 only tiny is retired,
    # never a stale 4 read from the previous hop (twelfth run, c2 C-002: the rc file is truncated before every hop)
    for ch_shape in none 124; do
        _repair_finding_via_model() {
            echo "$4" >> "$TEST_DIR/repair-calls"
            case "$4" in
                tiny) [[ -n "${_ADV_REPAIR_RC_FILE:-}" ]] && printf 4 > "$_ADV_REPAIR_RC_FILE"; return 1 ;;
                claude-headless) [[ "$CH_SHAPE" == "124" ]] && return 124; return 1 ;;
                *) return 1 ;;
            esac
        }
        : > "$TEST_DIR/repair-calls"; unset _ADV_REPAIR_DEAD_HOPS
        result=$(CH_SHAPE="$ch_shape" process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
        [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny claude-headless m claude-headless m " ]
        [ "$(grep -c "retired" "$TEST_DIR/repair-err")" = "1" ]
        grep -q "Repair hop tiny failed (rc 4) — retired" "$TEST_DIR/repair-err"
    done
    unset _ADV_REPAIR_DEAD_HOPS
    unset ANTHROPIC_API_KEY
}

@test "NRM-21 a rejected_summary entry names its sidecar row: the row's index and the raw payload's title — the normaliser's positional id only when the payload had none, marked title_derived (twelfth run, a1 C-003)" {
    # hermetic on its own, as its siblings are (sixteenth run, c2b C-005): a recording stub that fails, the dotenv seam an
    # empty directory — never a real repair on the host, whatever setup installs
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; return 1; }
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    doc='{"findings":[{"category":"other","description":"No title, no id, no severity."},{"title":"named payload","category":"other","description":"No severity either."}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "2" ]
    [ "$(jq -c '[.metadata.rejected_summary[] | {index, title_derived}]' <<<"$result")" = '[{"index":0,"title_derived":true},{"index":1,"title_derived":false}]' ]
    [[ "$(jq -r '.metadata.rejected_summary[0].title' <<<"$result")" =~ ^DISS-[0-9]{3}$ ]]
    [ "$(jq -r '.metadata.rejected_summary[1].title' <<<"$result")" = "named payload" ]
    sidecar="$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT/adversarial-rejected-audit.jsonl"
    [ "$(jq -c '[.index, (.payload.title // null)]' "$sidecar" | tr '\n' ' ')" = '[0,null] [1,"named payload"] ' ]
    # an EMPTY id or title is absent, not a title (sixteenth run, a1 C-005)
    doc='{"findings":[{"id":"","title":"","category":"other","description":"Empty id and title, no severity."}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [[ "$(jq -r '.metadata.rejected_summary[0].title' <<<"$result")" =~ ^DISS-[0-9]{3}$ ]]
    [ "$(jq -r '.metadata.rejected_summary[0].title_derived' <<<"$result")" = "true" ]
}

@test "NRM-22 the run's repairs share a wall-clock budget: once LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS is spent the remaining payloads are rejected unrepaired and counted in repair_budget_exhausted (twelfth run, a1 C-002)" {
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    _fake_repair_clock
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; _tick 3; return 1; }   # each hop takes three (fake) seconds
    doc='{"findings":[{"title":"one","category":"other","description":"No severity."},{"title":"two","category":"other","description":"No severity."},{"title":"three","category":"other","description":"No severity."}]}'
    # a 6 s budget with a 1 s call timeout and 3 s hops: `tiny` and `claude-headless` both reach the claude CLI, so each is
    # charged its CLI bound (twentieth run, a3 DISS-C-003) and is never started — named over_budget — while the answering
    # voice (an HTTP hop, estimated at its 1 s call timeout) runs while a second remains; two 3 s hops spend the budget, so
    # the third payload is rejected unrepaired (fourteenth run, a1 C-002). The clock is the test's own (run 23, c2b
    # DISS-C-001: the old wall-clock margins flaked under load), so every count is exact
    : > "$TEST_DIR/repair-calls"; CONF_TIMEOUT=1
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=6 process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
    CONF_TIMEOUT=60
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "3" ]
    [ "$(jq '.metadata.repair_budget_exhausted' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.repair_wall_budget_seconds' <<<"$result")" = "6" ]
    [ "$(jq '.metadata.repair_wall_seconds' <<<"$result")" = "6" ]
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "m m " ]
    jq -e '.metadata.repair_hops_skipped | index("claude-headless:over_budget") != null' <<<"$result" >/dev/null
    jq -e '.metadata.repair_hops_skipped | index("tiny:over_budget") != null' <<<"$result" >/dev/null
    grep -q "Repair hop claude-headless needs up to .*s and .*s of the repair budget remain — not started" "$TEST_DIR/repair-err"
    grep -q "Repair budget: 6s of 6s used — payload" "$TEST_DIR/repair-err"
    # every repair-budget clock read goes through the seam — a raw clock in process_findings, or in any function it calls,
    # is the wall clock again: every spelling (`date +%s`, `date '+%s'`, $EPOCHSECONDS / $EPOCHREALTIME, `printf '%(%s)T'`,
    # $SECONDS), only the seam itself excepted (twenty-fifth run, c2b DISS-C-001)
    # (every function reachable from process_findings, a worklist to a fixed point — the seam's own body is not walked — and
    # `date` as a word: an identifier holding "date" before a printf '%s' is not a clock — twenty-sixth run, c2b DISS-C-002)
    # (the graph walked is the production one: setup and this case stub _repair_finding_via_model, so the walk re-loads the
    # script in a subshell first — the production repair and its private callees are scanned too: twenty-seventh run, c2b
    # DISS-C-001)
    local out
    out=$( _src="$(sed 's/^\( *\)main "\$@"$/\1: main disabled for testing/' "$ADVERSARIAL_REVIEW")"; grep -q ': main disabled for testing' <<<"$_src" || { echo "the main trailer sed matched nothing"; exit 1; }; eval "$_src"
        local fns
        _nrm22_walk() {  # <root> → the space-padded set of functions reachable from it (the seam's body is not walked)
            local f g; local -a todo=("$1"); fns=" "
            while (( ${#todo[@]} )); do
                f="${todo[0]}"; todo=("${todo[@]:1}")
                [[ "$fns" == *" $f "* ]] && continue
                fns+="$f "; [[ "$f" == _adv_repair_now ]] && continue
                # (any name bash accepts for a function — a::b, a.b, a-b — as well as identifier words: twenty-ninth run, c2b DISS-C-001)
                for g in $(declare -f "$f" | tail -n +2 | grep -oE '[A-Za-z_][A-Za-z0-9_:.-]*|[A-Za-z_][A-Za-z0-9_]*' | LC_ALL=C sort -u); do
                    [[ "$fns" != *" $g "* ]] && declare -F "$g" >/dev/null 2>&1 && todo+=("$g")
                done
            done
        }
        _nrm22_clocks() {  # the functions of $fns that read a raw clock
            local f clk
            for f in $fns; do
                [[ "$f" == _adv_repair_now ]] && continue
                # (SECONDS as a word: $SECONDS, a bare `SECONDS=0` reset, `(( SECONDS - t ))` — twenty-ninth run, c2b DISS-C-001)
                clk=$(declare -f "$f" | grep -cE 'EPOCH(SECONDS|REALTIME)|(^|[^A-Za-z0-9_])date[[:space:]][^|;]*%s|%\([^)]*\)T|(^|[^A-Za-z0-9_])SECONDS([^A-Za-z0-9_]|$)') || true
                [ "$clk" = "0" ] || echo "CLOCK $f ($clk)"
            done
        }
        # the scan's own negative pin: a reset, an arithmetic read, behind a callee whose name is no identifier word
        _nrm22_x() { _nrm22::reset; _nrm22.read; _nrm22-tick; }
        _nrm22::reset() { SECONDS=0; }; _nrm22.read() { (( SECONDS > 1 )); }; _nrm22-tick() { let "t = SECONDS"; }
        _nrm22_walk _nrm22_x
        echo "PIN$(_nrm22_clocks | tr '\n' ' ')"
        _nrm22_walk process_findings
        echo "FNS$fns"
        _nrm22_clocks
        declare -f _repair_finding_via_model | grep -qE 'REPAIR_CANARY|repair-calls' && echo "STUBBED" || true ) || { echo "the clock scan did not run"; return 1; }
    if grep -q '^STUBBED' <<<"$out"; then echo "the walk saw the stub, not the production repair"; return 1; fi
    output=$out
    pin=$(grep '^PIN' <<<"$output")
    [[ "$pin" == *"CLOCK _nrm22::reset "* && "$pin" == *"CLOCK _nrm22.read "* && "$pin" == *"CLOCK _nrm22-tick "* ]] || { echo "the scan misses a clock spelling or a callee name: $pin"; return 1; }
    fns=$(grep '^FNS' <<<"$output"); fns=" ${fns#FNS}"
    [[ "$fns" == *" _adv_hop_charge "* && "$fns" == *" _adv_repair_now "* && "$fns" == *" _adv_cli_hop_bound "* ]]   # (the scan sees the budget helpers, and a callee's callee)
    [[ "$fns" == *" _repair_finding_via_model "* ]]
    if grep -q '^CLOCK ' <<<"$output"; then echo "reads the wall clock outside the _adv_repair_now seam: $(grep '^CLOCK ' <<<"$output" | tr '\n' ' ')"; return 1; fi
    # (the clock stays the test's for the rest of this case: none of the blocks below spends time)
    # the default budget is ADV_REPAIR_MAX_PER_RUN × timeout × 2, or one full CLI repair plus a timeout if that is more
    # (fourteenth run, a1 C-002: a CLI hop is bounded by cheval, not by the call timeout) — never spent by three
    # one-second payloads
    # (nineteenth run, a1 C-001: two full CLI repairs; twentieth run, a3 DISS-C-003: the heaviest hop is charged as the budget
    # charges it — `tiny` with a key pays its lock wait, its timeout and the claude CLI bound)
    # (both charges captured and checked as numbers first — an empty charge would make the comparison an arithmetic error
    # that `&&` swallows; tiny reaches the CLI, so it outweighs the CLI hop's own charge — twenty-sixth run, c2b DISS-C-003)
    local _tc _cc; _tc=$(_adv_hop_charge tiny 60); _cc=$(_adv_hop_charge claude-headless 60)
    [[ "$_tc" =~ ^[0-9]+$ && "$_cc" =~ ^[0-9]+$ ]] || { echo "hop charges tiny='$_tc' claude-headless='$_cc'"; return 1; }
    (( _tc > _cc ))
    _hmax=$_tc
    exp=$(( 2 * _hmax + 60 )); (( exp < ADV_REPAIR_MAX_PER_RUN * 60 * 2 )) && exp=$(( ADV_REPAIR_MAX_PER_RUN * 60 * 2 ))
    # (the budget figure, the skip list and the validator lines are invariant to hop duration: no sleep here — c2b C-002)
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; return 1; }
    : > "$TEST_DIR/repair-calls"
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(jq '.metadata.repair_budget_exhausted' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.repair_wall_budget_seconds' <<<"$result")" = "$exp" ]
    [ "$(jq -c '.metadata.repair_hops_skipped' <<<"$result")" = "[]" ]
    # a knob that is not a whole number is said once and the default applies — the envelope is intact (thirteenth run, a1 C-001)
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=5m process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "3" ]
    [ "$(jq '.metadata.repair_wall_budget_seconds' <<<"$result")" = "$exp" ]
    grep -q "LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS='5m' is not a whole number of at least 1" "$TEST_DIR/repair-err"
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=0900 process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
    [ "$(jq '.metadata.repair_wall_budget_seconds' <<<"$result")" = "$exp" ]   # (a2 C-004: a leading zero is octal to bash — rejected, the default applies)
    grep -q "LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS='0900' is not a whole number of at least 1" "$TEST_DIR/repair-err"
    # every hop pre-empted from the start (a 30 s budget against bounds of 900 s and more): no model is asked — a budget
    # exhaustion for every payload, repair_attempted false on the rows, no repair slot spent (fifteenth run, a2 C-001)
    # (twentieth-run dry run: a 1 s budget is spent by crossing one whole-second boundary, so under load the first payload
    # was rejected before any hop was weighed and the over_budget names were never written — 30 s is never spent here)
    : > "$TEST_DIR/repair-calls"
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=30 process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "3" ]
    [ "$(jq '.metadata.repair_budget_exhausted' <<<"$result")" = "3" ]
    [ ! -s "$TEST_DIR/repair-calls" ]
    [ "$(jq -r '.repair_attempted' "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT/adversarial-rejected-audit.jsonl" | sort -u)" = "false" ]
    jq -e '.metadata.repair_hops_skipped | index("tiny:over_budget") != null' <<<"$result" >/dev/null
    # a keyless host (no tiny): the default budget (two full CLI repairs plus a timeout) admits the CLI hop for both payloads
    # — this block pins the default budget, not duration-following: a failed hop notes no duration (NRM-27), and NRM-27's
    # usable-reply half is the regression pin for the observed-duration estimate (twentieth run, c2b C-002)
    unset ANTHROPIC_API_KEY
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; return 1; }   # (no real sleep: the fake clock is the test's — twenty-fourth run, c2b DISS-C-001)
    doc2='{"findings":[{"title":"one","category":"other","description":"No severity."},{"title":"two","category":"other","description":"No severity."}]}'
    : > "$TEST_DIR/repair-calls"
    result=$(process_findings "$(_env "$doc2")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "claude-headless m claude-headless m " ]
    [ "$(jq -c '.metadata.repair_hops_skipped' <<<"$result")" = "[]" ]
    [ "$(jq '.metadata.repair_budget_exhausted' <<<"$result")" = "0" ]
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
    unset ANTHROPIC_API_KEY
}

@test "NRM-23 a repair drops a shared hop only while the companion is ON it, and the envelope names the skip (repair_hops_skipped); a companion busy elsewhere leaves the hop in the chain (thirteenth run, a1 C-002)" {
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    companion_shared_hops="claude-headless"; companion_workdir="$TEST_DIR/cw"; mkdir -p "$companion_workdir"
    # the stand-in outlives any sequence of calls and never outlives the test (sixteenth run, c2b C-003: a 30 s timer was a
    # hidden ceiling, and a dead timer would read as a hop-skip regression)
    sleep 600 3>&- & _ADV_COMPANION_PID=$!; NORM_HOLDER_PIDS+=("$_ADV_COMPANION_PID"); _ADV_COMPANION_START=$(_adv_proc_start "$_ADV_COMPANION_PID")   # (a live companion has a token — nineteenth run, a4 C-001)
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; return 1; }
    doc='{"findings":[{"title":"no severity","category":"other","description":"Something fails."}]}'
    # the companion is on claude-headless: the repair skips it and says so
    printf 'claude-headless' > "$companion_workdir/companion.current"; printf 'hop' > "$companion_workdir/companion.phase"
    : > "$TEST_DIR/repair-calls"
    kill -0 "$_ADV_COMPANION_PID"   # the stand-in is alive for a skip-expecting call
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny m " ]
    [ "$(jq -c '.metadata.repair_hops_skipped' <<<"$result")" = '["claude-headless:shared_with_companion"]' ]
    # …and that decision does not depend on the PRIMARY chain sharing the hop (fourteenth run, a1 C-001): an OpenAI-primary
    # host with `claude` installed has an empty shared set and the same companion on claude-headless
    companion_shared_hops=""
    : > "$TEST_DIR/repair-calls"
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny m " ]
    [ "$(jq -c '.metadata.repair_hops_skipped' <<<"$result")" = '["claude-headless:shared_with_companion"]' ]
    companion_shared_hops="claude-headless"
    # a prefixed spelling of the companion's current hop is the same hop (fifteenth run, a1 C-002)
    printf 'anthropic:claude-headless' > "$companion_workdir/companion.current"; printf 'hop' > "$companion_workdir/companion.phase"
    : > "$TEST_DIR/repair-calls"
    kill -0 "$_ADV_COMPANION_PID"
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny m " ]
    [ "$(jq -c '.metadata.repair_hops_skipped' <<<"$result")" = '["claude-headless:shared_with_companion"]' ]
    # the companion is on opus: the hop stays
    printf 'opus' > "$companion_workdir/companion.current"; printf 'hop' > "$companion_workdir/companion.phase"
    : > "$TEST_DIR/repair-calls"
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny claude-headless m " ]
    [ "$(jq -c '.metadata.repair_hops_skipped' <<<"$result")" = '[]' ]
    # the rule is asked again right before EACH hop (seventeenth run, a1 C-003): the companion moves onto claude-headless
    # while tiny is running — the hop is skipped and named, never queued behind the live companion
    printf 'opus' > "$companion_workdir/companion.current"; printf 'hop' > "$companion_workdir/companion.phase"
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; [[ "$4" == "tiny" ]] && printf 'claude-headless' > "$companion_workdir/companion.current"; return 1; }
    : > "$TEST_DIR/repair-calls"
    kill -0 "$_ADV_COMPANION_PID"
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny m " ]
    [ "$(jq -c '.metadata.repair_hops_skipped' <<<"$result")" = '["claude-headless:shared_with_companion"]' ]
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; return 1; }
    # the ANSWERING voice is never skipped, however it is spelled (eighteenth run, a1 C-002): the companion on claude-headless,
    # the answering voice `anthropic:claude-headless` — the hop stays
    printf 'claude-headless' > "$companion_workdir/companion.current"; printf 'hop' > "$companion_workdir/companion.phase"
    : > "$TEST_DIR/repair-calls"
    result=$(process_findings "$(_env "$doc")" "audit" "anthropic:claude-headless" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny claude-headless " ]
    [ "$(jq -c '.metadata.repair_hops_skipped' <<<"$result")" = '[]' ]
    # the companion answered and is in its post-hop phase on claude-headless: the hop stays too
    printf 'claude-headless' > "$companion_workdir/companion.current"; printf 'post' > "$companion_workdir/companion.phase"
    : > "$TEST_DIR/repair-calls"
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny claude-headless m " ]
    kill "$_ADV_COMPANION_PID" 2>/dev/null || true; wait "$_ADV_COMPANION_PID" 2>/dev/null || true   # (never the line that fails a passing test)
    _ADV_COMPANION_PID=""; companion_shared_hops=""; companion_workdir=""
    unset ANTHROPIC_API_KEY
}

@test "NRM-24 the 200-character cap on a derived failure_mode counts codepoints, never bytes: a multibyte character at the boundary survives and the document round-trips through jq (thirteenth run, c2 C-002)" {
    desc="$(printf 'A%.0s' $(seq 1 198))$(printf '\xe2\x80\x94')x. Second sentence follows here."   # the em dash as its UTF-8 bytes, locale-independent (c2a C-004)
    doc=$(jq -nc --arg d "$desc" '{findings:[{"id":"DISS-001","severity":"LOW","category":"other","description":$d}]}')
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.findings[0].failure_mode_derived' <<<"$result")" = "true" ]
    [ "$(jq '.findings[0].failure_mode | length' <<<"$result")" = "200" ]
    [ "$(jq -r '.findings[0].failure_mode | endswith("\u2014x")' <<<"$result")" = "true" ]
    printf '%s' "$result" | jq -e 'type == "object"' >/dev/null   # valid UTF-8 JSON end to end
}

@test "NRM-25 the failure_mode derivation seam is bats-gated, as the test-mode rule requires: LOA_ADVERSARIAL_NO_FM_DERIVATION=1 without the bats marker still derives (sixteenth run, c2e C-002)" {
    f='{"id":"DISS-001","severity":"LOW","category":"other","description":"Something fails here. Second sentence."}'
    # outside bats (no marker) the knob is inert: production derives the failure_mode
    out=$( unset BATS_TEST_FILENAME BATS_VERSION; printf '%s' "$f" | LOA_ADVERSARIAL_NO_FM_DERIVATION=1 _derive_failure_mode 0 )
    [ "$(jq -r '.failure_mode_derived' <<<"$out")" = "true" ]
    [ "$(jq -r '.failure_mode' <<<"$out")" = "Something fails here." ]
    # under bats the seam holds: no failure_mode is derived, the id derivation stays production
    out=$( printf '%s' "$f" | LOA_ADVERSARIAL_NO_FM_DERIVATION=1 _derive_failure_mode 0 )
    [ "$(jq -r '.failure_mode_derived // "absent"' <<<"$out")" = "absent" ]
    [ "$(jq -r '.failure_mode // "absent"' <<<"$out")" = "absent" ]
    # …and the env var alone, or the marker alone, never disables it
    out=$( printf '%s' "$f" | _derive_failure_mode 0 )
    [ "$(jq -r '.failure_mode_derived' <<<"$out")" = "true" ]
}

@test "NRM-26 a repair hop that never ran — its CLI lock was not acquired within the wait — leaves no duration, so the next payload's estimate stays the hop's real bound (seventeenth run, a1 C-002)" {
    command -v flock >/dev/null 2>&1 || skip "flock not installed (macOS): the lock case cannot run here"
    unset ANTHROPIC_API_KEY   # keyless: the chain is claude-headless → m
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; return 1; }
    local lockdir="$XDG_RUNTIME_DIR/loa-headless-locks-$(id -u)"
    # (run 23, c2b DISS-C-002: the lock this test holds is its own — never the per-user one a live dissent holds)
    [[ -n "$TEST_DIR" && ( "$XDG_RUNTIME_DIR" == "$TEST_DIR" || "$XDG_RUNTIME_DIR" == "$TEST_DIR/"* ) ]] || { echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR is not under TEST_DIR=$TEST_DIR" >&2; return 1; }
    [ "$(_adv_cli_lock_dir)" = "$lockdir" ]
    mkdir -m 700 "$lockdir"
    exec 8>>"$lockdir/claude.lock"; flock 8   # another claude -p holds the binary's lock
    doc='{"findings":[{"title":"one","category":"other","description":"No severity."},{"title":"two","category":"other","description":"No severity."}]}'
    # the budget is exactly the hop's charge (its lock wait plus its bound — twenty-third run, a2 DISS-C-001), on the test's
    # own clock (run 23, c2b DISS-C-001): the first payload's hop is admitted at zero seconds used, waits for the lock and
    # never runs — the wait costs two (fake) seconds; the second payload finds less than the charge left, and with the fix
    # its estimate is still the charge, so the hop is pre-empted and named — a noted lock wait would have made it a few
    # seconds and queued the hop behind the lock again
    _fake_repair_clock
    eval "$(declare -f _adv_with_cli_lock | sed '1s/_adv_with_cli_lock/_adv_with_cli_lock_real/')"
    _adv_with_cli_lock() { local rc=0; _adv_with_cli_lock_real "$@" || rc=$?; [[ "$1" == "claude-headless" ]] && _tick 2; return "$rc"; }
    bound=$(_adv_cli_hop_bound claude-headless); [ "$bound" -gt 60 ]
    : > "$TEST_DIR/repair-calls"; CONF_TIMEOUT=1
    charge=$(_adv_hop_charge claude-headless 1); [ "$charge" = "$(( bound + 1 ))" ]
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS="$charge" process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
    CONF_TIMEOUT=60
    flock -u 8; exec 8>&-
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "2" ]
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "m m " ]   # the CLI hop never ran for either payload
    [ "$(grep -c "Repair hop claude-headless never ran (its CLI lock was not acquired within 1s) — no duration noted" "$TEST_DIR/repair-err")" = "1" ]
    jq -e '.metadata.repair_hops_skipped | index("claude-headless:over_budget") != null' <<<"$result" >/dev/null
}

@test "NRM-27 a repair hop that ran and failed fast leaves no duration either: only a usable reply says how long a completed attempt takes, so the next payload's estimate stays the bound (eighteenth run, a1 C-003)" {
    unset ANTHROPIC_API_KEY   # keyless: the chain is claude-headless → m
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    _fake_repair_clock   # (run 23, c2b DISS-C-001: the test's own clock — no wall-clock margin to flake under load)
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; _tick 6; return 1; }   # fails after six seconds — a transient provider error, far below the bound
    doc='{"findings":[{"title":"one","category":"other","description":"No severity."},{"title":"two","category":"other","description":"No severity."}]}'
    bound=$(_adv_cli_hop_bound claude-headless); [ "$bound" -gt 60 ]
    : > "$TEST_DIR/repair-calls"; CONF_TIMEOUT=1
    charge=$(_adv_hop_charge claude-headless 1)
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS="$(( charge + 5 ))" process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    CONF_TIMEOUT=60
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "2" ]
    # the first payload's CLI hop ran and failed after six seconds (then `m`, six more); the second payload's estimate is
    # still the charge — above what is left — so it is pre-empted and named, never admitted on a 12 s note
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "claude-headless m m " ]
    jq -e '.metadata.repair_hops_skipped | index("claude-headless:over_budget") != null' <<<"$result" >/dev/null
    # …and a usable reply IS noted: the second payload's hop is admitted on the observed duration (sixteenth run, a1 C-001) —
    # the first attempt takes six seconds, so a charge-sized estimate would no longer fit for the second payload while the
    # noted duration (doubled: 12 s) does
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; _tick 6; printf '%s' "$1" | jq -c '. + {severity: "LOW"}'; }
    : > "$TEST_DIR/repair-calls"; CONF_TIMEOUT=1
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS="$(( charge + 5 ))" process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    CONF_TIMEOUT=60
    [ "$(jq '.metadata.repaired_count' <<<"$result")" = "2" ]
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "claude-headless claude-headless " ]
    [ "$(jq -c '.metadata.repair_hops_skipped' <<<"$result")" = '[]' ]
}

@test "NRM-28 the test seams are honoured under the bats marker only: a production environment that exports _ADV_FLOCK_BIN never loses the per-binary serialisation (nineteenth run, a2 C-005)" {
    # the trailer is an indented `main "$@"` inside the BASH_SOURCE guard: the sed must match it (the old `"s/^main \"\\$@\"…"`
    # reached sed as `^main "\"` — `$@` expanded empty — and matched nothing), replace it with `:` (a comment would leave an
    # empty `then`), and the probe refuses to eval a body that still calls main (twentieth run, c2b C-001)
    # (unanchored, both: a one-line trailer `… && main "$@"` is disabled and refused too; and the script's one call is the
    # indented whole-line form every suite's setup sed disables — twenty-seventh run, c2b DISS-C-003)
    [ "$(grep -cE '(^|[^A-Za-z0-9_])main "\$@"' "$ADVERSARIAL_REVIEW")" = "1" ]
    grep -qE '^ +main "\$@"$' "$ADVERSARIAL_REVIEW"
    probe='cd "$1"; set --; PROJECT_ROOT=$PWD; source .claude/scripts/lib-content.sh; source .claude/scripts/compat-lib.sh; body=$(sed -E -e "s/(^|[^A-Za-z0-9_])main \"\\\$@\"/\\1: main disabled/g" .claude/scripts/adversarial-review.sh); if grep -Eq "(^|[^A-Za-z0-9_])main \"\\\$@\"" <<<"$body"; then echo MAIN-LIVE; exit 9; fi; eval "$body"; printf "[%s][%s][%s]" "${_ADV_FLOCK_BIN:-}" "${_ADV_PGREP_BIN:-}" "${_ADV_LOCK_WAIT_CLI:-}"'
    # (twenty-eighth run, c2b DISS-C-001: POSIX ERE via sed -E — a BRE `\|` is a GNU extension BSD sed reads as a literal bar)
    [[ "$probe" != *'\|'* ]] || { echo "the probe's sed uses GNU-only BRE alternation"; return 1; }
    # no marker: the seams are dropped at load
    out=$(env -u BATS_TEST_FILENAME -u BATS_VERSION _ADV_FLOCK_BIN=/nonexistent/flock _ADV_PGREP_BIN=/nonexistent/pgrep _ADV_LOCK_WAIT_CLI=1 bash -c "source /dev/stdin \"\$0\"" "$PROJECT_ROOT" <<<"$probe" 2>/dev/null)
    [ "$out" = "[][][]" ]
    # under the marker (this suite) they stand
    out=$(_ADV_FLOCK_BIN=/nonexistent/flock _ADV_PGREP_BIN=/nonexistent/pgrep _ADV_LOCK_WAIT_CLI=1 bash -c "source /dev/stdin \"\$0\"" "$PROJECT_ROOT" <<<"$probe" 2>/dev/null)
    [ "$out" = "[/nonexistent/flock][/nonexistent/pgrep][1]" ]
}

@test "NRM-29 the last_error summary of a line with no allowlisted token is empty and never fails, even called outside a command substitution under errexit and pipefail (twentieth run, a2 DISS-001)" {
    # (inside `$(…)` bash clears errexit, which is why the one caller never aborted; called directly, the empty grep is a
    # pipefail failure of the assignment — the summary may be empty by contract)
    ( set -euo pipefail; _adv_error_summary "plain words, nothing allowlisted" > "$TEST_DIR/summary"; echo done > "$TEST_DIR/after" )
    [ -f "$TEST_DIR/after" ]
    [ ! -s "$TEST_DIR/summary" ]
    [ "$(_adv_error_summary "boom RATE_LIMITED HTTP 429")" = "RATE_LIMITED HTTP 429" ]
}

@test "NRM-30 setup is keyless for every alias the probe recognises — the alias table, not a hand-kept list (twenty-first run, c2a C-001)" {
    local p v c
    # both legs the probe reads are pinned here, not inherited from setup (twenty-fourth run, c2b DISS-C-002): the dotenv leg is an
    # empty directory of this test's own, as NRM-21/22/23/26/27 pin it
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-nrm30"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    [ -z "$(ls -A "$LOA_ADVERSARIAL_ENV_DIR")" ]
    for p in anthropic openai google; do
        # a non-empty table: an empty or mis-keyed one would pass the loop below vacuously (twenty-second run, c2b C-001)
        [ -n "$(_adv_cred_aliases "$p")" ]
        # …that carries the provider's canonical variable (the name cheval's credential chain reads): a typo'd alias would
        # otherwise be self-consistent with the positive control below and blind to the real key
        case "$p" in anthropic) c=ANTHROPIC_API_KEY ;; openai) c=OPENAI_API_KEY ;; google) c=GOOGLE_API_KEY ;; esac
        [[ " $(_adv_cred_aliases "$p") " == *" $c "* ]]
        for v in $(_adv_cred_aliases "$p"); do
            run printenv "$v"
            [ "$status" -ne 0 ]
        done
        run _adv_cred_present "$p"
        [ "$status" -eq 1 ]
        # positive control: every alias the table lists is one the probe actually sees
        for v in $(_adv_cred_aliases "$p"); do
            export "$v=presence-only-never-printed"
            run _adv_cred_present "$p"
            unset "$v"
            [ "$status" -eq 0 ]
        done
    done
}

@test "NRM-31 a whole number too long for shell arithmetic is not a whole number: _conf_uint gives the default, said, instead of a value that wraps (twenty-third run, a1 DISS-C-002)" {
    [ "$(_conf_uint k 18446744073709551617 7 1 2>"$TEST_DIR/cu.err")" = "7" ]
    grep -q "k='18446744073709551617' is not a whole number" "$TEST_DIR/cu.err"
    [ "$(_conf_uint k 9223372036854775808 7 2>/dev/null)" = "7" ]
    [ "$(_conf_uint k 999999999999999 7 2>/dev/null)" = "999999999999999" ]   # fifteen digits still read
}

@test "NRM-32 a non-string id or failure_mode is derivable, not a repair: [id 1, id 1, failure_mode as a list] become three findings with distinct derived ids and no repair call (twenty-third run, a1 DISS-C-003)" {
    doc='{"findings":[{"id":1,"severity":"LOW","category":"other","description":"First real sentence here for the test. More.","failure_mode":"stated"},{"id":1,"severity":"LOW","category":"other","description":"Second real sentence here for the test. More.","failure_mode":"stated"},{"id":"DISS-009","severity":"LOW","category":"other","description":"Third real sentence here for the test. More.","failure_mode":["a","b"]}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq '[.findings[].id | strings] | unique | length' <<<"$result")" = "3" ]
    [ "$(jq '[.findings[] | select(.description | startswith("First") or startswith("Second")) | .id_derived] | all' <<<"$result")" = "true" ]
    [ "$(jq -r '.findings[] | select(.id == "DISS-009") | .failure_mode' <<<"$result")" = "Third real sentence here for the test." ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ]
    [ ! -e "$REPAIR_CANARY" ]
}


@test "NRM-33 a repair hop is charged once per run, not once per payload: the catalog reads behind a charge are not spent against the repair wall budget again for every rejected payload (twenty-third run, a2 DISS-C-002)" {
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    eval "$(declare -f _adv_hop_charge | sed '1s/^_adv_hop_charge/_orig_hop_charge/')"
    _adv_hop_charge() { echo "$1" >> "$TEST_DIR/charges"; _orig_hop_charge "$@"; }
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; return 1; }
    doc='{"findings":[{"title":"one","category":"other","description":"No severity."},{"title":"two","category":"other","description":"No severity."},{"title":"three","category":"other","description":"No severity."}]}'
    : > "$TEST_DIR/charges"; : > "$TEST_DIR/repair-calls"
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "3" ]
    [ "$(grep -c '' "$TEST_DIR/repair-calls")" -ge 3 ]           # the payloads did reach the hops
    [ -s "$TEST_DIR/charges" ]
    [ -z "$(sort "$TEST_DIR/charges" | uniq -d)" ]               # every hop charged once
}

@test "NRM-34 the operator's knobs are cleared BEFORE the script is sourced — a value it reads at load (the CLI hop bound) never drives the suite (twenty-third run, c2a DISS-C-001)" {
    # (setup cannot run twice here — the script declares a readonly — so the order is read from setup itself)
    local body unset_at eval_at
    body=$(declare -f setup)
    unset_at=$(grep -n 'unset .*LOA_ADVERSARIAL_CLI_HOP_TIMEOUT' <<<"$body" | head -n 1 | cut -d: -f1)
    eval_at=$(grep -n 'eval "$_src"' <<<"$body" | head -n 1 | cut -d: -f1)
    [ -n "$unset_at" ] || { echo "setup never clears LOA_ADVERSARIAL_CLI_HOP_TIMEOUT"; return 1; }
    [ -n "$eval_at" ]
    (( unset_at < eval_at )) || { echo "the knobs are cleared at line $unset_at, after the script is sourced at $eval_at"; return 1; }
    [ "$_ADV_CLI_HOP_TIMEOUT" = "610" ]
}

@test "NRM-35 no dissent-suite test name carries an inner double quote — bats emits the name into bash verbatim, so the quote splits it and what it wrapped is unquoted, a glob (twenty-third run, c2a DISS-C-002)" {
    local bad
    bad=$(grep -nE '^@test "([^"\\]|\\.)*"[^{]*"' "$PROJECT_ROOT"/tests/unit/adversarial-review*.bats "$PROJECT_ROOT"/tests/unit/verdict-derive.bats || true)
    [ -z "$bad" ] || { echo "a test name with an inner double quote: ${bad:0:300}"; return 1; }
}

@test "NRM-36 an explicit DISS-<n> id longer than fifteen digits does not drive the derived numbering: jq 1.7 keeps its digits and shell arithmetic would wrap them (twenty-fourth run, a1 DISS-C-002)" {
    doc='{"findings":[{"id":"DISS-99999999999999999999","severity":"LOW","category":"other","description":"First real sentence here for the test. More.","failure_mode":"stated"},{"severity":"LOW","category":"other","description":"Second real sentence here for the test. More.","failure_mode":"stated"},{"id":"DISS-002","severity":"LOW","category":"other","description":"Third real sentence here for the test. More.","failure_mode":"stated"}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    # the id-less finding's positional DISS-002 collides with the explicit one: it steps past max(explicit, count) = 3
    [ "$(jq -r '.findings[] | select(.description | startswith("Second")) | .id' <<<"$result")" = "DISS-004" ]
    [ "$(jq -r '.findings[] | select(.description | startswith("First")) | .id' <<<"$result")" = "DISS-99999999999999999999" ]   # a safe token, kept
}

@test "NRM-37 an explicit id in the companion's DISS-C- namespace is renumbered, never kept beside the fold's own DISS-C-NNN ids (twenty-fourth run, a1 DISS-C-003)" {
    doc='{"findings":[{"id":"DISS-C-001","severity":"LOW","category":"other","description":"First real sentence here for the test. More.","failure_mode":"stated"},{"id":"DISS-C-x","severity":"LOW","category":"other","description":"Second real sentence here for the test. More.","failure_mode":"stated"}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/pf.err")
    [ "$(jq '.findings | length' <<<"$result")" = "2" ]
    [ "$(jq '[.findings[].id | select(startswith("DISS-C-"))] | length' <<<"$result")" = "0" ]
    [ "$(jq '[.findings[].id] | unique | length' <<<"$result")" = "2" ]
    [ "$(jq '[.findings[].id_derived] | all' <<<"$result")" = "true" ]
    [ "$(grep -c "companion's DISS-C- namespace" "$TEST_DIR/pf.err")" = "2" ]
}

@test "NRM-38 the stale-directory sweep deletes only marked sprint-norm-<dead pid> directories, and setup marks its own (twenty-fifth run, c1a DISS-C-001)" {
    local a="$TEST_DIR/a2a" d1 d2
    ( : ) & d1=$!; wait "$d1"
    ( : ) & d2=$!; wait "$d2"
    mkdir -p "$a/sprint-norm-$d1" "$a/sprint-norm-$d2/x" "$a/sprint-norm-$d2-x" "$a/sprint-norm-$d2.reap-$d1"
    : > "$a/.sprint-norm-$d2.owner"
    _sweep_stale_suite_dirs "$a" sprint-norm
    [ -d "$a/sprint-norm-$d1" ]
    [ ! -e "$a/sprint-norm-$d2" ]
    [ -d "$a/sprint-norm-$d2-x" ]                     # a sibling the marker does not name stays (twenty-ninth run, c2a)
    [ ! -e "$a/sprint-norm-$d2.reap-$d1" ]
    [ ! -e "$a/.sprint-norm-$d2.owner" ]
    [ -f "$PROJECT_ROOT/grimoires/loa/a2a/.$SPRINT.owner" ]
}

@test "NRM-39 the credential scrub fails setup when the alias table is missing or empty, never a silent no-op, and all three suites share it (twenty-fifth run, c2e DISS-C-002)" {
    local s body
    run bash -c "$(declare -f _scrub_cred_aliases); unset -f _adv_cred_aliases; _scrub_cred_aliases"
    [ "$status" -ne 0 ]; [[ "$output" == *"_adv_cred_aliases"* ]]
    run bash -c "$(declare -f _scrub_cred_aliases); _adv_cred_aliases() { echo ''; }; _scrub_cred_aliases"
    [ "$status" -ne 0 ]; [[ "$output" == *"no alias"* ]]
    run env OPENAI_API_KEY=x GEMINI_API_KEY=y bash -c "$(declare -f _scrub_cred_aliases _adv_cred_aliases); _scrub_cred_aliases && echo \"[\${OPENAI_API_KEY-unset}][\${GEMINI_API_KEY-unset}]\""
    [ "$status" -eq 0 ]; [ "$output" = "[unset][unset]" ]
    # the table's contract is ONE space-separated line per provider — the production probe and the scrub both read it with one
    # `read -a`, so a line-per-alias table would break the probe itself; pinned here (twenty-sixth run, c1a/c2a/c2e DISS-C-001)
    local p; for p in anthropic openai google; do [ "$(_adv_cred_aliases "$p" | grep -c '')" = "1" ] || { echo "$p: the alias table is not one line"; return 1; }; done
    [ "$(_adv_cred_aliases google)" = "GOOGLE_API_KEY GEMINI_API_KEY" ]
    body=$(sed -n '/^_scrub_cred_aliases() {/,/^}/p' "$BATS_TEST_DIRNAME/adversarial-review-normalise.bats")
    [ -n "$body" ]
    for s in normalise companion repair-loop; do   # (the call site in all three — normalise is the body's reference copy only: twenty-seventh run, c2b DISS-C-002)
        [ "$(sed -n '/^_scrub_cred_aliases() {/,/^}/p' "$BATS_TEST_DIRNAME/adversarial-review-$s.bats")" = "$body" ]
        grep -q '^    _scrub_cred_aliases || return 1$' "$BATS_TEST_DIRNAME/adversarial-review-$s.bats"
        # (an `if`, never a mid-body `!`: bash exempts a negated pipeline from errexit, so only the last iteration counted —
        # twenty-sixth run, c2b DISS-C-001)
        # (a regex, so this file's own check line does not match itself)
        if grep -qE 'unset \$\(_adv_cred_aliases' "$BATS_TEST_DIRNAME/adversarial-review-$s.bats"; then echo "$s still unsets the aliases by hand"; return 1; fi
    done
}

@test "NRM-40 the repair pin is validated where it is read: only hop-name tokens survive, unglobbed, each dropped token said once, an all-invalid pin is ignored (twenty-sixth run, a1 DISS-C-001)" {
    local unpinned
    cd "$TEST_DIR"; : > "$TEST_DIR/glob-bait-1"; : > "$TEST_DIR/glob-bait-2"
    unpinned=$(_repair_model_chain "gpt-5.5-pro")
    LOA_ADVERSARIAL_REPAIR_MODEL='codex-headless *'
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "codex-headless" ]
    [ "$(_repair_chain_base "gpt-5.5-pro")" = "codex-headless" ]
    run _adv_repair_pin_check
    [[ "$output" == *"token 2"* ]]; [[ "$output" != *glob-bait* ]]
    LOA_ADVERSARIAL_REPAIR_MODEL='a=b codex-headless'
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "codex-headless" ]
    LOA_ADVERSARIAL_REPAIR_MODEL='  tiny   claude-headless '
    [ "$(_repair_chain_base "gpt-5.5-pro")" = "tiny claude-headless" ]
    run _adv_repair_pin_check
    [ -z "$output" ]
    LOA_ADVERSARIAL_REPAIR_MODEL='* a=b'
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "$unpinned" ]
    run _adv_repair_pin_check
    [[ "$output" == *"ignored"* ]]
    # a newline, CR or tab separates tokens like a space — never ends the pin early (twenty-seventh run, a1 DISS-C-003)
    LOA_ADVERSARIAL_REPAIR_MODEL=$'tiny\nclaude-headless'
    [ "$(_repair_chain_base "gpt-5.5-pro")" = "tiny claude-headless" ]
    LOA_ADVERSARIAL_REPAIR_MODEL=$'tiny\r\n\tclaude-headless\n* a=b'
    [ "$(_repair_chain_base "gpt-5.5-pro")" = "tiny claude-headless" ]
    run _adv_repair_pin_check
    [[ "$output" == *"token 3"* && "$output" == *"token 4"* ]]
    # a whitespace-only pin is an empty array: both helpers expand it guarded (bash < 4.4 under set -u — twenty-seventh run,
    # a1 DISS-C-004), and the check says the pin is ignored
    LOA_ADVERSARIAL_REPAIR_MODEL=$' \n\t '
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "$unpinned" ]
    run _adv_repair_pin_check
    [[ "$output" == *"ignored"* ]]
    local _f
    for _f in _adv_repair_pin _adv_repair_pin_check; do
        declare -F "$_f" >/dev/null || { echo "$_f is not defined: the guard check would be vacuous (thirty-second run, c2b DISS-C-002)"; return 1; }
        if declare -f "$_f" | grep -E '"\$\{!?_t\[@\]\}"' | grep -vqF '${_t[@]+'; then echo "$_f: unguarded _t expansion"; return 1; fi
    done
    unset LOA_ADVERSARIAL_REPAIR_MODEL
    declare -f process_findings | grep -q '_adv_repair_pin_check'
}

@test "NRM-41 a description with no sentence-ending punctuation derives its head as failure_mode, never drops the finding (twenty-sixth run, a1 DISS-001 refuted — pinned)" {
    local f='{"id":"DISS-001","severity":"LOW","category":"other","description":"A finding whose description never ends a sentence and runs on"}' out
    out=$( printf '%s' "$f" | _derive_failure_mode 0 )
    [ "$(jq -r '.failure_mode' <<<"$out")" = "A finding whose description never ends a sentence and runs on" ]
    [ "$(jq -r '.failure_mode_derived' <<<"$out")" = "true" ]
}

@test "NRM-42 the teardowns delete only real directories of their own: a symlink at an own-dir path is never followed nor fails the teardown — the sweep's rule, in every suite (twenty-seventh run, c2a DISS-C-002)" {
    local a2a="$PROJECT_ROOT/grimoires/loa/a2a" lnk tgt="$TEST_DIR/link-target" rc rc2 s
    # every delete below is under a2a/$SPRINT: the id is this suite's own shape, or nothing is deleted (thirtieth run, c2b DISS-C-001)
    [[ "$SPRINT" =~ ^sprint-norm-[0-9]+$ ]] || { echo "SPRINT '$SPRINT' is not this suite's own id"; return 1; }
    mkdir -p "$tgt" "$a2a"; : > "$tgt/keep"
    # (the link sits AT the own-dir path — the one path teardown deletes; twenty-ninth run, c2a: a sibling is never a candidate)
    if [[ -d "$a2a/$SPRINT" && ! -L "$a2a/$SPRINT" ]]; then find "$a2a/$SPRINT" -mindepth 1 -delete; rmdir "$a2a/$SPRINT"; fi
    # (thirty-third run, c2b DISS-C-004: named for the real teardown before it exists, as the sibling is below — an interrupted
    # test never leaves the link; the teardown under test runs without that name, so the leg still proves a link is never followed)
    lnk="$a2a/$SPRINT"; NORM_OWN_LINK="$lnk"; ln -s "$tgt" "$lnk"
    # (as bats runs it: errexit live — a subshell left of `||` would ignore it, so a background job is waited for)
    # (each mid-test teardown keeps the bats < 1.4 own tmp directory, which holds the link target — thirty-fourth run, c2b DISS-C-003)
    rc=0; ( set -e; NORM_OWN_TMP=""; NORM_OWN_LINK=""; teardown ) 3>&- & wait $! || rc=$?
    [ -L "$lnk" ] || { echo "the unregistered link was removed or followed"; return 1; }
    rc2=0; ( set -e; NORM_OWN_TMP=""; teardown ) 3>&- & wait $! || rc2=$?
    [ "$rc2" -eq 0 ] && [ ! -L "$lnk" ] || { echo "the registered own link outlived the teardown (rc $rc2)"; command rm -f -- "$lnk"; return 1; }
    [ -e "$tgt/keep" ] || { echo "removing the registered link followed it"; return 1; }
    NORM_OWN_LINK=""
    [ "$rc" -eq 0 ] || { echo "a symlinked own-dir path failed the teardown (rc $rc)"; return 1; }
    [ -e "$tgt/keep" ]
    # (twenty-eighth run, c2b DISS-C-002: a real own directory is removed — the path was a candidate, so the kept target is the
    # link rule's doing; twenty-ninth run, c2a: a real sibling <sprint>-x the suite never made stays, as c1a DISS-001 ruled)
    # (thirty-second run, c2b DISS-C-003: the sibling this test makes is named for the real teardown BEFORE it exists, so an
    # interrupted test never leaves it; the teardown under test runs without that name — a sibling it never made)
    NORM_SIB_DIR="$a2a/${SPRINT}-sib"
    mkdir -p "$a2a/$SPRINT/sub" "$a2a/${SPRINT}-sib/sub"; : > "$a2a/$SPRINT/sub/f"; : > "$a2a/${SPRINT}-sib/sub/f"
    rc=0; ( set -e; NORM_OWN_TMP=""; NORM_SIB_DIR=""; teardown ) 3>&- & wait $! || rc=$?
    : > "$a2a/.$SPRINT.owner"
    [ -e "$a2a/${SPRINT}-sib/sub/f" ] || { echo "teardown deleted a sibling it never made"; return 1; }
    find "$a2a/${SPRINT}-sib" -mindepth 1 -delete; rmdir "$a2a/${SPRINT}-sib"
    [ "$rc" -eq 0 ]
    [ ! -e "$a2a/$SPRINT" ] || { echo "teardown never reached its own directory: the link leg proves nothing"; return 1; }
    for s in normalise companion schema-enforced; do
        if grep -qE 'if \[\[ -d "\$d" \]\]; then find' "$BATS_TEST_DIRNAME/adversarial-review-$s.bats"; then echo "$s follows -d alone"; return 1; fi
        # (twenty-eighth run, c1a DISS-C-001: any -d-only guard — the companion's kept-workdir sweep in a world-writable TMPDIR too)
        if grep -nE -- '-d "\$d" *\]\]' "$BATS_TEST_DIRNAME/adversarial-review-$s.bats"; then echo "$s: a sweep guards with -d alone"; return 1; fi
        # (twenty-ninth run, c2a: no teardown or sweep globs a sibling of its own sprint directory)
        # (an a2a sprint path or the sweep's <prefix>-<pid>; the companion's TMPDIR adversarial-<sprint>-* are mktemp's own workdirs)
        if grep -nE 'a2a/\$\{?SPRINT\}?"-\*|\$pre-\$p"-\*' "$BATS_TEST_DIRNAME/adversarial-review-$s.bats"; then echo "$s: a sibling glob"; return 1; fi
    done
}

@test "NRM-43 a rejected payload larger than one argv string (MAX_ARG_STRLEN, 128 KiB) still gets its rejected_summary row — the summary never passes a payload on argv (twenty-eighth run, a1 DISS-C-001)" {
    local big="$TEST_DIR/big-doc.json"
    # 200 KB description, no severity: rejected; the envelope is built from a file (an --arg of the doc would itself E2BIG)
    head -c 200000 /dev/zero | tr '\0' 'x' > "$TEST_DIR/desc.txt"
    jq -nc --rawfile d "$TEST_DIR/desc.txt" '{findings: [{title: "Huge", category: "config", location: "x.sh:1", description: ("Fails. " + $d)}]}' > "$big"
    env_json=$(jq -nc --rawfile c "$big" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}')
    result=$(process_findings "$env_json" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.rejected_summary | length' <<<"$result")" = "1" ] || { echo "the rejected payload has no summary row"; return 1; }
    [ "$(jq -r '.metadata.rejected_summary[0].title' <<<"$result")" = "Huge" ]
    [ "$(jq -r '.metadata.rejected_summary[0].reason' <<<"$result")" = "missing-severity" ]
    [ "$(jq -r '.metadata.rejected_summary[0].description_head | length' <<<"$result")" = "160" ]
    # no temp dir to read from: the row is still there (index and reason only) and that is said
    result=$(_ADVERSARIAL_WORKDIR="" TMPDIR="$TEST_DIR/no-such-dir" process_findings "$env_json" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/err")
    [ "$(jq -c '.metadata.rejected_summary | map({index, reason, title})' <<<"$result")" = '[{"index":0,"reason":"missing-severity","title":null}]' ]
    grep -q 'the rejected payload at index 0 could not be summarised' "$TEST_DIR/err"
}

@test "NRM-44 the CLI hop bound reads every catalog timeout as cheval's adapter does — an exponent, a decimal, a padded or digit-grouped string — and never falls below cheval's own bound (twenty-eighth run, d DISS-C-001)" {
    command -v yq >/dev/null 2>&1 || skip "yq is required"
    python3 -c 'import yaml' 2>/dev/null || skip "PyYAML is required"
    local cat v ct rt b py i=0 n
    # (the 135 catalogs are written first and cheval's bound for all of them is read by ONE python3 — never two interpreters per
    # case: twenty-ninth run, c2b DISS-C-002)
    : > "$TEST_DIR/cats-44"
    for v in 900 900.5 9e2 '"9e2"' '" 900 "' '"1_000"' 1.2e3 '".5e3"' 0 -5 '"x"' '"nan"' '"inf"' 99999 '"1__0"'; do
        for ct in 10 30.5 '"3e1"'; do
            for rt in 120 '"7e2"' 650.25; do
                cat="$TEST_DIR/cat-44-$(( i++ )).yaml"
                printf 'providers:\n  anthropic:\n    connect_timeout: %s\n    read_timeout: %s\n    models:\n      claude-headless:\n        headless_timeout_seconds: %s\n' "$ct" "$rt" "$v" > "$cat"
                printf '%s\tv=%s ct=%s rt=%s\n' "$cat" "$v" "$ct" "$rt" >> "$TEST_DIR/cats-44"
            done
        done
    done
    (cd "$PROJECT_ROOT/.claude/adapters" && python3 -c '
import logging, sys, yaml
from loa_cheval.types import ModelConfig, ProviderConfig
from loa_cheval.providers.claude_headless_adapter import ClaudeHeadlessAdapter
logging.disable(logging.CRITICAL)
# (the adapter own bound, called — not its terms recomposed here: thirtieth run, c2b DISS-C-002)
for line in open(sys.argv[1], encoding="utf-8"):
    path = line.split("\t", 1)[0]
    p = yaml.safe_load(open(path, encoding="utf-8"))["providers"]["anthropic"]
    a = ClaudeHeadlessAdapter(ProviderConfig(name="anthropic", type="claude-headless", endpoint="", auth="",
                                             connect_timeout=p["connect_timeout"], read_timeout=p["read_timeout"]))
    print(a._compute_timeout(ModelConfig(headless_timeout_seconds=p["models"]["claude-headless"]["headless_timeout_seconds"])))' "$TEST_DIR/cats-44") > "$TEST_DIR/py-44"
    [ "$(grep -c '' "$TEST_DIR/py-44")" = "$i" ] || { echo "cheval's bounds: $(grep -c '' "$TEST_DIR/py-44") of $i"; return 1; }
    n=0
    while IFS=$'\t' read -r cat v <&5 && read -r py <&6; do
        b=$(LOA_MODEL_CONFIG="$cat" _adv_cli_hop_bound claude-headless)
        # at or above cheval's own bound, by under one second per rounded term
        awk -v b="$b" -v p="$py" 'BEGIN { exit !(b ~ /^[0-9]+$/ && p + 0 <= b + 0 && b + 0 < p + 2) }' \
            || { echo "$v: the script bounds the hop at $b, cheval at $py"; return 1; }
        n=$(( n + 1 ))
    done 5< "$TEST_DIR/cats-44" 6< "$TEST_DIR/py-44"
    [ "$n" = "$i" ]
}

@test "NRM-45 a rejected_summary row is a bounded, typed surface: a title is a capped control-free string, an explicit id stands in for one only when it is a safe token, and an anchor is always a capped string (twenty-ninth run, a1 DISS-C-002)" {
    local doc="$TEST_DIR/doc-45.json"
    jq -nc '{findings: [
      {title: ("Long\u0007\u001b[31m\n## Injected\t" + ("t" * 5000)), category: "config", location: ["x.sh", 1], description: "Fails.\n## Injected\tthere"},
      {id: ("bad id\u0007" + ("i" * 300)), category: "config", location: {file: ("f\u0001\n- x\t" + ("p" * 2000)), anchor: "a"}, description: "Fails."}
    ]}' > "$doc"
    env_json=$(jq -nc --rawfile c "$doc" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}')
    result=$(process_findings "$env_json" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.metadata.rejected_summary | length' <<<"$result")" = "2" ]
    rs=$(jq -c '.metadata.rejected_summary' <<<"$result")
    # every title and anchor is a string or null, at most 160 / 256 characters, with no control character
    jq -e 'all(.[]; ((.title | type) as $t | $t == "string" or $t == "null") and ((.anchor | type) as $a | $a == "string" or $a == "null"))' <<<"$rs" >/dev/null || { echo "$rs" | cut -c1-400; return 1; }
    jq -e 'all(.[]; ((.title // "") | length) <= 160 and ((.anchor // "") | length) <= 256)' <<<"$rs" >/dev/null || { jq -c 'map({t: (.title|length), a: (.anchor|length)})' <<<"$rs"; return 1; }
    if jq -r '.[] | .title, .anchor, .description_head' <<<"$rs" | LC_ALL=C grep -q $'[\x01-\x08\x0b-\x1f\x7f]'; then echo "a control character surfaced"; return 1; fi
    # (thirty-second run, c2b DISS-C-001: a newline or tab is a control character too — read from the values, never jq -r lines)
    jq -e 'all(.[]; [.title, .anchor, .description_head][] | strings | test("[\u0000-\u001f\u007f]") | not)' <<<"$rs" >/dev/null \
      || { echo "a newline or tab surfaced: $(jq -c 'map([.title, .anchor, .description_head] | map(strings | .[0:40]))' <<<"$rs")"; return 1; }
    [[ "$(jq -r '.[0].title' <<<"$rs")" == Long* ]]
    [ "$(jq -r '.[0].title_derived' <<<"$rs")" = "false" ]
    [ "$(jq -r '.[0].anchor' <<<"$rs")" = '["x.sh",1]' ]
    # the unsafe explicit id never surfaces: the row's title is the normaliser's id, marked derived
    if jq -r '.[1].title' <<<"$rs" | grep -q 'bad id'; then echo "the raw unsafe id surfaced"; return 1; fi
    [[ "$(jq -r '.[1].title' <<<"$rs")" =~ ^DISS-([A-Z]-)?[0-9]+$ ]] || { jq -r '.[1].title' <<<"$rs"; return 1; }
    [ "$(jq -r '.[1].title_derived' <<<"$rs")" = "true" ]
}

@test "NRM-46 no payload-sized value reaches jq on argv: a review whose findings total over one argv string (MAX_ARG_STRLEN, 128 KiB), one finding over it, and a repair of a payload over it all complete (twenty-ninth run, a1 DISS-C-003)" {
    head -c 3000 /dev/zero | tr '\0' 'x' > "$TEST_DIR/d3k.txt"
    head -c 200000 /dev/zero | tr '\0' 'y' > "$TEST_DIR/d200k.txt"
    # sixty findings of 3 KB: each is small, the set is not
    jq -nc --rawfile d "$TEST_DIR/d3k.txt" '{findings: [range(60) as $k | {title: "many \($k)", severity: "LOW", category: "other", location: "x.sh:\($k + 1)", description: ("Fails. " + $d)}]}' > "$TEST_DIR/many.json"
    env_json=$(jq -nc --rawfile c "$TEST_DIR/many.json" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}')
    result=$(process_findings "$env_json" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/err-many")
    [ "$(jq '.findings | length' <<<"$result")" = "60" ] || { echo "sixty findings over 128 KiB in all: $(jq '.findings | length' <<<"$result" 2>&1)"; tail -3 "$TEST_DIR/err-many"; return 1; }
    # one finding of 200 KB
    jq -nc --rawfile d "$TEST_DIR/d200k.txt" '{findings: [{title: "huge", severity: "LOW", category: "other", location: "x.sh:1", description: ("Fails. " + $d)}]}' > "$TEST_DIR/one.json"
    env_json=$(jq -nc --rawfile c "$TEST_DIR/one.json" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}')
    result=$(process_findings "$env_json" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/err-one")
    [ "$(jq '.findings | length' <<<"$result")" = "1" ] || { echo "one 200 KB finding: $(jq '.findings | length' <<<"$result" 2>&1)"; tail -3 "$TEST_DIR/err-one"; return 1; }
    [ "$(jq -r '.findings[0].description | length' <<<"$result")" -gt 200000 ]
    # a 200 KB payload missing its severity, repaired by the model changing that field only: the repair is accepted
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    _repair_finding_via_model() { printf '%s' "$1" | jq -c '. + {severity: "LOW"}'; }
    jq -nc --rawfile d "$TEST_DIR/d200k.txt" '{findings: [{title: "huge", category: "other", location: "x.sh:1", description: ("Fails. " + $d)}]}' > "$TEST_DIR/rep.json"
    env_json=$(jq -nc --rawfile c "$TEST_DIR/rep.json" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}')
    result=$(process_findings "$env_json" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/err-rep") || { cut -c1-300 "$TEST_DIR/err-rep" | tail -5; return 1; }
    [ "$(jq '.metadata.repaired_count' <<<"$result")" = "1" ] || { echo "a 200 KB repair: repaired_count $(jq '.metadata.repaired_count' <<<"$result" 2>&1)"; tail -3 "$TEST_DIR/err-rep"; return 1; }
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.findings[0].severity' <<<"$result")" = "LOW" ]
    # the helper reads exactly two values — one short or one over is an error, never a misread pair
    [ "$(_adv_jq_pair '[1]' '2' '$a + [$b]' -c)" = "[1,2]" ]
    if _adv_jq_pair '[1]' '' '$a' >/dev/null 2>&1; then echo "one value read as a pair"; return 1; fi
    if _adv_jq_pair '[1]' '2 3' '$a' >/dev/null 2>&1; then echo "three values read as a pair"; return 1; fi
    # and no payload-sized value is passed to jq on argv anywhere in the script: every --arg / --argjson operand is a literal,
    # or a variable or command reviewed as small — an allowlist, so a new operand fails here until it is reviewed (a payload
    # goes through _adv_jq_pair or a file; thirtieth run, c2b DISS-C-003)
    # (the lint runs over a fixture first: an unreviewed operand AFTER a reviewed one on the same line is caught — the capture is a
    # lookahead, so a match never swallows the next flag; thirty-first run, c2b DISS-C-001)
    local lint fx="$TEST_DIR/nrm46-fixture.sh"
    lint=$(cat <<'PY'
import re, sys
SMALL = set("""_ADV_RANGE_OIDS _ADV_RUN_TAG _cid _drop _enforced_err _ff_final _ff_why _repair_wall_budget _rewritten_cvq
_rewritten_vq _sc _sc_rel _sidecars_json _vq_agg _vq_err _xnew allowed_field attempts_json budget ceded chain cls comp_status
companion_answered companion_chain_csv companion_family companion_skip_reason cost cost_cents counted_as degraded demoted_sev
diff_range displaced dissenter_sev downgrade_count escalated estimated_cost_cents family fid final final_model finding_id i indep
index last_error latency m match_idx model new_sev parse_path prim primary_final primary_succeeded reject_reason rejected_count
rejected_sidecar_rel repair_attempted repair_budget_exhausted repair_metadata_json repair_skipped_no_hop repair_succeeded
repaired_count schema_enforced shared_hops sid sidecar sidecar_reject_reason since sprint_id st stability stop_reason t timestamp
tokens_in tokens_out try_model type until valid_categories valid_severities violated_clause violated_field why 1
api_exit_code _pf_rc""".split())
# ($2: _adv_refuse_json's dynamic --arg "$1" "$2" — its callers pass TMPDIR, the --diff-range value and a workdir path)
SMALL |= {"2"}
# (thirty-fourth run, c2b DISS-C-001: a positional parameter is small only in the function reviewed for it — _adv_refuse_json's
# dynamic --arg "$1" "$2", _adv_scope_json's sha — never anywhere)
SMALL -= {"1", "2"}
POS_OK = {"_adv_refuse_json": {"2"}, "_adv_scope_json": {"1"}}
CMDS = ("[[", "date ", "_adv_hop_canon ", "_adv_scope_json", "_companion_drop_reason ", "printf '%s\\n' \"${model_attempts[@]}\" |")
# (a positional operand of --args / --jsonargs: the dry run's two token counts — thirty-third run, c2b DISS-C-001)
POSITIONAL = ('"$(estimate_tokens ',)
def one_positional(p):   # exactly one "$(estimate_tokens …)" on the line, its parens balanced, nothing after it
    if not p.startswith(POSITIONAL):
        return False
    d = 0
    for i, ch in enumerate(p):
        d += ch == '('; d -= ch == ')'
        if ch == ')' and d == 0:
            return p[i + 1:].rstrip('\\').strip() == '"'
    return False
def whole(o, quoted):   # the leading $( / $(( / ${ construct is balanced and is the whole operand (thirty-fifth run, c2b DISS-C-001)
    op_, cl = ('(', ')') if o[1] == '(' else ('{', '}')
    d = 0
    for i, ch in enumerate(o):
        d += ch == op_; d -= ch == cl
        if ch == cl and d == 0:
            rest = o[i + 1:]
            return rest.startswith('"') if quoted else (rest == '' or rest[0] in ' \t;|&)')
    return False
bad = []
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
fn = ""
for n, line in enumerate(lines):
    fm = re.match(r'([A-Za-z_][A-Za-z0-9_]*)\(\) *\{', line)
    if fm:
        fn = fm.group(1)
    elif line.startswith('}'):
        fn = ""                                    # (a function's grant ends at its closing brace)
    ok = SMALL | POS_OK.get(fn, set())
    if line.lstrip().startswith('#'):
        continue                                   # a comment that names the flag
    line = re.split(r'\s{2,}# ', line, maxsplit=1)[0]   # and a trailing one
    # (thirty-third run, c2b DISS-C-001: a name is any word — a dynamic --arg "$1" "$2" is checked too — and every variable a
    # quoted operand interpolates, not the first one alone)
    for m in re.finditer(r'--(?:argjson|arg)\s+\S+\s+(?=(\S.*))', line):   # (the whole rest: a long operand's tail is read too)
        op = m.group(1)
        if op.startswith('"') and not op.startswith('"$'):
            # a literal, or one interpolating only reviewed scalars
            lit = op[1:].split('"', 1)[0]
            if '$(' in lit or '`' in lit or any(v not in ok for v in re.findall(r'\$\{?([A-Za-z_0-9]+)', lit)):
                bad.append(op)
            continue
        o = op[1:] if op.startswith('"') else op
        if not o.startswith('$'):
            bad.append(op)
        elif o.startswith('$((') or o.startswith('${#'):
            if not whole(o, op.startswith('"')):   # arithmetic, a length — the whole operand
                bad.append(op)
        elif o.startswith('$('):
            if not o[2:].lstrip().startswith(CMDS) or not whole(o, op.startswith('"')):
                bad.append(op)
        else:
            span = o.split('"', 1)[0] if op.startswith('"') else re.split(r'[\s;|&)]', o, maxsplit=1)[0]
            vs = re.findall(r'\$\{?([A-Za-z_0-9]+)', span)
            if not vs or '$(' in span or any(v not in ok for v in vs):
                bad.append(op)
    for m in re.finditer(r'(?<![\w-])--(?:json)?args(?![\w-])(.*)', line):
        rest, k = m.group(1).strip(), n
        if rest not in ('', '\\'):
            bad.append(m.group(0)); continue
        while lines[k].rstrip().endswith('\\') and k + 1 < len(lines):
            k += 1; p = lines[k].strip()
            if not one_positional(p):
                bad.append('positional: ' + p)
for b in bad: print("an unreviewed jq argv operand:", b[:80])
sys.exit(1 if bad else 0)
PY
)
    printf '%s\n' '  jq -n --arg m "$model" --arg p "$finding_json" '"'"'{m: $m, p: $p}'"'"'' > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a second operand on one line was never checked"; return 1; fi
    printf '%s\n' '  jq -n --arg m "$model" --argjson i "$i" '"'"'{m: $m, i: $i}'"'"'' > "$fx"
    python3 -c "$lint" "$fx"   # (the positive control: two reviewed operands on one line pass)
    # (thirty-third run, c2b DISS-C-001: a second variable in one quoted operand, a dynamic name, an unreviewed positional)
    printf '%s\n' '  jq -n --arg m "$model$finding_json" '"'"'{m: $m}'"'"'' > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a quoted operand's second variable was never checked"; return 1; fi
    printf '%s\n' '  jq -n --arg m "${model}-${finding_json}" '"'"'{m: $m}'"'"'' > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a braced second variable was never checked"; return 1; fi
    printf '%s\n' '  kv+=(--arg "$name" "$finding_json")' > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a dynamic name's operand was never checked"; return 1; fi
    printf '%s\n' '  jq -n '"'"'$ARGS.positional'"'"' --args \' '    "$finding_json"' > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a --args positional was never checked"; return 1; fi
    printf '%s\n' '  jq -n '"'"'$ARGS.positional'"'"' --jsonargs "$finding_json"' > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a same-line --jsonargs positional was never checked"; return 1; fi
    printf '%s\n' '  jq -n --arg m "$model-$i" '"'"'{m: $m}'"'"' --jsonargs \' '    "$(estimate_tokens "$x")"' > "$fx"
    python3 -c "$lint" "$fx"   # (the positive control: reviewed variables and a reviewed positional pass)
    # (thirty-fourth run, c2b DISS-C-001: a command substitution inside a quoted literal; $1 outside the two functions reviewed for
    # it; a second operand on a positional line; a variable past the eighty-first character of a quoted operand)
    printf '%s\n' '  jq -n --arg x "prefix$(cat "$payload_file")" '"'"'{x: $x}'"'"'' > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a command substitution in a quoted literal was never checked"; return 1; fi
    printf '%s\n' '_some_helper() {' '  jq -n --argjson f "$1" '"'"'{f: $f}'"'"'' > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a positional parameter outside its reviewed functions was never checked"; return 1; fi
    printf '%s\n' '  jq -n '"'"'$ARGS.positional'"'"' --jsonargs \' '    "$(estimate_tokens "$x")" "$finding_json"' > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a positional line's second operand was never checked"; return 1; fi
    printf '%s\n' "  jq -n --arg m \"\$model-$(printf 'a%.0s' $(seq 1 90))\$finding_json\" '{m: \$m}'" > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a variable past the eighty-first character was never checked"; return 1; fi
    printf '%s\n' '_adv_refuse_json() {' '  local -a kv=(); while (( $# >= 2 )); do kv+=(--arg "$1" "$2"); shift 2; done' '}' \
                   '_adv_scope_json() {' '  jq -nc --arg sha "${1:-}" '"'"'{s: $sha}'"'"'' '}' > "$fx"
    python3 -c "$lint" "$fx"   # (the positive control: $1 / $2 in the two functions reviewed for them)
    # (thirty-fifth run, c2b DISS-C-001: an operand that only BEGINS with an arithmetic, a length or a reviewed command — the rest
    # of it is read too; and a function's grant ends at its closing brace)
    for x in '"$(date +%s)-$finding_json"' '"$(( n ))$finding_json"' '"${#a}$finding_json"' '$(date +%s)$finding_json'; do
        printf '  jq -n --arg x %s %s\n' "$x" "'{x: \$x}'" > "$fx"
        if python3 -c "$lint" "$fx"; then echo "the tail of $x was never checked"; return 1; fi
    done
    printf '%s\n' '_adv_scope_json() {' '  :' '}' '  jq -n --arg s "$1" '"'"'{s: $s}'"'"'' > "$fx"
    if python3 -c "$lint" "$fx"; then echo "a function's positional grant leaked past its closing brace"; return 1; fi
    printf '%s\n' '  jq -n --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson n "$(( a + 1 ))" --argjson l "${#arr[@]}" '"'"'{}'"'"'' > "$fx"
    python3 -c "$lint" "$fx"   # (the positive control: a whole-operand construct passes)
    python3 -c "$lint" "$ADVERSARIAL_REVIEW"
}

@test "NRM-47 a repair hop whose CLI lock wait expired never asked a model: no repair slot is spent and the payload is repair_skipped_no_hop, the hop named <hop>:lock_wait once (thirty-first run, a1 DISS-C-001)" {
    command -v flock >/dev/null 2>&1 || skip "flock not installed (macOS): the lock case cannot run here"
    unset ANTHROPIC_API_KEY
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    export LOA_ADVERSARIAL_REPAIR_MODEL="claude-headless"   # the pin is the whole chain: one CLI hop
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; return 1; }
    local lockdir="$XDG_RUNTIME_DIR/loa-headless-locks-$(id -u)"
    [[ -n "$TEST_DIR" && ( "$XDG_RUNTIME_DIR" == "$TEST_DIR" || "$XDG_RUNTIME_DIR" == "$TEST_DIR/"* ) ]] || { echo "XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR is not under TEST_DIR=$TEST_DIR" >&2; return 1; }
    [ "$(_adv_cli_lock_dir)" = "$lockdir" ]
    mkdir -m 700 "$lockdir"
    exec 8>>"$lockdir/claude.lock"; flock 8   # another claude -p holds the binary's lock for the whole review
    # six payloads, one more than ADV_REPAIR_MAX_PER_RUN: a lock wait that spent a slot would leave the sixth budget-exhausted
    local doc i f=""
    for i in 1 2 3 4 5 6; do f+="${f:+,}{\"title\":\"t$i\",\"category\":\"other\",\"description\":\"No severity.\"}"; done
    doc="{\"findings\":[$f]}"
    : > "$TEST_DIR/repair-calls"; CONF_TIMEOUT=1
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=100000 process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
    CONF_TIMEOUT=60
    flock -u 8; exec 8>&-
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "6" ]
    [ ! -s "$TEST_DIR/repair-calls" ]   # no model was ever asked
    [ "$(jq '.metadata.repair_budget_exhausted' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.repair_skipped_no_hop' <<<"$result")" = "6" ]
    [ "$(jq -c '[.metadata.repair_hops_skipped[] | select(. == "claude-headless:lock_wait")] | length' <<<"$result")" = "1" ]
    [ "$(grep -c "Repair hop claude-headless never ran" "$TEST_DIR/repair-err")" = "6" ]
}

@test "NRM-48 a rejected_summary row's severity is a capped control-free string like every other row field — an invalid severity is exactly the model's free text (thirty-first run, a2 DISS-C-002)" {
    local doc="$TEST_DIR/doc-48.json"
    jq -nc '{findings: [
      {severity: ("HIGH\t\n## Injected\u0007" + ("s" * 5000)), title: "t1", category: "config", description: "Fails."},
      {severity: {nested: ("o" * 500)}, title: "t2", category: "config", description: "Fails."},
      {title: "t3", category: "config", description: "Fails."},
      {severity: "HIGH", title: "t4", category: ("cfg\t## Injected\u0007" + ("c" * 5000)), description: "Fails."}
    ]}' > "$doc"
    env_json=$(jq -nc --rawfile c "$doc" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}')
    result=$(process_findings "$env_json" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.metadata.rejected_summary | length' <<<"$result")" = "4" ]
    rs=$(jq -c '.metadata.rejected_summary' <<<"$result")
    # the reject reason quotes the bad value too: capped and control-free in the row and in the log line
    jq -e 'all(.[]; (.reason | type) == "string" and (.reason | length) <= 80)' <<<"$rs" >/dev/null || { jq -c 'map(.reason | length)' <<<"$rs"; return 1; }
    # (thirty-third run, c2b DISS-C-002: every C0 control, a tab too, checked on the jq side — a grep class skipped \t and \n)
    jq -e 'all(.[]; .reason | test("[\u0000-\u001f\u007f]") | not)' <<<"$rs" >/dev/null || { echo "a control character surfaced in a reason"; return 1; }
    [ "$(jq -r '.[] | .reason' <<<"$rs" | wc -l | tr -d ' ')" = "4" ]
    [[ "$(jq -r '.[3].reason' <<<"$rs")" == "category-not-in-enum (got: cfg ## injected "* ]]   # (the normaliser lower-cases a category)
    jq -e 'all(.[]; (.severity | type) as $t | $t == "string" or $t == "null")' <<<"$rs" >/dev/null || { echo "$rs" | cut -c1-400; return 1; }
    jq -e 'all(.[]; ((.severity // "") | length) <= 32)' <<<"$rs" >/dev/null || { jq -c 'map(.severity | length)' <<<"$rs"; return 1; }
    jq -e 'all(.[]; (.severity // "") | test("[\u0000-\u001f\u007f]") | not)' <<<"$rs" >/dev/null || { echo "a control character surfaced"; return 1; }
    [ "$(jq -r '.[] | .severity // empty' <<<"$rs" | wc -l | tr -d ' ')" = "3" ]   # one line each: no newline survived
    [[ "$(jq -r '.[0].severity' <<<"$rs")" == "HIGH  ## INJECTED"* ]]   # (the normaliser upper-cases a string severity)
    [[ "$(jq -r '.[1].severity' <<<"$rs")" == '{"nested":'* ]]
    [ "$(jq -r '.[2].severity' <<<"$rs")" = "null" ]
}

@test "NRM-49 a long model-written description costs linear time: the non-blank checks, the derived failure_mode and the rejected_summary row never run a whole-string gsub (thirty-second run, a1 DISS-C-001: 54 s for one 300 KB description on jq 1.7)" {
    local doc="$TEST_DIR/doc-49.json"
    # ~120 KB, 40,000-run descriptions: one valid, one derivable (no failure_mode), one rejected (no severity) whose description is
    # newlines — the control-character clean's matches — and one rejected for a 100,000-newline severity (the quoted excerpt)
    jq -nc '("ab " * 40000) as $d | {findings: [
      {id: "DISS-001", severity: "ADVISORY", category: "other", description: $d, failure_mode: ("fm " * 40000), anchor: "x.sh:1"},
      {id: "DISS-002", severity: "ADVISORY", category: "other", description: ("Short head. " + $d), anchor: "x.sh:1"},
      {title: "t3", category: "other", description: ("ab\n" * 40000)},
      {id: "DISS-004", severity: ("x\n" * 100000), category: "other", description: "d", failure_mode: "f", anchor: "x.sh:1"}
    ]}' > "$doc"
    env_json=$(jq -nc --rawfile c "$doc" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}')
    local t0=$SECONDS
    result=$(process_findings "$env_json" "review" "m" "$SPRINT" "0" "x.sh")
    local took=$(( SECONDS - t0 ))
    [ "$took" -lt 15 ] || { echo "process_findings took ${took}s over four long payloads"; return 1; }
    [ "$(jq '.findings | length' <<<"$result")" = "2" ]
    [ "$(jq -r '.findings[] | select(.id == "DISS-002") | .failure_mode' <<<"$result")" = "Short head. ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab ab" ] \
      || { jq -r '.findings[] | select(.id == "DISS-002") | .failure_mode' <<<"$result" | cut -c1-240; return 1; }
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "2" ]
    [ "$(jq -r '.metadata.rejected_summary[0].description_head | length' <<<"$result")" = "160" ]
    [[ "$(jq -r '.metadata.rejected_summary[1].reason' <<<"$result")" == "severity-not-in-enum (got: X X X X "* ]] || { jq -c '.metadata.rejected_summary[1]' <<<"$result" | cut -c1-300; return 1; }
    # the rewritten predicates keep their meaning: blank (any whitespace, incl. a lone newline) is empty, one visible char is not
    run validate_finding '{"id":"a","severity":"ADVISORY","category":"other","description":" \n\t ","failure_mode":"x"}' review
    [ "$status" -ne 0 ]
    run validate_finding '{"id":"a","severity":"ADVISORY","category":"other","description":" x ","failure_mode":"\n"}' review
    [ "$status" -ne 0 ]
    run validate_finding '{"id":"a","severity":"ADVISORY","category":"other","description":" x ","failure_mode":" y"}' review
    [ "$status" -eq 0 ]
}

@test "NRM-50 a marker records its owner's start token, so a killed run whose pid was recycled is still swept — a live pid with another start is not the owner; a matching or unknown token stays live (thirty-second run, c2a DISS-C-001)" {
    local a="$TEST_DIR/a2a" p tok
    # setup's own marker names this test's process and its start
    tok=$(_sweep_start "$$")
    [ -n "$tok" ] || skip "no start token on this host"
    [ "$(head -n1 "$PROJECT_ROOT/grimoires/loa/a2a/.$SPRINT.owner")" = "$tok" ]   # (line 2 is where it was written — thirty-fourth run, c2a)
    sleep 30 3>&- & p=$!; NORM_HOLDER_PIDS+=("$p")
    mkdir -p "$a/sprint-norm-$p/x"
    # the pid is alive but its start is not the marker's: the owner died and the pid was reused
    printf 't1\n' > "$a/.sprint-norm-$p.owner"
    _sweep_stale_suite_dirs "$a" sprint-norm
    [ ! -e "$a/sprint-norm-$p" ] || { echo "a recycled pid kept the dead owner's directory"; return 1; }
    [ ! -e "$a/.sprint-norm-$p.owner" ]
    # the owner itself (its own token), and a marker with no token (an older suite's), stay live
    mkdir -p "$a/sprint-norm-$p/x"
    _sweep_start "$p" > "$a/.sprint-norm-$p.owner"
    _sweep_stale_suite_dirs "$a" sprint-norm
    [ -d "$a/sprint-norm-$p/x" ]
    : > "$a/.sprint-norm-$p.owner"
    _sweep_stale_suite_dirs "$a" sprint-norm
    [ -d "$a/sprint-norm-$p/x" ]
}

@test "NRM-51 a sibling directory NRM-42 makes is removed by the real teardown when the test stops before its own cleanup — exactly that path, a real directory, this suite's shape (thirty-second run, c2b DISS-C-003)" {
    local a2a="$PROJECT_ROOT/grimoires/loa/a2a"
    [[ "$SPRINT" =~ ^sprint-norm-[0-9]+$ ]] || { echo "SPRINT '$SPRINT' is not this suite's own id"; return 1; }
    NORM_SIB_DIR="$a2a/${SPRINT}-sib"; mkdir -p "$NORM_SIB_DIR/sub"; : > "$NORM_SIB_DIR/sub/f"
    rc=0; ( set -e; NORM_OWN_TMP=""; teardown ) 3>&- & wait $! || rc=$?
    [ "$rc" -eq 0 ]
    [ ! -e "$NORM_SIB_DIR" ] || { echo "the registered sibling was left behind"; find "$NORM_SIB_DIR" -mindepth 1 -delete; rmdir "$NORM_SIB_DIR"; return 1; }
    # a link or a path of another shape is never followed nor deleted
    mkdir -p "$TEST_DIR/tgt"; : > "$TEST_DIR/tgt/keep"; ln -s "$TEST_DIR/tgt" "$a2a/${SPRINT}-sib"
    NORM_SIB_DIR="$a2a/${SPRINT}-sib"; rc=0; ( set -e; NORM_OWN_TMP=""; teardown ) 3>&- & wait $! || rc=$?
    command rm -f -- "$a2a/${SPRINT}-sib"
    [ "$rc" -eq 0 ]; [ -e "$TEST_DIR/tgt/keep" ]
    mkdir -p "$TEST_DIR/other"; : > "$TEST_DIR/other/keep"
    NORM_SIB_DIR="$TEST_DIR/other"; rc=0; ( set -e; NORM_OWN_TMP=""; teardown ) 3>&- & wait $! || rc=$?
    [ "$rc" -eq 0 ]; [ -e "$TEST_DIR/other/keep" ]
    NORM_SIB_DIR=""
    : > "$a2a/.$SPRINT.owner"
}

@test "NRM-52 a rejected_summary row and its reason quote carry no C1 control, Unicode line separator, bidi or zero-width format character — a row renders as the bytes it holds; other non-ASCII text stays (thirty-third run, a2 DISS-C-003)" {
    local doc="$TEST_DIR/doc-52.json"
    jq -nc '{findings: [
      {severity: "HIGH", title: "café \u202egnp.exe\u202c ok\u200b", category: "nope", anchor: "a.sh#f\u2066x\u2069\u2028y", description: "Fails\u0085 here\ufeff."},
      {severity: "HIGH", title: "t2", category: "cfg\u202e\u2029x", description: "Fails."},
      {severity: "HI\u200fGH", title: "t3", category: "config", description: "Fails."}
    ]}' > "$doc"
    env_json=$(jq -nc --rawfile c "$doc" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}')
    result=$(process_findings "$env_json" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.metadata.rejected_summary | length' <<<"$result")" = "3" ] || { echo "$result" | cut -c1-600; return 1; }
    rs=$(jq -c '.metadata.rejected_summary' <<<"$result")
    jq -e '[.. | strings | select(test("[\u0080-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u2064\u2066-\u2069\ufeff]"))] | length == 0' <<<"$rs" >/dev/null \
      || { jq -c '[.. | strings | select(test("[\u0080-\u009f\u200b-\u200f\u2028-\u202e\u2060-\u2064\u2066-\u2069\ufeff]"))]' <<<"$rs"; return 1; }
    [[ "$(jq -r '.[0].title' <<<"$rs")" == "café  gnp.exe  ok"* ]] || { jq -r '.[0].title' <<<"$rs"; return 1; }
    [[ "$(jq -r '.[1].reason' <<<"$rs")" == "category-not-in-enum (got: cfg  x"* ]] || { jq -r '.[1].reason' <<<"$rs"; return 1; }
}

@test "NRM-53 the failure_mode derivation window starts at the description's first visible character — a long whitespace prefix still derives its first sentence in linear time, and a dissenter's own *_derived markers are dropped before the normaliser decides (thirty-fourth run, a1 DISS-C-001)" {
    local doc="$TEST_DIR/doc-53.json"
    # DISS-001: 5,000 leading spaces (the old 4,000-character window saw only whitespace and derived " ");
    # DISS-002: 300,000 leading whitespace characters, mixed (linear: one anchored strip, never a whole-string gsub);
    # DISS-003: a dissenter that claims its own failure_mode and id were derived
    jq -nc '{findings: [
      {id: "DISS-001", severity: "ADVISORY", category: "other", description: ((" " * 5000) + "The token is dropped on retry. More detail."), anchor: "x.sh:1"},
      {id: "DISS-002", severity: "ADVISORY", category: "other", description: ((" \n\t" * 100000) + "The lock is never released. Then more."), anchor: "x.sh:1"},
      {id: "DISS-003", severity: "ADVISORY", category: "other", description: "d", failure_mode: "stated by the dissenter", anchor: "x.sh:1",
       failure_mode_derived: true, id_derived: true}
    ]}' > "$doc"
    env_json=$(jq -nc --rawfile c "$doc" '{content: $c, tokens_input: 10, tokens_output: 5, cost_usd: 0, latency_ms: 1, schema_enforced: false}')
    local t0=$SECONDS
    result=$(process_findings "$env_json" "review" "m" "$SPRINT" "0" "x.sh")
    local took=$(( SECONDS - t0 ))
    [ "$took" -lt 15 ] || { echo "process_findings took ${took}s over a 300,000-character whitespace prefix"; return 1; }
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ] || { jq -c '.metadata.rejected_summary' <<<"$result" | cut -c1-300; return 1; }
    [ "$(jq '.metadata.repaired_count // 0' <<<"$result")" = "0" ] || { echo "a repair was spent on a derivable payload"; return 1; }
    [ "$(jq -r '.findings[] | select(.id == "DISS-001") | .failure_mode' <<<"$result")" = "The token is dropped on retry." ] \
      || { jq -c '.findings[] | select(.id == "DISS-001") | .failure_mode' <<<"$result"; return 1; }
    [ "$(jq -r '.findings[] | select(.id == "DISS-002") | .failure_mode' <<<"$result")" = "The lock is never released." ] \
      || { jq -c '.findings[] | select(.id == "DISS-002") | .failure_mode' <<<"$result"; return 1; }
    [ "$(jq -r '.findings[] | select(.id == "DISS-001") | .failure_mode_derived' <<<"$result")" = "true" ]
    # the markers are the normaliser's provenance: a dissenter that claims them claims nothing
    [ "$(jq -c '.findings[] | select(.id == "DISS-003") | [.failure_mode, .failure_mode_derived, .id_derived]' <<<"$result")" = '["stated by the dissenter",null,null]' ] \
      || { jq -c '.findings[] | select(.id == "DISS-003")' <<<"$result"; return 1; }
}

@test "NRM-54 setup never inherits a directory standing at this test's sprint path: marked → emptied and removed; unmarked → refused and left (thirty-fourth run, c1a DISS-C-001)" {
    local a="$PROJECT_ROOT/grimoires/loa/a2a" d m
    d="$a/$SPRINT"; m="$a/.$SPRINT.owner"
    mkdir -p "$d"; printf 'stale' > "$d/adversarial-rejected-audit.jsonl"
    _claim_sprint_dir "$d"
    [ ! -e "$d" ] || { echo "a marked leftover was inherited: $(ls -A "$d")"; return 1; }
    command rm -f -- "$m"; mkdir -p "$d"; printf 'theirs' > "$d/keep"
    run _claim_sprint_dir "$d"
    [ "$status" -ne 0 ] && [[ "$output" == *"setup: $d stands and is not this suite's"* ]] || { echo "unmarked: status $status, $output"; return 1; }
    [ "$(cat "$d/keep")" = "theirs" ]
    sed -n '/^setup() {/,/^}/p' "$BATS_TEST_FILENAME" | grep -q '_claim_sprint_dir "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT" || return 1'
    _sweep_start "$$" > "$m"   # (ours again: teardown removes it with the directory)
}

@test "NRM-55 the stale sweep never deletes a live run's directory it cannot see: a kill -0 refused with EPERM is a live owner (hidepid), and a marker written on another host or pid namespace is never judged here; one of ours, dead, is still removed (thirty-fourth run, c2a DISS-C-001)" {
    # (thirty-fifth run, c2b DISS-C-003: the sweep legs run in this test's own a2a — never fixtures in the real one, which no
    # teardown registers; setup's own marker is still checked where setup writes it)
    local a="$TEST_DIR/a2a" dead
    mkdir -p "$a"
    dead=$(( $(cat /proc/sys/kernel/pid_max 2>/dev/null || echo 4194304) + 1 ))
    if kill -0 "$dead" 2>/dev/null; then echo "pid $dead is live"; return 1; fi
    # EPERM: the pid is invisible to ps and /proc, and kill -0 says "not permitted" — alive
    ( kill() { echo "bash: kill: ($2) - Operation not permitted" >&2; return 1; }; _sweep_alive "$dead" ) || { echo "an EPERM owner was judged dead"; return 1; }
    ! _sweep_alive "$dead" || { echo "pid $dead judged alive"; return 1; }
    # a marker that records where it was written: elsewhere → left; here → swept
    mkdir -p "$a/sprint-norm-$dead"; printf 't1\nwhere other-host pid:[1]\n' > "$a/.sprint-norm-$dead.owner"
    _sweep_stale_suite_dirs "$a" sprint-norm
    [ -d "$a/sprint-norm-$dead" ] || { echo "another namespace's directory was deleted"; return 1; }
    printf 't1\n%s\n' "$(_sweep_where)" > "$a/.sprint-norm-$dead.owner"
    _sweep_stale_suite_dirs "$a" sprint-norm
    [ ! -e "$a/sprint-norm-$dead" ] && [ ! -e "$a/.sprint-norm-$dead.owner" ] || { echo "our own dead run's directory was kept"; return 1; }
    # setup writes the where line
    [ "$(sed -n 2p "$PROJECT_ROOT/grimoires/loa/a2a/.$SPRINT.owner")" = "$(_sweep_where)" ] && [[ "$(_sweep_where)" == "where "* ]]
}
