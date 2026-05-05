#!/usr/bin/env bats
# =============================================================================
# tests/integration/cycle099-sprint-1ec3b-migration-smoke.bats
#
# cycle-099 Sprint 1E.c.3.b — bash caller migration smoke tests.
#
# Each migrated script MUST:
#   - source .claude/scripts/lib/endpoint-validator.sh
#   - declare a *_ALLOWLIST constant pointing under .claude/scripts/lib/allowlists/
#   - reach endpoint_validator__guarded_curl from at least one call site
#   - retain bash -n syntax cleanliness
#
# These are GREP-based contract tests, not behavioral E2E. The behavioral
# coverage for the wrapper itself lives in endpoint-validator-guarded-curl.bats
# (54 tests in 1E.c.3.a). This suite catches "did the migration land?" in CI.
#
# Mount-loa.sh has an explicit [ENDPOINT-VALIDATOR-EXEMPT] carve-out (bootstrap
# script — validator isn't on disk yet). Tests confirm the exemption banner
# AND the hardened defaults (--proto =https / --proto-redir =https /
# --max-redirs 10) are in place.
# =============================================================================

setup() {
    SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

    # Sanity: 1E.c.3.a artifacts MUST exist (we depend on them)
    [[ -f "$PROJECT_ROOT/.claude/scripts/lib/endpoint-validator.sh" ]] \
        || skip "endpoint-validator.sh missing (1E.c.3.a not on disk)"
    [[ -d "$PROJECT_ROOT/.claude/scripts/lib/allowlists" ]] \
        || skip "allowlists dir missing"
}

# Helper: assert script $1 sources endpoint-validator.sh AND uses guarded_curl
_assert_migrated() {
    local script="$1"
    local script_path="$PROJECT_ROOT/.claude/scripts/$script"
    [[ -f "$script_path" ]] || {
        printf 'script not found: %s\n' "$script_path" >&2
        return 1
    }
    grep -qE 'source[[:space:]]+.*endpoint-validator\.sh' "$script_path" || {
        printf '%s does NOT source endpoint-validator.sh\n' "$script" >&2
        return 1
    }
    grep -qE 'endpoint_validator__guarded_curl' "$script_path" || {
        printf '%s does NOT call endpoint_validator__guarded_curl\n' "$script" >&2
        return 1
    }
    bash -n "$script_path" || {
        printf '%s has bash -n syntax errors\n' "$script" >&2
        return 1
    }
}

# Helper: assert script $1 declares a *_ALLOWLIST constant pointing to a real file
_assert_has_allowlist_decl() {
    local script="$1"
    local script_path="$PROJECT_ROOT/.claude/scripts/$script"
    grep -qE '_ALLOWLIST="\$\{LOA_[A-Z_]+_ALLOWLIST:-' "$script_path" || {
        printf '%s does NOT declare a *_ALLOWLIST="${LOA_*:-...}" constant\n' "$script" >&2
        return 1
    }
}

# ---------------------------------------------------------------------------
# A — Allowlist fixture files exist and are valid JSON
# ---------------------------------------------------------------------------

@test "A1 loa-providers.json exists (sprint-1E.c.3.a artifact)" {
    [[ -f "$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-providers.json" ]]
    jq -e '.providers' "$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-providers.json" >/dev/null
}

@test "A2 loa-anthropic-docs.json exists (sprint-1E.c.3.a artifact)" {
    [[ -f "$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-anthropic-docs.json" ]]
    jq -e '.providers' "$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-anthropic-docs.json" >/dev/null
}

@test "A3 openai.json exists (sprint-1E.c.3.a artifact)" {
    [[ -f "$PROJECT_ROOT/.claude/scripts/lib/allowlists/openai.json" ]]
    jq -e '.providers' "$PROJECT_ROOT/.claude/scripts/lib/allowlists/openai.json" >/dev/null
}

@test "A4 loa-registry.json exists (sprint-1E.c.3.b new)" {
    [[ -f "$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-registry.json" ]]
    jq -e '.providers.loa_registry' "$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-registry.json" >/dev/null
}

@test "A5 loa-github.json exists (sprint-1E.c.3.b new)" {
    [[ -f "$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-github.json" ]]
    jq -e '.providers.github_api' "$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-github.json" >/dev/null
}

@test "A6 loa-registry.json allows api.constructs.network:443 only" {
    local hosts
    hosts=$(jq -r '.providers.loa_registry[].host' "$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-registry.json")
    [[ "$hosts" == "api.constructs.network" ]]
}

@test "A7 loa-github.json allows api.github.com (narrowest possible — bridgebuilder iter-1 LOW)" {
    # BB iter-1 LOW: previously had raw.githubusercontent.com + objects.githubusercontent.com
    # + github.com as speculative entries for future use. Removed because
    # mount-loa.sh is EXEMPT (doesn't route through validator) and check-updates
    # is the only consumer — only hits api.github.com. Future callers requiring
    # raw.githubusercontent.com etc. should add the entry in the same PR.
    local hosts
    hosts=$(jq -r '.providers | to_entries[].value[].host' "$PROJECT_ROOT/.claude/scripts/lib/allowlists/loa-github.json" | sort -u | tr '\n' ',' )
    [[ "$hosts" == *"api.github.com"* ]]
    # Confirm the speculative entries are NOT present (regression guard for
    # accidental re-widening)
    [[ "$hosts" != *"raw.githubusercontent.com"* ]] || {
        printf 'loa-github.json widened back to include raw.githubusercontent.com — review before adding\n' >&2
        return 1
    }
    [[ "$hosts" != *"objects.githubusercontent.com"* ]] || return 1
}

# ---------------------------------------------------------------------------
# F — Flatline batch migrations (4 scripts, ~9 sites)
# ---------------------------------------------------------------------------

@test "F1 flatline-semantic-similarity.sh sources validator + uses guarded_curl" {
    _assert_migrated "flatline-semantic-similarity.sh"
    _assert_has_allowlist_decl "flatline-semantic-similarity.sh"
}

@test "F2 flatline-learning-extractor.sh sources validator + uses guarded_curl" {
    _assert_migrated "flatline-learning-extractor.sh"
    _assert_has_allowlist_decl "flatline-learning-extractor.sh"
}

@test "F3 flatline-proposal-review.sh sources validator + uses guarded_curl (2 sites)" {
    _assert_migrated "flatline-proposal-review.sh"
    _assert_has_allowlist_decl "flatline-proposal-review.sh"
    # Both GPT and Opus paths must use guarded_curl
    local count
    count=$(grep -cE 'endpoint_validator__guarded_curl' \
        "$PROJECT_ROOT/.claude/scripts/flatline-proposal-review.sh")
    [[ "$count" -ge 2 ]] || {
        printf 'expected at least 2 guarded_curl calls (GPT + Opus); got %d\n' "$count" >&2
        return 1
    }
}

@test "F4 flatline-validate-learning.sh sources validator + uses guarded_curl (2 sites)" {
    _assert_migrated "flatline-validate-learning.sh"
    _assert_has_allowlist_decl "flatline-validate-learning.sh"
    local count
    count=$(grep -cE 'endpoint_validator__guarded_curl' \
        "$PROJECT_ROOT/.claude/scripts/flatline-validate-learning.sh")
    [[ "$count" -ge 2 ]] || return 1
}

@test "F5 flatline scripts use loa-providers.json allowlist (multi-model)" {
    for script in flatline-semantic-similarity.sh flatline-learning-extractor.sh \
                  flatline-proposal-review.sh flatline-validate-learning.sh; do
        grep -qF 'loa-providers.json' "$PROJECT_ROOT/.claude/scripts/$script" || {
            printf '%s missing loa-providers.json reference\n' "$script" >&2
            return 1
        }
    done
}

# ---------------------------------------------------------------------------
# H — api-resilience.sh helper migration (transitively migrates 3 callers)
# ---------------------------------------------------------------------------

@test "H1 api-resilience.sh sources validator + call_api_with_retry uses guarded_curl" {
    local script_path="$PROJECT_ROOT/.claude/scripts/lib/api-resilience.sh"
    [[ -f "$script_path" ]]
    grep -qE 'source[[:space:]]+.*endpoint-validator\.sh' "$script_path"
    grep -qE 'endpoint_validator__guarded_curl' "$script_path"
    bash -n "$script_path"
}

@test "H2 api-resilience.sh refuses to run with raw curl (fail-closed if validator missing)" {
    local script_path="$PROJECT_ROOT/.claude/scripts/lib/api-resilience.sh"
    grep -qE 'endpoint_validator__guarded_curl not available' "$script_path" || {
        printf 'api-resilience.sh does not have a fail-closed branch when validator is missing\n' >&2
        return 1
    }
}

@test "H3 api-resilience.sh: SSRF rejection (78) and usage error (64) do NOT retry" {
    local script_path="$PROJECT_ROOT/.claude/scripts/lib/api-resilience.sh"
    # The migration explicitly states: 78 + 64 are config bugs, not transients
    grep -qE 'curl_rc == 78' "$script_path"
    grep -qE 'curl_rc == 64' "$script_path"
}

# ---------------------------------------------------------------------------
# C — constructs-* batch + license-validator (5 scripts)
# ---------------------------------------------------------------------------

@test "C1 constructs-loader.sh sources validator + uses guarded_curl" {
    _assert_migrated "constructs-loader.sh"
    _assert_has_allowlist_decl "constructs-loader.sh"
}

@test "C2 constructs-auth.sh sources validator + uses guarded_curl" {
    _assert_migrated "constructs-auth.sh"
    _assert_has_allowlist_decl "constructs-auth.sh"
}

@test "C3 constructs-browse.sh sources validator + uses guarded_curl (4 sites)" {
    _assert_migrated "constructs-browse.sh"
    _assert_has_allowlist_decl "constructs-browse.sh"
    local count
    count=$(grep -cE 'endpoint_validator__guarded_curl' \
        "$PROJECT_ROOT/.claude/scripts/constructs-browse.sh")
    [[ "$count" -ge 4 ]] || {
        printf 'constructs-browse: expected at least 4 guarded_curl calls; got %d\n' "$count" >&2
        return 1
    }
}

@test "C4 constructs-install.sh sources validator + uses guarded_curl (2 sites)" {
    _assert_migrated "constructs-install.sh"
    _assert_has_allowlist_decl "constructs-install.sh"
    local count
    count=$(grep -cE 'endpoint_validator__guarded_curl' \
        "$PROJECT_ROOT/.claude/scripts/constructs-install.sh")
    [[ "$count" -ge 2 ]] || return 1
}

@test "C5 license-validator.sh sources validator + uses guarded_curl" {
    _assert_migrated "license-validator.sh"
    _assert_has_allowlist_decl "license-validator.sh"
}

@test "C6 constructs + license scripts use loa-registry.json allowlist" {
    for script in constructs-loader.sh constructs-auth.sh constructs-browse.sh \
                  constructs-install.sh license-validator.sh; do
        grep -qF 'loa-registry.json' "$PROJECT_ROOT/.claude/scripts/$script" || {
            printf '%s missing loa-registry.json reference\n' "$script" >&2
            return 1
        }
    done
}

@test "C7 constructs-* + license scripts pass auth tempfile via --config-auth (NOT --config)" {
    # The 1E.c.3.a smuggling defense: caller --config is REJECTED by the
    # wrapper. Migrated scripts MUST use --config-auth instead.
    for script in constructs-auth.sh constructs-browse.sh constructs-install.sh; do
        local script_path="$PROJECT_ROOT/.claude/scripts/$script"
        # Must have at least one --config-auth invocation
        grep -qE '\-\-config-auth' "$script_path" || {
            printf '%s does NOT pass auth via --config-auth (smuggling defense)\n' "$script" >&2
            return 1
        }
        # Must NOT have any direct --config inside guarded_curl calls
        # (heuristic: count `--config "$` occurrences; should be in raw curl
        # blocks only, but those are gone after migration)
        if grep -qE 'endpoint_validator__guarded_curl' "$script_path"; then
            # Confirm no `--config` appears within 5 lines of guarded_curl
            local violations
            violations=$(grep -A 5 'endpoint_validator__guarded_curl' "$script_path" \
                | grep -E '^\s+--config\s' || true)
            [[ -z "$violations" ]] || {
                printf '%s passes --config (not --config-auth) within guarded_curl call\n' "$script" >&2
                printf '%s\n' "$violations" >&2
                return 1
            }
        fi
    done
}

# ---------------------------------------------------------------------------
# G — GitHub batch (check-updates only; mount-loa is exempt)
# ---------------------------------------------------------------------------

@test "G1 check-updates.sh sources validator + uses guarded_curl" {
    _assert_migrated "check-updates.sh"
    _assert_has_allowlist_decl "check-updates.sh"
}

@test "G2 check-updates.sh uses loa-github.json allowlist" {
    grep -qF 'loa-github.json' "$PROJECT_ROOT/.claude/scripts/check-updates.sh"
}

# ---------------------------------------------------------------------------
# M — mount-loa.sh exemption (bootstrap path — validator not on disk yet)
# ---------------------------------------------------------------------------

@test "M1 mount-loa.sh has [ENDPOINT-VALIDATOR-EXEMPT] rationale banner" {
    grep -qF 'ENDPOINT-VALIDATOR-EXEMPT' "$PROJECT_ROOT/.claude/scripts/mount-loa.sh"
}

@test "M2 mount-loa.sh hardens raw curl with --proto =https / --proto-redir / --max-redirs" {
    local script_path="$PROJECT_ROOT/.claude/scripts/mount-loa.sh"
    # The bootstrap curl invocations MUST set the same hardened defaults
    # the validator wrapper would have applied. We grep for all three.
    grep -qE 'curl[[:space:]]+--proto[[:space:]]+=https' "$script_path"
    grep -qE '\-\-proto-redir[[:space:]]+=https' "$script_path"
    grep -qE '\-\-max-redirs[[:space:]]+10' "$script_path"
}

@test "M3 mount-loa.sh validates _loa_ref against alphanum+dot+slash regex" {
    # An attacker-controlled _loa_ref could have been used to traverse to a
    # different repo path. M3 pins the validation regex so this can't drift.
    grep -qE '\[\[[[:space:]]*!.*_loa_ref.*=~.*A-Za-z' \
        "$PROJECT_ROOT/.claude/scripts/mount-loa.sh"
}

@test "M4 mount-loa.sh REJECTS _loa_ref containing dot-dot (BB iter-1 MEDIUM regression guard)" {
    # The regex `^[A-Za-z0-9._/-]+$` accepts every char in the class
    # individually, including `..` as TWO separate dots. GitHub's CDN
    # normalizes `..` server-side per RFC 3986 §5.2.4, so an attacker passing
    # `--ref=../attacker/repo/refs/heads/main` could pivot to a different
    # repo. The companion check `[[ "$_loa_ref" == *..* ]]` rejects this.
    # Source-level pin: a future refactor that drops the `..` check needs to
    # update this test.
    grep -qE '\[\[[[:space:]]*"\$_loa_ref"[[:space:]]*==[[:space:]]*\*\.\.\*' \
        "$PROJECT_ROOT/.claude/scripts/mount-loa.sh"
    # Behavior-level pin: extract the bash branch into a sub-shell and run
    # it standalone with a `..`-containing ref. We can't actually invoke
    # mount-loa.sh end-to-end without massive setup, so verify the regex
    # logic in isolation.
    local ref="../attacker/repo"
    bash -c "[[ ! \"$ref\" =~ ^[A-Za-z0-9._/-]+\$ ]] || [[ \"$ref\" == *..* ]]" \
        && return 0 || {
            printf 'expected ref %q to be rejected by either regex or ..-check; both passed\n' "$ref" >&2
            return 1
        }
}

# ---------------------------------------------------------------------------
# Z — Cumulative check: NO new raw `curl ` invocations on critical lines
# ---------------------------------------------------------------------------

@test "Z1 model-health-probe / anthropic-oracle / lib-curl-fallback have NO new raw curl regressions" {
    # 1E.c.3.a migrated 3 sites; this test pins them so a future rebase
    # doesn't accidentally revert them. Each script must have at least one
    # guarded_curl call.
    for script in model-health-probe.sh anthropic-oracle.sh lib-curl-fallback.sh; do
        grep -qE 'endpoint_validator__guarded_curl' \
            "$PROJECT_ROOT/.claude/scripts/$script" || {
            printf '%s lost its guarded_curl migration (1E.c.3.a regression)\n' "$script" >&2
            return 1
        }
    done
}

@test "Z2 every migrated 1E.c.3.b script declares allowlist constant under canonical tree path" {
    # The wrapper rejects allowlist paths outside .claude/scripts/lib/allowlists/.
    # Migrated callers MUST resolve to this path. Match either the literal
    # path fragment OR a `$LIB_DIR/allowlists/` form (LIB_DIR := SCRIPT_DIR/lib),
    # since some callers compose the path through a derived var.
    for script in flatline-semantic-similarity.sh flatline-learning-extractor.sh \
                  flatline-proposal-review.sh flatline-validate-learning.sh \
                  constructs-loader.sh constructs-auth.sh constructs-browse.sh \
                  constructs-install.sh license-validator.sh check-updates.sh; do
        local script_path="$PROJECT_ROOT/.claude/scripts/$script"
        if ! grep -qE '(\$SCRIPT_DIR/lib|\$LIB_DIR)/allowlists/[a-z0-9-]+\.json' \
                "$script_path"; then
            printf '%s default allowlist does NOT resolve to .claude/scripts/lib/allowlists/\n' "$script" >&2
            return 1
        fi
    done
}

@test "Z3 wrapper-end-to-end smoke: source api-resilience.sh and call without allowlist override" {
    # Confirm api-resilience.sh sources cleanly when the validator IS on disk.
    # We don't actually make a network call; we just check the function is
    # defined and the validator fail-closed branch is reachable.
    local probe_out
    probe_out=$(bash -c "
        source '$PROJECT_ROOT/.claude/scripts/lib/api-resilience.sh' >/dev/null 2>&1
        declare -f call_api_with_retry >/dev/null && echo OK
        declare -f endpoint_validator__guarded_curl >/dev/null && echo VALIDATOR_OK
    ")
    [[ "$probe_out" == *'OK'* ]]
    [[ "$probe_out" == *'VALIDATOR_OK'* ]]
}
