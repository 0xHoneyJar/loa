#!/usr/bin/env bash
# tests/red-team/jailbreak/lib/corpus_loader.sh — cycle-100 T1.2
#
# JSONL corpus discovery + schema validation + iteration API.
# Source-only contract: defines functions and emits no top-level side effects.
#
#   source tests/red-team/jailbreak/lib/corpus_loader.sh
#   corpus_validate_all       # schema-validate every line; exit non-zero on any error
#   corpus_iter_active <cat>  # emit one canonical JSON per active vector to stdout
#   corpus_get_field <id> <f> # print field value for vector_id; exit 1 if unknown
#   corpus_count_by_status    # active=N\tsuperseded=M\tsuppressed=K
#
# CLI shim: `bash corpus_loader.sh validate-all` runs `corpus_validate_all` for
# CI usage (see SDD §4.8.3 step "Schema validate corpus").
#
# Determinism: iteration order is sorted ASC by vector_id under LC_ALL=C
# (Flatline IMP-001). JSONL `^\s*#` comment lines are stripped before jq
# parsing (Flatline IMP-004).

# Refuse to run under `set -u` if anything in here resolves an unset var; we
# do NOT enable strict mode at source-time because callers (bats) may have
# their own settings, but every function below pins LC_ALL/LANG locally.

# Path resolution: derive once at source time; all functions reuse.
_CORPUS_LOADER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CORPUS_LOADER_TREE_DIR="$(cd "${_CORPUS_LOADER_LIB_DIR}/.." && pwd)"
_CORPUS_LOADER_REPO_ROOT="$(cd "${_CORPUS_LOADER_LIB_DIR}/../../../.." && pwd)"

# Test-mode gate (cycle-098 L4/L6/L7 dual-condition pattern).
_corpus_test_mode_active() {
    [[ "${LOA_JAILBREAK_TEST_MODE:-0}" != "1" ]] && return 1
    [[ -n "${BATS_TEST_FILENAME:-}" || -n "${BATS_VERSION:-}" || -n "${PYTEST_CURRENT_TEST:-}" ]]
}
_corpus_resolve_override() {
    local var_name="$1" default_value="$2" override="${3:-}"
    if [[ -z "$override" ]]; then
        printf '%s' "$default_value"
        return
    fi
    if _corpus_test_mode_active; then
        printf '%s' "$override"
        return
    fi
    echo "corpus_loader: WARNING: ${var_name} ignored outside test mode (set LOA_JAILBREAK_TEST_MODE=1 + bats/pytest marker)" >&2
    printf '%s' "$default_value"
}

_CORPUS_LOADER_SCHEMA="$(_corpus_resolve_override "LOA_JAILBREAK_VECTOR_SCHEMA" "${_CORPUS_LOADER_REPO_ROOT}/.claude/data/trajectory-schemas/jailbreak-vector.schema.json" "${LOA_JAILBREAK_VECTOR_SCHEMA:-}")"
_CORPUS_LOADER_CORPUS_DIR="$(_corpus_resolve_override "LOA_JAILBREAK_CORPUS_DIR" "${_CORPUS_LOADER_TREE_DIR}/corpus" "${LOA_JAILBREAK_CORPUS_DIR:-}")"

# Strip JSONL comment lines (`^\s*#`). Emits stripped JSONL to stdout.
# Idempotent on already-clean input.
_corpus_strip_comments() {
    local file="$1"
    # `grep -vE` returns exit 1 when there are no non-matching lines (i.e.,
    # entirely comment file); we treat that as empty stdout, exit 0.
    grep -vE '^[[:space:]]*(#|$)' "$file" || [[ $? -eq 1 ]]
}

# Validate one JSON instance against the vector schema.
# Stdin = JSON object. Stdout = empty on success, error text on failure.
# Returns 0 on valid, non-zero on invalid.
_corpus_validate_one() {
    local schema="${_CORPUS_LOADER_SCHEMA}"
    if command -v ajv >/dev/null 2>&1; then
        # Use ajv if available; --spec=draft2020 matches our schema's $schema URL.
        local instance
        instance="$(cat)"
        local out
        if out="$(printf '%s' "$instance" | ajv validate -s "$schema" -d /dev/stdin --spec=draft2020 2>&1)"; then
            return 0
        fi
        echo "$out"
        return 1
    fi
    # Fallback: python jsonschema (cycle-098 CC-11 idiom). Read instance from
    # stdin via /dev/stdin (heredoc occupies python's own stdin via `-`).
    local instance_str
    instance_str="$(cat)"
    LOA_VALIDATE_SCHEMA="$schema" LOA_VALIDATE_INSTANCE="$instance_str" python3 -c '
import json, os, sys
try:
    from jsonschema import Draft202012Validator
except ImportError:
    print("python jsonschema 4.x not available", file=sys.stderr)
    sys.exit(2)
with open(os.environ["LOA_VALIDATE_SCHEMA"]) as f:
    schema = json.load(f)
try:
    instance = json.loads(os.environ["LOA_VALIDATE_INSTANCE"])
except json.JSONDecodeError as e:
    print(f"json parse: {e}")
    sys.exit(1)
v = Draft202012Validator(schema)
errs = list(v.iter_errors(instance))
if errs:
    for e in errs:
        path = "/".join(str(p) for p in e.path) or "<root>"
        print(f"{path}: {e.message}")
    sys.exit(1)
'
}

# Walk every corpus/*.jsonl line; schema-validate each; emit
# `<file>:<line_no>:<vector_id>:<error>` to stderr on failure; exit non-zero
# on any failure or duplicate vector_id.
corpus_validate_all() {
    LC_ALL=C
    local schema="${_CORPUS_LOADER_SCHEMA}"
    if [[ ! -f "$schema" ]]; then
        echo "corpus_loader: schema not found: $schema" >&2
        return 2
    fi
    if [[ ! -d "$_CORPUS_LOADER_CORPUS_DIR" ]]; then
        # Empty corpus dir is acceptable (used by apparatus tests).
        return 0
    fi
    local n_errors=0
    declare -A seen_ids=()
    local file lineno line stripped vector_id err

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        lineno=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            lineno=$((lineno + 1))
            # Strip comment / blank lines.
            if [[ "$line" =~ ^[[:space:]]*(#|$) ]]; then
                continue
            fi
            # Validate JSON parses to object.
            if ! printf '%s' "$line" | jq -e 'type=="object"' >/dev/null 2>&1; then
                echo "${file}:${lineno}:?:JSON parse error or not an object" >&2
                n_errors=$((n_errors + 1))
                continue
            fi
            vector_id="$(printf '%s' "$line" | jq -r '.vector_id // "?"')"
            if err="$(printf '%s' "$line" | _corpus_validate_one)"; then
                :
            else
                # err is the validator output; collapse newlines for grep-friendliness.
                local err_one_line
                err_one_line="$(printf '%s' "$err" | tr '\n' ' ' | tr -s ' ')"
                echo "${file}:${lineno}:${vector_id}:${err_one_line}" >&2
                n_errors=$((n_errors + 1))
                continue
            fi
            # Duplicate detection.
            if [[ -n "${seen_ids[$vector_id]:-}" ]]; then
                echo "${file}:${lineno}:${vector_id}:duplicate vector_id (also at ${seen_ids[$vector_id]})" >&2
                n_errors=$((n_errors + 1))
            else
                seen_ids[$vector_id]="${file}:${lineno}"
            fi
        done < "$file"
    done < <(find "$_CORPUS_LOADER_CORPUS_DIR" -maxdepth 1 -type f -name '*.jsonl' | LC_ALL=C sort)

    if [[ $n_errors -gt 0 ]]; then
        echo "corpus_loader: ${n_errors} validation error(s)" >&2
        return 1
    fi
    return 0
}

# Emit canonical JSON for active vectors filtered by category (empty = all).
# Sorted ASC by vector_id under LC_ALL=C.
corpus_iter_active() {
    LC_ALL=C
    local cat="${1:-}"
    if [[ ! -d "$_CORPUS_LOADER_CORPUS_DIR" ]]; then
        return 0
    fi
    local jq_filter='.status=="active"'
    if [[ -n "$cat" ]]; then
        jq_filter='.status=="active" and .category==$cat'
    fi
    # Sprint-3 BB iter-1 F-002 closure: capture jq stderr + exit so a
    # corrupted JSONL line that escapes validate-all (or callers that skip
    # validate-all) cannot silently produce partial output. The previous
    # `2>/dev/null || true` swallowed the parse error and the consumer saw
    # fewer vectors with rc=0 — the canonical vacuously-green class this
    # corpus exists to defeat. We use a tmpfile sentinel because the loop
    # runs in a subshell on the LHS of a pipe (variable assignments don't
    # propagate back to the caller in that shape).
    local _jq_failed_flag
    _jq_failed_flag="$(mktemp -t "corpus-iter-jq-failed-XXXXXX")"
    local _jq_stderr
    _jq_stderr="$(mktemp -t "corpus-iter-jq-stderr-XXXXXX")"
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        if ! _corpus_strip_comments "$file" | jq -c --arg cat "$cat" \
                "select(${jq_filter})" 2>>"$_jq_stderr"; then
            : > "$_jq_failed_flag.set"
            echo "corpus_loader: jq parse error in ${file}; refusing partial output" >&2
        fi
    done < <(find "$_CORPUS_LOADER_CORPUS_DIR" -maxdepth 1 -type f -name '*.jsonl' | LC_ALL=C sort) \
    | jq -c -s 'sort_by(.vector_id) | .[]'
    if [[ -f "${_jq_failed_flag}.set" ]]; then
        if [[ -s "$_jq_stderr" ]]; then
            cat "$_jq_stderr" >&2
        fi
        rm -f "$_jq_failed_flag" "${_jq_failed_flag}.set" "$_jq_stderr"
        return 1
    fi
    rm -f "$_jq_failed_flag" "$_jq_stderr"
}

# Print one field of one vector. Exit 1 if vector_id unknown.
corpus_get_field() {
    LC_ALL=C
    local id="$1" field="$2"
    if [[ ! -d "$_CORPUS_LOADER_CORPUS_DIR" ]]; then
        echo "corpus_loader: corpus dir absent: $_CORPUS_LOADER_CORPUS_DIR" >&2
        return 1
    fi
    local found
    found="$(
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            _corpus_strip_comments "$file" | jq -r --arg id "$id" --arg field "$field" \
                'select(.vector_id==$id) | .[$field] // empty' 2>/dev/null || true
        done < <(find "$_CORPUS_LOADER_CORPUS_DIR" -maxdepth 1 -type f -name '*.jsonl')
    )"
    if [[ -z "$found" ]]; then
        echo "corpus_loader: vector_id not found: $id" >&2
        return 1
    fi
    printf '%s' "$found"
    echo
}

# Tab-separated tally of statuses to stdout.
corpus_count_by_status() {
    LC_ALL=C
    local active=0 superseded=0 suppressed=0
    if [[ -d "$_CORPUS_LOADER_CORPUS_DIR" ]]; then
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            local s
            s="$(_corpus_strip_comments "$file" | jq -r '.status' 2>/dev/null || true)"
            while IFS= read -r status; do
                case "$status" in
                    active) active=$((active + 1)) ;;
                    superseded) superseded=$((superseded + 1)) ;;
                    suppressed) suppressed=$((suppressed + 1)) ;;
                esac
            done <<< "$s"
        done < <(find "$_CORPUS_LOADER_CORPUS_DIR" -maxdepth 1 -type f -name '*.jsonl')
    fi
    printf 'active=%d\tsuperseded=%d\tsuppressed=%d\n' "$active" "$superseded" "$suppressed"
}

# CLI dispatch when invoked as a script (`bash corpus_loader.sh validate-all`).
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        validate-all) corpus_validate_all ;;
        iter-active)  corpus_iter_active "${2:-}" ;;
        get-field)    corpus_get_field "${2:-}" "${3:-}" ;;
        count)        corpus_count_by_status ;;
        *) echo "Usage: $0 {validate-all|iter-active [<category>]|get-field <id> <field>|count}" >&2; exit 2 ;;
    esac
fi
