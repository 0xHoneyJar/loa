#!/usr/bin/env bash
# =============================================================================
# endpoint-validator.sh — bash wrapper per cycle-099 SDD §1.9.1.
#
# The Python canonical at .claude/scripts/lib/endpoint-validator.py is the
# sole implementation of the SDD §6.5 8-step URL canonicalization pipeline.
# This wrapper delegates to it via subprocess so bash callers (red-team
# adapter, model-adapter.sh) get byte-identical validation outcomes.
#
# Rationale: a pure-bash port of urllib.parse + idna + ipaddress is brittle
# (locale-sensitive regex, missing edge cases, BSD/GNU divergence). Using
# Python via subprocess delegates to the canonical with one fork+exec per
# validation; that's cheap enough for config-load-time validation, and the
# cross-runtime parity test asserts byte-equal output between Python direct
# and bash wrapper.
#
# Usage:
#   As library:
#     source .claude/scripts/lib/endpoint-validator.sh
#     endpoint_validator__check --json --allowlist <path> <url>
#   As filter:
#     bash .claude/scripts/lib/endpoint-validator.sh --json --allowlist X URL
#
# Hardening (cypherpunk MEDIUM 3 + 4):
#   - argv smuggling: any argument that LOOKS like a flag but follows the
#     designated URL slot is treated as opaque positional data via the
#     argparse `--` separator. Without this, an attacker URL value of
#     `--allowlist=/dev/stdin` would clobber the operator's allowlist arg.
#   - symlink swap: BASH_SOURCE-relative path resolution follows symlinks
#     by default, letting an attacker who controls a symlink target
#     redirect to a fake validator. We resolve with `realpath -e` and
#     bail if the resolved path is outside the project's lib directory.
# =============================================================================

set -euo pipefail

# Resolve the Python interpreter. Prefer the project's .venv (which has idna
# pinned at the version the canonical was tested against), else fall back to
# system python3. Operators should run `python3 -m pip install idna>=3.6`
# in their .venv before relying on this wrapper.
_endpoint_validator__python() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    local repo_root
    repo_root="$(cd "$script_dir/../../.." && pwd -P)"
    if [[ -x "$repo_root/.venv/bin/python" ]]; then
        printf '%s' "$repo_root/.venv/bin/python"
    elif command -v python3 >/dev/null 2>&1; then
        command -v python3
    else
        printf ''
    fi
}

# Resolve the canonical Python script path. Refuses symlinks: the resolved
# path MUST live under .claude/scripts/lib/ inside the same repo as this
# wrapper. Returns 0 + stdout on success, 1 on tamper detection.
_endpoint_validator__resolve_canonical() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    local resolved
    if command -v realpath >/dev/null 2>&1; then
        resolved="$(realpath -e "$script_dir/endpoint-validator.py" 2>/dev/null || true)"
    else
        resolved="$script_dir/endpoint-validator.py"
    fi
    if [[ -z "$resolved" ]] || [[ ! -f "$resolved" ]]; then
        printf '[ENDPOINT-VALIDATOR-MISSING] %s/endpoint-validator.py not found\n' \
            "$script_dir" >&2
        return 1
    fi
    # Guard: the resolved path MUST live under script_dir (same physical lib/).
    case "$resolved" in
        "$script_dir"/*) ;;
        *)
            printf '[ENDPOINT-VALIDATOR-SYMLINK-OUT-OF-TREE] %s\n' "$resolved" >&2
            return 1
            ;;
    esac
    printf '%s' "$resolved"
}

# Library entrypoint. Forwards argv to the Python canonical; preserves stdout,
# stderr, and exit code so callers see identical behavior to invoking the
# Python module directly.
#
# argv contract: callers MUST pass flags first and the URL last, e.g.
#   endpoint_validator__check --json --allowlist X URL
# We force a `--` separator before the URL so argparse can't be smuggled by
# an attacker URL that starts with `-`.
endpoint_validator__check() {
    local py
    py="$(_endpoint_validator__python)"
    if [[ -z "$py" ]]; then
        printf '[ENDPOINT-VALIDATOR-NO-PYTHON] python3 not found on PATH\n' >&2
        return 64  # EX_USAGE
    fi
    local validator
    if ! validator="$(_endpoint_validator__resolve_canonical)"; then
        return 64
    fi
    if [[ $# -lt 1 ]]; then
        # No argv at all → forward to Python so argparse emits its usage line.
        "$py" -I "$validator"
        return $?
    fi
    # Split argv: everything except the LAST argument is forwarded as flags,
    # the last argument is the URL slot and goes after `--` so argparse can
    # never reinterpret it as an option (cypherpunk M3).
    local last_idx=$(( $# - 1 ))
    local url="${!#}"
    local flags=("${@:1:$last_idx}")
    # `python -I` enables isolated mode (ignore PYTHON* env vars + user site-
    # packages) — defends against PYTHONPATH-injected interpreter modules.
    "$py" -I "$validator" "${flags[@]}" -- "$url"
}

# =============================================================================
# endpoint_validator__guarded_curl — SSRF-safe curl wrapper (sprint-1E.c.3.a)
# =============================================================================
#
# Validate a URL against the per-caller allowlist via the Python canonical;
# only if it accepts, exec curl with hardened defaults. Caller passes flags
# explicitly because curl invocations vary widely across the codebase.
#
# Contract:
#   endpoint_validator__guarded_curl --allowlist <PATH> [--config-auth <FILE>] \
#                                    --url <URL> [curl_args...]
#
#   Both --allowlist and --url MUST be supplied via these named flags so we
#   never have to disambiguate the URL position from miscellaneous curl args
#   (anthropic-oracle.sh-style `curl ARGS URL -o FILE` post-URL flags).
#
#   --config-auth <FILE> (optional): path to a curl-config file containing
#   ONLY `header = "..."` lines (plus comments / blanks). The wrapper inspects
#   the file and REJECTS it if any other directive is present (url=, next=,
#   output=, upload-file, --next, etc.) — defense against `curl --config`
#   URL-smuggling (cypherpunk CRITICAL on sprint-1E.c.3.a). Caller-passed
#   `--config` / `-K` / `--next` / `-:` are blocked outright; use this flag
#   instead for auth-tempfile injection.
#
# Hardened curl defaults (always added before caller-supplied args):
#   --proto =https        Refuse to send non-https requests (defense-in-depth;
#                         the validator already enforces https scheme but this
#                         catches a curl alias / config-file override).
#   --proto-redir =https  Refuse to follow redirects to non-https. Without
#                         this, `curl -L` would happily downgrade to http on
#                         a redirect even though the initial scheme is https.
#   --max-redirs 10       Bound redirect-chain length to match the Python
#                         validate_redirect_chain default (RFC 7231 §6.4 +
#                         sprint-1E.c.2).
#
# Notes on scope:
#   - This wrapper validates the INITIAL URL only. Per-hop redirect-target
#     validation (DNS rebinding lock, same-host, same-port) lives in the
#     Python canonical and is not yet wired to curl's redirect handling.
#     If a caller follows redirects (`-L`), `--proto-redir =https` plus
#     `--max-redirs 10` are the practical defenses. Full per-hop validation
#     would require `--no-location` + manual Location parsing, which would
#     break callers that depend on -L.
#   - Allowlist path is restricted to .claude/scripts/lib/allowlists/ via
#     realpath -e canonicalization (cypherpunk HIGH on sprint-1E.c.3.a).
#     Callers wanting a custom allowlist must drop a JSON file in that
#     directory, which is auditable via git diff. No env-var escape hatch
#     in production; tests bypass via LOA_ENDPOINT_VALIDATOR_TEST_ALLOWLIST_DIR
#     gated behind LOA_ENDPOINT_VALIDATOR_TEST_MODE=1.
#   - Argv layout (gating order):
#       --allowlist <path>  must come before --url
#       --config-auth <p>   optional; before --url
#       --url <url>         must come before any caller-supplied curl args
#       The wrapper REJECTS unknown leading flags before --url so an attacker
#       URL cannot smuggle flags into our gate (e.g. `--allowlist=/dev/stdin`).
#
# Exit codes:
#   0   acceptance + curl success (curl's exit forwarded)
#   2-N curl native exit code (forwarded)
#   64  EX_USAGE — bad argv to wrapper (missing --allowlist, missing --url,
#       allowlist out of tree, --config-auth file invalid, smuggling flag
#       in caller args, etc.)
#   78  EX_CONFIG — URL rejected by validator
endpoint_validator__guarded_curl() {
    local allowlist="" url="" config_auth=""
    # Phase 1: parse our own flags. Stop at the first arg that isn't ours.
    # We intentionally do NOT support intermixed wrapper/curl flags — once
    # we've consumed --allowlist / --config-auth / --url, every remaining arg
    # passes through to curl untouched.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --allowlist)
                if [[ $# -lt 2 ]]; then
                    printf '[ENDPOINT-VALIDATOR-USAGE] --allowlist requires a path argument\n' >&2
                    return 64
                fi
                allowlist="$2"; shift 2
                ;;
            --allowlist=*)
                allowlist="${1#--allowlist=}"; shift
                ;;
            --config-auth)
                if [[ $# -lt 2 ]]; then
                    printf '[ENDPOINT-VALIDATOR-USAGE] --config-auth requires a path argument\n' >&2
                    return 64
                fi
                config_auth="$2"; shift 2
                ;;
            --config-auth=*)
                config_auth="${1#--config-auth=}"; shift
                ;;
            --url)
                if [[ $# -lt 2 ]]; then
                    printf '[ENDPOINT-VALIDATOR-USAGE] --url requires a URL argument\n' >&2
                    return 64
                fi
                url="$2"; shift 2
                # --url is the LAST wrapper flag; everything after passes to curl.
                break
                ;;
            --url=*)
                url="${1#--url=}"; shift
                break
                ;;
            *)
                printf '[ENDPOINT-VALIDATOR-USAGE] unexpected arg before --url: %q (allowed wrapper flags: --allowlist, --config-auth, --url)\n' "$1" >&2
                return 64
                ;;
        esac
    done
    if [[ -z "$allowlist" ]]; then
        printf '[ENDPOINT-VALIDATOR-USAGE] --allowlist <path> is required\n' >&2
        return 64
    fi
    if [[ ! -f "$allowlist" ]]; then
        printf '[ENDPOINT-VALIDATOR-USAGE] allowlist file not found: %s\n' "$allowlist" >&2
        return 64
    fi
    if [[ -z "$url" ]]; then
        printf '[ENDPOINT-VALIDATOR-USAGE] --url <url> is required\n' >&2
        return 64
    fi

    # Phase 1.5: confine allowlist path to the canonical tree so a hostile env
    # var (e.g., LOA_PROBE_PROVIDERS_ALLOWLIST=/tmp/wide-open.json) cannot
    # substitute a permissive allowlist for the narrow per-caller one
    # (cypherpunk HIGH). Test mode opts out via LOA_ENDPOINT_VALIDATOR_TEST_MODE=1
    # + LOA_ENDPOINT_VALIDATOR_TEST_ALLOWLIST_DIR (mirrors cycle-098 L3 pattern).
    local lib_dir allowlists_root
    lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    allowlists_root="$lib_dir/allowlists"
    local allowlist_resolved
    if command -v realpath >/dev/null 2>&1; then
        allowlist_resolved="$(realpath -e "$allowlist" 2>/dev/null || true)"
    fi
    if [[ -z "$allowlist_resolved" ]]; then
        # realpath unavailable — fall back to the literal path. Loses some
        # symlink-confinement strength but keeps the wrapper portable.
        allowlist_resolved="$allowlist"
    fi
    local allowlist_in_tree=0
    case "$allowlist_resolved" in
        "$allowlists_root"/*) allowlist_in_tree=1 ;;
    esac
    if [[ "$allowlist_in_tree" != "1" ]]; then
        if [[ "${LOA_ENDPOINT_VALIDATOR_TEST_MODE:-0}" == "1" ]] \
            && [[ -n "${LOA_ENDPOINT_VALIDATOR_TEST_ALLOWLIST_DIR:-}" ]]; then
            local test_dir
            test_dir="$(cd "$LOA_ENDPOINT_VALIDATOR_TEST_ALLOWLIST_DIR" 2>/dev/null && pwd -P || true)"
            case "$allowlist_resolved" in
                "$test_dir"/*) allowlist_in_tree=1 ;;
            esac
        fi
    fi
    if [[ "$allowlist_in_tree" != "1" ]]; then
        printf '[ENDPOINT-VALIDATOR-ALLOWLIST-OUT-OF-TREE] allowlist must live under %s/; got: %s\n' \
            "$allowlists_root" "$allowlist_resolved" >&2
        return 64
    fi

    # Phase 1.6: validate --config-auth file content (if supplied). Per spec
    # the file MUST contain only blank/comment lines or `header = "..."`
    # directives. Any url=, next=, output=, upload-file=, write-out=, -K,
    # --next, -: line indicates `curl --config` URL-smuggling and is
    # rejected (cypherpunk CRITICAL).
    if [[ -n "$config_auth" ]]; then
        if [[ ! -f "$config_auth" ]]; then
            printf '[ENDPOINT-VALIDATOR-USAGE] --config-auth file not found: %s\n' "$config_auth" >&2
            return 64
        fi
        if [[ ! -r "$config_auth" ]]; then
            printf '[ENDPOINT-VALIDATOR-USAGE] --config-auth file not readable: %s\n' "$config_auth" >&2
            return 64
        fi
        # Reject CR bytes — they make grep treat the file as one line and
        # could hide a smuggled directive after a CR-only "newline".
        if LC_ALL=C grep -q $'\r' "$config_auth"; then
            printf '[ENDPOINT-VALIDATOR-CONFIG-AUTH-CR-BYTE] CR (0x0D) byte detected in %s — possible smuggling\n' \
                "$config_auth" >&2
            return 64
        fi
        # Per-line gate: only allow blank, comment (#...), or
        # `header = "..."` lines. Anything else fails the contract. The
        # `[^"\\]*` body excludes embedded backslashes (defense-in-depth on
        # top of write_curl_auth_config's sanitizer) and inner quotes.
        local _bad_lines
        _bad_lines="$(LC_ALL=C grep -nvE '^[[:space:]]*(#.*|header[[:space:]]*=[[:space:]]*"[^"\\]*"[[:space:]]*|)$' "$config_auth" || true)"
        if [[ -n "$_bad_lines" ]]; then
            printf '[ENDPOINT-VALIDATOR-CONFIG-AUTH-INVALID] %s contains directives other than `header = "..."` (only header lines + comments/blanks allowed; rejects url=/next=/output= smuggling). Offending lines:\n%s\n' \
                "$config_auth" "$_bad_lines" >&2
            return 64
        fi
    fi

    # Phase 1.7: scan caller args for curl-side smuggling vectors. We do this
    # AFTER URL validation but BEFORE curl exec so a rejected smuggling
    # attempt fails fast without burning a Python subprocess on rejection
    # path. (URL validation must precede this so allowlist/config-auth
    # parse errors don't leak into the smuggling-scan error path.)
    #
    # Vectors covered:
    #   - --config / -K (and all glued forms `--config=path`, `-K=path`,
    #     `-Kpath`): caller-supplied curl-config files can carry url=/next=/
    #     output= directives that smuggle past the allowlist. Caller MUST
    #     use the wrapper's --config-auth flag instead, which content-gates
    #     the file.
    #   - --next / -:: resets curl URL state, allowing a config-supplied
    #     second URL to escape the allowlist via "operation reset".
    #   - Naked positional URLs (`https://...` / `http://...` as a
    #     standalone arg): curl treats unattached positionals as ADDITIONAL
    #     URLs to fetch, alongside our validated --url. A caller passing
    #     `endpoint_validator__guarded_curl ... --url https://valid.com https://evil.com`
    #     would have curl fetch BOTH. Strict reject of any `^https?://`
    #     positional. Note: this is too strict for the rare case of
    #     `--data-urlencode https://x` (URL as flag value) — callers
    #     needing that should base64-encode or use `--data` with a tempfile.
    local _arg
    for _arg in "$@"; do
        case "$_arg" in
            --config|--config=*|-K|-K?*)
                printf '[ENDPOINT-VALIDATOR-CONFIG-FLAG-REJECTED] caller passed %q; use --config-auth (the wrapper inspects it for url=/next= smuggling)\n' "$_arg" >&2
                return 64
                ;;
            --next|-:)
                printf '[ENDPOINT-VALIDATOR-NEXT-FLAG-REJECTED] caller passed %q; --next/-: resets curl URL state and bypasses our allowlist (sprint-1E.c.3.a)\n' "$_arg" >&2
                return 64
                ;;
            [Hh][Tt][Tt][Pp]://*|[Hh][Tt][Tt][Pp][Ss]://*)
                printf '[ENDPOINT-VALIDATOR-POSITIONAL-URL-REJECTED] caller passed URL-shaped arg %q; curl would treat it as an additional URL to fetch, bypassing the allowlist (use --url for THE URL; encode any data-value URLs differently)\n' "$_arg" >&2
                return 64
                ;;
        esac
    done

    # Phase 2: validate the URL via Python canonical. We discard the JSON
    # acceptance line (callers don't need it on stdout) but preserve the
    # rejection JSON on stderr so operators can diagnose policy failures.
    if ! endpoint_validator__check --json --allowlist "$allowlist" "$url" >/dev/null; then
        # Python canonical already wrote the rejection JSON to its stderr.
        # We don't echo a second line — that would muddy the structured log.
        return 78
    fi

    # Phase 3: locate curl. We use `command -v` rather than the unqualified
    # name so a function/alias `curl` defined by a sourcing script can't
    # silently shadow this — we want the real binary. Note: `command -v`
    # still walks PATH; operators with hostile $PATH are out of scope (an
    # attacker who controls $PATH already has shell-level access).
    local curl_bin
    if ! curl_bin="$(command -v curl)"; then
        printf '[ENDPOINT-VALIDATOR-NO-CURL] curl not found on PATH\n' >&2
        return 64
    fi

    # Phase 4: exec with hardened defaults FIRST so caller flags can't
    # override them. curl applies later --proto / --max-redirs values
    # over earlier ones; ordering hardened-first means a caller who
    # explicitly passes `--proto =all` would override us — that's a
    # caller bug we accept (don't pretend to defend against malicious
    # callers in our own codebase). The ordering DOES matter for the
    # naive case where a caller doesn't think about TLS at all.
    #
    # If --config-auth was supplied, the validated config file goes BETWEEN
    # the hardened defaults and caller args, so `--proto =https` wins over
    # any (already-rejected) directives that might still slip through, and
    # caller args can still customize headers/data without surprise.
    local _config_args=()
    if [[ -n "$config_auth" ]]; then
        _config_args=(--config "$config_auth")
    fi
    "$curl_bin" --proto =https --proto-redir =https --max-redirs 10 \
        ${_config_args[@]+"${_config_args[@]}"} \
        "$@" --url "$url"
}

# When invoked as a script (not sourced), forward all argv to the library
# entry. This lets `bash endpoint-validator.sh --json --allowlist X URL` work
# the same as `source endpoint-validator.sh; endpoint_validator__check ...`.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    endpoint_validator__check "$@"
fi
