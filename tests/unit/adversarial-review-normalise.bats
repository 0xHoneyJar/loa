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
    export LOA_MODELINV_LOG_PATH="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/model-invoke.jsonl"
    export LOA_COST_LEDGER_PATH="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/cost-ledger.jsonl"
    ADVERSARIAL_REVIEW="$PROJECT_ROOT/.claude/scripts/adversarial-review.sh"
    FIXTURES="$PROJECT_ROOT/tests/fixtures/dissent-rejected"
    TEST_DIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
    local saved_root="$PROJECT_ROOT"
    source "$PROJECT_ROOT/.claude/scripts/lib-content.sh"
    source "$PROJECT_ROOT/.claude/scripts/compat-lib.sh"
    eval "$(sed 's/^main "\$@"/# main disabled for testing/' "$ADVERSARIAL_REVIEW")"
    PROJECT_ROOT="$saved_root"
    export PROJECT_ROOT
    CONF_ENABLED="true"; CONF_MODEL="gpt-5.5-pro"; CONF_TIMEOUT=60; CONF_BUDGET_CENTS=150
    CONF_ESCALATION_ENABLED="true"; CONF_SECONDARY_BUDGET=12000; CONF_MAX_FILE_LINES=500
    CONF_MAX_FILE_BYTES=51200; CONF_SECRET_SCANNING="true"; CONF_SECRET_ALLOWLIST=()
    LOA_ADVERSARIAL_REJECT_SIDECAR_DISABLE=""
    REPAIR_CANARY="$TEST_DIR/repair-called-$$"
    # the normaliser must make the repair unnecessary: a stub that records the call and fails
    _repair_finding_via_model() { : > "$REPAIR_CANARY"; return 1; }
    unset ANTHROPIC_API_KEY OPENAI_API_KEY LOA_ADVERSARIAL_REPAIR_MODEL
    unset LOA_ADVERSARIAL_RUN_TAG _ADV_SIDECAR_TAG LOA_ADVERSARIAL_ENV_DIR LOA_ADVERSARIAL_NO_FM_DERIVATION   # (seventh run, c2 C-005)
    export LOA_ADVERSARIAL_CLI_PROBE=both   # both CLI binaries "installed" unless a case says otherwise (the repair chain gates on it)
}
teardown() {
    local d
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
    long=$(python3 -c 'print("A" * 350 + ". Second sentence.")')
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
    run bash -xc "$(declare -f _adv_cred_present); PROJECT_ROOT='$PROJECT_ROOT'; LOA_ADVERSARIAL_ENV_DIR='$LOA_ADVERSARIAL_ENV_DIR'; BATS_TEST_FILENAME=x; _adv_cred_present anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" != *"dotenv-secret-value-xyz-987"* ]]
    # the exported-variable path too (seventh run, c2 C-003): the probe never expands the value
    # (the value enters through the environment, not the traced script — an `export` line would trace itself)
    ANTHROPIC_API_KEY=env-secret-value-123 run bash -xc "$(declare -f _adv_cred_present); PROJECT_ROOT='$PROJECT_ROOT'; _adv_cred_present anthropic"
    [ "$status" -eq 0 ]
    [[ "$output" != *"env-secret-value-123"* ]]
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
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.metadata.repaired_count' <<<"$result")" = "1" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "0" ]
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-models")" = "tiny claude-headless " ]   # the answering voice (m) would be third; never reached
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
    doc='{"findings":[{"severity":"HIGH","category":"config"},{"severity":"HIGH","category":"config","description":""},{"severity":"HIGH","category":"config","description":null}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "0" ]
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "3" ]
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

@test "NRM-15 the collision guard reads the highest explicit id, not the finding count: a derived id colliding with an explicit one takes max(explicit) + 1 (ninth run, a1 C-002 — the jq `?` that zeroed it)" {
    doc='{"findings":[{"id":"DISS-009","severity":"MEDIUM","category":"config","description":"Nine.","failure_mode":"s"},{"severity":"LOW","category":"other","description":"No id, positional DISS-002 collides."},{"id":"DISS-002","severity":"LOW","category":"other","description":"Two.","failure_mode":"s"}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "")
    [ "$(jq '.findings | length' <<<"$result")" = "3" ]
    [ "$(jq -r '[.findings[].id] | join(",")' <<<"$result")" = "DISS-009,DISS-010,DISS-002" ]
}

@test "NRM-16 credential presence resolves per alias with override precedence: an empty GOOGLE_API_KEY never hides a GEMINI_API_KEY assigned in the same or a lower source; every alias assigned empty at its deciding source disables (ninth run a1 C-005; tenth run c2 C-001)" {
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-g"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    _probe() {  # <env assignments…> — runs the probe in a shell with only the named Google variables (the operator's shell may export one)
        bash -c "unset GOOGLE_API_KEY GEMINI_API_KEY; $1; $(declare -f _adv_cred_present); PROJECT_ROOT='$PROJECT_ROOT'; LOA_ADVERSARIAL_ENV_DIR='$LOA_ADVERSARIAL_ENV_DIR'; BATS_TEST_FILENAME=x; _adv_cred_present google"
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
}

@test "NRM-18 the shell's CLI-hop ceiling equals cheval's HEADLESS_TIMEOUT_CEILING_SECONDS, and an over-ceiling catalog value bounds the hop at connect + ceiling (tenth run, d C-001: one clamp, two readers)" {
    command -v yq >/dev/null 2>&1 || skip "yq not installed: the hop bound cannot read a catalog"
    py="$PROJECT_ROOT/.venv/bin/python"; [[ -x "$py" ]] || py=python3
    ceiling=$(cd "$PROJECT_ROOT/.claude/adapters" && "$py" -c 'from loa_cheval.types import HEADLESS_TIMEOUT_CEILING_SECONDS as c; print(int(c))' 2>/dev/null) || skip "loa_cheval is not importable with $py"
    [ "$ceiling" = "$_ADV_CLI_HOP_CEILING" ]
    printf 'providers:\n  anthropic:\n    connect_timeout: 10\n    read_timeout: 120\n    models:\n      claude-headless:\n        kind: cli\n        context_window: 1000\n        headless_timeout_seconds: 7200\n' > "$TEST_DIR/over.yaml"
    [ "$(LOA_MODEL_CONFIG="$TEST_DIR/over.yaml" _adv_cli_hop_bound claude-headless)" = "$(( 10 + ceiling ))" ]
}

@test "NRM-19 LOA_ADVERSARIAL_RUN_TAG is validated, not stripped: a tag outside [A-Za-z0-9_-]{1,64} becomes a short hash of its raw value, said once, so c.1 and c1 never share a sidecar (eleventh run, a1 C-002)" {
    [ "$(LOA_ADVERSARIAL_RUN_TAG="" _adv_run_tag)" = "" ]
    [ "$(LOA_ADVERSARIAL_RUN_TAG="c1-dissent_script" _adv_run_tag 2>/dev/null)" = "c1-dissent_script" ]
    a=$(LOA_ADVERSARIAL_RUN_TAG="c.1" _adv_run_tag 2>"$TEST_DIR/tag-err"); b=$(LOA_ADVERSARIAL_RUN_TAG="c1" _adv_run_tag 2>/dev/null)
    c=$(LOA_ADVERSARIAL_RUN_TAG="a/1" _adv_run_tag 2>/dev/null); d=$(LOA_ADVERSARIAL_RUN_TAG="x y" _adv_run_tag 2>/dev/null)
    [[ "$a" =~ ^h[0-9a-f]{12}$ ]]; [ "$b" = "c1" ]; [[ "$c" =~ ^h[0-9a-f]{12}$ ]]; [[ "$d" =~ ^h[0-9a-f]{12}$ ]]
    [ "$a" != "$c" ]; [ "$a" != "$d" ]; [ "$c" != "$d" ]
    grep -q "LOA_ADVERSARIAL_RUN_TAG is not \[A-Za-z0-9_-\]{1,64}" "$TEST_DIR/tag-err"
    [ "$(grep -c "c.1" "$TEST_DIR/tag-err")" = "0" ]   # the raw value is not echoed (it may be anything the driver passed)
    long=$(printf 'a%.0s' $(seq 1 65)); [[ "$(LOA_ADVERSARIAL_RUN_TAG="$long" _adv_run_tag 2>/dev/null)" =~ ^h[0-9a-f]{12}$ ]]
    # the same warning once per process: the second call is silent
    ( LOA_ADVERSARIAL_RUN_TAG="c.1"; _adv_run_tag >/dev/null; _adv_run_tag >/dev/null ) 2>"$TEST_DIR/tag-err2"
    [ "$(grep -c "is not" "$TEST_DIR/tag-err2")" = "1" ]
    # end to end: the sidecar a rejecting run writes carries the hashed tag, never the stripped one
    doc='{"findings":[{"title":"no severity","category":"other","description":"Something fails."}]}'
    LOA_ADVERSARIAL_RUN_TAG="c.1" process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" >/dev/null 2>&1 || true
    [ -f "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT/adversarial-rejected-audit-$a.jsonl" ]
    [ ! -e "$PROJECT_ROOT/grimoires/loa/a2a/$SPRINT/adversarial-rejected-audit-c1.jsonl" ]
}

@test "NRM-20 a repair hop that failed with an auth / quota / unavailable class is retired for the run's remaining repairs; the answering voice never is; a lock timeout or an unusable reply retires nothing (eleventh run, a1 C-003)" {
    export ANTHROPIC_API_KEY="sk-ant-test-presence-only-never-printed"
    export LOA_ADVERSARIAL_ENV_DIR="$TEST_DIR/env-none"; mkdir -p "$LOA_ADVERSARIAL_ENV_DIR"
    [ "$(_repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]
    [ "$(_ADV_REPAIR_DEAD_HOPS="tiny" _repair_model_chain "gpt-5.5-pro")" = "claude-headless gpt-5.5-pro" ]
    [ "$(_ADV_REPAIR_DEAD_HOPS="tiny claude-headless" _repair_model_chain "gpt-5.5-pro")" = "gpt-5.5-pro" ]
    [ "$(_ADV_REPAIR_DEAD_HOPS="gpt-5.5-pro" _repair_model_chain "gpt-5.5-pro")" = "tiny claude-headless gpt-5.5-pro" ]   # the answering voice stays
    [ "$(_ADV_REPAIR_DEAD_HOPS="claude-headless" _repair_model_chain "claude-headless")" = "tiny claude-headless" ]
    _adv_repair_retire_hop tiny 4 2>/dev/null; _adv_repair_retire_hop tiny 4 2>/dev/null; _adv_repair_retire_hop foo 6 2>/dev/null
    [ "$_ADV_REPAIR_DEAD_HOPS" = "tiny foo" ]
    unset _ADV_REPAIR_DEAD_HOPS
    # through the loop: two payloads the normaliser cannot save; tiny answers the first with an auth failure (rc 4),
    # claude-headless with an unusable reply (rc 0, no JSON) — only tiny is retired for the second payload
    _repair_finding_via_model() {
        echo "$4" >> "$TEST_DIR/repair-calls"
        case "$4" in
            tiny) [[ -n "${_ADV_REPAIR_RC_FILE:-}" ]] && printf 4 > "$_ADV_REPAIR_RC_FILE"; return 1 ;;
            claude-headless) [[ -n "${_ADV_REPAIR_RC_FILE:-}" ]] && printf 0 > "$_ADV_REPAIR_RC_FILE"; return 1 ;;
            *) return 1 ;;
        esac
    }
    doc='{"findings":[{"title":"no severity one","category":"other","description":"Something fails."},{"title":"no severity two","category":"other","description":"Something else fails."}]}'
    result=$(process_findings "$(_env "$doc")" "audit" "m" "$SPRINT" "0" "" 2>"$TEST_DIR/repair-err")
    [ "$(jq '.metadata.rejected_count' <<<"$result")" = "2" ]
    [ "$(tr '\n' ' ' < "$TEST_DIR/repair-calls")" = "tiny claude-headless m claude-headless m " ]
    grep -q "Repair hop tiny failed (rc 4) — retired" "$TEST_DIR/repair-err"
    [ "$(grep -c "retired" "$TEST_DIR/repair-err")" = "1" ]
    unset ANTHROPIC_API_KEY
}
