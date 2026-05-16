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

# bug-898 SEC-001 v4 — positive allowlist of key names load_env_file will
# export. Anything NOT matching at least one of these patterns is rejected
# (warn-and-continue). This is the architecturally clean answer to the
# v1-v3 denylist whack-a-mole. Patterns are bash glob (`*` wildcards).
#
# Adding a key: append the literal name OR a pattern. The allowlist is
# intentionally narrow — extend it deliberately, with rationale, and
# prefer parent-process-set env vars for project-local keys when possible.
_LOA_ENV_LOADER_ALLOWLIST=(
    # Provider API auth — covers most LLM providers via suffix pattern
    API_KEY                        # bare form (used by some scripts / generic tooling)
    '*_API_KEY'                    # ANTHROPIC_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY, GEMINI_API_KEY, ...
    '*_AUTH_TOKEN'                 # ANTHROPIC_AUTH_TOKEN (Bedrock-style bearer)
    '*_BASE_URL'                   # ANTHROPIC_BASE_URL, OPENAI_BASE_URL, etc. (operator-configurable endpoint)

    # Anthropic / OpenAI / Google specific (explicit — pattern-match would
    # be too loose). Each name is the exact env var their SDKs honor.
    ANTHROPIC_API_KEY
    ANTHROPIC_AUTH_TOKEN
    ANTHROPIC_BASE_URL
    ANTHROPIC_BEDROCK_BASE_URL
    ANTHROPIC_VERTEX_BASE_URL
    OPENAI_API_KEY
    OPENAI_BASE_URL
    OPENAI_ORG_ID
    OPENAI_PROJECT_ID
    GOOGLE_API_KEY
    GEMINI_API_KEY
    GOOGLE_APPLICATION_CREDENTIALS

    # AWS / Bedrock (cycle-096 provider)
    AWS_ACCESS_KEY_ID
    AWS_SECRET_ACCESS_KEY
    AWS_SESSION_TOKEN
    AWS_REGION
    AWS_DEFAULT_REGION
    AWS_PROFILE
    'BEDROCK_*'                    # cycle-096 Bedrock-specific config

    # Project-namespaced (Loa + HoneyJar org)
    'LOA_*'
    'HONEYJAR_*'

    # GitHub (used by `gh` CLI invocations inside orchestrator)
    GITHUB_TOKEN
    GH_TOKEN

    # Test-mode toggles (bats fixtures set these to gate test paths)
    'LOA_*_TEST_MODE'              # already matched by LOA_*; explicit for clarity
)

_env_loader_key_is_allowlisted() {
    # Returns 0 (true) if the given key matches at least one pattern in
    # _LOA_ENV_LOADER_ALLOWLIST. Bash glob match — pattern need not match
    # the whole string, but in our use the patterns are anchored shapes.
    local key="$1"
    local pattern
    # shellcheck disable=SC2068
    for pattern in ${_LOA_ENV_LOADER_ALLOWLIST[@]}; do
        # shellcheck disable=SC2053
        if [[ "$key" == $pattern ]]; then
            return 0
        fi
    done
    return 1
}

_env_loader_reject_non_allowlisted_key() {
    # bug-898 SEC-001 v4: shared rejection helper for keys outside the
    # allowlist. The allowlist replaces the v1-v3 denylist that BB kept
    # finding bypasses around (PATH, SHELLOPTS, GIT_CONFIG_COUNT,
    # lowercase npm_config_*, etc.). Operator-controlled extension lives
    # in _LOA_ENV_LOADER_ALLOWLIST above this function.
    local key="$1" file="$2" lineno="$3"
    printf 'WARN: env-loader: rejected key %s in %s line %d (not in positive allowlist — see _LOA_ENV_LOADER_ALLOWLIST in env-loader.sh to extend)\n' \
        "$key" "$file" "$lineno" >&2
}

load_env_file() {
    # BB #912 v3 REL-001: the loader's contract is "best-effort parse;
    # NEVER abort the caller". We handle per-line failures internally
    # via warn-and-continue; the caller's `set -e` would otherwise abort
    # the orchestrator on the first hostile/readonly value. Save the
    # caller's errexit state, disable it for the function body, restore
    # before return.
    local _se_was_set=0
    case $- in *e*) _se_was_set=1; set +e ;; esac

    local file="$1"
    local line key value
    local lineno=0

    if [[ ! -f "$file" ]]; then
        [[ $_se_was_set -eq 1 ]] && set -e
        return 0
    fi

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

        # bug-898 SEC-001 (BB #912 v4 architectural fix — positive allowlist).
        #
        # The v1-v3 denylist approach was unwinnable whack-a-mole — every
        # BB iteration kept finding more exec-hook namespaces (PATH,
        # SHELLOPTS, GIT_CONFIG_COUNT, lowercase npm_config_*, etc.). BB
        # explicitly recommended positive allowlist three iterations in a
        # row. Switched at v4: the loader now exports ONLY keys whose
        # name matches one of the documented allowlist patterns below;
        # everything else is rejected with a WARN regardless of value
        # shape. Operator must set non-allowlisted keys via the parent
        # process or extend the allowlist in this file.
        #
        # Allowlist patterns (bash extended glob, case-sensitive):
        if ! _env_loader_key_is_allowlisted "$key"; then
            _env_loader_reject_non_allowlisted_key "$key" "$file" "$lineno"
            continue
        fi

        # BB #912 v2 COR-001 fix: strip inline trailing comments on
        # UNQUOTED values. A common dotenv shape is `KEY=value # note`;
        # without this, the comment text would be exported as part of
        # the value (silent corruption of API keys / config values). For
        # quoted values, comments after the closing quote are stripped;
        # comments inside the quoted region are preserved verbatim (they
        # may legitimately appear in the value).
        if [[ ! "$value" =~ ^[\"\'] ]]; then
            # Unquoted: drop everything from the first ` #` onward.
            # Note the leading space is required — `KEY=foo#bar` is NOT
            # a comment (legitimate "#" in value), only `KEY=foo # bar` is.
            if [[ "$value" =~ ^([^[:space:]#].*[^[:space:]])[[:space:]]+#.*$ ]]; then
                value="${BASH_REMATCH[1]}"
            elif [[ "$value" =~ ^[[:space:]]+#.*$ ]]; then
                # Pure-comment value (KEY=  # only): treat as empty value.
                value=""
            fi
            # Strip remaining trailing whitespace.
            value="${value%"${value##*[![:space:]]}"}"
        elif [[ "$value" =~ ^(\"[^\"]*\")[[:space:]]+#.*$ ]] \
          || [[ "$value" =~ ^(\'[^\']*\')[[:space:]]+#.*$ ]]; then
            # Quoted value followed by ` # comment` — drop the comment,
            # keep the quoted region for the regex below to parse.
            value="${BASH_REMATCH[1]}"
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

        # BB #912 v3 REL-001 (MEDIUM, 0.85 conf): `export "$key=$value"`
        # was unchecked. Under `set -e` in a sourcing caller, any export
        # failure (readonly user variable, restricted shell namespace,
        # quota exhaustion) would propagate and abort the orchestrator
        # mid-run — turning the loader into a DoS vector. Wrap the export
        # so failures warn + continue instead of crashing the parent.
        # (The denylist above already rejects bash's built-in readonly
        # set; this catches user-readonly vars or edge-case shell states.)
        #
        # Form: use `|| { ...; continue; }` rather than `if ! cmd; then`.
        # Per bash man page: "The shell does not exit if the command that
        # fails is ... part of any command executed in a && or || list
        # except the command following the final && or ||". The `if !`
        # form trips `set -e` in some bash versions; this form is
        # documented-safe.
        # shellcheck disable=SC2163
        export "$key=$value" 2>/dev/null || {
            printf 'WARN: env-loader: export failed for %s in %s line %d (readonly variable, restricted namespace, or shell-state conflict — skipping)\n' \
                "$key" "$file" "$lineno" >&2
            continue
        }
    done < "$file"

    # Restore caller's errexit state (matched at function entry).
    [[ $_se_was_set -eq 1 ]] && set -e
    return 0
}
