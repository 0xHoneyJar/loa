#!/usr/bin/env bats
# tests/red-team/jailbreak/differential.bats — cycle-100 sprint-3 T3.3 (FR-5)
#
# Run a curated subset of vectors against BOTH the current SUT (`.claude/
# scripts/lib/context-isolation-lib.sh`) and the frozen baseline
# (`.claude/scripts/lib/context-isolation-lib.sh.cycle-100-baseline`)
# captured at sprint-3 ship date by T3.4. Compare stdout + stderr + exit
# code byte-for-byte. Per SDD §4.5 + PRD FR-5:
#
#   - Divergence is INFORMATIONAL, not failing.
#   - On divergence: emit a JSONL entry to `.run/jailbreak-diff-<date>.jsonl`
#     and a TAP `# DIVERGE: ...` comment.
#   - Exit 0 even when divergent. Operator review is the gate.
#
# Why informational: a divergence may be (a) defense improved, (b) defense
# regressed, or (c) test-bug. Auto-failing would create noise during normal
# lib evolution. The audit trail is the deliverable; humans triage.
#
# Environment parity (Flatline IMP-003): both libs run under the shared
# `env_sanitize.sh` `env -i` allowlist. Single-shot and differential paths
# see identical environment surface, preventing developer-shell-shaped
# divergence (`PYTHONUNBUFFERED`, shell-rc aliases) from masking SUT diffs.

set -uo pipefail

DIFF_REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
DIFF_LOADER="${DIFF_REPO_ROOT}/tests/red-team/jailbreak/lib/corpus_loader.sh"
DIFF_FIXTURE_DIR="${DIFF_REPO_ROOT}/tests/red-team/jailbreak/fixtures"
DIFF_SUT_CURRENT="${DIFF_REPO_ROOT}/.claude/scripts/lib/context-isolation-lib.sh"
DIFF_SUT_BASELINE="${DIFF_REPO_ROOT}/.claude/scripts/lib/context-isolation-lib.sh.cycle-100-baseline"
DIFF_ENV_SANITIZE="${DIFF_REPO_ROOT}/tests/red-team/jailbreak/lib/env_sanitize.sh"
DIFF_VECTOR_LIST="${DIFF_REPO_ROOT}/tests/red-team/jailbreak/differential-vectors.txt"
DIFF_DATE="$(date -u +%Y-%m-%d)"
DIFF_LOG_DIR="${DIFF_REPO_ROOT}/.run"
DIFF_LOG_PATH="${DIFF_LOG_DIR}/jailbreak-diff-${DIFF_DATE}.jsonl"

mkdir -p "$DIFF_LOG_DIR"

# Hard-fail at file-source time if either lib is absent: the differential
# oracle cannot meaningfully run without both endpoints. T3.4 captures the
# baseline; if it's missing, the operator either skipped T3.4 or removed it
# accidentally — either way, we must surface the gap loudly rather than
# silently produce an "all converge" green run.
if [[ ! -f "$DIFF_SUT_CURRENT" ]]; then
    echo "differential.bats: BAIL: current SUT missing at $DIFF_SUT_CURRENT" >&2
    exit 1
fi
if [[ ! -f "$DIFF_SUT_BASELINE" ]]; then
    echo "differential.bats: BAIL: frozen baseline missing at $DIFF_SUT_BASELINE (T3.4)" >&2
    exit 1
fi
if [[ ! -f "$DIFF_VECTOR_LIST" ]]; then
    echo "differential.bats: BAIL: vector list missing at $DIFF_VECTOR_LIST (T3.5)" >&2
    exit 1
fi

# Cache validate-all + iter-active across the run (same Sprint-3 T3.7 perf
# pattern as runner.bats — bats re-sources this file once per test).
if [[ -n "${BATS_RUN_TMPDIR:-}" ]]; then
    DIFF_CACHE_DIR="${BATS_RUN_TMPDIR}/jailbreak-diff-cache"
else
    DIFF_CACHE_DIR="/tmp/jailbreak-diff-cache-${PPID:-$$}"
fi
mkdir -p "$DIFF_CACHE_DIR"
DIFF_CORPUS_DIR="${DIFF_REPO_ROOT}/tests/red-team/jailbreak/corpus"
# Sprint-3 review DISS-007: portable cache key (no `find -printf`).
DIFF_CACHE_KEY="$( (cd "$DIFF_CORPUS_DIR" && \
    LC_ALL=C ls -1 *.jsonl 2>/dev/null \
    | sort \
    | while IFS= read -r f; do
        sha256sum "$f" 2>/dev/null || shasum -a 256 "$f"
      done) | sha256sum | awk '{print $1}')"
DIFF_VALIDATE_SENTINEL="${DIFF_CACHE_DIR}/validated.${DIFF_CACHE_KEY}.sentinel"
DIFF_ITER_CACHE="${DIFF_CACHE_DIR}/iter-active.${DIFF_CACHE_KEY}.jsonl"

if [[ ! -f "$DIFF_VALIDATE_SENTINEL" ]]; then
    if ! bash "$DIFF_LOADER" validate-all >&2; then
        echo "differential.bats: BAIL: corpus validation failed" >&2
        exit 1
    fi
    : > "$DIFF_VALIDATE_SENTINEL"
fi
if [[ ! -s "$DIFF_ITER_CACHE" ]]; then
    DIFF_ITER_TMP="${DIFF_CACHE_DIR}/iter.tmp.$$"
    if ! bash "$DIFF_LOADER" iter-active > "$DIFF_ITER_TMP"; then
        echo "differential.bats: BAIL: iter-active failed" >&2
        rm -f "$DIFF_ITER_TMP"
        exit 1
    fi
    mv -f "$DIFF_ITER_TMP" "$DIFF_ITER_CACHE"
fi

# Read the curated vector list. Lines starting with `#` are comments;
# blank lines are skipped.
DIFF_REGISTRATION_TSV="${DIFF_CACHE_DIR}/registration.${DIFF_CACHE_KEY}.tsv"
if [[ ! -s "$DIFF_REGISTRATION_TSV" ]]; then
    : > "${DIFF_REGISTRATION_TSV}.tmp"
    while IFS= read -r raw_vid; do
        # Strip leading/trailing whitespace; skip comments + blanks.
        raw_vid="${raw_vid#"${raw_vid%%[![:space:]]*}"}"
        raw_vid="${raw_vid%"${raw_vid##*[![:space:]]}"}"
        [[ -z "$raw_vid" || "$raw_vid" == \#* ]] && continue
        # Look up the vector's category in iter-active cache; emit
        # vector_id<TAB>category<TAB>title<TAB>base64(json) for the test body.
        line="$(jq -r --arg v "$raw_vid" 'select(.vector_id == $v)
            | [.vector_id, .category, .title, (. | tojson | @base64)] | @tsv' "$DIFF_ITER_CACHE")"
        if [[ -z "$line" ]]; then
            echo "differential.bats: WARN: vector $raw_vid not found in active corpus; skipping" >&2
            continue
        fi
        printf '%s\n' "$line" >> "${DIFF_REGISTRATION_TSV}.tmp"
    done < "$DIFF_VECTOR_LIST"
    mv -f "${DIFF_REGISTRATION_TSV}.tmp" "$DIFF_REGISTRATION_TSV"
fi

DIFF_VECTOR_TMP="$(mktemp -t "jailbreak-diff-vectors-XXXXXX.tsv")"
export DIFF_VECTOR_TMP

while IFS=$'\t' read -r vid category title encoded_json; do
    [[ -z "$vid" ]] && continue
    # Skip multi_turn category — differential oracle is single-shot only.
    [[ "$category" == "multi_turn_conditioning" ]] && continue
    safe_vid="${vid//-/_}"
    fn_name="diff_vector_${safe_vid}"
    description="${vid}: ${title} (differential)"
    printf '%s\t%s\n' "$fn_name" "$encoded_json" >> "$DIFF_VECTOR_TMP"
    eval "${fn_name}() { _run_diff_vector_by_name \"\$BATS_TEST_NAME\"; }"
    bats_test_function --description "$description" --tags "" -- "${fn_name}"
done < "$DIFF_REGISTRATION_TSV"

teardown_file() {
    if [[ -n "${DIFF_VECTOR_TMP:-}" && -f "$DIFF_VECTOR_TMP" ]]; then
        rm -f "$DIFF_VECTOR_TMP"
    fi
}

# ---- per-vector diff body -----------------------------------------------
_run_diff_vector_by_name() {
    local fn_name="$1"
    local encoded_json json
    encoded_json="$(awk -F'\t' -v n="$fn_name" '$1 == n {print $2; exit}' "$DIFF_VECTOR_TMP")"
    if [[ -z "$encoded_json" ]]; then
        echo "differential: vector lookup failed for $fn_name" >&2
        return 1
    fi
    json="$(printf '%s' "$encoded_json" | base64 -d)"
    _run_diff_vector "$json"
}

_run_diff_vector() {
    local json="$1"
    local vid category payload_construction
    local _fields
    mapfile -t _fields < <(jq -r '
        .vector_id, .category, .payload_construction
    ' <<< "$json")
    vid="${_fields[0]}"
    category="${_fields[1]}"
    payload_construction="${_fields[2]}"

    local fixture_sh="${DIFF_FIXTURE_DIR}/${category}.sh"
    if [[ ! -f "$fixture_sh" ]]; then
        echo "differential: fixture missing: $fixture_sh" >&2
        return 1
    fi

    # shellcheck disable=SC1090
    source "$fixture_sh"
    if ! declare -f "$payload_construction" >/dev/null 2>&1; then
        echo "differential: fixture function missing: $payload_construction" >&2
        return 1
    fi
    local payload
    payload="$($payload_construction)"

    local cur_stdout cur_stderr_file cur_exit
    local base_stdout base_stderr_file base_exit
    cur_stderr_file="$(mktemp -t "diff-cur-${vid}-XXXXXX")"
    base_stderr_file="$(mktemp -t "diff-base-${vid}-XXXXXX")"

    cur_stdout="$(_invoke_sut_under_envi "$DIFF_SUT_CURRENT" "$payload" "$cur_stderr_file")"
    cur_exit=$?
    base_stdout="$(_invoke_sut_under_envi "$DIFF_SUT_BASELINE" "$payload" "$base_stderr_file")"
    base_exit=$?

    local cur_stderr="" base_stderr=""
    [[ -s "$cur_stderr_file" ]] && cur_stderr="$(cat "$cur_stderr_file")"
    [[ -s "$base_stderr_file" ]] && base_stderr="$(cat "$base_stderr_file")"
    rm -f "$cur_stderr_file" "$base_stderr_file"

    local stdout_match=true stderr_match=true exit_match=true
    [[ "$cur_stdout" == "$base_stdout" ]] || stdout_match=false
    [[ "$cur_stderr" == "$base_stderr" ]] || stderr_match=false
    [[ "$cur_exit" == "$base_exit" ]] || exit_match=false

    if [[ "$stdout_match" == "true" && "$stderr_match" == "true" && "$exit_match" == "true" ]]; then
        # Convergent. No JSONL entry written (FR-5: only divergences are
        # logged). Emit a TAP comment so operators can see coverage.
        echo "# CONVERGE: $vid"
        return 0
    fi

    # Divergent. Emit JSONL + TAP comment. Exit 0 (informational, not failing).
    _emit_diff_jsonl "$vid" "$category" "$cur_stdout" "$cur_stderr" "$cur_exit" \
        "$base_stdout" "$base_stderr" "$base_exit" \
        "$stdout_match" "$stderr_match" "$exit_match"
    echo "# DIVERGE: $vid stdout=$stdout_match stderr=$stderr_match exit=$exit_match cur_exit=$cur_exit base_exit=$base_exit"
    echo "# DIVERGE: see $DIFF_LOG_PATH for full record"
    return 0
}

# Invoke the SUT under the shared env -i allowlist (IMP-003 environment
# parity). Bash subshell sources the lib and runs sanitize_for_session_start.
_invoke_sut_under_envi() {
    local lib="$1" payload="$2" stderr_file="$3"
    # shellcheck disable=SC1091
    source "$DIFF_ENV_SANITIZE"
    local rc
    set +e
    local out
    out="$(loa_jailbreak_envi_invoke timeout 5s bash -c '
        # shellcheck disable=SC1090
        source "$1"; sanitize_for_session_start "$2" "$3" 2>"$4"
    ' _ "$lib" "L7" "$payload" "$stderr_file")"
    rc=$?
    set -e
    printf '%s' "$out"
    return $rc
}

# Emit one JSONL entry per divergence to `.run/jailbreak-diff-<date>.jsonl`.
# Schema (informational; no separate JSON Schema file in cycle-100):
#   { run_id, vector_id, category, ts_utc,
#     current:  { stdout_b64, stderr_b64, exit },
#     baseline: { stdout_b64, stderr_b64, exit },
#     match: { stdout, stderr, exit } }
# Outputs are base64-encoded so binary bytes (RS sentinel, NULs) survive
# JSONL round-tripping. `jq -c --arg` for safety (cycle-099 PR #215 pattern).
_emit_diff_jsonl() {
    local vid="$1" category="$2"
    local cur_stdout="$3" cur_stderr="$4" cur_exit="$5"
    local base_stdout="$6" base_stderr="$7" base_exit="$8"
    local stdout_m="$9" stderr_m="${10}" exit_m="${11}"

    # Sprint-3 T3.8 F8: macOS `base64` lacks `-w0`. Fallback's wrapped output
    # (76-char lines) is JSON-valid via jq --arg but downstream `base64 -d`
    # needs `-i` to ignore newlines. Strip newlines defensively so consumers
    # don't need that flag.
    _b64_oneline() {
        if base64 --help 2>&1 | grep -q -- '-w'; then
            printf '%s' "$1" | base64 -w0
        else
            printf '%s' "$1" | base64 | tr -d '\n'
        fi
    }
    local cur_stdout_b64 cur_stderr_b64 base_stdout_b64 base_stderr_b64
    cur_stdout_b64="$(_b64_oneline "$cur_stdout")"
    cur_stderr_b64="$(_b64_oneline "$cur_stderr")"
    base_stdout_b64="$(_b64_oneline "$base_stdout")"
    base_stderr_b64="$(_b64_oneline "$base_stderr")"

    local run_id ts_utc
    ts_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    # run_id = first 16 hex chars of sha256(workflow_run || ts_utc || pid), per
    # FR-7 conventions (matches audit_writer.sh pattern). Sprint-3 T3.8 F7:
    # include $BASHPID so two diverging vectors emitted in the same UTC
    # second under `bats --jobs N` don't collide.
    run_id="$(printf '%s' "${GITHUB_RUN_ID:-manual}-${ts_utc}-${BASHPID:-$$}" | sha256sum | head -c 16)"

    # flock the log so concurrent bats workers don't interleave bytes mid-line.
    # `flock` is required (cycle-099 sprint-1A precedent for shared append-only
    # writers). On macOS, `flock` ships via `brew install util-linux`.
    #
    # Sprint-3 BB iter-1 F6 closure: don't silently skip JSONL emit when
    # flock is missing — that turns FR-7 (audit deliverable) into a no-op.
    # Fall back to a temp-file + atomic-mv-append pattern that doesn't
    # require flock; under bats --jobs N two concurrent atomic-renames may
    # still interleave entries between commits, but each entry is a single
    # whole line on disk (no mid-line corruption). For single-worker runs
    # (the common case), the fallback is bit-equivalent to the flock path.
    if ! command -v flock >/dev/null 2>&1; then
        local _diff_tmp
        _diff_tmp="$(mktemp -t "diff-emit-XXXXXX.jsonl")"
        jq -cn \
            --arg run_id "$run_id" \
            --arg vid "$vid" \
            --arg cat "$category" \
            --arg ts "$ts_utc" \
            --arg cur_stdout_b64 "$cur_stdout_b64" \
            --arg cur_stderr_b64 "$cur_stderr_b64" \
            --argjson cur_exit "$cur_exit" \
            --arg base_stdout_b64 "$base_stdout_b64" \
            --arg base_stderr_b64 "$base_stderr_b64" \
            --argjson base_exit "$base_exit" \
            --arg stdout_m "$stdout_m" \
            --arg stderr_m "$stderr_m" \
            --arg exit_m "$exit_m" \
            '{
              run_id: $run_id, vector_id: $vid, category: $cat, ts_utc: $ts,
              current:  { stdout_b64: $cur_stdout_b64, stderr_b64: $cur_stderr_b64, exit: $cur_exit },
              baseline: { stdout_b64: $base_stdout_b64, stderr_b64: $base_stderr_b64, exit: $base_exit },
              match: { stdout: ($stdout_m == "true"), stderr: ($stderr_m == "true"), exit: ($exit_m == "true") }
            }' >> "$_diff_tmp"
        cat "$_diff_tmp" >> "$DIFF_LOG_PATH"
        rm -f "$_diff_tmp"
        echo "differential.bats: WARN: flock missing — used non-locked atomic-cat append (single-worker safe)" >&2
        return 0
    fi

    local lock="${DIFF_LOG_PATH}.lock"
    (
        flock -x 9
        jq -cn \
            --arg run_id "$run_id" \
            --arg vid "$vid" \
            --arg cat "$category" \
            --arg ts "$ts_utc" \
            --arg cur_stdout_b64 "$cur_stdout_b64" \
            --arg cur_stderr_b64 "$cur_stderr_b64" \
            --argjson cur_exit "$cur_exit" \
            --arg base_stdout_b64 "$base_stdout_b64" \
            --arg base_stderr_b64 "$base_stderr_b64" \
            --argjson base_exit "$base_exit" \
            --arg stdout_m "$stdout_m" \
            --arg stderr_m "$stderr_m" \
            --arg exit_m "$exit_m" \
            '{
              run_id: $run_id,
              vector_id: $vid,
              category: $cat,
              ts_utc: $ts,
              current:  { stdout_b64: $cur_stdout_b64, stderr_b64: $cur_stderr_b64, exit: $cur_exit },
              baseline: { stdout_b64: $base_stdout_b64, stderr_b64: $base_stderr_b64, exit: $base_exit },
              match: { stdout: ($stdout_m == "true"), stderr: ($stderr_m == "true"), exit: ($exit_m == "true") }
            }' >> "$DIFF_LOG_PATH"
    ) 9>"$lock"
}
