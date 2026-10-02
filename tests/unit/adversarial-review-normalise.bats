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

setup() {
    # the sprint id comes FIRST: teardown runs on any setup failure, and a delete target derived from
    # an unset id would be the a2a root (fourth run, chunk c C-001)
    SPRINT="sprint-norm-$$"
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
    export PROJECT_ROOT
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    FIXTURES="$PROJECT_ROOT/tests/fixtures/dissent-rejected"
    TEST_DIR="${BATS_TEST_TMPDIR:-}"; NORM_OWN_TMP=""
    if [[ -z "$TEST_DIR" ]]; then TEST_DIR="$(mktemp -d)"; NORM_OWN_TMP="$TEST_DIR"; fi   # bats < 1.4: our own directory, removed in teardown (sixteenth run, c2a C-003)
    # the two ledgers the script appends to are the TEST's, by construction — never a shared /tmp file no suite truncates
    export LOA_MODELINV_LOG_PATH="$TEST_DIR/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="$TEST_DIR/cost-ledger.jsonl"
    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    # the trailer is an indented `main "$@"` in the BASH_SOURCE guard: `^main` matched nothing; `:` keeps the `then` non-empty (twentieth run, c2b C-001)
    eval "$(sed 's/^\( *\)main "\$@"$/\1: main disabled for testing/' "$ADVERSARIAL_REVIEW")"
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT
    CONF_ENABLED="true"; CONF_MODEL="gpt-5.5-pro"; CONF_TIMEOUT=60; CONF_BUDGET_CENTS=150
    CONF_ESCALATION_ENABLED="true"; CONF_SECONDARY_BUDGET=12000; CONF_MAX_FILE_LINES=500
    CONF_MAX_FILE_BYTES=51200; CONF_SECRET_SCANNING="true"; CONF_SECRET_ALLOWLIST=()
    LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=""
    REPAIR_CANARY="$TEST_DIR/repair-called-$$"
    NORM_HOLDER_PIDS=()   # stand-in processes a test spawns (NRM-23's companion timer); teardown ends them (sixteenth run, c2b C-003)
    # every test gets its own CLI lock directory, as the companion suite does (round-1q dry run: a repair through the
    # claude-headless hop queued 60 s behind a LIVE dissent's claude.lock in the per-user directory and failed as a timeout —
    # the KF-037 contention class, in a unit test)
    export XDG_RUNTIME_DIR="$TEST_DIR"
    # the normaliser must make the repair unnecessary: a stub that records the call and fails
    _repair_finding_via_model() { : > "$REPAIR_CANARY"; return 1; }
    # every credential alias the probe recognises, from the script's own table (twenty-first run, c2a C-001; as the companion suite)
    unset $(_adv_cred_aliases anthropic) $(_adv_cred_aliases openai) $(_adv_cred_aliases google) LOA_ADVERSARIAL_REPAIR_MODEL
    unset LOA_ADVERSARIAL_RUN_TAG _ADV_SIDECAR_TAG LOA_ADVERSARIAL_ENV_DIR LOA_ADVERSARIAL_NO_FM_DERIVATION   # (seventh run, c2 C-005)
    # …and every other knob the script reads (thirteenth run, c2 C-004): hermetic like the companion suite; the dotenv
    # seam points at an empty directory unless a case says otherwise
    unset LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS _ADV_REPAIR_DEAD_HOPS _ADV_REPAIR_RC_FILE LOA_MODEL_CONFIG LOA_ADVERSARIAL_COMPANION_WAIT_SECONDS
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-default"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    export LOA_ADVERSARIAL_CLI_PROBE=both   # both CLI binaries "installed" unless a case says otherwise (the repair chain gates on it)
}
teardown() {
    local d p
    for p in ${NORM_HOLDER_PIDS[@]+"${NORM_HOLDER_PIDS[@]}"}; do kill "$p" 2>/dev/null || true; done
    if [[ -n "${NORM_OWN_TMP:-}" && -d "$NORM_OWN_TMP" && "$(basename "$NORM_OWN_TMP")" == tmp.* ]]; then find "$NORM_OWN_TMP" -mindepth 1 -delete; rmdir "$NORM_OWN_TMP"; fi
    # a directory an earlier, killed run of this suite left behind (its pid is dead) never accumulates (twenty-second run, c2a C-002)
    for d in "$PROJECT_ROOT"/grimoires/loa/a2a/sprint-norm-[0-9]*; do
        [[ "$d" == */a2a/sprint-norm-[0-9]* && -d "$d" && ! -L "$d" ]] || continue
        p=${d##*/sprint-norm-}; p=${p%%-*}
        [[ "$p" =~ ^[0-9]+$ ]] || continue
        if ! kill -0 "$p" 2>/dev/null; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi
    done
    [[ -n "${SPRINT:-}" && "$SPRINT" == sprint-norm-* ]] || return 0
    for d in "$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}" "$PROJECT_ROOT/grimoires/loa/a2a/${SPRINT}"-*; do
        [[ "$d" == */a2a/sprint-norm-* ]] || continue
        if [[ -d "$d" ]]; then find "$d" -mindepth 1 -delete; rmdir "$d"; fi
    done
}
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
    [ "$(jq -r '.metadata.rejected_summary[0].severity' <<<"$result")" = "null" ]
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
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-x"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    printf 'ANTHROPIC_API_KEY="dotenv-secret-value-xyz-987"\n' > "$LOA_ADVERSARIAL_ENV_DIR/.env.local"
    run bash -xc "$(declare -f _adv_cred_aliases _adv_cred_present); PROJECT_ROOT='$PROJECT_ROOT'; LOA_ADVERSARIAL_ENV_DIR='$LOA_ADVERSARIAL_ENV_DIR'; BATS_TEST_FILENAME=x; _adv_cred_present anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" != *"dotenv-secret-value-xyz-987"* ]]
    # the exported-variable path too (seventh run, c2 C-003): the probe never expands the value
    # (the value enters through the environment, not the traced script — an `export` line would trace itself)
    # …hermetic like the first probe (twentieth run, c2a C-001): the dotenv seam points at an EMPTY directory, so only the
    # environment branch can answer — the inherited env-x above (or a host .env.local) would otherwise say "present" for it
    mkdir -p "$TEST_DIR/env-empty"
    ANTHROPIC_API_KEY=env-secret-value-123 run bash -xc "$(declare -f _adv_cred_aliases _adv_cred_present); PROJECT_ROOT='$PROJECT_ROOT'; LOA_ADVERSARIAL_ENV_DIR='$TEST_DIR/env-empty'; BATS_TEST_FILENAME=x; _adv_cred_present anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" != *"env-secret-value-123"* ]]
    # the inverse under the same prelude: no variable, no dotenv — absent, so the branch is proven both ways
    run env $(printf -- '-u %s ' $(_adv_cred_aliases anthropic)) bash -xc "$(declare -f _adv_cred_aliases _adv_cred_present); PROJECT_ROOT='$PROJECT_ROOT'; LOA_ADVERSARIAL_ENV_DIR='$TEST_DIR/env-empty'; BATS_TEST_FILENAME=x; _adv_cred_present anthropic"
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
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
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
    [ "$(grep -c 'loa-headless-locks' "$ADVERSARIAL_REVIEW")" = "1" ]   # one resolver: no second path can bypass the override
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.metadata.repaired_count' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ]
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-models")" = "tiny claude-headless " ]   # the answering voice (m) would be third; never reached
    # the CLI hop's lock was taken under this test's XDG_RUNTIME_DIR, never in the per-user directory a live dissent holds
    if command -v flock >/dev/null 2>&1; then
        [ -e "$TEST_DIR/loa-headless-locks-$uid/claude.lock" ]
    fi
    [[ "$result" != *"sk-ant-test-presence-only-never-printed"* ]]
}

@test "NRM-11 a non-object element in findings[] still lands in rejected_summary (raw value as description_head) and in the sidecar (fifth run C-006)" {
    doc='{"findings":["just a string",{"id":"DISS-002","severity":"MEDIUM","category":"config","description":"Fine.","failure_mode":"stated"}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.rejected_summary | length' <<<"$result")" = "1" ]
    [ "$(jq -r '.metadata.rejected_summary[0].description_head' <<<"$result")" = '"just a string"' ]
    [ "$(jq -r '.metadata.rejected_summary[0].severity' <<<"$result")" = "null" ]
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

@test "NRM-15 the collision guard reads the highest explicit id, not the finding count: a derived id colliding with an explicit one takes max(explicit) + 1 (ninth run, a1 C-002 — the jq "?" that zeroed it)" {
    doc='{"findings":[{"id":"DISS-009","severity":"MEDIUM","category":"config","description":"Nine.","failure_mode":"s"},{"severity":"LOW","category":"other","description":"No id, positional DISS-002 collides."},{"id":"DISS-002","severity":"LOW","category":"other","description":"Two.","failure_mode":"s"}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq -r '[.findings[].id] | join(",")' <<<"$result")" = "DISS-009,DISS-010,DISS-002" ]
}

@test "NRM-16 credential presence resolves per alias with override precedence: an empty GOOGLE_API_KEY never hides a GEMINI_API_KEY assigned in the same or a lower source; every alias assigned empty at its deciding source disables (ninth run a1 C-005; tenth run c2 C-001)" {
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-g"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    _probe() {  # <env assignments…> — runs the probe in a shell with only the named Google variables (the operator's shell may export one)
        bash -c "unset GOOGLE_API_KEY GEMINI_API_KEY; $1; $(declare -f _adv_cred_aliases _adv_cred_present); PROJECT_ROOT='$PROJECT_ROOT'; LOA_ADVERSARIAL_ENV_DIR='$LOA_ADVERSARIAL_ENV_DIR'; BATS_TEST_FILENAME=x; _adv_cred_present google"
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
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; sleep 3; return 1; }
    doc='{"findings":[{"title":"one","category":"other","description":"No severity."},{"title":"two","category":"other","description":"No severity."},{"title":"three","category":"other","description":"No severity."}]}'
    # a 4 s budget with a 1 s call timeout and 2 s hops: `tiny` and `claude-headless` both reach the claude CLI, so each is
    # charged its CLI bound (twentieth run, a3 DISS-C-003: `tiny` falls through to the CLI inside one cheval call) and is
    # never started — named over_budget — while the answering voice (an HTTP hop, estimated at its 1 s call timeout) runs
    # while a second remains; two 2 s hops spend the budget, so the third payload is rejected unrepaired (fourteenth run,
    # a1 C-002: the budget pre-empts a hop it cannot afford instead of discovering the stall afterwards). Under load the
    # second hop may not fit either — at least one payload is exhausted whatever the scheduling. (twenty-second run, c2b
    # C-002: a 6 s budget and 3 s hops — the first `m` hop is admitted with up to five seconds of setup spent, not three)
    : > "$TEST_DIR/repair-calls"; CONF_TIMEOUT=1
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS=6 process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
    CONF_TIMEOUT=60
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "3" ]
    [ "$(jq '.metadata.repair_budget_exhausted' <<<"$result")" -ge 1 ]
    [ "$(jq '.metadata.repair_wall_budget_seconds' <<<"$result")" = "6" ]
    [ "$(jq '.metadata.repair_wall_seconds' <<<"$result")" -ge 3 ]
    [ "$(grep -c '' "$TEST_DIR/repair-calls")" -le 2 ]; [ "$(grep -c '' "$TEST_DIR/repair-calls")" -ge 1 ]
    [ "$(grep -c "claude-headless" "$TEST_DIR/repair-calls")" = "0" ]
    [ "$(grep -cx "tiny" "$TEST_DIR/repair-calls")" = "0" ]
    jq -e '.metadata.repair_hops_skipped | index("claude-headless:over_budget") != null' <<<"$result" >/dev/null
    jq -e '.metadata.repair_hops_skipped | index("tiny:over_budget") != null' <<<"$result" >/dev/null
    grep -q "Repair hop claude-headless needs up to .*s and .*s of the repair budget remain — not started" "$TEST_DIR/repair-err"
    grep -q "Repair budget: .* used — payload" "$TEST_DIR/repair-err"
    # the default budget is ADV_REPAIR_MAX_PER_RUN × timeout × 2, or one full CLI repair plus a timeout if that is more
    # (fourteenth run, a1 C-002: a CLI hop is bounded by cheval, not by the call timeout) — never spent by three
    # one-second payloads
    # (nineteenth run, a1 C-001: two full CLI repairs; twentieth run, a3 DISS-C-003: the heaviest hop is charged as the budget
    # charges it — `tiny` with a key pays its lock wait, its timeout and the claude CLI bound)
    _hmax=$(_adv_hop_charge claude-headless 60); (( $(_adv_hop_charge tiny 60) > _hmax )) && _hmax=$(_adv_hop_charge tiny 60)
    exp=$(( 2 * _hmax + 60 )); (( exp < ADV_REPAIR_MAX_PER_RUN * 60 * 2 )) && exp=$(( ADV_REPAIR_MAX_PER_RUN * 60 * 2 ))
    (( _hmax > $(_adv_cli_hop_bound claude-headless) ))   # (tiny reaches the CLI: it outweighs the CLI hop alone)
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
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; sleep 2; return 1; }
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
    mkdir -m 700 "$XDG_RUNTIME_DIR/loa-headless-locks-$(id -u)"
    exec 8>>"$XDG_RUNTIME_DIR/loa-headless-locks-$(id -u)/claude.lock"; flock 8   # another claude -p holds the binary's lock
    doc='{"findings":[{"title":"one","category":"other","description":"No severity."},{"title":"two","category":"other","description":"No severity."}]}'
    # the budget is the hop's bound plus two seconds: the first payload's hop is admitted with up to two whole seconds spent
    # before it (the twentieth-run dry run under load: a budget of exactly the bound pre-empted it as soon as one second boundary
    # had passed; twenty-first run, c2b C-001: plus one left about one real second of margin), waits 4 s for the lock and never
    # runs; the second payload finds less than the bound left (a 4 s wait crosses at least four whole-second boundaries, more
    # than the two of margin) — with the fix its estimate is still the bound, so the hop is pre-empted and named;
    # a noted lock wait would have made it a few seconds and queued the hop behind the lock again
    bound=$(_adv_cli_hop_bound claude-headless); [ "$bound" -gt 60 ]
    # (twenty-second run, c2b C-002: four seconds of margin and an eight-second wait — the wait still outlasts the margin, and
    # setup under load has twice the room)
    : > "$TEST_DIR/repair-calls"; CONF_TIMEOUT=8   # (an eight-second lock wait outlasts the four seconds of margin — the budget guard measures whole seconds)
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS="$(( bound + 4 ))" process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
    CONF_TIMEOUT=60
    flock -u 8; exec 8>&-
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "2" ]
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "m m " ]   # the CLI hop never ran for either payload
    [ "$(grep -c "Repair hop claude-headless never ran (its CLI lock was not acquired within 8s) — no duration noted" "$TEST_DIR/repair-err")" = "1" ]
    jq -e '.metadata.repair_hops_skipped | index("claude-headless:over_budget") != null' <<<"$result" >/dev/null
}

@test "NRM-27 a repair hop that ran and failed fast leaves no duration either: only a usable reply says how long a completed attempt takes, so the next payload's estimate stays the bound (eighteenth run, a1 C-003)" {
    unset ANTHROPIC_API_KEY   # keyless: the chain is claude-headless → m
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; sleep 6; return 1; }   # fails after six seconds — a transient provider error, far below the bound
    doc='{"findings":[{"title":"one","category":"other","description":"No severity."},{"title":"two","category":"other","description":"No severity."}]}'
    bound=$(_adv_cli_hop_bound claude-headless); [ "$bound" -gt 60 ]
    : > "$TEST_DIR/repair-calls"; CONF_TIMEOUT=1
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS="$(( bound + 5 ))" process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    CONF_TIMEOUT=60
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "2" ]
    # the first payload's CLI hop ran (admitted with five seconds of margin — twenty-second run, c2b C-002) and failed after six; the second payload's
    # estimate is still the bound — above what is left — so it is pre-empted and named, never admitted on an 8 s note
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "claude-headless m m " ]
    jq -e '.metadata.repair_hops_skipped | index("claude-headless:over_budget") != null' <<<"$result" >/dev/null
    # …and a usable reply IS noted: the second payload's hop is admitted on the observed duration (sixteenth run, a1 C-001) —
    # a budget of the bound plus five seconds admits the first attempt with margin; that attempt takes six seconds, so the
    # bound-sized estimate would no longer fit for the second payload while the noted duration does
    _repair_finding_via_model() { echo "$4" >> "$TEST_DIR/repair-calls"; sleep 6; printf '%s' "$1" | jq -c '. + {severity: "LOW"}'; }
    : > "$TEST_DIR/repair-calls"; CONF_TIMEOUT=1
    result=$(LOA_ADVERSARIAL_REPAIR_BUDGET_SECONDS="$(( bound + 5 ))" process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>/dev/null)
    CONF_TIMEOUT=60
    [ "$(jq '.metadata.repaired_count' <<<"$result")" = "2" ]
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "claude-headless claude-headless " ]
    [ "$(jq -c '.metadata.repair_hops_skipped' <<<"$result")" = '[]' ]
}

@test "NRM-28 the test seams are honoured under the bats marker only: a production environment that exports _ADV_FLOCK_BIN never loses the per-binary serialisation (nineteenth run, a2 C-005)" {
    # the trailer is an indented `main "$@"` inside the BASH_SOURCE guard: the sed must match it (the old `"s/^main \"\\$@\"…"`
    # reached sed as `^main "\"` — `$@` expanded empty — and matched nothing), replace it with `:` (a comment would leave an
    # empty `then`), and the probe refuses to eval a body that still calls main (twentieth run, c2b C-001)
    probe='cd "$1"; set --; PROJECT_ROOT=$PWD; source .claude/scripts/lib-content.sh; source .claude/scripts/compat-lib.sh; body=$(sed -e "s/^\\( *\\)main \"\\\$@\"\$/\\1: main disabled/" .claude/scripts/adversarial-review.sh); if grep -Eq "^ *main \"\\\$@\"" <<<"$body"; then echo MAIN-LIVE; exit 9; fi; eval "$body"; printf "[%s][%s][%s]" "${_ADV_FLOCK_BIN:-}" "${_ADV_PGREP_BIN:-}" "${_ADV_LOCK_WAIT_CLI:-}"'
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
