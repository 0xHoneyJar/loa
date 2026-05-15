#!/usr/bin/env bash
# =============================================================================
# .claude/scripts/lib/env-loader.sh
#
# Safe KEY=VALUE parser replacing `set -a; source .env; set +a`.
#
# Issue #898: the legacy pattern executes ANY bash inside .env files,
# including `$(...)`, backticks, and chained commands. A hostile or
# carelessly-edited .env at the repo root becomes arbitrary code
# execution as the Loa orchestrator process. This loader parses lines
# as `KEY=VALUE` only — never executes the value.
#
# Public API:
#   load_env_file <path>
#     Reads <path> line-by-line, exports each well-formed KEY=VALUE
#     into the current shell. Silently no-ops if the file is absent
#     (matches `[[ -f .env ]] && source .env` semantics).
#
# Trust model:
#   - .env / .env.local remain UNTRUSTED. The loader refuses to expand
#     `$(...)`, backticks, or unquoted shell-meta chains.
#   - Single-quoted values pass through raw (no escape expansion).
#   - Double-quoted values expand ONLY \n \t \\ \" — NEVER $VAR / $(...).
#   - Bare values (no quotes) are accepted if they pass the safety gate.
#
# Used by:
#   - .claude/scripts/flatline-orchestrator.sh
#   - .claude/skills/bridgebuilder-review/resources/entry.sh
# =============================================================================

# Guard against double-source.
if [[ "${_LOA_ENV_LOADER_SOURCED:-0}" == "1" ]]; then
    return 0
fi
_LOA_ENV_LOADER_SOURCED=1

load_env_file() {
    local file="$1"
    local line key value
    local lineno=0

    [[ -f "$file" ]] || return 0

    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))

        # Strip trailing CR (CRLF tolerance).
        line="${line%$'\r'}"

        # Skip blank and comment lines.
        [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Optional `export ` prefix — drop it.
        if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+(.*)$ ]]; then
            line="${BASH_REMATCH[1]}"
        fi

        # Strip leading whitespace on the KEY side.
        line="${line#"${line%%[![:space:]]*}"}"

        # Parse KEY=VALUE.
        if [[ ! "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            printf 'WARN: env-loader: malformed line %d in %s (skipped)\n' \
                "$lineno" "$file" >&2
            continue
        fi
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"

        # Strip trailing whitespace from unquoted values (but preserve it
        # inside quoted values).
        if [[ ! "$value" =~ ^[\"\'] ]]; then
            value="${value%"${value##*[![:space:]]}"}"
        fi

        # Quoted-value handling.
        if [[ "$value" =~ ^\"(.*)\"$ ]]; then
            # Double-quoted: expand a limited escape set ONLY.
            value="${BASH_REMATCH[1]}"
            value="${value//\\n/$'\n'}"
            value="${value//\\t/$'\t'}"
            value="${value//\\\"/\"}"
            value="${value//\\\\/\\}"
        elif [[ "$value" =~ ^\'(.*)\'$ ]]; then
            # Single-quoted: raw, no escape expansion.
            value="${BASH_REMATCH[1]}"
        else
            # Unquoted: explicit reject of dangerous shell metacharacters.
            # `set -a; source` would have executed all of these; we won't.
            if [[ "$value" == *'$('* ]] \
               || [[ "$value" == *'`'* ]] \
               || [[ "$value" == *';'* ]] \
               || [[ "$value" == *'&&'* ]] \
               || [[ "$value" == *'||'* ]] \
               || [[ "$value" == *'>'* ]] \
               || [[ "$value" == *'<'* ]] \
               || [[ "$value" == *'|'* ]]; then
                printf 'WARN: env-loader: rejected suspicious value for %s in %s line %d (contains shell metacharacters)\n' \
                    "$key" "$file" "$lineno" >&2
                continue
            fi
        fi

        # shellcheck disable=SC2163
        export "$key=$value"
    done < "$file"
}
