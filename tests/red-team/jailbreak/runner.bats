#!/usr/bin/env bats
# tests/red-team/jailbreak/runner.bats — cycle-100 T1.4
#
# Generator-driven single-shot runner (FR-3). Top-level loop iterates the
# active corpus and registers one bats test per vector via the public
# bats_test_function API. Each registered test feeds the fixture-built
# payload to `sanitize_for_session_start` under `timeout 5s` (IMP-002 ReDoS
# containment) and asserts the SDD §4.3.2 outcome semantics.
#
# Suppressed vectors → not iterated (corpus_iter_active drops them);
# superseded vectors → not iterated.
#
# DESIGN NOTE: Test registration MUST run at file source time (during bats
# gather), NOT in setup_file (which runs after gather). bats-preprocess
# evaluates the .bats file body before locking in the test list.

# ---- one-time discovery (file source time) -------------------------------
# bats does NOT propagate `set -euo pipefail` from this file into the
# preprocessed test bodies (it strips `set -e` from gather-phase). However
# we keep `set -uo pipefail` for the discovery loop to guard against silent
# corpus-validate / loader failures (F5 cypherpunk MED).
set -uo pipefail

RUNNER_REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
RUNNER_LOADER="${RUNNER_REPO_ROOT}/tests/red-team/jailbreak/lib/corpus_loader.sh"
RUNNER_AUDIT_LIB="${RUNNER_REPO_ROOT}/tests/red-team/jailbreak/lib/audit_writer.sh"
RUNNER_SUT_LIB="${RUNNER_REPO_ROOT}/.claude/scripts/lib/context-isolation-lib.sh"
RUNNER_FIXTURE_DIR="${RUNNER_REPO_ROOT}/tests/red-team/jailbreak/fixtures"
RUNNER_REDACTION_MARKERS="${RUNNER_REPO_ROOT}/.claude/data/lore/agent-network/jailbreak-redaction-markers.txt"

# Stash corpus rows in a tmpfile keyed by encoded test name so the test body
# can look them up at run time.
RUNNER_VECTOR_TMP="$(mktemp -t "jailbreak-runner-vectors-XXXXXX.tsv")"
export RUNNER_VECTOR_TMP

# Schema-first: validate corpus before any payload work (NFR-Rel1).
# Hard fail at file-source time if corpus is invalid — refuses to register
# tests against a corrupted corpus (F5 cypherpunk MED closure).
if ! bash "$RUNNER_LOADER" validate-all >&2; then
    echo "runner.bats: BAIL: corpus validation failed; refusing to register tests" >&2
    exit 1
fi

# Iterate active vectors and register one bats test each.
# Skip multi_turn_conditioning category — those vectors require the
# multi-turn replay harness (test_replay.py) per SDD §4.4 and have no
# single-turn semantics. The pytest harness consumes them via
# `iter_active(category="multi_turn_conditioning")`.
#
# BB iter-1 F6 closure (2026-05-08): `< <(...)` process substitution does
# not propagate exit status. If iter-active fails midway (jq parse error
# on a line that passed schema validation but whose subsequent jq filter
# trips), the read loop terminates with partial vectors registered and
# bats reports green-with-fewer-tests — vacuously-green class. Capture to
# a temp file first, fail-fast on non-zero exit, then iterate.
RUNNER_ITER_TMP="$(mktemp -t "jailbreak-iter-XXXXXX")"
if ! bash "$RUNNER_LOADER" iter-active > "$RUNNER_ITER_TMP"; then
    echo "runner.bats: BAIL: corpus_loader iter-active failed mid-stream" >&2
    rm -f "$RUNNER_ITER_TMP"
    exit 1
fi
while IFS= read -r json; do
    [[ -z "$json" ]] && continue
    cat_field="$(echo "$json" | jq -r '.category')"
    [[ "$cat_field" == "multi_turn_conditioning" ]] && continue
    vid="$(echo "$json" | jq -r '.vector_id')"
    title="$(echo "$json" | jq -r '.title')"
    # Encode vector_id into a valid bash identifier for the function name.
    safe_vid="${vid//-/_}"
    fn_name="test_vector_${safe_vid}"
    description="${vid}: ${title}"
    # Persist the JSON line for the test body to look up.
    # Encode JSON via base64 to keep TSV happy with arbitrary content.
    encoded_json="$(echo "$json" | base64 -w0 2>/dev/null || echo "$json" | base64)"
    printf '%s\t%s\n' "$fn_name" "$encoded_json" >> "$RUNNER_VECTOR_TMP"
    # Define the test body at gather time. Body looks up its JSON by name.
    eval "${fn_name}() { _run_one_vector_by_name \"\$BATS_TEST_NAME\"; }"
    bats_test_function --description "$description" --tags "" -- "${fn_name}"
done < "$RUNNER_ITER_TMP"
rm -f "$RUNNER_ITER_TMP"

setup_file() {
    # shellcheck disable=SC1090
    source "$RUNNER_AUDIT_LIB"
    audit_writer_init
    export _AUDIT_LOG_PATH _AUDIT_RUN_ID
}

teardown_file() {
    # Keep the audit log; remove the per-run vector cache.
    if [[ -n "${RUNNER_VECTOR_TMP:-}" && -f "$RUNNER_VECTOR_TMP" ]]; then
        rm -f "$RUNNER_VECTOR_TMP"
    fi
}

# ---- per-vector test body ------------------------------------------------
_run_one_vector_by_name() {
    local fn_name="$1"
    local encoded_json json
    encoded_json="$(awk -F'\t' -v n="$fn_name" '$1 == n {print $2; exit}' "$RUNNER_VECTOR_TMP")"
    if [[ -z "$encoded_json" ]]; then
        echo "runner: vector lookup failed for $fn_name" >&2
        return 1
    fi
    json="$(echo "$encoded_json" | base64 -d)"
    _run_one_vector "$json"
}

_run_one_vector() {
    local json="$1"
    local vid category defense_layer payload_construction expected_outcome expected_marker
    vid="$(echo "$json" | jq -r '.vector_id')"
    category="$(echo "$json" | jq -r '.category')"
    defense_layer="$(echo "$json" | jq -r '.defense_layer')"
    payload_construction="$(echo "$json" | jq -r '.payload_construction')"
    expected_outcome="$(echo "$json" | jq -r '.expected_outcome')"
    expected_marker="$(echo "$json" | jq -r '.expected_marker // empty')"

    local fixture_sh="${RUNNER_FIXTURE_DIR}/${category}.sh"
    if [[ ! -f "$fixture_sh" ]]; then
        _audit_emit_with_lib "$vid" "$category" "$defense_layer" "fail" \
            "FIXTURE-MISSING: file ${fixture_sh}"
        echo "fixture file missing: ${fixture_sh}" >&2
        return 1
    fi

    # shellcheck disable=SC1090
    source "$fixture_sh"
    if ! declare -f "$payload_construction" >/dev/null 2>&1; then
        _audit_emit_with_lib "$vid" "$category" "$defense_layer" "fail" \
            "FIXTURE-MISSING: function ${payload_construction}"
        echo "fixture function missing: ${payload_construction}" >&2
        return 1
    fi
    local payload
    payload="$($payload_construction)"

    # shellcheck disable=SC1090
    source "$RUNNER_SUT_LIB"

    local actual_stdout actual_stderr_file actual_exit
    actual_stderr_file="$(mktemp -t "jailbreak-stderr-${vid}-XXXXXX")"
    set +e
    actual_stdout="$(timeout 5s bash -c '
        # shellcheck disable=SC1090
        source "$1"; sanitize_for_session_start "$2" "$3" 2>"$4"
    ' _ "$RUNNER_SUT_LIB" "L7" "$payload" "$actual_stderr_file")"
    actual_exit=$?
    set -e
    local actual_stderr=""
    [[ -s "$actual_stderr_file" ]] && actual_stderr="$(cat "$actual_stderr_file")"
    rm -f "$actual_stderr_file"

    if [[ $actual_exit -eq 124 ]]; then
        _audit_emit_with_lib "$vid" "$category" "$defense_layer" "fail" \
            "TIMEOUT-REDOS-SUSPECT (>5s): payload[0..200]=${payload:0:200}"
        echo "TIMEOUT-REDOS-SUSPECT for ${vid}" >&2
        return 1
    fi

    if _assert_outcome "$vid" "$expected_outcome" "$expected_marker" \
        "$actual_stdout" "$actual_stderr" "$actual_exit"; then
        _audit_emit_with_lib "$vid" "$category" "$defense_layer" "pass" ""
        return 0
    else
        local short_reason
        short_reason="expected=${expected_outcome} actual_exit=${actual_exit} stdout[0..120]=${actual_stdout:0:120}"
        _audit_emit_with_lib "$vid" "$category" "$defense_layer" "fail" "$short_reason"
        return 1
    fi
}

_audit_emit_with_lib() {
    if ! declare -f audit_emit_run_entry >/dev/null 2>&1; then
        # shellcheck disable=SC1090
        source "$RUNNER_AUDIT_LIB"
    fi
    # F10 closure: do NOT swallow audit-emit failures with `|| true`. A
    # missing audit entry violates the FR-7 deliverable invariant. Surface
    # the failure as a stderr warning AND propagate the exit code so the
    # test can fail informatively.
    if ! audit_emit_run_entry "$@"; then
        echo "runner.bats: WARNING: audit_emit_run_entry failed for ${1:-<no-vid>}" >&2
        return 1
    fi
}

_assert_outcome() {
    local vid="$1" expected="$2" expected_marker="$3"
    local stdout="$4" stderr="$5" exit_code="$6"

    local trunc_stdout="${stdout:0:200}"
    local trunc_stderr="${stderr:0:200}"

    case "$expected" in
        redacted)
            if [[ -n "$expected_marker" ]]; then
                if [[ "$stdout" != *"$expected_marker"* ]]; then
                    echo "${vid}: expected marker ${expected_marker} not in stdout (truncated 200): ${trunc_stdout}" >&2
                    return 1
                fi
            else
                if ! _stdout_has_any_redaction_marker "$stdout"; then
                    echo "${vid}: no redaction marker in stdout (truncated 200): ${trunc_stdout}" >&2
                    return 1
                fi
            fi
            if [[ "$exit_code" -ne 0 ]]; then
                echo "${vid}: redacted expected exit 0, got ${exit_code}; stderr: ${trunc_stderr}" >&2
                return 1
            fi
            return 0
            ;;
        rejected)
            if [[ "$exit_code" -eq 0 ]]; then
                echo "${vid}: rejected expected non-zero exit, got 0" >&2
                return 1
            fi
            if [[ "$stderr" != *"BLOCKER:"* ]]; then
                echo "${vid}: rejected expected BLOCKER: in stderr; stderr: ${trunc_stderr}" >&2
                return 1
            fi
            return 0
            ;;
        wrapped)
            if [[ "$stdout" != "<untrusted-content"* ]]; then
                echo "${vid}: wrapped expected stdout to start with <untrusted-content; got: ${trunc_stdout}" >&2
                return 1
            fi
            if [[ "$stdout" != *"</untrusted-content>"* ]]; then
                echo "${vid}: wrapped expected stdout to contain </untrusted-content>; got tail: ${stdout: -200}" >&2
                return 1
            fi
            return 0
            ;;
        passed-through-unchanged)
            echo "${vid}: passed-through-unchanged not currently producible by SUT (always wraps)" >&2
            return 1
            ;;
        *)
            echo "${vid}: unknown expected_outcome '${expected}'" >&2
            return 1
            ;;
    esac
}

_stdout_has_any_redaction_marker() {
    local s="$1" marker
    while IFS= read -r marker; do
        [[ -z "$marker" || "$marker" =~ ^[[:space:]]*# ]] && continue
        if [[ "$s" == *"$marker"* ]]; then
            return 0
        fi
    done < "$RUNNER_REDACTION_MARKERS"
    return 1
}
