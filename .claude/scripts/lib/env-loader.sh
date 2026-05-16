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

_env_loader_reject_denylist_key() {
    # bug-898 SEC-001: shared rejection helper for ambient-execution key names.
    # See the case-statement in load_env_file for the full denylist + rationale.
    local key="$1" file="$2" lineno="$3"
    printf 'WARN: env-loader: rejected denylisted key %s in %s line %d (ambient-execution key — sourcing would let an attacker hijack subprocesses regardless of value content)\n' \
        "$key" "$file" "$lineno" >&2
}

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

        # bug-898 SEC-001: key-name denylist for ambient-execution variables.
        # The value-side gate below blocks `$(cmd)` / backticks / `;` chains,
        # but the legacy SHELLSHOCK class (CVE-2014-6271) and adjacent ones
        # exploit dangerous KEY NAMES that turn a plain `KEY=path` assignment
        # into deferred code execution in every child process. BASH_ENV is
        # sourced by every non-interactive bash subprocess at startup;
        # LD_PRELOAD / LD_LIBRARY_PATH inject shared objects; NODE_OPTIONS,
        # PYTHONSTARTUP, PERL5OPT, RUBYOPT, GIT_SSH_COMMAND, GIT_EXEC_PATH
        # all coerce code into otherwise-trusted runtimes.
        # Refuse these key names regardless of value shape.
        case "$key" in
            BASH_ENV|ENV|CDPATH|PROMPT_COMMAND|BASH_FUNC_*|FUNCNEST)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            LD_PRELOAD|LD_LIBRARY_PATH|LD_AUDIT|LD_BIND_NOW|LD_DEBUG)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            DYLD_INSERT_LIBRARIES|DYLD_LIBRARY_PATH|DYLD_FRAMEWORK_PATH|DYLD_FALLBACK_LIBRARY_PATH|DYLD_FALLBACK_FRAMEWORK_PATH)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            NODE_OPTIONS|NODE_PATH)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            PYTHONSTARTUP|PYTHONPATH|PYTHONHOME|PYTHONINSPECT|PYTHONDEBUG|PYTHONUSERBASE)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            PERL5OPT|PERL5LIB|PERL5DB|PERLIO_DEBUG|PERL_UNICODE)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            RUBYOPT|RUBYLIB)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            GIT_SSH_COMMAND|GIT_EXEC_PATH|GIT_DIR|GIT_WORK_TREE|GIT_INDEX_FILE|GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            # BB #912 v2 SEC-001: additional git tool-hook keys that
            # subprocess execution arbitrary binaries: GIT_ASKPASS runs an
            # askpass helper; GIT_EXTERNAL_DIFF/GIT_DIFF_OPTS run a diff
            # driver; GIT_PAGER/PAGER/MANPAGER pipe output through any
            # binary; GIT_EDITOR/EDITOR/VISUAL/SEQUENCE_EDITOR get invoked
            # by interactive git commands (commit, rebase, etc.).
            GIT_ASKPASS|GIT_EXTERNAL_DIFF|GIT_DIFF_OPTS|GIT_PAGER|GIT_EDITOR|GIT_SEQUENCE_EDITOR|GIT_PROXY_COMMAND|GIT_TRACE_SETUP_PROGRAM|GIT_CONFIG_PARAMETERS)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            PAGER|MANPAGER|EDITOR|VISUAL|BROWSER)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            # Compiler / toolchain wrapper hooks — cargo / rustup / cc / make
            # all honor these to swap the underlying compiler / linker /
            # invocation with an arbitrary path supplied at env-load time.
            RUSTC_WRAPPER|RUSTC|RUSTFLAGS|CARGO_HOME|CARGO_TARGET_DIR|CARGO_BUILD_RUSTC|CC|CXX|CPP|LD|AR|AS|NM|RANLIB|MAKE)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            # Node / npm execution-hook keys. NPM_CONFIG_NODE_OPTIONS is
            # the npm-config form of NODE_OPTIONS; npm exposes any
            # `--<key>=<val>` CLI flag as `NPM_CONFIG_<KEY>`, so the
            # safer move is to reject the whole NPM_CONFIG_ family.
            NPM_CONFIG_*)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            SSH_ASKPASS|SUDO_ASKPASS|SSH_AUTH_SOCK)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
            IFS|PS4|HISTFILE|HISTCMD)
                _env_loader_reject_denylist_key "$key" "$file" "$lineno"
                continue ;;
        esac

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

        # shellcheck disable=SC2163
        export "$key=$value"
    done < "$file"
}
